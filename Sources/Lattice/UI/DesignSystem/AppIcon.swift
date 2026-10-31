import AppKit
import SwiftUI
import LatticeKit

// MARK: - Icon store

/// Resolves real application icons by bundle identifier (falling back to a running
/// app name) and caches both the image and a representative colour sampled from it.
@MainActor
final class AppIconStore {

    static let shared = AppIconStore()

    struct Entry {
        let icon: NSImage
        let tint: Color
    }

    private var entries: [String: Entry] = [:]
    private var misses: Set<String> = []

    private init() {}

    func entry(bundleID: String?, appName: String) -> Entry? {
        let key = cacheKey(bundleID: bundleID, appName: appName)
        if let hit = entries[key] { return hit }
        if misses.contains(key) { return nil }
        guard let image = resolveIcon(bundleID: bundleID, appName: appName) else {
            misses.insert(key)
            return nil
        }
        let entry = Entry(icon: image, tint: dominantColor(of: image) ?? .secondary)
        entries[key] = entry
        return entry
    }

    func tint(bundleID: String?, appName: String) -> Color? {
        entry(bundleID: bundleID, appName: appName)?.tint
    }

    private func cacheKey(bundleID: String?, appName: String) -> String {
        bundleID ?? "name:\(appName)"
    }

    private func resolveIcon(bundleID: String?, appName: String) -> NSImage? {
        if let bundleID, !bundleID.isEmpty {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
               let icon = running.icon {
                return icon
            }
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
           let icon = running.icon {
            return icon
        }
        return nil
    }

    /// A representative colour: alpha- and saturation-weighted average of a 12×12
    /// downsample, so a mostly-white icon does not tint a window grey.
    private func dominantColor(of image: NSImage) -> Color? {
        let side = 12
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, total: CGFloat = 0
        for y in 0..<side {
            for x in 0..<side {
                guard let raw = rep.colorAt(x: x, y: y),
                      let c = raw.usingColorSpace(.sRGB) else { continue }
                let alpha = c.alphaComponent
                guard alpha > 0.25 else { continue }
                let maxC = max(c.redComponent, c.greenComponent, c.blueComponent)
                let minC = min(c.redComponent, c.greenComponent, c.blueComponent)
                let saturation = maxC > 0.001 ? (maxC - minC) / maxC : 0
                let weight = alpha * (0.18 + saturation * 1.5)
                r += c.redComponent * weight
                g += c.greenComponent * weight
                b += c.blueComponent * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }
        return Color(nsColor: NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1))
    }
}

// MARK: - Icon

/// A real app icon, or a monogram in the accent colour when the app cannot be found.
struct AppIcon: View {
    var bundleID: String?
    var appName: String
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image = AppIconStore.shared.entry(bundleID: bundleID, appName: appName)?.icon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                MonogramTile(name: appName, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Letter tile used when an app has no resolvable icon.
struct MonogramTile: View {
    var name: String
    var size: CGFloat = 26

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(scheme == .dark ? 0.34 : 0.20),
                             Color.accentColor.opacity(scheme == .dark ? 0.18 : 0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: LatticeTheme.hairline)
            }
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.first ?? "?").uppercased()
    }
}

// MARK: - App tile

/// Icon + app name + optional window title + optional trailing detail (size, "floating").
struct AppTile: View {
    var bundleID: String?
    var appName: String
    var title: String?
    var detail: String?
    var iconSize: CGFloat = 26

    var body: some View {
        HStack(spacing: LatticeTheme.Spacing.xs) {
            AppIcon(bundleID: bundleID, appName: appName, size: iconSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let title, !title.isEmpty, title != appName {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: LatticeTheme.Spacing.xxs)

            if let detail {
                Text(detail)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(height: max(LatticeTheme.compactRow, iconSize + 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        [appName, title, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
