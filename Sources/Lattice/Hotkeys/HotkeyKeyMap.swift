import AppKit
import Carbon
import CoreGraphics
import Foundation
import LatticeKit

/// Turns a `KeyCombo.key` into a virtual key code for the keyboard layout the user is
/// actually typing on. Letters and punctuation are resolved by translating every virtual
/// key through the live TIS layout with `UCKeyTranslate`, so a Dvorak or AZERTY keyboard
/// gets the key that *prints* the character rather than the ANSI position. If the character
/// lives behind Shift on that layout (`1` on AZERTY types `&`), the mapping says so and the
/// registration adds Shift to the chord. Named keys (arrows, return, tab, …) use their fixed
/// virtual codes because they are not characters.
enum HotkeyKeyMap {

    struct Mapping {
        var keyCode: CGKeyCode
        /// True when the layout needs Shift to produce the requested character.
        var requiresShift: Bool
    }

    // MARK: - Special keys

    /// Non-character keys. These are physical keys in every layout.
    private static let specialKeys: [String: CGKeyCode] = [
        "left": 123,
        "right": 124,
        "down": 125,
        "up": 126,
        "return": 36,
        "tab": 48,
        "space": 49,
        "escape": 53,
        "delete": 51,
    ]

    /// Named punctuation from `KeyCombo` → the character it types.
    private static let namedCharacters: [String: String] = [
        "comma": ",",
        "period": ".",
        "slash": "/",
        "minus": "-",
        "equal": "=",
    ]

    /// Last-resort ANSI codes, used only if the live layout cannot translate the character
    /// (e.g. an input source with no Unicode key layout data). Never the primary path.
    private static let ansiFallback: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, "`": 50,
    ]

    // MARK: - Public

    /// Virtual key code (and any implicit Shift) for a combo key, or `nil` if this keyboard
    /// cannot type it.
    static func mapping(for key: String) -> Mapping? {
        let normalized = key.lowercased()
        if let special = specialKeys[normalized] {
            return Mapping(keyCode: special, requiresShift: false)
        }

        let character: String
        if let named = namedCharacters[normalized] {
            character = named
        } else if normalized.count == 1 {
            character = normalized
        } else {
            return nil
        }

        let maps = characterMaps()
        if let code = maps.plain[character] {
            return Mapping(keyCode: code, requiresShift: false)
        }
        if let code = maps.shifted[character] {
            return Mapping(keyCode: code, requiresShift: true)
        }
        if let code = ansiFallback[character] {
            return Mapping(keyCode: code, requiresShift: false)
        }
        return nil
    }

    static func keyCode(for key: String) -> CGKeyCode? {
        mapping(for: key)?.keyCode
    }

    /// Carbon modifier mask for a set of `KeyCombo.Modifier`s.
    static func carbonModifiers(for modifiers: Set<KeyCombo.Modifier>) -> UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.control) { mask |= UInt32(controlKey) }
        if modifiers.contains(.option) { mask |= UInt32(optionKey) }
        if modifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        if modifiers.contains(.command) { mask |= UInt32(cmdKey) }
        return mask
    }

    /// The character → keycode tables, rebuilt whenever the input source changes.
    private static func characterMaps() -> (plain: [String: CGKeyCode], shifted: [String: CGKeyCode]) {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedMaps { return cached }
        let maps = buildMaps()
        cachedMaps = maps
        return maps
    }

    static func invalidate() {
        lock.lock()
        cachedMaps = nil
        lock.unlock()
    }

    /// Watch for input-source switches. Called once from `HotkeyCenter.install`.
    static func startWatchingLayout() {
        guard !watching else { return }
        watching = true
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            invalidate()
        }
    }

    // MARK: - TIS + UCKeyTranslate

    private static let lock = NSLock()
    private static var cachedMaps: (plain: [String: CGKeyCode], shifted: [String: CGKeyCode])?
    private static var watching = false

    private static func buildMaps() -> (plain: [String: CGKeyCode], shifted: [String: CGKeyCode]) {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return ([:], [:]) }

        // `raw` is a CFData owned by the input source; the bridged Data keeps it alive for
        // the duration of the translation.
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        return data.withUnsafeBytes { buffer -> (plain: [String: CGKeyCode], shifted: [String: CGKeyCode]) in
            guard let base = buffer.baseAddress else { return ([:], [:]) }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            var plain: [String: CGKeyCode] = [:]
            var shifted: [String: CGKeyCode] = [:]
            plain.reserveCapacity(128)
            shifted.reserveCapacity(128)

            let carbonShift = UInt32(shiftKey)
            for code in 0..<128 {
                if let character = translate(layout, code: code, modifiers: 0, keyboardType: keyboardType),
                   plain[character] == nil {
                    plain[character] = CGKeyCode(code)
                }
                if let character = translate(layout, code: code, modifiers: carbonShift, keyboardType: keyboardType),
                   plain[character] == nil, shifted[character] == nil {
                    shifted[character] = CGKeyCode(code)
                }
            }
            return (plain, shifted)
        }
    }

    private static func translate(_ layout: UnsafePointer<UCKeyboardLayout>,
                                  code: Int,
                                  modifiers: UInt32,
                                  keyboardType: UInt32) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout,
            UInt16(code),
            UInt16(kUCKeyActionDown),
            modifiers,
            keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        guard status == noErr, length > 0 else { return nil }
        let produced = chars.withUnsafeBufferPointer {
            String(utf16CodeUnits: $0.baseAddress!, count: length)
        }.lowercased()
        guard produced.count == 1,
              let scalar = produced.unicodeScalars.first,
              scalar.value >= 32 else { return nil }
        return produced
    }
}
