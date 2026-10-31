import SwiftUI
import AppKit
import LatticeKit

// MARK: - SettingsPane

/// One scrolling page, grouped into cards. No tabs, no sidebar of its own: the window
/// already has one. Every control writes through PreferencesStore immediately.
@MainActor
struct SettingsPane: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
                paneHeader

                TilingSettingsSection()
                GapsSettingsSection()
                LayoutTuningSettingsSection()
                MotionSettingsSection()
                BordersSettingsSection()
                DisplaysSettingsSection()
                SpacesSettingsSection()
                InputSettingsSection()
                StartupSettingsSection()
                AdvancedSettingsSection()
            }
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, LatticeTheme.gutter)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.latticeCanvas)
        .onAppear {
            store.beginObserving()
            model.refreshSpaces()
        }
        .onDisappear {
            store.endObserving()
        }
    }

    private var paneHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Settings")
                    .latticeTitle()
                Text("Changes apply immediately. Nothing here needs a relaunch unless it says so.")
                    .latticeCaption()
            }

            Spacer(minLength: LatticeTheme.Spacing.sm)

            if !model.accessibilityGranted {
                Button("Grant Access") {
                    SettingsLinks.openAccessibilitySettings()
                }
                .controlSize(.small)
                .accessibilityLabel("Open Accessibility settings to grant Lattice access")
            }

            StatusPill(
                text: model.isEnabled ? "Tiling on" : "Tiling paused",
                tone: model.isEnabled ? .positive : .warning,
                symbol: model.isEnabled ? "rectangle.split.3x1" : "pause.circle"
            )
        }
        .accessibilityElement(children: .contain)
    }
}
