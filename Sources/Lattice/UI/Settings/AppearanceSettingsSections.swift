import SwiftUI
import AppKit
import LatticeKit

// MARK: - Motion

struct MotionSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        SettingsSection(
            "Motion",
            subtitle: "How layouts glide into place.",
            footnote: "Motion only affects windows Lattice moves. It never animates a window you are dragging, and it never runs longer than 400 ms."
        ) {
            SettingsToggleRow(
                title: "Animate layout changes",
                subtitle: "Windows slide to their new positions instead of jumping.",
                isOn: store.binding(\.animate)
            )

            SettingsSegmentedRow(
                title: "Curve",
                subtitle: "Ease out starts quickly and settles. Ease in-out is even. Spring has a little overshoot.",
                selection: store.binding(\.animationCurve),
                options: AnimationCurve.allCases.map { SettingsOption($0.title, $0) },
                isEnabled: store.prefs.animate,
                width: 264
            )

            SettingsSliderRow(
                title: "Duration",
                subtitle: "Long enough to follow with your eye, short enough to stay out of the way.",
                value: store.binding(\.animationDuration),
                range: 0...0.4,
                step: 0.01,
                valueText: { "\(Int(($0 * 1000).rounded())) ms" },
                isEnabled: store.prefs.animate
            )

            SettingsToggleRow(
                title: "Animate snap previews",
                subtitle: "The outline that follows the pointer while you drag a window to an edge.",
                isOn: store.binding(\.animateSnap),
                isEnabled: store.prefs.animate
            )

            SettingsToggleRow(
                title: "Animate layout swaps",
                subtitle: "When two windows trade places, they travel rather than cut.",
                isOn: store.binding(\.animateLayoutSwaps),
                showsDivider: false,
                isEnabled: store.prefs.animate
            )

            SettingsContentRow(showsDivider: false) {
                if reduceMotion {
                    VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xs) {
                        HStack(spacing: LatticeTheme.Spacing.xs) {
                            StatusPill(text: "Reduce Motion is on", tone: .warning, symbol: "figure.walk.motion")
                            Spacer(minLength: 0)
                        }
                        Text("macOS has asked apps to avoid movement, so every change is instant while that setting is on. Turn it off in System Settings ▸ Accessibility ▸ Display to use these controls.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    InlineHint(
                        text: "If Reduce Motion is turned on in System Settings, Lattice makes every change instant. That system setting always wins.",
                        symbol: "figure.walk.motion"
                    )
                }
            }
        }
    }
}

// MARK: - Borders

struct BordersSettingsSection: View {
    @ObservedObject private var store = SettingsPreferences.shared

    private var borderColor: Color {
        SettingsHexColor.color(from: store.prefs.borderColorHex)
            ?? Color(nsColor: .controlAccentColor)
    }

    var body: some View {
        SettingsSection(
            "Borders",
            subtitle: "A quiet outline around the window you are working in.",
            footnote: "Borders are drawn over the window edge and never take a click. The system accent colour follows System Settings ▸ Appearance."
        ) {
            SettingsToggleRow(
                title: "Show a window border",
                subtitle: "Marks the focused window so it is obvious which one receives a shortcut.",
                isOn: store.binding(\.borderEnabled)
            )

            SettingsSliderRow(
                title: "Thickness",
                subtitle: "One point reads as a hairline; six points is clearly visible on a bright desktop.",
                value: store.binding(\.borderWidth).settingsDouble,
                range: 1...6,
                step: 1,
                valueText: { "\(Int($0)) pt" },
                isEnabled: store.prefs.borderEnabled
            )

            SettingsSliderRow(
                title: "Opacity",
                subtitle: "Lower values let the wallpaper show through the border.",
                value: store.binding(\.borderOpacity),
                range: 0.2...1,
                step: 0.05,
                valueText: { "\(Int(($0 * 100).rounded()))%" },
                isEnabled: store.prefs.borderEnabled
            )

            SettingsColorRow(
                title: "Colour",
                subtitle: "Pick one of these, use the colour well for anything else, or keep the system accent.",
                hex: store.prefs.borderColorHex,
                isEnabled: store.prefs.borderEnabled
            ) { hex in
                store.update { $0.borderColorHex = hex }
            }

            SettingsSegmentedRow(
                title: "Which windows",
                subtitle: "Focused only is quieter. Every window makes the whole layout legible at a glance.",
                selection: store.binding(\.borderScope),
                options: [
                    SettingsOption("Focused window", BorderScope.focused),
                    SettingsOption("Every window", BorderScope.all),
                ],
                isEnabled: store.prefs.borderEnabled,
                width: 250
            )

            SettingsContentRow(
                title: "Preview",
                subtitle: store.prefs.borderEnabled
                    ? "The real width, colour, opacity and scope."
                    : "Preview only — the border is off.",
                showsDivider: false
            ) {
                SettingsBorderPreview(
                    width: store.prefs.borderWidth,
                    opacity: store.prefs.borderOpacity,
                    color: borderColor,
                    scope: store.prefs.borderScope
                )
                .frame(height: 104)
                .opacity(store.prefs.borderEnabled ? 1 : 0.45)
            }
        }
    }
}
