# Lattice — build contract

Lattice is a native macOS window manager. One app, zero dependencies, no `brew install`,
no config file the user has to learn. It tiles windows on **real macOS Spaces**.

## Hard constraints

1. **SIP stays enabled.** No yabai scripting addition, no AeroSpace. The window layer is
   our own Accessibility (AX) engine in `LatticeKit`.
2. **Real Spaces only.** Never draw, emulate, or name a fake workspace. Spaces come from
   WindowServer (`SpaceManager`). Windows on inactive Spaces are never touched.
3. **Fully self-contained.** No Sparkle, no SPM dependencies, no helper installed outside
   the bundle, no network calls. `build/Lattice.app` must run on a clean Mac.
4. **SWIFT 5 LANGUAGE MODE.** `Package.swift` sets `.swiftLanguageMode(.v5)` on purpose.
   Do not change it. Do not add strict-concurrency refactors.
5. **Never edit another agent's files.** Extend shared types from a new file in your own
   directory (Swift extensions across files in the same module are fine).
6. **Build with your own scratch path** so parallel builds don't collide:
   `swift build --scratch-path .build-<yourid> -c debug`
   (`./scripts/bundle.sh` uses `.build` and is for the lead only.)

## Layout of the code

```
Sources/LatticeKit        core, no SwiftUI
  Geometry.swift          WindowID / SpaceID / DisplayID / ManagedWindow / DisplayInfo
  Spaces.swift            SpaceManager (SkyLight), KeySynth            [core agent]
  WindowEngine.swift      AX enumeration + frame control + observers   [core agent]
  Layout.swift            LayoutKind + pure layout maths                [lead]
  Settings.swift          Preferences, PreferencesStore, KeyCombo, CommandID [lead]
  Tiler.swift             tile order per Space, commands, SpaceBridge   [core agent]
Sources/Lattice           app + SwiftUI
  AppDelegate.swift       app lifecycle                                [lead]
  AppModel.swift          single source of truth for UI                [lead]
  UI/MainWindow.swift     window shell + sidebar                       [shell agent]
  UI/Chrome.swift         main menu, HotkeyCenter install stub         [lead]
  UI/StatusBar.swift      menu bar item                                [menubar agent]
  Hotkeys/                global shortcuts, drag snapping, overlays    [hotkey agent]
  UI/DesignSystem/        tokens + reusable components                 [shell agent]
  UI/Settings/            settings, shortcuts editor, apps rules       [settings agent]
  UI/Palette/             command palette, cheat sheet, HUD            [menubar agent]
Tests/LatticeKitTests     layout maths + model tests                   [qa agent]
```

## The contract you build against

```swift
AppModel.shared                       // ObservableObject, @MainActor
  engine: WindowEngine                // windows, focus, frames
  tiler: Tiler                        // order, layout, commands
  prefs: PreferencesStore             // .prefs, .update { }, .onChange
  @Published accessibilityGranted, windowsBySpace, displays, spaces,
             focusedSpace, focusedWindow, layout, isEnabled, recentActions
  func dispatch(_ command: CommandID) // every keyboard/menu action goes through here
  func refreshSpaces(), rebuildWindowCache(), setLayout(_:), setEnabled(_:)

Tiler
  func reconcile(animated: Bool = true)
  func tiledWindows(on: SpaceID) -> [WindowID]
  func focusedSpace() -> SpaceID
  func setLayout(_ kind: LayoutKind)
  var order: [SpaceID: [WindowID]], floating: Set<WindowID>

CommandID.allCases                    // metadata: title, category, symbol, spaceNumber
Preferences.bindings: [CommandID: KeyCombo]   // user-editable shortcuts
KeyCombo(key:modifiers:).display      // "⌃⌥H"
```

Notifications already posted by `AppModel.dispatch`:
`.latticeShowPalette`, `.latticeShowCheatSheet`, `.latticeShowMainWindow`.

## What "Apple native" means here, concretely

- **Type.** SF Pro via `.font(.system(...))` only. Body 13, callout 12, caption 11,
  large title 26–28 semibold, section headers 11 semibold uppercase + tracking .6,
  secondary. No web fonts, no custom families, no all-caps body copy.
- **Material.** `NSVisualEffectView`/`.background(.regularMaterial)` for chrome,
  `Color(nsColor: .windowBackgroundColor)` for content, 1px `Color(nsColor: .separatorColor)`
  hairlines drawn at 1/backingScale.
- **Colour.** Semantic only: `.primary`, `.secondary`, `.tertiary`, `.tint`, `.quaternary`.
  One signature accent: `Color.accentColor` for controls; the user's system accent is
  respected. No neon, no purple gradients on buttons.
- **Shape.** Corner radii 6 / 10 / 14 / 18. Materials get 10. Cards get 14. Never mix
  radii inside one row.
- **Spacing.** 4-pt grid, 8/12/16/24. Content gutter 20. Row height 32 (compact) / 44 (list).
- **Motion.** Springs only: `.spring(response: 0.34, dampingFraction: 0.86)`. Nothing
  linear, nothing over 400 ms, nothing bouncing more than once. Respect
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- **Controls.** Real AppKit-backed SwiftUI controls. `Toggle(.switch)`, `Picker(.segmented)`,
  `.formStyle(.grouped)`, `Table` for lists, `Section` footers for help text. No custom
  fake checkboxes, no HTML-looking pills.
- **Windows.** Unified toolbar, `NSWindow` autosave, `.windowResizability(.contentSize)`
  for small utility windows, sidebar 200–240 pt.
- **Empty states and permission states are designed**, not `Text("No data")`.

## The bar to clear

Shoji (shojimac.com) is the reference competitor: auto-tiling, four layouts, stacks,
focus mode, menu-bar control, settings window, per-app exclusions, real Spaces,
localised, notarised, 6 MB.

We beat it on: keyboard-first control (a real command palette + recordable bindings with
conflict detection), live layout previews, per-Space layout memory, multi-display aware
tiling, undo, drag-to-swap, a cheat sheet, and a menu-bar surface that shows the actual
tiles instead of a list of words. We do not beat it on localisation in this pass.

## Build + run

```
swift build -c debug                       # compile only
./scripts/bundle.sh debug && open build/Lattice.app
pkill -f "Lattice.app/Contents/MacOS/Lattice"; tccutil reset Accessibility com.shashvat.lattice
tail -f ~/Library/Logs/Lattice/lattice.log
```

First launch needs Accessibility approval (System Settings ▸ Privacy & Security ▸
Accessibility). Until it is granted, all tiling is inert by design.

## Cross-subsystem API contract (do not change without telling the lead)

Created by the menu-bar/HUD agent in `Sources/Lattice/UI/HUD/`, consumed by the hotkey agent:

```swift
@MainActor public final class HUDController {
    public static let shared: HUDController
    public func start()                                   // call once from AppDelegate
    public func showToast(_ text: String, symbol: String? = nil)   // transient capsule, 1.1 s
    public func showSnapPreview(rect: CGRect, label: String? = nil) // CG-global rect, animated in
    public func hideSnapPreview(animated: Bool = true)
}
```

- `rect` is in global Core Graphics coordinates (top-left origin, same space as
  `DisplayInfo.frame`). The HUD flips it internally for AppKit windows.
- The preview window must be a non-activating, click-through `NSPanel`
  (`.borderless, .nonactivatingPanel`, `ignoresMouseEvents = true`, level `.screenSaver`,
  `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`) so it can
  never steal focus or a click.
- Must render correctly at 60 fps while the pointer moves, and must not animate when
  `accessibilityDisplayShouldReduceMotion` is true.
