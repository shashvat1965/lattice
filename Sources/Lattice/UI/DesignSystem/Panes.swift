import AppKit
import SwiftUI
import LatticeKit

/// The seam every detail pane implements. Panes read `AppModel.shared` themselves and
/// are constructed by the shell without arguments, so another module can replace one
/// without touching `MainWindow.swift`.
@MainActor
protocol LatticePane: View {
    init()
}

/// A deliberately quiet placeholder for any pane that is not implemented yet.
struct PanePlaceholder: View {
    var title: String
    var symbol: String

    var body: some View {
        VStack(spacing: LatticeTheme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("…")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Coming soon")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.latticeCanvas)
    }
}

// The four configuration panes live in their own modules; these declarations make
// the seam explicit without those files needing to know about the shell.
extension ShortcutsPane: LatticePane {}
extension AppsPane: LatticePane {}
extension SettingsPane: LatticePane {}
extension AboutPane: LatticePane {}
