#!/usr/bin/env swift
// Draws Lattice.icns — a squircle mark with a dwindle split motif.
// Run: swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Lattice.iconset")
let out = root.appendingPathComponent("App/Lattice.icns")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func squircle(_ rect: CGRect) -> CGPath {
    // Continuous-curvature rounded rect, close to the macOS icon grid.
    let radius = rect.width * 0.2237
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let inset = size * 0.055
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    // Drop shadow beneath the squircle.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                 blur: size * 0.035,
                 color: NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.addPath(squircle(body))
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()

    // Body: deep graphite, lit from the top.
    cg.saveGState()
    cg.addPath(squircle(body))
    cg.clip()
    let colors = [
        NSColor(srgbRed: 0.157, green: 0.165, blue: 0.196, alpha: 1).cgColor,
        NSColor(srgbRed: 0.086, green: 0.090, blue: 0.110, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(gradient,
                          start: CGPoint(x: body.midX, y: body.maxY),
                          end: CGPoint(x: body.midX, y: body.minY),
                          options: [])
    // Top sheen.
    let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.16).cgColor,
                                    NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    cg.drawLinearGradient(sheen,
                          start: CGPoint(x: body.midX, y: body.maxY),
                          end: CGPoint(x: body.midX, y: body.midY * 0.96),
                          options: [])
    cg.restoreGState()

    // Tile motif: a dwindle split — one tall tile, two stacked on the right.
    let pad = size * 0.215
    let field = body.insetBy(dx: pad, dy: pad)
    let gap = size * 0.032
    let leftWidth = field.width * 0.545
    let leftRect = CGRect(x: field.minX, y: field.minY, width: leftWidth, height: field.height)
    let rightX = field.minX + leftWidth + gap
    let rightWidth = field.width - leftWidth - gap
    let topHeight = (field.height - gap) * 0.58
    let topRect = CGRect(x: rightX, y: field.minY + (field.height - topHeight), width: rightWidth, height: topHeight)
    let bottomRect = CGRect(x: rightX, y: field.minY, width: rightWidth, height: field.height - topHeight - gap)

    func tile(_ rect: CGRect, alpha: CGFloat, accent: Bool, radius: CGFloat) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -size * 0.006),
                     blur: size * 0.018,
                     color: NSColor.black.withAlphaComponent(0.35).cgColor)
        cg.addPath(path)
        if accent {
            let accentColors = [
                NSColor(srgbRed: 0.478, green: 0.588, blue: 1.0, alpha: 1).cgColor,
                NSColor(srgbRed: 0.290, green: 0.400, blue: 0.980, alpha: 1).cgColor,
            ] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: accentColors, locations: [0, 1])!
            cg.clip()
            cg.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
                                  end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        } else {
            cg.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            cg.fillPath()
        }
        cg.restoreGState()
    }

    let radius = size * 0.028
    tile(leftRect, alpha: 0.94, accent: false, radius: radius)
    tile(topRect, alpha: 0.78, accent: false, radius: radius)
    tile(bottomRect, alpha: 1.0, accent: true, radius: radius)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, size) in variants {
    let rep = drawIcon(size: size)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! process.run()
process.waitUntilExit()
print("wrote \(out.path)")
