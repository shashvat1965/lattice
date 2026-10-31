import CoreGraphics
import LatticeKit

/// The drag-to-snap targets. Deliberately small and learnable — the same set macOS itself
/// teaches through Mission Control and Rectangle, not a hidden grid.
enum DragSnapZone: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximise
    case centre

    var label: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .maximise: "Maximise"
        case .centre: "Centre"
        }
    }

    /// The exact frame the window will receive, mirroring `LayoutMath` so a snapped window
    /// lines up with its tiled neighbours.
    func rect(in visibleFrame: CGRect, gap: CGFloat) -> CGRect {
        let gap = max(0, gap)
        let inner = visibleFrame.insetBy(dx: gap, dy: gap)
        guard inner.width > 1, inner.height > 1 else { return visibleFrame }

        let halfWidth = (inner.width - gap) / 2
        let halfHeight = (inner.height - gap) / 2
        let rightX = inner.minX + halfWidth + gap
        let bottomY = inner.minY + halfHeight + gap

        switch self {
        case .leftHalf:
            return CGRect(x: inner.minX, y: inner.minY, width: halfWidth, height: inner.height)
        case .rightHalf:
            return CGRect(x: rightX, y: inner.minY, width: halfWidth, height: inner.height)
        case .topHalf:
            return CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: inner.minX, y: bottomY, width: inner.width, height: halfHeight)
        case .topLeft:
            return CGRect(x: inner.minX, y: inner.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: rightX, y: inner.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: inner.minX, y: bottomY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: rightX, y: bottomY, width: halfWidth, height: halfHeight)
        case .maximise:
            return inner
        case .centre:
            let width = inner.width * 0.7
            let height = inner.height * 0.7
            return CGRect(x: inner.midX - width / 2, y: inner.midY - height / 2,
                          width: width, height: height)
        }
    }
}

/// Pure geometry for choosing a zone from the pointer. No AppKit, no AX, easy to unit test.
///
/// The zone table (`p` = pointer, `f` = display `visibleFrame`, `e = 18%`):
///
/// ```
///  horizontal band: left  if p.x < f.minX + 0.18·f.width
///                   right if p.x > f.maxX - 0.18·f.width
///                   edge  otherwise (0.18…0.82)
///  vertical band:   top    if p.y < f.minY + 0.18·f.height
///                   bottom if p.y > f.maxY - 0.18·f.height
///                   middle otherwise
///
///  left+top      → Top Left quarter      right+top    → Top Right quarter
///  left+bottom   → Bottom Left quarter   right+bottom → Bottom Right quarter
///  left+middle   → Left Half             right+middle → Right Half
///  top+middle (centre 30% of width)      → Maximise (whole visible frame)
///  top+middle (outside that centre)      → Top Half
///  bottom+middle (centre 30% of width)   → Centre (70% of the visible frame, centred)
///  bottom+middle (outside that centre)   → Bottom Half
///  no band (the middle ~64% of the screen) → nothing, the window stays floating
/// ```
///
/// A pointer outside the visible frame (menu bar, Dock) never matches, and no zone arms
/// until the drag has travelled `minimumDragDistance`, so clicks and small nudges are inert.
enum DragSnapZones {

    /// Width of the edge band as a fraction of the display's visible frame.
    static let edgeBand: CGFloat = 0.18
    /// Horizontal span that turns the top/bottom edge into Maximise / Centre.
    static let centreSpan: CGFloat = 0.30
    /// A drag shorter than this never produces a preview.
    static let minimumDragDistance: CGFloat = 10

    static func zone(for point: CGPoint, in visibleFrame: CGRect) -> DragSnapZone? {
        // `contains` is half-open, so grow by a point: dragging into the very last pixel
        // column/row of the display must still snap.
        guard visibleFrame.width > 1, visibleFrame.height > 1,
              visibleFrame.insetBy(dx: -1, dy: -1).contains(point) else {
            return nil
        }

        let x = point.x - visibleFrame.minX
        let y = point.y - visibleFrame.minY

        let leftEdge = visibleFrame.width * edgeBand
        let rightEdge = visibleFrame.width - leftEdge
        let topEdge = visibleFrame.height * edgeBand
        let bottomEdge = visibleFrame.height - topEdge

        let inLeft = x < leftEdge
        let inRight = x > rightEdge
        let inTop = y < topEdge
        let inBottom = y > bottomEdge

        let centreLow = visibleFrame.width * (0.5 - centreSpan / 2)
        let centreHigh = visibleFrame.width * (0.5 + centreSpan / 2)
        let inCentre = x >= centreLow && x <= centreHigh

        if inLeft && inTop { return .topLeft }
        if inRight && inTop { return .topRight }
        if inLeft && inBottom { return .bottomLeft }
        if inRight && inBottom { return .bottomRight }
        if inTop { return inCentre ? .maximise : .topHalf }
        if inBottom { return inCentre ? .centre : .bottomHalf }
        if inLeft { return .leftHalf }
        if inRight { return .rightHalf }
        return nil
    }
}
