import AppKit
import SwiftUI
import LatticeKit

// MARK: - Card

/// The base surface of the app: material, 14 pt radius, hairline border and a
/// one-pixel inner highlight along the top edge. Falls back to a solid system fill
/// when Reduce Transparency is on.
struct Card<Content: View>: View {

    var padding: CGFloat
    var radius: CGFloat
    var elevated: Bool
    private let content: Content

    @Environment(\.colorScheme) private var scheme

    init(padding: CGFloat = LatticeTheme.Spacing.md,
         radius: CGFloat = LatticeTheme.Radius.card,
         elevated: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.radius = radius
        self.elevated = elevated
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(radius: radius))
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(elevated ? (scheme == .dark ? 0.30 : 0.055) : 0),
                radius: elevated ? 12 : 0,
                x: 0,
                y: elevated ? 3 : 0
            )
    }
}

/// The material face of a card, without content or padding.
struct CardBackground: View {
    var radius: CGFloat = LatticeTheme.Radius.card

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if LatticeTheme.reducesTransparency {
                shape
                    .fill(Color.latticeCardFill)
                    .overlay {
                        // A hair of contrast so cards stay legible without material.
                        shape.fill(Color.primary.opacity(scheme == .dark ? 0.045 : 0.028))
                    }
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .overlay {
            shape.strokeBorder(
                Color.latticeHairline,
                lineWidth: LatticeTheme.increasesContrast
                    ? max(1, LatticeTheme.hairline)
                    : LatticeTheme.hairline
            )
        }
        .overlay {
            shape
                .inset(by: 0.5)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(scheme == .dark ? 0.09 : 0.45),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Section header

/// Uppercase 11 pt header with optional subtitle and trailing accessory.
struct SectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).latticeSectionHeader()
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Setting row

/// A native-height row: 13 pt title, optional 11 pt explanation, trailing control.
struct SettingRow<Control: View>: View {
    var title: String
    var subtitle: String?
    var showsDivider: Bool
    private let control: Control

    init(_ title: String,
         subtitle: String? = nil,
         showsDivider: Bool = false,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.showsDivider = showsDivider
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: LatticeTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: LatticeTheme.Spacing.sm)
                control
                    .controlSize(.regular)
            }
            .frame(minHeight: LatticeTheme.listRow)
            .padding(.vertical, subtitle == nil ? 0 : LatticeTheme.Spacing.xs)

            if showsDivider {
                LatticeDivider()
            }
        }
    }
}

// MARK: - Inline hint

/// A quiet aside that belongs to the control above it. Never a paragraph.
struct InlineHint: View {
    var text: String
    var symbol: String? = "info.circle"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status pill

struct StatusPill: View {

    enum Tone {
        case neutral, accent, positive, warning, critical

        var color: Color {
            switch self {
            case .neutral: return .secondary
            case .accent: return .accentColor
            case .positive: return Color(nsColor: .systemGreen)
            case .warning: return Color(nsColor: .systemOrange)
            case .critical: return Color(nsColor: .systemRed)
            }
        }

        var fill: Color {
            switch self {
            case .neutral: return Color.primary.opacity(0.06)
            case .accent: return Color.accentColor.opacity(0.13)
            case .positive: return Color(nsColor: .systemGreen).opacity(0.14)
            case .warning: return Color(nsColor: .systemOrange).opacity(0.16)
            case .critical: return Color(nsColor: .systemRed).opacity(0.14)
            }
        }
    }

    var text: String
    var tone: Tone = .neutral
    var symbol: String?
    var showsDot: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            if showsDot {
                Circle()
                    .fill(tone.color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .latticeMonoDigits()
                .lineLimit(1)
        }
        .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(tone.color))
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule(style: .continuous).fill(tone.fill))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Permission banner

/// The designed state for a missing Accessibility grant. Amber, not red: nothing is
/// broken, the user just has one switch to flip.
struct PermissionBanner: View {

    static let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    var onOpenSettings: () -> Void
    var onRequest: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    init(onOpenSettings: @escaping () -> Void = {
        NSWorkspace.shared.open(PermissionBanner.accessibilityURL)
    }, onRequest: (() -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
        self.onRequest = onRequest
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: LatticeTheme.Spacing.md) {
                icon
                copy
                Spacer(minLength: LatticeTheme.Spacing.md)
                actions
            }
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.md) {
                HStack(alignment: .top, spacing: LatticeTheme.Spacing.md) {
                    icon
                    copy
                }
                actions
                    .padding(.leading, 44)
            }
        }
        .padding(LatticeTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: LatticeTheme.Radius.lg, style: .continuous)
            shape
                .fill(Color(nsColor: .systemOrange).opacity(scheme == .dark ? 0.16 : 0.10))
                .overlay {
                    shape.strokeBorder(Color(nsColor: .systemOrange).opacity(0.34),
                                       lineWidth: LatticeTheme.hairline * 2)
                }
        }
        .accessibilityElement(children: .contain)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .systemOrange).opacity(0.20))
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemOrange))
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Accessibility access is required")
                .font(.system(size: 13, weight: .semibold))
            Text("Lattice moves windows through macOS Accessibility. Turn it on in System Settings, then come back — no restart needed.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            if let onRequest {
                Button("Request Access", action: onRequest)
                    .buttonStyle(.bordered)
            }
            Button("Open System Settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
        .fixedSize()
    }
}

// MARK: - Empty state

/// A composed empty state. Icon in a soft tile, a sentence, one action.
struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var compact: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: LatticeTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.primary.opacity(scheme == .dark ? 0.10 : 0.06),
                                     Color.primary.opacity(scheme == .dark ? 0.045 : 0.025)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Image(systemName: symbol)
                    .font(.system(size: compact ? 18 : 24, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(width: compact ? 44 : 58, height: compact ? 44 : 58)
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
            }

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                Text(message)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 2)
            }
        }
        .padding(LatticeTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
