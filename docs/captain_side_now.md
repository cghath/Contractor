# Captain's side: what we're working on (2026-10-13)

For cghath and cghath's agent. Kept up to date as pieces land. Newest at the top of the log.

**Ground rule today:** cghath owns the 26 findings in the three-part audit (A1-01 to A3-10).
Captain's side stays out of those areas: saves and campaign, loot-all and the aid bag, reload,
IV sites, the medical menu's row limit, launcher slot controls, pack drag and AI pack recovery,
the scavenge command, corpse extraction, clear-area bonus, civilian blast accounting, building
caches, streamed-out proxies, vehicle repair reach, numeric doctrine profiles, the import-error
verdict, CI logs and `tools/make_build.sh`. If something below needs one of those files, we'll
ask here first.

Captain's side checks GitHub every 15 minutes. If you push a README or note saying what you're
picking up next, we'll read it and steer around it.

## Today's list, in order

| # | Work | Branch | Files it touches | State |
|---|---|---|---|---|
| 1 | Spotter module: camo from colours (every pattern x preset x civilians), foliage concealment, rifle sights and binoculars past 60 m | `ai/spotting` (3858d2f) | `scripts/ai/spotting.gd`, `scripts/ai/squad_ai.gd` (`_find_target`), `scripts/world/zone_scatter.gd` (`foliage_between`), `data/items.json` (binoculars magnification), `tests/squad_test.gd`, `FEATURES.md` | Built. R0267: squad, smoke, roles and people pass. One intermittent casualty check to fix (#2), then CI, then dev on Captain's go |
| 2 | Casualty flake: "doesn't pick him up again while the order stands" (failed R0257, R0267) | `ai/spotting` | `scripts/ai/squad_ai.gd` (`_care_carry`, `_should_carry`), `tests/casualty_test.gd` | Finding the cause |
| 3 | Terrain visual pass: hot-zone roads drawn on the ground | new `art/terrain-roads` | `scripts/world/zone_terrain.gd`, `scripts/world/zone_scatter.gd` | Next |
| 4 | Gear fit: wire `gear_rig` to the fit helpers in `voxel_art.gd` (male and female) | `art/gear-fit` | `scripts/combat/gear_rig.gd`, `scripts/art/voxel_art.gd` | Queued |
| 5 | Gear secondary motion: bags and armour sway with the body | new `art/gear-motion` | `scripts/combat/gear_rig.gd`, `scripts/player/character_model.gd` | Queued |
| 6 | Tree and bush art pass to match the voxel characters | `art/terrain-roads` or own branch | `scripts/world/zone_scatter.gd` | Queued |
| 7 | Final audit and a smoke test of the debug tools (bug-report key, session logs, AI overlay, test-log numbering) | none until fixes are found | read-only first | Last |

## Waiting on Captain

- Hostiles wear "urban" in every zone: terrain-matched enemy camo vs friend-or-foe.
- Scrub draws to 240 m but hides from the AI at any range.
- Back utility points (A/B/C/D), homeostasis.

## Log

- 2026-10-13 04:15: list posted.
