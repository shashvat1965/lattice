import AppKit
import SwiftUI
import Combine
import LatticeKit

/// The floating command palette.
///
/// Presented by `.latticeShowPalette`, by ⌃⌥⌘K (hotkey subsystem) and by ⌘K while
/// the Lattice window is key. It lives in a non-activating panel, so opening it
/// never pulls focus away from the app the user was typing in.
@MainActor
public final class CommandPaletteController: NSObject, NSWindowDelegate {

    public static let shared = CommandPaletteController()

    static let width: CGFloat = 560
    static let height: CGFloat = 420

    public private(set) var isVisible = false

    private var model: AppModel?
    private var panel: PalettePanel?
    private let state = PaletteState()
    private var localKeyMonitor: Any?
    private var isRunning = false
    private weak var previousKeyWindow: NSWindow?

    private override init() {
        super.init()
    }

    // MARK: - Configuration

    /// Called once by `SurfaceCoordinator` when the status bar comes up.
    public func configure(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        state.rebuild(model: model)
        installMainWindowShortcut()
    }

    // MARK: - Presentation

    public func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    public func show() {
        let model = self.model ?? AppModel.shared
        self.model = model

        if isVisible {
            state.focusBox.focus()
            return
        }

        let panel = makePanel(model: model)
        state.rebuild(model: model)
        state.selection = 0
        state.appeared = false

        let screen = SurfaceScreen.pointer
        let size = NSSize(width: Self.width, height: Self.height)
        let idealX = screen.frame.midX - size.width / 2
        let x = min(max(screen.frame.minX + 12, idealX), screen.frame.maxX - size.width - 12)
        let idealY = screen.frame.maxY - 80 - size.height
        let y = max(screen.visibleFrame.minY + 12, idealY)

        panel.setFrame(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height),
                       display: false)
        panel.alphaValue = 1
        previousKeyWindow = NSApp.keyWindow == panel ? nil : NSApp.keyWindow
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.state.focusBox.focus()
            if SurfaceTokens.reduceMotion {
                self.state.appeared = true
            } else {
                withAnimation(SurfaceTokens.spring) {
                    self.state.appeared = true
                }
            }
        }
    }

    public func dismiss() {
        guard isVisible else { return }
        isVisible = false
        state.appeared = false
        state.selection = 0
        // Order out at once: the spring is for arriving, not for leaving, and an
        // instant close keeps focus hand-back predictable.
        panel?.orderOut(nil)

        // If Lattice itself was in front, the main window becomes key again so the
        // user is exactly where they were.
        if NSApp.isActive,
           let previous = previousKeyWindow,
           previous.isVisible,
           previous != panel {
            previous.makeKey()
        }
        previousKeyWindow = nil
    }

    // MARK: - Running

    private func run(_ row: PaletteRow) {
        guard !isRunning else { return }
        isRunning = true
        dismiss()
        let action = row.item.run
        DispatchQueue.main.async { [weak self] in
            action()
            self?.isRunning = false
        }
    }

    // MARK: - Panel

    private func makePanel(model: AppModel) -> PalettePanel {
        if let panel { return panel }

        let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.title = "Command Palette"
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.dismiss() }

        let root = CommandPaletteView(
            model: model,
            state: state,
            onRun: { [weak self] row in self?.run(row) },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        host.setAccessibilityLabel("Command palette")
        panel.contentView = host

        self.panel = panel
        return panel
    }

    // MARK: - Delegate

    public func windowDidResignKey(_ notification: Notification) {
        guard isVisible, !isRunning else { return }
        dismiss()
    }

    // MARK: - ⌘K in the main window

    private func installMainWindowShortcut() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            var handled = false
            MainActor.assumeIsolated {
                handled = self.handleLocalKey(event)
            }
            return handled ? nil : event
        }
    }

    private func handleLocalKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command,
              event.charactersIgnoringModifiers?.lowercased() == "k" else { return false }

        if isVisible {
            dismiss()
            return true
        }

        guard NSApp.isActive,
              let key = NSApp.keyWindow,
              !(key is NSPanel),
              !(key.firstResponder is NSTextView) else { return false }

        show()
        return true
    }
}

// MARK: - Panel

final class PalettePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
