import SwiftUI
import AppKit
import LatticeKit

/// Captures the next chord for a command using a local NSEvent monitor.
/// Local, not global: the recorder only listens while the settings window is key,
/// so it can never swallow keystrokes from other apps.
@MainActor
final class KeyRecorder: ObservableObject {

    enum Feedback: Equatable {
        case idle
        case needsModifier
    }

    @Published private(set) var target: CommandID?
    @Published private(set) var heldModifiers: Set<KeyCombo.Modifier> = []
    @Published private(set) var feedback: Feedback = .idle

    /// `nil` combo means "clear this binding".
    var onResult: ((CommandID, KeyCombo?) -> Void)?
    var onCancel: (() -> Void)?

    private var monitor: Any?

    var isRecording: Bool { target != nil }

    func begin(_ command: CommandID) {
        cancel()
        target = command
        heldModifiers = []
        feedback = .idle
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    func cancel() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        target = nil
        heldModifiers = []
        feedback = .idle
    }

    // MARK: - Event handling

    /// Returns true when the event was consumed by the recorder.
    private func handle(_ event: NSEvent) -> Bool {
        guard let command = target else { return false }

        if event.type == .flagsChanged {
            heldModifiers = Self.modifiers(from: event.modifierFlags)
            return true
        }

        let flags = Self.modifiers(from: event.modifierFlags)

        switch event.keyCode {
        case 53: // Escape
            cancel()
            onCancel?()
            return true
        case 51, 117: // Delete / forward delete
            finish(command, combo: nil)
            return true
        default:
            break
        }

        guard let key = Self.keyName(for: event) else {
            return true
        }

        guard !flags.isEmpty else {
            feedback = .needsModifier
            return true
        }

        finish(command, combo: KeyCombo(key: key, modifiers: flags))
        return true
    }

    private func finish(_ command: CommandID, combo: KeyCombo?) {
        cancel()
        onResult?(command, combo)
    }

    // MARK: - Key translation

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<KeyCombo.Modifier> {
        let raw = flags.intersection(.deviceIndependentFlagsMask)
        var set: Set<KeyCombo.Modifier> = []
        if raw.contains(.control) { set.insert(.control) }
        if raw.contains(.option) { set.insert(.option) }
        if raw.contains(.shift) { set.insert(.shift) }
        if raw.contains(.command) { set.insert(.command) }
        return set
    }

    /// Maps an AppKit key event onto the vocabulary KeyCombo.pretty already understands.
    static func keyName(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        case 36: return "return"
        case 76: return "return" // keypad enter
        case 48: return "tab"
        case 49: return "space"
        case 51, 117: return "delete"
        case 53: return "escape"
        case 43: return "comma"
        case 47: return "period"
        case 44: return "slash"
        case 27: return "minus"
        case 24: return "equal"
        case 122: return "f1"
        case 120: return "f2"
        case 99: return "f3"
        case 118: return "f4"
        case 96: return "f5"
        case 97: return "f6"
        case 98: return "f7"
        case 100: return "f8"
        case 101: return "f9"
        case 109: return "f10"
        case 103: return "f11"
        case 111: return "f12"
        case 115: return "↖"
        case 119: return "↘"
        case 116: return "⇞"
        case 121: return "⇟"
        default:
            guard let characters = event.charactersIgnoringModifiers?.lowercased(),
                  !characters.isEmpty else { return nil }
            guard let scalar = characters.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar),
                  !CharacterSet.illegalCharacters.contains(scalar) else { return nil }
            return characters
        }
    }
}

/// The armed cell: shows what is held right now and pulses while it waits.
struct KeyRecorderField: View {
    @ObservedObject var recorder: KeyRecorder
    var command: CommandID

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Text("Press keys…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)

            if !recorder.heldModifiers.isEmpty {
                let order: [KeyCombo.Modifier] = [.control, .option, .shift, .command]
                ForEach(order.filter { recorder.heldModifiers.contains($0) }, id: \.self) { modifier in
                    KeyCap(text: modifier.symbol, emphasis: .accent, compact: true)
                }
            }

            if recorder.feedback == .needsModifier {
                Text("needs ⌘ ⌃ ⌥ or ⇧")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            Capsule().strokeBorder(Color.accentColor.opacity(pulse ? 0.95 : 0.35), lineWidth: 1.5)
        )
        .animation(
            LatticeTheme.reducesMotion
                ? nil
                : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
            value: pulse
        )
        .onAppear { pulse = true }
        .onDisappear { pulse = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recording shortcut for \(command.title). Press keys. Escape cancels, Delete clears.")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
