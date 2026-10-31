import AppKit
import SwiftUI
import LatticeKit

// MARK: - Groups

enum PaletteGroup: Int, CaseIterable, Identifiable {
    case layouts, window, spaces, displays, lattice, windows

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .layouts: "Layouts"
        case .window: "Window"
        case .spaces: "Spaces"
        case .displays: "Displays"
        case .lattice: "Lattice"
        case .windows: "Windows"
        }
    }

    init(_ category: CommandCategory) {
        switch category {
        case .focus, .move, .resize: self = .window
        case .layout: self = .layouts
        case .spaces: self = .spaces
        case .displays: self = .displays
        case .app: self = .lattice
        }
    }
}

// MARK: - Item

/// One runnable palette entry. Built once per model change, filtered per keystroke.
struct PaletteItem {
    let id: String
    let title: String
    let subtitle: String?
    let group: PaletteGroup
    let symbol: String
    let pid: pid_t?
    let combo: KeyCombo?
    let keywords: [String]
    let run: () -> Void
}

// MARK: - Catalog

enum PaletteCatalog {

    @MainActor
    static func items(model: AppModel) -> [PaletteItem] {
        let bindings = model.prefs.prefs.bindings
        var items: [PaletteItem] = CommandID.allCases.map { command in
            let pausedTitle = command == .toggleEnabled
                ? (model.isEnabled ? "Pause Tiling" : "Resume Tiling")
                : command.title
            let symbol = command == .toggleEnabled
                ? (model.isEnabled ? "pause.circle" : "play.circle")
                : command.symbol

            return PaletteItem(
                id: "command." + command.rawValue,
                title: pausedTitle,
                subtitle: subtitle(for: command, model: model),
                group: PaletteGroup(command.category),
                symbol: symbol,
                pid: nil,
                combo: bindings[command],
                keywords: keywords(for: command),
                run: { [weak model] in
                    guard let model else { return }
                    // Choosing "Command Palette" is how the user got here.
                    if command == .commandPalette { return }
                    model.dispatch(command)
                }
            )
        }

        items.append(contentsOf: windowItems(model: model))
        return items
    }

    // MARK: Commands

    @MainActor
    private static func subtitle(for command: CommandID, model: AppModel) -> String? {
        switch command {
        case .toggleEnabled:
            return model.isEnabled ? "Tiling is on" : "Tiling is paused"
        case .undo:
            return model.recentActions.isEmpty ? nil : "Last: \(model.recentActions[0])"
        case .commandPalette, .cheatSheet:
            return nil
        default:
            return nil
        }
    }

    private static func keywords(for command: CommandID) -> [String] {
        switch command {
        case .focusLeft: ["left", "previous", "focus", "pane", "h"]
        case .focusRight: ["right", "next", "focus", "pane", "l"]
        case .focusUp: ["up", "above", "focus", "pane", "k"]
        case .focusDown: ["down", "below", "focus", "pane", "j"]

        case .moveLeft: ["left", "reorder", "shift", "move"]
        case .moveRight: ["right", "reorder", "shift", "move"]
        case .moveUp: ["up", "reorder", "shift", "move"]
        case .moveDown: ["down", "reorder", "shift", "move"]

        case .swapLeft: ["swap", "exchange", "left", "order"]
        case .swapRight: ["swap", "exchange", "right", "order"]
        case .swapUp: ["swap", "exchange", "up", "order"]
        case .swapDown: ["swap", "exchange", "down", "order"]

        case .grow: ["wider", "grow", "horizontal", "ratio", "split"]
        case .shrink: ["narrower", "shrink", "horizontal", "ratio", "split"]
        case .growHeight: ["taller", "grow", "vertical", "height"]
        case .shrinkHeight: ["shorter", "shrink", "vertical", "height"]

        case .layoutDwindle: ["dwindle", "bsp", "split", "tile", "layout"]
        case .layoutColumns: ["columns", "vertical", "layout", "split"]
        case .layoutRows: ["rows", "horizontal", "layout", "split"]
        case .layoutGrid: ["grid", "even", "layout", "square"]
        case .layoutMaster: ["master", "main", "stack", "layout"]
        case .layoutStack: ["stack", "accordion", "layout", "overlap"]
        case .cycleLayout: ["next", "layout", "cycle", "rotate"]

        case .toggleFloat: ["float", "free", "untile", "detach", "pin"]
        case .toggleFullscreen: ["fullscreen", "full screen", "maximise", "maximize"]
        case .focusMode: ["focus mode", "solo", "isolate", "zen", "single"]
        case .center: ["centre", "center", "middle", "place"]
        case .zoom: ["zoom", "maximise", "maximize", "fill", "expand"]

        case .nextSpace: ["space", "next", "desktop", "swipe"]
        case .previousSpace: ["space", "previous", "desktop", "swipe"]

        case .space1, .space2, .space3, .space4, .space5,
             .space6, .space7, .space8, .space9:
            ["space", "desktop", "go", "switch", "\(command.spaceNumber)"]

        case .moveToSpace1, .moveToSpace2, .moveToSpace3, .moveToSpace4, .moveToSpace5,
             .moveToSpace6, .moveToSpace7, .moveToSpace8, .moveToSpace9:
            ["space", "desktop", "send", "move", "window", "\(command.spaceNumber)"]

        case .nextDisplay: ["display", "monitor", "screen", "next"]
        case .previousDisplay: ["display", "monitor", "screen", "previous"]

        case .commandPalette: ["palette", "launcher", "search", "spotlight", "commands", "k"]
        case .cheatSheet: ["shortcuts", "keys", "help", "cheat sheet", "keyboard"]
        case .showApp: ["open", "settings", "preferences", "window", "app", "lattice"]
        case .toggleEnabled: ["pause", "resume", "disable", "enable", "stop", "tiling"]
        case .undo: ["undo", "revert", "back", "restore"]
        }
    }

    // MARK: Windows

    @MainActor
    private static func windowItems(model: AppModel) -> [PaletteItem] {
        let spaces = model.spaces

        var windows: [ManagedWindow] = []
        for list in model.windowsBySpace.values {
            windows.append(contentsOf: list)
        }

        let focusedSpace = model.focusedSpace
        windows.sort { lhs, rhs in
            if (lhs.space == focusedSpace) != (rhs.space == focusedSpace) {
                return lhs.space == focusedSpace
            }
            if lhs.appName != rhs.appName {
                return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return windows.map { window in
            let hasTitle = !window.title.isEmpty
            let title = hasTitle ? window.title : window.appName

            var subtitleParts: [String] = []
            if hasTitle { subtitleParts.append(window.appName) }
            if let entry = spaces.first(where: { $0.spaceIDs.contains(window.space) }),
               let index = entry.spaceIDs.firstIndex(of: window.space) {
                let display = model.displays.first { $0.id == entry.display }?.name
                let spaceName = "Space \(index + 1)"
                subtitleParts.append(display.map { "\($0) · \(spaceName)" } ?? spaceName)
            }
            if window.isFloating { subtitleParts.append("Floating") }
            if window.isFullscreen { subtitleParts.append("Full Screen") }

            return PaletteItem(
                id: "window.\(window.id.raw)",
                title: title,
                subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
                group: .windows,
                symbol: "macwindow",
                pid: window.pid,
                combo: nil,
                keywords: [window.appName, window.title, window.bundleID ?? ""],
                run: { [weak model] in
                    model?.engine.focus(window.id)
                }
            )
        }
    }
}
