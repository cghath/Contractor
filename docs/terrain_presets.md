# Terrain presets

Zones are generated from presets in `data/terrain_presets.json` (`TerrainPresets`, `ZoneTerrain`, `ZoneScatter`).
A preset sets the land shape (relief scale, wavelength, octaves, ridge, flatten, wadis), the sea, the ground
palette and the scatter (rocks, scrub, trees per km2 of zone, so bigger zones get more, with caps).

**Which preset a zone gets** (`ZoneDef.normalize`, so it is in the def the host sends): the def's `terrain`,
else the first `name_hints` word in the zone's name, else `region_defaults[region]`, else `default`.
Coast -> coastal_lowland, inland -> desert_wadi; Salt flats -> salt_flats; Black Ridge hills -> rocky_ridge;
Wadi farm -> desert_wadi. The test zone is `plain` (no scatter).

**Sea**: a preset with `sea` gets a shoreline on one side picked by the seed, never a side holding a pad
(`def.sea_side`, `def.sea_m`). Ground deeper than 0.9 m under the water is left out of navigation.

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
