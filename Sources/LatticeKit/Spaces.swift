import Foundation
import CoreGraphics
import AppKit

/// Read-only + minimally-mutating access to the *real* macOS Spaces stack.
/// Everything here talks to WindowServer's SkyLight (CGS) layer, which is available
/// with SIP enabled: we never create or destroy Spaces, we only describe, select and
/// ask WindowServer to move windows between them.
public final class SpaceManager: @unchecked Sendable {

    public static let shared = SpaceManager()

    private init() {
        if !SkyLight.isAvailable {
            Log.error("SpaceManager: SkyLight unavailable (connectionID == 0); Spaces disabled")
        }
    }

    // MARK: - Reading

    public struct DisplaySpaces: Sendable {
        public var display: DisplayID
        public var displayUUID: String
        public var spaceIDs: [SpaceID]
        /// SkyLight Space type per entry: 0 = a normal user Space, 4 = a fullscreen Space.
        public var spaceTypes: [Int]
        public var currentIndex: Int
        public var isMain: Bool

        public init(display: DisplayID,
                    displayUUID: String,
                    spaceIDs: [SpaceID],
                    spaceTypes: [Int] = [],
                    currentIndex: Int,
                    isMain: Bool) {
            self.display = display
            self.displayUUID = displayUUID
            self.spaceIDs = spaceIDs
            self.spaceTypes = spaceTypes
            self.currentIndex = currentIndex
            self.isMain = isMain
        }

        public var current: SpaceID? {
            spaceIDs.indices.contains(currentIndex) ? spaceIDs[currentIndex] : nil
        }

        /// Spaces a person would number ("Space 1", "Space 2"…). Fullscreen Spaces are not
        /// user Spaces and must not shift the numbering.
        public var userSpaceIDs: [SpaceID] {
            guard spaceTypes.count == spaceIDs.count else { return spaceIDs }
            return zip(spaceIDs, spaceTypes).filter { $0.1 == 0 }.map(\.0)
        }

        public func index(of space: SpaceID, usersOnly: Bool = false) -> Int? {
            (usersOnly ? userSpaceIDs : spaceIDs).firstIndex(of: space)
        }
    }

    /// Every Space on every display, in Mission Control order.
    public func displaySpaces() -> [DisplaySpaces] {
        let raw = SkyLight.managedDisplaySpaces()
        var out: [DisplaySpaces] = []
        for (index, entry) in raw.enumerated() {
            let uuid = (entry["Display Identifier"] as? String) ?? String(index)
            let spaces = (entry["Spaces"] as? [[String: Any]]) ?? []
            var ids: [SpaceID] = []
            var types: [Int] = []
            for dict in spaces {
                let rawID: UInt64
                if let number = dict["id64"] as? NSNumber, number.uint64Value != 0 {
                    rawID = number.uint64Value
                } else if let mid = dict["ManagedSpaceID"] as? NSNumber, mid.uint64Value != 0 {
                    rawID = mid.uint64Value
                } else {
                    continue
                }
                ids.append(SpaceID(rawID))
                types.append((dict["type"] as? NSNumber)?.intValue ?? 0)
            }
            let currentManaged = (entry["Current Space"] as? [String: Any])
                .flatMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
            let currentIdx = currentManaged.flatMap { mid in
                ids.firstIndex(where: { $0.raw == mid })
            } ?? 0
            let displayID: DisplayID
            if uuid == "Main" || uuid.isEmpty {
                // Older WindowServer builds report "Main" instead of a UUID.
                displayID = NSScreen.screens.first.map(Self.displayID(for:)) ?? DisplayID(0)
            } else {
                displayID = Self.displayID(forUUID: uuid) ?? DisplayID(0)
            }
            out.append(DisplaySpaces(display: displayID,
                                     displayUUID: uuid,
                                     spaceIDs: ids,
                                     spaceTypes: types,
                                     currentIndex: currentIdx,
                                     isMain: index == 0))
        }
        return out
    }

    public func activeSpaceID() -> SpaceID? {
        SkyLight.activeSpace().map(SpaceID.init)
    }

    /// The Space currently showing on the display that contains the pointer.
    public func focusedSpace() -> SpaceID? {
        if let screen = Self.pointerScreen(),
           let entry = displaySpaces().first(where: { $0.display == Self.displayID(for: screen) }),
           let current = entry.current {
            return current
        }
        return activeSpaceID()
    }

    public func spaceFor(displayID: DisplayID) -> DisplaySpaces {
        displaySpaces().first { $0.display == displayID }
            ?? DisplaySpaces(display: displayID, displayUUID: "", spaceIDs: [],
                             spaceTypes: [], currentIndex: 0, isMain: true)
    }

    /// Every Space that is on-screen right now (one per display).
    public func visibleSpaceIDs() -> Set<SpaceID> {
        Set(displaySpaces().compactMap(\.current))
    }

    public func isVisible(_ space: SpaceID) -> Bool {
        visibleSpaceIDs().contains(space)
    }

    /// Which Space a window is on, straight from WindowServer. No AX guessing, and no
    /// dependency on `kCGWindowWorkspace` (which CGWindowListCopyWindowInfo does not expose
    /// on macOS 26 — reading it there silently produced an empty map).
    public func spaces(for window: WindowID) -> [SpaceID] {
        SkyLight.spaces(forWindow: window).map(SpaceID.init)
    }

    public func space(for window: WindowID) -> SpaceID? {
        let all = spaces(for: window)
        // A window can be reported on more than one Space while it is moving, or when it is
        // sticky. Prefer the Space the user can actually see; taking the first entry made a
        // window on the visible Space look like it belonged to the Space we just left, and the
        // engine then dropped it from the cache.
        if let visible = all.first(where: { isVisible($0) }) { return visible }
        return all.first
    }

    public func spaceAssignments(for windows: [WindowID]) -> [WindowID: SpaceID] {
        var map: [WindowID: SpaceID] = [:]
        map.reserveCapacity(windows.count)
        let visible = visibleSpaceIDs()
        for id in windows {
            let all = SkyLight.spaces(forWindow: id).map(SpaceID.init)
            if let live = all.first(where: { visible.contains($0) }) {
                map[id] = live
            } else if let first = all.first {
                map[id] = first
            }
        }
        return map
    }

    /// Kept for compatibility. Prefer `spaceAssignments(for:)`, which only asks about the
    /// windows the caller actually cares about.
    public func spaceAssignments() -> [WindowID: SpaceID] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        let ids: [WindowID] = list.compactMap { info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber else { return nil }
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return WindowID(number.uint32Value)
        }
        return spaceAssignments(for: ids)
    }

    public func displayUUID(for window: WindowID) -> String? {
        SkyLight.displayUUID(forWindow: window)
    }

    public func displayID(for window: WindowID) -> DisplayID? {
        guard let uuid = SkyLight.displayUUID(forWindow: window) else { return nil }
        return Self.displayID(forUUID: uuid)
    }

    // MARK: - Acting (always through native Spaces semantics)

    public enum SwitchOutcome: Sendable { case switched, keyEventFallback, failed }

    /// Select a Space on a display. The WindowServer call works with SIP enabled on macOS 26;
    /// the keystroke fallback exists for the rare display where it is refused.
    @discardableResult
    public func activate(_ space: SpaceID, on display: DisplayID) -> SwitchOutcome {
        let all = displaySpaces()
        guard let entry = all.first(where: { $0.display == display }) ?? all.first,
              let targetIndex = entry.spaceIDs.firstIndex(of: space) else {
            Log.error("space activate: \(space) is not on display \(display)")
            return .failed
        }

        if entry.current == space { return .switched }

        if SkyLight.hasSetCurrentSpaceSymbol {
            let status = SkyLight.setCurrentSpace(displayUUID: entry.displayUUID, space: space.raw)
            if status == 0 {
                Log.info("space activate: \(space) on \(entry.displayUUID) via WindowServer")
                return .switched
            }
            Log.error("space activate: WindowServer refused \(space) (status \(status)), trying keys")
        }

        // Native fallback: drive Mission Control the way a human does. Space-switch keys act on
        // the display under the pointer, so park the pointer on the target display first and
        // restore it afterwards.
        let delta = targetIndex - entry.currentIndex
        guard delta != 0 else { return .switched }
        let savedPointer = CGEvent(source: nil)?.location
        if let screen = Self.screen(for: display) {
            let centre = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            CGWarpMouseCursorPosition(Self.flip(centre, screens: NSScreen.screens))
        }
        let key = delta > 0 ? CGKeyCode(124) : CGKeyCode(123) // right / left arrow
        for _ in 0..<abs(delta) {
            if !KeySynth.controlKey(key) { 
                if let savedPointer { CGWarpMouseCursorPosition(savedPointer) }
                return .failed
            }
            usleep(120_000)
        }
        if let savedPointer { CGWarpMouseCursorPosition(savedPointer) }
        return .keyEventFallback
    }

    public func activateNextSpace(on display: DisplayID) {
        guard let entry = displaySpaces().first(where: { $0.display == display }) else { return }
        let ids = entry.spaceIDs
        guard !ids.isEmpty else { return }
        let next = (entry.currentIndex + 1) % ids.count
        activate(ids[next], on: display)
    }

    public func activatePreviousSpace(on display: DisplayID) {
        guard let entry = displaySpaces().first(where: { $0.display == display }) else { return }
        let ids = entry.spaceIDs
        guard !ids.isEmpty else { return }
        let prev = (entry.currentIndex - 1 + ids.count) % ids.count
        activate(ids[prev], on: display)
    }

    /// Raw WindowServer request. Verify with `spaces(for:)` — the return value is noise.
    @discardableResult
    public func requestWindowMove(_ window: WindowID, to space: SpaceID) -> Bool {
        guard SkyLight.hasMoveSymbol else {
            Log.error("space move: CGSMoveWindowsToManagedSpace is unavailable")
            return false
        }
        _ = SkyLight.moveWindow(window, to: space)
        return true
    }

    // MARK: - Helpers

    public static func displayID(for screen: NSScreen) -> DisplayID {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return DisplayID(number.uint32Value)
        }
        return DisplayID(0)
    }

    static func displayID(forUUID uuid: String) -> DisplayID? {
        guard let cfUUID = CFUUIDCreateFromString(nil, uuid as CFString) else { return nil }
        let cgUUID = CFUUIDCreateString(nil, cfUUID) as String
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            guard let displayUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
            if (CFUUIDCreateString(nil, displayUUID) as String) == cgUUID { return DisplayID(id) }
        }
        return nil
    }

    public static func screen(for display: DisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(for: $0) == display }
    }

    static func pointerScreen() -> NSScreen? {
        guard let pointer = CGEvent(source: nil)?.location else { return nil }
        let point = flip(pointer, screens: NSScreen.screens)
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// NSScreen uses a bottom-left origin for the primary display; AX / CGEvent / WindowServer
    /// use a top-left global origin. This is the single conversion used everywhere.
    static func flip(_ point: CGPoint, screens: [NSScreen]) -> CGPoint {
        let primaryHeight = screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func flip(_ rect: CGRect, screens: [NSScreen]) -> CGRect {
        let primaryHeight = screens.first?.frame.height ?? 0
        return CGRect(x: rect.origin.x,
                      y: primaryHeight - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }
}

/// Tiny wrapper so the engine never depends on NSEvent/CGEvent details.
public enum KeySynth {
    @discardableResult
    public static func controlKey(_ code: CGKeyCode) -> Bool {
        send(code, flags: .maskControl)
    }

    @discardableResult
    public static func send(_ code: CGKeyCode, flags: CGEventFlags) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
