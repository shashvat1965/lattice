import Foundation
import AppKit
import CoreGraphics

/// Which kind of operation asked for a frame change. The user can gate each kind separately.
public enum MotionReason: String, Sendable {
    /// Ordinary retile (a window appeared, a Space became visible, a preference changed).
    case general
    /// A swap / move within the tile order, or an explicit layout change.
    case layoutSwap
    /// A snap-style placement: centre, zoom, drag-to-rect.
    case snap
}

/// The easing functions themselves. Pure maths so they can be unit-tested without a display.
public enum MotionCurve {

    /// `t` is normalised progress in 0...1. Every curve returns exactly 0 at 0 and 1 at 1.
    public static func progress(_ t: Double, curve: AnimationCurve, duration: TimeInterval = 0.18) -> Double {
        let t = min(1, max(0, t))
        switch curve {
        case .easeOut:
            return 1 - pow(1 - t, 3)

        case .easeInOut:
            // Smoothstep: zero velocity at both ends, no overshoot.
            return t * t * (3 - 2 * t)

        case .spring:
            // Damped spring sampled directly, response 0.34 s and damping 0.86 — the same feel
            // as the app chrome. Normalised so the last sample lands exactly on the target.
            let span = max(0.18, duration)
            let time = t * span
            let response = 0.34
            let damping = 0.86
            let omega = 2 * Double.pi / response
            let damped = omega * (1 - damping * damping).squareRoot()

            func value(_ seconds: Double) -> Double {
                let envelope = exp(-damping * omega * seconds)
                let cosine = cos(damped * seconds)
                let sine = sin(damped * seconds)
                return 1 - envelope * (cosine + (damping * omega / damped) * sine)
            }

            let end = value(span)
            guard end > 0.0001 else { return t }
            let raw = value(time) / end
            return max(0, raw)
        }
    }
}

/// One place decides whether a change is allowed to animate. Reduce Motion always wins.
public enum MotionPolicy {

    public static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public static func allowsAnimation(_ prefs: Preferences,
                                       reason: MotionReason,
                                       requested: Bool = true) -> Bool {
        allowsAnimation(animate: prefs.animate,
                        animateSnap: prefs.animateSnap,
                        animateLayoutSwaps: prefs.animateLayoutSwaps,
                        reduceMotion: reducesMotion,
                        reason: reason,
                        requested: requested)
    }

    /// Pure overload: the self-test cannot change the system Reduce Motion setting.
    public static func allowsAnimation(animate: Bool,
                                       animateSnap: Bool,
                                       animateLayoutSwaps: Bool,
                                       reduceMotion: Bool,
                                       reason: MotionReason,
                                       requested: Bool = true) -> Bool {
        guard requested, animate, !reduceMotion else { return false }
        switch reason {
        case .general: return true
        case .layoutSwap: return animateLayoutSwaps
        case .snap: return animateSnap
        }
    }
}

/// The frame tween. `WindowEngine` owns AX writes but its built-in tween is fixed cubic-out, so
/// LatticeKit drives the samples here and asks the engine for instant writes. One timer per
/// batch of windows; a new batch cancels only batches that overlap its windows, so a snap tween
/// and a retile can run side by side instead of killing each other. Nothing polls when idle.
public final class FrameAnimator {

    public static let shared = FrameAnimator()

    private struct Batch {
        var ids: Set<WindowID>
        var timer: Timer
    }

    private var batches: [Int: Batch] = [:]
    private var nextBatchID = 0

    private init() {}

    public var isAnimating: Bool { !batches.isEmpty }

    /// Returns true when a tween was started, false when the frames were applied instantly.
    @discardableResult
    public func animate(engine: WindowEngine,
                        targets: [(id: WindowID, frame: CGRect)],
                        duration: TimeInterval,
                        curve: AnimationCurve,
                        reduceMotion: Bool = MotionPolicy.reducesMotion,
                        completion: (() -> Void)? = nil) -> Bool {
        guard !targets.isEmpty else {
            completion?()
            return false
        }

        let ids = Set(targets.map(\.id))
        // A newer tween for the same window supersedes the old one.
        for (key, batch) in batches where !batch.ids.isDisjoint(with: ids) {
            batch.timer.invalidate()
            batches[key] = nil
        }

        // Only windows that actually need to move take part; the engine already no-ops the rest.
        let moving = targets.filter { target in
            guard engine.window(target.id) != nil else { return false }
            guard let current = engine.frame(of: target.id) else { return true }
            return !current.isClose(to: target.frame, tolerance: 0.5)
        }

        guard !reduceMotion, duration > 0.02, !moving.isEmpty else {
            for target in targets {
                engine.setFrame(target.frame, for: [target.id], animated: false, duration: 0)
            }
            completion?()
            return false
        }

        let starts = moving.map { engine.frame(of: $0.id) ?? $0.frame }
        nextBatchID += 1
        let batchID = nextBatchID
        let steps = max(4, min(24, Int(duration * 60)))
        let interval = max(1.0 / 120.0, duration / Double(steps))
        let startedAt = CFAbsoluteTimeGetCurrent()
        var step = 0

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            step += 1
            let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
            let t = min(1, max(elapsed / duration, Double(step) / Double(steps)))
            let eased = MotionCurve.progress(t, curve: curve, duration: duration)

            for (index, target) in moving.enumerated() {
                let from = starts[index]
                let rect = CGRect(
                    x: from.origin.x + (target.frame.origin.x - from.origin.x) * eased,
                    y: from.origin.y + (target.frame.origin.y - from.origin.y) * eased,
                    width: from.width + (target.frame.width - from.width) * eased,
                    height: from.height + (target.frame.height - from.height) * eased
                )
                engine.setFrame(rect, for: [target.id], animated: false, duration: 0)
            }

            if step >= steps || t >= 1 {
                timer.invalidate()
                self.batches[batchID] = nil
                for target in moving {
                    engine.setFrame(target.frame, for: [target.id], animated: false, duration: 0)
                }
                completion?()
            }
        }
        batches[batchID] = Batch(ids: ids, timer: timer)
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    public func cancel() {
        for batch in batches.values {
            batch.timer.invalidate()
        }
        batches.removeAll()
    }
}
