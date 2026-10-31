import AppKit
import SwiftUI
import LatticeKit

/// Guides the user through the one thing Lattice cannot do itself — adding or removing a
/// Space — without pretending it has its own workspace list.
@MainActor
final class AddSpaceGuide {

    enum Mode { case add, remove }

    static let shared = AddSpaceGuide()

    private var panel: GuidePanel?
    private var timer: Timer?
    private var baseline: [String: Int] = [:]
    private weak var model: AppModel?
    private var mode: Mode = .add
    private var opened: Date = .distantPast

    private init() {}

    func begin(mode: Mode, model: AppModel) {
        self.mode = mode
        self.model = model
        finish(silently: true)

        baseline = snapshot()
        opened = Date()
        openMissionControl()
        presentHint()
        startPolling()
    }

    func cancel() {
        finish(silently: true)
    }

    // MARK: - Mission Control

    private func openMissionControl() {
        let candidates = [
            "/System/Applications/Mission Control.app",
            "/Applications/Mission Control.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error { Log.error("could not open Mission Control: \(error.localizedDescription)") }
            }
            return
        }
        KeySynth.controlKey(126) // ⌃↑ is the keyboard route to Mission Control.
    }

    // MARK: - Hint panel

    private func presentHint() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 306, height: 92)
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 12
        )
        let panel = GuidePanel(contentRect: CGRect(origin: origin, size: size))
        panel.setContent(AnyView(GuideBody(
            title: mode == .add ? "Add a Space" : "Remove a Space",
            message: mode == .add
                ? "Click the + at the right end of the Space bar."
                : "Hover a Space at the top, then click the ✕.",
            onCancel: { AddSpaceGuide.shared.cancel() },
            onConfirm: { AddSpaceGuide.shared.confirmManually() }
        )))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func confirmManually() {
        guard let model else { return finish(silently: true) }
        model.refreshSpaces()
        finish(silently: false)
    }

    // MARK: - Detection

    private func snapshot() -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in SpaceManager.shared.displaySpaces() {
            counts[entry.displayUUID] = entry.spaceIDs.count
        }
        return counts
    }

    private func startPolling() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard Date().timeIntervalSince(opened) < 60 else {
            finish(silently: true)
            return
        }
        guard let model else { return finish(silently: true) }

        let now = SpaceManager.shared.displaySpaces()
        for entry in now {
            let before = baseline[entry.displayUUID] ?? entry.spaceIDs.count
            guard entry.spaceIDs.count != before else { continue }

            if mode == .add, entry.spaceIDs.count > before {
                // The Space exists now. Adopt it: it inherits the default layout, and we
                // jump to it so the user can keep working where they just landed.
                let newSpace = entry.spaceIDs.last!
                let prefs = PreferencesStore.shared.prefs
                Log.info("space added: \(newSpace) on \(entry.displayUUID) — layout \(prefs.layout(for: newSpace).title)")
                baseline = snapshot()
                model.refreshSpaces()
                timer?.invalidate()
                timer = nil
                panel?.close()
                panel = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    SpaceManager.shared.activate(newSpace, on: entry.display)
                }
                return
            }

            if mode == .remove, entry.spaceIDs.count < before {
                baseline = snapshot()
                model.refreshSpaces()
                finish(silently: true)
                return
            }
        }
    }

    private func finish(silently: Bool) {
        timer?.invalidate()
        timer = nil
        panel?.close()
        panel = nil
        _ = silently
    }
}

// MARK: - Panel

private final class GuidePanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    func setContent(_ view: AnyView) {
        contentView = NSHostingView(rootView: view)
    }
}

private struct GuideBody: View {
    let title: String
    let message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Done", action: onConfirm)
                        .controlSize(.small)
                    Button("Cancel", action: onCancel)
                        .controlSize(.small)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        )
    }
}

// MARK: - Window

@MainActor
final class SpacesWindowController: NSWindowController {

    private static var shared: SpacesWindowController?

    static func show(model: AppModel) {
        if shared == nil {
            shared = SpacesWindowController(model: model)
        }
        NSApp.activate(ignoringOtherApps: true)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    private init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Spaces"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 820, height: 540)
        window.setFrameAutosaveName("LatticeSpacesWindow")
        window.center()
        window.contentViewController = NSHostingController(rootView: SpacesView(model: model))
        super.init(window: window)
        window.isReleasedWhenClosed = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

extension Notification.Name {
    static let latticeShowSpaces = Notification.Name("lattice.showSpaces")
}
