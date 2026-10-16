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

8. **Warzone / war-torn terrain preset** (Captain, 2026-10-16: "warzone maps and some other
   stuff would be good too"): a battle-damaged aesthetic distinct from the clean generated
   zones — craters, rubble, wrecked/burnt-out vehicles, collapsed or shelled structures, downed
   power lines. Overlaps #4's man-made props and #7's trenches; probably its own terrain preset
   (or a `"war_torn": true` layer any preset can take) rather than a whole new generator. "some
   other stuff" — more environment ideas likely to keep landing here as they come up.

9. **Unused enemy vehicle variety — LATER (Captain, 2026-10-16: "unused techs too" (later)).**
   Found: no faction has its own vehicle roster — every hostile faction shares one global pool
   (`data/ground_supports.json` "vehicle_qrf"), which only ever spawns `technical_dshk`/
   `technical`. The five other technical variants (ZU-23-2, SPG-9, M40, Type 63 rockets, ZPU-2 —
   `data/vehicles.json:147-151`) have their own art colour schemes but turned out NOT just
   unwired: their `"gun": {}` override is a shallow replace (`VehicleSpecs.spec`,
   scripts/vehicles/vehicle_specs.gd:63-69 merges top-level keys, not deep), so they currently
   have no weapon at all — none of ZU-23/SPG-9/M40/rockets/ZPU has a real gun entry in
   `data/vehicles.json`'s "guns" dict, and no matching rounds in `data/rounds.json` either.
   Bigger than "wire them in": needs real weapon stats (round, rpm, spread, feed) per variant
   first. Parked for later.

10. **Enemy PMC faction — LATER (Captain, 2026-10-16: "can you make the enemy pmc faction with
    those assets?", then "pmc isnt this run thing", "pmc will be later down").** Found while
    scoping it: `Soldier.faction` is only ever "hostile"/"friendly" — the named factions in
    `data/factions.json` (meridian/black_ridge/salvage_union) are economy/rep-only labels
    (`Contracts.gd`, `MissionRegistry.zone(...).get("faction")`) and never reach AI spawning.
    Every hostile, in every zone, gets the same AKM-pattern kit (`CompoundLevel.HOSTILE_*`,
    compound_level.gd:147-165) and the same vehicle pool — there is no faction-aware kit or
    vehicle selection mechanism to hook into yet. A real PMC faction (Western gear/M4-pattern
    kit, M-ATV/MaxxPro/Bradley/Abrams/Black Hawk/Viper roster — vehicle models aren't
    faction-locked in the data, so this is legitimately doable) needs: (a) a new named faction
    entry, (b) a parallel kit constant block alongside HOSTILE_BODY/HOSTILE_GUNS/HOSTILE_MIX,
    (c) threading the zone's named faction from the contract/hot-zone record into the runtime
    ZoneDef/ZoneLevel (it doesn't flow there today) so garrison/patrol spawns and vehicle_qrf can
    pick a faction-specific profile, (d) a zone actually assigned to it. Real feature, correctly
    sized for its own session — parked for later, not this run.

11. **Helicopters don't crash — they just freeze** (Captain, 2026-10-16, with reference photos of
    real crash sites: scattered wreckage, a snapped-off tail/rotor, impact scarring).
    `Vehicle._become_wreck()` (scripts/vehicles/vehicle.gd:1613) is generic for every vehicle:
    on destruction it goes `FREEZE_MODE_STATIC` right where it was, with two scorch marks — a
    helicopter destroyed mid-flight just hangs there, inert, instead of falling and crashing.
    Needs: unfreeze and let a destroyed heli fall/tumble (maybe a short uncontrolled spin first),
    then on ground impact a real crash wreck — broken-off rotor/tail pieces as separate debris,
    a wider scorch/impact mark, flattened scatter/vegetation around it — distinct from a ground
    vehicle's in-place burnt wreck. Ties into #7 (crash-landing mission entrance: could reuse the
    same wreck art for a pre-placed crashed heli as an infil variant) and the AV-damage bug
    (item 12, the fix/heli-rpg-damage branch) — same vehicle-destruction code, worth doing
    together next time rather than in this session.

12. **Bug/balance: anti-vehicle damage too weak** — Captain, 2026-10-16: "rpgs and such dont do
    enough damage, the infil heli took a hit earlier today and it did almost nothing."
    Investigated in B:/Contractor-avdamage, branch fix/heli-rpg-damage: the damage formula
    itself checks out (a PG-7V's 260 mm penetration vs the UH-60M's 6 mm "aircraft" armour does
    ~150 kJ against its 120 kJ hull — plenty) and `Vehicle.server_take_hit`'s hull-voxel probe
    (can report a shot "missed" if it finds no solid voxel within PROBE_M, 0.4 m — already known
    to happen through an open vehicle bed, `tests/antiarmor_test.gd` `_real_open_bed`) works
    correctly for a direct hit on a *parked* helicopter: added `_real_uh60()` to
    antiarmor_test.gd (zero helicopter antiarmor coverage existed before) firing a PG-7V at the
    fuel cell — it penetrates and hurts the hull as expected (ANTIARMOR TEST PASSED). So the
    reported "did almost nothing" isn't the core formula or probe being broken outright; it's
    likely specific to a scenario a static test can't reproduce — hitting a *moving/flying*
    helicopter (hit-registration timing between the round's recorded position and the aircraft's
    current hull transform) or a hit landing on a thin/open part of the airframe (rotor, open
    cabin) rather than solid fuselage. Needs a repro with the heli actually flying to pin down
    further. Ties into #11 (heli crash wrecks) — same code area.

## Open

- Does #1's patrol/alert system for regular zones get the full `EnemyResponse` feature set
  (QRF, hunters, radio chatter) or a lighter slice sized for a 1.5-2 km contract zone vs a 4 km
  hot zone? Leaning lighter: roads + 1-2 roaming patrols + basic alert-on-contact, no QRF waves
  (those are already a hot-zone thing and a contract zone's garrison is small).
- Trench maps: one hand-authored zone, or a generator? Park until the E-tool groundwork answers
  how trenches get carved.
