import AppKit
import SwiftUI
import LatticeKit

/// The real macOS Spaces for one display, drawn as small screen rectangles.
///
/// These are not named workspaces — they are WindowServer's own Spaces in Mission
/// Control order. The active one is filled; a thin accent rule sits beneath it.
struct SpaceStrip: View {

    var spaces: [SpaceID]
    var current: SpaceID?
    var rectSize: CGSize = CGSize(width: 24, height: 15)
    var showsUnderline: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            ForEach(Array(spaces.enumerated()), id: \.element) { index, space in
                let isCurrent = space == current
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(
                        isCurrent
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.80)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(
                                isCurrent ? Color.clear : Color.primary.opacity(0.12),
                                lineWidth: LatticeTheme.hairline
                            )
                    }
                    .frame(width: rectSize.width, height: rectSize.height)
                    .overlay(alignment: .bottom) {
                        if isCurrent && showsUnderline {
                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(6, rectSize.width * 0.52), height: 2)
                                .offset(y: 5)
                        }
                    }
                    .help("Space \(index + 1) of \(spaces.count)")
                    .accessibilityLabel("Space \(index + 1) of \(spaces.count)")
                    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(.bottom, showsUnderline ? 7 : 0)
    }
}

/// Space strip plus an honest "n of m" counter, used under display maps.
struct LabelledSpaceStrip: View {
    var spaces: [SpaceID]
    var current: SpaceID?
    var displayName: String?

    var body: some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            SpaceStrip(spaces: spaces, current: current)
            if let index = spaces.firstIndex(where: { $0 == current }) {
                Text("Space \(index + 1) of \(spaces.count)")
                    .latticeCaption()
                    .latticeMonoDigits()
            }
        }
    }
}
