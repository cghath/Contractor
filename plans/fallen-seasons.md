# Fallen: the seasons on the terrain (M2, art gate Blocker 2)

Branch `feat/fallen-seasons` (from `fallen/nov10-playtest` a6064f8b). Owner: Cheeno (code); Captain signs off
the look. Status: **draft, waiting for Captain's OK**. Every new number is **Proposed**.

## What exists (research, 2026-11-21)

- `autoload/survival.gd:254` `_host_zone` duplicates the zone def and hosts it with no `"season"`, so
  `ZoneFeatures` (`zone_features.gd:167`, `Season.of_def`) draws `Season.DEFAULT` = **summer** in every
  Fallen zone, while a new Fallen world starts in **spring** (`Seasons.START`). So step 1 changes today's
  terrain even for a spring world (crops, orchards); it is not a no-op.
- Both season classes use the same names (spring/summer/autumn/winter); the calendars differ (Season 30
  campaign days, Seasons 10 world days), which doesn't matter here: we pass the name, not a day.
- The def reaches clients through `LevelSwitch.load_level(..., {"def": ...})` (`main.gd:38`); the season in
  it reaches every client with the def. `ZoneTerrain.checksum()` folds the season in, and the scatter's
  cache key holds the checksum, so a new season builds a new scatter and never reuses an old one.
- Already drawn by season: crops (`CROPS`), orchard crowns (`ORCHARD_CROWNS`, bare in winter), the snow
  line, but **only on presets with snow** (`_snow` from the preset; `snow_strength()` is 0 elsewhere).
- Ground: `zone_ground.gdshader` (uniforms dry/rock/earth colours, `snow_strength`) over per-vertex colours
  from `ZoneTerrain._ground_colour`. Grass: `GrassCarpet.setup(..., colours)` and the scatter's tufts.
  Wild trees: `ZoneScatter`, per-instance crown colours from the preset's `"crown"` list (`zone_scatter.gd:362`),
  crowns a mesh of their own (`_crown_mesh`, LOD `crown_lod`), far canopy blobs past `SEE_TREE_M`;
  crowns also count as foliage for spotting (`foliage_between`). Conifers have their own mesh.
- Water: `water_surface.gdshader` (shallow/deep/foam colours); "frozen" exists only as static preset data
  on snow_mountain. `Seasons.water_frozen()` is read only by the body lane today.
- Weather particles: `DayNight._make_rain()` (`day_night.gd:405`), a GPUParticles3D box round the camera.

## Steps

Each step ends with `tools/run_tests.sh` on the suites it names (own `CONTRACTOR_PORT`), run IDs in the
commit, and a `WIP fallen-seasons: step N` commit.

1. **Wiring.** In `_host_zone`, `hosted["season"] = season()` (before `FirstHour.farmstead`). Run survival,
   worldsim, firsthour, seasons, smoke, world, water, nature, fallenevents. Any check that assumed summer
   terrain gets the season pinned in its setup (`"season": "summer"` in its new-world options) with a
   comment saying why, never a loosened check. *Verify:* the suites green; a `seasons_test` check that a
   winter world's hosted def carries "winter" and `ZoneFeatures.season` on the host and a client is "winter".
2. **One season source for the look.** A small static `SeasonLook` (`scripts/world/season_look.gd`): per
   season, the ground tint, grass colours, wild-crown colours (or bare), snow cover, ice, leaves rate. All
   tables Proposed, read by the steps below, so tuning lives in one place. *Verify:* parse clean in smoke.
3. **Ground and grass tint.** A `season_tint` (vec3 multiply) and `season_dry` (0-1, toward `dry_colour`)
   uniform in `zone_ground.gdshader`, set in `ZoneTerrain.ground_material()`; the grass carpet and tufts
   take their colours through `SeasonLook` (spring fresh green, summer as now, autumn straw, winter dead
   brown-grey). Proposed values in the table. *Verify:* terrain/nature suites; shots of each season.
4. **Wild trees.** Broadleaf crowns take `SeasonLook` colours (autumn: a mix of rust, ochre and the summer
   green; spring: a lighter green). Winter: broadleaf crowns are not drawn (trunks and a thin branch mesh
   stay; conifers keep theirs) and **stop counting as foliage for spotting** (see call A). Far canopy blobs
   follow (bare winter: blob tinted grey-brown and thinned to 40%). *Verify:* a check that a winter zone has
   0 broadleaf crown instances and `foliage_between` through a bare wood is lower than summer; shots.
5. **Snow cover.** In winter every preset gets snow (`SNOW_DEFAULTS` with the winter line), so the existing
   snow look, drifts and tracks apply off the snow presets too. Movement slow per call B. Late winter
   (days 8-10) thins the cover toward the spring line. *Verify:* a check that `snow_strength() > 0` and
   `snow_at` > 0.5 on open ground in a temperate winter zone; summer 0; the movement check per call B.
6. **Frozen water.** `ice` uniform (0-1) in `water_surface.gdshader`: grey-white, matte, cracks, no ripple
   or foam, set from `Seasons.water_frozen()` at zone load. Walking per call C. *Verify:* a water_test
   check per call C; shots of a frozen pond and stream.
7. **Falling leaves.** A second particle box in `DayNight` like the rain: autumn only, emitting by how
   wooded the camera's surroundings are (the scatter's foliage near the camera, sampled once a second),
   ~120 leaves max, slow tumbling quads in the autumn crown colours; off under `Settings` low particles.
   *Verify:* a check that it emits in an autumn wood and not in summer or open ground; FrameCost line.
8. **Frame time.** A perf run (`perfcases` style) on the same seed and camera path in winter and in
   summer: average and worst frame, draw calls, from FrameCost. Recorded in this plan's Progress and in
   `docs/survival_seasons.md`. *Verify:* winter within 5% of summer on average (Proposed budget); if not,
   fix before step 9.
9. **Screenshots for Captain.** `tests/terrain_shots.gd`-style script (an S run) of one Fallen zone, same
   seed and four cameras (farm, wood edge, pond, road), in all four seasons: 16 PNGs in the S folder.
10. **Docs.** `docs/survival_seasons.md` (the line about the held-back season goes), calls in
    `docs/audits/followups.md`, PROGRESS. Push the branch, CI green on it.

## Calls for Captain (gameplay, not only looks)

- **A. Bare trees and hiding:** leafless broadleaf woods in winter stop hiding people (only trunks and
  conifers block sight), so winter woods are more open. Proposed: yes.
- **B. Snow and movement:** snow cover slows walking (the existing `slow` 0.25 of the snow presets) and
  leaves tracks. Proposed: yes, 0.15 slow off the mountain presets (shallower lowland snow).
- **C. Ice:** frozen ponds and streams can be walked on by players and the dead (AI crosses on them only
  where its navigation already allows; deep water stays off the nav mesh). Proposed: visual + walkable for
  players, nav unchanged this pass.
- **D. When the look changes:** the zone's season is fixed when the zone loads (a new season shows on the
  next zone load or sleep-through), not live mid-visit. Proposed: on load (live re-tint is a later pass).

## Progress

- 2026-11-21: research done, plan drafted.
