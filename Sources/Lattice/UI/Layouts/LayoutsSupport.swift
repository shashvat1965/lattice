import SwiftUI
import LatticeKit

// MARK: - Preferences mirror

/// A redraw trigger for the page, not a second copy of the preferences.
///
/// `PreferencesStore` is not observable, so the page keeps this small mirror up to date
/// every time a row writes. Every setter still goes through `PreferencesStore.shared`,
/// which is why the tiler and the menu bar see the change on the same pass.
final class LayoutsPreferences: ObservableObject {

    @Published private(set) var prefs: Preferences

    init() {
        prefs = PreferencesStore.shared.prefs
    }

    func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(
            get: { self.prefs[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }

    func update(_ mutate: (inout Preferences) -> Void) {
        PreferencesStore.shared.update(mutate)
        prefs = PreferencesStore.shared.prefs
    }

    func refresh() {
        let latest = PreferencesStore.shared.prefs
        if latest != prefs { prefs = latest }
    }
}

// MARK: - Layout kinds

extension LayoutKind {
    /// The layouts that own a control of their own under the picker.
    var hasTuning: Bool {
        switch self {
        case .master, .stack, .grid: return true
        default: return false
        }
    }
}

// MARK: - Section

/// One uppercase header, one card, and an optional row that trails the card.
struct LayoutsSection<Content: View, Footer: View>: View {

    var title: String
    private let content: Content
    private let footer: Footer

    init(_ title: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xs) {
            SectionHeader(title)

            Card(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
            }

            footer
        }
    }
}

extension LayoutsSection where Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content) { EmptyView() }
    }
}

// MARK: - Row

/// One native-height row inside a `LayoutsSection`, at the standard gutter.
struct LayoutsRow<Control: View>: View {

    var title: String
    var showsDivider: Bool
    private let control: Control

    init(_ title: String, showsDivider: Bool = true, @ViewBuilder control: () -> Control) {
        self.title = title
        self.showsDivider = showsDivider
        self.control = control()
    }

    var body: some View {
        SettingRow(title, showsDivider: showsDivider) {
            control
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
    }
}

// MARK: - Slider

/// A slider and its live value, sized for the trailing slot of a `SettingRow`.
struct LayoutsSlider: View {

    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var label: String
    var valueText: (Double) -> String

    var body: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            LatticeSlider(value: $value, in: range, step: step)
                .frame(width: 184)
                .accessibilityLabel(label)
                .accessibilityValue(valueText(value))

            Text(valueText(value))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Toggle

/// A native switch for the trailing slot of a `SettingRow`.
struct LayoutsToggle: View {

    @Binding var isOn: Bool
    var label: String

    var body: some View {
        LatticeSwitch(isOn: $isOn)
            .accessibilityLabel(label)
    }
}

// MARK: - Layout menu

/// One layout, chosen from a menu. Used for a Space's own layout and for the default.
struct LayoutsLayoutPicker: View {

    @Binding var selection: LayoutKind
    var label: String
    var width: CGFloat = 132

    var body: some View {
        LatticeMenuButton(
            selection: $selection,
            options: LayoutKind.allCases.map { (value: $0, title: $0.title) }
        )
        .frame(width: width)
        .accessibilityLabel(label)
        .accessibilityValue(selection.title)
    }
}
