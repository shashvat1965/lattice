import SwiftUI
import AppKit
import LatticeKit

// MARK: - Section container

/// One settings section: an uppercase header, a card of native rows, and at most one
/// sentence underneath. The card is the only thing on the page; there are no tabs.
struct SettingsSection<Content: View, Trailing: View>: View {
    var title: String
    var subtitle: String?
    var footnote: String?
    private let content: Content
    private let trailing: Trailing

    init(_ title: String,
         subtitle: String? = nil,
         footnote: String? = nil,
         @ViewBuilder content: () -> Content,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.footnote = footnote
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xs) {
            SectionHeader(title, subtitle: subtitle) {
                trailing
            }

            Card(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
                .padding(.vertical, 2)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityLabel(footnote)
            }
        }
    }
}

extension SettingsSection where Trailing == EmptyView {
    init(_ title: String,
         subtitle: String? = nil,
         footnote: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, footnote: footnote, content: content) {
            EmptyView()
        }
    }
}

// MARK: - Toggle row

struct SettingsToggleRow: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var showsDivider: Bool = true
    var isEnabled: Bool = true

    var body: some View {
        SettingRow(title, subtitle: subtitle, showsDivider: showsDivider) {
            LatticeSwitch(isOn: $isOn)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(LatticeTheme.animation, value: isEnabled)
    }
}

// MARK: - Slider row

struct SettingsSliderRow: View {
    var title: String
    var subtitle: String?
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var valueText: (Double) -> String
    var showsDivider: Bool = true
    var isEnabled: Bool = true

    var body: some View {
        SettingRow(title, subtitle: subtitle, showsDivider: showsDivider) {
            HStack(spacing: LatticeTheme.Spacing.xs) {
                LatticeSlider(value: $value, in: range, step: step)
                    .frame(width: 184)
                    .disabled(!isEnabled)
                    .accessibilityLabel(title)
                    .accessibilityValue(valueText(value))

                Text(valueText(value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(LatticeTheme.animation, value: isEnabled)
    }
}

// MARK: - Picker rows

struct SettingsOption<Value: Hashable>: Identifiable {
    var title: String
    var value: Value
    var id: Value { value }

    init(_ title: String, _ value: Value) {
        self.title = title
        self.value = value
    }
}

struct SettingsPickerRow<Value: Hashable>: View {
    var title: String
    var subtitle: String?
    @Binding var selection: Value
    var options: [SettingsOption<Value>]
    var showsDivider: Bool = true
    var isEnabled: Bool = true
    var width: CGFloat = 178

    var body: some View {
        SettingRow(title, subtitle: subtitle, showsDivider: showsDivider) {
            LatticeMenuButton(
                selection: $selection,
                options: options.map { (value: $0.value, title: $0.title) }
            )
            .frame(width: width)
            .disabled(!isEnabled)
            .accessibilityLabel(title)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(LatticeTheme.animation, value: isEnabled)
    }
}

struct SettingsSegmentedRow<Value: Hashable>: View {
    var title: String
    var subtitle: String?
    @Binding var selection: Value
    var options: [SettingsOption<Value>]
    var showsDivider: Bool = true
    var isEnabled: Bool = true
    var width: CGFloat = 280

    var body: some View {
        SettingRow(title, subtitle: subtitle, showsDivider: showsDivider) {
            LatticeSegmented(
                selection: $selection,
                options: options.map { (value: $0.value, title: $0.title) }
            )
            .frame(width: width)
            .disabled(!isEnabled)
            .accessibilityLabel(title)
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(LatticeTheme.animation, value: isEnabled)
    }
}

// MARK: - Content row

/// A full-width row for previews and small editors that do not fit the title/control shape.
struct SettingsContentRow<Content: View>: View {
    var title: String?
    var subtitle: String?
    var showsDivider: Bool = true
    private let content: Content

    init(title: String? = nil,
         subtitle: String? = nil,
         showsDivider: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.showsDivider = showsDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xs) {
                if let title {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                content
            }
            .padding(.horizontal, LatticeTheme.Spacing.md)
            .padding(.vertical, LatticeTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDivider {
                LatticeDivider(insetLeading: LatticeTheme.Spacing.md)
            }
        }
    }
}

// MARK: - Disclosure header

/// A quiet, full-width button that reveals advanced controls underneath the row.
struct SettingsDisclosureRow: View {
    var title: String
    var subtitle: String?
    var isExpanded: Bool
    var showsDivider: Bool = true
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: LatticeTheme.Spacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, LatticeTheme.Spacing.md)
                .frame(minHeight: LatticeTheme.listRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide these controls")

            if showsDivider {
                LatticeDivider(insetLeading: LatticeTheme.Spacing.md)
            }
        }
        .animation(LatticeTheme.animation, value: isExpanded)
    }
}

// MARK: - Action row

/// A whole row that is one action. Launchers read as launchers, not as a title with a
/// button stuck to the right of it.
struct SettingsActionRow: View {
    var title: String
    var symbol: String = "arrow.up.forward"
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    var showsDivider: Bool = true
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: LatticeTheme.Spacing.sm) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isDestructive ? Color(nsColor: .systemRed) : Color.primary)

                    Spacer(minLength: 0)

                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, LatticeTheme.Spacing.md)
                .frame(minHeight: LatticeTheme.listRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)

            if showsDivider {
                LatticeDivider(insetLeading: LatticeTheme.Spacing.md)
            }
        }
    }
}

// MARK: - Colour

enum SettingsHexColor {
    /// Six colours, not a colour wheel. The well beside the menu is for anything else.
    static let palette: [(name: String, hex: String)] = [
        ("Red", "#FF3B30"),
        ("Orange", "#FF9500"),
        ("Yellow", "#FFCC00"),
        ("Green", "#34C759"),
        ("Blue", "#007AFF"),
        ("Purple", "#AF52DE"),
    ]

    static func color(from hex: String?) -> Color? {
        guard let hex, let ns = nsColor(from: hex) else { return nil }
        return Color(nsColor: ns)
    }

    static func nsColor(from hex: String) -> NSColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    static func hex(from color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
    }

    static func name(for hex: String?) -> String {
        guard let hex else { return "System accent" }
        return palette.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? "Custom"
    }
}

/// One menu (system accent plus six colours) and a colour well. A nil value is the accent.
struct SettingsColorRow: View {
    var title: String
    var subtitle: String?
    var hex: String?
    var showsDivider: Bool = true
    var isEnabled: Bool = true
    var onChange: (String?) -> Void

    private var currentColor: Color {
        SettingsHexColor.color(from: hex) ?? Color(nsColor: .controlAccentColor)
    }

    var body: some View {
        SettingRow(title, subtitle: subtitle, showsDivider: showsDivider) {
            HStack(spacing: LatticeTheme.Spacing.sm) {
                Menu {
                    Button {
                        onChange(nil)
                    } label: {
                        if hex == nil {
                            Label("System accent", systemImage: "checkmark")
                        } else {
                            Text("System accent")
                        }
                    }

                    Divider()

                    ForEach(Array(SettingsHexColor.palette.enumerated()), id: \.offset) { _, entry in
                        Button {
                            onChange(entry.hex)
                        } label: {
                            if hex?.caseInsensitiveCompare(entry.hex) == .orderedSame {
                                Label(entry.name, systemImage: "checkmark")
                            } else {
                                Text(entry.name)
                            }
                        }
                    }
                } label: {
                    swatchLabel
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!isEnabled)
                .accessibilityLabel("Border colour, \(SettingsHexColor.name(for: hex))")

                ColorPicker(
                    "Custom colour",
                    selection: Binding(
                        get: { currentColor },
                        set: { colour in
                            if let value = SettingsHexColor.hex(from: colour) {
                                onChange(value)
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 26)
                .disabled(!isEnabled)
                .help("Choose any colour")
                .accessibilityLabel("Choose a custom border colour")
            }
        }
        .padding(.horizontal, LatticeTheme.Spacing.md)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(LatticeTheme.animation, value: isEnabled)
    }

    private var swatchLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(currentColor)
                .frame(width: 13, height: 13)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))

            Text(SettingsHexColor.name(for: hex))
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .fill(Color.latticeCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        )
    }
}

// MARK: - Live previews

/// Two miniature windows with the real border width, opacity and colour applied.
struct SettingsBorderPreview: View {
    var width: CGFloat
    var opacity: Double
    var color: Color
    var scope: BorderScope

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 6
            let gap: CGFloat = 10
            let canvas = CGRect(origin: .zero, size: geo.size).insetBy(dx: inset, dy: inset)
            let tileWidth = (canvas.width - gap) / 2

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor))

                ForEach(0..<2, id: \.self) { index in
                    let focused = index == 0
                    let outlined = scope == .all || focused
                    let rect = CGRect(
                        x: canvas.minX + CGFloat(index) * (tileWidth + gap),
                        y: canvas.minY,
                        width: tileWidth,
                        height: canvas.height
                    )

                    miniWindow(rect: rect,
                               focused: focused,
                               outlined: outlined,
                               radius: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                    .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scope == .all
                            ? "Preview: every window has a border"
                            : "Preview: only the focused window has a border")
    }

    private func miniWindow(rect: CGRect, focused: Bool, outlined: Bool, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(focused ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        outlined ? color.opacity(opacity) : Color.primary.opacity(0.09),
                        lineWidth: outlined ? max(1, width) : LatticeTheme.hairline
                    )
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.primary.opacity(0.16))
                    .frame(width: max(0, rect.width - 14), height: 4)
                    .padding(.leading, 7)
                    .padding(.top, 7)
            }
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .offset(x: rect.minX, y: rect.minY)
    }
}

// MARK: - Binding conveniences

extension Binding where Value == CGFloat {
    /// Sliders work in Double; preferences keep points as CGFloat.
    var settingsDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = CGFloat($0) }
        )
    }
}

extension Binding where Value == Int {
    /// Sliders work in Double; preferences keep millisecond counts as Int.
    var settingsDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Int($0.rounded()) }
        )
    }
}
