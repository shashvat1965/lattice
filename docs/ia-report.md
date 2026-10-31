# Lattice — information architecture

Research report. Question: what should the sections be, in what order, and what belongs in each.
Verdict first, evidence second.

**Verdict: four rows, one editor per object, actions anywhere.**
`Overview · Layouts · Shortcuts · Settings`. Delete the Spaces, Apps and About pages, dissolve the ten-section Settings page into seven six-row sections, and stop writing a subtitle under every row.

---

## Field notes: how the comparables actually build it

Counts marked ✓ were read from shipping source (September 2026), not from marketing pages.

| App | Top-level sections | Where settings live | Structure notes |
|---|---|---|---|
| **Rectangle** ✓ | **4** — Shortcuts, Snap Areas, Behavior, App Settings | Separate window, `NSTabViewController` with `.toolbar` style, min 500×350 | No sidebar. Opens **on Shortcuts**, not General. Remembers a different window size per tab. |
| **Ice** ✓ | **6** — General, Menu Bar Layout, Menu Bar Appearance, Hotkeys, Advanced, About | Separate window, `NavigationSplitView` sidebar 190–230 pt | One section header ("Ice", 36 pt). Icons per row. `Menu Bar Layout` is a live drag-and-drop editor *inside* settings. |
| **Loop** ✓ | **10**, in **3 labelled groups** (Theming: Icon, Accent Color, Radial Menu, Preview · Settings: Behavior, Keybinds, Gestures · Loop: Advanced, Excluded Apps, About) | Separate window, 230 pt sidebar + 390 pt pane + optional inspector | Inspector shows the radial menu / preview live while you drag. `Excluded Apps` is its own tab, not a row inside Advanced. |
| **Amethyst** ✓ | **6** — General, Layouts, Shortcuts, Mouse, Floating, Debug | Separate window, toolbar-style tabs | Ships a `Debug` tab in the release build. Shortcuts is one giant table. |
| **Stats** ✓ | Sidebar: **Dashboard** + one row per module; module on/off lives in the pane's **toolbar** | 720×480 window, 180 pt sidebar, `NSSplitViewController` | Each module ships its own `settings.swift`; the pane is the module. Preview button in the toolbar. |
| **Raycast** ✓ | **12** — Account, General, Appearance, Launcher, Shortcuts, Keyboard, Advanced, Organizations, About, AI, Applications, Extensions | Separate window, sidebar | Pays for its breadth with **⌘F settings search** and deep links: "Configure Command" from the Action Panel lands on the exact row. Shortcuts pane is a bird's-eye list across *all* extensions. |
| **iStat Menus** | One pane per menu-bar module (~8); each module has its own menu bar item and dropdown | Separate prefs window | One surface per module; the menu bar dropdown carries the module's data, never its configuration. |
| **Bartender** | Small settings window + arrangement | Arrangement is edited **where the arrangement is** (drag in the menu bar) | Never rebuilds the object you're already looking at inside a form. |
| **Moom** | Tabbed prefs; up to 61 custom actions in a nested folder tree | Separate prefs window + popover palette on the green button | The palette *is* the product surface; prefs are a folder manager. |
| **One Switch / Amphetamine / HazeOver** | 1 popover (tiles / session controls / intensity) + a small tabbed settings window | Popover acts; window configures | No text settings in the popover. |
| **BetterTouchTool** | ~10 vertical entries, everything reachable in one tree | One window | The cautionary case: all density, no hierarchy. |
| **AeroSpace / yabai** | **0** | TOML / YAML only; AeroSpace's tray icon just prints the active workspace name | Proof that a WM GUI is optional — so every screen Lattice ships has to justify itself. |
| **Apple System Settings** | ~30 sidebar panes, grouped, searchable | One level deep; "Advanced…" pushes a sheet | No "Advanced" catch-all pane. One footer line per group, never one per row. |
| **Shortcuts / Passwords / Reminders / Notes** | Sidebar = **object lists** (folders, categories, lists) | `⌘,` opens a small window with 3–5 tabs | User-created objects live in the sidebar; app behaviour lives in a separate window. |
| **1Password / Things / Fantastical** | Sidebar = vaults / lists / calendars | Separate `⌘,` window with a flat tab list | The thing you *navigate* is never the thing you *configure*, and vice versa. |

Rectangle is the closest comparable — a window manager whose only UI is a settings window — and it ships **four** top-level sections for 20+ window actions. Lattice currently exposes **17 destinations** (7 sidebar rows, 10 Settings sections, minus the four duplicated).

---

## 1. Patterns observed

1. **Settings is a window, not a row.** Every app in the list that has a main navigation (Ice, Loop, Rectangle, Amethyst, Stats, Raycast, Things, Fantastical, 1Password) opens configuration with `⌘,` into separate chrome. Lattice makes Settings, Shortcuts, Apps and About *peer rows* of the live overview — the only app here that does.
2. **The pane count is 4–6; breadth is paid for with search, not with more panes.** Rectangle 4, Ice 6, Amethyst 6, median 6. Raycast's 12 is the outlier and it buys ⌘F plus deep links from the action you were already using.
3. **Sections group by the user's noun, not the implementation.** Loop labels its groups *Theming / Settings / Loop*. Rectangle's four tabs are *the four things you might be thinking about* (keys, snap zones, behaviour, per-app). Lattice groups by implementation: Gaps, Borders, Input, Displays, Motion.
4. **An object gets exactly one editor, and it is the object's own page.** Ice's menu bar layout is edited in `Menu Bar Layout`, not in `Appearance`. Loop's excluded apps are a tab, not a row under Advanced. System Settings has no second Wi-Fi pane. Lattice edits Layouts in two places and Spaces in two places.
5. **The menu bar popover acts; it does not configure.** One Switch is a grid of toggles, Amphetamine is a session control, iStat's module menus are readouts, Rectangle's is a flat action list. None of them contains a form, a slider with a preview, or a list you can edit.
6. **State is mirrored freely; settings are not.** Every app shows "on/off" in the popover, the menu, and the window. None of them lets you *set* the same preference in two places. This is the distinction Lattice is missing.
7. **Preview lives beside the control, inside the same pane.** Loop's inspector renders the radial menu while you drag its controls; Stats puts a preview button in the pane's toolbar; Lattice's own Gaps section has a live four-window preview — the single best thing in the current Settings page. It is also the only section that gets it.
8. **Tuning follows the selection.** Stats: pick a module in the sidebar, its on/off switch appears in that pane's toolbar. Loop: pick Radial Menu, its editor and guide appear. Lattice's Master ratio, Stack peek and Grid columns are three orphan sliders in a "Layouts" section, 400 pt below the layout chips they modify.
9. **Advanced is a small, real, last page — never a dump.** Ice `Advanced`, Amethyst `Debug`, Rectangle `Behavior`. Each holds 3–6 genuinely dangerous or diagnostic rows.
10. **Settings copy is a label plus a control.** Ice's General pane is six groups of bare toggles and pickers with no row-level prose. System Settings writes one footer sentence per *group*. Lattice writes a 15–25 word subtitle under every one of its ~55 rows (~1,100 words of documentation inside a settings page).
11. **First run asks one question or one permission, once, in a small window.** Rectangle's entire welcome is a 380 pt modal: headline, one sentence, two buttons (`Recommended` / `Spectacle`), two caption lines of consequences, `wasWelcomeDisplayed` set before the window is shown. Ice shows a dedicated non-closable permissions window with a real escape hatch: **"Continue in Limited Mode."**
12. **Rare configuration is reached by deep link, not by browsing.** Raycast's `Configure Command` from the Action Panel lands on the exact settings row. Lattice has no equivalent: "this app should float" requires knowing it lives under a sidebar row called *Apps*.
13. **No GUI is a defensible answer.** AeroSpace ships a tray icon that prints a workspace name. A window manager's GUI earns nothing by existing; it earns by showing what the keys can't — the live map, the geometry, the conflicts.

---

## 2. Anti-patterns in the current Lattice build

| Anti-pattern | Where it is now | The app that proves otherwise |
|---|---|---|
| **Two navigation trees describing the same objects.** Sidebar has Layouts and Spaces; Settings has a Layouts section and a Spaces section. Same nouns, two editors, different controls in each. | `MainWindow.sidebarPrimary`, `SettingsPane` sections 3 and 7 | Rectangle: one tree, four leaves; "App Settings" is the only home for per-app config. |
| **Settings as a peer row of live content.** Settings/Shortcuts/Apps/About sit next to the map as if they were pages of the same kind. | Sidebar, 6 rows + About in the footer | Ice, Loop, Stats, Rectangle, Raycast all use `⌘,` chrome. |
| **A ten-section scroll with no search and no sub-navigation.** The user's only tool is scrolling. | `SettingsPane` | Ice splits into 6 panes; Raycast adds ⌘F; System Settings adds search over 30. |
| **Documentation-grade copy.** ~55 rows × 1–2 sentence subtitles, plus section subtitles plus footnotes — three layers of prose per screen. | Every `Settings*Section` | Ice `GeneralSettingsPane`: 6 groups, zero row subtitles. Apple: one footer per group. |
| **The master switch is plumbed four times.** Sidebar footer toggle, toolbar pause button, Settings›Tiling "Tile windows automatically", menu bar panel badge. | `MainWindow.sidebarFooter`, `toolbarContent`, `TilingSettingsSection` | Rectangle has one toggle in one place. |
| **Overview restates the popover.** Window list, layout buttons, "Latest" actions, permission card — the popover already does all of it at 360 pt. | `Overview.swift` + `MenuBarPanel.swift` | iStat/Bartender: the window shows what the popover structurally cannot. |
| **Tuning divorced from its subject.** Master ratio / Stack peek / Grid columns live a screen away from the layout they change. | `LayoutTuningSettingsSection` | Stats: the module's controls are in the module's pane. Loop: an inspector beside the control. |
| **`About` as a destination.** A sidebar-row-sized amount of information that belongs in the app menu. | `MainTab.about` | Rectangle: About lives in the popover and app menu; Ice makes it the last settings pane, not a nav row. |
| **Welcome as a place.** `.welcome` is a `MainTab` that resolves to `.overview`; onboarding is a 3-step flow with a "Step 1 of 3" counter. | `MainTab.welcome`, `OnboardingFlow` | Rectangle: one modal, no steps, no counter, never seen again. |
| **Permission as content.** A dismissible card inside Overview, a "Grant Access" button in the Settings header, a warning row in the popover, and step 2 of onboarding. | `Overview`, `SettingsPane.paneHeader`, `MenuBarPanel`, `Onboarding` | Ice: one window, one checklist, one explicit degraded mode. |
| **Dead controls.** `enterFullScreenDelay`, `accentOverride`, `snapPreviewStyle` are stored in `Preferences` and surfaced nowhere. | `LatticeKit/Settings.swift` | — |

---

## 3. Recommended structure

### The three rules

1. **Actions can be invoked from anywhere. Editors exist once. State may be displayed anywhere.**
2. **A row earns a permanent sidebar slot if it has more than ~25 editable rows or is used daily.** Shortcuts (65 bindings) qualifies. Apps (4 rules, edited twice a year) does not.
3. **Nothing appears twice.** If a control describes an object that has a page, it lives on that page. Full stop.

### Sidebar (4)

| # | Row | One-sentence purpose |
|---|---|---|
| 1 | **Overview** | Your desk, live: every display, every Space, every window, with the current Space's layout one click away. |
| 2 | **Layouts** | The six arrangements, their geometry, and how much air sits between windows. |
| 3 | **Shortcuts** | Every chord in the app, one editor, conflict-checked. |
| 4 | **Settings** | The seven things that have no other home. |

Order is *see → shape → drive → configure*: content first, configuration last. No section headers in a four-row sidebar (headers need ≥3 rows per group to pay for themselves; Lattice would have 3 + 1).

`About` leaves the nav: version stays in the sidebar footer (already there, well done), credits/website go to the app menu, diagnostics go to Settings›Advanced.

### 1 · Overview — *"What is on my screen right now."*

Merges today's `Overview` + `Spaces` + `Settings›Spaces`.

- **Header:** "Overview" + one right-aligned line of live state — `3 displays · 8 Spaces · 14 windows`. No stat cards.
- **Space strip, per display:** a row of Space chips, each showing `Space 2`, its layout glyph, its key (`⌥2`), and window count. Selected chip = the Space being shown. Drag a window tile onto a chip to send it there. Clicking the glyph opens the layout popover for *that Space* — this is the only per-Space layout editor.
- **The map:** one card per display, tiles drawn at true relative geometry, labelled with app icon + window title, focused tile accented. This is the one thing a 360 pt popover cannot do, which is why it justifies a window.
- **Row context menu on a tile:** Focus · Float · Send to Space ▸ · **Don't tile this app…** (opens `Settings›Apps` with the bundle ID pre-filled) · Move to display ▸.
- **One toggle in the header:** *Follow a window to its Space* (moved out of Settings). It changes what the map does, so it lives on the map.
- **Empty/blocked state:** permission missing → the map is replaced by a designed state with one primary button, not a card layered on top of a working page.

Deleted from the old Overview: "Latest" recent-actions list (the HUD already toasts, and the log has it), the display stat cards, the permission explainer card, the duplicated window list.

### 2 · Layouts — *"How windows get arranged."*

Merges today's `Layouts` gallery + `Settings›Layouts` + `Settings›Gaps & padding` + the min-size and insertion rows from `Settings›Tiling`.

- **Selector row:** the six layouts as live thumbnails rendered from the *current* Space's real window count, not abstract diagrams. Clicking one sets the current Space's layout; a segmented control above says `This Space` / `All Spaces` so the scope is never ambiguous.
- **Per-layout tuning, inline:** the selected card expands in place with only its own controls — Master → *Master share*; Stack → *Stack peek*; Grid → *Columns*; Dwindle/Columns/Rows → nothing. This deletes the orphan "Layouts" settings section and puts each slider 20 pt from the thing it changes.
- **Space:** *Gap between windows*, *Gap to screen edge*, with the existing live four-window preview beside them. Keep the preview — it is the best control in the app.
- **Per-edge padding:** a disclosure row that expands to the four sliders + *Clear*. Collapsed by default, with a one-line summary when set (`Top 24 · Leading 12 pt`).
- **Limits:** *Smallest tile width / height*.
- **When a window opens:** *Insertion policy*, *Rebalance after a window closes*.
- **Footer:** `Each Space remembers its own layout. Change one in Overview.`

`respectMenuBar` / `respectDock` do **not** belong here — they describe the screen, not the layout. They move to Settings›Displays.

### 3 · Shortcuts — *"What every key does."*

Keeps today's `ShortcutsPane` almost intact — search, category filter, live conflict detection, alternate chords, and the Space-key editor are already the strongest screen in the app (Raycast only rebuilt its recorder with conflict detection and overwrite *this year*; Lattice has it).

Changes:
- Add a **flat "essentials" strip** at the top: the 8 chords shown in the cheat sheet, so a new user sees the working set before the 56-command list.
- One row at the bottom of the list: `Space keys — 9 assigned · edited here` (they stay here; the Overview chips only *display* them).
- Footer link: `Hold ⌃⌥⌘/ to see these on screen` (cheat sheet stays an overlay — it is not a page).
- No settings of any kind. No "reset to defaults" buried elsewhere: the reset button lives at the bottom of this page, scoped to shortcuts.

### 4 · Settings — *"The rest."*

One scroll, **seven sections, ≤6 rows each, no duplicated object**. Ordered by how often they get opened. Section = one `Section` header + rows; prose only where a consequence is genuinely non-obvious, ≤12 words, one per group where possible.

| Section | Rows |
|---|---|
| **General** | Launch at login (default **on**) · Show menu bar icon · Run setup again · Version (read-only footer with About… in the app menu) |
| **Displays** | Keep windows below the menu bar *(global)* · Display list: name, resolution, Space count · per display: Layout override, Gap between windows, Gap to edge, Respect the Dock, `Reset this display` |
| **Apps** | Floating apps list · Rules table (app, behaviour, Space, title match) · `Add app…` · the existing rule editor sheet, unchanged |
| **Pointer & dragging** | Snap windows to edges · Snap zones · Show a preview while dragging · ⌘-drag to swap · Focus follows the mouse · Move the pointer to the focused window |
| **Window border** | Show a window border · Which windows · Thickness · Opacity · Colour + the existing inline preview |
| **Motion** | Animate layout changes · Curve · Duration · Animate snap previews · Animate layout swaps · footnote: `Follows Reduce Motion.` |
| **Advanced** | Settle time before rearranging · Verbose logging · Open logs · Copy diagnostics · `Reset Lattice…` |

No About pane. No Settings search at 30 rows (Raycast's 12 panes earn ⌘F; seven sections do not). If Settings passes ~45 rows, add ⌘F — not before.

### What is removed

| Removed | Fate |
|---|---|
| `Spaces` sidebar page | Absorbed by Overview's Space strip; the page's per-Space layout picker becomes the chip popover. |
| `Apps` sidebar page | `Settings›Apps`. Reachable contextually from any window's context menu. |
| `About` sidebar page | App menu + sidebar footer version line. Diagnostics → Advanced. |
| `Welcome` tab / 3-step onboarding | One first-run window (below). |
| `Settings›Tiling` | Split: layout + insertion + rebalance + limits → Layouts; master switch deleted (state, not setting). |
| `Settings›Layouts` | Per-layout tuning moves inside the layout cards. |
| `Settings›Gaps & padding` | → Layouts. `respectMenuBar`/`respectDock` → Settings›Displays. |
| `Settings›Spaces` | *Follow a window* → Overview header; the "Spaces window" link button → deleted. |
| `Settings›Borders`, `›Motion`, `›Input`, `›Displays`, `›Startup`, `›Advanced` | Re-cut into the seven sections above. |
| Toolbar pause button | Sidebar footer toggle already owns this; popover keeps the primary. |
| Overview "Latest", stat cards | Deleted. |
| `enterFullScreenDelay`, `accentOverride`, `snapPreviewStyle` | Delete from `Preferences` or surface in Border/Advanced — do not ship stored-but-invisible prefs. |

---

## 4. What lives where

| Current control | Today | New home |
|---|---|---|
| Tile windows automatically | Settings›Tiling + sidebar footer + toolbar + popover badge | **Delete the Settings row.** State control lives in the popover (primary) and the sidebar footer. |
| Default layout (6 chips) | Settings›Tiling | Layouts›selector (scope: This Space / All Spaces) |
| Where a new window goes | Settings›Tiling | Layouts›When a window opens |
| Rebalance after a window closes | Settings›Tiling | Layouts›When a window opens |
| Smallest tile width / height | Settings›Tiling | Layouts›Limits |
| Layouts (sidebar page, gallery) | Sidebar | **Layouts** (only home) |
| Master window share | Settings›Layouts | Layouts›Master card (inline, appears on selection) |
| Stack peek | Settings›Layouts | Layouts›Stack card (inline) |
| Grid columns | Settings›Layouts | Layouts›Grid card (inline) |
| Live layout previews | Settings›Layouts | Inside each card, replacing the abstract gallery thumbnails |
| Gap between windows | Settings›Gaps | Layouts›Space |
| Gap to the screen edge | Settings›Gaps | Layouts›Space |
| Gaps preview | Settings›Gaps | Layouts›Space, beside the two sliders |
| Per-edge padding ×4 + Clear | Settings›Gaps | Layouts›Space›disclosure (unchanged behaviour) |
| Keep windows below the menu bar | Settings›Gaps | Settings›Displays (top, global) |
| Keep windows out of the Dock | Settings›Gaps | Settings›Displays (global default; per-display override below) |
| Displays list + Refresh | Settings›Displays | Settings›Displays |
| Per-display layout / gap / outer gap / Dock / Reset | Settings›Displays | Settings›Displays (unchanged) |
| Follow a window to its Space | Settings›Spaces | **Overview** header toggle |
| "The Spaces window" link row | Settings›Spaces | **Delete** (it navigated to the page you were on) |
| Per-Space layout picker | Settings›Spaces + Spaces page | Overview Space chip (one editor) |
| Space keys (9 keys, add sheet) | Shortcuts page | **Shortcuts** (unchanged; Overview displays them as labels) |
| 56 commands + alternate chords | Shortcuts page | **Shortcuts** (unchanged, + essentials strip) |
| Everything in Spaces page (strip, per-Space tiles, send-to-Space) | Sidebar | **Overview** |
| App rules table + editor (float / don't move / layout override / Space / title match) | Apps page | Settings›Apps (editor sheet unchanged; + context-menu deep link) |
| Floating apps list | Apps page | Settings›Apps |
| Snap windows to edges | Settings›Input | Settings›Pointer & dragging |
| Snap zones | Settings›Input | Settings›Pointer & dragging |
| Show a preview while dragging | Settings›Input | Settings›Pointer & dragging |
| ⌘-drag to swap windows | Settings›Input | Settings›Pointer & dragging |
| Focus follows the mouse | Settings›Input | Settings›Pointer & dragging |
| Move the pointer to the focused window | Settings›Input | Settings›Pointer & dragging |
| Show a window border | Settings›Borders | Settings›Window border |
| Which windows / thickness / opacity / colour / preview | Settings›Borders | Settings›Window border (unchanged) |
| Animate layout changes / curve / duration | Settings›Motion | Settings›Motion |
| Animate snap previews / layout swaps | Settings›Motion | Settings›Motion |
| Launch at login | Settings›Startup | Settings›General (default on) |
| Show the menu bar icon | Settings›Startup | Settings›General |
| Accessibility access row | Settings›Startup (+ header button + popover warning + Overview card) | **General**, one row: status + `Open System Settings…`. Popover keeps a warning *only* when it is the blocking reason. |
| Welcome tour row | Settings›Startup | Settings›General: `Run setup again` |
| Settle time before rearranging | Settings›Advanced | Settings›Advanced |
| Verbose logging / Open logs | Settings›Advanced | Settings›Advanced |
| Copy diagnostics | Settings›Advanced | Settings›Advanced |
| Reset Lattice | Settings›Advanced | Settings›Advanced |
| About page (version, credits, links) | Sidebar | App menu `About Lattice`; version in sidebar footer |
| Onboarding steps 1–3 | Welcome tab | First-run window + one HUD toast (below) |
| Cheat sheet | Overlay, linked from Shortcuts | Unchanged — overlay, never a page |
| Command palette | Overlay | Unchanged |
| `enterFullScreenDelay`, `accentOverride`, `snapPreviewStyle` | Nowhere | **Delete from `Preferences`** |

---

## 5. Menu bar panel vs main window

**The law:** the popover holds *actions and current state*; the window holds *geometry, lists and forms*. A control that needs a preview, a text field, a table, or more than one line of explanation is a window control. A control that fits in a 28 pt icon or a one-line toggle is a popover control. Both may render the same state; never both edits of the same preference.

### Menu bar popover (target ≤ 420 pt wide, one screen)

1. **Header** — glyph, `Space 2 of 5 · Columns`, and the tiling on/off switch on the right. Nothing else.
2. **Layout row** — the six glyph buttons, acting on the *current* Space. A trailing `…` opens Layouts on that Space. This is an action, not an editor, so it is allowed to exist here.
3. **Window list for the current Space** — click to focus, ⌥-click to float/hide, right-click → *Don't tile this app…*. This is Lattice's differentiator against Shoji's text list; keep it.
4. **Footer icons** — command palette, cheat sheet, open Lattice, quit.
5. **Conditional, at the top, only when true:** the permission warning with one button.

### Main window

Everything with a slider, a colour well, a table, a rule editor, or a per-display override. Specifically: the map, the Space strip, the layout cards and their tuning, gaps + preview, all of Shortcuts, all seven Settings sections.

### Never duplicated

- Per-Space layout **editing** — one editor (Overview chip popover). The popover's six buttons are an action with a visible result; that is the only sanctioned second surface.
- Space keys — edited once in Shortcuts; displayed as labels in Overview.
- App rules — edited once in Settings›Apps; invoked/bypassed from the window context menu.
- Gaps, borders, motion, per-display overrides — never in the popover, not even a shortcut toggle.
- The permission state — displayed in as many places as it blocks; configured nowhere (it is a system setting). No "Grant Access" button in the Settings page header.

---

## 6. First run

**What launches:** the app is already tiling before any window appears (launch at login defaults on; Accessibility is requested the first time a window needs moving). What opens is **one window, 420 × 380, no sidebar, no steps, no counter**, shown exactly once.

Contents, top to bottom:

1. App icon, 64 pt.
2. **"Every window in its place."** — 28 pt semibold, one line under it: *Lattice tiles the Spaces you already use. No config file, no helper, no network access.*
3. **The one state machine:** a permission row that renders as `Accessibility — Required` with a single primary button `Turn on Lattice`. Pressing it fires the system prompt; the row becomes `Accessibility — On` with a green check, and the button becomes `Done` (default). No "Waiting for macOS…" ellipsis state with a spinner — Ice shows a checklist, and a checklist is better than a progress metaphor for something the user must do in another app.
4. **One escape hatch**, secondary text button: `Continue without it` → the app runs, the popover shows the warning, and nothing pretends to work. (Ice's "Continue in Limited Mode" is the model.)
5. **One caption:** *Lattice reads window positions and titles. It never reads window contents and contains no network code.*

Then, and only then, a single HUD toast after the first successful tile: `⌥H J K L to move · ⌃⌥⌘K for everything`. Tapping it opens the cheat sheet. That is the whole tutorial.

**Deferred to Settings, and never asked at launch:** layout choice, gaps, per-edge padding, borders, motion, per-display overrides, app rules, display order, panel behaviour. Lattice does not need Rectangle's `Recommended / Spectacle` question — that exists only because two legacy keymaps were in the wild; Lattice's defaults are its own and are already good.

**Deferred to the second launch:** nothing. If the user closes the first-run window without granting permission, it must **not** reappear as a modal; the popover warning plus a `General›Accessibility` row is the recovery path. Re-open the setup only from `Settings›General›Run setup again`.

**Never shipped again:** a Welcome sidebar row. Rectangle sets `wasWelcomeDisplayed` *before* showing its welcome window, so a crash on first run cannot produce a second welcome. Copy that ordering.

---

## The one-line version

Four rows — **Overview, Layouts, Shortcuts, Settings** — because those are the four things a window manager does: show you the desk, shape the desk, let you drive it, and get out of the way. One editor per object, actions wherever they are useful, state visible everywhere, copy almost nowhere.
