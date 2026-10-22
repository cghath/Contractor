# Performance

Captain, 2026-10-22: "we definitely need more performance fixes". The game ran worst in towns and
cities, in big firefights, in woods and open terrain, and in vehicles and helis, with low frame
rates and stutters both, on his PC (RTX 4060, 14.6 GB RAM). This page is how it's measured, what
the perf pass (branch claude/perf-pass, 2026-10-22) found and changed, the numbers before and
after, and what's left. All budgets are Proposed.

## How it's measured

`tests/perfcases_test.tscn` (suite **perfcases**, in CI) hosts real zones with their AI and plays
five scenes, building each zone's visuals as a player's machine does (terrain levels, scatter cells,
water, roads, grass) with a camera riding on the player:

| Case | Zone | Scene |
|---|---|---|
| town | Old Quarter (city_hot) | the player walks into the city's biggest town with the squad; its garrisons, patrols and QRF teams spawn and move |
| fight | Black Ridge hills (ridge_hot) | the squad and a 10-man allied section 90-140 m from the biggest garrison, the zone ENGAGED: the QRF launches, gun teams man their guns |
| woods | Kestrel Valley (river_valley: woods, a river, reeds) | the squad walks through the zone's densest wood and meets an 8-man hostile patrol |
| drive | Kestrel Valley | the player rides an AI-driven M-ATV 1.7 km along the roads |
| heli | Kestrel Valley | the player rides a UH-60 contour-flying across the zone |

Each case is measured for 30-45 s (CI: 0.6 of that). For every frame that ran a physics tick it
takes the **60 Hz frame cost**: that frame's average tick (its `_physics_process` scripts and the
engine's own step) plus the frame's `_process`. That's what a frame costs at 60 ticks a second
minus the GPU, however far behind the engine has fallen. A machine that can't keep up runs up to
8 ticks a frame, the "451 ms frames" of P1104, and the wall-clock frame balloons and swings run to
run on a shared machine; the frame cost holds steady. **Hitches** are single ticks or `_process`
passes over 33 ms and over 3x the case's median one, each printed with what it went on (FrameCost
systems, nodes and soldiers added). Rendering itself isn't measurable headless (the renderer is a
dummy); the **draw proxy** counts what the camera would draw (geometry instances in view range and
in the frustum, MultiMesh instances, shadow casters within the sun's reach) and which kind of thing
each draw is.

Run it: `tools/run_tests.sh perfcases` with `CONTRACTOR_PORT` and `CONTRACTOR_TEST_TAG` set.
`PERF_CASES=town,fight` picks cases, `PERF_NO_BUDGETS=1` only prints, and `PERF_PROFILE=1` times
every script's `_physics_process` and `_process` by script (and SquadAI's parts) and names the
slowest script in each hitch. `tests/perf_spawn.tscn` times one soldier's spawn, part by part.
`tests/townperf_test.tscn` (the town fight's physics, 2026-10-14) and `tests/perf_timing.tscn` (the
older timing script) still stand.

Building scans run under their frame budget in the cases (`Buildings.budget_always`), as on a
player's machine; the other suites keep headless's exact answers.

## Before and after

60 Hz frame cost in ms (average / 95th percentile / 99th / worst) and hitches a minute, before (the
branch point, origin/claude/ai-driving e13d2f7, with the same harness) and after (15ec60a). The
machine was quiet for these (the other sessions between runs):

| Case | Average | 95th | 99th | Worst | Hitches a minute |
|---|---|---|---|---|---|
| town | 50.7 -> **21.4** | 114.0 -> **32.0** | 228.0 -> **47.1** | 306.6 -> **67.3** | 44 -> 60 (155-290 ms each -> 39-65 ms) |
| fight | 24.1 -> **18.3** | 32.5 -> **25.7** | 89.6 -> **39.6** | 167.8 -> **74.2** | 45 -> **24** |
| woods | 12.9 -> **8.6** | 17.5 -> **12.5** | 26.5 -> **17.6** | 76.9 -> **29.7** | 30 -> **0** |
| drive | 10.3 -> **7.8** | 13.7 -> **10.8** | 19.2 -> **13.8** | 64.3 -> **33.1** | 11 -> **0** |
| heli | 17.9 -> **10.4** | 58.9 -> **18.4** | 67.2 -> **24.5** | 101.4 -> **35.8** | 310 -> **0** |

Runs: before R2427, after R2430 (town: R2425, the same code; R2430's town garrison went out hunting
the squad and most of the zone's AI ended asleep, a different scene). Town's hitch count went up
because the hitch line is three times the median and the median fell; each one is a quarter of what
it was. The worst town frames left are a building scan's grouping and entrances (below).

On a busy machine (Captain's game and other sessions' test runs alongside; before R2420, after
R2422 at 9e235a4, the pass before its last fixes), the same picture:

| Case | Average | 95th | Worst | Hitches a minute |
|---|---|---|---|---|
| town | 55.2 -> 37.5 | 167.9 -> 67.6 | 213.8 -> 94.1 | 40 -> 24 |
| fight | 28.4 -> 18.7 | 41.4 -> 27.1 | 209.9 -> 67.6 | 54 -> 21 |
| woods | 14.5 -> 10.2 | 20.3 -> 15.3 | 70.8 -> 32.1 | 34 -> 0 |
| drive | 12.0 -> 9.3 | 16.9 -> 13.7 | 77.6 -> 41.0 | 11 -> 3 |
| heli | 19.9 -> 12.9 | 63.9 -> 22.0 | 113.5 -> 58.1 | 309 -> 2 |

Busiest of all, the first pass alone (R2405 -> R2408): town 91.5 / 267.0 -> 60.2 / 101.6, fight
95.8 / 236.6 -> 35.8 / 56.4, heli 55.3 / 100.6 -> 15.2 / 29.2. A soldier's spawn: about 45 ms ->
5-10 ms (tests/perf_spawn.tscn). townperf's tick: 17.2 -> 15.6 ms average, 95th 31.2 -> 26.0
(R2418 -> R2419).

The draw proxy (what the camera would draw; not timed headless): the Old Quarter about 515 draws, 340
of them soldiers; Kestrel Valley from the M-ATV about 935 (scatter 412, terrain 201, soldiers 199),
from the UH-60 about 1370 (scatter 1181) with about 965 shadow casters. The Detail setting's High
stops the far canopy at 3.2 km; Medium and Low draw less scatter.

## What it found, and what changed

Baseline profile (Old Quarter): SquadAI about 12 ms a tick and soldiers' movement about 12 ms a
tick for ~50 AI, `_process` 56-90 ms a frame, and every frame running 8 ticks. Hitches: building
scans 300-600 ms (a town's first scan, and again whenever its 20 s cache ran out), team spawns
300-500 ms (75 ms a soldier; 0.4-0.6 s for the first of each uniform), grass re-lays 100-300 ms,
scatter cells 100-400 ms, craters 50-150 ms.

**AI think rate and level of detail** (`AiLod`, a hook in SquadAI). An AI further than 120 m from
every player, not in contact, with no target and no casualty or body to see to, scans for enemies,
thinks and re-plans its path 2x less often past 120 m, 3x past 250 m and 4x past 400 m. Awareness
and hearing still build per second of sight (`_scan_dt`), so a far patrol notices the squad within
a second or so of when it would have. DynamicSim still sleeps them past 650 m and the Virtualizer
takes groups out past 700 m.

**Soldiers standing still** (SoldierMovement.REST_EVERY) step their movement every 4 ticks with the
time summed: a town's garrison mostly stands at its posts. Any order to move, aim, sprint, change
stance, lean or climb ends the rest that tick.

**Spawns** (45 -> about 8 ms a soldier). A head's size and pivot no longer build the whole face's
spec (25-40 ms a soldier, every spawn: every face is new); model specs are kept (VoxelArt._spec);
armour shares its undamaged meshes (each helmet and plate was meshed three times per spawn); the
zone's uniforms (the company's, and the holding and attacking factions' kits) are rasterised and
meshed on a worker at zone start (PerfWarm), so the first soldier of each look and his first reload
build nothing on the main thread.

**Building scans**: a scan's cell probes stop at the frame's 4 ms budget and go on at the next ask
(the cells probed so far are kept); meanwhile the asker gets what it knew, as an over-budget ask
already did. The first scan in a frame used to run to the end whatever it cost.

**Grass, scatter, terrain**: the grass carpet keeps each grid point's tuft and narrows the pads and
roads to the ones near it; ground cover narrows them per 128 m cell; scatter cells and the
terrain's fine chunks are built one a frame; the terrain re-plans which chunks to refine only once
the camera has moved 16 m (it measured and sorted all 1024 chunks of a hot zone every frame).

**Voxel edits**: impact marks keep a multimesh slot each (one write per new mark, where every mark
laid all of them again); a blast copies its box once, walks only the sphere and pastes the cleared
voxels back (a mortar round was ~130k voxel reads and writes); craters redraw their ground a block
a frame.

**Effects**: tracers draw one shared box in a material per kind and fade by their own transparency
(each shot made a mesh and a material, and resized the mesh every frame); impacts and bursts share
meshes and materials; the effects' shaders are drawn once at zone start so their pipelines compile
before the first shot.

**Smaller**: module streaming counts distinct focus points; a far body's hitboxes follow it on the frames it's drawn (a downed
body's every frame); footsteps and a moving vehicle's body check no longer allocate per frame.

**Detail setting** (Settings, Video, "World detail at distance"): Ultra draws everything as before;
High (the default) stops the far tree canopy at 3.2 km with a 300 m fade; Medium and Low draw the
scatter 0.8x and 0.65x as far and the canopy to 2.4 and 1.8 km. Up close they all look the same.

## Budgets (Proposed)

`tests/perfcases_test.gd` BUDGETS: each case's average 60 Hz frame cost, its 95th percentile, and
hitches a minute. About twice the pass's numbers on a busy machine (room for CI's runners) and under
the numbers before the pass, so going back to them fails.

| Case | Average | 95th | Hitches a minute |
|---|---|---|---|
| town | 75 | 140 | 90 |
| fight | 40 | 60 | 45 |
| woods | 25 | 35 | 20 |
| drive | 20 | 30 | 15 |
| heli | 28 | 45 | 20 |

townperf keeps its own (tick 20 ms average, 40 ms 95th percentile).

## What's left

See F-206 in docs/audits/followups.md: a cold building scan's grouping (100-250 ms once its probes
are done), a whole team spawned in one frame (about 8 ms a soldier), BodyDeform meshing on the main
thread, three RPCs a shot in co-op, and rendering costs the headless suites can't see (soldiers are
15-25 draws each with shadows; the terrain's coarsest level is a draw per 128 m chunk to the
horizon; module proxies cast shadows). The physics step cap stays at 8: a lower one turns overload
into slow motion, and the AI's clocks run on real time (Soldier._now), so they'd drift from the
movement.
