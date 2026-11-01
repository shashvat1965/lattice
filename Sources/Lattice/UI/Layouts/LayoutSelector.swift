import AppKit
import SwiftUI
import LatticeKit

/// Six layouts, drawn from the windows actually on the focused Space. Choosing one gives
/// it to that Space. The chosen card opens the controls that belong to it.
struct LayoutSelector: View {

    @ObservedObject var model: AppModel
    @ObservedObject var prefs: LayoutsPreferences

    private var selected: LayoutKind {
        model.layout(for: model.focusedSpace)
    }

    /// The real number of windows on this Space, so every thumbnail is honest — but with
    /// fewer than three windows the six cards collapse into near-identical single tiles and
    /// the selector stops telling you anything. Show at least three; the real count takes
    /// over as soon as the Space has that many.
    private var windowCount: Int {
        let tiled = model.tiler.tiledWindows(on: model.focusedSpace)
        let real = tiled.isEmpty
            ? (model.windowsBySpace[model.focusedSpace] ?? [])
                .filter { !$0.isMinimized && !$0.isFloating && !$0.isFullscreen }
                .count
            : tiled.count
        return min(max(real, 3), 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: LatticeTheme.Spacing.xs) {
                ForEach(LayoutKind.allCases) { kind in
                    LayoutChoiceCard(
                        kind: kind,
                        count: windowCount,
                        isSelected: kind == selected
                    ) {
                        model.setLayout(kind)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // The selected layout's controls sit on their own full-width row: inside a card
            // column they were narrower than their labels and truncated.
            if selected.hasTuning {
                LayoutTuning(kind: selected, model: model, prefs: prefs)
                    .padding(.top, LatticeTheme.Spacing.xs)
                    .transition(.opacity)
            }
        }
        .animation(LatticeTheme.animation, value: selected)
    }
}

// MARK: - Card

private struct LayoutChoiceCard: View {

    var kind: LayoutKind
    var count: Int
    var isSelected: Bool
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                LayoutThumbnail(kind: kind, count: count, showsFocus: true)
                    .frame(height: 78)
                    .frame(maxWidth: .infinity)
                    .animation(LatticeTheme.animation, value: count)

                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(radius: LatticeTheme.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : LatticeTheme.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(LatticeTheme.quickAnimation, value: hovering)
        .help(kind.summary)
        .accessibilityLabel("\(kind.title) layout")
        .accessibilityHint(kind.summary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor.opacity(0.9) }
        return hovering ? Color.primary.opacity(0.18) : Color.latticeHairline
    }
}

// MARK: - Tuning

/// The one control the chosen layout owns. Dwindle, Columns and Rows own none, so the
/// space under their card stays empty rather than holding a placeholder.
private struct LayoutTuning: View {

    var kind: LayoutKind
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: LayoutsPreferences

    var body: some View {
        HStack(spacing: LatticeTheme.Spacing.sm) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            control
                .frame(maxWidth: 260)

            // A menu already shows its own value; only sliders need the readout.
            if kind != .grid {
                Text(valueText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .frame(width: 70, alignment: .trailing)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, LatticeTheme.gutter)
        .padding(.vertical, LatticeTheme.Spacing.xs)
        .animation(LatticeTheme.animation, value: valueText)
    }

    @ViewBuilder
    private var control: some View {
        switch kind {
        case .master:
            LatticeSlider(value: masterRatio, in: 0.40...0.80, step: 0.01)
                .accessibilityLabel("Master share")
                .accessibilityValue(valueText)
        case .stack:
            LatticeSlider(value: stackPeek, in: 0...40, step: 1)
                .accessibilityLabel("Stack peek")
                .accessibilityValue(valueText)
        case .grid:
            LatticeMenuButton(
                selection: gridColumns,
                options: [(value: 0, title: "Automatic")]
                    + (1...8).map { (value: $0, title: "\($0)") }
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Grid columns")
            .accessibilityValue(valueText)
        default:
            EmptyView()
        }
    }

    private var label: String {
        switch kind {
        case .master: return "Master share"
        case .stack: return "Stack peek"
        case .grid: return "Grid columns"
        default: return "Columns"
        }
    }

    private var valueText: String {
        switch kind {
        case .master:
            return "\(Int((prefs.prefs.masterRatio * 100).rounded()))%"
        case .stack:
            return "\(Int(prefs.prefs.stackPeek)) pt"
        default:
            let columns = prefs.prefs.gridColumns
            return columns == 0 ? "Automatic" : "\(columns)"
        }
    }

    // MARK: Writes

    private var masterRatio: Binding<Double> {
        Binding(
            get: { prefs.prefs.masterRatio },
            set: { newValue in apply { $0.masterRatio = newValue } }
        )
    }

    private var stackPeek: Binding<Double> {
        Binding(
            get: { Double(prefs.prefs.stackPeek) },
            set: { newValue in apply { $0.stackPeek = CGFloat(newValue) } }
        )
    }

    private var gridColumns: Binding<Int> {
        Binding(
            get: { prefs.prefs.gridColumns },
            set: { newValue in apply { $0.gridColumns = newValue } }
        )
    }

    private func apply(_ mutate: (inout Preferences) -> Void) {
        PreferencesStore.shared.update(mutate)
        prefs.refresh()
        model.tiler.reconcile()
    }
}
