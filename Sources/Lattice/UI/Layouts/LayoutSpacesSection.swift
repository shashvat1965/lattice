import AppKit
import SwiftUI
import LatticeKit

/// Every real Space, grouped by the display it lives on: its layout, its window count,
/// and which one you are looking at. This replaces the old Spaces page.
struct LayoutSpacesSection: View {

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: LayoutsPreferences

    /// The per-Space rows are a list you rarely edit, so they fold away behind one row that
    /// still reports how many Spaces exist and how many keep their own layout.
    @State private var expanded = false

    var body: some View {
        LayoutsSection("Spaces") {
            if groups.allSatisfy({ $0.rows.isEmpty }) {
                noSpacesRow
            } else {
                SettingsDisclosureRow(
                    title: summaryTitle,
                    subtitle: expanded ? nil : summarySubtitle,
                    isExpanded: expanded
                ) {
                    withAnimation(LatticeTheme.animation) { expanded.toggle() }
                }

                if expanded {
                    ForEach(groups) { group in
                        if groups.count > 1 {
                            groupHeader(group.name)
                        }

                        ForEach(group.rows) { row in
                            spaceRow(row)
                            LatticeDivider(insetLeading: LatticeTheme.Spacing.md)
                        }
                    }
                }
            }

            LayoutsRow("New Spaces start with", showsDivider: false) {
                LayoutsLayoutPicker(
                    selection: prefs.binding(\.layout),
                    label: "New Spaces start with"
                )
            }
        } footer: {
            addSpaceRow
        }
    }

    // MARK: - Summary

    private var allRows: [SpaceRow] { groups.flatMap(\.rows) }

    private var summaryTitle: String {
        let count = allRows.count
        return "\(count) \(count == 1 ? "Space" : "Spaces")"
    }

    private var summarySubtitle: String {
        let overrides = allRows.filter { prefs.prefs.hasOwnLayout($0.space) }.count
        let base = overrides == 0 ? "All use the default layout" : "\(overrides) with their own layout"
        if groups.count > 1 { return "\(base) · \(groups.count) displays" }
        return base + " · " + (groups.first?.name ?? "")
    }

    // MARK: - Rows

    private func groupHeader(_ name: String) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .padding(.top, LatticeTheme.Spacing.sm)
        .padding(.bottom, LatticeTheme.Spacing.xxs)
    }

    private func spaceRow(_ row: SpaceRow) -> some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            Text("Space \(row.index)")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 74, alignment: .leading)

            Spacer(minLength: 0)

            LayoutsLayoutPicker(
                selection: layoutBinding(for: row.space),
                label: "Layout for Space \(row.index)"
            )

            HStack(spacing: 3) {
                Image(systemName: "macwindow")
                    .font(.system(size: 9, weight: .medium))
                Text("\(row.count)")
                    .font(.system(size: 12).monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .frame(width: 36, alignment: .trailing)
            .help("\(row.count) \(row.count == 1 ? "window" : "windows")")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.count) \(row.count == 1 ? "window" : "windows")")

            currentMarker(row.isCurrent)
                .frame(width: 62, alignment: .trailing)
        }
        .frame(minHeight: 34)
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func currentMarker(_ isCurrent: Bool) -> some View {
        if isCurrent {
            HStack(spacing: LatticeTheme.Spacing.xxs) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                Text("Current")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Current Space")
        } else {
            Color.clear
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var noSpacesRow: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("No Spaces reported")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .frame(minHeight: LatticeTheme.listRow)
    }

    private var addSpaceRow: some View {
        Button {
            AddSpaceGuide.shared.begin(mode: .add, model: model)
        } label: {
            HStack(spacing: LatticeTheme.Spacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Add a Space…")
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, LatticeTheme.Spacing.md)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(
                    Color.latticeHairline,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        }
        .help("Opens Mission Control")
        .accessibilityLabel("Add a Space")
    }

    // MARK: - Model

    private func layoutBinding(for space: SpaceID) -> Binding<LayoutKind> {
        Binding(
            get: { model.layout(for: space) },
            set: { kind in
                model.setLayout(kind, for: space)
                prefs.refresh()
            }
        )
    }

    /// The Spaces a person would number, ignoring fullscreen Spaces, in Mission Control order.
    private var groups: [DisplayGroup] {
        model.spaces.map { entry in
            let spaces = entry.spaceTypes.count == entry.spaceIDs.count
                ? entry.userSpaceIDs
                : entry.spaceIDs
            let name = model.displays.first { $0.id == entry.display }?.name ?? "Display"

            let rows = spaces.enumerated().map { index, space in
                SpaceRow(
                    space: space,
                    index: index + 1,
                    count: windowCount(on: space),
                    isCurrent: space == model.focusedSpace
                )
            }

            return DisplayGroup(id: entry.display, name: name, rows: rows)
        }
    }

    private func windowCount(on space: SpaceID) -> Int {
        let tiled = model.tiler.tiledWindows(on: space).count
        if tiled > 0 { return tiled }
        return (model.windowsBySpace[space] ?? []).filter { !$0.isMinimized }.count
    }
}

// MARK: - Models

private struct SpaceRow: Identifiable {
    var id: SpaceID { space }
    let space: SpaceID
    let index: Int
    let count: Int
    let isCurrent: Bool
}

private struct DisplayGroup: Identifiable {
    let id: DisplayID
    let name: String
    let rows: [SpaceRow]
}
