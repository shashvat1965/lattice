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
        case .layoutRows: "rectangle.split.1x2"
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
             .moveToSpace6, .moveToSpace7, .moveToSpace8, .moveToSpace9: "arrow.right.square"
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
    /// What to do when a Space holds more windows than the display can fit at the sizes their
    /// apps demand. `true` keeps the chosen layout and lets each app clamp (yabai-style, which
    /// means windows can overlap); `false` leaves the Space exactly as it is and says "Space
    /// full" in Overview.
    public var tileCrowdedSpaces: Bool = true
    /// The floor each app actually enforces, learned from a refused write. Keyed by bundle id
    /// as `[width, height]`; persisted so a relaunch does not have to learn it again.
    public var learnedMinimums: [String: [CGFloat]] = [:]

    // MARK: Input
    public var bindings: [CommandID: KeyCombo] = Preferences.defaultBindings
    /// A second chord for a command, for people who want both a mnemonic and an arrow.
    public var alternateBindings: [CommandID: KeyCombo] = Preferences.defaultAlternates
    /// Which key jumps to which Space. `⌥<key>` switches, `⇧⌥<key>` sends the window.
    /// Any key the keyboard can type is allowed, so letters work as well as digits.
    public var spaceKeys: [String: Int] = Preferences.defaultSpaceKeys
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
        case tileCrowdedSpaces, learnedMinimums
        case bindings, alternateBindings, spaceKeys
        case snapToEdges, snapZoneSet, dragToSwap, focusFollowsMouse,
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
        tileCrowdedSpaces = try c.decodeIfPresent(Bool.self, forKey: .tileCrowdedSpaces) ?? d.tileCrowdedSpaces
        learnedMinimums = try c.decodeIfPresent([String: [CGFloat]].self, forKey: .learnedMinimums) ?? d.learnedMinimums
        bindings = try c.decodeIfPresent([CommandID: KeyCombo].self, forKey: .bindings) ?? d.bindings
        alternateBindings = try c.decodeIfPresent([CommandID: KeyCombo].self, forKey: .alternateBindings) ?? d.alternateBindings
        spaceKeys = try c.decodeIfPresent([String: Int].self, forKey: .spaceKeys) ?? d.spaceKeys
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
        // AeroSpace-compatible: ⌥ + HJKL focuses, ⇧⌥ + HJKL moves the window.
        let option: Set<KeyCombo.Modifier> = [.option]
        let shiftOption: Set<KeyCombo.Modifier> = [.option, .shift]
        map[.focusLeft] = KeyCombo(key: "h", modifiers: option)
        map[.focusRight] = KeyCombo(key: "l", modifiers: option)
        map[.focusUp] = KeyCombo(key: "k", modifiers: option)
        map[.focusDown] = KeyCombo(key: "j", modifiers: option)
        map[.moveLeft] = KeyCombo(key: "h", modifiers: shiftOption)
        map[.moveRight] = KeyCombo(key: "l", modifiers: shiftOption)
        map[.moveUp] = KeyCombo(key: "k", modifiers: shiftOption)
        map[.moveDown] = KeyCombo(key: "j", modifiers: shiftOption)

        let cmdCtrl: Set<KeyCombo.Modifier> = [.control, .option, .command]
        map[.swapLeft] = KeyCombo(key: "left", modifiers: cmdCtrl)
        map[.swapRight] = KeyCombo(key: "right", modifiers: cmdCtrl)
        map[.swapUp] = KeyCombo(key: "up", modifiers: cmdCtrl)
        map[.swapDown] = KeyCombo(key: "down", modifiers: cmdCtrl)

        map[.grow] = KeyCombo(key: "equal", modifiers: option)
        map[.shrink] = KeyCombo(key: "minus", modifiers: option)
        map[.growHeight] = KeyCombo(key: "up", modifiers: [.control, .option])
        map[.shrinkHeight] = KeyCombo(key: "down", modifiers: [.control, .option])

        map[.layoutDwindle] = KeyCombo(key: "1", modifiers: cmdCtrl)
        map[.layoutColumns] = KeyCombo(key: "2", modifiers: cmdCtrl)
        map[.layoutRows] = KeyCombo(key: "3", modifiers: cmdCtrl)
        map[.layoutGrid] = KeyCombo(key: "4", modifiers: cmdCtrl)
        map[.layoutMaster] = KeyCombo(key: "5", modifiers: cmdCtrl)
        map[.layoutStack] = KeyCombo(key: "6", modifiers: cmdCtrl)
        map[.cycleLayout] = KeyCombo(key: "space", modifiers: option)
        map[.toggleFloat] = KeyCombo(key: "f", modifiers: option)
        map[.toggleFullscreen] = KeyCombo(key: "f", modifiers: [.option, .shift])
        map[.focusMode] = KeyCombo(key: "z", modifiers: [.option, .shift])
        map[.center] = KeyCombo(key: "c", modifiers: option)
        map[.zoom] = KeyCombo(key: "return", modifiers: option)
        map[.nextSpace] = KeyCombo(key: "right", modifiers: [.option, .control])
        map[.previousSpace] = KeyCombo(key: "left", modifiers: [.option, .control])
        map[.commandPalette] = KeyCombo(key: "k", modifiers: cmdCtrl)
        map[.cheatSheet] = KeyCombo(key: "slash", modifiers: cmdCtrl)
        map[.toggleEnabled] = KeyCombo(key: "p", modifiers: cmdCtrl)
        map[.showApp] = KeyCombo(key: "l", modifiers: cmdCtrl)
        return map
    }()

    /// Arrow-key equivalents, so ⌥↑ moves a window up while ⇧⌥K does the same thing.
    public static let defaultAlternates: [CommandID: KeyCombo] = [
        .moveLeft: KeyCombo(key: "left", modifiers: [.option]),
        .moveRight: KeyCombo(key: "right", modifiers: [.option]),
        .moveUp: KeyCombo(key: "up", modifiers: [.option]),
        .moveDown: KeyCombo(key: "down", modifiers: [.option]),
    ]

    /// ⌥1…⌥9 jump to Spaces, ⇧⌥1…⇧⌥9 send the focused window there. Letters are allowed.
    public static let defaultSpaceKeys: [String: Int] = {
        var map: [String: Int] = [:]
        for number in 1...9 { map[String(number)] = number }
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
