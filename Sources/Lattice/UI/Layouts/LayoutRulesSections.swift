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

/// What happens when a Space holds more windows than the display can fit at the sizes their
/// apps demand. This is the one place the "yabai or leave it" trade-off is made.
struct LayoutCrowdingSection: View {

    @ObservedObject var prefs: LayoutsPreferences

    var body: some View {
        LayoutsSection("Crowded Spaces") {
            LayoutsRow("Tile anyway", showsDivider: false) {
                LayoutsToggle(isOn: prefs.binding(\.tileCrowdedSpaces),
                              label: "Tile crowded Spaces")
            }
        } footer: {
            Text(prefs.prefs.tileCrowdedSpaces
                 ? "Keeps the layout and lets each app clamp its own size, so windows can overlap. The yabai behaviour."
                 : "Leaves a Space that cannot fit every window exactly as it is and shows “Space full” in Overview.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
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
