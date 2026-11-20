# Contractor: art director gate review

Scope and honesty: I viewed 4 of 16 images in `screenshots/` (00, 01, 07, 10) and read code. I did not run the game. All 16 files date from 9-10 Oct 2026 (git: 9 Oct), so they predate the UI theme (20 Oct) and most later work. I cannot say what the build looks like today.

No `docs/STYLE.md` exists. De facto style, inferred:
- Mood: dry, dusty, utilitarian. Faces are blocky voxel portraits.
- Palette: olive-khaki ground, desaturated sky, camo (desert, woodland, grey digital), amber UI accent. UI constants at `scripts/ui/ui_kit.gd:18-36` (amber `ACCENT` 0.93/0.69/0.27, olive-black `PANEL_BG`, Inter font, `themes/contractor_ui.tres`).
- Materials: code-built voxel models (`scripts/art/voxel_art.gd`, `vehicle_art.gd`, `prop_art.gd`). `docs/model_realism.md` records a deliberate "built, not boxed" pass.

## Findings

**Blocker**
1. No STYLE.md. Palette, wear rules and banned elements exist only in constants and chat history. Breaks the gate's own rule. Fix: write it from `ui_kit.gd`, `voxel_art.gd` and `docs/model_realism.md`.
2. Screenshots are stale and are the only visual record. No capture shows the themed UI, vehicles, zones, day/night or weather. Fix: re-shoot a fixed set (soldier, zone day/dusk/rain, vehicle, HUD, inventory, map) at the current build.

**Major**
3. Compound screenshot `01_compound_overview.png` reads as a test range: flat tan plane, bare grey slab walls, one green box building, hard horizon band (brown to blue-grey gradient). No scatter, no wear, no grime. Whether `zone_scatter.gd` or `zone_ground.gdshader` fix this in current builds I could not check.
4. Inventory in `07`/`10` is Godot default look: flat grey panel, text-only rows, no item icons, HUD text overlapping the 3D world. `docs/ui_audit.md:24` confirms "No theme" at that date; `ui_kit.gd` and `themes/contractor_ui.tres` now exist, but I did not see the result.
5. Dog tags: soldiers carry `dog_tags` data (`scripts/actors/soldier.gd:253-257`) but no worn model exists. `docs/cg_brief.md:334` lists F-160/F-161 as open. I found no tag art in `scripts/art/`.
6. Soldier lineup (`00`): all four stand in the same stiff pose, with clean, unworn kit. Camo patterns read well, but there is no dirt, fade or scuffing at knees, elbows or boots. Breaks "lived-in".

**Minor**
7. Faces (`face_art.gd`) are identical flat-eyed masks at distance; variety comes only from skin tone.
8. Voxel size is inconsistent: close-up faces in `10` show large pixels against fine camo texture on the same character.
9. Shadows are crisp, hard and uniform (`00`), with no sky-motivated softness.
10. Item pickups on the ground (`01`) are tiny, unreadable specks and yellow dummies read as placeholder.

## What's well done (seen)
- Camo variety on uniforms, with visible knee pads and plate carriers.
- Amber-on-dark UI accent is consistent in code.
- Helmet and visor variants (heavy vs light) read differently in `08`/`09` file names; I did not open those two.

## Missing / not done visually
- STYLE.md and a current screenshot set.
- Worn dog-tag model (F-160/F-161).
- Material wear pass on soldiers (grime, fade, sweat).
- Verified evidence of day/night (`scripts/world/day_night.gd` exists) and weather looks on Contractor.
- Not reviewed: vehicles, interiors, terrain shaders, map and briefing screens, icons (`item_icons.gd`).
