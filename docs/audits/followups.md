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
| F-121 | P3 | ~~The vehicle range's concrete blocks and sandbag wall (z -30 and -45) lie outside its voxel world's edit area, so they're never built~~ fixed 2026-10-22 (cghath's world/perf: VoxelWorld.fit_structures) |
| F-162 | P3 | The AI building scan misses the middle of a big open hall (a hangar: rays reach 12 m with no wall), so it isn't garrisoned or cleared room by room (landmarks, 2026-10-21) |
| F-190 | P3 | The woods' GPU frame time is unmeasured: the forest suite counts draws and triangles headless (no renderer); a windowed frame time in a dense copse wants a build on a real GPU (woods perf pass, 2026-10-22) |
| F-191 | P2 | claude/perf-pass and world/perf both change ZoneScatter's build_near, _process, _build_cell and _build_far: whoever merges second keeps both (woods perf pass, 2026-10-22) |

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

Fixed 2026-10-22 (cghath's queue item 1.8, world/perf), without touching vehicle_range.gd (Claude's):
`VoxelWorld.fit_structures()` grows a world's edit area (and its view distance, to reach across it) to hold every
structure added before it builds, and CompoundLevel calls it after `_build_structures`. A world whose structures fit
(the compound, the base, the LHD, every zone module) is unchanged. The range's blocks have voxels and collision now
(2400, 2400 and 1760 voxels), its structures still finish building with the player at the spawn, and the demolitions
suite sets a demo block on a concrete block and checks it carves it.

## F-175: roads lie on the riverbed under a bridge (the roads agent's ZoneRoads)

Location: [zone_roads.gd](../../scripts/world/zone_roads.gd) `_strip`; the bridges are
[zone_bridges.gd](../../scripts/world/zone_bridges.gd). Found by cghath's agent on `world/water`
(2026-10-21, queue item 1.1); zone_roads.gd is the roads agent's (paved roads, item 1.2), so it isn't
changed there.

What happens: a road crossing a river or stream gets a bridge (or a culvert's embankment, or a
ford) from ZoneWater, but ZoneRoads drapes its strip on the terrain as before: under a bridge it
runs down the bank, along the riverbed under the water and up the far bank, seen through the water.
Looks only (the strip has no collision; vehicles drive on the deck).

Suggested: break the strip where `terrain.water and terrain.water.bridges.covers(p)` is true for a
bridge (as `_on_pad` breaks it on a pad), or lay it on the deck (each bridge record in
`terrain.water.bridges.bridges` has its `xform`, the deck's top middle, and `length`). With
collision on roads, keep a road's collision off the bridge's span too. A culvert's embankment and a
ford are ground, so the strip can follow them.

## F-176: the dug ground never comes back from a zone save

Location: [game_state.gd](../../autoload/game_state.gd) `read_save` (and `load_zone`). Found by
cghath's agent on `world/water` (2026-10-21) while adding the bridges' section to the save; not
changed there (Digging's side).

What happens: `save_zone` writes `"ground"` (Digging.to_save: the cuts and berms) into the zone's
save, but `read_save` builds its result from a list of sections and `"ground"` isn't one, so
`load_zone`'s `ground = zone.get("ground", {})` is always `{}`: foxholes, trenches, berms and blast
craters are gone when a zone is loaded from its save (Digging.server_prepare then digs the enemy's
outposts in afresh).

Suggested: copy `"ground"` through in `read_save` (a dictionary with "cuts" and "berms" arrays,
checked like the other sections), and a digging test that saves, reloads and finds its cuts.

## F-177: a river ends in a notch at the zone's edge

Location: [zone_water.gd](../../scripts/world/zone_water.gd) (rivers run edge to edge) and
ZoneTerrain's apron. cghath's agent, `world/water` (2026-10-21); a known gap, not a bug.

What happens: the river's channel and valley run to the zone's edge, but the apron past it is flat
at 0, so from inside the zone (looking out past the invisible wall, in the haze) the river ends
against a bank a few metres high at the edge.

Suggested: lower the apron along the river's line past the edge (a channel strip in the apron
mesh at the river's level, and the water strip carried on with it), or fade the river into a
gorge's end. Looks only.
## F-162: the building scan misses the middle of a big open hall (a hangar)

Location: [buildings.gd](../../scripts/ai/buildings.gd) (`inside`: PROBE_M, MAX_OPEN). Found by
cghath's agent on `world/landmarks` (2026-10-21, queue item 1.4); the file is Claude's, so it
isn't changed there.

What happens: a spot counts as inside when at most MAX_OPEN (2) of its 8 level rays reach PROBE_M
(12 m) without a wall. A hangar's hall is about 19 x 17 m with a 14 m door, so from its middle
most rays run 12 m without meeting a wall: only its back corners and office read as a building
(the landmarks suite scans one from its office: 1 room, 3 entrances). A factory floor (up to 18 x
16 m) is on the edge of it. The AI won't garrison or clear a hangar's hall room by room.

Suggested: count a spot as inside when a ray straight up meets a roof within a few metres and the
walls it does meet enclose it (e.g. rays to 24 m for a spot under a roof), or let a building's
rooms grow from its walls inward. A test: `BuildingGen.building("hangar", 5)` stood up as in
tests/landmarks_test.gd, scanned from the hall's middle.

## F-178: point the roadside props at the new roads (cghath's side, queue item 1.7)

Location: [zone_props.gd](../../scripts/world/zone_props.gd), `street_lines()`.

What happens: roadside poles, signs, parked cars and checkpoint barriers go along today's straight
`def.roads` segments, 5 m wide (`ROAD_HALF_M`), and a town's furniture along BuildingGen's main
and cross streets. The roads work (zone_roads.gd) will give roads curves, kerbs and pavements.

Suggested: return the new road edges (and pavements, with their half width) from
`street_lines()`; everything roadside follows. Town lamps and stalls could then stand on the
pavements instead of the street's edge.

## F-179: a round into an animal makes a "vehicle" hit (Ballistics)

Location: [ballistics.gd](../../scripts/combat/ballistics.gd), the `on_bullet` branch;
[zone_animals.gd](../../scripts/world/zone_animals.gd) uses it.

What happens: an animal is hit through Ballistics' `on_bullet` meta (as a drone is), which
returns `{"result": "vehicle"}`, so the shooter's impact effect is the one for metal, not flesh.
The animal dies (and lies down) on every peer either way.

Suggested: let an `on_bullet` callable return the result kind ("animal": a blood puff), or add a
meta for it.

## F-180: props can't be knocked down or destroyed

Location: [zone_scatter.gd](../../scripts/world/zone_scatter.gd) (static bodies per cell).

What happens: like the rocks, trees and old box props before them, library props are static and
deterministic from the zone's seed: a blast doesn't flatten a fence or a stall, a vehicle doesn't
push through a chain-link fence (it senses it as an obstacle), and nothing about them is saved.

Suggested (later, with structural collapse, queue item 13): destructible light props (fences,
stalls, awnings, washing lines) as a host-saved "gone" set per zone, like the voxel edit log.

## F-190: the woods' GPU frame time is unmeasured

Location: [forest_test.gd](../../tests/forest_test.gd) `_test_dense_normal`, `_drawn`. Found by cghath's agent on
world/perf (2026-10-22, queue item 1.8).

The suites run headless (no renderer, no window, so nothing pops up while the Captain plays), so the woods perf pass
measured what the GPU is given, not how long it takes: draws, triangles in view range and the shadow pass's triangles
from a dense copse (590 -> 435 draws, 1.70M -> 0.64M triangles), the main thread's frame standing in the copse, and the
AI's and navigation's woods costs. The Captain's 4 -> 10 ms in woods was a windowed number.

Suggested: in the next test build, stand in a dense copse on a normal zone (temperate, river_valley) and in the
Experimental forest and read the frame time and the monitor's draw calls and primitives; tune `ZoneScatter.LOD_M`
(200 m), `NEAR_BUILD_M` and the shadows setting from there.

## F-191: claude/perf-pass and world/perf change the same ZoneScatter functions

Location: [zone_scatter.gd](../../scripts/world/zone_scatter.gd) `build_near`, `_process`, `_build_cell`, `_build_far`.
Found by cghath's agent on world/perf (2026-10-22).

claude/perf-pass (not merged yet) builds one queued cell a frame (`_wanted_near`, `_queued`), scales the draw ranges by
the detail setting (`_range_scale`, far blobs' `far_trees_m`) and narrows `_ground_blocked`; world/perf builds each cell
in two tiers (`Tier.NEAR` / `Tier.FAR`; `_wanted_near` returns [cell, tier] pairs) and groups the far blobs in
blocks that are the far tier's visibility parents.

Suggested, for whoever merges second: queue [cell, tier] pairs (world/perf's wants) one a frame (perf-pass's
`_queued`); scale LOD_M, the near tier's end, the far tier's begin, SEE_TREE_M and the blobs' begin by the same
detail share, so the tiers still hand over at one distance (the forest suite's "every cell's trees drawn exactly once"
check catches a gap); keep perf-pass's `_ground_blocked`.

## Calls made for the Captain

One line each, newest last (docs/cg_brief.md, rule zero): date | what was decided | why | the alternative.
2026-10-21 | Deep water: players swim (1.1 m/s, 0.5 under a full load, head out, hands busy, the current carries them, no drowning); the AI never routes into it (deep water is off its navigation mesh) and crosses on bridges and fords | Arma 3, the realism bar, has men swim, and rivers that block outright read as more map edges | an invisible wall at deep water, or drowning with a breath meter
2026-10-21 | Wading pace (Wading): 1 - 0.7 x ((depth - 0.1) / 0.9)^0.8 of the pace (knee-deep 0.63, waist-deep 0.3), no sprint past 0.6 m, no prone past 0.45 m, the current pushes at half its speed (Proposed consts) | wading is hard work, more so the deeper | a flat 50% in any water
2026-10-21 | Bridge damage: each span has health in carve-radius-cubed units (a demo block, 1.8 m, does 5.8 on contact; 105 mm HE 1.5); concrete span 12 (3 blocks, ~8 HE), steel truss 8 (2 blocks, ~6 HE), footbridge 2 (1 block); blasts under 0.5 m carve do nothing (Proposed, ZoneBridges.TYPES) | demolitions and fire support both drop spans, charge counts near real while playable | voxel bridges through the voxel damage path (a VoxelWorld per bridge streamed across the zone), or one health for a whole bridge
2026-10-21 | Crossings: every road over a river gets a vehicle bridge (concrete 60%, steel truss 40%, by the seed), a road over a stream a culvert (65% where it's 7 m wide or less) or a ford, and the river a ford or footbridge (half each) in every 450 m without a crossing (data: "water" in data/terrain_presets.json) | keeps both banks joined for the AI's paths and the squad | bridges only where roads cross (half a zone cut off from the AI)
2026-10-21 | Which presets have water: river_valley a river edge to edge (22-30 m wide, 2.1 m deep), 1-2 streams and 1-2 ponds; temperate 0-1 stream and 0-2 ponds; highland_moor 2-3 burns, 0-1 tarn and ponds; coastal_lowland 0-2 ponds; scrubland 0-1 stock pond; desert, badlands, salt flats, rocky ridge and the test grounds none (their wadis stay dry) | the hot zones' presets (rocky_ridge, salt_flats) and the dry country keep their ground; rivers where the land is wet | a river on every preset
2026-10-21 | river_valley's dry wadi is gone for the river; its "wadi groves" grow in a 45 m band along the river and streams instead (the terrain's bed weight, under the sand tint) | its riverside woods stay | no groves on river_valley

- 2026-10-21 | Landmarks go by data/landmarks.json: the tags that exist (mosque, harbour, oil, airfield, fields) plus route: a fuel station, crossing: a garage, hq: an office, airfield: a fuel depot too; church, school and factory (no tag names them) by zone id | the brief says where its tag already says, and only five tags name landmarks | new asset tags in contracts.json, or towns with landmark lots
- 2026-10-21 | The drug lab and IED workshop stand in the zones of the groups whose factions.json site_names call their cache that (by the zone's starting holder), as landmarks with a garrison, not yet a contract's target | gives the names their geometry without changing any contract board | make them the raid's cache site (changes boards and their tests)
- 2026-10-21 | At most 4 landmarks a contract zone and 6 a hot zone, in a fixed order (mosque, harbour, oil field, airfield, farm, drug lab, IED workshop, fuel depot, office, fuel station, garage, school, church, factory) | room in 2-4 km zones and the extra garrisons | every tag's landmark in every zone
- 2026-10-21 | Ruined landmarks: 20% ruined and 8% bombed out in contract zones, 35% and 30% in hot zones (by the zone's seed) | hot zones are the war's front | ruin by the faction war's damage over time
- 2026-10-21 | A harbour's quay edge at 0.55 of the sea's width in from the zone's edge, its land built up 1.6 m over the water, piers 30 m out | water under the piers on every coast preset (checked on six zones) | measure the shoreline per zone and fit the quay to it
- 2026-10-21 | The airfield's runway is 240 x 22 m painted on the ground, not voxels | a module's voxels must stay within its streaming range, and it's a strip for light aircraft and helicopters | a 600 m+ runway, or voxel slabs
- 2026-10-21 | A minaret is solid; tanks and silos are hollow with a floor every 1.5 m inside | no closed room the navmesh bakes and the AI thinks is a building | a hollow minaret with a stair up (later)
- 2026-10-21 | The control tower is two storeys (the generator's limit) with a console room on top and a mast | storeys over two come with city zones (queue item 1.5) | a third-storey glazed cab now
- 2026-10-21 | Landmarks are garrisoned like other sites: a post inside each front door, one up high, one in a back room, the site's own (2-9 posts) | the brief says garrisonable like today's types | civilian-only landmarks
- 2026-10-21 | Upper-floor doorways slide along their wall off the stairwell (or another wall takes the doorway): some existing two-storey buildings' doorways move | a doorway over the stairwell cut its room off | leave existing buildings as they were
- 2026-10-21 | Prop library (1.7): today's outdoor set counted as 25 shapes (the scatter's 8 natural and 6 box props, the modules' 11 outdoor dressings), so "triple" means 75+; the library adds 72 (69 static props, 3 animals): 97 | the brief's own "about 25" | count only the scatter's 6 man-made props (18 would have done)
- 2026-10-21 | Prop library: each part takes rounds by its own material (PropArt.MATERIALS, Proposed): a car's cabin and boot 600 J/m (an M855 goes through, a 9 mm stops), its engine bay stops everything, a container 450 J/m (through its width, not its 6 m length), hay 3500, a full tank 4000, wood, sheet and mud as VoxelWorld's | Arma/ACE: car bodies don't stop rifle rounds, engine blocks do | every prop hard cover, as the old box props were
- 2026-10-21 | Prop library: chain-link and barbed wire collide on Soldier.BODY_LAYER only: they stop men (and vehicles sense them) but not sight lines or rounds | you see and shoot through wire mesh | solid on the world layer (the AI would hide behind a mesh fence)
- 2026-10-21 | Prop library: animals are walked by the host and sent 4 times a second in one unreliable packet (Proposed); a hit kills one; no fleeing, not saved | the brief: wandering only, synced, cheap | a deterministic walk from a shared clock (no packets, but no shared clock to drive it yet)
- 2026-10-21 | Prop library: scenery vehicles are built from flat-shaded blocks (boxes, wedges, drums) that collide exactly as drawn, not from VehicleArt's 5 cm voxel canvases | collision has to match what's drawn, and one mesh per shape batches | VehicleArt-style canvases (finer, but collision would only approximate them)
- 2026-10-21 | Prop library: placement by terrain style in data/props.json (temperate, woodland, highland, coastal, arid; a procedural mix takes its first preset's style), Proposed densities: 0.2-0.55 farms a km2, 0-2 pylon lines, poles on 45-70% of roads, 0.9-1.4 vehicles per km of road (35-50% burnt out) | towns lived-in, the country with power and farms | per-preset numbers in terrain_presets.json (shared with the terrain work)
- 2026-10-21 | Prop library: a town's street furniture stands on its streets inside the town's pad, clear of every box, guard post, loot spot and civilian walk (the world suite's "nothing on a pad" allows it) | that's where a town's streets are | keep every prop off the pads (towns stay bare)
- 2026-10-21 | Prop library: pylons every 95 m, roadside poles every 38 m, wires sag 3% of their span (Proposed consts in ZoneProps and ZoneScatter) | a 2-4 km zone shows several spans | real 300 m pylon spacing (6-10 pylons a zone)
- 2026-10-21 | Prop library: the old box car wreck becomes a burnt-out hulk where it fits (same spot and heading), and scatter props no longer count as foliage (they hid people like bushes on top of being solid) | the brief: real shapes in place of box wrecks; props are solid | keep both
- 2026-10-21 | Prop library: the screenshots are drawn by a small software rasteriser in tests/props_shots.gd (headless has no renderer and no window may open) | the brief's "headless screenshots" | tests/world_shots.gd in a real window
- 2026-10-22 | Prop library: a helicopter climbs over a tall library prop (6 m and up: pylons, masts, poles' tops) it would pass within its rotor reach of, from ZoneScatter.tall_top (one call in Helicopter.obstacle_top); the lattice is too thin for its rays (heliflight harbour_yard flew into a pylon on CI) | pilots know where the pylons are | keep pylon lines away from every LZ and approach (unknowable: the LZ is picked in dead ground near the objective)
- 2026-10-22 | Prop library, merged with the water and landmarks work: props keep off ZoneWater.keeps_clear (water, wet banks, bridges) like the rest of the scatter; a power line whose footing falls in water skips it and its wires span the gap (two steps); landmark sites get no site kit (they build their own props) and countryside farms keep FARM_GAP_M from a landmark farm | the coordinator's merge brief | move a wet footing to the bank (the line would kink)
- 2026-10-22 | Woods perf pass: each cell drawn in two tiers, the full trees, thickets and scrub to 200 m (LOD_M) and low-poly stand-ins (crown 44 triangles, thicket 38, square trunk 8) out to 950 m, blobs past that (Proposed) | the woods' cost was triangles (1.7M from a dense copse); a four-tier crown 300 m off is a few pixels | Godot's automatic mesh LOD (per MultiMesh, not per tree) or flat impostor cards (wrong in the blocky look)
- 2026-10-22 | Woods perf pass: far blobs one MultiMesh a block of 2 x 2 cells, each block the visibility parent of its cells' far-tier trees (hierarchical LOD) | a quarter of the blob draws, and a tree is never drawn twice or missing | a blob MultiMesh a cell, or bigger blocks (blobs from 770 m)
- 2026-10-22 | Woods perf pass: the caps nobody sees (inside the tier above, under the ground, inside the crown) left out of the crown, conifer, scrub, trunk and blob meshes | free triangles, the look unchanged | keep them
- 2026-10-22 | Woods perf pass: foliage and solids indexed in 16 m squares (FINE_M, Proposed) and the sight-line walk stops once both lines are hidden (Spotting.foliage_m passes FOLIAGE_OPAQUE_M; the value is exact below it) | a sight line through a dense wood 10x cheaper, the AI's foliage cost in a fight 9.0 -> 0.4 ms a frame, every decision the same | a cache of sight results per pair (stale as men move)
- 2026-10-22 | Woods perf pass: collision left as it was (a body a cell, every trunk, big rock and prop as drawn) | rays through dense woods cost 5-7 us and the build is once at load; building shapes without nodes would change the props suite's round_through owners | shape owners without CollisionShape3D nodes
- 2026-10-22 | Dense copses (copse_cover and its caps) in every wooded normal preset (temperate, river_valley, highland_moor, coastal_lowland, amphibious_coast, rocky_ridge, scrubland); temperate and river_valley woods 2.1 and copses 6 a km2 (forest 2.4 / 6) (data, Proposed); the dense layout's thicket cap 11000 -> 16000 (CAP_THICKETS), as a 16 km2 hot zone ran out before its last copses had their skirts (world: 130 of 256 lines through woods hidden, R0506) | Captain: "Then denser copses" once the woods were cheap | only the Experimental forest dense; desert_wadi, badlands and salt flats keep their small copses (copse_cover's default copse is 35-110 trees)
- 2026-10-22 | F-121: the voxel world's edit area grows to hold a level's structures (VoxelWorld.fit_structures, called by CompoundLevel), not the range's blocks moved | vehicle_range.gd is Claude's, and any level's structure past 22 m is built too | move the blocks to z -18 and -21
- 2026-10-22 | Woods perf budgets in the forest suite (Proposed): from a normal preset's densest copse 600 draws, 700k triangles, 200k in the shadow pass; a capped sight line 400 us; a nav chunk 0.5 ms; standing in the forest's densest copse 25 ms a frame on average, 60 ms at the 95th percentile; a scan round of 16 men 30 ms | room for CI's slower runners over this PC's numbers | frame budgets only (noisy on a shared PC)
