import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

public protocol WindowEngineDelegate: AnyObject {
    func engineDidChangeWindows(_ engine: WindowEngine)
    func engine(_ engine: WindowEngine, didFocus window: ManagedWindow?)
    func engineSpaceDidChange(_ engine: WindowEngine)
    /// Frame-only change (the user moved or resized a window). Never implies re-tiling.
    func engine(_ engine: WindowEngine, didUpdateFrames ids: [WindowID])
    /// A window refused our geometry twice; it is now excluded from tiling.
    func engine(_ engine: WindowEngine, didMarkStubborn id: WindowID, reason: String)
}

public extension WindowEngineDelegate {
    func engine(_ engine: WindowEngine, didUpdateFrames ids: [WindowID]) {}
    func engine(_ engine: WindowEngine, didMarkStubborn id: WindowID, reason: String) {}
}

/// The Accessibility-based window layer. This is Lattice's own tiling engine —
/// no yabai, no AeroSpace, nothing to install. Everything here runs with SIP enabled.
///
/// Design rules that keep it from fighting itself:
///  * Enumeration is cached per app; an AX notification only rebuilds the app that fired it.
///  * The engine never writes to a window on a Space that is not currently visible.
///  * The engine never writes to the window the user is dragging.
///  * Writes are verified; a window that lies about its frame twice is marked stubborn.
///  * Notifications caused by our own writes are absorbed inside a short quiet window.
public final class WindowEngine {

    public weak var delegate: WindowEngineDelegate?

    public private(set) var windows: [WindowID: ManagedWindow] = [:]
    public private(set) var focused: WindowID?

    // MARK: - State

    private let spaces = SpaceManager.shared
    private var axObservers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appEntries: [pid_t: AppEntry] = [:]

    private var pendingPids: Set<pid_t> = []
    private var pendingStructural = false
    private var refreshWorkItem: DispatchWorkItem?
    private var burstStart = CFAbsoluteTimeGetCurrent()
    private var burstCount = 0

    private var recentWrites: [WindowID: WriteRecord] = [:]
    private var pendingWrites: [WindowID: PendingWrite] = [:]
    private var writeFailures: [WindowID: Int] = [:]
    private var stubbornUntil: [WindowID: CFAbsoluteTime] = [:]
    /// Floors we learned from a refused write, for apps that never report AXMinSize.
    private var learnedMinimums: [WindowID: CGSize] = [:]
    private var stubbornReasons: [WindowID: String] = [:]
    private var loggedSkips: Set<String> = []

    private var animationTimer: Timer?
    private var animationToken = 0
    private var verifyWorkItem: DispatchWorkItem?

    private var visibleCache: (ids: Set<SpaceID>, at: CFAbsoluteTime) = ([], 0)
    private var syntheticIDs: [String: WindowID] = [:]
    private var nextSyntheticID: UInt32 = 0x8000_0000

    private var started = false

    // MARK: - Types

    private struct AppEntry {
        var pid: pid_t
        var bundleID: String?
        var appName: String
        var axApp: AXUIElement
        var observer: AXObserver?
        var windowIDs: Set<WindowID>
        var lastRefresh: CFAbsoluteTime
    }

    private struct WriteRecord {
        var frame: CGRect
        var until: CFAbsoluteTime
    }

    private struct PendingWrite {
        var element: AXUIElement
        var target: CGRect
        /// The frame the window had before we first asked it to move. If the write is refused,
        /// this is where it goes back to, so "leave it alone" really means leave it alone.
        var origin: CGRect?
        var attempts: Int
        var deadline: CFAbsoluteTime
    }

    private struct FrameTarget {
        var id: WindowID
        var element: AXUIElement
        var from: CGRect
        var to: CGRect
    }

    private struct CGSnapshot {
        var layer: [WindowID: Int] = [:]
        var alpha: [WindowID: Double] = [:]
        var bounds: [WindowID: CGRect] = [:]
        var onscreen: Set<WindowID> = []
    }

    private struct RebuildResult {
        var structural = false
        var framesChanged: [WindowID] = []
        var windowCount = 0
        var axCalls = 0
    }

    private static let getWindowFn: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
    }()

    /// Payload-free notifications we care about, so a chatty app cannot drown the engine.
    private static let watchedNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXUIElementDestroyedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]

    public init() {
        if LatticeSelfTest.isRequested {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                LatticeSelfTest.run(engine: self)
            }
        }
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    public var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    public func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func start() {
        guard isTrusted else {
            Log.error("engine.start called without accessibility trust")
            return
        }
        guard !started else {
            refresh(reason: "start-again")
            return
        }
        started = true
        observeWorkspace()
        observeScreens()
        refresh(reason: "start")
        Log.info("engine started with \(windows.count) windows, \(appEntries.count) apps, axCalls=\(AXPerf.peek())")
    }

    public func stop() {
        workspaceObservers.forEach { observer in
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        for (pid, observer) in Array(axObservers) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            axObservers[pid] = nil
        }
        animationTimer?.invalidate()
        animationTimer = nil
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        verifyWorkItem?.cancel()
        verifyWorkItem = nil
        appEntries.removeAll()
        started = false
    }

    // MARK: - Enumeration

    /// Full, synchronous refresh. Used on launch, Space changes, and explicit requests.
    public func refresh(reason: String = "explicit") {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let callsBefore = AXPerf.peek()
        let snapshot = Self.cgSnapshot()
        let running = NSWorkspace.shared.runningApplications
        var livePids = Set<pid_t>()
        var structural = false
        var framesChanged: [WindowID] = []

        for app in running {
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            guard pid != getpid(), pid > 0 else { continue }
            livePids.insert(pid)
            let result = rebuildApp(pid: pid,
                                    app: app,
                                    cg: snapshot,
                                    reason: reason,
                                    notify: false)
            structural = structural || result.structural
            framesChanged.append(contentsOf: result.framesChanged)
        }

        for pid in Array(appEntries.keys) where !livePids.contains(pid) {
            removeApp(pid)
            structural = true
        }

        // Stubborn windows whose app is gone lose their sentence.
        let liveIDs = Set(windows.keys)
        for id in Array(stubbornUntil.keys) where !liveIDs.contains(id) {
            stubbornUntil[id] = nil
            stubbornReasons[id] = nil
        }

        updateFocusedWindow()
        if structural || !framesChanged.isEmpty || reason != "explicit" {
            delegate?.engineDidChangeWindows(self)
        }

        let ms = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let calls = AXPerf.peek() - callsBefore
        LatticeDiagnostics.record(String(format: "refresh(%@): %d windows, %d apps, %d ax calls, %.1f ms",
                                         reason, windows.count, appEntries.count, calls, ms))
        Log.info(String(format: "refresh(%@): %d windows in %.1f ms, %d ax calls",
                        reason, windows.count, ms, calls))
    }

    /// Rebuild exactly one app. Returns whether the set of tileable windows changed.
    @discardableResult
    private func rebuildApp(pid: pid_t,
                            app: NSRunningApplication,
                            cg: CGSnapshot,
                            reason: String,
                            notify: Bool = true) -> RebuildResult {
        var result = RebuildResult()
        let callsBefore = AXPerf.peek()

        let axApp = appEntries[pid]?.axApp ?? AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        registerObserver(for: pid, axApp: axApp)

        guard let rawWindows = axApp.copyAttribute(kAXWindowsAttribute) as? [AXUIElement] else {
            // App not responding or has no windows. Keep whatever we already knew: dropping
            // windows because an app was busy for half a second would make the Space flicker.
            result.axCalls = AXPerf.peek() - callsBefore
            Log.debug("rebuildApp: no windows for pid \(pid) (app busy or empty)")
            return result
        }

        var resolved: [(AXUIElement, WindowID)] = []
        for element in rawWindows {
            if let wid = windowID(of: element, pid: pid) {
                resolved.append((element, wid))
            }
        }

        let assignments = spaces.spaceAssignments(for: resolved.map(\.1))
        var next: [WindowID: ManagedWindow] = [:]
        next.reserveCapacity(resolved.count)

        for (element, wid) in resolved {
            if let window = makeWindow(element: element,
                                       wid: wid,
                                       pid: pid,
                                       app: app,
                                       cg: cg,
                                       assignments: assignments) {
                next[wid] = window
            }
        }

        let previous = windows.filter { $0.value.pid == pid }
        result.windowCount = next.count

        if previous.keys.sorted(by: { $0.raw < $1.raw }) != next.keys.sorted(by: { $0.raw < $1.raw }) {
            result.structural = true
        } else {
            for (id, window) in next {
                guard let old = previous[id] else { continue }
                if old.space != window.space
                    || old.isFloating != window.isFloating
                    || old.isFullscreen != window.isFullscreen
                    || old.isMinimized != window.isMinimized {
                    result.structural = true
                }
                if !old.frame.isClose(to: window.frame, tolerance: 0.5) {
                    result.framesChanged.append(id)
                }
            }
        }

        // Merge, preserving identity for untouched apps.
        for id in previous.keys where next[id] == nil {
            windows[id] = nil
            pendingWrites[id] = nil
            recentWrites[id] = nil
            writeFailures[id] = nil
            stubbornUntil[id] = nil
            stubbornReasons[id] = nil
            _ = id
        }
        for (id, window) in next {
            windows[id] = window
        }

        let observer = axObservers[pid]
        appEntries[pid] = AppEntry(pid: pid,
                                   bundleID: app.bundleIdentifier,
                                   appName: app.localizedName ?? "App",
                                   axApp: axApp,
                                   observer: observer,
                                   windowIDs: Set(next.keys),
                                   lastRefresh: CFAbsoluteTimeGetCurrent())

        result.axCalls = AXPerf.peek() - callsBefore

        if result.structural {
            for id in next.keys where !(previous[id] != nil) {
                Log.debug("new window \(id) in \(app.localizedName ?? "app") on space \(next[id]?.space.raw ?? 0)")
            }
        }

        if notify {
            if result.structural {
                updateFocusedWindow()
                delegate?.engineDidChangeWindows(self)
            } else if !result.framesChanged.isEmpty {
                delegate?.engine(self, didUpdateFrames: result.framesChanged)
            }
        }
        return result
    }

    private func makeWindow(element: AXUIElement,
                            wid: WindowID,
                            pid: pid_t,
                            app: NSRunningApplication,
                            cg: CGSnapshot,
                            assignments: [WindowID: SpaceID]) -> ManagedWindow? {
        // One AX round-trip instead of eight. Enumeration of a 12-window Space has to stay
        // cheap enough that an AX notification never becomes a visible hitch.
        let batch = element.batchAttributes([
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXTitleAttribute,
            kAXPositionAttribute,
            kAXSizeAttribute,
            kAXMinimizedAttribute,
            "AXFullScreen",
            "AXMinSize",
            "AXMaxSize",
        ])

        guard let role = (batch[kAXRoleAttribute] as? String) ?? element.stringAttribute(kAXRoleAttribute) else {
            logSkipOnce(wid, "no role", app: app.localizedName)
            return nil
        }
        guard role == (kAXWindowRole as String) else {
            logSkipOnce(wid, "role \(role)", app: app.localizedName)
            return nil
        }

        let minSize = batch["AXMinSize"].flatMap { value -> CGSize? in
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            return Self.cgSize(from: value as! AXValue)
        }
        let maxSize = batch["AXMaxSize"].flatMap { value -> CGSize? in
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            return Self.cgSize(from: value as! AXValue)
        }

        let subrole = (batch[kAXSubroleAttribute] as? String)
            ?? element.stringAttribute(kAXSubroleAttribute)
            ?? ""
        let floatingSubroles: Set<String> = [
            kAXDialogSubrole as String,
            kAXSystemDialogSubrole as String,
            kAXFloatingWindowSubrole as String,
            kAXSystemFloatingWindowSubrole as String,
            "AXSheet",
            "AXUnknown",
        ]
        let standard = (kAXStandardWindowSubrole as String)
        guard subrole == standard || subrole.isEmpty || floatingSubroles.contains(subrole) else {
            logSkipOnce(wid, "subrole \(subrole)", app: app.localizedName)
            return nil
        }

        if let layer = cg.layer[wid], layer != 0 {
            logSkipOnce(wid, "window layer \(layer)", app: app.localizedName)
            return nil
        }

        if let alpha = cg.alpha[wid], alpha <= 0.01 {
            logSkipOnce(wid, "alpha 0", app: app.localizedName)
            return nil
        }

        let frame = AXUIElement.frame(from: batch) ?? element.frame
        guard let frame, frame.width > 1, frame.height > 1 else {
            logSkipOnce(wid, "zero size", app: app.localizedName)
            return nil
        }

        let minimized = (batch[kAXMinimizedAttribute] as? NSNumber)?.boolValue
            ?? element.boolAttribute(kAXMinimizedAttribute)
            ?? false
        let fullscreen = (batch["AXFullScreen"] as? NSNumber)?.boolValue
            ?? element.boolAttribute("AXFullScreen")
            ?? false
        if fullscreen {
            logSkipOnce(wid, "fullscreen (floating)", app: app.localizedName)
        }

        let space = assignments[wid]
            ?? windows[wid]?.space
            ?? spaces.focusedSpace()
            ?? SpaceID(0)

        let display = spaces.displayID(for: wid)
            ?? Self.display(containing: frame.center, screens: NSScreen.screens)

        return ManagedWindow(
            id: wid,
            pid: pid,
            appName: app.localizedName ?? "App",
            bundleID: app.bundleIdentifier,
            title: (batch[kAXTitleAttribute] as? String) ?? element.stringAttribute(kAXTitleAttribute) ?? "",
            frame: frame,
            space: space,
            display: display,
            isFloating: floatingSubroles.contains(subrole) || fullscreen,
            isFullscreen: fullscreen,
            isMinimized: minimized,
            role: role,
            subrole: subrole,
            minSize: minSize,
            maxSize: maxSize,
            axElement: element
        )
    }

    /// Design-review fixtures: pretend these windows exist, with no AX elements behind them.
    /// Everything downstream (floating rules, ordering) then behaves exactly as it would live.
    public func installFixtures(_ fixtures: [WindowID: ManagedWindow]) {
        for (id, window) in fixtures { windows[id] = window }
    }

    public func windows(on space: SpaceID) -> [ManagedWindow] {
        windows.values
            .filter { $0.space == space && !$0.isMinimized && !$0.isFullscreen }
            .sorted { $0.id.raw < $1.id.raw }
    }

    public func window(_ id: WindowID) -> ManagedWindow? { windows[id] }

    public func element(for id: WindowID) -> AXUIElement? { windows[id]?.axElement }

#if DEBUG
    /// Test-only seam used by the engine harness: lets a process adopt its *own* windows so
    /// geometry/verification can be exercised without Accessibility trust over another app.
    /// Never called by the product.
    public func _adoptForTesting(_ window: ManagedWindow) {
        windows[window.id] = window
    }
#endif

    // MARK: - Frame control

    /// Sets the AX frame. `animated` tweens the geometry ourselves at display refresh rate,
    /// which is what makes Lattice feel like part of the system rather than a batch job.
    public func setFrame(_ rect: CGRect, for ids: [WindowID], animated: Bool = true, duration: TimeInterval = 0.18) {
        guard rect.width > 1, rect.height > 1, !rect.isNull else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let visible = visibleSpaceIDs()

        var targets: [FrameTarget] = []
        for id in ids {
            guard !isStubborn(id) else { continue }
            guard let window = windows[id], let element = window.axElement else { continue }
            guard !window.isMinimized, !window.isFullscreen else { continue }
            if window.space.raw != 0 && !visible.contains(window.space) { continue }
            if Self.isDragging(windowFrame: window.frame) {
                LatticeDiagnostics.record("skip \(id.raw): user is dragging it")
                continue
            }
            let target = rect.roundedToPixels(scale: 2)
            if window.frame.isClose(to: target, tolerance: 0.5) { continue }
            if let recent = recentWrites[id], recent.until > now, recent.frame.isClose(to: target, tolerance: 0.5) {
                continue
            }
            targets.append(FrameTarget(id: id, element: element, from: window.frame, to: target))
        }
        guard !targets.isEmpty else { return }

        for target in targets {
            recentWrites[target.id] = WriteRecord(frame: target.to, until: now + 0.45)
        }

        if animated && duration > 0.02 {
            animate(targets, duration: duration)
        } else {
            for target in targets {
                write(target.to, to: target.element, sizeFirst: false)
                markPending(target.id, element: target.element, target: target.to, origin: target.from, attempts: 0)
            }
            scheduleVerification(after: 0.12)
        }
    }

    public func frame(of id: WindowID) -> CGRect? { windows[id]?.frame }

    /// Drops the focused-window pointer after the window vanished (closed, moved, minimised).
    func clearFocused() {
        guard focused != nil else { return }
        focused = nil
        delegate?.engine(self, didFocus: nil)
    }

    public func focus(_ id: WindowID) {
        guard let window = windows[id], let element = window.axElement else { return }
        // Who asked for this? Focus theft is invisible without a caller.
        Log.info("focus -> \(window.appName) / \(id.raw) from \(Thread.callStackSymbols.dropFirst().prefix(3).joined(separator: " <- "))")
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if focused != id {
            focused = id
            delegate?.engine(self, didFocus: window)
        }
    }

    public func toggleFullscreen(_ id: WindowID) {
        guard let element = windows[id]?.axElement else { return }
        let current = element.boolAttribute("AXFullScreen") ?? false
        AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, (current ? kCFBooleanFalse : kCFBooleanTrue) as CFTypeRef)
    }

    public func setMinimized(_ id: WindowID, _ minimized: Bool) {
        guard let element = windows[id]?.axElement else { return }
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, (minimized ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }

    // MARK: - Stubborn windows

    /// The smallest size we have actually seen this window accept, learned by watching a
    /// refused write clamp. `nil` until the app refuses something.
    public func learnedMinimum(_ id: WindowID) -> CGSize? { learnedMinimums[id] }

    public func isStubborn(_ id: WindowID) -> Bool {
        guard let until = stubbornUntil[id] else { return false }
        if CFAbsoluteTimeGetCurrent() > until {
            stubbornUntil[id] = nil
            stubbornReasons[id] = nil
            return false
        }
        return true
    }

    public func stubbornReason(_ id: WindowID) -> String? { stubbornReasons[id] }

    private func markStubborn(_ id: WindowID, reason: String) {
        guard stubbornUntil[id] == nil else { return }
        stubbornUntil[id] = CFAbsoluteTimeGetCurrent() + 180
        stubbornReasons[id] = reason
        let name = windows[id]?.appName ?? "?"
        Log.error("window \(id.raw) (\(name)) marked stubborn for 180s: \(reason)")
        LatticeDiagnostics.record("stubborn \(id.raw) \(name): \(reason)")
        delegate?.engine(self, didMarkStubborn: id, reason: reason)
    }

    // MARK: - Frame writing

    @discardableResult
    private func write(_ rect: CGRect, to element: AXUIElement, sizeFirst: Bool) -> Bool {
        var point = rect.origin
        var size = rect.size
        guard let posValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

        AXPerf.note()
        let positionError: AXError
        let sizeError: AXError
        if sizeFirst {
            AXPerf.note()
            sizeError = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
            positionError = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
        } else {
            positionError = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posValue)
            AXPerf.note()
            sizeError = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        }

        let fatal: Set<AXError> = [.apiDisabled, .invalidUIElement, .illegalArgument,
                                   .attributeUnsupported, .notImplemented]
        if fatal.contains(positionError) || fatal.contains(sizeError) {
            Log.debug("write refused: pos=\(positionError.rawValue) size=\(sizeError.rawValue)")
            return false
        }
        return true
    }

    private func markPending(_ id: WindowID, element: AXUIElement, target: CGRect, origin: CGRect?, attempts: Int) {
        pendingWrites[id] = PendingWrite(element: element,
                                         target: target,
                                         origin: origin,
                                         attempts: attempts,
                                         deadline: CFAbsoluteTimeGetCurrent() + 0.06)
        windows[id]?.frame = target
    }

    private func scheduleVerification(after delay: TimeInterval) {
        verifyWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.verifyPendingWrites() }
        verifyWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func verifyPendingWrites() {
        verifyWorkItem = nil
        guard !pendingWrites.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        var retryScheduled = false

        for (id, pending) in pendingWrites {
            if now < pending.deadline {
                retryScheduled = true
                continue
            }
            let actual = pending.element.frame
            if let actual, actual.isClose(to: pending.target, tolerance: 1.5) {
                pendingWrites[id] = nil
                writeFailures[id] = 0
                windows[id]?.frame = actual
                if let known = learnedMinimums[id], actual.width < known.width - 2 || actual.height < known.height - 2 {
                    learnedMinimums[id] = nil
                }
                continue
            }

            let attempts = pending.attempts + 1
            writeFailures[id] = attempts
            if attempts == 1 {
                // Retry once, size first: some Electron/Java toolkits clamp a size that is
                // applied after a position and then never recover.
                write(pending.target, to: pending.element, sizeFirst: true)
                pendingWrites[id] = PendingWrite(element: pending.element,
                                                 target: pending.target,
                                                 origin: pending.origin,
                                                 attempts: 1,
                                                 deadline: now + 0.12)
                retryScheduled = true
                if let actual {
                    Log.debug("frame retry (size-first) for \(id.raw): wanted \(pending.target) got \(actual)")
                } else {
                    Log.debug("frame retry (size-first) for \(id.raw): frame unreadable")
                }
            } else {
                pendingWrites[id] = nil
                if let actual {
                    windows[id]?.frame = actual
                    // Learn the app's real floor. Many apps clamp to a minimum they never
                    // report through AXMinSize; the failed write is the only source of truth.
                    // Only learn when *something* about the write took effect: a window that
                    // ignores the whole request (wrong Space, fullscreen, app holding it) is
                    // not evidence that its current size is its minimum.
                    let moved = pending.origin.map { !actual.isClose(to: $0, tolerance: 1.5) } ?? true
                    if moved,
                       actual.width > pending.target.width + 1.5 || actual.height > pending.target.height + 1.5 {
                        let learned = CGSize(width: max(actual.width, windows[id]?.minSize?.width ?? 0),
                                             height: max(actual.height, windows[id]?.minSize?.height ?? 0))
                        windows[id]?.minSize = learned
                        learnedMinimums[id] = learned
                        Log.info("learned minimum \(Int(learned.width))x\(Int(learned.height)) for \(windows[id]?.appName ?? "?") (window \(id.raw))")
                    }
                    // The app would not take the tile, so put it back where it was. Leaving it
                    // at the half-applied target is how a Space ends up with windows dumped on
                    // top of each other; "left alone" has to mean untouched.
                    if let origin = pending.origin, !actual.isClose(to: origin, tolerance: 1.5) {
                        write(origin, to: pending.element, sizeFirst: false)
                        windows[id]?.frame = origin
                        Log.info("restored window \(id.raw) (\(windows[id]?.appName ?? "?")) to \(Self.format(origin)) after refusing \(Self.format(pending.target))")
                    }
                    markStubborn(id, reason: "frame mismatch after 2 writes (wanted \(Self.format(pending.target)) got \(Self.format(actual)))")
                } else {
                    markStubborn(id, reason: "frame unreadable after 2 writes")
                }
            }
        }

        if retryScheduled {
            scheduleVerification(after: 0.20)
        }
    }

    // MARK: - Animation

    private func animate(_ targets: [FrameTarget], duration: TimeInterval) {
        animationTimer?.invalidate()
        animationToken += 1
        let token = animationToken
        let steps = max(4, min(16, Int(duration * 60)))
        let interval = duration / Double(steps)
        var step = 0

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self, self.animationToken == token else {
                timer.invalidate()
                return
            }
            step += 1
            let t = min(1.0, Double(step) / Double(steps))
            let eased = 1 - pow(1 - t, 3)
            for target in targets {
                let rect = CGRect(
                    x: target.from.origin.x + (target.to.origin.x - target.from.origin.x) * eased,
                    y: target.from.origin.y + (target.to.origin.y - target.from.origin.y) * eased,
                    width: target.from.width + (target.to.width - target.from.width) * eased,
                    height: target.from.height + (target.to.height - target.from.height) * eased
                )
                self.write(rect, to: target.element, sizeFirst: false)
                self.recentWrites[target.id] = WriteRecord(frame: target.to, until: CFAbsoluteTimeGetCurrent() + 0.45)
            }
            if step >= steps {
                timer.invalidate()
                self.animationTimer = nil
                for target in targets {
                    self.markPending(target.id, element: target.element, target: target.to, origin: target.from, attempts: 0)
                    self.windows[target.id]?.frame = target.to
                }
                self.scheduleVerification(after: 0.12)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    // MARK: - Focus

    private func updateFocusedWindow() {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedApp = systemWide.elementAttribute(kAXFocusedApplicationAttribute) else {
            // Same transient case: keep the last known window rather than dropping focus.
            return
        }
        guard let axWindow = focusedApp.elementAttribute(kAXFocusedWindowAttribute) else {
            // Many apps report no focused window for a beat during activation, and the
            // system-wide query can come back empty while the app is switching. Clearing the
            // pointer here made arrow-key focus die one step after every successful switch:
            // `focus -> Open Design` was immediately followed by `focused = nil`. Keep the last
            // known window instead; `pruneOrder` clears it when that window actually vanishes.
            return
        }
        guard let wid = windowID(of: axWindow, pid: nil), windows[wid] != nil else {
            // The focused AX window can be a sheet, a palette, or a window we deliberately do
            // not manage. Recording its id made `focusedApp` (and every arrow-key command)
            // point at a window that is not in the tile order. Keep the last managed window.
            return
        }
        if focused != wid {
            focused = wid
            delegate?.engine(self, didFocus: windows[wid])
        }
    }

    // MARK: - Workspace + observers

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let launch = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.scheduleFullRefresh(reason: "launch")
        }
        let terminate = center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                           object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self.removeApp(app.processIdentifier)
                self.delegate?.engineDidChangeWindows(self)
            }
            self.scheduleFullRefresh(reason: "terminate")
        }
        let activate = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                          object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.updateFocusedWindow()
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self.scheduleFrameRefresh(pid: app.processIdentifier, reason: "activate")
                }
            }
        }
        let spaceChange = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                             object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.visibleCache = ([], 0)
            LatticeDiagnostics.record("space changed, refreshing")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                self.refresh(reason: "space-change")
                self.delegate?.engineSpaceDidChange(self)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.refresh(reason: "space-settle")
            }
        }
        workspaceObservers.append(contentsOf: [launch, terminate, activate, spaceChange])
    }

    private func observeScreens() {
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.visibleCache = ([], 0)
            self.refresh(reason: "screens")
            self.delegate?.engineSpaceDidChange(self)
        }
        workspaceObservers.append(token)
    }

    private func registerObserver(for pid: pid_t, axApp: AXUIElement) {
        guard axObservers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let engine = Unmanaged<WindowEngine>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let name = notification as String
            DispatchQueue.main.async {
                engine.handleAXNotification(name: name, element: element, pid: pid)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.watchedNotifications {
            AXObserverAddNotification(observer, axApp, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObservers[pid] = observer
    }

    private func removeApp(_ pid: pid_t) {
        if let observer = axObservers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        removeWindows(pid: pid)
        appEntries[pid] = nil
    }

    private func removeWindows(pid: pid_t) {
        for id in windows.filter({ $0.value.pid == pid }).keys {
            windows[id] = nil
            pendingWrites[id] = nil
            recentWrites[id] = nil
            writeFailures[id] = nil
            stubbornUntil[id] = nil
            stubbornReasons[id] = nil
        }
    }

    // MARK: - Notification batching

    private func handleAXNotification(name: String, element: AXUIElement, pid: pid_t) {
        let now = CFAbsoluteTimeGetCurrent()
        if now - burstStart > 0.1 {
            burstStart = now
            burstCount = 0
        }
        burstCount += 1

        switch name {
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            updateFocusedWindow()
            scheduleFrameRefresh(pid: resolvePid(pid, element: element), reason: name)

        case kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
             kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            scheduleStructuralRefresh(pid: resolvePid(pid, element: element), reason: name)

        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            if suppressOwnWrite(element: element) { return }
            scheduleFrameRefresh(pid: resolvePid(pid, element: element), reason: name)

        case kAXTitleChangedNotification:
            scheduleFrameRefresh(pid: resolvePid(pid, element: element), reason: name)

        default:
            scheduleFrameRefresh(pid: resolvePid(pid, element: element), reason: name)
        }
    }

    private func resolvePid(_ pid: pid_t, element: AXUIElement) -> pid_t {
        if pid > 0 { return pid }
        var value: pid_t = 0
        AXUIElementGetPid(element, &value)
        return value
    }

    /// Our own frame writes bounce back as moved/resized notifications. Absorb them inside a
    /// short quiet window instead of re-enumerating (which is what made the old engine loop).
    private func suppressOwnWrite(element: AXUIElement) -> Bool {
        guard let wid = windowID(of: element, pid: nil),
              let record = recentWrites[wid] else { return false }
        let now = CFAbsoluteTimeGetCurrent()
        guard record.until > now else {
            recentWrites[wid] = nil
            return false
        }
        windows[wid]?.frame = record.frame
        return true
    }

    private func scheduleStructuralRefresh(pid: pid_t, reason: String) {
        pendingPids.insert(pid)
        pendingStructural = true
        LatticeDiagnostics.record("notification \(reason) pid \(pid) (structural)")
        scheduleDrain()
    }

    private func scheduleFrameRefresh(pid: pid_t, reason: String) {
        guard pid > 0 else { return }
        pendingPids.insert(pid)
        scheduleDrain()
        _ = reason
    }

    private func scheduleFullRefresh(reason: String) {
        Log.debug("full refresh scheduled: \(reason)")
        pendingStructural = true
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshWorkItem = nil
            self?.pendingPids.removeAll()
            self?.pendingStructural = false
            self?.refresh(reason: reason)
        }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: item)
    }

    private func scheduleDrain() {
        guard refreshWorkItem == nil else { return }
        // Five or more notifications inside 100 ms means a burst (window animation, app launch,
        // tab switch). Wait for the burst to settle, then do one pass.
        let delay = burstCount >= 5 ? 0.16 : 0.10
        let item = DispatchWorkItem { [weak self] in self?.drainNotifications() }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func drainNotifications() {
        refreshWorkItem = nil
        let pids = pendingPids
        let structural = pendingStructural
        pendingPids.removeAll()
        pendingStructural = false
        burstCount = 0
        guard !pids.isEmpty else { return }

        let snapshot = Self.cgSnapshot()
        var changed = false
        var frameChanges: [WindowID] = []

        for pid in pids {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy == .regular,
               pid != getpid() {
                let result = rebuildApp(pid: pid, app: app, cg: snapshot, reason: "notification", notify: false)
                changed = changed || result.structural
                frameChanges.append(contentsOf: result.framesChanged)
            } else {
                removeApp(pid)
                changed = true
            }
        }

        if changed || structural {
            updateFocusedWindow()
            delegate?.engineDidChangeWindows(self)
        } else if !frameChanges.isEmpty {
            delegate?.engine(self, didUpdateFrames: frameChanges)
        }
    }

    // MARK: - Helpers

    public func visibleSpaceIDs() -> Set<SpaceID> {
        let now = CFAbsoluteTimeGetCurrent()
        if now - visibleCache.at < 0.25 { return visibleCache.ids }
        let ids = spaces.visibleSpaceIDs()
        visibleCache = (ids, now)
        return ids
    }

    private func logSkipOnce(_ id: WindowID, _ reason: String, app: String? = nil) {
        let key = "\(id.raw):\(reason)"
        guard !loggedSkips.contains(key) else { return }
        loggedSkips.insert(key)
        if loggedSkips.count > 500 { loggedSkips.removeAll() }
        let name = app ?? windows[id]?.appName ?? "?"
        Log.info("skip window \(id.raw) (\(name)): \(reason)")
    }

    private func windowID(of element: AXUIElement, pid: pid_t?) -> WindowID? {
        if let fn = Self.getWindowFn {
            var wid: CGWindowID = 0
            if fn(element, &wid) == .success, wid != 0 {
                return WindowID(wid)
            }
        }
        // Some apps expose AXWindowNumber even when the private call is absent.
        if let number = element.copyAttribute("AXWindowNumber") as? NSNumber, number.uint32Value != 0 {
            return WindowID(number.uint32Value)
        }
        // Last resort: a stable synthetic identity derived from pid + title. Collisions are
        // possible for apps with several identically-titled windows, but this path only runs
        // when _AXUIElementGetWindow is missing entirely.
        var actualPid = pid ?? 0
        if actualPid == 0 { AXUIElementGetPid(element, &actualPid) }
        let title = element.stringAttribute(kAXTitleAttribute) ?? element.stringAttribute(kAXRoleAttribute) ?? "window"
        let key = "\(actualPid)|\(title)"
        if let existing = syntheticIDs[key] { return existing }
        nextSyntheticID &+= 1
        let id = WindowID(nextSyntheticID)
        syntheticIDs[key] = id
        Log.error("windowID fallback in use for pid \(actualPid) title \"\(title)\" -> \(id.raw)")
        return id
    }

    private static let getWindowFnCompat: Void = {
        if getWindowFn == nil { Log.error("_AXUIElementGetWindow unavailable; using pid+title hashing") }
    }()

    /// AXValue → CGSize, for the min/max size attributes.
    static func cgSize(from value: AXValue) -> CGSize? {
        guard AXValueGetType(value) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return size
    }

    static func windowID(of element: AXUIElement) -> WindowID? {
        _ = getWindowFnCompat
        guard let fn = getWindowFn else { return nil }
        var wid: CGWindowID = 0
        guard fn(element, &wid) == .success, wid != 0 else { return nil }
        return WindowID(wid)
    }

    static func display(containing point: CGPoint, screens: [NSScreen]) -> DisplayID {
        let primaryHeight = screens.first?.frame.height ?? 0
        for screen in screens {
            let flipped = CGRect(x: screen.frame.origin.x,
                                 y: primaryHeight - screen.frame.maxY,
                                 width: screen.frame.width,
                                 height: screen.frame.height)
            if flipped.contains(point) {
                return SpaceManager.displayID(for: screen)
            }
        }
        return screens.first.map(SpaceManager.displayID(for:)) ?? DisplayID(0)
    }

    static func display(for rect: CGRect, screens: [NSScreen]) -> DisplayID {
        let primaryHeight = screens.first?.frame.height ?? 0
        var best: (DisplayID, CGFloat)?
        for screen in screens {
            let flipped = CGRect(x: screen.frame.origin.x,
                                 y: primaryHeight - screen.frame.maxY,
                                 width: screen.frame.width,
                                 height: screen.frame.height)
            let overlap = flipped.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.1 {
                best = (SpaceManager.displayID(for: screen), area)
            }
        }
        return best?.0 ?? display(containing: rect.center, screens: screens)
    }

    /// True while the physical left mouse button is down over `windowFrame` — a resize right
    /// now would fight the user's hand.
    static func isDragging(windowFrame: CGRect?) -> Bool {
        let buttonDown = (NSEvent.pressedMouseButtons & 0x1) != 0
            || CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard buttonDown else { return false }
        guard let frame = windowFrame, !frame.isEmpty else { return false }
        guard let pointer = CGEvent(source: nil)?.location else { return true }
        return frame.insetBy(dx: -12, dy: -12).contains(pointer)
    }

    private static func cgSnapshot() -> CGSnapshot {
        var snapshot = CGSnapshot()
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return snapshot
        }
        for info in list {
            guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let id = WindowID(number.uint32Value)
            if let layer = info[kCGWindowLayer as String] as? NSNumber {
                snapshot.layer[id] = layer.intValue
            }
            if let alpha = info[kCGWindowAlpha as String] as? NSNumber {
                snapshot.alpha[id] = alpha.doubleValue
            }
            if let dict = info[kCGWindowBounds as String] as? [String: Any],
               let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) {
                snapshot.bounds[id] = bounds
            }
            if let onscreen = info[kCGWindowIsOnscreen as String] as? NSNumber, onscreen.boolValue {
                snapshot.onscreen.insert(id)
            }
        }
        return snapshot
    }

    private static func format(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
}

// MARK: - Geometry helpers

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 1.0) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

// MARK: - AX conveniences

extension AXUIElement {
    func copyAttribute(_ attribute: String) -> AnyObject? {
        AXPerf.note()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    /// Fetches many attributes in one AX round-trip. Returns only the attributes that exist;
    /// callers must fall back to per-attribute reads when this comes back empty.
    func batchAttributes(_ names: [String]) -> [String: AnyObject] {
        AXPerf.note()
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            self,
            names as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )
        guard error == .success, let array = values as? [AnyObject] else { return [:] }
        var result: [String: AnyObject] = [:]
        for (index, name) in names.enumerated() where index < array.count {
            let value = array[index]
            if value is NSNull { continue }
            result[name] = value
        }
        return result
    }

    func stringAttribute(_ attribute: String) -> String? {
        copyAttribute(attribute) as? String
    }

    func boolAttribute(_ attribute: String) -> Bool? {
        (copyAttribute(attribute) as? NSNumber)?.boolValue
    }

    func elementAttribute(_ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(attribute) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    var frame: CGRect? {
        let batch = batchAttributes([kAXPositionAttribute, kAXSizeAttribute])
        if let rect = AXUIElement.frame(from: batch) { return rect }
        guard let posValue = copyAttribute(kAXPositionAttribute),
              let sizeValue = copyAttribute(kAXSizeAttribute) else { return nil }
        return AXUIElement.rect(from: posValue, size: sizeValue)
    }

    static func frame(from values: [String: AnyObject]) -> CGRect? {
        guard let pos = values[kAXPositionAttribute], let size = values[kAXSizeAttribute] else { return nil }
        return rect(from: pos, size: size)
    }

    private static func rect(from posValue: AnyObject, size sizeValue: AnyObject) -> CGRect? {
        var point = CGPoint.zero
        var size = CGSize.zero
        guard CFGetTypeID(posValue) == AXValueGetTypeID(),
              AXValueGetValue(posValue as! AXValue, .cgPoint, &point) else { return nil }
        guard CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    func apply(frame: CGRect, sizeFirst: Bool = false) -> Bool {
        var point = frame.origin
        var size = frame.size
        guard let posValue = AXValueCreate(.cgPoint, &point),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

        AXPerf.note()
        if sizeFirst {
            AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, sizeValue)
            AXPerf.note()
            return AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, posValue) == .success
        } else {
            let position = AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, posValue)
            AXPerf.note()
            let size = AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, sizeValue)
            return position == .success && size == .success
        }
    }
}
