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
clearings; `thicket_share` (default 0.35) of the sites also get a thicket: tall undergrowth that hides a standing
man), `copses_per_km2` (tight clumps of `copse_trees` [min, max], default 10-40), `hedgerows_per_km2` (tree and bush
lines along the edges of a `field_m` field grid, default 120 m), `road_trees` (0..1, the share of the roads' sides
lined), `wadi_groves_per_km2` (clumps of `wadi_grove_trees` on the wadis' banks, `ZoneTerrain.bed_at`), and
`edge_scrub_per_m` (bushes a metre round each wood, copse and grove, default 0.5). `trees_per_km2` is now only the
few lone trees. Caps: trees 5000, thickets 3000, solid 5600. Set as:

| preset | woods | copses | hedgerows | road_trees | wadi groves | lone trees |
| --- | --- | --- | --- | --- | --- | --- |
| temperate | 1.5 | 5 | 4 | 0.4 | - | 12 |
| coastal_lowland (harbour_yard) | 0.8 | 6 | 5 | 0.5 | - | 10 |
| amphibious_coast | 0.4 | 4 | 3 | 0.3 | - | 8 |
| desert_wadi | 0 | 1.5 (6-16 trees) | 0.5 | - | 6 (6-16 trees) | 4 |
| rocky_ridge | 1.0 | 4 | - | - | - | 8 |
| scrubland | 0.3 | 3 | - | - | - | 6 |
| salt_flats | - | - | - | - | - | 0 |

**Caching** ("we'll use caching for performance if needed"): the layout is kept in memory per zone (`CACHE_ZONES`,
4) and on disk (`user://cache/scatter_*.bin`, the newest 24), keyed by everything it comes from (layout version,
seed, preset, ground checksum, pads, roads), so coming back to a zone skips the layout (`cache_source`: "generated",
"memory" or "disk"; `ZoneScatter.clear_cache`). The shapes and material are built once a game; each cell's built
MultiMeshes are kept for the 2 newest zones. Thickets draw with the scrub mesh to 950 m, no shadows. **Far
stand-ins**: past 940 m each 24 m square of trees is one low canopy blob (one MultiMesh per 128 m cell, no shadows),
out to the horizon, built with the visuals (never on a headless server; `far_counts()`).
