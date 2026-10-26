# Contractor: Fallen — building, the settlement's work and infrastructure

## Where the build is (2026-10-26 ~03:00 CDT)

Phase B's free building (§1-4, §10-11's building part) built on `claude/survival-building`
(worktree `B:\Contractor\.claude\worktrees\survival-building`), building suite R2638 PASS (survival PASS):
- `scripts/survival/`: `BuildPieces` (the catalogue: six materials, six shapes, twelve pieces, tools,
  costs), `Builder` (the host's authority: blocks as sites that fill with work, blueprints, upgrade in
  place, dismantle 60%, repair, damage, chewing, doors and locks, saves, late joiners), `BuildVoxels`
  (a 16 m `VoxelWorld` chunk replaying its edit log: "bset"/"bclr" beside shots and blasts),
  `BuildIntegrity` (load and span on a worker thread; cracks, falls, debris), `BuildPiece` (a piece's
  node and its interaction menu), `BuildMode` (the owner's ghost, key 6).
- Hooks: `ZoneLevel` (_add_builder, _restore_builds, _blast_builds, _breach_builds), `GameState.builds`
  (the zone save's "builds"), `PlayerInput` (BuildMode.handle, no firing while building), `Controls`
  (build_mode on 6). Items: planks, scrap_sheet, sandbag, brick, concrete_bag, steel_beam; hammer,
  saw, trowel, shovel, cutting_torch; door_key. Some in the "stores" loot table.
- Not yet: materials from felling and stripping (a dev kit: build mode with dev tools on), templates
  of blueprints, arches and the wall shape, pieces as structural support, stash storage, ladder
  climbing, the workbench's crafting, weather wear (§3), the
  settlement (§5-9), the "settlement" perfcase, collapses hurting whoever's under them,
  ZombieAI calling `Builder.server_chew_at`.

### The settlement's work and the council (§5-7), first form (2026-10-26, R2649 PASS (settlement, survival, fallenpeople, building))

Built on `claude/survival-settlement` (worktree `B:\Contractor\.claude\worktrees\survival-settlement`),
settlement suite `tests/settlement_test.gd` (R2649 PASS (settlement, survival, fallenpeople, building) with survival):
- `Settlement` (`scripts/survival/settlement.gd`, a node "Settlement" in the zone played, installed by
  `Survival.server_level_ready`): the record in `Survival.state()["settlement"]` (zone, pos, radius 40 m,
  stores by stash/pile piece id plus the "yard", orders, council, the cached beds/defence/footprint/
  stations), members, stocks by category with trends, beds, defence, `footprint()` (call 90's input),
  morale, size cap (min of 24, beds, food for 3 days), the settlers' hour (schedule, meals and drinks
  from the stores, the night watch rota, moodlets for jobs liked/hated and too long a watch),
  `server_guard_check` (a guard calls out the dead chasing within 60 m and wakes every sleeper),
  settler bodies at home, stow/take for players, the screen's view and actions over RPC.
- `SettlementJobs` (the twelve jobs, an hour each), `WorkOrders` (orders, claims, the planning view),
  `Council` (`server_put`, `server_choose`, `server_resolve`, factions, influence, standing, the
  challenge), `SettlementScreen` (key [), `SoloPause` (call 138).
- Hooks: `Builder.server_work_from_stock`, `server_work_piece_from_stock`, `server_repair_from_stock`,
  `worked_by_player`, `pieces_of`, `piece_pos`; `BuildPieces` pile, stove, lookout, farm_bed, generator,
  lamp; `SurvivorsLayer.server_settle`, `server_settler_body`, `server_take_along`; `TalkMenu` ("Make a
  settler", "Take along", a place want settles when a bed is free); `SurvivalSleep` wait functions
  (`is_waiting`, `start_wait`, `wait_step`; the clock runs at SPEED while everyone sleeps or waits);
  `Survival.server_wait`; `PauseMenu` (SoloPause.on_open/on_close); `Hud` (the screen); items
  cooked_meal and vegetables.
- Proposed defaults: radius 40 m; stash 60 items, pile 300, the yard unlimited; sleep 22-6, meals 7/12/18,
  work 7-19, watch shifts 4 h (over 4 h a night: "too long a watch"); eat under hunger 70 at a meal or
  35 any hour, drink under 60; scavenge 150 m at 0.6 finds an hour; a farm bed 1 vegetables per 8 worked
  hours; hunting 0.25 raw meat an hour; cook 3 an hour, 2 hot meals a member kept; build 120 s of work
  an hour; haul 12 items an hour; 4 repairs an hour; a generator burns a fuel item per 12 h; cut wood 3
  planks an hour (woodpile stub), sandbags 3 an hour (a cloth rag each), the stove 3 an hour; a claim
  holds 2 h; defence wood 0.2 a block .. steel 1.2, gate 6, lookout 10, HESCO 8, wire 3, a guard 10;
  footprint 60 m a generator, 15 m a lamp; the vote closes after 2 world hours, the players' weight
  1 + standing / 20, influence +1 the oldest, a medic, the first settled; a challenge under morale 35
  and standing 0, once in 3 days; waiting: 60 m clear of the dead, home within 40 m or indoors, dusk
  19:00, dawn 06:00.
- Not yet: felling ZoneScatter's trees (cut wood is a woodpile stub), crops (farm beds yield a stub),
  animals, power runs nothing but the footprint, settlers walking to their jobs (a body stands at home),
  stash contents shown on the stash piece (stow and take go through the screen), theft, desertion
  splits as a new group (call 52), the challenge's contest, relations with other settlements, the
  raid AI against the defence value (§9), the "settlement" perfcase, the settlement's world-sim record
  for the world lane (it reads `Settlement.data()`, `defence()`, `footprint()`, `stocks()`).

The free building system (calls 8, 12, 39), the settlement's economy of stocks, jobs, work
orders and the council (calls 23, 28, 59), and the old world's infrastructure brought back
(call 60). Written 2026-10-26 from the Captain's calls in docs/survival.md. The aim he set:
"a building system that is better than DayZ's mods" and "build anything (reasonably)".

Built on: `VoxelWorld` (0.1 m voxels, `Mat` materials with per-material round loss,
`server_carve`/`server_blast`/`server_breach`/`server_shot`, marks and holes), `Digging` and
`GroundCuts` (berms, pits, trenches, craters saved with the zone), `DefencePlacer` (the ghost
placement of sandbags, HESCO and wire with a reach, an OK/BAD ghost and snapping, from the
operations lane), `BuildingGen` (the houses' walls, roofs, doors and windows as voxel stamps),
`GameState.voxel_edits` (per-zone saved edits), and the vehicles' physics bodies.

## 1. The two layers

**Blocks** (any shape) and **pieces** (what blocks do badly), on one build grid.

- **Build grid**: BLOCK_M (Proposed 0.5 m = 5 voxels a side), aligned to the zone's voxel grid.
  A block is a solid cube of one material stamped into `VoxelWorld`; half-blocks, slabs
  (0.1 m), ramps and wedges are block shapes. Anything the voxel world can draw, a block can
  be: a wall one block thick, a tower, a tunnel under a fence, a bridge of slabs, a berm faced
  with sandbags.
- **Pieces** are prefab nodes snapped to the grid: doors and hatches (opening, lockable,
  breakable), windows and shutters, stairs and ladders, floors with trapdoors, a drawbridge, a
  gate, fences and wire, furniture (beds, bunks, tables, shelves, stashes, a stove, a
  workbench), lights, a well, a water filter, rain barrels, a generator, solar panels, a wind
  turbine, a smokehouse, a greenhouse frame, animal pens, a lookout platform, spike pits and
  bear traps (survival_world.md §5 and call 53). A piece has a footprint in blocks, a material
  tier, a strength and a function (what it does when powered, used or hit).

Both layers go through one **`Builder`** (server authority; owner → host RPCs like `Digging`):
place, remove, repair, upgrade, dismantle, with the result replicated as voxel edits and piece
records in the zone save. Every placed thing is a real physics body: zombies push on it,
bullets damage it (`server_shot` with the block's material), a truck can ram it, fire burns it
(survival_world.md: fire as a lure and a hazard).

## 2. Materials

| Tier | Material (`Mat`) | Source | Strength | Span | Zombies | Weather |
|---|---|---|---|---|---|---|
| 1 | **wood** (planks, logs) | felled trees (axe, saw), stripped buildings, pallets | low | 3 blocks | chewed at CHEW_WOOD (Proposed a block per 6 min with 5 on it) | rots in rain without a roof (ROT_DAYS Proposed 20 wet days) |
| 1 | **scrap** (sheet, fencing) | wrecks (wrench, hacksaw), fences, signs | low-medium | 2 | slowed; sheet bends | rusts near the coast (SALT_DAYS Proposed 30) |
| 2 | **sandbag / earth** | sand or soil + cloth (shovel), berms (`Digging`) | medium (absorbs) | 1 (stack only) | shoved, not chewed | washes out in heavy rain if unprotected |
| 2 | **HESCO** | the operations lane's pieces: wire + fill | high | 1 | holds | holds |
| 3 | **brick / block** | stripped buildings (a chisel, slow), bagged mortar | high | 4 | holds | holds |
| 3 | **concrete** | bags + water + gravel, a mixer piece | very high | 6 | near-immune | spalls under shots, otherwise holds |
| 4 | **steel** (beams, plate) | the port's containers, the base, the dam (torch cut, a vehicle to haul) | highest | 8 | immune | rusts slowly by the coast |

Materials are items with weight and volume (a sack of sand, a bundle of planks, a beam needs a
cart or a truck: survival_world.md's mounts and vehicles), so hauling is part of the job.
Upgrading in place (call 12): a wood wall becomes brick without tearing it down, costing the
difference; dismantling returns DISMANTLE_SHARE (Proposed 60%).

## 3. Structural integrity (call 39)

Real, not a rule of thumb:
- Each block carries **load** = its own mass + what rests on it; each material has a
  **capacity** per block and a **max unsupported span** (table above). Support flows down and
  sideways through touching blocks and pieces to the ground (terrain voxels and the existing
  buildings count as ground).
- Over capacity: the block **cracks** (the voxel world's crack marks, a creak), then after
  CRACK_S (Proposed 20 s) **fails**: it and everything that only it held fall as real voxel
  destruction (`server_blast`-style removal, debris as items where the material allows).
- The solver runs on the host, incrementally: a change marks its connected cluster dirty; the
  cluster is re-solved on a worker thread (clusters are small: a settlement is a few hundred
  blocks). A ghost shows the load colour (green, amber, red) before you place.
- Damage lowers capacity: a chewed, shot or burnt block holds less; repair restores it.
- Weather wear (call 39): rain on roofless wood, snow load on weak roofs (winter), salt rust by
  the coast; the settlement's **maintenance job** (§6) walks the builds and repairs what's worn.

## 4. Building in play

- **Build mode** (a key): the first-person placement from `DefencePlacer` generalized: a ghost
  of the block or piece at the aimed spot, snapped to the grid, rotated with the scroll, OK/BAD
  by the integrity colour, the material and tool in hand, the cost shown. Place with the use
  key; hold to place a line of blocks; a wall of 4x3 is 12 placements or one "wall" shape.
- **Shapes**: block, half, slab, ramp, wedge, pillar, arch (pieces of blocks placed as one).
- **Tools** (call 39): a hammer for wood and pieces, a saw to make planks, a wrench for scrap
  and vehicles, a trowel for brick and concrete, a shovel for earth and sandbags, a torch for
  steel. No tool, no placing that tier. Tools wear and are repaired.
- **Time**: BUILD_S per block by material (Proposed wood 4 s, brick 8 s, concrete 12 s, steel
  15 s), shortened by the building skill (survival_rpg.md). A block being built is a ghost that
  fills; stopping keeps the progress.
- **Blueprints** (call 12): lay ghosts without materials, then build them yourself or leave
  them for companions and settlers with the materials in stock (§6). A blueprint can be saved
  as a template (a wall section, a tower, a bunk room) and stamped again.
- **Claims**: anything you built is yours and your settlement's; a group that takes the place
  takes the builds. No claim radius or locked ground: ownership is who holds the place
  (survival_world.md §4).
- **Co-op**: everyone builds; the host resolves conflicts (two placements on one cell: first
  wins, the other's ghost turns red).

## 5. The settlement

The safehouse farm grows into a settlement (call 23) by what is built and who joins. A
settlement is a **place** in the world sim with a group record (the players' group) so every
rule in survival_world.md applies to it: it has a defence value from its builds and guards, a
noise and light footprint that feeds the zone's pressure, stocks that groups judge, relations.

**Stocks** (call 59): food, water, fuel, firewood, wood, scrap, sand, brick, concrete, steel,
meds, ammo, parts; kept in stashes, piles and tanks (pieces), counted by the planning view.
**Beds** cap the people (call 28: Proposed 24 at most, by beds and food).

## 6. Work: jobs, work orders, hauling (call 59)

- **Jobs** a person can hold (several, in priority order): guard (a post and a watch
  rotation), scavenge (a route, a cart), farm (beds, water, weed, harvest), hunt/fish, cook
  (meals, smoking, canning), medic (the clinic), build (blueprints), haul (stocks to where
  they're needed), maintain (wear and damage), craft (the workbench orders), mind the animals,
  mind the generator, scout.
- **Work orders**: build these blueprints; cut N wood; make N sandbags; smoke the meat; boil
  water to N; repair the north wall; dig a pit here. Orders have a priority and a count; the
  planning view shows what's short and who's idle (RimWorld's loop, kept first-person: you can
  do any job yourself, and a job you're doing isn't taken over).
- **Schedules**: people sleep at night by default (survival_medical.md: fatigue), eat at meals,
  work the day, with the guard rotation as the exception; a night build is possible, loud and
  lit.
- **Moods** (survival_people.md): a job someone hates, too long a watch, a cold bunk lower
  morale; a good kitchen and a dry bed raise it.

## 7. The council (calls 28, 59)

Big decisions go to a **vote** the players' standing can sway: take in a group, pay a raider's
demand, hand someone over, move the settlement, join or defy the enclave, exile a member. Each
settler votes by mood, relations and traits; your standing (what you've done for them, the
jobs you do yourself, the losses you've led them into) is a weight on your side. Losing a vote
means the settlement does the other thing (pays the demand from stock, refuses to take the
group in) and you live with it. A **leader challenge** comes when morale and your standing both
fall under a line: a settler with the traits for it asks for the lead; win it by standing, a
contest of skill, or by leaving. Factions inside the settlement (two families, the old crew and
the newcomers) vote together and can split off as a new group in the world sim (call 52).

## 8. Infrastructure (call 60)

- **Power**: generator pieces (fuel, loud: a steady pressure source), solar panels and
  batteries (scarce, quiet), a wind turbine build (hills and coast), wiring as a piece between
  them; power runs lights, a fridge (food keeps), a radio (survival_world.md §10), an electric
  fence (stuns walkers), power tools (faster builds), a water pump. A lit settlement is found
  sooner by groups and the dead.
- **Water works**: repair a town's water tower or pump house (a mechanic, parts, power) so taps
  run in that zone; a settlement well (dug, lined), rain barrels, a filter tower
  (survival_medical.md: water quality).
- **The dam or power plant**: a late project (a crew, parts, days) that powers a whole zone;
  every group's eye turns to it, the enclave may want it; holding it is a settlement in itself.
- **Roads and bridges**: clear wrecks to open a road to vehicles and carts (a winch, a truck,
  a crew); repair a bridge (steel, concrete) or blow it (the demolitions we have) to shape where
  hordes and raiders can come from; crossings as chokepoints with a gate and a watch.

## 9. Raids and sieges against builds (call 55)

Raiders judge the defence value (walls by tier, gates, towers, guards, traps their scouts saw);
the attack uses the tactics AI: support by fire on a tower, a breach charge on a wood wall
(`server_breach`), a truck through a gate, fire on a wood roof. Horde sieges push on walls
(chewing wood, piling at a corner until the pile is a ramp: a real risk, the kill corridor and
the pit are the answers) and on gates. The siege leaves damage to repair and bodies to burn or
bury (a job).

## 9b. Navigation round builds (call 141, built 2026-10-26 on claude/survival-polish)

Before this, the zone navigation (ZoneNav: 12 m chunks baked in the background around the
soldiers) read only the modules' voxels: a wall built in the open was not in the navmesh, so the
dead and companions planned paths straight through it and walked into it. What's done now (the
cheapest correct fix: a throttled rebake of the touched chunks, no obstacle avoidance):
- **Blocks**: `ZoneNav._add_builds` adds `Builder.nav_boxes(bounds)` to every chunk's bake: each
  built block (not a site or blueprint) from Builder's records, a column of full blocks merged into
  one box per run, a half block, ramp or wedge half high, a slab its slab, a pillar its post. Read
  from the records, not the voxels (BuildVoxels' edits sit outside VoxelWorld's structures, and
  reading a chunk's voxels costs too much).
- **Pieces**: a built piece standing solid joins `NavBuilder.OBSTACLES_GROUP` (BuildPiece.apply),
  baked in as its collision box. Doors, shutters, hatches, gates and the drawbridge don't (the
  dead path up to them and push: BuildIntegrity's battering, Builder.server_chew_at); stairs don't
  (walked up); open or unbuilt pieces don't.
- **Rebake**: a block stamped or cleared (Builder._op: built, dismantled, fallen) or a piece made,
  changed or removed marks its footprint (`_nav_touch`); NAV_BATCH_S (0.25 s, Proposed) after the
  first change of a run, the chunks the merged rectangle touches are rebaked
  (`ZoneNav.rebake_rect`: off-thread, those baked now). A row of blocks bakes once.
- **The dead**: ZombieAI asks its path again when the navigation map's iteration changes (at most
  every REPATH_S, 0.5 s), so a wall built in front of a walker turns it round within a second.
  Companions path with the squad AI's own queries, which read the same map.
- Polish suite: a 9 m wall built between two points: the path query goes round it within a second
  and a zombie's own path changes.

## 10. Performance

Blocks are voxel edits: a settlement of 2,000 blocks is one zone's worth of edits, re-stamped on
load as today. Pieces are nodes with a cap per zone (PIECES_CAP Proposed 600) and LOD past 100 m.
The integrity solver is incremental and off-thread. Wear ticks per world hour, not per frame.
A perfcases case "settlement" (2,000 blocks, 200 pieces, 12 people working) joins the suite in
phase B.

## 11. Tests (phase B)

`building` suite: a block placed, saved and reloaded; a span over capacity cracks and falls as
voxels; an upgrade in place; dismantling returns a share; a door opens, locks, breaks; a
blueprint built by a settler from stock; a work order counted and completed; the council votes a
demand paid from stock; a generator raises pressure and lights the fence; weather wears a
roofless wood wall; a horde chews a wood wall and not a steel one.

## 12. Calls answered (2026-10-26)

Grid 0.5 m blocks (call 70); integrity real with cracks and a load-coloured ghost (71);
ownership by who holds the place, locks with keys or codes (72); slow wear with a maintenance
job (73). All as written above.
