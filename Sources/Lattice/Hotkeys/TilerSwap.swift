import Foundation
import LatticeKit

// MARK: - Swap two tiles by window id

extension Tiler {

    /// Swap the positions of two tiled windows without touching anything else.
    ///
    /// `Tiler.order` has a file-private setter, so the swap is expressed through the public
    /// `move(_:on:)` primitive: move one window across the gap, then move the other back into
    /// the vacated slot. `isSuspended` suppresses the intermediate reflows so the user sees a
    /// single animation, not a shuffle. Focus returns to `first` (the dragged window).
    @discardableResult
    func swapTiles(_ first: WindowID, _ second: WindowID, on space: SpaceID, animated: Bool = true) -> Bool {
        guard first != second else { return false }
        let tiled = tiledWindows(on: space)
        guard let indexA = tiled.firstIndex(of: first),
              let indexB = tiled.firstIndex(of: second) else { return false }

        let low = min(indexA, indexB)
        let high = max(indexA, indexB)
        let lowID = tiled[low]
        let highID = tiled[high]
        let span = high - low
        guard span > 0 else { return false }

        let wasSuspended = isSuspended
        isSuspended = true

        // Phase one: push the low tile to the high slot.
        engine.focus(lowID)
        for _ in 0..<span { move(.right, on: space) }

        // Phase two: the high tile is now one step lower; walk it back to the low slot.
        engine.focus(highID)
        for _ in 0..<(span - 1) { move(.left, on: space) }

        isSuspended = wasSuspended
        if !wasSuspended {
            engine.focus(first)
            reconcile(animated: animated)
        }
        return true
    }
}
