import AppKit
import LatticeKit

/// Runtime smoke test for the panels that nobody can reach without a keyboard.
/// `LATTICE_SMOKE=1` drives each surface once and reports, so a crash or a stuck panel
/// is caught before a human ever sees it.
@MainActor
enum SmokeTest {

    static var isRequested: Bool { ProcessInfo.processInfo.environment["LATTICE_SMOKE"] == "1" }

    static func runIfRequested(model: AppModel) {
        guard isRequested else { return }
        Log.info("SMOKE start")
        var steps: [(String, () -> Void, TimeInterval)] = []

        steps.append(("hud toast", {
            HUDController.shared.showToast("Columns", symbol: "rectangle.split.3x1")
        }, 0.6))

        steps.append(("snap preview", {
            let display = model.displays.first
            let frame = display?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
            let half = CGRect(x: frame.minX + 8, y: frame.minY + 8,
                              width: frame.width / 2 - 12, height: frame.height - 16)
            HUDController.shared.showSnapPreview(rect: half, label: "Left Half")
        }, 0.8))

        steps.append(("snap preview hide", {
            HUDController.shared.hideSnapPreview()
        }, 0.3))

        steps.append(("palette open", {
            CommandPaletteController.shared.show()
            assert(CommandPaletteController.shared.isVisible, "palette did not report visible")
        }, 0.7))

        steps.append(("palette close", {
            CommandPaletteController.shared.dismiss()
        }, 0.4))

        steps.append(("cheat sheet open", {
            CheatSheetController.shared.show()
            assert(CheatSheetController.shared.isVisible, "cheat sheet did not report visible")
        }, 0.7))

        steps.append(("cheat sheet close", {
            CheatSheetController.shared.dismiss()
        }, 0.4))

        steps.append(("spaces window", {
            NotificationCenter.default.post(name: .latticeShowSpaces, object: nil)
        }, 0.6))

        steps.append(("main window", {
            NotificationCenter.default.post(name: .latticeShowMainWindow, object: nil)
        }, 0.6))

        steps.append(("done", {
            Log.info("SMOKE complete: \(NSApp.windows.filter(\.isVisible).count) windows visible")
            if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_EXIT"] == "1" { NSApp.terminate(nil) }
        }, 0.2))

        var delay: TimeInterval = 1.2
        for (name, action, wait) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Log.info("SMOKE step: \(name)")
                action()
            }
            delay += wait
        }
    }
}
