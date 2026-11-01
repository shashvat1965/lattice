import AppKit
import SwiftUI
import LatticeKit

// MARK: - Tabs

public enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case welcome, overview, spaces, layouts, shortcuts, settings, rules, about

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .overview: "Overview"
        case .spaces: "Spaces"
        case .layouts: "Layouts"
        case .shortcuts: "Shortcuts"
        case .settings: "Settings"
        case .rules: "Apps"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .overview: "square.grid.2x2"
        case .spaces: "rectangle.on.rectangle"
        case .layouts: "rectangle.split.3x1"
        case .shortcuts: "keyboard"
        case .settings: "gearshape"
        case .rules: "app.badge"
        case .about: "info.circle"
        }
    }

    /// The rows that actually live in the sidebar, in order.
    static var sidebarPrimary: [MainTab] { [.overview, .layouts] }
    static var sidebarConfiguration: [MainTab] { [.shortcuts, .settings] }

    /// Tabs the shell knows how to show, even when there is no sidebar row for them.
    static func resolved(_ tab: MainTab) -> MainTab {
        tab == .welcome ? .overview : tab
    }
}

// MARK: - Shell state

@MainActor
final class LatticeWindowState: ObservableObject {
    @Published var tab: MainTab

    init(tab: MainTab = .overview) {
        self.tab = MainTab.resolved(tab)
    }
}

// MARK: - Window controller

final class MainWindowController: NSWindowController {

    private let model: AppModel
    private let state: LatticeWindowState
    private var hosting: NSHostingController<MainWindowView>?

    init(model: AppModel) {
        self.model = model
        self.state = LatticeWindowState(tab: .overview)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Lattice"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 900, height: 640)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor

        super.init(window: window)

        let root = MainWindowView(model: model, state: state)
        hosting = NSHostingController(rootView: root)
        window.contentViewController = hosting

        window.setFrameAutosaveName("LatticeMainWindow")
        // Follow the user: a window left on another Space can never become key, which makes
        // the app look like it refuses to come to the front.
        window.collectionBehavior = [.moveToActiveSpace, .managed, .participatesInCycle]
        if !window.setFrameUsingName("LatticeMainWindow") {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(tab: MainTab) {
        state.tab = MainTab.resolved(tab)
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Shell

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: LatticeWindowState

    @State private var showComponents = false

    private var selection: Binding<MainTab?> {
        Binding(
            get: { state.tab },
            set: { if let new = $0 { state.tab = new } }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(LatticeTheme.sidebarWidth)
        } detail: {
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.latticeCanvas)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 640)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showComponents) {
            PreviewGallery()
                .frame(minWidth: 900, minHeight: 640)
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["LATTICE_SHOW_COMPONENTS"] == "1" {
                showComponents = true
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: selection) {
            // Four rows, no group header: a header needs at least three rows beneath it to
            // pay for its own vertical space, and this sidebar has four rows in total.
            ForEach(MainTab.sidebarPrimary + MainTab.sidebarConfiguration) { tab in
                sidebarRow(tab)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { sidebarBrand }
        .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
    }

    private func sidebarRow(_ tab: MainTab) -> some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            Label {
                Text(tab.title)
            } icon: {
                Image(systemName: tab.symbol)
                    .symbolRenderingMode(.monochrome)
            }
            Spacer(minLength: 0)
            if tab == .overview, let count = overviewCount {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .tag(tab)
    }

    private var overviewCount: Int? {
        let count = model.windowsBySpace[model.focusedSpace]?.count ?? 0
        return count > 0 ? count : nil
    }

    private var sidebarBrand: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            LatticeBrandMark(size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Lattice")
                    .font(.system(size: 13, weight: .semibold))
                Text("Window manager")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LatticeTheme.Spacing.sm)
        .padding(.top, LatticeTheme.Spacing.xs)
        .padding(.bottom, LatticeTheme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            LatticeDivider()
            HStack(spacing: LatticeTheme.Spacing.xs) {
                Circle()
                    .fill(model.isEnabled
                          ? Color(nsColor: .systemGreen)
                          : Color(nsColor: .systemOrange))
                    .frame(width: 6, height: 6)
                Text("Tiling")
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                LatticeSwitch(isOn: Binding(
                    get: { model.isEnabled },
                    set: { model.setEnabled($0) }
                ))
                .help(model.isEnabled ? "Pause tiling" : "Resume tiling")
            }
            .padding(.horizontal, LatticeTheme.Spacing.sm)
            .padding(.top, LatticeTheme.Spacing.sm)

            Button {
                state.tab = .about
            } label: {
                HStack(spacing: 4) {
                    Text("Version \(Self.appVersion)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("About Lattice")
            .accessibilityLabel("About Lattice, version \(Self.appVersion)")
            .padding(.horizontal, LatticeTheme.Spacing.sm)
            .padding(.top, 3)
            .padding(.bottom, LatticeTheme.Spacing.xs)
        }
        .background(.clear)
    }

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, build != short { return "\(short) (\(build))" }
        return short
    }

    // MARK: Detail

    @ViewBuilder
    private var detailPane: some View {
        switch state.tab {
        case .welcome, .overview:
            Overview(model: model)
        case .spaces:
            // Spaces is now part of Overview; this case survives for old notifications only.
            Overview(model: model)
        case .layouts:
            LayoutsGallery(model: model)
        case .shortcuts:
            ShortcutsPane()
        case .rules:
            // App rules now live inside Settings.
            SettingsPane()
        case .settings:
            SettingsPane()
        case .about:
            AboutPane()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.setEnabled(!model.isEnabled)
            } label: {
                Image(systemName: model.isEnabled ? "pause.fill" : "play.fill")
            }
            .help(model.isEnabled ? "Pause tiling" : "Resume tiling")

            Button {
                NotificationCenter.default.post(name: .latticeShowPalette, object: nil)
            } label: {
                Image(systemName: "command")
            }
            .help("Command palette")
        }
    }
}
