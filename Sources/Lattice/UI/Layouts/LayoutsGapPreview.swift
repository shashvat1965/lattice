import AppKit
import SwiftUI
import LatticeKit

/// A four-window diagram that moves with the gap sliders. It applies the same arithmetic
/// as `Tiler.tileRect`: edge padding first, then the difference between the outer and
/// inner gap, then the inner gap around every tile.
///
/// This is the preview the old Settings section used. It lives here now because gaps
/// describe a layout, and this page is the one place that sets them.
struct LayoutsGapPreview: View {

    var gap: CGFloat
    var outerGap: CGFloat
    var layout: LayoutKind
    var edges: Margin = Margin()
    var respectMenuBar: Bool = true
    var respectDock: Bool = true

    private let scale: CGFloat = 0.62

    var body: some View {
        GeometryReader { geo in
            diagram(in: geo.size)
        }
        .animation(LatticeTheme.animation, value: gap)
        .animation(LatticeTheme.animation, value: outerGap)
        .animation(LatticeTheme.animation, value: layout)
        .animation(LatticeTheme.animation, value: edges)
        .animation(LatticeTheme.animation, value: respectMenuBar)
        .animation(LatticeTheme.animation, value: respectDock)
    }

    private func diagram(in size: CGSize) -> some View {
        let full = CGRect(origin: .zero, size: size)
        let screen = full.insetBy(dx: 2, dy: 2)
        let menuHeight: CGFloat = respectMenuBar ? 9 : 0
        let dockHeight: CGFloat = respectDock ? 9 : 0

        var base = screen.insetBy(dx: 2, dy: 2)
        base.origin.y += menuHeight
        base.size.height = max(1, base.height - menuHeight - dockHeight)
        base = CGRect(
            x: base.minX + edges.leading * scale,
            y: base.minY + edges.top * scale,
            width: max(1, base.width - (edges.leading + edges.trailing) * scale),
            height: max(1, base.height - (edges.top + edges.bottom) * scale)
        )
        let pre = (outerGap - gap) * scale
        let canvas = base.insetBy(dx: pre, dy: pre)
        let frames = LayoutMath.frames(
            count: 4,
            in: canvas,
            gap: max(1.5, gap * scale),
            layout: layout
        )

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))

            if respectMenuBar {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: max(0, screen.width - 24), height: 4)
                    .offset(x: 14, y: 3)
            }

            ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55),
                                          lineWidth: LatticeTheme.hairline)
                    )
                    .frame(width: max(0, frame.width), height: max(0, frame.height))
                    .offset(x: frame.minX, y: frame.minY)
            }

            if respectDock {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: min(70, screen.width * 0.38), height: 5)
                    .offset(x: (screen.width - min(70, screen.width * 0.38)) / 2,
                            y: screen.maxY - 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        )
    }
}

// MARK: - Disclosure

/// A quiet, full-width row that reveals the controls underneath it. The subtitle carries
/// the current values, so the disclosure says what is set without being opened.
struct LayoutsDisclosureRow: View {

    var title: String
    var subtitle: String?
    var isExpanded: Bool
    var showsDivider: Bool
    var action: () -> Void

    init(title: String,
         subtitle: String? = nil,
         isExpanded: Bool,
         showsDivider: Bool = true,
         action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isExpanded = isExpanded
        self.showsDivider = showsDivider
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: LatticeTheme.Spacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LatticeTheme.Spacing.md)
                .frame(minHeight: LatticeTheme.listRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide these controls")

            if showsDivider {
                LatticeDivider(insetLeading: LatticeTheme.Spacing.md)
            }
        }
        .animation(LatticeTheme.animation, value: isExpanded)
    }
}
