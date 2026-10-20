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
     rescue, intel grab and raids can play in a town; its sites (`ZoneModules.town_sites`)
     come from its buildings: the whole town as the area, its intel spots, an HVT in an office
     or living room, a hostage in the police cells or a bedroom (upstairs too), a weapons cache
     of crates in the police armoury or a store room.
   - Its people: a civilian for every third building, walking front step, street, crossroads
     (`BuildingGen.TOWN_CIVILIAN_EVERY`); loot from `BuildingGen.TOWN_LOOT` by spot table.
   - Urban hot zones (built): `ZoneDef.generate_hot(seed, size, urban = true)`, zone def
     `"urban": true`. 3-4 towns within 900 m of the HQ, 190 m apart (districts of one city), a
     road from the HQ into each, enemy patrols through their streets, 1-2 villages outside. The
     campaign's is "Old Quarter" (`city_hot`, scrubland, Meridian).
   - Measured (agent-tools/city_shots.gd, Old Quarter): a town streams in in under a second;
     the frame it lands in takes 290-350 ms against a village's 190 ms (the garrison spawning
     and the voxel build together). Worth smoothing before city zones (phase 4).
   - Phase 3 made a town 1,100-1,250 boxes; `VoxelWorld` now stamps base structures at most
     `BUILD_BUDGET_MS` (4 ms) a frame instead of all in one frame. A teleport next to a town still
     costs one long frame (about 350 ms, a village about 280): terrain, scatter and the garrison
     arriving together, not the buildings. Walking in, the town builds over 30-40 frames.
3. **Storeys, roofs, L shapes, yards (built, 2026-10-13, Captain approved).** Per type in
   `BuildingGen.TYPES`: the chance of each.
   - Two storeys: the upper walls stand on the ground floor's (load-bearing, and the
     stairwell always lands in one room), the rooms get the type's `"upper"` roles (a house:
     a family room, bedrooms, a bathroom; a shop: a flat; a police station: offices) and
     doorways of their own. A concrete slab (wood in mud-brick) between.
   - Stairs: built from solid steps, 0.23 m rise (the navmesh climbs 0.25), 0.25 m tread, 1 m
     wide, along a wall from a corner, clear of every doorway, 0.8 m landing past the top; the
     stairwell above has a steel railing on its open side and foot. A door entry with
     `"stair": true` links the floors (rooms numbered across floors).
   - Roofs: two-storey buildings always, and some single-storey ones (`"roof"`), get a stair
     up through a railed hatch onto a flat roof with a 0.9 m parapet.
   - L shapes (single storey, no yard behind): a back corner left out; the outside walls are
     traced round whatever shape the rooms make. More than half of them wall the missing
     corner in as a courtyard.
   - Yards: a walled yard behind (4-6.5 m deep, part of the lot), a gate to the side alley,
     furnished from four "yard" chunks (water tank, woodpile, crates, table and benches).
   - Checks (world_test): every room reachable up the stairs, no step over 0.25 m, nothing
     in a stairwell above, a voxel budget per storey; screenshots `agent-tools/phase3_shots.gd`.
   - Not yet, tasks for cghath in the audit (`docs/audits/followups.md` on
     `fix/audit-2026-10-13`): F-01, the AI's building scan (`scripts/ai/buildings.gd`) sees one
     floor, so upper floors and roofs are walkable but not garrisoned or cleared room by room;
     F-02, town garrison posts are all on the ground floor (Captain's side adds upper and
     rooftop posts to `BuildingGen.town` once F-01 lands).
4. **City zones.** A dense-streets terrain preset made of towns, with what it takes to stream
   that many buildings (budgets measured with the session log's performance lines).

## Looks and skin (world visual pass, cghath, 2026-10-20)

- Each building has a look (`BuildingGen._look`, `LOOKS`). Its wall material is one of its style's
  shades, and the trim, plinth, weathering, lintels, shutters, sign and roof go with it. All are
  picked from the seed on a random stream of their own, so rooms, furniture, loot spots and
  garrison posts are as they were.
- The skin (`BuildingGen._skin`, `building().skin`, `town().skin`) is boxes over the outside walls:
  frames, sills, a plinth, rising damp, a cornice or eaves (beam ends on mud brick), corner stones,
  shutters, signs, copings and roof tanks. It is all in the walls' outermost voxels or above
  `PROUD_ABOVE` (2.3 m). It is cut round every doorway and window (`_face_boxes`), so nothing of it
  stands in one.
- Every skin colour is a `VoxelWorld` variant of the material the wall is, or one as hard
  (`VoxelWorld.VARIANT_OF`, `base_mat`): rounds, chips, holes and blasts are unchanged.
- Zone modules stamp the skin after their structure as skin boxes (`ZoneModules.skin`,
  `VoxelWorld.add_box_m(..., skin = true)`). Those boxes are carved like any voxels but kept out
  of the navmesh's boxes, the proxies and the cache-site voxel counts. Hand-built modules get theirs
  from their own boxes (`ZoneModules._dress`: sandbags' bags, HESCO frames, wall plinths and
  copings, crates, drums, tents, the compound's gate).
- Screenshots: `tests/world_shots.tscn` (a compound, outpost, village, HQ and town, the ground,
  props and a wood).

## Open (Captain)

- Replace the village's hand-built houses with generated ones after phase 1, or keep both.
- Which building types matter most for missions.
- How tall buildings get in cities.
