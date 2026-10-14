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
