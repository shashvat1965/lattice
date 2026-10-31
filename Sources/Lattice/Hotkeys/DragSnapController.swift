import AppKit
import ApplicationServices
import CoreGraphics
import LatticeKit

/// The mouse half of Lattice's input layer: hold the title bar, drag a window to a screen
/// edge, see exactly where it will land, let go.
///
/// A **listen-only** `CGEventTap` on the session run loop. It never swallows, reorders or
/// rewrites an event — it only observes `leftMouseDown/Dragged/Up` and computes geometry.
/// The tap callback itself does no work beyond copying a point into a bounded mailbox; AX
/// hit-testing and main-actor reads happen on a worker queue, and preview/snap writes hop to
/// the main actor.
final class DragSnapController: @unchecked Sendable {

    static let shared = DragSnapController()

    // MARK: - Types

    private struct RawSample {
        var type: CGEventType
        var point: CGPoint
        var flags: CGEventFlags
        var timestamp: UInt64
    }

    /// Everything captured once, at the moment the drag starts.
    private struct DragContext {
        var window: WindowID
        var space: SpaceID
        var display: DisplayInfo
        var startPoint: CGPoint
        var wasTiled: Bool
        var title: String
    }

    private struct ActiveDrag {
        var context: DragContext
        var previewRect: CGRect?
        var previewLabel: String?
        /// Tiled windows (id, frame, title) captured on the first ⌘-drag sample.
        var tiledFrames: [(WindowID, CGRect, String)]?
    }

    // MARK: - Event tap wiring

    private let stateLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var started = false
    private var retryTimer: Timer?
    private var loggedTrustWait = false

    // MARK: - Mailbox (tap thread → worker queue)

    private let mailboxLock = NSLock()
    private var mailbox: [RawSample] = []
    private let mailboxSignal = DispatchSemaphore(value: 0)
    private static let mailboxCapacity = 64

    private let workQueue = DispatchQueue(label: "app.lattice.dragsnap.work", qos: .userInteractive)

    // MARK: - Worker state (work queue only)

    private var pendingStart: CGPoint?
    private var lastSampleTime: UInt64 = 0
    private var active: ActiveDrag?

    private init() {
        // One worker for the life of the process; it parks on the mailbox semaphore until
        // the tap delivers something.
        workQueue.async { [weak self] in self?.runWorker() }
    }

    // MARK: - Lifecycle

    /// Idempotent. Needs Accessibility trust; until it is granted this quietly retries.
    func start() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.start() }
            return
        }

        MainActor.assumeIsolated {
            SnapPreviewBridge.installHUD()
        }

        guard AXIsProcessTrusted() else {
            scheduleTrustRetry()
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil

        stateLock.lock()
        if started {
            stateLock.unlock()
            return
        }
        started = true
        stateLock.unlock()

        let thread = Thread { [weak self] in self?.runTapThread() }
        thread.name = "app.lattice.dragsnap.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        stateLock.lock()
        let tap = self.tap
        let source = self.runLoopSource
        let loop = self.tapRunLoop
        started = false
        self.tap = nil
        self.runLoopSource = nil
        self.tapRunLoop = nil
        stateLock.unlock()

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source, let loop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
            CFRunLoopStop(loop)
        }
        retryTimer?.invalidate()
        retryTimer = nil
        mailboxSignal.signal()
    }

    private func scheduleTrustRetry() {
        guard retryTimer == nil else { return }
        stateLock.lock()
        let shouldLog = !loggedTrustWait
        loggedTrustWait = true
        stateLock.unlock()
        if shouldLog {
            Log.info("drag snapping idle until Accessibility is granted")
        }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard AXIsProcessTrusted() else { return }
            self.start()
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    /// The tap could not be created (revoked trust, tap budget). Allow a later retry.
    private func tapCreationFailed() {
        stateLock.lock()
        started = false
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in self?.scheduleTrustRetry() }
    }

    // MARK: - Tap thread

    private func runTapThread() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: dragSnapTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            Log.error("drag snap: could not create listen-only event tap")
            tapCreationFailed()
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Log.error("drag snap: could not create run loop source")
            tapCreationFailed()
            return
        }

        stateLock.lock()
        self.tap = tap
        self.runLoopSource = source
        self.tapRunLoop = CFRunLoopGetCurrent()
        loggedTrustWait = false
        stateLock.unlock()

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }

    /// Runs on the tap thread. Must stay tiny and allocation-light: copy, enqueue, return
    /// the event untouched so the system keeps delivering it to the app underneath.
    fileprivate func enqueue(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            stateLock.lock()
            let tap = self.tap
            stateLock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            // A disabled tap may have swallowed the mouse-up; retract the preview.
            workQueue.async { [weak self] in self?.resetDrag() }
            return
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            break
        default:
            return
        }

        let sample = RawSample(type: type,
                               point: event.location,
                               flags: event.flags,
                               timestamp: event.timestamp)

        mailboxLock.lock()
        if mailbox.count >= Self.mailboxCapacity {
            mailbox.removeFirst(mailbox.count - Self.mailboxCapacity + 1)
        }
        mailbox.append(sample)
        mailboxLock.unlock()
        mailboxSignal.signal()
    }

    // MARK: - Worker

    private func runWorker() {
        while true {
            mailboxSignal.wait()

            mailboxLock.lock()
            let batch = mailbox
            mailbox.removeAll(keepingCapacity: true)
            mailboxLock.unlock()

            for sample in batch { process(sample) }
        }
    }

    private func process(_ sample: RawSample) {
        // Guard against a drag whose mouse-up never reached us (tap timeout, Space switch):
        // any event after a long silence starts from a clean slate.
        if sample.timestamp &- lastSampleTime > 8_000_000_000 {
            resetDrag()
        }
        lastSampleTime = sample.timestamp

        switch sample.type {
        case .leftMouseDown: onMouseDown(sample)
        case .leftMouseDragged: onMouseDragged(sample)
        case .leftMouseUp: onMouseUp(sample)
        default: break
        }
    }

    /// Drops all drag state and retracts the preview. Safe to call at any time.
    private func resetDrag() {
        if active?.previewRect != nil { publishHide() }
        active = nil
        pendingStart = nil
    }

    // MARK: - Drag state machine

    private func onMouseDown(_ sample: RawSample) {
        // A previous drag that never saw its mouse-up (Space switch, tap timeout) is
        // discarded here as well as on mouse-up, so state can never leak between drags.
        resetDrag()
        pendingStart = sample.point
    }

    private func onMouseDragged(_ sample: RawSample) {
        guard let start = pendingStart else { return }

        if active == nil {
            let dx = sample.point.x - start.x
            let dy = sample.point.y - start.y
            let threshold = DragSnapZones.minimumDragDistance
            guard dx * dx + dy * dy >= threshold * threshold else { return }
            guard let context = beginDrag(at: start) else {
                pendingStart = nil
                return
            }
            active = ActiveDrag(context: context, previewRect: nil,
                                previewLabel: nil, tiledFrames: nil)
        }

        guard var drag = active else { return }
        let prefs = PreferencesStore.shared.prefs

        var targetRect: CGRect?
        var targetLabel: String?
        var zone: DragSnapZone?

        if sample.flags.contains(.maskCommand), prefs.dragToSwap {
            // ⌘-drag: the drop target is another tiled window, not a screen edge.
            if drag.tiledFrames == nil {
                drag.tiledFrames = tiledFramesSnapshot(for: drag.context.space)
            }
            if let hit = drag.tiledFrames?.first(where: {
                $0.0 != drag.context.window && $0.1.contains(sample.point)
            }) {
                targetRect = hit.1
                targetLabel = "Swap"
            }
        } else if prefs.snapToEdges {
            zone = DragSnapZones.zone(for: sample.point, in: drag.context.display.visibleFrame)
            if let zone {
                targetRect = DragSnapGeometry.frame(for: zone, display: drag.context.display, prefs: prefs)
                targetLabel = zone.label
            }
        }

        let changed = drag.previewRect != targetRect || drag.previewLabel != targetLabel
        drag.previewRect = targetRect
        drag.previewLabel = targetLabel
        active = drag

        guard changed else { return }
        if let targetRect {
            publishShow(targetRect, label: targetLabel)
        } else {
            publishHide()
        }
    }

    private func onMouseUp(_ sample: RawSample) {
        // Clear first: a duplicate mouse-up is then a guaranteed no-op.
        defer {
            pendingStart = nil
            active = nil
        }
        guard let drag = active else { return }

        let prefs = PreferencesStore.shared.prefs
        let commandHeld = sample.flags.contains(.maskCommand)

        var swap: WindowID?
        var zone: DragSnapZone?

        if commandHeld, prefs.dragToSwap {
            swap = swapTarget(in: drag, point: sample.point)?.0
        } else if prefs.snapToEdges {
            zone = DragSnapZones.zone(for: sample.point, in: drag.context.display.visibleFrame)
        }

        if drag.previewRect != nil { publishHide() }
        finalize(drag.context, zone: zone, swap: swap)
    }

    private func swapTarget(in drag: ActiveDrag, point: CGPoint) -> (WindowID, CGRect, String)? {
        drag.tiledFrames?.first {
            $0.0 != drag.context.window && $0.1.contains(point)
        }
    }

    // MARK: - Main-actor work

    /// Hit roles that mean "this is content, not chrome". A drag starting inside a text
    /// field, scroll area or web view is a selection/content drag, never a window drag.
    private static let contentDragRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        kAXScrollAreaRole as String,
        "AXWebArea",
        kAXListRole as String,
        kAXTableRole as String,
        kAXOutlineRole as String,
        kAXRowRole as String,
    ]

    /// Hit-test the pointer, resolve the AX window, and validate it against the live model.
    /// Called from the worker; hops to main (synchronously) because the engine cache is
    /// main-actor owned. One AX round-trip per drag, not per event.
    private func beginDrag(at point: CGPoint) -> DragContext? {
        guard AXIsProcessTrusted() else { return nil }
        guard let element = systemWideElement(at: point),
              let windowElement = windowElement(from: element),
              let windowID = Self.windowID(of: windowElement) else { return nil }

        // Text selection, scrolling and web-content drags belong to the app.
        if let role = axString(element, kAXRoleAttribute), Self.contentDragRoles.contains(role) {
            return nil
        }

        return DispatchQueue.main.sync { () -> DragContext? in
            MainActor.assumeIsolated {
                let model = AppModel.shared
                guard model.isEnabled else { return nil }
                let prefs = PreferencesStore.shared.prefs
                guard prefs.snapToEdges || prefs.dragToSwap else { return nil }

                guard let window = model.engine.window(windowID) else { return nil }
                // Never act on Lattice itself, the Dock, Spotlight, or other system chrome.
                guard window.pid != getpid() else { return nil }
                guard window.appName != "Lattice" else { return nil }
                if let bundle = window.bundleID, prefs.floatBundleIDs.contains(bundle) { return nil }

                // Fullscreen windows and windows on other real Spaces are off limits.
                guard !window.isFullscreen, !window.isMinimized else { return nil }
                // A window that already refused AX writes keeps its frames to itself.
                guard !model.engine.isStubborn(windowID) else { return nil }
                guard let space = SpaceManager.shared.focusedSpace(),
                      window.space == space else { return nil }
                guard let display = model.tiler.displayInfo(for: window.display) else { return nil }

                let wasTiled = model.tiler.tiledWindows(on: space).contains(windowID)
                guard wasTiled || prefs.snapToEdges else { return nil }

                return DragContext(window: windowID,
                                   space: space,
                                   display: display,
                                   startPoint: point,
                                   wasTiled: wasTiled,
                                   title: window.title)
            }
        }
    }

    private func tiledFramesSnapshot(for space: SpaceID) -> [(WindowID, CGRect, String)] {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                let engine = AppModel.shared.engine
                return AppModel.shared.tiler.tiledWindows(on: space).compactMap { id in
                    guard let frame = engine.frame(of: id) else { return nil }
                    return (id, frame, engine.window(id)?.title ?? "")
                }
            }
        }
    }

    private func finalize(_ context: DragContext, zone: DragSnapZone?, swap: WindowID?) {
        guard zone != nil || swap != nil else { return }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                SnapPreviewBridge.hide()

                // Space switched under the drag: leave everything alone.
                guard SpaceManager.shared.focusedSpace() == context.space else { return }

                let model = AppModel.shared
                guard model.isEnabled else { return }
                let prefs = PreferencesStore.shared.prefs

                if let swap, prefs.dragToSwap {
                    let tiled = model.tiler.tiledWindows(on: context.space)
                    guard tiled.contains(context.window), tiled.contains(swap) else { return }
                    model.tiler.swapTiles(context.window, swap, on: context.space)
                    return
                }

                guard let zone, prefs.snapToEdges else { return }
                guard let window = model.engine.window(context.window),
                      !window.isFullscreen,
                      !window.isMinimized,
                      !model.engine.isStubborn(context.window),
                      let element = window.axElement else { return }

                // A window that refuses AX writes: give up silently rather than fighting it.
                var settable = DarwinBoolean(false)
                guard AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success,
                      settable.boolValue else { return }

                let rect = DragSnapGeometry.frame(for: zone, display: context.display, prefs: prefs)

                model.tiler.snapshot()

                // Leaving the tile order is what lets the remaining tiles close the hole.
                if model.tiler.tiledWindows(on: context.space).contains(context.window) {
                    model.engine.focus(context.window)
                    model.tiler.toggleFloat()
                }

                model.engine.setFrame(rect, for: [context.window],
                                      animated: prefs.animate,
                                      duration: prefs.animationDuration)
                model.tiler.reconcile()
            }
        }
    }

    // MARK: - Preview publishing

    private func publishShow(_ rect: CGRect, label: String?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard PreferencesStore.shared.prefs.showSnapPreview else {
                    SnapPreviewBridge.hide()
                    return
                }
                SnapPreviewBridge.show(rect: rect, label: label)
            }
        }
    }

    private func publishHide() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { SnapPreviewBridge.hide() }
        }
    }

    // MARK: - AX helpers

    private static let getWindowFn: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    private static func windowID(of element: AXUIElement) -> WindowID? {
        guard let fn = getWindowFn else { return nil }
        var wid: CGWindowID = 0
        guard fn(element, &wid) == .success, wid != 0 else { return nil }
        return WindowID(wid)
    }

    private func systemWideElement(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                                      Float(point.x), Float(point.y),
                                                      &element)
        guard status == .success else { return nil }
        return element
    }

    private func windowElement(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<24 {
            guard let node = current else { return nil }
            if axString(node, kAXRoleAttribute) == (kAXWindowRole as String) { return node }
            current = axElement(node, kAXParentAttribute)
        }
        return nil
    }

    private func axCopy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        axCopy(element, attribute) as? String
    }

    private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axCopy(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

/// File-scope C callback: the tap thread's only job is `enqueue`.
private func dragSnapTapCallback(proxy: CGEventTapProxy,
                                 type: CGEventType,
                                 event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<DragSnapController>.fromOpaque(userInfo)
            .takeUnretainedValue()
            .enqueue(type: type, event: event)
    }
    // Listen-only: hand the event straight back, byte for byte.
    return Unmanaged.passUnretained(event)
}
