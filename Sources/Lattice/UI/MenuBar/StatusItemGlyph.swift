import AppKit
import LatticeKit

/// Template glyphs for the status item. Drawn as alpha-only `NSImage`s so macOS
/// recolours them for light, dark and translucent menu bars and for notch overflow.
enum StatusItemGlyph {

    static let canvas = NSSize(width: 18, height: 18)

    static func image(layout: LayoutKind, paused: Bool) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { rect in
            let inner = rect.insetBy(dx: 2, dy: 2.5)
            let stroke: CGFloat = 1.3
            NSColor.black.setStroke()

            for tile in tiles(for: layout, in: inner) {
                let path = NSBezierPath(roundedRect: tile, xRadius: 1.5, yRadius: 1.5)
                path.lineWidth = stroke
                path.stroke()
            }

            if paused {
                // Knock a clean channel out of the tiles, then lay the slash in it.
                // A plain line over the outlines reads as noise at 18 pt.
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: rect.minX + 2.5, y: rect.minY + 2.5))
                slash.line(to: NSPoint(x: rect.maxX - 2.5, y: rect.maxY - 2.5))
                slash.lineCapStyle = .round

                if let context = NSGraphicsContext.current {
                    context.compositingOperation = .clear
                    slash.lineWidth = 3.4
                    slash.stroke()
                    context.compositingOperation = .sourceOver
                }
                slash.lineWidth = 1.5
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = paused
            ? "Lattice, tiling paused, \(layout.title) layout"
            : "Lattice, \(layout.title) layout"
        return image
    }

    // MARK: - Shapes

    private static func tiles(for layout: LayoutKind, in rect: NSRect) -> [NSRect] {
        let gap: CGFloat = 2

        switch layout {
        case .columns:
            return split(rect, count: 3, gap: gap, horizontal: true)
        case .rows:
            return split(rect, count: 3, gap: gap, horizontal: false)
        case .grid, .stack:
            return [
                NSRect(x: rect.minX, y: rect.minY, width: (rect.width - gap) / 2, height: (rect.height - gap) / 2),
                NSRect(x: rect.minX + (rect.width - gap) / 2 + gap, y: rect.minY,
                       width: (rect.width - gap) / 2, height: (rect.height - gap) / 2),
                NSRect(x: rect.minX, y: rect.minY + (rect.height - gap) / 2 + gap,
                       width: (rect.width - gap) / 2, height: (rect.height - gap) / 2),
                NSRect(x: rect.minX + (rect.width - gap) / 2 + gap, y: rect.minY + (rect.height - gap) / 2 + gap,
                       width: (rect.width - gap) / 2, height: (rect.height - gap) / 2),
            ]
        case .dwindle, .master:
            // One large pane, two stacked beside it: the silhouette that reads
            // as "tiling" at 18 pt better than an even split does.
            let leftWidth = (rect.width - gap) * 0.55
            let rightHeight = (rect.height - gap) / 2
            return [
                NSRect(x: rect.minX, y: rect.minY, width: leftWidth, height: rect.height),
                NSRect(x: rect.minX + leftWidth + gap, y: rect.minY,
                       width: rect.width - leftWidth - gap, height: rightHeight),
                NSRect(x: rect.minX + leftWidth + gap, y: rect.minY + rightHeight + gap,
                       width: rect.width - leftWidth - gap, height: rightHeight),
            ]
        }
    }

    private static func split(_ rect: NSRect, count: Int, gap: CGFloat, horizontal: Bool) -> [NSRect] {
        var result: [NSRect] = []
        let step = (horizontal ? rect.width : rect.height)
        let size = (step - gap * CGFloat(count - 1)) / CGFloat(count)
        for index in 0..<count {
            let offset = CGFloat(index) * (size + gap)
            result.append(
                horizontal
                    ? NSRect(x: rect.minX + offset, y: rect.minY, width: size, height: rect.height)
                    : NSRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: size)
            )
        }
        return result
    }
}
