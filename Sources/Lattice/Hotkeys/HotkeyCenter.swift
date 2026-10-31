import AppKit
import Carbon
import LatticeKit

/// Global keyboard shortcuts.
///
/// Carbon's `RegisterEventHotKey` is used on purpose: it needs no Accessibility grant, it
/// works while another app is frontmost, and it gives us a real "this shortcut is already
/// claimed" error we can surface in Settings. Every binding routes through
/// `AppModel.shared.dispatch(_:)`, so keyboard and menu/toolbar actions share one code path.
///
/// Threading: registration state is main-thread affine (`install`, `reload`, the prefs watcher
/// and the Carbon handler all run on the main run loop). Public mutators hop to main if needed.
final class HotkeyCenter: @unchecked Sendable {

    static let shared = HotkeyCenter()

    /// Bindings that could not be registered. Settings shows a warning icon for each of these.
    private(set) var conflicts: [CommandID] = []
    /// Human-readable reason per conflicting binding, for the tooltip/trailer in Settings.
    private(set) var conflictReasons: [CommandID: String] = [:]

    private weak var model: AppModel?
    private var installed = false
    private var suspended = false

    private var eventHandler: EventHandlerRef?
    private var registrations: [CommandID: EventHotKeyRef] = [:]
    private var commandForID: [UInt32: CommandID] = [:]
    private var nextID: UInt32 = 1

    private var lastAppliedBindings: [CommandID: KeyCombo]?
    private var reloadWorkItem: DispatchWorkItem?
    private var pollTimer: Timer?
    private var watchingPreferences = false

    private static let signature: OSType = 0x4C415454 // 'LATT'

    private init() {}

    // MARK: - Lifecycle

    /// Called once from `AppDelegate` at launch. Idempotent.
    func install(model: AppModel) {
        if Thread.isMainThread {
            installOnMain(model: model)
        } else {
            DispatchQueue.main.async { [weak self] in self?.installOnMain(model: model) }
        }
    }

    private func installOnMain(model: AppModel) {
        self.model = model
        guard !installed else { return }
        installed = true

        installEventHandler()
        HotkeyKeyMap.startWatchingLayout()
        watchPreferences()
        reloadNow()
        // Drag-to-snap is part of the input subsystem and is booted from the same entry point.
        DragSnapController.shared.start()
    }

    /// Re-read `Preferences.bindings` and replace every registration.
    func reload() {
        if Thread.isMainThread {
            scheduleReload()
        } else {
            DispatchQueue.main.async { [weak self] in self?.scheduleReload() }
        }
    }

    /// Unregister everything (e.g. while the user is recording a new shortcut) but remember
    /// the bindings so `resume()` restores them.
    func suspend() {
        onMain { [weak self] in
            guard let self else { return }
            self.suspended = true
            self.unregisterAll()
            self.conflicts = []
            self.conflictReasons = [:]
            self.postChange()
        }
    }

    /// Re-register everything after a `suspend()`.
    func resume() {
        onMain { [weak self] in
            guard let self else { return }
            self.suspended = false
            self.reloadNow()
        }
    }

    /// Register (or re-register) a single command. Returns whether it ended up registered.
    @discardableResult
    func register(_ command: CommandID) -> Bool {
        guard Thread.isMainThread else {
            reload()
            return false
        }
        reloadNow()
        return isRegistered(command)
    }

    func unregister(_ command: CommandID) {
        onMain { [weak self] in
            guard let self, let ref = self.registrations.removeValue(forKey: command) else { return }
            UnregisterEventHotKey(ref)
            self.commandForID = self.commandForID.filter { $0.value != command }
            self.postChange()
        }
    }

    func isRegistered(_ command: CommandID) -> Bool {
        registrations[command] != nil
    }

    // MARK: - Registration

    /// Coalesce bursts of prefs changes from the shortcut recorder into one re-registration.
    private func scheduleReload() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleReload() }
            return
        }
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reloadNow() }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    private func reloadNow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reloadNow() }
            return
        }
        unregisterAll()
        // Settings can trigger a reload before `install` has run; make sure events have a home.
        installEventHandler()

        let bindings = PreferencesStore.shared.prefs.bindings
        lastAppliedBindings = bindings

        guard !suspended else {
            conflicts = []
            conflictReasons = [:]
            postChange()
            return
        }

        var seen: [Binding: CommandID] = [:]
        var nextConflicts: [CommandID] = []
        var nextReasons: [CommandID: String] = [:]

        for command in CommandID.allCases {
            guard let combo = bindings[command] else { continue }
            // A binding without ⌃/⌥/⌘ would intercept ordinary typing system-wide.
            guard !combo.modifiers.isDisjoint(with: [.control, .option, .command]) else {
                nextConflicts.append(command)
                nextReasons[command] = "Needs ⌃, ⌥ or ⌘"
                continue
            }
            guard let mapping = HotkeyKeyMap.mapping(for: combo.key) else {
                nextConflicts.append(command)
                nextReasons[command] = "This keyboard cannot type “\(combo.key)”"
                continue
            }
            var modifiers = HotkeyKeyMap.carbonModifiers(for: combo.modifiers)
            // On layouts where the character sits behind Shift (AZERTY digits), the chord
            // needs that Shift to reach the same key the user sees printed.
            if mapping.requiresShift { modifiers |= UInt32(shiftKey) }
            let binding = Binding(keyCode: mapping.keyCode, modifiers: modifiers)
            if let owner = seen[binding] {
                nextConflicts.append(command)
                nextReasons[command] = "Also assigned to “\(owner.title)”"
                continue
            }

            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(UInt32(mapping.keyCode), modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                registrations[command] = ref
                commandForID[id] = command
                seen[binding] = command
            } else {
                nextConflicts.append(command)
                nextReasons[command] = status == eventHotKeyExistsErr
                    ? "Already used by another app"
                    : "Could not register (error \(status))"
                Log.info("hotkey \(combo.display) for \(command.rawValue) unavailable: \(status)")
            }
        }

        conflicts = nextConflicts
        conflictReasons = nextReasons
        postChange()
        Log.info("hotkeys registered \(registrations.count)/\(bindings.count)"
                 + (nextConflicts.isEmpty ? "" : ", conflicts: \(nextConflicts.map(\.rawValue))"))
    }

    private func unregisterAll() {
        for (_, ref) in registrations { UnregisterEventHotKey(ref) }
        registrations.removeAll()
        commandForID.removeAll()
    }

    // MARK: - Carbon handler

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         latticeHotKeyHandler,
                                         1,
                                         &spec,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         &eventHandler)
        if status != noErr {
            Log.error("could not install hotkey event handler: \(status)")
        }
    }

    fileprivate func handleHotKey(id: UInt32) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.dispatch(id) }
        } else {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.dispatch(id) }
            }
        }
    }

    /// Main-thread only: look up the command and hand it to the single dispatch funnel.
    @MainActor
    private func dispatch(_ id: UInt32) {
        guard let command = commandForID[id] else { return }
        (model ?? AppModel.shared).dispatch(command)
    }

    // MARK: - Preferences watching

    private func watchPreferences() {
        guard !watchingPreferences else { return }
        watchingPreferences = true
        lastAppliedBindings = PreferencesStore.shared.prefs.bindings

        // The store is a real multicast now, so no chaining gymnastics are needed.
        let store = PreferencesStore.shared
        _ = store.observe { [weak self] prefs in
            guard let self, self.lastAppliedBindings != prefs.bindings else { return }
            self.reload()
        }

        // Belt and braces: a cheap 1.5 s comparison still catches anything a future
        // subsystem forgets to publish through the store.
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, self.lastAppliedBindings != PreferencesStore.shared.prefs.bindings else { return }
            self.reload()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Helpers

    private func postChange() {
        NotificationCenter.default.post(name: .latticeHotkeysDidChange, object: self)
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private struct Binding: Hashable {
        var keyCode: CGKeyCode
        var modifiers: UInt32
    }
}

// MARK: - Carbon callbacks

/// The Carbon callback must be a C function pointer, so it lives at file scope.
private func latticeHotKeyHandler(_ callRef: EventHandlerCallRef?,
                                  _ event: EventRef?,
                                  _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr else { return noErr }
    let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
    center.handleHotKey(id: hotKeyID.id)
    return noErr
}

extension Notification.Name {
    /// Posted on the main thread whenever registrations or conflicts change.
    static let latticeHotkeysDidChange = Notification.Name("lattice.hotkeys.didChange")
}
