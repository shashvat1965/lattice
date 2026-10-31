import SwiftUI
import AppKit
import ServiceManagement
import LatticeKit

// MARK: - Displays

struct DisplaysSettingsSection: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared
    @State private var expanded: Set<DisplayID> = []

    var body: some View {
        SettingsSection(
            "Displays",
            subtitle: "Defaults unless overridden. Every screen macOS reports, with its own optional settings.",
            footnote: "A per-display override only changes that display. Unplugging it keeps the override for when it comes back."
        ) {
            if model.displays.isEmpty {
                SettingsContentRow(showsDivider: false) {
                    EmptyState(
                        symbol: "display",
                        title: "No displays reported",
                        message: "Lattice reads displays from macOS. If a screen is connected, refresh the list.",
                        actionTitle: "Refresh",
                        action: { model.refreshSpaces() },
                        compact: true
                    )
                }
            } else {
                ForEach(model.displays) { display in
                    displayRow(display)
                }
            }
        } trailing: {
            Button("Refresh") { model.refreshSpaces() }
                .controlSize(.small)
                .accessibilityLabel("Refresh the list of displays")
        }
    }

    @ViewBuilder
    private func displayRow(_ display: DisplayInfo) -> some View {
        let isExpanded = expanded.contains(display.id)
        let isLast = display.id == model.displays.last?.id
        let override = store.prefs.displayOverrides[String(display.id.raw)]

        SettingsContentRow(showsDivider: isExpanded || !isLast) {
            Button {
                withAnimation(LatticeTheme.animation) {
                    if isExpanded { expanded.remove(display.id) } else { expanded.insert(display.id) }
                }
            } label: {
                HStack(spacing: LatticeTheme.Spacing.sm) {
                    Image(systemName: display.hasNotch ? "laptopcomputer" : "display")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: LatticeTheme.Spacing.xs) {
                            Text(display.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if display.hasNotch {
                                StatusPill(text: "Notch", tone: .neutral, symbol: "camera.metering.unknown")
                            }
                            if override != nil {
                                StatusPill(text: "Custom", tone: .accent, symbol: "slider.horizontal.3")
                            }
                        }

                        Text(summary(for: display, override: override))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: LatticeTheme.Spacing.sm)

                    Text(resolution(display))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(display.name), \(summary(for: display, override: override))")
            .accessibilityHint(isExpanded ? "Hide display settings" : "Show display settings")
        }

        if isExpanded {
            SettingsPickerRow(
                title: "Layout on this display",
                subtitle: "Overrides the Space's layout only while a window is on this screen.",
                selection: layoutBinding(display, override: override),
                options: layoutOptions,
                width: 250
            )

            DisplayOverrideSlider(
                title: "Gap between windows",
                subtitle: "The inner gap used on this display.",
                isCustom: override?.gap != nil,
                defaultValue: store.prefs.gap,
                range: 0...32,
                unit: "pt",
                setCustom: { custom in
                    update(display) { value in
                        value.gap = custom ? (override?.gap ?? store.prefs.gap) : nil
                    }
                },
                value: gapBinding(display, override: override)
            )

            DisplayOverrideSlider(
                title: "Gap to the screen edge",
                subtitle: "The space between the outer windows and this screen's edge.",
                isCustom: override?.outerGap != nil,
                defaultValue: store.prefs.outerGap,
                range: 0...64,
                unit: "pt",
                setCustom: { custom in
                    update(display) { value in
                        value.outerGap = custom ? (override?.outerGap ?? store.prefs.outerGap) : nil
                    }
                },
                value: outerGapBinding(display, override: override)
            )

            SettingsPickerRow(
                title: "The Dock",
                subtitle: "Keep this display's windows above the Dock, or let them use the full screen.",
                selection: dockBinding(display, override: override),
                options: [
                    SettingsOption("Use the setting above", 0),
                    SettingsOption("Keep clear of the Dock", 1),
                    SettingsOption("Use the full screen", 2),
                ],
                width: 200
            )

            SettingsContentRow(showsDivider: display.id != model.displays.last?.id) {
                HStack {
                    Text(override == nil
                         ? "This display uses the defaults from Gaps & padding."
                         : "This display has its own settings.")
                        .latticeCaption()

                    Spacer(minLength: LatticeTheme.Spacing.sm)

                    Button("Reset this display") {
                        store.update { $0.displayOverrides.removeValue(forKey: String(display.id.raw)) }
                    }
                    .controlSize(.small)
                    .disabled(override == nil)
                    .accessibilityLabel("Remove every override for \(display.name)")
                }
            }
        }
    }

    // MARK: Copy

    private func summary(for display: DisplayInfo, override: DisplayOverride?) -> String {
        guard let override else {
            return "Defaults — \(store.prefs.layout.title.lowercased()), \(Int(store.prefs.gap)) pt gap, \(Int(store.prefs.outerGap)) pt edge"
        }
        var parts: [String] = []
        if let layout = override.layout { parts.append(layout.title.lowercased()) }
        if let gap = override.gap { parts.append("\(Int(gap)) pt inner gap") }
        if let outer = override.outerGap { parts.append("\(Int(outer)) pt edge gap") }
        if let dock = override.respectDock { parts.append(dock ? "stops at the Dock" : "uses the full screen") }
        return parts.isEmpty ? "Defaults" : parts.joined(separator: " · ")
    }

    private func resolution(_ display: DisplayInfo) -> String {
        let width = Int(display.frame.width.rounded())
        let height = Int(display.frame.height.rounded())
        return "\(width) × \(height)"
    }

    private var layoutOptions: [SettingsOption<LayoutKind?>] {
        [SettingsOption("Use the Space's layout", nil)]
            + LayoutKind.allCases.map { SettingsOption($0.title, Optional($0)) }
    }

    // MARK: Bindings

    private func layoutBinding(_ display: DisplayInfo, override: DisplayOverride?) -> Binding<LayoutKind?> {
        Binding(
            get: { override?.layout },
            set: { kind in update(display) { $0.layout = kind } }
        )
    }

    private func gapBinding(_ display: DisplayInfo, override: DisplayOverride?) -> Binding<Double> {
        Binding(
            get: { Double(override?.gap ?? store.prefs.gap) },
            set: { value in
                guard override?.gap != nil else { return }
                update(display) { $0.gap = CGFloat(value) }
            }
        )
    }

    private func outerGapBinding(_ display: DisplayInfo, override: DisplayOverride?) -> Binding<Double> {
        Binding(
            get: { Double(override?.outerGap ?? store.prefs.outerGap) },
            set: { value in
                guard override?.outerGap != nil else { return }
                update(display) { $0.outerGap = CGFloat(value) }
            }
        )
    }

    private func dockBinding(_ display: DisplayInfo, override: DisplayOverride?) -> Binding<Int> {
        Binding(
            get: {
                guard let value = override?.respectDock else { return 0 }
                return value ? 1 : 2
            },
            set: { selection in
                update(display) { value in
                    switch selection {
                    case 1: value.respectDock = true
                    case 2: value.respectDock = false
                    default: value.respectDock = nil
                    }
                }
            }
        )
    }

    private func update(_ display: DisplayInfo, _ mutate: (inout DisplayOverride) -> Void) {
        let key = String(display.id.raw)
        store.update { prefs in
            var value = prefs.displayOverrides[key] ?? DisplayOverride()
            mutate(&value)
            if value.gap == nil, value.outerGap == nil, value.layout == nil, value.respectDock == nil {
                prefs.displayOverrides.removeValue(forKey: key)
            } else {
                prefs.displayOverrides[key] = value
            }
        }
    }
}

/// A row whose switch turns a per-display override on and off, and whose slider is only
/// editable while the override exists. "Using 8 pt" is the honest default state.
private struct DisplayOverrideSlider: View {
    var title: String
    var subtitle: String?
    var isCustom: Bool
    var defaultValue: CGFloat
    var range: ClosedRange<Double>
    var unit: String
    var setCustom: (Bool) -> Void
    @Binding var value: Double

    var body: some View {
        SettingRow(title, subtitle: subtitle, showsDivider: true) {
            HStack(spacing: LatticeTheme.Spacing.xs) {
                Toggle("", isOn: Binding(
                    get: { isCustom },
                    set: { setCustom($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("Override \(title.lowercased()) on this display")

                if isCustom {
                    Slider(value: $value, in: range, step: 1)
                        .frame(width: 130)
                        .accessibilityLabel(title)
                        .accessibilityValue("\(Int(value)) \(unit)")

                    Text("\(Int(value)) \(unit)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                        .monospacedDigit()
                } else {
                    Text("Using \(Int(defaultValue)) \(unit)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 178, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .animation(LatticeTheme.animation, value: isCustom)
    }
}

// MARK: - Spaces

struct SpacesSettingsSection: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        SettingsSection(
            "Spaces",
            subtitle: "Lattice arranges windows on the real Spaces macOS already has.",
            footnote: "Lattice never creates, hides or renames a Space. Creating and deleting Spaces stays Mission Control's job."
        ) {
            SettingsToggleRow(
                title: "Follow a window to its Space",
                subtitle: "When you send a window to another Space, the view follows it so you are not left looking at the old one.",
                isOn: store.binding(\.followWindowAcrossSpaces)
            )

            SettingsContentRow(
                title: "The Spaces window",
                subtitle: "Every Space on every display, its layout, and a way to send windows between them."
            ) {
                HStack {
                    Button {
                        NotificationCenter.default.post(name: .latticeShowSpaces, object: nil)
                    } label: {
                        Label("Open Spaces", systemImage: "rectangle.on.rectangle")
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Open the Spaces window")

                    Spacer(minLength: LatticeTheme.Spacing.sm)

                    Text("\(model.spaces.reduce(0) { $0 + $1.userSpaceIDs.count }) Spaces on \(model.displays.count) \(model.displays.count == 1 ? "display" : "displays")")
                        .latticeCaption()
                        .monospacedDigit()
                }
            }

            if model.spaces.isEmpty {
                SettingsContentRow(showsDivider: false) {
                    HStack(spacing: LatticeTheme.Spacing.xs) {
                        InlineHint(text: "No Spaces reported yet. Lattice reads them directly from the window server.",
                                   symbol: "rectangle.on.rectangle.slash")
                        Spacer(minLength: LatticeTheme.Spacing.xs)
                        Button("Refresh") { model.refreshSpaces() }
                            .controlSize(.small)
                            .accessibilityLabel("Refresh the list of Spaces")
                    }
                }
            } else {
                ForEach(Array(model.spaces.enumerated()), id: \.offset) { index, entry in
                    spaceRows(entry, isLast: index == model.spaces.count - 1)
                }
            }
        }
    }

    @ViewBuilder
    private func spaceRows(_ entry: SpaceManager.DisplaySpaces, isLast: Bool) -> some View {
        let displayName = model.displays.first { $0.id == entry.display }?.name ?? "Display"
        let spaces = entry.userSpaceIDs

        SettingsContentRow(
            title: displayName,
            subtitle: spaces.isEmpty ? "No user Spaces on this display." : "Each Space can keep its own layout.",
            showsDivider: !isLast
        ) {
            VStack(spacing: LatticeTheme.Spacing.xs) {
                ForEach(Array(spaces.enumerated()), id: \.offset) { index, space in
                    HStack(spacing: LatticeTheme.Spacing.xs) {
                        Text("Space \(index + 1)")
                            .font(.system(size: 12))
                            .frame(width: 62, alignment: .leading)

                        if space == entry.current {
                            StatusPill(text: "Showing", tone: .accent, symbol: "eye")
                        }

                        Spacer(minLength: LatticeTheme.Spacing.xs)

                        Picker("Layout for Space \(index + 1)", selection: spaceLayoutBinding(space)) {
                            Text("Default (\(store.prefs.layout.title))").tag(LayoutKind?.none)
                            ForEach(LayoutKind.allCases) { kind in
                                Text(kind.title).tag(Optional(kind))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 170)
                        .accessibilityLabel("Layout for Space \(index + 1) on \(displayName)")
                    }
                }
            }

            if !store.prefs.spaceLayouts.isEmpty {
                HStack {
                    Text(spaceOverrideSummary)
                        .latticeCaption()
                        .monospacedDigit()
                    Spacer(minLength: LatticeTheme.Spacing.xs)
                    Button("Clear all") {
                        store.update { $0.clearLayoutOverrides() }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Clear every per-Space layout choice")
                }
                .padding(.top, 2)
            }
        }
    }

    private var spaceOverrideSummary: String {
        let count = store.prefs.spaceLayouts.count
        return count == 1
            ? "1 Space keeps its own layout."
            : "\(count) Spaces keep their own layout."
    }

    private func spaceLayoutBinding(_ space: SpaceID) -> Binding<LayoutKind?> {
        let key = String(space.raw)
        return Binding(
            get: { store.prefs.spaceLayouts[key] },
            set: { kind in
                store.update { prefs in
                    if let kind {
                        prefs.spaceLayouts[key] = kind
                    } else {
                        prefs.spaceLayouts.removeValue(forKey: key)
                    }
                }
            }
        )
    }
}

// MARK: - Input

struct InputSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        SettingsSection(
            "Input",
            subtitle: "How dragging and pointing interact with tiling.",
            footnote: "Drag gestures are read through Accessibility. Lattice never sees keystrokes while another app is in front."
        ) {
            SettingsToggleRow(
                title: "Snap windows to edges",
                subtitle: "Drag a window to an edge or corner and it takes that portion of the screen.",
                isOn: store.binding(\.snapToEdges)
            )

            SettingsPickerRow(
                title: "Snap zones",
                subtitle: "How many places a dragged window can land.",
                selection: store.binding(\.snapZoneSet),
                options: SnapZoneSet.allCases.map { SettingsOption($0.title, $0) },
                isEnabled: store.prefs.snapToEdges,
                width: 240
            )

            SettingsToggleRow(
                title: "Show a preview while dragging",
                subtitle: "A translucent outline shows exactly where the window will land.",
                isOn: store.binding(\.showSnapPreview),
                isEnabled: store.prefs.snapToEdges
            )

            SettingsToggleRow(
                title: "⌘-drag to swap windows",
                subtitle: "Hold Command while dragging one tiled window onto another to trade their places.",
                isOn: store.binding(\.dragToSwap)
            )

            SettingsToggleRow(
                title: "Focus follows the mouse",
                subtitle: "Moving the pointer over a window focuses it without a click. Keyboard focus and the border follow along.",
                isOn: store.binding(\.focusFollowsMouse)
            )

            SettingsToggleRow(
                title: "Move the pointer to the focused window",
                subtitle: store.prefs.focusFollowsMouse
                    ? "Unavailable while focus follows the mouse, because warping the pointer would immediately change focus again."
                    : "When a shortcut focuses a window, the pointer moves with it so your next click lands where you are looking.",
                isOn: store.binding(\.warpMouseOnFocus),
                showsDivider: false,
                isEnabled: !store.prefs.focusFollowsMouse
            )
        }
    }
}

// MARK: - Startup

struct StartupSettingsSection: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var loginError: String?

    var body: some View {
        SettingsSection(
            "Startup",
            subtitle: "When Lattice starts and how it introduces itself.",
            footnote: "Launch at login uses the system's own login item, so it can also be managed from System Settings ▸ General ▸ Login Items."
        ) {
            SettingsToggleRow(
                title: "Launch at login",
                subtitle: "Start Lattice automatically so tiling is ready before you open a window.",
                isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })
            )

            if let loginError {
                SettingsContentRow {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                        Text(loginError)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            SettingsToggleRow(
                title: "Show the menu bar icon",
                subtitle: "The Lattice tile glyph. Applies the next time Lattice starts; the item is created at launch.",
                isOn: store.binding(\.showMenuBarIcon)
            )

            SettingsContentRow(
                title: "Accessibility access",
                subtitle: "Lattice needs this to read and move windows. It can be revoked at any time."
            ) {
                HStack {
                    StatusPill(
                        text: model.accessibilityGranted ? "Granted" : "Not granted",
                        tone: model.accessibilityGranted ? .positive : .warning,
                        symbol: model.accessibilityGranted ? "checkmark.circle" : "hand.raised"
                    )

                    Spacer(minLength: LatticeTheme.Spacing.sm)

                    Button("Open System Settings") {
                        SettingsLinks.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Open Accessibility settings")
                }
            }

            SettingsContentRow(
                title: "Welcome tour",
                subtitle: "The short first-run walkthrough, including the Accessibility step.",
                showsDivider: false
            ) {
                HStack {
                    Text(store.prefs.hasCompletedOnboarding
                         ? "You have completed the tour."
                         : "The tour has not been completed yet.")
                        .latticeCaption()

                    Spacer(minLength: LatticeTheme.Spacing.sm)

                    Button("Show Welcome") {
                        store.update { $0.hasCompletedOnboarding = false }
                        OnboardingWindowController.show()
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Show the welcome tour again")
                }
            }
        }
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
            launchAtLogin = enabled
            store.update { $0.launchAtLogin = enabled }
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            loginError = "Launch at login could not be \(enabled ? "enabled" : "disabled"): \(error.localizedDescription)"
        }
    }
}

// MARK: - Advanced

struct AdvancedSettingsSection: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    @State private var copied = false
    @State private var confirmReset = false

    var body: some View {
        SettingsSection(
            "Advanced",
            subtitle: "Timing, logging and the reset switch.",
            footnote: "These are safe to change. If windows feel twitchy during app launches, raise the debounce; if they feel slow, lower it."
        ) {
            SettingsSliderRow(
                title: "Settle time before rearranging",
                subtitle: "How long Lattice waits for macOS to finish moving a window before it tiles again.",
                value: store.binding(\.reconcileDebounceMs).settingsDouble,
                range: 60...400,
                step: 10,
                valueText: { "\(Int($0)) ms" }
            )

            SettingsToggleRow(
                title: "Verbose logging",
                subtitle: "Records every window decision in the log. Useful when one app refuses to tile.",
                isOn: store.binding(\.verboseLogging)
            )

            SettingsContentRow(
                title: "Logs",
                subtitle: "~/Library/Logs/Lattice/lattice.log",
                showsDivider: true
            ) {
                HStack(spacing: LatticeTheme.Spacing.xs) {
                    Button("Open Logs") { SettingsLinks.openLogFolder() }
                        .controlSize(.small)
                        .accessibilityLabel("Open the Lattice log folder")

                    Button(copied ? "Copied" : "Copy Diagnostics") { copyDiagnostics() }
                        .controlSize(.small)
                        .accessibilityLabel("Copy diagnostics to the clipboard")

                    Spacer(minLength: 0)
                }
            }

            SettingsContentRow(
                title: "Reset Lattice",
                subtitle: "Layouts, gaps, borders, motion, app rules and every shortcut return to their shipping values.",
                showsDivider: false
            ) {
                HStack {
                    Text("This cannot be undone.")
                        .latticeCaption()

                    Spacer(minLength: LatticeTheme.Spacing.sm)

                    Button("Reset All Settings…") { confirmReset = true }
                        .controlSize(.small)
                        .accessibilityLabel("Reset all Lattice settings to defaults")
                }
            }
        }
        .confirmationDialog("Reset Lattice to defaults?", isPresented: $confirmReset) {
            Button("Reset Everything", role: .destructive) {
                store.resetEverything(keepingOnboarding: true)
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                model.setEnabled(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every setting returns to its shipping value and the login item is removed. This cannot be undone.")
        }
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            SettingsDiagnostics.text(model: model, prefs: store.prefs),
            forType: .string
        )
        withAnimation(LatticeTheme.animation) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run {
                withAnimation(LatticeTheme.animation) { copied = false }
            }
        }
    }
}
