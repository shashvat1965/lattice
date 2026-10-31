import AppKit
import LatticeKit

/// Focus follows mouse, implemented as a cheap pointer poll rather than an event tap:
/// no Accessibility permission is needed, nothing is swallowed, and it costs one
/// comparison at 10 Hz — only while the preference is on.
@MainActor
final class FocusFollowMonitor {

    static let shared = FocusFollowMonitor()

    private var timer: Timer?
    private weak var model: AppModel?
    private var lastPoint: CGPoint = .zero
    private var lastFocused: WindowID?

    private init() {}

    func start(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        applyPreference()
        _ = PreferencesStore.shared.observe { [weak self] _ in
            Task { @MainActor in self?.applyPreference() }
        }
    }

    private func applyPreference() {
        let enabled = PreferencesStore.shared.prefs.focusFollowsMouse
        if enabled { startTimer() } else { stopTimer() }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let model, model.accessibilityGranted else { return }
        // Do not steal focus mid-drag; the pointer is already committed to something.
        guard CGEventSource.buttonState(.combinedSessionState, button: .left) == false else { return }

        let point = NSEvent.mouseLocation
        let flipped = CGPoint(x: point.x,
                              y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        guard hypot(flipped.x - lastPoint.x, flipped.y - lastPoint.y) > 1 else { return }
        lastPoint = flipped

        if model.tiler.focusWindowUnderPointer() {
            if model.engine.focused != lastFocused {
                lastFocused = model.engine.focused
            }
        }
    }
}
