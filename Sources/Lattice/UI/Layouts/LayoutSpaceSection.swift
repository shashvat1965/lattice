import AppKit
import SwiftUI
import LatticeKit

/// Everything about the room around the tiles: gaps, screen furniture and per-edge padding.
/// It is layout, so it belongs on this page rather than in Settings.
struct LayoutSpaceSection: View {

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: LayoutsPreferences

    @State private var showsEdges = false

    private var layout: LayoutKind {
        model.layout(for: model.focusedSpace)
    }

    var body: some View {
        LayoutsSection("Space") {
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 0) {
                    LayoutsRow("Inner gap") {
                        LayoutsSlider(
                            value: point(\.gap),
                            range: 0...32,
                            step: 1,
                            label: "Inner gap",
                            valueText: { "\(Int($0)) pt" }
                        )
                    }

                    LayoutsRow("Edge gap", showsDivider: false) {
                        LayoutsSlider(
                            value: point(\.outerGap),
                            range: 0...64,
                            step: 1,
                            label: "Edge gap",
                            valueText: { "\(Int($0)) pt" }
                        )
                    }
                }
                .frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.latticeHairline)
                    .frame(width: LatticeTheme.hairline)
                    .padding(.vertical, LatticeTheme.Spacing.sm)

                LayoutsGapPreview(
                    gap: prefs.prefs.gap,
                    outerGap: prefs.prefs.outerGap,
                    layout: layout,
                    edges: prefs.prefs.edges,
                    respectMenuBar: prefs.prefs.respectMenuBar,
                    respectDock: prefs.prefs.respectDock
                )
                .frame(width: 204, height: 104)
                .padding(.horizontal, LatticeTheme.Spacing.md)
                .padding(.vertical, LatticeTheme.Spacing.sm)
                .accessibilityLabel("Four windows with the current gaps and padding")
            }

            LatticeDivider()

            LayoutsDisclosureRow(
                title: "Screen edges",
                subtitle: edgeSummary,
                isExpanded: showsEdges,
                showsDivider: showsEdges
            ) {
                withAnimation(LatticeTheme.animation) { showsEdges.toggle() }
            }

            if showsEdges {
                LayoutsRow("Keep clear of the menu bar") {
                    LayoutsToggle(
                        isOn: prefs.binding(\.respectMenuBar),
                        label: "Keep clear of the menu bar"
                    )
                }

                LayoutsRow("Keep clear of the Dock") {
                    LayoutsToggle(
                        isOn: prefs.binding(\.respectDock),
                        label: "Keep clear of the Dock"
                    )
                }

                LayoutsRow("Top") {
                    LayoutsSlider(
                        value: point(\.edges.top),
                        range: 0...120,
                        step: 1,
                        label: "Top edge padding",
                        valueText: { "\(Int($0)) pt" }
                    )
                }

                LayoutsRow("Leading") {
                    LayoutsSlider(
                        value: point(\.edges.leading),
                        range: 0...120,
                        step: 1,
                        label: "Leading edge padding",
                        valueText: { "\(Int($0)) pt" }
                    )
                }

                LayoutsRow("Bottom") {
                    LayoutsSlider(
                        value: point(\.edges.bottom),
                        range: 0...120,
                        step: 1,
                        label: "Bottom edge padding",
                        valueText: { "\(Int($0)) pt" }
                    )
                }

                LayoutsRow("Trailing", showsDivider: false) {
                    LayoutsSlider(
                        value: point(\.edges.trailing),
                        range: 0...120,
                        step: 1,
                        label: "Trailing edge padding",
                        valueText: { "\(Int($0)) pt" }
                    )
                }
            }
        }
        .animation(LatticeTheme.animation, value: showsEdges)
    }

    // MARK: - Helpers

    /// Only shown when something is set, so the row carries information rather than a promise.
    private var edgeSummary: String? {
        let edges = prefs.prefs.edges
        if edges == Margin() {
            let menu = prefs.prefs.respectMenuBar ? "menu bar" : nil
            let dock = prefs.prefs.respectDock ? "Dock" : nil
            let clear = [menu, dock].compactMap { $0 }.joined(separator: " + ")
            return clear.isEmpty ? "Nothing kept clear" : "Keeps clear of the \(clear)"
        }
        return "Top \(Int(edges.top)) · Leading \(Int(edges.leading)) · Bottom \(Int(edges.bottom)) · Trailing \(Int(edges.trailing)) pt"
    }

    private func point(_ keyPath: WritableKeyPath<Preferences, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(prefs.prefs[keyPath: keyPath]) },
            set: { value in prefs.update { $0[keyPath: keyPath] = CGFloat(value) } }
        )
    }
}
