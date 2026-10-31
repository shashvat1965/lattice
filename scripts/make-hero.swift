#!/usr/bin/env swift
// Renders docs/hero.png — a branded banner for the README, drawn with Core Graphics so it
// needs no screen capture permission.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = root.appendingPathComponent("docs/hero.png")
try? FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)

let width = 1760.0
let height = 720.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// Background: deep graphite with a soft indigo glow bottom-left.
cg.setFillColor(NSColor(srgbRed: 0.055, green: 0.06, blue: 0.075, alpha: 1).cgColor)
cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [NSColor(srgbRed: 0.29, green: 0.40, blue: 0.98, alpha: 0.34).cgColor,
                               NSColor(srgbRed: 0.29, green: 0.40, blue: 0.98, alpha: 0).cgColor] as CFArray,
                      locations: [0, 1])!
cg.drawRadialGradient(glow,
                      startCenter: CGPoint(x: width * 0.16, y: height * 0.18), startRadius: 0,
                      endCenter: CGPoint(x: width * 0.16, y: height * 0.18), endRadius: height * 0.85,
                      options: [])

// Layout motif: four tiles on the right, drawn as a dwindle split.
let field = CGRect(x: width * 0.60, y: height * 0.20, width: width * 0.33, height: height * 0.60)
let gap = 14.0
let leftWidth = field.width * 0.55
let tiles: [(CGRect, CGFloat)] = [
    (CGRect(x: field.minX, y: field.minY, width: leftWidth, height: field.height), 0.92),
    (CGRect(x: field.maxX - (field.width - leftWidth - gap), y: field.minY + field.height * 0.46,
            width: field.width - leftWidth - gap, height: field.height * 0.54), 0.46),
    (CGRect(x: field.maxX - (field.width - leftWidth - gap), y: field.minY,
            width: field.width - leftWidth - gap, height: field.height * 0.46 - gap), 0.18),
]
for (rect, alpha) in tiles {
    let path = CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)
    cg.addPath(path)
    cg.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
    cg.fillPath()
}
// Accent tile rides on top of the third slot.
let accent = CGRect(x: field.maxX - (field.width - leftWidth - gap), y: field.minY,
                    width: field.width - leftWidth - gap, height: field.height * 0.46 - gap)
let accentPath = CGPath(roundedRect: accent, cornerWidth: 14, cornerHeight: 14, transform: nil)
cg.saveGState()
cg.addPath(accentPath)
cg.clip()
let accentGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [NSColor(srgbRed: 0.52, green: 0.62, blue: 1, alpha: 1).cgColor,
                                         NSColor(srgbRed: 0.30, green: 0.41, blue: 0.98, alpha: 1).cgColor] as CFArray,
                                locations: [0, 1])!
cg.drawLinearGradient(accentGradient,
                      start: CGPoint(x: accent.midX, y: accent.maxY),
                      end: CGPoint(x: accent.midX, y: accent.minY), options: [])
cg.restoreGState()

// Wordmark.
let title = NSAttributedString(string: "Lattice", attributes: [
    .font: NSFont.systemFont(ofSize: 128, weight: .semibold),
    .foregroundColor: NSColor.white,
    .kern: -3,
])
title.draw(at: CGPoint(x: 120, y: height * 0.50))

let subtitle = NSAttributedString(string: "Every window in its place.", attributes: [
    .font: NSFont.systemFont(ofSize: 40, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.62),
])
subtitle.draw(at: CGPoint(x: 124, y: height * 0.50 - 56))

let eyebrow = NSAttributedString(string: "A NATIVE WINDOW MANAGER FOR macOS", attributes: [
    .font: NSFont.systemFont(ofSize: 21, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.52, green: 0.62, blue: 1, alpha: 0.9),
    .kern: 3.4,
])
eyebrow.draw(at: CGPoint(x: 128, y: height * 0.50 + 132))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
