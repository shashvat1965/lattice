import AppKit
import SwiftUI

/// A physical-looking key cap. Two stacked rounded rects: a dark base that reads as
/// depth, and a gradient face with a hairline border. Text is SF Mono so ⌃⌥⇧⌘ align.
struct KeyCap: View {

    enum Emphasis {
        case standard, accent
    }

    var text: String
    var emphasis: Emphasis = .standard
    var compact: Bool = false

    @Environment(\.colorScheme) private var scheme

    private var fontSize: CGFloat { compact ? 10 : 11 }
    private var capHeight: CGFloat { compact ? 18 : 22 }
    private var radius: CGFloat { compact ? 4 : 5.5 }

    var body: some View {
        let faceRadius = radius
        Text(text)
            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, compact ? 4.5 : 6.5)
            .frame(minWidth: capHeight + 2, minHeight: capHeight)
            .background {
                ZStack(alignment: .top) {
                    // Base: the part of the key that sits in the keyboard.
                    RoundedRectangle(cornerRadius: faceRadius, style: .continuous)
                        .fill(baseColor)
                        .offset(y: 1.5)

                    // Face.
                    RoundedRectangle(cornerRadius: faceRadius, style: .continuous)
                        .fill(faceGradient)
                        .overlay {
                            RoundedRectangle(cornerRadius: faceRadius, style: .continuous)
                                .strokeBorder(borderColor, lineWidth: LatticeTheme.hairline)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: faceRadius - 0.5, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(scheme == .dark ? 0.10 : 0.65),
                                    lineWidth: 1
                                )
                                .padding(0.5)
                        }
                }
            }
            .padding(.bottom, 1.5)
            .accessibilityLabel(text)
    }

    private var foreground: Color {
        switch emphasis {
        case .standard: return .primary.opacity(scheme == .dark ? 0.92 : 0.82)
        case .accent: return .white
        }
    }

    private var faceGradient: LinearGradient {
        switch emphasis {
        case .standard:
            let top = scheme == .dark ? Color(white: 0.33) : Color(white: 1.0)
            let bottom = scheme == .dark ? Color(white: 0.22) : Color(white: 0.93)
            return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        case .accent:
            return LinearGradient(
                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var baseColor: Color {
        switch emphasis {
        case .standard:
            return .black.opacity(scheme == .dark ? 0.55 : 0.16)
        case .accent:
            return .accentColor.opacity(0.45)
        }
    }

    private var borderColor: Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.14)
    }
}

/// A compact row of key caps, e.g. `⌃⌥H` shown as one or several caps.
struct KeyCapGroup: View {
    var keys: [String]
    var compact: Bool = true

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(text: key, compact: compact)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}
