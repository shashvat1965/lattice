import AppKit
import SwiftUI

// MARK: - Tokens

/// The single source of truth for Lattice's visual language.
///
/// Everything here is semantic: colours come from AppKit's dynamic system colours,
/// radii and spacing come from the architecture's 4-pt grid, and motion is spring-only
/// and honours Reduce Motion.
enum LatticeTheme {

    // MARK: Spacing (4-pt grid)

    enum Spacing {
        /// 4
        static let xxs: CGFloat = 4
        /// 8
        static let xs: CGFloat = 8
        /// 12
        static let sm: CGFloat = 12
        /// 16
        static let md: CGFloat = 16
        /// 20
        static let lg: CGFloat = 20
        /// 24
        static let xl: CGFloat = 24
        /// 32
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radii

    enum Radius {
        /// Controls, key caps, tiny thumbnails.
        static let sm: CGFloat = 6
        /// Materials, inset fields.
        static let md: CGFloat = 10
        /// Cards.
        static let card: CGFloat = 14
        /// Feature surfaces, permission banners.
        static let lg: CGFloat = 18
    }

    // MARK: Layout

    /// Horizontal gutter for every detail pane.
    static let gutter: CGFloat = 24
    /// Sidebar width, matching the native 200–240 pt range.
    static let sidebarWidth: CGFloat = 220
    /// Detail content never grows past this.
    static let contentMaxWidth: CGFloat = 1120
    /// Compact row height.
    static let compactRow: CGFloat = 32
    /// List row height.
    static let listRow: CGFloat = 44

    // MARK: Hairline

    /// One physical pixel on the current display.
    static var hairline: CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return 1 / max(1, scale)
    }

    // MARK: Motion

    static var spring: Animation { .spring(response: 0.34, dampingFraction: 0.86) }
    static var quickSpring: Animation { .spring(response: 0.24, dampingFraction: 0.90) }

    /// True when the user has asked the system to reduce motion.
    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// True when the user has asked the system to reduce transparency.
    static var reducesTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    static var increasesContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Spring animation, or `nil` when Reduce Motion is on.
    static var animation: Animation? {
        reducesMotion ? nil : spring
    }

    /// Short spring animation, or `nil` when Reduce Motion is on.
    static var quickAnimation: Animation? {
        reducesMotion ? nil : quickSpring
    }
}

// MARK: - Typography

extension View {

    /// 26 pt semibold — the one large title per pane.
    func latticeTitle() -> some View {
        font(.system(size: 26, weight: .semibold))
            .tracking(-0.35)
    }

    /// 15 pt semibold for card titles and important sub-headings.
    func latticeHeading() -> some View {
        font(.system(size: 15, weight: .semibold))
            .tracking(-0.1)
    }

    /// 13 pt regular. The workhorse.
    func latticeBody() -> some View {
        font(.system(size: 13))
    }

    /// 13 pt semibold for row titles.
    func latticeBodyStrong() -> some View {
        font(.system(size: 13, weight: .semibold))
    }

    /// 11 pt semibold, uppercase, widely tracked. Secondary by default.
    func latticeSectionHeader() -> some View {
        font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    /// 11 pt secondary.
    func latticeCaption() -> some View {
        font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    /// 11 pt tertiary, for asides under a control.
    func latticeFootnote() -> some View {
        font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    /// Monospaced digits for anything numeric, so values never jitter.
    func latticeMonoDigits() -> some View {
        monospacedDigit()
    }
}

// MARK: - Semantic colours

extension Color {
    /// Window content background.
    static var latticeCanvas: Color { Color(nsColor: .windowBackgroundColor) }
    /// A card / grouped-control fill that works with Reduce Transparency.
    static var latticeCardFill: Color { Color(nsColor: .controlBackgroundColor) }
    /// Hairline separators.
    static var latticeHairline: Color { Color(nsColor: .separatorColor) }
    /// Selection / pressed fill, derived from the user's accent.
    static var latticeAccentFill: Color { Color.accentColor.opacity(0.14) }
}

// MARK: - Brand mark

/// The Lattice mark: an accent squircle holding the Master layout — one tall pane
/// and two stacked panes. Reads as "tiling" at 16 pt and at 96 pt.
struct LatticeBrandMark: View {
    var size: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let padding = side * 0.205
            let gap = max(1, side * 0.055)
            let inner = CGRect(x: padding, y: padding,
                               width: side - padding * 2,
                               height: side - padding * 2)
            let masterWidth = (inner.width - gap) * 0.58
            let stackWidth = inner.width - gap - masterWidth
            let paneRadius = side * 0.055
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: side * 0.235, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: side * 0.235, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }

                pane(x: inner.minX, y: inner.minY, width: masterWidth, height: inner.height,
                     radius: paneRadius, opacity: 0.96)
                let stackHeight = (inner.height - gap) / 2
                pane(x: inner.minX + masterWidth + gap, y: inner.minY,
                     width: stackWidth, height: stackHeight,
                     radius: paneRadius, opacity: 0.86)
                pane(x: inner.minX + masterWidth + gap, y: inner.minY + stackHeight + gap,
                     width: stackWidth, height: stackHeight,
                     radius: paneRadius, opacity: 0.64)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.accentColor.opacity(0.26), radius: size * 0.16, x: 0, y: size * 0.04)
        .accessibilityHidden(true)
    }

    private func pane(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                      radius: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(width: max(0, width), height: max(0, height))
            .offset(x: x, y: y)
    }
}

// MARK: - Dividers

/// A true 1-pixel separator, rather than a 1-point one.
struct LatticeDivider: View {
    var insetLeading: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Color.latticeHairline)
            .frame(height: LatticeTheme.hairline)
            .padding(.leading, insetLeading)
            .accessibilityHidden(true)
    }
}
