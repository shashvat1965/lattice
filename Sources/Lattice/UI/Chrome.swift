import AppKit
import LatticeKit

// Global hotkeys and drag-to-snap live in Sources/Lattice/Hotkeys/.

@MainActor
final class MenuCommandTarget: NSObject {
    static let shared = MenuCommandTarget()
    weak var model: AppModel?

    @objc func run(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let command = CommandID(rawValue: raw) else { return }
        (model ?? AppModel.shared).dispatch(command)
    }

    @objc func showSettings() {
        NotificationCenter.default.post(name: .latticeShowMainWindow, object: nil)
    }

    @objc func showSpaces() {
        NotificationCenter.default.post(name: .latticeShowSpaces, object: nil)
    }

    @objc func openLogs() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Lattice", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

enum MainMenuBuilder {
    static func build() -> NSMenu {
        let target = MenuCommandTarget.shared
        let mainMenu = NSMenu()

        // MARK: App
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Lattice")
        appMenu.addItem(withTitle: "About Lattice",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Open Lattice…", .showApp, target, "0"))
        appMenu.addItem(item("Command Palette…", .commandPalette, target, ","))
        appMenu.addItem(item("All Shortcuts", .cheatSheet, target, "/"))
        let spacesItem = NSMenuItem(title: "Spaces…", action: #selector(MenuCommandTarget.showSpaces), keyEquivalent: "1")
        spacesItem.keyEquivalentModifierMask = [.command, .shift]
        spacesItem.target = target
        appMenu.addItem(spacesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(item("Pause Tiling", .toggleEnabled, target, "p"))
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(MenuCommandTarget.showSettings), keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Lattice", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Lattice", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // MARK: Edit
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // MARK: Layout
        let layoutItem = NSMenuItem()
        mainMenu.addItem(layoutItem)
        let layoutMenu = NSMenu(title: "Layout")
        layoutMenu.addItem(item("Dwindle", .layoutDwindle, target, "1"))
        layoutMenu.addItem(item("Columns", .layoutColumns, target, "2"))
        layoutMenu.addItem(item("Rows", .layoutRows, target, "3"))
        layoutMenu.addItem(item("Grid", .layoutGrid, target, "4"))
        layoutMenu.addItem(item("Master", .layoutMaster, target, ""))
        layoutMenu.addItem(item("Stack", .layoutStack, target, ""))
        layoutMenu.addItem(.separator())
        layoutMenu.addItem(item("Next Layout", .cycleLayout, target, " "))
        layoutMenu.addItem(.separator())
        layoutMenu.addItem(item("Focus Mode", .focusMode, target, "z"))
        layoutItem.submenu = layoutMenu

        // MARK: Space
        let spaceItem = NSMenuItem()
        mainMenu.addItem(spaceItem)
        let spaceMenu = NSMenu(title: "Space")
        spaceMenu.addItem(item("Next Space", .nextSpace, target, "]"))
        spaceMenu.addItem(item("Previous Space", .previousSpace, target, "["))
        spaceMenu.addItem(.separator())
        for number in 1...9 {
            guard let command = CommandID(rawValue: "space\(number)") else { continue }
            spaceMenu.addItem(item("Go to Space \(number)", command, target, "\(number)"))
        }
        spaceItem.submenu = spaceMenu

        // MARK: Window
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Float Window", .toggleFloat, target, "f"))
        windowMenu.addItem(item("Full Screen", .toggleFullscreen, target, "f"))
        windowMenu.addItem(item("Centre", .center, target, "c"))
        windowMenu.addItem(item("Zoom", .zoom, target, ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        // MARK: Help
        let helpItem = NSMenuItem()
        mainMenu.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(item("All Shortcuts", .cheatSheet, target, "/"))
        let logs = NSMenuItem(title: "Open Logs", action: #selector(MenuCommandTarget.openLogs), keyEquivalent: "")
        logs.target = target
        helpMenu.addItem(logs)
        helpItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    private static func item(_ title: String, _ command: CommandID, _ target: MenuCommandTarget, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuCommandTarget.run(_:)), keyEquivalent: key)
        item.target = target
        item.representedObject = command.rawValue
        return item
    }
}
