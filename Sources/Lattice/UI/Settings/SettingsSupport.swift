import SwiftUI
import AppKit
import Combine
import LatticeKit

// MARK: - Preferences bridge
//
// PreferencesStore is a plain class and AppModel already owns its `onChange` hook,
// so the panes read through this small observable mirror instead of touching it.
// It also fans out a hotkey reload through a protocol so this module compiles
// whether or not HotkeyCenter.reload() has landed yet.

@MainActor
final class SettingsPreferences: ObservableObject {
    static let shared = SettingsPreferences()

    @Published private(set) var prefs: Preferences
    private var ticker: AnyCancellable?
    private var observers = 0

    private init() {
        prefs = PreferencesStore.shared.prefs
    }

    /// A two-way binding for one preference. Every setter goes through
    /// PreferencesStore.update, so the engine sees the change on the same pass.
    func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { self.prefs[keyPath: keyPath] },
            set: { newValue in
                self.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    func update(_ mutate: (inout Preferences) -> Void) {
        let previousBindings = PreferencesStore.shared.prefs.bindings
        PreferencesStore.shared.update(mutate)
        prefs = PreferencesStore.shared.prefs
        if prefs.bindings != previousBindings {
            SettingsHotkeyReload.reload()
        }
    }

    func resetEverything(keepingOnboarding: Bool) {
        let completed = PreferencesStore.shared.prefs.hasCompletedOnboarding
        PreferencesStore.shared.update { prefs in
            prefs = Preferences()
            if keepingOnboarding { prefs.hasCompletedOnboarding = completed }
        }
        prefs = PreferencesStore.shared.prefs
        SettingsHotkeyReload.reload()
    }

    func refresh() {
        let latest = PreferencesStore.shared.prefs
        if latest != prefs { prefs = latest }
    }

    func beginObserving() {
        observers += 1
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 0.4, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func endObserving() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        ticker?.cancel()
        ticker = nil
    }
}

/// Sent after any binding change. HotkeyCenter picks this up as soon as the hotkey
/// subsystem provides `reload()`; until then the default implementation is a no-op.
protocol LatticeHotkeyReloading: AnyObject {
    func reload()
}

extension LatticeHotkeyReloading {
    func reload() {}
}

extension HotkeyCenter: LatticeHotkeyReloading {}

enum SettingsHotkeyReload {
    static func reload() {
        (HotkeyCenter.shared as LatticeHotkeyReloading).reload()
    }
}

// MARK: - Paths & links

enum SettingsLinks {
    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Lattice", isDirectory: true)
    }

    static func openLogFolder() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logDirectory.path) {
            try? fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(logDirectory)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Chords
//
// The design system owns the caps; this turns a KeyCombo into the glyph list they take.

struct SettingsKeyChord: View {
    var combo: KeyCombo?
    var placeholder: String = "Unbound"
    var compact: Bool = true

    static func glyphs(for combo: KeyCombo) -> [String] {
        let order: [KeyCombo.Modifier] = [.control, .option, .shift, .command]
        var out = order.filter { combo.modifiers.contains($0) }.map(\.symbol)
        out.append(KeyCombo.pretty(combo.key))
        return out
    }

    var body: some View {
        if let combo {
            KeyCapGroup(keys: Self.glyphs(for: combo), compact: compact)
        } else {
            Text(placeholder)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Space key capture
//
// A Space key is a bare key: the chords are built around it (⌥key, ⇧⌥key). So this
// recorder deliberately ignores modifiers, and rejects anything that is not a letter,
// a digit or a function key — the only things a Space key can sensibly be.

@MainActor
final class SpaceKeyRecorder: ObservableObject {

    static let acceptedFunctionKeys: Set<String> = Set((1...12).map { "f\($0)" })

    @Published private(set) var key: String?
    @Published private(set) var message: String?

    var onCancel: (() -> Void)?

    private var monitor: Any?

    var isRecording: Bool { monitor != nil }

    static func isAccepted(_ name: String) -> Bool {
        if acceptedFunctionKeys.contains(name) { return true }
        guard name.count == 1, let character = name.first else { return false }
        return character.isLetter || character.isNumber
    }

    func begin() {
        cancel()
        key = nil
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func clear() {
        key = nil
        message = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            cancel()
            onCancel?()
            return true
        case 51, 117: // Delete / forward delete
            clear()
            return true
        case 48, 36, 76:
            // Tab moves focus and Return activates a button; a sheet recorder must not
            // swallow either, or the sheet cannot be used from the keyboard.
            return false
        default:
            break
        }

        guard let name = KeyRecorder.keyName(for: event), Self.isAccepted(name) else {
            message = "Use a letter, a digit or a function key."
            return true
        }

        key = name
        message = nil
        return true
    }
}

// MARK: - System shortcut awareness

struct SettingsSystemShortcut {
    var combo: KeyCombo
    var name: String
}

enum SettingsSystemShortcuts {
    static let all: [SettingsSystemShortcut] = {
        var out: [SettingsSystemShortcut] = []
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "space", modifiers: [.command]),
                                  name: "Spotlight search"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "space", modifiers: [.control, .command]),
                                  name: "Emoji & symbols"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "up", modifiers: [.control]),
                                  name: "Mission Control"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "down", modifiers: [.control]),
                                  name: "Application windows"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "left", modifiers: [.control]),
                                  name: "Move left a Space"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "right", modifiers: [.control]),
                                  name: "Move right a Space"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "tab", modifiers: [.command]),
                                  name: "Application switcher"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "f", modifiers: [.control, .command]),
                                  name: "Enter full screen"))
        for n in 1...9 {
            out.append(SettingsSystemShortcut(combo: KeyCombo(key: "\(n)", modifiers: [.control]),
                                      name: "Switch to desktop \(n)"))
        }
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "3", modifiers: [.command, .shift]),
                                  name: "Screenshot"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "4", modifiers: [.command, .shift]),
                                  name: "Screenshot selection"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "5", modifiers: [.command, .shift]),
                                  name: "Screenshot and recording options"))
        out.append(SettingsSystemShortcut(combo: KeyCombo(key: "q", modifiers: [.control, .command]),
                                  name: "Lock screen"))
        return out
    }()

    static func conflict(for combo: KeyCombo) -> SettingsSystemShortcut? {
        all.first { $0.combo == combo }
    }
}

// MARK: - Live gap diagram

/// Draws the real layout inside a miniature screen so a slider drag is visible. The
/// Layouts page uses it for its gaps controls.
struct SettingsGapPreview: View {
    var gap: CGFloat
    var outerGap: CGFloat
    var layout: LayoutKind
    var edges: Margin = Margin()
    var respectMenuBar: Bool = true
    var respectDock: Bool = true

    private let scale: CGFloat = 0.62

    var body: some View {
        GeometryReader { geo in
            diagram(in: geo.size)
        }
        .animation(LatticeTheme.animation, value: gap)
        .animation(LatticeTheme.animation, value: outerGap)
        .animation(LatticeTheme.animation, value: layout)
        .animation(LatticeTheme.animation, value: edges)
        .animation(LatticeTheme.animation, value: respectMenuBar)
        .animation(LatticeTheme.animation, value: respectDock)
    }

    private func diagram(in size: CGSize) -> some View {
        let full = CGRect(origin: .zero, size: size)
        let screen = full.insetBy(dx: 2, dy: 2)
        let menuHeight: CGFloat = respectMenuBar ? 9 : 0
        let dockHeight: CGFloat = respectDock ? 9 : 0

        var base = screen.insetBy(dx: 2, dy: 2)
        base.origin.y += menuHeight
        base.size.height = max(1, base.height - menuHeight - dockHeight)
        base = CGRect(
            x: base.minX + edges.leading * scale,
            y: base.minY + edges.top * scale,
            width: max(1, base.width - (edges.leading + edges.trailing) * scale),
            height: max(1, base.height - (edges.top + edges.bottom) * scale)
        )
        let pre = (outerGap - gap) * scale
        let canvas = base.insetBy(dx: pre, dy: pre)
        let frames = LayoutMath.frames(
            count: 4,
            in: canvas,
            gap: max(1.5, gap * scale),
            layout: layout
        )

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))

            if respectMenuBar {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: max(0, screen.width - 24), height: 4)
                    .offset(x: 14, y: 3)
            }

            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55),
                                          lineWidth: LatticeTheme.hairline)
                    )
                    .frame(width: max(0, frame.width), height: max(0, frame.height))
                    .offset(x: frame.minX, y: frame.minY)
            }

            if respectDock {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: min(70, screen.width * 0.38), height: 5)
                    .offset(x: (screen.width - min(70, screen.width * 0.38)) / 2,
                            y: screen.maxY - 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        )
    }
}

// MARK: - Diagnostics

/// The text behind "Copy Diagnostics". It is deliberately the same information the
/// log carries, so a report can be matched against a log without asking questions.
@MainActor
enum SettingsDiagnostics {
    static func text(model: AppModel, prefs: Preferences) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        var out = """
        Lattice \(version) (\(build))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        accessibility: \(model.accessibilityGranted ? "granted" : "not granted")
        tiling: \(prefs.enabled ? "on" : "paused"), default layout \(prefs.layout.rawValue)
        gaps: \(Int(prefs.gap)) pt inner, \(Int(prefs.outerGap)) pt outer, \
        edges t\(Int(prefs.edges.top)) l\(Int(prefs.edges.leading)) \
        b\(Int(prefs.edges.bottom)) r\(Int(prefs.edges.trailing))
        motion: \(prefs.animate ? "on" : "off"), \(prefs.animationCurve.rawValue), \
        \(Int(prefs.animationDuration * 1000)) ms
        borders: \(prefs.borderEnabled ? "on" : "off"), \(Int(prefs.borderWidth)) pt, \
        \(prefs.borderScope.rawValue), colour \(prefs.borderColorHex ?? "system accent")
        rules: \(prefs.rules.count) app rules, \(prefs.unmanagedBundleIDs.count) left alone, \
        \(prefs.floatBundleIDs.count) always floating
        displays: \(model.displays.count), overrides \(prefs.displayOverrides.count)
        per-Space layouts: \(prefs.spaceLayouts.count)
        shortcuts: \(prefs.bindings.count) of \(CommandID.allCases.count) bound

        """
        out += LatticeDiagnostics.snapshot()
        return out
    }
}
