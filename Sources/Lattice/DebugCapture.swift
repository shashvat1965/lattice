import AppKit
import LatticeKit

/// Renders Lattice's own windows to PNGs. Useful for design review and CI without needing
/// Screen Recording permission, because we only ever read our own view hierarchy.
@MainActor
enum DebugCapture {

    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["LATTICE_CAPTURE"] else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func scheduleIfRequested(delay: TimeInterval = 2.5) {
        guard let directory else { return }
        Log.info("capture mode enabled → \(directory.path)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            captureWindows(into: directory)
            if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_EXIT"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }

    static func captureWindows(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() {
            guard window.isVisible, let view = window.contentView, view.bounds.width > 20 else { continue }
            let name = makeName(window: window, index: index)

            // ScreenCaptureKit (the only supported path on macOS 26) needs Screen Recording
            // permission, so we fall back to rendering the view tree ourselves.
            if let data = imageData(of: view) {
                try? data.write(to: directory.appendingPathComponent("\(name).png"))
                Log.info("captured \(name) via view render")
            }
        }
    }

    static func imageData(of view: NSView) -> Data? {
        view.layoutSubtreeIfNeeded()
        if let data = layerImageData(of: view), !isBlank(data) { return data }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// SwiftUI renders through its own layer tree, so a plain `cacheDisplay` comes back blank.
    /// Rendering the layer tree into a context is the reliable path.
    private static func layerImageData(of view: NSView) -> Data? {
        guard let layer = view.layer ?? view.subviews.first?.layer else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return nil }
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    private static func isBlank(_ data: Data) -> Bool {
        data.count < 3_000
    }

    private static func makeName(window: NSWindow, index: Int) -> String {
        let base = window.title.isEmpty ? "window" : window.title
        let slug = base.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "…", with: "")
        return String(format: "%02d-%@", index, slug)
    }
}
