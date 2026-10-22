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

NUMBERS_TABLE

The machine was shared throughout (Captain's game and other sessions' test runs), so the absolute
numbers are high and noisy; the baseline and the pass ran back to back (runs RUN_IDS).

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

BUDGETS_TABLE

## What's left

See F-206 in docs/audits/followups.md: a cold building scan's grouping (100-250 ms once its probes
are done), a whole team spawned in one frame (about 8 ms a soldier), BodyDeform meshing on the main
thread, three RPCs a shot in co-op, and rendering costs the headless suites can't see (soldiers are
15-25 draws each with shadows; the terrain's coarsest level is a draw per 128 m chunk to the
horizon; module proxies cast shadows). The physics step cap stays at 8: a lower one turns overload
into slow motion, and the AI's clocks run on real time (Soldier._now), so they'd drift from the
movement.
