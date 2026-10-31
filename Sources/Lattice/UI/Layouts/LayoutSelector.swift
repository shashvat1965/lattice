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

    /// The real number of windows on this Space, so every thumbnail is honest.
    private var windowCount: Int {
        let tiled = model.tiler.tiledWindows(on: model.focusedSpace)
        if !tiled.isEmpty { return tiled.count }
        return (model.windowsBySpace[model.focusedSpace] ?? [])
            .filter { !$0.isMinimized && !$0.isFloating && !$0.isFullscreen }
            .count
    }

    var body: some View {
        HStack(alignment: .top, spacing: LatticeTheme.Spacing.xs) {
            ForEach(LayoutKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 0) {
                    LayoutChoiceCard(
                        kind: kind,
                        count: windowCount,
                        isSelected: kind == selected
                    ) {
                        model.setLayout(kind)
                    }

                    if kind == selected && kind.hasTuning {
                        LayoutTuning(kind: kind, model: model, prefs: prefs)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: LatticeTheme.Spacing.xxs) {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }

            control
        }
        .padding(.top, 6)
        .padding(.horizontal, 2)
        .animation(LatticeTheme.animation, value: valueText)
    }

    @ViewBuilder
    private var control: some View {
        switch kind {
        case .master:
            Slider(value: masterRatio, in: 0.40...0.80, step: 0.01)
                .controlSize(.small)
                .accessibilityLabel("Master share")
                .accessibilityValue(valueText)
        case .stack:
            Slider(value: stackPeek, in: 0...40, step: 1)
                .controlSize(.small)
                .accessibilityLabel("Stack peek")
                .accessibilityValue(valueText)
        case .grid:
            Picker("Columns", selection: gridColumns) {
                Text("Automatic").tag(0)
                ForEach(1...8, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
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
