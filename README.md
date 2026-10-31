# Lattice

A native window manager for macOS. Every window in its place — on the Spaces you
already use.

No config file. No `brew install`. No emulated workspaces. One 6 MB app that you drag
to Applications and forget about, because it just works the way macOS works.

<img src="docs/hero.png" width="880" alt="Lattice">

## What it does

**Tiles automatically.** Open a window and it gets a place. Close one and the rest
reflow. Nothing to arrange by hand.

**Uses your real Spaces.** Lattice reads the Space list straight from WindowServer.
Switching Spaces is the system switching Spaces — the same animation, the same
Mission Control, the same thumbnails. Windows on a Space you're not looking at are
never moved. There is no second, parallel idea of a workspace anywhere in the app.

**Six layouts, remembered per Space.** Dwindle, Columns, Rows, Grid, Master, Stack.
Each Space keeps its own layout and its own proportions.

**Keyboard first, mouse welcome.** Arrow/HJKL focus and move, drag a window to a screen
edge to snap it into the exact rectangle shown by the preview, ⌘-drag one window onto
another to trade places.

**A command palette, not a settings hunt.** ⌃⌥⌘K runs anything: layouts, Space moves,
window actions, or jump straight to a window by name.

**Every shortcut is yours.** Record any chord, see conflicts as you type, and hold
⌃⌥⌘/ to see the whole keyboard on screen.

## Install

```
./scripts/make-icon.swift      # (optional) regenerate the app icon
./scripts/bundle.sh release
open build/Lattice.app
```

Drag `build/Lattice.app` into `/Applications`. First launch asks for Accessibility —
that permission is what lets any window manager move windows; Lattice reads window
frames and titles only, never window contents, and it has no network code.

## How it works

```
LatticeKit      Accessibility engine, Space introspection, layout maths
   WindowEngine    window discovery, frame writes, animation, notifications
   SpaceManager    real Spaces from WindowServer (SkyLight), native switching
   Tiler           per-Space tile order, commands, undo
   LayoutMath      pure functions: (count, rect, gap) -> [CGRect]
Lattice         SwiftUI app
   Overview        live map of your display, one tile per window
   Palette         fuzzy command runner
   HUD             snap preview and toasts
   Hotkeys         Carbon global shortcuts, drag-to-snap event tap
```

SIP stays enabled. Lattice never installs a helper, never asks you to disable
System Integrity Protection, and never replaces a system component.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌥ H J K L | Focus left / down / up / right |
| ⇧⌥ H J K L | Move the window through the tile order |
| ⌥ ← → ↑ ↓ | Also move the window (alternate chords) |
| ⌥ 1–9 | Jump to a Space |
| ⇧⌥ 1–9 | Send the focused window to that Space |
| ⌃⌥ ← → | Previous / next Space |
| ⌥⌘ 1–6 | Dwindle · Columns · Rows · Grid · Master · Stack |
| ⌥ Space | Next layout |
| ⌥ F | Float / tile |
| ⇧⌥ F | macOS full screen |
| ⇧⌥ Z | Focus mode |
| ⌥ C | Centre |
| ⌥ ↩ | Zoom |
| ⌃⌥⌘ K | Command palette |
| ⌃⌥⌘ / | Every shortcut on screen |
| ⌃⌥⌘ P | Pause tiling |

Space keys are a real mapping: any key can point at any Space (⌥A for Space 3 is fine), and
you can add a second chord to any command. All of it lives in Settings ▸ Shortcuts.

Every one of them is rebindable in Settings ▸ Shortcuts, with live conflict detection.

## Notes

- Requires macOS 15 or later, Apple silicon or Intel.
- Windows that refuse to be resized (a few Java and Electron apps) are detected and
  left alone rather than fought with.
- Logs live in `~/Library/Logs/Lattice/lattice.log`.
