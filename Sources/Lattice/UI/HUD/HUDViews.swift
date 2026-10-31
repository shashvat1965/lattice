import AppKit
import SwiftUI
import LatticeKit

// MARK: - Toast model

@MainActor
final class HUDToastModel: ObservableObject {
    struct Toast: Identifiable {
        let id: UUID
        let text: String
        let symbol: String?
    }

    @Published var items: [Toast] = []
}

// MARK: - Toast stack

struct HUDToastStack: View {
    @ObservedObject var model: HUDToastModel

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            ForEach(model.items) { toast in
                HUDToastCapsule(toast: toast)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom))
                        )
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lattice notifications")
    }
}

private struct HUDToastCapsule: View {
    let toast: HUDToastModel.Toast

    var body: some View {
        HStack(spacing: 7) {
            if let symbol = toast.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(toast.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 13)
        .frame(height: 28)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: SurfaceTokens.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.text)
    }
}

// MARK: - Snap preview

@MainActor
final class HUDSnapPreviewModel: ObservableObject {
    @Published var label: String?
    @Published var appeared = false
}

/// The drag-to-snap target. The panel frame *is* the geometry: this view simply
/// fills its bounds minus the glow padding, so a 60 fps drag only moves an
/// AppKit frame and never republishes SwiftUI state.
struct HUDSnapPreview: View {
    @ObservedObject var model: HUDSnapPreviewModel
    let padding: CGFloat

    private var reduceMotion: Bool { SurfaceTokens.reduceMotion }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.92), lineWidth: 2)
                )
                .shadow(color: Color.accentColor.opacity(0.38), radius: 9, x: 0, y: 1)

            if let label = model.label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: SurfaceTokens.hairline)
                    )
                    .padding(.leading, 10)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .padding(padding)
        .scaleEffect(model.appeared || reduceMotion ? 1 : 0.97)
        .opacity(model.appeared || reduceMotion ? 1 : 0)
        .animation(SurfaceTokens.motion(), value: model.appeared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Snap target")
        .accessibilityValue(model.label ?? "")
    }
}
