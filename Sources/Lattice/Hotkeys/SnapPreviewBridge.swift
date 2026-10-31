import CoreGraphics

/// The preview surface the drag-snap subsystem draws into.
///
/// The real implementation is the HUD agent's `HUDController` in `UI/HUD/`. To keep this
/// directory buildable before that lands — and to keep the two subsystems decoupled — calls
/// go through this tiny internal protocol. `SnapPreviewBridge.presenter` defaults to a no-op
/// and is swapped for the HUD-backed conformance in `HUDControllerSnapPreview.swift`.
@MainActor
protocol SnapPreviewPresenting: AnyObject {
    func showSnapPreview(rect: CGRect, label: String?)
    func hideSnapPreview(animated: Bool)
}

/// Does nothing. Used until the HUD is available (and whenever it is not).
@MainActor
final class NullSnapPreview: SnapPreviewPresenting {
    func showSnapPreview(rect: CGRect, label: String?) {}
    func hideSnapPreview(animated: Bool) {}
}

/// Main-actor entry point used by `DragSnapController`. Callers inside a main-queue block
/// use `MainActor.assumeIsolated`; nothing here touches the window server off the main thread.
@MainActor
enum SnapPreviewBridge {
    static var presenter: SnapPreviewPresenting = NullSnapPreview()

    /// Swap the no-op for the real HUD. Safe to call more than once.
    static func installHUD() {
        presenter = HUDControllerSnapPreview.shared
    }

    static func show(rect: CGRect, label: String?) {
        presenter.showSnapPreview(rect: rect, label: label)
    }

    static func hide(animated: Bool = true) {
        presenter.hideSnapPreview(animated: animated)
    }
}
