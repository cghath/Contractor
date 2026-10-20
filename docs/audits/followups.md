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
| F-07 | P2 | The far-AI sleep (DynamicSim) can freeze a falling soldier in his last metre above the ground |

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
