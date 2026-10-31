import AppKit
import SwiftUI
import Combine
import LatticeKit

/// Owns the `NSStatusItem`, its template glyph and the popover it presents.
///
/// The glyph is redrawn whenever the layout or the paused state changes, so the
/// menu bar always shows the actual tile silhouette rather than a static icon.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var hosting: NSHostingController<MenuBarPanel>?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        configurePopover()
        observeState()

        // AppDelegate only builds the status bar, so the other always-available
        // surfaces (palette, cheat sheet, HUD) are installed from here exactly once.
        SurfaceCoordinator.shared.install(model: model)
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Lattice")
        button.setAccessibilityHelp("Open the Lattice menu")
        statusItem.isVisible = model.prefs.prefs.showMenuBarIcon
        updateGlyph(layout: model.layout, enabled: model.isEnabled)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let root = MenuBarPanel(model: model) { [weak self] in
            self?.closePopover()
        }
        let controller = NSHostingController(rootView: root)
        controller.view.setAccessibilityLabel("Lattice menu")
        hosting = controller

        popover.contentViewController = controller
        popover.contentSize = NSSize(width: MenuBarPanel.width, height: MenuBarPanel.height)
    }

    private func observeState() {
        model.$layout
            .combineLatest(model.$isEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] layout, enabled in
                MainActor.assumeIsolated {
                    self?.updateGlyph(layout: layout, enabled: enabled)
                }
            }
            .store(in: &cancellables)
    }

    private func updateGlyph(layout: LayoutKind, enabled: Bool) {
        guard let button = statusItem.button else { return }
        button.image = StatusItemGlyph.image(layout: layout, paused: !enabled)
        button.toolTip = enabled
            ? "Lattice — \(layout.title) layout"
            : "Lattice — tiling paused"
        button.setAccessibilityLabel(
            enabled ? "Lattice, \(layout.title) layout" : "Lattice, tiling paused"
        )
    }

    // MARK: - Presentation

    @objc private func statusItemClicked() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // The popover is the truth for what is on screen right now, including
        // when Lattice launched without Accessibility trust and missed events.
        model.refreshSpaces()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
