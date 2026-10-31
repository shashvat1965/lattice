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
        // Fixtures come after bootstrap so the permission state the renderer sees is ours.
        DemoData.apply(to: model)
        ControlServer.shared.start(model: model)
        statusBar = StatusBarController(model: model)
        HotkeyCenter.shared.install(model: model)

        if !model.accessibilityGranted {
            showMainWindow(tab: .overview)
            OnboardingWindowController.showIfNeeded()
            // One prompt, once, at launch. Never again from a shortcut or a timer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !AXIsProcessTrusted() { self.model.requestAccessibility() }
            }
        } else {
            // Access is granted: the tour has done its job. Leaving it open kept a second
            // window holding key status, which made the app look like it refused to focus.
            if !PreferencesStore.shared.prefs.hasCompletedOnboarding {
                PreferencesStore.shared.update { $0.hasCompletedOnboarding = true }
            }
            showMainWindow(tab: .overview)
        }

        NotificationCenter.default.addObserver(forName: .latticeShowMainWindow, object: nil, queue: .main) { [weak self] _ in
            self?.showMainWindow(tab: .overview)
        }

        NotificationCenter.default.addObserver(forName: .latticeShowSettings, object: nil, queue: .main) { [weak self] _ in
            self?.showMainWindow(tab: .settings)
        }

        NotificationCenter.default.addObserver(forName: .latticeShowSpaces, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            SpacesWindowController.show(model: self.model)
        }

        installActivationLogging()
        Log.info("launch: probe env=\(ProcessInfo.processInfo.environment["LATTICE_PROBE"] ?? "nil") snapshot env=\(ProcessInfo.processInfo.environment["LATTICE_SNAPSHOT"] ?? "nil")")
        BorderOverlayController.shared.start(model: model)
        FocusFollowMonitor.shared.start(model: model)
        DebugCapture.scheduleIfRequested()
        SmokeTest.runIfRequested(model: model)
        if let path = ProcessInfo.processInfo.environment["LATTICE_SHOTS"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                PageSnapshots.runIfRequested(into: URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        if let path = ProcessInfo.processInfo.environment["LATTICE_PROBE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                RenderProbe.runIfRequested(into: URL(fileURLWithPath: path, isDirectory: true))
            }
        }
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

    /// Panels (HUD, palette, cheat sheet, borders) are windows too, so `hasVisibleWindows`
    /// was true whenever any of them existed — and the main window was never restored. An app
    /// that activates with no key window is handed straight back to the previous app, which is
    /// exactly the "click Lattice, it bounces away" behaviour.
    func applicationDidBecomeActive(_ notification: Notification) {
        // Always present a window that can take key status. A window parked on another Space,
        // or none at all, leaves the app active-but-focusless, and macOS hands focus straight
        // back to whatever was in front.
        guard NSApp.keyWindow == nil || !hasRegularWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.hasRegularWindow { self.showMainWindow(tab: .overview) }
            else { self.windowController?.window?.makeKeyAndOrderFront(nil) }
        }
    }

    private var hasRegularWindow: Bool {
        NSApp.windows.contains { window in
            window.isVisible
                && window.level == .normal
                && window.styleMask.contains(.titled)
                && window.canBecomeKey
        }
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

extension AppDelegate {
    /// Activation normally "just works", so when it does not, the log has to say who took the
    /// focus away and when. Two observers, negligible cost, invaluable when a click bounces.
    func dumpWindows(_ phase: String) {
        let rows = NSApp.windows.map { w in
            let mask = w.styleMask
            let flags = [(NSWindow.StyleMask.titled, "titled"), (.borderless, "borderless"),
                         (.nonactivatingPanel, "nonActivating"), (.fullSizeContentView, "fullSize")]
                .filter { mask.contains($0.0) }.map(\.1).joined(separator: ",")
            return "title=\(w.title.isEmpty ? "-" : w.title) level=\(w.level.rawValue) [\(flags)]"
                + " visible=\(w.isVisible) key=\(w.isKeyWindow) canKey=\(w.canBecomeKey)"
                + " frame=\(Int(w.frame.width))x\(Int(w.frame.height))"
        }
        Log.info("windows[\(phase)] active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) count=\(NSApp.windows.count): \(rows.joined(separator: " | "))")
    }

    func installActivationLogging() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Log.info("activation: became active")
            self.dumpWindows("becameActive")
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            let windows = NSApp.windows.filter(\.isVisible).count
            Log.info("activation: resigned active (front=\(front), visible windows=\(windows), key=\(NSApp.keyWindow?.title ?? "-"), canBecomeKey=\(NSApp.keyWindow?.canBecomeKey ?? false))")
        }
    }
}
