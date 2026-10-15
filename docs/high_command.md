# High command: hero-led squads (proposal)

**Status: Proposed** (2026-10-14). For the Captain to approve, change or turn down. Nothing here
is built, and every number is Proposed and tunable. Checked against dev `fc98665` (B0734), the
co-op soak brain in `tests/coop_soak.gd` (`test/coop-soak` `33d3e87`, `test/coop-fakehuman-checks`
`5858854`, `test/coop-soak-stuckbots` `10a41c3`), and the co-op fix branches in flight
(`fix/respawn-own-kit` `4421481`, `fix/coop-extraction` `906053c`, `feat/fob-ready-up` `8ebcdc3`).

On harder contracts the company fields more than the player squad. One to three **hero squads**
deploy beside it, each led by a named roster member (the hero). The player commands squads, not
men, from the map or from the command menu. Every order is a record with a lifecycle that ends
`done`, `failed` with a reason, or `cancelled`. The host compiles it into squad orders that already
work, the squad reports back over a company net, and its men come home with experience, wounds or
losses that persist on the roster.

Contractor learns from other games here. It is inspired by the Arma 3
high command bar and squad-leader AI, by LAMBS and VCOM group tasks and mutual support, and by
Bannerlord heroes who lead their own parties. It also learns from where Arma's high command feels
weak: little feedback, waypoints that fail silently, and no way to time squads together.

## How this proposal was put together

Three designs were written against the code and judged. This document leads with the top-ranked
one and grafts in the best parts of the other two.

| Design | Rank | What it gives this proposal |
|---|---|---|
| **Command-first:** the high command map and order model | 1st (lead) | The order record and lifecycle (nothing fails silently), the verb-to-primitive compile table, the option mask on SquadTactics, progress watchdogs, the MapMarkers-shaped RPCs with host re-resolution and late-join snapshot, the ghost line until the host acks, map Command mode, the HC panel, knowledge fairness, the most complete Phase 0 list, and the buildable phasing |
| **Campaign-first:** heroes as roster progression, squads as company assets | 2nd | Heroes earned from the Captain's own roster, standing squads (detachments) that keep their men, `squads_max` from the briefed rating, field promotion, MIA leading to recovery contracts, hero history lines, lazily migrated roster data with no save bump, one company commander with handover, `squad_for` kept as "the player squad" plus a new `squad_of`, and G1 landing alone with a test |
| **AI-first:** a squad-level planner under a hero leader | 3rd | The tasking context (anchor, leash, sector, rally) that replaces the human-lead leash, sector boundaries so squads stay in their lanes, the `safe_to_fire` fan and lift/shift fire, support-by-fire spot rules, combat effectiveness (CE) colours, a company enemy picture with radio latency and "going dark" when the hero falls, the `assess()` player-count gap, and later reuse of the planner for enemy hunters |

What the judges found and how it is folded in:

- **Persistent heroes arrive too late in the lead design** (its Phase 3). The Captain's direction
  is named AI squad leaders, so the MVP hero here is a **real roster member** picked at prep, with
  history and outcomes from day one. Promotion, traits and wages still wait for Phase 3, so the
  MVP doesn't depend on the FOB economy (the campaign-first design's weakness: its MVP could not be
  tried in a zone until promotion and assignment worked).
- **A dev-tools spawn** exists from Phase 1 so the orders can be proven headless before any FOB
  work.
- **`SquadTactics.assess()` counts the human players for any friendly squad** (tactics.gd:285-292
  checks only `squad.faction == &"friendly"`). A hero squad would think the humans are its own men.
  Both top designs missed it; it is G4 below.
- **Extraction and CCP** treat every friendly AI as the player squad (the lead design caught this;
  the campaign-first design didn't). They are in Phase 0.
- **Streaming.** On the host, `ZoneLevel.stream_focus()` (zone_level.gd:633) streams modules only
  around players and fighting AI. A hero squad holding a building 500 m out would have its module
  streamed out under it. Hero leaders join `stream_focus` (G8).
- **Grid references** are already static: `MapGrid.grid_ref(point, area, digits)` and
  `grid_ref_3d` (map_grid.gd:36, 47). No split of `MapView.reference_at` is needed.
- **Doctrine weights are still PENDING** (audit A3-07). Hero traits and order biases use only the
  wired channel (SquadTactics option biases through `doctrine()`) and the planner constants, and
  are never presented as doing more.
- **AI load.** Hero squads spawn when the deployment starts, not when the briefing opens; the
  briefing shows their insertion markers only.

## 1. What already exists to build on

- **The order bus.** `CommandMenu` (scripts/ui/command_menu.gd) is local to each player: F1-F8
  select men by `squad_slot`, 1-9/0 pick entries, and every order is a string verb plus a point
  plus a set of names sent as `Soldier._server_squad_command.rpc_id(1, cmd, point, selected)`. On
  the host `Squad.order_command()` runs first, then `give_order` / `set_hold_fire` / `command()` /
  `Supports.server_command` (the `support:` prefix is a registry seam). High command reuses this
  grammar one level up.
- **Squad** (scripts/ai/squad.gd): host-side command state with an enemy picture (`known`,
  `clusters()`), `leader`, `ccp`, formations, and order wrappers that take `from: Soldier`:
  `give_order` (FOLLOW / HOLD / MOVE), `order_bound`, `order_suppress`, `order_garrison`,
  `order_clear`, `order_take_cover`, `order_fall_back`, `order_command` ("watch", heal, give ammo,
  ccp), `command` (formation, target, mode). Every order sets `leader = from`; called with `from` =
  the hero they become the hero's orders to his own men.
- **More than one Squad per side already works for the enemy.** `EnemyResponse._new_squad` /
  `_spawn_team` and `Reinforcements` create a `Squad`, spawn through `level.spawn_soldier` and set
  each brain's `squad`. Hero squads spawn the same way.
- **SquadTactics** (scripts/ai/tactics.gd): HOLD, SUPPRESS_FLANK, ASSAULT, CLEAR, DEFEND,
  BREAK_CONTACT, CASUALTY, SEARCH. `score()` is static and pure; `doctrine()` adds biases;
  "orders always win". `elements()`, `flank_route()`, `garrison_tasks()`, `clear_op()` and
  `fall_back_point()` are static and reusable. `OPTION_NAMES` and `CALLS` already give readable
  state for reports. `FOLLOW_LEASH_M` is 30.
- **SquadAI** (scripts/ai/squad_ai.gd): ordered tactics win over the evaluator; followers read
  only `leader.global_position` and its basis, so an AI soldier as `squad.leader` already works for
  them; `_friendly_in_line` checks every friendly on the side, so cross-squad fire discipline
  exists as a last guard.
- **Map**: `MapView` (right-click menu, Ctrl+drag lines, plan mode in briefings), `MapScreen` side
  panels (`MapExtractionPanel` is the template), `MapMarkers` (host-authoritative `request_*` ->
  `server_*` -> `_client_*`, `_client_snapshot` on `Net.peer_joined`, `server_report_enemy` for
  intel), `MapGrid.grid_ref`, and `MapNodes.install(level)` for per-level nodes on every peer.
- **Comms**: `Callouts._show` to the side's players; `RadioChatter`'s queue and gap rules
  (`LINE_GAP_S`, `QUEUE_MAX`) with a non-soldier speaker name.
- **Roster and deployment**: members carry callsign, identity, role, skills {aim, nerve, medical,
  movement}, xp, missions, wage, gear, status, injuries and history. `Roster.ai_stats()` maps aim to
  combat and nerve to discipline. `RosterDeployment.resolve()` keys outcomes by member id, so it
  already settles any number of AI members as extracted, MIA (with a recovery contract) or KIA.
- **BaseHub**: `server_spawn_roster_squadmate()` (base_hub.gd:854) and `_spawn_recovery_targets()`
  (base_hub.gd:893) already spawn roster members with identity, own gear, `roster_id` and
  `ai_stats`, the second one outside the 8 slots. Company decisions are host-only requests, and
  `Campaign.snapshot()` before deploy means roster changes revert for free.
- **Contracts**: a briefed `rated` 1-5, a hidden `true_rating`, `difficulty_pay`.
- **Extraction** (on `fix/coop-extraction`): any player in a point confirms; AI away from it don't
  block; the first confirm warns who would be left, a second within `LEAVE_CONFIRM_S` leaves them
  MIA. Hero squads plug into that warning, not a second mechanism.
- **The co-op soak "player brain"** (tests/coop_soak.gd): `_follow_tick` (850), `_stuck_note` (909),
  `_extract_with_human` (938), `_follow_spot` (985), `_hidden_fraction` (1099), `_dead_ground`
  (1118), `_treat_loop` (1586), `_wedge_spot` (1705), `_give_up_tick` (1727), `_casevac_tick`
  (1762), `_hunt` (1825), `_fight_tick` (1981). It drives player bodies over RPCs from other
  processes, so it can't ship, but its decisions are the behaviour spec for Follow, Support me and
  Extract, and the harness becomes the high command test bench (section 9).

**Lessons taken from the soak bot:** progress watchdogs and detours, phase timeouts with "stuck"
reports (S0758: bots stood 400 m behind for 20 minutes with nothing logged), points clamped inside
the map (S0672, S0697), and the leave-behind rules. **Lesson avoided:** `_dead_ground` and
`_hostile_posts` read true hostile positions. That is fine in a test and a cheat in game AI; heroes
plan only from what our side knows (5.6).

## 2. Groundwork: a second friendly squad breaks one-squad assumptions

Fixed first (Phase 0), no gameplay change, a regression check each. All checked against fc98665.

| # | Where | What breaks | Fix |
|---|---|---|---|
| G1 | `Squad.members()` (squad.gd:187) | Returns every friendly AI in the faction (filtered only by vehicle crew). Player orders, `pick()`, `follow_point()` would reach hero squad men | Keep only soldiers whose brain is on this squad, as `brains()` (squad.gd:108) does. **Lands alone first, with a test** |
| G2 | `CompoundLevel._squad_ai()` and `rebalance_squad()` | A hero squad man (slot -1) could be removed on the next join or leave | Exclude hero squad men |
| G3 | `CommandMenu.roster()` | F-keys, select-all and HUD squad lines would list hero squad men | Player squad only |
| G4 | `SquadTactics.assess()` (tactics.gd:285-292) | Every slotted human is counted in every friendly squad's up/down | `Squad.is_player_squad()`; count humans only there |
| G5 | `Callouts.recipients()` | Every friendly shout reaches every friendly player at any range | Hero squad shouts reach players within `HC_VOICE_M` (40-60 m); the rest is summarised on the net (section 6) |
| G6 | `EnemyResponse._watchers()` | QRFs and hunters may spawn in a hero squad's face | Add hero squad men |
| G7 | `CompoundLevel._make_soldier` | Sets `brain.squad = squad_for(faction)` | Re-point after spawn, as `_spawn_team` does |
| G8 | `ZoneLevel.stream_focus()` (zone_level.gd:633) | Modules (and garrisons) stream out under a hero squad out of contact | Add each hero squad's leader on the host |
| G9 | `Squad.follow_point()` (squad.gd:649) | Indexes `members()` including the leader: an AI hero on FOLLOW chases his own slot | Skip the hero; he walks `Intent.LEAD` (5.3) |
| G10 | `SquadAI._tactic()` / `_tactic_done` | A friendly whose order isn't FOLLOW drops evaluator moving tasks; a finished ordered tactic leaves him on HOLD | The order executor restores FOLLOW after ordered tactics unless the phase wants men held (5.2) |
| G11 | Extraction `required()` / `missing_at`, CCP, body carrying, respawn kit | Count every friendly AI as the player squad: extraction would wait for hero squads | Scope to the player squad; hero squads get their own path in the leave-behind warning |
| G12 | Callers of `squad_for(faction)` (14 sites in 8 files: soldier.gd, callouts.gd, vehicle_layer.gd, aav_support.gd, heli_call.gd, base_hub.gd, compound_level.gd, zone_level.gd) and of `MapNodes.squad_ai` / `squad_slot >= 0` | Each assumes one friendly squad | `squad_for` keeps meaning **the player squad**, so most callers stay correct. Callers that mean "this soldier's squad" (vehicle mounting, callouts by speaker, supports) move to a new `CompoundLevel.squad_of(s)` = `SquadAI.of(s).squad`. Audit each |

**One marker, not scattered checks.** Each hero squad soldier gets a replicated `Soldier.hc_id`
(StringName, `&""` for the player squad), set from spawn data and added to the soldier's
`SceneReplicationConfig`, so the HUD, map and command menu on clients can tell hero squad men apart
(a meta wouldn't replicate). `Squad` gets `hc_id`, `hero`, `is_player_squad()`, and one predicate
`Squad.is_squadmate(s)` (friendly AI, player squad, not a recovery target, not vehicle crew) in
place of the meta checks G2, G3 and G11 repeat today.

**Sequencing.** G1, G9, G10 touch squad.gd and squad_ai.gd, and G5 touches callouts.gd: the
coop-respawn agent (B:\Contractor-coop-respawn: body carrying, `ccp_off`) is editing those now. G11
touches extraction (coop-extract). Phase 0 starts after those branches land on dev and builds on
them; anything needed sooner goes as an F-task in docs/audits/followups.md.

## 3. What the player does

### 3.1 A hard contract, end to end

1. **Board.** A rated-4 raid shows "Squads: 1 + up to 1". `squads_max` comes from the **briefed**
   `rated`, never the hidden `true_rating`: rated 1-3 gives 0, rated 4 gives 1, rated 5 gives 2, a
   hot zone adds 1, at most 3 (the MVP caps it at 1). An understated contract is exactly where a
   squad brought "just in case" pays off.
2. **FOB prep.** The "Squad & deploy" page gets a **Hero squads** block: pick a hero and his men
   from available roster members (roles auto-filled by `Roles.layout`, as `auto_squad` does), and
   see a **friendly AI budget** line ("AI: 7 + 4 = 11 of 20"). More co-op players means fewer AI in
   the player squad and room for more hero squads, which keeps the 8-slot squad player-scalable.
   From Phase 3 these are standing detachments (section 8). Picks follow the FOB ready-up rules.
3. **Briefing.** Hero squads show at their insertion markers (default: the next insertion
   candidate, 80-150 m from the player squad). From Phase 2 the player can drag them and give
   **H-hour orders** that start with the deployment, or wait on a go code.
4. **In the field.** The player commands squads from the map's **Command mode** or (Phase 2) the
   command menu's **Squads mode**. Squads acknowledge, report contact (dropping an intel marker),
   casualties, "set", "objective secure", "held up", "unable" with a reason, and requests:
   - "Hawk 2, copy: moving to 041 053."
   - "Hawk 2, set at 041 053. Ready on Alpha."
   - "Viper 3, contact: 6 enemy, north, 180 m, engaging."
   - "Viper 3, amber: two wounded, request to break contact." (Approve / Deny, 20 s.)
   - "Hawk 2, Mercer is down. Okafor has command."
5. **Synchronising** (Phase 2). The player presses go code Alpha: Hawk 2 opens fire on the compound
   while the player squad assaults. When any friendly comes within `DANGER_CLOSE_M` of the target or
   the fire fan, Hawk shifts or lifts by itself ("Hawk 2, shifting fire").
6. **Extraction.** "Extract" sends a squad to a point with an avoid-contact posture. Hero squads
   never confirm and never extract without the humans (the Captain's 2026-10-14 co-op rule). They
   never block the player squad either: the leave-behind warning names them ("Leaving behind:
   Viper 3, 2 men, 380 m out"), and a second confirm leaves them MIA under the existing rules.
7. **Debrief.** Each hero squad gets a section: who came back, wounds, KIA, MIA, objectives it was
   credited with. The hero's history gains "Led Hawk 2 at Outpost 2: held the bridge, 1 wounded".

### 3.2 Orders

| Order | The squad does | Compiles to (existing) | Done when | Phase |
|---|---|---|---|---|
| **Move** (point; route later) | Hero walks the legs, men follow in formation; on contact react, fight, resume | `Intent.LEAD` legs, `FORMATIONS`, halt spots | Hero within `ARRIVE_M` of the last point | 1 |
| **Hold** | Stop; halt spots; watch the threat axis | `give_order(HOLD)`, "watch" | Replaced | 1 |
| **Defend** (point, facing) | Move; garrison a building within 30 m, else a line across the facing, a watch sector per buddy pair | `order_garrison`, `garrison_tasks`, "watch" | Replaced (reports "set") | 1 |
| **Follow me / Support me** (a player) | Loose station off the player, turned his way; Follow 30-60 m, Support me in echelon at 60-120 m; hold and fight in contact | `FollowBrain` (section 9) | Replaced | 1 (fire for the player 2) |
| **Regroup** (hero, point or player) | Gather within `REGROUP_M`, set `ccp`, cross-load ammo, treat; sitrep | `give_order`, `order_give_ammo`, `ccp` | All living men gathered | 1 |
| **Extract** (point) | Route with a break-contact bias and return fire; hold inside | `Extraction.points`, `inside()` | Every living man inside: "Hawk 2, at the LZ" | 1 |
| **Posture** (no point) | ROE, combat mode, formation, speed | `set_hold_fire`, `set_combat_mode`, `command("formation:")` | At once | 1 |
| **Report** (no point) | A sitrep | | At once | 1 |
| **Attack** (area, building, objective, marker) | Approach to an attack position; set a base of fire; wait for a go code if gated; assault or clear; lift and shift; consolidate; abort past the risk threshold | `order_bound`, `order_clear`, `forced_plan`, biases | Objective clear for `CONSOLIDATE_S`: "objective secure" | 2 |
| **Support by fire** (position, target) | Take the best SBF spot; suppress while the target holds known enemies; shift or lift for danger close; "fire on call" option | `order_suppress`, "watch", `safe_to_fire` | Lifted, or target quiet `SBF_IDLE_S` | 2 |
| **Bound** (point) | Fire teams bound by pairs | `order_bound`, `elements()` | Arrived | 2 |
| **Fall back** (point) | Break contact by pairs with smoke, then hold | `order_fall_back` | Arrived | 2 |

On an SBF order: Shift fire, Lift fire, Fire, Cancel. With two squads selected, Bound becomes a
leapfrog (one overwatches, the other moves a leg) in Phase 4.

### 3.3 Controls (all rebindable through `GameSettings.BINDABLE`)

| Where | Input | Effect |
|---|---|---|
| Map | **Command** toolbar toggle or the `high_command` action | Command mode on or off; markers stay visible but aren't editable in it |
| Map, command mode | Left-click a squad icon (Shift adds, Tab cycles, 1-4 pick squads) | Select |
| Map, command mode | Short right-click | Order menu for what's under the cursor (3.4); right-drag still pans |
| Map, command mode | Shift with an order | Queue it (Phase 2) |
| Map, command mode | Ctrl+left-drag | A route (multi-point Move), reusing MapView's line capture (Phase 2) |
| Map, command mode | Backspace | Cancel the selected squad's order |
| World | `high_command` action | Command menu **Squads mode**: F1-F4 select hero squads, verbs aim with the crosshair (Phase 2) |
| Map or world | Go-code buttons; `hc_approve` / `hc_deny` | Alpha / Bravo / Charlie; answer the latest request (Phase 2) |

F1-F8 stay for men in the player squad. New defaults avoid Ctrl and Alt chords: the Ctrl and Alt
menus own those modifiers, Ctrl+F-key already adds to the command menu selection, and Alt+F4 closes
the window. Defaults are checked against `Controls.KEYS` before they ship.

### 3.4 The map order menu by what's under the cursor

- **Open ground:** Move, Hold here, Defend (drag for facing), Regroup here; later Bound, Fall back,
  Support by fire from here (a second click picks the target).
- **Building** (`Buildings.nearest`): Defend (garrison), Move; later Clear.
- **Enemy intel marker, objective or hostile site:** later Attack, Support by fire on it. Attack
  snaps to an objective within 60 m.
- **Extraction point:** Extract here.
- **A player icon:** Follow, Support me, Regroup on him.
- **Always:** Report, Posture; later Risk (Careful, Balanced, Press on) and Go code for the next
  order.

The host re-resolves every lookup and never trusts the client's.

## 4. The order model

### 4.1 HcOrder (JSON-safe: it replicates, goes in the session log and survives saves)

```
{"id": int, "squad": "hawk2",
 "verb": "move|hold|defend|follow|support|regroup|extract|attack|sbf|bound|fall_back",
 "points": [[x, z], ...],
 "target": {"kind": "area|building|objective|marker|player|squad|extraction", "pos": [x, z],
            "radius": m, "ref": "id"},
 "facing": [dx, dz] or null,
 "posture": {"roe": "free|return|hold", "mode": "safe|aware|combat|stealth",
             "formation": "wedge|file|line|staggered column", "speed": "slow|normal|fast",
             "contact": "react|push|avoid"},
 "risk": "careful|balanced|press", "go": "" | "alpha" | "bravo" | "charlie" | "hhour",
 "after": 0, "state": "sent|queued|waiting|active|set|done|failed|cancelled",
 "phase": "route|set|execute|consolidate", "by": peer, "at": seconds, "why": ""}
```

- **Lifecycle:** `sent` (client only, the ghost line), `queued`, `waiting` when gated, `active`
  (route), `set` (in position, waiting for a go code or "Fire"), `active` (execute), then `done`,
  `failed` (with `why`) or `cancelled`. **Latest order wins** unless shift-queued, matching
  today's command menu.
- **Contact on a Move** follows `posture.contact`: react (the hero halts, SquadTactics fights, the
  move resumes 10 s after contact ends), push (keep moving), avoid (break-contact bias, continue).
- **Risk sets the casualty threshold:** Careful is the first urgent casualty or 25% down, Balanced
  35%, Press on 50%. Past it the hero requests to break contact; a Careful hero breaks at once and
  reports.
- **Go codes** (Phase 2) are session-wide: one press launches every `waiting` order with that code.
  `hhour` orders start on `Briefing.deployment_started`. Phase 4 adds `after` ("Viper 3 moves when
  Hawk 2 is set").
- **Commander's intent:** if an attack's enemy cluster drifts within `OBJ_DRIFT_M`, the hero re-aims
  instead of failing.

### 4.2 The order is law; autonomy lives inside it

SquadTactics still fights every contact, but the verb narrows its options (an **option mask**) and
biases what is left:

| Verb / phase | Allowed options | Biases (Proposed: flank / assault / clear / defend / break / hold / search) |
|---|---|---|
| Move (react) | all but SEARCH | -0.15 / -0.2 / -0.3 / 0 / +0.05 / 0 / - |
| Follow / Support me | all | 0 / -0.1 / -0.2 / 0 / 0 / 0 / -0.1 |
| Defend | HOLD, DEFEND, CASUALTY (BREAK only as a request) | - / - / - / +0.3 / -0.15 x nerve / +0.15 / - |
| Support by fire | HOLD (suppress task), CASUALTY | - / - / - / 0 / -0.05 / +0.2 / - |
| Attack (execute) | all | +0.1 / +0.15 / +0.15 / -0.1 / -0.1 / 0 / 0 |
| Regroup / Extract | HOLD, BREAK_CONTACT, CASUALTY | - / - / - / 0 / +0.15 / 0 / - |
| Risk Press on / Careful | | break -0.1 / +0.1 |

A "hold" term is new in `score()` (`+ d.get("hold", 0.0)`); Defend and SBF need one. Biases go
through the same `doctrine()` seam the A3-07 doctrine weights are meant to use, so there is no
second weight system.

A hero squad never leaves its order on its own. A deviation (break contact on a Defend, go help
another squad on a Move) is a **request** to the commander. Unanswered within its timeout (20 s at
average leadership), the hero decides from his traits and the order's risk ("Viper 3, no answer,
breaking contact"). A broken squad may still fall back, as `SquadAI.broken()` allows today.

### 4.3 Nothing fails silently (S0758)

- **Held up:** less than 3 m of progress toward the current leg in `STUCK_S` (30 s) out of
  contact: "Hawk 2, held up at 041 053, finding a way round". It tries a detour off the straight
  line (a different side each time, the stuck-bots lesson), then the nav path again, then an
  offset point.
- **Unable:** after `UNABLE_S` (90 s) the order fails: "Hawk 2, unable: no route to 041 053.
  Holding." The next queued order starts.
- Every planner phase has a timeout and a fallback, and every failure has a `why` on the panel, in
  the net log and in the session log (`[hc]` lines in the `[tactics]` style).
- Order points are clamped into `map_area().grow(-80)`.
- The soak bot's catch-up teleport stays test-only: a player would see it.

## 5. Execution on the host

```
HighCommand (one per level)       registry, order intake, go codes, requests, company net,
   |                              company enemy picture, mutual support (Phase 4), the view
SquadOrders (one per hero Squad)  queue and phase machines, tasking (anchor, leash, sector,
   |                              rally), SBF spots, CE, watchdogs
SquadTactics (existing)           contact drill scoring, masked and biased by the order
   |
SquadAI (existing)                hero: Intent.LEAD; men FOLLOW the hero as today
```

### 5.1 HighCommand (new `scripts/campaign/high_command.gd`, Node)

Installed by `MapNodes.install` next to MapMarkers and Extraction, so the same path exists on every
peer; found with `MapNodes.high_command(from)`.

- **Host:** the registry `id -> {callsign, hero, squad, members, orders, queue, status}`; order
  intake and validation (section 7); go codes and requests; the company net (section 6); spawning
  through `server_spawn_squad(def, at)`, which creates a `Squad` (`HC_<id>`, friendly, `hc_id`) the
  way `EnemyResponse._new_squad` does and spawns members with the body set-up
  `server_spawn_roster_squadmate` uses (identity, own gear, `roster_id`, `ai_stats`), then
  `brain.squad` and buddies. Called at deployment start.
- **Company enemy picture** (from the AI-first design): a squad whose hero (or whoever has his
  radio) is up passes fresh contacts to the other squads' `known` as heard, after `NET_DELAY_S`
  (2-5 s, shorter with better leadership), and to `MapMarkers.server_report_enemy` as intel. A
  squad whose hero is down and whose radio nobody has picked up **goes dark**: no reports, no shared
  contacts, the icon greys. Losing an officer costs our side too, mirroring
  `EnemyResponse.coordination()`.
- **Clients:** only the replicated view and the net log.

### 5.2 SquadOrders (new `scripts/ai/squad_orders.gd`, RefCounted)

One per hero Squad, like `SquadTactics`, ticked from `Squad._physics_process` every `THINK_S`
(0.5 s; the planner re-plans every 3 s or on triggers) just before `tactics.think`. One small
handler per verb maps section 3.2 onto existing calls, always with `from` = the hero. Its pure
maths (spot scoring, frontage split, CE) is static, like `SquadTactics.score`, so tests stage it.

- **Tasking** (the AI-first seam on Squad): `squad.tasking = {anchor, leash_m, sector: [left_dir,
  right_dir], rally, axis}`. When set, it replaces the "follow the lead within `FOLLOW_LEASH_M`"
  constraint: `_leashed()` uses the anchor and leash, `flank_route()` rejects flank points outside
  the sector, and `fall_back_point()` / BREAK_CONTACT head for the rally point. Empty tasking means
  exactly today's behaviour (a regression test compares `[tactics]` lines on a seeded run).
- **Sectors:** every Attack, Defend or Move order gets a corridor around its axis, half-width
  max(30 m, frontage / 2). HighCommand offsets a lane that overlaps another squad's or the player
  squad's bubble, and warns when it can't ("Viper and Rook lanes cross: Rook shifted right").
- **Defend frontage** (two points, Phase 2): split into one sector per buddy pair; each pair takes
  cover or a building port near its sector midpoint with a watch on its bearing; the autorifleman
  takes the likeliest approach. At 15-25 m per man; too wide and the hero says "frontage too wide,
  covering the centre".
- **Resting order** (G10): men whose order flipped to HOLD because an ordered tactic ended get
  FOLLOW back when the phase wants them free; Defend and SBF keep HOLD on purpose.
- **Straggler control:** the hero halts while any man up is more than 25 m from his slot, or a
  casualty is being moved.
- **Combat effectiveness:** `CE = clamp(up / size) x 0.5 + ammo x 0.25 + morale x 0.25 -
  0.1 x urgent casualties`, from numbers `assess()` already produces. GREEN >= 0.7, AMBER >= 0.45,
  RED below. RED aborts attack phases: consolidate and "Hawk 2 is red, request orders" (a
  high-initiative hero falls back to the last rally point instead). CE is in the replicated view.

### 5.3 The hero leads (small edits in squad_ai.gd and tactics.gd)

- **`Intent.LEAD`.** In the friendly branch of `_choose_intent`, `squad.hero == body` scores LEAD in
  place of FOLLOW. Out of contact he walks the planner's current leg at the squad's pace; on a halt
  he stops and faces the threat axis from a halt spot; in contact he fights around the tasking
  anchor. His order stays FOLLOW, so `_tactic()` still hands him evaluator tasks. Status text:
  "Leading", "Waiting for the squad".
- **The hero stays in the base of fire:** `elements()` keeps him in the base, as it keeps the
  player lead today; `_call_option()`'s speaker is the hero.
- **Leader aura:** `MORALE_LEADER` and its range scale with the hero's leadership (a morale floor
  for men within 30 m).
- **Succession:** when the hero goes down, the other fire team's leader, else the man with the best
  nerve then missions, becomes `hero` and `leader` and takes the current order, with plan quality
  scaled (x 0.7 of his own skill). "Hawk 2, Mercer is down. Okafor has command." Each man takes a
  morale hit. The radio passes when the new leader picks it up; until then the squad is dark. A
  recovered hero takes command back. After the contract the company must promote a new leader or
  the detachment disbands into the pool (Phase 3).

### 5.4 Support by fire and danger close

- **SBF spot** (when the player gives only a rough position, or Attack sets its base): on a ring
  80-250 m from the target and within `Doctrine.engage_m`; line of sight at `Squad.SIGHT_HEIGHTS`;
  prefer cover and height; at least 45 degrees off the assault axis so the assault never walks into
  its own fire; the fire lane clear of every current and planned friendly position out to target +
  60 m. No spot clears: "Hawk 2, can't fire, friendlies in the lane", and it tries the next.
- **`SquadOrders.safe_to_fire(shooter, target, friendlies)`** (static): no suppression with any
  friendly (players, the player squad, other hero squads) inside a 10-degree fan around the shot
  line out to the target + 30 m. The suppress task asks it before each burst; `_friendly_in_line`
  stays as the last guard on each shot. This is the single most important safety rule once several
  squads fight in one place, and a test asserts zero blue-on-blue damage.
- **Lift and shift:** when the supported element comes within 40 m of the target, or any friendly
  within `DANGER_CLOSE_M` (35 m) of the target area, fire shifts to the depth or flank of the
  objective along the axis, or lifts ("check fire, friendlies on target").
- **Ammo:** below two magazines a man the squad suppresses on call only and reports "ammo amber";
  below `AMMO_LOW` it lifts and reports "ammo red".

### 5.5 Knowledge fairness

Routes, attack positions, SBF spots and avoid areas use only the side's intel markers, each squad's
`known`, the contract's `known_enemies` and terrain: never `EnemyResponse` internals or true
soldier lists. That is how the AI bar (beat Arma 3 Veteran with LAMBS and VCOM) is met fairly. A
test checks the planner's inputs.

### 5.6 Streaming and performance

- Each hero leader joins `stream_focus()` on the host (G8). Garrison spawns cost CPU, so streaming
  stays staggered.
- Each hero squad adds 4 (MVP) to 8 brains on a machine that is already loaded, on top of hot-zone
  hostiles (`EnemyResponse.MAX_ALIVE` 40, waves, garrisons). Mitigations: one squad of 4 first, the
  friendly AI budget at prep, staggered think timers, and an **AI LOD** (Phase 3): with no player
  within 350-400 m and no contact, a squad scans every 1.0 s, thinks every 1.5 s and plans every
  4 s. `FrameCost` gets an `hc` key; `perf_timing` gets an 8 + 8 + 8 friendly AI case against the
  B0734 baseline.
- **Travel LOD** (Phase 4): a squad far from every player and not in contact moves as a token along
  its route and re-materializes inside the stream radius. Fights are always real.

## 6. The company net (reports)

`HighCommand.radio(squad, kind, text, pos := null)` on the host:

- appends to a replicated net log `{t, squad, kind, text, pos}` (last 50 lines);
- shows a subtitle to the side's players through `Callouts._show` with the speaker "Hawk 2 (net)"
  in its own colour, so net lines read apart from shouted callouts;
- writes `SessionLog.note("[hc] ...")` for playtest review.

**Rate limits:** one line per squad per `NET_GAP_S` (3 s), a queue of 4, priority casualty >
request > unable > contact > set > moving. A repeated contact report within 60 s and 40 m is
dropped. The net gets at most one tactics summary per squad per `TACTIC_REPORT_GAP_S` ("Hawk 2, in
contact, suppressing and flanking left"); shouts stay within voice range (G5).

| Trigger | Example | Side effect | Phase |
|---|---|---|---|
| Accepted / refused | "Hawk 2, copy, from Player 2: moving to 041 053." / "Hawk 2, unable: no route." | Order active / failed with `why` | 1 |
| Set, done | "Hawk 2, set at 041 053." / "at the LZ" | Panel state | 1 |
| First fresh cluster | "Viper 3, contact: 6 enemy, north, 180 m, engaging." | Intel marker "Viper 3: 6x"; shared to other squads | 1 |
| Man down | "Hawk 2, man down, one urgent." | Casualty count | 1 |
| Succession | "Hawk 2, Mercer is down. Okafor has command." | Leader changes | 1 |
| Held up | "Hawk 2, held up at 041 053, finding a way round." | Replan | 1 |
| Sitrep (asked, at order end, idle every `SITREP_S`) | "Hawk 2, green, 4 up, ammo amber, holding at 041 053." | Panel refresh | 1 |
| CE change | "Hawk 2 is red, request orders." | Attack phases abort | 2 |
| Danger close | "Hawk 2, check fire, friendlies on target." | Lift or shift | 2 |
| Request | "Viper 3, amber: request to break contact." | Pending request | 2 |
| Initiative offer | "Hawk 2 can support Viper 3, approve?" | One key turns it into an SBF order | 4 |
| Going dark | (silence) | Icon grey, "no comms 2 min" | 2 |

Grids from `MapGrid.grid_ref` at 100 m; a hero with high leadership gives finer grids and exact
counts, a low one "several". Ammo and morale are bands, not numbers, in keeping with the minimal
HUD. Clicking a log line centres the map on its grid.

## 7. Network and authority (host-authoritative co-op)

**RPCs on HighCommand**, shaped like MapMarkers: requests are `@rpc("any_peer", "call_local",
"reliable")` to the host; validation lives in a pure static `HcOrder.clean()` so tests and the soak
bot use the same rules.

| RPC | Host checks | Effect |
|---|---|---|
| `request_order(order, append)` | Sender owns a player Soldier that is up; has command authority; squad exists, is deployed and not dark; verb whitelisted; points finite, inside `map_area()`, through `Soldier.usable_point`; at most 16 route points and 8 queued; every ref re-resolved on the host; at most 4 orders a second per peer | Order added; "copy" or "unable" on the net; a refusal reason to the sender via `_client_message` |
| `request_cancel(squad, id)` | Authority | Cancelled |
| `request_go(code)` | Authority | Waiting orders with that code go active |
| `request_answer(req_id, yes)` | Authority; still pending | Resolved |
| `request_command()` | Setting | Commander token moves; "Player 2 has command" |

The in-world Squads mode may instead send `hc:` commands through `_server_squad_command`, forwarded
to HighCommand the way `support:` goes to Supports (two lines in soldier.gd).

**Replication.**
- Hero squad men are ordinary Soldiers: positions replicate as now, and `Soldier.hc_id` with them.
- `_client_order(dict)` reliable to all on every change, and a compact **status** view on change at
  most 2 Hz (unreliable_ordered): per squad `{id, callsign, hero_name, up, total, wounded, ce,
  ammo_band, morale_band, dark, order: {id, verb, points, state, phase, go}, queue, tactic,
  last_line}`. Around 200 B a squad.
- Late joiners and rejoiners get `_client_snapshot(view, orders, net_log)` on `Net.peer_joined`.
- **Latency UX:** the client draws a dotted ghost line until the host's ack, then solid, or red with
  the reason. 150-300 ms over the soak's lossy relay then feels responsive.
- Clients never run SquadOrders or SquadTactics.

**Who commands** (both top designs agree): one **commander token**, the host by default, stored in
the deployment record by `BaseHub.player_key` so it survives a reconnect. It can be handed over at
the FOB ready-up or from the map panel; a host setting chooses "anyone may take it" or "host
approves". Other players see every squad read-only and can **Request support** (a ping to the
commander). If the commander leaves or stays down past bleed-out, the token passes to the next
player by key, with a net line. Every order carries `by`, and the net names who gave it. The HC
panel always shows "Commander: Player 2", so clients never think orders are broken. The player
squad keeps today's rule (anyone orders it). Phase 3 adds per-squad **delegation** to a co-op
player.

**Campaign data:** promote, form, assign and disband are host-only BaseHub requests, like
"release"; picks at prep follow "pick". It all travels in `BaseHub.view`.

**Determinism:** HighCommand ticks from `Soldier._now()` / the Alert clock, so tests can advance it
(as with `EnemyResponse.server_tick`). It never reads files; the soak's phase.json stays a harness.

## 8. Campaign: heroes on the books

From the campaign-first design: heroes are earned from the Captain's own roster, and squads are
company assets that are hired, paid, kitted, risked and grown at the FOB. Losing Sgt Okafor's squad
on a rated-5 hot zone costs a veteran, three trained hands, their gear and a recovery contract.

**Phase 1 (MVP, no economy):** the hero and his 3 men are available roster members picked at prep.
They spawn like `server_spawn_roster_squadmate` with their own identity, gear and `ai_stats`, go
into `dep.spawned`, and `resolve()` settles them already. History lines are written. No promotion,
fee, wage change or traits yet.

**Phase 3 data** (JSON-safe in the roster section, lazily defaulted the way `ensure_identity` fills
older saves, so no `SAVE_VERSION` bump):

- `member["hero"]` (only on promoted members): `{promoted_day, rank (1 team leader, 2 squad
  leader), command: {leadership, tactics, initiative} (each 0..1), traits: [ids], ops, kills_led,
  lost_led, detachment: "d01"}`. Command skills sit outside `Roster.SKILLS`, so existing wages
  don't shift.
- `roster["detachments"]`: id -> `{id, callsign: "2-1", leader: mid, members: [mids], formation,
  doctrine, standing: {roe, mode}, formed_day, cohesion}`. `Campaign.SHAPES["roster"]` gains the
  key.
- `roster["deployment"]` gains `detachments`, `det_spawned` (mid -> det id), `det_orders` (the last
  order each, for the debrief) and `commander`.

**New `scripts/campaign/heroes.gd`** (`class_name Heroes`, pure statics on the roster section, like
`Roster`, so host, tests and UI share one set of rules):

- **Eligibility:** READY and either team_leader role with missions >= 4, or missions >= 8 and nerve
  >= 0.6. `promote(data, mid, day)` charges a fee (10 days of wage), raises the wage 25%, makes the
  hero block and a detachment, and writes "Day 14: Promoted to Squad Leader". `demote()`.
- **Detachments:** `assign`, `unassign`, `detachment_of`, `strength` (ready / total), `disband`.
  A member is in at most one detachment; the dead and MIA can't be assigned; detachment members
  never fill the player squad's 8 slots (`auto_squad()` and `member_for_slot()` skip them via
  `in_detachment()`). Size 4 (one fire team), 8 at rank 2 on `Roles.layout`.
- **`command_stats(hero)`** gives what the runtime uses: planner cadence (1.5-3.0 s), score noise
  (±0.15 x (1 - tactics), so a poor leader picks worse options), morale floor, `leash_m` from
  initiative, request timeout (10-30 s), report delay and grid precision. Starting skills come from
  nerve, xp and role; `after_op(hero, report, rng, day)` grows them like `Roster.after_mission`,
  scaled by rating and success; cohesion +0.1 a deployment, -0.15 per man lost or replaced.
- **Traits** (data in data/heroes.json, loaded like Doctrine with `_notes` and `_pending`): earned
  from history, 6-8 of them, visible on the card. Each is a few option biases plus at most one
  planner or stat tweak, never shooting:

  | Trait | Earned by | Effect |
  |---|---|---|
  | Steady | no man lost in 3 ops | +0.08 discipline for his men; aura x1.5; denies break contact by default |
  | Hard to kill | wounded 3 times and came back | morale floor up; slower CE abort |
  | Aggressive | many Attack orders completed | assault +0.08, flank +0.05, break -0.1; shorter standoff |
  | Cautious | broke contact and got everyone out | break +0.06, hold +0.05; bounds the last 150 m; asks to break sooner |
  | Methodical | many Defend / SBF orders set | Attack always sets a base of fire first; longer standoff |
  | Medic's eye | medical above 0.7 | casualty +0.08; sets the CCP at the first casualty |
  | Good on the radio | many contact reports | finer grids, exact counts, net delay halved |
  | Improviser / By-the-book | initiative high / low | adapts a stale order ("objective's empty, pushing to the next building") / always asks |

- **Contracts:** `ContractsGen` adds public `squads_max` from the briefed rating (setting
  `difficulty_squads` = [0, 0, 0, 0, 1, 2], hot zone +1, cap 3). Squads beyond it can be brought at
  the company's cost.
- **Money:** each authorized squad is an `hc_squad` charge through `Economy.server_pay_support`
  (contract support budget first, then cash; 5000 Proposed in `data/prices.json` "supports"); extra
  squads are cash only. Members are paid their own wages.
- **Hiring:** 6 candidates every 3 days can't staff three squads. A rare ready-made SL from the top
  experience tier, and (Proposed) a "fire team for hire" bundle as the safety valve.
- **Resolve:** every detachment member goes through `resolve()` (extracted, MIA, KIA, wounds,
  sit-out days); `Heroes.after_op` runs for each hero deployed, with "Led 2-1 at Outpost 3: held the
  bridge, 1 KIA". A hero MIA creates a recovery contract exactly as today. A squad that extracts on
  its own has its outcomes recorded then (`mark_hc_out`) and despawns ("Hawk 2 is out").

**Phase 4, the company campaign:** a detachment sent alone on a low-rated contract is auto-resolved
off-screen from its skills against the true rating (income, wound and MIA risk); "company op"
contracts built for three squads; bonds and rivalries between heroes.

## 9. Build now so the co-op fixes stay reusable

The co-op work in flight (the soak bot's player brain, the stuck-bots detour, the extraction
leave-behind warning, FOB ready-up, own-kit respawn) already holds most of what hero squads need.
These keep it reusable instead of rewritten. None needs a gameplay decision; each is a small branch
after its owner's branch lands (the soak harness belongs to the coopsoak agent, extraction to
coop-extract, ready-up to coop-ready, squad.gd and squad_ai.gd to coop-respawn). Until then they go
to the owners as F-tasks in docs/audits/followups.md.

1. **Lift the soak bot's follow brain into game code: `FollowBrain`** (new
   scripts/ai/follow_brain.gd, pure). Inputs: my position, the leader's position, yaw and vehicle,
   whether I'm in contact, the active extraction points, an offset table, near and far distances.
   Output: `{kind: walk|hold|board|exit|none, point, speed}`. It holds the decisions of
   `_follow_tick`, `_follow_spot` and `_wedge_spot` (a loose spot off the leader turned his way; hold
   and fight in contact; board and leave his vehicle with him; get inside the point he stands in).
   `coop_soak.gd` calls it with its RPC actuator; hero squads call it with SquadAI as the actuator
   and bigger offsets (Follow 30-60 m, Support me 60-120 m). One brain, tested two ways.
2. **Lift the stuck watch: `ProgressWatch`** (new scripts/ai/progress_watch.gd, pure). Feed it
   position, goal and time; it reports headway, "wedged", a detour bearing (a different side each
   time), "held up" and "unable", with a log line. It holds `_stuck_note` and the stuck-bots
   branch's wedge tracking. The soak uses it (its catch-up teleport stays in the test), SquadOrders
   uses it for 4.3, and later player-squad followers can use it for the same S0758 failure in real
   AI.
3. **Lift the medic and give-up decisions** (`_treat_loop`, `_casevac_tick`, `_give_up_tick`) as
   pure "who needs care next, when to give up" helpers next to the existing casualty care, so hero
   squads and the soak share one rule. No reflex body-hauling: carrying stays a chosen, announced
   act (Captain, 2026-10-14).
4. **Make dead ground knowledge-fair at the seam.** When `_dead_ground` / `_hidden_fraction` are
   lifted into `SquadOrders` statics, they take the threat points as an argument: the soak passes
   true posts, the game passes intel markers and `known`.
5. **Extraction by group.** Once `fix/coop-extraction` is on dev, give Extraction a group query,
   `missing_of(point, soldiers)` beside `missing_at`, and let the leave-behind warning list extra
   groups. The soak's `_extract_with_human` and hero squads then both use the game's rule.
6. **One squad marker and predicate** (Phase 0, after coop-respawn lands): `Soldier.hc_id`,
   `Squad.members()` scoped to its brains, `Squad.is_squadmate(s)`. This also hardens recovery
   targets and AAV crews today.
7. **Command through the game's own seam.** Soak bots give squad orders through
   `_server_squad_command` (as the command menu does) and later `HighCommand.request_order`, so
   `coop_soak --hc` exercises the real validated path over the lossy relay.
8. **Group records in the soak recorder.** The recorder and `coop_soak_report.py` key positions,
   state and stuck notes by group (`hc_id`, "" for the player squad), so `--hc` needs no new report
   format.

## 10. UI

- **Map** (`map_view.gd` gets narrow hooks; drawing and command-mode input live in a new
  `scripts/ui/map_command.gd`, `MapCommandLayer`, so the view barely grows):
  - **Squad icon:** a friendly unit frame inspired by APP-6 (infantry cross, callsign "HAWK 2",
    strength "4/4", CE pip) at the hero, or the members' centroid if he's down. State glyphs:
    moving (heading arrow), set (bar), contact (red outline pulsing), casualty (cross), pending
    request (amber "!"), dark (grey dashed, "?"). Selected: yellow outline. Members as dots at close
    zoom; hidden behind the frame zoomed out.
  - **Order graphics:** current order solid, queued dashed, unacknowledged dotted ghost; move as a
    line with arrowheads and numbered waypoints; defend as a facing arc (a hatched frontage in
    Phase 2); attack as a red arrow to an objective circle; SBF as a fan to the target; lanes as
    faint bands; go-gated orders tagged A / B / C. A failed order flashes red with its `why`.
- **HC panel** (new `scripts/ui/map_hc_panel.gd`, modelled on `MapExtractionPanel`): a card per
  squad (callsign, hero, strength, wounded, CE, ammo, order, phase, `why`, last 3 lines; Report /
  Cancel / Regroup buttons); requests with Approve / Deny and a timeout bar; go-code buttons with
  waiting counts; "Commander: <name>"; the net log.
- **Command menu Squads mode** (Phase 2, `command_menu.gd`): an `HC_MENU` in the existing entry
  format with a `squads_mode` flag; F1-F4 pick squads, entries are `"point": true` at the
  crosshair; sent to HighCommand instead of `_server_squad_command`.
- **HUD:** company net subtitles in their own colour; a squads strip shown only while hero squads
  are deployed ("HAWK 2 ● green Set | VIPER 3 ● amber Contact"); request prompts with the keys.
- **Briefing:** hero squad insertion markers (Phase 1); drag placement and H-hour orders (Phase 2).
- **FOB** (`base_ui.gd`): the Hero squads block on "Squad & deploy" (Phase 1); a **Squads** page
  (Phase 3): detachment cards (callsign, hero name tape and rank, command skills as bars, traits as
  tags with tooltips, members with role, skills and status, strength, wages), Promote (eligible only,
  showing the fee), Assign / Unassign (warns when the team has no medic), Disband; deploy checkboxes
  capped by `squads_max` with the reason a squad can't go ("Doc recovering").
- **Extraction panel and debrief:** hero squads in the leave-behind warning ("2-1: 3 of 4 not at
  extraction, will be left: MIA"); a debrief section each.

## 11. Phases

Each step lands on its own work branch and reaches dev only through the CI gate. Phase 0 and the
section 9 lifts can go when their owners' branches have landed. Phases 1 and up are sequenced after
the movement and performance phase 1, per the current priorities.

**Phase 0: groundwork, no gameplay change.**
- G1 alone first, with a squad_test case: two friendly Squads give disjoint `members()`.
- Then G2-G12, `Soldier.hc_id`, `Squad.hc_id` / `hero` / `is_player_squad()` / `is_squadmate()`,
  `CompoundLevel.squad_of()`, and an empty `tasking` that changes nothing.
- A test hook (and a dev-tools entry) that spawns an extra friendly Squad of 4.
- Acceptance: the player squad's orders, rebalance, HUD, F-keys and extraction ignore the extra
  squad; its own SquadTactics fights from its own picture; every existing suite is unchanged.

**Build-now lifts (section 9).** `FollowBrain`, `ProgressWatch`, care and give-up helpers, the
knowledge-fair dead-ground seam, extraction by group, soak commands through the game's RPCs, group
records. Acceptance: the soak's behaviour is unchanged in a short replay, and the pure pieces have
unit tests.

**Phase 1: MVP, one named hero, one fire team.**
- One hero squad of 4 roster members (hero plus 3) picked at prep, on contracts rated 4 and up,
  plus the dev-tools spawn. No promotion page, traits or cost yet.
- HighCommand, HcOrder, SquadOrders with Move (one point), Hold, Defend, Follow / Support me
  (station keeping), Regroup, Extract, Posture, Report.
- `Intent.LEAD`, the resting-order rule, the option mask and biases, lanes, `ProgressWatch`,
  succession.
- Reports: copy, unable, set, done, contact (plus intel marker), man down, succession, held up,
  sitrep, at the LZ. Cross-squad contact sharing.
- Map Command mode with click-select and the right-click menu; the HC panel; ghost lines. The host
  is the only commander.
- Extraction warning, MIA, outcomes, history and debrief lines.
- Acceptance: a headless test drives every MVP order to `done` or a clean `failed` with a reason
  before any UI polish; a client can order through the RPC path; nothing stalls silently. Enough
  for the Captain to try a rated-4 contract with Hawk's team holding a flank.

**Phase 2: real high command.**
- Attack (approach, SBF set, assault, lift and shift, consolidate, CE abort), Support by fire with
  `safe_to_fire` and danger close, Bound, Fall back, Defend frontage.
- Queues, routes, go codes, H-hour orders and briefing placement; risk levels; requests (break
  contact, reinforce, CASEVAC) with timeouts.
- CE colours, going dark, the company enemy picture with net delay.
- Commander handover; command menu Squads mode; the HUD strip; `squads_max` up to 2.

**Phase 3: campaign heroes and several squads.**
- `Heroes`, detachments, the Squads page, promotion, command skills and traits wired into
  SquadTactics (biases, noise, leash, morale floor), wages, cohesion, history.
- Up to 3 squads by rating and zone; the support-budget charge; the friendly AI budget; 8-man
  detachments on `Roles.layout` with their own casualty care once the coop-respawn work has landed.
- The AI LOD; per-squad delegation; initiative requests; resupply requests; field promotion carried
  into the roster; hiring of SLs and fire teams.

**Phase 4: coordination and scale.**
- A SupportBroker graph (who covers whom; "Hawk 2 can support Viper 3, approve?", never automatic),
  leapfrog between squads, `after` sequencing, standing "Support squad 1".
- Fog mode (squads at last reported position), a jammer cutting high command, squads boarding AAVs
  and helicopters through `FollowBrain`.
- Travel LOD; auto-resolved detachment contracts; company ops.
- A co-op player leading or joining a hero squad (the player-scalable rule at squad level).
- Point the same SquadOrders planner at EnemyResponse hunters, so the enemy plans at squad level
  too: a large step toward beating Veteran + LAMBS + VCOM.

## 12. Tests

Headless only, own worktree and port, R#### logs in B:\Contractor-test-logs. Every suite stays
under 5 minutes, runs in the background with a hang watch, and a failing suite is rerun alone once
before blaming code. Most logic sits in pure classes so in-level scenarios stay few and short.

- **Pure, fast:**
  - `HcOrder.clean` rejects unknown verbs, NaN and off-map points, a 17-point route, a ninth queued
    order, a non-commander sender.
  - Lane clamping keeps flank and fall-back points inside the sector; the SBF spot search never
    picks a lane that crosses a friendly; `safe_to_fire` inside and outside the fan and beyond the
    target; frontage split into pair sectors; CE colours from staged `assess()` dictionaries.
  - `SquadTactics.score` with the mask and biases: Defend picks DEFEND where the unbiased score
    flanks; Attack makes ASSAULT or SUPPRESS_FLANK win; Extract makes BREAK_CONTACT win. With empty
    tasking, seeded `[tactics]` lines match today's.
  - `FollowBrain` and `ProgressWatch` on staged inputs (station, contact hold, boarding, wedged,
    detour, held up, unable).
  - The planner's inputs are intel and `known` only.
  - New `tests/heroes_test.gd` (Phase 3): eligibility, promotion fee, wage and history, one
    detachment per member, dead and MIA can't be assigned, trait earning from synthetic histories,
    growth capped at `SKILL_MAX`, a JSON round trip, an old save without detachments loads.
- **New `tests/high_command_test.gd`** (compound level, host, like squad_test), a squad of 4
  spawned 30 m from the player:
  - Phase 0 scoping: `members()`, `CommandMenu.roster()`, `MapNodes.squad_ai` and Extraction
    `required()` leave it out; `rebalance_squad()` keeps it; its `assess().up` is 4; a shout 200 m
    away doesn't reach the player; its leader is in `stream_focus()`; `squad_for(&"friendly")` is
    still the player squad; `give_order` on squad 1 doesn't move squad 2.
  - Validation: each bad order and sender (AI, downed, non-commander, unknown squad, flood) is
    refused with a reason.
  - Move: arrive within the timeout, men within `REGROUP_M`; the net log shows copy, set, done.
  - Stuck: an unreachable point gives "held up" then `failed` with a `why`; the next order starts.
  - Defend near a building: garrison tactics are used and the men stay on HOLD.
  - Contact: an intel marker with "Hawk 2" within 5 s, not repeated within the gap, and another
    squad's `known` gets it after `NET_DELAY_S`.
  - Succession: kill the hero; the leader changes, a net line, the order continues.
  - Extract: all members inside, and Extraction counts them; they never confirm.
  - Phase 2: a go code holds an order `waiting`; SBF plus an assault reaches the objective with
    zero blue-on-blue damage; a friendly within `DANGER_CLOSE_M` lifts fire; RED CE aborts; a
    request timeout resolves by trait.
- **base_test / contracts_test:** `squads_max` by rating and in `public_view`; the deployment
  records the squads; the charge comes from the support budget then cash; outcomes extracted / MIA /
  KIA and the hero's "led" line; `auto_squad` never returns detachment members;
  `server_revert_deployment` restores them.
- **map_test:** command mode selects on click; the context menu per cursor target; drawing with 0
  and 3 squads; marker editing outside command mode unchanged.
- **net_test:** a client order is applied and mirrored with "copy"; a non-commander is refused with
  a message; a late joiner's snapshot holds orders and the net log; `Soldier.hc_id` replicates.
- **loop_test:** one contract end to end with one hero squad, through the debrief.
- **coop_soak `--hc`** (proposed to the soak owner as an F-task, not edited): the host bot orders a
  hero squad Move, Defend, Extract over the lossy relay; checks ack within 3 s, every order ends
  `done` or `failed` with a reason, no squad stuck over 120 s, no friendly fire between squads, the
  squad present (never confirming) at extraction.
- **perf_timing:** 8 + 8 + 8 friendly AI plus hostiles against the frame-cost budget and B0734.

## 13. Risks

1. **Scattered one-squad assumptions** leak orders, delete hero squad men, stall extraction or
   garble comms. G1 alone would silently corrupt F-key selection. Mitigation: Phase 0 first, G1 on
   its own, one marker and predicate, and a grep audit of `faction == &"friendly"`, `squad_slot >=
   0`, `MapNodes.squad_ai` and `squad_for`.
2. **Weak execution makes high command feel bad.** Mitigation: short phase machines over tested
   primitives, a reason for every failure, `ProgressWatch`, requests that keep the player in the
   loop, and the MVP proven headless before UI polish. The soak brain was tuned for 2-4 bots behind
   a human; as a leader it must meet the AI bar, so it reuses SquadTactics rather than a second
   tactics stack.
3. **An AI leader in follow logic built for a human lead** (leash, halt spots, `fall_back_point`).
   Mitigation: `Intent.LEAD`, tasking, the hero in the base of fire, the resting-order rule.
4. **Host CPU and bandwidth.** Mitigation: one squad of 4 first, the AI budget, the AI LOD,
   `FrameCost` and `perf_timing`, staggered streaming, later the travel LOD.
5. **Long routes on 2-4 km zones** (nav chunking, the zone edge, unbuilt navmesh far from players).
   Mitigation: per-leg paths, points clamped inside the map, `stream_focus`, the watchdog.
6. **Friendly fire between squads.** Mitigation: sectors, the SBF lane rule, `safe_to_fire`, lift
   and shift, `_friendly_in_line`, a zero-damage test.
7. **Radio and subtitle overload** with three squads. Mitigation: per-squad gaps, de-duplication,
   priorities, voice range for shouts, the full log on the panel.
8. **Co-op command contention.** Mitigation: one commander token, "Commander: X" always shown, the
   author named on every order, Request support for everyone else.
9. **Economy and roster inflation** (wages for 16-24 members, MIA cascades). Mitigation: rank
   wages, the support charge, numbers in data files marked Proposed; tune so a mid-campaign company
   can field one detachment.
10. **Losses unseen.** Deep medical means far-off squads can bleed out unseen. Mitigation: prompt
    casualty reports, the Regroup verb, squad-level casualty care in Phase 3.
11. **Agency:** hero squads could win the contract for the player. Mitigation: they support by
    default (SBF, flanks), human-only objectives stay human-only, credit is the Captain's call.
12. **Ownership and timing:** squad.gd, squad_ai.gd and callouts.gd (coop-respawn), extraction and
    deployment (coop-extract, coop-ready), the soak harness (coopsoak). Mitigation: Phase 0 and the
    lifts wait for those branches; F-tasks meanwhile; edits stay at the listed seams.
13. **Scope** competes with bug fixes and the movement and performance phase. Phase 0 and the lifts
    are cheap; the rest is sequenced after.

## 14. Open questions for the Captain

Each has a recommendation; the Captain's answer replaces it.

1. **Who commands in co-op:** host only, a commander token anyone can take, or host-approves?
   *Recommended: a token held by the host by default, handover at ready-up or the map panel.*
2. **Who are the men?** Roster members from the MVP (wages, permadeath, MIA), or per-contract
   attached men with no persistence? *Recommended: roster members from the MVP, because named
   squad leaders are the point and spawning them already works.*
3. **Where do heroes come from?** Promoted veterans only, or also SLs hired at higher reputation?
   *Recommended: promotion first, a rare SL and fire-team offers on the hiring board in Phase 3.*
4. **How many squads, and who pays?** Rated 4 gives 1, rated 5 gives 2, hot +1, cap 3; extra at the
   company's cost; does the client's support budget pay for authorized ones? *Recommended: as
   written.*
5. **Squad size:** 4 in the MVP and 8 at rank 2, or 8 from the start? *Recommended: 4 then 8.*
6. **Disobedience:** may a hero ever disobey by trait, or only request and then decide after the
   timeout? *Recommended: request, then decide; never ignore a fresh order.*
7. **Live squad positions or fog** by default on hard contracts? *Recommended: live in the MVP;
   fog as a Phase 4 setting.*
8. **Does high command need a radio** (commander and hero)? *Recommended: no in the MVP; going dark
   when the hero falls from Phase 2.*
9. **Squads mode in the world menu:** MVP or Phase 2? *Recommended: Phase 2; the map is enough to
   prove it.*
10. **A squad left in the field:** straight to MIA, or an abstract exfil roll? *Recommended: MIA in
    the MVP, decide after playtests.*
11. **Objective credit:** full, a pay share, or none when a hero squad clears a target?
12. **Traits:** which, and do flaws (Glory hound, Expensive) come with them?
13. **Callsigns and keys:** the hero's own ("Hawk 2") or company numbers ("2-1" with the player
    squad as "1"); the `high_command` default key and the approve and deny keys.
14. **Later:** may a co-op player lead or join a hero squad?

## Sources

- The three judged designs (Command-first, Campaign-first, AI-first), 2026-10-14, and the judges'
  notes.
- dev `fc98665`: scripts/ai/squad.gd, tactics.gd, squad_ai.gd, doctrine.gd, roles.gd;
  scripts/ui/command_menu.gd, map_view.gd, map_screen.gd, map_markers.gd, map_nodes.gd, map_grid.gd,
  map_extraction_panel.gd, callouts.gd; scripts/actors/soldier.gd; scripts/world/compound_level.gd,
  zone_level.gd; scripts/campaign/roster.gd, roster_deployment.gd, base_hub.gd, hiring.gd,
  contracts_gen.gd, economy.gd, enemy_response.gd, reinforcements.gd, extraction.gd, briefing.gd,
  radio_chatter.gd; data/prices.json; docs/squad_design.md.
- tests/coop_soak.gd on `test/coop-soak` `33d3e87`, `test/coop-fakehuman-checks` `5858854` and
  `test/coop-soak-stuckbots` `10a41c3`.
- `fix/coop-extraction` `906053c`, `feat/fob-ready-up` `8ebcdc3`, `fix/respawn-own-kit` `4421481`
  (file lists and doc comments only).
