import Foundation
import CoreGraphics
import ApplicationServices

/// Stable identity for a managed window. Backed by the CGWindowID so it survives
/// AX tree churn (re-parenting, title changes, tab switches in browsers).
public struct WindowID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
    public var description: String { "window(\(raw))" }
}

public struct SpaceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
    public var description: String { "space(\(raw))" }
}

public struct DisplayID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let raw: UInt32
    public init(_ raw: UInt32) { self.raw = raw }
    public var description: String { "display(\(raw))" }
}

/// Where a window lives and what it is, as far as Lattice is concerned.
public struct ManagedWindow: Identifiable, Hashable, Sendable {
    public var id: WindowID
    public var pid: pid_t
    public var appName: String
    public var bundleID: String?
    public var title: String
    public var frame: CGRect
    /// The macOS Space this window is assigned to. Real Spaces, not emulated ones.
    public var space: SpaceID
    public var display: DisplayID
    public var isFloating: Bool
    public var isFullscreen: Bool
    public var isMinimized: Bool
    public var role: String?
    public var subrole: String?
    /// The smallest size the app will accept for this window, from `AXMinSize`.
    /// Many apps clamp resizes to this, so the tiler plans around it instead of fighting it.
    public var minSize: CGSize?
    public var maxSize: CGSize?
    public var axElement: AXUIElementRef?

    public init(id: WindowID, pid: pid_t, appName: String, bundleID: String? = nil,
                title: String, frame: CGRect, space: SpaceID, display: DisplayID,
                isFloating: Bool = false, isFullscreen: Bool = false, isMinimized: Bool = false,
                role: String? = nil, subrole: String? = nil,
                minSize: CGSize? = nil, maxSize: CGSize? = nil,
                axElement: AXUIElementRef? = nil) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
        self.space = space
        self.display = display
        self.isFloating = isFloating
        self.isFullscreen = isFullscreen
        self.isMinimized = isMinimized
        self.role = role
        self.subrole = subrole
        self.minSize = minSize
        self.maxSize = maxSize
        self.axElement = axElement
    }
}

public typealias AXUIElementRef = AXUIElement

public struct DisplayInfo: Identifiable, Hashable, Sendable {
    public var id: DisplayID
    /// Full frame in the global CG coordinate space.
    public var frame: CGRect
    /// Frame minus the menu bar (and minus the Dock when it is not auto-hidden).
    public var visibleFrame: CGRect
    public var name: String
    public var hasNotch: Bool
    public var scale: CGFloat

    public init(id: DisplayID, frame: CGRect, visibleFrame: CGRect, name: String,
                hasNotch: Bool = false, scale: CGFloat = 2) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.name = name
        self.hasNotch = hasNotch
        self.scale = scale
    }
}

public struct Margin: Codable, Hashable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init(_ all: CGFloat) {
        self.init(top: all, leading: all, bottom: all, trailing: all)
    }
}

public extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func inset(by margin: Margin) -> CGRect {
        CGRect(x: origin.x + margin.leading,
               y: origin.y + margin.top,
               width: max(0, width - margin.leading - margin.trailing),
               height: max(0, height - margin.top - margin.bottom))
    }

    func roundedToPixels(scale: CGFloat) -> CGRect {
        func r(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
        return CGRect(x: r(origin.x), y: r(origin.y), width: r(width), height: r(height))
    }
}
