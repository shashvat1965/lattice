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
        let width: CGFloat = 1000

        shot(AnyView(Overview(model: model).content.frame(maxWidth: .infinity)), width: width, name: "01-overview", dir: directory)
        shot(AnyView(LayoutsPage(model: model).content.frame(maxWidth: .infinity)), width: width, name: "02-layouts", dir: directory)
        shot(AnyView(SettingsPane().content.frame(maxWidth: .infinity)), width: width, name: "04-settings", dir: directory)
        shot(AnyView(MenuBarPanel(model: model, dismiss: {}).frame(width: 340)), width: 340, name: "05-menu-bar", dir: directory)

        Log.info("SHOTS done → \(directory.path)")
        if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_EXIT"] == "1" { NSApp.terminate(nil) }
    }

    private static func shot<V: View>(_ view: V, width: CGFloat, name: String, dir: URL) {
        // Render tall, then crop to the last row that actually has pixels: `fittingSize` on a
        // detached NSHostingView under-reports SwiftUI content height.
        let tall: CGFloat = 2800
        let renderer = ImageRenderer(content: view
            .frame(width: width, height: tall, alignment: .top)
            .clipped())
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cropped = cropToContent(rep),
              let data = cropped.representation(using: .png, properties: [:]) else {
            Log.error("SHOTS \(name): renderer produced nothing")
            return
        }
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
        Log.info("SHOTS \(name): \(cropped.pixelsWide)x\(cropped.pixelsHigh)")
    }

    /// Trims the fully transparent rows below the content.
    private static func cropToContent(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
        guard let cg = rep.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        guard let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let bytesPerRow = cg.bytesPerRow
        let bytesPerPixel = cg.bitsPerPixel / 8
        var lastRow = height - 1
        var y = height - 1
        outer: while y > 0 {
            let row = bytes + y * bytesPerRow
            var x = 0
            while x < width {
                let alpha = row[x * bytesPerPixel + (bytesPerPixel - 1)]
                if alpha > 6 { lastRow = y; break outer }
                x += 2
            }
            y -= 1
        }
        let cropHeight = min(height, lastRow + 1)
        guard cropHeight > 10, let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: width, height: cropHeight)) else {
            return rep
        }
        return NSBitmapImageRep(cgImage: cropped)
    }
}
