import AppKit
import SwiftUI
import LatticeKit

/// What is on screen right now: one card per display with its real Spaces and the real
/// windows macOS put on them, then the last few things Lattice did. Every rectangle here
/// belongs to a window that exists; nothing is simulated.
struct Overview: View {

    @ObservedObject var model: AppModel

    /// Bumped after a preference write that `AppModel` does not publish, so the strip and
    /// the follow toggle redraw with the value that was just stored.
    @State private var prefsRevision = 0

    var body: some View {
        ScrollView {
            content
        }
        .background(Color.latticeCanvas)
    }

    /// Renders without a ScrollView so a screenshot can capture the page directly.
    @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
            header

            if model.accessibilityGranted {
                screen
                recentSection
            } else {
                blockedState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: LatticeTheme.contentMaxWidth, alignment: .leading)
        .padding(.horizontal, LatticeTheme.gutter)
        .padding(.top, LatticeTheme.Spacing.lg)
        .padding(.bottom, LatticeTheme.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(LatticeTheme.animation, value: prefsRevision)
    }

    // MARK: - Model projections

    private var focusedEntry: SpaceManager.DisplaySpaces? {
        model.spaces.first { $0.spaceIDs.contains(model.focusedSpace) } ?? model.spaces.first
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

    private var displayName: String {
        focusedDisplay?.name ?? "This Mac"
    }

    /// The Spaces a person would number, ignoring fullscreen Spaces.
    private func userSpaces(of entry: SpaceManager.DisplaySpaces) -> [SpaceID] {
        entry.spaceTypes.count == entry.spaceIDs.count ? entry.userSpaceIDs : entry.spaceIDs
    }

    private var userSpaces: [SpaceID] {
        focusedEntry.map(userSpaces(of:)) ?? []
    }

    private var spaceNumber: Int? {
        userSpaces.firstIndex(of: model.focusedSpace).map { $0 + 1 }
    }

    private var contextLine: String {
        guard let number = spaceNumber else { return displayName }
        return "\(displayName) · Space \(number) of \(userSpaces.count)"
    }

    private var problem: (text: String, symbol: String)? {
        if !model.accessibilityGranted { return ("Accessibility off", "lock.fill") }
        if !model.isEnabled { return ("Tiling paused", "pause.fill") }
        return nil
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: LatticeTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Overview")
                    .latticeTitle()
                Text(contextLine)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel(contextLine.replacingOccurrences(of: " · ", with: ", "))
            }

            Spacer(minLength: LatticeTheme.Spacing.md)

            if let problem {
                StatusPill(text: problem.text, tone: .warning, symbol: problem.symbol)
            }

            followToggle
        }
    }

    private var followToggle: some View {
        Toggle("Follow a window to its Space", isOn: Binding(
            get: { PreferencesStore.shared.prefs.followWindowAcrossSpaces },
            set: { newValue in
                PreferencesStore.shared.update { $0.followWindowAcrossSpaces = newValue }
                prefsRevision &+= 1
            }
        ))
        .toggleStyle(.latticeSwitch)
        .controlSize(.small)
        .font(.system(size: 12))
        .fixedSize()
    }

    // MARK: - Displays

    @ViewBuilder private var screen: some View {
        if model.displays.isEmpty {
            Card {
                EmptyState(
                    symbol: "display.trianglebadge.exclamationmark",
                    title: "No displays",
                    message: "macOS has not reported a display to Lattice.",
                    actionTitle: nil,
                    action: nil
                )
            }
        } else if model.displays.count == 1, let display = model.displays.first {
            mapCard(for: display)
                .frame(maxWidth: 620)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 440, maximum: 640), spacing: LatticeTheme.Spacing.md)],
                alignment: .leading,
                spacing: LatticeTheme.Spacing.md
            ) {
                ForEach(model.displays) { display in
                    mapCard(for: display)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func mapCard(for display: DisplayInfo) -> some View {
        let entry = entry(for: display)
        let floating = floatingWindows(for: display)
        let targets = sendTargets(for: display)

        return Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if model.displays.count > 1 {
                    displayHeader(display)
                }

                if let entry, !userSpaces(of: entry).isEmpty {
                    spaceStrip(entry: entry)
                        .padding(.horizontal, LatticeTheme.Spacing.sm)
                        .padding(.top, model.displays.count > 1 ? LatticeTheme.Spacing.xs : LatticeTheme.Spacing.sm)
                        .padding(.bottom, LatticeTheme.Spacing.xs)
                }

                DisplaySurface(
                    display: display,
                    windows: tiledWindows(for: display),
                    focused: model.focusedWindow?.id,
                    spaceTargets: targets,
                    onFloat: { floatWindow($0) },
                    onDontTile: { dontTileApp($0) },
                    onSend: { window, space in send(window, to: space, on: display.id) }
                )
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, LatticeTheme.Spacing.sm)
                .padding(.top, entry == nil ? LatticeTheme.Spacing.sm : 0)
                .padding(.bottom, LatticeTheme.Spacing.sm)
                .accessibilityLabel(mapSummary(for: display, entry: entry))

                if !floating.isEmpty {
                    floatingRow(floating)
                        .padding(.horizontal, LatticeTheme.Spacing.md)
                        .padding(.bottom, LatticeTheme.Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var menuBridge: LayoutMenuBridge { LayoutMenuBridge.shared }

    /// Pops a real NSMenu at the pointer. A SwiftUI `Menu` is AppKit-backed and cannot be
    /// captured by the offscreen renderer; this control has to look right in both.
    private func popUpLayoutMenu(for space: SpaceID, from number: Int) {
        let menu = NSMenu()
        for kind in LayoutKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(LayoutMenuBridge.pick(_:)), keyEquivalent: "")
            item.target = menuBridge
            item.state = kind == model.layout(for: space) ? .on : .off
            item.representedObject = LayoutMenuPayload(space: space, kind: kind)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Use the default layout", action: #selector(LayoutMenuBridge.clearOverride(_:)), keyEquivalent: "")
        clear.target = menuBridge
        clear.isEnabled = PreferencesStore.shared.prefs.hasOwnLayout(space)
        clear.representedObject = LayoutMenuPayload(space: space, kind: model.layout(for: space))
        menu.addItem(clear)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func displayHeader(_ display: DisplayInfo) -> some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            Image(systemName: "display")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(display.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(verbatim: "\(Int(display.frame.width.rounded())) × \(Int(display.frame.height.rounded())) pt")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .padding(.top, LatticeTheme.Spacing.sm)
        .padding(.bottom, 2)
    }

    private func mapSummary(for display: DisplayInfo, entry: SpaceManager.DisplaySpaces?) -> String {
        var parts = ["\(display.name) layout map"]
        if let entry,
           let index = entry.current.flatMap({ userSpaces(of: entry).firstIndex(of: $0) }) {
            parts.append("Space \(index + 1) of \(userSpaces(of: entry).count)")
        }
        parts.append("\(tiledWindows(for: display).count) tiled")
        if !floatingWindows(for: display).isEmpty {
            parts.append("\(floatingWindows(for: display).count) floating")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Space strip

    /// One chip per Space on the display: its number, its layout glyph (which is also the
    /// only per-Space layout editor on this page) and the key that switches to it.
    private func spaceStrip(entry: SpaceManager.DisplaySpaces) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(userSpaces(of: entry).enumerated()), id: \.element) { index, space in
                spaceChip(
                    space: space,
                    number: index + 1,
                    current: entry.current,
                    display: entry.display
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func spaceChip(space: SpaceID,
                           number: Int,
                           current: SpaceID?,
                           display: DisplayID) -> some View {
        let layout = PreferencesStore.shared.prefs.layout(for: space)
        let isCurrent = space == current
        let key = spaceKey(for: number)

        return HStack(spacing: 0) {
            Button {
                SpaceManager.shared.activate(space, on: display)
            } label: {
                HStack(spacing: 4) {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    if let key {
                        Text(key)
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : Color.secondary)
                    }
                }
                .foregroundStyle(isCurrent ? Color.white : Color.primary)
                .padding(.leading, 9)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCurrent ? "This is Space \(number)" : "Switch to Space \(number)")
            .accessibilityLabel("Space \(number), \(layout.title)\(isCurrent ? ", current" : "")")
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])

            Button {
                popUpLayoutMenu(for: space, from: number)
            } label: {
                Image(systemName: layout.symbol)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isCurrent ? Color.white.opacity(0.9) : Color.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change this Space's layout")
            .accessibilityLabel("Layout for Space \(number): \(layout.title)")
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Layout for Space \(number)")
            .accessibilityLabel("Layout for Space \(number): \(layout.title)")
        }
        .background(
            Capsule(style: .continuous)
                .fill(isCurrent ? Color.accentColor : Color.primary.opacity(0.055))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(isCurrent ? Color.clear : Color.latticeHairline,
                              lineWidth: LatticeTheme.hairline)
        )
    }

    /// The key that jumps to this Space number, if the person has mapped one.
    private func spaceKey(for number: Int) -> String? {
        let keys = PreferencesStore.shared.prefs.spaceKeys
            .filter { $0.value == number }
            .keys
            .sorted { KeyCombo.pretty($0) < KeyCombo.pretty($1) }
        guard let key = keys.first else { return nil }
        return "⌥" + KeyCombo.pretty(key)
    }

    /// Windows the tiler deliberately leaves alone. Shown as chips instead of map tiles so the
    /// map keeps meaning "the layout", and overlapping rectangles never look like a bug.
    private func floatingRow(_ floating: [ManagedWindow]) -> some View {
        HStack(spacing: 6) {
            Text("FLOATING")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)

                HStack(spacing: 6) {
                    ForEach(floating) { window in
                        Button {
                            model.engine.focus(window.id)
                            model.rebuildWindowCache()
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

    // MARK: - Window data

    private func entry(for display: DisplayInfo) -> SpaceManager.DisplaySpaces? {
        model.spaces.first { $0.display == display.id }
    }

    private func sendTargets(for display: DisplayInfo) -> [SendTarget] {
        guard let entry = entry(for: display) else { return [] }
        return userSpaces(of: entry).enumerated().map {
            SendTarget(space: $0.element, number: $0.offset + 1)
        }
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

    /// Only the windows the tiler is actually arranging; floating windows get their own row.
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

    // MARK: - Actions

    private func applyLayout(_ kind: LayoutKind, to space: SpaceID) {
        model.setLayout(kind, for: space)
        prefsRevision &+= 1
    }

    /// `Tiler` floats whichever window is focused, so focus the tile first — the same path the
    /// palette and the keyboard use.
    private func floatWindow(_ window: ManagedWindow) {
        model.engine.focus(window.id)
        model.tiler.toggleFloat()
        model.rebuildWindowCache()
    }

    private func dontTileApp(_ window: ManagedWindow) {
        guard let bundleID = window.bundleID, !bundleID.isEmpty else { return }
        PreferencesStore.shared.update { $0.unmanagedBundleIDs.insert(bundleID) }
        prefsRevision &+= 1
        model.tiler.reconcile()
    }

    private func send(_ window: ManagedWindow, to space: SpaceID, on display: DisplayID) {
        model.tiler.sendWindow(window.id, from: window.space, to: space, on: display)
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            SectionHeader("Recent") {
                if !model.recentActions.isEmpty {
                    Button {
                        model.dispatch(.undo)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                }
            }

            if model.recentActions.isEmpty {
                Card {
                    InlineHint(text: "Actions you take with the keyboard show up here.")
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        let actions = Array(model.recentActions.prefix(3))
                        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                            recentRow(action)
                            if index < actions.count - 1 {
                                LatticeDivider(insetLeading: LatticeTheme.Spacing.md + 24)
                            }
                        }
                    }
                }
            }
        }
    }

    private func recentRow(_ action: String) -> some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                Image(systemName: symbol(for: action))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 20, height: 20)

            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(action)
    }

    private func symbol(for action: String) -> String {
        CommandID.allCases.first { $0.title == action }?.symbol ?? "bolt"
    }

    // MARK: - Blocked

    /// The one designed state for a missing Accessibility grant: a sentence and the button
    /// that fixes it. No map is drawn, because there is nothing Lattice can move yet.
    private var blockedState: some View {
        PermissionBanner()
    }
}

// MARK: - Send target

private struct SendTarget: Identifiable {
    let space: SpaceID
    let number: Int

    var id: SpaceID { space }
}

// MARK: - Display surface

/// The display drawn to scale: bezel, visible frame, and every window at its real
/// position. Frames are clamped into the screen, never re-invented from a layout.
private struct DisplaySurface: View {
    var display: DisplayInfo
    var windows: [ManagedWindow]
    var focused: WindowID?
    var spaceTargets: [SendTarget]
    var onFloat: (ManagedWindow) -> Void
    var onDontTile: (ManagedWindow) -> Void
    var onSend: (ManagedWindow, SpaceID) -> Void

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
                            spaceTargets: spaceTargets.filter { $0.space != window.space },
                            onFloat: { onFloat(window) },
                            onDontTile: { onDontTile(window) },
                            onSend: { onSend(window, $0) }
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

    /// "Finder, 816 by 542 points".
    private func windowLabel(_ window: ManagedWindow) -> String {
        let width = Int(window.frame.width.rounded())
        let height = Int(window.frame.height.rounded())
        return "\(window.appName), \(width) by \(height) points"
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

/// A window at its real position. Tapping does nothing: the palette is where focus is
/// chosen. The context menu is where a single window or app is acted on.
private struct MapWindowTile: View {
    var window: ManagedWindow
    var isFocused: Bool
    var tint: Color?
    var accessibilityText: String
    var spaceTargets: [SendTarget]
    var onFloat: () -> Void
    var onDontTile: () -> Void
    var onSend: (SpaceID) -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
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
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(LatticeTheme.animation, value: hovering)
            .animation(LatticeTheme.animation, value: isFocused)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .contextMenu { menuItems }
    }

    @ViewBuilder private var menuItems: some View {
        Button("Float window", action: onFloat)

        if let bundleID = window.bundleID, !bundleID.isEmpty {
            Button("Don't tile this app…", action: onDontTile)
        }

        if !spaceTargets.isEmpty {
            Divider()
            Menu("Send to Space") {
                ForEach(spaceTargets) { target in
                    Button("Space \(target.number)") { onSend(target.space) }
                }
            }
        }
    }

    private var baseFill: Color {
        scheme == .dark ? Color(white: 0.17) : Color(white: 0.90)
    }

    private var helpText: String {
        window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)"
    }
}

// MARK: - Layout menu bridge

struct LayoutMenuPayload {
    var space: SpaceID
    var kind: LayoutKind
}

@MainActor
final class LayoutMenuBridge: NSObject {
    static let shared = LayoutMenuBridge()

    @objc func pick(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? LayoutMenuPayload else { return }
        AppModel.shared.setLayout(payload.kind, for: payload.space)
    }

    @objc func clearOverride(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? LayoutMenuPayload else { return }
        PreferencesStore.shared.update { $0.spaceLayouts.removeValue(forKey: String(payload.space.raw)) }
        AppModel.shared.syncLayoutWithFocusedSpace()
        AppModel.shared.tiler.reconcile()
    }
}
