# Enemy high command (proposal)

**Status: Phase 1 and Phase 2 part one built** (2026-10-17, untested; Captain's answers below).
Every number is proposed and tunable. Not to be confused with `docs/high_command.md`,
which is the *friendly* side (hero-led squads the player commands).

Captain, 2026-10-17: "enemy forces also need a high command that kind of dictates the flow of
reinforcements and such, if an outpost is lost and a suitable force cant take it back we
shouldnt be assaulted by the rest of the map. the high commander can control high level stuff
like that and help direct."

## The problem today

A hot zone's enemy is a set of reflexes, each reacting to one event on its own:

- `EnemyResponse`: an engaged zone launches a QRF wave at the last known position (LKP) at most
  every 5 min; tier 3 sends hunter teams to the LKP; tier 4 sends two and HQ pairs to every
  site. A spawn budget (20-36 living) caps the total.
- `Reinforcements` (driven): each wave heads for the LKP, hunts it for 10 min, then holds.
- `Pressure` raises the tier from what the squad does; `Alert` decides what the enemy knows,
  with radio delays.

Nothing in that chain asks "can this attack win?" or "is this site worth it?". So every
response points at the same place, the squad. Wave after wave walks into the same kill zone
until the budget runs dry: the meat grinder. A lost outpost gets no answer at all, except more
hunters at the LKP.

## The idea: one commander per zone, deciding with what it knows

`EnemyCommand` (host only, one node per hot zone beside Alert/Pressure/EnemyResponse) owns the
enemy's *decisions*. The existing systems keep doing the *doing*: spawning, routes, QRF
technicals, check-ins, radio delays. The reflexes that launch forces today (QRF launch, hunters,
HQ pairs) stop firing on their own and become **requests** the commander approves, sizes, delays
or turns down.

It thinks every `COMMAND_TICK_S` (30 s, slower when degraded, see below), only from what reached
its radio net (Alert's reports and LKP, never the squad's real position), and acts through
**operations**.

### What it knows (its picture)

- **Sites**: each garrisoned site's state (held, under attack, lost, retaken), its value
  (`hq` 10, `qrf_base` 6, `outpost` 4, `comms` 4, `checkpoint` 2: Proposed) and what's left of
  its garrison.
- **Its forces**: every living soldier it can task (garrisons, patrols, waves, hunters), as
  **combat power (CP)**: 1 per man, × skill (combat 0.5 = 1.0), × 1.5 with body armour, + 4 per
  armed technical.
- **Reserves**: a finite manpower pool per QRF base and the HQ for the deployment (replaces
  the spawn budget as the thing that runs out). Pressure tier raises the pool and its refill
  rate; a destroyed base loses its pool.
- **The squad's estimated strength** (`threat CP`): what its people have reported, not the
  truth. Men seen (the most seen at once, × 1.5 for armour, × 2 for an LX-3 frame seen),
  raised by how much damage the squad has done lately (enemy losses in the last 10 min ÷ 3),
  plus vehicles seen. It fades slowly when unseen.

### What it decides (operations)

Each operation is a record: kind, target, task force (named units), state (`assembling`,
`moving`, `attacking`, `holding`, `done`, `failed`, `called off`), and a reason. One
operation per site; at most `MAX_OPS` (2, 3 from tier 3) attacking or moving at once.

| Operation | When | What it does |
|---|---|---|
| **Hold** (default) | Always, for every site | Garrisons stay home. Nobody leaves a site to chase noise further than its own area. |
| **Reinforce** | A site under attack or next to the LKP, and reserves to spare | Sends a few men from the nearest base *to the site*, to defend it (not to the LKP). |
| **Probe** | LKP stale (older than 10 min) or uncertain, and it wants to find the squad | One patrol pair walks toward the LKP area, reports, and pulls back if it makes contact. Cheap and expendable by design. |
| **Counterattack** | A site was lost (`site_down`) and it can field `COUNTER_RATIO` (3:1) of the threat CP from bases within reach, without stripping any base below its own guard | Assembles the task force at a rally point out of sight (`SPAWN_UNSEEN_M`), waits until it's all there, then attacks the site *together* (base of fire + assault, `SquadTactics`). Called off if it falls under 1.5:1 on the way. |
| **Contain** | A site was lost and it *can't* field 3:1 | Writes the site off for now. Holds the neighbouring sites harder (Reinforce), maybe a Probe to watch it. **No attack.** Re-checks each tick: if the squad leaves or reserves grow, it can become a Counterattack later. |
| **Hunt** | The squad is in the field (not at a site), LKP fresh (under 3 min), and it has 3:1 | The current hunter teams, but as one coordinated operation with a size and a stop. |
| **Consolidate** | Its losses this deployment pass `WITHDRAW_SHARE` (50%) of everything it had | Pulls survivors back to the HQ and the remaining bases. Outposts may be abandoned. |
| **Reoccupy** | A lost or abandoned site with no squad near it for `REOCCUPY_S` (20 min) | Quietly sends a garrison back (the world doesn't stay empty after you leave). |

The rule the Captain asked for is the Counterattack/Contain split: **a lost outpost is retaken
only by a force that can actually retake it. Otherwise the rest of the map doesn't come.**

### Decapitation and friction (making the commander part of the fight)

- **The commander is somebody**: the HQ's officer post 0. Killed, the zone loses its brain for
  `HEADLESS_S` (10 min): no new operations. Units keep defending; ones in the middle of an
  operation finish it badly (no coordination), or hold where they are. A deputy (another
  officer post) takes over after that, slower.
- **Comms down** (`Alert.comms_down`): orders reach units `COMMS_DOWN_MULT` slower, the
  commander's tick doubles, and Probes stop reporting back.
- **Officers killed** (`EnemyResponse.coordination()`): task forces assemble slower and
  attack less in step.
- **Fog**: it only sees what Alert reports, with Alert's delays. A quiet, suppressed squad
  stays misjudged (low threat CP) and will see thin counterattacks; a loud one gets a cautious
  enemy that contains rather than feeds.

### What the player reads (no meters)

- Behaviour: probes, then silence, then a real assault arriving together; outposts that stay
  lost; garrisons that dig in.
- **Radio chatter** (`RadioChatter`, looted radios): the commander's orders are on the net.
  "All stations, hold your positions." "Outpost 2 is lost, do not engage, hold at the
  checkpoint." "Assembling at grid 0412, we take it back at first light." This makes a captured
  radio worth a lot and gives intel contracts a target.

## How it fits the code

- New `scripts/campaign/enemy_command.gd` (`class_name EnemyCommand`), added by `ZoneLevel`
  beside `EnemyResponse`, on the Alert's clock (tests jump it with `Alert.advance`, then
  `server_tick`), like the others.
- `EnemyResponse` keeps patrols, check-ins, spawning, unseen gates, QRF technicals
  (`VehicleQrf`) and hunter behaviour. Its `_launch_qrf`, hunter and HQ-pair triggers ask
  `EnemyCommand.request(kind, target, size)` instead of acting. With no `EnemyCommand` (contract
  zones, tests that want today's behaviour) they act as now.
- `Reinforcements.server_send(origin, extra_pairs, cap)` already spawns a wave at a gate with a
  route; operations call it with an `aim` of the rally point or site, not the LKP.
- Task-force moves and attacks reuse `Squad` + `SquadTactics` (`elements`, `flank_route`,
  `clear_op`) as hunter teams do now.
- `Pressure` tier keeps meaning "how hard the enemy pushes", now by sizing reserves, `MAX_OPS`
  and refill rather than by spawning on its own.
- Saves: operations are deployment-scoped (no save change); site states already persist with
  the zone.

## Phases

1. **Commander + Counterattack/Contain** (the Captain's ask): picture, CP, reserves, the
   request gate, Hold/Reinforce/Counterattack/Contain, `MAX_OPS`. Tests (new `enemy_command`
   suite): a lost outpost is retaken only with 3:1 (and the task force arrives together); with
   less it's contained and no wave heads for the squad; at most `MAX_OPS` at once; the budget
   still holds.
2. **Part one (built 2026-10-17, simple on purpose, NOT tested: Captain "dont fix the tests")**:
   fog (contact reports carry how many were seen, `Alert._seen_at`; the estimate fades unseen,
   raised by recent losses; a site counts it only with a fresh LKP near it), finite reserves
   with slow refill (a lost base takes its share), Probe (stale LKP or a lost site nobody was
   seen at), Hunt gate (hunters need a fresh LKP, else a probe), Reoccupy (a probe finds the
   site clear, stays, `REOCCUPY_MIN` hold it; retaken men count as garrison via meta
   `garrison_of` in `ZoneLevel.garrison_alive`), Consolidate (past 50% lost: hunters and task
   forces home, no new hunts/probes, only HQ and QRF bases fought for), decapitation (HQ post 0;
   `HEADLESS_S` with no decisions, then the deputy at half pace; `commander_name()` for a
   contract), comms friction (slower tick and assembly, probes silent), orders on the net
   (`RadioChatter.order`), and hot zones: `HotZoneOps` answers the commander's death with a
   radio follow-up contract ("commander" in `FOLLOW_UPS`).
   **Part two (2b), built the same night**: per-site fog (a site counts the most any fresh
   contact report near it saw); the 2:1 retake (`REOCCUPY_RATIO`) when a probe meets fewer at a
   site than the squad is thought to be (a defender left on it); QRF waves recalled on
   Consolidate; the HQ's pairs to its sites ask the commander (`request_men`, paid from
   reserves); hunts have a stop (`HUNT_STOP_S`, recalled teams aren't retargeted).
   Then: outposts and checkpoints abandoned on Consolidate (garrisons regrouped into a squad,
   meta `left_post`, walk to the nearest base); the employer tips the squad off over its field
   radio when a counterattack masses (`HotZoneOps._on_operation`, `TIP_CHANCE` 0.6,
   `EnemyCommand.operation_started`).
   Commander capture missions: a hostile HVT at the HQ (an hvt_capture contract there) IS the
   commander (`_find_commander_hvt`, within `COMMANDER_HVT_M`); captured, delivered or dead,
   the zone goes headless. HotZoneOps' QRF-base follow-up is now an hvt_capture at the HQ
   ("their commander's there, take him alive"), raid as the fallback.
   **Still to do**: in-situ interrogation of captured squad leads/commanders for intel and
   missions (Captain's idea, parked: "lets not worry about interrogation yet"); an enemy_command
   test suite and missions_test's QRF checks updated to the 2:1 gate.
3. Vehicles in task forces (`VehicleQrf` technicals), mortars or air when they exist, named
   enemy commanders (wave 6).

## The Captain's answers (2026-10-17)

1. Ratios: **keep** counterattack at 3:1, call off under 1.5:1.
2. Reserves: **finite per deployment, refilled slowly by tier.**
3. Decapitation: **yes**, the HQ officer is huntable, **and can be a contract target** (an HVT
   contract on the zone's commander; contract side is a follow-up).
4. Reoccupy: **no timer; the commander decides.** Retaking a site is an operation like any other:
   a Probe goes first, then a Reoccupy at 2:1 or better (`REOCCUPY_RATIO`), paid from the finite
   reserves. A site with a defender (a squadmate or rebel left on it) counts that defender in the
   threat at the site; a site handed to the rebels must be taken out of rebel hands (rebels count
   as the threat there). No squad near it and no defender: a cheap one-pair Reoccupy is enough.
