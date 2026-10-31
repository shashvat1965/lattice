import SwiftUI
import AppKit
import LatticeKit

// MARK: - AboutPane
//
// The About page is gone from the sidebar: identity lives in the app menu, and the
// version line belongs to Settings › General. This pane only has to keep compiling for
// the shell's `.about` tab, so it shows the name, the version and nothing to press.

@MainActor
struct AboutPane: View {

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

            Text("No accounts, no telemetry, no network.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 14)

            Spacer(minLength: LatticeTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.latticeCanvas)
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
}
