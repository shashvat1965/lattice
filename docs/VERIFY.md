# Verifying Lattice on a real Mac

Everything here is a thing I could not prove from inside the build sandbox, ordered so a
failure is cheap to attribute.

## 0. Grant Accessibility (once, ever)

Run `./scripts/make-signing-identity.sh` first. On a new Mac it prints one
`add-trusted-cert` command; run it, then `./scripts/bundle.sh release`. The signature is
now stable, so the Accessibility grant below survives future rebuilds — that is the whole
point of the identity.

`./scripts/bundle.sh release` signs with your Apple Development certificate when one is
installed (designated requirement `identifier "com.shashvat.lattice" and anchor apple
generic and certificate leaf[CN] = "Apple Development: …"`), and otherwise with the local
"Lattice Dev Signing" identity (`identifier … and certificate root = H"…"`).

1. Launch `build/Lattice.app`.
2. Onboarding ▸ Permission ▸ **Request Access**, or System Settings ▸ Privacy & Security ▸
   Accessibility ▸ **Lattice**.
3. The banner flips to a green "granted" state within a second (the app polls TCC).
4. `./scripts/selftest.sh` should now print `accessibilityTrusted: true` and a window list.

## 1. Enumeration

```
./scripts/selftest.sh
```

Expect: one entry per standard window on the **current** Space, correct app names, and
`space` values that match what Mission Control shows. Windows on other Spaces must appear
with *their* Space, and must not be written during reconcile.

Failure to look for: every window reporting the same Space (the old bug), or no windows at
all while apps are visibly open (AX trust, or an app with `activationPolicy != .regular`).

## 2. Tiling

1. Open three apps on one Space.
2. They should tile immediately, 8 pt gaps, no window under the menu bar or Dock.
3. ⌃⌥⌘1–4 should re-layout the Space; the windows animate, not jump.
4. Switch to another Space and back: the layout and proportions must be remembered per
   Space, and the other Space's windows must be untouched.
5. Open more windows than the display can hold at their minimum sizes. The Space must not
   be rearranged into overlapping columns: Overview shows **Space full** and the windows
   stay exactly where they were. Close one and tiling resumes.
6. Settings ▸ Window border ▸ on. The focused window gets a ring in the chosen colour,
   and it follows focus without covering the window's own controls.

## 3. Snap preview

Drag any window toward the left edge. A rounded accent rectangle with a label
("Left Half") must appear and the window must land exactly inside it. Esc-free: releasing
outside a zone must cancel with no movement.

## 4. Cross-Space move

Focus a window, press ⌃⌥⌘2. The log should show either `windowServer` (own-process window)
or `nativeDrag` for a third-party app, followed by a Space change if
*Spaces ▸ Follow window* is on. If the window did not move, check the log for
`refused` — the native drag needs Accessibility to post HID events.

## 5. Shortcuts

Press ⌃⌥⌘K (palette) and ⌃⌥⌘/ (cheat sheet). Both must open over a full-screen app without
stealing the Space. In the palette, exactly one row is highlighted; type `columns` and
press Return — the layout changes and the palette closes. Rebind one chord in Settings ▸
Shortcuts and confirm the old chord stops working and the new one starts.

## 6. Undo and pause

⌃⌥⌘P pauses tiling (menu bar glyph gets a slash). Moving windows while paused must not
trigger retiling. Resuming re-tiles the current Space.

## 7. Performance

Leave Lattice running for an hour with a few windows. Idle CPU should sit at ~0% and
memory under ~80 MB. `Activity Monitor ▸ Lattice`. There are no polling timers outside
the permission watcher, which stops once access is granted.

## Known limits (by design, not bugs)

- Creating or deleting a Space stays in Mission Control: it needs SIP off, and we refuse to
  pretend otherwise. The app opens Mission Control and adopts the new Space when it appears.
- Moving *another app's* window across Spaces uses the native drag path. WindowServer's own
  call silently refuses cross-process moves with SIP on.
- Window opacity and always-on-top are not offered: both need private paths that break
  across releases.
