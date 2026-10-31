import SwiftUI
import AppKit
import LatticeKit

/// Headless design review: renders the app's screens straight from SwiftUI.
/// No window server capture, no permissions, and it works over SSH.
@MainActor
enum DesignSnapshots {

    static func renderAll(model: AppModel, into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let background = Color(nsColor: .windowBackgroundColor)

        shot(AnyView(Overview(model: model).background(background)), size: CGSize(width: 1040, height: 720), name: "overview", dir: directory)
        shot(AnyView(LayoutsGallery(model: model).background(background)), size: CGSize(width: 1040, height: 720), name: "layouts", dir: directory)
        shot(AnyView(SpacesView(model: model).background(background)), size: CGSize(width: 1040, height: 700), name: "spaces", dir: directory)
        shot(AnyView(SettingsPane().background(background)), size: CGSize(width: 820, height: 900), name: "settings", dir: directory)
        shot(AnyView(ShortcutsPane().background(background)), size: CGSize(width: 820, height: 900), name: "shortcuts", dir: directory)
        shot(AnyView(AppsPane().background(background)), size: CGSize(width: 820, height: 760), name: "apps", dir: directory)
        shot(AnyView(AboutPane().background(background)), size: CGSize(width: 820, height: 620), name: "about", dir: directory)
        shot(AnyView(MenuBarPanel(model: model, dismiss: {}).background(background)), size: CGSize(width: 340, height: 560), name: "menubar", dir: directory)
    }

    static func shot(_ view: AnyView, size: CGSize, name: String, dir: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).clipped())
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            Log.error("snapshot failed: \(name)")
            return
        }
        let url = dir.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        Log.info("snapshot \(name): \(Int(image.size.width))×\(Int(image.size.height))")
    }
}
