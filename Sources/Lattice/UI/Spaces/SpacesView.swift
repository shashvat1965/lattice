import SwiftUI
import AppKit
import LatticeKit

struct SpacesView: View {
    @ObservedObject var model: AppModel
    @StateObject private var spaces = SpacesModel()
    @State private var hovered: SpaceID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if spaces.displays.isEmpty {
                    emptyState
                } else {
                    ForEach(spaces.displays, id: \.id) { display in
                        displaySection(display)
                    }
                }

                footnote
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { spaces.attach(model) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Spaces")
                    .font(.system(size: 26, weight: .semibold))
                Text("The Spaces your Mac already has, one card each.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    AddSpaceGuide.shared.begin(mode: .add, model: model)
                } label: {
                    Label("Add a Space…", systemImage: "plus")
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Menu {
                    Button("Remove a Space…") {
                        AddSpaceGuide.shared.begin(mode: .remove, model: model)
                    }
                    Divider()
                    Button("Mission Control Settings…") {
                        openDesktopSettings()
                    }
                    Button("Refresh") { spaces.reload() }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
                .controlSize(.large)
            }
        }
    }

    // MARK: Display section

    private func displaySection(_ display: (id: DisplayID, name: String, cards: [SpaceCard])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(display.name)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("\(display.cards.count) \(display.cards.count == 1 ? "Space" : "Spaces")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(display.cards) { card in
                        SpaceCardView(
                            card: card,
                            model: model,
                            isHovered: hovered == card.space,
                            onOpen: { spaces.go(to: card) },
                            onLayout: { spaces.setLayout($0, for: card) },
                            onSend: { spaces.sendFocusedWindow(to: card) },
                            onReset: { spaces.clearLayout(for: card) },
                            canReceive: spaces.canReceiveWindow(into: card)
                        )
                        .onHover { hovering in
                            hovered = hovering ? card.space : (hovered == card.space ? nil : hovered)
                        }
                    }

                    AddSpaceCard {
                        AddSpaceGuide.shared.begin(mode: .add, model: model)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Looking for Spaces…")
                .font(.system(size: 13, weight: .medium))
            Text("Lattice reads the Space list from WindowServer. If this stays empty, Mission Control is unavailable.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Refresh") { spaces.reload() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var footnote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.tertiary)
            Text("Lattice can see and switch every Space, and gives each one its own layout. Creating or deleting a Space stays with Mission Control — that is the only place macOS allows it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private func openDesktopSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Card

private struct SpaceCardView: View {
    let card: SpaceCard
    let model: AppModel
    let isHovered: Bool
    let onOpen: () -> Void
    let onLayout: (LayoutKind) -> Void
    let onSend: () -> Void
    let onReset: () -> Void
    let canReceive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
                .frame(width: 188, height: 108)
                .padding(8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Space \(card.index)")
                        .font(.system(size: 13, weight: .semibold))
                    if card.hasOwnLayout {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .help("This Space keeps its own layout")
                    }
                    Spacer()
                    Text("\(card.windows.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(card.hasOwnLayout ? card.layout.title : "\(card.layout.title) · default")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
        }
        .frame(width: 204)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(card.isCurrent ? Color.accentColor.opacity(0.9) : Color(nsColor: .separatorColor),
                              lineWidth: card.isCurrent ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.16 : 0.06),
                radius: isHovered ? 10 : 4, y: isHovered ? 4 : 2)
        .scaleEffect(isHovered ? 1.012 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isHovered)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button("Switch to This Space", action: onOpen)
            Divider()
            Menu("Layout") {
                ForEach(LayoutKind.allCases) { kind in
                    Button {
                        onLayout(kind)
                    } label: {
                        Label(kind.title, systemImage: card.layout == kind ? "checkmark" : kind.symbol)
                    }
                }
            }
            if canReceive {
                Button("Move Focused Window Here", action: onSend)
            }
            if card.hasOwnLayout {
                Button("Use Default Layout", action: onReset)
            }
        }
        .help(card.isCurrent ? "The Space you are on" : "Switch to Space \(card.index)")
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )

            GeometryReader { geo in
                ForEach(Array(card.windows.enumerated()), id: \.offset) { index, window in
                    let rect = index < card.tiles.count ? card.tiles[index] : .zero
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(windowTint(window))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .frame(width: max(4, rect.width * geo.size.width),
                               height: max(4, rect.height * geo.size.height))
                        .position(x: (rect.midX) * geo.size.width,
                                  y: (rect.midY) * geo.size.height)
                }

                if card.isEmpty {
                    Text("Empty")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(7)
        }
    }

    private func windowTint(_ window: ManagedWindow) -> Color {
        // Stable, pleasant per-app tint derived from the bundle id, so a Space reads at a glance.
        let seed = abs(window.bundleID?.hashValue ?? Int(window.id.raw))
        let hue = Double(seed % 360) / 360
        return Color(hue: hue, saturation: 0.28, brightness: 0.92)
    }
}

private struct AddSpaceCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                Text("Add a Space")
                    .font(.system(size: 12, weight: .medium))
                Text("Opens Mission Control")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 204, height: 182)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(Color(nsColor: .separatorColor))
            )
        }
        .buttonStyle(.plain)
    }
}
