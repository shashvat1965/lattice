import Foundation
import CoreGraphics

/// Thin, typed wrapper over the private SkyLight (CGS) symbols Lattice is allowed to use.
///
/// Everything here is *read* or *native* Space manipulation that works with SIP enabled:
/// describing Spaces, asking WindowServer to move a window, and selecting a Space.
/// There is no scripting addition, no SIP change, and no injected code.
///
/// Symbols were verified on macOS 26.3.1:
///   CGSMainConnectionID
///   CGSCopyManagedDisplaySpaces
///   CGSGetActiveSpace
///   CGSManagedDisplaySetCurrentSpace          (works: returns 0)
///   CGSCopySpacesForWindows                   (mask 7 = all spaces containing a window)
///   CGSCopyManagedDisplayForWindow
///   CGSMoveWindowsToManagedSpace              (own-process windows only when untrusted)
///   CGSAddWindowsToSpaces / CGSRemoveWindowsFromSpaces
///
/// All `Copy` functions are declared returning `Unmanaged` so we take ownership exactly once
/// instead of leaking a CF object per call.
enum SkyLight {

    typealias ConnectionFn = @convention(c) () -> UInt32
    typealias CopyDisplaySpacesFn = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    typealias GetActiveSpaceFn = @convention(c) (UInt32) -> UInt64
    typealias SetCurrentSpaceFn = @convention(c) (UInt32, CFString, UInt64) -> Int32
    typealias CopySpacesForWindowsFn = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias MoveWindowsFn = @convention(c) (UInt32, CFArray, UInt64) -> Int32
    typealias AddRemoveWindowsFn = @convention(c) (UInt32, CFArray, CFArray) -> Int32
    typealias CopyDisplayForWindowFn = @convention(c) (UInt32, UInt32) -> Unmanaged<CFString>?

    /// Mask used by yabai and friends: every Space that currently contains the window.
    /// (On macOS 26 only bits 0x4/0x7 return results; 0x7 is the documented "all".)
    static let spaceMaskAll: Int32 = 0x7

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY
    )

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static let connectionFn: ConnectionFn? = symbol("CGSMainConnectionID")
    private static let copyDisplaySpacesFn: CopyDisplaySpacesFn? = symbol("CGSCopyManagedDisplaySpaces")
    private static let getActiveSpaceFn: GetActiveSpaceFn? = symbol("CGSGetActiveSpace")
    private static let setCurrentSpaceFn: SetCurrentSpaceFn? = symbol("CGSManagedDisplaySetCurrentSpace")
    private static let copySpacesForWindowsFn: CopySpacesForWindowsFn? = symbol("CGSCopySpacesForWindows")
    private static let moveWindowsFn: MoveWindowsFn? = symbol("CGSMoveWindowsToManagedSpace")
    private static let addWindowsFn: AddRemoveWindowsFn? = symbol("CGSAddWindowsToSpaces")
    private static let removeWindowsFn: AddRemoveWindowsFn? = symbol("CGSRemoveWindowsFromSpaces")
    private static let copyDisplayForWindowFn: CopyDisplayForWindowFn? = symbol("CGSCopyManagedDisplayForWindow")

    static let connection: UInt32 = connectionFn?() ?? 0

    static var isAvailable: Bool { connection != 0 }
    static var hasMoveSymbol: Bool { moveWindowsFn != nil }
    static var hasSetCurrentSpaceSymbol: Bool { setCurrentSpaceFn != nil }

    // MARK: - Reading

    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let fn = copyDisplaySpacesFn else { return [] }
        guard let value = fn(connection)?.takeRetainedValue() else { return [] }
        return (value as? [[String: Any]]) ?? []
    }

    static func activeSpace() -> UInt64? {
        guard let fn = getActiveSpaceFn else { return nil }
        let raw = fn(connection)
        return raw == 0 ? nil : raw
    }

    /// Every Space that contains `window`. A normal window is in one of them; a fullscreen
    /// window is in its own fullscreen Space plus (briefly) the Space it came from.
    static func spaces(forWindow window: WindowID) -> [UInt64] {
        guard let fn = copySpacesForWindowsFn else { return [] }
        let list = [NSNumber(value: window.raw)] as CFArray
        guard let value = fn(connection, spaceMaskAll, list)?.takeRetainedValue() else { return [] }
        let numbers = (value as? [NSNumber]) ?? []
        return numbers.map { $0.uint64Value }.filter { $0 != 0 }
    }

    static func displayUUID(forWindow window: WindowID) -> String? {
        guard let fn = copyDisplayForWindowFn else { return nil }
        guard let value = fn(connection, window.raw)?.takeRetainedValue() else { return nil }
        let string = value as String
        return string.isEmpty ? nil : string
    }

    // MARK: - Acting

    @discardableResult
    static func setCurrentSpace(displayUUID: String, space: UInt64) -> Int32 {
        guard let fn = setCurrentSpaceFn else { return -1 }
        return fn(connection, displayUUID as CFString, space)
    }

    /// Asks WindowServer to move the window. The return value is **not** a reliable status on
    /// macOS 26 (it is uninitialised register noise), so callers must verify by re-reading
    /// `spaces(forWindow:)`. Cross-process moves are silently refused unless the caller has the
    /// private window-management privilege, so a false result is expected and handled by the
    /// synthetic-drag fallback in `SpaceBridge`.
    @discardableResult
    static func moveWindow(_ window: WindowID, to space: SpaceID) -> Int32 {
        guard let fn = moveWindowsFn else { return -1 }
        return fn(connection, [NSNumber(value: window.raw)] as CFArray, space.raw)
    }

    @discardableResult
    static func addWindow(_ window: WindowID, to space: SpaceID) -> Int32 {
        guard let fn = addWindowsFn else { return -1 }
        return fn(connection,
                  [NSNumber(value: window.raw)] as CFArray,
                  [NSNumber(value: space.raw)] as CFArray)
    }

    @discardableResult
    static func removeWindow(_ window: WindowID, from space: SpaceID) -> Int32 {
        guard let fn = removeWindowsFn else { return -1 }
        return fn(connection,
                  [NSNumber(value: window.raw)] as CFArray,
                  [NSNumber(value: space.raw)] as CFArray)
    }
}
