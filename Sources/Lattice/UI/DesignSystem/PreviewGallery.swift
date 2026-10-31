import AppKit
import SwiftUI
import LatticeKit

/// Debug-only showcase of every design-system piece. Reached from About ▸ Show
/// components, or by launching with `LATTICE_SHOW_COMPONENTS=1`. Never in the sidebar.
struct PreviewGallery: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var model = AppModel.shared

    @State private var toggleSample = true
    @State private var pickerSample = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xl) {
                header
                typeSection
                motionSection
                shapeSection
                controlSection
                layoutSection
                spaceSection
                appSection
                statusSection
                emptySection
                permissionSection
                footer
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .padding(.horizontal, LatticeTheme.gutter)
            .padding(.vertical, LatticeTheme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.latticeCanvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: LatticeTheme.Spacing.md) {
            LatticeBrandMark(size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Components")
                    .latticeTitle()
                Text("Every token and control in the Lattice design system.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: LatticeTheme.Spacing.md)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Type

    private var typeSection: some View {
        GallerySection("Typography") {
            Card {
                VStack(alignment: .leading, spacing: LatticeTheme.Spacing.md) {
                    sampleRow("Title", sample: "Overview", style: { $0.latticeTitle() })
                    LatticeDivider()
                    sampleRow("Heading", sample: "One switch, then Lattice takes over", style: { $0.latticeHeading() })
                    LatticeDivider()
                    sampleRow("Body", sample: "Lattice keeps every window on this Space in order.", style: { $0.latticeBody() })
                    LatticeDivider()
                    sampleRow("Section header", sample: "On screen", style: { $0.latticeSectionHeader() })
                    LatticeDivider()
                    sampleRow("Caption", sample: "Live positions, scaled to each display.", style: { $0.latticeCaption() })
                    LatticeDivider()
                    sampleRow("Monospaced digits", sample: "01 · 1280 × 800 · ⌃⌥H", style: { $0.latticeBody().latticeMonoDigits() })
                }
            }
        }
    }

    private func sampleRow(_ label: String,
                           sample: String,
                           style: @escaping (Text) -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LatticeTheme.Spacing.md) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 130, alignment: .leading)
            style(Text(sample))
            Spacer(minLength: 0)
        }
    }

    // MARK: - Motion

    private var motionSection: some View {
        GallerySection("Motion & appearance") {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    SettingRow("Spring", subtitle: "response 0.34 s · damping 0.86") {
                        Text("0.34 s · 0.86")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    LatticeDivider()
                    SettingRow("Reduce Motion") {
                        Text(LatticeTheme.reducesMotion ? "On" : "Off")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    LatticeDivider()
                    SettingRow("Reduce Transparency") {
                        Text(LatticeTheme.reducesTransparency ? "On" : "Off")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    LatticeDivider()
                    SettingRow("Hairline", subtitle: "one physical pixel at the current scale") {
                        Text("\(LatticeTheme.hairline, specifier: "%.3f") pt")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    LatticeDivider()
                    SettingRow("Spacing grid", subtitle: "4 / 8 / 12 / 16 / 20 / 24 / 32") {
                        HStack(spacing: 3) {
                            ForEach([4, 8, 12, 16, 20, 24, 32], id: \.self) { value in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.55))
                                    .frame(width: CGFloat(value) * 0.6, height: 20)
                            }
                        }
                    }
                }
                .padding(.horizontal, LatticeTheme.Spacing.md)
            }
        }
    }

    // MARK: - Shape

    private var shapeSection: some View {
        GallerySection("Radii & key caps") {
            Card {
                VStack(alignment: .leading, spacing: LatticeTheme.Spacing.lg) {
                    HStack(spacing: LatticeTheme.Spacing.md) {
                        radiusSample(6, label: "6 · controls")
                        radiusSample(10, label: "10 · materials")
                        radiusSample(14, label: "14 · cards")
                        radiusSample(18, label: "18 · banners")
                    }
                    LatticeDivider()
                    HStack(spacing: LatticeTheme.Spacing.sm) {
                        KeyCap(text: "⌘")
                        KeyCap(text: "⌃⌥H")
                        KeyCap(text: "Space")
                        KeyCap(text: "⌘Z", emphasis: .accent)
                        KeyCap(text: "⌃⌥←", compact: true)
                        Spacer(minLength: 0)
                        Text("SF Mono 11 · two-layer cap")
                            .latticeFootnote()
                    }
                }
            }
        }
    }

    private func radiusSample(_ radius: CGFloat, label: String) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: LatticeTheme.hairline)
                }
                .frame(width: 64, height: 44)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Controls

    private var controlSection: some View {
        GallerySection("Settings rows") {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    SettingRow("Show menu bar icon", subtitle: "Uses the real switch style.") {
                        Toggle("", isOn: $toggleSample)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    LatticeDivider()
                    SettingRow("Animation speed") {
                        Picker("", selection: $pickerSample) {
                            Text("Fast").tag(0)
                            Text("Standard").tag(1)
                            Text("Slow").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    LatticeDivider()
                    SettingRow("Drag to swap", subtitle: "Hold a window against another to exchange places.") {
                        Button("Learn More") {}
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, LatticeTheme.Spacing.md)
            }

            InlineHint(text: "Inline hints sit directly under the control they explain.")
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Layouts

    private var layoutSection: some View {
        GallerySection("Layout thumbnails") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LatticeTheme.Spacing.sm), count: 3),
                      spacing: LatticeTheme.Spacing.sm) {
                ForEach(LayoutKind.allCases) { kind in
                    VStack(alignment: .leading, spacing: 6) {
                        LayoutThumbnail(kind: kind, count: 3)
                            .frame(height: 92)
                        Text(kind.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(8)
                    .background(CardBackground(radius: LatticeTheme.Radius.md))
                }
            }
        }
    }

    // MARK: - Spaces

    private var spaceSection: some View {
        GallerySection("Spaces") {
            Card {
                VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
                    if let entry = model.spaces.first {
                        SpaceStrip(spaces: entry.spaceIDs, current: entry.current)
                        InlineHint(text: "\(entry.spaceIDs.count) Spaces from WindowServer · current is filled.")
                    } else {
                        InlineHint(text: "WindowServer has not reported any Spaces yet.", symbol: "exclamationmark.circle")
                    }
                }
            }
        }
    }

    // MARK: - Apps

    private var appSection: some View {
        GallerySection("App tiles") {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if let window = model.windowsBySpace.values.flatMap({ $0 }).first {
                        AppTile(bundleID: window.bundleID,
                                appName: window.appName,
                                title: window.title,
                                detail: "\(Int(window.frame.width)) × \(Int(window.frame.height))")
                            .padding(.horizontal, LatticeTheme.Spacing.md)
                    } else if let app = NSWorkspace.shared.runningApplications.first(where: { $0.activationPolicy == .regular }) {
                        AppTile(bundleID: app.bundleIdentifier, appName: app.localizedName ?? "App")
                            .padding(.horizontal, LatticeTheme.Spacing.md)
                    } else {
                        AppTile(bundleID: nil, appName: "Lattice", title: "Window manager")
                            .padding(.horizontal, LatticeTheme.Spacing.md)
                    }
                    LatticeDivider()
                    HStack(spacing: LatticeTheme.Spacing.sm) {
                        MonogramTile(name: "Lattice", size: 26)
                        MonogramTile(name: "Safari", size: 26)
                        MonogramTile(name: "Xcode", size: 26)
                        Text("Monogram fallback when an app icon cannot be resolved.")
                            .latticeFootnote()
                        Spacer(minLength: 0)
                    }
                    .padding(LatticeTheme.Spacing.md)
                }
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        GallerySection("Status pills") {
            Card {
                HStack(spacing: LatticeTheme.Spacing.xs) {
                    StatusPill(text: "Tiling on", tone: .positive, showsDot: true)
                    StatusPill(text: "Tiling paused", tone: .warning, symbol: "pause.fill")
                    StatusPill(text: "Space 2 uses Columns", tone: .accent)
                    StatusPill(text: "Access needed", tone: .warning, symbol: "lock.fill")
                    StatusPill(text: "12 windows", tone: .neutral)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Empty & permission

    private var emptySection: some View {
        GallerySection("Empty state") {
            Card {
                EmptyState(
                    symbol: "macwindow.on.rectangle",
                    title: "Nothing to tile here",
                    message: "Open a window on this Space, or move one in from another Space.",
                    actionTitle: "Refresh",
                    action: {}
                )
                .frame(height: 200)
            }
        }
    }

    private var permissionSection: some View {
        GallerySection("Permission state") {
            PermissionBanner()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.xs) {
            LatticeDivider()
            Text("Reachable only from About ▸ Show components, or LATTICE_SHOW_COMPONENTS=1.")
                .latticeFootnote()
                .padding(.top, LatticeTheme.Spacing.xs)
        }
    }
}

// MARK: - Section wrapper

private struct GallerySection<Content: View>: View {
    var title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LatticeTheme.Spacing.sm) {
            SectionHeader(title)
            content
        }
    }
}
