# Verifying Lattice on a real Mac

Everything here is a thing I could not prove from inside the build sandbox, ordered so a
failure is cheap to attribute.

## 0. Grant Accessibility (once, ever)

`./scripts/bundle.sh release` signs with your Apple Development certificate, so the
designated requirement is

```
identifier "com.shashvat.lattice" and anchor apple generic and certificate leaf[CN] = "Apple Development: …"
```

That is stable across rebuilds — unlike ad-hoc signing, which macOS pins to a binary hash
and therefore forgets on every build. Grant once:

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
stealing the Space. Rebind one chord in Settings ▸ Shortcuts and confirm the old chord
stops working and the new one starts.

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
