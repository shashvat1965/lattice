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
            footnote: "An override stays with its display when it is unplugged."
        ) {
            SettingsToggleRow(
                title: "Keep windows below the menu bar",
                isOn: store.binding(\.respectMenuBar)
            )

            SettingsToggleRow(
                title: "Keep windows out of the Dock",
                isOn: store.binding(\.respectDock),
                showsDivider: !model.displays.isEmpty
            )

            if model.displays.isEmpty {
                SettingsContentRow(showsDivider: false) {
                    InlineHint(text: "No displays reported. Reconnect a screen, then reopen this page.",
                               symbol: "display.slash")
                }
            } else {
                ForEach(model.displays) { display in
                    displayRows(display)
                }
            }
        }
    }

    @ViewBuilder
    private func displayRows(_ display: DisplayInfo) -> some View {
        let isExpanded = expanded.contains(display.id)
        let isLast = display.id == model.displays.last?.id
        let override = store.prefs.displayOverrides[String(display.id.raw)]

        SettingsContentRow(showsDivider: isExpanded || !isLast) {
            Button {
                withAnimation(LatticeTheme.animation) {
                    if isExpanded {
                        expanded.remove(display.id)
                    } else {
                        expanded.insert(display.id)
                    }
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

                            if override != nil {
                                StatusPill(text: "Custom", tone: .accent, symbol: "slider.horizontal.3")
                            }
                        }

                        Text(summary(for: display, override: override))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                title: "Layout",
                selection: layoutBinding(display, override: override),
                options: layoutOptions,
                width: 220
            )

            DisplayOverrideSlider(
                title: "Inner gap",
                isCustom: override?.gap != nil,
                defaultValue: store.prefs.gap,
                range: 0...32,
                setCustom: { custom in
                    update(display) { value in
                        value.gap = custom ? (override?.gap ?? store.prefs.gap) : nil
                    }
                },
                value: gapBinding(display, override: override)
            )

            DisplayOverrideSlider(
                title: "Edge gap",
                isCustom: override?.outerGap != nil,
                defaultValue: store.prefs.outerGap,
                range: 0...64,
                setCustom: { custom in
                    update(display) { value in
                        value.outerGap = custom ? (override?.outerGap ?? store.prefs.outerGap) : nil
                    }
                },
                value: outerGapBinding(display, override: override)
            )

            SettingsPickerRow(
                title: "Dock",
                selection: dockBinding(display, override: override),
                options: [
                    SettingsOption("Use the setting above", 0),
                    SettingsOption("Keep clear of the Dock", 1),
                    SettingsOption("Use the full screen", 2),
                ],
                width: 200
            )

            SettingsActionRow(
                title: "Reset this display",
                symbol: "arrow.counterclockwise",
                isEnabled: override != nil,
                showsDivider: !isLast
            ) {
                store.update { $0.displayOverrides.removeValue(forKey: String(display.id.raw)) }
            }
        }
    }

    // MARK: Copy

    private func summary(for display: DisplayInfo, override: DisplayOverride?) -> String {
        var parts: [String] = []
        parts.append((override?.layout ?? store.prefs.layout).title)
        parts.append("\(Int(override?.gap ?? store.prefs.gap)) pt")
        parts.append("\(Int(override?.outerGap ?? store.prefs.outerGap)) pt edge")
        let dock = override?.respectDock ?? store.prefs.respectDock
        parts.append(dock ? "above the Dock" : "full screen")
        return parts.joined(separator: " · ")
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
    var isCustom: Bool
    var defaultValue: CGFloat
    var range: ClosedRange<Double>
    var setCustom: (Bool) -> Void
    @Binding var value: Double

    var body: some View {
        SettingRow(title, showsDivider: true) {
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
                        .accessibilityValue("\(Int(value)) pt")

                    Text("\(Int(value)) pt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                        .monospacedDigit()
                } else {
                    Text("Using \(Int(defaultValue)) pt")
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

// MARK: - Pointer & dragging

struct PointerSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        SettingsSection("Pointer & dragging") {
            SettingsToggleRow(
                title: "Snap to edges",
                isOn: store.binding(\.snapToEdges)
            )

            SettingsPickerRow(
                title: "Zone set",
                selection: store.binding(\.snapZoneSet),
                options: SnapZoneSet.allCases.map { SettingsOption($0.title, $0) },
                isEnabled: store.prefs.snapToEdges,
                width: 240
            )

            SettingsToggleRow(
                title: "Preview while dragging",
                isOn: store.binding(\.showSnapPreview),
                isEnabled: store.prefs.snapToEdges
            )

            SettingsToggleRow(
                title: "⌘-drag to swap windows",
                isOn: store.binding(\.dragToSwap)
            )

            SettingsToggleRow(
                title: "Focus follows the mouse",
                isOn: store.binding(\.focusFollowsMouse)
            )

            SettingsToggleRow(
                title: "Move the pointer to the focused window",
                subtitle: store.prefs.focusFollowsMouse
                    ? "Unavailable while focus follows the mouse."
                    : nil,
                isOn: store.binding(\.warpMouseOnFocus),
                showsDivider: false,
                isEnabled: !store.prefs.focusFollowsMouse
            )
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
        SettingsSection("Advanced") {
            SettingsSliderRow(
                title: "Settle time",
                value: store.binding(\.reconcileDebounceMs).settingsDouble,
                range: 60...400,
                step: 10,
                valueText: { "\(Int($0)) ms" }
            )

            SettingsToggleRow(
                title: "Verbose logging",
                isOn: store.binding(\.verboseLogging)
            )

            SettingsActionRow(title: "Open logs", symbol: "folder") {
                SettingsLinks.openLogFolder()
            }

            SettingsActionRow(
                title: copied ? "Copied" : "Copy diagnostics",
                symbol: copied ? "checkmark" : "doc.on.doc"
            ) {
                copyDiagnostics()
            }

            SettingsActionRow(
                title: "Reset all settings…",
                symbol: "arrow.counterclockwise",
                isDestructive: true,
                showsDivider: false
            ) {
                confirmReset = true
            }
        }
        .confirmationDialog("Reset Lattice to defaults?", isPresented: $confirmReset) {
            Button("Reset everything", role: .destructive) {
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
