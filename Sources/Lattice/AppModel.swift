import AppKit
import SwiftUI
import Combine
import LatticeKit

@MainActor
public final class AppModel: ObservableObject {

    public static let shared = AppModel()

    // Core
    public let engine = WindowEngine()
    public let tiler: Tiler
    public let prefs = PreferencesStore.shared

    // Published UI state
    @Published public var accessibilityGranted = false
    @Published public var windowsBySpace: [SpaceID: [ManagedWindow]] = [:]
    @Published public var displays: [DisplayInfo] = []
    @Published public var spaces: [SpaceManager.DisplaySpaces] = []
    @Published public var focusedSpace: SpaceID = SpaceID(0)
    @Published public var focusedWindow: ManagedWindow?
    @Published public var layout: LayoutKind = .dwindle
    @Published public var isEnabled = true
    @Published public var lastAction: String?
    @Published public var recentActions: [String] = []

    public var onWindowsChanged: (([ManagedWindow]) -> Void)?

    private var cancellables: Set<AnyCancellable> = []
    private var spaceRefreshTask: DispatchWorkItem?
    private var permissionTimer: Timer?
    private var hasBootstrapped = false

    private init() {
        tiler = Tiler(engine: engine)
        engine.delegate = self
        tiler.delegate = self
        layout = prefs.prefs.layout
        isEnabled = prefs.prefs.enabled
        EngineHolder.shared = engine

        prefs.observe { [weak self] new in
            guard let self else { return }
            Task { @MainActor in
                self.layout = new.layout
                self.isEnabled = new.enabled
                self.tiler.reconcile()
            }
        }
    }

    // MARK: - Boot

    public func bootstrap() {
        refreshPermissions()
        guard accessibilityGranted else {
            startPermissionWatcher()
            return
        }
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        engine.start()
        refreshSpaces()
        tiler.reconcile(animated: false)
    }

    public func refreshPermissions() {
        accessibilityGranted = engine.isTrusted
    }

    /// Watches TCC while we do not have the grant, so flipping the switch in System Settings
    /// takes effect immediately instead of requiring a relaunch.
    public func startPermissionWatcher() {
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPermission() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    private func pollPermission() {
        let trusted = engine.isTrusted
        if trusted != accessibilityGranted {
            accessibilityGranted = trusted
            if trusted { bootstrap() }
        }
        if trusted, permissionTimer != nil, hasBootstrapped {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }

    private var hasPromptedForAccessibility = false

    /// Shows the system prompt at most once per launch. Prompting again is what makes macOS
    /// pull focus back to the alert while the user is trying to use the app.
    public func requestAccessibility() {
        guard !engine.isTrusted else { accessibilityGranted = true; return }
        guard !hasPromptedForAccessibility else { startPermissionWatcher(); return }
        hasPromptedForAccessibility = true
        _ = engine.requestTrust()
        Task {
            for _ in 0..<120 {
                try? await Task.sleep(for: .milliseconds(500))
                if engine.isTrusted {
                    await MainActor.run { self.accessibilityGranted = true; self.bootstrap() }
                    return
                }
            }
        }
    }

    public func refreshSpaces() {
        spaces = SpaceManager.shared.displaySpaces()
        focusedSpace = SpaceManager.shared.focusedSpace() ?? SpaceID(0)
        syncLayoutWithFocusedSpace()
        displays = NSScreen.screens.compactMap { screen in
            tiler.displayInfo(for: SpaceManager.displayID(for: screen))
        }
        rebuildWindowCache()
    }

    private var demoWindows: [WindowID: ManagedWindow] = [:]
    private var demodOrder: [WindowID] = []

    public var isDemo: Bool { !demoWindows.isEmpty }

    public func rebuildWindowCache() {
        if isDemo { return }
        var map: [SpaceID: [ManagedWindow]] = [:]
        for window in engine.windows.values where !window.isMinimized {
            map[window.space, default: []].append(window)
        }
        for key in map.keys {
            map[key]?.sort { $0.id.raw < $1.id.raw }
        }
        windowsBySpace = map
        focusedWindow = engine.focused.flatMap { engine.window($0) }
        onWindowsChanged?(Array(engine.windows.values))
    }

    // MARK: - Commands

    public func dispatch(_ command: CommandID) {
        guard accessibilityGranted else {
            // Never raise the system prompt from a shortcut: it steals focus mid-keystroke.
            note(action: "Accessibility needed — open Settings ▸ Privacy")
            startPermissionWatcher()
            return
        }
        let space = tiler.focusedSpace()
        switch command {
        case .focusLeft: tiler.focus(.left, on: space)
        case .focusRight: tiler.focus(.right, on: space)
        case .focusUp: tiler.focus(.up, on: space)
        case .focusDown: tiler.focus(.down, on: space)
        case .moveLeft: tiler.move(.left, on: space)
        case .moveRight: tiler.move(.right, on: space)
        case .moveUp: tiler.move(.up, on: space)
        case .moveDown: tiler.move(.down, on: space)
        case .swapLeft: tiler.swap(.left, on: space)
        case .swapRight: tiler.swap(.right, on: space)
        case .swapUp: tiler.swap(.up, on: space)
        case .swapDown: tiler.swap(.down, on: space)
        case .grow: tiler.adjustSize(.horizontal, delta: 0.06, on: space)
        case .shrink: tiler.adjustSize(.horizontal, delta: -0.06, on: space)
        case .growHeight: tiler.adjustSize(.vertical, delta: 0.06, on: space)
        case .shrinkHeight: tiler.adjustSize(.vertical, delta: -0.06, on: space)
        case .layoutDwindle: setLayout(.dwindle)
        case .layoutColumns: setLayout(.columns)
        case .layoutRows: setLayout(.rows)
        case .layoutGrid: setLayout(.grid)
        case .layoutMaster: setLayout(.master)
        case .layoutStack: setLayout(.stack)
        case .cycleLayout: tiler.cycleLayout()
        case .toggleFloat: tiler.toggleFloat()
        case .toggleFullscreen:
            if let focused = engine.focused { engine.toggleFullscreen(focused) }
        case .focusMode: tiler.toggleFocusMode()
        case .center: tiler.centre()
        case .zoom: tiler.zoom()
        case .nextSpace: tiler.nextSpace(forward: true)
        case .previousSpace: tiler.nextSpace(forward: false)
        case .space1, .space2, .space3, .space4, .space5, .space6, .space7, .space8, .space9:
            tiler.goToSpace(number: command.spaceNumber)
        case .moveToSpace1, .moveToSpace2, .moveToSpace3, .moveToSpace4, .moveToSpace5,
             .moveToSpace6, .moveToSpace7, .moveToSpace8, .moveToSpace9:
            tiler.moveWindowToSpace(number: command.spaceNumber)
        case .nextDisplay: tiler.nextDisplay(forward: true)
        case .previousDisplay: tiler.nextDisplay(forward: false)
        case .commandPalette: NotificationCenter.default.post(name: .latticeShowPalette, object: nil)
        case .cheatSheet: NotificationCenter.default.post(name: .latticeShowCheatSheet, object: nil)
        case .showApp: NotificationCenter.default.post(name: .latticeShowMainWindow, object: nil)
        case .toggleEnabled: setEnabled(!isEnabled)
        case .undo: tiler.undo()
        }
        note(action: command.title)
    }

    /// Design-review fixture: real displays and Spaces, invented windows. Used only when
    /// `LATTICE_DEMO=1`, so every screen can be rendered without Accessibility permission.
    public func installDemoWindows(_ windows: [WindowID: ManagedWindow], order: [WindowID]) {
        demoWindows = windows
        demodOrder = order
        var map: [SpaceID: [ManagedWindow]] = [:]
        for window in windows.values {
            map[window.space, default: []].append(window)
        }
        windowsBySpace = map
        focusedWindow = windows[order.first ?? WindowID(0)]
        accessibilityGranted = true
        objectWillChange.send()
    }

    /// Space navigation entry points for the hotkey layer and the CLI.
    public func goToSpace(_ number: Int) {
        tiler.goToSpace(number: number)
    }

    public func moveFocusedWindowToSpace(_ number: Int) {
        tiler.moveWindowToSpace(number: number)
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        prefs.update { $0.enabled = enabled }
        tiler.isSuspended = !enabled
        if enabled { tiler.reconcile() }
    }

    public func setLayout(_ kind: LayoutKind) {
        setLayout(kind, for: tiler.focusedSpace())
    }

    /// Applies a layout to one Space only. Other Spaces keep theirs.
    public func setLayout(_ kind: LayoutKind, for space: SpaceID) {
        prefs.update { $0.setLayout(kind, for: space) }
        if space == tiler.focusedSpace() { layout = kind }
        tiler.setLayout(kind, for: space)
    }

    /// Explicit reset: give every Space this layout and make it the default.
    public func setLayoutEverywhere(_ kind: LayoutKind) {
        prefs.update { prefs in
            prefs.clearLayoutOverrides()
            prefs.layout = kind
        }
        layout = kind
        tiler.applyLayoutEverywhere(kind)
    }

    public func layout(for space: SpaceID) -> LayoutKind {
        prefs.prefs.layout(for: space)
    }

    public var currentSpaceHasOwnLayout: Bool {
        prefs.prefs.hasOwnLayout(focusedSpace)
    }

    /// Called when a Space change lands so the UI always reflects the Space in front of you.
    public func syncLayoutWithFocusedSpace() {
        let kind = prefs.prefs.layout(for: focusedSpace)
        if kind != layout { layout = kind }
    }

    private func note(action: String) {
        lastAction = action
        recentActions.insert(action, at: 0)
        if recentActions.count > 8 { recentActions.removeLast() }
    }
}

extension Notification.Name {
    public static let latticeShowPalette = Notification.Name("lattice.showPalette")
    public static let latticeShowCheatSheet = Notification.Name("lattice.showCheatSheet")
    public static let latticeShowMainWindow = Notification.Name("lattice.showMainWindow")
    public static let latticeShowSettings = Notification.Name("lattice.showSettings")
}

extension AppModel: WindowEngineDelegate {
    public nonisolated func engineDidChangeWindows(_ engine: WindowEngine) {
        Task { @MainActor in
            self.rebuildWindowCache()
            autoLayoutIfNeeded()
        }
    }

    public nonisolated func engine(_ engine: WindowEngine, didFocus window: ManagedWindow?) {
        Task { @MainActor in
            self.focusedWindow = window
        }
    }

    public nonisolated func engineSpaceDidChange(_ engine: WindowEngine) {
        Task { @MainActor in
            self.refreshSpaces()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.tiler.reconcile(animated: false)
            }
        }
    }

    private func autoLayoutIfNeeded() {
        guard isEnabled else { return }
        tiler.reconcile()
    }
}

extension AppModel: TilerDelegate {
    public nonisolated func tilerDidUpdate(_ tiler: Tiler, space: SpaceID, windows: [ManagedWindow]) {
        Task { @MainActor in
            self.windowsBySpace[space] = windows
        }
    }

    public nonisolated func tiler(_ tiler: Tiler, didFail message: String) {
        Task { @MainActor in
            self.lastAction = message
        }
    }
}
