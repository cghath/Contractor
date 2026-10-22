# Terrain presets

Zones are generated from presets in `data/terrain_presets.json` (`TerrainPresets`, `ZoneTerrain`, `ZoneScatter`).
A preset sets the land shape (relief scale, wavelength, octaves, ridge, flatten, wadis), the sea, the ground
palette and the scatter (rocks, scrub, trees per km2 of zone, so bigger zones get more, with caps).

**Which preset a zone gets** (`ZoneDef.normalize`, so it is in the def the host sends): the def's `terrain`,
else the first `name_hints` word in the zone's name, else `region_defaults[region]`, else `default`.
Coast -> coastal_lowland, inland -> desert_wadi; Salt flats -> salt_flats; Black Ridge hills -> rocky_ridge; Kestrel Valley -> river_valley;
Wadi farm -> desert_wadi. The test zone is `plain` (no scatter).

**Sea**: a preset with `sea` gets a shoreline on one side picked by the seed, never a side holding a pad
(`def.sea_side`, `def.sea_m`). Ground deeper than 0.9 m under the water is left out of navigation.

**Water** (queue item 1.1, `ZoneWater` in `scripts/world/zone_water.gd`, `ZoneBridges`, `Wading`): a preset's
`water` carves rivers, streams, lakes and ponds into the heightmap once the pads are flat, from the seed only (every
peer builds the same). Every key is optional (defaults in `ZoneWater`'s `*_DEFAULTS`, all Proposed):
- `rivers`: `count`, `width_m` [min, max], `depth_m`, `bank_h_m`, `bank_w_m`, `valley_m` (its surface under the
  ground along it), `valley_w_m` (the valley blends back into the land over this), `meander_m`,
  `meander_wavelength_m`, `grade` (the least fall a metre), `drop_max_m`, `flow_ms`, `reeds` (clumps a metre of
  bank). Edge to edge, kept `PAD_CLEAR_M` past its banks off every pad, flowing downhill from its higher end.
- `streams`: the same keys plus `length_m` [min, max]: from a seeded spring downhill into the river (or a lake, or
  off the edge), joining at its level.
- `lakes`, `ponds`: `count`, `radius_m`, `depth_m`, `bank_h_m`, `bank_w_m`, `valley_w_m`, `reeds`. A wobbly bowl
  whose level is its lowest rim, clear of pads, roads, rivers and each other.
- `crossing_gap_m` (450), `bridges` {"concrete", "truss"} weights, `culvert_share` (0.65), `footbridge_share`
  (0.5): every road over a river gets a vehicle bridge, a road over a stream a culvert or ford, and the river a ford
  or footbridge in every `crossing_gap_m` without a crossing (`ZoneBridges`: collision, the AI's navigation over
  them, spans a big blast drops, saved with the zone).
Ground deeper than `ZoneWater.NAV_WATER_M` (0.9 m) under the water is out of the navigation mesh; wading slows a man
and deeper than 1.45 m he swims (`Wading`). On river_valley (the river, 1-2 streams, 1-2 ponds), temperate (a stream
and ponds, sometimes), highland_moor (burns, a tarn), coastal_lowland and scrubland (ponds). "procedural" takes
`water` whole from the nearer of its two presets, like `sea` and `wadi`. A zone def's `"no_water": true` leaves it
out (checks).

**Scatter**: deterministic from the seed; never on pads, roads, in water or on steep ground. Large rocks and
trunks have collision and are baked into navigation; scrub is visual only. Visuals build nearest cells first.
Trees and scrub are low-poly octagonal tiers like the soldiers; a tree is a broadleaf or a conifer, the
preset's scatter `conifer_share` (0..1, default 0.2) of them conifers, picked by where each stands.

**Adding one**: add an entry under `presets`, then name it from a zone (`"terrain"`) or a hint/region default.
Test it in `tests/world_test.gd` (`_test_presets` runs every preset).

**Ground look** (art/terrain-look, 2026-10-14): the ground draws with `scripts/world/zone_ground.gdshader`, the vertex
palette broken up in world space (macro dry/gravel patches, mid patches, fine grain near the camera), per-pixel rock
on steep faces and part-faceted normals (`facet_share`), all procedural. **Ground cover**: a preset's scatter
`tufts_per_km2` (grass tufts, colours `colours.tuft`, else the scrub's) and `pebbles_per_km2` are visual only: laid
out per cell when it builds, from the cell and the seed, not in `items`, no collision, no effect on sight or the
checksum; seen out to 140 m / 90 m. Set on desert_wadi and coastal_lowland (the co-op soak's zones). The zone's sky:
a lower warm sun, a blue procedural sky, lighter haze with aerial perspective, ACES tonemap (ZoneLevel).
Round 2 (same day): `rock_clusters_per_km2` adds visual-only clusters of 3-7 half-buried stones under a metre (seen out
to 420 m); pebbles on; more scrub on the soak presets (desert_wadi 600/km2, coastal_lowland and amphibious_coast
750/km2; scrub is visual but counts for sight through foliage). ZoneLevel adds a weak shadowless "SkyFill" light from
the sun's far side (GameSettings.apply_sun leaves it alone), so rock and crown shade sides read; the sky's lower half
is haze-coloured (no dark band past the far plane) and the sea is a lighter blue-teal. Land heights are unchanged.
Round 3 (build 2): **relief**: land `detail_m` / `detail_wavelength_m` add gentle swells (desert_wadi 3.2 m over 150 m,
coastal_lowland 2.4 m over 190 m) and wadi `berm_m` a low ridge along each bank top (2 m); pads still flatten after
(heights only change where nothing is built), steepest ground wadi_farm 18.9 -> 23.3 degrees, harbour_yard 7.9 -> 8.4.
**Coast**: sea `coast_wobble_m` (coastal_lowland 70, capped at 0.45 x sea_m) pushes the shoreline out up to that and
inland at most `ZoneTerrain.COAST_IN_M` (35 m; pads keep ZoneDef.SEA_PAD_KEEP_M, 60 m, clear); low land near the
sea rises out of it along that profile, so the shoreline is the coast's, not the water plane's straight inner edge.
The beach is a band along the measured shoreline (`shore_distance`). The sea strip's water carries on past the zone's
two sides, and the apron (ground past the edge) now faces up: it was culled, leaving a void past the edge.
**Cover**: scatter `scrub_size` [min, max] (default 0.6-1.5); desert_wadi (600/km2) and coastal_lowland (750/km2) at
0.7-1.7, scrub seen out to 550 m (was 400).
Round 4 (Captain, 2026-10-14: "we need copses and groves and such. the terrain is too empty"): **trees grow in
clusters** (`ZoneScatter._lay_out_trees`), each optional in a preset's scatter, per km2 of zone: `woods_per_km2`
(ragged woods `wood_radius_m` [min, max] across, default 50-130, trees `wood_spacing_m` apart, default 6.5, with
clearings; `thicket_share` (default 0.5) of the sites also get a thicket: tall undergrowth, 1.8-2.5 m, that hides a
standing man), `copses_per_km2` (tight clumps of `copse_trees` [min, max], default 10-40, 20-60 with `copse_cover`; see Copses as cover below), `hedgerows_per_km2` (tree and bush
lines along the edges of a `field_m` field grid, default 120 m), `road_trees` (0..1, the share of the roads' sides
lined), `wadi_groves_per_km2` (clumps of `wadi_grove_trees` on the wadis' banks, `ZoneTerrain.bed_at`), and
`edge_scrub_per_m` (bushes a metre round each wood, copse and grove, default 0.5). `trees_per_km2` is now only the
few lone trees. Caps: trees 5000 (woods at most 60% of it, woods with copses and groves 82%, so a 16 km2 zone's woods leave
trees for its copses, hedgerows and roadsides), thickets 5000, solid 5600; a `copse_cover` preset: trees 6000 (50% / 80%),
thickets 8000, solid 6800. Set as:

| preset | woods | copses | hedgerows | road_trees | wadi groves | lone trees |
| --- | --- | --- | --- | --- | --- | --- |
| temperate | 1.5 | 5 | 4 | 0.4 | - | 12 |
| forest_experimental (copse_cover) | 2.4 (70-170 m, thicket_share 0.35) | 6 (24-60 trees) | 2 | 0.6 | - | 16 |
| coastal_lowland (harbour_yard) | 0.8 | 6 | 5 | 0.5 | - | 10 |
| amphibious_coast | 0.4 | 4 | 3 | 0.3 | - | 8 |
| desert_wadi | 0 | 1.5 (6-16 trees) | 0.5 | - | 6 (6-16 trees) | 4 |
| rocky_ridge | 1.0 | 4 | - | - | - | 8 |
| scrubland | 0.3 | 3 | - | - | - | 6 |
| salt_flats | - | - | - | - | - | 0 |

**Copses as cover** (Captain, 2026-10-14, playtesting v0.4.0: "the copses of trees are too small and spread out to be
cover", "but they look fantastic": the trees' look is unchanged). EXPERIMENTAL, only in a preset whose scatter says
`"copse_cover": true` (forest_experimental, the main menu's "Host Experimental forest (dense woods, test)"; Captain,
2026-10-14: "include experimental forest mission like we dev'd", "make it a button on the menu, not a regular
mission"). Every other preset keeps round 4's copses and caps (the normal zones' woods have a perf problem; a perf pass
is queued). Fewer but bigger, denser copses (Proposed numbers, `ZoneScatter._copse`, layout version 7): 20-60 trees in a compact blob of radius `COPSE_SPREAD` (1.9) x sqrt(trees) + 2 m
(20 trees ~10.5 m, 60 ~16.7 m; round 4: 2.3 sqrt(n) + 3), trees ~3.2 m from the nearest (round 4: ~3.7);
`copse_thicket_share` (default 0.9) thickets a tree inside (round 4: one per two trees); a skirt of thickets every
`COPSE_SKIRT_M` (2.2 m) round the edge, the edge scrub outside it; 1-3 big solid rocks inside (`COPSE_ROCKS`) as low
cover. Wadi groves are built the same way. Woods get an edge belt: a thicket every `WOOD_BELT_M` (3.5 m) just inside
their ragged edge. Measured on hot zone 4409 on art/denser-copses, where every preset had it (fewer copses a km2 there) (eye-height lines, 1.6 m; hidden = `Spotting.FOLIAGE_OPAQUE_M` or more):

| preset | copses (before -> after) | trees a copse | lines through the middle blocked | man at the middle hidden from 50 m |
| --- | --- | --- | --- | --- |
| temperate | 59 -> 51 | 22 -> 37 | 68% -> 100% | 43% -> 98% |
| coastal_lowland | 76 -> 43 | 26 -> 40 | 71% -> 98% | 46% -> 93% |
| amphibious_coast | 52 -> 29 | 23 -> 37 | 65% -> 93% | 42% -> 85% |
| rocky_ridge | 67 -> 42 | 23 -> 38 | 72% -> 99% | 46% -> 97% |
| scrubland | 50 -> 33 | 27 -> 38 | 75% -> 100% | 50% -> 97% |
| desert_wadi | 124 -> 17 (copses alone; groves were counted before) | 11 -> 18 | 56% -> 97% | 33% -> 92% |

**Caching** ("we'll use caching for performance if needed"): the layout is kept in memory per zone (`CACHE_ZONES`,
4) and on disk (`user://cache/scatter_*.bin`, the newest 24), keyed by everything it comes from (layout version,
seed, preset, ground checksum, pads, roads), so coming back to a zone skips the layout (`cache_source`: "generated",
"memory" or "disk"; `ZoneScatter.clear_cache`). The shapes and material are built once a game; each cell's built
MultiMeshes are kept for the 2 newest zones. Thickets draw with the scrub mesh to 950 m, no shadows. **Far
stand-ins**: past 940 m each 24 m square of trees is one low canopy blob (one MultiMesh per 128 m cell, no shadows),
out to the horizon, built with the visuals (never on a headless server; `far_counts()`).

**Salt flats** (Captain, 2026-10-14, v0.3.1, first person on an HVT capture: "this terrain is an actual eye sore": a
near-white pan, brighter than the sky, meeting it at a hard line with nothing on it). Numbers Proposed; judged in the
next build (no windowed look was possible while the Captain was playing).
- **Ground**: palette crust `9a9587` / dry `a39e90` (sRGB ~0.59-0.62, was `cfc9b4` / `b9b095`), mud `7d7464`, damp
  channels `8a8577`. `ZoneLevel.ground_glare` (lit flat ground against the horizon sky, linear luminance) is 0.68, was
  1.38: the pan no longer outshines the sky. The shader's preset `ground` switches: `damp` (darker patches ~350 m and
  ~70 m), `crust` (a warped hex grid of crust plates ~1.8 m with lighter raised rims, faded out 30-75 m from the
  camera), `tracks` (5 long tyre tracks of two ruts each, seen to ~320 m); `mud_margin_m` (300) darkens the ground
  toward the edge. All 0 on the other presets, so they look as before.
- **Relief**: land `detail_m` 0.9 over 240 m (swells), `wadi` 3 shallow channels (0.7 m deep, 24 m wide, damp-coloured),
  and land `margin` (new, `ZoneTerrain`): in a 420 m band inside the edge a 3.5 m berm and flat-topped two-tier mesas
  6-15 m high (noise over 150 m), rising from 25 m in so the apron stays level, kept 110 m (+60 m blend) off every pad
  and road. `ground.rock_above_m` 5 paints the mesa tops rock; their sides are rock from the shader's slope.
- **Scatter**: rocks 40, scrub (dead bushes, 0.5-1.3 m, grey-browns) 160, rock clusters 60, pebbles 3000 per km2, but
  only where `ZoneScatter._open_weight` allows: within scatter `margin_m` (380 m) of the edge, fading over
  `margin_fade_m` (220 m), and within `near_pad_m` (110 m) of a pad or `near_road_m` (35 m) of a road. The pan's middle
  stays bare (open for spotting); the tries scale up by the share of the zone that has scatter.
- **Light**: the preset's `sky` (any preset can have one; `ZoneLevel.sky_for`): sun 1.05 (was 1.25), fill 0.3, exposure
  0.92 (was 1.05), a warm haze `c2bfb5` as horizon and fog colour, fog 0.00045 (64% clear at 1 km), so the far pan
  fades into the horizon instead of ending in a hard white line. The preset's `backdrop` swaps the procedural sky for
  `zone_sky.gdshader`: the same gradient and sun plus two bands of low-poly ridges and mesas round the horizon (near
  0.25-1.1 degrees, far 0.6-2.4, `8a8478` mixed into the haze), seeded by the zone; part of the sky, so never clipped
  and nearly free.

**Open terrain fill and world loot** (Captain, 2026-10-16, playtest B1399 on Red Mesa, `rocky_ridge`: "open terrain
reads nearly empty", "nothing to loot out in the world"; a general problem across most maps, not just the desert
example): three related fixes, layout version 8.
- **Ruins and wrecks**: `ruins_per_km2` places bigger, rougher `Kind.PROP` clutter (`RUIN_SIZE_LO`-`RUIN_SIZE_HI`, 1.2-3.0 m,
  colours `colours.ruin`, else a rust/concrete default) out in the open terrain, placed like the rocks are (anywhere
  open, away from pads and roads, no "near a road" requirement) — unlike the roadside crates (`props_per_km2`,
  `props_near_m`), which keep their own gating. Both share `CAP_PROPS` (1000, up from 600).
- **Ground cover filled in**: `temperate`, `rocky_ridge` and `scrubland` had no `tufts_per_km2` / `pebbles_per_km2` /
  `rock_clusters_per_km2` at all (only `coastal_lowland`, `amphibious_coast`, `desert_wadi` and `salt_flats` did) —
  a big share of "feels empty", since those are visual-only and laid out everywhere, not just at the margins. All
  four (plus `forest_experimental`) now have modest values; `rocky_ridge` gets the most rock clusters (it's a ridge).
- **Valuable sites**: `valuables_per_km2` places a new placement-only kind, `Kind.VALUABLE` (no mesh — `ZoneScatter`
  only marks where), well clear of a site or a road (`VALUABLE_AVOID_M`, 70 m, more than the bare pad/road keep-out).
  `ZoneScatter.valuable_sites()` hands the marked spots to `WorldValuables` (`scripts/world/world_valuables.gd`),
  which spawns the real pickups the first time a zone hosts (`ZoneLevel._on_hosted`): a dead drop (one piece of cash
  or intel) or a small wreck/cache (a weapon, its mags, a medical or salvage item), rolled deterministically per
  site. Ordinary `WorldItem`s with a stable uid, so they drop into the existing flow — `GameState.is_looted` keeps a
  taken one from respawning, selling one feeds `Prices`, and carrying intel out already trips `IntelReveal`.
- Both `ruins_per_km2` and `valuables_per_km2` are capped sparse (`CAP_PROPS`, `CAP_VALUABLES` 40) and set on every
  preset except `plain` (the empty test zone, left alone).

**Terrain features and the marsh, snow and farmland presets** (queue item 1.3, `ZoneFeatures` in
`scripts/world/zone_features.gd`, `Season`): a preset's `features` are planned once the pads are flat and carved
into the heights after the water (kept off its water and banks: a stream cuts a notch through a cliff), from the seed
and the season only (every peer builds the same; the season is in the def,
`Season.of_day` of the campaign day, 30 days each from spring, put there by the host when it switches to a zone; a def
without one is summer). Every part is optional, its keys default in `ZoneFeatures`' `*_DEFAULTS` (all Proposed):
- `gullies`, `ditches`: `count` [min, max], `depth_m`, `half_m` (the sides reach this far from the middle), `floor_m`
  (the flat floor's half width), `length_m`, `meander`. Seeded lines leaning downhill, kept `LINE_PAD_GAP_M` (30 m) off
  pads and apart from each other and the cliffs, faded out at roads, the edge and their ends. Gullies 2-2.8 m deep hide
  a prone man (and mostly a crouched one) from the flat round them; ditches 1.2-1.5 m a prone one. They're the
  heightmap, so the AI's rays (spotting, `SquadAI.find_cover`'s cover and folds) see them as cover.
- `cliffs`: `count`, `height_m`, `length_m`, `plateau_m` (the ledge), `back_m` (the ground eases back down over this),
  `talus_per_m` (fallen rocks at the foot, ZoneScatter rocks). An escarpment whose face crosses one 4 m cell (60-79
  degrees: no walking, driving or navigation up it; the shader draws it as layered rock), its high side where the ground
  already rises, tapering out over 45 m at each end, kept 60 m off pads, a ramp where a road crosses it.
- `marsh`: `share` (of the ground soft), `slow` (the pace lost on the softest: 0.35), `wavelength_m`, `reeds` (reed
  beds over the soft ground), `reed_h_m`, `colour` (the mud). Slows a man on foot (`Wading.ground_mult`, the water's
  movement hook), not on roads or pads; reed beds hide (`cover_least`, added in `ZoneScatter.foliage_least`).
- `snow`: `cover`, `line_m` (the snow line per season: winter covers everything), `slow` (0.25), `colour`, `drifts`
  (bare patches where the wind takes it). Off steep rock; the ground shader's `snow_strength` turns grass clumps back to
  snow. The roads, tracks and pads are packed (no slowing). Water parts with `"frozen": true` are ice on their bed:
  walked on, not waded (`ZoneWater._ice`).
- `fields`: `share` (of the ground farmed), `size_m`, `lane_m` (the verge between fields), `orchard_share` and
  `orchards_max`, `crops` (weights of wheat, maize, vegetables, fallow: their colour, height and cover by season in
  `ZoneFeatures.CROPS`), `hedges` (share of field sides with a hedge: bushes and a tree every sixth), `channels` (share
  of the grid's column edges with irrigation channels: the water's `"channels"` part carves them, `ZoneWater.add_line`),
  `channel_m`. A turned grid with each column's rows staggered, never within 6 m of a pad (a landmark farm keeps its
  yard), off water and slopes over 16 degrees. ZoneScatter keeps its own rocks, trees and ground cover off the fields
  (`keeps_clear`) and lays the orchards, hedges and talus through `ZoneFeatures.lay_out`. Crops stand near the camera
  as blocks in rows (maize with lanes); ripe wheat hides a prone man, maize a standing one.

| preset | features | water | campaign zone |
| --- | --- | --- | --- |
| marsh | soft ground (60%), reed beds, ditches 2-4 | 16-24 shallow ponds, 1-2 pools, 1-2 sluggish streams | Blackwater Fen (inland) |
| snow_mountain | snow (line: winter all, spring -6 m, summer 6 m, autumn -2 m), cliffs 2-4 (10-18 m), gullies 2-3 | 2-3 frozen streams, 1-3 frozen ponds | Whitecap Pass (inland) |
| farmland | fields (80%, 70-150 m), orchards (12%, at most 6), hedges, ditches 1-3 | irrigation channels (12% of the column edges), 1-2 ponds, a stream sometimes | Harrow Fields (inland) |
| rocky_ridge | cliffs 2-3 (8-16 m), gullies 1-2 | - | Red Mesa, Black Ridge hills |
| highland_moor, badlands | cliffs 1-2 / 1-3 (6-12 m), gullies 1-3 / 3-5 | as before | |
| temperate, scrubland, desert_wadi | gullies 1-3 / 2-4 / 2-4 (temperate: ditches 0-2) | as before | |
| river_valley, coastal_lowland | ditches 1-3 / 1-2 | as before | |

"procedural" mixes take the new presets too, and their `features` part by part (the nearer preset's part where both
have one); frozen water only where the mix has snow. Name hints: marsh, swamp, fen, bog -> marsh; snow, winter, glacier
-> snow_mountain; farmland, fields -> farmland. Checked by `tests/terrain_test.gd` (the `terrain` suite); pictures of
each preset, headless, by `tests/terrain_shots.tscn` (to %TEMP%\contractor_world_shots).
