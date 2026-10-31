import AppKit
import SwiftUI
import LatticeKit

// Private surface primitives for the menu-bar, palette and overlay surfaces.
//
// The shared design system (UI/DesignSystem) now owns `KeyCap`, `LayoutThumbnail`,
// `SpaceStrip` and `LatticeTheme`. Those are used wherever they fit. The only
// component duplicated here is the clickable space strip: the shared `SpaceStrip`
// is a display-only view, and the menu-bar strip must switch real Spaces.

// MARK: - Tokens

enum SurfaceTokens {
    /// 1 physical pixel on the current display.
    static var hairline: CGFloat { LatticeTheme.hairline }

    static var reduceMotion: Bool { LatticeTheme.reducesMotion }

    /// The one spring used across every surface.
    static let spring = LatticeTheme.spring

    static func motion(_ enabled: Bool? = nil) -> Animation? {
        (enabled ?? !reduceMotion) ? spring : nil
    }

    static let body = Font.system(size: 12.5)
    static let caption = Font.system(size: 11)
    static let micro = Font.system(size: 10.5)
}

// MARK: - Surfaces

struct SurfaceHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: SurfaceTokens.hairline)
            .allowsHitTesting(false)
    }
}

struct SurfaceVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var appearance: NSAppearance.Name? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        if let appearance { view.appearance = NSAppearance(named: appearance) }
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.appearance = appearance.flatMap(NSAppearance.init(named:))
        view.state = .active
    }
}

// MARK: - Key caps

struct SurfaceKeyCap: View {
    let text: String
    var size: CGFloat = 11

    var body: some View {
        KeyCap(text: text, compact: size <= 10.5)
    }
}

/// A real `KeyCombo` rendered as individual caps: ⌃ ⌥ H.
struct SurfaceKeyCombo: View {
    let combo: KeyCombo
    var size: CGFloat = 11

    private var modifiers: [KeyCombo.Modifier] {
        let order: [KeyCombo.Modifier] = [.control, .option, .shift, .command]
        return order.filter { combo.modifiers.contains($0) }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(modifiers.enumerated()), id: \.offset) { _, modifier in
                SurfaceKeyCap(text: modifier.symbol, size: size)
            }
            SurfaceKeyCap(text: KeyCombo.pretty(combo.key), size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo.display)
    }
}

// MARK: - Space strip

/// The real Spaces of one display as Mission Control-style screen pips.
///
/// This is the interactive sibling of the design system's `SpaceStrip`: clicking a
/// pip asks the WindowServer to switch, and the focused pip carries the accent rule.
struct SurfaceSpaceStrip: View {
    let spaces: [SpaceManager.DisplaySpaces]
    let focusedSpace: SpaceID
    let displayID: DisplayID?
    var onSelect: ((SpaceManager.DisplaySpaces, SpaceID) -> Void)? = nil

    private var entry: SpaceManager.DisplaySpaces? {
        spaces.first { $0.display == displayID } ?? spaces.first
    }

    private var currentSpace: SpaceID? {
        (entry?.current == focusedSpace ? entry?.current : nil) ?? entry?.current
    }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            if let entry, !entry.spaceIDs.isEmpty {
                ForEach(Array(entry.spaceIDs.enumerated()), id: \.element) { index, space in
                    let isCurrent = space == (currentSpace ?? focusedSpace)
                    SpacePip(number: index + 1, isCurrent: isCurrent) {
                        guard space != currentSpace else { return }
                        onSelect?(entry, space)
                    }
                }
            } else {
                Text("No Spaces reported")
                    .font(SurfaceTokens.micro)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 6)
        .animation(SurfaceTokens.reduceMotion ? nil : .easeOut(duration: 0.16), value: currentSpace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }
}

private struct SpacePip: View {
    let number: Int
    let isCurrent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(
                        isCurrent
                            ? AnyShapeStyle(
                                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.80)],
                                               startPoint: .top,
                                               endPoint: .bottom)
                            )
                            : AnyShapeStyle(Color.primary.opacity(hovering ? 0.16 : 0.07))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .strokeBorder(isCurrent ? Color.clear : Color.primary.opacity(0.12),
                                          lineWidth: SurfaceTokens.hairline)
                    }

                Text("\(number)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? Color.white.opacity(0.95) : Color.secondary)
            }
            .frame(width: 23, height: 15)
            .overlay(alignment: .bottom) {
                if isCurrent {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 2)
                        .offset(y: 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Space \(number)")
        .accessibilityLabel("Space \(number)")
        .accessibilityValue(isCurrent ? "Current" : "")
    }
}

// MARK: - Small controls

struct SurfaceSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.quaternary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SurfaceIconButton: View {
    let symbol: String
    let label: String
    var isOn = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.09 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(SurfaceTokens.reduceMotion ? nil : .easeOut(duration: 0.1), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Icons

@MainActor
final class SurfaceIconCache {
    static let shared = SurfaceIconCache()

    private var cache: [pid_t: NSImage] = [:]

    func icon(for pid: pid_t) -> NSImage? {
        if let cached = cache[pid] { return cached }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let image = app.icon ?? NSImage(size: NSSize(width: 16, height: 16))
        cache[pid] = image
        return image
    }
}

// MARK: - Screens and coordinate spaces

enum SurfaceScreen {
    /// The screen the pointer is on, which is where transient surfaces appear.
    static var pointer: NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    /// Height of the primary display — the origin of CG's top-left coordinate space.
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// CG global (top-left origin) → AppKit global (bottom-left origin).
    static func appKitRect(fromCG rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }
}
