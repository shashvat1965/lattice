import SwiftUI
import AppKit
import LatticeKit

// MARK: - Tiling

/// The five decisions that change what tiling does, before any of the tuning.
struct TilingSettingsSection: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        SettingsSection(
            "Tiling",
            subtitle: "How windows are arranged on every Space.",
            footnote: "The default layout is what a new Space starts with. A Space you have switched yourself keeps its own layout until you change it or clear it."
        ) {
            SettingsToggleRow(
                title: "Tile windows automatically",
                subtitle: "When off, Lattice stops moving windows. Your shortcuts and the menu bar stay available.",
                isOn: Binding(
                    get: { model.isEnabled },
                    set: { model.setEnabled($0) }
                )
            )

            SettingsContentRow(
                title: "Default layout",
                subtitle: "Used by any Space that has not been given a layout of its own."
            ) {
                HStack(spacing: LatticeTheme.Spacing.xs) {
                    ForEach(LayoutKind.allCases) { kind in
                        SettingsLayoutChoice(kind: kind, selected: store.prefs.layout == kind) {
                            store.update { $0.layout = kind }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            SettingsPickerRow(
                title: "Where a new window goes",
                subtitle: "Pick the position a newly opened window takes in the layout.",
                selection: store.binding(\.insertionPolicy),
                options: InsertionPolicy.allCases.map { SettingsOption($0.title, $0) }
            )

            SettingsToggleRow(
                title: "Rebalance after a window closes",
                subtitle: "The remaining windows grow to fill the gap. When off, the gap stays until you change the layout.",
                isOn: store.binding(\.autoBalance)
            )

            SettingsSliderRow(
                title: "Smallest tile width",
                subtitle: "Below this, a layout cannot fit. Lattice falls back to a balanced grid rather than overlapping windows.",
                value: store.binding(\.minTiledWidth).settingsDouble,
                range: 120...520,
                step: 10,
                valueText: { "\(Int($0)) pt" }
            )

            SettingsSliderRow(
                title: "Smallest tile height",
                subtitle: "The same floor for height. macOS itself refuses to make a window smaller than its title bar.",
                value: store.binding(\.minTiledHeight).settingsDouble,
                range: 80...380,
                step: 10,
                valueText: { "\(Int($0)) pt" },
                showsDivider: false
            )
        }
    }
}

// MARK: - Gaps and padding

struct GapsSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared
    @State private var showsEdges = false

    var body: some View {
        SettingsSection(
            "Gaps & padding",
            subtitle: "The breathing room around and between windows.",
            footnote: "Gaps are measured in points and applied live. The menu bar and a notch are always respected; the Dock is respected when the switch is on."
        ) {
            SettingsSliderRow(
                title: "Gap between windows",
                subtitle: "Space between neighbouring tiles, on every side.",
                value: store.binding(\.gap).settingsDouble,
                range: 0...32,
                step: 1,
                valueText: { "\(Int($0)) pt" }
            )

            SettingsSliderRow(
                title: "Gap to the screen edge",
                subtitle: "Space between the outer windows and the edge of the display.",
                value: store.binding(\.outerGap).settingsDouble,
                range: 0...64,
                step: 1,
                valueText: { "\(Int($0)) pt" },
                showsDivider: false
            )

            SettingsContentRow(
                title: "Preview",
                subtitle: "Four windows with the current gaps, edge padding and screen furniture."
            ) {
                SettingsGapPreview(
                    gap: store.prefs.gap,
                    outerGap: store.prefs.outerGap,
                    layout: store.prefs.layout,
                    edges: store.prefs.edges,
                    respectMenuBar: store.prefs.respectMenuBar,
                    respectDock: store.prefs.respectDock
                )
                .frame(height: 118)
                .accessibilityLabel("Preview of the current gaps and padding")
            }

            SettingsDisclosureRow(
                title: "Per-edge padding",
                subtitle: edgeSummary,
                isExpanded: showsEdges
            ) {
                withAnimation(LatticeTheme.animation) { showsEdges.toggle() }
            }

            if showsEdges {
                SettingsSliderRow(
                    title: "Top",
                    subtitle: "Extra space above every tile, added to the gap to the screen edge.",
                    value: edge(\.top), range: 0...120, step: 1,
                    valueText: { "\(Int($0)) pt" }
                )
                SettingsSliderRow(
                    title: "Leading",
                    subtitle: "Extra space on the left. On a right-to-left system this is the right edge.",
                    value: edge(\.leading), range: 0...120, step: 1,
                    valueText: { "\(Int($0)) pt" }
                )
                SettingsSliderRow(
                    title: "Bottom",
                    subtitle: "Extra space below every tile, on top of the Dock allowance.",
                    value: edge(\.bottom), range: 0...120, step: 1,
                    valueText: { "\(Int($0)) pt" }
                )
                SettingsSliderRow(
                    title: "Trailing",
                    subtitle: "Extra space on the right. On a right-to-left system this is the left edge.",
                    value: edge(\.trailing), range: 0...120, step: 1,
                    valueText: { "\(Int($0)) pt" },
                    showsDivider: false
                )

                SettingsContentRow(showsDivider: true) {
                    InlineHint(
                        text: "Edge padding is added on top of the gap to the screen edge. Useful for a side display, a webcam housing or a shelf.",
                        symbol: "rectangle.inset.filled"
                    )
                    HStack {
                        Spacer()
                        Button("Clear edge padding") {
                            store.update { $0.edges = Margin() }
                        }
                        .controlSize(.small)
                        .disabled(store.prefs.edges == Margin())
                        .accessibilityLabel("Clear per-edge padding")
                    }
                }
            }

            SettingsToggleRow(
                title: "Keep windows below the menu bar",
                subtitle: "The menu bar and a notch are never covered, even in full-height layouts.",
                isOn: store.binding(\.respectMenuBar)
            )

            SettingsToggleRow(
                title: "Keep windows out of the Dock",
                subtitle: "When the Dock is showing, tiles stop above it instead of sliding underneath.",
                isOn: store.binding(\.respectDock),
                showsDivider: false
            )
        }
    }

    private var edgeSummary: String {
        let edges = store.prefs.edges
        guard edges != Margin() else {
            return "Add extra space on one side only. Nothing is set right now."
        }
        return "Top \(Int(edges.top)) · Leading \(Int(edges.leading)) · Bottom \(Int(edges.bottom)) · Trailing \(Int(edges.trailing)) pt"
    }

    private func edge(_ keyPath: WritableKeyPath<Margin, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(store.prefs.edges[keyPath: keyPath]) },
            set: { value in
                store.update { $0.edges[keyPath: keyPath] = CGFloat(value) }
            }
        )
    }
}

// MARK: - Layout tuning

struct LayoutTuningSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        SettingsSection(
            "Layouts",
            subtitle: "Fine-tuning for the Master, Stack and Grid layouts.",
            footnote: "Master ratio and stack peek apply wherever those layouts are used. Each Space can still pick a different layout in the Spaces window."
        ) {
            SettingsSliderRow(
                title: "Master window share",
                subtitle: "How much of the width the large window takes in the Master layout.",
                value: store.binding(\.masterRatio),
                range: 0.40...0.80,
                step: 0.01,
                valueText: { "\(Int(($0 * 100).rounded()))%" }
            )

            SettingsSliderRow(
                title: "Stack peek",
                subtitle: "How much of each window behind the front one stays visible in the Stack layout.",
                value: store.binding(\.stackPeek).settingsDouble,
                range: 0...40,
                step: 1,
                valueText: { "\(Int($0)) pt" }
            )

            SettingsPickerRow(
                title: "Grid columns",
                subtitle: "Automatic picks a balanced number of columns for the windows on screen.",
                selection: store.binding(\.gridColumns),
                options: [
                    SettingsOption("Automatic", 0),
                    SettingsOption("1 column", 1),
                    SettingsOption("2 columns", 2),
                    SettingsOption("3 columns", 3),
                    SettingsOption("4 columns", 4),
                    SettingsOption("5 columns", 5),
                    SettingsOption("6 columns", 6),
                    SettingsOption("7 columns", 7),
                    SettingsOption("8 columns", 8),
                ]
            )

            SettingsContentRow(
                title: "Live previews",
                subtitle: "The two layouts these controls affect, updating as you drag.",
                showsDivider: false
            ) {
                HStack(alignment: .top, spacing: LatticeTheme.Spacing.xxl) {
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsMasterPreview(
                            ratio: store.prefs.masterRatio,
                            peek: store.prefs.stackPeek
                        )
                        .frame(width: 140, height: 84)

                        Text("Master · \(Int((store.prefs.masterRatio * 100).rounded()))%, peek \(Int(store.prefs.stackPeek)) pt")
                            .latticeCaption()
                            .monospacedDigit()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SettingsGridPreview(columns: store.prefs.gridColumns)
                            .frame(width: 140, height: 84)

                        Text(gridCaption)
                            .latticeCaption()
                            .monospacedDigit()
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var gridCaption: String {
        switch store.prefs.gridColumns {
        case 0: return "Grid · automatic columns"
        case 1: return "Grid · 1 column"
        default: return "Grid · \(store.prefs.gridColumns) columns"
        }
    }
}
