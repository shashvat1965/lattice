import AppKit
import LatticeKit

/// Renders Lattice's own windows to PNGs for design review, without Screen Recording.
///
/// On macOS 26 a SwiftUI view tree often renders blank through both `cacheDisplay` and a
/// layer render, so this writes a file only when the result is not a uniform sheet of one
/// colour. Use `screencapture` when it refuses; the offscreen page harness is in
/// `PageSnapshots`.
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
            } else {
                Log.info("capture \(name): view render came back blank; use `screencapture` for this window")
            }
            if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_DEBUG"] == "1" {
                if let cache = cacheDisplayData(of: view) {
                    try? cache.write(to: directory.appendingPathComponent("\(name)-cache.png"))
                }
                if let layer = layerData(of: view) {
                    try? layer.write(to: directory.appendingPathComponent("\(name)-layer.png"))
                }
            }
        }
    }

    static func cacheDisplayData(of view: NSView) -> Data? {
        guard let rep = cacheDisplayRep(of: view) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func imageData(of view: NSView) -> Data? {
        view.layoutSubtreeIfNeeded()
        let reps = [cacheDisplayRep(of: view), layerRep(of: view)].compactMap { $0 }
        for rep in reps {
            guard !isEffectivelyBlank(rep),
                  let data = rep.representation(using: .png, properties: [:]) else { continue }
            return data
        }
        return nil
    }

    /// True when almost every sampled pixel is the same colour. A blank render still has the
    /// window's rounded corners and a >3 KB PNG, so file size is not evidence of content.
    static func isEffectivelyBlank(_ rep: NSBitmapImageRep) -> Bool {
        guard let cg = rep.cgImage, let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return true }
        let width = cg.width
        let height = cg.height
        guard width > 4, height > 4 else { return true }
        let bpp = cg.bitsPerPixel / 8
        let rowBytes = cg.bytesPerRow
        var counts: [UInt32: Int] = [:]
        var sampled = 0
        var y = 0
        while y < height {
            let row = bytes + y * rowBytes
            var x = 0
            while x < width {
                let p = row + x * bpp
                // Quantise to 5 bits per channel so antialiasing is not counted as content.
                let key = (UInt32(p[0] >> 3) << 10) | (UInt32(p[1] >> 3) << 5) | UInt32(p[2] >> 3)
                counts[key, default: 0] += 1
                sampled += 1
                x += 6
            }
            y += 6
        }
        guard sampled > 0, let mode = counts.values.max() else { return true }
        return Double(mode) / Double(sampled) > 0.995
    }

    private static func cacheDisplayRep(of view: NSView) -> NSBitmapImageRep? {
        view.window?.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// SwiftUI renders through its own layer tree. Rendering that tree into a context is the
    /// best remaining attempt on a Mac without Screen Recording; on macOS 26 it often still
    /// comes back blank, which `isEffectivelyBlank` catches.
    private static func layerRep(of view: NSView) -> NSBitmapImageRep? {
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
        return NSBitmapImageRep(cgImage: image)
    }

    private static func layerData(of view: NSView) -> Data? {
        layerRep(of: view)?.representation(using: .png, properties: [:])
    }

    private static func makeName(window: NSWindow, index: Int) -> String {
        let base = window.title.isEmpty ? "window" : window.title
        let slug = base.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "…", with: "")
        return String(format: "%02d-%@", index, slug)
    }
}
