# AI virtualization (inspired by ALiVE's profile system)

**Status:** built 2026-10-20 (branch `claude/virtualization`): phases 1 to 3 (profiles, garrisons,
vehicles and convoys, off-screen fights, saves); occlusion culling (phase 4) still to do (see
"What's built" at the end). Design 2026-10-18 (Captain: "virtualization of anything beyond the players
sightlines", then "instead of dynamic sim lets take a page out of the ALIVE mods book and
actually virtualize").

## The idea

ALiVE doesn't freeze far units the way Arma's dynamic simulation does; it removes them. A group
nobody is near is despawned into a **profile**: a few lines of data (where it is, who is in it,
what they carry, how hurt they are, what it's doing). The profile keeps moving and doing its job
on the map at almost no cost, and when a player comes within range it's spawned back as real
soldiers, where the profile had got to, with the same men, kit and wounds. Players never see the
swap, because it happens past what they can see.

For Contractor that means a hot zone can hold a whole enemy force (garrisons, patrols, QRFs,
hunters, convoys) while only the groups near a player cost frame time, physics, navigation and
network traffic. It's also the base of wave 6's persistent world: profiles are what gets saved and
what the faction simulation moves between deployments.

## What we have to build on

| Today | Where |
|---|---|
| Modules stream in at 260 m and out at 340 m around players (and around AI in a fight, on the host) | `ZoneLevel` `STREAM_IN_M`, `STREAM_OUT_M`, `stream_focus()` |
| Garrisons spawn the first time their module streams in, and never despawn | `ZoneLevel._on_streamed_in`, `_spawn_garrison` |
| Patrols, QRF waves, hunters and HQ pairs are always live soldiers once spawned | `EnemyResponse` (`patrols`, `hunters`, `reinforcement_pairs`), `Reinforcements.waves` |
| Never spawning where the squad would see it | `EnemyResponse._unseen` (distance), `_hidden` (line of sight, new for the look rally points) |
| Kit and wounds already save and restore | `Inventory` and `Vitals` save data (zone saves keep bodies and items) |

## Design

### Profiles

A profile is a plain `Dictionary`, host-only, saved with the zone:

- `id`, `side`, `kind` (`garrison`, `patrol`, `qrf`, `hunters`, `pair`, `convoy`), `owner` (which
  system made it: the module id, the patrol record, the HC operation).
- `members`: per man his name, role, `Inventory` save, a `Vitals` summary (blood, open wounds,
  tourniquets, pain, unconscious), skill stats, and his offset in the group.
- `pos`, `heading`, `speed`, and the job: `route` + index (patrol), `target` (move, assault,
  search), `hold` (a post), `until`.
- `mode` (safe / aware / combat) and the last known position of the squad it was told about.

### The virtualizer (host, one per zone)

Every `TICK_S` (1 s):

1. **Live -> virtual.** A live group goes virtual when all of these hold for `CALM_S`:
   - every member is further than `DESPAWN_M` (proposed 700 m) from every player;
   - no member is in contact, suppressed, treating a casualty or in a vehicle seat that's moving
     (vehicles virtualize with their crew later, phase 3);
   - no player has had a line of sight to any member for `UNSEEN_S`.
   Its soldiers are snapshotted into a profile and freed. Their squad node goes with them.
2. **Virtual -> live.** A profile comes back when any player is within `SPAWN_M` (proposed 550 m,
   below `DESPAWN_M` so nothing flickers) of it, and only at a spot no player has a line of sight
   to (the profile waits a tick or two otherwise; at `FORCE_M`, 300 m, it spawns regardless,
   behind cover if there is any). Men come back with their own kit and wounds, in the group's
   formation round `pos`, with the same job.
3. **Moving the virtual.** Each profile advances along its job at its speed over the terrain
   (straight lines between route points, roads where it has them, no navmesh), and reaches
   targets, holds, searches (timers) and goes home like the live group would.
4. **Virtual fights** (phase 3, with wave 6's factions): two hostile profiles meeting resolve by a
   quick strength roll and lose men; never against the player's squad, whose groups are always live.

### The systems that send groups

`EnemyResponse`, `EnemyCommand` and `Reinforcements` keep records that point at soldiers
(`record.soldiers`, `living`). They'll hold a **group handle** instead: one object that is either
live (soldiers) or virtual (a profile) and answers the same questions (`living()`, `position()`,
`set_route()`, `send_to()`). Their decisions stay exactly as they are; only how a group is held
changes. Garrisons get handles too, keyed to their module: a garrison whose module streams out
(and whose men are out of range) goes virtual at its posts, and streams back in with its module.

### Rendering (the "beyond the sightlines" half)

- Godot occlusion culling on, with an `ArrayOccluder3D` per terrain chunk built from its coarse
  (LOD 1) mesh, so ridges and the new folds hide what's behind them: modules, scatter, people.
- The existing visibility ranges (scatter, roads, module proxies) stay as they are.

### Saves and networking

- Profiles are host-only and saved with the zone, so a squad that leaves and comes back meets the
  same men (wave 6's persistent world builds on this).
- Clients never hear about virtual groups: nothing is replicated until they're live, which also
  cuts network load in big zones.

## Phases (proposed)

1. **Patrols, QRF waves, hunters, HQ pairs** (`EnemyResponse`'s groups): handles, the virtualizer,
   virtual movement along routes and to targets. Tests: a patrol walked out of range goes virtual
   and comes back where its route took it, same men, same kit and wounds; nothing spawns in sight.
2. **Garrisons:** virtual at their posts once their module streams out; back with the module.
3. **Vehicles and convoys**, virtual fights between factions, saves of profiles across deployments.
4. **Occlusion culling** from the terrain (can run beside 1-3: rendering only).

Every number above is Proposed. Credit where it's due: the profile system is ALiVE's idea; this is
our own build of it for Contractor's zones.

## What's built (2026-10-20)

`scripts/world/virtualizer.gd` (`Virtualizer`, one per zone, host only). Tests:
`tests/virtualization_test.gd` (suite `virtualization`), the co-op check in `tests/net_test.gd`'s
zone leg, and the timing script `tests/virtualization_perf.gd`.

- **Groups, not handles.** Instead of a new handle object, the owners' own records
  (`{"squad", "soldiers", ...}`) are tracked (`Virtualizer.track`). A virtual record keeps its
  `squad` node (asleep) and holds its profile under `"virtual"`; its `soldiers` are empty. The
  owners ask `Virtualizer.up(record)`, `lead(record)` and `points(record)` where they used to look
  at the soldiers, and keep setting `squad.patrol` to send a group somewhere: a profile walks
  whatever route its squad has (a new route starts it over, as `SquadAI._patrol_index` does).
  Tracked: EnemyResponse's patrols, hunters and HQ pairs, the QRF waves (Reinforcements),
  EnemyCommand's counterattacks, probes and reoccupations, a faction skirmish team, and a hot zone's
  new roaming teams.
- **Numbers as proposed:** DESPAWN_M 700, SPAWN_M 550, FORCE_M 300; calm and unseen for HOLD_S
  (15 s), a group just sent out at once. Live enemy AI counts too (a skirmish team reaching a
  patrol): within AI_DESPAWN_M (300) it stays real, within AI_SPAWN_M (220) a profile comes back.
- **Exactly as they were:** each man's `Inventory.net_state` (rounds, plates, chips), his
  `Vitals.server_snapshot` (the whole wound model), his skill, mode, post, route leg, metas (a
  named squad's, `garrison_of`, `left_post`, ...) and buddy. Men come back through the AISpawner
  (not `spawn_soldier`: who they are is settled), a few a frame.
- **Garrisons** go virtual at their posts once their module has streamed out (calm, unseen, nobody
  within STREAM_OUT_M) and come back with the module (`ZoneLevel._spawn_garrison`). Their gun and
  mortar teams wait, paused, and get their men back. `ZoneLevel.garrison_alive`, Alert's check-ins,
  Objectives' clear-area count and EnemyCommand's officers all count virtual men.
- **Off-screen fights** between profiles of sides at war (CONTACT_M 150, ROUND_S 10): hits by
  skill, garrisons behind walls are harder to hit, a hit kills half the time and wounds otherwise,
  a side cut to a third breaks off. The dead are real bodies with their kit; EnemyCommand counts
  them as losses.
- **Saves:** `GameState.profiles` (every profile, and every tracked group or garrison still live,
  snapshotted), given back on load: patrols and roaming teams by route, hunters, HQ pairs and QRF
  waves to their owners' lists, garrisons to their modules. A save old enough to fade the loose
  gear (`fade_loose`) drops them: the zone's enemy is fresh.
- **Co-op:** profiles never replicate; men come back as ordinary AI (late joiners get them).
- **Rides (vehicles and convoys):** a group whose every man is aboard vehicles on their way somewhere
  goes virtual with them: each vehicle's `Vehicle.to_save` (its id, damage, fuel, cargo) and who sits
  in which seat. Rides are VehicleQrf technicals driving a QRF or a patrol in (`VehicleQrf.convoy_of`)
  and a mission's convoy while it rolls (MissionScenario vouches for it: `virtual_ride`). The profile
  drives the ride's route at the ride's speed (RIDE_OFFROAD_MULT 0.6 of it off a road, slower up
  hills). Back in the world the same vehicles come out on its way, the men in their seats, and the
  owner drives on (`VehicleQrf.server_resume`, `MissionScenario.virtual_ride_back`). A QRF ride that
  reaches where its men get out leaves its technical parked there (real, empty) and the men walk on.
  A virtual convoy reaching the end of its route gets away (the objective fails) as a live one does.
  A group half aboard and half walking stays real. Mission convoys aren't in the zone save's profiles:
  the scenario checkpoint keeps them (it wakes them first).
- **DynamicSim stays** for the AI the virtualizer doesn't take (crews of vehicles that aren't rides,
  bombers, the rival PMC team, scenario waves): it still sleeps them in place past SLEEP_M.
- **Capacity:** a hot zone fields `EnemyResponse.ROAM_TEAMS` (2) roaming teams of `ROAM_SIZE` (4)
  on each patrol route, outside the spawn budget (which still paces what is sent at the squad).

**Measured** (tests/virtualization_perf.gd, headless, ridge_hot's 4 km hot zone, 2026-10-20; the same
three teams within 450 m of the player in every case, every other team at least 800 m out, each
walking its own route; other test runs were sharing the PC, so read the cases against each other):

Two runs each (the second after the first):

| Case | Frame avg | Worst frame | Physics step | In the world | Virtual |
|---|---|---|---|---|---|
| Today: 40 men, DynamicSim only | 7.33 / 7.04 ms | 19.9 / 20.2 ms | 12.5 / 10.6 ms | 40 (28 asleep) | 0 |
| Today with virtualization | 7.03 / 6.96 ms | 17.1 / 14.3 ms | 14.2 / 12.8 ms | 12 | 28 |
| 3x: 120 men, DynamicSim only | 9.03 / 9.75 ms | 33.4 / 44.5 ms | 23.1 / 29.0 ms | 120 (108 asleep) | 0 |
| 3x with virtualization | 6.98 / 7.04 ms | 15.4 / 16.3 ms | 7.9 / 8.0 ms | 12 | 108 |

("Physics step" is Godot's physics-process time monitor sampled each frame: the last step's cost,
noisier than the frame times.)

Three times the force with virtualization costs no more than today's does without it. Sleeping men
(DynamicSim) still cost physics (their bodies stay in the world, and the navigation is kept baked
round them); profiles cost next to nothing.

Still to do: occlusion culling, an alert report for an off-screen fight (gunfire heard), choosing a
covered spot at FORCE_M, a QRF technical's gunner staying on the gun when it parks off-screen (all its
men walk on), and the squad's own vehicles (never virtual: the squad is always real).

