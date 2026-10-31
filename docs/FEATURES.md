# Feature coverage vs yabai and AeroSpace

Everything below must be reachable from **Settings** (or the menu bar), in plain language,
with no config file. "Exposed" means a real control bound to a real engine behaviour —
not a stored preference nobody reads.

## Layout

| Capability | yabai | AeroSpace | Lattice |
|---|---|---|---|
| Automatic tiling | bsp | tree | dwindle (bsp-like) ✓ |
| Stack / accordion | stack | accordion | stack with configurable peek ✓ |
| Columns / rows | — | tree orientation | ✓ explicit layouts |
| Grid | grid command | — | ✓ with optional fixed column count |
| Master + stack | — | — | ✓ with adjustable master ratio |
| Master ratio / split weights | resize | resize | ✓ weight per Space, persisted |
| Swap two windows | swap | move | ✓ ⌃⌥⌘arrows, ⌘-drag |
| Move a window within the tree | move | move | ✓ ⌃⌥⇧arrows |
| Insertion point for new windows | external_app_launch_action | root container | ✓ end / after focused / master |
| Auto-balance after close | balance | automatic | ✓ automatic, plus manual reset |
| Float a window | float | toggle-float | ✓ ⌃⌥F |
| Un-manage an app entirely | manage=off rule | — | ✓ Apps pane "Leave alone" |
| Focus mode / zoom one window | zoom-fullscreen | fullscreen | ✓ ⌃⌥⌘Z |
| Zoom parent / zoom-fullscreen | ✓ | ✓ | ✓ zoom (⌃⌥↩) |
| Native macOS full screen | native-fullscreen | macos-fullscreen | ✓ ⌃⌥⌘F |
| Centre / arbitrary placement | custom grid/position | — | ✓ centre, plus drag-to-rect |

## Gaps and padding

| Capability | yabai | AeroSpace | Lattice |
|---|---|---|---|
| Inner gap between windows | window_gap | inner gaps | ✓ 0–32 pt slider |
| Outer gap to screen edge | padding | outer gaps | ✓ 0–64 pt slider |
| Per-edge padding | top/bottom/left/right | — | ✓ advanced disclosure |
| Respect the menu bar | automatic | automatic | ✓ always |
| Respect a visible Dock | via padding | automatic | ✓ toggle |
| Notch-aware | — | — | ✓ uses `safeAreaInsets` |
| Per-display gap override | — | per-monitor config | ✓ Displays section |

## Windows

| Capability | yabai | AeroSpace | Lattice |
|---|---|---|---|
| Focused-window border | border | — | ✓ width, colour, opacity, focused-only |
| Window opacity | opacity | — | not exposed (would need a private camera path; skipped deliberately) |
| Shadows | shadow | — | follows the system setting, never overridden |
| Sticky window | sticky | — | ✓ stays on the current Space while you switch |
| Topmost / pin above others | topmost | — | not exposed |
| Minimise / restore | ✓ | ✓ | ✓ |
| Close window | ✓ | ✓ | ✓ via palette |
| Warp cursor to focused window | warp | — | ✓ toggle |
| Focus follows mouse | mff | focus-follows-mouse | ✓ toggle, pointer poll (no event tap, no warp) |
| Modifier-drag to move / resize | ✓ | — | ✓ drag-to-snap, ⌥-drag free move |
| ⌘-drag to swap | — | — | ✓ |

## App rules

| Capability | yabai | AeroSpace | Lattice |
|---|---|---|---|
| Per-app float | ✓ | on-window-detected | ✓ |
| Per-app "leave alone" | manage=off | — | ✓ |
| Per-app layout override | label/grid | run: layout | ✓ |
| Per-app Space assignment | rule → space | run: move-node-to-workspace | ✓ (send to Space N on appearance) |
| Min size exemption | min/max size | — | ✓ automatic + adjustable |
| Title-based rules | regex | regex | title contains match ✓ |

## Spaces and displays

| Capability | yabai | AeroSpace | Lattice |
|---|---|---|---|
| Real macOS Spaces | needs scripting addition (SIP off) | no (own workspaces) | ✓ by design |
| Per-Space layout | — | per-workspace | ✓ |
| Switch Space | ✓ | ✓ (virtual) | ✓ native switch |
| Move window to Space | ✓ | ✓ | ✓ with native fallback |
| Move window to next display | ✓ | ✓ | ✓ |
| Follow window when moved | — | — | ✓ toggle |
| Space switch animation | system | instant | system's own |
| Create / destroy Spaces | ✓ (SIP off) | — | not supported — that is Mission Control's job, and we do not pretend otherwise |

## Keyboard

| Capability | yabai (skhd) | AeroSpace | Lattice |
|---|---|---|---|
| Every action rebindable | ✓ config file | ✓ config file | ✓ recorder UI |
| Conflict detection | — | — | ✓ including known system chords |
| Per-layout chords | — | workspaces 1–9 | ✓ |
| Keyboard-layout aware keys | — | ✓ | ✓ (UCKeyTranslate) |
| Cheat sheet overlay | — | — | ✓ ⌃⌥⌘/ |
| Command palette | — | — | ✓ ⌃⌥⌘K |

## Motion

| Behaviour | Lattice |
|---|---|
| Tiling retile tween | 60 fps interpolation, cubic ease-out by default |
| Curve choice | ease-out, ease-in-out, spring (settings) |
| Duration | 0 – 400 ms, default 180 ms |
| Reduce Motion | forces instant, no exceptions |
| During a user drag | tiling never animates a window under the pointer |
| Snap preview | spring scale + fade, follows the pointer at 60 fps |
| Curve | ease-out (cubic), ease-in-out (smoothstep), or a damped spring (0.34 / 0.86), sampled per frame |
| Palette / cheat sheet | single spring, ≤ 260 ms, no bounce |
| Toast | spring in, 1.1 s hold, fade out |
