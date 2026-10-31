import CoreGraphics
import LatticeKit

/// The geometry a tiled window lives in, shared by the snap preview and the drop so the
/// rectangle the user sees is exactly the rectangle the window receives — including
/// per-display overrides, per-edge padding and outer gaps smaller than the inner gap.
enum DragSnapGeometry {

    static func tileBase(for display: DisplayInfo, prefs: Preferences) -> CGRect {
        TilingGeometry.contentRect(for: display, prefs: prefs)
    }

    /// The frame a window snapped to `zone` will receive.
    static func frame(for zone: DragSnapZone, display: DisplayInfo, prefs: Preferences) -> CGRect {
        let base = tileBase(for: display, prefs: prefs)
        let gap = max(0, prefs.innerGap(for: display.id))
        return zone.rect(in: base, gap: gap).roundedToPixels(scale: max(1, display.scale))
    }
}
