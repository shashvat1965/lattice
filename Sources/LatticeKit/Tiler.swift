import Foundation
import AppKit
import CoreGraphics

public protocol TilerDelegate: AnyObject {
    func tilerDidUpdate(_ tiler: Tiler, space: SpaceID, windows: [ManagedWindow])
    func tiler(_ tiler: Tiler, didFail message: String)
    /// A sentence about how this Space had to be arranged, or nil when the chosen layout was
    /// used exactly as asked. Used by the UI to explain "Space full" instead of looking broken.
    func tiler(_ tiler: Tiler, didReportNote note: String?, space: SpaceID)
}

public extension TilerDelegate {
    func tiler(_ tiler: Tiler, didReportNote note: String?, space: SpaceID) {}
}

public extension Notification.Name {
    /// Posted when macOS refuses a cross-Space move, so the UI can open Mission Control and
    /// tell the person to drag the window thumbnail onto the target Desktop.
    static let latticeManualSpaceMove = Notification.Name("lattice.manualSpaceMove")
}

/// Owns the tile order for each real Space and applies layout maths to it.
///
/// Safety rules:
///  * `reconcile` never re-enters. A call that arrives while we are tiling is coalesced into
///    one follow-up pass.
///  * Only Spaces that are on-screen right now are ever written to.
///  * A window the user is dragging is left alone for that pass.
///  * A window whose app refuses AX geometry twice is excluded (and reported) instead of
///    being fought forever.
///
/// Preferences are honoured end to end: gaps/edges/per-display overrides feed the geometry,
/// tuning values feed the layout maths, and rules decide what is allowed to be tiled at all.
public final class Tiler {

    public weak var delegate: TilerDelegate?
    public let engine: WindowEngine
    public var prefs: Preferences { PreferencesStore.shared.prefs }

    public private(set) var order: [SpaceID: [WindowID]] = [:]
    public private(set) var floating: Set<WindowID> = []
    public private(set) var weights: [SpaceID: [CGFloat]] = [:]
    public private(set) var focusModeSpace: SpaceID?
    public private(set) var focusModeRestore: [SpaceID: [WindowID]] = [:]
    public private(set) var isReconciling = false

    public var isSuspended = false

    /// Logged snapshots of what each window was last asked to be, used for undo and for
    /// carrying a tile slot across a browser tab swap.
    public private(set) var lastFrames: [WindowID: CGRect] = [:]

    private let spaces = SpaceManager.shared
    private var undoStack: [[WindowID: CGRect]] = []
    private var needsReconcile = false
    private var followUpScheduled = false

    // Rule bookkeeping. Layout rules apply once per (Space, app, layout); Space rules once per
    // window, so a refused move can never become a retry loop.
    private var appliedLayoutRules: Set<String> = []
    private var appliedSpaceRules: Set<WindowID> = []
    private var pendingSpaceMoves: Set<WindowID> = []
    private var loggedRuleNotes: Set<String> = []
    /// The last tile that actually had keyboard focus on each Space. A brand-new window is usually
    /// focused the instant it appears, so `afterFocused` must anchor on the tile focus came from.
    private var focusAnchors: [SpaceID: WindowID] = [:]
    /// Set when an order change happens while tiling is suspended (the app's drag-to-swap path);
    /// the next `reconcile(animated:)` is a layout swap, not an ordinary retile.
    private var pendingSwapAnimation = false

    public init(engine: WindowEngine) {
        self.engine = engine
        TilerHolder.shared = self
    }

    deinit {
        if TilerHolder.shared === self { TilerHolder.shared = nil }
    }

    // MARK: - Reconciliation

    public func reconcile(animated: Bool = true, reason: MotionReason = .general) {
        guard !isSuspended, prefs.enabled else { return }
        if prefs.verboseLogging { Log.verbose = true }
        // A suspended batch of `move` calls is a swap once it finally reconciles.
        var reason = reason
        if reason == .general, pendingSwapAnimation {
            pendingSwapAnimation = false
            reason = .layoutSwap
        }
        guard !isReconciling else {
            needsReconcile = true
            LatticeDiagnostics.record("reconcile re-entered; coalescing")
            return
        }

        isReconciling = true
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            isReconciling = false
            if needsReconcile {
                needsReconcile = false
                scheduleFollowUp()
            }
        }

        pruneOrder()

        var tiles = 0
        var spacesTiled = 0
        for (space, display) in visibleSpaces() {
            if tile(space: space, display: display, animated: animated, reason: reason) {
                spacesTiled += 1
                tiles += (order[space] ?? []).filter { !isFloating($0) }.count
            }
        }

        let ms = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        LatticeDiagnostics.record(String(format: "reconcile: %d spaces, %d tiles, %.1f ms",
                                         spacesTiled, tiles, ms))
    }

    private func scheduleFollowUp() {
        guard !followUpScheduled else { return }
        followUpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.followUpScheduled = false
            self.reconcile(animated: false)
        }
    }

    /// Drops windows from every Space's tile order as soon as WindowServer says they left.
    /// Idempotent: a window that moved once disappears from its old Space exactly once.
    ///
    /// This is also where `autoBalance` lives: when a window closes, a balancing Space goes back
    /// to equal shares; with it off, the surviving windows keep the splits the user dragged.
    private func pruneOrder() {
        let liveSpaces: [SpaceID: Set<WindowID>] = Dictionary(grouping: engine.windows.values, by: \.space)
            .mapValues { Set($0.map(\.id)) }

        for space in Array(order.keys) {
            guard let ids = order[space] else { continue }
            let live = liveSpaces[space] ?? []
            let kept = ids.filter { live.contains($0) }
            guard kept.count != ids.count else { continue }

            let oldTiled = ids.filter { !isFloating($0) }
            let newTiled = kept.filter { !isFloating($0) }
            let existing = weights[space] ?? []
            let balanced = WeightBalancing.afterClose(existing: existing,
                                                      previousTiled: oldTiled,
                                                      surviving: newTiled,
                                                      autoBalance: prefs.autoBalance)
            weights[space] = balanced.isEmpty ? nil : balanced
            if prefs.autoBalance {
                LatticeDiagnostics.record("auto-balance: space \(space.raw) reset \(newTiled.count) weight(s) after \(ids.count - kept.count) close(s)")
            } else {
                LatticeDiagnostics.record("auto-balance off: space \(space.raw) kept \(newTiled.count) weight(s)")
            }

            LatticeDiagnostics.record("prune \(space.raw): removed \(ids.count - kept.count) window(s)")
            order[space] = kept.isEmpty ? nil : kept
        }

        let known = Set(engine.windows.keys)
        let staleFloating = floating.subtracting(known)
        if !staleFloating.isEmpty {
            floating.subtract(staleFloating)
        }
        pendingSpaceMoves.formIntersection(known)
        appliedSpaceRules.formIntersection(known)
        for (space, anchor) in focusAnchors where !known.contains(anchor) {
            focusAnchors[space] = nil
        }
        if loggedRuleNotes.count > 500 { loggedRuleNotes.removeAll() }
        if let focused = engine.focused, !known.contains(focused) {
            engine.focusFirstAvailable()
        }
    }

    @discardableResult
    private func tile(space: SpaceID, display: DisplayInfo, animated: Bool, reason: MotionReason) -> Bool {
        let live = engine.windows(on: space)
        guard !live.isEmpty else {
            if order[space] != nil || weights[space] != nil {
                order[space] = nil
                weights[space] = nil
            }
            return false
        }

        // Rules run before order/geometry: a layout rule can change what this Space is about to
        // render, and a Space rule removes the window from this pass entirely.
        applyRules(live: live, space: space, display: display)

        let liveSet = Set(live.map(\.id))
        let liveIDs = live
            .filter { !prefs.isUnmanaged($0.bundleID) && !pendingSpaceMoves.contains($0.id) }
            .map(\.id)

        let oldOrder = order[space] ?? []
        let previousTiled = oldOrder.filter { liveIDs.contains($0) && !isFloating($0) }

        var ids = oldOrder.filter { liveIDs.contains($0) }
        // Focus mode deliberately narrows the Space to the focused window. New windows must not
        // silently rejoin the layout until the mode is switched off.
        let appeared = focusModeSpace == space ? [] : liveIDs.filter { !ids.contains($0) }

        // The insertion anchor is the focused tile if it is already in this Space's order;
        // otherwise the tile focus came from before the new window stole it.
        let insertionAnchor = TilerOrdering.anchor(currentFocus: engine.focused,
                                                   in: ids,
                                                   last: focusAnchors[space])

        if !appeared.isEmpty && !oldOrder.isEmpty {
            // A tab switch in some browsers swaps the AX window identity while the tile stays
            // put. Carry the old slot forward when a new window lands where the vanished one
            // was, so the whole Space does not reshuffle.
            var unmatched = appeared
            var carried: [WindowID] = []
            for id in oldOrder {
                if liveIDs.contains(id) {
                    carried.append(id)
                    continue
                }
                if liveSet.contains(id) {
                    // Still alive but excluded by a rule (unmanaged, pending move): drop it.
                    continue
                }
                guard let previousFrame = lastFrames[id] else { continue }
                if let index = unmatched.firstIndex(where: { candidate in
                    guard let frame = engine.window(candidate)?.frame else { return false }
                    return abs(frame.minX - previousFrame.minX) < 40
                        && abs(frame.minY - previousFrame.minY) < 40
                        && abs(frame.width - previousFrame.width) < 40
                        && abs(frame.height - previousFrame.height) < 40
                }) {
                    let replacement = unmatched.remove(at: index)
                    carried.append(replacement)
                    LatticeDiagnostics.record("space \(space.raw): carried slot \(id.raw) -> \(replacement.raw) after identity swap")
                }
            }
            let inserted = TilerOrdering.inserting(unmatched, into: carried,
                                                   policy: prefs.insertionPolicy,
                                                   focused: insertionAnchor)
            ids = inserted.order
            for (window, index) in zip(unmatched, inserted.indices) {
                let message = "insert \(window.raw) at \(index) in space \(space.raw) (\(prefs.insertionPolicy.rawValue))"
                LatticeDiagnostics.record(message)
                Log.info(message)
            }
        } else if !appeared.isEmpty {
            let inserted = TilerOrdering.inserting(appeared, into: ids,
                                                   policy: prefs.insertionPolicy,
                                                   focused: insertionAnchor)
            ids = inserted.order
            for (window, index) in zip(appeared, inserted.indices) {
                let message = "insert \(window.raw) at \(index) in space \(space.raw) (\(prefs.insertionPolicy.rawValue))"
                LatticeDiagnostics.record(message)
                Log.info(message)
            }
        }
        order[space] = ids
        if let focused = engine.focused, ids.contains(focused) {
            focusAnchors[space] = focused
        } else if focusAnchors[space] == nil, let first = ids.first {
            focusAnchors[space] = first
        }

        let tileable = ids.filter { !isFloating($0) }
        guard !tileable.isEmpty else {
            weights[space] = nil
            LatticeDiagnostics.record("space \(space.raw): \(ids.count) windows, all floating or excluded")
            delegate?.tilerDidUpdate(self, space: space, windows: live)
            return true
        }

        let spaceWeights = mappedWeights(space: space, previousTiled: previousTiled, tileable: tileable)
        weights[space] = spaceWeights

        let content = TilingGeometry.contentRect(for: display, prefs: prefs)
        let gap = max(0, prefs.innerGap(for: display.id))
        let layout = TilingGeometry.resolvedLayout(space: space, display: display, prefs: prefs)
        let focusIndex = engine.focused.flatMap { tileable.firstIndex(of: $0) } ?? 0

        let solution = TilingSolver.solve(count: tileable.count,
                                          content: content,
                                          gap: gap,
                                          layout: layout,
                                          weights: spaceWeights,
                                          focusIndex: focusIndex,
                                          masterRatio: prefs.masterRatio,
                                          stackPeek: prefs.stackPeek,
                                          gridColumns: prefs.gridColumns,
                                          minimum: TilingGeometry.effectiveMinimum(prefs),
                                          minimums: tileable.map { minimumSize(for: $0) },
                                          respectMinimums: !prefs.tileCrowdedSpaces)
        if let note = solution.note {
            LatticeDiagnostics.record("space \(space.raw): \(note)")
            Log.info("space \(space.raw): \(note)")
        }
        delegate?.tiler(self, didReportNote: solution.note, space: space)

        // If the solver had to leave any window out because the display cannot hold them all
        // at their own minimum sizes, move nothing at all. Tiling "as many as fit" rotates
        // which window gets the one big slot every time the order changes, and the result is
        // two windows stacked in the same rectangle. A Space that cannot be tiled is better
        // left exactly as the user had it, with an explanation.
        if solution.skipped > 0 {
            let message = "space \(space.raw): \(solution.placedCount) of \(tileable.count) windows fit; leaving the Space untouched"
            LatticeDiagnostics.record(message)
            Log.info(message)
            delegate?.tilerDidUpdate(self, space: space, windows: live)
            return true
        }

        var targets: [(id: WindowID, frame: CGRect)] = []
        for (index, id) in tileable.enumerated() {
            guard solution.frames.indices.contains(index), let target = solution.frames[index] else {
                LatticeDiagnostics.record("space \(space.raw): leave \(id.raw) untiled (no safe frame)")
                continue
            }
            lastFrames[id] = target
            // A stubborn window is skipped only while we have nothing better to offer it.
            // Once a refused write has taught us its real floor, it can be planned for.
            if engine.isStubborn(id), engine.learnedMinimum(id) == nil {
                LatticeDiagnostics.record("space \(space.raw): skip stubborn window \(id.raw)")
                continue
            }
            targets.append((id, target))
        }

        place(targets, animated: animated, reason: reason, context: "space \(space.raw)")

        // A refused write is learned asynchronously by the engine; remember it shortly after
        // so the next launch starts from the truth instead of re-learning it window by window.
        let learnedIDs = tileable
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.persistLearnedMinimums(for: learnedIDs)
        }

        LatticeDiagnostics.record("space \(space.raw): \(tileable.count) tiled, \(ids.count - tileable.count) floating, layout \(solution.layout.rawValue)"
                                  + (solution.skipped > 0 ? ", \(solution.skipped) deferred" : ""))
        delegate?.tilerDidUpdate(self, space: space, windows: live)
        return true
    }

    /// Maps the Space's existing weight vector onto its new tile order. New windows get a weight
    /// of 1 (a real share, not a reset); closers have already been handled by `pruneOrder`.
    private func mappedWeights(space: SpaceID,
                               previousTiled: [WindowID],
                               tileable: [WindowID]) -> [CGFloat] {
        let existing = weights[space] ?? []
        guard existing.count == previousTiled.count, !existing.isEmpty else {
            return Array(repeating: 1, count: tileable.count)
        }
        return tileable.map { id in
            if let index = previousTiled.firstIndex(of: id), existing.indices.contains(index) {
                return existing[index]
            }
            return 1
        }
    }

    // MARK: - Motion

    /// Single path for every frame write in the tiler, so the curve, Reduce Motion, the snap
    /// switch and the layout-swap switch are decided in exactly one place.
    private func place(_ targets: [(id: WindowID, frame: CGRect)],
                       animated: Bool,
                       reason: MotionReason,
                       context: String) {
        // Never touch a window that is already where it belongs: a focus change must not
        // rewrite (and therefore animate) the whole Space under the user's cursor.
        let slack: CGFloat = 0.5
        let pending = targets.filter { target in
            guard let current = engine.frame(of: target.id) else { return true }
            return abs(current.minX - target.frame.minX) > slack
                || abs(current.minY - target.frame.minY) > slack
                || abs(current.width - target.frame.width) > slack
                || abs(current.height - target.frame.height) > slack
        }
        guard !pending.isEmpty else {
            LatticeDiagnostics.record("motion \(context): nothing to do (already placed)")
            return
        }
        let targets = pending
        let curve = prefs.animationCurve

        guard animated, MotionPolicy.allowsAnimation(prefs, reason: reason) else {
            LatticeDiagnostics.record("motion \(context): instant (reason \(reason.rawValue))")
            for target in targets {
                engine.setFrame(target.frame, for: [target.id], animated: false, duration: 0)
            }
            return
        }

        LatticeDiagnostics.record(String(format: "motion %@: %d frame(s), curve %@, %.0f ms",
                                         context, targets.count, curve.rawValue,
                                         prefs.animationDuration * 1000))
        Log.debug(String(format: "motion %@: curve %@ for %d window(s)",
                         context, curve.rawValue, targets.count))
        FrameAnimator.shared.animate(engine: engine,
                                     targets: targets,
                                     duration: prefs.animationDuration,
                                     curve: curve)
    }

    /// Spaces that are actually on-screen right now. Windows on other Spaces are never touched,
    /// which is what keeps Mission Control honest.
    public func visibleSpaces() -> [(SpaceID, DisplayInfo)] {
        var result: [(SpaceID, DisplayInfo)] = []
        var seen = Set<DisplayID>()
        for entry in spaces.displaySpaces() {
            guard let current = entry.current else { continue }
            guard !seen.contains(entry.display) else { continue }
            guard let display = displayInfo(for: entry.display) else { continue }
            seen.insert(entry.display)
            result.append((current, display))
        }
        return result
    }

    public func displayInfo(for id: DisplayID) -> DisplayInfo? {
        for screen in NSScreen.screens {
            guard SpaceManager.displayID(for: screen) == id else { continue }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let flipped = CGRect(x: screen.frame.origin.x,
                                 y: primaryHeight - screen.frame.maxY,
                                 width: screen.frame.width,
                                 height: screen.frame.height)
            let visible = CGRect(x: screen.visibleFrame.origin.x,
                                 y: primaryHeight - screen.visibleFrame.maxY,
                                 width: screen.visibleFrame.width,
                                 height: screen.visibleFrame.height)
            return DisplayInfo(id: id,
                               frame: flipped,
                               visibleFrame: visible,
                               name: screen.localizedName,
                               hasNotch: screen.safeAreaInsets.top > 0 && screen.frame.maxY >= primaryHeight,
                               scale: screen.backingScaleFactor)
        }
        return nil
    }

    /// The rectangle tiles may occupy on a display: visible frame (or full frame when the Dock
    /// is ignored), minus menu bar/notch, per-edge margins and outer padding.
    public func contentRect(for display: DisplayInfo) -> CGRect {
        TilingGeometry.contentRect(for: display, prefs: prefs)
    }

    // MARK: - Rules

    /// Applies model rules to the live windows of one Space. Everything here is idempotent:
    /// layout rules record (Space, app, layout) once; Space rules record the window once, so a
    /// refused WindowServer move cannot become a loop.
    private func applyRules(live: [ManagedWindow], space: SpaceID, display: DisplayInfo) {
        for window in live {
            guard let bundle = window.bundleID else { continue }
            let rule = prefs.rule(for: bundle)

            if prefs.isUnmanaged(bundle) {
                noteOnce("unmanaged|\(bundle)") { "rule: \(bundle) is unmanaged; never tiled or touched" }
                continue
            }
            if prefs.shouldFloat(bundle) {
                noteOnce("float|\(bundle)") { "rule: \(bundle) floats" }
            }
            if let layout = rule?.layout {
                applyLayoutRule(layout, bundle: bundle, space: space, display: display)
            }
            if let number = rule?.spaceNumber, number > 0 {
                applySpaceRule(window, number: number, display: display)
            }
            if let needle = rule?.titleContains, !needle.isEmpty,
               window.title.localizedCaseInsensitiveContains(needle) {
                noteOnce("title|\(window.id.raw)|\(needle)") {
                    "rule: \(bundle) title matches “\(needle)”; window \(window.id.raw) floats"
                }
            }
        }
    }

    private func applyLayoutRule(_ layout: LayoutKind,
                                 bundle: String,
                                 space: SpaceID,
                                 display: DisplayInfo) {
        let key = "\(space.raw)|\(bundle)|\(layout.rawValue)"
        guard !appliedLayoutRules.contains(key) else { return }
        appliedLayoutRules.insert(key)

        guard prefs.layout(for: space) != layout else {
            LatticeDiagnostics.record("rule: \(bundle) already uses \(layout.rawValue) on space \(space.raw)")
            return
        }

        LatticeDiagnostics.record("rule: \(bundle) switches space \(space.raw) to \(layout.rawValue) (display \(display.id.raw))")
        Log.info("rule: \(bundle) -> layout \(layout.rawValue) for space \(space.raw)")
        PreferencesStore.shared.update { $0.setLayout(layout, for: space) }
    }

    private func applySpaceRule(_ window: ManagedWindow, number: Int, display: DisplayInfo) {
        guard !appliedSpaceRules.contains(window.id),
              !pendingSpaceMoves.contains(window.id) else { return }

        let entry = spaces.spaceFor(displayID: display.id)
        let users = entry.userSpaceIDs
        guard users.indices.contains(number - 1) else {
            appliedSpaceRules.insert(window.id)
            noteOnce("space-missing|\(window.id.raw)") {
                "rule: display \(display.id.raw) has no Space \(number); leaving \(window.id.raw) where it is"
            }
            return
        }

        let target = users[number - 1]
        appliedSpaceRules.insert(window.id)
        if window.space == target || spaces.space(for: window.id) == target {
            LatticeDiagnostics.record("rule: window \(window.id.raw) already on space \(target.raw)")
            return
        }

        pendingSpaceMoves.insert(window.id)
        noteOnce("space|\(window.id.raw)") {
            "rule: sending window \(window.id.raw) to space \(target.raw) (Space \(number) on display \(display.id.raw))"
        }
        sendWindow(window.id, from: window.space, to: target, on: display.id, follow: false)
    }

    private func noteOnce(_ key: String, _ message: () -> String) {
        guard loggedRuleNotes.insert(key).inserted else { return }
        let text = message()
        LatticeDiagnostics.record(text)
        Log.info(text)
    }

    public func isFloating(_ id: WindowID) -> Bool {
        // Stubborn means "this app refused a frame". In the default leave-alone mode that
        // window is effectively floating; in tile-anyway mode it stays in the layout (its
        // frame is just clamped) and only pauses for a few seconds.
        if engine.isStubborn(id), !prefs.tileCrowdedSpaces { return true }
        if floating.contains(id) { return true }
        guard let window = engine.window(id) else { return true }
        if window.isFloating || window.isFullscreen || window.isMinimized { return true }

        let prefs = self.prefs
        if prefs.isUnmanaged(window.bundleID) { return true }
        if prefs.shouldFloat(window.bundleID) { return true }
        // Older builds stored app *names* in floatApps; keep honouring that too.
        if prefs.floatApps.contains(window.appName) { return true }
        if let needle = prefs.rule(for: window.bundleID)?.titleContains, !needle.isEmpty,
           window.title.localizedCaseInsensitiveContains(needle) {
            return true
        }
        return false
    }

    // MARK: - Ordering operations

    public func focusedSpace() -> SpaceID {
        // A command should act on the Space the focused window is on, even when the pointer
        // has wandered to another display.
        if let focused = engine.focused,
           let window = engine.window(focused),
           window.space.raw != 0 {
            return window.space
        }
        return spaces.focusedSpace() ?? SpaceID(0)
    }

    /// The display that owns the focused window; falls back to the pointer's display.
    public func focusedDisplay() -> DisplayID {
        if let focused = engine.focused {
            if let display = spaces.displayID(for: focused) { return display }
            if let window = engine.window(focused) { return window.display }
        }
        if let screen = SpaceManager.pointerScreen() { return SpaceManager.displayID(for: screen) }
        return NSScreen.main.map(SpaceManager.displayID(for:)) ?? DisplayID(0)
    }

    public func tiledWindows(on space: SpaceID) -> [WindowID] {
        (order[space] ?? []).filter { !isFloating($0) }
    }

    public func focusedIndex(on space: SpaceID) -> Int? {
        guard let focused = engine.focused else { return nil }
        return tiledWindows(on: space).firstIndex(of: focused)
    }

    /// Focus hand-off that honours `warpMouseOnFocus`. Every focus path in the tiler goes
    /// through here.
    private func focusWindow(_ id: WindowID, warp: Bool = true) {
        engine.focus(id)
        guard warp, prefs.warpMouseOnFocus, let window = engine.window(id) else { return }
        let centre = window.frame.center
        guard centre.x.isFinite, centre.y.isFinite else { return }
        CGWarpMouseCursorPosition(centre)
        LatticeDiagnostics.record("focus: warped pointer to \(Int(centre.x)),\(Int(centre.y)) for \(id.raw)")
    }

    /// Called by the app's own mouse-moved monitor when `focusFollowsMouse` is on. The window
    /// under the pointer on a visible Space wins; the smallest frame under the pointer is used so
    /// a dialog inside a window takes focus rather than the parent behind it.
    @discardableResult
    public func focusWindowUnderPointer(force: Bool = false) -> Bool {
        guard force || prefs.focusFollowsMouse else { return false }
        guard let pointer = CGEvent(source: nil)?.location else { return false }
        let visible = Set(visibleSpaces().map(\.0))
        let candidates = engine.windows.values.filter { window in
            guard !window.isMinimized, !window.isFullscreen else { return false }
            guard visible.isEmpty || visible.contains(window.space) else { return false }
            guard !prefs.isUnmanaged(window.bundleID) else { return false }
            return window.frame.contains(pointer)
        }
        guard let target = candidates.min(by: { lhs, rhs in
            (lhs.frame.width * lhs.frame.height) < (rhs.frame.width * rhs.frame.height)
        }) else { return false }
        guard engine.focused != target.id else { return true }
        // Hover focus never warps: the pointer is already where the user wants it.
        focusWindow(target.id, warp: false)
        return true
    }

    public func focus(_ direction: Direction, on space: SpaceID) {
        let ids = tiledWindows(on: space)
        guard ids.count > 1 else { return }
        guard let current = focusedIndex(on: space) else {
            if let first = ids.first { focusWindow(first) }
            return
        }
        let target: Int
        switch direction {
        case .left, .up: target = max(0, current - 1)
        case .right, .down: target = min(ids.count - 1, current + 1)
        }
        focusWindow(ids[target])
        delegate?.tilerDidUpdate(self, space: space, windows: engine.windows(on: space))
    }

    public func move(_ direction: Direction, on space: SpaceID) {
        var ids = tiledWindows(on: space)
        guard let current = focusedIndex(on: space), ids.count > 1 else { return }
        let target: Int
        switch direction {
        case .left, .up: target = max(0, current - 1)
        case .right, .down: target = min(ids.count - 1, current + 1)
        }
        guard target != current else { return }
        ids.swapAt(current, target)
        let others = (order[space] ?? []).filter { isFloating($0) }
        order[space] = ids + others
        if isSuspended { pendingSwapAnimation = true }
        reconcile(reason: .layoutSwap)
    }

    public func swap(_ direction: Direction, on space: SpaceID) {
        move(direction, on: space)
    }

    /// Resizes the focused tile in every layout. Weights are ratios, so the focused tile takes
    /// from its neighbour and the Space keeps exactly the same total area.
    public func adjustSize(_ axis: Axis, delta: CGFloat, on space: SpaceID) {
        let ids = tiledWindows(on: space)
        guard ids.count > 1, let index = focusedIndex(on: space) else { return }

        var spaceWeights = weights[space] ?? Array(repeating: 1, count: ids.count)
        if spaceWeights.count != ids.count {
            spaceWeights = Array(repeating: 1, count: ids.count)
        }

        let layout = engine.focused
            .flatMap { engine.window($0)?.display }
            .flatMap { displayInfo(for: $0) }
            .map { TilingGeometry.resolvedLayout(space: space, display: $0, prefs: prefs) }
            ?? prefs.layout(for: space)
        let partner = partnerIndex(for: index, axis: axis, count: ids.count, layout: layout)
        guard partner != index, spaceWeights.indices.contains(partner) else { return }

        let change = max(-2, min(2, delta))
        let next = min(6, max(0.2, spaceWeights[index] + change))
        let actual = next - spaceWeights[index]
        let partnerNext = spaceWeights[partner] - actual
        guard partnerNext >= 0.2 else {
            // Not enough room to give away; scale both so the neighbour keeps its floor.
            let allowed = max(0, spaceWeights[partner] - 0.2)
            spaceWeights[index] += allowed
            spaceWeights[partner] -= allowed
            weights[space] = spaceWeights
            reconcile()
            return
        }
        spaceWeights[index] = next
        spaceWeights[partner] = partnerNext
        weights[space] = spaceWeights
        reconcile()
    }

    private func partnerIndex(for index: Int, axis: Axis, count: Int, layout: LayoutKind) -> Int {
        guard count > 1 else { return index }
        switch layout {
        case .grid:
            let columns = prefs.gridColumns > 0
                ? min(prefs.gridColumns, count)
                : Int(ceil(sqrt(Double(count))))
            let axisToUse: Axis = (axis == .horizontal && columns == 1) ? .vertical : axis
            if axisToUse == .horizontal {
                if (index % columns) + 1 < columns, index + 1 < count { return index + 1 }
                if index - 1 >= 0 { return index - 1 }
            } else {
                if index + columns < count { return index + columns }
                if index - columns >= 0 { return index - columns }
            }
            return index + 1 < count ? index + 1 : index - 1
        case .rows:
            // Rows have no width to give; treat "wider" as taller so the command still does
            // something sensible instead of silently failing.
            return index + 1 < count ? index + 1 : index - 1
        case .master:
            if index == 0 { return 1 }
            return index + 1 < count ? index + 1 : index - 1
        default:
            return index + 1 < count ? index + 1 : index - 1
        }
    }

    public func resetWeights(on space: SpaceID) {
        weights[space] = nil
        reconcile()
    }

    public func setLayout(_ layout: LayoutKind) {
        // The plain command changes what the Space in front of the user is doing, and makes
        // that the default for Spaces that never had a choice of their own.
        let space = focusedSpace()
        PreferencesStore.shared.update { prefs in
            prefs.layout = layout
            prefs.setLayout(layout, for: space)
        }
        reconcile(reason: .layoutSwap)
    }

    /// Applies a layout to one Space only. Other Spaces keep theirs (per-Space memory).
    public func setLayout(_ layout: LayoutKind, for space: SpaceID) {
        PreferencesStore.shared.update { $0.setLayout(layout, for: space) }
        reconcile(reason: .layoutSwap)
    }

    /// Explicit "everywhere" reset: give every Space this layout and make it the default.
    public func applyLayoutEverywhere(_ layout: LayoutKind) {
        PreferencesStore.shared.update { prefs in
            prefs.clearLayoutOverrides()
            prefs.layout = layout
        }
        weights.removeAll()
        reconcile(reason: .layoutSwap)
    }

    public func layout(for space: SpaceID) -> LayoutKind {
        prefs.layout(for: space)
    }

    public func cycleLayout() {
        let all = LayoutKind.allCases
        let space = focusedSpace()
        guard let index = all.firstIndex(of: prefs.layout(for: space)) else { return }
        setLayout(all[(index + 1) % all.count], for: space)
    }

    public func toggleFloat() {
        guard let focused = engine.focused else { return }
        let space = engine.window(focused)?.space ?? focusedSpace()
        if floating.contains(focused) {
            floating.remove(focused)
            if var ids = order[space], !ids.contains(focused) {
                let inserted = TilerOrdering.inserting([focused], into: ids,
                                                       policy: prefs.insertionPolicy,
                                                       focused: nil)
                ids = inserted.order
                order[space] = ids
            }
        } else {
            floating.insert(focused)
            order[space]?.removeAll { $0 == focused }
        }
        reconcile()
    }

    public func centre() {
        guard let focused = engine.focused, let frame = engine.frame(of: focused),
              let window = engine.window(focused),
              let display = displayInfo(for: window.display) else { return }
        let content = contentRect(for: display)
        let size = CGSize(width: min(frame.width, content.width * 0.7),
                          height: min(frame.height, content.height * 0.7))
        let target = CGRect(x: content.midX - size.width / 2,
                            y: content.midY - size.height / 2,
                            width: size.width, height: size.height)
        floating.insert(focused)
        place([(focused, target)], animated: true, reason: .snap, context: "centre")
        reconcile()
    }

    public func zoom() {
        guard let focused = engine.focused, let window = engine.window(focused),
              let display = displayInfo(for: window.display) else { return }
        floating.insert(focused)
        place([(focused, contentRect(for: display))], animated: true, reason: .snap, context: "zoom")
        reconcile()
    }

    public func toggleFocusMode() {
        let space = focusedSpace()
        if focusModeSpace == space {
            focusModeSpace = nil
            order = focusModeRestore.isEmpty ? order : order.merging(focusModeRestore) { _, restored in restored }
            focusModeRestore = [:]
        } else {
            focusModeSpace = space
            focusModeRestore = order
            if let focused = engine.focused {
                order[space] = [focused]
            }
        }
        reconcile()
    }

    // MARK: - Undo

    /// The largest of: what AX reports, what a refused write taught us this session, what a
    /// previous session learned for this app, and nothing else.
    private func minimumSize(for id: WindowID) -> CGSize {
        var size = engine.window(id)?.minSize ?? .zero
        if let learned = engine.learnedMinimum(id) {
            size = CGSize(width: max(size.width, learned.width), height: max(size.height, learned.height))
        }
        if let bundleID = engine.window(id)?.bundleID,
           let stored = prefs.learnedMinimums[bundleID], stored.count == 2 {
            // A window cannot have a minimum larger than the screen it is on. Values outside
            // that range are usually a whole-window refusal recorded as a minimum; ignore
            // them rather than making the app permanently untilable.
            let display = engine.window(id).flatMap { displayInfo(for: $0.display) }
            let cap = CGSize(width: (display?.frame.width ?? 4096) * 0.95,
                             height: (display?.frame.height ?? 4096) * 0.95)
            if stored[0] <= cap.width, stored[1] <= cap.height {
                size = CGSize(width: max(size.width, stored[0]), height: max(size.height, stored[1]))
            }
        }
        return size
    }

    /// Remember each app's real floor so the first pass after a relaunch is already achievable.
    /// Only bundle-id-keyed values are stored: window ids are not stable across launches.
    private func persistLearnedMinimums(for ids: [WindowID]) {
        var additions: [String: [CGFloat]] = [:]
        for id in ids {
            guard let window = engine.window(id), let bundleID = window.bundleID,
                  !bundleID.isEmpty, let learned = engine.learnedMinimum(id) else { continue }
            let display = displayInfo(for: window.display)
            let cap = CGSize(width: (display?.frame.width ?? 4096) * 0.95,
                             height: (display?.frame.height ?? 4096) * 0.95)
            guard learned.width <= cap.width, learned.height <= cap.height else { continue }
            let stored = prefs.learnedMinimums[bundleID] ?? [0, 0]
            if learned.width > stored[0] + 1 || learned.height > stored[1] + 1 {
                additions[bundleID] = [max(learned.width, stored[0]), max(learned.height, stored[1])]
            }
        }
        guard !additions.isEmpty else { return }
        PreferencesStore.shared.update { prefs in
            for (bundleID, size) in additions { prefs.learnedMinimums[bundleID] = size }
        }
    }

    /// Design-review fixtures only: adopt a tile order for Space with no AX windows behind it.
    public func adoptDemoOrder(_ ids: [WindowID], on space: SpaceID) {
        order[space] = ids
    }

    /// Places a dragged window into a snapped rectangle and lets the rest of the Space reflow.
    /// The window becomes floating so the tiled layout never fights the user's explicit choice.
    public func snapWindow(_ id: WindowID, to rect: CGRect, on space: SpaceID) {
        floating.insert(id)
        order[space]?.removeAll { $0 == id }
        engine.setFrame(rect, for: [id], animated: MotionPolicy.allowsAnimation(prefs, reason: .snap),
                        duration: prefs.animationDuration)
        reconcile(animated: false)
    }

    public func snapshot() {
        undoStack.append(lastFrames)
        if undoStack.count > 20 { undoStack.removeFirst() }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        isSuspended = true
        place(previous.map { (id: $0.key, frame: $0.value) }, animated: true, reason: .general, context: "undo")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.isSuspended = false
            self.reconcile(animated: false)
        }
    }

    // MARK: - Space changes

    /// Send the focused window to the nth user Space of the display it is on (the same display
    /// ordering Mission Control shows).
    public func moveWindowToSpace(number: Int) {
        guard let focused = engine.focused, let window = engine.window(focused) else { return }
        let display = spaces.displayID(for: focused) ?? window.display
        let entry = spaces.spaceFor(displayID: display)
        let users = entry.userSpaceIDs
        guard users.indices.contains(number - 1) else {
            let message = "Space \(number) does not exist on display \(display)"
            Log.error("move to space: \(message)")
            delegate?.tiler(self, didFail: message)
            return
        }
        sendWindow(focused, from: window.space, to: users[number - 1], on: display)
    }

    /// Move any window to any Space on a display, through the same verified pipeline used by
    /// the keyboard command. `follow` is false for rule-driven moves: an app opening on another
    /// Space must not drag the user away from what they are doing.
    public func sendWindow(_ id: WindowID,
                           from: SpaceID,
                           to target: SpaceID,
                           on display: DisplayID,
                           follow: Bool = true) {
        guard let window = engine.window(id) else { return }
        guard target != window.space else { return }

        floating.remove(id)
        for space in Array(order.keys) {
            order[space]?.removeAll { $0 == id }
            if order[space]?.isEmpty == true { order[space] = nil }
        }
        LatticeDiagnostics.record("send \(id.raw) \(window.space.raw) -> \(target.raw) on display \(display.raw)")

        pendingSpaceMoves.insert(id)
        let entry = spaces.spaceFor(displayID: display)
        SpaceBridge.perform(window: id, to: target, display: entry) { [weak self] result in
            guard let self else { return }
            self.pendingSpaceMoves.remove(id)
            if !result.succeeded {
                self.delegate?.tiler(self, didFail: "Could not move window to Space \(target.raw) — \(result.detail)")
                // With SIP on, WindowServer refuses cross-process moves and macOS only offers
                // the Mission Control drag. Open it with an instruction instead of failing
                // silently; the user can finish the move in one gesture.
                let number = entry.userSpaceIDs.firstIndex(of: target).map { $0 + 1 } ?? 0
                NotificationCenter.default.post(name: .latticeManualSpaceMove,
                                                object: nil,
                                                userInfo: ["app": window.appName,
                                                           "title": window.title,
                                                           "space": number])
            }
            self.engine.refresh(reason: "space-move")
            if result.succeeded, follow, self.prefs.followWindowAcrossSpaces {
                LatticeDiagnostics.record("follow: switching display \(display.raw) to space \(target.raw)")
                self.spaces.activate(target, on: display)
            }
            self.reconcile()
        }
    }

    public func goToSpace(number: Int) {
        let display = focusedDisplay()
        let entry = spaces.spaceFor(displayID: display)
        let users = entry.userSpaceIDs
        guard users.indices.contains(number - 1) else {
            Log.error("go to space: Space \(number) does not exist on display \(display) (has \(users.count))")
            return
        }
        LatticeDiagnostics.record("go to space \(number) -> \(users[number - 1].raw) on display \(display.raw)")
        spaces.activate(users[number - 1], on: display)
    }

    public func nextSpace(forward: Bool) {
        let display = focusedDisplay()
        let entry = spaces.spaceFor(displayID: display)
        let ids = entry.spaceIDs
        guard ids.count > 1, ids.indices.contains(entry.currentIndex) else { return }
        let next = (entry.currentIndex + (forward ? 1 : -1) + ids.count) % ids.count
        LatticeDiagnostics.record("next space \(forward ? "->" : "<-") \(ids[next].raw) on display \(display.raw)")
        spaces.activate(ids[next], on: display)
    }

    public func nextDisplay(forward: Bool) {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }
        let currentDisplay = focusedDisplay()
        guard let index = screens.firstIndex(where: { SpaceManager.displayID(for: $0) == currentDisplay }) else { return }
        let next = (index + (forward ? 1 : -1) + screens.count) % screens.count
        let target = screens[next]
        let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
        CGWarpMouseCursorPosition(SpaceManager.flip(point, screens: screens))
    }
}

public enum Direction: Sendable { case left, right, up, down }
public enum Axis: Sendable { case horizontal, vertical }

extension WindowEngine {
    public static func sharedElement(for id: WindowID) -> AXUIElement? {
        EngineHolder.shared?.element(for: id)
    }

    /// Best-effort focus hand-off when the focused window vanished (closed, moved to another
    /// Space, minimised); keeps keyboard commands useful instead of inert.
    func focusFirstAvailable() {
        let visible = visibleSpaceIDs()
        let candidate = windows.values
            .filter { !$0.isMinimized && !$0.isFloating && (visible.isEmpty || visible.contains($0.space)) }
            .sorted { $0.id.raw < $1.id.raw }
            .first
        if let candidate {
            focus(candidate.id)
        } else {
            clearFocused()
        }
    }
}

/// Small registry so the static bridge can reach the live engine without global mutable state sprawl.
public final class EngineHolder: @unchecked Sendable {
    nonisolated(unsafe) public static var shared: WindowEngine?
}
