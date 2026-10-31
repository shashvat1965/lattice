import CoreGraphics

/// Connects `SnapPreviewBridge` to the menu-bar agent's real HUD. Kept in its own file so the
/// drag-snap machinery only ever sees the `SnapPreviewPresenting` protocol.
@MainActor
final class HUDControllerSnapPreview: SnapPreviewPresenting {

    static let shared = HUDControllerSnapPreview()
    private init() {}

    func showSnapPreview(rect: CGRect, label: String?) {
        HUDController.shared.showSnapPreview(rect: rect, label: label)
    }

    func hideSnapPreview(animated: Bool) {
        HUDController.shared.hideSnapPreview(animated: animated)
    }
}
