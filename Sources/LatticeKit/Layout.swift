import Foundation
import CoreGraphics

public enum LayoutKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case dwindle
    case columns
    case rows
    case grid
    case master
    case stack

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dwindle: "Dwindle"
        case .columns: "Columns"
        case .rows: "Rows"
        case .grid: "Grid"
        case .master: "Master"
        case .stack: "Stack"
        }
    }

    public var summary: String {
        switch self {
        case .dwindle: "Each new window splits the largest tile."
        case .columns: "Side-by-side columns, newest on the right."
        case .rows: "Stacked rows, full width."
        case .grid: "Even grid, balanced as windows come and go."
        case .master: "One large window, the rest in a column."
        case .stack: "All windows share one tile, sized to the active one."
        }
    }

    public var symbol: String {
        switch self {
        case .dwindle: "rectangle.split.3x1"
        case .columns: "rectangle.split.3x1"
        case .rows: "rectangle.split.1x3"
        case .grid: "square.grid.2x2"
        case .master: "rectangle.leadinghalf.inset.filled"
        case .stack: "rectangle.stack"
        }
    }
}

public enum LayoutMath {

    /// Pure geometry: where each of `count` windows goes inside `rect`.
    /// `weights` lets layouts honour a resized split (sum-normalised) instead of forcing equal tiles.
    public static func frames(count: Int,
                              in rect: CGRect,
                              gap: CGFloat,
                              layout: LayoutKind,
                              weights: [CGFloat] = [],
                              focusIndex: Int = 0) -> [CGRect] {
        guard count > 0 else { return [] }
        let inner = rect.insetBy(dx: gap, dy: gap)
        guard inner.width > 0, inner.height > 0 else { return Array(repeating: rect, count: count) }
        if count == 1 { return [inner] }

        switch layout {
        case .dwindle:
            return bsp(count: count, in: inner, gap: gap, vertical: inner.width >= inner.height)
        case .columns:
            return splitHorizontally(count: count, in: inner, gap: gap, weights: normalised(weights, count))
        case .rows:
            return splitVertically(count: count, in: inner, gap: gap, weights: normalised(weights, count))
        case .grid:
            return grid(count: count, in: inner, gap: gap)
        case .master:
            return masterStack(count: count, in: inner, gap: gap, ratio: 0.62)
        case .stack:
            return stack(count: count, in: inner, gap: gap, focusIndex: focusIndex)
        }
    }

    private static func normalised(_ weights: [CGFloat], _ count: Int) -> [CGFloat] {
        var w = Array(weights.prefix(count))
        while w.count < count { w.append(1) }
        let total = w.reduce(0, +)
        guard total > 0 else { return Array(repeating: 1 / CGFloat(count), count: count) }
        return w.map { $0 / total }
    }

    private static func splitHorizontally(count: Int, in rect: CGRect, gap: CGFloat, weights: [CGFloat]) -> [CGRect] {
        var result: [CGRect] = []
        var x = rect.minX
        let usableWidth = rect.width - gap * CGFloat(count - 1)
        for i in 0..<count {
            let width = usableWidth * weights[i]
            result.append(CGRect(x: x, y: rect.minY, width: width, height: rect.height))
            x += width + gap
        }
        return result
    }

    private static func splitVertically(count: Int, in rect: CGRect, gap: CGFloat, weights: [CGFloat]) -> [CGRect] {
        var result: [CGRect] = []
        var y = rect.minY
        let usableHeight = rect.height - gap * CGFloat(count - 1)
        for i in 0..<count {
            let height = usableHeight * weights[i]
            result.append(CGRect(x: rect.minX, y: y, width: rect.width, height: height))
            y += height + gap
        }
        return result
    }

    /// Recursive bisection: the first window keeps a stable half, the rest subdivide the other half.
    private static func bsp(count: Int, in rect: CGRect, gap: CGFloat, vertical: Bool) -> [CGRect] {
        if count == 1 { return [rect] }
        let ratio: CGFloat = count == 2 ? 0.5 : 0.55
        let remainder = count - 1
        var result: [CGRect] = []
        if vertical {
            let firstWidth = (rect.width - gap) * ratio
            let first = CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
            let rest = CGRect(x: rect.minX + firstWidth + gap, y: rect.minY,
                              width: rect.width - firstWidth - gap, height: rect.height)
            result.append(first)
            result.append(contentsOf: bsp(count: remainder, in: rest, gap: gap, vertical: rest.width >= rest.height))
        } else {
            let firstHeight = (rect.height - gap) * ratio
            let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
            let rest = CGRect(x: rect.minX, y: rect.minY + firstHeight + gap,
                              width: rect.width, height: rect.height - firstHeight - gap)
            result.append(first)
            result.append(contentsOf: bsp(count: remainder, in: rest, gap: gap, vertical: rest.width >= rest.height))
        }
        return result
    }

    private static func grid(count: Int, in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellWidth = (rect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        var result: [CGRect] = []
        for i in 0..<count {
            let row = i / columns
            let column = i % columns
            result.append(CGRect(x: rect.minX + CGFloat(column) * (cellWidth + gap),
                                 y: rect.minY + CGFloat(row) * (cellHeight + gap),
                                 width: cellWidth,
                                 height: cellHeight))
        }
        return result
    }

    private static func masterStack(count: Int, in rect: CGRect, gap: CGFloat, ratio: CGFloat) -> [CGRect] {
        if count == 1 { return [rect] }
        if count == 2 {
            let masterWidth = (rect.width - gap) * 0.5
            return [
                CGRect(x: rect.minX, y: rect.minY, width: masterWidth, height: rect.height),
                CGRect(x: rect.minX + masterWidth + gap, y: rect.minY,
                       width: rect.width - masterWidth - gap, height: rect.height),
            ]
        }
        let masterWidth = (rect.width - gap) * ratio
        let stackRect = CGRect(x: rect.minX + masterWidth + gap, y: rect.minY,
                               width: rect.width - masterWidth - gap, height: rect.height)
        var result = [CGRect(x: rect.minX, y: rect.minY, width: masterWidth, height: rect.height)]
        result.append(contentsOf: splitVertically(count: count - 1, in: stackRect, gap: gap,
                                                  weights: normalised([], count - 1)))
        return result
    }

    private static func stack(count: Int, in rect: CGRect, gap: CGFloat, focusIndex: Int) -> [CGRect] {
        // Accordion: the active window reads at full size, the rest peek behind it.
        var result: [CGRect] = []
        let peek: CGFloat = 14
        for i in 0..<count {
            let depth = CGFloat(count - 1 - i)
            result.append(rect.insetBy(dx: peek * depth, dy: peek * depth * 0.6))
        }
        if result.indices.contains(focusIndex), count > 1 {
            let focused = result.remove(at: focusIndex)
            result.insert(focused, at: 0)
        }
        return result
    }
}
