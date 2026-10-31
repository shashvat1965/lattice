import Foundation
import CoreGraphics

/// Layout maths that understands Lattice's per-Space weight vector *and* the tuning values the
/// Settings window exposes (master ratio, stack peek, grid columns).
///
/// `LayoutMath` (owned by the layout/preview work) hard-codes 0.62 / 14 pt / automatic columns.
/// This wrapper delegates to it for rows and columns with uniform weights — so previews and
/// tiles agree exactly — and reproduces its master/grid formulas with the user's tuning applied.
/// Stack is computed here because `LayoutMath` assigns depth by array position before moving the
/// focused frame to the front, which gives the focused window the *smallest* frame; the depth here
/// is a rank around the focus, so the focused tile is always full size and `peek` is exact.
public enum WeightedLayout {

    public static func frames(count: Int,
                              in rect: CGRect,
                              gap: CGFloat,
                              layout: LayoutKind,
                              weights: [CGFloat] = [],
                              focusIndex: Int = 0,
                              masterRatio: Double = 0.62,
                              stackPeek: CGFloat = 14,
                              gridColumns: Int = 0) -> [CGRect] {
        guard count > 0 else { return [] }
        let normalised = normalise(weights, count: count)
        let gap = max(0, gap)

        // Simple split layouts keep using LayoutMath when the user has not resized anything, so
        // previews, tests and tiles stay pixel-identical.
        if isUniform(normalised) && (layout == .rows || layout == .columns) {
            return LayoutMath.frames(count: count, in: rect, gap: gap,
                                     layout: layout, weights: normalised,
                                     focusIndex: focusIndex)
        }

        let inner = rect.insetBy(dx: gap, dy: gap)
        guard inner.width > 0, inner.height > 0 else {
            return Array(repeating: rect, count: count)
        }
        if count == 1 { return [inner] }

        switch layout {
        case .dwindle:
            return dwindle(weights: normalised, in: inner, gap: gap)
        case .columns:
            return columns(weights: normalised, in: inner, gap: gap)
        case .rows:
            return rows(weights: normalised, in: inner, gap: gap)
        case .grid:
            return grid(weights: normalised, in: inner, gap: gap, columns: gridColumns)
        case .master:
            return master(weights: normalised, in: inner, gap: gap, ratio: masterRatio)
        case .stack:
            return stack(count: count, in: inner, focusIndex: focusIndex, peek: max(0, stackPeek))
        }
    }

    // MARK: - Normalisation

    public static func normalise(_ weights: [CGFloat], count: Int) -> [CGFloat] {
        var out = Array(weights.prefix(count))
        while out.count < count { out.append(1) }
        return out.map { min(6, max(0.2, $0.isFinite ? $0 : 1)) }
    }

    private static func isUniform(_ weights: [CGFloat]) -> Bool {
        guard let first = weights.first else { return true }
        return weights.allSatisfy { abs($0 - first) < 0.001 }
    }

    /// Splits `total` into `weights`-proportional spans with `gap` between them, ending exactly
    /// on the last pixel so frames never creep out of their display.
    private static func spans(total: CGFloat, gap: CGFloat, weights: [CGFloat]) -> [CGFloat] {
        let n = weights.count
        guard n > 0 else { return [] }
        let usable = max(0, total - gap * CGFloat(n - 1))
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return Array(repeating: usable / CGFloat(n), count: n) }
        var result = weights.map { usable * ($0 / sum) }
        let assigned = result.reduce(0, +)
        result[n - 1] += usable - assigned
        return result
    }

    // MARK: - Layouts

    private static func columns(weights: [CGFloat], in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let widths = spans(total: rect.width, gap: gap, weights: weights)
        var result: [CGRect] = []
        var x = rect.minX
        for width in widths {
            result.append(CGRect(x: x, y: rect.minY, width: width, height: rect.height))
            x += width + gap
        }
        return result
    }

    private static func rows(weights: [CGFloat], in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let heights = spans(total: rect.height, gap: gap, weights: weights)
        var result: [CGRect] = []
        var y = rect.minY
        for height in heights {
            result.append(CGRect(x: rect.minX, y: y, width: rect.width, height: height))
            y += height + gap
        }
        return result
    }

    private static func dwindle(weights: [CGFloat], in rect: CGRect, gap: CGFloat) -> [CGRect] {
        var result: [CGRect] = []
        var remaining = weights
        var area = rect

        while remaining.count > 1 {
            let first = remaining.removeFirst()
            let uniform = remaining.allSatisfy { abs($0 - first) < 0.001 }
            let ratio: CGFloat
            if uniform {
                // Match LayoutMath's default bisection exactly so previews stay honest.
                ratio = remaining.count == 1 ? 0.5 : 0.55
            } else {
                let rest = remaining.reduce(0, +)
                ratio = min(0.8, max(0.2, first / (first + rest)))
            }

            let vertical = area.width >= area.height
            if vertical {
                let usable = max(0, area.width - gap)
                let firstWidth = usable * ratio
                result.append(CGRect(x: area.minX, y: area.minY, width: firstWidth, height: area.height))
                area = CGRect(x: area.minX + firstWidth + gap, y: area.minY,
                              width: max(0, usable - firstWidth), height: area.height)
            } else {
                let usable = max(0, area.height - gap)
                let firstHeight = usable * ratio
                result.append(CGRect(x: area.minX, y: area.minY, width: area.width, height: firstHeight))
                area = CGRect(x: area.minX, y: area.minY + firstHeight + gap,
                              width: area.width, height: max(0, usable - firstHeight))
            }

            if area.width < 1 || area.height < 1 {
                // The Space has run out of pixels; the remaining windows share the sliver
                // rather than growing outside the display.
                result.append(contentsOf: Array(repeating: area, count: remaining.count))
                return result
            }
        }
        result.append(area)
        return result
    }

    private static func grid(weights: [CGFloat], in rect: CGRect, gap: CGFloat, columns requested: Int) -> [CGRect] {
        let count = weights.count
        let columnCount = max(1, min(count, requested > 0 ? requested : Int(ceil(sqrt(Double(count))))))
        let rowCount = Int(ceil(Double(count) / Double(columnCount)))

        var columnWeights = Array(repeating: CGFloat(0), count: columnCount)
        var columnCounts = Array(repeating: CGFloat(0), count: columnCount)
        var rowWeights = Array(repeating: CGFloat(0), count: rowCount)
        var rowCounts = Array(repeating: CGFloat(0), count: rowCount)
        for (index, weight) in weights.enumerated() {
            let column = index % columnCount
            let row = index / columnCount
            columnWeights[column] += weight
            columnCounts[column] += 1
            rowWeights[row] += weight
            rowCounts[row] += 1
        }
        columnWeights = columnWeights.enumerated().map { columnWeights[$0.offset] / max(1, columnCounts[$0.offset]) }
        rowWeights = rowWeights.enumerated().map { rowWeights[$0.offset] / max(1, rowCounts[$0.offset]) }

        let widths = spans(total: rect.width, gap: gap, weights: columnWeights)
        let heights = spans(total: rect.height, gap: gap, weights: rowWeights)

        var xs: [CGFloat] = []
        var x = rect.minX
        for width in widths { xs.append(x); x += width + gap }
        var ys: [CGFloat] = []
        var y = rect.minY
        for height in heights { ys.append(y); y += height + gap }

        var result: [CGRect] = []
        for index in 0..<count {
            let column = index % columnCount
            let row = index / columnCount
            result.append(CGRect(x: xs[column], y: ys[row],
                                 width: widths[column], height: heights[row]))
        }
        return result
    }

    /// Master keeps `ratio` (clamped 0.4–0.8) of the width. A user resize is expressed relative
    /// to the uniform share, so dragging "Wider" grows the master without losing the preference.
    private static func master(weights: [CGFloat], in rect: CGRect, gap: CGFloat, ratio preference: Double) -> [CGRect] {
        let count = weights.count
        if count == 1 { return [rect] }
        let mean = weights.reduce(0, +) / CGFloat(count)
        let base = min(0.8, max(0.4, preference))
        let derived = mean > 0 ? base * (weights[0] / mean) : base
        let ratio = min(0.8, max(0.4, derived))

        let masterWidth = max(0, (rect.width - gap) * ratio)
        let stackRect = CGRect(x: rect.minX + masterWidth + gap, y: rect.minY,
                               width: max(0, rect.width - masterWidth - gap), height: rect.height)
        var result = [CGRect(x: rect.minX, y: rect.minY, width: masterWidth, height: rect.height)]
        result.append(contentsOf: rows(weights: Array(weights.dropFirst()), in: stackRect, gap: gap))
        return result
    }

    /// Accordion: the focused window is full size, the rest recede behind it at `peek` points per
    /// step. Frames stay in tile order — the rank (not the array position) carries the depth, so
    /// the window that receives frame `i` is always tile `i`.
    private static func stack(count: Int, in rect: CGRect, focusIndex: Int, peek: CGFloat) -> [CGRect] {
        let focus = min(max(0, focusIndex), count - 1)
        var result: [CGRect] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let rank = ((index - focus) % count + count) % count
            let inset = peek * CGFloat(rank)
            result.append(CGRect(x: rect.minX + inset,
                                 y: rect.minY + inset * 0.6,
                                 width: max(1, rect.width - inset * 2),
                                 height: max(1, rect.height - inset * 1.2)))
        }
        return result
    }
}
