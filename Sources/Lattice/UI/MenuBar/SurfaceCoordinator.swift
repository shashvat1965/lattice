import AppKit
import LatticeKit

/// Installs the always-available surfaces and routes the notifications `AppModel`
/// posts. `StatusBarController` owns the only call site, so everything here runs
/// exactly once, at launch, on the main thread.
@MainActor
final class SurfaceCoordinator {

    static let shared = SurfaceCoordinator()

    private var installed = false
    private var observers: [NSObjectProtocol] = []

    private init() {}

    func install(model: AppModel) {
        guard !installed else { return }
        installed = true

        HUDController.shared.start()
        CommandPaletteController.shared.configure(model: model)
        CheatSheetController.shared.configure(model: model)

        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: .latticeShowPalette, object: nil, queue: .main) { _ in
            Task { @MainActor in
                CheatSheetController.shared.dismiss()
                CommandPaletteController.shared.toggle()
            }
        })

        observers.append(center.addObserver(forName: .latticeShowCheatSheet, object: nil, queue: .main) { _ in
            Task { @MainActor in
                CommandPaletteController.shared.dismiss()
                CheatSheetController.shared.toggle()
            }
        })
    }
}
