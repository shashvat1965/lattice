import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Moving a window across real macOS Spaces. Lattice does it the way the system does it:
/// WindowServer is asked first, and if it refuses (which it does for other apps' windows with
/// SIP enabled on macOS 26), the title bar is dragged to the screen edge until macOS itself
/// performs the Space switch.
public enum SpaceBridge {

    public enum Path: String, Sendable {
        case windowServer = "windowServer"
        case nativeDrag = "nativeDrag"
        case alreadyThere = "alreadyThere"
        case failed = "failed"
    }

    public struct MoveResult: Sendable {
        public var path: Path
        public var detail: String
        public var ticks: Int

        public init(path: Path, detail: String, ticks: Int = 0) {
            self.path = path
            self.detail = detail
            self.ticks = ticks
        }

        public var succeeded: Bool { path == .windowServer || path == .nativeDrag || path == .alreadyThere }
        public var summary: String { "\(path.rawValue): \(detail)" }
    }

    /// Fire-and-forget compatibility entry point (was the only signature before).
    public static func move(window: WindowID,
                            pid: pid_t,
                            to space: SpaceID,
                            currentSpace: SpaceID,
                            display: SpaceManager.DisplaySpaces) {
        perform(window: window, to: space, display: display)
    }

    /// Try WindowServer, verify, and fall back to a synthetic native drag. Completion runs on
    /// the main queue. Always logs which path won, so the answer is in lattice.log.
    public static func perform(window id: WindowID,
                               to target: SpaceID,
                               display: SpaceManager.DisplaySpaces? = nil,
                               completion: ((MoveResult) -> Void)? = nil) {
        let manager = SpaceManager.shared
        let current = manager.space(for: id)

        if current == target {
            let result = MoveResult(path: .alreadyThere, detail: "window already on \(target)")
            Log.info("space move \(id) -> \(target): \(result.summary)")
            completion?(result)
            return
        }

        guard let engine = EngineHolder.shared, let managed = engine.window(id) else {
            let result = MoveResult(path: .failed, detail: "engine does not know \(id)")
            Log.error("space move \(id) -> \(target): \(result.summary)")
            completion?(result)
            return
        }

        // Snapshot everything the background drag needs before leaving the main thread.
        let frame = managed.frame
        let displayID = managed.display
        let element = managed.axElement
        let isFullscreen = managed.isFullscreen

        let symbolAvailable = SkyLight.hasMoveSymbol
        if symbolAvailable {
            manager.requestWindowMove(id, to: target)
        }

        // WindowServer's return value is unreliable; the Space list is the source of truth.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            if manager.spaces(for: id).contains(target) {
                let result = MoveResult(path: .windowServer,
                                        detail: "CGSMoveWindowsToManagedSpace accepted \(id) -> \(target)")
                Log.info("space move \(id) -> \(target): \(result.summary)")
                completion?(result)
                return
            }
            Log.info("space move \(id): WindowServer did not move the window " +
                     "(symbol=\(symbolAvailable), caller trusted=\(AXIsProcessTrusted())); trying native drag")

            // Bring the window forward so the first click drags instead of merely activating.
            engine.focus(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = nativeDrag(window: id,
                                            to: target,
                                            display: display,
                                            frame: frame,
                                            displayID: displayID,
                                            element: element,
                                            isFullscreen: isFullscreen)
                    DispatchQueue.main.async {
                        Log.info("space move \(id) -> \(target): \(result.summary)")
                        completion?(result)
                    }
                }
            }
        }
    }

    // MARK: - Native drag fallback

    private static func nativeDrag(window id: WindowID,
                                   to target: SpaceID,
                                   display: SpaceManager.DisplaySpaces?,
                                   frame: CGRect,
                                   displayID: DisplayID,
                                   element: AXUIElement?,
                                   isFullscreen: Bool) -> MoveResult {
        guard AXIsProcessTrusted() else {
            return MoveResult(path: .failed, detail: "accessibility not trusted; cannot post drag events")
        }
        guard let element else {
            return MoveResult(path: .failed, detail: "window element unavailable")
        }
        guard !isFullscreen else {
            return MoveResult(path: .failed, detail: "window is fullscreen; no title bar to drag")
        }
        guard let screen = SpaceManager.screen(for: displayID) ?? NSScreen.main else {
            return MoveResult(path: .failed, detail: "display \(displayID) not found")
        }

        let manager = SpaceManager.shared
        let entry = display ?? manager.spaceFor(displayID: displayID)
        guard let targetIndex = entry.spaceIDs.firstIndex(of: target) else {
            return MoveResult(path: .failed, detail: "target \(target) is not on display \(entry.displayUUID)")
        }

        let originalFrame = frame
        let savedPointer = CGEvent(source: nil)?.location
        let screenFrame = SpaceManager.flip(screen.frame, screens: NSScreen.screens)

        var ticks = 0
        var outcome: MoveResult?
        let hops = min(4, max(1, abs(targetIndex - entry.currentIndex)))

        for _ in 0..<hops {
            let live = manager.spaceFor(displayID: displayID)
            let currentIndex = live.spaceIDs.firstIndex(of: manager.space(for: id) ?? target) ?? live.currentIndex
            if manager.spaces(for: id).contains(target) {
                outcome = MoveResult(path: .nativeDrag, detail: "macOS switched Spaces during drag", ticks: ticks)
                break
            }
            let forward = targetIndex >= currentIndex
            let edgeX = forward ? screenFrame.maxX - 1 : screenFrame.minX + 1
            dragOnce(frame: element.frame ?? originalFrame,
                     edgeX: edgeX,
                     ticks: &ticks)
            usleep(380_000)
            if manager.spaces(for: id).contains(target) {
                outcome = MoveResult(path: .nativeDrag,
                                     detail: "edge drag switched \(currentIndex + 1) hop(s) toward \(target)",
                                     ticks: ticks)
                break
            }
        }

        // Put the cursor back where the person left it, whatever happened.
        if let savedPointer {
            CGWarpMouseCursorPosition(savedPointer)
        }
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))

        if let outcome {
            // The window is on its new Space now; that Space's tiling pass will place it.
            return outcome
        }

        // A failed drag can leave the window nudged into the screen edge; restore it on the
        // Space it stayed on so the only visible change is "nothing happened".
        let landed = manager.spaces(for: id)
        DispatchQueue.main.async {
            element.apply(frame: originalFrame, sizeFirst: false)
        }
        return MoveResult(path: .failed,
                          detail: "native drag did not change Spaces (landed on \(landed.map(\.raw)))",
                          ticks: ticks)
    }

    /// Picks a point in the title bar that is not a control. Dragging the middle of Safari's
    /// URL field or Chrome's tab strip does not move the window, so hit-test first.
    private static func titleBarPoint(for frame: CGRect) -> CGPoint {
        let candidates = [
            CGPoint(x: frame.maxX - 36, y: frame.minY + 9),
            CGPoint(x: frame.minX + 110, y: frame.minY + 9),
            CGPoint(x: frame.midX, y: frame.minY + 9),
        ]
        let system = AXUIElementCreateSystemWide()
        let blockedRoles: Set<String> = [
            kAXButtonRole as String,
            kAXTextFieldRole as String,
            kAXRadioButtonRole as String,
            kAXCheckBoxRole as String,
            kAXPopUpButtonRole as String,
            kAXMenuButtonRole as String,
            kAXSliderRole as String,
            "AXSegmentedControl",
            "AXTabGroup",
        ]
        for point in candidates {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
                  let hit else { return point }
            let role = hit.stringAttribute(kAXRoleAttribute) ?? ""
            if !blockedRoles.contains(role) { return point }
        }
        return candidates[0]
    }

    /// One complete mouse-down / move-to-edge / hold / mouse-up cycle. Always releases the
    /// button, even if an event cannot be posted.
    private static func dragOnce(frame: CGRect,
                                 edgeX: CGFloat,
                                 ticks: inout Int) {
        let titlePoint = titleBarPoint(for: frame)
        let edgePoint = CGPoint(x: edgeX, y: titlePoint.y)
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType, _ point: CGPoint) {
            guard let event = CGEvent(mouseEventSource: source,
                                      mouseType: type,
                                      mouseCursorPosition: point,
                                      mouseButton: .left) else { return }
            event.post(tap: .cghidEventTap)
        }

        var released = false
        func release(at point: CGPoint) {
            guard !released else { return }
            released = true
            post(.leftMouseUp, point)
        }
        defer { release(at: edgePoint) }

        CGWarpMouseCursorPosition(titlePoint)
        usleep(30_000)
        post(.leftMouseDown, titlePoint)
        usleep(90_000)

        // Creep to the edge in small steps so this is a real drag, not a teleport.
        let steps = 10
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(x: titlePoint.x + (edgePoint.x - titlePoint.x) * t,
                                y: titlePoint.y + (edgePoint.y - titlePoint.y) * t)
            post(.leftMouseDragged, point)
            usleep(22_000)
        }

        // Hold at the edge: this is the cue macOS uses to switch Spaces.
        for tick in 0..<12 {
            let jitter = CGFloat(tick % 2 == 0 ? 1 : -1)
            post(.leftMouseDragged, CGPoint(x: edgeX + jitter, y: edgePoint.y))
            ticks += 1
            usleep(55_000)
        }

        release(at: edgePoint)
        usleep(280_000)
    }
}
