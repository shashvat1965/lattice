import AppKit
import SwiftUI
import Combine
import LatticeKit

/// One real macOS Space, described for display. Nothing here is invented: every card maps
/// to a `ManagedSpaceID` that WindowServer gave us.
struct SpaceCard: Identifiable, Hashable {
    var id: SpaceID { space }
    let space: SpaceID
    let display: DisplayID
    let displayName: String
    let index: Int
    let isCurrent: Bool
    let layout: LayoutKind
    let hasOwnLayout: Bool
    let windows: [ManagedWindow]
    let tiles: [CGRect]

    var isEmpty: Bool { windows.isEmpty }
}

@MainActor
final class SpacesModel: ObservableObject {

    @Published private(set) var displays: [(id: DisplayID, name: String, cards: [SpaceCard])] = []
    @Published private(set) var currentSpace: SpaceID = SpaceID(0)

    private weak var model: AppModel?
    private var cancellables: Set<AnyCancellable> = []

    func attach(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.$spaces
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        model.$windowsBySpace
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        model.$focusedSpace
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        _ = PreferencesStore.shared.observe { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        reload()
    }

    func reload() {
        guard let model else { return }
        let prefs = PreferencesStore.shared.prefs
        currentSpace = model.focusedSpace

        var result: [(DisplayID, String, [SpaceCard])] = []
        for entry in SpaceManager.shared.displaySpaces() {
            let info = model.tiler.displayInfo(for: entry.display)
            let name = info?.name ?? "Display"
            let displayRect = info?.visibleFrame ?? .zero

            var cards: [SpaceCard] = []
            for (index, space) in entry.spaceIDs.enumerated() {
                let windows = (model.windowsBySpace[space] ?? [])
                    .filter { !$0.isMinimized }
                    .sorted { $0.id.raw < $1.id.raw }
                cards.append(SpaceCard(
                    space: space,
                    display: entry.display,
                    displayName: name,
                    index: index + 1,
                    isCurrent: space == entry.current,
                    layout: prefs.layout(for: space),
                    hasOwnLayout: prefs.hasOwnLayout(space),
                    windows: windows,
                    tiles: Self.tileRects(windows: windows, in: displayRect)
                ))
            }
            result.append((entry.display, name, cards))
        }
        displays = result.map { (id: $0.0, name: $0.1, cards: $0.2) }
    }

    /// Proportional rectangles for the mini map, normalised into a 0…1 box so the view can
    /// scale them to whatever card size it likes.
    static func tileRects(windows: [ManagedWindow], in display: CGRect) -> [CGRect] {
        guard display.width > 1, display.height > 1 else { return [] }
        return windows.map { window in
            CGRect(
                x: (window.frame.minX - display.minX) / display.width,
                y: (window.frame.minY - display.minY) / display.height,
                width: window.frame.width / display.width,
                height: window.frame.height / display.height
            ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    // MARK: - Actions

    func go(to card: SpaceCard) {
        SpaceManager.shared.activate(card.space, on: card.display)
    }

    func setLayout(_ kind: LayoutKind, for card: SpaceCard) {
        PreferencesStore.shared.update { $0.setLayout(kind, for: card.space) }
        model?.tiler.setLayout(kind, for: card.space)
        reload()
    }

    func clearLayout(for card: SpaceCard) {
        PreferencesStore.shared.update { prefs in
            prefs.spaceLayouts.removeValue(forKey: String(card.space.raw))
        }
        reload()
    }

    func sendFocusedWindow(to card: SpaceCard) {
        guard let model, let focused = model.engine.focused,
              let window = model.engine.window(focused) else { return }
        model.tiler.sendWindow(focused, from: window.space, to: card.space, on: card.display)
        reload()
    }

    func canReceiveWindow(into card: SpaceCard) -> Bool {
        guard let model, let focused = model.engine.focused,
              let window = model.engine.window(focused) else { return false }
        return window.space != card.space && window.display == card.display
    }
}
