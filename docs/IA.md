# Lattice — information architecture (final)

Synthesised from three independent audits: comparative (shipping apps + Apple), jobs-to-be-done,
and copy/density. Where they disagreed, the decision is recorded below.

## The rules
1. **One editor per object.** State may be shown anywhere; a preference is *set* in exactly one place.
2. **Actions are available where the object is**; settings live in one window.
3. **A row earns a sidebar slot only if it is used weekly.** Shortcuts qualifies (65 bindings).
   Apps does not (4 rules, twice a year) — it becomes a Settings section with a deep link.
4. **A control earns a caption only if it says something the control cannot.** One sentence per
   group, never per row.
5. **Nothing appears twice.** No duplicated toggles, no two pickers for one layout, no About page.

## Sidebar — four rows

| # | Row | Purpose | Contains |
|---|---|---|---|
| 1 | **Overview** | What is on screen right now | Per-display Space strip, live map, floating chips, last 3 actions + Undo, `Follow a window to its Space` |
| 2 | **Layouts** | How windows get arranged | Six layout cards with their own tuning inline, gaps + preview, limits, insertion, per-Space layout rows, `New Spaces start with…` |
| 3 | **Shortcuts** | What every key does | Essentials strip, Space keys, 55 commands + alternates, conflicts |
| 4 | **Settings** | Everything else | General · Displays · Apps · Pointer & dragging · Window border · Motion · Advanced |

Absorbed/deleted: **Spaces** page (→ Overview strip + Layouts rows), **Apps** page (→ Settings › Apps
+ context-menu deep link), **About** page (→ app menu + Settings footer), **Welcome** tab (dead),
the second Spaces window, all ten Settings sections as they were.

## Settings — seven sections, ≤6 rows each, ordered by use

1. **General** — launch at login · menu bar icon · accessibility status · run setup again · version
2. **Displays** — menu bar · display list · per display: layout, gap, edge gap, Dock, reset
3. **Apps** — floating apps · rules table · add app (one search that also adds) · editor sheet
4. **Pointer & dragging** — snap · zones · preview · ⌘-drag swap · focus follows mouse · warp
5. **Window border** — on · scope · thickness · opacity · colour (menu, not 13 swatches) · preview
6. **Motion** — animate · curve · duration · snap · swaps · Reduce Motion note
7. **Advanced** — settle time · verbose logging · logs · diagnostics · reset

Deleted preferences: `enterFullScreenDelay`, `accentOverride`, `snapPreviewStyle` (stored, surfaced
nowhere).

## Copy rules
- Sentence case everywhere, including `CommandID.title` and layout names in prose.
- No row subtitle that restates the control. Footers: one sentence, one per group.
- The Space-owns-its-layout idea is stated **once**, on Layouts: "Each Space keeps its own."
- Accessibility is explained **once** (the banner). Everywhere else: state only.
- Launchers: "Open System Settings", "Open logs", "Copy diagnostics", "Reset all settings…".

## Density targets
| Screen | Now | Target |
|---|---|---|
| Overview | 15 controls | 4 |
| Layouts | 14 | 8 |
| Shortcuts | 174 | ~56 (one chord per row; alternate on hover) |
| Settings | 67 | ≤32 (7 sections) |
| Menu bar panel | 23 | ~16 |

## Menu bar vs window
Popover = actions and current state (Space, six layout glyphs acting on this Space, window list,
pause, palette, cheat sheet, open, quit). Window = geometry, lists, forms. Gaps/borders/motion/
per-display/edit-a-rule never appear in the popover.

## First run — one window, once
420×380, no steps, no counter: product line, one permission row that flips to a green check,
`Turn on Lattice` → `Done`, one escape ("Continue without it"), one privacy line. Then a single
HUD toast with the four chords worth knowing.

## Missing command to add
`moveToNextDisplay` / `moveToPreviousDisplay` — the only job with no surface at all today.


---

## Shipped in this pass

- Sidebar 7 → **4** rows (Overview · Layouts · Shortcuts · Settings); `Spaces`, `Apps` and `About` no
  longer occupy a row.
- Overview absorbs Spaces: per-display Space strip, map, floating chips, 3 recents + Undo,
  `Follow a window to its Space`. Control count 15 → 4.
- Layouts absorbs the layout tuning, gaps + preview, limits, insertion, and the per-Space list
  including `New Spaces start with` and `Add a Space…`.
- Settings 10 sections → **7** (General · Displays · Apps · Pointer & dragging · Window border ·
  Motion · Advanced), Apps folded in as one list, About folded into General's footer.
- System apps collapsed to one "8 system apps are always floating" row.
- First run is one 440×420 window with a single permission row and one escape hatch.
- AppKit switches/sliders/segmented pickers replaced with drawn equivalents so the UI is
  consistent and capturable.

## Known rough edges (next pass)

- Overview's map card does not stretch to the page width.
- Shortcuts still uses `List`; it is the one page that cannot be captured offscreen yet.
- The Apps search field and the border colour row are the last AppKit-backed controls, so they
  appear as placeholders in the offscreen renders (they are correct in the running app).
