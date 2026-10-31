import SwiftUI
import AppKit
import ServiceManagement
import LatticeKit

// MARK: - SettingsPane

/// One scrolling page. Seven sections, in the order people reach for them. No tabs and
/// no sidebar of its own: the window already has one. Every control writes through
/// PreferencesStore immediately.
@MainActor
struct SettingsPane: View {

    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    var body: some View {
        ScrollView {
            content
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

    /// Renders on its own, with no scroll view around it, so screenshots taken with
    /// `ImageRenderer` at 900 pt wide are not blank.
    @ViewBuilder var content: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
            Text("Settings")
                .latticeTitle()

            GeneralSettingsSection()
            DisplaysSettingsSection()
            SettingsAppsSection()
            PointerSettingsSection()
            BordersSettingsSection()
            MotionSettingsSection()
            AdvancedSettingsSection()
        }
        .frame(maxWidth: 880, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, LatticeTheme.gutter)
        .padding(.top, 18)
        .padding(.bottom, 40)
    }
}

// MARK: - General

struct GeneralSettingsSection: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var store = SettingsPreferences.shared

    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var loginError: String?

    var body: some View {
        SettingsSection("General", footnote: versionLine) {
            SettingsToggleRow(
                title: "Launch at login",
                isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)
            )

            SettingsToggleRow(
                title: "Show the menu bar icon",
                subtitle: "Applies the next time Lattice starts.",
                isOn: store.binding(\.showMenuBarIcon)
            )

            SettingRow("Accessibility", showsDivider: true) {
                HStack(spacing: LatticeTheme.Spacing.xs) {
                    StatusPill(
                        text: model.accessibilityGranted ? "Granted" : "Not granted",
                        tone: model.accessibilityGranted ? .positive : .warning,
                        symbol: model.accessibilityGranted ? "checkmark.circle" : "hand.raised"
                    )

                    Button("Open System Settings") {
                        SettingsLinks.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Open Accessibility settings")
                }
            }
            .padding(.horizontal, LatticeTheme.Spacing.md)

            SettingsActionRow(
                title: "Run setup again",
                symbol: "arrow.clockwise",
                showsDivider: loginError == nil
            ) {
                store.update { $0.hasCompletedOnboarding = false }
                OnboardingWindowController.show()
            }

            if let loginError {
                SettingsContentRow(showsDivider: false) {
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
        }
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        if let version {
            return "Lattice \(version)" + (build.map { " (\($0))" } ?? "")
        }
        return "Lattice, development build"
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
