import SwiftUI
import AppKit
import LatticeKit

// MARK: - Window border

struct BordersSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared

    private var borderColor: Color {
        SettingsHexColor.color(from: store.prefs.borderColorHex)
            ?? Color(nsColor: .controlAccentColor)
    }

    var body: some View {
        SettingsSection("Window border") {
            SettingsToggleRow(
                title: "Show a window border",
                isOn: store.binding(\.borderEnabled)
            )

            SettingsSegmentedRow(
                title: "Scope",
                selection: store.binding(\.borderScope),
                options: [
                    SettingsOption("Focused window", BorderScope.focused),
                    SettingsOption("Every window", BorderScope.all),
                ],
                isEnabled: store.prefs.borderEnabled,
                width: 250
            )

            SettingsSliderRow(
                title: "Thickness",
                value: store.binding(\.borderWidth).settingsDouble,
                range: 1...6,
                step: 1,
                valueText: { "\(Int($0)) pt" },
                isEnabled: store.prefs.borderEnabled
            )

            SettingsSliderRow(
                title: "Opacity",
                value: store.binding(\.borderOpacity),
                range: 0.2...1,
                step: 0.05,
                valueText: { "\(Int(($0 * 100).rounded()))%" },
                isEnabled: store.prefs.borderEnabled
            )

            SettingsColorRow(
                title: "Colour",
                hex: store.prefs.borderColorHex,
                isEnabled: store.prefs.borderEnabled
            ) { hex in
                store.update { $0.borderColorHex = hex }
            }

            SettingsContentRow(showsDivider: false) {
                SettingsBorderPreview(
                    width: store.prefs.borderWidth,
                    opacity: store.prefs.borderOpacity,
                    color: borderColor,
                    scope: store.prefs.borderScope
                )
                .frame(height: 96)
                .opacity(store.prefs.borderEnabled ? 1 : 0.45)
            }
        }
    }
}

// MARK: - Motion

struct MotionSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        SettingsSection("Motion") {
            SettingsToggleRow(
                title: "Animate layout changes",
                isOn: store.binding(\.animate)
            )

            SettingsSegmentedRow(
                title: "Curve",
                selection: store.binding(\.animationCurve),
                options: AnimationCurve.allCases.map { SettingsOption($0.title, $0) },
                isEnabled: store.prefs.animate,
                width: 264
            )

            SettingsSliderRow(
                title: "Duration",
                value: store.binding(\.animationDuration),
                range: 0...0.4,
                step: 0.01,
                valueText: { "\(Int(($0 * 1000).rounded())) ms" },
                isEnabled: store.prefs.animate
            )

            SettingsToggleRow(
                title: "Animate snaps",
                isOn: store.binding(\.animateSnap),
                isEnabled: store.prefs.animate
            )

            SettingsToggleRow(
                title: "Animate swaps",
                isOn: store.binding(\.animateLayoutSwaps),
                isEnabled: store.prefs.animate
            )

            SettingsContentRow(showsDivider: false) {
                InlineHint(
                    text: "Reduce Motion in System Settings makes every change instant.",
                    symbol: "figure.walk.motion"
                )
            }
        }
    }
}
