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
| F-230 | P2 | A soldier's movement in a city costs about 3x what it does in the woods: the voxel blocks collide as per-face trimeshes (10 cm faces), and move_and_slide was ~13% of the city case's AI tick (world content pass, 2026-10-23) |
| F-231 | P2 | The zone's navigation map now builds its iterations on a worker (ZoneNav.MAP_ASYNC): watch a city fight in game for AI that stop pathing into chunks just baked (the "missing region updates" ZoneNav's note describes from before); if seen, set it false (world content pass, 2026-10-23) |
| F-232 | P3 | Draw counts the headless suites can't time: the terrain ~300 draws a view (a mesh per 128 m chunk at every level), the scatter's far tier 350-600 (each stand-in kind a MultiMesh per cell): merged far levels (HLOD, visibility parents) want a GPU check in game (world content pass, 2026-10-23) |
| F-233 | P2 | On CI the city case's blocks sometimes aren't built for minutes while their garrisons come in (perfcases "city_x_y streamed in": claude/ai-driving e0caa68 at 60 s, this branch once each at 60, 100 and 180 s; locally ~60 s even on 4 cores): the blocks' voxel stamping is BUILD_BUDGET_MS a frame each at ~3 frames a second (world content pass, 2026-10-23) |
| F-140 | P2 | ~~Ambushers by a road and a friendly convoy driving past (missions 2 overwatch)~~ fixed 2026-10-21 (Claude, claude/ai-followups: RoadAmbush, the convoy's drive-through; the mission's two calls are F-178) |
| F-176 | P2 | ~~The dug ground never comes back from a zone save~~ fixed 2026-10-21 (Claude, claude/ai-followups) |
| F-178 | P2 | The overwatch mission (feat/missions-2) should lay its ambush teams with `RoadAmbush.server_lay` and drive its convoy with `SquadDrivers.server_drive_route` (two lines in MissionScenario) |
| F-179 | P3 | Players can't fire the hand flare (it's loot only), and the M320's 40 mm star round waits on F-130 (the AI grenadier) |
| F-190 | P1 | ~~A squadmate following along a path walks head-on into a wall's end and stands there pushing~~ fixed 2026-10-22 (Claude, claude/ci-cleanup: SquadAI._unblock; F-80's collection-point half was the test's point) |
| F-191 | P3 | A shot-down transport's crash landing with two aboard killed both (supports suite, CI once; "most of them alive") |
| F-192 | P2 | Following the player through the compound's building, a squadmate on the follow-in stack can run a loop round the building on his way to his stack place (casualty soak, CI only, now and then) |
| F-193 | P3 | base_zone: the player is down on landing after the helicopter insertion, and the walk home and the rest of the deployment fail after it (CI only, now and then) |
| F-163 | P3 | A helicopter insertion came 4.9 m from the ground, inside its 5 m airframe clearance, before the final (loop suite, kestrel_valley, world/landmarks' CI once) |
| F-122 | P2 | A client's first late join to the vehicle range: its RPCs never reach the host, and the link drops about 50 s later; joining again works |

| F-162 | P3 | The AI building scan misses the middle of a big open hall (a hangar: rays reach 12 m with no wall), so it isn't garrisoned or cleared room by room (landmarks, 2026-10-21) |
| F-214 | P2 | A convoy ambush's convoy drives its own straight-ish line across the zone, not the roads (scenario_gen `_convoy`) |
| F-215 | P3 | Vehicle grip ignores the surface: asphalt, a dirt track and open ground all grip alike (Vehicle `_wheel_forces`, Claude's file) |
| F-216 | P3 | AI drivers can go round a roundabout the wrong way, and RoadRoute's graph has no one-way edges (Claude's files) |
| F-217 | P3 | A crater or a dug pit on a road leaves the road's surface hanging over the hole (GroundCuts doesn't tell ZoneRoads) |
| F-218 | P3 | ~~A helicopter's J-hook can come over a natural hump 4 m clear (heliflight ridge_hot insertion 1)~~ fixed 2026-10-22 (cghath's agent, world/roads: Helicopter._contour) |
| F-07 | P2 | The far-AI sleep (DynamicSim) can freeze a falling soldier in his last metre above the ground |
| F-08 | P2 | A squadmate walking into something the navmesh doesn't know stands there pushing (casualty soak "stuck") |
| F-195 | P3 | Note: ZoneWater takes an operation zone's `river_hint` (combined arms D1, 2026-10-22): keep it when reworking the river line and road crossings |
| F-196 | P3 | Note: ZoneBridges' bridge records carry the crossing's `role` ("msr" on an operation's main bridge; combined arms D1, 2026-10-22) |
| F-197 | P3 | Note: ZoneModules.place_landmarks and landmark_kinds take an operation zone's band hint, covered zones, own list and max (combined arms D1, 2026-10-22) |

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

## F-140: ambushers and a friendly convoy driving past (missions 2 overwatch, cghath's side, 2026-10-20)

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd) (target choice and engagement), and how
hostiles see a crew in a moving vehicle.

The overwatch mission (MissionScenario "overwatch", docs/missions.md "Missions 2") puts 2-3 hostile
teams by the road (Reinforcements.server_send waves holding their own spot). A friendly convoy of
1-2 M-ATVs or MaxxPros with friendly crews (`vehicle_crew` and `allied_element` meta, their own
Squad, no squad slot) drives past them. The mission only works if the ambushers open fire on the
trucks and their crews as they come by, and go for the trucks rather than standing still. The
tests resolve the convoy by hand (trucks moved to the end, or set burning), so no test shows
whether the AI engages a crew sitting in a moving vehicle at 45-150 m. Nothing in Claude's files
was changed for this.

Suggested: check in a playtest or a probe that a hostile squad in contact picks a friendly
vehicle's crew (or the vehicle) as a target and fires on it. If it does not, let a holding wave
engage friendly vehicles that pass within its engage range.

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

## F-122: a late joiner's first connection carries no RPCs to the host, then drops

Location: the join path (`autoload/net.gd`, `scripts/world/level_switch.gd`'s auth, the level's
`_on_peer_joined`); seen on the vehicle range. Found by cghath's agent on `feat/demolitions`
(2026-10-21) after merging claude/ai-driving 0a649e9 and 4092a26; it didn't happen on a7e9207
(R0353, R0369). It isn't in this branch's code, so it's an entry, not a fix.

What happens (demolitions suite, its late-joining client, R0392): the client joins at 16.7 s, the
host logs the peer connected, spawns its player and sends its own state, and the client's
`multiplayer.get_peers()` is `[1]`. But the client's RPCs to the host (`_ask_expect`, every 3 s
from 24.9 s) never arrive: the host never prints that it was asked. At 67.6 s the link drops ("peer
1 left" on the client, the peer left on the host), with no frame over 2 s on either side. The
client joins again at 69.9 s and from then on everything works. Before the reconnect was added the
suite failed every time on it (R0377, R0388). The loadout suite's client, which also joins late,
dropped the same way on CI (run 39526347358), and loadout fails on claude/ai-driving's own CI
(39529244923, 39562279704).

Suggested: log on the host whether the client's first RPCs reach SceneMultiplayer (the path cache
confirmation for `/root/<test node>`), and check what the auth (`LevelSwitch._on_auth_data`,
`complete_auth`) leaves half-done on a first join that a second join doesn't have (the client has
the level loaded by then). The demolitions suite now prints the client's asks and join/leave times
(`[test]` lines), which shows it.
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

### F-206 update (claude/perf-towns, 2026-10-22)
- Buildings: done. The grouping (`_group`) and the stair paths (`_link_floors`, answers kept in
  `_climbs`) stop at the frame budget too and go on at the next ask, a building or stair path at
  a time; headless keeps exact answers. F-211's "slice a scan over frames" is this; its follow-in
  scan is skipped when the squad has nobody to send in (Squad._tick_follow_in).
- Team spawns: still open. `_spawn_team`'s callers use the whole team at once (sizes for refunds,
  nemesis tags, `_virtualize`, `_maybe_ride`), so spreading it means the Virtualizer owning the
  spawn: a team that would go virtual at once (far from every player) should be made virtual
  without spawning (today it's spawned, 10-20 ms a man on a busy machine, then taken out), and a
  near one woken a few a frame (`Virtualizer.server_wake` already does that for woken groups).

### F-224 (done, for review): GrassCarpet lays budgeted (claude/perf-towns)
`lay` hands the multimesh one buffer (each kept tuft is its 16 floats), walks only the rows' points
that can be in the circle, and stops working out new tufts after NEW_USEC (2.5 ms) as well as
NEW_PER_LAY; an unfinished lay goes on from the points it left (`_lay_pending`) instead of the
whole circle again. From the UH-60 the grass was 40-60 ms frames on a busy machine. Same look.

### F-225 (open, cghath): a scatter cell's build and a fine terrain chunk are 15-25 ms each
From the UH-60 on a busy machine (perfcases heli, R2519) the hitches left are one ZoneScatter cell
(`scatter_cells` 17-26 ms in one frame) or one ZoneTerrain fine chunk (`terrain_fine` ~18 ms):
already one a frame (F-201, F-202), but each is one piece of work. Splitting a cell's build (its
kinds or near/far tiers a frame each) or making the instance transforms on a worker would take
them under the 33 ms line.

### F-226 (open): soldiers are most of a city's draws
The draw proxy in the city case: about 2100 draws, 1630 of them soldiers (107 AI, 15-25 draws
each with their gear), 930 shadow casters. Buildings are 36 (merged per block), terrain 300.
Not measurable headless; worth a GPU capture in game. Options: soldiers' gear merged into the
body's mesh past ~40 m, visibility ranges on small gear (pouches, tape, optics), no sun shadow from
gear.

### F-227 (open, cghath): rifle-calibre STANAG threats still use the tier rule in play
cg_brief queue item 2.0 rates every vehicle by STANAG 4569 from its plates (armour_test), but KE
levels 1-3's rounds (5.56, 7.62x39 API, 7.62x51 AP, 7.62x54R API) have no data/shells.json row, so
in play they keep VehicleDamage's tiers (call 79, the Captain's small-calibre rule): an M993 or a
7.62x54R never gets through an M-ATV's crew zone, though its plates rate KE 2 (they'd let a
tungsten-carbide AP round through the glass). Giving those rounds shells.json rows with
`round_id` (the reference rows in data/armour_standards.json are a start) would make the plates
decide; it changes the small-calibre rule, so it's a call for Captain or a playtest.

### F-228 (open, cghath): technicals' own modules (cg_brief 4.2, D6b)
cg_brief queue item 2.1 (A2) authored modules for the five plated models only. Technicals have no
plates, so their hits never carry a residual to trace: they keep their zones (VehicleModules builds
a layout from them for reading). Author theirs (engine, fuel tank, cab crew, bed, wheels, the bed
gun as ext_gun with gun_seat) with their guns in A3/D6b, and route VehicleDamage results through
`server_apply` for them as for the MRAPs.

### F-229 (closed by cg_brief queue item 2.5, A7, armour/fx): what a catastrophic kill and a cook-off look like and do around them
Done: VehicleFire (scripts/vehicles/vehicle_fire.gd, the host's state) takes VehicleModules'
detonation rolls (server_ammo): a catastrophic kill is a fireball of 2 + 1.5 x rounds^(1/3) m with
min(0.4 x rounds, 12) kg on everyone near (Warheads.server_people, BlastGore) and a shake, the
turret thrown with 10 or more main-gun rounds aboard (else the hull ruptures), 12-24 debris pieces
from the seed, the hulk charred; the bustle's vent is an 8 m column of fire for 4 s and nothing
else; a cook-off pops every 0.5-3 s for 20-60 s, each pop a small HE event, a rack of 120/125 mm
rolling 5% a second to go up. VehicleFx draws all of it on every peer; the turret's and debris'
rest poses replicate and save. The original note:
A2 sets the state and the outcome; A7 draws it. Today a detonation wrecks the vehicle through the
existing fire burnout (DETONATE_BURN_S, the crew killed by `_become_wreck`), a cook-off is the
45 s fire, and a vent sets `flags.vented`. Still to do (2.10.2, 2.10.4): the fireball and its
`Warheads.server_burst` on everyone near (min(0.4 x rounds, 12) kg), the thrown turret (10+ rounds
aboard), debris, the venting column, cook-off pops as small HE events.

### F-236 (open, Claude's A9): AI crews read the kill states
A7 (cg_brief 2.5) gives the bail-out a stand-in: VehicleFire.server_bail (on a cook-off, or 3 s of
flames) says "Bail out!", emits `bail_out_called(reason)`, and while `VehicleFire.auto_bail` is on
puts the AI aboard an armoured vehicle out of its doors (Vehicle.server_exit) and calls
server_bail_out. A9 turns auto_bail off for its own rule, and adds where they run (the lee side,
20-40 m to cover) and the smarter triggers; popping smoke is `vehicle.smoke.server_pop(by)`.
`Vehicle.modules.kill_state()` / `kill_changed` / `server_bail_out()` are there. A9's crews: bail
out on a crew-compartment fire, a cook-off or a catastrophic warning (2.10.1) and call
`server_bail_out()` as they go; abandon a knocked-out vehicle that isn't repairable; call for
recovery or repair when it is; the commander takes the gun when the gunner is down (2.5.3).
Hooks only, per the brief (one line in squad_drivers or squad_ai).

### F-237 (closed by cg_brief queue item 2.2, A3, armour/guns): main guns on their own modules
Done: VehicleWeapons' mounts each read their own modules (the coax its sights only, the main gun
its breech, barrel and sights, the TOW its launcher, the commander's and loader's guns their
ext_gun modules); a damaged breech makes every load x1.5 (the 25 mm keeps the jam); the bustle's
doors open during the pull make a vent catastrophic; the turret runs on batteries for
BATTERY_TURRET_S after the engine dies, then by hand; the Abrams and Bradley have turrets, so the
traverse and elevation modules act. The original note:
Until A3 the Abrams' and Bradley's gun seat fires the coax stand-in, so the breech, barrel and
sights (gun_seat 1) gate it. A3: separate weapons per seat (main gun, coax, TOW, the pintle guns)
each reading its own modules; breech damaged reload x1.5 (2.2.2); the Abrams' bustle doors open
while loading make a bustle detonation catastrophic (2.10.2: VehicleModules vents it today); the
turret on batteries for 10 min after the engine goes (BATTERY_TURRET_S); traverse and elevation
drives already slow a VehicleTurret's rates (VehicleModules._effects) once those tanks have one.

### F-238 (closed by cg_brief queue item 2.6, A8, armour/logistics): field and FOB repair by module
Done: VehicleLogistics (scripts/vehicles/vehicle_logistics.gd) runs 2.2.2's field column by module
(data/vehicle_logistics.json "repair": the part, the time with two men, alone x2 but a wheel, the
states it fixes, to 60%), the service point lists them by part, a job pauses under fire or a hit
and keeps its progress on the module; ERA tiles and slat from the spares; the zone repairs keep
to the same limits on a model with modules (VehicleService.field_limit). The motor pool quotes and
services per module (data/ground_supports.json "module_prices"), fired tiles at their spare's
price, and its service clears the record's modules (it left them damaged). Track links per track,
racks (the rearm) and the bottles' refill are in. The original note:
A2 keeps VehicleService's zone repairs (a repair kit on "engine" lifts the engine and
transmission). A8: the 2.2.2 repair column per module (damaged only in the field, destroyed at
the FOB), track links per track, patching a tank, refilling racks, extinguisher bottles.

### F-239 (closed by cg_brief queue item 2.4, A5, armour/hud): the x-ray reads the HitEvents
Done: HitReport (scripts/ui/hit_report.gd) is built on every peer from `Vehicle.modules.events`
(VehicleModules._event_path adds the round's direction, angle, range, shooter, the path in order
and up to 12 spall rays to each HitEvent), never by resolving the hit again; VehicleXray's card,
full view and the pause menu's last hits read it. The original note:
`Vehicle.modules.events` (the last 10 on every peer) and `VehicleModules.describe()` are the
card's line ("pen hull_rear: transmission destroyed, engine destroyed; seats 0 hit
[mobility]"). A5 builds the HitReport and card from them (2.11).

### F-240 (closed by cg_brief queue item 2.7, A6, armour/drive; A4's part done by cg_brief queue item 2.3, armour/gunnery): turned-out crew and flooding
Done (A6): water deeper than a model's ford_m stalls its engine at once, damages it after 5 s and
destroys it after 20 s (a mobility kill through the engine module); water over its roof_m floods the
crew compartment (VehicleDrive.server_flood): everyone aboard who can gets out, nobody can board,
the hull keeps 5% of its buoyancy, and it drains 60 s after it's out of the water; an amphibious
hull holed under its waterline takes water against its pumps and floods when full. Replicated and
saved. The original note:
A2 leaves out what needs other phases: turned-out crew taking an outside blast as in the open
(2.3.6, hatches are A4), sights losing thermal and LRF when damaged (A4's sights), and flooding as
a mobility kill (A6's fording). A4 took its two: a turned-out man is out in the open for blasts
and fragments (Vehicle.seat_open: VehicleHatches.exposed) and his hitboxes stand over the hull
for rounds; the sights read their modules (VehicleGunnery.sight_for: the primary damaged loses
thermal and the laser, destroyed falls back to the aux sight; the commander's viewer damaged loses
thermal). Left: flooding (A6).

### F-241 (open, A7 or the perf lane): a launcher hit on a vehicle costs ~14 ms on the host in the hull carving
A7 (cg_brief 2.5): VehicleHull._apply walks its cube with integer distances and reads the canvas
directly, and a voxel marks only the chunks it pads (the same edits): a 0.5 m scorch 150 -> 59 ms
(R0640, R0641). A burning hull now scorches 0.35 m every 4 s (8.0-9.0 ms each, R0644), not 0.5 m
every second (8 burning vehicles took the host to a few frames a second), and a catastrophic
kill's hull marks are carved one a frame (VehicleFire._marks; the kill's own frame ~3 ms, R0645).
Four kills at once still give 3 frames of 66-190 ms (the debris bodies made, the carves): the
carve on a worker or a deferred remesh on a headless host is still the fix.
Measured while building A2 (vehicles suite, `_test_modules_budget`, R0599): a PG-7V through an
AAV-7's side is about 0.5 ms of armour work (resolve, path, spall, apply: the A2 budget) but
12-14 ms for the whole `server_take_hit`, nearly all of it V1's `VehicleHull` carve (the SCORCH
and HOLE edits re-meshing the hull's chunks on the host, `_apply` in vehicle_hull.gd). One rocket
is one hitch; an MG burst on an MRAP is many small ones. Worth deferring the remesh on a headless
host, batching a frame's carves, or carving on a worker. A7 adds more carves (fired tiles, debris).

### F-242 (open, Claude's A9): AI crews fire the main guns
cg_brief queue item 2.2 (A3) gives every action a server_* call on `Vehicle.weapons`
(VehicleWeapons): `can_fire(shooter, mount)` says why not, `server_fire(shooter, mount, dir)`,
`server_select(seat, mount)`, `server_select_ammo("main", shell)`, `server_set_fuze("main", mode,
airburst_m)`, `server_switch_feed()`, `server_set_rate(rate)`, `server_raise(up)` (the TOW),
`server_unload`, `server_restock(n)`, `server_reload_tow(rider)`, `server_refill(s)`; a TOW is
guided by keeping the turret (server_aim) on the target, slewing under WIRE_BREAK_DPS. The AI
loader, the short-crewed loads, the restock, the box refill and a dismount's TOW reload already
run on their own. Today AavGunner still fires only the coax on the Abrams and Bradley (through
Vehicle.server_fire_gun). A9's CrewGunner picks the mount and round by target (2.7.7); one hook
line in aav_gunner.gd or its replacement.

### F-243 (closed by cg_brief queue item 2.3, A4, armour/gunnery): sights and fire control replace A3's plain aim
Done: the sights and their overlay (VehicleGunnery, VehicleSight, VehicleSightOverlay), the
laser into the fire control computer (FireControl: the ballistic table from ShellFlight's flight,
lead from tracking, parallax; the gun laid off the sight by VehicleTurret.lay) and into the AMP's
airburst range (VehicleGunnery.fuze_for, through VehicleWeapons._fire_shell), the stabiliser, the
commander's 1.5x lay (VehicleTurret.rate_mult) and hand-off, and hatches (VehicleHatches: the
commander's M2 and loader's M240 fire only turned out, the M2 from inside with a "crows" package;
the TOW reloader stands out of the roof hatch, exposed). The TOW's wire follows the sight's line
(VehicleWeapons.sight_line). The original note:
A3 fires along the barrel: the gunner lays the turret (first person: the mouse; chase view: the
camera's crosshair). The SACLOS sight line is the gunner_sight module's middle along the gun's
line (VehicleWeapons.sight_origin, barrel), with its parallax to the coax. A4: the sights and
their crosshairs, the laser's range into `server_set_fuze` for AMP airburst (today a set range
only), lead and superelevation (ShellFlight.flight_to is the ballistic table), the stabiliser,
the commander's override's 1.5x lay time, and hatches: the commander's M2, the loader's M240 and
the TOW reloader are fired or worked from inside today (as if CROWS or turned out, with no
exposure).

### F-244 (open, cghath, D6b/C6): the rest of 9.2's A3 list
Not built in A3 (cg_brief 2.2 scoped it to the Abrams and Bradley): the AAV's UGWS as mounts
(Mk19 and M2 ready cans, 350 rpm, a 30 s can), the five technical guns (ZU-23-2, ZPU-2, SPG-9,
M40, Type 63) and the enemy's 2A46, 2A42, 2A72 and PKT for D6b's T-72B3, BMP-2 and BTR-82A (the
data shape is data/vehicle_weapons.json's), the crew wheel's basic orders (2.5.2, C6's contextual
menus), and timed seat moves on the MRAPs, technicals and AAV (4 s / 6 s: a "switch_s" in their
data does it).

### F-245 (closed by cg_brief queue item 2.5, A7, armour/fx): the guns' sounds and effects
Done: the M256 plays shot_m256 (a report heard to 5 km, duller past 300 m) with m256_blast (a
pressure thump and a shake within 40 m, ears ringing for dismounts within 10 m in front), a muzzle
flash, light and the dust its overpressure kicks up, the gun's recoil and the hull rocking; the
M242 plays shot_m242 (its thud, 3 km) and a small flash; the TOW plays tow_launch and tow_wire with
a launch flash and back-blast. The TOW launcher is a part of its own (the turret's "launcher" box,
VehicleTurret.split) raised 25 degrees over the 4 s raise and lowered again (VehicleFx). Left: the
Mk19's chug and engines by RPM (F-268). The original note:
The 120 mm and the 25 mm play the "hmg" shot sound; 2.10.5 wants a 120 mm report with a pressure
thump, the 25 mm's thud-thud, the TOW's launch whoosh and wire spool. No muzzle flash or blast
dust, no recoil kick on the hull, and the TOW launcher's voxels don't move when it's raised
(VehicleWeapons.state "p").

### F-246 (open, A5 or A7): the turret's modules don't turn with it
A2's module boxes are in the hull's frame, laid out for the turret to the front; A3's turrets
turn, so a round into a traversed turret meets the breech, sights, bustle rack and ring where the
turret would be facing front. VehicleModules.trace could carry the turret's modules (a "turret"
flag) into the turret's frame before the path, as Vehicle._seat_at does for its seats.

### F-247 (closed by cg_brief queue item 2.6, A8, armour/logistics): the racks become item stowage
Done: rounds are items (data/items.json "shell", "per_item", "stow_s"); a rack's rounds are its
items (VehicleLogistics.rack_items: one 120 mm round or TOW an item, a 25 mm can 50); they come
aboard through server_stow and out through VehicleWeapons.server_take_rounds (rearm and unstow
jobs at the cargo point), and the motor pool rearms to a load-out (VehicleWeapons.server_rearm's
load-out, VehicleLogistics.loadout_racks), stocking M919 for M791 when the Bradley's M919 package
is fitted. The original note:
A3 keeps which rounds a rack holds in VehicleWeapons.racks (the module's rounds stay the total);
A8's hook is `server_stow(rack, shell, n)` and `rack_contents(rack)`; `server_rearm` fills the
racks to data/vehicle_weapons.json's load-out. The M919 package unlocks the AP feed's M919 only
once some is in the racks (the default load-out is M791): A8 stocks it.

### F-248 (open, A3 follow-up): over-penetration and the player loader's window over the net
A shell that penetrates a hull ends there (A2 traces it inside); one through a soft vehicle doesn't
carry on behind it. A client's ram press is judged on the host's clock (RAM_WINDOW_S 0.7 s), so a
high ping eats into the window; worth a client-side judgement sent with the press time.

### F-249 (closed by cg_brief queue item 2.5, A7, armour/fx): the smoke dischargers' multispectral screen
Done: VehicleSmoke (scripts/vehicles/vehicle_smoke.gd): the Abrams' M250 (6 a side, salvos of 3 a
side) and the Bradley's M257 (4 a side, salvos of 2), each salvo a screen of multispectral
SmokeClouds 30 m out across the turret's front that blocks sight, thermal and the laser for the
cloud's life; a damaged launcher loses half its grenades, a destroyed one all; reloads from the
stowage (10 s a salvo, stopped, an able crewman), A8's rearm restocks; the crew wheel's "Pop
smoke" fires it. A9's call is `vehicle.smoke.server_pop(by)` (why not, "" when it went;
`can_pop()` says why first; `salvos()` counts). The original note:
2.7.1's smoke dischargers (the Abrams 2 x 6 salvos, the Bradley 2 x 4) and 2.5.2's "Pop smoke"
aren't built. ThermalView already treats a SmokeCloud of colour "multispectral"
(ThermalView.MULTISPECTRAL) as blocking thermal while ordinary smoke is hidden, and the laser
stops in any screen thick enough to block sight: the dischargers only need to spawn that colour
(CompoundLevel.server_spawn_smoke) round the turret and use up a salvo (the "smoke" modules).

### F-250 (open, A5 or the perf lane): thermal by part, and its GPU cost
A7 (cg_brief 2.5) left the parts alone (2.7.4 lists them with the sights, and 9.2's A7 row doesn't
have them): the fire sets the whole vehicle's heat (burning 1.0, a burning wreck 0.95 cooling to
the cold wreck's 0.35 over 15 minutes; VehicleFire.heat), and debris (0.8) and a thrown turret
(0.9) are hot through ThermalView's new "thermal_bodies" group.
ThermalView gives each body one heat (a man 0.85, dead 0.4; a running vehicle 0.7, cold 0.3, a
wreck 0.35, burning 1.0). 2.7.4's list wants parts: engines and exhausts 1.0, a barrel after
firing 0.8 cooling over 90 s, tracks and tyres after driving 0.6 cooling over 120 s, bodies
cooling after death, the ground 0.2-0.4 by time of day (today the ambient grey). The hull's
meshes are per chunk, so a part needs its own GeometryInstance3D or a heat mask in the overlay
shader. The CPU side is measured (gunnery suite); the GPU's extra additive pass over hot bodies
and the full-screen pass want a windowed run on a real GPU (as F-221).

### F-251 (open, Claude's A9): AI crews on the A4 API
With F-242: A9's CrewGunner lases (`Vehicle.gunnery.server_lase(seat)`: 0.5-1.5 s by skill after
acquiring, 2.7.7), lays the sight (`lay_on(point)`), waits for `laid()` and fires; reads
`solution()`; sets the AMP's fuze (`server_set_fuze("m1147", "airburst")` against infantry in the
open); corrects a miss by half. AI commanders scan with the viewer (`server_view(seat, dir)`) and
hand targets to the gun (`hand_off(point)`). Hatches: VehicleHatches' stand-in rule (out after
60 s of quiet, in at once on contact) is `auto_ai`; A9's states replace it (SAFE and AWARE out,
COMBAT in, under artillery or after a near miss, 60 s after contact ends; drivers in towns
buttoned up) with `server_set(seat, out)`. An AI gunner gets no fire control solution until it
lases (call A4.10), so today's AavGunner fires as before.

### F-252 (closed by cg_brief queue item 2.4, A5, armour/hud): what the HUDs and the audio add to A4
Done: VehicleHud (the 3P panel, the compass marks, the gun's ring, BFT chevrons in every view and
the sights), the sight overlay's crew pips, damage word and bracketed round, muffled hearing in a
closed seat (Sfx.set_muffled), VehicleVision's vision blocks and the driver's periscopes with
their night channel, the loader's turned-in view. Binoculars for a turned-out commander: his own,
if he carries them (nothing new). What's left is F-255 onwards. The original note:
VehicleSightOverlay is minimal for A5's VehicleHud to restyle (2.12.2: crew pips, the damage
word, the round selector's look, BFT blue chevrons in the sight: B5.6). Not built in A4: buttoned
up hearing muffled (outside sounds -12 dB, low-passed: 2.6), the vision blocks as a player's view
when buttoned up (he looks from his seat's eye as before), the driver's periscopes and their night
channel, the loader's turned-in view (the bustle doors, a big round selector), binoculars for a
turned-out commander (he has his own if he carries them).

### F-253 (open, cghath D6b with F-244): sights for the rest of 2.7.4's table
A8 (cg_brief 2.6) did its part: TUSK II now includes "crows" (data/vehicle_armour.json), and
VehicleHatches reads the fitted packages, so a TUSK II Abrams' commander fires his M2 from inside;
the CROWS sight (day/thermal with LRF) is still to do here.
The data shape is data/vehicle_weapons.json's `optics`, `fire_control`, `stab`, `hatches`: the
AAV's UGWS sight (1x, 3x; no laser, unstabilised), CROWS on the MRAPs and the Abrams' TUSK II
(also the "crows" package that lets the commander's M2 fire from inside: A8 adds it), the
T-72B3's Sosna-U, the BMP-2's sight and image intensifier, the BTR-82A's. The MRAP gunner's
hatch seat stays "open" (always exposed) until CROWS.

### F-254 (open, A4 follow-up): the hand-off in the chase view, and the commander's look
In the chase view a player gunner's turret follows the camera's crosshair (Arma's third-person
gunner), so once a hand-off's slew ends his camera takes the turret back; in first person his aim
carries on from the new line. The commander's viewer looks where his head looks (all round while
it's up); a full CITV with its own traverse and stabilised head apart from the seat would be
nicer, and lets him designate while turned out with binoculars (today: buttoned up only).

### F-255 (closed by cg_brief queue item 2.7, A6, armour/drive): the BRIDGE MLC alert
Done: VehicleHud.bridge_line: the span within 40 m along the way the vehicle is going (or under
it), "BRIDGE MLC 40", ": TOO HEAVY" when VehicleDrive.mlc (its mass with packages) is over the
span's class (ZoneBridges.span_mlc: the type's mlc times the span's health, sent to every peer). The
original note:
VehicleHud.alerts has every 2.12.1 alert but BRIDGE MLC: bridges have no load class yet (A6's
`mlc` on ZoneBridges). One line in VehicleHud.alerts once ZoneBridges answers "the next span on
this vehicle's way and its class".

### F-256 (open, A5 follow-up): a late joiner's x-ray starts empty
HitEvents go to every peer as they happen (A2) and each keeps the last 10, so a player who joins
mid-fight has no past hits in his x-ray list (the module states and kill states do replicate). The
host could send its last EVENTS_KEPT to a joining peer with the vehicle's state.

### F-257 (closed by cg_brief queue item 2.7, A6, armour/drive): rollover risk from a stand-in centre of mass
Done: every model has its real centre of mass in data/vehicle_drive.json (the M-ATV 1.25 m, the
MaxxPro 1.35, the technical 0.75, the AAV 1.15, the Bradley 1.05, the Abrams 0.95, merged over
vehicles.json's), and VehicleHud.tip_deg is VehicleDrive.tip_deg: the outermost wheel's or track's
offset over that height. ROLLOVER RISK reads the body's side lean (not its pitch) and shows both
numbers. The original note:
VehicleHud.tip_deg takes the centre of mass at TIP_CG_SHARE (0.45) of the hull box's height and the
hull's half width; A6's real centres of mass and track widths (2.8.3) should replace it.

### F-258 (open, A7 or the perf lane): the HUD's GPU side
The panel and markers cost 0.10 ms a frame on the CPU (vehiclehud suite, R0623); the night
channel's full-glass intensifier pass, the vision mask and the x-ray's SubViewport (drawn only
while open) want a windowed run on a real GPU, as F-250 and F-221.

### F-259 (open, Claude's A9): main guns keep B5's 50 m area rule
The door-gunner fix (cg_brief 2.4) gave AavGunner's machine guns a line-of-fire rule
(Deconfliction.bft_in_line: a tracked vehicle within 6 m of the line, out to 150 m past the target,
shorter fired downhill). Deconfliction.near_bft (no target within 50 m of a tracked vehicle) is
still there for A9's CrewGunner to use with HE and main guns, where the splash is the risk.

### F-260 (closed by cg_brief queue item 2.5, A7, armour/fx): crew voices on the intercom filter, the own engine inside
Done: crewmen (not riders) of an armoured vehicle hear each other's voice clips on the Intercom bus
(300-3400 Hz, a little clip, never muffled; Sfx.voice_route, play_intercom, one hook in
Callouts.play) buttoned up or turned out; buttoned up, the own vehicle's engine and its tracks
play on the Interior bus (louder, duller, not muffled), turned out as anyone outside hears them;
tracked vehicles' tracks clatter louder with speed. The subtitles' reach is F-267. The original note:
Buttoned up, Sfx muffles every outside sound on the effects buses (the vehicle's own engine too);
2.10.5 also wants the crew's voices on an intercom filter and the engine heard from inside (a
louder, duller drone) rather than muffled.

### F-262 (open, A7 follow-up; A8's bottles and refills done by cg_brief queue item 2.6): extinguishers and fires that spread
A8 (armour/logistics) took the logistics part: VehicleLogistics.bottles (halon 1, engine 2 on the
Abrams, Bradley and MRAPs, data/vehicle_logistics.json "extinguishers"), replicated and saved,
server_use_bottle(kind) for the extinguishing to call, and the FOB refill priced
(MotorPool's rearm, server_fob_rearm). The extinguishing and the spread are 2.10.1's (A7's
section, not 9.2's A8 row), so they stay here:
A7 (cg_brief 2.5) draws 2.10.1's stages over the burn that was there (a fire is a loss: lost at
once, a wreck after Vehicle.FIRE_S). Not built: the automatic halon in the crew compartment of
the Abrams, Bradley and MRAPs (one shot, 70%, within 1 s), the two manual engine-bay shots (60%,
the `extinguish` action), a smoke-stage fire put out 60% of the time, a fire spreading module to
module (engine to fuel to the crew compartment after 20 s), burns only to the crew in the burning
compartment, and A8's bottle refills at the FOB. They change what "on fire" means to every caller
(is_burning, destroyed, objectives, the motor pool), so they want a pass of their own.

### F-263 (open, A7 follow-up): fired ERA tiles leave their voxels
9.2's `REMOVE` edit (2.4.4: fired tiles and torn slat shown missing) isn't built: ArmourModel keeps
which tiles fired (meta armour_tiles; the HUD's doll greys them), but a tile's box takes in hull
voxels behind it too, and removing those would open the plate (a round then meets nothing). The
art needs the tiles' voxels marked (VehicleArt) so REMOVE takes only them.

### F-264 (open, A7 follow-up): damage shown on a living vehicle
A6 (cg_brief 2.7) built 2.8.3's rule for throwing a track (VehicleDrive.throw_risk,
server_throw_track: the track module destroyed); the visuals below are 2.10.4's (A7's section),
not 2.8's, so they stay here.
2.10.4's list: done, the barrel drooping to its lower stop when it's destroyed or the vehicle is a
wreck (VehicleHull.droop). Not built: a broken track running off and lying flat behind, a wheel
blown off by a mine or HE flying 5-10 m (a rigid body, as the debris), a burning engine glowing
through the deck grilles, torn slat panels.

### F-265 (open, the perf lane): A7's effects on a real GPU
The fire, smoke, debris and impact effects are GPUParticles3D (box particles; CPUParticles3D cost
6-10 ms a frame a thousand, R0642) and billboards past 600 m, at most 2,000 particles and 10 lights
in a zone (data/vehicle_fx.json budgets). Headless the CPU side is measured (vehiclefx suite: the
effects' scripts and nodes against fx_ms); the GPU's share wants a windowed run, as F-250 and F-258.

### F-266 (open, Claude's A9): AI crews pop smoke
`vehicle.smoke.server_pop(by)` fires a salvo ("" when it went, else why: "No smoke left", "Reload
the smoke", "Wrecked"); `can_pop()` and `salvos()` read it first; `server_reload(by)` reloads from
the stowage (stopped). 2.13's triggers (a seen ATGM launch, a near miss from a big round, a laser
warning) and the reverse into the screen are A9's; one hook line where its tactics decide.

### F-267 (open, Claude's Callouts): intercom lines heard only inside the vehicle
A7 routes a crewman's voice clip to his crewmates on the intercom (Sfx.voice_route), but
Callouts.say still sends the subtitle ("Gunner: Bail out!") to every player on his side; 2.5.2's
intercom channel is heard only inside that vehicle (grey, radio-filtered in 4.6's table). A
recipients rule in Callouts (crew seats of the speaker's vehicle) does it.

### F-268 (open, A7 follow-up): the rest of 2.10.5's sounds
Built in A7: the guns, the ammunition, the impacts by material, the fire's roar, the thrown
turret's crash, tracks clattering, the intercom and the engine from inside. Left: engines by type
and load pitched by RPM (today by speed: the Abrams' engine_mbt is the turbine's whine), tracks
squealing in a turn, MRAP tyre roar on asphalt, the Mk19's chug (the AAV's UGWS mounts are F-244),
the ERA tile's crack (the HitEvent says a tile fired; the impact effect doesn't read it yet).

### F-269 (open, Claude's A9 / B4): AI crews and support on A8's API
cg_brief queue item 2.6 (A8) gives every logistics action a host call any brain can make, as
players get: `vehicle.logistics.needs()` (rounds short of the load-out by shell, salvos, field
repairs with their part and time, workshop-only modules, fired tiles, fuel room, empty bottles,
recovery), `rearm_sources(actor)` and `fuel_sources()` (where from, at what speed),
`repair_options(actor)` (the field jobs and why not), `tow_candidates()` / `tow_problem(tower)`,
`server_start_job(actor, action, key, item)` (repair_module, tile, stow, unstow, refuel_from,
load_pallet, tow, unhook; the same timing, pauses and stops as a player's), `job_done` (signal),
`server_call_recovery(by)` and `VehicleLogistics.recoveries(level)` (the vehicles waiting for
one, `recovery_called`). A9: crews rearm, repair and call for recovery when the kill states say so
(F-236), a dismount helps (two men make the times), a truck's AI driver backs up within 8 m; B4's
"Request rearm" and "Tow or recovery" (4.2.8, 4.3) answer with them. One hook line each.

### F-270 (open, cghath D6a/D6b): the real ammo truck, fuel truck and recovery vehicle
No HEMTT, M978 or M88 is in data/vehicles.json yet, so A8 stands in: any vehicle's hold within 8 m
is an ammo carrier at twice hand speed (2.9.2's "ammo truck"), a drum pallet the fuel source, and
2.8.3's tow (a vehicle of half the mass) the recovery. When D6a adds the HEMTTs: give the cargo
HEMTT its ammo load in its spawn record (pallets in its hold work as they are), name the M978 in
data/vehicle_logistics.json "fuel.tankers" (9,500 L at 300 L/min is already there: its hose is
VehicleLogistics.fuel_sources' "t:" key), and an M88 is just a heavy tower (its mass already lets
it tow an Abrams).

### F-271 (open, A8 follow-up): pallets by hand
An ammo pallet is an 800 L item: nobody can pick it up ("No room for..."), a truck loads it from
beside its cargo point (Load the pallet) and Cargo > take sets it down. It weighs as full however
much is left in it, and there's no pallet jack or drag to shift one a few metres by hand.

### F-272 (closed by cg_brief queue item 2.7, A6, armour/drive): the tow bar, and righting a rollover
Done: the bar is drawn on every peer between the tower's rear hitch and the towed vehicle's nearer
one (VehicleLogistics._process, "TowBar"); the tow is in the zone save ("tow_by") and hooked up
again once every vehicle is back (server_rehook_saved, VehicleLayer.server_restore); a rolled-over
vehicle hooked up to a tower of half its mass (the same 60 s job: "Hook up to the X to right it")
is pulled back onto its wheels (VehicleDrive.server_start_righting) and stays on the tow. A tow up
a 7 degree hill works (armourdrive): the pair stuck on slopes because part throttle no longer held
a grade once the grade hold went; the drive now holds one at part throttle as far as the engine's
power goes (VehicleDrive.drive_force's demand). The original note:
The tow (VehicleLogistics.server_hook) is a spring between the hitches: no bar is drawn, it isn't
saved (a zone loaded mid-tow comes back unhooked), and A6's rollovers (2.8.3: righting by a tow,
60 s) can use it once there are rollovers. On uneven ground an MRAP's hull can scrape and the pair
sticks (seen in the armourlog suite on a slope: the suite looks for flat ground).

### F-273 (open, cghath D6b / F-244): racks for the Mk19 and the enemy's rounds
can_40_m430 (48 rounds of 40 mm HEDP) and the enemy's round_125_3bm42, round_125_3of26 and
links_30_3ubr8 are items with prices, but nothing stows them yet: the AAV's UGWS mounts (F-244) and
the T-72B3's, BMP-2's and BTR-82A's weapons and racks (D6b) give them racks, and then salvaging an
enemy's racks (Take out rounds) works as on ours.

### F-274 (open, A8 follow-up / art): packages drawn on the model, and their gadgets
2.4.5 says packages are "drawn on the model": the hull art is the same with or without (A1's tiles
are drawn whatever is fitted; the appliqué, slat, roller and CROWS have no voxels of their own).
The packages' own behaviour beyond armour and weight isn't built either: Trophy's intercepts, the
mine roller setting off pressure-plate IEDs 6.5 m ahead (3 blasts and it's scrap), CROWS on the
MRAPs (F-253's sights; TUSK II's commander's M2 does fire from inside now), the UGWS thermal kit.

### F-275 (open, Claude's A9): heavy vehicles' navmesh paths over light bridges
A6 keeps the AI off a span too light for it in two places: road routes (TerrainRoute.roads_for,
one line in SquadDrivers.plan) and the driver's care (VehicleDrive.ai_guard stops it at the deck's
end, VehicleAI then backs off and goes round, SquadDrivers sees it stuck). A path from the
navigation mesh can still lead an Abrams to a truss bridge (and every vehicle to a footbridge, MLC
2): the mesh has no idea of load. Navigation layers or region costs per class, or
TerrainRoute.path_problem on the planned path with a re-plan, would route it to the concrete one.

### F-276 (open, Claude's AI driving): other road routes by load class
us_field.gd (D7's US convoys) and mission_scenario.gd call RoadRoute.route with the def's roads as
they are; `RoadRoute.route(TerrainRoute.roads_for(v, def), ...)` is the one-line change, as in
SquadDrivers.plan.

### F-277 (open, A6 follow-up): tracks pivot at about 45% of turn_deg_s
On the spot a Bradley turns 17 deg/s against a commanded 40 (armourdrive): the stations' sideways
scrub (Vehicle.TRACK_TURN_LATERAL, the grip cap) eats most of the turning torque, as it did before
A6. The doc's half rate at 30 km/h is in the command (VehicleDrive.track_turn); tuning the scrub or
the torque cap for real pivot times (an M1 turns about 360 deg in 10-12 s) is a balance pass with
the AI drivers' corner speeds.

### F-278 (open, cghath world): rubble and other ground the level lays
VehicleDrive.add_patch(level, rect, kind, heights) lays ground over the terrain (the suite's test
ground uses it); nothing lays rubble yet: a ruined or bombed-out building's footprint, a demolished
wall, a city's ruined blocks. One call where those are built gives tracks 0.75 and tyres 0.6 of
their grip there and the track-throw risk.

### F-279 (open, cghath D6b): the Soviet vehicles' driving numbers
data/vehicle_drive.json already has 2.8.2's and 2.8.4's numbers for the T-72B3 (840 kW, fords 1.2
m), BMP-2 (220 kW, swims 7 km/h), BTR-82A (220 kW, 10 km/h) and MT-LB (175 kW, 5 km/h); they take
effect once the models are in vehicles.json, the swimmers with "amphibious" (their swim speed
there, as the AAV's). Their centres of mass, roofs and ground pressures need setting with the art.
No deep-fording or snorkel kits: 2.8.4 has none.

### F-280 (open, cghath world): river current by width
2.8.4 says ZoneWater.flow_at runs 0.5-2 m/s by width; it gives each body its preset's flow_ms
(rivers 0.8, streams 0.5, channels 0.25) along its line. A6 reads it as it is (the hull drags
through the water as it moves with it). Faster narrows and slower wide reaches are cghath's call.

### F-281 (open, cghath world; note): ZoneTerrain and ZoneScatter in an 8 km zone (cg_brief 3.1, D2)
For zones of 4,224 m or more (`on_demand`, BigZoneStreaming.streams) ZoneTerrain builds its
collision by chunk (`stream_plan` / `build_chunks`, `has_collision`, `_blanks` for GroundCuts) and
draws far tiles and rings (`_build_far_tiles`, `_ring_process`, `_ring_plan`, `ring_counts`);
ZoneScatter scales its caps by area (`_scale`, `_cap`), streams its cover by cell (`stream_plan` /
`build_cells`, `_build_cover`), frees drawn cells behind the camera (`_free_far_cells`,
`_cell_nodes`) and lets its layout go from memory as its zone goes (`forget`). Two changes give
the same result everywhere and are worth keeping when reworking these files: a chunk's collision
reads the height grid by rows (`_build_chunk`), and a cover cell's bodies get their shapes before
they enter the tree (`_build_cover`; the same collision, built much faster). Keep the `on_demand`
paths when reworking the collision, the coarse levels or the scatter's cells.

### F-282 (open, Claude's world/net): a two-process late join on an 8 km zone
The late joiner's ground (BigZoneStreaming builds the 200 m round a player who appears, anywhere,
on every peer) is checked on the host only: world_test's client joins the 2 km test zone, and the
invasion suite is one process. A client joining an operation zone generates the same 8 km zone
from the def LevelSwitch sends (~15 s headless here) and streams round its own player and everyone
it sees. A net or world suite case that joins one and walks off the start would prove it end to end.

### F-283 (open, Claude's Virtualizer): wrecks from off-screen kills of virtual rides
B2.15 left "wrecks from off-screen kills wait for virtual vehicles on profiles (A7, D2)": a ride's
vehicles killed in an off-screen fight should become real wrecks where they were (3.8). The
Virtualizer's fights don't touch rides' vehicles yet. D2 only adds the live caps (one hook in
`_wake_due`).

### F-284 (open, D1 follow-up): band 2 as a ridge with two passes on dry inland ground
Call D1-3: band 2 is always a river for now (the hint brings its own to dry presets). The ridge
with two passes needs a ZoneTerrain hook (a raised band across the axis with two cuts).

### F-285 (open, Claude's AI / perf lane): the invasion load's AI cost in an 8 km zone
The invasion suite's two cases put the same load (60 live AI fighting, 200 virtual, two columns)
in the operation zone and in a 4 km hot zone on the same terrain preset. The streaming is under 2
ms a frame at worst, but the operation zone's frames cost 1.3-1.45x the hot zone's (CI 40161930345:
70.5 against 50.3 ms), nearly all of it the AI's own ticks (squad_ai.gd 213 against 115 ms a frame
in a profiled local run; "ai" in FrameCost). The columns start at the FOB, beside the fight, in the
operation zone and away from it in the hot zone, which likely accounts for some of it. The budget
holds it to VS_HOT (1.6x); spreading SquadAI's work (F-261's idea) helps both.

### F-286 (done 2026-10-25, ops/contracts, cg_brief 3.2): what an operation contract needs from the zone
Used as written: `Operations` (scripts/campaign/operations.gd) hosts the zone from
`ZoneDef.generate_operation` (MissionRegistry.zone_def answers for "op_<seed>"), places its phases
and OOB by the def's "op" (bands, MSR, crossings, town, HQ, depth, FOB) with `OperationGen.band_at`,
`along` and `band_range`, lines `FrontGrid`'s 32 x 32 cells of 256 m up with the zone, spawns by the
front within `BigZoneStreaming.at_cap`, and sets the def's controller to the target as WorldSites
has it when it offers the operation. What was:
D3 can host an operation zone as any zone (`ZoneDef.generate_operation(seed, op_type, covers)`,
then the level switch's def). Its layout is in the def's "op": the bands, the axis, `msr`
(points) and `msr_roads` (road indices), `laterals`, `route` (the truss route), `fords`, `start`,
`fob`, `town` ("town" or "city"), `hq`, `depth` (the depth target's module id) and `river_at_m`;
`OperationGen.band_at`, `along`, `across` and `band_range` place things in it. The front grid's
32 x 32 cells of 256 m line up with the zone (8,192 / 256); BigZoneStreaming.at_cap and its live
counts are there for spawning by the front. `controller` is the first covered zone's (call D1-8):
D3 sets it from WorldSites when it offers the operation.

### F-287 (open, cghath world; CI only): props' client animals a little behind the host's
props_test's "the host's animals, where the host has them" allows ANIMAL_SLACK_M 1.5 m between the
client's glided animals and the host's when it asks. On ops/zones' CI run 40165318361 it failed on
both attempts (worst 2.57 m, then 2.71 m: a dog's 1.4 m/s over about 2 s of lag), while the same
zone code passed on runs 40161930345 and 40163881923 and locally (R0676), and props passed on
armour/drive's and claude/ai-driving's runs. Nothing in cg_brief 3.1 touches ZoneAnimals or its
sync in a normal zone. Measuring the client's position against the host's at the same packet (or
the slack from the packet's age) would take the runner's speed out of it.

### F-288 (done 2026-10-25, ops/types, cg_brief 3.3): the allies' fires and the attached armour
Done by `OpSupport` (scripts/campaign/op_support.gd; calls D4-4, D4-5). The contract's `attached`
vehicles come out at the start line at H-hour with an allied driver and gunner (and loader), the
commander's hatch left to players, overwatch the company's task (or move, hold, follow on the
company's orders: Support > Operation > Attached armour), and a player aboard can take the gun.
The `allied_fires` rounds are fired by the employer's guns (`FireSupport.server_allied_fire`, data
`allied_units`): each type's preparation fires, the allied commander's `fire_support_wanted` (smoke
for a breach) and the company's calls (Support > Operation > Allied fires), never danger close.
What was: the contract carried both and nothing used them.

### F-289 (open, D3 follow-up): a saved operation's live groups come back fresh
`Operations._store` keeps each live OOB group's men still up, its vehicles not wrecked and its
lead's position on the contract (op_run.oob), so a loaded save brings them back there by the same
rules (pending, then out as the front and the players allow). Their wounds, ammunition and the
vehicles' damage aren't kept: they come back whole. The Virtualizer's own save of them is off
(`v_nosave`), so they aren't twice in the world; keeping a profile's members (Virtualizer's
records) would take their state along.

### F-290 (open, D3 follow-up): taken off-screen, a site costs the allies nothing real
Call D3-6: a site nobody has been near falls once the allies have twice its expected garrison
round it for the flip time; `overrun_loss_share` (34%) of that garrison is counted against the
allies in the phase's record (the low-losses bonus reads it), but no profile or live group loses
the men. Taking them from the nearest friendly profile's members (Virtualizer) would make the
front's numbers honest.

### F-291 (open, D3 follow-up): the front on the map is one line
The front grid draws on the map as one blue line marker ("Front", intel channel) along the far
edge of the friendly cells. 6.3's arrows for the main and alternate axes, the cells shaded by
side, and the high command map's own drawing of it aren't built. The view (`Operations.view`)
and the grid on every peer have what they need.

### F-292 (done 2026-10-25, ops/types, cg_brief 3.3): trucks and medevac in the OOB
Done for the types whose OOB the doc gives them (the phased invasion: an ammunition and a fuel
truck; the armoured thrust: a fuel truck; call D4-7): an OOB entry's `logistics` ("ammo", "fuel")
drives to the logistics point (the MSR 400 m short of the last phase line taken) and rearms or
refuels the allied and attached vehicles within 50 m every 60 s (the vehicles' own `server_rearm`
and `server_refuel`). MaxxPros stand in for the HEMTTs until D6a (F-297). The medevac is each
type's `medevac` count of the company's Dustoff calls, flown on the employer (one line in
Economy.server_pay_support). Still not built: resupplying AI infantry in the field (no system
for it yet).

### F-293 (note, B2): hooks into the commander, none made inside Captain's files
D3 drives B2 only through its public API: `SideCommand.install(level, side, plan)`,
`server_register(squad, kind, callsign, record)`, `withdrawn`, `advance()`, and on OperationPlan
`phase`, `started`, `taken`, `taken_by`, `reserve`, `start_phase()` and `withdraw()`; DefencePlan
from the enemy's sites with their band as `line`. The hostile commander's picture is fed from
Alert's contact reports as EnemyCommand's is. Nothing in side_command.gd, operation_plan.gd,
hot_zone_policy.gd, defence_plan.gd, squad_ai.gd, tactics.gd or squad.gd changed. Worth a hook
later (Captain's side): OperationPlan saying when a phase's objectives are seized (D3 polls `taken`
each tick) and the plan's own time limits reading the contract's (D3 passes them in the spec).

### F-294 (open, D5 follow-up): the beach landing's x4 time afloat
6.4.2: "the host can speed time x4 while afloat and out of contact". Not built (call D5-4):
Engine.time_scale on the host also runs every client's view of the physics faster, and the AAV's
swim (AavWater) isn't proven stable at 4x its step. The waves swim in at their speed (a few
minutes from the stern gate to the beach). A host-only "skip the swim" (the waves moved along their
lanes while every player is aboard and nothing hostile is within 800 m) would do it without
touching the physics.

### F-295 (open, armour lane / D5): troops at the AAV's open hatches
6.4.2: "troops can stand at the open cargo hatches to see and shoot (the AAV's FFV positions, as
FfvGunner does for helicopters)". The AAV's spec has no FFV positions (data/vehicles.json `aav7`
seats: driver, gunner, 22 passengers), so the run-in is ridden inside. Two FFV seats on the cargo
hatches and FfvGunner's rules would do it.

### F-296 (open, Claude's A9): what A9 would improve for the operation types
The types use the AI that exists (cg_brief 3.3: "Don't build A9"). What A9's ArmourTactics would
add: the attached armour picking a hull-down overwatch spot with its front to the threat (today:
a point 300 m short of the task, by road), shoot and scoot and smoke on a launch; AI gunners on
the main gun and the TOW, not only the coax (AavGunner); the thrust's column keeping its spacing
by speed (a ConvoyColumn) and turning its fronts to an ambush; AT gunners aiming at the attached
vehicles' weak faces; AAV crews swimming evasive lanes under fire. OpSupport and OpThrust drive
them through SquadDrivers and Vehicle's own API, so A9 can take them over vehicle by vehicle.

### F-297 (open, D6a/D6b): the phased invasion against the Eastern Concord, and the HEMTTs
6.4.1's enemy OOB against the Concord (a mechanised company of BMP-2s, a T-72B3 platoon, Konkurs
teams) needs D6b's vehicles and data; the trucks are MaxxPros standing in for the fuel and
ammunition HEMTTs (D6a). Add a `concord` OOB to data/operations.json's phased_invasion (and the
thrust's hull-down T-72B3s) when the models land.

### F-298 (open, D5 follow-up): the town's field defences are coloured boxes
OpTown's pieces (sandbag wall, HESCO, concertina wire) are solid boxes of their size and colour on
collision layer 1: they stop rounds and people alike, wire included, and the AI's cover search
(Tactics) doesn't know them as cover points. Art (the bag pattern, HESCO frames, coiled wire),
wire that blocks movement but not rounds, and cover points for the squads would finish them.

### F-299 (note, D5): the crossing's H-hour is rolled, not chosen
6.4.4: "quietly, if the player chooses: a night or dawn H-hour". There's no briefing choice of
H-hour yet, so a seizing-a-crossing offer rolls a dawn start (05:00) half the time (call D5-6). A
briefing choice (now, dawn, night) on the contract's sky would make it the company's.

### F-300 (note, Captain's B2 side): what the types would like from the commander
The types use B2's public API only (call D4-14; no hooks in Captain's files). Worth a hook later:
DefencePlan accepting a counterattack force handed to it (today a type leads its own waves with a
SquadOrders, D5-12, because a free group would be garrisoned or contained); OperationPlan knowing
the attached armour and the column, so its own armour pairing (B3) works with them.

### F-301 (open, cghath's D3 front): a hold's ground can go back to the enemy from far off
A hold_line task needs its cell (256 m) the company's. The front's flip looks at the 3 x 3 cells
round it, so a site still standing or a group 400-600 m off can take the held cell back with no
enemy within the task's 200 m, and the hold's clock stops. Seen in the optypes suite's crossing
hold (its zones spawn no garrisons, so the bridge's checkpoint "stood"; the suite now clears the
sites by the bridge and gives the ground back as if the waves were beaten off). Worth watching in
play: a crossing or town held for minutes against nothing near. Ask: flip a held task's cell by
its own presence only, or let the hold count while no enemy is within its radius.

### F-302 (done in ops/types, cg_brief 3.3; a few lines in BaseHub, shared): clients dropped by a switch into an 8 km zone
D3-21 kept a late joiner in while it makes an 8 km zone; a client already in the session when the
host switched to one wasn't: the host makes the zone first (8-10 s of frames held, more on CI), past
ENet's 5 s, and the client dropped it (the optypes suite's client, following the host from the
invasion's zone to the thrust's: R0701, R0702). BaseHub now gives both ends LevelSwitch's
LOAD_TIMEOUT from the switch's start until the client has the level and LOAD_SETTLE_S more
(`_hold_timeouts`, two small RPCs), only for an 8 km zone. level_switch.gd unchanged. Call D4-15.

### F-261 (open, Claude's AI / the perf lane): the city's hitches are the AI's ticks
The post-merge recheck (cg_brief 2.4) of perfcases' city, alone on a quiet machine (R0633, at
1087536b): 134.7 ms average, 179.2 p95, **51 hitches a minute** (the local budget 96 passes;
R2569's 322 a minute was Captain's PC under load). Every hitch logged is a physics tick of 210-320
ms whose FrameCost is the AI's ("ai" 130-800 ms so far in the frame, nav_wanted 2-11, buildings and
probes 0-4): ~75 awake AI (63 patrolling) in SquadAI. Nothing from the world content, the vehicles
or the HUD shows. The AI's tick is Claude's (docs/performance.md "What's left": SquadAI 30-45 ms a
tick for ~100 AI, F-230's movement); spreading the patrols' think over ticks, or sleeping far
patrols (DynamicSim) in the city, would take the spikes. On CI the case still sometimes waits on
its blocks (F-233: "city_3_1 streamed in (180 s; building)", run 40043786957), and fight's hitches
ran 100 a minute against 90 there (the AI's, as before).

### F-225 update (done, perf/world-content, 2026-10-23)
A fine terrain chunk's vertices, normals and colours (ZoneTerrain._chunk_arrays) and a scatter
cell's near-tier ground cover (ZoneScatter._ground_cover, the near tier's whole cost) are worked
out on a WorkerThreadPool task, one at a time, and the mesh or MultiMeshes made on the main thread
once it's done (_take_refined, _take_cover). Measured on kestrel_valley (scratch bench, busy
machine): 22-32 ms a chunk and 27-35 ms a cell of main thread before; now a few hundred
microseconds of node and resource making. build_near (tests, the first round a spot) still builds
in place. Ground cover reads the generated ground (plane_height, plane_normal), so a crater made
before a cell's near tier is built no longer lowers the tufts on it (logged under Calls made).

### F-230 (open): soldiers' movement against a city's voxels
perfcases city (R0572, busy machine, a temporary timer round SoldierMovement._slide): move_and_slide
74 ms a frame against the AI's 472 (~13%), per soldier about three times the woods case's; the
engine's step 6-10 ms a tick in the city against under 1 elsewhere. Every voxel face is two
triangles in the blocks' collision (VoxelTerrain from the blocky mesher), so a capsule on a floor
or along a wall touches dozens. Options: a merged collision mesh (greedy faces) per block, or the
floors and walls as boxes (VoxelWorld.solid_boxes_m, as the navigation reads them) on a movement
layer, the per-face mesh kept for rounds and sight. scripts/world/voxel_world.gd.

### F-231 (open): the navigation map's async iterations
ZoneNav.build_zone turned the map's async iterations on (MAP_ASYNC, 2026-10-23): a city's map
update (~500 chunks of floors over floors) was 10-16 ms on the main thread about twice a second
(perfcases city: the server's frame median 9.8 -> 2.4 ms locally, R0576 -> R0577; CI 15.9 -> 1.5 ms
a frame, runs 39903846000 -> 39908072526). The regions' own iterations stay synchronous: an
earlier note says that with async iterations some region updates never reached the map. townperf's
seam, breach and proxy checks pass (R0578) and CI's suites do; worth a look in a city fight in game.

### F-232 (open): world draws the headless suites can't time
The draw proxy (perfcases): the terrain is ~300 draws a view in a city or town (a mesh per 128 m
chunk at each level, the coarsest out to the horizon), the scatter's far tier 350-610 from a
vehicle or the UH-60 (trunk, crown, conifer, thicket and scrub stand-ins, a MultiMesh each per
cell within 1 km). Merging the coarse terrain into 512 m blocks and the stand-ins per FAR_BLOCK
(the far blobs' blocks) as visibility parents would cut them several times over; both change where
levels hand over, so they want a look on a real GPU (F-221).

### F-233 (open): the city's blocks build slowly on CI
perfcases' city case waits for its 12 nearest blocks before it measures. On CI the wait ran out with
a block still stamping its voxels on claude/ai-driving's own run (e0caa68, run 39881233361, at 60
s) and on this branch three times (60, 100 and 180 s; runs 39908072526, 39912912838, 39916162742);
other runs had them in. Locally, even pinned to 4 CPUs, they're all in at about 60 s, with the
navigation's map synchronous or not (R0588, R0589). Each block stamps BUILD_BUDGET_MS (4 ms) a
frame while ~100 garrison men spawn and think, and CI runs that at 2-3 frames a second. Worth a
look: stamping off the main thread, or a budget shared by the blocks building at once.

## F-195 to F-197: combined arms D1's hints in the world files (notes, nothing to fix)

Branch `claude/ca-d1-operation-zones` (docs/combined_arms.md 6.2, phase D1: operation zones of
8,192 m, `OperationGen`, `ZoneDef.generate_operation`). The doc (9.1) allows one hint each in
ZoneWater and ZoneBridges; these are them, plus the landmark band hint, so the world work rebases
cleanly. Every hint is inert for a def without the key: hot and contract zones generate exactly as
before (the same seeds give the same water, crossings and landmarks).

### F-195: ZoneWater's `river_hint`

[zone_water.gd](../../scripts/world/zone_water.gd): `carve` merges the def's `river_hint.water`
into the preset's water spec (an operation brings its own river to a dry preset: `rivers` count 1,
`crossing_gap_m` 900, `footbridge_share` 1.0); `_generate` keeps the hint in `_hint`; `_make_river`
lays its first river across the hint's `axis` at `at_m` from the friendly edge (the tries still
pick the meander furthest from the pads); `_plan_crossings` gives a road crossing the river the
kind the hint planned for it within `match_m` (`_planned`: the MSR's concrete bridge, the second
route's truss, the ford tracks' fords), its `default` (a ford) for any other road, and puts the
plan's `role` on the crossing. The rng is drawn as before, so zones without a hint don't change.
If the river line or crossing planning is reworked, keep the hint: operation zones rely on the
river crossing band 2 and the MSR's bridge being concrete (seizing a crossing, 6.4.4).

### F-196: ZoneBridges' `role`

[zone_bridges.gd](../../scripts/world/zone_bridges.gd) `setup`: each bridge record gets
`"role"` from its crossing ("msr", "route", "ford" or ""), so later phases find the operation's
main bridge (A6's `mlc`, D5's demolition and firing point) without matching positions.

### F-197: ZoneModules' landmark band hint

[zone_modules.gd](../../scripts/world/zone_modules.gd): `place_landmarks` asks
`OperationGen.landmark_area(def, kind, half)` for the rect a landmark's centre may go in (its band
in an operation zone, from data/operation_zones.json `landmark_bands`; an empty rect elsewhere: the
old draw, unchanged); `landmark_kinds` also reads the zones in the def's `covers` (data/landmarks.json
"zones" by id), the def's own `landmarks` list (an operation's fallback depth target) and its
`landmark_max` (8 for an operation; the data's contract and hot maxima otherwise).

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
- 2026-10-22 | perfcases budgets re-based on cghath's world expansion (world/perf merge): town 270/360 ms and 90 hitches a minute, fight 140/260/90, woods 45/60/30, drive 52/86/45, heli 58/100/45 (Proposed) | the content about doubled the cases (R2484 -> R2485) and v0.5.3 needs a green CI; still fails a further doubling | keep the old budgets and hold the build on the city's perf
2026-10-22 | 3D loadout editor: edits are a draft until Apply (Enter) or Buy missing (B), not applied click by click | a draft can hold items the stash lacks and be bought in one go | apply each pick at once like the old menu
2026-10-22 | Saved kits: on the roster (campaign save, shared in co-op), max 40, any player may save or delete; applying makes it the standing loadout; fire teams = picked squad in fours | one list for the company | per-player kits
2026-10-22 | 3D armory: a room of 9 shelves by Loadouts group, up to 40 items a shelf (owned first, then cheapest), opened from the base screen rather than walked to in the FOB/LHD level | the levels are other lanes' files | a walk-in room in base_fob/lhd_layout
2026-10-23 | cg_brief 2.0: NIJ 0101.07's threat lists as the standard publishes them: RF1 = 7.62x51 M80, 7.62x39 MSC and 5.56 M193; RF2 adds 5.56 M855; RF3 is .30-06 M2 AP (velocities and 5 m / 15 m ranges in data/armour_standards.json) | Captain asked for the current standard, and the brief's "RF2 adds M855 and M80" would leave the old III+ plates (SAPI, UHMWPE), which map to RF1, failing against the M80 ball they stopped before; the light RF1 plate now stops 7.62 ball and AK rounds, ending 0101.06's game swap | M80 above RF1 (one line in data/rounds.json: "762x51_m80" level RF2)
2026-10-23 | cg_brief 2.0: rounds outside 0101.07's lists keep their place by the old ladder's map: 9 mm +P+, Tokarev, 9x18 HG1; 10 mm, .357 SIG, slug HG2; .303, M118LR, 6.5 CM, Mk 262, SS190, DM11 RF1; 7N6 and 7.62x54R LPS RF2; M993 and M995 RF3; .50 BMG above RF3 | every hit stays as it was except where a published list moves it | rate each round by its own penetration (no published figures to tune)
2026-10-23 | cg_brief 2.0: STANAG 4569 KE 1-3 are rated with reference rows (7.62x51 ball 8 mm, SS109 9, M193 7, 7.62x39 BZ 12, 7.62x51 WC AP 24, 7.62x54R B32 16 mm RHA at the muzzle, Proposed) run through ArmourModel.resolve on the plates; in play rifle rounds keep VehicleDamage's tiers (call 79), logged as F-227 | the plates are what's rated, and the Captain's small-calibre rule stays | shells.json rows with round_id for them (routes 7.62 AP into the plates in play)
2026-10-23 | cg_brief 2.0: a STANAG arc is proven by every crew-envelope plate facing the round from front -30..30, sides 60..120, rear 150..210 degrees at 0/15/30 degrees elevation (KE 1-4) or level (5-6), at the level's range, ricochets left out; KE 5 is 25 mm M791 APDS-T at 500 m, KE 6 30 mm APFSDS (110 mm at 500 m), front arc only | AEP-55's arcs, elevations and threats; the brief's "up to 25 mm APDS-T" is level 5 | sample only head-on (misses the roof a 30-degree shot meets)
2026-10-23 | cg_brief 2.0: tyres, an MRAP's bonnet (engine_bay) and the open O-GPK gunner's shield are outside the rated crew envelope ("stanag": false) | STANAG rates the crew compartment; with them in, nothing could rate above its bonnet or open hatch | count every plate
2026-10-23 | cg_brief 2.0: artillery levels 1-6 = a 155 mm burst at 100/80/60/30/25/10 m, its worst fragment a 20 mm FSP of 6/8/11/16/19/30 mm RHA, all round at 0-18 (1-3) or 0-30 degrees (4-6), Proposed | rounded from public summaries of AEP-55's fragment velocities | per-fragment physics (no data to tune it)
2026-10-23 | cg_brief 2.0: a mine level holds when kg x station share (belly 1, wheel 0.35, track 0.2) x belly.blast x 0.5 with blast seats reaches the crew floor at 0.55 kg or less (level 1 = 0.5 kg anywhere under, 2a-4b = 6/8/10 kg), Proposed; A2 turns the belly into crew injuries | 2.3.6's belly share, the one blast model in the doc, gives the MRAPs the brief's 3b and real-looking ratings for the rest (Bradley 2a/1, AAV 1) | a stored mine level per vehicle with nothing behind it
2026-10-23 | cg_brief 2.0: MaxxPro belly.blast 0.15 -> 0.13, BUSK III's 0.2 -> 0.18 (unused in play until A2) | 0.15 x 8 kg equals 0.12 x 10 kg, so the MaxxPro and M-ATV couldn't both be 3b on one rule; BUSK III's belly kit fell just short of 2b | MaxxPro mine 2b and BUSK III belly 1
2026-10-23 | cg_brief 2.0: the M-ATV appliqué also covers the rear (+10 mm) and roof and cargo top (+4), 0.8 t (was 0.6); a MaxxPro appliqué the same (0.9 t) | the brief's "add-on armour KE 3" means all round, and a 30-degree shot meets the rear and the roof | the doc's front-and-sides kit (front 3, sides 3, rear 2: KE 2 overall)
2026-10-23 | cg_brief 2.0: the ratings are what the plates as built give: Bradley KE 4/3/3 (its 30 mm turret sides don't stop 14.5 mm at 200 m), Abrams 6/4/3 (hull rear 30 mm), AAV 3/3/3 (the UGWS's 30 mm), Abrams TUSK 4a/1 (its 0.25 belly kit without blast seats) | the armour data stays as A1 tuned it against the 2.4.6 table | thicken plates to rate round numbers
2026-10-23 | cg_brief 2.0: aircraft and crew-served weapons are "not rated" (stanag_rated false, with a note) | STANAG 4569 rates land vehicles' crew protection; the UH-60 would read KE 2 only from the small-calibre tier rule | rate them by the tier rule
2026-10-23 | cg_brief 2.0: ArmourModel.vehicle_hit adds a fitted package's plates_add to the plate a round meets (with_packages) | the appliqué's millimetres would otherwise do nothing once A8 fits packages | leave it to A8
2026-10-23 | cg_brief 2.1 (A2): module boxes authored against each model's old zone boxes, plates and seats, with 2.2.3's hp and 2.3.5's absorb_mm (data/vehicle_modules.json, kind defaults in "kinds"); the old crew and cargo zones become "compartment" modules (absorb 0) and the hull's hp the structure | the doc leaves the exact boxes to the build session, and the compartments keep zone_health(crew/cargo) answering | boxes from the interior voxel art (D6a)
2026-10-23 | cg_brief 2.1: technicals, helicopters and static weapons keep their old zones (VehicleModules.layout builds a read-only layout from them; their hits stay on VehicleDamage and Vehicle._spall), F-228 | they have no plates, so no residual to trace, and the doc wants soft vehicles exactly as before | authoring the technicals' modules now
2026-10-23 | cg_brief 2.1: the old zones come from the modules on the five plated models (hull = structure, engine = the worse of engine and transmission, wheels = the worse track or the wheels' mean (0 past two gone), fuel = the worst tank, crew and cargo = their compartments); server_set_zone and server_repair set the modules under a zone | DriveContact, VehicleService, MotorPool, the HUD readout and saves read zones and need no change in A2 (2.2.1) | rewriting each of those readers
2026-10-23 | cg_brief 2.1: one thrown track is a mobility kill | 2.2.2 makes it immobile (it can only pivot), and objectives' "can't drive" should mean what it says; 2.2.5's "both tracks" read as the pair | a mobility kill only with both tracks gone
2026-10-23 | cg_brief 2.1: wheeled armour runs on run-flats (x0.75 a wheel, two at most) and a third gone stops it, replacing the 15% crawl on every rim (vehicles_test's check changed to match) | 2.2.2 | keep the crawl on rims
2026-10-23 | cg_brief 2.1: knocked out = catastrophic, burning, a crew kill, or a mobility kill with the guns out (or with no armament modules at all); repairable = knocked out but not burning or burnt and its structure not gone | 2.2.5 plus the brief's "knocked out but repairable"; an unarmed vehicle's mobility kill puts it out | never knocked out when unarmed; a per-module repairability table now (A8, F-238)
2026-10-23 | cg_brief 2.1: a crew kill = nobody able (up and not dying) in a crew seat, and a man who can't act in one or a crewman taken out since it last had an able crew (dead AI are put out of their seats); an empty parked vehicle is never one; a bail-out sets it through server_bail_out (A7/A9) | 2.2.5's "dead, unconscious or bailed out" without marking every parked vehicle out | any empty crew seat counting
2026-10-23 | cg_brief 2.1: catastrophic = a wreck (burned out or gone up) | every wreck in the game is a burnout, and a detonation wrecks at once | a separate flag beside wrecked
2026-10-23 | cg_brief 2.1: an ammo rack rolls to go off only when destroyed, by 2.10.2's KE / CE / HE-inside column; vent (the Abrams' bustle, doors taken as shut until A3's loader), cook_off (a fire: the Bradley's 25 mm, the AAV's Mk19 and M2 cans), catastrophic (wrecked within 0.1 s: the Abrams' hull rack, the Bradley's TOW rack); gated by Vehicle.fire_rolls like the other fire rolls; the fireball, turret toss and blast on bystanders left to A7 (F-229) | 2.2.2 and 2.10.2, A7 owning the effects | the whole A7 sequence in A2
2026-10-23 | cg_brief 2.1: a rod, jet or 12.7 mm+ shell crossing a man's real hitbox on the path is a Warheads direct hit (lethal, torn by it) | the Captain's ".50 is instant death" (2026-10-16), and a rod or jet through a body is | a wound scaled by the residual
2026-10-23 | cg_brief 2.1: a bullet Ballistics carries on (it has energy_j) skips the crew stations on the path and flies on with energy x residual left after the modules / pen | Ballistics already hits the hitboxes behind the plate; no double hits | tracing the bullet into the crew here
2026-10-23 | cg_brief 2.1: spall fragments are rays (2.5 m) from the hole's back, evenly over the cone's solid angle by the hit's seed; each stops in the first module (4% of module_dmg) or man it meets (a fragment wound, the first on each man deep, his soft armour checked as a grenade's is); compartments are air | 2.3.5 | Warheads.frag_body with physics rays (needs a level, slower)
2026-10-23 | cg_brief 2.1: HE inside: modules within 1.5 x kg^(1/3) m take 120 kJ/kg falling to 0 at the edge (twice the outside 60, confined); the crew take Warheads' blast with the radius doubled (enclosed), its lethal zone, and the round's frag_wounds (else 2-6) | 2.3.5 | the outside HE_PER_KG inside too
2026-10-23 | cg_brief 2.1: HE and stopped shaped charges outside: the module at the hit takes the old zone damage, the structure half; external modules within 1.5 x kg^(1/3) m take module_dmg x the blast share of the armour class where they sit | 2.3.6, keeping the old zone hit for charges and fire support (call 80) | only the hull
2026-10-23 | cg_brief 2.1: a belly blast is an HE hit at or below the belly plate's top (+0.15 m) going up (dir.y > 0.5); its station is the wheel within 0.7 m, the track outboard of the road wheels' line less 0.4 m, else the belly; the floor's kg is ArmourStandards.floor_kg (the mine proof's sum, refactored out of mine_result) | the brief: the same proof constants as the 2.0 mine ratings | a separate injury model
2026-10-23 | cg_brief 2.1: belly injuries: at or under 0.55 kg on the floor (what the rating holds) ringing ears for 5-20 s and nothing worse; over it a blast at 0.15 + 0.2 per floor's worth over and a fall from 3 m + 3 m per floor's worth over (WoundModel.add_fall: fractures, then death); the blast seats' halving counted once, inside the floor sum | STANAG 4569 rates a hull by its crew fighting on, so a rated hull leaves them able; 2.3.6's "blast seats halve the leg roll" is the 0.5 the proof already applies | doubling the seats' halving; a concussion roll on held blasts
2026-10-23 | cg_brief 2.1: a charge of 2 kg or more destroys the wheel or track station over it; smaller (an AP mine) only damages it like other HE; modules whose bottom is within 0.6 m of the belly's top and 1.6 m across take 120 kJ/kg of the floor's kg (the AAV's fuel under its troops) | 2.3.6's "always destroyed" read for anti-vehicle charges: a 0.2 kg AP mine shouldn't throw a 60 t tank's track | always destroyed
2026-10-23 | cg_brief 2.1: a gun seat can't fire with a gun module of it destroyed (breech, barrel, external gun, UGWS) or all its sights destroyed; until A3 the Abrams' and Bradley's coax stand-in is their armament (F-237); a damaged gun module jams for 3 s every 8 rounds, a damaged barrel scatters x3 | 2.2.2 with what fires today | waiting for A3's weapons
2026-10-23 | cg_brief 2.1: a destroyed radio sets meta radio_down (SideIntel's Blue Force Tracker, B1.13); damaged has no effect yet | B1.13's hook is the only reader | a radio state of its own
2026-10-23 | cg_brief 2.1: a HitEvent for every hit ArmourModel resolves and every belly blast, reliable to every peer, short keys (o, p, pl, sh, t, pen, s, m, c, k, b), the last 10 kept on each; module health goes in net_state as one byte each | 2.3.9 | events for penetrations only
2026-10-23 | cg_brief 2.1: budgets: a penetration's path and spall cone under 0.5 ms pure (armour_test), and the whole hit with spall under 0.5 ms on the host (vehicles_test, an AAV taking PG-7Vs) | 9.3's "a hit with spall under 0.5 ms on the host" | budget only the pure part
2026-10-23 | cg_brief 2.2 (A3): turret rates Abrams 40 deg/s traverse, 25 elevation, -9 to +20; Bradley 50 and 30, -9 to +60 (data/vehicle_weapons.json "turret", Proposed, rounded public figures); the turret and gun voxels split as the O-GPK's do (pivot over the ring, the gun's box by colour) | the doc gives the drives' effects but no rates | the default 60/40 deg/s
2026-10-23 | cg_brief 2.2 (A3): the vehicle's own "gun" stays the coax, fired by Vehicle.server_fire_gun from the cargo's belts; the main gun, TOW and the commander's and loader's guns are VehicleWeapons mounts | every AI and support system that reads gun_info (AavGunner, MotorPool, QRFs, convoys) keeps working unchanged; A9 moves the AI onto the mounts (F-242) | 2.7.2's weapons block replacing "gun" everywhere now
2026-10-23 | cg_brief 2.2 (A3): the AI loader's whole load 6 s unskilled to 5 s skilled by SquadAI combat; a player's ram window is 0.7 s from the end of the 2 s pull, a press before it gives the slow 6.5 s load | 2.7.3 gives 5-6 s and 4.5 / 6.5 s but no window | a window from the start of the ram step to its end (1.5 s: too easy)
2026-10-23 | cg_brief 2.2 (A3): short-crewed, the commander loads if he's aboard and able, else the gunner, 15 s, automatically for AI and players alike; whoever loads can't fire anything meanwhile (the coax included) | 2.5.1's table; "off his sight" | a player gunner loading only on his key
2026-10-23 | cg_brief 2.2 (A3): a damaged breech makes every main-gun load (and the 25 mm's feed switch) x1.5; the 25 mm keeps A2's jam (3 s every 8 rounds) for its damaged breech | 2.2.2's "reload x1.5" for a loaded gun, A2's jam for a belt-fed one | the jam for the 120 mm too
2026-10-23 | cg_brief 2.2 (A3): the bustle's blast doors are open only during the pull (2 s, x1.5 with a damaged breech); a vent while they're open is catastrophic (flags "doors_open") | 2.7.3, 2.10.2 | doors open the whole cycle
2026-10-23 | cg_brief 2.2 (A3): the AI loader restocks the bustle from the hull on his own when it's below 10 and the vehicle has been quiet 30 s (no hit taken, nothing fired), or at once when the gun and the bustle are both empty; a kind at a time, the one furthest below its share of the load-out; the turret within 15 deg of the front, aborted (the round back) if it turns away | 2.7.3's "between fights" and "when the bustle is below 10" | only when told
2026-10-23 | cg_brief 2.2 (A3): which rounds a rack holds lives in VehicleWeapons.racks, the module's "rounds" stays the total (A2's racks the truth for how many); rounds a hit loses come off the most numerous kind first; a count that grew (a reset, an older save) fills by the default mix; rearm counts the round in the breech as one of the load-out (33 + 1) | keeps A2's counts and saves working and gives A8 one hook (server_stow, rack_contents: F-247) | a rack per kind of round
2026-10-23 | cg_brief 2.2 (A3): the Bradley's 600 stowed 25 mm are 200 AP and 400 HE; an empty ready box is refilled (both boxes, 120 s) on its own when the vehicle is stopped and quiet 30 s with the gunner and a dismount aboard, or when asked (server_refill), and stops on a hit, moving, or either man gone | 2.7.1's "any mix", 2.7.3's refill | a player-only refill key
2026-10-23 | cg_brief 2.2 (A3): the AP feed takes M919 only with the "m919" package fitted and M919 in the racks, else M791 | the package exists in A1's data; stocking it is A8's | swap every M791 when the package is fitted
2026-10-23 | cg_brief 2.2 (A3): TOW: raising 4 s at a halt, lowering at once; moving faster than 1 m/s lowers it (a missile in the air loses its wire); a rider or the commander reloads, 45 s a missile, launcher down and stopped; an AI rider does it on his own when quiet; raising or driving off stops it and the missile goes back | 2.7.3 | the gunner reloading from his seat
2026-10-23 | cg_brief 2.2 (A3): SACLOS: the line is from the gunner_sight module's middle (turning with the turret) along the main gun's line, as it was 0.3 s before; after the boost the missile holds cruise_mps (TOW 190 m/s: 3,750 m in about 20 s), turns at 25 deg/s and steers for the point 0.5 s ahead on the line; the wire breaks on a turret slew over 25 deg/s, smoke between the sight and the missile (SmokeCloud.blocks), the launcher down or destroyed, nobody on the sight, or past wire_m, and it then falls free; Konkurs-M gets the same guidance for D6b | 2.7.2 | the line from the launcher itself (no parallax: wrong for a real TOW)
2026-10-23 | cg_brief 2.2 (A3): ShellFlight's drag is quadratic per metre (a = g - drag x v|v|), tuned so 2.7.5's table comes out within 5% (M792 7%): M829A3 7.2e-5, M830A1 1.49e-4, M1147 1.63e-4, M791 1.91e-4, M792 3.17e-4, 3BM42 7.8e-5 (the M919 and the Russian rounds by eye) | 2.3.8, 2.7.5 (the 0.00035 in 2.3.1's example was never flown) | G7 tables as rifle rounds use
2026-10-23 | cg_brief 2.2 (A3): a shell that penetrates a hull ends there (A2 traces it inside); a ricochet flies on along the bounce at 60% speed, twice at most; a solid shot goes through a man (Warheads' direct hit) and flies on; a filling bursts on whatever it meets armed (outside a hull: Warheads.server_people on everyone not under armour, the gore, the objectives), cratering the world by its kg; frag_m from shells.json (M830A1 8 m, M1147 12 m, M792 3 m), else 6 m x (kg / 0.2)^(1/3) | 2.3.3, 2.3.8; Warheads called, not rewritten | over-penetration through soft vehicles (F-248)
2026-10-23 | cg_brief 2.2 (A3): a late joiner doesn't see shells already in the air (they last seconds); every peer draws each round from the fire event and stops it at the host's end event | 2.3.8 | replaying rounds in flight to a joiner
2026-10-23 | cg_brief 2.2 (A3): gun shells hitting a model with no plates (technicals, aircraft) count as autocannon tier (data/vehicles.json round_tiers: m829a3, m919, m791, 3bm42, 3ubr8) | VehicleDamage resolves kinetic hits by tier; with no tier a 120 mm sabot bounced off a pickup | a separate kinetic path for soft models
2026-10-23 | cg_brief 2.2 (A3): the commander and loader are their own seat kinds; boarding, casualty loading and the AI's seat order treat them as the passenger seats they were (Vehicle.rider_like), so the AI's boarding order is unchanged | 2.5.1, and nothing that seats people changes behaviour | every rider check rewritten to is_rider now
2026-10-23 | cg_brief 2.2 (A3): timed seat moves only on models with "switch_s" (Abrams, Bradley); the man stays in his seat at no job until the move's done; turret to driver on the Abrams needs the turret within 15 deg of the front (refused otherwise) | 2.5.3; the MRAPs, technicals and AAV can take theirs with their mounts (F-244) | every vehicle at once
2026-10-23 | cg_brief 2.2 (A3): the turret on batteries for 600 s after the engine is destroyed, then the hand crank (VehicleModules.turret_manual), back to powered when the engine's whole | 2.2.2's BATTERY_TURRET_S | ignore the batteries
2026-10-23 | cg_brief 2.2 (A3): the commander's override fires the main gun and the TOW from his seat at once; the commander's M2 and loader's M240 fire from inside where their man looks (any bearing, -10 to +60 deg), fed from the cargo (M2 belts, 7.62 rounds) and rearmed with the vehicle | 2.5.1; A4 adds the 1.5x lay time and the hatches (F-243) | the commander's M2 only turned out
2026-10-23 | cg_brief 2.2 (A3): keys in a gun seat: 1 the seat's own gun (main gun, the commander's or loader's), 2 the coax, 3 the TOW; fire mode cycles the next round or the 25 mm's rate; reload is the loader's key, the feed switch, the launcher up or down, or a gunner's unload; a dismount's reload key reloads the TOW | the bindings players already know for weapons, fire mode and reload | new rebindable vehicle actions
2026-10-23 | cg_brief 2.2 (A3): budgets: 50 shells in flight under 0.5 ms a host physics step (9.3), a shot fired under 0.5 ms (maingun_test, Proposed); the 120 mm and 25 mm play the "hmg" shot sound until A7's (F-245) | 9.3 | no shot budget
2026-10-23 | cg_brief 2.3 (A4.1): keys: lase E (held 0.6 s: first or last return), designate Q, hatch X, sight channel C, each seated only and sharing its key with an on-foot action (lean right, lean left, crouch, rest weapon: GameSettings.SHARED); the sight on aim (right mouse, a toggle), its power on zoom in/out, the main gun's fuze on the underbarrel key (4); all rebindable and on the pad's wheel | the doc's R, T and H are reload (A3's loader and feed), voice orders and the medical menu, and every letter is taken | new actions on spare keys (none left on the letters), or moving A3's reload uses
2026-10-23 | cg_brief 2.3 (A4.2): thermal is per-body additive overlays (the heat in a magenta channel) plus one full-screen pass on the sight's overlay; the global uniform thermal_view is set but no shared shader was changed | the cheapest way here, headless-safe, no rewrite of the voxel, hull, terrain, scatter, water and sky shaders; walls still hide (one render) | every shared material shader reading the uniform (2.7.4's wording)
2026-10-23 | cg_brief 2.3 (A4.3): one heat per body: a man 0.85, dead 0.4, a running vehicle 0.7, cold 0.3, a wreck 0.35, burning 1.0 (Proposed) | per-part heat needs parts tagged (F-250) | per-part now
2026-10-23 | cg_brief 2.3 (A4.4): ordinary smoke is hidden in thermal, a cloud of colour "multispectral" blocks it (the dischargers that make it: F-249); the laser echoes off smoke of optical depth 1 or more (a first return) and stops in a screen thick enough to block sight (no last return) | how lasers and thermal meet smoke, and 2.7.4's call 21 | lasers through all smoke
2026-10-23 | cg_brief 2.3 (A4.5): turned out = the seat's "out" spot in data (standing, head and shoulders over the hull), so rounds meet the man's own hitboxes and Vehicle.seat_open gives blasts and fragments to him; 1.5 s to turn out or in | exposure through the hit paths that already exist | a separate exposure roll
2026-10-23 | cg_brief 2.3 (A4.6): AI crewmen's stand-in hatch rule: out once it's been quiet 60 s (counting from the vehicle coming into the level), in at once on contact (a hit, a round fired, a crewman shot at or near-missed in the last 60 s); A9 replaces it (auto_ai, F-251) | 2.6's SAFE/AWARE out, COMBAT in, without A9's states | AI crews buttoned up (blind) or out (exposed) all the time until A9
2026-10-23 | cg_brief 2.3 (A4.7): the hatch spotting factor (x1 out; x2.5 inside a vision block's cone, unseen outside) applies to hatch seats only (driver, commander, loader); the gunner keeps today's spotting | the gunner sees through his sight; changing it would change every armed vehicle's AI before A9 | sight-cone spotting for gunners
2026-10-23 | cg_brief 2.3 (A4.8): the primary sight damaged: day only (thermal and the laser gone), the computer on battlesight; the commander's viewer damaged: thermal gone, its lowest power left as a day picture; the aux sight isn't stabilised, so the stabiliser is off on it | 2.2.2 and 2.7.4's table ("GAS: stabilised no") | a blind CITV when damaged
2026-10-23 | cg_brief 2.3 (A4.9): the Bradley's aux sight 6x day with stadia, battlesight 1,000 m (AP, HE), the computer's error 0.15 mil, the stabiliser 0.12 + 0.05 mil; the Abrams' 0.1 mil and 0.08 + 0.04; roughness = the hull's turn rate over 0.35 rad/s (Proposed) | the doc gives only the Abrams' battlesight and no error figures | none
2026-10-23 | cg_brief 2.3 (A4.10): the computer gives a solution once the gunner lases, or while a player is at the gun (battlesight); an AI gunner keeps A3's plain aim until A9 lases | AavGunner's coax fire on the Abrams and Bradley stays as it was (battlesight's sabot lay would put it 0.14 degrees high) | battlesight for everyone
2026-10-23 | cg_brief 2.3 (A4.11): a lase that gets nothing (no return, under the 200 m gate, the laser out) keeps the last good range in the computer and says why on the sight | a slip of the thumb shouldn't throw the lay away | battlesight on a failed lase
2026-10-23 | cg_brief 2.3 (A4.12): errors per lase from its seed: the laser +-5 m, the computer's err_mil in a random direction (x3 with the fire control damaged), the lead 5% when tracked a second or more, rising linearly to 65% at none; tracking restarts on a slew over 20 deg/s | 2.7.4's LEAD_TRACK_S; the same on a replay | a fixed lead error
2026-10-23 | cg_brief 2.3 (A4.13): the stabiliser's jitter widens each round's dispersion (added in quadrature to the gun's) rather than shaking the view; unstabilised, firing on the move scatters 1 mil a m/s; past max_kmh it's off (the gun turns with the hull) | a shaking sight picture is hard to play; 2.7.4's "fire at the halt or not at all" | jitter on the sight's line
2026-10-23 | cg_brief 2.3 (A4.14): the hand-off slews at full speed with a gunner in place (his aim waits until the sight's on, 6 s at most), at 1/1.5 with none (the commander lays it himself, holding designate); the viewer only buttoned up; his lase within 10 s goes with it | 2.5.1 and 2.7.4 | the commander's lay always slower
2026-10-23 | cg_brief 2.3 (A4.15): the commander's M2 needs him turned out unless a "crows" package is fitted (F-253), the loader's M240 always; the TOW reloader (a rider) stands out of the roof hatch while he reloads, exposed | 2.5.1's table and the brief | the M2 worked from inside as A3 had it
2026-10-23 | cg_brief 2.3 (A4.16): the vehicle's own speed for the gunnery is measured from where it was each step (the round carries it, the stabiliser reads it), not linear_velocity | the same for a driven tank and a test rig moved by hand | linear_velocity (zero on a frozen rig)
2026-10-23 | cg_brief 2.3 (A4.17): the AMP's airburst goes off at the computer's range (the lase; battlesight 900 m with none) plus the fuze's 5 m; the fuze is per round, set by the gunner or commander, saved with the vehicle | 2.7.4's "AIRBURST at the lased range" | the range typed in
2026-10-23 | cg_brief 2.3 (A4.18): budgets (Proposed): thermal under 1 ms an update on the CPU at 4 updates a second (9.3; its GPU cost F-250), the gunnery's host step under 0.25 ms (0.10 measured), a lase with its solution under 0.5 ms; the sight's near plane 0.6 m | 9.3 | no budgets

2026-10-23 | Navigation chunks aren't kept round a soldier in a helicopter flying faster than 8 m/s or more than 15 m up (ZoneNav.RIDE_FAST_MS, RIDE_AGL_M, Proposed) | he can't walk off; from a UH-60 every chunk passed over was baked and dropped again (~20-25 bakes a second, R0568/R0573) and they come back as it slows to land | keep baking under every flight
2026-10-23 | The grass carpet isn't laid or drawn with the eye more than 10 m over the ground (GrassCarpet.EYE_MAX_M, Proposed) | view distance over removal: 0.35-0.75 m tufts 10-28 m off are a few pixels, and from a helicopter at 12.5 m the lays were 12-30 ms frames (R0579) | a tighter lay budget, drawn all the same
2026-10-23 | The zone's navigation map builds its iterations on a worker (ZoneNav.MAP_ASYNC); the regions' stay synchronous | a city's map update was 10-16 ms on the main thread twice a second; townperf's seam checks pass with it | keep it synchronous and bake fewer chunks round the AI (their AI_RADIUS_M, Claude's AI)
2026-10-23 | A helicopter's contour flight works out its look-ahead points 2 s and further every third tick, in turn (Helicopter.FAR_SAMPLE_S, FAR_SAMPLE_TICKS, Proposed) | ~2 ms a tick a helicopter, and those points are 25-100 m apart while they move a few metres in three ticks; heliflight passes | every point every tick
2026-10-23 | A scatter cell's ground cover is laid on the ground as generated (plane_height), not with craters made before the cell was built | so it can be laid on a worker thread without reading GroundCuts while the game writes it (F-225) | read the cuts under a lock
2026-10-23 | perfcases budgets tightened after the world content pass to about 2.5-3x CI's numbers (town 15 / 25 / 30, city 200 / 300 / 60, woods 18 / 26 / 15, drive 18 / 26 / 15, heli 18 / 30 / 15; fight 100 / 170 with its hitches 70 -> 90 a minute: its AI ticks and team spawns failed 70 on claude/ai-driving's own CI) | CI is the guard and measured town 6.0, city 83, woods 5.8, drive 6.7, heli 5.9 ms average (run 39911142961); fight is the AI's | twice a quiet local run as before (this PC had a game running all session)
2026-10-23 | cg_brief 2.4 (door gunner): a mounted machine gun (AavGunner: door guns, the M2, the coax) holds fire only for a Blue Force Tracker vehicle within 6 m of its line of fire, out to 150 m past the target, ending where a downhill miss has dropped 2 m below the target's feet (Deconfliction.bft_in_line, BFT_LINE_M / BFT_OVERSHOOT_M / BFT_GROUND_M, Proposed); its own vehicle's key as SideIntel makes it (bft_key) | B5's 50 m around every tracked vehicle held a Black Hawk's door guns and an MRAP's M2 off every enemy near any friendly vehicle (the vehicles suite's two reds since B5, afdb4f9d), and so a whole convoy off an ambush | keep the 50 m area for MGs (it stays for A9's main guns and HE: F-259)
2026-10-23 | cg_brief 2.4 (A5.1): the armoured HUDs for every vehicle with authored modules (Abrams, Bradley, AAV, M-ATV, MaxxPro); technicals, helicopters and static guns keep the text strip | the modules are what the doll, the pips and the damage word read | the new HUD on every vehicle (empty dolls)
2026-10-23 | cg_brief 2.4 (A5.2): the 3P HUD fits the HUD's zones: its panel in the strip's place (bottom centre, under the radio), the hull caret, turret bracket and hit tick on the existing compass strip, the gun's ring in the centre; on a small window the keys, the crew names, the drive line and the selector go in turn | the HUD zones keep everything apart at the ui_test's sizes (the doc's full-width bottom strip runs under the squad list and the weapon readout) | a separate full-width vehicle HUD that hides the rest
2026-10-23 | cg_brief 2.4 (A5.3): the x-ray key is 5 (rebindable, on the pad wheel: "Last hit (x-ray)"); the full view opens the latest report, or protection analysis with none at the vehicle range, the base zone or with dev tools; the pause menu's "Last hits (x-ray)" opens it too | the doc's X is the hatch since A4 and every letter is taken on foot or seated | a Shift chord (Shift is sprint and hold breath)
2026-10-23 | cg_brief 2.4 (A5.4): HitEvents carry the round's direction, angle, range, the shooter's node name, the path ([module, from, to]) and up to 12 spall rays (EVENT_SPALL); the card shows by GameSettings hud.hit_analysis (off / my shots / my shots and hits on me (default) / every hit), "mine" = the shooter is this player's node | the x-ray must draw the host's own trace (F-239); call 31's default | resolving the hit again on each peer
2026-10-23 | cg_brief 2.4 (A5.5): muffled = the local player in a closed seat of an armoured vehicle (not Vehicle.seat_open: not turned out, not an open gunner's hatch, not out of the roof hatch): -12 dB and a 900 Hz low-pass on the effects buses (Sfx.MUFFLE_DB, MUFFLE_CUTOFF_HZ, Proposed), the vehicle's own engine included (F-260) | 2.6's numbers; the MRAPs' closed cabs are as shut as a tank's | only hatch seats
2026-10-23 | cg_brief 2.4 (A5.6): vision blocks only in first person buttoned up in a hatch seat; the chase view is never cut; the block is the one nearest the player's look, pitch within 8 deg, the glass 14 deg tall, the driver's arc split into 35 deg periscopes (VehicleVision, Proposed); the sight (aim) takes over while up | 2.6's "fixed slices, 1x, no peripheral" without taking the third-person view away | a free look with a mask
2026-10-23 | cg_brief 2.4 (A5.7): the driver's night channel on the sight channel key (C), NvgView's intensifier over the glass with the rest of the HUD at 50%; driver_vision damaged: day only; destroyed: the glass blacked out, "turn out to drive" | 2.2.2's driver_vision row and 2.12.2's night | night vision always on
2026-10-23 | cg_brief 2.4 (A5.8): BFT chevrons over every friendly vehicle but your own whose radio works (SideIntel.radio_ok), within 2.5 km and dimmed past 1.5 km, in every view and the sights; none over one whose radio is down; the radio's meta now set on every peer (VehicleModules._radio_meta) | B1.13's tracker and 4.5's "blue chevron in the sight"; a dead radio is what makes armour IFF fail | a grey frozen chevron at its last place
2026-10-23 | cg_brief 2.4 (A5.9): the damage word none / damaged / mobility / firepower / knocked out / burning / wrecked; SHORT-CREWED when the driver's, gunner's or loader's seat is empty or its man is down; ROLLOVER RISK at 70% of a tip angle from half the hull's width over 0.45 of its height (F-257); MISSILE LAUNCH for a rocket or missile within 2.5 km heading within 10 deg of the vehicle (Proposed) | 2.12's alerts with what's built | a commander-only short-crew rule
2026-10-23 | cg_brief 2.4 (A5.10): budget 0.3 ms a frame for the HUD (9.3; readouts gathered 10 times a second, markers each frame; 0.10 ms measured, R0623), 2x locally under load | 9.3 | gathering every frame
2026-10-23 | cg_brief 2.4 (A5.11): protection analysis: ArmourModel.resolve with seed 20261023 at 100-3000 m, the ricochet chance over 40 seeds, every shell with a penetration figure, the vehicle's fitted packages and all its tiles whole | 2.11's "fixed seed"; the chance shows how often a bounce happens | one seed only
2026-10-23 | cg_brief 2.4 (A5.12): the loader's turned-in view is drawn over his periscope (the bustle doors' state and a large tile per round, the next one lit, the reload bar), not a rendered turret interior | the turret's inside has no art yet; the information is what the job needs | an interior model
2026-10-23 | cg_brief 2.4 (city hitches): perfcases' city budgets kept as they are (60 a minute on CI, 96 locally): alone on a quiet machine the city ran 51 a minute (R0633), every hitch an AI tick (F-261) | the measurement shows the budget holds on a quiet machine; R2569's 322 was load | raising the budget
2026-10-24 | cg_brief 2.5 (A7.1): 2.10.1's stages over the burn that was there: grey smoke 8 s, then flames; lost at once and a wreck after Vehicle.FIRE_S (45 s) as before; the wreck burns on 120-300 s (seeded), its column stands 300-600 s from the wreck, then a smoulder for the deployment; extinguishers and spreading fires left (F-262) | every caller reads "on fire = lost" (is_burning, destroyed, objectives) | rebuilding the burn as per-module fires now
2026-10-24 | cg_brief 2.5 (A7.2): bail-out stand-in: the AI aboard an armoured vehicle get out by its doors on a cook-off or after 3 s of flames ("Bail out!", a crew kill), not on a catastrophic kill, never from a helicopter; VehicleFire.auto_bail for A9 to replace (F-236) | 2.10.1's triggers; A9 owns where they run | crews burning to death in every fire until A9
2026-10-24 | cg_brief 2.5 (A7.3): a fireball counts main-gun rounds and missiles (racks the fx block marks big) plus the other racks' rounds / 50; the turret goes at 10 or more big rounds (an Abrams with its hull rack: toss; a Bradley's 5 TOWs: the hull ruptures) | 2.10.4's formula wants one count; 25 mm aren't main-gun rounds | every round counted alike (a Bradley's 900 25 mm would throw its turret)
2026-10-24 | cg_brief 2.5 (A7.4): cook-off pops: 0.05 kg each for 25 mm and 40 mm, 0.3 kg for 120 mm and missiles, 0.01 for .50, every 0.5-3 s (seeded) out of the rack's top | 2.10.1 | one blast at the end
2026-10-24 | cg_brief 2.5 (A7.5): the fireball's blast reaches people only (Warheads.server_people, 18 m fragments); a vehicle parked beside takes nothing | Warheads' people path is what 2.10.4 names | routing it through every hull near
2026-10-24 | cg_brief 2.5 (A7.6): every peer throws the turret and the debris from the seed; the host's rest poses (turret asleep or 12 s, debris frozen at 30 s) replace the clients' and go to late joiners and the save; the kill event carries the seed (it can beat the state) | call 30 and BlastGore's pattern; physics differs between machines only in flight | streaming positions
2026-10-24 | cg_brief 2.5 (A7.7): debris: 12-24 boxes of 0.18-0.55 m off the roof at 6-16 m/s; at most 64 moving in a zone (the oldest frozen static), 256 kept; 4 holes with scorches on the roof, carved one a frame | 2.10.4, 2.10.6 | merging them into one static mesh
2026-10-24 | cg_brief 2.5 (A7.8): dischargers: a salvo is 3 grenades a side (M250, 6 tubes a side: 2 salvos, 6 a side stowed) or 2 (M257, 4 tubes: 2 salvos, 4 stowed), landing 30 m out at 3/17/31 (4/20) degrees off the turret's line, multispectral clouds lasting a grenade's 30 s; damaged loses half, destroyed all; reload 10 s a salvo, stopped, an able crewman; the FOB rearm restocks | 2.7.1's 2 x 6 and 2 x 4; one grenade a side left a gap the sight line went through | a salvo of one grenade a side
2026-10-24 | cg_brief 2.5 (A7.9): gun sounds: shot_m256 to 5 km (far past 300 m), m256_blast and a shake within 40 m outside, ears ringing up to 8 s for dismounts within 10 m and 60 degrees of the bore (not with ear protection); shot_m242 to 3 km; tow_launch to 1.5 km, tow_wire at the launcher | 2.10.5's "pressure thump close by" | no overpressure harm
2026-10-24 | cg_brief 2.5 (A7.10): the intercom: crew seats (not riders) of a vehicle with modules, buttoned up or turned out (CVC helmets), on a 300-3400 Hz band with a little clip, never muffled; riders and men outside hear voices as before; subtitles still go to the side (F-267) | 2.5.2 | everyone inside on the intercom
2026-10-24 | cg_brief 2.5 (A7.11): your own vehicle from inside: buttoned up its engine and tracks on an Interior bus (+4 dB, 500 Hz low-pass, not muffled), turned out as outside; tracks silent at a halt, full at 8 m/s | 2.10.5, F-260 | muffling your own engine with the outside
2026-10-24 | cg_brief 2.5 (A7.12): impacts: ricochet sparks and a ping; KE stopped sparks and a thud (MBT composite), clank (IFV aluminium) or clang (steel); a penetration's white flash and boom; HEAT's orange flash, black puff and bang; HE a ball by its filling; tracers white-hot (sabot), orange (HEAT), red (HE) | 2.10.3 | one flash for every end
2026-10-24 | cg_brief 2.5 (A7.13): budgets: full effects (flames, light) on the 6 nearest fires, smoke only beyond; 2,000 particles, as GPU particles (CPU particles cost 6-10 ms a frame a thousand); 10 lights; 64 moving debris; a billboard past 600 m; fx_ms 1.5 ms a frame of CPU for 8 fires and 4 kills' debris; kill_ms 40 ms for a catastrophic kill's frame on the host; 3x slack locally | 2.10.6, 9.3 | CPU particles
2026-10-24 | cg_brief 2.5 (A7.14): a burning hull scorches 0.35 m every 4 s (was 0.5 m every second: 60-150 ms a second of host carving per burning vehicle), and VehicleHull's carve loop runs 2.5x faster for the same edits | F-241; VehicleFx draws the fire now | leaving it (8 burning vehicles held the host to a few frames a second)
2026-10-24 | cg_brief 2.5 (A7.15): F-250's per-part heat stays with A4 and the perf lane; A7 ties the fire to thermal (burning 1.0, a burning wreck 0.95 cooling to 0.35 over 15 minutes, debris 0.8, a thrown turret 0.9) | 9.2's A7 row; 2.7.4 lists parts with the sights | per-part heat in A7
2026-10-24 | cg_brief 2.5 (A7.16): the TOW launcher is its own part on the turret, raised 25 degrees nose-up about its rear hinge over the 4 s raise and lowered in 1.5 s; rounds meet its voxels as stowed whatever its pose; a thrown turret's voxels leave its hull's hit test | F-245; a few voxels | posing every part for hits
2026-10-24 | cg_brief 2.5 (A7.17): a rack that goes up in a vehicle already alight from the same hit's fire roll still goes up at once (the burn cut to 0.1 s) | 2.10.2 | A2's order (a 45 s burn first)
2026-10-24 | cg_brief 2.5 (A7.18): wrecks in saves from before A7 smoulder (no column) | they burned out long ago | no smoke at all
2026-10-24 | cg_brief 2.5 (A7.19): Pop smoke from the crew wheel (C6's option, VehicleSmoke.request_pop); no key of its own yet | the wheel already had it | a new rebindable key
2026-10-24 | cg_brief 2.6 (A8.1): rounds are items of type "vehicle" with stats shell / per_item / stow_s (round_120_m829a3, _m830a1, _m1147, links_25_m791, _m919, _m792, tow_2a, can_40_m430, smoke_salvo; the 120 mm and TOW two-handed); the racks keep counts by shell, so a rack's items are its rounds (one each, 25 mm by cans of 50) and a can goes in only whole | 2.9.2's ids; one model for racks, saves and hits | type "ammo" (the inventory pools those by calibre as magazines and loose rounds) or a rack of item entries
2026-10-24 | cg_brief 2.6 (A8.2): the right rack: a cannon's racks then its stowage (the bustle, then the hull rack); the 25 mm and the TOW into the hull's stowage only, the crew filling the ready boxes and the launcher from there as A3 has it | 2.9.2's "into the right rack" without breaking A3's feeds | anything into the ready boxes
2026-10-24 | cg_brief 2.6 (A8.3): the ammo truck: no HEMTT in data, so any vehicle's hold within 8 m (with its pallets) is an ammo carrier at twice hand speed (F-270) | 2.9.2's rule works today with the M-ATV and MaxxPro holds | waiting for D6a's HEMTT
2026-10-24 | cg_brief 2.6 (A8.4): an ammo pallet is an item (800 L: too big for a man, a truck's hold takes one) holding its load in its state, one data/pallets.json kind per calibre (120 mm 6/4/2, 25 mm 4 M791 + 8 M792 cans, 6 TOW, 12 salvos, and the drum pallet 4 x 208 L); a vehicle within 8 m rearms from it at hand speed | the item system already replicates and saves state on the ground and in holds | PalletField site pallets (enemy sites, no shared contents) or a static vehicle model per pallet
2026-10-24 | cg_brief 2.6 (A8.5): rearming needs one able man on foot at the cargo point (or a crewman aboard working from the hold), the vehicle stopped (0.5 m/s), not burning; it pauses under fire and while the vehicle is being hit, as repairs do | 2.9.2 gives times, not crew; the repair rules for the rest | two men for every rearm
2026-10-24 | cg_brief 2.6 (A8.6): the helicopter resupply's armour load rides on the existing resupply drop: for each company tank or IFV in the zone that's short, a pallet of the calibre it's shortest of (by share of its load-out), 8 x 120 mm, 6 cans of 25 mm or 2 TOW in its load-out's mix | 2.9.2's "the existing support gets an armour ammo load" | a separate support with its own price
2026-10-24 | cg_brief 2.6 (A8.7): the FOB rearm charges the main-gun, autocannon and TOW rounds and the smoke salvos it puts in at prices.json "ammo" (and the bottles' refill), to the run (Economy.charge_run) going out and coming home; MG belts stay a free top-up; rounds swapped out by a new load-out aren't refunded | 2.9.2's "everything, priced" without moving the MRAP-only economy (Captain's 2026-10-14 belts fix) | charging belts too
2026-10-24 | cg_brief 2.6 (A8.8): three FOB load-outs per armoured model (standard = the racks' default, anti_armour, urban), picked on the motor pool page | quick to tune, readable | a per-round editor
2026-10-24 | cg_brief 2.6 (A8.9): the field table is 2.2.2's (engine 90 s, transmission 120, tracks 180, a wheel 25, a fuel tank patch 45, traverse and elevation 60, a mounted gun 60, the UGWS 90, a periscope 30, a radio 20, a tile 40) at 2.9.3's two men (alone x2), but the wheel a one-man job as today; to 60% (engine parts to 100%, their own numbers); a destroyed track, wheel, fuel tank, periscope or radio is fixed in the field, the rest damaged only | 2.2.2 is the per-module source, 2.9.3 the crew rule | 2.9.3's 60-120 s band for the engine
2026-10-24 | cg_brief 2.6 (A8.10): a helper is an able man of the same side on foot within 3 m of the worker | two men work a track together | crewmen inside counting
2026-10-24 | cg_brief 2.6 (A8.11): a job pauses (worker suppressed over 0.3, or fired at in the last 2 s; the vehicle hit in the last 5 s) and stops if the worker walks 1.5 m off or the vehicle moves, its progress kept on the module (saved, replicated) | 2.9.3's "pauses while suppressed or hit" | restarting from zero
2026-10-24 | cg_brief 2.6 (A8.12): parts come from the worker's kit first, else the vehicle's hold | 2.9.3: spares carried in the cargo hold | the worker's kit only
2026-10-24 | cg_brief 2.6 (A8.13): the old zone repairs stay for technicals and callers that name a zone, kept to the same field limits on a model with modules (VehicleService.field_limit); the service point lists repairs by part there | the vehicles suite's zone checks keep their meaning | removing the zone repairs
2026-10-24 | cg_brief 2.6 (A8.14): the motor pool's quote per module: a destroyed module costs its kind's share of the model's value (module_prices: structure 0.12, engine 0.06, breech 0.05, gunner's sight 0.05...), scaled by the health it lacks; days repair_days x the bill's share, at least 1, at least fob_days 2 with a module destroyed past what the field fixes; fired tiles at their spare's price | 2.9.3's "priced per module, days by damage" | flat prices per module
2026-10-24 | cg_brief 2.6 (A8.15): packages: fit days by package (TUSK I 3, TUSK II 4, Trophy 4, BUSK III 3, CROWS 2, slat, roller and thermal kit 1, the rest 2, M919 0), removing 1 day for half the price back; an upgrade (TUSK II over TUSK I) credits the one it includes and drops it from the list; "needs" gates on the employer's tier, "after" on a fitted package, and one another needs can't come off first | 2.4.5's table, prices and refund | days by weight
2026-10-24 | cg_brief 2.6 (A8.16): the packages' weight changes top speed, the drive's acceleration and fuel per km by 2.4.5's formulas; the body's physical mass stays the model's | the suspension and handling stay as tuned | raising the RigidBody's mass (sag, braking change)
2026-10-24 | cg_brief 2.6 (A8.17): fitted packages live in VehicleLogistics (net_state, the zone save, the motor pool record's "logistics") and set ArmourModel's meta on every peer; fired tiles replicate and save the same way | A1 call 86 left them host meta "until A2/A7 move them" | separate syncs per system
2026-10-24 | cg_brief 2.6 (A8.18): recovery is 2.8.3's tow: a vehicle of at least half the towed one's mass, 60 s hooking up at the towed vehicle's service point by a man on foot, both stopped, hitches within 8 m; a 3 m stiff damped bar (6 N/m per kg), the pair at 15 km/h, the towed vehicle's brakes and skid steering off; not saved | no recovery vehicle in data (F-270); A6's rollovers want the same tow | an off-map recovery purchase
2026-10-24 | cg_brief 2.6 (A8.19): fuel: a drum pallet (4 x 208 L, a hand pump at 60 L/min) on the ground or in a hold within 8 m; the M978's 9,500 L at 300 L/min as data for D6a | 2.9.1's sources with what exists | waiting for the tanker
2026-10-24 | cg_brief 2.6 (A8.20): extinguisher bottles: halon 1 and engine 2 on the Abrams, Bradley and MRAPs, refilled at the FOB at $2,500 and $600 | 2.10.1's shots; F-262 uses them | no counts until F-262
2026-10-24 | cg_brief 2.6 (A8.21): prices: round items per round (prices.json "ammo", 2.9.2's numbers), pallets their load plus $300, a smoke salvo $600, a periscope $1,500, an ERA tile $3,000, a slat panel $1,200; the enemy's 125 mm and 30 mm sell-only; every package in prices.json "packages" (the MaxxPro appliqué $40,000) | 2.9.2 and 2.4.5 | guessing per item
2026-10-24 | cg_brief 2.6 (A8.22): budgets (9.3 gives A8 none): a vehicle's logistics tick 0.05 ms, needs() 0.3 ms, the cargo point's menu 3 ms, 3x slack locally | small against the frame; the menu walks nearby vehicles and items | none
2026-10-24 | cg_brief 2.6 (A8.23): TUSK II includes CROWS ("crows" in its includes), so its commander's M2 fires from inside; VehicleHatches reads the fitted packages, not the raw list | 2.4.5's TUSK II row; F-253 says A8 adds it | a separate Abrams CROWS package
2026-10-24 | cg_brief 2.7 (A6.1): the driving numbers in data/vehicle_drive.json, a topic file merged into each model's spec (VehicleSpecs.TOPIC_PATHS) and over vehicles.json's "com": power_kw, ford_m, roof_m, ground_kpa, belts, the real centres of mass (M-ATV 1.25, MaxxPro 1.35, technical 0.75, AAV 1.15, Bradley 1.05, Abrams 0.95 m) | 9.1's data split; one file for the driving lane | editing vehicles.json
2026-10-24 | cg_brief 2.7 (A6.2): ZoneTerrain.ground_at: road cores asphalt (asphalt, street) or dirt; pads dirt, their streets asphalt; water over 0.05 m mud, a ford's gravel track dirt; marsh soft over 0.35 mud; snow over 0.4; slopes over about 37 deg or 4 m over the preset's rock line rock; riverbed weight over 0.45 and beaches sand; a salt pan's crust dirt; else grass; decks asphalt (footbridges dirt); no terrain (compound, range) dirt; level patches (add_patch) over all | 2.8.1's table from what the world has; fords are where columns cross | per-wheel splat reads (cost)
2026-10-24 | cg_brief 2.7 (A6.3): a wheel's grip is Vehicle.GRIP (0.95) x the table's traction; rolling resistance comes on top of the grip (soft ground holds a vehicle that grips); on sand, mud and snow it scales by sqrt(ground pressure / 150 kPa) within 0.7-1.5; ground pressures M-ATV 290, MaxxPro 320, technical 220, AAV 57, Bradley 76, Abrams 103 kPa | wide tracks float, narrow tyres dig in | rolling resistance inside the grip (an MRAP climbed out of anything)
2026-10-24 | cg_brief 2.7 (A6.4): power at the wheels power_kw x 0.8; the pull min(P / max(v, 2), the force for accel_ms2 x throttle net of rolling resistance and the slope), so part throttle holds a grade only as far as the power goes; top_speed_kmh the governor | 2.8.2's formula, and AI drivers (VehicleAI's part throttle) still climb | throttle as a share of the power (AI vehicles stalled on hills)
2026-10-24 | cg_brief 2.7 (A6.5): ground vehicles lose the engine's default linear damping (0.12 x v, 1/s, which held them all near 50 km/h) for air drag 0.5 x 1.2 x 0.9 x the hull box's frontal area x v^2 | the power and governor mean something; the 0-30 km/h times then match 2.8.2 within 5% | compensating the damping in the drive
2026-10-24 | cg_brief 2.7 (A6.6): tracks turn at turn_deg_s x the ground's tracked traction over firm dirt's (0.85, at most 1), half by 30 km/h | 2.8.3's falloff "scaled by traction" without slowing tanks on the range's dirt | traction as is (every tank 15% slower on dirt)
2026-10-24 | cg_brief 2.7 (A6.7): the tip angle atan(outermost wheel or track offset / CoM height); rolled over after 0.75 s past it (body tilt); the crew falls 3.2 m (belted seats half: MRAPs' but the gunner's; open seats and riders 1.5x); the HUD's ROLLOVER RISK by the side lean at 70% | 2.8.3; the tilt table holds at 34-38 deg body lean and rolls by 33-35 deg ground for the MRAPs (within 10%) | a hit-point pool for crashes
2026-10-24 | cg_brief 2.7 (A6.8): righting is A8's tow job (60 s at the service point, a tower of half the mass), then a winch pull: a torque up to 1.4x the weight's turning moment, a lift of 0.45 g while past 45 deg, done under 12 deg and settled, given up after 30 s; it stays on the tow | 2.8.3's "a new tow action" is A8's, so one job | a teleport upright
2026-10-24 | cg_brief 2.7 (A6.9): the AI driver's care (host, AI input only, in zones): lateral acceleration under 0.6 x the tip's (g x half track / CoM height: off the throttle, then braking), and a look 6 m + 1.5 s ahead at 10 Hz by rays onto the world for a span too light, water deeper than it fords, a side slope over 60% of its tip angle, a grade over its climb; stopped, VehicleAI backs off and goes round | 2.8.3's 60% and 2.8.5's never-over-a-light-span without editing VehicleAI | AI that tips MRAPs in corners
2026-10-24 | cg_brief 2.7 (A6.10): bogging: a wheeled vehicle of 250 kPa or more on mud, under 3 km/h for 4 s with the throttle open on more than 2 deg, stuck until towed 4 m | 2.8.1's "MRAPs can bog"; the technical doesn't | bogging every wheeled vehicle
2026-10-24 | cg_brief 2.7 (A6.11): thrown tracks: steer 0.9 or more over 10 km/h on rock or rubble, or leaning over 20 deg, 0.5% a second, the outer track (rolled from the vehicle and the physics frame) | 2.8.3 | a random roll per frame
2026-10-24 | cg_brief 2.7 (A6.12): fording depth is the water over the ground under the hull (not over its floor, as AavWater had); the engine stalls at once, restarts 3 s after it's out (if it lives), damaged after 5 s, destroyed after 20 s; roofs M-ATV 2.52, MaxxPro 2.92, technical 1.72, AAV 2.64, Bradley 2.0, Abrams 1.5 m; flooded: the crew out, no boarding, 5% buoyancy, dry 60 s after it's out | 2.8.4's depths are depths of water | the hull floor's depth (an M-ATV stalled in 1 m)
2026-10-24 | cg_brief 2.7 (A6.13): an amphibious hull holed by a penetration under its waterline (1.5 m on the AAV) takes 35 L/s a hole against 25 L/s of pumps and sinks at 9,000 L aboard (its buoyancy falling with it) | 2.8.4's "hull holed below the waterline" | sinking at the first hole
2026-10-24 | cg_brief 2.7 (A6.14): the waterjets push by the mean of A2's two waterjet modules' health; one out pulls it round at half its turn rate | the brief's "waterjets from A2's modules" | jets ignoring damage
2026-10-24 | cg_brief 2.7 (A6.15): a hull drags through the water as the water moves (ZoneWater.flow_at), so a swimming AAV crabs and drifts at the current; 2.8.4's 0.5 x rho x 1.0 x A x v_rel^2 pushes a hull that isn't afloat (a truck in a ford) | the formula alone left a floating hull nearly still in the current | both on every hull (counted twice)
2026-10-24 | cg_brief 2.7 (A6.16): a vehicle's MLC is its mass with its packages in tonnes, rounded up (the Abrams 62, 66 with TUSK II); a span's class is its type's (80 / 40 / 2) times its health share; over it the span loses hp x (load / class - 1) / (0.5 x 8 s) a second, the class as it was when the load came on (1.5x drops it in 8 s; the shown class falls as it weakens); weighed 4 times a second; its health sent to the clients each 0.25 it falls | 2.8.5 | tracked MLC tables by STANAG 2021 (no public tables to tune)
2026-10-24 | cg_brief 2.7 (A6.17): RoadRoute gets the load classes through TerrainRoute.roads_for (the road pieces within 3 m of a too-light bridge's deck line left out), one line in SquadDrivers.plan (Captain's AI-driving file) | 2.8.5's "RoadRoute gets the bridge's mlc" without changing RoadRoute's graph | an mlc per segment in RoadNet's def
2026-10-24 | cg_brief 2.7 (A6.18): the HUD lines: ROLLOVER RISK x / y deg, ROLLED OVER: NEEDS A TOW (RIGHTING), FORD x / y m, AFLOAT, FLOODING n%, FLOODED: GET OUT, STALLED: TOO DEEP, BOGGED: NEEDS A TOW, BRIDGE MLC n (: TOO HEAVY) for a span within 40 m ahead | 2.12.1's alerts with A6's numbers | a separate driving panel
2026-10-24 | cg_brief 2.7 (A6.19): budgets (9.3: the physics step unchanged): a vehicle's drive step 0.03 ms, the AI driver's care 0.05 ms a tick, the bridges' weighing 0.2 ms with 25 vehicles, an Abrams' 14 stations of wheel forces 0.25 ms (most of it the suspension rays from before A6); 3x locally | measured 0.013, 0.018, 0.08 and 0.13 ms (R0672) | none
2026-10-24 | cg_brief 2.7 (A6.20): no deep-fording or snorkel kits (2.8.4 has none); the thrown-track and blown-wheel visuals stay A7's (2.10.4, F-264) | the doc's split | building them here
2026-10-25 | cg_brief 3.1: ops/zones starts from armour/drive (PR #34) and merges claude/ca-d1-operation-zones as a real merge, both sides kept in every conflict (zone_def, zone_water, zone_scatter: the prop library's collision moved into D2's per-cell _build_cover; CHANGELOG, followups) | the brief's plan: conflicts resolved once, on the newest world code | rebasing the WIP (rewrites its commits)
2026-10-25 | cg_brief 3.1: the D1/D2 calls renumbered D1-1..D1-12 and D2-1..D2-13 in their own section of docs/combined_arms.md 10 (the WIP had 74-90, which A1's calls 74-92 also use) | no two calls with one number | prefixing the old numbers
2026-10-25 | cg_brief 3.1 (D1-12): an operation of data "city_op_types" (hold_town) gets a city (BuildingGen.city_layout) where its town module would stand; the MSR to the city's near side and on from its far side, through its own streets | 6.2.1's "urban types where cghath's city work allows"; a city is the heaviest perf case | every operation's town a city
2026-10-25 | cg_brief 3.1 (D2-2): ground collision planned every 0.25 s and built every physics frame for 0.75 ms (data "frame_ms"), nearest first, at least one chunk and one cell a frame; a soldier whose squad is in a fight holds 450 m on the host ("engaged_in_m") | the WIP's 12 chunks + 3 cells a tick were 25-50 ms spikes (one wooded cell was 25 ms); an AI fight far from the players needs the hills between the sides | a time budget per 0.25 s tick (2 ms: the 1 km round a flying player then lagged 10-12 s)
2026-10-25 | cg_brief 3.1 (D2-7): an 8 km zone's terrain drawn as 256 far tiles (512 m, coarsest step, from 2 km) plus each chunk's levels in rings on a worker (650 m / 1.5 km / 2.6 km, freed past 0.9 / 1.8 / 3.0 km); a level drawn from 0 while the one inside isn't built (ZoneTerrain FAR_TILE_*, RING_*) | 8,192 coarse meshes and draws up front, held all game; the rings keep memory and draws to where the camera is | every chunk's coarse levels up front as in smaller zones
2026-10-25 | cg_brief 3.1 (D2-3): an 8 km zone's scatter frees a drawn cell's near tier past 620 m and its far tier past 1.4 km (ZoneScatter NEAR_FREE_M, FAR_FREE_M), and looks only at the cells near the camera | its 4,096 cells were all looked at every 0.5 s and every one passed stayed built | keeping them (memory grows with the ground seen)
2026-10-25 | cg_brief 3.1 (D2-8): a chunk or cover cell with an item, ragdoll or vehicle in it is kept (one shape query, every 5 s while held, at most 24 looks a plan: BigZoneStreaming.held, FREE_PER_PLAN) | nothing falls through when everyone leaves; a teleport leaves hundreds of chunks behind at once | freeing them and letting GroundGuard put bodies back
2026-10-25 | cg_brief 3.1 (D2-9): a player or vehicle that appears gets the 200 m round it at once (ensure_m), the cover cell under it too; every peer streams round every player, vehicle and soldier it has | late joiners anywhere on the map, respawns, spawned vehicles | waiting for the next frames' budget
2026-10-25 | cg_brief 3.1 (D2-10): the perf pass's helicopter rule (ZoneNav.RIDE_FAST_MS / RIDE_AGL_M) for a player aboard: his ground stays at 1 km, his cover drops to 300 m | reuse the rule the perf pass already has for the heli; rounds still meet the ground | the full 1.2 km of cover at 250 km/h
2026-10-25 | cg_brief 3.1 (D2-11): an 8 km zone's scatter layout (~164,000 items) is let go from memory as its zone goes, kept on disk (ZoneScatter.forget) | up to CACHE_ZONES of them in memory would be gigabytes | keeping it like a hot zone's
2026-10-25 | cg_brief 3.1 (D2-6): the invasion case is a suite (tests/invasion_test.gd extends perfcases_test.gd for its meter; `invasion` in run_tests.sh and CI's ALL_SUITES, 1200 s); the WIP's tests/invasion_perf.gd goes | one meter, a real suite with budgets, the hot zone in the same run | a second copy of the meter, or the timing script
2026-10-25 | cg_brief 3.1 (D2-12): headless budgets (60 Hz frame cost; perfcases' LOCAL_SLACK off CI): invasion and hot 140 / 190 ms avg / p95 (about twice CI's first run), 60 hitches a min, invasion at most 1.6x a 4 km hot zone on the same preset under the same load (CI 1.40x, the AI's own ticks: F-285); drive and flight 20 / 30-32 ms, 15 hitches a min, nothing missing within 300 m, the 1 km whole again within 4 s; the physics step 6 / 1.5 ms a tick; a frame's streaming 8 ms; the zone hosted in 45 s, 1.4 GB static, growing 150 MB at most across it (30 MB here); the doc's 14 / 33 ms printed beside | headless can't time the GPU and 60 live AI already cost the hot zone 50-100 ms of CPU here; D2 must not add to it and must keep up | the doc's 14 / 33 ms as the headless check (every AI-heavy case fails it today)
2026-10-25 | cg_brief 3.1 (D2-13): CI runs the same 8 km zone and cases, for perfcases' CI_MEASURE_SHARE of the time | it loads in ~15 s headless here; a smaller stand-in would test less | a smaller zone on CI
2026-10-25 | cg_brief 3.1: far drawing scans soldiers new to the zone first and each again every 10 s, 12 a scan (BigZoneStreaming DRAW_AGAIN_S, DRAW_PER_SCAN) | the WIP walked every soldier's meshes every 2 s | once per soldier only (gear and stand-ins that come later stay unlimited)
2026-10-25 | cg_brief 3.1: hooks for D3 left, not built: the def's "op" (bands, MSR and its road indices, laterals, route, fords, start, FOB, town or city, HQ, depth target), OperationGen.band_at/along/across, BigZoneStreaming.at_cap and its live counts (F-286) | 3.2 is D3's | building the front grid now
2026-10-25 | cg_brief 3.2 (D3-1): operation types in data/operations.json with an `offer` flag; the employer's factions.json `operation_types` names what it posts | an operation is phases, OOBs and a front, not one mission type; D4/D5 flip a flag | entries in contracts.json mission_types
2026-10-25 | cg_brief 3.2 (D3-2): US forces post the phased invasion only; Vessmark keeps D7's stand-in operation | the other types' mechanics are D4/D5's | posting every type with stand-in mechanics
2026-10-25 | cg_brief 3.2 (D3-3): an operation covers its front's zone and up to two neighbours the target holds; its zone `op_<seed>` is generated from the contract on asking and cached, controller the target from WorldSites | one seed, the same zone everywhere and after a load | saving the def with the contract
2026-10-25 | cg_brief 3.2 (D3-4): pay = type base ($320,000 phased invasion) x difficulty_pay x op_pay_mult; 20% on signing whatever the terms; the rest by phase share 20/25/25/30% | 6.5 | the terms' advance points
2026-10-25 | cg_brief 3.2 (D3-5): phase bonuses and penalties as shares of the phase's pay (fast +10%, low allied losses +5%, asks answered +2% each to +10%, clean, bridge kept +10%, late -20%, friendly fire -5% each and -1 rep), never below nothing | 6.5's list; a good phase pays about a third more | flat sums
2026-10-25 | cg_brief 3.2 (D3-6): unvisited sites fall off-screen at 2x the expected garrison for the flip time, 34% of it counted as allied losses (F-290) | the allies take ground the players never see | spawning every site's fight
2026-10-25 | cg_brief 3.2 (D3-7): a phase is done with its required task and required allied objectives; it stalls at side_command phase_fail_share x its limit and the operation stops, what's done paid | B2's own stall rule | the company going on alone
2026-10-25 | cg_brief 3.2 (D3-8, D3-9): friendly fire counts players' incidents only; the debrief outcome completed / partial / failed, partial +2 rep at half or more | the AI's mistakes aren't the company's; a partial push still did work | every incident; success or failure only
2026-10-25 | cg_brief 3.2 (D3-10, D3-11): the front is 32 x 32 cells of 256 m, cycled every 10 s, a cell weighing its 3 x 3 and flipping at 2x for 60 s with no defending garrison standing; objectives falling flip their cells, a phase consolidates behind its line, a withdrawal gives back past the last line held | 6.3 | each cell alone; presence only
2026-10-25 | cg_brief 3.2 (D3-12, D3-13): OOB out by the front (friendly at H-hour, enemy 600-2,600 m from a player and unseen, two men a frame, held at the live caps); waves of 6 every 7 min (3 a phase) on enemy cells near the main objective; a 50% team behind the front every 15 min | 6.2.3's caps; 6.3's reinforcements from the enemy's side | everyone at once; fixed spawn points
2026-10-25 | cg_brief 3.2 (D3-15, D3-16): the run saved on the contract (op_run: clock, phases, pay, front, OOB where it stands); peers ask for the whole run and grid, then get flipped cells and the view every 10 s | one save with the campaign; small and in step | a zone save; the whole grid each time
2026-10-25 | cg_brief 3.2 (D3-17): the HUD's operation strip in the top-right corner over the objectives (the objectives panel shrinks for what's above it) | where a player looks for what to do | a banner at the top
2026-10-25 | cg_brief 3.2 (D3-19): budgets 0.2 ms a front cycle for the zone's own load (~0.13 ms measured), 0.6 ms for a 160-group fight, 1 ms the whole cycle, 0.3 ms the strip, 3x allowed in the test | GDScript costs ~0.4 ms for the fight load, every 10 s | 0.2 ms for any load
2026-10-25 | cg_brief 3.2 (D3-20): the operations suite plays the invasion with a small OOB of its own via register_type | the full OOB would take the suite past CI's time | the data's OOB
2026-10-25 | cg_brief 3.2: no hooks in Captain's commander files (side_command, operation_plan, hot_zone_policy, defence_plan) or in squad_ai, tactics, squad; D3 uses B2's public API only (F-293) | the brief: public API first | one-line hooks
2026-10-25 | cg_brief 3.2: the economy sim plays operations phase by phase through the real pay (_play_operation) and skips offers the company can't sign; no profile took one in 2 x 40 campaigns (rated 5; careful/median take 3/4; sloppy seldom trusted by the US), so pay by phase leaves the money curve as it was; the war's stream moved it within the seed spread (docs/economy.md); nothing tuned | the brief: re-run the sim if pay by phase moves the curve | lowering an operation's rating so the sim takes one
2026-10-25 | cg_brief 3.2: the phased invasion's bridge kept is +10% of phase 2 (6.5's +40% is the seize-crossing type's, data/operations.json seize_crossing) | the bridge is the whole job only in a crossing operation | +40% for every type
2026-10-25 | cg_brief 3.2 (D3-21): a client joining an 8 km zone (BigZoneStreaming.streams) gets up to 180 s to make it: the host's auth timeout and both ends' ENet timeouts (32, 120 s, 180 s) while it loads, back to Net.ENET_TIMEOUT 15 s after it's in (LevelSwitch, a few lines in a shared net file) | the client was dropped mid-load and rejoined from scratch (the operations suite's late joiner, up to 10 tries; on CI it never got in) | the test raising timeouts itself, as armourdrive_test does, leaving players' late joins broken
2026-10-25 | cg_brief 3.2: the operations suite's client waits for the host's door file (user://operations_test_door<tag>_<port>.txt) before joining | let in while the host's door was shut it was dropped and loaded the 8 km zone again each try | joining in a loop as the other two-process suites do
2026-10-25 | cg_brief 3.3 (D4-1): the five operation types register through D3's Operations.register_type (hooks only, data in data/operations.json); each a mechanic node (OpInvasion, OpThrust, OpLanding, OpCrossing, OpTown) plus OpSupport under the zone's Operations node on every peer, records on the run (op_run "mech"), a "resume" hook for a loaded save | D3's API; one RPC path everywhere; one save | a script per type outside the zone
2026-10-25 | cg_brief 3.3 (D4-2): offer rules: a type's region (beach landing coast fronts only, armoured thrust inland only, the rest any) and min_rep 30; the US posts the invasion, thrust and beach landing, Vessmark seizing a crossing and holding a town (D7's Vessmark stand-in retired) | 6.1, 6.4.2, 6.4.3 | tiers of standing per type
2026-10-25 | cg_brief 3.3 (D4-3): an operation's rating counts the enemy sites in its rate_bands, its OOB and its counterattack waves (holding a town: waves and its mortar team only) | the ground it fights over; each still rates 5 | the whole 8 km zone's garrisons
2026-10-25 | cg_brief 3.3 (D4-4): attached armour gets an allied driver and gunner (+ the Abrams' loader), the commander's hatch and troop seats left to players; it overwatches the company's task 300 m short on our side by default and takes the company's orders (Support > Operation); a player aboard takes its gun and gives it back; lost = the employer's loss | 6.1 with today's AI (no A9: F-296) | registering the crew with HighCommand (its SquadOrders can't drive a seated crew)
2026-10-25 | cg_brief 3.3 (D4-5): allied fires are data/fire_support.json "allied_units" fired by FireSupport.server_allied_fire (no mission, no bill): the battlegroup's 81 mm from its mortar section's tubes (none once gone), its 105 mm battery and naval gunfire off the map; prep fires on each phase's enemy sites (never a bridge to take intact), the allied commander's fire_support_wanted (smoke for a breach), the company's call 3 rounds a unit every 120 s; never danger close | 6.1, F-288 | the company's own FireSupport units for free
2026-10-25 | cg_brief 3.3 (D4-6): the phased invasion's full OOB per 6.4.1 (6 rifle squads, 4 Bradleys, 4 Abrams, a 2-tube mortar section, an ammo and a fuel truck 8 min behind as MaxxPros, the medevac as 2 company Dustoff calls on the employer, 2 Abrams attached); the Concord OOB waits for D6b (F-297) | the vehicles that exist | leaving trucks and medevac out
2026-10-25 | cg_brief 3.3 (D4-7, F-292): trucks wait at the logistics point (the MSR 400 m short of the last phase line taken) and rearm or refuel (200 l) allied and attached vehicles within 50 m every 60 s; a type's "medevac" count of the company's Dustoff calls is flown on the employer (one line in Economy.server_pay_support) | the vehicles' own rearm/refuel API; nothing resupplies AI infantry yet | trucks that only drive about
2026-10-25 | cg_brief 3.3 (D4-8): phase 4's bonus: the HQ's commander comes out at the HQ as PL STEEL begins; down or captive and not dead, with one of the company within 6 m, pays +15% of the phase | 6.4.1 "alive for a bonus" | an HVT person delivered to extraction
2026-10-25 | cg_brief 3.3 (D4-9): the thrust's blocking positions are its phases' tasks, band 2's crossing passed between; the column (allied armour, mech platoon, the attached Bradleys) drives by road 30 m apart at 35 km/h, halts 280 m short of a position not clear, goes on when it's clear and every player is aboard (or after 90 s); mech squads dismount at a halt; 45 minutes from H-hour or half the column lost fails it | 6.4.3 | SquadDrivers' ConvoyColumn
2026-10-25 | cg_brief 3.3 (D4-10): a bypass is the company's order: off-road 450 m to whichever side TerrainRoute.path_problem allows, the position counted passed, its 200 m left to the enemy behind the front | 6.4.3 | an automatic bypass
2026-10-25 | cg_brief 3.3 (D4-11): F-284 (the ridge with two passes) stays open: 6.4.3 doesn't need it; the thrust's passes are band 2's crossings (the MSR bridge, the fords) | the doc's thrust runs the river band | building the ridge in ZoneTerrain now
2026-10-25 | cg_brief 3.3 (D4-12, D4-13): the strip gets the type's own line and the attached/fires line, the debrief the type's notes; each mechanic's tick budget 0.5 ms (3x allowed) | 6.3's strip; debrief per type | a panel per type
2026-10-25 | cg_brief 3.3 (D4-14): no hooks in Captain's files (side_command, operation_plan, hot_zone_policy, defence_plan, squad_ai, tactics, squad, level_switch): public API only (SideCommand.install/server_register/server_unregister/fire_support_wanted/picture, OperationPlan.taken, SquadOrders, HcOrder) (F-300) | the brief | a one-line hook in operation_plan.gd
2026-10-25 | cg_brief 3.3 (D5-1, D5-2, D5-3): the beach landing starts at 04:30 (contract sky), H-hour at wave 1 ashore or 10 min in; wave 1 (2 company AAVs with the company aboard, 4 allied with squads) out of the stern gate from 20 s, wave 2 (2) 4 min later, lanes 70 m apart, 45 m up the sand, the AI dismounting there; prep fires at H-2 min on up to 4 known defences, smoke on both exits at H-30 s; exits 600 m apart (the company the left); fail on half of wave 1's AAVs lost afloat or the beachhead held by the enemy 60 s | 6.4.2 | spawning the company on the beach
2026-10-25 | cg_brief 3.3 (D5-4): not built: the x4 time afloat (F-294) and troops at the AAV's open hatches (F-295) | host time_scale speeds every client's physics; the AAV spec has no FFV seats | both now
2026-10-25 | cg_brief 3.3 (D5-5, D5-6, D5-7): seizing a crossing: 3 demo blocks under the middle span on a firing device, the firing point 160 m past the bridge, 60 m off the road; seen within 1 km by line of sight (600 m before its engineers are out) it blows in 90 s, a vehicle on the span at once; stopped by the engineers down, the wire cut at a marked point (3 m) or the firing point seized (12 m, no enemy within 40); the far bank a company task, the far checkpoint not required; a dawn start rolled half the time (F-299); blown: keep-intact fails, the armour goes by the ford; fail on both banks or the bridge and every ford held 60 s | 6.4.4 | always dawn; the checkpoint required
2026-10-25 | cg_brief 3.3 (D5-8): holding a town: garrisons gone and cells within 700 m ours at the start, the company inserting on the city's ring street (OperationGen town_start_types), the allies "at" the town; 6 free pieces (sandbags, HESCO, wire) within 250 m of the centre in the 10-minute prep, placed with DefencePlacer's field mode, solid boxes on every peer, saved with the run (F-298) | 6.4.5's budget 6 | paid defences as zone modules
2026-10-25 | cg_brief 3.3 (D5-9): a piece is seen when a live enemy within 450 m has a line of sight (every 5 s, 24 rays) or its picture has a contact on it; the counterattack's axis is the lowest-scored of 3 approaches 900 m out, 50 deg apart, scored by seen pieces and contacts in a 35 deg cone (+2 off its ground) | 6.4.5 "from its picture" | DefencePlan's own counterattack (3x seen CP or contain)
2026-10-25 | cg_brief 3.3 (D5-10, D5-11, D5-12): 3 town waves at 0:30, 10:00, 20:00 (2 groups of 5; the second with DShK technicals and 4 enemy mortar rounds first), won when all are down to a quarter after 10 min or 30 min with the centre ours, lost when the enemy holds the centre 60 s; the beach (2 waves) and crossing (2) share it; the enemy mortar fires from 1,800 m back while its team stands; a type leads its waves itself (a SquadOrders under its mechanic) | 6.4.5; DefencePlan would garrison or contain a free group | registering waves with the hostile commander
2026-10-25 | cg_brief 3.3 (D5-13): the AAV waves come out of the operation zone's own LHD (its stern gate, Lhd.launch_transform), not the walkable LhdLevel home; the company deploys as usual and starts seated in its AAVs; lhd_level.gd unchanged | one level per deployment | a level switch from the home's well deck mid-launch
2026-10-25 | cg_brief 3.3 (D5-14): the crossing's phase 3 limit 18 min (its hold is 10 min, stopped while the enemy is within 200 m) | the hold is the phase | 12 min
2026-10-25 | cg_brief 3.3: the economy sim re-run after D4/D5 (seeds 1 and 101, 40 campaigns each): no profile takes an operation, day-35 means as after D3 (careful $627k/$622k, median $666k/$596k, sloppy $113k/$61k with 6 and 10 of 40 in debt); nothing tuned (docs/economy.md) | the targets hold as they are | tuning the operations' pay to make them reachable
2026-10-25 | cg_brief 3.3 (D4-15): a switch into an 8 km zone gives every end LevelSwitch.LOAD_TIMEOUT from its start until the client has the level + 15 s (BaseHub._hold_timeouts, shared file, a few lines; F-302) | the clients were dropped while the host made the zone | the test raising its own timeouts
2026-10-31 | Captain's item 7 ("bots joining a human-hosted game") is the co-op soak bots joining a game a person hosts (tools/coop_soak.sh --join, built 2026-10-19 from his 2026-10-14 ask) and the squad rule under it (AI fills what players don't, a joiner takes an AI's slot, a leaver's slot goes back to AI). Both were in the code; built: the two-process botsjoin suite that runs them together, and the two gaps it and a read of rebalance_squad found (next two lines) | commit 92a371ef quotes the ask word for word; squad_test checked the slots in one process only, nothing ran the --join bot | a new bot-client mode or a new slot system
2026-10-31 | A squadmate lying down (out cold, dying) keeps his slot when a player joins: Roles.assign's new `avoid` (CompoundLevel.rebalance_squad passes the downed AI's slots) sends a joiner to another slot that fits (a medic to the other team's medic slot, else a rifleman's slot taken on as medic), his own only when nothing else is free | the old take-over freed the casualty, wounds and all, from under the medic treating or the man carrying him (nothing teleports) | the joiner waiting outside the squad until he's up or dead
2026-10-31 | A joiner still takes a slot by its AI leaving the session and the player coming in at the spawn or last crossing in their own kit (linked_zones.md 5, the late-join rule), not in that squadmate's body where he stands (F-331) | keeps the late-join, spawn and body rules as they are | an in-place body hand-off
2026-10-31 | BaseHub forgets a leaving player's profile in a plain session too (only a campaign did), and a newly hosted session starts with none taken | a bot that left a plain session came back as "soak_bot1_2", and in a campaign hosted later in the same run as a brand-new main character, its gear not found | clearing them only when a client's session ends
2026-10-31 | Roles.assign's 'only medic slots left' fallback runs in the last pass only, so with `avoid` a joiner takes an avoided slot of his own role (or an avoided non-medic slot) before a standing medic's slot: every team keeps its medic (roles.json), and a downed man's slot is the lesser harm, the 'last resort' the avoid rule already meant | review of feat/bots-join-hosted: players TL/AR/GR in 0-2, AI 4-6 down, a rifleman joining took Charlie's medic slot 3 and nothing rebalances when the casualties get up; roles_test case added | leave the fallback in both passes, or rebalance again when a casualty gets up

## F-08: a squadmate pushing into something the navmesh doesn't know stays stuck

Found by cghath's side (fix/ci-flakes, 2026-10-20) in casualty_test's soak and CCP checks; the
unsticking is SquadAI's (Claude's file), so it isn't changed here.

Location: [squad_ai.gd](../../scripts/ai/squad_ai.gd), following a path (`_path`, `move_input`);
on cghath's side [nav_builder.gd](../../scripts/world/nav_builder.gd) (what the compound's
navmesh is baked from, and `AGENT_RADIUS`).

A following squadmate whose path runs into something solid stands there with `move_input` full
forward and his velocity exactly zero for 8 s and more, and never side-steps or repaths:
- Into a target dummy (`TargetDummy`, `scenes/levels/compound.tscn`: (-4, 0, 12), (4, 0, 12),
  (0, 0, -8)): a static body on the bodies' layer, not voxels, so not in the navmesh and paths
  run straight through it. CI 39435450203: Foxtrot at (-3.5, 12.3), touching nothing else; CI
  39441304589 and 39442290938 (and claude/lhd-home 39443651706, claude/ai-driving 39424984277):
  Golf pushing into HeavyDummy, and "with a collection point set, a squadmate picks his body up"
  failed with nobody picking Echo up.
- Into the corner of the compound's low concrete wall at (-1.5, 10): the navmesh is baked for a
  0.25 m agent (`NavBuilder.AGENT_RADIUS`) and the capsule is 0.3 m round
  (`SoldierMovement.CAPSULE_RADIUS`), so a path hugging a corner is 5 cm too tight. Seen locally
  (R0274) with the dummies baked into the navmesh as a try (paths then went by that corner;
  the try was taken back out).
Seen on several branches since 2026-10-20 ~12:00 UTC, so CI's timing seems to have made it
likelier; dev's code has it too.

Suggested fix: in SquadAI, a body that wants to move (`move_input` not zero) but hasn't moved
for a second or so side-steps along the obstacle's normal (`get_slide_collision`) and repaths,
as a player would. On cghath's side, separately: bake static props (the dummies) into the
compound's navmesh and keep the agent radius at least the capsule's (each changes paths
everywhere in the compound, so both want the full suite).

## F-224: the co-op soak harness expects the pre-ready-up deploy and a shorter extraction

Found on the v0.7.0 build's first soak (S2605, 2026-10-25, 10 min clean, 3 clients): the harness
(claude/coop-join, written 2026-10-19) is behind the game it now runs on. Not a game fault: the
bots joined (late join, leave and rejoin), a contract played with a revive and a confirmed
extraction, no script errors, no persistent divergence past one 5 s inventory mark.

- Cycle 1 gave up 1.5 s after kitting with "deploy: Waiting for: Player <id>": the briefing now
  waits for every player's ready-up (FOB ready-up, 2026-10-14) and the bots hadn't readied; the
  deployment then went ahead on its own at 45 s. The harness should ready each bot up
  (BaseHub/briefing ready) and wait for all_ready before counting the deploy as failed.
- Cycle 2 ran 550 s of a 600 s soak and ended "never got back to the base (extraction state 1)":
  the extraction was gathered and confirmed, the flight home just outran the window. Either count
  a confirmed extraction as the cycle's end, or make --minutes a per-cycle floor.
- Shutdown noise: "Attempt to call RPC with unknown peer ID" from Soldier._set_carry_mode via
  CompoundLevel._server_player_leaves when a carrying peer leaves last; harmless, worth a guard.

Location: tests/coop_soak.gd (the host's cycle checks), tools/coop_soak.sh. Report:
B:/Contractor-test-logs/2026-10-25/S2605-231428-FAIL-coop-soak-v070-integrate-oct25-37ff24ca/report.md

## F-331 to F-333: bots joining a human-hosted game (Captain's item 7, feat/bots-join-hosted)

The botsjoin suite (tests/botsjoin_test.gd) hosts the way the build's menu does and starts the
soak bot (`tests/coop_soak.tscn --soak-join`) as a second process: AI fill, a bot taking an AI's
slot with that role's kit and buddy, following the human, the slot back to AI when it leaves; in
the campaign, the FOB join and ready-up, gear kept on leaving (and in the save) and brought back
on rejoining with no second kit. R0718 PASS. What it left open:

### F-331 (open, design, cghath): a joiner takes the slot, not the squadmate's body
A player joining mid-fight takes an AI's slot by that AI leaving the session wherever he is and
the player coming in at the spawn (the compound) or the last crossing (a zone), in their own kit
(linked_zones.md 5). Arma-style join-in-progress would put the player in that squadmate's body
where it stands, with its kit. That changes the late-join rule, spawns and (in a campaign) whose
gear is whose, so it's a call for cghath, not a fix. Since this branch a downed squadmate is never
the one taken while another slot fits (Roles.assign `avoid`). Files: compound_level.gd
(rebalance_squad, _remove_squadmate), base_hub.gd (server_squadmate_leaving).

### F-332 (open, test tools): the soak bots run on this PC's settings.cfg
tests/coop_soak.gd never calls `GameSettings.use_file`, unlike every suite, so bots joining a game
on the same PC (`coop_soak.sh --join 127.0.0.1`) play with that player's handedness and controls
(CLAUDE.md: a left-handed settings.cfg once broke the pistol draw) and could write to it. A
per-bot test file (`soak_bot<N>_settings.cfg`) in `_ready` would keep them apart.

### F-333 (open, test coverage): the --join bots in a deployment
botsjoin covers the FOB (ready-up) and the plain session (follow). The bots' briefing ready-up,
following the human into a zone, boarding with them and the extraction (coop_soak.gd `_join_tick`,
`_follow_tick`) only run in a manual `coop_soak.sh --join` soak. A deployment in CI is minutes of
zone generation; a short contract zone in the suite, or a periodic soak run, would cover it.
