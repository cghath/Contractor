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
4. **Types.** House, shop, warehouse, clinic, police station; the landmarks (below) add an
   office, a mosque, a church, a school, a garage, a fuel station, a factory, a farmhouse and barn,
   a harbour shed, a hangar and control tower, a pump house, a drug lab and an IED workshop. Each
   type has its rooms, its loot (the clinic's treatment room has medical loot, the police station
   an armoury) and its materials. (Until 2026-10-21 this list named an office that didn't exist.)
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
4. **City zones (built, cghath 2026-10-22, queue item 1.5: "City zones" below).** A city of
   street-grid blocks, 2-8 storeys, streamed block by block; the Old Quarter is one.

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

## Landmarks (queue item 1.4, cghath 2026-10-21)

Landmark buildings and sites, each its own `BuildingGen` type with interior chunks, enterable,
navmeshed and garrisoned like the rest, and placed in the zones their asset tags name.

- **Building types** (`BuildingGen.LANDMARK_TYPES`, in `TYPES` with the others), generated as
  any building (rooms by role, doorways, stairs, chunks, loot, a look and skin), with keys of
  their own (all Proposed): `styles` (a church in stone or brick), `h` (a hall's wall height),
  `door_h` (a garage's or hangar's door), `apron` (open lot in front: a forecourt, room for a
  tower or a canopy), `keep_big` (the bigger part of the first split stays one hall: a prayer
  hall, a nave, a factory floor, a hangar), `chunk_area` (a big hall gets a chunk per that many
  m²), `sign`, `extras` (what's built round the shell, `_extras`):
  - **office**: two storeys always, a roof with a parapet, open-plan offices and a meeting room,
    a canopy over its door;
  - **mosque**: a prayer hall with a minbar and mihrab, rugs and shelves, an ablution room, a
    dome (octagonal courses) over the hall, a minaret (a solid shaft, a railed balcony, a cap and
    crescent) in its forecourt clear of the door;
  - **church**: a nave with pews, an altar and a font, a vestry, a hollow gable roof, a bell tower
    over the front door (a porch: doorways through it front and back, belfry arches, a bell, a
    spire and a cross);
  - **school**: classrooms (desks in rows with aisles, a board), offices, often two storeys and a
    walled playground, a flagpole and railings along its forecourt;
  - **garage**: a workshop hall with a wide door, a car on a lift, benches and tyres, a car and
    drums outside;
  - **fuel station**: a kiosk (a shop) behind a forecourt with a canopy on columns, two pump
    islands, a price board and the tanks' fill caps;
  - **factory**: a factory floor (lathes, presses, a conveyor, pallets and racks), offices, a
    chimney stack and a container on its forecourt, a sawtooth roof unless its roof is used;
  - **farmhouse** (house rules) and **barn** (stalls, hay, a cart, a gable roof); **harbour
    shed** (a dock hall with nets, crates, pallets); **hangar** (a light aircraft, tools, a
    curved roof, its doors slid back); **control tower** (two storeys, a console room above,
    a mast and windsock on its roof); **pump house** (pumps, pipes out to its forecourt);
  - **drug lab**: blacked out (no windows), lab benches with glassware, cookers and gas
    cylinders, chemical drums, a packing table; a generator and drums in its yard;
  - **IED workshop**: a bench with wire, phones and batteries, artillery shells, yellow jugs and
    fertiliser sacks; a car being rigged in its yard.
- **Ruined and bombed out** (`building(type, seed, style, RUINED / BOMBED)`, `_ruin`, every type,
  the older ones too): the same building with breaches through its outside walls (scorched
  round), holes in its roof, rubble heaped under them; bombed out, a back corner fallen in
  (everything over it from 0.4-1.2 m up gone, a heap of rubble in it), a two-storey building's
  roof gone and its upper walls broken (its stair up there no longer counts). Its stairs, their
  landings and every doorway's way through are kept: rooms reachable before still are, unless
  the fallen corner buried a doorway (`"buried"`).
- **Sites** (`BuildingGen.site(kind, seed, ruin, turn)`, `SITE_KINDS`): a landmark alone on its
  lot, or several buildings and their props, with garrison posts (inside front doors, up high,
  back rooms, and the site's own), loot by its rooms' tables (`LANDMARK_LOOT`: a lab's hashish, an
  IED workshop's wire and detonators), named points, stair ramps, a footprint, its flat pad and
  the hard standing painted on it (`streets`):
  - **farm**: farmhouse, barn facing the yard, one or two silos, fenced pens with a shelter and
    trough, hay bales, a well;
  - **fuel depot**: three or four storage tanks in a bund (hollow, with decks inside so no room
    in one bakes into the navmesh), a pump house, an overhead pipe rack to a loading gantry with a
    tanker under it, a security fence, gate and guard booth;
  - **harbour** (its sea toward -z, turned to face the zone's): a quay with its concrete face and
    bollards, two piers on piles out `PIER_L` past it with a portal crane on each, two sheds facing
    the quay, the harbourmaster's office, container stacks, a fishing boat moored;
  - **airfield**: a runway (`RUNWAY`, painted on the ground: no voxels), an apron, two hangars, a
    control tower, a light aircraft parked, a windsock, fuel drums, a sandbagged guard post;
  - **oil field**: four or five pumpjacks on gravel pads, flowlines along the ground to a
    separator, two tanks in a bund, a pump house and a site cabin, a flare stack.
- **Module types** (`ZoneModules`): `"lm#<kind>#<seed>#<ruin>#<turn>"`, `base()` its kind. A
  landmark's pad can be its own (`PAD`: a harbour's land, not its piers) and made at a height over
  the sea (`PAD_SEA`, `ZoneTerrain._flatten`), its hard standing is painted on the ground
  (`STREETS`, `ZoneTerrain`), its voxel bounds are its voxels' own (`EXTENT`, `BELOW`).
- **Where** (`data/landmarks.json`, `ZoneModules.landmark_kinds`, `place_landmarks`,
  `place_harbour`, called from `ZoneDef.normalize`; `MissionRegistry.zone_def` gives the def its
  `assets` and `controller`): by asset tag (mosque, harbour, oil, airfield and a fuel depot,
  fields: a farm, route: a fuel station, crossing: a garage, hq: an office), by the holder's own
  site (the Kestrels' and the Syndicate's drug lab, the Banner's and the Shura's IED workshop), a
  few by zone (churches, schools, factories); at most 4 a contract zone, 6 a hot zone, in the
  data's order; 20% ruined and 8% bombed out in contract zones, 35% and 30% in hot zones. Each
  clear of the other modules and the insertion and extraction points, never nearer an edge than
  the zone's sea could come in (its coast stays as it was), with a road to the nearest site. A
  harbour goes on the sea once it's chosen, its quay out in the shallows (`HARBOUR_SHORE`), its
  land built up to 1.6 m over the water, its piers' ends over water. Placed once: a def that has
  them keeps them (normalizing again changes nothing).
- **Upper-floor doorways** (all types, a fix): a doorway on the floor above no longer opens onto
  the stairwell (one did now and then: the room behind it was cut off).
- **Checks**: `tests/landmarks_test.gd` (suite `landmarks`). **Pictures** (headless, its own
  flat-shaded drawing of the boxes, no window): `tests/landmark_shots.tscn`.
- Not yet: mission sites in the landmarks (a raid on the drug lab itself, an HVT in the mosque's
  office: contracts.json "modules" for them), towns with landmark lots, a real control-tower cab
  (a third storey), the runway's markings and lights.

## City zones (phase 4: queue item 1.5, cghath 2026-10-22)

- **Any number of storeys.** `building(type, seed, style, ruin, {"storeys": n})` builds a type
  with an `"upper"` spec n storeys high: a flight up from every floor to the next, each kept off
  the stairwell coming up into its floor and its landing (`_stair`'s `keep`), the walls above on
  the ones below, every floor's rooms its own roles and doorways, and a stair onto the roof. A
  flight that fits nowhere tops the building out there (`"storeys"` says how many it got).
  Buildings made without opts are as they were (checked against the old generator: 880
  buildings, towns and sites the same). City stairs keep `CITY_STAIR_APPROACH` (1.0 m) clear in
  front of their foot (0.5 m, eroded by the agent's radius, left the bake a strip one cell deep:
  whether a stair joined the floor hung on where the bake's 0.25 m grid fell, and a zone's pads
  stand at any height). Every stair's ramp for the navmesh (`ramp_faces`) now has a wedge up onto
  it from the floor and one down off it (`RAMP_FACES` corners a stair).
- **City types** (`CITY_TYPES`): an apartment block (flats on every floor), a tenement (a shop
  under flats) and a tower (offices, the city's landmarks). Clinics, police stations, houses and
  shops stand in cities too; one too small for its stairs gives way to flats, a lot too narrow
  for stairs is left open.
- **The street grid** (`city_layout(seed)`, cheap, no buildings): `CITY_BLOCKS` (5 x 4) blocks
  `CITY_PITCH` (48 m: a multiple of 24, so every block's middle is on the zone's 12 m navigation
  grid) apart, `CITY_STREET_W` (10 m) streets between and round them; the inner blocks are the
  core, the ring the outskirts; `CITY_TOWERS` (2-3) core blocks hold a tower. Its `"streets"`
  (centre lines with widths) and `"junctions"` are the grid's own data, for the roads to pave
  (`ZoneModules.city_streets(def)` in zone metres; F-210).
- **A block** (`city_block(seed, ix, iz)`): a perimeter block, rows of terraced buildings along
  its four streets (`CITY_LOT_GAP` alleys between them, `CITY_OPEN_LOT` of lots left open), fronts
  on the street, backs on a courtyard; storeys by `CITY_CORE_STOREYS` (3-5),
  `CITY_OUTSKIRT_STOREYS` (2-3), `CITY_TOWER_STOREYS` (6-8); types by `CITY_MIX`; a district style
  (`CITY_STYLES`); `CITY_RUINED` (12%) of its buildings ruined (never a tower); street barricades
  and rubble in its half of the streets. What `town()` gives a town (garrison, loot, points,
  civilians, fallback points, a weapons cache, an HVT's and a hostage's rooms), and its pad and
  half streets.
- **Garrisons hold the upper floors** (`_city_finish`, `CITY_POSTS`: 4 a core block, 2 an
  outskirts block, a tower 2 more on its top floor and roof; `CITY_HIGH_SHARE` 70% up high): at
  windows onto the street, the floor spread by building, then a back room upstairs, then inside
  front doors. Every post stands clear with a little to spare (`_clear_margin`).
- **Module types** (`ZoneModules`): `"city#<seed>#<ix>#<iz>"`, one block each, so a city streams
  in block by block; `base()` is `"town"` (missions, people, callsigns and UrbanDefence take a
  block as a town; one relief counterattack for the whole city, `city_of`). Every block's pad is
  the whole city's rect (`PAD`: they flatten to one height), its half streets are painted on it
  (`STREETS`). `has_type` enters its footprint, pad and streets only; its buildings are made the
  first time its boxes are (a zone module's proxy).
- **Urban hot zones** (`ZoneDef.generate_hot(..., urban = true)`): a city (`_place_city`) in
  place of the 3-4 towns, its middle `URBAN_REACH_M` from the HQ and `URBAN_CITY_KEEP_M` clear of
  the other sites, a road from the HQ to its ring street, a patrol round its inner streets, the
  def's `"cities"`. The Old Quarter (`city_hot`) is one, on the `"city"` terrain preset (low
  rolling ground, dusty verges, grey streets, few trees, more litter and ruins).
- **Streaming and performance.** The zone's navmesh bakes up to the tallest module on a chunk
  (`ZoneNav._bounds_of`: a city's upper floors and roofs; it stopped 8 m over the ground). A
  whole city streamed in passed Jolt's 10 240 bodies (each voxel mesh block's collision is one):
  `physics/jolt_physics_3d/limits/max_bodies` is 32 768. A block is generated in 30-230 ms (zone
  load: about 2 s for the city). The `city` suite walks into the Old Quarter at a run and times
  every frame while its blocks stream in (budgets in tests/city_test.gd, Proposed); the AI's
  building scans near tall buildings are the long frames (F-211). Godot's path search stops at
  4096 navmesh polygons, short of a tower's top floors from the street (F-213): the navmesh joins
  them, the suite checks it with a wider search.
- **Checks**: tests/city_test.gd (suite `city`). **Pictures**: tests/city_shots.tscn (headless,
  its own drawing of the boxes: the whole city, a tower block, an outskirts block, the village).

## Village houses (queue item 1.6, cghath 2026-10-22)

The village's four hand-built houses are generated (`BuildingGen.village_house`,
`ZoneModules.VILLAGE_HOUSES`) in village style where they stood: a mud-brick house, a cinder-block
house, a two-room brick house and a plank shack (`VILLAGE_STYLES` "plank": kept out of `STYLES` so
every other building's style pick is as it was), each on its old ground, its front door on the
same side at the same place, single storey, no yard, no roof stair. Rooms, furniture, windows,
a look and a skin of their own; the furniture keeps off the village's garrison posts, loot, named
points, mission sites (contracts.json "village"), site boxes (loot_tables.json) and the world
suite's firing lines (`_village_keep`). The stone yard wall and the shack's weapons cache stay.

## Open (Captain)

- Which building types matter most for missions.
- Towns' and landmarks' stairs keep a 0.5 m approach (F-212): moving them changes those
  buildings (saved damage), so it's left for a call.
