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
| F-210 | P2 | A city's street grid isn't paved: ZoneRoads doesn't draw the def's `"cities"` streets (ZoneModules.city_streets), junctions or kerbs, and its own roads aren't joined to them (city zones, 2026-10-22) |
| F-211 | P2 | One AI building scan near a city's tall buildings takes 150-450 ms, and a frame's first scan isn't capped (Buildings.FRAME_BUDGET_USEC): a fight in a city hitches (city zones, 2026-10-22) |
| F-212 | P3 | A town's or landmark's stair (0.5 m approach) can be cut off from a zone's navmesh, depending on how its pad's height falls on the bake's 0.25 m grid (city zones, 2026-10-22) |
| F-213 | P3 | The AI's navmesh paths (map_get_path, 4096 polygons at most) from the street to a tall tower's top floors stop a floor or two short until it re-paths (city zones, 2026-10-22) |
| F-162 | P3 | ~~The AI building scan misses the middle of a big open hall (a hangar: rays reach 12 m with no wall), so it isn't garrisoned or cleared room by room (landmarks, 2026-10-21)~~ fixed 2026-10-21 (Claude, claude/ai-followups: a roofed spot probes to 26 m) |
| F-221 | P3 | The woods' GPU frame time is unmeasured: the forest suite counts draws and triangles headless (no renderer); a windowed frame time in a dense copse wants a build on a real GPU (woods perf pass, 2026-10-22) |
| F-222 | P2 | claude/perf-pass and world/perf both change ZoneScatter's build_near, _process, _build_cell and _build_far: whoever merges second keeps both (woods perf pass, 2026-10-22) |
| F-223 | P3 | An AI-driven vehicle turning round beside the range's concrete blocks runs into one and never makes the pickup (vehicle AI; the blocks exist since F-121) |
| F-140 | P2 | ~~Ambushers by a road and a friendly convoy driving past (missions 2 overwatch)~~ fixed 2026-10-21 (Claude, claude/ai-followups: RoadAmbush, the convoy's drive-through; the mission's two calls are F-178) |
| F-176 | P2 | ~~The dug ground never comes back from a zone save~~ fixed 2026-10-21 (Claude, claude/ai-followups) |
| F-178 | P2 | The overwatch mission (feat/missions-2) should lay its ambush teams with `RoadAmbush.server_lay` and drive its convoy with `SquadDrivers.server_drive_route` (two lines in MissionScenario) |
| F-179 | P3 | Players can't fire the hand flare (it's loot only), and the M320's 40 mm star round waits on F-130 (the AI grenadier) |
| F-190 | P1 | ~~A squadmate following along a path walks head-on into a wall's end and stands there pushing~~ fixed 2026-10-22 (Claude, claude/ci-cleanup: SquadAI._unblock; F-80's collection-point half was the test's point) |
| F-191 | P3 | A shot-down transport's crash landing with two aboard killed both (supports suite, CI once; "most of them alive") |
| F-192 | P2 | Following the player through the compound's building, a squadmate on the follow-in stack can run a loop round the building on his way to his stack place (casualty soak, CI only, now and then) |
| F-193 | P3 | base_zone: the player is down on landing after the helicopter insertion, and the walk home and the rest of the deployment fail after it (CI only, now and then) |
| F-163 | P3 | A helicopter insertion came 4.9 m from the ground, inside its 5 m airframe clearance, before the final (loop suite, kestrel_valley, world/landmarks' CI once) |
| F-214 | P2 | A convoy ambush's convoy drives its own straight-ish line across the zone, not the roads (scenario_gen `_convoy`) |
| F-215 | P3 | Vehicle grip ignores the surface: asphalt, a dirt track and open ground all grip alike (Vehicle `_wheel_forces`, Claude's file) |
| F-216 | P3 | AI drivers can go round a roundabout the wrong way, and RoadRoute's graph has no one-way edges (Claude's files) |
| F-217 | P3 | A crater or a dug pit on a road leaves the road's surface hanging over the hole (GroundCuts doesn't tell ZoneRoads) |
| F-218 | P3 | ~~A helicopter's J-hook can come over a natural hump 4 m clear (heliflight ridge_hot insertion 1)~~ fixed 2026-10-22 (cghath's agent, world/roads: Helicopter._contour) |

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

Status (2026-10-22, world/roads, queue item 1.2): done. The roads are now planned (RoadNet) after the
water, which plans its crossings over the links the roads take (`RoadNet.water_links`, handed to
ZoneWater.carve by ZoneTerrain.generate). Each road runs straight through the bridge on its link
(fixed control points from the bridge's `xform`/`length`), its profile pinned to the deck's top and
down the ramps; those samples are neither laid (no strip, no collision: the bridge's own deck and
collision carry it) nor graded. Fords and culverts stay ground the road follows. roads suite
"every road bridge carries its road" checks it on Kestrel Valley.
## F-140: ambushers and a friendly convoy driving past (fixed 2026-10-21)

The write-up is on cghath's feat/missions-2 (its followups.md, F-140): the overwatch mission's
ambush teams were plain Reinforcements waves wandering a 12 m loop round their spot, in Aware,
and nothing in the AI knew to wait for the convoy.

Fixed on claude/ai-followups (Claude, 2026-10-21):
- [road_ambush.gd](../../scripts/ai/road_ambush.gd) `RoadAmbush` (a GarrisonPost): laid with
  `RoadAmbush.server_lay(men, point, route)`. Each man gets his own spot on a line along the road
  (5 m apart), in cover against the kill zone (the road's nearest stretch), down and facing it,
  holding fire. No patrolling and no going to look at a sound. It springs when the first crewed
  enemy vehicle comes level with it (its closest pass, within 160 m) or anything comes within
  35 m. It springs sooner when it's given away: one of them fired on or down, or found by an
  enemy on foot within 30 m. Sprung, every man opens up, the guns' gunners and crews first
  (`target_bonus`), the launchers at the lead truck and then the last (`priority_vehicle`,
  LauncherAI). They fight from their own ground (the leash) and break and run when outgunned
  (GarrisonPost's flight).
- The convoy: [squad_drivers.gd](../../scripts/vehicles/squad_drivers.gd)
  `server_drive_route(v, path, speed_kmh, squad)` drives a truck as an order, so DriveContact
  meets the ambush: it always drives through, faster, the gunner firing on (AavGunner). Disabled,
  its crew bail out to the side away from the fire and hold there (a convoy's crew aren't squad
  members, so they get the move themselves). An order keeps the last threat it met, so a truck
  disabled once the firing has died down still bails its crew out away from it.
- Firing at a man in a vehicle (SquadAI `_gate_open`, `_shoot`): the sights need only be on the
  vehicle (VEHICLE_GATE_SHARE of its hull's size), since a round that misses him still hits it, and
  the shot leads it by its speed. Before, a truck passing at 18 m/s never let the man-sized aim gate
  open, so nobody fired at all. `SquadAI.shoot_blocker()` now names whatever stops a shot.
- AavGunner now needs to make a man out before it fires (Spotting.spot_seconds, as SquadAI): an
  M2 gunner saw anyone in a clear line at once, which gave every ambush away at 600 m.
- The mission's side is F-178. tests/garrison_test.gd checks it with an M-ATV on a road past
  three ambushers.

## F-178: the overwatch mission's two calls

Location: cghath's feat/missions-2, `MissionScenario._overwatch_begin` and `_overwatch_spawn`.
Claude's side is built (F-140); the mission isn't merged, so it isn't changed there.

To do: in `_overwatch_begin`, after `r.server_send(at, 0, men, at)` for each ambush, lay them with
`RoadAmbush.server_lay(those_soldiers, at, route)` (route: the run's PackedVector3Array). In
`_overwatch_spawn`, in place of `v.server_follow_path(path, speed)`, use
`SquadDrivers.of(level).server_drive_route(v, path, speed, element)` (falling back to
`server_follow_path` if it returns false). Nothing else changes: the mission's own `_neutralized`
dismount and its through/lost counts still work.

## F-179: hand flares for players, 40 mm star rounds

The hand-held parachute flare (`hand_flare`, G-24) is fired by the AI only. A player who takes one
off a body can't fire it (it isn't a throwable; it wants its own use input). The M320's 40 mm star
parachute round would light the same way (Flares "hand"), but the AI never fires the M320 (F-130).

## F-176: the dug ground never comes back from a zone save

**Fixed 2026-10-21** (Claude, claude/ai-followups): `read_save` copies "ground", every cut checked
(`Digging.cut_ok`: a known kind, every field a finite number) and every berm (`Digging.berm_ok`); a
bad record is dropped with a warning and the rest loads. tests/world_test.gd reads the save back
and finds every cut and berm after the reload, none dug afresh on top.

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

**Fixed 2026-10-21** (Claude, claude/ai-followups): a spot too open for the usual probes counts as
inside when a ray straight up meets the underside of a roof within 12 m and, probing out to 26 m,
at most 3 of the 8 ways are open and no two opposite (`Buildings.inside`, `_hall_inside`,
`roofed`). A canopy with no walls stays outside. The landmarks suite scans a hangar's hall and a
factory floor from their middle (R2350: 153 of about 284 and 171 of about 196 floor cells).

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
## F-214: a convoy ambush's convoy doesn't drive the roads

(Logged on world/roads as F-190, an id claude/ai-driving also used; renumbered 2026-10-22.)

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

## F-215: vehicle grip ignores the surface

(Logged on world/roads as F-191, an id claude/ai-driving also used; renumbered 2026-10-22.)

Found by cghath's agent on `world/roads` (2026-10-21). Location:
[vehicle.gd](../../scripts/vehicles/vehicle.gd) `_wheel_forces` (Claude's file, so roads didn't
change it): `grip := GRIP * ...` is the same on every surface.

The roads now give the wheels' rays something to read: every road body (ZoneRoads) has a
`PhysicsMaterial` (friction 1.0 on asphalt and concrete, 0.75 on dirt, data/roads.json) and the
meta `road` ("asphalt"/"dirt"). Suggested: multiply the grip by the hit collider's
`physics_material_override.friction` when it has one, and by a Proposed 0.7 on the terrain
(ZoneTerrain), so tyres hold best on asphalt and slide sooner off-road. A wet-weather factor
(DayNight) could come later.

## F-216: roundabouts are two-way to the AI drivers

(Logged on world/roads as F-192, an id claude/ai-driving also used; renumbered 2026-10-22.)

Found by cghath's agent on `world/roads` (2026-10-21). Location:
[road_route.gd](../../scripts/vehicles/road_route.gd) `_graph` and
[vehicle_ai.gd](../../scripts/vehicles/vehicle_ai.gd) (Claude's files).

A roundabout is in the def's "roads" as a ring of RoadNet.RING_SIDES pieces (in order, corner k
to corner k + 1), with the arms ending on its corners. RoadRoute's graph is undirected, so a
route round the ring takes the shorter way, which is the wrong way half the time. Suggested: give
ring pieces (both ends within the ring's radius of one centre) one direction only in `_graph`
(the def order is the driving direction), and have VehicleAI slow to a Proposed 20 km/h through a
turn of more than 30 degrees.

## F-217: a crater on a road leaves the road hanging

(Logged on world/roads as F-193, an id claude/ai-driving also used; renumbered 2026-10-22.)

Found by cghath's agent on `world/roads` (2026-10-21). Location:
[ground_cuts.gd](../../scripts/world/ground_cuts.gd) `_cut_area` / `_rebuild_around` and
[zone_roads.gd](../../scripts/world/zone_roads.gd).

A blast or a dig cuts the terrain under a road, but the road's mesh and trimesh collision stay
whole, so the road surface spans the crater (an IED on a road leaves no hole in it). Suggested: a
small hook in GroundCuts after a cut, `ZoneRoads.of(self).cut(area)`, that rebuilds the road
tiles touching `area` without the triangles over cut cells (ZoneRoads keeps its geometry per
TILE_M tile, so it's one tile's mesh and body each time).

## F-218: a J-hook over a natural hump comes in 4 m clear

(Logged on world/roads as F-194, an id claude/ai-driving also used; renumbered 2026-10-22.)

Found by cghath's agent on `world/roads` (2026-10-22, queue item 1.2): CI run 39729719130 (commit
0ca5246) and local run R0507, heliflight "ridge_hot insertion 1: the airframe at least 5 m clear
until the final, 4.0 m at the least (at (-1737, 14.1, 1938) 78 m to go, 61 km/h)". Location:
[helicopter.gd](../../scripts/supports/helicopter.gd) (the J-hook's descent, `hook_plan`) and
[heli_flight_check.gd](../../tests/heli_flight_check.gd).

The ground there is natural (a 7.3 m hump 77 m short of the LZ at -0.8 m; no road within 30 m,
none graded: checked against the terrain before and after the roads). The roads branch changes
nothing on that line; what changes is the zone's scatter (ridge_hot gains a road joining its town
and landmark to the network, so trees and rocks land elsewhere), and the hook flown over the hump
no longer has whatever stood there keeping it higher. Suggested: let the hook's descent look ahead
at the terrain under the rest of its path (obstacle_top along the next points), not only what stands
on it, so it holds 5 m over a hump on the way down.

Rechecked 2026-10-22 with the prop library merged (ZoneScatter.tall_top in obstacle_top): the
same 4.0 m at the same spot (local R0520). No tall prop stands there, so tall_top doesn't bind. A
closer look: the hook already looks ahead along its own points (_contour, _ahead, _need_y with
footprint_ground), and at the hump its own need is about 17 m (ground 7.3 m + MIN_CLEAR_M 5 +
CLEAR_MARGIN_M 2 + about 2.8 m of airframe drop); it flies 14.1 m. So it plans the height and
doesn't make it in time: the ground climbs 15 m in 64 m (23%) while it's coming down the glide
slope at 61 km/h. That's the climb and steering response (CONTOUR_CLIMB, _climb_to, _steer),
not a missing look-ahead, so it's left for the helicopter side rather than tuned here.
Suggested: plan the hook's climb at a lower share of CLIMB_MS when it's sinking (or slow the
hook where the ground ahead rises faster than the glide slope).

Fixed 2026-10-22 (world/roads), in Helicopter._contour, two small changes. The cause: held to
where it was (the binding point "now"), its rate was the change of need one second ahead, and over
the rise the glide slope's need fell ahead faster than the ground rose, so the rate came out
negative (-7 m/s) and cancelled the climb term: `_climb_to` gave 0 and it sat level 2.5 m under
its own need from 100 m to go to 78 m. Now (1) below its need that rate is never negative, and (2)
on the J-hook while sinking it plans the rise ahead at HOOK_SINK_CLIMB (0.5) of its climb, so it
starts up sooner. ridge_hot insertion 1: 5.5 m at the least (4.0 before; 5.3 with (1) alone).
The 5 m minimum is unchanged.

## F-219: point the roadside props at the new roads (cghath's side, queue item 1.7) (done 2026-10-22)

(Logged on world/props as F-178, an id claude/ai-driving also used; renumbered when the two met on world/roads.)

Location: [zone_props.gd](../../scripts/world/zone_props.gd), `street_lines()`.

What happens: roadside poles, signs, parked cars and checkpoint barriers go along today's straight
`def.roads` segments, 5 m wide (`ROAD_HALF_M`), and a town's furniture along BuildingGen's main
and cross streets. The roads work (zone_roads.gd) will give roads curves, kerbs and pavements.

Suggested: return the new road edges (and pavements, with their half width) from
`street_lines()`; everything roadside follows. Town lamps and stalls could then stand on the
pavements instead of the street's edge.

Status (2026-10-22, world/roads, queue item 1.2): done. `street_lines()` returns the planned
roads: the def's "roads" pieces once ZoneRoads has planned them (the curves as straight pieces
within 1 m, each naming its kind), each line's `half_w` its kind's half width (RoadNet.half_width:
asphalt 3.5 m, dirt 2.1 m, a town street's carriageway 3 m), so a line's edge is the road's edge as
`ZoneRoads.edges()` has it and every roadside prop (poles, parked cars and hulks, checkpoint
barriers and signs, direction signs, bus shelters, billboards) follows the curves and keeps off the
road's surface. The pieces rather than ZoneRoads itself because the scatter's layout cache keys on
them and the props are laid where no ZoneRoads node is reachable (the cache, a test terrain). The
lines are indexed by 64 m cell (`_lines_near`): hundreds of short pieces against the old few
links. The town's furniture already stands on the new pavements (lamps 0.35 m and poles 0.25 m
in from the street rect's edge; the pavement runs from 1 m in to 1 m out); stalls and benches set
against the street's edge still overhang the carriageway by up to a metre (not moved).

## F-220: a round into an animal makes a "vehicle" hit (Ballistics)

(Logged on world/props as F-179, an id claude/ai-driving also used; renumbered on world/roads.)

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

## F-221: the woods' GPU frame time is unmeasured

Location: [forest_test.gd](../../tests/forest_test.gd) `_test_dense_normal`, `_drawn`. Found by cghath's agent on
world/perf (2026-10-22, queue item 1.8).

The suites run headless (no renderer, no window, so nothing pops up while the Captain plays), so the woods perf pass
measured what the GPU is given, not how long it takes: draws, triangles in view range and the shadow pass's triangles
from a dense copse (590 -> 435 draws, 1.70M -> 0.64M triangles), the main thread's frame standing in the copse, and the
AI's and navigation's woods costs. The Captain's 4 -> 10 ms in woods was a windowed number.

Suggested: in the next test build, stand in a dense copse on a normal zone (temperate, river_valley) and in the
Experimental forest and read the frame time and the monitor's draw calls and primitives; tune `ZoneScatter.LOD_M`
(200 m), `NEAR_BUILD_M` and the shadows setting from there.

## F-222: claude/perf-pass and world/perf change the same ZoneScatter functions

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

## F-223: an AI vehicle turning round next to an obstacle doesn't get clear

Location: [vehicle_ai.gd](../../scripts/vehicles/vehicle_ai.gd) (the obstacle and stuck handling: `_obstacles`,
`_back_off`, `_go_round`); [squad_drivers.gd](../../scripts/vehicles/squad_drivers.gd) `server_pickup`. Found by
cghath's agent on world/perf (2026-10-22) once F-121 built the range's blocks; the files are Claude's.

What happens: the vehicles suite's squad drivers drove the M-ATV to (-12, -20), facing south, then ordered a pickup
at (10, 4). Its turn round to the right swings through about (-6, -29), the concrete block at x -8..-6, z -30..-29:
it was "blocked", backed off and went round, and 30 s later sat about 38 m from the commander; "Follow me" after it
failed the same way (R0534; with the blocks left unbuilt it passes, R0537). The suite now drives to (-12, -14), clear
of the blocks, and its path with a turn goes along z -36. Its "Follow me" then waits out the RPG hit
(SquadDrivers.CONTACT_S) before the order: given sooner it met the hit as contact and halted, depending on how fast
the squadmate got out (R0550). The suite passes (R0553).

Suggested: when a goal is behind it and something is beside the turn, back up and turn (a three-point turn), or
plan the turn on the navmesh, which has the blocks.

## F-185: vehicles aren't slowed by marsh mud or snow

Location: scripts/vehicles/* (Claude's). Found by cghath's agent on `world/terrain` (2026-10-22,
queue item 1.3). Men on foot are (Wading.ground_mult, ZoneFeatures.slow_at); a truck drives
through the fen and the snow at full speed.

Suggested: a vehicle reads `terrain.features.soft_at(x, z)` and `snow_at(x, z)` (both 0..1, 0 on
roads and pads) under its wheels or tracks and loses grip or top speed by them (wheels more than
tracks). Public, no changes to ZoneFeatures needed.

## F-186: the map doesn't show the fields, the marsh, the snow or ice

Location: [map_render.gd](../../scripts/ui/map_render.gd) (`zone_inputs`, `compose_zone`). Found
on `world/terrain` (2026-10-22, 1.3). The map paints height, contours, trees, roads and open water
(ZoneWater.surface_grid); frozen streams and ponds aren't in that grid, and the fields, soft ground
and snow are only in the ground's vertex colours.

Suggested: pass a coarse grid of ZoneFeatures' layers (field_at's crop, soft_at, snow_at) and the
ice (ZoneWater._ice) into zone_inputs and tint the map by them (a field pattern, marsh hatching,
white over the snow line, pale-blue ice). A test in tests/map_test.gd on Harrow Fields.

## F-187: farmland's fields and the props' farms don't know each other (done 2026-10-22)

Location: [zone_features.gd](../../scripts/world/zone_features.gd) and `origin/world/props`'s
zone_props.gd (PR #22, not merged into world/terrain). Found on `world/terrain` (2026-10-22, 1.3).
The fields, orchards, hedges and irrigation channels are ZoneFeatures' own; once the props branch
merges, its farmsteads (_farm: pens, field fences, hay, irrigation props) are laid by its own field
grid, and the farmland, marsh and snow presets fall back to its default prop style.

Suggested: after both merge, add "farmland" (more farms), "marsh" and "snow_mountain" to
data/props.json "preset_styles", and let ZoneProps._farm put its field fences and gates along
ZoneFeatures' field edges (field_cols, field_rows, row_shift, _from_grid) and keep its props off
the fields (ZoneFeatures.keeps_clear) and the channels.

Done (world/terrain, 2026-10-22, after the roads/props merge 863ac43): data/props.json maps
farmland to a new "farmland" style (more farms, more hay, no prop irrigation: the zone's channels
are the irrigation), marsh to "woodland" and snow_mountain to "highland". ZoneProps keeps every prop
but the power lines' pylons and poles out of a crop field (ZoneFeatures.field_at, reject "field"),
lays its farmsteads on the rough ground off the fields, and runs a farm's field fences and gates
down the lanes along the 2-5 nearest field sides (ZoneFeatures.field_sides_near, within 170 m).
Fields keep off the planned roads and their verges (ZoneTerrain.road_weight). The talus and the
orchards' trees keep off the props. terrain_test's farmland check counts what stands in a field.

## F-188: crops and reed beds are plain blocks; their cover counts near the ends of a line only

Location: [zone_features.gd](../../scripts/world/zone_features.gd) (`_crop_cell`, `_reed_cell`,
`cover_least`). Found on `world/terrain` (2026-10-22, 1.3). Crops are drawn as voxel-style blocks
in rows within 170 m (reeds 260 m), with no wind sway and no trampling; past that the ground's
colour carries the field. For spotting, crops and reeds count only within 25 m of either end of a
line (a man in a field, or a watcher in one), not a field crossed in the middle of a long line.

Suggested: an art pass on the crop blocks (stalks, ears, maize tassels) and a cheap sway in a
shader; walk the whole line through fields with a field-crossing test on the grid if a playtest
finds men seen through a field between them.
## F-189: a helicopter doesn't settle on an LZ of 10-12 degrees on rugged ground

Location: scripts/vehicles/helicopter.gd / scripts/supports/heli_flight.gd (Claude's), and
[landing_zone.gd](../../scripts/supports/landing_zone.gd). Found on `world/terrain` (2026-10-22,
1.3), CI run 39755429759 (0defd900), the loop suite on Whitecap Pass (snow_mountain): the
briefing's helicopter LZ at (-1035, 179) passed LandingZone.check (slope 10 degrees, the ground
round the rotor disc -2.6 to +1.5 m), the helicopter touched the ground there at 0 m to go and
never reached LANDED in 120 s. LandingZone allows 15 degrees (Captain's limit; the supports suite
checks a 12-degree slope takes a landing) but only flat landings are flown in the suites.

Suggested: fly a landing onto a 12-degree slope in tests/heliflight_test.gd and let the
helicopter settle on it (gear on the uphill side first), or have LandingZone also require the
ground within the rotor disc to stay within a metre or so of the spot. The snow preset was made
gentler (relief 2.1 -> 1.7) meanwhile.

Eased (world/terrain, 2026-10-22): it came back on CI (ad6a064e, the loop suite's intel grab on
Whitecap Pass: LZs of 13 and 15 degrees, touched down at 0 m to go, never landed). DeadGround.find
now looks on (up to LZ_LEVEL_LOOK = 40 more candidates) for a hidden LZ of 8 degrees or less
before taking a steeper one, and then takes the flattest; Whitecap Pass's LZs round every site
come out at 2-8 degrees. Still open: the helicopter settling on a slope LandingZone allows.

## F-210: a city's street grid isn't paved (the roads agent's ZoneRoads)

Queue item 1.5 (city zones) gives a city's street grid as data of its own: the def's `"cities"`
(`[{"id", "seed", "pos"}]`, ZoneDef._place_city) and `ZoneModules.city_streets(def)`, every
street's centre line in zone metres with its width (`BuildingGen.CITY_STREET_W`, 10 m: a 6 m road
and 2 m pavements; `BuildingGen.city_layout(seed).junctions` where they cross). Today the streets
are only painted road-coloured on the city's pad (`ZoneModules.STREETS`, ZoneTerrain), and the
zone's own roads (the HQ's to the city's ring street, `"roads"`, the trails) stop at its pad.
`scripts/world/zone_roads.gd` (the roads agent's, not touched here) should pave the grid with
its kerbs and junctions, join the road from the HQ where it meets the ring street, and keep its
other roads (HQ to outposts, trails) off the city's lots.

## F-211: an AI building scan near a city's tall buildings takes 150-450 ms

Measured in the `city` suite (headless, the Old Quarter, the player walking into the city): the
long frames are all `Buildings.near` scans (FrameCost "buildings": groups 30-255 ms, probes
100-190 ms, entrances 10-125 ms), asked by `Squad._tick_follow_in` (Buildings.at at the leader,
every 2 m he moves, before it checks there's anyone to follow him in) and `Squad._update_context`
(has_near). Near 3-8 storey buildings a scan has many more floors, stairs and stacked groups to
link than in a town. `Buildings.FRAME_BUDGET_USEC` stops a frame's later scans in a game, but
the first always runs: a 300 ms scan is a 300 ms hitch. Suggested (buildings.gd and squad.gd are
Claude's: helper-and-hook territory): skip the follow-in scan when the squad has nobody to send
in, cap a scan's floors to those within reach of the asker, or slice a scan over frames. The
suite's frame budget counts the scans as a game caps them (tests/city_test.gd).

## F-212: a town's or landmark's stair can be cut off from a zone's navmesh

Found building city zones: in a zone a module stands on its pad's height (any 0.05 m), so the
navmesh bake's 0.25 m height grid falls anywhere on its floors. A stair's foot with only
`BuildingGen.STAIR_APPROACH` (0.5 m) between it and the end wall leaves, after the agent's radius
is eroded off, a strip one cell deep in front of the first step: at some heights it bakes and
the stair joins the floor, at others it doesn't (a scratch probe: three of twelve city stairs cut
off with the grid 0.2 m off the floor, none with it on). City buildings keep 1.0 m
(`CITY_STAIR_APPROACH`; 215 flights checked at five grid offsets, all joined) and every stair's
ramp now has wedges at both ends (`ramp_faces`), but towns and landmarks keep 0.5 m: giving them
1.0 m moves their stairs (and so their furniture), which changes those buildings for saved
damage. Captain's call: move them (and accept the change), or keep them and bake a little floor
ramp in front of each foot instead.

## F-213: a path from the street to a tower's top floors stops a floor or two short

Found building city zones: `NavigationServer3D.map_get_path`, which the AI calls (squad_ai.gd,
tactics.gd, buildings.gd, civilian_ai.gd), searches at most 4096 navmesh polygons (Godot's
`path_search_max_polygons`; there's no project setting for it) and then returns the path to the
nearest spot it reached. In a city, from the street to an 8-storey tower's top floors that's more
than 4096 (every flight, landing and furnished room on the way), so the path ends on floor 6 (in
the `city` suite, 6 of the tower's 48 rooms; a path with the limit at 65 536 reaches every one).
The navmesh itself joins them up, and a man re-pathing as he climbs gets there, but an order to
"go to the top floor" from outside takes him only part of the way first. Suggested (the callers are
Claude's files): one helper that paths with `NavigationServer3D.query_path` and a higher
`path_search_max_polygons` (or in hops: to the building's door, then up), used where the AI paths
into a building.

## F-180: the co-op soak onto the game's high command pieces (high_command.md section 9, lifts 1-3, 7, 8)

C1 (claude/ca-c-high-command) lifted the soak bot's decisions into game code: `FollowBrain`
(scripts/ai/follow_brain.gd: _follow_tick, _follow_spot, _wedge_spot), `ProgressWatch`
(scripts/ai/progress_watch.gd: _stuck_note, _track_wedge), `CareRules` (scripts/ai/care_rules.gd:
_treat_loop's pick, _casevac_tick's carrier, _give_up_tick), `Extraction.missing_of(point,
soldiers)` and `DeadGround.known_watchers(level, squads)` (the knowledge-fair seam; the soak keeps
true posts through `DeadGround.watchers`). tests/coop_soak.gd isn't on claude/ai-driving (it lives
on test/coop-soak and claude/coop-join), so it wasn't edited.

Suggested, on the soak's branch: call those in place of its own copies (its RPC actuator and the
catch-up teleport stay in the test); give squad orders through `_server_squad_command` and, from
C2, `HighCommand.request_order` (lift 7, so `coop_soak --hc` runs the real validated path); key the
recorder and coop_soak_report.py by group (`Soldier.hc_id`, "" for the player squad) (lift 8).
Acceptance: a short replay behaves the same.
## F-190: a following squadmate stuck head-on against a wall's end (casualty suite)

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd), `_steer` (the path walk). Found and fixed by
Claude on `claude/ci-cleanup` (2026-10-22), a CI red directly in the squad AI (the one change there:
`_unblock`, called from `_steer`; `claude/ai-followups`' hunks don't reach it). Supersedes F-90
and the stuck half of F-08.

What happens: casualty's soak ("nobody got stuck on the way", then "everyone is back in formation"
and the collection-point checks) fails on nearly every CI run on `claude/ai-driving` (39710962889's
predecessors 39689572822, 39687185890, 39682370659, 39655370830 ...). Before 2026-10-22 the man
was held against the LightDummy at (-4, 0, 12), which the compound's navmesh didn't know. The
dummies are baked in now (NavBuilder.OBSTACLES_GROUP), and the same thing happens one obstacle
over, on CI (run 39722065652) and locally (R2364) alike: Foxtrot at (-1.39, 0, 9.70), path next
(-1.5, 0.5, 10.75), input forward, speed 0. The low wall at x -1.5..1.5, z 10.0..10.4 (1.1 m)
ends at x -1.5; the bake keeps a path only about 0.1-0.25 m off it at its corner (agent radius
0.25 m, one 0.25 m cell of erosion, edge_max_error 1 cell), and the soldier's capsule is 0.3 m,
so with its centre at x -1.39 (inside the wall's x span) it meets the wall's south face head on
and move_and_slide has nothing to slide along.

Tried on the navigation side and dropped: padding the baked boxes 0.125 m (fixes casualty, but
closes the compound's 1.2 m doorway in the 0.25 m-cell bake: logistics' "through the doorway"
path went 15.9 m round, squad's path into the building ended outside); edge_max_error 0.5
(Foxtrot then stuck elsewhere, the carry checks broke).

Fix: `SquadAI._unblock`: pushing with no way on for 0.5 s against a face met square on
(get_slide_collision's normal), the man steps along it, the side his next waypoint lies, for
0.6 s, then takes the path again. casualty passes locally with it (R2382), and failed every
time without it once the dummies were baked in (R2364). The test is casualty's soak as it stands.

F-80's half ("with a collection point set, a squadmate picks his body up" and its radio line,
every squadmate idle in formation; CI run 39725520165, R2400) was the test: Echo falls where the
dynamic wedge has him, about (-4.3, 3.8), within BODY_THERE_M of the test's collection point at
(-8, 4), so he already lay "there" (`_body_destination` null) and nobody had cause to carry him.
The test takes the point on the other side (8, 4) when he lies within 10 m of it, and the check
names, per squadmate, any `_can_bear` condition that holds him back.
## F-163: a helicopter insertion came 0.1 m inside its 5 m airframe clearance

Location: the loop suite's helicopter insertion check ([loop_test.gd](../../tests/loop_test.gd)
`_heli_insert`, `HeliFlight.airframe_clearance`, `Helicopter.MIN_CLEAR_M`). Found by cghath's
agent on `world/landmarks` (2026-10-22); the flight code is Claude's, so it isn't changed there.

What happens: on world/landmarks' CI (run 39717899713) the insertion into kestrel_valley's
compound job (entry (-1072, 72), LZ (-905, -426)) passed 4.9 m from the ground or what stands on
it at (-921, 1.9, -378), 51 m before the final. The same flight passed locally (R0474). The
nearest landmark (the drug lab at (-804, -228)) is about 190 m off that spot, so it's the ground
or the props along the way in, not a landmark; it shows up now because landmarks lengthen
kestrel_valley's module list and the board deals that job.

Suggested: a margin on the approach (the clearance the flight keeps a little over MIN_CLEAR_M),
or the check counting from the final's start rather than FINAL_LOW_M.

The loop suite's other two failures on that branch were the test's: a drop lets go of what's in
the hands first, so with the intel grab's hard case carried out the rifle stayed slung ("the rifle
set down in the point goes into the hold"), and the "banked" check expected a dead hostile's
intel in the stash, where intel never goes (`Contracts.without_intel`, also red on
claude/ai-driving's CI 39682370659). Both are fixed in tests/loop_test.gd on world/landmarks.

Seen again on `claude/ci-cleanup` (Claude, 2026-10-22), the same few metres every time, in a
different zone from cghath's: "its airframe at least 5 m clear until the final: 3.5 m at the least
(at (-32, 14.7, -938), 356 m to go)" on CI run 39732150758 (2ff7a91c), and 3.4 m at (-29, 14.7,
-944) locally (R2363); the same suite passed in R2365, R2386 and R2402. It follows the zone the
board deals, so it comes and goes from run to run; a flake for CI's purposes until the flight
keeps its margin.

## F-191: a crash landing with two aboard can kill both (supports suite)

Location: [supports_test.gd](../../tests/supports_test.gd) (the transport shot down: "a crash
landing: everyone thrown clear and hurt, %d of %d alive") and the crash's injuries to those thrown
clear (Helicopter's crash landing). Found by Claude on `claude/ci-cleanup` (2026-10-22).

What happens: the check wants at least half of those aboard alive (Captain, 2026-10-18: the crash
landing is survivable, "most of them alive"). With two aboard, CI run 39732150758 (2ff7a91c) had
both dead ("Alpha: dead, riding nothing, 3 m from the helicopter; Bravo: dead, ... 4 m"); the
runs before on the same branch (39722065652, 39725520165) and locally passed. Nothing on that
branch touches the crash or its injuries (its changes there: a test's waits, the squad's wall
sidestep, the stash count), so it reads as the injury rolls: two riders leave no room for one
bad roll.

Suggested: crash injuries rolled within a survivable band for those thrown clear (the "most of
them alive" call), or the check with more riders aboard.

## F-192: a follow-in stacker running a loop round the building (casualty soak, CI only)

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) (the clear tactic: `_tactic_clear`, a man's
walk to his stack place) and [squad.gd](../../scripts/ai/squad.gd) `_tick_follow_in`. Found by
Claude on `claude/ci-cleanup` (2026-10-22); left for the squad-AI work (`claude/ai-followups` is
in `_tactic_clear` now).

What happens: casualty's soak leads the squad through the compound's building ((0, -8) is on its
route), so a follow-in clear stacks them at its door. On CI run 39740524497 (45da4fa8) Echo,
"Stacking up" with his place at (5.3, -3.8), ran (5.6, 2.4) -> (7.8, -2.6) -> (12.0, -5.1) ->
(14.0, -2.7) -> (14.0, 0.4) -> (12.8, 5.8) -> (10.1, 7.4) -> (6.2, 3.8) in 8 s, a loop round the
building's east side and back, at a run, and the soak's stuck check (no more than 0.6 m from
where he was 8 s before) took him for stuck. Locally the soak passes (R2382, R2402, R2435,
R2436). A man standing at his stack place or waiting his turn to go in is no longer counted
(the soak skips men where their op put them); this one hadn't got there.

Suggested: watch a stacker's distance to his place (as `_reach_progress` does for a casualty):
no closer for a few seconds means a new path, or his place in the stack handed to the next man.
The test: casualty's soak.

## F-193: base_zone's player down after the helicopter insertion (CI only)

Location: [base_zone_test.gd](../../tests/base_zone_test.gd) (the walk-through deployment: flown in
to the insertion LZ, walking home through the base zone). Found by Claude on `claude/ci-cleanup`
(2026-10-22). The brief listed base_zone as an occasional red already.

What happens: on CI run 39740524497 (45da4fa8) "flown in aboard a helicopter to its insertion LZ"
failed with the player at (-2006, 0, 891), up=false, 25 s after the insertion drop; everything
after it failed with him ("walking home through it": only a player standing inside an extraction
point can confirm it; "back at the base zone, the deployment over"; the MIA recovery contract and
the raid's standing). The same commit passed it twice locally (R2442, R2443), and the branch's
three CI runs before passed it (39722065652, 39725520165, 39732150758). Why he was down isn't in
the annotations.

Suggested: shield the player for the insertion (Vitals.shielded, as the loop suite does: the
fight isn't what this suite checks) or say in the check what put him down (his wounds and who
hit him, Harm).
## F-200 to F-206: perf hooks in cghath's world files (perf pass, claude/perf-pass, 2026-10-22)

Captain, 2026-10-22: "we definitely need more performance fixes". docs/performance.md has the
cases, the numbers before and after and how to measure (tests/perfcases_test.tscn). These are the
hooks the pass put into world generation's files, for cghath to keep (or redo his way) when he next
works there. Each keeps the look and the gameplay as they were.

### F-200 (done, for review): GrassCarpet keeps its tufts
`GrassCarpet.lay` keeps each grid point's tuft (or none) in `_tufts` until the ground is cut again,
and narrows the scatter's pads and roads to those near the circle once per lay (`_blockers_near`).
Each tuft used to test every road in the zone: 100-300 ms a lay, every 6 m on foot and many times a
second in a vehicle.

### F-201 (done, for review): ZoneScatter ground cover and cell builds
`_ground_blocked` narrows pads and roads per 128 m cell (`_blockers_for`); cells are built one a
frame from a queue (`_queued`), the same PER_FRAME per CHECK_S as before. The new Detail setting
(GameSettings.detail) scales the draw ranges (`_range_scale`) and stops the far canopy blobs at
"far_trees_m" with a fade ("ultra" keeps today's: to the horizon).

### F-202 (done, for review): ZoneTerrain refines a chunk a frame
`_process` re-plans the chunks to refine only once the camera has moved REPLAN_M (it measured and
sorted every chunk of the zone every frame) and refines one a frame (`_refine`).

### F-203 (done, for review): GroundCuts redraws over frames
A cut's collision still goes in at once; its blocks are redrawn one a frame and the coarse chunks
after them (`_process`, `_fine_dirty`). A barrage of craters used to redraw every block in its own
frame (50-150 ms a crater).

### F-204 (done, for review): VoxelWorld marks and blasts
Marks keep a slot in their multimesh (`_show_mark`, `_drop_mark`, a rebuild only to grow); the
oldest mark at the cap is found without `_marks.keys()[0]`; `drawn_marks()` for tests. `_blast`
copies its box once, walks only the sphere's rows and pastes the cleared voxels back
(`paste_masked`). Still open: `_breach` walks voxels one tool call at a time, and a module's edit log
is replayed in one frame when it streams in (`for edit in _pending`): a fought-over town costs
hundreds of ms there.

### F-205 (done, for review): streaming by distinct points
`ZoneLevel._update_streaming` takes the focus points once per 2 m (`_distinct`). (Marking the
navigation's wanted chunks once per 4 m square of soldiers was tried and taken back: the wider
reach it needed to stay a superset baked and kept more chunks, and the navigation server's time went
up 1-1.8 ms a frame, R2422.)

### F-206 (open, for ai-followups / cghath): what's left in the hitches
- Buildings: a cold scan's grouping, entrances and ports (`_group`, `_building`) still run in one
  frame once its probes are done (100-250 ms in the Old Quarter); the probes are budgeted now.
- EnemyResponse._spawn_team spawns a whole team in one frame (about 8 ms a soldier now, was 45):
  its eight callers use the soldiers at once, so a queue needs their records to wait.
- Gore: BodyDeform meshes its results on the main thread (`_done_work`); hang and piece meshes
  aren't counted against its budget.
- Co-op: three RPCs a shot (sound, tracer, impact); one batched RPC a frame would do.
- Headless: meshes made on a worker (VoxelArt.build_async's faces, BodyDeform) race the main thread's
  in the dummy renderer, whose mesh RIDs aren't thread-safe: "Initializing already initialized RID"
  shows in the perfcases logs before the pass too (R2420, R2427), and the pass's own warm-up meshing
  crashed a run that way (R2424) until it stopped meshing on the worker headless. A player's renderer
  is thread-safe there; a headless host or test isn't.
- Rendering (not measurable headless): soldiers are 15-25 draws each with shadows and no range
  (338 draws in the Old Quarter case); module proxies cast shadows; terrain's coarsest level is a
  draw per 128 m chunk out to the horizon (could merge into 512 m blocks).

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
- 2026-10-21 | Road ambushes spring on the first crewed enemy vehicle's closest pass within 160 m, or anything within 35 m, or when given away (fired on, a man down, found within 30 m); guns' gunners first, then crews; launchers at the lead truck, then the last (RoadAmbush, Proposed) | Lead and trail vehicles hit first is the drill; waiting for the pass gets the most of the column in the kill zone | spring at a fixed distance, or on the first sighting
- 2026-10-21 | A convoy truck driven as an order always drives through an ambush; only a disabled one stops, its crew out to the lee (SquadDrivers.server_drive_route) | MRAPs drive through small-arms fire and the mission counts trucks through | DriveContact's judging (stop and dismount under heavy fire)
- 2026-10-21 | At a man in a vehicle the AI's sights need only be on the vehicle (0.3 of its hull's diagonal) and the shot leads its speed (SquadAI, Proposed) | a passing truck never let the man-sized gate open, and a miss on him still hits the truck | aim at the hull's middle
- 2026-10-21 | AI vehicle gunners need Spotting's time to make a man out before firing | the M2 saw anyone in a clear line at once, out to 600 m, which made ambushes impossible | an ambush-only exception
- 2026-10-21 | A roofed spot in a big hall is inside with walls out to 26 m and up to 3 open ways (Buildings, Proposed) | hangars and factory floors are 17-26 m across with 14 m doors | grow rooms inward from the walls
- 2026-10-21 | G-14: smoke over open ground of 15 m or more the threat sees, once a squad near there (bounds, fall backs, move orders), and over a casualty dragged off in the open; bangs into a hot building with no breacher and up each stair (flash first for our side, frag first for the enemy), never with a noncombatant inside | Arma/LAMBS smoke crossings; CQB bangs rooms and stairs | bangs into every room on every clear
- 2026-10-21 | G-24: hand flares 150 m up for 35 s, lighting full within 110 m and out to 220 m; mortar illumination 350 m up for 45 s, full within 200 m and out to 360 m; one hostile in 4 on the standard kit carries 2; a squad flares once per 45 s at most, at darkness 0.55 or more; NVGs bloom (Flares, Proposed) | close to the M127A1 and 60/81 mm illumination; enough to light a firefight without lighting the zone | every hostile with flares, or flares by script at set times
- 2026-10-21 | G-26: a line in contact, a staggered column in a town, a file in the woods, on a road a column (a staggered column on the alert or in the dark), on open ground a wedge (a staggered column in the dark); spacing x doctrine (insurgents 0.7, regulars and PMCs 1.0) | FM 3-21.8's choices by terrain, visibility and threat | random formations as LAMBS does
- 2026-10-21 | Upper-floor doorways slide along their wall off the stairwell (or another wall takes the doorway): some existing two-storey buildings' doorways move | a doorway over the stairwell cut its room off | leave existing buildings as they were
- 2026-10-22 | AI level of detail (AiLod): full rate within 120 m of a player, in contact, with a target or busy with a casualty; past that scan, think and re-path 2x less often, 3x past 250 m, 4x past 400 m (Proposed) | most of a hot zone's AI is far from everyone and nobody sees its exact timing; awareness still builds per second | one lower rate for every AI, or none (DynamicSim's 650 m sleep only)
- 2026-10-22 | An AI standing still steps its movement every 4 ticks with the time summed (SoldierMovement.REST_EVERY, Proposed) | most of a town's garrison stands at its posts; anything ordered ends the rest that tick | every tick as before
- 2026-10-22 | New Detail setting, default High: the far tree canopy stops at 3.2 km with a 300 m fade; Ultra keeps today's look (canopy to the horizon); Medium/Low draw scatter 0.8/0.65x as far (Proposed) | the canopy past 3 km is mostly fog; visual changes behind a setting with today's look at the top | default Ultra (no gain unless changed)
- 2026-10-22 | Building scans' probes stop at the frame's 4 ms budget on a player's machine, the first scan's too; headless keeps exact answers | the first scan was 200-600 ms in one frame; an over-budget ask already got stale answers | budget headless too (changes every suite's answers)
- 2026-10-22 | The physics step cap stays at 8 a frame | a lower cap turns overload into slow motion while the AI's clocks run on real time (Soldier._now) | 3-4 a frame
- 2026-10-22 | perfcases budgets (Proposed): town 75/140 ms and 90 hitches a minute, fight 60/110/45 (40/60 first: CI measured 42.7/71.7), woods 25/35/20, drive 20/30/15, heli 28/45/20 (60 Hz frame cost average/95th) | about twice the pass's numbers on a busy machine, under the numbers before it | tighter (flaky on CI's runners) or none

- 2026-10-22 | A season from the campaign day: 30 days each, starting in spring (Season); the host puts it in a zone's def when it switches to it (BaseHub.server_switch_level), a def without one (the menu's test zones) is summer | there was none (DayNight keeps the hour, the economy the day); a campaign month a season lets a long campaign see the year turn | a real 91-day calendar, or the season from the weather
- 2026-10-22 | Gullies 2.0-2.8 m deep (a 2.6 m floor, sides out to 8-10 m), ditches 1.2-1.5 m; 260-520 m and 140-320 m long, kept 30 m off pads, fading out at roads, the zone's edge and their ends | a man prone in a gully is hidden from 91% of the lines from the flat round it (35-140 m), crouched 73%, prone in a ditch 78% (terrain run) | narrower, deeper cuts (the 4 m height grid can't draw them)
- 2026-10-22 | Cliffs are escarpments in the heightmap: a face across one 4 m cell (60-79 degrees), a 10-24 m ledge, the ground easing back over 110-170 m behind, the ends tapering over 45 m, 6-18 m high by preset, 60 m off pads, a ramp where a road crosses one; talus rocks at the foot | collision, the navigation mesh's slope limit and the ground shader's rock come with it, nothing new to keep in sync | voxel or mesh cliff faces (overhangs: later)
- 2026-10-22 | Existing presets get features: gullies on temperate, scrubland, desert_wadi, highland_moor, badlands, rocky_ridge; ditches on temperate, river_valley, coastal_lowland; cliffs on rocky_ridge, highland_moor, badlands (none on plain, salt_flats, forest_experimental, amphibious_coast) | the brief's gullies and cliffs are for the world, not only the new presets | new presets only
- 2026-10-22 | Soft marsh ground keeps 65% of a man's pace at its softest, deep snow 75%; none on roads, tracks and pads (packed); on foot only (vehicles: F-185) | slower than a walk but still a game; the movement hook is the water's | a pace by snow depth, or mud that also tires (stamina)
- 2026-10-22 | Frozen streams and ponds (the snow preset) are ice lying on their bed (0.1 m of channel): walked on, never waded or swum, on the AI's navigation mesh, pale and glossy; no thin ice | it reads as ice and needs no ice collision of its own | real ice over deep water with breakable slabs
- 2026-10-22 | Crops and reeds hide by foliage metres a metre: ripe wheat 0.9 m tall 0.08 (about 15 m of it hides a man), maize 2.2 m 0.25, reed beds 1.7 m 0.3; counted within 25 m of either end of a line (F-188) | a man prone in summer wheat is hidden at 80 m, standing he isn't; standing in maize he is | walk every line through every field
- 2026-10-22 | Crops by season (ZoneFeatures.CROPS): wheat green 0.35 m in spring, gold 0.9 m in summer, stubble in autumn, bare in winter; maize ploughed in spring, 2.2 m green in summer, 2 m dry in autumn, stubble in winter; vegetables low; orchards blossom in spring and stand bare in winter | the brief: crops by season | one fixed look
- 2026-10-22 | "procedural" mixes take marsh, snow_mountain and farmland too, and their "features" part by part (the nearer preset's part wins); frozen water only where the mix has snow. Adding to MIX_FROM changes which presets the existing procedural zones (Hollow Downs, Ashfield, Marrow Shore) mix | the brief: procedural can mix them | a second list that leaves the old mixes as they were
- 2026-10-22 | The new campaign zones are in data/contracts.json "zones" (where the campaign's zones live; data/zones.json holds the hand-made test zones): Blackwater Fen (marsh, inland, Valley Shura), Whitecap Pass (snow_mountain, inland, Black Ridge), Harrow Fields (farmland, inland, Kestrel, a farm landmark by its "fields" tag), all inland so the coast's block (FOB Halberd's hand-placed cell beside Cove outpost) keeps its shape; Whitecap isn't the Highland Front's, so Greyfell Moor stays its last zone (the war's siege rule) | a contract can go to each | turn existing zones into the new presets
- 2026-10-22 | Farmland built without merging world/props (PR #22): fields, orchards, hedges and irrigation channels are ZoneFeatures' own; the props' farm fences and hay follow when both merge (F-187) | keeps the two PRs independent | merge world/props into world/terrain first
- 2026-10-22 | Irrigation channels are ZoneWater line bodies ("channels"): 2.6-3.2 m wide, a 0.5 m cut, along an eighth of the field grid's column edges where both sides are fields and the ground keeps within 3 m of level, cut into 72-340 m lengths | they build on the water (wading, culverts, scatter keep-out, bank tint) | ditches with a separate water mesh
- 2026-10-22 | The world suite's "steepest ground" check on the ridge hot zone now skips 12 m round its cliffs (they're steep on purpose) | it guards the ridge noise, not the cliffs | drop the check
- 2026-10-22 | Cliffs and gullies are carved after the water and kept off its water and banks: a stream crossing a cliff's line runs through a notch | carved first, a frozen stream held at its level through a cliff cut a 34 m canyon that took an extraction pad with it (the world suite, snow_mountain) | keep the cliffs off where the streams will run (unknown before the water)
- 2026-10-22 | snow_mountain's relief down from 2.1 to 1.7 times the zone's, its ridges and detail a little softer | on CI the loop suite's helicopter didn't settle on a 10-12 degree LZ on Whitecap Pass (F-189) | keep it rugged and fix the landing first

- 2026-10-22 | A city is a 5 x 4 grid of perimeter blocks 48 m apart with 10 m streets (240 x 192 m), each block a zone module of its own ("city#<seed>#<ix>#<iz>": streamed, garrisoned and given missions block by block, a town to the rest of the game) on one flat pad for the whole city (Proposed: BuildingGen.CITY_*) | streaming per block keeps a city's cost to the blocks near the squad; one pad keeps the streets level | one big city module, or towns packed together
- 2026-10-22 | City heights (the brief's call): 3-5 storeys in the inner blocks, 2-3 on the outer ring, 2-3 towers of 6-8 in the core; new types apartment (flats), tenement (a shop under flats) and tower (offices); clinics, police stations, houses and shops too; a house or shop too small for its stairs gives way to flats, a lot too narrow for stairs is left open (no one-storey buildings in a city) | the bands as called, every building with stairs to every floor and its roof | let small buildings top out lower than their band
- 2026-10-22 | City garrisons: 4 posts a core block, 2 an outskirts block, 2 more in a tower (its top floor and roof), 70% up high (in practice all upstairs: windows onto the street, the floors spread by building, a back room upstairs); about 58 for the Old Quarter | "garrisons use the upper floors", and about what its 3-4 towns held | a post per building (200+)
- 2026-10-22 | The Old Quarter's 3-4 towns become one city (its HQ outside it, a road from the HQ to its ring street, a patrol round its inner streets, its villages outside), on a new "city" terrain preset (low rolling ground, dusty verges, grey streets, few trees, more ruins) | "the Old Quarter becomes a real city" | a city alongside the towns
- 2026-10-22 | 12% of a city's buildings ruined (never a tower; never bombed out: the bombed-out roof-and-walls collapse is two-storey only) | it's a hot zone in a living war, as its landmarks are | none ruined, or bombed out too
- 2026-10-22 | A city's street grid is its own data (the def's "cities", ZoneModules.city_streets), painted on its pad, not paved: joining it to the roads is F-210 | the roads agent owns zone_roads.gd | pave it here
- 2026-10-22 | The zone navmesh bakes up to the tallest module on each chunk (was 8 m over the ground), and Jolt's body limit goes 10 240 -> 32 768 (project.godot) | a city's upper floors weren't in the navmesh, and a whole city streamed in passed 10 240 bodies (each voxel mesh block's collision is one) | stream fewer blocks at once (a city is meant to be fought through)
- 2026-10-22 | City stairs keep 1.0 m clear in front of their foot (towns and landmarks keep 0.5 m: F-212), and every stair's navmesh ramp gets a wedge on and off | at 0.5 m a zone's pad height decided whether a stair joined the floor (3 of 12 cut off at one offset; 215 of 215 joined at five offsets with 1.0 m) | move every building's stairs now (changes towns and landmarks for saves)
- 2026-10-22 | City block frame-time check: walking in at a run while its blocks stream in, worst frame 200 ms and average 25 ms (Proposed; 76 ms and 9 ms measured here), with the AI's building scans counted as a game caps them (4 ms a frame past the first; F-211) | headless runs every scan in full, and those (not the blocks) are the long frames | count the scans in full (fails on F-211, not on the city)
- 2026-10-22 | Village houses (queue item 1.6): the four hand-built houses are generated on their own ground (mud brick, cinder block, a two-room brick house, a plank shack: a "plank" style kept out of STYLES so no other building changes), front doors where they were, one storey, no roof stairs; their furniture keeps off the posts, loot, named points, mission sites, site boxes and the world suite's firing lines; every village the same | the brief: "keeping each module's layout and garrison posts" | a village seed per zone with varied houses (moves posts and sites)

2026-10-21 | Roads come in three kinds (asphalt 7 m, dirt tracks 4.2 m, town streets 6 m between kerbs), every number in data/roads.json as Proposed | one place to tune widths, grip and which sites get what | hard-coded consts in ZoneRoads
2026-10-21 | Asphalt to towns, the HQ, QRF bases, comms, checkpoints and the FOB; dirt to outposts, compounds and villages, and on the trails; a link takes the better of its two ends | main roads read as main roads, farms and compounds get tracks (Arma's mix) | everything asphalt in hot zones
2026-10-21 | A trail that ends within 14 m of another road joins it (a T); junctions within 30 m of each other share one height; a later road passing close by an earlier one is drawn toward its height; routes cost 1.5x a metre alongside a road already laid | the ground between two roads can only be graded to one height, so roads that touch must agree | let them overlap at different heights (terrain through one of them)
2026-10-21 | Every site is joined to the roads: the links' separate networks are joined nearest sites first until every site is on one, and a link passing within 90 m of a checkpoint runs through it | hot zones only linked the HQ to its outposts, so comms, QRF bases, checkpoints, villages and the town had no road, and a landmark's link to its town can leave the two on their own; the brief wants every site on the network | leave the links as ZoneDef makes them
2026-10-21 | A road out through a linked-zone crossing runs straight out from the crossing to the zone's edge, its kind from the link's two zone ids (60% asphalt), so both sides of a link get the same road at their own crossing | crossings slide along their edge per zone (RegionMap SLIDES), so "the matching point" is each zone's crossing, not one shared coordinate | change RegionMap so both crossings share one along-edge position
2026-10-21 | Towns get a mini roundabout (a 2 m mountable dome) at the crossroads; full roundabouts (6 m island, 7 m ring) go at junctions of 3+ arms within 320 m of a town, or where 4 asphalt arms meet, clear of pads | the crossroads is about 5 x 6 m between corner buildings, too tight for a full ring without moving BuildingGen's lots | widen the crossroads in BuildingGen.town (changes every town's layout)
2026-10-21 | Kerbs and pavements sit inside the town's existing street rects (carriageway = street less 1 m each side, 2 m pavements out to the building fronts, 12 cm high with a chamfered kerb you can walk and drive over); BuildingGen.town is unchanged | no layout change, no step for soldiers or the navmesh to trip on | move the building fronts back for wider pavements
2026-10-21 | The terrain is cut and filled to the roads: ground 0.10 m under the surface, a level shoulder (3 m low side, 6 m high side), banks 1:2 up and 1:1.6 down to 10 m out; the profile is the ground smoothed over 20 m, solved as a stretched string (36 m) through flat junctions (14 m, ramps between them and the pads at most 12%), level with any pad it leaves or passes within 4 m of; then no height point under a road is left above it | roads that follow the ground but drive smoothly and never have terrain poking through (99% of road within 4 m of the natural ground; the worst, a track climbing to a junction on a site's embankment, about 8 m) | drape the road on the raw 4 m grid (bumpy, terrain through it)
2026-10-21 | Where a road meets water (ZoneTerrain.water_height over the ground) it isn't laid or graded: the span is listed in ZoneRoads.water_crossings() for the water side's bridges and the road runs straight over it in the profile | the water side owns bridges, fords and culverts | fill a causeway across
2026-10-22 | The water plans its crossings over the links the roads take (RoadNet.water_links: the def's links completed, plus a line in from each linked-zone crossing), handed over inside ZoneTerrain.generate; water_test's "every road over the river has a bridge" reads the same links | the bridges must stand where the roads run, on every peer and in every test that builds a terrain | ZoneLevel swapping the def's "roads" before generate (other callers of generate would get other bridges)
2026-10-22 | A road runs straight through the crossing on its link: fixed points at the bridge's ramps' ends plus 4 m (a ford or culvert: 10 m either side) and 12 m before that to line up; its profile is pinned to the deck and down the ramps there, not laid or graded (F-175) | the deck is the road; the curve can't wander off a 7 m deck | lay a road strip on the deck (doubles the deck's surface and collision)
2026-10-22 | A link passing within 30 m of another link's crossing (heading the same way) takes it too; if an earlier road already has it, the later way joins that road either side of the bridge (two Ts) instead of running along it | the water keeps one crossing where links cross the river close together; without this the second road went into the river a few metres beside the bridge | run both roads over the deck side by side (overlapping strips and junction clutter)
2026-10-22 | ZoneWater._apply never raises a pad's ground with a stream's bank (the pad keep weight now also scales a raise inside the bank); the water agent's file, a 3-line change | a stream past highland_pass's checkpoint lifted its pad 2 m (terrain through the road and the site); found by the roads suite | log it for the water side and leave the road check failing
2026-10-22 | Helicopter._contour: below its need the rate it holds is never negative, and on the J-hook while sinking it plans the rise ahead at half its climb (HOOK_SINK_CLIMB 0.5, Proposed); helicopter.gd isn't Claude's | heliflight's ridge_hot insertion 1 came over a 23% rise 4.0 m clear (the 5 m check) once the roads moved the scatter: it sat level under its own need (F-218) | slow the hook where the ground rises ahead (changes every approach's timing)
2026-10-21 | Road collision is a trimesh per 256 m tile (a hard body and a soft one, friction 1.0 / 0.75, meta hard_ground for footsteps) on top of the graded heightfield | the 4 m heightfield can't follow a 7 m road's curves and edges; vehicles drive on exactly what's drawn | the graded heightfield only
2026-10-21 | The def's "roads" become the curved roads as straight pieces (within 1 m of the curve, at most 80 m, a third entry naming the kind), the links kept in "road_links"; the trails' patrols follow their curved trails | RoadRoute, ZoneScatter, the map, IEDs and the tracker all read "roads" and now follow the real roads with no change to them | a separate key (they'd all keep the old straight lines)
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
- 2026-10-22 | Dense copses (copse_cover and its caps) in every wooded normal preset (temperate, river_valley, highland_moor, coastal_lowland, amphibious_coast, rocky_ridge, scrubland, and since the merge with world/terrain snow_mountain and farmland; marsh keeps its own 12-40 tree copses, city has no woods); temperate and river_valley woods 2.1 and copses 6 a km2 (forest 2.4 / 6) (data, Proposed); the dense layout's thicket cap 11000 -> 16000 (CAP_THICKETS), as a 16 km2 hot zone ran out before its last copses had their skirts (world: 130 of 256 lines through woods hidden, R0506) | Captain: "Then denser copses" once the woods were cheap | only the Experimental forest dense; desert_wadi, badlands and salt flats keep their small copses (copse_cover's default copse is 35-110 trees)
- 2026-10-22 | F-121: the voxel world's edit area grows to hold a level's structures (VoxelWorld.fit_structures, called by CompoundLevel), not the range's blocks moved | vehicle_range.gd is Claude's, and any level's structure past 22 m is built too | move the blocks to z -18 and -21
- 2026-10-22 | Woods perf budgets in the forest suite (Proposed): from a normal preset's densest copse 600 draws, 700k triangles, 200k in the shadow pass; a capped sight line 400 us; a nav chunk 0.5 ms; standing in the forest's densest copse 25 ms a frame on average, 60 ms at the 95th percentile; a scan round of 16 men 30 ms | room for CI's slower runners over this PC's numbers | frame budgets only (noisy on a shared PC)
- 2026-10-22 | F-121's blocks in the vehicles suite: its AI driving goals moved off them ((-12, -20) -> (-12, -14); the path with a turn along z -36), the vehicle AI's trouble turning beside one logged as F-223 | the blocks are the range's ("something for the AI driver to steer round") and the AI code is Claude's | leave the range's blocks unbuilt
- 2026-10-22 | Helicopter.OBSTACLE_CLEAR_M 6 -> 7 m (Proposed): MIN_CLEAR_M + CLEAR_MARGIN_M, the margin it already plans over the ground | after the terrain merge (78f78543) heliflight's harbour_yard insertion 1 came over the roads' billboard 4.99 m clear, banked (CI 39779567296, R0557/R0559); the dense copses moved its line, the 1 m margin over obstacles was too thin for the bank. Not the tall-prop index (the billboard is in it) and not the test's 5 m | heliflight, supports, loop
- 2026-10-22 | Farmland and the props library (F-187): nothing of the props stands in a crop field but the power lines' pylons and poles; a farm's field fences and gates run down the lanes between the fields (2-5 sides within 170 m of it, Proposed); farmland has no prop irrigation (its channels are ZoneWater's); fields keep off the planned roads' verges | props and fields agree, the lanes stay walkable, power lines stay straight | power lines bending round every field, or the props' own field grid over the features' fields
- 2026-10-22 | A city's props (cities #23 under the props library): its street furniture is laid once for the whole city from its street grid's numbers (BuildingGen.city_layout: lamps every 16 m on alternating pavements, 1-2 benches and 0-1 bins a block, 2-4 dogs; data/props.json "city", Proposed), without building its blocks, and a city's clutter round its pad once, not once a block; city_hot's layout 4028 ms -> ~380 ms locally | each of a city's 20 blocks was laid as a town (building the block, ~100 ms each) and round the same city pad 20 times | the town street template inside each 48 m block, or a bigger budget
- 2026-10-22 | terrain_test's "the hosted zone's ground ... are a fresh build's" compares like with like: the fresh build starts from the def as sent before the roads were planned (RoadNet.unplanned), plans its roads too (ZoneRoads.prepare), and must match the ground, the features and the planned road pieces | the host plans the roads into the def it sends, as base_zone_test found | comparing against the planned def (two different builds)
- 2026-10-22 | Helicopter LZs (DeadGround.find, Noah's file, a small change): a hidden LZ steeper than 8 degrees is taken only if none of up to 40 more candidates is a hidden one of 8 or less, and then the flattest (Proposed) | helicopters land on 6-7 degrees but not on 10-15 (F-189), and Whitecap Pass's first hidden LZs were 13-15 | the first hidden LZ that LandingZone passes (15), or a gentler snow preset again
- 2026-10-22 | loop_test's deposit check brings the hostile body that fell last, not the first in the group | the body cap (12) takes the oldest body, gear dropped where it lay, and a raid with a dozen more falling after it lost the body brought to the point ("bodies 0", its gear banked as deposited) | raise the cap in the test
- 2026-10-22 | A group coming back from virtual (Virtualizer._woke, Noah's file, a small change) puts every man on the group's leg of its route (the profile's route_i, from its lead), as a moving profile already did | whichever man thinks first becomes the patrol's lead and the rest copy his leg, so a man left on leg 0 took the group back a leg (virtualization's "same leg of the route" failed 1 run in 2 here and on CI, R0563) | restore the old lead (patrol_lead drops a lead not yet patrolling)
