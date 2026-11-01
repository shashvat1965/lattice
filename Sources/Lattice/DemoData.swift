import AppKit
import LatticeKit

/// Fixture content for design review and screenshots. Real displays and real Spaces come from
/// the system; only the windows are invented, so every screen can be rendered without the
/// Accessibility permission.
@MainActor
enum DemoData {

    static var isEnabled: Bool { ProcessInfo.processInfo.environment["LATTICE_DEMO"] == "1" }

    static func apply(to model: AppModel) {
        guard isEnabled else { return }
        guard let display = model.displays.first else {
            Log.error("DEMO: no displays yet")
            return
        }
        // Use the Space WindowServer says is showing on that display, so the fixtures land in
        // the bucket the UI actually reads.
        let space = model.spaces.first(where: { $0.display == display.id })?.current
            ?? model.focusedSpace
        let area = display.visibleFrame.insetBy(dx: 8, dy: 8)

        // Fixtures must obey the same gaps the tiler would apply, or the map looks like the
        // layout ignores the gap setting.
        let gap = max(0, PreferencesStore.shared.prefs.gap)
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: area.minX + area.width * x,
                   y: area.minY + area.height * y,
                   width: area.width * w,
                   height: area.height * h).insetBy(dx: gap / 2, dy: gap / 2)
        }

        let fixtures: [(String, String, String, CGRect)] = [
            ("Xcode", "com.apple.dt.Xcode", "Lattice — Sources/AppModel.swift", rect(0.00, 0.00, 0.545, 1.00)),
            ("Figma", "com.figma.Desktop", "Lattice — Design system", rect(0.545, 0.00, 0.230, 1.00)),
            ("Arc", "company.thebrowser.Browser", "github.com/shashvat1965/lattice", rect(0.775, 0.00, 0.225, 0.50)),
            ("Spotify", "com.spotify.client", "Lattice Radio", rect(0.775, 0.50, 0.225, 0.50)),
        ]

        var windows: [WindowID: ManagedWindow] = [:]
        for (index, fixture) in fixtures.enumerated() {
            let id = WindowID(UInt32(9000 + index))
            windows[id] = ManagedWindow(id: id,
                                        pid: pid_t(9000 + index),
                                        appName: fixture.0,
                                        bundleID: fixture.1,
                                        title: fixture.2,
                                        frame: fixture.3,
                                        space: space,
                                        display: display.id,
                                        isFloating: false,
                                        isFullscreen: false,
                                        isMinimized: false,
                                        role: kAXWindowRole as String,
                                        subrole: kAXStandardWindowSubrole as String)
        }

        // One floating window, so the floating band has something true to show.
        let floatID = WindowID(9100)
        windows[floatID] = ManagedWindow(id: floatID,
                                         pid: 9100,
                                         appName: "System Settings",
                                         bundleID: "com.apple.systempreferences",
                                         title: "Accessibility",
                                         frame: rect(0.62, 0.55, 0.30, 0.40),
                                         space: space,
                                         display: display.id,
                                         isFloating: true,
                                         isFullscreen: false,
                                         isMinimized: false,
                                         role: kAXWindowRole as String,
                                         subrole: kAXStandardWindowSubrole as String)

        Log.info("DEMO applying \(windows.count) windows to space \(space) display \(display.id)")
        // The fixture must not be reconciled against the real windows on this Mac, or the
        // tiler publishes the real set back over it. Suspending only affects this demo run.
        model.tiler.isSuspended = true
        model.installDemoWindows(windows, order: [WindowID(9000), WindowID(9001), WindowID(9002), WindowID(9003)])
        model.recentActions = ["Focus Left", "Columns", "Send to Space 2"]
        // The fixture is a picture of the shipping state, not of this Mac's pause switch.
        // This only changes the published flag; tiling stays exactly as paused as it was.
        model.isEnabled = true
    }
}
