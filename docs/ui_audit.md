# UI audit and the shared look (2026-10-14)

The Captain, playtesting v0.3.1 on 2026-10-14, said: "all of the UIs need a pass". This document records the audit that comes before restyling the screens one by one:

1. Every UI in the game: where it is built, how it sizes itself, and what is wrong with it.
2. One shared look: `themes/contractor_ui.tres` and `scripts/ui/ui_kit.gd`. It is applied here to three screens as the pattern: the pause menu, the main menu and settings.
3. A proposed split of the remaining screens into follow-up branches.

The headless fit test is `tests/ui_test.gd` (the `ui` suite).

These screens are being reworked on other branches, so this one does not redo them. They should adopt the kit when they land.

- **Briefing map and map HUD:** `fix/briefing-map-ui`, already merged into integrate/v0.4.0. It has its own fit test in `tests/map_test.gd`, `_test_fit_sizes`.
- **Debrief and salvage:** `ui/debrief-salvage`, in progress.
- **New loadout menu:** `feat/loadout-menu`, in progress.

## How the UI scales today

- **No stretch mode.** `project.godot` sets only a 1600x900 window, so every pixel size in the code is a real window pixel.
- **The only scaling is the "Menu and HUD size" setting.** That is GameSettings `video/ui_scale`, which sets the root's `content_scale_factor`. Its range is 0.75 to 1.5 and it defaults to 1.0.
  - At 1.5, a 1280x720 window lays out as 853x480. That is where fixed-size panels break.
  - At 1.0 on a 4K screen, the 11 to 14 px text drawn by the HUD, inventory and medical menu is physically tiny. Even the maximum of 1.5 only makes 12 px into 18 px.
- **Since `ui/auto-scale` (P1-7):** the window picks its own scale, its height / 1080 kept within 1.0 to 2.0 (`GameSettings.auto_ui_scale`), and the setting (now 0.75 to 2.0) multiplies it (`GameSettings.ui_scale_for`). The result never shrinks the logical window below 853x480 (1280x720 at 1.5), so 2.0 on a small window acts as 1.5. It follows window resizes, and the settings Video tab shows what the window picks and the size that makes.
- **No theme.** Nothing sets a theme, so every screen uses Godot's default and then overrides sizes and colours one control at a time. The result is:
  - **Three text styles:**
    - HUD labels: 18 px with an outline.
    - Godot's default: 16 px, no outline.
    - Hand-drawn text: 11 to 14 px.
  - **Two palettes:**
    - Olive and amber (`c8d6a0`, `ffd35a`) on the command, interaction and objectives UIs.
    - Teal (`0.33,0.85,0.95`) on the inventory.
  - **Three heading styles:**
    - Yellow, in BaseUI.
    - 15 px at 70% alpha, on the contract board.
    - 13 px at 60% alpha, on the briefing.
- **Keyboard and gamepad.** Nothing had keyboard focus until this branch, and nothing reads a gamepad (a search of `scripts/` for "joy" finds nothing). Esc is the custom `pause` action everywhere; `ui_cancel` is never used.

## Inventory

Headless fit is the result of `tests/ui_test.gd` (run R0969, before the fixes on this branch). For each window size it divides the size by the UI scale, at 1.0, 1.2 and 1.5. "Fits" means every button, field, list, line of text and scroll area is inside the window at all 10 sizes: 1280x720, 1366x768, 1600x900, 1920x1080, 1920x1200, 2000x1250, 2560x1440, 2560x1600, 3440x1440 and 3840x2160. "n/t" means the screen needs a level or a player, so it can't be built headless yet.

| Screen | File | Built | Layer / parent | Text and colour | Size and anchoring | Headless fit |
|---|---|---|---|---|---|---|
| Main menu | `scripts/ui/menu.gd` (Menu) | code | CanvasLayer in `main.tscn` | default 16; hint 13 at 60% | scrolling, centred, min width 380; 20 controls in one column | fits (it scrolls) |
| Settings | `scripts/ui/settings_menu.gd` | code | CanvasLayer 30 | default 16; own opaque StyleBox | fixed 620x560, centred; 4 tabs, each scrolling | **@1.5: 1280x720, 1366x768 overflow** (fixed here) |
| Pause menu | `scripts/ui/pause_menu.gd` | code | CanvasLayer 20, on the player | default 16; session lines at 60% | min width 320, centred | fits |
| Bug report | `scripts/ui/bug_report.gd` | code | CanvasLayer 21 | default 16 | min width 420, centred; title about 440 px, not wrapped | fits |
| HUD: crosshair, prompt, downed, killed, respawn wait, flash message | `scripts/player/hud.gd` | code | CanvasLayer 1, on the player | 18 px with outline 4; downed text 28 px `ff6b5e` | `PRESET_CENTER` without grow BOTH | n/t |
| HUD: status and squad list | `scripts/player/hud.gd` `_squad_lines` | code | Hud | 18 px with outline | bottom-left, grows up; about 11 lines with 8 squadmates | n/t |
| Bleed silhouette | `scripts/player/hud.gd` | code | Hud | drawn | fixed (16,16), about 48x88 | n/t |
| Ammo readout | `scripts/ui/ammo_readout.gd` | drawn | Hud | 14 (fill), 12 (grenades at 40%) | bottom-right, fixed 260x44; 4x10 px pips | fits |
| Vehicle readout (fuel, engine, seats) | `scripts/vehicles/vehicle.gd:2030` | code | Hud | default 16, **no outline** | centre-bottom, 70 px up; one line of up to 8 parts | n/t |
| Objectives panel | `scripts/ui/objectives_panel.gd` | code | Hud | 15 px; own StyleBox at 60% | top-right, 364 px wide | fits |
| Objective hint and markers | `scripts/ui/objective_helper.gd` | drawn and code | Hud | hint 14; markers 11 to 12 px, diamonds 3.5 to 6 px at 30 to 70% | hint 480 px wide under a 364 px panel | n/t |
| Radio feed and subtitles | `scripts/ui/callouts.gd` (Subtitles) | code | Hud | 17 px `e8e4c8` with outline 4 | centre-bottom, 110 px up; 4 lines, no wrap | n/t |
| Command menu | `scripts/ui/command_menu.gd` | code | Hud | default 16; own StyleBox | centre-left, x+16 | n/t |
| Medical / treatment menu | `scripts/ui/medical_menu.gd` | drawn | Hud | 11 to 20 px; legend 11; log 12 | **fixed 1080x620 panel**, min height 540 | n/t (needs Vitals) |
| Interaction menu (rings) | `scripts/ui/interaction_menu.gd` | drawn | Hud | entries 15, point names 12 | ring radius 120; entries 180x26; submenus up to 20 entries; **nothing clamped to the screen** | n/t |
| Inventory and loot | `scripts/ui/inventory_screen.gd` | code | Hud | **9 to 22 px; teal palette** | margin 18; columns 330 and 300 fixed; tiles 96x112 | n/t |
| Map, briefing panel, extraction panel | `scripts/ui/map_*.gd`, `briefing_screen.gd` | code and drawn | Hud | 12 to 20 px | being reworked on fix/briefing-map-ui | covered by `map_test` |
| Contract board | `scripts/ui/contract_board.gd` | code | CanvasLayer 10 | default 16; sections 15 at 70% | full window inset 40; left column 460; bottom row of 7 buttons | **@1.5: 1280x720, 1366x768 overflow** |
| Shop | `scripts/ui/shop.gd` | code | CanvasLayer 11 | default 16; notice `ffd35a` | fixed 620x560, placed by hand | **@1.5: 1280x720, 1366x768 overflow** |
| Debrief | `scripts/ui/debrief.gd` | code | CanvasLayer 12 | title 22, headings 17, lines 15 | full window inset 80, scrolls | fits when empty (being reworked on ui/debrief-salvage) |
| Base hub pages (squad / Ops desk, roster, hiring board, medbay, shop, armory) | `scripts/campaign/base_ui.gd` (page from `base_terminal.gd`) | code | CanvasLayer 20 | default 16; headings `ffd35a` | **fixed 980x640**, centred; rows 700 / 760 / 640 / 420 px with `clip_text` | **@1.2: 1280x720; @1.5: 1280x720, 1366x768, 1600x900 overflow** (all 6 pages) |
| Motor pool | `base_hub.gd` `_motor_pool_actions` | interaction ring | n/a | n/a | no page of its own | n/a |
| Base loading screen | `base_hub.gd:694` | code | CanvasLayer 120 | default 16 | full window | n/t |
| Extraction | `scripts/campaign/extraction.gd` | no UI (text for the map and HUD) | n/a | n/a | n/a | n/a |
| Dev: AI overlay | `scripts/ui/ai_overlay.gd` | Label3D | 3D, on the player | 28 px fixed-size at 0.0007 | up to 16 three-line labels over the squad | n/a |
| Dev: hot-zone readout | `scripts/ui/hot_zone_debug.gd` | code | CanvasLayer 50 | 13 px with outline | **absolute (12,120)**; 8 to 9 lines, no wrap | n/t |

## Problems, ranked

- **P0:** broken or unusable at a common window size, or at the Captain's UI scale of 1.2.
- **P1:** hard to use.
- **P2:** polish.

"Measured" means the headless fit test shows it. "Read" means it comes from reading the code: the screen can't be built headless yet.

### P0

1. **Base hub screen (`base_ui.gd`), measured.** The fixed 980x640 panel is centred with grow both.
   - At 1280x720 with the Captain's 1.2, the header (day, funds, wages) and the Close (Esc) button are above the top of the window.
   - At 1.5, all six pages are cut off at 1280x720, 1366x768 and 1600x900.
2. **Medical menu, read.** Its fixed 1080x620 panel is wider than a 1280x720 window at 1.2 (which lays out as 1067x600), and its minimum height of 540 is more than 480 at 1.5. The signs column and the treatment log, drawn at +720 px, are cut off on the right.
3. **Interaction menu, read.** Rings and submenus are never clamped to the screen.
   - A 20-entry loot submenu is about 560 px tall and runs off a 720 px window unless its parent entry is near the middle.
   - At 1.5 the self-interaction ring's head entry is at centre −303 px, which is off the top.
4. **Shop, measured and read.**
   - **Esc is not handled.** It falls through and closes the contract board **underneath**, leaving the shop open.
   - At 1.5, 1280x720 and 1366x768, its title and filter are above the window.
5. **Contract board, measured.** At 1.5, 1280x720 and 1366x768, 12 controls are outside the window: the header, both offer lists and the details. The bottom row of seven buttons doesn't wrap.
6. **Settings, measured. Fixed on this branch.** The fixed 620x560 box overflowed at 1.5 on 1280x720 and 1366x768. It is now sized to the window.

### P1

7. **No automatic UI scale, read.** On 2560x1440, 3440x1440 and 3840x2160 every screen is laid out for 1600x900 pixels. HUD, inventory and medical text at 11 to 14 px is physically tiny, and the 1.5 maximum isn't enough for 4K (which needs about 2.0).
8. **Inventory screen, read.**
   - Text is 9 to 12 px (captions 9, tile names 11, readouts 10).
   - Muted teal on dark is low contrast.
   - The fixed columns take 694 px, which leaves about 160 px for the doll and grid at 1280x720 with 1.5.
   - Buttons are `FOCUS_NONE`, so the screen is mouse only.
9. **Vehicle readout, read.**
   - It is one run-on line of up to 8 parts ("Humvee, Gunner | Fuel 40 L | Engine 55% | ... | F: get out"), 800 to 900 px wide, with no wrap.
   - It has **no outline**, so it is unreadable over bright ground.
   - It sits 17 px under the subtitles.
10. **HUD left edge overlap, read.** Three things stack at x = 12 to 16:
    - the squad list (bottom-left, growing up to about 280 px with 8 squadmates);
    - the command menu (centre-left);
    - the hot-zone readout at the absolute position (12,120).

    At 720 px tall the squad list and the command menu overlap.
11. **HUD centre labels drift and run on, read.**
    - The prompt, the downed text and the flash message use `PRESET_CENTER` without `grow_horizontal = BOTH`, so longer text grows to the right of centre.
    - The 28 px downed line "Your team can treat you; you'll come round when your body recovers" is about 900 px wide with no wrap, wider than an 853 px layout.
12. **Base pages clip text silently, read.**
    - Roster, hiring and medbay rows are 700, 760 and 640 px Labels with `clip_text`, so wages and skills are cut with no "..." and no tooltip.
    - The armory intro (about 130 characters) and the header are single unwrapped lines.
    - BaseUI's own Shop tab duplicates the shop screen in a different style.
13. **Objective hint and markers, read.**
    - The hint is 480 px wide under a 364 px objectives panel, so its left edge pokes out 116 px.
    - Marker labels are 11 to 12 px, and diamonds are 3.5 px at 30% alpha.
14. **Ammo readout, read.** The grenade line is 12 px at 40% alpha, the fill word is 14 px at 75%, and the pips are 4 px wide. The grenade line is drawn 3 px below the control's own box.
15. **Keyboard, read.** No screen took focus until this branch: Tab, the arrow keys and Enter did nothing until the first click. The menu, the pause menu and the inventory are mouse only. There is no gamepad support anywhere.
16. **Debrief, read.** It is being reworked on ui/debrief-salvage; these are notes for that branch.
    - Intel rows (label, Turn in, faction picker, Sell) don't wrap.
    - Continue sits at the end of the scroll and isn't pinned.
    - Casualties and the carried-out list are comma-separated text dumps.

### P2

17. **Main menu. Fixed on this branch.** It was one column of 20 controls with play and debug mixed together. It is now sections (You, Play, Campaign, Test zones) in two columns that fold into one on a narrow window, with keyboard focus from the start.
18. **Pause menu. Fixed on this branch.** It used the default theme and the session lines were at 60% alpha. It is now themed, with Leave and Playtest logs sections and an Esc key hint, and it takes focus when opened.
19. **Inconsistent styles, read.** There are three text styles, two palettes and three heading styles (see "How the UI scales today"), plus five different hand-made StyleBoxes:
    - settings,
    - objectives,
    - command menu,
    - inventory,
    - medical.
20. **Briefing panel, read.** Its 12 to 13 px help and section text is at 60% alpha. It belongs to fix/briefing-map-ui (merged); adopt `HintLabel` and `HeadingLabel` from the kit when it is next touched.
21. **Bug report, read.** Its title (about 440 px) is wider than its 420 px box, and it uses the default theme.
22. **Hot-zone and AI dev overlays, read.**
    - The hot-zone readout is 13 px at an absolute position and overlaps the command menu.
    - Up to 16 AI labels pile up over the squad.
23. **Design gaps, read.** The motor pool has no page (it is only an interaction ring), and the roster page has no terminal. These are design questions to settle when the base hub is restyled, not layout bugs.

## The shared look

### Theme: `themes/contractor_ui.tres`

- **Panels:** dark translucent olive, `0.07,0.08,0.07` at 90%, with a 1 px `0.32,0.35,0.29` border, 4 px corners and 16/14 px content margins. The `SolidPanel` variation is opaque, for a screen opened over another screen.
- **Text:** `0.90,0.91,0.87` with a soft shadow. Sizes are 16 body (the theme default), 14 small, 20 heading and 26 title. Nothing goes below 14.
- **One accent:** amber `0.91,0.67,0.25`. It is used for the button hover border, pressed buttons, the 2 px focus ring, headings, the selected tab, progress fill and key chips.
- **Status colours:** good `0.47,0.76,0.42` and warn `0.93,0.45,0.36`.
- **Label variations** (set with `theme_type_variation`): `TitleLabel`, `HeadingLabel`, `HintLabel`, `WarnLabel` and `KeyLabel`.
- **Spacing scale:** 4, 8, 12 and 20 (`UiKit.SPACE_XS`, `SPACE_S`, `SPACE_M`, `SPACE_L`). Boxes are spaced at 8 and keep `UiKit.EDGE` = 24 from the window edge.
- **Scale:** every size is a logical pixel, so the Menu and HUD size setting (`content_scale_factor`) scales all of it.

### Kit: `scripts/ui/ui_kit.gd` (UiKit, all static)

| Call | Gives |
|---|---|
| `UiKit.apply(control)` | the theme on a control and everything under it (a CanvasLayer can't hold a theme, so call it on the layer's top Control) |
| `UiKit.dim(alpha)` | a full-window darkening behind a menu |
| `UiKit.screen(layer, width, solid)` | a centred menu screen: a full-window ScrollContainer (themed) with a centred panel and a VBox fitted to `width` or to the window, whichever is smaller. Returns the VBox; the panel is `get_parent()`. A screen too tall for a small window, or for a big UI scale, scrolls instead of running off it. |
| `UiKit.fit_width(c, w)` / `UiKit.fit_height(c, h, reserve)` | keeps a minimum size within the window (less `EDGE`) and follows resizes and UI scale changes |
| `UiKit.panel(solid)` | a panel in the shared style |
| `UiKit.title(t)` / `heading(t)` / `text(t)` / `hint(t)` / `warn(t)` | labels in the shared styles, all wrapping (no run-on lines) |
| `UiKit.section(heading, parent)` | a heading over a VBox, which it returns for the section's rows |
| `UiKit.row(label, control, label_width)` | a wrapping label column, then the control filling the rest |
| `UiKit.button(text, callable, tooltip)` | a button that cuts long text with "..." and keeps the whole text in its tooltip, instead of widening the panel |
| `UiKit.button_row(buttons, align_end)` | buttons that wrap onto another line when the panel is narrow |
| `UiKit.list(min_height)` | an ItemList that cuts long items with "..." |
| `UiKit.scroll(min_height)` | a vertical scroll area; returns its VBox |
| `UiKit.key_hint("Esc", "Close")` | a key chip and what the key does |
| `UiKit.budget_bar(value, max, caption)` | a bar with a caption that turns warn-red past `max` (for salvage budgets, cash against cost, load) |
| `UiKit.focus_first(root)` | focuses the first enabled button, so Tab, the arrow keys and Enter work as soon as a menu opens |

### Pattern: a menu screen in the kit (see `pause_menu.gd`)

```gdscript
func _ready() -> void:
	add_child(UiKit.dim(0.45))
	var box := UiKit.screen(self, 380.0)        # self is the CanvasLayer
	box.add_child(UiKit.title("Paused"))
	box.add_child(UiKit.button("Resume", close))
	var leave := UiKit.section("Leave", box)
	leave.add_child(UiKit.button("Quit game", _quit))
	box.add_child(UiKit.key_hint("Esc", "Resume"))

func open() -> void:
	visible = true
	UiKit.focus_first(box.get_parent())
```

### Rules for the follow-up branches

- **No colours or sizes by hand.** Don't add `add_theme_font_size_override`, `modulate = Color(1,1,1,0.6)` or a hand-made StyleBoxFlat. Use a label variation or a UiKit constant. Drawn UIs (the medical, interaction and ammo readouts, the map) take their colours and sizes from the UiKit constants (`UiKit.ACCENT`, `UiKit.FONT_SMALL`, and so on).
- **No fixed panel sizes.** Use `UiKit.screen`, `fit_width` or `fit_height`. A drawn panel clamps itself to `get_viewport().get_visible_rect()`.
- **Wrap or cut with "...", never clip silently.** Long text wraps. Long single-line text cuts with "..." and has a tooltip.
- **Every screen closes on Esc** (the `pause` action) and consumes the event, so the screen underneath doesn't close instead.
- **Every screen takes focus when it opens** (`UiKit.focus_first`), unless it is a key-capture screen like the settings Keys tab.
- **Every new screen gets a `_fit` line in `tests/ui_test.gd`.** A branch that fixes a KNOWN screen takes its entries off `KNOWN`; the test fails if a KNOWN entry starts fitting, so the list can't go stale.

## The fit test (`ui` suite)

`tests/ui_test.gd` builds each screen that needs no level inside a SubViewport. The viewport is sized to each of the 10 window sizes divided by the UI scale each setting gives there (`GameSettings.ui_scale_for` with the setting at 1.0, 1.2, 1.5 and 2.0), which matches what `content_scale_factor` does to the root. The test then checks that every visible button, field, slider, list, tab set, non-empty label and scroll area is inside the viewport.

- **Scroll areas count as one item**, because their content can scroll.
- **Screens waiting for a follow-up branch are in `KNOWN`.** Their overflows are printed as `[known]` instead of failing.
- **It prints a `FIT` summary line for each screen and scale.**
- **Screens covered:**
  - pause menu
  - settings
  - main menu
  - bug report
  - contract board
  - shop
  - empty debrief
  - the six base pages
  - objectives panel
  - ammo readout
- **Not covered yet:** the HUD, the medical, interaction, command and inventory screens, and the vehicle readout all need a player. ui/hud-pass should add a hosted-level fit section for them, the way `map_test` hosts a level.

## Follow-up branches

Sizes: S is about half a day, M about a day, L two or more days.

| # | Branch | Screens | Fixes | Size |
|---|---|---|---|---|
| 1 | `ui/auto-scale` | GameSettings and the settings Video tab | P1-7. Choose the default UI scale from the window height (height / 1080, clamped 1.0 to 2.0) with the setting as a multiplier; raise the maximum to 2.0. Do this first: it changes what every later branch fits against. Keep `ui_test`'s scales in step. | S |
| 2 | `ui/base-hub` | BaseUI (all six pages), the base loading label, the motor pool's page question | P0-1, P1-12, P2-23. Use `UiKit.screen` with SolidPanel; rows built with `row` and `button`, cut with "..." and tooltips; drop the duplicate Shop tab or make it the shop screen; take the base entries off KNOWN. Coordinate with feat/loadout-menu, since the armory page is where a loadout menu would hang. | M |
| 3 | `ui/campaign-screens` | contract board, shop | P0-4 (Esc, fit) and P0-5. Use `button_row` for the board's seven buttons; make the details scroll; `list()` with tooltips; take them off KNOWN. | M |
| 4 | `ui/hud-pass` | Hud labels (crosshair, prompt, downed, respawn, flash), squad list, ammo readout, vehicle readout, objectives panel and hint, subtitles, hot-zone readout | P1-9, P1-10, P1-11, P1-13, P1-14, P2-22. Set out HUD zones (top-right objectives, bottom-left squad, bottom-right weapon, bottom-centre radio and vehicle, centre-left command), use one outlined text style from the theme, and split the vehicle readout into parts. Add a hosted-level HUD fit section to `ui_test`. | L |
| 5 | `ui/medical-interaction` | medical menu, interaction rings (both drawn) | P0-2, P0-3. Clamp panels, rings and submenus to the visible rect; scroll long loot submenus; sizes from UiKit (14 px minimum). | L |
| 6 | `ui/inventory` | inventory and loot screen | P1-8 and the inventory side of P1-15. Re-palette to the theme, 14 px minimum, columns that flex, keyboard focus. Coordinate with feat/loadout-menu, which likely shares the item tiles. | L |
| 7 | `ui/small-screens` | command menu, bug report, AI overlay | Theme the command menu's panel and rows (P2-19) and the bug report (P2-21); thin out the AI overlay's labels. | S |
| 8 | (on their own branches) | debrief (ui/debrief-salvage), loadout (feat/loadout-menu), briefing and map (next time they are touched) | Adopt UiKit: `budget_bar` for the salvage budget, `HintLabel` and `HeadingLabel` for the briefing. Notes for the debrief are in P1-16. | n/a |

Branches 2, 3 and 7 are independent of each other and can run in parallel. Branch 4 should land after branch 1. Branches 5 and 6 touch the biggest files (`medical_menu.gd` is 618 lines, `inventory_screen.gd` 1330), so give each one a session of its own.
