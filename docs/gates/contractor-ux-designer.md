# Contractor (dev): UX gate review, UX designer

Method: read code and docs only. I could not run the game. `screenshots/` holds 16 images; I opened only `07_hud_inventory.png`. It shows an early build (overlapping HUD text behind the inventory, "Stow/Drop" rows), so it is not evidence for the current UI. Nothing below was observed in play.

## Findings

### Blocker
None found in what I read. I can't rule one out without playing.

### Major
1. **No colour-blind support (usability: signs and feedback, accessibility).** Grep for colour-blind, deuteranopia, high contrast and similar across `*.gd` and `*.md` returned no matches. Red/green tells (hit, armour, wound state) have no shape or text backup that I could confirm. The Fallen branch already has a working palette and shape system (`B:\Contractor-build-fallen\scripts\survival\accessibility.gd:1`). Port it.
2. **No subtitle toggle and no text-size setting (accessibility).** Callout subtitles always show (`scripts/ui/callouts.gd:545`, class `Subtitles`). `scripts/ui/settings_menu.gd` has no "subtitle" match, and no text-scale setting exists. Only the Menu and HUD size slider (`settings_menu.gd:218`, 75% to 200%) scales text, and it also scales layout. Players can't turn subtitles off or enlarge text alone.
3. **Gamepad is fixed-layout and the tutorial is keyboard-only (flexibility, consistency).** Pad bindings are a constant table (`autoload/controls.gd:118`). The settings Keys tab handles keyboard and mouse only (`settings_menu.gd:104-130`; the only pad settings are stick sliders, `:264-269`). The tutorial's steps name keys, mouse buttons, Left Ctrl, Page Up/Down (`tutorial_guide.gd:97-150`). The only pad mention is the last line (`:347`). A pad player gets instructions they can't follow, and Page Down is the only way to advance "read" steps.
4. **Interaction menus rest on hold Left Ctrl (+ Left Alt), which can't be rebound.** The Keys tab refuses Ctrl/Alt/Meta (`settings_menu.gd:122-123`). The tutorial hard-codes "Left Ctrl", "W / S", "A / D", "F1-F8", "` (backquote)" (`tutorial_guide.gd:102,109,119,128`). A rebound or non-US layout makes those lines wrong, despite the header promising live bindings (`:7-8`). The backquote key is also awkward on many non-US keyboards.

### Minor
5. **Tutorial progress is a one-way list.** Skips are kept for the whole run (static, `tutorial_guide.gd:20-21`). Whether the learner can go back a step, I couldn't tell.
6. **Co-op teacher sees no panel** by design (`tutorial_guide.gd:22-25`). Acceptable; note it in the lobby text.
7. **Pause menu says "nothing pauses"** (`pause_menu.gd:32`). This is honest and well-written. But a solo player has no pause. Fallen has `solo_pause.gd`. Consider the same here.
8. **Text quality is good.** Plain voice, tooltips on every setting (`settings_menu.gd:12-41`), real terms (MOLLE, tourniquet, pressure bandage). I found no filler or typos in what I read; that is a sample, not an audit.

### Strengths I verified in code
Esc backs out on settings, pause and shops (`settings_menu.gd:6,79`; `docs/ui_audit.md:89` records the shop fix). Reset-all asks first (`:73-76`). Focus goes to the first button on open (`docs/ui_audit.md:182`). Auto UI scale from window height (`game_settings.gd:125-329`). A rebind swap is announced ("X moved to Y", `:113,128`). Tutorial is the third play button, labelled "new here? start with this" (`menu.gd:94`).

## What's missing or not done for UX
- Colour-blind mode, subtitle toggle, text-size slider (above).
- Gamepad rebinding and pad-aware tutorial text.
- Keyboard rebind of the Ctrl/Alt interaction modifier.
- No automatic first-run prompt to the tutorial. I only saw the menu label; I did not check for a first-launch nudge.
- Hints during normal play: Fallen has once-each contextual hints (`field_hints.gd`). I saw none in Contractor; I didn't search exhaustively.
- Inventory screenshot is stale; fresh captures of menu, HUD, map and debrief are needed to review readability visually. I reviewed none.
- Not verified: contrast ratios, touch/target sizes, HUD overlap (`ui_test` covers fit, which I didn't run).
