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

        guard let engine = EngineHolder.shared, engine.window(id) != nil else {
            let result = MoveResult(path: .failed, detail: "engine does not know \(id)")
            Log.error("space move \(id) -> \(target): \(result.summary)")
            completion?(result)
            return
        }

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
            // With SIP on, WindowServer refuses cross-process moves and there is no API that
            // can take its place. The old fallback dragged the title bar to the screen edge
            // and waited for macOS to switch Spaces; that edge is a *display* boundary here,
            // so it moved windows onto the other monitor instead. Stop at the truth and let
            // the app open Mission Control with an instruction.
            let result = MoveResult(
                path: .failed,
                detail: "macOS refuses cross-process Space moves with SIP on (WindowServer did not accept \(id) -> \(target)); use Mission Control"
            )
            Log.info("space move \(id) -> \(target): \(result.summary)")
            completion?(result)
        }
    }

    // The synthetic edge-drag fallback lived here. It was removed deliberately: macOS does
    // not switch Spaces when a window is dragged to a screen edge on this build, and when two
    // displays touch at that edge the drag moves the window to the other display instead.
    // A Mission Control drag is the only supported route, so the app guides the person there.
}
