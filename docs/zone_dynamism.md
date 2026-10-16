# Environment variety / "missions feel repetitive" (Captain, 2026-10-16)

The Captain: "its boring as all get out tbh after a while because the missions are repetitive."
Mission *types* already vary (`docs/missions.md`, nine of them); the complaint is the
environments don't. Root-caused below; queue at the bottom.

## Root causes found (2026-10-16)

1. **Only 6 zones exist, ever, with fixed seeds.** `data/contracts.json` "zones": `compound_01`,
   `wadi_farm`, `harbour_yard` (contract zones) and `ridge_hot`, `coast_hot`, `city_hot` (hot
   zones). Every contract of every type plays in one of these six, same layout every visit (by
   design, for the persistent world — `ZoneDef.generate(seed, ...)` is deterministic). After a
   few hours you've seen all of them.
2. **Regular contract zones have no roads, no patrols, no alert/escalation.**
   `scripts/world/zone_level.gd:93-107`: `EnemyResponse` (roaming patrols, QRF, hunters),
   `Alert`, `Pressure`, `RadioChatter`, `HotZoneOps` are only added `if def.kind == "hot"`.
   Regular zones get `squad_for("hostile").patrol = []` ("garrisons hold their ground") and
   nothing else — no roads either (`ZoneDef.generate()`, the regular-zone generator, never
   fills `def["roads"]`/`def["patrols"]`; only `generate_hot()` does, scripts/world/zone_def.gd:
   205-238 vs 251-349). This is most of the "no roads or paths enemies patrol" complaint and a
   big share of "boring" (static garrisons, nothing roaming, nothing escalates).
3. **No real campaign zone uses forest terrain.** `temperate` and `forest_experimental` presets
   exist and look good (`docs/terrain_presets.md`), but `forest_experimental` is menu-only
   (Test zones, never on the contract board) and no zone in `contracts.json` uses `temperate`
   either. The campaign has desert_wadi x2, coastal_lowland, rocky_ridge, salt_flats, scrubland —
   zero forest.
4. **No man-made scatter props.** `data/terrain_presets.json` scatter is all-natural (rocks,
   scrub, trees, tufts, pebbles, copses/woods/groves). No crates, barrels, wrecked vehicles,
   fencing, abandoned equipment, battle damage debris outside hand-built modules.
5. **No visible tracers / bullets.** Hitscan only (`Ballistics.fire` + `Soldier._server_fire`,
   scripts/actors/soldier.gd:823-857). `Sfx.server_shot(origin, round_end, kind)` already
   broadcasts start/end points to every peer for the shot sound — a tracer effect can ride that
   same call, client-side only, no new RPC needed.

## Queue, in priority order

1. **Roads + roaming patrols for regular contract zones** (not just hot zones): generalize
   `ZoneDef.generate()` to lay roads between modules and emit `patrols` like `generate_hot()`
   does (scripts/world/zone_def.gd:281-325 is the pattern to reuse/adapt); wire a scoped
   `EnemyResponse` (or the roaming-patrol slice of it) into non-hot `ZoneLevel._ready()`. This is
   the architectural fix underneath #2 and #3 of the Captain's complaints (dynamism, roads/
   patrols) — IN PROGRESS (B:/Contractor-zonedyn, branch feat/zone-dynamism).
2. **A real forest zone in the campaign**, once roads exist to run through it: add a
   `contracts.json` zone on `temperate` (or a toned-down `forest_experimental`), sized and
   populated like the others.
3. **Zone rotation**: more generated layouts (varied seed/type-mix/terrain) instead of the fixed
   6, so contracts stop returning to the same geography. Mechanical once #1 is solid.
4. **Terrain man-made props**: crates, barrels, wrecked/abandoned vehicles, fencing, debris —
   new scatter categories in `terrain_presets.json` + `ZoneScatter`, by preset/region (Captain,
   2026-10-16: "the terrains need more objects too").
5. **Tracers / visible bullets**: client-side effect off the existing `Sfx.server_shot` call;
   self-contained, no new network wiring.
6. **Entrenching tool — diggable fighting positions** (Captain, 2026-10-16): an E-tool item that
   digs a fighting position/foxhole into the terrain; the dug earth/spoil takes the colour of
   whatever ground it came from (desert dirt looks like desert dirt, not one generic brown).
   Needs: a dig action/animation, a voxel carve into the terrain mesh (or a pre-shaped pit
   stamped in, like a pad), a spoil-pile prop coloured from the terrain's own palette at that
   point (`ZoneTerrain` ground colour lookup already exists for the shader — reuse it), save/
   persistence if the zone keeps it.
7. **Trench maps** (Captain, 2026-10-16, "wait also trench maps"): a zone/terrain preset built
   around WWI-style trench lines — needs design (static trench network like a module, or
   player/AI-dug via the E-tool above scaled up, or both). Not scoped yet.

## Open

- Does #1's patrol/alert system for regular zones get the full `EnemyResponse` feature set
  (QRF, hunters, radio chatter) or a lighter slice sized for a 1.5-2 km contract zone vs a 4 km
  hot zone? Leaning lighter: roads + 1-2 roaming patrols + basic alert-on-contact, no QRF waves
  (those are already a hot-zone thing and a contract zone's garrison is small).
- Trench maps: one hand-authored zone, or a generator? Park until the E-tool groundwork answers
  how trenches get carved.
