import AppKit
import SwiftUI
import LatticeKit

// MARK: - Controller

/// Fullscreen shortcut overlay. Shown by `.latticeShowCheatSheet` and by the same
/// hotkey again. It is a non-activating panel, so Esc or a click returns the user
/// to exactly the app they were in.
@MainActor
public final class CheatSheetController: NSObject {

    public static let shared = CheatSheetController()

    public private(set) var isVisible = false

    private var model: AppModel?
    private var panel: CheatSheetPanel?
    private var previousApp: NSRunningApplication?
    private weak var previousKeyWindow: NSWindow?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private override init() {
        super.init()
    }

    public func configure(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
    }

    public func toggle() {
        if isVisible { dismiss() } else { show() }
    }

    public func show() {
        guard !isVisible else { return }
        let model = self.model ?? AppModel.shared
        self.model = model

        let screen = SurfaceScreen.pointer
        let panel = makePanel(model: model, frame: screen.frame)
        self.panel = panel
        previousApp = NSWorkspace.shared.frontmostApplication
        previousKeyWindow = NSApp.keyWindow

        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        installEscapeMonitors()
    }

    public func dismiss() {
        guard isVisible else { return }
        isVisible = false
        removeEscapeMonitors()

        panel?.orderOut(nil)
        panel = nil

        // We never activated Lattice, so the system normally hands key focus back
        // by itself. If it does not (because Lattice happened to be active), put
        // the user's previous app back in front explicitly.
        if let previousApp,
           previousApp.bundleIdentifier != Bundle.main.bundleIdentifier,
           !previousApp.isTerminated {
            previousApp.activate()
        } else if NSApp.isActive,
                  let previous = previousKeyWindow,
                  previous.isVisible {
            previous.makeKey()
        }
        previousApp = nil
        previousKeyWindow = nil
    }

    // MARK: Panel

    private func makePanel(model: AppModel, frame: NSRect) -> CheatSheetPanel {
        let panel = CheatSheetPanel(contentRect: frame,
                                    styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered,
                                    defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = false
        panel.title = "Lattice Shortcuts"
        panel.onDismiss = { [weak self] in self?.dismiss() }

        let host = NSHostingView(rootView: CheatSheetView(model: model) { [weak self] in
            self?.dismiss()
        })
        host.autoresizingMask = [.width, .height]
        host.setAccessibilityLabel("Lattice shortcut cheat sheet")
        panel.contentView = host
        return panel
    }

    // MARK: Esc fallback

    private func installEscapeMonitors() {
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            var handled = false
            MainActor.assumeIsolated {
                handled = self.handleDismiss(event)
            }
            return handled ? nil : event
        }

        // If the panel could not become key (another app is frontmost), the only
        // way to see Esc is a global monitor. It requires the same Accessibility
        // trust Lattice already needs, and it is removed on dismiss.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return }
            Task { @MainActor in self.dismiss() }
        }
    }

    private func removeEscapeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handleDismiss(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            dismiss()
            return true
        case .keyDown:
            guard event.keyCode == 53 else { return false }
            dismiss()
            return true
        default:
            return false
        }
    }
}

// MARK: - Panel

final class CheatSheetPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }
}

// MARK: - Model

struct CheatSheetRow: Identifiable {
    let id: String
    let title: String
    let combo: KeyCombo
}

struct CheatSheetGroup: Identifiable {
    let category: CommandCategory
    let rows: [CheatSheetRow]

    var id: String { category.rawValue }

    var estimatedHeight: CGFloat { 26 + CGFloat(rows.count) * 24 }
}

// MARK: - View

struct CheatSheetView: View {
    @ObservedObject var model: AppModel
    var dismiss: () -> Void

    private var groups: [CheatSheetGroup] {
        let bindings = model.prefs.prefs.bindings
        return CommandCategory.allCases.compactMap { category in
            let rows = CommandID.allCases
                .filter { $0.category == category }
                .compactMap { command -> CheatSheetRow? in
                    guard let combo = bindings[command] else { return nil }
                    return CheatSheetRow(id: command.rawValue, title: command.title, combo: combo)
                }
            guard !rows.isEmpty else { return nil }
            return CheatSheetGroup(category: category, rows: rows)
        }
    }

    private var columns: [[CheatSheetGroup]] {
        let groups = groups
        let count = 3
        var buckets = Array(repeating: [CheatSheetGroup](), count: count)
        var heights = Array(repeating: CGFloat(0), count: count)
        for group in groups {
            var target = 0
            for index in 1..<count where heights[index] < heights[target] {
                target = index
            }
            buckets[target].append(group)
            heights[target] += group.estimatedHeight
        }
        return buckets
    }

    var body: some View {
        ZStack {
            SurfaceVisualEffect(material: .hudWindow,
                                blending: .behindWindow,
                                appearance: .vibrantDark)
            Color.black.opacity(0.22)
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if columns.allSatisfy(\.isEmpty) {
                        emptyState
                    } else {
                        HStack(alignment: .top, spacing: 32) {
                            ForEach(0..<columns.count, id: \.self) { index in
                                column(columns[index])
                            }
                        }
                    }
                }
                .padding(.horizontal, 56)
                .padding(.top, 48)
                .padding(.bottom, 44)
                .frame(maxWidth: 1320, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lattice shortcut cheat sheet. Press Escape or click to close.")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Lattice — all shortcuts")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                Text("Press")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                SurfaceKeyCap(text: "esc", size: 10)
                Text("to close")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func column(_ groups: [CheatSheetGroup]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups) { group in
                groupCard(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupCard(_ group: CheatSheetGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.category.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .padding(.bottom, 5)
                .accessibilityAddTraits(.isHeader)

            ForEach(group.rows) { row in
                HStack(spacing: 14) {
                    Text(row.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    SurfaceKeyCombo(combo: row.combo, size: 10.5)
                }
                .frame(height: 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.title), \(row.combo.display)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: SurfaceTokens.hairline)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No shortcuts are bound")
                .font(.system(size: 13, weight: .medium))
            Text("Open Lattice ▸ Shortcuts to record a binding.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }
}
