import AppKit
import SwiftUI
import LatticeKit

/// Always-available HUD surfaces: transient toasts and the drag-to-snap target.
///
/// Both are single, reused, click-through, non-activating panels at
/// `.screenSaver` level. The public API is the cross-subsystem contract in
/// ARCHITECTURE.md — the hotkey agent calls `showToast` and
/// `showSnapPreview`/`hideSnapPreview`, never anything else.
@MainActor
public final class HUDController {

    public static let shared = HUDController()

    // MARK: - Geometry constants

    static let previewPadding: CGFloat = 20
    private static let toastPanelSize = NSSize(width: 620, height: 120)

    // MARK: - State

    private var started = false

    private let toasts = HUDToastModel()
    private var toastPanel: HUDPanel?
    private var toastHideWork: DispatchWorkItem?

    private let preview = HUDSnapPreviewModel()
    private var previewPanel: HUDPanel?
    private var previewVisible = false

    private init() {}

    // MARK: - Lifecycle

    /// Wires the panels up. Safe to call any number of times from anywhere.
    public func start() {
        guard !started else { return }
        started = true
        _ = makeToastPanel()
        _ = makePreviewPanel()
    }

    // MARK: - Toasts

    /// A compact capsule at the bottom of the pointer's screen: symbol, then text.
    /// Up to three stack vertically; each dismisses itself after 1.1 s.
    public func showToast(_ text: String, symbol: String? = nil) {
        start()

        let toast = HUDToastModel.Toast(id: UUID(),
                                        text: text,
                                        symbol: validSymbol(symbol))
        if toasts.items.count >= 3 {
            toasts.items.removeFirst()
        }
        withAnimation(SurfaceTokens.motion()) {
            toasts.items.append(toast)
        }

        presentToastPanel()

        let id = toast.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self else { return }
            withAnimation(SurfaceTokens.motion()) {
                self.toasts.items.removeAll { $0.id == id }
            }
            self.scheduleToastTeardown()
        }
    }

    private func presentToastPanel() {
        let panel = makeToastPanel()
        let frame = Self.toastFrame()
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
        }
        if !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
    }

    /// Keep the window around briefly so spamming toasts never blinks the panel
    /// in and out; order it out only once the stack has actually settled empty.
    private func scheduleToastTeardown() {
        toastHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.toasts.items.isEmpty else { return }
            self.toastPanel?.orderOut(nil)
        }
        toastHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func makeToastPanel() -> HUDPanel {
        if let toastPanel { return toastPanel }
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: Self.toastPanelSize),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.configureAsHUD()
        panel.ignoresMouseEvents = true
        panel.setAccessibilityLabel("Lattice notification")
        panel.setAccessibilityRole(.group)

        let host = NSHostingView(rootView: HUDToastStack(model: toasts))
        host.setAccessibilityLabel("Lattice notifications")
        panel.contentView = host

        toastPanel = panel
        return panel
    }

    private static func toastFrame() -> NSRect {
        let screen = SurfaceScreen.pointer
        let size = toastPanelSize
        let x = screen.frame.midX - size.width / 2
        let y = screen.visibleFrame.minY + 20
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func validSymbol(_ name: String?) -> String? {
        guard let name, !name.isEmpty,
              NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return nil }
        return name
    }

    // MARK: - Snap preview

    /// Shows the snap target for a global CG rect (top-left origin, same space as
    /// `DisplayInfo.frame`). Repeated calls while visible just move the frame so
    /// the preview tracks the pointer at full refresh rate.
    public func showSnapPreview(rect: CGRect, label: String? = nil) {
        start()
        guard rect.width > 1, rect.height > 1 else {
            hideSnapPreview()
            return
        }

        let panel = makePreviewPanel()
        if preview.label != label {
            preview.label = label
        }

        let target = SurfaceScreen.appKitRect(fromCG: rect)
        let padded = target.insetBy(dx: -Self.previewPadding, dy: -Self.previewPadding)

        if !previewVisible {
            panel.alphaValue = 1
            panel.setFrame(padded, display: false)
            panel.orderFrontRegardless()
            previewVisible = true

            if SurfaceTokens.reduceMotion {
                preview.appeared = true
            } else {
                preview.appeared = false
                // One tick later so the 0.97 start state is on screen before the spring.
                DispatchQueue.main.async { [weak self] in
                    withAnimation(SurfaceTokens.spring) { self?.preview.appeared = true }
                }
            }
        } else {
            // Never animate a move: the hotkey agent calls this per mouse sample.
            panel.setFrame(padded, display: true)
        }
    }

    /// Hides the snap target. Safe to call when nothing is showing.
    public func hideSnapPreview(animated: Bool = true) {
        guard let panel = previewPanel, previewVisible else { return }
        previewVisible = false
        preview.appeared = false

        if animated && !SurfaceTokens.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, !self.previewVisible else { return }
                    self.previewPanel?.orderOut(nil)
                    self.previewPanel?.alphaValue = 1
                }
            }
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    private func makePreviewPanel() -> HUDPanel {
        if let previewPanel { return previewPanel }
        let panel = HUDPanel(contentRect: .zero,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.configureAsHUD()
        panel.ignoresMouseEvents = true
        panel.setAccessibilityLabel("Snap target")
        panel.setAccessibilityRole(.group)

        let host = NSHostingView(rootView: HUDSnapPreview(model: preview, padding: Self.previewPadding))
        panel.contentView = host

        previewPanel = panel
        return panel
    }
}

// MARK: - Panel

/// Non-activating, click-through HUD panel that can never take focus or a click.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configureAsHUD() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
    }
}
