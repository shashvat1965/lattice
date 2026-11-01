import AppKit
import SwiftUI

// MARK: - LatticeSwitch

/// A macOS switch drawn entirely in SwiftUI.
///
/// `Toggle(...).toggleStyle(.switch)` is AppKit-backed, so `ImageRenderer` draws it as an
/// unsupported yellow rectangle. This is the same control in SwiftUI: a 38 × 22 capsule with
/// an 18 pt white knob, the system accent when on, and a quarter-label track when off.
///
/// The whole control (and its label, when it has one) is the hit target. It is focusable and
/// toggles with Space, and it hands VoiceOver a real `Toggle` through
/// `accessibilityRepresentation`.
struct LatticeSwitch: View {

    @Binding private var isOn: Bool
    private let label: String?

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    private static let width: CGFloat = 38
    private static let height: CGFloat = 22
    private static let knob: CGFloat = 18
    private static let inset: CGFloat = 2

    init(isOn: Binding<Bool>, label: String? = nil) {
        self._isOn = isOn
        self.label = label
    }

    var body: some View {
        Group {
            if let label {
                HStack(spacing: LatticeTheme.Spacing.xs) {
                    Text(label)
                        .lineLimit(1)
                    control
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
            } else {
                control
            }
        }
        .opacity(isEnabled ? 1 : 0.72)
        .focusable(isEnabled)
        // The system draws a rectangular focus ring around the whole label row. A switch this
        // small does not need a permanent ring; keyboard users still toggle it with Space and
        // VoiceOver sees a real Toggle through the accessibility representation below.
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard isEnabled else { return .ignored }
            toggle()
            return .handled
        }
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) {
                if let label { Text(label) }
            }
        }
    }

    // MARK: Drawing

    private var control: some View {
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(trackFill)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(trackBorder, lineWidth: LatticeTheme.hairline)
                }

            Circle()
                .fill(knobFill)
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(scheme == .dark ? 0.22 : 0.10),
                                      lineWidth: 0.5)
                }
                .frame(width: Self.knob, height: Self.knob)
                .shadow(color: Color.black.opacity(isEnabled ? 0.30 : 0.14),
                        radius: 1.5, x: 0, y: 0.5)
                .offset(x: isOn ? Self.width - Self.knob - Self.inset : Self.inset)
        }
        .frame(width: Self.width, height: Self.height)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .animation(LatticeTheme.reducesMotion
                   ? nil
                   : .spring(response: 0.18, dampingFraction: 0.86),
                   value: isOn)
    }

    private var trackFill: Color {
        if !isEnabled {
            return Color(nsColor: .quaternaryLabelColor)
        }
        if isOn {
            return Color.accentColor
        }
        return LatticeTheme.increasesContrast
            ? Color(nsColor: .secondaryLabelColor).opacity(0.55)
            : Color(nsColor: .quaternaryLabelColor)
    }

    private var trackBorder: Color {
        if isOn {
            return Color.black.opacity(LatticeTheme.increasesContrast ? 0.22 : 0.08)
        }
        return LatticeTheme.increasesContrast
            ? Color(nsColor: .secondaryLabelColor).opacity(0.45)
            : Color.primary.opacity(0.05)
    }

    private var knobFill: Color {
        isEnabled ? Color.white : Color.white.opacity(0.85)
    }

    private func toggle() {
        guard isEnabled else { return }
        withAnimation(LatticeTheme.reducesMotion
                      ? nil
                      : .spring(response: 0.18, dampingFraction: 0.86)) {
            isOn.toggle()
        }
    }
}

// MARK: - LatticeSwitch as a ToggleStyle

/// The same switch, for places where a `Toggle`'s own row label must stay in place — the
/// label-bearing rows inside a `Form`, for example. Use `.toggleStyle(.latticeSwitch)`.
struct LatticeSwitchStyle: ToggleStyle {

    func makeBody(configuration: Configuration) -> some View {
        let isOn = Binding(
            get: { configuration.isOn },
            set: { configuration.isOn = $0 }
        )
        return HStack(spacing: LatticeTheme.Spacing.xs) {
            configuration.label
            Spacer(minLength: LatticeTheme.Spacing.xs)
            LatticeSwitch(isOn: isOn)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        // The system draws a rectangular focus ring around the whole label row; that reads as
        // a selection box around the sentence, not as focus on the switch.
        .focusEffectDisabled()
        .accessibilityRepresentation {
            Toggle(isOn: isOn) {
                configuration.label
            }
        }
    }
}

extension ToggleStyle where Self == LatticeSwitchStyle {
    /// A SwiftUI-drawn macOS switch that survives `ImageRenderer`.
    static var latticeSwitch: LatticeSwitchStyle { LatticeSwitchStyle() }
}

// MARK: - LatticeSlider

/// A macOS slider drawn entirely in SwiftUI: a 4 pt quaternary track, the accent-filled
/// portion, and a 16 pt white knob with a hairline and a shadow.
///
/// Drag anywhere on the track; arrow keys step by `step`, or by 1 % of the range when the
/// slider is continuous. Pass `showsValue: true` to put an 11 pt monospaced read-out to the
/// right of the track.
struct LatticeSlider: View {

    @Binding private var value: CGFloat
    private let range: ClosedRange<CGFloat>
    private let step: CGFloat?
    private let showsValue: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    private static let height: CGFloat = 16
    private static let knob: CGFloat = 16
    private static let track: CGFloat = 4

    init(value: Binding<CGFloat>,
         in range: ClosedRange<CGFloat>,
         step: CGFloat? = nil,
         showsValue: Bool = false) {
        self._value = value
        self.range = range
        self.step = step
        self.showsValue = showsValue
    }

    /// Convenience for the Double bindings the settings store uses.
    init(value: Binding<Double>,
         in range: ClosedRange<Double>,
         step: Double? = nil,
         showsValue: Bool = false) {
        self._value = Binding(
            get: { CGFloat(value.wrappedValue) },
            set: { value.wrappedValue = Double($0) }
        )
        self.range = CGFloat(range.lowerBound)...CGFloat(range.upperBound)
        self.step = step.map { CGFloat($0) }
        self.showsValue = showsValue
    }

    var body: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            GeometryReader { geometry in
                sliderBody(width: max(0, geometry.size.width))
            }
            .frame(height: Self.height)

            if showsValue {
                Text(formattedValue)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isEnabled ? 1 : 0.55)
        .focusable(isEnabled)
        .onKeyPress(.leftArrow) { nudge(-1) }
        .onKeyPress(.downArrow) { nudge(-1) }
        .onKeyPress(.rightArrow) { nudge(1) }
        .onKeyPress(.upArrow) { nudge(1) }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(formattedValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = nudge(1)
            case .decrement: _ = nudge(-1)
            @unknown default: break
            }
        }
    }

    // MARK: Drawing

    private func sliderBody(width: CGFloat) -> some View {
        let knobCentre = knobCentreX(width: width)
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(trackFill)
                .frame(height: Self.track)

            Capsule(style: .continuous)
                .fill(fillColor)
                .frame(width: max(0, knobCentre), height: Self.track)

            Circle()
                .fill(isEnabled ? Color.white : Color.white.opacity(0.85))
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(scheme == .dark ? 0.28 : 0.14),
                                      lineWidth: LatticeTheme.hairline * 2)
                }
                .frame(width: Self.knob, height: Self.knob)
                .shadow(color: Color.black.opacity(isEnabled ? 0.28 : 0.12),
                        radius: 1.5, x: 0, y: 0.5)
                .offset(x: knobCentre - Self.knob / 2)
        }
        .frame(width: width, height: Self.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    guard isEnabled else { return }
                    setValue(atX: gesture.location.x, width: width)
                }
        )
    }

    private var trackFill: Color {
        LatticeTheme.increasesContrast
            ? Color(nsColor: .secondaryLabelColor).opacity(0.45)
            : Color(nsColor: .quaternaryLabelColor)
    }

    private var fillColor: Color {
        isEnabled ? Color.accentColor : Color(nsColor: .tertiaryLabelColor)
    }

    // MARK: Maths

    private var span: CGFloat {
        max(range.upperBound - range.lowerBound, .ulpOfOne)
    }

    private var clampedValue: CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func knobCentreX(width: CGFloat) -> CGFloat {
        let usable = max(0, width - Self.knob)
        let progress = (clampedValue - range.lowerBound) / span
        return Self.knob / 2 + usable * min(max(progress, 0), 1)
    }

    private func setValue(atX x: CGFloat, width: CGFloat) {
        let usable = max(1, width - Self.knob)
        let progress = min(max((x - Self.knob / 2) / usable, 0), 1)
        apply(range.lowerBound + progress * span, quantise: true)
    }

    private func apply(_ proposed: CGFloat, quantise: Bool) {
        var next = min(max(proposed, range.lowerBound), range.upperBound)
        if quantise, let step, step > 0 {
            let steps = ((next - range.lowerBound) / step).rounded()
            next = range.lowerBound + steps * step
            next = min(max(next, range.lowerBound), range.upperBound)
        }
        if next != value { value = next }
    }

    private func nudge(_ direction: CGFloat) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        let delta = (step ?? span / 100) * direction
        apply(clampedValue + delta, quantise: true)
        return .handled
    }

    private var formattedValue: String {
        if let step, step >= 1 {
            return "\(Int(clampedValue.rounded()))"
        }
        return String(format: "%.2f", Double(clampedValue))
    }
}

// MARK: - LatticeSegmented

/// A macOS segmented control drawn entirely in SwiftUI: one 28 pt rounded track, a selected
/// segment in `.regularMaterial` with a hairline and a 1 pt shadow, and 12 pt medium labels.
///
/// Left and right arrows move the selection while the group has focus.
struct LatticeSegmented<Value: Hashable>: View {

    @Binding private var selection: Value
    private let options: [(value: Value, title: String)]

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    private static var height: CGFloat { 28 }

    init(selection: Binding<Value>, options: [(value: Value, title: String)]) {
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                segment(index)
            }
        }
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(trackBorder, lineWidth: LatticeTheme.hairline)
        }
        .clipShape(RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous))
        .opacity(isEnabled ? 1 : 0.55)
        .focusable(isEnabled)
        .onKeyPress(.leftArrow) {
            guard isEnabled else { return .ignored }
            move(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard isEnabled else { return .ignored }
            move(by: 1)
            return .handled
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Segments

    private func segment(_ index: Int) -> some View {
        let option = options[index]
        let active = option.value == selection

        return Button {
            guard isEnabled else { return }
            selection = option.value
        } label: {
            Text(option.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active
                                 ? AnyShapeStyle(.primary)
                                 : AnyShapeStyle(Color.primary.opacity(0.78)))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background {
                    if active {
                        selectedSegment
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var selectedSegment: some View {
        let shape = RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm - 1, style: .continuous)
        return ZStack {
            if LatticeTheme.reducesTransparency {
                shape.fill(Color(nsColor: .controlBackgroundColor))
            } else {
                shape.fill(.regularMaterial)
                shape.fill(Color.white.opacity(scheme == .dark ? 0.16 : 0.92))
            }
            shape.strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        }
        .padding(2)
        .shadow(color: Color.black.opacity(0.18), radius: 1, x: 0, y: 0.5)
    }

    private var trackBorder: Color {
        LatticeTheme.increasesContrast
            ? Color(nsColor: .separatorColor).opacity(0.9)
            : Color.latticeHairline
    }

    private func move(by delta: Int) {
        guard let index = options.firstIndex(where: { $0.value == selection }) else { return }
        let next = min(max(index + delta, 0), options.count - 1)
        guard next != index else { return }
        selection = options[next].value
    }
}

// MARK: - LatticeMenuButton

/// A pop-up menu drawn in SwiftUI, for the places a `Picker(.menu)` or `Menu` would have
/// been: those are AppKit-backed too, and render as the same unsupported yellow rectangle.
///
/// The face is SwiftUI — 22 pt tall, 6 pt radius, control fill, hairline and a chevron. The
/// menu itself is a real `NSMenu`, so behaviour is unchanged (checkmarks, keyboard tracking,
/// submenu-free items). The selected title is read straight from the binding.
struct LatticeMenuButton<Value: Hashable>: View {

    @Binding private var selection: Value
    private let options: [(value: Value, title: String)]
    private let placeholder: String

    @Environment(\.isEnabled) private var isEnabled

    @State private var target = LatticeMenuTarget()

    private static var height: CGFloat { 22 }

    init(selection: Binding<Value>,
         options: [(value: Value, title: String)],
         placeholder: String = "—") {
        self._selection = selection
        self.options = options
        self.placeholder = placeholder
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(currentTitle)
                .font(.system(size: 12))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(borderColor,
                              lineWidth: LatticeTheme.increasesContrast
                                  ? max(1, LatticeTheme.hairline * 2)
                                  : LatticeTheme.hairline * 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { present(atMouse: true) }
        .opacity(isEnabled ? 1 : 0.55)
        .focusable(isEnabled)
        .onKeyPress(.space) {
            guard isEnabled else { return .ignored }
            present(atMouse: false)
            return .handled
        }
        .onKeyPress(.return) {
            guard isEnabled else { return .ignored }
            present(atMouse: false)
            return .handled
        }
        .accessibilityRepresentation {
            Picker("", selection: $selection) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].title).tag(options[index].value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var currentTitle: String {
        options.first { $0.value == selection }?.title ?? placeholder
    }

    private var borderColor: Color {
        LatticeTheme.increasesContrast
            ? Color(nsColor: .separatorColor)
            : Color.latticeHairline
    }

    private func present(atMouse: Bool) {
        guard isEnabled else { return }

        let menu = NSMenu()
        menu.autoenablesItems = false

        target.actions = [:]
        for (index, option) in options.enumerated() {
            let item = NSMenuItem(
                title: option.title,
                action: #selector(LatticeMenuTarget.perform(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = index
            item.state = option.value == selection ? .on : .off
            target.actions[index] = { selection = option.value }
            menu.addItem(item)
        }

        let point: NSPoint
        if atMouse {
            point = NSEvent.mouseLocation
        } else if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            point = NSPoint(x: window.frame.midX, y: window.frame.midY)
        } else {
            point = NSEvent.mouseLocation
        }
        menu.popUp(positioning: nil, at: point, in: nil)
    }
}

/// Retains the menu-item actions for the lifetime of the pop-up.
private final class LatticeMenuTarget: NSObject {
    var actions: [Int: () -> Void] = [:]

    @objc func perform(_ sender: NSMenuItem) {
        actions[sender.tag]?()
    }
}
