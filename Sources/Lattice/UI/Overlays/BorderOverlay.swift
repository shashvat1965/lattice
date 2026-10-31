import AppKit
import SwiftUI
import Combine
import LatticeKit

/// Draws the active-window ring. Each ring is its own click-through, non-activating panel
/// that joins every Space, so it behaves like a system decoration rather than a window.
@MainActor
final class BorderOverlayController {

    static let shared = BorderOverlayController()

    private weak var model: AppModel?
    private var panels: [WindowID: BorderPanel] = [:]
    private var followTimer: Timer?
    private var settleDeadline: Date = .distantPast
    private var cancellables: Set<AnyCancellable> = []
    private var lastSignature: String = ""

    private init() {}

    func start(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model

        model.$windowsBySpace
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleFollow()
            }
            .store(in: &cancellables)

        model.$focusedWindow
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh(force: true)
            }
            .store(in: &cancellables)

        model.$focusedSpace
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh(force: true)
            }
            .store(in: &cancellables)

        _ = PreferencesStore.shared.observe { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }

        refresh(force: true)
    }

    // MARK: - Following the tiling animation

    /// Tiling tweens for `animationDuration`; the ring has to track the AX frames while that
    /// happens or it visibly trails the window by a frame or two.
    private func scheduleFollow() {
        let duration = max(0.05, PreferencesStore.shared.prefs.animationDuration)
        settleDeadline = Date().addingTimeInterval(duration + 0.25)
        guard followTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh(force: false)
                if Date() >= self.settleDeadline {
                    self.followTimer?.invalidate()
                    self.followTimer = nil
                }
            }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    // MARK: - Rendering

    private func refresh(force: Bool) {
        guard let model else { return }
        let prefs = PreferencesStore.shared.prefs

        guard prefs.borderEnabled, model.accessibilityGranted else {
            hideAll()
            return
        }

        let visibleSpaces = Set(model.spaces.compactMap(\.current))
        if visibleSpaces.isEmpty, let space = model.focusedSpace as SpaceID? {
            _ = space
        }

        let focused = model.engine.focused
        var desired: [WindowID: CGRect] = [:]

        for window in model.engine.windows.values {
            guard visibleSpaces.isEmpty || visibleSpaces.contains(window.space) else { continue }
            guard !window.isMinimized, !window.isFullscreen else { continue }
            guard !model.tiler.isFloating(window.id) else { continue }

            if prefs.borderScope == .focused {
                guard window.id == focused else { continue }
            }
            var frame = window.frame
            if let live = model.engine.frame(of: window.id) { frame = live }
            guard frame.width > 40, frame.height > 40 else { continue }
            desired[window.id] = frame
        }

        let signature = desired
            .sorted { $0.key.raw < $1.key.raw }
            .map { "\($0.key.raw):\(Int($0.value.minX)),\(Int($0.value.minY)),\(Int($0.value.width)),\(Int($0.value.height))" }
            .joined(separator: "|")
        if !force && signature == lastSignature { return }
        lastSignature = signature

        // Recycle panels that are no longer needed.
        for (id, panel) in panels where desired[id] == nil {
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }

        let color = Self.borderColor(prefs: prefs)
        for (id, frame) in desired {
            let panel: BorderPanel
            if let existing = panels[id] {
                panel = existing
            } else {
                panel = BorderPanel(frame: .zero)
                panels[id] = panel
            }
            panel.apply(frame: Self.flipped(frame), width: prefs.borderWidth,
                        color: color, opacity: prefs.borderOpacity)
            if panel.windowNumber == 0 {
                panel.orderFrontRegardless()
            }
        }
    }

    private func hideAll() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        followTimer?.invalidate()
        followTimer = nil
        lastSignature = ""
    }

    private static func borderColor(prefs: Preferences) -> NSColor {
        if let hex = prefs.borderColorHex, let color = NSColor(hexString: hex) {
            return color
        }
        return NSColor.controlAccentColor
    }

    private static func flipped(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

private final class BorderPanel: NSPanel {

    private let shape = CAShapeLayer()

    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let host = NSView(frame: frame)
        host.wantsLayer = true
        host.layer?.addSublayer(shape)
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func apply(frame: CGRect, width: CGFloat, color: NSColor, opacity: Double) {
        setFrame(frame, display: false)
        let local = CGRect(origin: .zero, size: frame.size)
        let inset = width / 2 + 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGPath(roundedRect: local.insetBy(dx: inset, dy: inset),
                          cornerWidth: 10, cornerHeight: 10, transform: nil)
        shape.frame = local
        shape.path = path
        shape.fillColor = nil
        shape.strokeColor = color.withAlphaComponent(opacity).cgColor
        shape.lineWidth = width
        CATransaction.commit()
    }
}

extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
