import Foundation
import CoreGraphics

/// Everything that turns "a DisplayInfo + the user's Preferences" into the exact frames a
/// Space should occupy. Kept pure and free of AX so `LATTICE_SELFTEST` can exercise it on a
/// machine without Accessibility permission, and so the tiler itself stays a thin shell.
public enum TilingGeometry {

    /// The WindowServer will not place a window smaller than this; asking it to is a bug.
    public static let hardMinimumSize = CGSize(width: 80, height: 60)

    /// The minimum a tile should be before we stop calling the layout "good". Comes from
    /// preferences, but never below the hard floor.
    public static func effectiveMinimum(_ prefs: Preferences) -> CGSize {
        CGSize(width: max(hardMinimumSize.width, prefs.minTiledWidth),
               height: max(hardMinimumSize.height, prefs.minTiledHeight))
    }

    /// The rectangle tiles may occupy on `display`: the visible frame (or the full frame when
    /// the Dock is ignored), minus the menu bar / notch, minus the per-edge margins and the
    /// outer padding. All values are per-display aware.
    public static func contentRect(for display: DisplayInfo, prefs: Preferences) -> CGRect {
        let frame = display.frame
        let visible = display.visibleFrame
        guard frame.width > 1, frame.height > 1 else { return frame }
        let hasVisible = visible.width > 1 && visible.height > 1
        let respectsDock = prefs.docksRespect(for: display.id)

        var base = frame
        if hasVisible {
            // Decompose visibleFrame into per-edge insets so the menu bar and the Dock can be
            // honoured independently instead of all-or-nothing.
            let topInset = max(0, visible.minY - frame.minY)
            let bottomInset = max(0, frame.maxY - visible.maxY)
            let leadingInset = max(0, visible.minX - frame.minX)
            let trailingInset = max(0, frame.maxX - visible.maxX)

            // The notch is never negotiable, even with "respect menu bar" off.
            let keepMenuBar = prefs.respectMenuBar || display.hasNotch
            if keepMenuBar, topInset > 0, base.height > topInset + 1 {
                base.origin.y += topInset
                base.size.height -= topInset
            }
            if respectsDock {
                if bottomInset > 0, base.height > bottomInset + 1 {
                    base.size.height -= bottomInset
                }
                if leadingInset > 0, base.width > leadingInset + 1 {
                    base.origin.x += leadingInset
                    base.size.width -= leadingInset
                }
                if trailingInset > 0, base.width > trailingInset + 1 {
                    base.size.width -= trailingInset
                }
            }
        }

        // Per-edge margins are applied literally (negative values are treated as 0), then the
        // outer padding is added on every edge.
        let outer = max(0, prefs.outerPadding(for: display.id))
        let edges = prefs.edges
        let insets = Margin(top: max(0, edges.top) + outer,
                            leading: max(0, edges.leading) + outer,
                            bottom: max(0, edges.bottom) + outer,
                            trailing: max(0, edges.trailing) + outer)
        var content = base.inset(by: insets)

        // Belt and braces for notched displays: whatever the padding maths says, the top edge
        // of the tiling area can never sit above the bottom of the notch.
        if display.hasNotch, hasVisible {
            let notchBottom = frame.minY + max(0, visible.minY - frame.minY)
            if content.minY < notchBottom {
                let delta = notchBottom - content.minY
                content.origin.y += delta
                content.size.height = max(0, content.height - delta)
            }
        }

        if content.width < 1 { content.size.width = 1 }
        if content.height < 1 { content.size.height = 1 }
        return content
    }

    /// `LayoutMath` and `WeightedLayout` inset the rect they are given by `gap` themselves.
    /// Expanding the content by `gap` first means their internal inset lands exactly on the
    /// content rect, so the *outer* margin stays outerGap and the *inner* gaps are exactly gap.
    public static func layoutInputRect(content: CGRect, gap: CGFloat) -> CGRect {
        let g = max(0, gap)
        return content.insetBy(dx: -g, dy: -g)
    }

    /// Per-display layout override, then per-Space layout, then the global default.
    public static func resolvedLayout(space: SpaceID, display: DisplayInfo, prefs: Preferences) -> LayoutKind {
        prefs.override(for: display.id)?.layout ?? prefs.layout(for: space)
    }

    /// How many columns/rows of at least `minimum` points fit in `total`, including gaps.
    public static func capacity(total: CGFloat, gap: CGFloat, minimum: CGFloat) -> Int {
        guard minimum > 0, total > 0 else { return 1 }
        let usable = total + max(0, gap)
        let step = minimum + max(0, gap)
        return max(1, Int(floor(usable / step)))
    }
}

/// Resolves a layout request against the hard/preferred minimum sizes and degrades instead of
/// handing the WindowServer geometry it will refuse.
public enum TilingSolver {

    public struct Solution {
        /// One entry per window in tile order. `nil` means "leave this window alone this pass".
        public var frames: [CGRect?]
        public var layout: LayoutKind
        public var note: String?
        public var skipped: Int
        public var minimumSide: CGFloat

        public var placedCount: Int { frames.compactMap { $0 }.count }

        public init(frames: [CGRect?], layout: LayoutKind, note: String? = nil,
                    skipped: Int = 0, minimumSide: CGFloat = 0) {
            self.frames = frames
            self.layout = layout
            self.note = note
            self.skipped = skipped
            self.minimumSide = minimumSide
        }
    }

    public static func solve(count: Int,
                             content: CGRect,
                             gap: CGFloat,
                             layout: LayoutKind,
                             weights: [CGFloat] = [],
                             focusIndex: Int = 0,
                             masterRatio: Double = 0.62,
                             stackPeek: CGFloat = 14,
                             gridColumns: Int = 0,
                             minimum: CGSize = TilingGeometry.hardMinimumSize,
                             minimums: [CGSize] = [],
                             respectMinimums: Bool = true) -> Solution {
        let hard = TilingGeometry.hardMinimumSize
        let prefW = max(hard.width, minimum.width)
        let prefH = max(hard.height, minimum.height)

        guard count > 0 else {
            return Solution(frames: [], layout: layout)
        }
        guard content.width >= hard.width, content.height >= hard.height else {
            return Solution(frames: Array(repeating: nil, count: count),
                            layout: layout,
                            note: String(format: "content %.0fx%.0f is below the 80x60 floor", content.width, content.height),
                            skipped: count)
        }

        // A gap larger than a third of the screen cannot be honoured; clamp it so the maths
        // stays finite rather than producing inverted rectangles.
        let usableGap = max(0, min(gap, max(0, min(content.width, content.height) / 3)))
        var notes: [String] = []
        if usableGap != gap {
            notes.append(String(format: "gap clamped %.0f → %.0f", gap, usableGap))
        }

        let input = TilingGeometry.layoutInputRect(content: content, gap: usableGap)

        // Stack peeks must never push a window below the hard floor.
        var peek = max(0, stackPeek)
        if layout == .stack && count > 1 {
            let depth = CGFloat(count - 1)
            let maxWidthPeek = max(0, content.width - hard.width) / (2 * depth)
            let maxHeightPeek = max(0, content.height - hard.height) / (1.2 * depth)
            let allowed = min(maxWidthPeek, maxHeightPeek)
            if peek > allowed {
                notes.append(String(format: "peek clamped %.0f → %.0f", peek, allowed))
                peek = allowed
            }
        }

        func build(_ n: Int, _ kind: LayoutKind, _ columns: Int) -> [CGRect] {
            guard n > 0 else { return [] }
            return WeightedLayout.frames(count: n,
                                         in: input,
                                         gap: usableGap,
                                         layout: kind,
                                         weights: Array(weights.prefix(n)),
                                         focusIndex: min(max(0, focusIndex), n - 1),
                                         masterRatio: masterRatio,
                                         stackPeek: peek,
                                         gridColumns: columns)
        }

        /// The smallest side of the tile that determines the layout's quality. Stack peeks are
        /// intentional overlap, so only the full-size (focused) frame counts.
        func score(_ frames: [CGRect], _ kind: LayoutKind) -> CGFloat {
            guard !frames.isEmpty else { return 0 }
            let considered: [CGRect]
            if kind == .stack, let full = frames.max(by: { $0.width < $1.width }) {
                considered = [full]
            } else {
                considered = frames
            }
            return considered.map { min($0.width, $0.height) }.min() ?? 0
        }

        func meets(_ frames: [CGRect], kind: LayoutKind, _ width: CGFloat, _ height: CGFloat) -> Bool {
            guard !frames.isEmpty else { return false }
            // Stack peeks are intentional overlap; only the full-size frame needs to be usable.
            let considered: [CGRect]
            if kind == .stack, let full = frames.max(by: { $0.width < $1.width }) {
                considered = [full]
            } else {
                considered = frames
            }
            return considered.allSatisfy { $0.width >= width - 0.5 && $0.height >= height - 0.5 }
        }

        // Each window's own floor: the app's AXMinSize, the user's minimum, and our hard floor.
        // Planning around the real minimum is what stops the tiler asking for a 768x530 tile
        // that the app will refuse, which is what produced ragged, gappy layouts.
        let perWindowMin: [CGSize] = (0..<count).map { index in
            let appMin = index < minimums.count ? minimums[index] : .zero
            return CGSize(width: max(hard.width, max(prefW, appMin.width)),
                          height: max(hard.height, max(prefH, appMin.height)))
        }

        func fits(_ frames: [CGRect], kind: LayoutKind) -> Bool {
            guard !frames.isEmpty else { return false }
            if kind == .stack, let full = frames.max(by: { $0.width < $1.width }) {
                return full.width >= perWindowMin.map(\.width).max()! - 0.5
                    && full.height >= perWindowMin.map(\.height).max()! - 0.5
            }
            return frames.enumerated().allSatisfy { index, frame in
                guard index < perWindowMin.count else { return true }
                let need = perWindowMin[index]
                return frame.width >= need.width - 0.5 && frame.height >= need.height - 0.5
            }
        }

        var chosenKind = layout
        var chosenColumns = gridColumns
        var frames = build(count, chosenKind, chosenColumns)

        // The "tile anyway" mode (yabai-style): keep the layout the user asked for, write every
        // frame, and let each app clamp its own size. The result can overlap — that is the
        // trade the setting makes. No minimum-size planning, no "Space full" note.
        if !respectMinimums {
            return finish(frames.map { $0 }, kind: chosenKind, notes: notes, hard: .zero)
        }

        // 1. If the layout the user picked cannot honour the real minimums, look for the densest
        //    arrangement that can, before falling back to fewer windows on screen.
        if count > 1 && !fits(frames, kind: chosenKind) {
            var best: (kind: LayoutKind, columns: Int, frames: [CGRect], note: String)? = nil
            let maxColumns = max(1, count)
            for columns in stride(from: maxColumns, through: 1, by: -1) {
                let candidate = build(count, .grid, columns)
                if fits(candidate, kind: .grid) {
                    best = (.grid, columns, candidate,
                            "\(chosenKind.rawValue) cannot honour app minimums; using a \(columns)-column grid")
                    break
                }
            }
            if best == nil {
                let candidate = build(count, .columns, max(1, TilingGeometry.capacity(total: content.width, gap: usableGap, minimum: perWindowMin.map(\.width).max() ?? prefW)))
                if fits(candidate, kind: .columns) {
                    best = (.columns, 0, candidate, "\(chosenKind.rawValue) cannot honour app minimums; using columns")
                }
            }
            if let best {
                notes.append(best.note)
                chosenKind = best.kind
                chosenColumns = best.columns
                frames = best.frames
            }
        }

        // 2. If, even after degradation, the real minimums cannot be met, tile only as many
        //    windows as genuinely fit and leave the rest untouched. This has to run *before*
        //    the 80x60 safety net: squeezing nine 900 pt apps into 156 pt columns is worse
        //    than leaving them alone, and every refused write costs a visible jump and three
        //    minutes of "stubborn" before the same mistake is tried again.
        if count > 1, !fits(frames, kind: chosenKind) {
            let widest = max(hard.width, perWindowMin.map(\.width).max() ?? hard.width)
            let tallest = max(hard.height, perWindowMin.map(\.height).max() ?? hard.height)
            let columns = max(1, TilingGeometry.capacity(total: content.width, gap: usableGap, minimum: widest))
            let rows = max(1, TilingGeometry.capacity(total: content.height, gap: usableGap, minimum: tallest))
            let capacity = max(1, min(count, columns * rows))
            if capacity < count {
                notes.append("Space full: only \(capacity) of \(count) windows fit at their minimum size")
                var out: [CGRect?] = build(capacity, .grid, columns).map { $0 }
                out.append(contentsOf: Array(repeating: nil, count: count - capacity))
                return finish(out, kind: .grid, notes: notes, hard: hard)
            }
        }

        // 3. The hard floor: never place a window under 80x60. If the display cannot fit every
        //    window at that size, tile the ones that fit and leave the rest where they are.
        if frames.contains(where: { $0.width < hard.width - 0.5 || $0.height < hard.height - 0.5 }) {
            let columns = TilingGeometry.capacity(total: content.width, gap: usableGap, minimum: hard.width)
            let rows = TilingGeometry.capacity(total: content.height, gap: usableGap, minimum: hard.height)
            let capacity = max(1, min(count, columns * rows))
            let gridFrames = build(capacity, .grid, columns)
            if capacity < count {
                notes.append("display fits \(capacity) of \(count) windows at 80x60; leaving \(count - capacity) untiled")
            } else {
                notes.append("\(chosenKind.rawValue) produced sub-80x60 tiles; using a \(columns)-column grid")
            }
            var out: [CGRect?] = gridFrames.map { $0 }
            if out.count < count {
                out.append(contentsOf: Array(repeating: nil, count: count - out.count))
            }
            chosenKind = .grid
            return finish(out, kind: chosenKind, notes: notes, hard: hard)
        }

        return finish(frames.map { $0 }, kind: chosenKind, notes: notes, hard: hard)
    }

    private static func finish(_ frames: [CGRect?], kind: LayoutKind, notes: [String], hard: CGSize) -> Solution {
        var out = frames
        var skipped = 0
        for index in out.indices {
            guard let frame = out[index] else { skipped += 1; continue }
            if frame.width < hard.width - 0.5 || frame.height < hard.height - 0.5 {
                out[index] = nil
                skipped += 1
            }
        }
        let placed = out.compactMap { $0 }
        let minimumSide = placed.map { min($0.width, $0.height) }.min() ?? 0
        let note = notes.isEmpty ? nil : notes.joined(separator: "; ")
        return Solution(frames: out, layout: kind, note: note, skipped: skipped, minimumSide: minimumSide)
    }
}

/// Weight vector maintenance when a Space's windows come and go.
public enum WeightBalancing {

    /// Weights for the surviving tiles. With `autoBalance` on, a close returns the Space to
    /// equal shares; with it off, every surviving window keeps exactly the split it had.
    public static func afterClose(existing: [CGFloat],
                                  previousTiled: [WindowID],
                                  surviving: [WindowID],
                                  autoBalance: Bool) -> [CGFloat] {
        guard !autoBalance else { return Array(repeating: 1, count: surviving.count) }
        return surviving.map { id in
            if let index = previousTiled.firstIndex(of: id), existing.indices.contains(index) {
                return existing[index]
            }
            return 1
        }
    }
}

/// Pure tile-order maths so the insertion policy is testable and identical for every layout.
public enum TilerOrdering {

    /// Resolves "the currently focused tile" for `.afterFocused`. A window that has just appeared
    /// is usually focused already but is not in the order yet, so the last real anchor is used.
    public static func anchor(currentFocus: WindowID?,
                              in ids: [WindowID],
                              last: WindowID?) -> WindowID? {
        if let currentFocus, ids.contains(currentFocus) { return currentFocus }
        return last
    }

    public static func insertionIndex(policy: InsertionPolicy,
                                      in ids: [WindowID],
                                      focused: WindowID?) -> Int {
        switch policy {
        case .end:
            return ids.count
        case .master:
            return 0
        case .afterFocused:
            guard let focused, let index = ids.firstIndex(of: focused) else { return ids.count }
            return index + 1
        }
    }

    /// Inserts `new` as one run at the policy's insertion point. Returns the new order and the
    /// index each window landed at (for logging and tests).
    public static func inserting(_ new: [WindowID],
                                 into ids: [WindowID],
                                 policy: InsertionPolicy,
                                 focused: WindowID?) -> (order: [WindowID], indices: [Int]) {
        guard !new.isEmpty else { return (ids, []) }
        var order = ids
        var at = insertionIndex(policy: policy, in: ids, focused: focused)
        var indices: [Int] = []
        for id in new {
            let index = min(max(0, at), order.count)
            order.insert(id, at: index)
            indices.append(index)
            at = index + 1
        }
        return (order, indices)
    }
}
