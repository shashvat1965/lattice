import AppKit
import SwiftUI
import LatticeKit

/// The hero screen: a live map of every display's current Space, the real windows on it,
/// and the numbers that matter. Nothing here is simulated — every rectangle is a window
/// that exists right now, drawn where macOS actually put it.
struct Overview: View {

    @ObservedObject var model: AppModel

    /// Bumped after clearing a Space's layout override, which changes nothing in
    /// `AppModel`'s published state when the override equalled the default.
    @State private var prefsRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
                header
                    .animation(LatticeTheme.animation, value: prefsRevision)

                if model.accessibilityGranted {
                    if model.displays.isEmpty {
                        noDisplaysSection
                    } else if visibleWindowCount == 0 {
                        emptyScreenSection
                        statsRow
                        recentSection
                    } else {
                        displaySection
                        statsRow
                        recentSection
                    }
                } else {
                    permissionSection
                }
            }
            .frame(maxWidth: LatticeTheme.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, LatticeTheme.gutter)
            .padding(.top, LatticeTheme.Spacing.lg)
            .padding(.bottom, LatticeTheme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.latticeCanvas)
    }

    // MARK: - Model projections

    /// The Space in front of the user, read through the per-Space API so a stray global
    /// value can never show up here.
    private var spaceLayout: LayoutKind {
        model.layout(for: model.focusedSpace)
    }

    private var focusedEntry: SpaceManager.DisplaySpaces? {
        model.spaces.first { $0.spaceIDs.contains(model.focusedSpace) } ?? model.spaces.first
    }

    /// The Spaces a person would number, ignoring fullscreen Spaces.
    private var userSpaces: [SpaceID] {
        guard let entry = focusedEntry else { return [] }
        return entry.spaceTypes.count == entry.spaceIDs.count ? entry.userSpaceIDs : entry.spaceIDs
    }

    private var focusedDisplay: DisplayInfo? {
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

    private var spaceNumber: Int? {
        userSpaces.firstIndex(of: model.focusedSpace).map { $0 + 1 }
    }

    private var spaceLabel: String {
        guard let number = spaceNumber else {
            return model.accessibilityGranted ? "This Space" : "Accessibility off"
        }
        return "Space \(number) of \(userSpaces.count)"
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Overview")
                    .latticeTitle()
                contextLine
            }

            Spacer(minLength: LatticeTheme.Spacing.md)

            HStack(spacing: LatticeTheme.Spacing.xs) {
                if !model.accessibilityGranted {
                    StatusPill(text: "Access needed", tone: .warning, symbol: "lock.fill")
                } else if !model.isEnabled {
                    StatusPill(text: "Tiling paused", tone: .warning, symbol: "pause.fill")
                }

                if model.accessibilityGranted {
                    layoutMenu
                }
            }
            .fixedSize()
        }
    }

    /// display name · Space N of M · layout · window count, in one wrapping line.
    private var contextLine: some View {
        let separator = Text("  ·  ").foregroundColor(Color.secondary.opacity(0.55))
        return (
            Text(displayName)
            + separator
            + Text(spaceLabel)
            + separator
            + Text(spaceLayout.title)
            + separator
            + Text("\(windowCount) \(windowCount == 1 ? "window" : "windows")")
        )
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("\(displayName), \(spaceLabel), \(spaceLayout.title), \(windowCount) \(windowCount == 1 ? "window" : "windows")")
    }

    private var displayName: String {
        focusedDisplay?.name ?? "This Mac"
    }

    private var windowCount: Int {
        guard let display = focusedDisplay else { return 0 }
        return windows(for: display).count
    }

    private var layoutMenu: some View {
        Menu {
            Picker("Layout", selection: Binding(
                get: { spaceLayout },
                set: { model.setLayout($0) }
            )) {
                ForEach(LayoutKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if model.currentSpaceHasOwnLayout {
                Divider()
                Button("Match the Default Layout") { matchDefault() }
            }
        } label: {
            HStack(spacing: LatticeTheme.Spacing.xs) {
                Image(systemName: spaceLayout.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(spaceLayout.title)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Change the layout for this Space")
        .accessibilityLabel("Layout: \(spaceLayout.title)")
    }

    // MARK: - Displays

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            SectionHeader(
                "On screen",
                subtitle: "Each display's current Space, at its real window positions."
            ) {
                if model.displays.count > 1 {
                    Text("\(model.displays.count) displays")
                        .latticeCaption()
                        .latticeMonoDigits()
                }
            }

            if model.displays.count == 1, let display = model.displays.first {
                mapCard(for: display)
                    .frame(maxWidth: 640)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320, maximum: 620), spacing: LatticeTheme.Spacing.md)],
                    alignment: .leading,
                    spacing: LatticeTheme.Spacing.md
                ) {
                    ForEach(model.displays) { display in
                        mapCard(for: display)
                    }
                }
            }
        }
    }

    private func mapCard(for display: DisplayInfo) -> some View {
        DisplayMapCard(
            display: display,
            entry: entry(for: display),
            windows: tiledWindows(for: display),
            floating: floatingWindows(for: display),
            focused: model.focusedWindow?.id,
            onFocus: { id in
                model.engine.focus(id)
                model.rebuildWindowCache()
            },
            onShowSpaces: showSpaces
        )
    }

    private var noDisplaysSection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            SectionHeader("On screen", subtitle: "Each display's current Space, at its real window positions.")
            Card {
                EmptyState(
                    symbol: "display.trianglebadge.exclamationmark",
                    title: "No displays detected",
                    message: "Lattice is waiting for macOS to report a display. Connect one, or wake a sleeping display, then check again.",
                    actionTitle: "Check again",
                    action: { model.refreshSpaces() }
                )
                .frame(minHeight: 190)
            }
        }
    }

    private var emptyScreenSection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            SectionHeader(
                "On screen",
                subtitle: "Each display's current Space, at its real window positions."
            )

            Card(padding: 0) {
                VStack(spacing: 0) {
                    EmptyState(
                        symbol: "macwindow.on.rectangle",
                        title: "Nothing to tile on this Space",
                        message: "Open a window here, or switch Spaces. Lattice picks up new windows automatically — there is nothing to set up.",
                        actionTitle: "Refresh",
                        action: { model.refreshSpaces() }
                    )
                    .frame(minHeight: 200)

                    LatticeDivider()

                    HStack(spacing: LatticeTheme.Spacing.sm) {
                        if !userSpaces.isEmpty {
                            SpaceStrip(spaces: userSpaces, current: model.focusedSpace)
                        }
                        Text(emptyContext)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: LatticeTheme.Spacing.sm)
                        Button("Spaces…") { showSpaces() }
                            .buttonStyle(.link)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, LatticeTheme.Spacing.md)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var emptyContext: String {
        let number = spaceNumber.map { "Space \($0) of \(userSpaces.count)" } ?? "This Space"
        return "\(number) · \(spaceLayout.title) · 0 windows"
    }

    private func entry(for display: DisplayInfo) -> SpaceManager.DisplaySpaces? {
        model.spaces.first { $0.display == display.id }
    }

    /// Every window on that display's current Space: tiled order first, then floating and
    /// fullscreen windows, which are real too.
    private func windows(for display: DisplayInfo) -> [ManagedWindow] {
        guard let entry = entry(for: display), let space = entry.current else {
            return (model.windowsBySpace[model.focusedSpace] ?? [])
                .filter { $0.display == display.id && !$0.isMinimized }
                .sorted { $0.id.raw < $1.id.raw }
        }
        let all = (model.windowsBySpace[space] ?? []).filter { !$0.isMinimized }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ordered = model.tiler.tiledWindows(on: space).compactMap { byID[$0] }
        let seen = Set(ordered.map(\.id))
        let rest = all
            .filter { !seen.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.isFloating != rhs.isFloating { return !lhs.isFloating }
                return lhs.id.raw < rhs.id.raw
            }
        ordered.append(contentsOf: rest)
        return ordered
    }

    /// Only the windows the tiler is actually arranging. Floating windows are real, but drawing
    /// them on the map makes it look like the layout is broken — they overlap by definition.
    private func tiledWindows(for display: DisplayInfo) -> [ManagedWindow] {
        windows(for: display).filter { window in
            !window.isFullscreen && !model.tiler.isFloating(window.id) && !window.isFloating
        }
    }

    private func floatingWindows(for display: DisplayInfo) -> [ManagedWindow] {
        windows(for: display).filter { window in
            window.isFullscreen || model.tiler.isFloating(window.id) || window.isFloating
        }
    }

    /// Every window currently drawn on any display's active Space.
    private var visibleWindowCount: Int {
        model.displays.reduce(0) { total, display in
            total + windows(for: display).count
        }
    }

    private func showSpaces() {
        NotificationCenter.default.post(name: .latticeShowSpaces, object: nil)
    }

    private func matchDefault() {
        guard model.currentSpaceHasOwnLayout else { return }
        PreferencesStore.shared.update { prefs in
            prefs.spaceLayouts.removeValue(forKey: String(model.focusedSpace.raw))
        }
        model.syncLayoutWithFocusedSpace()
        model.tiler.reconcile()
        prefsRevision &+= 1
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: LatticeTheme.Spacing.md) {
            StatCard(
                symbol: "macwindow",
                value: "\(tiledWindowCount)",
                unit: tiledWindowCount == 1 ? "window" : "windows",
                caption: model.isEnabled
                    ? "Tiled on \(spaceNumber.map { "Space \($0)" } ?? "this Space")"
                    : "Tiling is paused"
            )
            StatCard(
                symbol: "square.stack.3d.up",
                value: "\(totalSpaces)",
                unit: totalSpaces == 1 ? "Space" : "Spaces",
                caption: model.displays.count == 1
                    ? "On this display"
                    : "Across \(model.displays.count) displays"
            )
            StatCard(
                symbol: "display",
                value: "\(model.displays.count)",
                unit: model.displays.count == 1 ? "display" : "displays",
                caption: primaryResolution
            )
        }
    }

    private var tiledWindowCount: Int {
        let ids = model.tiler.tiledWindows(on: model.focusedSpace)
        if !ids.isEmpty { return ids.count }
        return (model.windowsBySpace[model.focusedSpace] ?? [])
            .filter { !$0.isFloating && !$0.isFullscreen }
            .count
    }

    private var totalSpaces: Int {
        model.spaces.reduce(0) { total, entry in
            total + (entry.spaceTypes.count == entry.spaceIDs.count
                     ? entry.userSpaceIDs.count
                     : entry.spaceIDs.count)
        }
    }

    private var primaryResolution: String {
        guard let display = focusedDisplay else { return "None connected" }
        let width = Int(display.frame.width.rounded())
        let height = Int(display.frame.height.rounded())
        return "\(display.name) · \(width) × \(height) pt"
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            SectionHeader("Recent", subtitle: "What Lattice did last.") {
                if !model.recentActions.isEmpty {
                    Button {
                        model.dispatch(.undo)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            Card(padding: 0) {
                if model.recentActions.isEmpty {
                    InlineHint(text: "Actions you take with the keyboard show up here.")
                        .padding(LatticeTheme.Spacing.md)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.recentActions.enumerated()), id: \.offset) { index, action in
                            recentRow(action, isLatest: index == 0)
                            if index < model.recentActions.count - 1 {
                                LatticeDivider(insetLeading: LatticeTheme.Spacing.md + 24)
                            }
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ action: String, isLatest: Bool) -> some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(isLatest
                          ? Color.accentColor.opacity(0.14)
                          : Color.primary.opacity(0.05))
                Image(systemName: symbol(for: action))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isLatest ? Color.accentColor : Color.secondary)
            }
            .frame(width: 20, height: 20)

            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(isLatest ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            if isLatest {
                Text("Latest")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .frame(height: 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isLatest ? "\(action), latest action" : action)
    }

    private func symbol(for action: String) -> String {
        CommandID.allCases.first { $0.title == action }?.symbol ?? "bolt"
    }

    // MARK: - Permission

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.md) {
            PermissionBanner(onRequest: { model.requestAccessibility() })

            Card {
                VStack(alignment: .leading, spacing: LatticeTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("One switch, then Lattice takes over")
                            .latticeHeading()
                        Text("macOS gates every window action behind Accessibility. Lattice asks for nothing else — no helper, no login item, no network.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 190), spacing: LatticeTheme.Spacing.md)],
                        alignment: .leading,
                        spacing: LatticeTheme.Spacing.md
                    ) {
                        permissionStep(
                            number: 1,
                            title: "Enable Lattice",
                            detail: "System Settings ▸ Privacy & Security ▸ Accessibility."
                        )
                        permissionStep(
                            number: 2,
                            title: "Arrange windows",
                            detail: "Focus a window and press \(focusHint) to move around."
                        )
                        permissionStep(
                            number: 3,
                            title: "It stays put",
                            detail: "Each Space keeps its own layout and window order."
                        )
                    }

                    HStack(spacing: LatticeTheme.Spacing.xs) {
                        Button("Check Again") {
                            model.bootstrap()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Spacer(minLength: 0)

                        InlineHint(text: "Typically detected within a second.",
                                   symbol: "clock")
                    }
                }
            }
        }
    }

    private var focusHint: String {
        let bindings = model.prefs.prefs.bindings
        let left = bindings[.focusLeft]?.display
        let right = bindings[.focusRight]?.display
        if let left, let right { return "\(left) or \(right)" }
        return "⌃⌥H or ⌃⌥L"
    }

    private func permissionStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: LatticeTheme.Spacing.sm) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.13)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Display map card

private struct DisplayMapCard: View {
    var display: DisplayInfo
    var entry: SpaceManager.DisplaySpaces?
    var windows: [ManagedWindow]
    var floating: [ManagedWindow]
    var focused: WindowID?
    var onFocus: (WindowID) -> Void
    var onShowSpaces: () -> Void

    private var currentSpace: SpaceID? {
        entry?.current
    }

    private var displayLayout: LayoutKind? {
        guard let current = currentSpace else { return nil }
        return PreferencesStore.shared.prefs.layout(for: current)
    }

    private var hasOwnLayout: Bool {
        guard let current = currentSpace else { return false }
        return PreferencesStore.shared.prefs.hasOwnLayout(current)
    }

    private var userSpaces: [SpaceID] {
        guard let entry else { return [] }
        return entry.spaceTypes.count == entry.spaceIDs.count ? entry.userSpaceIDs : entry.spaceIDs
    }

    private var spaceNumber: Int? {
        guard let current = currentSpace else { return nil }
        return userSpaces.firstIndex(of: current).map { $0 + 1 }
    }

    private var spaceLabel: String? {
        guard let number = spaceNumber else { return nil }
        return "Space \(number) of \(userSpaces.count)"
    }

    private var displayResolution: String {
        let width = Int(display.frame.width.rounded())
        let height = Int(display.frame.height.rounded())
        return "\(width) × \(height) pt"
    }

    private var windowCountText: String {
        let tiled = "\(windows.count) tiled"
        guard !floating.isEmpty else { return tiled }
        return tiled + " · \(floating.count) floating"
    }

    private var mapSummary: String {
        [
            "\(display.name) layout map",
            spaceLabel,
            displayLayout?.title,
            windowCountText
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow

                DisplaySurface(
                    display: display,
                    windows: windows,
                    focused: focused,
                    onFocus: onFocus
                )
                .aspectRatio(max(0.6, display.frame.width / max(1, display.frame.height)),
                             contentMode: .fit)
                .padding(.horizontal, LatticeTheme.Spacing.sm)
                .padding(.bottom, LatticeTheme.Spacing.sm)
                .accessibilityLabel(mapSummary)

                if !floating.isEmpty {
                    floatingRow
                        .padding(.horizontal, LatticeTheme.Spacing.md)
                        .padding(.bottom, LatticeTheme.Spacing.sm)
                }

                LatticeDivider()

                spaceLine
                    .padding(.horizontal, LatticeTheme.Spacing.md)
                    .padding(.vertical, LatticeTheme.Spacing.sm)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Windows the tiler deliberately leaves alone. Shown as chips instead of map tiles so the
    /// map keeps meaning "the layout", and overlapping rectangles never look like a bug.
    private var floatingRow: some View {
        HStack(spacing: 6) {
            Text("FLOATING")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(floating) { window in
                        Button {
                            onFocus(window.id)
                        } label: {
                            HStack(spacing: 4) {
                                AppIcon(bundleID: window.bundleID, appName: window.appName, size: 12)
                                Text(window.appName)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(window.title.isEmpty ? window.appName : window.title)
                        .accessibilityLabel("\(window.appName), floating")
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            Image(systemName: "display")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(display.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(verbatim: displayResolution)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: LatticeTheme.Spacing.xs)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .padding(.top, LatticeTheme.Spacing.sm)
        .padding(.bottom, LatticeTheme.Spacing.xs)
    }

    /// The Space line the map needs: which layout, whether it is this Space's own, and
    /// a way to reach the Spaces pane.
    private var spaceLine: some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            if !userSpaces.isEmpty {
                SpaceStrip(spaces: userSpaces, current: currentSpace, rectSize: CGSize(width: 20, height: 13))
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(spaceLabel ?? "This Space")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let displayLayout {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(displayLayout.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                Text("\(hasOwnLayout ? "Its own layout" : "Default layout") · \(windowCountText)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: LatticeTheme.Spacing.xs)

            Button("Spaces…", action: onShowSpaces)
                .buttonStyle(.link)
                .controlSize(.small)
                .help("Open the Spaces window")
        }
    }
}

// MARK: - Display surface

/// The display drawn to scale: bezel, visible frame, and every window at its real
/// position. Frames are clamped into the screen, never re-invented from a layout.
private struct DisplaySurface: View {
    var display: DisplayInfo
    var windows: [ManagedWindow]
    var focused: WindowID?
    var onFocus: (WindowID) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let outerRadius = max(6, min(12, min(size.width, size.height) * 0.05))
            let frame = display.frame
            let visible = display.visibleFrame
            let scaleX = size.width / max(1, frame.width)
            let scaleY = size.height / max(1, frame.height)
            let visibleRect = CGRect(
                x: (visible.minX - frame.minX) * scaleX,
                y: (visible.minY - frame.minY) * scaleY,
                width: visible.width * scaleX,
                height: visible.height * scaleY
            )
            let innerRadius = max(4, outerRadius * 0.55)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .fill(bezelFill)

                RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                    .fill(screenFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(scheme == .dark ? 0.10 : 0.07),
                                             Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: innerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07),
                                          lineWidth: LatticeTheme.hairline)
                    }
                    .frame(width: max(0, visibleRect.width), height: max(0, visibleRect.height))
                    .offset(x: visibleRect.minX, y: visibleRect.minY)

                if windows.isEmpty {
                    Text("No windows on this Space")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .position(x: visibleRect.midX, y: visibleRect.midY)
                        .allowsHitTesting(false)
                } else {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        let frameInMap = mapRect(for: window, in: visibleRect,
                                                 scaleX: scaleX, scaleY: scaleY)
                        MapWindowTile(
                            window: window,
                            isFocused: window.id == focused,
                            tint: AppIconStore.shared.tint(bundleID: window.bundleID,
                                                           appName: window.appName),
                            accessibilityText: windowLabel(window),
                            action: { onFocus(window.id) }
                        )
                        .frame(width: max(4, frameInMap.width),
                               height: max(4, frameInMap.height))
                        .offset(x: frameInMap.minX, y: frameInMap.minY)
                        .zIndex(window.id == focused ? 1000 : Double(index))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.10 : 0.08),
                                  lineWidth: LatticeTheme.hairline)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// The real frame, converted into the map and kept inside the screen so a window is
    /// never silently dropped.
    private func mapRect(for window: ManagedWindow,
                         in visibleRect: CGRect,
                         scaleX: CGFloat,
                         scaleY: CGFloat) -> CGRect {
        let frame = window.frame
        var rect = CGRect(
            x: visibleRect.minX + (frame.minX - display.visibleFrame.minX) * scaleX,
            y: visibleRect.minY + (frame.minY - display.visibleFrame.minY) * scaleY,
            width: frame.width * scaleX,
            height: frame.height * scaleY
        )
        rect.size.width = max(4, min(rect.width, visibleRect.width))
        rect.size.height = max(4, min(rect.height, visibleRect.height))
        rect.origin.x = min(max(rect.minX, visibleRect.minX),
                            max(visibleRect.minX, visibleRect.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, visibleRect.minY),
                            max(visibleRect.minY, visibleRect.maxY - rect.height))
        return rect
    }

    /// "Finder, Documents, left half, 816 by 542 points".
    private func windowLabel(_ window: ManagedWindow) -> String {
        var parts = [window.appName]
        if !window.title.isEmpty, window.title != window.appName {
            parts.append(window.title)
        }
        parts.append(positionDescription(of: window.frame))
        let width = Int(window.frame.width.rounded())
        let height = Int(window.frame.height.rounded())
        parts.append("\(width) by \(height) points")
        if window.isFloating {
            parts.append("floating")
        }
        return parts.joined(separator: ", ")
    }

    private func positionDescription(of frame: CGRect) -> String {
        let visible = display.visibleFrame
        guard visible.width > 1, visible.height > 1 else { return "on this display" }

        let widthShare = frame.width / visible.width
        let heightShare = frame.height / visible.height
        let midX = (frame.midX - visible.minX) / visible.width
        let midY = (frame.midY - visible.minY) / visible.height

        if widthShare > 0.9, heightShare > 0.9 { return "full screen" }
        if heightShare > 0.85, abs(widthShare - 0.5) < 0.08 {
            return midX < 0.5 ? "left half" : "right half"
        }
        if widthShare > 0.85, abs(heightShare - 0.5) < 0.08 {
            return midY < 0.5 ? "top half" : "bottom half"
        }

        let vertical: String? = midY < 0.38 ? "top" : (midY > 0.62 ? "bottom" : nil)
        let horizontal: String? = midX < 0.38 ? "left" : (midX > 0.62 ? "right" : nil)
        let words = [vertical, horizontal].compactMap { $0 }
        return words.isEmpty ? "centred" : words.joined(separator: " ")
    }

    private var bezelFill: LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(white: 0.16), Color(white: 0.10)]
                : [Color(white: 0.93), Color(white: 0.88)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var screenFill: Color {
        scheme == .dark ? Color(white: 0.075) : Color(white: 0.985)
    }
}

// MARK: - Window tile

private struct MapWindowTile: View {
    var window: ManagedWindow
    var isFocused: Bool
    var tint: Color?
    var accessibilityText: String
    var action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let radius = max(3, min(6, min(width, height) * 0.12))
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(baseFill)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill((tint ?? .accentColor).opacity(scheme == .dark ? 0.20 : 0.11))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(scheme == .dark ? 0.06 : 0.30), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )

                    if width > 30, height > 20 {
                        let iconSize = max(10, min(min(width * 0.22, height * 0.22), 30))
                        HStack(spacing: 5) {
                            AppIcon(bundleID: window.bundleID, appName: window.appName, size: iconSize)
                            if width > 74 {
                                Text(window.appName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(0.88))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .padding(.horizontal, max(3, radius * 0.7))
                        .padding(.vertical, max(2.5, radius * 0.6))
                    }

                    if width > 112, height > 78, !window.title.isEmpty {
                        VStack {
                            Spacer(minLength: 0)
                            Text(window.title)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 6)
                                .padding(.bottom, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            isFocused ? Color.accentColor : Color.primary.opacity(0.10),
                            lineWidth: isFocused ? 2 : LatticeTheme.hairline
                        )
                }
                .shadow(
                    color: Color.black.opacity(scheme == .dark ? 0.35 : 0.10),
                    radius: hovering ? 8 : 2,
                    x: 0,
                    y: hovering ? 3 : 1
                )
                .scaleEffect(hovering ? 1.025 : 1)
                .animation(LatticeTheme.animation, value: hovering)
                .animation(LatticeTheme.animation, value: isFocused)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Focus this window")
    }

    private var baseFill: Color {
        scheme == .dark ? Color(white: 0.17) : Color(white: 0.90)
    }

    private var helpText: String {
        window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)"
    }
}

// MARK: - Stat card

private struct StatCard: View {
    var symbol: String
    var value: String
    var unit: String
    var caption: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Card(padding: LatticeTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xs) {
                HStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                                .fill(Color.accentColor.opacity(scheme == .dark ? 0.18 : 0.11))
                        )
                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .tracking(-0.4)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .animation(LatticeTheme.animation, value: value)

                Text(caption)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(unit), \(caption)")
    }
}
