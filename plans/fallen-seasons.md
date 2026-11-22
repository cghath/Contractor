# Fallen: the seasons on the terrain (M2, art gate Blocker 2)

Branch `feat/fallen-seasons` (from `fallen/nov10-playtest` a6064f8b). Owner: Cheeno (code); Captain signs off
the look. Status: **built; look signed off by Captain 2026-11-21**. Every new number is **Proposed**.

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
2. **One season source for the look, live (call D).** A small static `SeasonLook`
   (`scripts/world/season_look.gd`): per season, the ground tint, grass colours, wild-crown colours (or
   bare), snow cover, ice, leaves rate. All tables Proposed, so tuning lives in one place. A `SeasonLive`
   node on the zone holds the season shown now; the host sets it from `Survival.season()` when the season
   turns (Seasons already ticks it) and sends it to clients (one reliable RPC, and in the late-join state);
   it emits `changed(season)`, and steps 3-7 listen and update in place, blending over 20 s (Proposed) so
   nothing pops. Geometry from the def's season (crops, orchards, the mountain snow line) stays as loaded
   until the next zone load, because rebuilding fields mid-visit is a voxel rebuild; called out to Captain.
   `ZoneFeatures.season` (and the checksum) keep the def's season; the live season lives beside it.
   *Verify:* a seasons_test check that a host and a client both see `changed("winter")` within 2 s of
   the host's season turning; parse clean in smoke.
3. **Ground and grass tint.** A `season_tint` (vec3 multiply) and `season_dry` (0-1, toward `dry_colour`)
   uniform in `zone_ground.gdshader`, set in `ZoneTerrain.ground_material()`; the grass carpet and tufts
   take their colours through `SeasonLook` (spring fresh green, summer as now, autumn straw, winter dead
   brown-grey). Proposed values in the table. Live: shader uniforms and the carpet's instance colours
   are set again on `changed`. *Verify:* terrain/nature suites; shots of each season.
4. **Wild trees.** Broadleaf crowns take `SeasonLook` colours (autumn: a mix of rust, ochre and the summer
   green; spring: a lighter green). Winter: broadleaf crowns are not drawn (trunks and a thin branch mesh
   stay; conifers keep theirs) and **stop counting as foliage for spotting** (see call A). Far canopy blobs
   follow (bare winter: blob tinted grey-brown and thinned to 40%). Live: crown instance colours are
   rewritten on `changed` (a crown shader `leaf` uniform 0-1 shrinks crowns to bare over the blend, no
   MultiMesh rebuild), and the spotting index (`_foliage`) gets a per-season flag on broadleaf crowns
   rather than a rebuild. *Verify:* a check that a winter zone has
   0 broadleaf crown instances and `foliage_between` through a bare wood is lower than summer; shots.
5. **Snow cover, live.** The snow presets bake snow into vertex colours, which can't change mid-visit, so
   lowland winter snow is a shader layer instead: a `season_snow` uniform (0-1) in `zone_ground.gdshader`
   whitening open, flat ground with drift noise (less under trees, none on roads' cores), blended live by
   `SeasonLive`. `ZoneFeatures.snow_at` adds the live cover on presets without their own snow, so the
   walking slow is 0.15 (call B, Proposed) and tracks print; the mountain presets keep 0.25. Late winter
   (days 8-10) thins the cover. *Verify:* checks that a temperate winter zone has `snow_at` > 0.5 on open
   ground and summer 0, and that walking pace on that ground drops by ~15%.
6. **Frozen water, walkable by everyone (call C).** `ice` uniform (0-1) in `water_surface.gdshader`:
   grey-white, matte, cracks, no ripple or foam, blended live from `Seasons.water_frozen()`. When water
   freezes, the water bodies get a walkable ice collider at the surface, wading and swimming stop there,
   and `NavBuilder` rebakes the chunks the water covers (its background rebakes, `nav_builder.gd`) so the
   dead and the AI path across; the thaw takes the ice away and rebakes again (anyone on it at the thaw
   drops into the water). First research step: how deep water is kept off the nav mesh today. Hard frost
   froze heads stand still already; this only opens the paths. *Verify:* water_test checks: a player walks
   across a frozen pond at walking pace and doesn't swim; an AI routes across a frozen stream where it
   went round in summer; after the thaw it goes round again; rebakes and their time in FrameCost.
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

## Captain's calls (2026-11-21)

- **A. Bare trees and hiding:** yes. Leafless broadleaf woods in winter stop hiding people (trunks and
  conifers still block sight).
- **B. Snow and movement:** yes. Lowland winter snow slows walking by 0.15 (Proposed) and leaves tracks;
  the mountain presets keep 0.25.
- **C. Ice:** everyone walks on it. Players, the dead and the AI cross frozen water, and the nav mesh is
  rebaked at the freeze and the thaw.
- **D. When the look changes:** live, mid-visit. Tint, grass, crowns, snow, ice and leaves blend in place
  when the season turns. Crops, orchards and the mountain snow line are geometry and follow on the next
  zone load (needs Captain's OK on this split).

## Progress

- 2026-11-21: research done, plan drafted.
- 2026-11-21: built (steps 1-7, 9, 10). Suites R2977 (13dcd875's code): smoke, survival, worldsim,
  firsthour (one flake on its silent_kill hint, passed the rerun; clean in R2940), world, water,
  nature, fallenevents, terrain, hands pass; seasons fails only "a spike pit and wire", which fails
  on the base commit too (R2935, a6064f8b). New checks: seasons "The season on the land" (R2937),
  water "Ice" (R2939: the AI crosses a frozen pond 54 m straight where it went 62 m round).
- Step 8, frame time (S2963, summer and winter alternated live in one process, medians of 720
  frames, the machine busy with another game): Kestrel wood GPU 16.85 -> 16.41 ms, farm 5.60 ->
  5.89; wadi_farm wood 19.84 -> 19.12, farm 33.30 -> 33.41. Winter within 5% everywhere (Kestrel's
  farm right at it, +0.29 ms). Separate runs per season (S2941, S2946, S2957) were noise from the
  machine's load and are not a measure.
- Step 9, shots: S2966 (wadi_farm, the start zone: desert_wadi, no water; kestrel_valley for the ice).
- Open for Captain: winter's bare crowns read as pale dotted spheres (frosted more than twiggy);
  the start zone is a desert wadi that now gets full lowland snow (call B said every map).
- 2026-11-21, bare trees (Captain asked): limbs mesh (ZoneScatter._branch_mesh) shown when bare, the
  crown a twig haze. R2990: seasons (only the old spike-pit check fails), forest, smoke, terrain,
  nature pass. Frame time S3002 (alternating, a quiet machine): Kestrel wood GPU 3.70 -> 3.56 ms,
  farm 4.49 -> 4.55; wadi_farm wood 3.35 -> 3.44, farm 3.83 -> 3.88. Shots S2991.
- 2026-11-21: **Captain signed off the four seasons** (shots S2966 and S2991). Still open: the desert
  wadi getting full lowland snow (call B said every map; not raised again at sign-off), the old
  spike-pit check (Cheeno), merging to dev (Captain's go and green CI).
- 2026-11-22: **Captain: keep snow off the desert wadi.** `"lowland_snow": false` on the desert_wadi
  preset (carried into mixed presets from the nearer half); `ZoneTerrain.set_season_look` zeroes
  `season_snow` there, so no white ground, snow slow or snow footsteps. Seasons check "winter on
  desert_wadi" (R3006); R3006: terrain, smoke, survival pass, seasons fails only the old spike-pit check.
- 2026-11-22: Captain: salt flats and badlands too (`"lowland_snow": false`). R3007: terrain, smoke pass;
  seasons fails only the old spike-pit check; its new check finds the three dry presets bare.
