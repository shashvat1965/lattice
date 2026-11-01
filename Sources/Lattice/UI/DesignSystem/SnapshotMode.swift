import SwiftUI

/// The design-review renderer draws a detached SwiftUI tree with `ImageRenderer`, which has
/// no AppKit behind it: `TextField` and `ColorPicker` come back as the OS "unsupported view"
/// yellow placeholder. This flag lets a control swap in a drawn stand-in **for the snapshot
/// only**. The running app always uses the real control, so nothing here is a fake in the UI.
private struct LatticeSnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var latticeSnapshotMode: Bool {
        get { self[LatticeSnapshotModeKey.self] }
        set { self[LatticeSnapshotModeKey.self] = newValue }
    }
}

/// A drawn, non-interactive stand-in for a search field, used by the snapshot renderer.
struct SnapshotSearchField: View {
    var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? prompt : text)
                .font(.system(size: 12))
                .foregroundStyle(text.isEmpty ? Color.secondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LatticeTheme.Spacing.xs)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .fill(Color.latticeCardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                .strokeBorder(Color.latticeHairline, lineWidth: LatticeTheme.hairline)
        )
        .accessibilityHidden(true)
    }
}

/// The real search field, with a drawn stand-in when a snapshot is being rendered.
///
/// This has to be its own `View`: a page's `content` property is evaluated *before* SwiftUI
/// installs the environment on that page, so reading `latticeSnapshotMode` from a page's own
/// `@Environment` always sees the default. A child view is mounted normally and gets it.
struct LatticeSearchField: View {
    @Binding var text: String
    var prompt: String
    var isLoading: Bool = false

    @Environment(\.latticeSnapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            SnapshotSearchField(text: text, prompt: prompt)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .accessibilityLabel(prompt)

                if isLoading {
                    ProgressView().controlSize(.small)
                } else if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, LatticeTheme.Spacing.xs)
            .frame(height: 26)
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
}

/// A drawn colour well for the snapshot renderer. The live control is a `ColorPicker`.
struct SnapshotColorWell: View {
    var color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
            .fill(color)
            .frame(width: 44, height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: LatticeTheme.Radius.sm, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: LatticeTheme.hairline)
            )
            .accessibilityHidden(true)
    }
}
