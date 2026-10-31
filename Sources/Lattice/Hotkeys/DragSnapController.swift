import AppKit
import ApplicationServices
import CoreGraphics
import LatticeKit

/// Drag a window to a screen edge, see exactly where it will land, let go.
///
/// This deliberately uses **AppKit global monitors**, not a `CGEventTap`. A tap — even a
/// listen-only one — sits inside the system's input path, and any latency there is felt as
/// unresponsive clicking in every app. A global monitor is a passive observer: it cannot
/// delay, reorder or swallow anything, and if the callback is slow the worst case is that a
/// preview arrives late, never that a click goes missing.
///
/// Only title-bar drags are considered, so selecting text or dragging content in a canvas is
/// never mistaken for moving a window.
@MainActor
final class DragSnapController {

    static let shared = DragSnapController()

    // MARK: - State

    private struct Drag {
        let id: WindowID
        let space: SpaceID
        let display: DisplayInfo
        let startPoint: CGPoint
        let wasTiled: Bool
        var zone: DragSnapZone?
        var swapTarget: WindowID?
        var lastPreviewRect: CGRect?
        var lastLabel: String?
    }

    private var monitors: [Any] = []
    private var drag: Drag?
    private var started = false
    private var trustTimer: Timer?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        guard AXIsProcessTrusted() else {
            scheduleTrustRetry()
            return
        }
        started = true
        trustTimer?.invalidate()
        trustTimer = nil

        SnapPreviewBridge.installHUD()

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            // AppKit delivers this on the main thread; the explicit hop keeps it honest.
            Task { @MainActor in self?.handle(event) }
        }) {
            monitors.append(monitor)
        }
        Log.info("drag snapping active (passive monitors, no event tap)")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        drag = nil
        started = false
        SnapPreviewBridge.hide(animated: false)
    }

    private func scheduleTrustRetry() {
        guard trustTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard AXIsProcessTrusted() else { return }
                self?.start()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
        Log.info("drag snapping idle until Accessibility is granted")
    }

    // MARK: - Events

    private func handle(_ event: NSEvent) {
        guard let model = AppModel.shared as AppModel? else { return }
        guard model.accessibilityGranted, model.isEnabled else { return }
        let prefs = PreferencesStore.shared.prefs
        guard prefs.snapToEdges || prefs.dragToSwap else { return }

        let point = Self.cgPoint(from: event)

        switch event.type {
        case .leftMouseDown:
            beginDrag(at: point, model: model)
        case .leftMouseDragged:
            updateDrag(at: point, flags: event.modifierFlags, model: model)
        case .leftMouseUp:
            finishDrag(at: point, model: model)
        default:
            break
        }
    }

    private func beginDrag(at point: CGPoint, model: AppModel) {
        drag = nil
        guard let window = Self.window(under: point, model: model) else { return }
        guard window.pid != getpid(), window.appName != "Lattice" else { return }
        guard !window.isMinimized, !window.isFullscreen else { return }
        guard !model.engine.isStubborn(window.id) else { return }
        guard !PreferencesStore.shared.prefs.isUnmanaged(window.bundleID) else { return }
        // Title-bar only: a drag that starts in content belongs to the app, not to us.
        let titleBarBand: CGFloat = 34
        guard point.y >= window.frame.minY, point.y <= window.frame.minY + titleBarBand else { return }
        guard let display = model.tiler.displayInfo(for: window.display) else { return }

        drag = Drag(id: window.id,
                    space: window.space,
                    display: display,
                    startPoint: point,
                    wasTiled: !model.tiler.isFloating(window.id),
                    zone: nil,
                    swapTarget: nil,
                    lastPreviewRect: nil,
                    lastLabel: nil)
    }

    private func updateDrag(at point: CGPoint, flags: NSEvent.ModifierFlags, model: AppModel) {
        guard var drag else { return }
        guard hypot(point.x - drag.startPoint.x, point.y - drag.startPoint.y) > 10 else { return }

        // A Space switch mid-drag cancels: the geometry we planned no longer applies.
        let currentSpace = SpaceManager.shared.focusedSpace() ?? drag.space
        guard currentSpace == drag.space else { endDrag(model: model, cancel: true); return }

        let prefs = PreferencesStore.shared.prefs

        // ⌘-drag over a tile = swap the two.
        if prefs.dragToSwap, flags.contains(.command) {
            if let other = Self.window(under: point, model: model),
               other.id != drag.id,
               !model.tiler.isFloating(other.id),
               other.space == drag.space {
                drag.swapTarget = other.id
                drag.zone = nil
                if drag.lastLabel != "Swap" || drag.lastPreviewRect != other.frame {
                    drag.lastPreviewRect = other.frame
                    drag.lastLabel = "Swap"
                    SnapPreviewBridge.show(rect: other.frame, label: "Swap")
                }
                self.drag = drag
                return
            }
        }

        guard prefs.snapToEdges else { return }
        let zone = DragSnapZones.zone(for: point, in: drag.display.visibleFrame)
        if let zone {
            let rect = DragSnapGeometry.frame(for: zone, display: drag.display, prefs: prefs)
            if drag.lastPreviewRect != rect || drag.lastLabel != zone.label {
                drag.lastPreviewRect = rect
                drag.lastLabel = zone.label
                SnapPreviewBridge.show(rect: rect, label: zone.label)
            }
        } else if drag.lastPreviewRect != nil {
            drag.lastPreviewRect = nil
            drag.lastLabel = nil
            SnapPreviewBridge.hide()
        }
        drag.zone = zone
        drag.swapTarget = nil
        self.drag = drag
    }

    private func finishDrag(at point: CGPoint, model: AppModel) {
        guard let drag else { return }
        _ = point
        if let target = drag.swapTarget {
            model.tiler.swapTiles(drag.id, target, on: drag.space, animated: PreferencesStore.shared.prefs.animateLayoutSwaps)
            endDrag(model: model, cancel: true)
            return
        }
        if let zone = drag.zone {
            let prefs = PreferencesStore.shared.prefs
            let rect = DragSnapGeometry.frame(for: zone, display: drag.display, prefs: prefs)
            model.tiler.snapWindow(drag.id, to: rect, on: drag.space)
            HUDController.shared.showToast(zone.label, symbol: "rectangle.split.2x1")
        }
        endDrag(model: model, cancel: true)
    }

    private func endDrag(model: AppModel, cancel: Bool) {
        _ = model
        _ = cancel
        drag = nil
        SnapPreviewBridge.hide()
    }

    // MARK: - Geometry helpers

    /// AppKit reports screen coordinates with a bottom-left origin; WindowServer and our
    /// layout maths use top-left. Everything crossing this boundary goes through here.
    static func cgPoint(from event: NSEvent) -> CGPoint {
        let screenPoint = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)
    }

    /// The Lattice-managed window under a point, via Accessibility hit-testing.
    static func window(under point: CGPoint, model: AppModel) -> ManagedWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              var current = element else { return nil }

        var depth = 0
        while depth < 12 {
            if let id = windowID(of: current), let window = model.engine.window(id) {
                return window
            }
            guard let parent = parent(of: current) else { break }
            current = parent
            depth += 1
        }
        return nil
    }

    private static let getWindowFn: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    static func windowID(of element: AXUIElement) -> WindowID? {
        guard let fn = getWindowFn else { return nil }
        var wid: CGWindowID = 0
        guard fn(element, &wid) == .success, wid != 0 else { return nil }
        return WindowID(wid)
    }

    static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
