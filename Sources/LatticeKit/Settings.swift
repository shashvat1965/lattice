import Foundation
import AppKit

// MARK: - Key combos

public struct KeyCombo: Codable, Hashable, Sendable, Comparable {
    public var key: String          // single character, lowercase; or a special name
    public var modifiers: Set<Modifier>

    public enum Modifier: String, Codable, CaseIterable, Sendable {
        case control, option, command, shift

        public var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .command: "⌘"
            case .shift: "⇧"
            }
        }

        public var flag: CGEventFlags {
            switch self {
            case .control: .maskControl
            case .option: .maskAlternate
            case .command: .maskCommand
            case .shift: .maskShift
            }
        }
    }

    public init(key: String, modifiers: Set<Modifier>) {
        self.key = key
        self.modifiers = modifiers
    }

    public var display: String {
        let order: [Modifier] = [.control, .option, .shift, .command]
        return order.filter { modifiers.contains($0) }.map(\.symbol).joined() + Self.pretty(key)
    }

    public static func pretty(_ key: String) -> String {
        switch key {
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "return": "↩"
        case "tab": "⇥"
        case "space": "Space"
        case "escape": "Esc"
        case "delete": "⌫"
        case "comma": ","
        case "period": "."
        case "slash": "/"
        case "minus": "-"
        case "equal": "="
        default: key.uppercased()
        }
    }

    public static func < (lhs: KeyCombo, rhs: KeyCombo) -> Bool {
        lhs.display < rhs.display
    }
}

// MARK: - Commands

public enum CommandCategory: String, CaseIterable, Sendable {
    case focus = "Focus"
    case move = "Move Window"
    case resize = "Resize"
    case layout = "Layout"
    case spaces = "Spaces"
    case displays = "Displays"
    case app = "Lattice"

    public var title: String { rawValue }
}

public enum CommandID: String, CaseIterable, Codable, Sendable, Identifiable {
    case focusLeft, focusRight, focusUp, focusDown
    case moveLeft, moveRight, moveUp, moveDown
    case swapLeft, swapRight, swapUp, swapDown
    case grow, shrink, growHeight, shrinkHeight
    case layoutDwindle, layoutColumns, layoutRows, layoutGrid, layoutMaster, layoutStack
    case cycleLayout
    case toggleFloat, toggleFullscreen, focusMode, center, zoom
    case nextSpace, previousSpace
    case space1, space2, space3, space4, space5, space6, space7, space8, space9
    case moveToSpace1, moveToSpace2, moveToSpace3, moveToSpace4, moveToSpace5
    case moveToSpace6, moveToSpace7, moveToSpace8, moveToSpace9
    case nextDisplay, previousDisplay
    case commandPalette, cheatSheet, showApp, toggleEnabled, undo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focusLeft: "Focus Left"
        case .focusRight: "Focus Right"
        case .focusUp: "Focus Up"
        case .focusDown: "Focus Down"
        case .moveLeft: "Move Left"
        case .moveRight: "Move Right"
        case .moveUp: "Move Up"
        case .moveDown: "Move Down"
        case .swapLeft: "Swap Left"
        case .swapRight: "Swap Right"
        case .swapUp: "Swap Up"
        case .swapDown: "Swap Down"
        case .grow: "Wider"
        case .shrink: "Narrower"
        case .growHeight: "Taller"
        case .shrinkHeight: "Shorter"
        case .layoutDwindle: "Dwindle"
        case .layoutColumns: "Columns"
        case .layoutRows: "Rows"
        case .layoutGrid: "Grid"
        case .layoutMaster: "Master"
        case .layoutStack: "Stack"
        case .cycleLayout: "Next Layout"
        case .toggleFloat: "Float Window"
        case .toggleFullscreen: "Full Screen"
        case .focusMode: "Focus Mode"
        case .center: "Centre Window"
        case .zoom: "Zoom Window"
        case .nextSpace: "Next Space"
        case .previousSpace: "Previous Space"
        case .space1, .space2, .space3, .space4, .space5, .space6, .space7, .space8, .space9:
            "Go to Space \(spaceNumber)"
        case .moveToSpace1, .moveToSpace2, .moveToSpace3, .moveToSpace4, .moveToSpace5,
             .moveToSpace6, .moveToSpace7, .moveToSpace8, .moveToSpace9:
            "Send to Space \(spaceNumber)"
        case .nextDisplay: "Next Display"
        case .previousDisplay: "Previous Display"
        case .commandPalette: "Command Palette"
        case .cheatSheet: "Shortcut Cheat Sheet"
        case .showApp: "Open Lattice"
        case .toggleEnabled: "Pause Tiling"
        case .undo: "Undo Layout Change"
        }
    }

    public var category: CommandCategory {
        switch self {
        case .focusLeft, .focusRight, .focusUp, .focusDown: .focus
        case .moveLeft, .moveRight, .moveUp, .moveDown,
             .swapLeft, .swapRight, .swapUp, .swapDown,
             .moveToSpace1, .moveToSpace2, .moveToSpace3, .moveToSpace4, .moveToSpace5,
             .moveToSpace6, .moveToSpace7, .moveToSpace8, .moveToSpace9,
             .toggleFloat, .toggleFullscreen, .center, .zoom: .move
        case .grow, .shrink, .growHeight, .shrinkHeight: .resize
        case .layoutDwindle, .layoutColumns, .layoutRows, .layoutGrid, .layoutMaster,
             .layoutStack, .cycleLayout, .focusMode: .layout
        case .nextSpace, .previousSpace, .space1, .space2, .space3, .space4, .space5,
             .space6, .space7, .space8, .space9: .spaces
        case .nextDisplay, .previousDisplay: .displays
        case .commandPalette, .cheatSheet, .showApp, .toggleEnabled, .undo: .app
        }
    }

    public var spaceNumber: Int {
        let digits = rawValue.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    public var symbol: String {
        switch self {
        case .focusLeft, .moveLeft, .swapLeft: "arrow.left"
        case .focusRight, .moveRight, .swapRight: "arrow.right"
        case .focusUp, .moveUp, .swapUp: "arrow.up"
        case .focusDown, .moveDown, .swapDown: "arrow.down"
        case .grow, .shrink: "arrow.left.and.right"
        case .growHeight, .shrinkHeight: "arrow.up.and.down"
        case .layoutDwindle: "rectangle.split.3x1"
        case .layoutColumns: "rectangle.split.3x1"
        case .layoutRows: "rectangle.split.1x3"
        case .layoutGrid: "square.grid.2x2"
        case .layoutMaster: "rectangle.leadinghalf.inset.filled"
        case .layoutStack: "rectangle.stack"
        case .cycleLayout: "square.stack.3d.up"
        case .toggleFloat: "macwindow.on.rectangle"
        case .toggleFullscreen: "arrow.up.left.and.arrow.down.right"
        case .focusMode: "circle.dashed"
        case .center: "dot.squareshape"
        case .zoom: "arrow.up.left.and.arrow.down.right.circle"
        case .nextSpace: "arrow.right.to.line"
        case .previousSpace: "arrow.left.to.line"
        case .nextDisplay: "display"
        case .previousDisplay: "display"
        case .commandPalette: "command"
        case .cheatSheet: "keyboard"
        case .showApp: "macwindow"
        case .toggleEnabled: "pause.circle"
        case .undo: "arrow.uturn.backward"
        case .space1, .space2, .space3, .space4, .space5,
             .space6, .space7, .space8, .space9: "square.dashed"
        case .moveToSpace1, .moveToSpace2, .moveToSpace3, .moveToSpace4, .moveToSpace5,
             .moveToSpace6, .moveToSpace7, .moveToSpace8, .moveToSpace9: "square.and.arrow.right"
        }
    }
}

// MARK: - Preferences

public enum InsertionPolicy: String, Codable, CaseIterable, Sendable {
    case end, afterFocused, master

    public var title: String {
        switch self {
        case .end: "At the end"
        case .afterFocused: "After the focused window"
        case .master: "As the master window"
        }
    }
}

public enum AnimationCurve: String, Codable, CaseIterable, Sendable {
    case easeOut, easeInOut, spring

    public var title: String {
        switch self {
        case .easeOut: "Ease out"
        case .easeInOut: "Ease in-out"
        case .spring: "Spring"
        }
    }
}

public enum BorderScope: String, Codable, CaseIterable, Sendable {
    case focused, all

    public var title: String {
        switch self {
        case .focused: "Focused window"
        case .all: "Every tiled window"
        }
    }
}

public enum SnapZoneSet: String, Codable, CaseIterable, Sendable {
    case halves, halvesAndQuarters, everything

    public var title: String {
        switch self {
        case .halves: "Halves"
        case .halvesAndQuarters: "Halves and quarters"
        case .everything: "Halves, quarters, thirds and centre"
        }
    }
}

/// A rule for one application. Rules are additive: an app can float *and* be sent to a Space.
public struct AppRule: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var float: Bool = false
    public var unmanaged: Bool = false
    public var layout: LayoutKind? = nil
    public var spaceNumber: Int? = nil
    public var titleContains: String? = nil

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public var summary: String {
        var parts: [String] = []
        if unmanaged { parts.append("leave alone") }
        if float { parts.append("float") }
        if let layout { parts.append(layout.title.lowercased()) }
        if let spaceNumber { parts.append("Space \(spaceNumber)") }
        if let titleContains, !titleContains.isEmpty { parts.append("“\(titleContains)”") }
        return parts.isEmpty ? "tiled" : parts.joined(separator: " · ")
    }
}

/// Per-display overrides. Any nil field falls back to the global preference.
public struct DisplayOverride: Codable, Hashable, Sendable {
    public var gap: CGFloat?
    public var outerGap: CGFloat?
    public var layout: LayoutKind?
    public var respectDock: Bool?

    public init(gap: CGFloat? = nil, outerGap: CGFloat? = nil, layout: LayoutKind? = nil, respectDock: Bool? = nil) {
        self.gap = gap
        self.outerGap = outerGap
        self.layout = layout
        self.respectDock = respectDock
    }
}

public struct Preferences: Codable, Sendable, Equatable {
    // MARK: Core
    public var enabled: Bool = true
    /// Default layout for a Space that has never been given its own.
    public var layout: LayoutKind = .dwindle
    /// Per-Space layout, keyed by WindowServer's own Space id. A Space keeps its layout
    /// until the user deletes that Space; new Spaces fall back to `layout`.
    public var spaceLayouts: [String: LayoutKind] = [:]

    // MARK: Gaps and padding
    public var gap: CGFloat = 8
    public var outerGap: CGFloat = 8
    public var edges: Margin = Margin(top: 0, leading: 0, bottom: 0, trailing: 0)
    public var respectDock: Bool = true
    public var respectMenuBar: Bool = true

    // MARK: Layout tuning
    public var masterRatio: Double = 0.62
    public var stackPeek: CGFloat = 14
    public var gridColumns: Int = 0          // 0 = choose automatically
    public var insertionPolicy: InsertionPolicy = .end
    public var autoBalance: Bool = true

    // MARK: Motion
    public var animate: Bool = true
    public var animationDuration: Double = 0.18
    public var animationCurve: AnimationCurve = .easeOut
    public var animateSnap: Bool = true
    public var animateLayoutSwaps: Bool = true

    // MARK: Borders
    public var borderEnabled: Bool = false
    public var borderWidth: CGFloat = 2
    public var borderOpacity: Double = 0.85
    public var borderColorHex: String? = nil   // nil = system accent
    public var borderScope: BorderScope = .focused

    // MARK: Rules
    public var floatBundleIDs: Set<String> = [
        "com.apple.Spotlight", "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.systemuiserver", "com.apple.dock", "com.raycast.macos",
        "com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.Passwords",
    ]
    public var floatApps: Set<String> = []
    public var unmanagedBundleIDs: Set<String> = []
    public var rules: [AppRule] = []
    public var minTiledWidth: CGFloat = 220
    public var minTiledHeight: CGFloat = 140

    // MARK: Input
    public var bindings: [CommandID: KeyCombo] = Preferences.defaultBindings
    public var snapToEdges: Bool = true
    public var snapZoneSet: SnapZoneSet = .halvesAndQuarters
    public var dragToSwap: Bool = true
    public var focusFollowsMouse: Bool = false
    public var warpMouseOnFocus: Bool = false
    public var showSnapPreview: Bool = true
    public var snapPreviewStyle: String = "tinted"

    // MARK: Spaces and displays
    public var followWindowAcrossSpaces: Bool = true
    public var displayOverrides: [String: DisplayOverride] = [:]

    // MARK: App
    public var enterFullScreenDelay: Double = 0.2
    public var showMenuBarIcon: Bool = true
    public var accentOverride: String? = nil
    public var launchAtLogin: Bool = false
    public var hasCompletedOnboarding: Bool = false

    // MARK: Advanced
    public var reconcileDebounceMs: Int = 120
    public var verboseLogging: Bool = false

    public init() {}

    // MARK: Per-Space layout

    /// The layout a given Space is using. Spaces that have never been configured fall back
    /// to the user's default, so adding a Space never produces a surprise.
    public func layout(for space: SpaceID) -> LayoutKind {
        spaceLayouts[String(space.raw)] ?? layout
    }

    /// Returns true when the Space has an explicit choice of its own.
    public func hasOwnLayout(_ space: SpaceID) -> Bool {
        spaceLayouts[String(space.raw)] != nil
    }

    public mutating func setLayout(_ kind: LayoutKind, for space: SpaceID) {
        spaceLayouts[String(space.raw)] = kind
    }

    public mutating func clearLayoutOverrides() {
        spaceLayouts.removeAll()
    }

    // MARK: - Rule and display helpers

    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return rules.first { $0.bundleID == bundleID }
    }

    public func isUnmanaged(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return unmanagedBundleIDs.contains(bundleID) || (rule(for: bundleID)?.unmanaged ?? false)
    }

    public func shouldFloat(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return floatBundleIDs.contains(bundleID)
            || floatApps.contains(bundleID)
            || (rule(for: bundleID)?.float ?? false)
    }

    public func override(for display: DisplayID) -> DisplayOverride? {
        displayOverrides[String(display.raw)]
    }

    public func innerGap(for display: DisplayID) -> CGFloat {
        override(for: display)?.gap ?? gap
    }

    public func outerPadding(for display: DisplayID) -> CGFloat {
        override(for: display)?.outerGap ?? outerGap
    }

    public func layout(for display: DisplayID, space: SpaceID) -> LayoutKind {
        layout(for: space)
    }

    public func docksRespect(for display: DisplayID) -> Bool {
        override(for: display)?.respectDock ?? respectDock
    }

    // MARK: Decoding

    private enum CodingKeys: String, CodingKey {
        case enabled, layout, spaceLayouts
        case gap, outerGap, edges, respectDock, respectMenuBar
        case masterRatio, stackPeek, gridColumns, insertionPolicy, autoBalance
        case animate, animationDuration, animationCurve, animateSnap, animateLayoutSwaps
        case borderEnabled, borderWidth, borderOpacity, borderColorHex, borderScope
        case floatBundleIDs, floatApps, unmanagedBundleIDs, rules, minTiledWidth, minTiledHeight
        case bindings, snapToEdges, snapZoneSet, dragToSwap, focusFollowsMouse,
             warpMouseOnFocus, showSnapPreview, snapPreviewStyle
        case followWindowAcrossSpaces, displayOverrides
        case enterFullScreenDelay, showMenuBarIcon, accentOverride, launchAtLogin, hasCompletedOnboarding
        case reconcileDebounceMs, verboseLogging
    }

    /// Tolerant decoding: a preferences file written by an older build must never be lost
    /// because a field was added. Every key falls back to the current default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        layout = try c.decodeIfPresent(LayoutKind.self, forKey: .layout) ?? d.layout
        spaceLayouts = try c.decodeIfPresent([String: LayoutKind].self, forKey: .spaceLayouts) ?? [:]
        gap = try c.decodeIfPresent(CGFloat.self, forKey: .gap) ?? d.gap
        outerGap = try c.decodeIfPresent(CGFloat.self, forKey: .outerGap) ?? d.outerGap
        edges = try c.decodeIfPresent(Margin.self, forKey: .edges) ?? d.edges
        respectDock = try c.decodeIfPresent(Bool.self, forKey: .respectDock) ?? d.respectDock
        respectMenuBar = try c.decodeIfPresent(Bool.self, forKey: .respectMenuBar) ?? d.respectMenuBar
        masterRatio = try c.decodeIfPresent(Double.self, forKey: .masterRatio) ?? d.masterRatio
        stackPeek = try c.decodeIfPresent(CGFloat.self, forKey: .stackPeek) ?? d.stackPeek
        gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? d.gridColumns
        insertionPolicy = try c.decodeIfPresent(InsertionPolicy.self, forKey: .insertionPolicy) ?? d.insertionPolicy
        autoBalance = try c.decodeIfPresent(Bool.self, forKey: .autoBalance) ?? d.autoBalance
        animate = try c.decodeIfPresent(Bool.self, forKey: .animate) ?? d.animate
        animationDuration = try c.decodeIfPresent(Double.self, forKey: .animationDuration) ?? d.animationDuration
        animationCurve = try c.decodeIfPresent(AnimationCurve.self, forKey: .animationCurve) ?? d.animationCurve
        animateSnap = try c.decodeIfPresent(Bool.self, forKey: .animateSnap) ?? d.animateSnap
        animateLayoutSwaps = try c.decodeIfPresent(Bool.self, forKey: .animateLayoutSwaps) ?? d.animateLayoutSwaps
        borderEnabled = try c.decodeIfPresent(Bool.self, forKey: .borderEnabled) ?? d.borderEnabled
        borderWidth = try c.decodeIfPresent(CGFloat.self, forKey: .borderWidth) ?? d.borderWidth
        borderOpacity = try c.decodeIfPresent(Double.self, forKey: .borderOpacity) ?? d.borderOpacity
        borderColorHex = try c.decodeIfPresent(String.self, forKey: .borderColorHex)
        borderScope = try c.decodeIfPresent(BorderScope.self, forKey: .borderScope) ?? d.borderScope
        floatBundleIDs = try c.decodeIfPresent(Set<String>.self, forKey: .floatBundleIDs) ?? d.floatBundleIDs
        floatApps = try c.decodeIfPresent(Set<String>.self, forKey: .floatApps) ?? d.floatApps
        unmanagedBundleIDs = try c.decodeIfPresent(Set<String>.self, forKey: .unmanagedBundleIDs) ?? d.unmanagedBundleIDs
        rules = try c.decodeIfPresent([AppRule].self, forKey: .rules) ?? d.rules
        minTiledWidth = try c.decodeIfPresent(CGFloat.self, forKey: .minTiledWidth) ?? d.minTiledWidth
        minTiledHeight = try c.decodeIfPresent(CGFloat.self, forKey: .minTiledHeight) ?? d.minTiledHeight
        bindings = try c.decodeIfPresent([CommandID: KeyCombo].self, forKey: .bindings) ?? d.bindings
        snapToEdges = try c.decodeIfPresent(Bool.self, forKey: .snapToEdges) ?? d.snapToEdges
        snapZoneSet = try c.decodeIfPresent(SnapZoneSet.self, forKey: .snapZoneSet) ?? d.snapZoneSet
        dragToSwap = try c.decodeIfPresent(Bool.self, forKey: .dragToSwap) ?? d.dragToSwap
        focusFollowsMouse = try c.decodeIfPresent(Bool.self, forKey: .focusFollowsMouse) ?? d.focusFollowsMouse
        warpMouseOnFocus = try c.decodeIfPresent(Bool.self, forKey: .warpMouseOnFocus) ?? d.warpMouseOnFocus
        showSnapPreview = try c.decodeIfPresent(Bool.self, forKey: .showSnapPreview) ?? d.showSnapPreview
        snapPreviewStyle = try c.decodeIfPresent(String.self, forKey: .snapPreviewStyle) ?? d.snapPreviewStyle
        followWindowAcrossSpaces = try c.decodeIfPresent(Bool.self, forKey: .followWindowAcrossSpaces) ?? d.followWindowAcrossSpaces
        displayOverrides = try c.decodeIfPresent([String: DisplayOverride].self, forKey: .displayOverrides) ?? d.displayOverrides
        enterFullScreenDelay = try c.decodeIfPresent(Double.self, forKey: .enterFullScreenDelay) ?? d.enterFullScreenDelay
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        accentOverride = try c.decodeIfPresent(String.self, forKey: .accentOverride)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        reconcileDebounceMs = try c.decodeIfPresent(Int.self, forKey: .reconcileDebounceMs) ?? d.reconcileDebounceMs
        verboseLogging = try c.decodeIfPresent(Bool.self, forKey: .verboseLogging) ?? d.verboseLogging
    }

    public static let defaultBindings: [CommandID: KeyCombo] = {
        var map: [CommandID: KeyCombo] = [:]
        let mods: Set<KeyCombo.Modifier> = [.control, .option]
        map[.focusLeft] = KeyCombo(key: "h", modifiers: mods)
        map[.focusRight] = KeyCombo(key: "l", modifiers: mods)
        map[.focusUp] = KeyCombo(key: "k", modifiers: mods)
        map[.focusDown] = KeyCombo(key: "j", modifiers: mods)
        let shift: Set<KeyCombo.Modifier> = [.control, .option, .shift]
        map[.moveLeft] = KeyCombo(key: "h", modifiers: shift)
        map[.moveRight] = KeyCombo(key: "l", modifiers: shift)
        map[.moveUp] = KeyCombo(key: "k", modifiers: shift)
        map[.moveDown] = KeyCombo(key: "j", modifiers: shift)
        let cmdCtrl: Set<KeyCombo.Modifier> = [.control, .option, .command]
        map[.swapLeft] = KeyCombo(key: "left", modifiers: cmdCtrl)
        map[.swapRight] = KeyCombo(key: "right", modifiers: cmdCtrl)
        map[.swapUp] = KeyCombo(key: "up", modifiers: cmdCtrl)
        map[.swapDown] = KeyCombo(key: "down", modifiers: cmdCtrl)
        map[.grow] = KeyCombo(key: "equal", modifiers: mods)
        map[.shrink] = KeyCombo(key: "minus", modifiers: mods)
        map[.growHeight] = KeyCombo(key: "up", modifiers: mods)
        map[.shrinkHeight] = KeyCombo(key: "down", modifiers: mods)
        map[.layoutDwindle] = KeyCombo(key: "1", modifiers: cmdCtrl)
        map[.layoutColumns] = KeyCombo(key: "2", modifiers: cmdCtrl)
        map[.layoutRows] = KeyCombo(key: "3", modifiers: cmdCtrl)
        map[.layoutGrid] = KeyCombo(key: "4", modifiers: cmdCtrl)
        map[.cycleLayout] = KeyCombo(key: "space", modifiers: mods)
        map[.toggleFloat] = KeyCombo(key: "f", modifiers: mods)
        map[.toggleFullscreen] = KeyCombo(key: "f", modifiers: [.control, .option, .command])
        map[.focusMode] = KeyCombo(key: "z", modifiers: cmdCtrl)
        map[.center] = KeyCombo(key: "c", modifiers: mods)
        map[.zoom] = KeyCombo(key: "return", modifiers: mods)
        map[.nextSpace] = KeyCombo(key: "right", modifiers: [.option, .command])
        map[.previousSpace] = KeyCombo(key: "left", modifiers: [.option, .command])
        map[.commandPalette] = KeyCombo(key: "k", modifiers: [.control, .option, .command])
        map[.cheatSheet] = KeyCombo(key: "slash", modifiers: [.control, .option, .command])
        map[.toggleEnabled] = KeyCombo(key: "p", modifiers: cmdCtrl)
        map[.showApp] = KeyCombo(key: "l", modifiers: [.control, .option, .command])
        return map
    }()
}

public final class PreferencesStore: @unchecked Sendable {
    public static let shared = PreferencesStore()

    public private(set) var prefs: Preferences

    /// Real multicast: every subsystem can observe preferences without clobbering the others.
    private var observers: [UUID: (Preferences) -> Void] = [:]
    private let observerLock = NSLock()

    @discardableResult
    public func observe(_ handler: @escaping (Preferences) -> Void) -> UUID {
        let token = UUID()
        observerLock.lock()
        observers[token] = handler
        observerLock.unlock()
        return token
    }

    public func unobserve(_ token: UUID) {
        observerLock.lock()
        observers.removeValue(forKey: token)
        observerLock.unlock()
    }

    private func notify(_ new: Preferences) {
        observerLock.lock()
        let handlers = Array(observers.values)
        observerLock.unlock()
        if Thread.isMainThread {
            handlers.forEach { $0(new) }
        } else {
            DispatchQueue.main.async { handlers.forEach { $0(new) } }
        }
    }

    /// Kept for source compatibility; prefer `observe`.
    public var onChange: ((Preferences) -> Void)? {
        didSet { if let onChange { observe { onChange($0) } } }
    }

    private let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lattice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("preferences.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Preferences.self, from: data) {
            prefs = decoded
        } else {
            prefs = Preferences()
        }
    }

    public func update(_ mutate: (inout Preferences) -> Void) {
        var copy = prefs
        mutate(&copy)
        prefs = copy
        save()
        notify(copy)
    }

    public func replace(_ new: Preferences) {
        prefs = new
        save()
        notify(new)
    }

    public func reset() {
        replace(Preferences())
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
