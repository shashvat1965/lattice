import AppKit
import LatticeKit

@main
enum LatticeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = MainMenuBuilder.build()
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private(set) static var shared: AppDelegate?

    let model = AppModel.shared
    var windowController: MainWindowController?
    var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        model.bootstrap()
        statusBar = StatusBarController(model: model)
        HotkeyCenter.shared.install(model: model)

        if !model.accessibilityGranted {
            showMainWindow(tab: .overview)
            OnboardingWindowController.showIfNeeded()
            // Show the system prompt immediately, the way every window utility does.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !AXIsProcessTrusted() { self.model.requestAccessibility() }
            }
        } else if !PreferencesStore.shared.prefs.hasCompletedOnboarding {
            showMainWindow(tab: .overview)
            OnboardingWindowController.showIfNeeded()
        } else {
            showMainWindow(tab: .overview)
        }

        NotificationCenter.default.addObserver(forName: .latticeShowMainWindow, object: nil, queue: .main) { [weak self] _ in
            self?.showMainWindow(tab: .overview)
        }

        NotificationCenter.default.addObserver(forName: .latticeShowSpaces, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            SpacesWindowController.show(model: self.model)
        }

        BorderOverlayController.shared.start(model: model)
        FocusFollowMonitor.shared.start(model: model)
        DebugCapture.scheduleIfRequested()
        SmokeTest.runIfRequested(model: model)
        if let path = ProcessInfo.processInfo.environment["LATTICE_SNAPSHOT"] {
            let dir = URL(fileURLWithPath: path, isDirectory: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                DesignSnapshots.renderAll(model: self.model, into: dir)
                if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_EXIT"] == "1" { NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow(tab: .overview)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @discardableResult
    func showMainWindow(tab: MainTab) -> NSWindow {
        if windowController == nil {
            windowController = MainWindowController(model: model)
        }
        windowController?.show(tab: tab)
        return windowController!.window!
    }
}
