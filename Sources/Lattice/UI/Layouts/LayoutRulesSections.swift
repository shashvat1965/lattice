import SwiftUI
import LatticeKit

/// How small a tile may get, and where the next window lands.
struct LayoutLimitsSection: View {

    @ObservedObject var prefs: LayoutsPreferences

    var body: some View {
        LayoutsSection("Limits") {
            LayoutsRow("Smallest tile width") {
                LayoutsSlider(
                    value: point(\.minTiledWidth),
                    range: 120...520,
                    step: 10,
                    label: "Smallest tile width",
                    valueText: { "\(Int($0)) pt" }
                )
            }

            LayoutsRow("Smallest tile height", showsDivider: false) {
                LayoutsSlider(
                    value: point(\.minTiledHeight),
                    range: 80...380,
                    step: 10,
                    label: "Smallest tile height",
                    valueText: { "\(Int($0)) pt" }
                )
            }
        }
    }

    private func point(_ keyPath: WritableKeyPath<Preferences, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(prefs.prefs[keyPath: keyPath]) },
            set: { value in prefs.update { $0[keyPath: keyPath] = CGFloat(value) } }
        )
    }
}

/// What happens to the arrangement when a window arrives or leaves.
struct LayoutInsertionSection: View {

    @ObservedObject var prefs: LayoutsPreferences

    var body: some View {
        LayoutsSection("When a window opens") {
            LayoutsRow("New window position") {
                LatticeMenuButton(
                    selection: prefs.binding(\.insertionPolicy),
                    options: InsertionPolicy.allCases.map { (value: $0, title: $0.title) }
                )
                .frame(width: 210)
                .accessibilityLabel("New window position")
            }

            LayoutsRow("Rebalance after close", showsDivider: false) {
                LayoutsToggle(
                    isOn: prefs.binding(\.autoBalance),
                    label: "Rebalance after close"
                )
            }
        }
    }
}
