import SwiftUI
import AppKit
import LatticeKit

/// Renders a set of container variants so we know what the in-app screenshot path can capture.
/// `screencapture` is unavailable without Screen Recording, so the design review images are
/// produced by `ImageRenderer`; AppKit-backed containers are the ones that fail.
@MainActor
enum RenderProbe {

    static func runIfRequested(into dir: URL) {
        guard ProcessInfo.processInfo.environment["LATTICE_PROBE"] != nil else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Log.info("PROBE start → \(dir.path)")

        probe("vstack", AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Plain VStack").font(.system(size: 22, weight: .semibold))
                RoundedRectangle(cornerRadius: 10).fill(Color.accentColor).frame(height: 60)
                Text("card body").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        ), size: CGSize(width: 520, height: 240), dir: dir)

        probe("scrollview", AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Inside ScrollView").font(.system(size: 22, weight: .semibold))
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(height: 48)
                            .overlay(Text("row \(index)").font(.system(size: 13)))
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        ), size: CGSize(width: 520, height: 320), dir: dir)

        probe("form", AnyView(
            Form {
                Section("Section") {
                    TextField("Field", text: .constant("value"))
                    Toggle("Switch", isOn: .constant(true))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        ), size: CGSize(width: 520, height: 240), dir: dir)

        probe("list", AnyView(
            List {
                Label("One", systemImage: "square.grid.2x2")
                Label("Two", systemImage: "keyboard")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        ), size: CGSize(width: 260, height: 200), dir: dir)

        probe("material", AnyView(
            VStack(spacing: 10) {
                Text("Material").font(.system(size: 18, weight: .semibold))
                RoundedRectangle(cornerRadius: 12).fill(.regularMaterial).frame(height: 60)
                Button("Button") {}.buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        ), size: CGSize(width: 420, height: 240), dir: dir)

        Log.info("PROBE done")
        if ProcessInfo.processInfo.environment["LATTICE_CAPTURE_EXIT"] == "1" { NSApp.terminate(nil) }
    }

    private static func probe(_ name: String, _ view: AnyView, size: CGSize, dir: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            Log.error("PROBE \(name): renderer produced nothing")
            return
        }
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
        Log.info("PROBE \(name): \(Int(image.size.width))x\(Int(image.size.height)) \(data.count) bytes")
    }
}
