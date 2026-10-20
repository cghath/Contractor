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
