import SwiftUI
import AppKit
import LatticeKit

/// Renders pages to PNGs for design review.
///
/// Screen capture needs a Screen Recording grant we do not have, and `ImageRenderer` cannot
/// draw scroll content — so every page exposes a `content` view that renders standalone and
/// this harness sizes it to its natural height.
@MainActor
enum PageSnapshots {

    static func runIfRequested(into directory: URL) {
        guard ProcessInfo.processInfo.environment["LATTICE_SHOTS"] != nil else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel.shared
        Log.info("SHOTS state: demo=\(model.isDemo) spaces=\(model.spaces.count) windowsBySpace=\(model.windowsBySpace.mapValues(\.count)) focusedSpace=\(model.focusedSpace)")
        let width: CGFloat = 1000

        // Render on the app's own canvas in light mode. Without an explicit background the
        // renderer leaves the page transparent, and on a dark-mode Mac every `.primary` label
        // comes back as white-on-nothing — a screenshot that is worse than none.
        func page<V: View>(_ view: V) -> AnyView {
            AnyView(
                view.frame(maxWidth: .infinity)
                    .environment(\.colorScheme, .light)
                    .environment(\.latticeSnapshotMode, true)
            )
        }

        shot(page(Overview(model: model).content), width: width, name: "01-overview", dir: directory)
        shot(page(LayoutsPage(model: model).content), width: width, name: "02-layouts", dir: directory)
        shot(page(SettingsPane().content), width: width, name: "04-settings", dir: directory)
        shot(page(ShortcutsPane().content), width: width, name: "03-shortcuts", dir: directory)
        shot(AnyView(MenuBarPanel(model: model, dismiss: {})
            .frame(width: 340)
            .environment(\.colorScheme, .light)
            .environment(\.latticeSnapshotMode, true)), width: 340, name: "05-menu-bar", dir: directory)

        Log.info("SHOTS done → \(directory.path)")
        if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_EXIT"] == "1" { NSApp.terminate(nil) }
    }

    private static func shot<V: View>(_ view: V, width: CGFloat, name: String, dir: URL) {
        // `fixedSize` gives flexible rows their ideal height, so a section cannot swallow the
        // whole canvas just because the render frame is tall.
        let content = view.fixedSize(horizontal: false, vertical: true)
        let tall: CGFloat = 4000

        // Pass 1 measures. `fittingSize` on a detached NSHostingView under-reports SwiftUI
        // content height, so render tall on a transparent canvas and find the last row that
        // actually has pixels.
        let probe = ImageRenderer(content: content
            .frame(width: width, height: tall, alignment: .top)
            .clipped())
        probe.scale = 1
        guard let probeImage = probe.nsImage,
              let probeTiff = probeImage.tiffRepresentation,
              let probeRep = NSBitmapImageRep(data: probeTiff),
              let measuredHeight = contentHeight(probeRep), measuredHeight > 10 else {
            Log.error("SHOTS \(name): could not measure content height")
            return
        }

        // Pass 2 draws the measured page on the app's own canvas. A few points of slack stop
        // the last row's descenders (and the bottom safe-area inset) from being cut off.
        let height = measuredHeight + 20
        let renderer = ImageRenderer(content: content
            .frame(width: width, height: height, alignment: .top)
            .background(Color.latticeCanvas))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            Log.error("SHOTS \(name): renderer produced nothing")
            return
        }
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
        Log.info("SHOTS \(name): \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }

    /// The height of the last row that is not fully transparent.
    private static func contentHeight(_ rep: NSBitmapImageRep) -> CGFloat? {
        guard let cg = rep.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let bytesPerRow = cg.bytesPerRow
        let bytesPerPixel = cg.bitsPerPixel / 8
        var y = height - 1
        while y > 0 {
            let row = bytes + y * bytesPerRow
            var x = 0
            while x < width {
                let alpha = row[x * bytesPerPixel + (bytesPerPixel - 1)]
                if alpha > 6 { return CGFloat(y + 1) }
                x += 2
            }
            y -= 1
        }
        return nil
    }
}
