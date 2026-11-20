# Fallen: art director gate review

Scope and honesty: no Fallen-specific screenshot exists. `screenshots/` in this checkout is byte-identical to Contractor's (SHA-256 of `10_reload_pose.png` matches; file dates 9-10 Oct 2026) and shows no zombies, farm, settlement, seasons or gore. I viewed none of Fallen's own visuals; every finding below comes from code and docs, and the game was not run. I did not view zombie models.

No `docs/STYLE.md` exists. De facto style: shares Contractor's voxel art (`scripts/art/voxel_art.gd`), UI kit (`scripts/ui/ui_kit.gd`, Inter font, amber accent on olive-black) and day/night system. Survival adds seasons, wear and weather: grim, muted, weathered.

## Findings

**Blocker**
1. No STYLE.md and no Fallen screenshots. The survival look (dead, wounds, snow, decay, farm) has no visual record, so nothing can be gated visually. Fix: write STYLE.md and capture zombie types, settlement, each season, night, storm, gore.
2. Seasons are not drawn on the terrain. `docs/survival_seasons.md:29` says the zone def "doesn't carry the season to the terrain yet" (snow and crops by season held back). Winter is overcast light plus a flag only. Fix: pass the season to terrain, scatter and ground shader, and add snow, leaf-fall and dead grass.

**Major**
3. The dog-tag item has data (`scripts/actors/soldier.gd:268-272`, `Fallen.TAGS`) but no worn model. `docs/cg_brief.md:334` lists F-160/F-161 open. No tag art found under `scripts/art/`. Fix: a voxel tag chain on the neck, restyled to match the kit.
4. The zombie look: I found only a `crowd_zombie` model hook (`voxel_art.gd:1018`) and a `WOUND`/`WOUND_DARK` palette pair (`voxel_art.gd:35,887`, dark red `6e1712`). Distinct looks for the walker, runner, crawler and bloater that `docs/survival_seasons.md` names could not be confirmed. Fix: confirm each type has its own silhouette, rot and clothing wear.
5. The Contractor inherited issues apply too: bare grey slab walls, flat tan ground in the compound capture, and an uncertain UI theme state (see Contractor report, findings 3 and 4). Not re-verified on Fallen.
6. Weather and night exist as data in `scripts/world/day_night.gd:66-70` (clear, overcast, fog, rain, storm; fog density, light multipliers, moon). I did not see them rendered. Colour-grade and rain look are unverified.

**Minor**
7. The accessibility palette (Okabe-Ito, `docs/survival_polish.md`) is defined only for noise and load tells. It is not mapped to the main UI accent, so the colour-blind-safe mode could clash with the amber theme.
8. Survival docs note "Proposed" values everywhere; visual tuning (gore amount, snow depth) is likewise untested.

## What's done (code and docs only)
- Clothing, wear and vehicle wear systems exist (`scripts/survival/clothing_art.gd`, `clothing_wear.gd`, `wear.gd`, `vehicle_wear.gd`), so wear is designed in. I did not see the output.
- Season-aware lighting hooks and wound deformation (`BodyDeform`) exist.

## Missing / not done visually
- STYLE.md; any Fallen capture set.
- Season rendering on terrain (item 2).
- Worn dog-tag model (F-160/F-161).
- Evidence for the farm, settlement, building pieces, traps, pyres and children looks.
- Gore and corpse pile readability, and horde crowd density at distance.
- UI in survival screens (body screen, settlement, character, builder): not viewed.
