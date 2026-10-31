import AppKit
import SwiftUI
import LatticeKit

/// The Layouts page: how windows get arranged, and the Space that keeps the arrangement.
///
/// `content` sits outside the `ScrollView` on purpose. `ImageRenderer` draws a
/// `ScrollView` as blank, so design snapshots render the same tree through `content`.
struct LayoutsPage: View {

    @ObservedObject var model: AppModel
    @StateObject private var prefs = LayoutsPreferences()

    var body: some View {
        ScrollView {
            content
        }
        .background(Color.latticeCanvas)
        .onAppear { prefs.refresh() }
    }

    @ViewBuilder
    var content: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
            header
            LayoutSelector(model: model, prefs: prefs)
            LayoutSpaceSection(model: model, prefs: prefs)
            LayoutLimitsSection(prefs: prefs)
            LayoutInsertionSection(prefs: prefs)
            LayoutSpacesSection(model: model, prefs: prefs)
            footer
        }
        .frame(maxWidth: LatticeTheme.contentMaxWidth, alignment: .leading)
        .padding(.horizontal, LatticeTheme.gutter)
        .padding(.top, LatticeTheme.Spacing.lg)
        .padding(.bottom, LatticeTheme.Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Layouts")
                .latticeTitle()
            Text("Each Space keeps its own.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text("⌥Space cycles layouts.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}
