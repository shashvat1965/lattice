import AppKit
import SwiftUI
import LatticeKit

/// The layout picker, built around the model that actually ships: a layout belongs to
/// a Space, not to the app. One card per layout, one live preview of the Space you are
/// on right now, and one chip per real Space on this display.
struct LayoutsGallery: View {

    @ObservedObject var model: AppModel

    @State private var hoveredSpace: SpaceID?
    @State private var pendingEverywhere: LayoutKind?
    @State private var appliedEverywhere = false
    /// Bumped after a preference-only change that does not publish through AppModel,
    /// so the Space's "own layout" state redraws immediately.
    @State private var prefsRevision = 0

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 430), spacing: LatticeTheme.Spacing.md)
    ]

    // MARK: - What the model says

    /// The layout of the Space in front of the user. Read through the per-Space API so
    /// the UI never falls back to the global default by accident.
    private var spaceLayout: LayoutKind {
        model.layout(for: model.focusedSpace)
    }

    private var focusedEntry: SpaceManager.DisplaySpaces? {
        if let entry = model.spaces.first(where: { $0.spaceIDs.contains(model.focusedSpace) }) {
            return entry
        }
        if let focused = model.focusedWindow,
           let entry = model.spaces.first(where: { $0.display == focused.display }) {
            return entry
        }
        return model.spaces.first
    }

    /// The Spaces a person would number on this display, in Mission Control order.
    /// Fullscreen Spaces are not user Spaces and would otherwise shift the numbering.
    private var stripSpaces: [SpaceID] {
        guard let entry = focusedEntry else { return [] }
        return entry.spaceTypes.count == entry.spaceIDs.count ? entry.userSpaceIDs : entry.spaceIDs
    }

    private var spaceNumber: Int? {
        stripSpaces.firstIndex(of: model.focusedSpace).map { $0 + 1 }
    }

    private var previewDisplay: DisplayInfo? {
        if let entry = focusedEntry,
           let display = model.displays.first(where: { $0.id == entry.display }) {
            return display
        }
        if let focused = model.focusedWindow,
           let display = model.displays.first(where: { $0.id == focused.display }) {
            return display
        }
        return model.displays.first
    }

    /// Windows that are actually laid out on this Space right now. Falls back to the
    /// Space's own window list while the tiler is still catching up after a switch.
    private var liveWindowCount: Int {
        let ids = model.tiler.tiledWindows(on: model.focusedSpace)
        if !ids.isEmpty { return ids.count }
        return (model.windowsBySpace[model.focusedSpace] ?? [])
            .filter { !$0.isFloating && !$0.isFullscreen }
            .count
    }

    private var allSpaceCount: Int {
        model.spaces.reduce(0) { total, entry in
            total + (entry.spaceTypes.count == entry.spaceIDs.count
                     ? entry.userSpaceIDs.count
                     : entry.spaceIDs.count)
        }
    }

    private var defaultLayout: LayoutKind {
        model.prefs.prefs.layout
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
                header

                if !model.accessibilityGranted {
                    PermissionBanner(onRequest: { model.requestAccessibility() })
                }

                thisSpaceSection
                    .animation(LatticeTheme.animation, value: prefsRevision)

                SectionHeader(
                    "All layouts",
                    subtitle: "Click a card to change the Space you are on. Other Spaces keep theirs."
                ) {
                    if let hint = layoutShortcutHint {
                        Text(hint)
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: LatticeTheme.Spacing.md) {
                    ForEach(LayoutKind.allCases) { kind in
                        LayoutCard(
                            kind: kind,
                            isActive: kind == spaceLayout,
                            binding: binding(for: kind),
                            onSelect: { apply(kind) },
                            onApplyEverywhere: { pendingEverywhere = kind }
                        )
                    }
                }

                footer
            }
            .frame(maxWidth: LatticeTheme.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, LatticeTheme.gutter)
            .padding(.top, LatticeTheme.Spacing.lg)
            .padding(.bottom, LatticeTheme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.latticeCanvas)
        .confirmationDialog(
            everywhereTitle,
            isPresented: Binding(
                get: { pendingEverywhere != nil },
                set: { if !$0 { pendingEverywhere = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingEverywhere
        ) { kind in
            Button("Use \(kind.title) Everywhere") {
                applyEverywhere(kind)
            }
            Button("Cancel", role: .cancel) {
                pendingEverywhere = nil
            }
        } message: { _ in
            Text(everywhereMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Layouts")
                    .latticeTitle()
                Text("Layouts apply to the Space you're on.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: LatticeTheme.Spacing.md)

            if model.accessibilityGranted {
                StatusPill(text: contextLabel, tone: .accent, symbol: spaceLayout.symbol)
                    .help("The Space in front of you and the layout it uses")
            } else {
                StatusPill(text: "Access needed", tone: .warning, symbol: "lock.fill")
            }
        }
    }

    private var contextLabel: String {
        if let spaceNumber {
            return "Space \(spaceNumber) · \(spaceLayout.title)"
        }
        return spaceLayout.title
    }

    // MARK: - This Space

    private var thisSpaceSection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            SectionHeader(
                "This Space",
                subtitle: "Layouts stay with the Space you give them to."
            )

            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: LatticeTheme.Spacing.xl) {
                            previewThumbnail
                            previewCopy
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.md) {
                            previewThumbnail
                            previewCopy
                        }
                    }
                    .padding(LatticeTheme.Spacing.md)

                    LatticeDivider()
                    spaceChipRow
                        .padding(.horizontal, LatticeTheme.Spacing.md)
                        .padding(.vertical, 10)

                    LatticeDivider()
                    actionBar
                        .padding(.horizontal, LatticeTheme.Spacing.md)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var previewThumbnail: some View {
        if let display = previewDisplay {
            let aspect = display.frame.height > 0
                ? display.frame.width / display.frame.height
                : 1.6
            ScreenLayoutPreview(
                kind: spaceLayout,
                count: liveWindowCount,
                aspect: aspect,
                height: 132
            )
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                            .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
                    }
            }
            .overlay {
                if liveWindowCount == 0 {
                    Text("No windows on this Space")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .animation(LatticeTheme.animation, value: spaceLayout)
            .animation(LatticeTheme.animation, value: liveWindowCount)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(spaceLayout.title) preview, \(liveWindowCount) \(liveWindowCount == 1 ? "window" : "windows") on \(display.name)"
            )
        } else {
            VStack(spacing: 6) {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text("No display reported yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 211, height: 132)
            .background {
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            }
        }
    }

    private var previewCopy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview on this display")
                .latticeSectionHeader()

            Text(previewDisplay?.name ?? "This display")
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text("\(liveWindowCount) \(liveWindowCount == 1 ? "window" : "windows")")
                    .latticeMonoDigits()
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(verbatim: "\(resolutionWidth) × \(resolutionHeight) pt")
                    .latticeMonoDigits()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            HStack(spacing: LatticeTheme.Spacing.xs) {
                StatusPill(text: spaceLayout.title, tone: .accent, symbol: spaceLayout.symbol)
                StatusPill(
                    text: model.currentSpaceHasOwnLayout ? "Its own layout" : "Default layout",
                    tone: .neutral,
                    symbol: model.currentSpaceHasOwnLayout ? "pin.fill" : "arrow.turn.down.right"
                )
            }
            .padding(.top, 2)

            Text(ownershipSentence)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var resolutionWidth: Int {
        Int((previewDisplay?.frame.width ?? 0).rounded())
    }

    private var resolutionHeight: Int {
        Int((previewDisplay?.frame.height ?? 0).rounded())
    }

    private var ownershipSentence: String {
        if model.currentSpaceHasOwnLayout {
            return "This Space keeps \(spaceLayout.title) when you switch away."
        }
        return "This Space follows the default, \(defaultLayout.title). Choosing a card pins one just to this Space."
    }

    // MARK: - Space chips

    private var spaceChipRow: some View {
        HStack(alignment: .center, spacing: LatticeTheme.Spacing.xs) {
            if stripSpaces.isEmpty {
                InlineHint(
                    text: "Lattice has not read this display's Spaces yet.",
                    symbol: "rectangle.on.rectangle.slash"
                )
            } else {
                ForEach(Array(stripSpaces.enumerated()), id: \.element) { index, space in
                    SpaceChip(
                        index: index + 1,
                        space: space,
                        kind: model.layout(for: space),
                        isCurrent: space == model.focusedSpace,
                        isHovered: hoveredSpace == space,
                        action: { switchTo(space) }
                    )
                    .onHover { inside in
                        if inside {
                            hoveredSpace = space
                        } else if hoveredSpace == space {
                            hoveredSpace = nil
                        }
                    }
                }

                Spacer(minLength: LatticeTheme.Spacing.sm)

                Text(chipDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(hoveredSpace == nil ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityHidden(true)
            }
        }
    }

    private var chipDetail: String {
        guard let hoveredSpace,
              let index = stripSpaces.firstIndex(of: hoveredSpace) else {
            return "Click a Space to switch to it."
        }
        let kind = model.layout(for: hoveredSpace)
        let source = model.prefs.prefs.hasOwnLayout(hoveredSpace) ? "its own layout" : "default layout"
        return "Space \(index + 1) · \(kind.title) · \(source)"
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(alignment: .center, spacing: LatticeTheme.Spacing.sm) {
            Image(systemName: model.currentSpaceHasOwnLayout ? "pin.fill" : "arrow.turn.down.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)

            Text(actionBarSentence)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: LatticeTheme.Spacing.sm)

            if appliedEverywhere {
                StatusPill(
                    text: "Used on all \(allSpaceCount) \(allSpaceCount == 1 ? "Space" : "Spaces")",
                    tone: .positive,
                    symbol: "checkmark"
                )
                .transition(.opacity)
            }

            Button("Match the default") {
                matchDefault()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!model.currentSpaceHasOwnLayout)
            .help(model.currentSpaceHasOwnLayout
                  ? "Drop this Space's own layout and use \(defaultLayout.title) again"
                  : "This Space already uses the default layout")

            Button("Use everywhere…") {
                pendingEverywhere = spaceLayout
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(allSpaceCount <= 1)
            .help(allSpaceCount <= 1
                  ? "There is only one Space."
                  : "Give every Space the same layout")
        }
        .animation(LatticeTheme.animation, value: appliedEverywhere)
    }

    private var actionBarSentence: String {
        if model.currentSpaceHasOwnLayout {
            return "This Space has its own layout. Changing it here does not touch the other Spaces."
        }
        return "This Space uses the default. Changing it here gives it a layout of its own."
    }

    private var everywhereTitle: String {
        "Use \(pendingEverywhere?.title ?? spaceLayout.title) on every Space?"
    }

    private var everywhereMessage: String {
        let kind = pendingEverywhere?.title ?? spaceLayout.title
        return "This replaces the layout on all \(allSpaceCount) Spaces and makes \(kind) the default for new ones."
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: LatticeTheme.Spacing.md) {
            InlineHint(
                text: "\(cycleHint) cycles layouts on this Space. Each Space remembers its own."
            )
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    private func apply(_ kind: LayoutKind) {
        model.setLayout(kind)
    }

    private func applyEverywhere(_ kind: LayoutKind) {
        model.setLayoutEverywhere(kind)
        pendingEverywhere = nil
        withAnimation(LatticeTheme.animation) { appliedEverywhere = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(LatticeTheme.animation) { appliedEverywhere = false }
        }
    }

    /// Drops this Space's own choice so it follows the default again.
    private func matchDefault() {
        guard model.currentSpaceHasOwnLayout else { return }
        PreferencesStore.shared.update { prefs in
            prefs.spaceLayouts.removeValue(forKey: String(model.focusedSpace.raw))
        }
        model.syncLayoutWithFocusedSpace()
        model.tiler.reconcile()
        prefsRevision &+= 1
    }

    private func switchTo(_ space: SpaceID) {
        guard space != model.focusedSpace, let entry = focusedEntry else { return }
        SpaceManager.shared.activate(space, on: entry.display)
        model.refreshSpaces()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            model.refreshSpaces()
        }
    }

    // MARK: - Shortcut hints

    private var layoutShortcutHint: String? {
        let bindings = model.prefs.prefs.bindings
        guard let first = bindings[.layoutDwindle]?.display,
              let last = bindings[.layoutGrid]?.display else { return nil }
        return "\(first) – \(last)"
    }

    private var cycleHint: String {
        model.prefs.prefs.bindings[.cycleLayout]?.display ?? "⌃⌥Space"
    }

    private func binding(for kind: LayoutKind) -> String? {
        let command: CommandID
        switch kind {
        case .dwindle: command = .layoutDwindle
        case .columns: command = .layoutColumns
        case .rows: command = .layoutRows
        case .grid: command = .layoutGrid
        case .master: command = .layoutMaster
        case .stack: command = .layoutStack
        }
        return model.prefs.prefs.bindings[command]?.display
    }
}

// MARK: - Space chip

/// One real Space on this display. The symbol is the layout it uses, the number is its
/// Mission Control position, and the ring marks the Space you are on.
private struct SpaceChip: View {
    var index: Int
    var space: SpaceID
    var kind: LayoutKind
    var isCurrent: Bool
    var isHovered: Bool
    var action: () -> Void

    private var foreground: Color {
        if isCurrent { return .accentColor }
        return isHovered ? .primary : .secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                Text("\(index)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .bold))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                    .fill(isCurrent
                          ? Color.accentColor.opacity(0.14)
                          : Color.primary.opacity(isHovered ? 0.08 : 0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                    .strokeBorder(isCurrent ? Color.accentColor.opacity(0.55) : Color.latticeHairline,
                                  lineWidth: isCurrent ? 1 : LatticeTheme.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Space \(index) — \(kind.title)")
        .accessibilityLabel(isCurrent
                            ? "Space \(index), \(kind.title), current"
                            : "Space \(index), \(kind.title)")
        .accessibilityHint("Switch to this Space")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

// MARK: - Layout card

private struct LayoutCard: View {
    var kind: LayoutKind
    var isActive: Bool
    var binding: String?
    var onSelect: () -> Void
    var onApplyEverywhere: () -> Void

    @State private var hovering = false
    @State private var previewCount = 3
    @Environment(\.colorScheme) private var scheme

    private var animationKey: String {
        "\(hovering)-\(isActive)"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
                ZStack(alignment: .topTrailing) {
                    LayoutThumbnail(kind: kind, count: previewCount)
                        .frame(height: 112)
                        .frame(maxWidth: .infinity)
                        .animation(LatticeTheme.animation, value: previewCount)
                        .animation(LatticeTheme.animation, value: kind)

                    if isActive {
                        InThisSpaceBadge()
                            .padding(7)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.xs) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    if let binding {
                        KeyCap(text: binding, compact: true)
                    }
                }

                Text(kind.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
            }
            .padding(LatticeTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(radius: LatticeTheme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.85) : Color.clear,
                        lineWidth: isActive ? 1.5 : 0
                    )
            }
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(hovering || isActive ? (scheme == .dark ? 0.34 : 0.08) : 0.04),
                radius: hovering ? 14 : 8,
                x: 0,
                y: hovering ? 5 : 2
            )
            .scaleEffect(hovering ? 1.008 : 1)
            .contentShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(LatticeTheme.animation, value: hovering)
        .animation(LatticeTheme.animation, value: isActive)
        .contextMenu {
            Button("Use \(kind.title) on This Space") { onSelect() }
            Button("Use \(kind.title) on All Spaces…") { onApplyEverywhere() }
        }
        .help("\(kind.title) — \(kind.summary)")
        .accessibilityLabel(isActive
                            ? "\(kind.title) layout, in this Space"
                            : "\(kind.title) layout")
        .accessibilityHint("\(kind.summary) Applies to this Space.")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .task(id: animationKey) {
            guard !LatticeTheme.reducesMotion else {
                previewCount = 3
                return
            }
            if hovering {
                // While the pointer is on the card, show how the layout deals with
                // one, two, three and four windows.
                var next = 1
                while !Task.isCancelled {
                    withAnimation(LatticeTheme.animation) { previewCount = next }
                    next = next % 4 + 1
                    try? await Task.sleep(for: .milliseconds(780))
                }
            } else if isActive {
                // One short showcase pass when a layout becomes the Space's layout.
                for count in [1, 2, 3, 4] where !Task.isCancelled {
                    withAnimation(LatticeTheme.animation) { previewCount = count }
                    try? await Task.sleep(for: .milliseconds(300))
                }
                if !Task.isCancelled {
                    withAnimation(LatticeTheme.animation) { previewCount = 3 }
                }
            } else {
                withAnimation(LatticeTheme.animation) { previewCount = 3 }
            }
        }
    }
}

// MARK: - Badge

/// The "In this Space" marker: a check ring and words, so the state is read, not guessed.
private struct InThisSpaceBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.4)
                    .frame(width: 13, height: 13)
                Image(systemName: "checkmark")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            Text("In this Space")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(.regularMaterial))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.38), lineWidth: LatticeTheme.hairline)
        }
        .accessibilityHidden(true)
    }
}
