import AppKit
import SwiftUI
import LatticeKit

/// A fully vector-drawn, resolution-independent preview of a layout.
///
/// Draws a screen, then the exact frames `LayoutMath` would produce at the requested
/// window count. Geometry is animated by the caller (the count change is a spring),
/// so hovering a card makes the tiles glide rather than cut.
struct LayoutThumbnail: View {

    var kind: LayoutKind
    var count: Int = 3
    var focusIndex: Int = 0
    var showsFocus: Bool = false
    var accent: Color = .accentColor
    var drawsScreen: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let minSide = min(width, height)
            let outerRadius = max(4, min(LatticeTheme.Radius.md, minSide * 0.09))
            let inset = drawsScreen ? max(3, minSide * 0.055) : 0
            let canvas = CGRect(x: inset, y: inset,
                                width: max(0, width - inset * 2),
                                height: max(0, height - inset * 2))
            let gap = max(1.5, minSide * 0.034)
            let tiles = frames(in: canvas, gap: gap)
            let tileRadius = max(2, min(5, minSide * 0.055))

            ZStack(alignment: .topLeading) {
                if drawsScreen {
                    RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                        .fill(screenFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: LatticeTheme.hairline)
                        }
                }

                ForEach(Array(tiles.enumerated()), id: \.offset) { index, rect in
                    windowTile(rect: rect,
                               radius: tileRadius,
                               isFocused: showsFocus && index == clampedFocus(tiles.count),
                               width: width)
                        .frame(width: max(0, rect.width), height: max(0, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Geometry

    private func clampedFocus(_ total: Int) -> Int {
        total == 0 ? 0 : min(max(0, focusIndex), total - 1)
    }

    private func frames(in rect: CGRect, gap: CGFloat) -> [CGRect] {
        let n = max(0, count)
        guard n > 0, rect.width > 1, rect.height > 1 else { return [] }
        if n == 1 { return [rect] }
        if kind == .stack {
            // The 14 pt peek in LayoutMath is tuned for real windows; scale it to thumbs.
            let peek = min(rect.width, rect.height) * 0.055
            var result: [CGRect] = []
            for i in 0..<n {
                let depth = CGFloat(n - 1 - i)
                result.append(rect.insetBy(dx: peek * depth, dy: peek * depth * 0.6))
            }
            let focus = clampedFocus(n)
            if result.indices.contains(focus) {
                let focused = result.remove(at: focus)
                result.insert(focused, at: 0)
            }
            return result
        }
        return LayoutMath.frames(count: n, in: rect, gap: gap, layout: kind, focusIndex: clampedFocus(n))
    }

    // MARK: Painting

    private var screenFill: LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color.white.opacity(0.075), Color.white.opacity(0.035)]
                : [Color.black.opacity(0.055), Color.black.opacity(0.028)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    private func windowTile(rect: CGRect, radius: CGFloat, isFocused: Bool, width: CGFloat) -> some View {
        let barHeight = max(2.5, min(rect.height * 0.22, 8))
        let showBar = rect.width > 22 && rect.height > 16
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isFocused
                            ? [accent.opacity(0.72), accent.opacity(0.52)]
                            : (scheme == .dark
                                ? [Color.white.opacity(0.25), Color.white.opacity(0.13)]
                                : [Color.black.opacity(0.22), Color.black.opacity(0.12)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            isFocused ? accent.opacity(0.9) : Color.primary.opacity(0.10),
                            lineWidth: isFocused ? max(1, LatticeTheme.hairline * 2) : LatticeTheme.hairline
                        )
                }

            if showBar {
                VStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: radius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: radius,
                        style: .continuous
                    )
                    .fill(isFocused ? Color.white.opacity(0.22) : Color.primary.opacity(0.11))
                    .frame(height: barHeight)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        }
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.22 : 0.08), radius: max(1, width * 0.006), x: 0, y: 0.5)
    }
}

/// A layout thumbnail pinned to a real display aspect, used for "preview on this screen".
struct ScreenLayoutPreview: View {
    var kind: LayoutKind
    var count: Int
    var aspect: CGFloat
    var accent: Color = .accentColor
    var height: CGFloat = 220

    var body: some View {
        LayoutThumbnail(kind: kind, count: count, showsFocus: true, accent: accent)
            .frame(width: max(80, height * max(0.8, aspect)), height: height)
    }
}
