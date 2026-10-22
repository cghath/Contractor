# Audit follow-ups from Captain's side (added 2026-10-13)

New tasks for cghath, found while building towns and multi-storey buildings on Captain's side.
They are new work, not reopened findings: the 26 audit findings stay as SUMMARY.md has them.
Each names the files involved. The files are yours (the AI building scan, the garrison spawn,
doctrine numbers), so Captain's side hasn't changed them.

| Id | Priority | Task |
| --- | --- | --- |
| F-01 | P2 | The AI building scan only finds one floor; upper floors and roofs are never garrisoned or cleared |
| F-02 | P2 | Town garrison posts are all on the ground floor |
| F-03 | P2 | Doctrine `engage_m` numbers sit below the new sight ranges |
| F-04 | P1 | ~~A carer who boards a vehicle keeps his casualty claimed, so no backup medic comes (audit A2-12)~~ fixed 2026-10-20 (Claude, cghath's fix/a2-ai-vehicles) |
| F-05 | P2 | ~~Element men told to board from a distance never get the walk order (audit A2-10)~~ fixed 2026-10-20 (Claude, cghath's fix/a2-ai-vehicles) |
| F-06 | P2 | ~~An ammo bearer's belt handoff turns a part-used belt into a full one (audit A2-11)~~ fixed 2026-10-20 (Claude, cghath's fix/a2-ai-vehicles) |

| F-20 | P2 | A medic walks over unasked to a player whose bandages are in his IFAK (fixed 2026-10-20 by Claude: Vitals.has_item) |
| F-07 | P2 | ~~The far-AI sleep (DynamicSim) can freeze a falling soldier in his last metre above the ground~~ fixed 2026-10-20 (Claude: sleeps only on the floor and still) |
| F-130 | P2 | The AI grenadier carries the M320 and 40 mm grenades but never fires or loads it |
| F-131 | P3 | An AI soldier with a shotgun counts its loose shells as no spare ammo (reload, ammo-low, scavenging) |
| F-160 | P3 | Dog tags have no worn model: a chain and tags on the neck while `Soldier.dog_tags` is set (Captain's side: gear rig, character model) |
| F-161 | P3 | AI squadmates never take a fallen man's dog tags (squad AI: a scavenger or bearer could) |
| F-150 | P3 | Enemy soldiers and gunners never aim at the player's recon UAV (fire support, 2026-10-20) |
| F-151 | P3 | Enemy vehicle crews don't move off when fire missions land round them (fire support, 2026-10-20) |
| F-120 | P2 | Squad AI walks onto our own marked mines and into our claymores' fans and tripwires (Demolitions.hazards) |
| F-121 | P3 | The vehicle range's concrete blocks and sandbag wall (z -30 and -45) lie outside its voxel world's edit area, so they're never built |
| F-190 | P2 | A convoy ambush's convoy drives its own straight-ish line across the zone, not the roads (scenario_gen `_convoy`) |
| F-191 | P3 | Vehicle grip ignores the surface: asphalt, a dirt track and open ground all grip alike (Vehicle `_wheel_forces`, Claude's file) |
| F-192 | P3 | AI drivers can go round a roundabout the wrong way, and RoadRoute's graph has no one-way edges (Claude's files) |
| F-193 | P3 | A crater or a dug pit on a road leaves the road's surface hanging over the hole (GroundCuts doesn't tell ZoneRoads) |

## F-01: the building scan only sees one floor

Location: [buildings.gd](../../scripts/ai/buildings.gd), the inside-spot grid in `_scan`.

Generated buildings (`scripts/world/building_gen.gd`, phase 3, on `world/building-storeys`)
now have a second storey and flat roofs. Stairs are solid steps (0.23 m rise), so the
navmesh covers them, the upper floor and the roof, and soldiers can walk all of it. But the scan
samples one grid at the query's height: a navmesh point counts only within 2.5 m of that
height, so a scan from the ground floor finds its rooms and nothing above. Upper rooms never
become "rooms", their windows never become firing ports, and the stairs aren't entrances. So
the AI doesn't garrison, defend or clear room by room above the ground floor, and doesn't use
the roofs' parapets as cover.

To do: scan each floor of a building (heights from the navmesh, or from the storey heights
`BuildingGen.building` returns: `"rooms"[i].y`, `"stairs"`), link floors at the stairs (a stair
works as an inside entrance between two floors), and treat a roof with a parapet as a floor with
ports all round. Keep A3-04's per-world cache scope.

Check with: `agent-tools/phase3_shots.gd` (Captain's side) builds two-storey buildings, and
world_test's `_test_building_gen` lists them by seed.

## F-02: town garrison posts are all on the ground floor

Locations: `BuildingGen.town` "garrison" (posts just inside every other front door, and two at
the crossroads), [zone_level.gd](../../scripts/world/zone_level.gd) `_spawn_garrison`.

A town's hostiles stand at street level only, even with two-storey buildings and roofs to hold.
This depends on F-01: once the scan knows upper floors, garrison posts can go up there (Captain's
side can add upper-floor and rooftop posts to `BuildingGen.town`; the guards then need the scan
to fight from them).

## F-03: doctrine `engage_m` sits below the sight ranges

Location: [doctrines.json](../../data/doctrines.json), `engage_m` (60 to 120 m), still in
`_pending` (A3-07).

Captain raised the engagement ranges (ai/ranges, on dev): hostiles see 200 m (was 60), the
squad 300 m (was 120), aim error at skill 0 is 1.2 degrees (was 2.0). When the doctrine numbers
are wired in, `engage_m` should be raised to match, or the doctrines will pull the new ranges
back down.

## F-04 to F-06: three audit findings in Claude's files (cghath's side, 2026-10-20)

These come from the executive audit of `68a1b83` (`docs/audits/executive-2026-10-19/PART-2.md`).
They sit in Claude's files (`scripts/ai/squad_ai.gd`, `scripts/vehicles/`), so per the Captain's
tasking they are logged here, not fixed on cghath's branch.

**A fix with tests is already built and ready to take or adapt:** branch `fix/a2-ai-vehicles`
(commit `184f408`, pushed, based on `3e5a1ee`). Each test failed on the unfixed code (R0198).
With the fix, casualty, medical, squad, logistics, roles and scavenge passed (R0206; one roles flake
passed in R0208), and the vehicles host passed apart from the co-op checks dev already fails (R0208).

### F-04 (P1, audit A2-12): a carer who boards keeps his casualty claimed

Location: [vehicle.gd](../../scripts/vehicles/vehicle.gd) `server_enter`;
[squad_ai.gd](../../scripts/ai/squad_ai.gd) `_carer_of`, `_find_casualty`.

`Vehicle.server_enter` turns the soldier's brain off but leaves his care job running: `casualty`,
`care` and the casualty's `care_by` all stay set. `SquadAI._carer_of` still counts that carer, so
other responders' `_find_casualty` skips the casualty for as long as he sits there.

The fix on the branch:
- `server_enter` calls a new `SquadAI.drop_care()` (a public wrapper on `_end_care`, which clears
  `care_by`, the HVT handoff claim and any carry) before turning the brain off.
- `_carer_of` ignores a seated AI carer.

Test: `casualty_test._test_carer_boards`. A medic treating, or walking to, a casualty is seated
directly, or boards through `VehicleLayer.server_board`, and a backup takes the casualty.

### F-05 (P2, audit A2-10): distant element men never walk over to board

Location: [vehicle_layer.gd](../../scripts/vehicles/vehicle_layer.gd) `server_board`.

The move-to-door order always goes through the commander's main squad
(`lvl.squad_for(from.faction)`). `Squad.pick` skips men owned by another squad, so an element man
is queued for boarding but stays on HOLD.

The fix on the branch: the order goes through the man's own squad (`SquadAI.of(s).squad`), and
falls back to the main squad when he has none. As `server_squad_dismount` already does, it names the
high-command player as that squad's leader.

Test: `vehicles_test._test_squad_drivers`. Two element medics 25 m out get MOVE; the first takes the
last seat, and the second finds the vehicle full and leaves the queue.

### F-06 (P2, audit A2-11): the ammo bearer's belt handoff makes ammunition

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) `_maybe_resupply_gunner`.

`remove_one(ammo)` followed by `gunner.inventory.take(ammo, 1)` drops the belt's `"rounds"` state,
so a part-used belt arrives as a full 100-round belt. The result of `take` is ignored, so a belt
that doesn't fit vanishes.

The fix on the branch: take the belt entry out with `_take_out(ammo)`, as the magazine handoff does,
and hand it over with its state. If the gunner has no room, the bearer keeps the belt.

Test: `roles_test._test_ammo_bearer` (with a `_belt_rounds` helper). Belts of 7, 0 and 100 rounds
arrive with exactly their own rounds, and with no room the bearer keeps his.

## F-20: a medic walks over unasked to a player whose bandages are in his IFAK

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd), `SquadAI.player_wants_care` (the line
"nothing of his own for it: a squadmate comes"). Found by cghath's agent on `feat/tutorial`
(2026-10-20), writing the tutorial's medical steps.

Cause: it asks `s.inventory.count_of(id)` whether the player carries an item for each care task.
`Inventory.count_of` counts loose items only, not what's inside a kit, so a player whose only
pressure bandages are the two in his IFAK (the usual kit) counts as carrying nothing for a graze
or a venous bleed, and out of a firefight a squadmate comes to treat him though he never called.
The treatments themselves do use kit contents (`Vitals.has_item`, `Inventory.medical_count`), so
he could have treated himself.

Suggested fix: use `Vitals.has_item(s.inventory, id)` there (it counts loose items, kit contents,
and items that need none), so "on its own" only covers a wound he really can't treat. The tutorial
works around it by handing out two loose bandages (`TutorialGuide.KIT`), so its "treat yourself"
step isn't done for the player by a medic.
## F-07: the far-AI sleep can freeze a soldier mid-fall

Found by cghath's side (fix/ci-flakes, 2026-10-20) in world_test's ground guard check; the file
is Claude's (Captain's side), so it isn't changed here.

Location: [dynamic_sim.gd](../../scripts/world/dynamic_sim.gd), `should_sleep`, the
`OFF_GROUND_M` test.

A hostile far from every player (world_test's FallGuy, ~800 m off) that falls is only kept
awake while he's more than `OFF_GROUND_M` (1 m) above `ground_point`. In his last metre he can
be put to sleep mid-fall, `process_mode` disabled with his velocity still set: CI run
39421584652 left him at y 1.73 over ground at 0.99, falling at 4.9 m/s, not on the floor, until
the test gave up. A slow runner makes it likelier (a fall spread over more ticks), and a body
frozen like that floats in the air until a player comes within `WAKE_M`. The doc comment says
"nobody is frozen mid-fall".

Suggested fix: don't sleep a soldier that isn't on the floor (`not s.is_on_floor()`), or whose
`velocity` isn't about zero, as well as the height test; or sleep him only after he has been
on the floor for a tick or two. world_test now turns DynamicSim off during its ground guard
check (that check isn't about the sleep); a test of the fix could drop a far hostile 2 m onto
the ground with DynamicSim running and check he lands.

## F-90: a squadmate stuck on his way back to formation (casualty suite, CI only)

**Same failure as F-08** (a following squadmate pushing with no speed; logged on `fix/ci-flakes`,
cghath/Contractor#10, which this branch didn't have). Kept as extra evidence for F-08: it also
happens away from the target dummies, around (5, 5), so a side-step/repath in SquadAI is the fix to
look at, not only baking the dummies into the navmesh.

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd), following the lead (`Following (dynamic: ...)`).
Found by cghath's agent on `feat/tutorial-2` (2026-10-20), whose change doesn't reach it (the
tutorial guide, its test and the ui test only).

What happens: `casualty_test` "nobody got stuck on the way" failed on CI three times in a row on
`feat/tutorial-2` (run 39493797840, first try and its re-run; run 39496845311), each time Golf
following the lead along a path of 14-17 points and making no progress (at about (5, 5) with input
but little speed, once at (-3.5, 12.3) with input and zero velocity). The unrelated
`feat/economy-balance` failed the same check the same way, Golf at (5.0, 4.9) (run 39495689709).
It passes locally (R0300) and passed on dev's 52037f2. The same kind of "stuck" failure shows on
other branches' CI (`spacing` "walking away from the wall, nobody stays stuck on it" on
`claude/ai-driving`). Suggested: read Golf's path
and input in the CI log; a timing difference on the Linux runners in path following looks likely.

## F-80: with a collection point set, no squadmate picks the body up (casualty suite, CI only)

**Same failure as F-08** (squadmates held against the target dummies; logged on `fix/ci-flakes`,
cghath/Contractor#10, which this branch didn't have). F-08 already lists this collection-point check.
Kept as extra evidence: five of the six were touching the same StaticBody3D.

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd), the "ccp" order (`Squad.order_command(...,
"ccp", ...)`) and the bearer it should send. Found by cghath's agent on `feat/assault-warning`
(2026-10-20). That change doesn't reach it (the debrief, BaseHub's deployment end, BaseAssault, the
supports origin lookup, and the base_zone and ui tests).

What happens: `casualty_test` failed two checks on CI twice in a row on `feat/assault-warning`
(run 39496388734, first try and its re-run of the failed jobs). "saying so ([])": the "ccp" order
gave no radio line. "with a collection point set, a squadmate picks his body up": nobody took
Echo's body in 25 s. All six squadmates stayed "Following (dynamic: wedge, normal)" with no speed,
and five of them were touching the same StaticBody3D. It passes locally (R0314) and passed on dev's
52037f2. It may be the same as F-08 and F-90 (squadmates held against the target dummies on the
Linux runners), seen from the care side. Suggested: read the order's path in the CI log, then check
whether "ccp" finds a bearer when every squadmate is blocked on the dummies.

## F-130: the AI grenadier never fires the M320

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) (engagement and reload), maybe
[tactics.gd](../../scripts/ai/tactics.gd). Found by cghath's agent on `feat/m320-shotgun`
(2026-10-20), which built the M320 (Captain's list for cghath, "Not built yet / Weapons and
items") and left the AI out because it's Claude's file.

What happens: the grenadier's kit (data/roles.json) now puts an M320 on his M4 with eight 40 mm
HE and two smoke grenades (Roles.give mounts it). He fights with the rifle only: nothing in
SquadAI loads or fires the launcher. The host-side calls are ready to use: `Underbarrel.on_gun(s)`
(has one), `Underbarrel.loaded_of(s)` / `carried_rounds(s)` / `next_round(s, id)`,
`Underbarrel.server_reload(s, round_id)` (timed, returns the seconds or -1) and
`Underbarrel.server_fire(s, eye, dir)` ("" when it fired). The grenade flies the launchers' flight
(`LauncherProjectile.drop_at(&"m406", range)` gives the drop and time to aim over, as LauncherAI
does for the RPG-7). HE arms only past 14 m (`Warheads.data(&"m406").arming_m`), so closer it is a
dud. Suggested: like LauncherAI's fire at groups behind cover, a grenadier with a loaded M320 lobs
HE at enemies in cover 30-250 m off with no friendly within 12 m of the aim point, and screens with
smoke on the squad's "throw smoke" order when he has one loaded; he loads by hand in cover.

## F-131: an AI soldier with a shotgun thinks it has no spare ammo

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) (`rounds`/`spare` around the ammo checks and
`_mag_size`), [scavenge.gd](../../scripts/ai/scavenge.gd). Found by cghath's agent on
`feat/m320-shotgun` (2026-10-20). No AI kit carries the shotgun yet, so it only matters once one
does (or an AI picks one up).

What happens: a shotgun (stats.tube, Shotguns) loads loose 12 ga shells shell by shell, and its
stats.ammo names the buckshot shell. `Inventory.spare_rounds(ammo)` counts a magazine's rounds, so
for loose shells (no "rounds" in their state, magazine_rounds 0) it gives 0: the AI's ammo-low and
"reload when" checks see a shotgun with shells in the pack as out of ammo. The host side already
loads a tube when the AI asks: `Soldier._server_reload` on a tube weapon runs
`Shotguns.server_load(s, slot)`. Suggested: for `Shotguns.is_tube(weapon)` count
`Shotguns.shells_of(weapon)` with `inventory.count_of(id)` as the spares, and the tube's
`Shotguns.capacity(weapon)` as the magazine size.
## F-160: dog tags have no worn model (Captain's side)

Location: [gear_rig.gd](../../scripts/combat/gear_rig.gd), [character_model.gd](../../scripts/player/character_model.gd)
(and [voxel_art.gd](../../scripts/art/voxel_art.gd) for the piece itself). Found by cghath's agent on
`feat/fallen` (2026-10-20), which builds the tags but may not touch these files (the Captain's side's
items 1-5).

What's there: every company soldier wears tags (`Soldier.dog_tags`, a Dictionary set by the host as the
body spawns, replicated by ServerSync with the other soldier fields, late joiners included; `{}` for
everyone else and once they've been taken off a body). Taking them makes a `dog_tags` item (data/items.json,
`size_m` [0.05, 0.005, 0.03]) in the taker's gear. Nothing draws them: no chain on the neck, and the item
on the ground or in hand uses the generic look.

Suggested: a small chain and two tags at the neck (under the carrier's collar) while `dog_tags` isn't
empty, gone once taken (the property changes on every peer); a voxel piece for the item.

## F-161: AI squadmates never take a fallen man's dog tags (Claude's side)

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) (the scavenger and the bearer: `scavenge.gd`'s
picks, the bearer's walk to a body). Found by cghath's agent on `feat/fallen` (2026-10-20).

What's there: `Soldier.server_take_tags(body)` (host; no reach check of its own, the caller's: measure to
`Soldier.body_point()`, as CLAUDE.md says) takes a fallen company soldier's tags into the taker's gear;
carried out at extraction they make him killed in action instead of missing (BaseHub `_collect_tags`,
`Fallen`). Only players take them now (the interaction menu's Take dog tags). A squadmate who reaches a
fallen friend (a bearer, a scavenger) walks away without them, so a man killed while the players are
elsewhere stays missing unless a player goes back.

Suggested (Proposed): a squadmate at a fallen company soldier's body (`not body.dog_tags.is_empty()`)
takes his tags as he would a pick (`server_take_tags`), and says so on the radio ("Got Reaper's tags").
## F-150: enemy soldiers and gunners never aim at the player's recon UAV

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) target picking (it only looks at Soldiers),
and the AA technicals' gunners (`technical_zu23`, `technical_zpu`) under
[scripts/vehicles/](../../scripts/vehicles/). Found by cghath's agent on `feat/fire-support`
(2026-10-20).

What happens: the player's recon UAV (`UavSupport`, scripts/supports/uav_support.gd) can be shot
down, as the enemy's drones can: its body takes Ballistics' `on_bullet` and three hits bring it
down. But no enemy AI ever fires at it, because their targets are Soldiers only. For now
`UavSupport._aa` stands in: a manned hostile AA technical within 1,500 m with a clear line to the
UAV has a 6% chance every 5 s to hit it (data/fire_support.json "uav", Proposed). Suggested: let the
AA technicals' gunners (and maybe riflemen who see it low) pick the UAV's body as a target, and
then drop `_aa`'s dice roll.

## F-151: enemy vehicle crews don't move off when fire missions land round them

Location: [vehicle_ai.gd](../../scripts/vehicles/vehicle_ai.gd) and the crews' SquadAI. Found by
cghath's agent on `feat/fire-support` (2026-10-20).

What happens: the player's fire missions (`FireSupport`) land on vehicles through
`Vehicle.server_take_hit`, and every soldier near a burst is suppressed (Warheads, Alert). A crewed
enemy vehicle under adjusting rounds stays where it is, though, until it's hit. Real crews drive
off when the first rounds walk in. Suggested: when a burst lands within about 50 m of a crewed
hostile vehicle, its driver moves it 100-200 m away from the burst, toward cover.
## F-120: the squad AI doesn't keep off our own mines and claymores

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) (moving, formation spots, cover picks) and
perhaps [tactics.gd](../../scripts/ai/tactics.gd). Found by cghath's agent on `feat/demolitions`
(2026-10-20), which added player mines and claymores (`scripts/combat/demolitions.gd`); the AI
files are Claude's, so they aren't changed there.

What happens: friendly fire is on for placed mines and claymores, as the Captain asked, and our
side's are marked on the map ("Our mine", "Our claymore", field channel). Squadmates don't know
about them: one following the lead, bounding or taking cover can step on a pressure mine (a leg
wrecked) or walk through a claymore's tripwire.

What's there to use: `Demolitions.of(level).hazards(faction)` (host) lists the armed mines and
claymores placed by that faction's side, each `{"id", "kind", "pos", "radius", "forward"}`
(`radius`: keep this far off; `forward`: a claymore's facing, its fan is 60 degrees either side
of it out to 50 m, its tripwire 2 m out across 4 m). It is cheap (a handful of records).

Suggested: when SquadAI picks a move target, formation slot or cover spot, skip any within a
hazard's `radius` (and, for a claymore, don't stand in front of it within 10 m); a path that
passes within `radius` could add a waypoint round it. Enemy AI should stay unaware (they don't
know where ours are). A test could place a friendly mine on the line between a squadmate and his
formation spot and check he goes round it.

## F-121: the vehicle range's obstacles are outside its voxel world

Location: [vehicle_range.gd](../../scripts/vehicles/vehicle_range.gd), `BLOCKS`; the bounds are
`VoxelWorld.BOUNDS` (`scripts/world/voxel_world.gd`: -220 to 220 voxels, so -22 to 22 m). Found by
cghath's agent on `feat/demolitions` (2026-10-20) while setting a demo block on them; the file is
Claude's, so it isn't changed there.

What happens: the range's two concrete blocks at z -30 and the sandbag wall at z -45 ("something
for the AI driver to steer round") are added with `add_box_m`, and the log says "voxel structures
built (3 boxes)", but they fall outside the voxel world's edit area: there are no voxels there
(`Objectives.solid_count` over the block is 0) and no collision (a ray at 0.6 m through it meets
nothing). The demolitions suite uses a plain box as its wall instead.

Suggested: move the blocks inside 22 m of the range's origin (e.g. z -18 and -21), or give the
range's VoxelWorld `bounds` that reach them before it builds.

## F-190: a convoy ambush's convoy doesn't drive the roads

Found by cghath's agent on `world/roads` (2026-10-21, cg_brief 1.2). Location:
[scenario_gen.gd](../../scripts/campaign/scenario_gen.gd) `_convoy`, which the convoy ambush's
objective keeps as "route" and [mission_scenario.gd](../../scripts/campaign/mission_scenario.gd)
drives.

What happens: the route is made when the contract is generated, before the zone's level exists:
a line through the ambush point across the zone with a little sine bend ("the road bends a
little"). The zone's real roads (ZoneRoads, planned when the level builds) go elsewhere, so the
convoy drives cross-country past them.

Suggested: when the scenario starts the convoy (the level is built by then), replace the route's
middle with `RoadRoute.route(level.def, start, finish)` (the def's "roads" are the curved roads
now) when it isn't empty, and put the ambush point on the road nearest it (`ZoneRoads.of(level)
.segments()`). Keep the old line as the fallback.

## F-191: vehicle grip ignores the surface

Found by cghath's agent on `world/roads` (2026-10-21). Location:
[vehicle.gd](../../scripts/vehicles/vehicle.gd) `_wheel_forces` (Claude's file, so roads didn't
change it): `grip := GRIP * ...` is the same on every surface.

The roads now give the wheels' rays something to read: every road body (ZoneRoads) has a
`PhysicsMaterial` (friction 1.0 on asphalt and concrete, 0.75 on dirt, data/roads.json) and the
meta `road` ("asphalt"/"dirt"). Suggested: multiply the grip by the hit collider's
`physics_material_override.friction` when it has one, and by a Proposed 0.7 on the terrain
(ZoneTerrain), so tyres hold best on asphalt and slide sooner off-road. A wet-weather factor
(DayNight) could come later.

## F-192: roundabouts are two-way to the AI drivers

Found by cghath's agent on `world/roads` (2026-10-21). Location:
[road_route.gd](../../scripts/vehicles/road_route.gd) `_graph` and
[vehicle_ai.gd](../../scripts/vehicles/vehicle_ai.gd) (Claude's files).

A roundabout is in the def's "roads" as a ring of RoadNet.RING_SIDES pieces (in order, corner k
to corner k + 1), with the arms ending on its corners. RoadRoute's graph is undirected, so a
route round the ring takes the shorter way, which is the wrong way half the time. Suggested: give
ring pieces (both ends within the ring's radius of one centre) one direction only in `_graph`
(the def order is the driving direction), and have VehicleAI slow to a Proposed 20 km/h through a
turn of more than 30 degrees.

## F-193: a crater on a road leaves the road hanging

Found by cghath's agent on `world/roads` (2026-10-21). Location:
[ground_cuts.gd](../../scripts/world/ground_cuts.gd) `_cut_area` / `_rebuild_around` and
[zone_roads.gd](../../scripts/world/zone_roads.gd).

A blast or a dig cuts the terrain under a road, but the road's mesh and trimesh collision stay
whole, so the road surface spans the crater (an IED on a road leaves no hole in it). Suggested: a
small hook in GroundCuts after a cut, `ZoneRoads.of(self).cut(area)`, that rebuilds the road
tiles touching `area` without the triangles over cut cells (ZoneRoads keeps its geometry per
TILE_M tile, so it's one tile's mesh and body each time).

## Calls made for the Captain

One line each, newest last (docs/cg_brief.md, rule zero): date | what was decided | why | the alternative.

2026-10-21 | Roads come in three kinds (asphalt 7 m, dirt tracks 4.2 m, town streets 6 m between kerbs), every number in data/roads.json as Proposed | one place to tune widths, grip and which sites get what | hard-coded consts in ZoneRoads
2026-10-21 | Asphalt to towns, the HQ, QRF bases, comms, checkpoints and the FOB; dirt to outposts, compounds and villages, and on the trails; a link takes the better of its two ends | main roads read as main roads, farms and compounds get tracks (Arma's mix) | everything asphalt in hot zones
2026-10-21 | Every site is joined to the roads: a site no link reaches gets one to its nearest linked site, and a link passing within 90 m of a checkpoint runs through it | hot zones only linked the HQ to its outposts, so comms, QRF bases, checkpoints, villages and the town had no road; the brief wants every site on the network | leave the links as ZoneDef makes them
2026-10-21 | A road out through a linked-zone crossing runs straight out from the crossing to the zone's edge, its kind from the link's two zone ids (60% asphalt), so both sides of a link get the same road at their own crossing | crossings slide along their edge per zone (RegionMap SLIDES), so "the matching point" is each zone's crossing, not one shared coordinate | change RegionMap so both crossings share one along-edge position
2026-10-21 | Towns get a mini roundabout (a 2 m mountable dome) at the crossroads; full roundabouts (6 m island, 7 m ring) go at junctions of 3+ arms within 320 m of a town, or where 4 asphalt arms meet, clear of pads | the crossroads is about 5 x 6 m between corner buildings, too tight for a full ring without moving BuildingGen's lots | widen the crossroads in BuildingGen.town (changes every town's layout)
2026-10-21 | Kerbs and pavements sit inside the town's existing street rects (carriageway = street less 1 m each side, 2 m pavements out to the building fronts, 12 cm high with a chamfered kerb you can walk and drive over); BuildingGen.town is unchanged | no layout change, no step for soldiers or the navmesh to trip on | move the building fronts back for wider pavements
2026-10-21 | The terrain is cut and filled to the roads: ground 0.10 m under the surface, a level shoulder (3 m low side, 6 m high side), banks 1:2 up and 1:1.6 down to 10 m out; the profile is the ground smoothed over 20 m, solved as a stretched string (36 m) through flat junctions (14 m, ramps between them at most 8%) and the pads, never more than about 3 m off the ground | roads that follow the ground but drive smoothly and never have terrain poking through | drape the road on the raw 4 m grid (bumpy, terrain through it)
2026-10-21 | Where a road meets water (ZoneTerrain.water_height over the ground) it isn't laid or graded: the span is listed in ZoneRoads.water_crossings() for the water side's bridges and the road runs straight over it in the profile | the water side owns bridges, fords and culverts | fill a causeway across
2026-10-21 | Road collision is a trimesh per 256 m tile (a hard body and a soft one, friction 1.0 / 0.75, meta hard_ground for footsteps) on top of the graded heightfield | the 4 m heightfield can't follow a 7 m road's curves and edges; vehicles drive on exactly what's drawn | the graded heightfield only
2026-10-21 | The def's "roads" become the curved roads as straight pieces (within 1 m of the curve, at most 80 m, a third entry naming the kind), the links kept in "road_links"; the trails' patrols follow their curved trails | RoadRoute, ZoneScatter, the map, IEDs and the tracker all read "roads" and now follow the real roads with no change to them | a separate key (they'd all keep the old straight lines)
