# AI virtualization (inspired by ALiVE's profile system)

**Status:** built 2026-10-20 (branch `claude/virtualization`): phases 1 and 2, profile saves and
off-screen fights from phase 3; vehicles and occlusion culling still to do (see "What's built"
at the end). Design 2026-10-18 (Captain: "virtualization of anything beyond the players
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
- **DynamicSim stays** for the AI the virtualizer doesn't take (vehicle crews, bombers, the rival
  PMC team, scenario waves): it still sleeps them in place past SLEEP_M.
- **Capacity:** a hot zone fields `EnemyResponse.ROAM_TEAMS` (2) roaming teams of `ROAM_SIZE` (4)
  on each patrol route, outside the spawn budget (which still paces what is sent at the squad).

Still to do: vehicles and convoys as profiles (mounted groups stay real), occlusion culling, an
alert report for an off-screen fight (gunfire heard), and choosing a covered spot at FORCE_M.

