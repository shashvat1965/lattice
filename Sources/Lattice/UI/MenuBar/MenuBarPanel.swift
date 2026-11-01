import AppKit
import SwiftUI
import LatticeKit

/// The SwiftUI content of the status-item popover. It observes `AppModel`
/// directly, so it stays correct while it is open.
struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    var dismiss: () -> Void
    @Environment(\.latticeSnapshotMode) private var snapshotMode

    static let width: CGFloat = 340
    static let height: CGFloat = 444

    var body: some View {
        VStack(spacing: 0) {
            header
            spaceRow
            if !model.accessibilityGranted {
                permissionBanner
            }
            SurfaceHairline()
            layoutPicker
            SurfaceHairline()
            windowSection
            SurfaceHairline()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lattice menu")
    }

    // MARK: - Header

    private var currentEntry: SpaceManager.DisplaySpaces? {
        model.spaces.first { $0.current == model.focusedSpace }
            ?? model.spaces.first { $0.display == currentDisplayID }
    }

    private var currentDisplayID: DisplayID? {
        if let entry = model.spaces.first(where: { $0.current == model.focusedSpace }) {
            return entry.display
        }
        return model.displays.first?.id
    }

    private var displayName: String {
        if let id = currentDisplayID,
           let name = model.displays.first(where: { $0.id == id })?.name {
            return name
        }
        return NSScreen.main?.localizedName ?? "This Display"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Lattice")
                .font(.system(size: 13, weight: .semibold))
            if !model.isEnabled {
                Text("Paused")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
            }
            Spacer(minLength: 8)
            Text(displayName)
                .font(SurfaceTokens.micro)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 9)
    }

    private var spaceRow: some View {
        HStack(spacing: 10) {
            SurfaceSpaceStrip(spaces: model.spaces,
                              focusedSpace: model.focusedSpace,
                              displayID: currentDisplayID) { entry, space in
                guard space != entry.current else { return }
                SpaceManager.shared.activate(space, on: entry.display)
                dismiss()
            }
            Spacer(minLength: 0)
            if let entry = currentEntry, entry.spaceIDs.count > 1, entry.spaceIDs.count <= 5,
               let index = entry.spaceIDs.firstIndex(of: model.focusedSpace) {
                Text("Space \(index + 1) of \(entry.spaceIDs.count)")
                    .font(SurfaceTokens.micro)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var permissionBanner: some View {
        Button {
            model.requestAccessibility()
            dismiss()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                Text("Accessibility access is required to tile windows")
                    .font(SurfaceTokens.micro)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text("Open Settings")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .accessibilityLabel("Accessibility access is required. Open System Settings")
    }

    // MARK: - Layouts

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SurfaceSectionHeader(title: "Layout", trailing: model.layout.title)
            HStack(spacing: 5) {
                ForEach(LayoutKind.allCases) { kind in
                    LayoutButton(kind: kind,
                                 isActive: model.layout == kind) {
                        model.setLayout(kind)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 12)
    }

    // MARK: - Windows

    private var spaceWindows: [ManagedWindow] {
        let windows = model.windowsBySpace[model.focusedSpace] ?? []
        let tiled = model.tiler.tiledWindows(on: model.focusedSpace)
        var rank: [WindowID: Int] = [:]
        for (index, id) in tiled.enumerated() { rank[id] = index }
        return windows.sorted { lhs, rhs in
            let left = rank[lhs.id] ?? (1000 + Int(lhs.id.raw % 1000))
            let right = rank[rhs.id] ?? (1000 + Int(rhs.id.raw % 1000))
            if left != right { return left < right }
            return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
        }
    }

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SurfaceSectionHeader(title: "Windows", trailing: "\(spaceWindows.count)")
                .padding(.horizontal, 16)
                .padding(.top, 11)
                .padding(.bottom, 2)

            if spaceWindows.isEmpty {
                emptyWindows
            } else {
                if snapshotMode {
                    windowRows
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        windowRows
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The list itself. `ImageRenderer` draws a `ScrollView` as blank, so the snapshot path
    /// renders the rows directly.
    private var windowRows: some View {
        LazyVStack(spacing: 1) {
            ForEach(spaceWindows) { window in
                MenuBarWindowRow(
                    window: window,
                    isFocused: model.focusedWindow?.id == window.id,
                    onFocus: {
                        model.engine.focus(window.id)
                        dismiss()
                    },
                    onHide: {
                        model.engine.setMinimized(window.id, true)
                        model.rebuildWindowCache()
                    }
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    private var emptyWindows: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No windows on this Space")
                .font(SurfaceTokens.caption)
                .foregroundStyle(.secondary)
            Text(model.isEnabled
                 ? "Open an app and Lattice tiles it here."
                 : "Tiling is paused. Resume to arrange new windows.")
                .font(SurfaceTokens.micro)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 2) {
            SurfaceIconButton(
                symbol: model.isEnabled ? "pause.fill" : "play.fill",
                label: model.isEnabled ? "Pause tiling" : "Resume tiling",
                isOn: !model.isEnabled
            ) {
                model.setEnabled(!model.isEnabled)
            }

            SurfaceIconButton(symbol: "command", label: "Command palette") {
                dismiss()
                NotificationCenter.default.post(name: .latticeShowPalette, object: nil)
            }

            SurfaceIconButton(symbol: "keyboard", label: "Shortcut cheat sheet") {
                dismiss()
                NotificationCenter.default.post(name: .latticeShowCheatSheet, object: nil)
            }

            Spacer(minLength: 4)

            SurfaceIconButton(symbol: "macwindow", label: "Open Lattice") {
                dismiss()
                NotificationCenter.default.post(name: .latticeShowMainWindow, object: nil)
            }

            SurfaceIconButton(symbol: "power", label: "Quit Lattice") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(height: 40)
    }
}

// MARK: - Layout button

private struct LayoutButton: View {
    let kind: LayoutKind
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                LayoutThumbnail(kind: kind, count: 3)
                    .frame(width: 44, height: 27)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isActive ? Color.accentColor.opacity(0.10) : Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isActive ? Color.accentColor : Color.primary.opacity(0.10),
                                          lineWidth: isActive ? 1.5 : SurfaceTokens.hairline)
                    )
                Text(kind.title)
                    .font(.system(size: 9.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(kind.summary)
        .accessibilityLabel("\(kind.title) layout")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Window row

private struct MenuBarWindowRow: View {
    let window: ManagedWindow
    let isFocused: Bool
    let onFocus: () -> Void
    let onHide: () -> Void

    @State private var hovering = false

    private var title: String {
        window.title.isEmpty ? window.appName : window.title
    }

    private var subtitle: String {
        var parts: [String] = []
        if !window.title.isEmpty { parts.append(window.appName) }
        if window.isFloating { parts.append("Floating") }
        return parts.joined(separator: " · ")
    }

    private var sizeText: String {
        "\(Int(window.frame.width.rounded()))×\(Int(window.frame.height.rounded()))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onFocus) {
                HStack(spacing: 8) {
                    icon

                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(SurfaceTokens.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(isFocused ? .secondary : .tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(sizeText)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(window.appName). \(title). \(sizeText) points.")
            .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)

            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(hovering ? 0.10 : 0)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help("Hide window")
            .accessibilityLabel("Hide \(title)")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.075 : (isFocused ? 0.045 : 0)))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering = $0 }
        .animation(SurfaceTokens.reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = SurfaceIconCache.shared.icon(for: window.pid) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 17, height: 17)
                .accessibilityHidden(true)
        } else {
            // A pid can be stale (or, in the design fixture, fictional); the bundle id still
            // resolves the real icon through NSWorkspace.
            AppIcon(bundleID: window.bundleID, appName: window.appName, size: 17)
        }
    }
}
