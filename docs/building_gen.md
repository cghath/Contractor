# Procedural buildings (Captain, 2026-10-13)

Buildings are generated, not hand-placed: a shell from a footprint, rooms laid out by rules for
the building's type, and each room furnished from a library of preset interior chunks picked to
suit it. Captain's side; see `docs/build_plan.md` ("Procedural buildings") for where it sits.

## Why it fits the build

- A module's structures are already lists of voxel boxes, `[lo, hi, material]`
  (`ZoneModules._room` and friends). The generator outputs the same, so destruction, materials,
  streaming, proxies and zone saves work unchanged.
- The AI finds buildings by probing what stands in the world (`Buildings`: rooms, entrances,
  firing ports), not from a list, so generated buildings are garrisoned and cleared as they are.

## How a building is made

1. **Shell.** A footprint sized for the building's type and lot; outer walls, a floor per
   storey, a roof. Wall, floor and roof materials by region and terrain preset (mud brick in
   the desert, brick and concrete in temperate zones, cinder block and sheet metal for poor
   quarters), from the 18 regional materials already in.
2. **Rooms.** The footprint is split into rooms by the type's rules: which rooms it must have,
   which it may, how big, and which go next to which (a house: living room, kitchen, bedrooms,
   a bathroom off the hall; a shop: the shopfront on the street, a storeroom and an office
   behind). Doors join every room to the rest (a spanning tree, plus a loop now and then so
   it can be cleared two ways); outside doors on the street side and one more; windows on outer
   walls only, by room (none in a bathroom's or an armoury's outer wall).
3. **Interior chunks.** Each room gets a preset interior from a data library
   (`data/building_chunks.json`, planned): furniture as boxes in the room's own coordinates, with
   the room roles and sizes it fits, the clearance it needs in front of doors and windows, loot
   points (by loot table), cover and spots for the AI. Picked by seed among those that fit; a
   chunk can be mirrored or turned to fit the room's doors.
4. **Types.** House, shop, warehouse, clinic, police station, office; later a mosque or church,
   a school, a garage. Each type has its rooms, its loot (the clinic's treatment room has medical
   loot, the police station an armoury) and its materials.
5. **Seeded.** The zone's seed and the lot give the same building every visit: saved damage and
   looting depend on it.

## Phases

1. **Houses (built, 2026-10-13: `BuildingGen.house`, 14 chunks).** Single-storey houses with about 8 interior chunks (living room, kitchen, two
   bedrooms, bathroom, hall, storeroom, courtyard). Checks: every room reachable, no door
   blocked by furniture, the same building from the same seed, `Buildings` finds the rooms and
   entrances, under a voxel budget. Screenshots. Generated houses then stand alongside the
   hand-built village houses (Captain decides on replacing them after a look).
2. **More types and a town module.** Shops, warehouses, clinic, police station; a "town" module:
   a small street grid of lots (12 to 20 buildings), placed in zones like a village, roads into
   it from the zone's road network.
   **Towns in zones (built, 2026-10-13, Captain "both, and urban hot zones too").** A module
   type "town#<seed>" (`ZoneModules.base` gives "town" for mission data, callsigns, dress):
   - Hot zones: one of `ZoneDef.HOT_VILLAGES` is a town (`HOT_TOWNS`), seed from the zone's.
     Patrols leave towns alone, like villages. Radio callsign "Town 1".
   - Contract zones: a "town" in a zone's `types` (Harbour yard has one). HVT capture, hostage
     rescue and intel grab can play in a town; its sites (`ZoneModules.town_sites`) come from
     its buildings: the whole town as the area, its intel spots, an HVT in an office or living
     room, a hostage in the police cells or a store room. No weapons-cache site yet (raids
     skip towns), since cache counting is on cg's audit list.
   - Its people: a civilian for every third building, walking front step, street, crossroads
     (`BuildingGen.TOWN_CIVILIAN_EVERY`); loot from `BuildingGen.TOWN_LOOT` by spot table.
   - Urban hot zones (built): `ZoneDef.generate_hot(seed, size, urban = true)`, zone def
     `"urban": true`. 3-4 towns within 900 m of the HQ, 190 m apart (districts of one city), a
     road from the HQ into each, enemy patrols through their streets, 1-2 villages outside. The
     campaign's is "Old Quarter" (`city_hot`, scrubland, Meridian).
   - Measured (agent-tools/city_shots.gd, Old Quarter): a town streams in in under a second;
     the frame it lands in takes 290-350 ms against a village's 190 ms (the garrison spawning
     and the voxel build together). Worth smoothing before city zones (phase 4).
   - Next: storeys.
3. **Storeys.** Multi-storey buildings: stair chunks, upper floors, rooftops the AI can use.
4. **City zones.** A dense-streets terrain preset made of towns, with what it takes to stream
   that many buildings (budgets measured with the session log's performance lines).

## Open (Captain)

- Replace the village's hand-built houses with generated ones after phase 1, or keep both.
- Which building types matter most for missions.
- How tall buildings get in cities.
