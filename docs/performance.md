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
High (the default) stops the far tree canopy at 3.2 km with a 300 m fade, and soldiers further than
150 m from the view cast no sun shadow (each is 15-25 shadow draws); Medium and Low draw the scatter
0.8x and 0.65x as far, the canopy to 2.4 and 1.8 km and soldiers' shadows to 100 and 60 m. Up close
they all look the same.

## Budgets (Proposed)

`tests/perfcases_test.gd` BUDGETS: each case's average 60 Hz frame cost, its 95th percentile, and
hitches a minute. About twice the pass's numbers on a busy machine (room for CI's runners) and under
the numbers before the pass, so going back to them fails.

| Case | Average | 95th | Hitches a minute |
|---|---|---|---|
| town | 75 | 140 | 90 |
| fight | 60 | 110 | 45 |
| woods | 25 | 35 | 20 |
| drive | 20 | 30 | 15 |
| heli | 28 | 45 | 20 |

(These were the first pass's; the latest, from the world content pass: town 15 / 25 / 30, city
200 / 300 / 60, fight 100 / 170 / 90, woods 18 / 26 / 15, drive 18 / 26 / 15, heli 18 / 30 / 15.)
These are CI's: its runners have nothing else on them. Run locally the budgets get 1.6x room
(LOCAL_SLACK): on this shared machine a busy run measured 2.5-3x a quiet one (R2431: town 62 ms,
fight 49 against 21 and 17 in R2425), so a local failure is first a question of what else was
running. townperf keeps its own (tick 20 ms average, 40 ms 95th percentile). The fight's were raised from
40/60 after CI's first run measured 42.7/71.7 there (run 39737889264); the other four cases passed
on CI at the first budgets.

## With cghath's world expansion (2026-10-22)

Merging world/perf (the Old Quarter a real city, roads, fields, the prop library, near/far scatter
tiers) about doubled the cases' cost: back to back, claude/ai-driving df3133f without it against the
merge (R2484 -> R2485), town 66.7 / 102 -> 132.6 / 178 ms (75 AI against 62, none of them far enough
to sleep, the navigation server 3.5 -> 10.9 ms a frame, SquadAI's act about 9x), heli 14.9 / 28.5 ->
28.7 / 48.7 (_process 6.8 -> 19.7 ms: the grass 1.3 -> 3.8, the terrain and scatter cells). The
budgets were re-based on the merge (about twice its local numbers; CI's runners measured about twice
a quiet local run): town 270 / 360 and 90 hitches a minute, fight 140 / 260 / 90, woods 45 / 60 / 30,
drive 52 / 86 / 45, heli 58 / 100 / 45. The city's cost is the next perf task.

## Towns, cities and the heli (claude/perf-towns, 2026-10-22)

The follow-up for the world expansion's cost. perfcases gained a **city** case (the Old Quarter's
city, walked up its middle street from 40 m outside: about 107 AI, its blocks' garrisons and
patrols); **town** is now the zone's biggest town or village outside the city (after the
expansion the old pick landed on a city block).

60 Hz frame cost, average / 95th percentile ms, and hitches a minute, quiet machine, each run all
six cases (before R2513 at 8edc184b with the new city case, after R2517 at e0f7b46e):

| Case | Before | After | Hitches a minute |
|---|---|---|---|
| town (village) | 8.8 / 13.3 | 8.5 / 14.1 | 8 -> 12 (team spawns, 40-60 ms) |
| city | 136.3 / 196.3 | **107.4** / 213.4 | 1.5 -> 15 (the median fell) |
| fight | 61.9 / 94.6 | **35.6 / 50.0** | 19.5 -> 31.5 |
| woods | 24.8 / 34.4 | **14.0 / 21.1** | 16 -> 10 |
| drive | 16.0 / 27.7 | **9.2 / 14.1** | 13.3 -> 4 |
| heli | 15.1 / 30.5 | **12.2 / 21.6** | 27.4 -> **3.4** |

What the city's profile found (R2514-R2516): it's the AI, not the buildings or props. SquadAI
about 50 ms a tick for ~100 AI: `_find_casualty` 9 ms a think (every AI asked responder_for, a pass
over every combatant, for every casualty), patrols' formation slots 1.8 ms a call (a few rays a
man, worked out again for each man), act 0.3 ms a patrol member a tick; soldiers' movement 10-20 ms
a tick. The heli's hitches were the grass carpet (a lay from a helicopter is mostly new ground).

Fixed: casualty responders kept 0.25 s while still free; formation slots kept 4 ticks while the
lead holds his place and heading; a cold building scan's grouping and stair paths stop at the
frame budget and go on (F-206); grass lays write one buffer, clip rows to the circle, budget new
tufts by time and go on from where they stopped.

Batch 2 (3d11c456 and after): medic_for kept the same way for `_find_casualty`; an AI squad's slots
kept 8 ticks and through turns under about 6 degrees; a path kept while its destination drifts
under 15% of the way left (up to 3 m) until REPATH_S (patrol men re-planned every time the lead's
slots moved half a metre); the follow-in scan skipped when the squad has nobody to send in (F-211).
R2519 ran on a busy machine (woods, drive and heli, untouched by batch 2, measured 1.6x R2517):
city 122 / 288, fight 53 / 82. Quiet again at c570c558 (R2523, with the budgets, PASS): town 9.2 /
14.0, city **103.3** / 225.7, fight **35.4 / 49.7**, woods **14.1 / 21.1**, drive **8.5 / 12.8**,
heli **10.6 / 18.8**.

Budgets tightened (Proposed; about twice a quiet local run, as before; CI's runners measured about
twice a quiet local run): town 30 / 50 / 40 hitches a minute (a village now), city 260 / 520 / 90,
fight 100 / 170 / 70, woods 35 / 50 / 30, drive 40 / 60 / 30, heli 40 / 70 / 45. Against the first
pass's (town 75 / 140, heli 28 / 45) the heli is close; the city carries about 100 AI where the
first pass's town had 50-60, and its AI is what's left there (below).

What's left in the city: SquadAI still 30-45 ms a tick for ~100 AI (act, steering, think), soldiers'
movement 10-20 ms a tick (most of the city's AI are patrols, walking), the navigation server 10 ms a
frame. No building, prop or scatter cost shows in the city's profile. The rendering side, which
headless can't time: 2100 draws in the city, 1630 of them soldiers (F-226). Team spawns in one
frame (F-206) and a scatter cell's or terrain chunk's single build (F-225) are the hitches left.

## Render pass (2026-10-22): what was found, and the windowed check still to run

Captain, after v0.5.4: the frame rate is "unbelievably bad", stutters and low fps everywhere,
menus included (v0.5.3 already bad). The headless cases can't see the GPU, so
`tests/render_bench.tscn` runs the game in a window (today's default video settings from a
settings file of its own, vsync off, no fps cap) and prints, per case: fps, frame ms, GPU and
render-thread ms (RenderingServer.viewport_get_measured_render_time_gpu/cpu), draw calls, objects,
primitives, video and buffer memory, the modules streamed in, and every SubViewport still rendering.
BENCH_SPLIT=1 hides each of the level's children in turn and prints what each costs.
`tests/mesh_census.tscn` (headless) counts geometry nodes and meshes by owner.

What the bench found on Captain's PC (RTX 4060 Laptop, 2026-10-22 evening; logs in
B:/Contractor-test-logs/2026-10-22/bench):

| Build | menu | town (Old Quarter) |
|---|---|---|
| v0.5.2 ac4f718b | | 5.3 fps, GPU 31.7 ms, 4284 draws, 3.66M primitives; 2 modules streamed |
| c1207b17 (before the world/perf merge) | | 4.8 fps, GPU 31.1 ms, 4206 draws, 3.65M primitives |
| world/perf 4dcf71fa alone | | GPU buffers run out: 121,529 errors, the bench hangs |
| v0.5.3 9729d106 | | GPU buffers run out: 174,767 errors |
| v0.5.4 78dc9a17 | 882 fps, GPU 0.75 ms, 181 draws | GPU buffers run out: 379,107 errors in under ten minutes |
| v0.5.4, the player's voxels not drawn (experiment) | | GPU 41.7 ms, 1182 draws, 6.37M primitives; no errors |

- **The jump is v0.5.3, the world expansion's cities.** The Old Quarter is now 38 modules, its
  city 20 blocks of 50 m, and from its edge all twenty stream in as voxels. Each is a voxel terrain
  of a thousand-odd 3.2 m mesh blocks, every block several GPU buffers; the renderer's buffer pool
  ("RID_Alloc<RenderingDevice::Buffer>: Element limit reached") runs out, and from then on every mesh
  anything makes (feet, faces, the HUD, flags) fails with an error and a backtrace: about 380,000
  of them in the first minutes. That is the stutter everywhere, menus included (the game runs on
  under them). Even nine blocks within 60 m overflowed (BENCH 60 m run).
- **Soldiers are heavy on the GPU.** Their 0.5 cm parts in per-voxel camo are about 80k triangles
  each: in the town case the AI is 6.0M of the 6.3M primitives (20.6 ms of GPU) and the sun's
  shadow pass another 4.7M (15.2 ms).
- No SubViewport keeps rendering in any case; the menu alone is fine.

The fixes (branch claude/render-perf), all under Video, "World detail at distance" (GameSettings.DETAIL_LEVELS):
- **At most "voxel_modules" sites as voxels at once** (low 3, medium 4, high 5, ultra 6; every
  level caps it, so no setting can run the pool out): the nearest to this peer's players first, a
  site only AI are fighting in ranking 100 m further; the rest stand as their proxies, as
  streamed-out sites always have (box collision, coarse breaches). Not on a headless server.
- **Soldiers' far stand-ins** ("soldier_lod_m": low 25, medium 35, high 50 m; ultra none): each
  0.5 cm part gets a 1 cm copy drawn past that distance (about a quarter of the triangles);
  a part carved or cut loses it (BodyDeform), whole again gets it back.
- **Soldiers' sun shadows** end nearer ("soldier_shadow_m": low 30, medium 50, high 80; ultra always).

### The windowed check (when Captain frees the PC; about 10 minutes)

From the branch's worktree (import first, headless), then windowed, one at a time:

    GODOT=".../godot.windows.editor.x86_64.exe"; export CONTRACTOR_PORT=24731 CONTRACTOR_TEST_TAG=bench
    BENCH_WINDOWED=1 "$GODOT" --path . res://tests/render_bench.tscn                  # menu, town, woods, fight at High
    BENCH_WINDOWED=1 BENCH_DETAIL=ultra "$GODOT" --path . res://tests/render_bench.tscn -- --cases=town  # the cap at Ultra (6)
    BENCH_WINDOWED=1 BENCH_SPLIT=1 "$GODOT" --path . res://tests/render_bench.tscn -- --cases=town  # what's left, by owner

Read: `grep -c "Element limit" <log>` must be 0 in every case and level. The "census" lines show
how many sites streamed in (at most the cap). Expected at High against v0.5.4 (78dc9a17), Proposed:
town no errors, GPU under 20 ms (from 41.7 with no voxels at all: soldiers' far stand-ins and shadows
should take most of the 20.6 + 15.2 ms), primitives under 3M, draws under 3000; menu unchanged
(about 0.75 ms GPU); woods and fight no worse than v0.5.4 (woods 5.9 ms GPU). If Ultra (6 sites)
still overflows, lower its cap; if High's town is still over 20 ms GPU, the split shows what's left.
These numbers were taken at the game's own window size (the project's 1600x900); the bench opens at
that size unless `BENCH_SIZE=WxH` says otherwise, and since 2026-10-31 every measure line names its
size. GPU time in foliage and full-screen passes goes with the pixel count, so compare at one size.

## cghath's world content (perf/world-content, 2026-10-23)

A pass on the world stack's own cost (roads, terrain features, cities, village houses, props,
dense woods), measured case by case where it goes. Numbers are 60 Hz frame cost, average / 95th
percentile ms and hitches a minute.

**CI** (its runners are the guard; claude/ai-driving 78dc9a17, run 39888713096, against this branch
at 7a92356a, run 39911142961; CI's runners vary a little run to run):

| Case | Before | After | Hitches a minute |
|---|---|---|---|
| town (village) | 7.46 / 15.27 | **6.02 / 9.47** | 6.7 -> 0 |
| city | 111.9 / 127.3 | **82.8 / 94.6** | 0 -> 0 |
| fight | 40.4 / 65.2 | 15.6 / 28.1 | 72.5 -> 52.5 (the AI's: see below) |
| woods | 8.28 / 12.33 | **5.82 / 8.58** | 3.3 -> 0 |
| drive | 8.38 / 11.59 | **6.68 / 10.04** | 2.2 -> 0 |
| heli | 10.19 / 18.34 | **5.85 / 8.20** | 2.9 -> 0 |

A later run at b74ddc99 (run 39914788172) drew a slower runner, everything ~25% up: town 7.2 / 11.4,
city 95.6 / 107.8, fight 20.2 / 37.9, woods 7.3 / 10.5, drive 8.4 / 12.5, heli 8.9 / 13.4, no hitches
outside town (13 a minute, team spawns) and fight. The city's navigation server went from 10.9 to
1.4 ms a frame there. townperf's tick on CI: 13.1 ms
on claude/ai-driving, 14.8, 11.9 and 15.9 ms on this branch's three runs (budget 20; world/perf's
miss was 20.4).

**Locally** (cghath's PC, back to back with nothing else running: before R0582 at 78dc9a17, after
R0583 at 7a92356a; earlier runs this session had a game and another agent's suites alongside and
measured 2-3x):

| Case | Before | After | Worst frame | Hitches a minute |
|---|---|---|---|---|
| town | 9.12 / 15.37 | 9.44 / 13.87 | 216 -> 215 | 18 -> 18 (team spawns, F-206) |
| city | 143.5 / 203.0 | **137.4 / 153.2** | 245 -> 177 | 6 -> 0 |
| fight | 30.0 / 42.8 | 34.7 / 46.8 | 185 -> 190 | 57 -> 54 |
| woods | 9.62 / 14.40 | 9.74 / 13.98 | 29 -> 26 | 0 -> 0 |
| drive | 9.96 / 13.58 | 10.68 / 14.79 | 60 -> 36 | 1.3 -> 0 |
| heli | 14.35 / 23.93 | **10.69 / 16.02** | 44 -> 32 | 1.7 -> 0 |

Busy, back to back (R0580 -> R0581): town 16.0 -> 9.95, city 349 -> 139, woods 20.6 -> 9.3, drive
25.3 -> 9.5, heli 61.3 -> 9.3 (the load eased during the second run, so read these as direction only).

### Where the world content's cost was, and what changed

- **Building the world round the camera, on the main thread** (the hitches from a vehicle or the
  UH-60). A scratch bench on kestrel_valley timed a fine terrain chunk at 22-32 ms (its ground
  colours: pads, roads, banks, fields) and a scatter cell's near tier at 27-35 ms, nearly all of it
  ground cover (about 1000 tufts and pebbles a cell, each tested against pads, roads, water and
  fields and set on the ground). Both now run on a worker thread, one at a time; the main thread
  only makes the mesh or MultiMeshes (F-225, done). Terrain skirts reuse their edge vertices'
  normals and colours; pads are shrunk once, not per vertex.
- **The navigation round soldiers.** In the city a map update (about 500 chunks of floors over
  floors) was 10-16 ms on the main thread about twice a second: the map now builds its iterations
  on a worker (ZoneNav.MAP_ASYNC; the regions' stay synchronous, F-231). Working out which chunks the
  soldiers want was 5-40 ms a pass for ~100 AI (every 0.3 s): plain floats instead of a Rect2 a
  chunk, and the chunks to drop looked for every fourth pass. From the UH-60 every chunk flown over
  was baked and dropped (20-25 bakes a second): a soldier in a helicopter flying faster than 8 m/s
  or higher than 15 m wants none (5 a second now, from the AI on the ground).
- **The helicopter's contour flight**: 14 look-ahead points a tick, each a dozen ground heights and
  three rays down through what stands there (props, pylons, buildings), ~2 ms a tick a helicopter
  on a busy machine. The points 2 s and further ahead are worked out every third tick in turn.
- **The grass carpet** from a helicopter at its 12.5 m contour height: a lay most frames, 12-30 ms
  on a busy machine. Off with the eye more than 10 m over the ground.
- **Animals**: every hit box moved and every herd slot written every tick and frame (about 1 ms a
  tick in the city on a busy machine): now only those that walked.
- **No cost found** in the props', roads' (trimesh tiles) and trees' collision: the engine's step
  is 0.4-0.6 ms a tick on CI in the town, woods, drive and heli cases. The AI's building scans near
  the new buildings are 0.1-0.3 ms a frame outside the city (2.7 in it, under their 4 ms frame cap),
  and sight lines through the woods 0.01-0.15 ms.

### What's left (the world content's part)

- **The city is still its AI** (about 100 of them: SquadAI 30-45 ms a tick, soldiers' movement):
  Claude's. Of the movement, move_and_slide against the city's voxels was about 13% of the AI tick,
  a soldier there costing about 3x one in the woods: the blocks collide as per-face trimeshes
  (F-230).
- **Draws** (not timed headless): the terrain is ~300 draws a view, the scatter's far tier 350-610
  from a vehicle or the UH-60 (F-232); soldiers are most of a city's (F-226).
- **fight** isn't world content: its hitches are the AI's ticks (40-110 ms) and team spawns.

## Operation zones of 8 km (cg_brief queue item 3.1, D2, 2026-10-25)

`tests/invasion_test.tscn` (suite **invasion**, in CI) extends perfcases' meter for an 8,192 m
operation zone (ZoneDef.generate_operation): the 6.2.3 load (two armour columns, 60 live AI
fighting, 200 virtual, one player), a drive along the MSR, a UH-60 contour flight across the zone,
and the same load in a 4 km hot zone on the same terrain preset. Besides the frame cost and hitches
it measures the ground's streaming (its worst frame, chunks missing near the player, how long the
1 km round him takes to fill again), the physics step, the zone's hosting time and the static
memory. CI's first run (40161930345), average / 95th of the 60 Hz frame cost:

| Case | avg | p95 | Streaming, worst frame | Note |
|---|---|---|---|---|
| invasion (8 km) | 70.5 | 94.8 | 1.1 ms | 1.40x the hot zone: the AI's own ticks (F-285) |
| hot zone, same load | 50.3 | 59.0 | - | everything built up front |
| drive (M-ATV, MSR) | 3.0 | 5.2 | 1.7 ms | nothing missing within 300 m |
| heli (UH-60 contour) | 3.6 | 6.4 | 1.6 ms | the 1 km round it whole again within 0.6 s |

The zone hosts in about 17 s locally (generating its ground, water, roads, 164,000 scatter items and
its modules; 4 s for a hot zone) and takes about 330 MB of static memory with its visuals; driving
and flying across it adds about 40 MB (the terrain's rings and the scatter's cells free behind the
camera). What made it run (docs/combined_arms.md D2-1 to D2-13): collision on demand round every
player, vehicle and soldier, built a little every frame; the terrain drawn as far tiles and rings
instead of every chunk's levels up front; the scatter's cover streamed and its drawn cells freed;
far drawing; live caps.

## Woods, 2026-10-31 (perf/woods-copses)

Captain's "Next" item 1 (2026-10-14): "frame goes 4 -> 10 ms in woods, up to 1.5k draws, 1.4M
prims. Then denser copses." Those were windowed numbers from before the woods perf pass of
2026-10-22 (bbef7e05, queue item 1.8: each cell in a near tier of full shapes to 200 m and a far
tier of low-poly stand-ins, far canopy blobs in 2x2-cell blocks as the far tier's visibility
parents, no sun shadows from thickets, scrub or ground cover). That pass also gave the dense copses
to every wooded normal preset, so `art/denser-copses` (ea4d575e, in dev's history) has nothing
left to bring in.

**How it was measured.** Two ways, and they disagree on the draws.

*Windowed, the real renderer (S0771): partial numbers from a run that was stopped early, not a
finished measurement.* An agent's windowed run of `tests/render_bench.tscn` on this PC (RTX 4080
SUPER, Vulkan Forward+, the default High detail: far trees 3200 m, soldiers' shadows to 80 m)
locked cghath's mouse inside its window while they were using the machine, and the coordinator
killed it (exit 127) during the forest case. Before that it printed one 10 s measure line each
for open, woods and woods_in: one sample each, never repeated, at a window size the log doesn't
give (the bench didn't print it then). Read them as a pointer, not as numbers to budget on. Agents
no longer launch any windowed Godot; the bench is for cghath to run by hand (F-366). It runs only
with `BENCH_WINDOWED=1`, lets go of the mouse every frame, opens at the game's own 1600x900 unless
`BENCH_SIZE=WxH` says otherwise and names its size on every measure line. Each case hosts Kestrel
Valley afresh and stands still 10 s; the frame is wall-clock with the whole game running (the
squad, the zone's patrols and the sites streamed in).

| S0771 (partial, stopped early), Kestrel Valley | frame avg (p95) | GPU | render CPU | draws (max) | primitives | sites streamed in |
|---|---|---|---|---|---|---|
| open ground, 2 cells (64 m) from a tree, looking across the zone | 8.85 ms (16.25) | 0.69 ms | 0.72 ms | 646 (678) | 732k | none |
| woods: the densest wood's west edge, looking in | 8.84 ms (15.18) | 0.68 ms | 0.56 ms | 377 (414) | 766k | compound_6 204 m, lm_office 231 m |
| woods_in: that wood's middle, looking the same way | 10.13 ms (17.45) | 0.68 ms | 0.91 ms | **1036** (1077) | 836k | compound_6 166 m, lm_office 255 m |

In these partial numbers, inside the wood the renderer makes about 60% more draws than on open ground (+390) and 2.7x what
it makes 40 m back at the wood's edge looking the same way (+660), for only 70-100k more
primitives: many small draws. The frame is 1.3 ms longer than open ground's, the render thread
0.2 ms. The GPU is 0.7 ms in all three: the frame is the CPU's. Where the extra draws come from
isn't settled. The draw proxy (below) counts only 37 more vegetation draws in the woods than in
the open and each shadow caster once, so the likely sources are what it can't see: the near tier's
shadow casters drawn again in every sun cascade they overlap (inside the wood they are all round
the camera, in the near cascades), or the site behind the wood (compound_6, 40 m nearer from the
middle; a voxel site's blocks are drawn once per cascade too, voxel_world.gd MESH_BLOCK). The bench's
BENCH_SPLIT=1 hides each of the level's parts in turn and would say which (F-366).

*Headless, the draw proxy (perfcases).* What the renderer would be given: geometry in view and in
range, MultiMesh instances, triangles, and the shadow casters within the sun's reach (each
once). Until this pass it never counted the scatter: the headless renderer gives a MultiMesh no
bounds, so every scatter cell sat at the zone's origin, out of its own range. It now places
scatter nodes by their "centre" meta and follows visibility parents. The new **open** case is the
woods case's walk on Kestrel Valley's most open ground. Its first version (R0768) kept the woods'
patrol 60 m ahead: in the open it saw the squad and fought it (CASUALTY and INVESTIGATE at the end,
a 57 ms AI tick and 4 hitches in 20 s), so its frame cost (10.38 ms against the woods' 8.68) said
nothing about the trees. The patrol now stands 500 m to the side, out of the AI's sight
(SquadAI.SIGHT_RANGE 300 m), and open is measured 30 s like the woods (R0776: the patrol on
PATROL at the end as in the woods, 2 hitches, both a soldier model built, 71 ms).

Kestrel Valley (river_valley), at the draw proxy's peak (this PC; perfcases' densest wood is
another than the bench's: it keeps 250 m from the sites):

| | woods (densest wood, 62 trees in 64 m), R0768 | open ground, R0768 (with the fight) |
|---|---|---|
| everything drawn | 293 draws, 758k triangles | 255 draws, 695k triangles |
| of which soldiers | 159 draws, 547k triangles | 159 draws, 547k triangles |
| of which vegetation (scatter, both tiers) | **102 draws, 161k triangles** | 65 draws, 99k triangles |
| shadow casters | 270 (707k triangles) | 233 (665k triangles) |
| vegetation in the shadow pass | 40k triangles | 17k triangles |

With the open case's patrol out of sight and nobody fighting (R0776, the same PC, 30 s each):

| R0776 | woods | open ground |
|---|---|---|
| 60 Hz frame cost, avg / p95 / p99 (ms) | 8.22 / 11.70 / 15.04 | 8.12 / 11.32 / 14.89 |
| tick scripts / _process scripts (ms) | 4.25 / 3.55 | 4.11 / 3.60 |
| hitches | 0 | 2 (4.0 a minute) |
| everything drawn | 293 draws, 758k triangles | 103 draws, 170k triangles |
| of which soldiers | 159 draws, 547k triangles (the patrol in view, 60 m on) | 7 draws, 21k triangles |
| of which vegetation | 102 draws, 161k triangles | 65 draws, 99k triangles |

Headless, the trees cost the CPU about 0.1 ms a frame (8.22 against 8.12 ms); the vegetation's own
counts are as in R0768. The soldiers' share in the woods' view is the patrol standing in it, not
the trees. This is the CPU side only: in S0771's partial windowed numbers (a run stopped early)
the frame inside the wood was 1.3 ms longer than open ground's, with the extra draws above.

What the vegetation is given the renderer, counted once: about 37 draws and 62k triangles more in
the woods than on open ground; in the woods' view the patrol's soldiers are 3-4x the vegetation. In the woods,
the near tier's thickets (36k) and grass tufts (40k) are the biggest shares, then scrub (24k) and
crowns (20k). The forest suite, standing in temperate's densest copse (105 trees), counts 465 draws,
530k triangles and about 52k shadow triangles; the Experimental forest's densest copse runs a
6.9 ms frame (headless).

**Cut in this pass:** far-tier trunks (past 200 m, a 0.3 m post) cast no sun shadow: 17 fewer
shadow casters in the woods view (287 -> 270), 2.7k fewer shadow triangles (R0765 -> R0768). That
does nothing for the extra draws inside the wood that S0771's partial numbers show (the far tier
is past 200 m).
From the usual list, these no longer apply: trees are MultiMeshes per cell with tiers and
visibility ranges, thickets and scrub cast no shadow, the materials are opaque, and the scatter's
_process costs nothing measurable (the grass carpet 0.13 ms a frame). Still open: the draws inside
the wood (F-366, which wants the windowed split) and the cuts that would change the look (F-367).
Captain's item 1 stays open.

**Budgets** (Proposed, `DRAW_BUDGETS` in tests/perfcases_test.gd, about 1.5x the proxy's numbers
above, no local slack since they're counts): woods 160 draws / 250k triangles / 65k shadow
triangles of vegetation, open 100 / 150k / 50k. They catch the vegetation getting heavier, not the
per-cascade draws the proxy doesn't count. The frame budgets for open are the woods' own (18 /
26 ms, 15 hitches a minute over 30 s).

## What's left

See F-206 in docs/audits/followups.md: a cold building scan's grouping (100-250 ms once its probes
are done), a whole team spawned in one frame (about 8 ms a soldier), BodyDeform meshing on the main
thread, three RPCs a shot in co-op, and rendering costs the headless suites can't see (soldiers are
15-25 draws each with shadows; the terrain's coarsest level is a draw per 128 m chunk to the
horizon; module proxies cast shadows). The physics step cap stays at 8: a lower one turns overload
into slow motion, and the AI's clocks run on real time (Soldier._now), so they'd drift from the
movement.
