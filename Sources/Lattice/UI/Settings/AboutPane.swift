import SwiftUI
import AppKit
import LatticeKit

// MARK: - AboutPane

@MainActor
struct AboutPane: View {

    @State private var confirmReset = false
    @State private var copied = false
    @State private var showComponents = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: LatticeTheme.Spacing.xl)

            LatticeBrandMark(size: 76)

            Text("Lattice")
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.35)
                .padding(.top, 18)

            Text("Every window in its place.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(versionLine)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)

            HStack(spacing: 5) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 10))
                Text("Made for macOS")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            LatticeDivider()
                .frame(width: 220)
                .padding(.vertical, 18)

            HStack(spacing: LatticeTheme.Spacing.xs) {
                Button("Open Logs") { SettingsLinks.openLogFolder() }
                    .accessibilityLabel("Open the Lattice log folder")
                Button(copied ? "Copied" : "Copy Diagnostics") { copyDiagnostics() }
                    .accessibilityLabel("Copy a diagnostics snapshot to the clipboard")
                Button("Reset…") { confirmReset = true }
                    .accessibilityLabel("Reset Lattice to defaults")
                Button("Quit Lattice") { NSApp.terminate(nil) }
                    .accessibilityLabel("Quit Lattice")
            }
            .controlSize(.regular)

            Text("No accounts, no telemetry, no network.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)

            if DesignSystemGallery.isAvailable {
                Button("Show components") { showComponents = true }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 10)
                    .accessibilityLabel("Show the interface components")
            }

            Spacer(minLength: LatticeTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.latticeCanvas)
        .confirmationDialog("Reset Lattice to defaults?", isPresented: $confirmReset) {
            Button("Reset Everything", role: .destructive) {
                SettingsPreferences.shared.resetEverything(keepingOnboarding: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Layouts, gaps, app rules and every shortcut return to their shipping values.")
        }
        .sheet(isPresented: $showComponents) {
            PreviewGallery()
                .frame(minWidth: 900, minHeight: 640)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        if let version {
            return "Version \(version)" + (build.map { " (\($0))" } ?? "")
        }
        return "Development build"
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(LatticeDiagnostics.snapshot(), forType: .string)
        withAnimation(LatticeTheme.animation) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await MainActor.run { withAnimation(LatticeTheme.animation) { copied = false } }
        }
    }
}

// MARK: - Gallery availability
//
// The design-system agent owns PreviewGallery. The button only appears when the
// linked image actually carries that type, so a stripped build without the gallery
// never shows a dead control.

enum DesignSystemGallery {
    static var isAvailable: Bool {
        sym("$s7Lattice14PreviewGalleryVMa") || sym("$s7Lattice14PreviewGalleryVN")
    }

    private static func sym(_ name: String) -> Bool {
        guard let handle = dlopen(nil, RTLD_NOW) else { return false }
        defer { dlclose(handle) }
        return dlsym(handle, name) != nil
    }
}
