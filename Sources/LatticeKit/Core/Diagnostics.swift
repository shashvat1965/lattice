import Foundation
import AppKit
import ApplicationServices

/// A tiny registry so `LatticeDiagnostics.snapshot()` and `LATTICE_SELFTEST` can reach the
/// live tiler without introducing global mutable state all over the app.
public final class TilerHolder: @unchecked Sendable {
    nonisolated(unsafe) public static var shared: Tiler?
}

/// Counts AX round-trips so reconcile cost can be measured instead of guessed.
/// AX reads can happen on the drag fallback's background queue, so the counter is locked.
public enum AXPerf {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var calls = 0

    static func note() {
        lock.lock()
        calls += 1
        lock.unlock()
    }

    public static func take() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let value = calls
        calls = 0
        return value
    }

    public static func peek() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

/// Human-readable picture of the engine. This is the thing the lead reads when a window
/// refuses to tile, so it must answer "why is this window not where I expect it?".
public enum LatticeDiagnostics {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var decisions: [String] = []
    private static let capacity = 60

    public static func record(_ decision: String) {
        let stamp = String(format: "%.3f", CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 1000))
        lock.lock()
        decisions.append("[\(stamp)] \(decision)")
        if decisions.count > capacity { decisions.removeFirst(decisions.count - capacity) }
        lock.unlock()
        Log.debug("reconcile: \(decision)")
    }

    public static var recentDecisions: [String] {
        lock.lock(); defer { lock.unlock() }
        return decisions
    }

    public static func snapshot() -> String {
        let engine = EngineHolder.shared
        let tiler = TilerHolder.shared
        var out: [String] = []

        out.append("=== Lattice diagnostics ===")
        out.append("time: \(ISO8601DateFormatter().string(from: Date()))")
        out.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("accessibilityTrusted: \(AXIsProcessTrusted())")
        out.append("skyLight: \(SkyLight.isAvailable ? "connected" : "UNAVAILABLE") " +
                   "(moveSymbol: \(SkyLight.hasMoveSymbol), setSpace: \(SkyLight.hasSetCurrentSpaceSymbol))")

        // Displays
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        out.append("")
        out.append("displays (\(screens.count)):")
        for screen in screens {
            let id = SpaceManager.displayID(for: screen)
            let frame = CGRect(x: screen.frame.origin.x,
                               y: primaryHeight - screen.frame.maxY,
                               width: screen.frame.width,
                               height: screen.frame.height)
            let visible = CGRect(x: screen.visibleFrame.origin.x,
                                 y: primaryHeight - screen.visibleFrame.maxY,
                                 width: screen.visibleFrame.width,
                                 height: screen.visibleFrame.height)
            let notch = screen.safeAreaInsets.top > 0
            out.append("  \(id) \"\(screen.localizedName)\" frame=\(fmt(frame)) visible=\(fmt(visible)) notch=\(notch) scale=\(screen.backingScaleFactor)")
        }

        // Spaces
        let entries = SpaceManager.shared.displaySpaces()
        out.append("")
        out.append("spaces (\(entries.count) displays):")
        for entry in entries {
            let order = entry.spaceIDs.map { "\($0.raw)" }.joined(separator: ",")
            let users = entry.userSpaceIDs.map { "\($0.raw)" }.joined(separator: ",")
            let current = entry.current.map { "\($0.raw)" } ?? "-"
            out.append("  \(entry.display) uuid=\(entry.displayUUID.prefix(8)) current=\(current) index=\(entry.currentIndex) order=[\(order)] userSpaces=[\(users)]")
        }
        out.append("  activeSpace=\(SpaceManager.shared.activeSpaceID()?.raw.description ?? "-")")
        out.append("  focusedSpace=\(SpaceManager.shared.focusedSpace()?.raw.description ?? "-")")

        // Windows
        let tilerOrder = tiler?.order ?? [:]
        let floating = tiler?.floating ?? []
        let windows = engine.map { Array($0.windows.values) } ?? []
        out.append("")
        out.append("windows (\(windows.count)):")
        for window in windows.sorted(by: { $0.id.raw < $1.id.raw }) {
            var flags: [String] = []
            if window.isFloating { flags.append("float") }
            if window.isFullscreen { flags.append("fullscreen") }
            if window.isMinimized { flags.append("min") }
            if engine?.isStubborn(window.id) == true { flags.append("stubborn") }
            if floating.contains(window.id) { flags.append("userFloat") }
            if tilerOrder[window.space]?.contains(window.id) == true { flags.append("ordered") }
            if flags.isEmpty { flags.append("tiled") }
            out.append("  \(window.id) pid=\(window.pid) app=\"\(window.appName)\" title=\"\(window.title.prefix(40))\" space=\(window.space.raw) display=\(window.display.raw) frame=\(fmt(window.frame)) flags=[\(flags.joined(separator: ","))] subrole=\(window.subrole ?? "-")")
        }

        // Tiling state
        if let tiler {
            let prefs = tiler.prefs
            out.append("")
            out.append("tiling: defaultLayout=\(prefs.layout.rawValue) gap=\(prefs.gap) outerGap=\(prefs.outerGap) edges=\(prefs.edges) suspended=\(tiler.isSuspended) reconciling=\(tiler.isReconciling)")
            out.append("tuning: masterRatio=\(prefs.masterRatio) stackPeek=\(prefs.stackPeek) gridColumns=\(prefs.gridColumns) insertion=\(prefs.insertionPolicy.rawValue) autoBalance=\(prefs.autoBalance) minTile=\(prefs.minTiledWidth)x\(prefs.minTiledHeight)")
            out.append("motion: animate=\(prefs.animate) curve=\(prefs.animationCurve.rawValue) duration=\(Int(prefs.animationDuration * 1000))ms snap=\(prefs.animateSnap) swaps=\(prefs.animateLayoutSwaps) reduceMotion=\(MotionPolicy.reducesMotion)")
            out.append("rules: unmanaged=\(prefs.unmanagedBundleIDs.count) float=\(prefs.floatBundleIDs.count) appRules=\(prefs.rules.count) perDisplayOverrides=\(prefs.displayOverrides.count)")
            for (space, ids) in tiler.order.sorted(by: { $0.key.raw < $1.key.raw }) {
                let list = ids.map { "\($0.raw)" }.joined(separator: ",")
                let layout = tiler.layout(for: space)
                let weights = tiler.weights[space]?.map { String(format: "%.2f", $0) }.joined(separator: ",") ?? "-"
                out.append("  order[\(space.raw)]=[\(list)] layout=\(layout.rawValue) weights=\(weights) tiled=\(tiler.tiledWindows(on: space).count)")
            }
        }

        // Decisions
        out.append("")
        out.append("last \(min(20, recentDecisions.count)) reconcile decisions:")
        for line in recentDecisions.suffix(20) {
            out.append("  \(line)")
        }
        return out.joined(separator: "\n")
    }

    public static func dumpToLog(reason: String) {
        Log.info("diagnostics [\(reason)]\n\(snapshot())")
    }

    private static func fmt(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
}
