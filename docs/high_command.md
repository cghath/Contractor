# High command: hero-led squads (proposal)

**Status: Proposed** (2026-10-14). For the Captain to approve, change or turn down; nothing here is
built. Every number is Proposed and tunable. Checked against dev `fc98665` (B0734), the co-op soak
branch `test/coop-soak` (`33d3e87`, plus `test/coop-soak-stuckbots` `25dcf0c`) and the co-op fix
branches in flight (`fix/respawn-own-kit`, `fix/coop-extraction`, `feat/fob-ready-up`).

On harder contracts the company fields more than the player squad: one to three **hero squads**,
each led by a named roster member (the hero), deploy beside it. The player commands squads, not
men, from the map or from the command menu. Each order runs on the host as a short phased plan
built from squad orders that already work, the squad reports back over the radio, and its men come
home with experience, wounds or losses that persist.

Contractor learns from other games here and copies none of them: it is inspired by Arma 3's High
Command bar and squad-leader AI, by LAMBS and VCOM group tasks and mutual support, and by
Bannerlord's companions who lead their own parties. It also learns from where Arma's high command
feels weak: little feedback, waypoints that fail silently, and no way to time squads together.

## How this proposal was put together

Three designs were written against the code and judged. This document leads with the top-ranked
one and grafts in the best parts of the other two.

| Design | Rank | What it gives this proposal |
|---|---|---|
| **Command-First:** map orders, order model and comms | 1st (lead) | The order model (phase machines that end `done` or `failed` with a reason), go codes, risk levels, requests the commander approves or denies, the report catalogue, the RPC table with host checks, the replicated view and late-join snapshot, the map Command mode and HC panel, knowledge fairness, and "nothing fails silently" |
| **AI-first:** the squad planner under a hero leader | 2nd | `Intent.LEAD` for the hero, frontage lanes, the support-by-fire spot rules and lift/shift, "Support me" and company mutual support, order biases as a table (with a new "hold" term), the AI LOD, "the order is law, autonomy lives inside it" |
| **Heroes on the Books:** campaign-first | 3rd and 4th | The campaign side (hero rank, squads as company assets, cohesion, wages, history, debrief), the spawn seam (`_spawn_recovery_targets`), the support-budget charge, the friendly AI budget line, delegation, and the `stream_focus` gap the others missed |

Corrections the judges found in the lead design, folded in below:

- **Streaming.** On the host, `ZoneLevel.stream_focus()` (zone_level.gd:633-647) streams modules in
  only around players and around AI that are fighting. A hero squad defending a building 500 m out
  would have its module streamed out under it (`STREAM_OUT_M` 340), and an attack would reach an
  outpost whose garrison hasn't spawned. Hero squad leaders go into `stream_focus` (groundwork G8).
- **The hero and the evaluator.** `SquadAI._tactic()` (squad_ai.gd:2367-2378) drops evaluator
  moving tasks for any friendly whose order isn't FOLLOW, so a hero kept on MOVE or HOLD never
  moves with the fight. This proposal keeps the hero on FOLLOW and gives him `Intent.LEAD`
  instead of a follow slot (from the AI-first design), so he takes base-of-fire tasks and the leash
  moves with him.
- **Finished ordered tactics.** `_tactic_done` (squad_ai.gd:2421-2428) sets a friendly to HOLD,
  which makes `assess()` report the squad as not free and stops flank, assault and break. The
  order executor restores FOLLOW after every bound, garrison or suppress ends, unless the phase
  wants the men held (defend, support by fire).
- **UI before AI.** The lead design's MVP was UI-heavy. The MVP here keeps the map UI to a click
  and a menu, and proves the orders headless first (Phase 1 acceptance).
- **Initiative.** Biases alone can make squads feel like obedient order executors. The AI-first
  planner pieces (lanes, SBF spots, Support me, requests) give them initiative inside the order.

## 1. What already exists to build on

- **Squad** (scripts/ai/squad.gd): host-side command state per side, with an enemy picture
  (`known`, `note_enemy`, `clusters()`), `leader`, formations, `ccp`, and stable order wrappers
  that take `from: Soldier`: `give_order` (FOLLOW / HOLD / MOVE), `order_suppress`, `order_bound`,
  `order_garrison`, `order_clear`, `order_take_cover`, `order_fall_back`, `order_command`
  ("watch", stance, heal, give ammo, treat, ccp) and `command` (formation, target, mode). Every
  order sets `leader = from`; called with `from` = the hero, they become the hero's orders to his
  own men.
- **More than one Squad per side already works for the enemy.** `EnemyResponse._new_squad` /
  `_spawn_team` (enemy_response.gd ~597-626) and `Reinforcements` (reinforcements.gd ~189-206)
  create a `Squad`, spawn through `level.spawn_soldier`, then set each brain's `squad`. Hero
  squads spawn the same way.
- **SquadTactics** (scripts/ai/tactics.gd): runs per Squad, thinks every second. `score(sit, d)` is
  pure and adds `doctrine()` biases (flank, assault, clear, defend, break, casualty, search).
  `elements()`, `flank_route()`, `garrison_tasks()`, `clear_op()` and `fall_back_point()` are
  static and reusable at squad scale. `_call_option()` already has a leader's voice.
- **SquadAI** (scripts/ai/squad_ai.gd): ordered tactics win over the evaluator (`ORDERED_SCORE`
  0.85 > `TACTIC_SCORE` 0.75); halt spots give all-round security when the lead stops; a leader
  aura for morale (`MORALE_LEADER`); radio contact sharing between radio carriers
  (`_share_contact`, `SHARE_RADIO_S` 2.5); `_friendly_in_line` already checks every friendly on the
  side, so cross-squad fire discipline works today.
- **Map**: `MapView` (right-click `_open_menu`, Ctrl+drag lines), `MapScreen` side panels,
  `MapMarkers` (host-authoritative, `server_report_enemy` for intel, `_client_snapshot` on
  `Net.peer_joined`), `MapGrid.grid_ref`, and `MapNodes.install(level)` for per-level nodes on
  every peer.
- **Comms**: `Callouts._show` to the side's players; `RadioChatter`'s rate-limited line queue
  (`LINE_GAP_S` 5, `QUEUE_MAX` 3) with a non-soldier speaker name, the route hero squad radio
  lines take.
- **Roster and deployment**: `Roster.ai_stats` (aim to combat, nerve to discipline), `identity`,
  `add_history`, `after_mission`. `RosterDeployment.resolve()` already settles any member in
  `dep.spawned` as extracted, left behind (MIA plus a recovery contract) or killed.
- **BaseHub**: `_spawn_recovery_targets()` (base_hub.gd:893, called from `_on_briefing_started`)
  already spawns roster members outside the 8 slots (slot -1, meta `roster_id`, own gear,
  identity, `ai_stats`); hero squads spawn the same way. Company decisions are host-only
  `_server_request`s. `Campaign.snapshot()` before deploy means anything in the roster section
  reverts for free.
- **Economy and contracts**: `Economy.server_pay_support(kind, cid)` (economy.gd:313) draws on the
  contract's support budget before cash; `data/prices.json` "supports". Contracts carry `rated`
  (briefed, 1-5) and the hidden `true_rating`; hot zones are harder.
- **Extraction**: on `fix/coop-extraction`, any player inside a point confirms, and AI squadmates
  away from it don't block: the first confirm warns who would be left behind, a second one within
  `LEAVE_CONFIRM_S` extracts without them and they are reported MIA (`can_leave_behind`,
  `left_at_call`). Hero squads plug into that warning instead of a second mechanism.
- **The co-op soak bot "player brain"** (tests/coop_soak.gd on `test/coop-soak`): `_follow_tick`
  and `_follow_spot` (a loose place 10-25 m off the leader, turned his way; hold and fight in
  contact; board or leave his vehicle with him; get inside the extraction point he stands in),
  `_extract_with_human` (confirm once everyone is in, leave stragglers after 90 s), `_stuck_note`
  (S0758: bots stood 400 m behind for 20 minutes with nothing logged), the stuck-bots branch's
  `_track_wedge` (no headway, then a detour, then a catch-up), `_give_up_tick`, `_hunt`, and
  `_dead_ground` / `_hidden_fraction`. It drives player bodies over RPCs from separate processes,
  so it can't ship, but its decisions are the behaviour spec for "Follow me" and "Extract" and the
  harness becomes the high command test bench. Section 9 is about lifting it into game code now.

**Why heroes are not soak bots.** A soak bot is a peer (`Net.MAX_CLIENTS` is 3), moves by stepping
its position with no navmesh, and fights through raw fire RPCs. Heroes are host AI soldiers on the
full SquadAI stack (cover, medical, morale, casualty care, scavenging). The bot's decision layer
ports; its actuator doesn't.

**One caution from the soak bot.** `_dead_ground` reads true hostile positions (every garrison post
and hostile soldier). That is fine in a test harness and would be a cheat in game AI. Hero squads
plan only from what our side knows (section 5.6).

## 2. Groundwork: a second friendly squad breaks one-squad assumptions

These are fixed first (Phase 0), with no gameplay change and a regression check each. All were
checked against fc98665.

| # | Where | What breaks with a second friendly squad | Fix |
|---|---|---|---|
| G1 | `Squad.members()` (squad.gd:187) | Takes every friendly AI by faction. Player orders with no names, `pick()`, `follow_point()` and `_share_contact()` would reach hero squad men | Keep only soldiers whose brain is on this squad, as `brains()` already does |
| G2 | `CompoundLevel._squad_ai()` (compound_level.gd:658) and `rebalance_squad()` (640-642) | A hero squad man has slot -1, so the next join or leave calls `_remove_squadmate` on him | Exclude hero squad men |
| G3 | `CommandMenu.roster()` (command_menu.gd:183-195) | F-keys, select-all and the HUD squad lines would list hero squad men | Player squad only |
| G4 | `SquadTactics.assess()` (tactics.gd:286-292) | Every slotted player is counted into every friendly squad's up/down | Count players only for the main squad |
| G5 | `Callouts.recipients()` (callouts.gd:151) | Every friendly line goes to every friendly player at any range: three squads talk over each other | Hero squad speakers reach players within `HC_VOICE_M` (40-60 m); their tactical calls are summarised on the net (section 6) |
| G6 | `EnemyResponse._watchers()` (enemy_response.gd:558) | Players plus `MapNodes.squad_ai`: QRFs and hunters may spawn in a hero squad's face | Add hero squad men |
| G7 | `CompoundLevel._make_soldier` (compound_level.gd:828) | Sets `brain.squad = squad_for(faction)` | Re-point to the hero squad after spawn, as `_spawn_team` does |
| G8 | `ZoneLevel.stream_focus()` (zone_level.gd:633-647) | Hero squads out of contact don't keep modules (and garrisons) streamed in | Add each hero squad's leader on the host |
| G9 | `Squad.follow_point()` (squad.gd:649) | Indexes `members()` including the leader: a hero on FOLLOW chases his own slot | Skip the leader; the hero walks `Intent.LEAD` (section 5.3) |
| G10 | `SquadAI._tactic()` and `_tactic_done` (squad_ai.gd:2367-2378, 2421-2428) | Not a bug for the player squad, but the executor depends on it | `SquadOrders` restores FOLLOW after ordered tactics (section 5.2) |
| G11 | Call sites on `MapNodes.squad_ai` / `squad_slot >= 0` (briefing.gd:329, extraction.gd:212 and 358, radio_chatter.gd:136, heli_call.gd:209/558/684/740, map_extraction_panel.gd:49, objective_helper.gd:403, map_view.gd:525, compound_level.gd:731, soldier.gd:1925) | Each assumes "friendly AI" means the player squad | Audit each: they stay player-squad-only (slot >= 0 already excludes hero squads); hero squads get their own path where it matters (extraction, map) |

**One marker, not scattered checks.** Every hero squad soldier gets a replicated `Soldier.hc_id`
(StringName, `&""` for the player squad), set from spawn data in `_make_soldier` and added to the
server `SceneReplicationConfig` in scenes/soldier.tscn, so the HUD, map and command menu on clients
can tell hero squad men apart (a meta wouldn't replicate). `Squad` gets `var hc_id := ""` and a
static `Squad.hc_of(s)`. One predicate, `Squad.is_squadmate(s)` (friendly AI, player squad, not
recovery, not vehicle crew), replaces the meta checks G2, G3 and G11 repeat today.

**Sequencing.** G1, G9 and G10 touch squad.gd and squad_ai.gd, and G5 touches callouts.gd: the
`fix/respawn-own-kit` agent (B:\Contractor-coop-respawn) is editing all three now (body carrying,
`ccp_off`). Phase 0 starts after that branch lands on dev and is built on top of it.

## 3. What the player does

### 3.1 A hard contract, end to end

1. **Board.** A rated-4 raid shows "Squads authorized: 1". Authorization comes from the briefed
   `rated`, not `true_rating`: rated 4 gives 1, rated 5 gives 2, a hot zone adds 1, at most 3
   (the MVP caps it at 1). Because the client's rating can understate the threat, the player may
   bring squads beyond what's authorized at the company's own cost.
2. **FOB prep.** The "Squad & deploy" page gets a **Hero squads** block: pick a hero and his men
   from available roster members (roles auto-filled by `Roles.layout`, as `auto_squad` does),
   see the cost and a **friendly AI budget** line ("AI: 7 + 4 + 4 = 15 of 20"). More co-op players
   means fewer AI in the player squad and more room for hero squads, which keeps the 8-slot squad
   player-scalable. Picks are part of prep, so they follow the FOB ready-up rules
   (`feat/fob-ready-up`).
3. **Briefing.** Hero squads show at their insertion points (picked from the zone's insertion
   points). From Phase 2 the player can give **H-hour orders** that wait for the deployment to
   start, any of them gated on a go code.
4. **In the field.** The player commands squads from the map's **Command mode** or the command
   menu's **Squads mode**. Hero squads acknowledge, report contact (which drops an intel marker),
   casualties, "in position", "objective secure", "unable" with a reason, and requests:
   - "Hawk 2, copy: moving to 041 053."
   - "Hawk 2, set at 041 053. Ready on Alpha."
   - "Viper 3, contact: 6 enemy, north, 180 m."
   - "Viper 3, two wounded, taking heavy fire: request to break contact." (Approve / Deny, 20 s.)
   - "Hawk 2, Mercer is down. Okafor has command."
5. **Synchronising.** The player presses go code Alpha: Hawk 2 opens fire on the compound while
   the player's squad assaults. When any friendly comes within `DANGER_CLOSE_M` of the target area,
   Hawk shifts or lifts fire by itself ("Hawk 2, shifting fire").
6. **Extraction.** "Extract" sends a squad to an extraction point with an avoid-contact posture.
   Hero squads never block the player squad's extraction: the leave-behind warning from
   `fix/coop-extraction` also names hero squad men away from the point ("Leaving behind: Viper 3,
   2 men, 380 m out"), and a second confirm leaves them, MIA under the existing rules.
7. **Debrief.** Each hero squad gets a section: who came back, wounds, KIA, MIA, objectives it was
   credited with, and the hero's growth. The hero's history gains "Led Hawk 2 at Outpost 2:
   objective secure, 1 wounded".

### 3.2 Orders

| Order | The squad does | Built from (existing) | Done when | Phase |
|---|---|---|---|---|
| **Move** (point; queued points later) | Hero walks the legs, members follow in the order's formation; on contact, react, fight, resume | `Intent.LEAD`, `FORMATIONS`, halt spots | Hero within `ARRIVE_M` of the last point | 1 (queues 2) |
| **Hold** | Stop; halt spots; watch the threat axis | `give_order(HOLD)`, `_find_halt_spot` | Replaced | 1 |
| **Defend** (point, facing) | Move; garrison a building within `DEFEND_BUILDING_M` (30 m), else a line across the facing with a watch sector per pair | `order_garrison`, `garrison_tasks`, "watch" | Replaced (reports "set") | 1 |
| **Follow me / Support me** (a player) | Keep a loose station off the player, turned his way; hold and fight in contact. Follow is close (30-60 m); Support me is an echelon left, right or rear at 60-120 m that sets up a base of fire for the player's squad when it's hit | `FollowBrain` (section 9), Support-by-fire rules | Replaced | 1 (auto fire for the player 2) |
| **Regroup** (on the hero, a point or a player) | Gather within `REGROUP_M`, set `ccp`, cross-load ammo, treat; report strength and ammo | `give_order`, `give_ammo`, `ccp` | All living men gathered | 1 |
| **Extract** (point) | Route with a break-contact bias and return fire; hold inside; carry the downed | `Extraction.points`, `inside()`, casualty care | Every living man inside: "Hawk 2, at the LZ" | 1 |
| **Attack** (area, building, objective or marker) | Route to an attack position; set; wait for a go code if gated; execute (base of fire plus assault, or clear a building); lift and shift; consolidate; abort past the risk threshold | `order_bound`, `order_clear`, `forced_plan`, biases | Objective clear for `CONSOLIDATE_S` with the squad inside: "objective secure" | 2 |
| **Support by fire** (position, target) | Take the best SBF spot near the position; suppress the target while it holds known enemies, refreshed every `SUPPRESS_ORDER_S`; shift or lift for danger close; "fire on call" option | `order_suppress`, "watch", `_friendly_in_line` | Lifted, or target clear `SBF_IDLE_S` | 2 |
| **Bound** (point) | Fire teams bound by pairs to the point | `order_bound`, `elements()` | Arrived | 2 |
| **Fall back** (point or away) | Break contact by pairs with smoke, then hold | `order_fall_back` | Arrived | 2 |
| **Posture** (no point) | ROE, combat mode, formation, speed | `set_hold_fire`, `set_combat_mode`, `command("formation:")` | At once | 1 |
| **Report status** (no point) | A sitrep | | At once | 1 |

Direct fire commands on an SBF order: Shift fire, Lift fire, Fire, Cancel. With two squads
selected, Bound becomes a leapfrog (one overwatches, the other moves a leg) in Phase 4.

### 3.3 Controls (all rebindable through `GameSettings.BINDABLE`)

| Where | Input | Effect |
|---|---|---|
| Map | **Command** toolbar toggle, or the bindable `high_command` action | Command mode on or off. Marker editing is unchanged outside it |
| Map, command mode | Left-click a squad icon (Shift adds, Tab cycles) | Select |
| Map, command mode | Right-click (short) | Order menu for what's under the cursor (3.4). Right-drag still pans |
| Map, command mode | Shift with an order | Queue it after the current one (Phase 2) |
| Map, command mode | Ctrl+left-drag | A route (multi-point Move), reusing MapView's line capture (Phase 2) |
| Map, command mode | Backspace / Del | Cancel the selected squad's order / the hovered one |
| World | `high_command` action | The command menu enters **Squads mode**: F1-F4 select hero squads, entries aim with the crosshair, "Open map" opens Command mode (Phase 2) |
| Map or world | Go-code buttons; `hc_approve` / `hc_deny` | Alpha / Bravo / Charlie; answer the latest request (Phase 2) |

Ctrl and Alt combinations are avoided for new defaults: the Ctrl and Alt menus own those
modifiers, Ctrl+F-key already adds to the command menu selection, and Alt+F4 closes the window.

### 3.4 The map order menu by what's under the cursor

- **Open ground:** Move, Defend (drag for facing), Regroup here, Hold; later Bound, Support by fire
  from here (second click picks the target), Fall back.
- **Building** (`Buildings.nearest`): Defend (garrison), Move; later Clear.
- **Enemy intel marker, objective or hostile site:** later Attack, Support by fire on it.
- **Extraction point:** Extract here.
- **A player icon:** Follow, Support, Regroup on him.
- **Another hero squad:** later Regroup with it, Reinforce.
- **Always:** Report status; Posture (ROE, mode, formation, speed); later Risk (Careful,
  Balanced, Press on) and Go code (none, Alpha, Bravo, Charlie) for the next order.

The host re-checks every lookup.

## 4. The order model

### 4.1 Order data (JSON-safe: it replicates, logs and survives the session log)

```
{"id": int, "squad": "hawk2",
 "kind": "move|hold|defend|follow|support|regroup|extract|attack|sbf|bound|fall_back",
 "points": [[x, z], ...],
 "target": {"kind": "area|building|objective|marker|player|squad|extraction", "pos": [x, z],
            "radius": m, "ref": "id"},
 "facing": [dx, dz] or null,
 "posture": {"roe": "free|return|hold", "mode": "safe|aware|combat|stealth",
             "formation": "wedge|file|line|staggered column", "speed": "slow|normal|fast",
             "contact": "react|push|avoid"},
 "risk": "careful|balanced|press", "go": "" | "alpha" | "bravo" | "charlie" | "hhour",
 "after": 0, "state": "queued|waiting|active|set|done|failed|cancelled",
 "phase": "route|set|execute|consolidate", "by": peer, "at": seconds, "why": ""}
```

- **Lifecycle:** `queued`, then `waiting` when gated, `active` (route), `set` (in position,
  waiting for a go code or "Fire"), `active` (execute), then `done`, `failed` (with `why`) or
  `cancelled`. A new order that isn't queued cancels the queue, matching today's "latest order
  wins".
- **Contact on a Move** follows `posture.contact`: react (the hero halts, SquadTactics fights, the
  move resumes 10 s after contact ends), push (keep moving; the discipline-weighted MOVE score
  already does this), or avoid (break-contact bias and continue).
- **Risk to a casualty threshold:** Careful is the first urgent casualty (`triage_tier`) or 25%
  down; Balanced 35%; Press on 50%. Past it the hero requests to break contact; a Careful hero
  breaks at once and reports.
- **Go codes** are session-wide: one press launches every waiting order with that code, so
  several squads move together. `hhour` orders start on `Briefing.deployment_started`. Phase 4
  adds `after` ("Viper 3 moves when Hawk 2 is set").
- **Commander's intent:** the kind is the task, the target the purpose, risk what the player will
  pay. If an attack's enemy cluster drifts within `OBJ_DRIFT_M`, the hero re-aims instead of
  failing.

### 4.2 The order is law; autonomy lives inside it

A hero squad never leaves its order on its own. When the hero wants to deviate (break contact
under Defend, go and help another squad under Move) he asks. A request unanswered within its
timeout (20 s at average leadership) is decided by the hero: his traits, then his risk level
("Viper 3, no answer, breaking contact"). A broken squad may still fall back, as `SquadAI.broken()`
does today; that stays honest.

### 4.3 Nothing fails silently (S0758)

- **Held up:** less than 3 m of progress toward the current leg for `STUCK_S` (30 s, out of
  contact): "Hawk 2, held up at 041 053, finding a way round". It tries a detour off the straight
  line (the stuck-bots branch's lesson), then the nav path again, then an offset point.
- **Unable:** after `UNABLE_S` (90 s) the order fails: "Hawk 2, unable: no route to 041 053.
  Holding." The next queued order starts.
- Every failure has a `why` on the panel, in the net log and in the session log. The soak bot's
  catch-up teleport stays test-only: a player would see it.
- Order points are clamped into `map_area().grow(-80)`, as the soak learned (S0672, S0697 put bots
  past the zone edge).

## 5. Execution on the host

```
HighCommand (one per level)     registry, order intake, go codes, requests, the company net,
   |                            cross-squad contact sharing, mutual support (Phase 3-4), view
SquadOrders (one per hero Squad) order queue and phase machines; lanes and SBF spots (HcOrders)
   |
SquadTactics (existing)         contact drill scoring, biased and bounded by the order
   |
SquadAI (existing)              hero: Intent.LEAD; members FOLLOW the hero as today
```

### 5.1 HighCommand (new `scripts/campaign/high_command.gd`, Node)

Installed by `MapNodes.install` next to MapMarkers, Extraction and Reinforcements, so the same path
exists on every peer; found with `MapNodes.high_command(from)`.

- Host: the registry `id -> {callsign, hero, squad: Squad, members, comms, orders}`; order intake
  and validation (section 7); go codes and requests; the company net (section 6); and spawning:
  `server_spawn_squad(def, at)` creates a `Squad` (name `HC_<id>`, faction friendly, `hc_id`) as
  its child, the way `EnemyResponse._new_squad` does, and spawns members through
  `level.spawn_soldier` with the same body set-up `_spawn_recovery_targets` and
  `server_spawn_roster_squadmate` use (identity, own gear, `roster_id`, `ai_stats`), then
  `brain.squad` and buddies.
- Cross-squad contacts: a squad's contact report reaches the other squads' `known` as heard
  (`note_enemy(who, pos, true)`) after `NET_DELAY_S` (2.5, like `SHARE_RADIO_S`), so the company
  has one rough picture of the enemy.
- Clients: only the replicated `view` and the net log.

### 5.2 SquadOrders (new `scripts/ai/squad_orders.gd`, RefCounted)

One per hero Squad, like `SquadTactics`, ticked from `Squad._physics_process` every `THINK_S`
(0.5 s) just before `tactics.think`. It holds the queue and the active order's phase machine, one
small handler per kind mapping section 3.2 onto existing calls, always with `from` = the hero.

- **Seams on Squad** (narrow): `hero` (Soldier), `leg` ({point, halt, face}) for the hero's LEAD
  intent, `lane` ({a, b, half_w}), `order_bias` (Dictionary), plus `tactics.forced_plan` (a base
  of fire and maneuver route the order chose; `_draw_flank` uses it when set).
- **Resting order:** each tick, men whose order flipped to HOLD because an ordered tactic ended
  (`_tactic_done`) get FOLLOW again when the phase wants them free; Defend and SBF phases keep HOLD
  on purpose.
- **Straggler control:** `leg.halt` while any man up is more than 25 m from his slot, or a
  casualty is being carried.
- **Order biases** (added to SquadTactics option scores through `doctrine()`, Proposed):

  | Order / phase | flank | assault | clear | defend | break | hold | search |
  |---|---|---|---|---|---|---|---|
  | Move | -0.15 | -0.2 | -0.3 | 0 | +0.05 | 0 | -0.2 |
  | Follow / Support me | 0 | -0.1 | -0.2 | 0 | 0 | 0 | -0.1 |
  | Attack (execute) | +0.1 | +0.15 | +0.15 | -0.1 | -0.1 | 0 | 0 |
  | Defend | -0.5 | -0.5 | -0.5 | +0.3 | -0.15 x nerve | +0.15 | -0.3 |
  | Support by fire | -0.6 | -0.6 | -0.6 | 0 | -0.05 | +0.2 | -0.3 |
  | Regroup / Extract | -0.5 | -0.5 | -0.6 | 0 | +0.15 | 0 | -0.5 |
  | Risk Press on / Careful | | | | | -0.1 / +0.1 | | |

  This goes through the same `doctrine()` seam the doctrine weights (audit A3-07, still pending)
  are meant to use, so there is no second weight system.

### 5.3 The hero leads (squad_ai.gd and tactics.gd, small edits)

- **`Intent.LEAD`.** In the friendly branch of `_choose_intent`, `squad.hero == body` scores LEAD
  in place of FOLLOW. Out of contact he walks `squad.leg.point` at the squad's pace; on `leg.halt`
  he stops and faces `leg.face` from a halt spot; in contact he fights around the leg anchor, as
  the FOLLOW fight branch does. His order stays FOLLOW, so `_tactic()` lets him take evaluator
  tasks and the leash (`FOLLOW_LEASH_M` 30) moves with him. Status text: "Leading", "Waiting for
  the squad".
- **The hero stays in the base of fire:** `elements()` keeps `squad.hero` in the base, as the player
  lead is today; `_call_option()`'s speaker is the hero.
- **Lanes:** every order gets a lane, the axis from the squad to its objective with half-width
  50 m. `flank_route()`, `fall_back_point()` and SBF spot search are clamped into it (a static
  `_in_lane()` beside `_leashed()`). HighCommand offsets a new lane that overlaps another squad's
  or the player squad's 30 m bubble, and warns when it can't ("Viper and Rook lanes cross: Rook
  shifted right").
- **A "hold" term** in `score()` (`+ d.get("hold", 0.0)`): Defend and SBF need one; none exists.
- **Leader aura:** `MORALE_LEADER` and its range scale with the hero's leadership.
- **If the 30 m leash proves too tight in attacks** (Phase 2): `Squad.lead_anchor()` returns the
  objective during execute, used for the leash only.

### 5.4 Support by fire and danger close

- **SBF spot** (when the player gives only a rough position, or Attack sets its base): line of
  sight to the target at three heights; on a ring 80-200 m from it; 30-120 degrees off the assault
  axis so the assault lane isn't masked; the fire lane keeps 30 m from every current and planned
  friendly position out to target + `DOWNRANGE_M` (60 m). No spot clears: "Hawk 2, can't fire,
  friendlies in the lane", and it tries the next.
- **Danger close:** every SBF tick checks for any friendly (players, the player squad, other hero
  squads) within `DANGER_CLOSE_M` (35 m) of the target area or inside the fire cone; then it shifts
  to an uncovered part of the area or lifts ("check fire, friendlies on target"). The assault
  element closing within 50 m of the target, or within 15 degrees of the SBF line, lifts or shifts
  fire too. `_friendly_in_line` stays as the last guard on each shot.
- **Ammo:** below `AMMO_LOW` the squad lifts and reports "ammo red".

### 5.5 Succession and comms

- **Succession:** when the hero goes down or dies, the other fire team's team leader, else the
  member with the best nerve then missions, becomes `squad.hero` and `squad.leader` and takes the
  current order. "Hawk 2, Mercer is down. Okafor has command." The hero's traits stop applying;
  each man takes a morale hit (double for losing the leader). His history records it.
- **Combat ineffective** (2 or fewer up, or most broken): report, then regroup on the nearest
  friendly squad or extraction point.
- **Comms** (Phase 3, setting `hc_needs_radio`, off in the MVP): the hero or someone within voice
  range of him carries a `RADIO`. Without one the squad is **comms lost**: its icon greys, new
  orders are refused ("No comms with Hawk 2"), it finishes its current order, holds, then extracts
  when the player squad's extraction starts. The commander likewise needs a radio or a radio
  carrier in voice range. A jammer cuts high command (Phase 4).

### 5.6 Knowledge fairness

Routes, attack positions, SBF spots and avoid areas use only the side's intel markers, each squad's
`known`, the contract's `known_enemies` and terrain: never `EnemyResponse` internals or true
soldier lists. That is how the AI bar (beat Arma 3 Veteran with LAMBS and VCOM) is met fairly. A
test checks the planner's inputs (section 11).

### 5.7 Streaming and performance

- **Streaming:** each hero squad's leader joins `stream_focus()` on the host (G8), so modules and
  their garrisons stream in as a squad approaches. Garrison spawns cost CPU; streaming stays
  staggered.
- **Budget:** each hero squad adds 4 (MVP) to 8 brains on a machine that is already loaded, on top
  of hot-zone hostiles (`EnemyResponse.MAX_ALIVE` 40, reinforcement waves, garrisons). Mitigations:
  one squad of 4 in the MVP; the friendly AI budget cap at prep; staggered think timers; an **AI
  LOD** (Phase 3): a squad with no player within `HC_LOD_M` (350-400 m) and not in contact scans
  every 1.0 s, thinks every 1.5 s and plans every 4 s; `FrameCost` keys `ai` and a new `hc`; a
  `perf_timing` case with 8 + 8 + 8 friendly AI in a hot zone against a budget.
- **Travel LOD** (Phase 4): a squad over 340 m from every player and not in contact moves as a
  token along its route and re-materializes inside the stream radius. Fights are always real.

## 6. The company net (reports)

`HighCommand.radio(squad, kind, text, pos := null)` on the host:

- appends to a replicated net log `{t, squad, kind, text, pos}` (last 50 lines);
- shows a subtitle to the side's players through `Callouts._show` with the speaker "Hawk 2 (net)",
  the route RadioChatter uses, so net lines read apart from shouted callouts;
- writes `SessionLog.note("[hc] ...")` for playtest review, in the style of `[tactics]`.

**Rate limits:** one line per squad per `NET_GAP_S` (3 s), a queue of 4, casualty, request and
unable lines first; a repeated contact report within 60 s and 40 m of the last is dropped. Hero
squad shouts ("Reloading!", "Base of fire, suppress!") stay within voice range (G5); the net gets at
most one tactics summary per squad per `TACTIC_REPORT_GAP_S` ("Hawk 2, in contact, suppressing and
flanking left").

| Trigger | Example | Side effect | Phase |
|---|---|---|---|
| Order accepted / refused | "Hawk 2, copy: moving to 041 053." / "Hawk 2, unable: no route." | Order active / failed with `why` | 1 |
| Set, done | "Hawk 2, set at 041 053." / "objective secure" / "at the LZ" / "Hawk 2 is out." | Panel state | 1 |
| First fresh cluster | "Viper 3, contact: 6 enemy, north, 180 m." | `MapMarkers.server_report_enemy(centre, "Viper 3: 6x", "intel")`; shared to other squads | 1 |
| Man down | "Hawk 2, man down, one urgent." | Casualty count | 1 |
| Succession | "Hawk 2, Mercer is down. Okafor has command." | Leader changes | 1 |
| Held up | "Hawk 2, held up at 041 053, finding a way round." | Replan | 1 |
| Sitrep (asked, idle every `SITREP_S`, order end) | "Hawk 2, 3 up, 1 wounded, ammo amber, holding at 041 053." | Panel refresh | 1 |
| Ammo low | "Hawk 2, ammo red." | Lift fire; later a resupply request | 2 |
| Danger close | "Hawk 2, check fire, friendlies on target." | Lift or shift | 2 |
| Request | "Viper 3, two wounded, taking heavy fire: request to break contact." | Pending request | 2 |
| Initiative | "Viper 3, contact at Hawk 2's position, request to support." | One key turns it into a Support order | 3 |
| Comms lost | (silence) | Icon grey, "no comms 2 min" | 3 |

Grids come from `MapGrid.grid_ref` at 100 m; a hero with high leadership gives finer grids and exact
counts, a low one "several". Ammo, morale and wounds are bands, not numbers, in keeping with the
minimal HUD: ammo green above 0.6, amber 0.3-0.6, red below 0.3 (`ammo_share`); morale steady,
shaken, breaking (`MORALE_SHAKEN`, `MORALE_BROKEN`).

**Requests** `{id, squad, kind, text, at, until}`: break contact, reinforce, CASEVAC (bring the
casualty to the CCP or the player: `ccp` / `ccp_me`), resupply (Phase 3). Answered with
`HighCommand.request_answer(id, approve)` from the panel or the approve and deny keys.

## 7. Network and authority (host-authoritative co-op)

**RPCs on HighCommand** (requests `any_peer`, `call_local`, reliable; the host validates; validation
lives in pure statics, `HcOrders.validate`, so tests and the soak bot use the same rules):

| RPC | Host checks | Effect |
|---|---|---|
| `_server_order(squad_id, order, append)` | Sender has a Soldier in Players, not AI, up; authority (below); the squad exists and has comms; kind whitelisted; points finite and inside `map_area()` grown by the pan margin; at most 16 route points and 8 queued orders; refs resolve on the host (building, objective, marker, player, extraction point); at most 4 orders a second per peer; text clamped | Order added; "copy" or "unable" on the net; a refusal to the sender |
| `_server_cancel(squad_id, order_id)` | Authority | Cancelled |
| `_server_go(code)` | Authority | Waiting orders with that code go active |
| `_server_answer(request_id, approve)` | Authority; still pending | Resolved |
| `_server_take_command()` / delegation | Setting, current commander | "Player 2 has command" |

**Replication.**
- Hero squad men are ordinary spawned Soldiers: positions replicate as now, and `Soldier.hc_id`
  replicates with them (G-marker).
- The host-only state (orders, phases, tactics option, requests, bands, comms, last report) goes
  out as one compact **view**, on change only, at most 2 Hz (like `BaseHub._queue_broadcast`).
  Per squad: `{id, callsign, hero_name, up, total, wounded, ammo_band, morale_band, comms,
  last_report_t, last_pos, order: {id, kind, points, target, state, phase, go}, queue, tactic}`.
- Late joiners get `_client_snapshot(view, net_log)` on `Net.peer_joined`, the MapMarkers pattern.
- Clients never run SquadOrders or SquadTactics.

**Authority** (host setting `hc_authority`):
- `"anyone"` (MVP default): today's squad rule, any player may order and the latest order wins; the
  author is shown on the order and in the net line.
- `"commander"` (Phase 3): one commander seat, the host by default. The host can **delegate** a hero
  squad to a co-op player at the briefing, keyed by `BaseHub.player_key` so it survives a
  reconnect. A delegate who leaves: the squad holds, reports "lost comms with command", and falls
  back to the host.
- A player joining mid-deployment takes a player-squad slot (`rebalance_squad`); hero squads are
  untouched (G2).
- Phase 4 option: a co-op player **takes a hero squad's lead** (the hero becomes second in
  command) or joins one of its slots, which keeps the player-scalable rule at squad level.

**Campaign data:** promote, form, assign and disband are host-only BaseHub requests (like
"release"); picking hero squads in prep follows "pick". All of it travels in `BaseHub.view`.

**Fog option** (Phase 3, `hc_bft`): on, live member dots; off, hero squads are drawn at their last
reported position with an age tag. A co-op honesty setting, not anti-cheat.

## 8. Campaign: heroes on the books

Hero squads are company assets: hired, paid, kitted, risked and grown at the FOB like squadmates
today. Losing Sgt Okafor's squad on a rated-5 hot zone costs a veteran, three trained hands, their
gear and a recovery contract.

**Roster member fields** (lazily defaulted by `Company.ensure_hero()`, as `ensure_identity` fills
older saves; all JSON-safe in the roster section, so saves, revert and `BaseHub.view` work with no
new plumbing):
- `rank`: 0 contractor, 1 team leader (leads up to 4, himself included), 2 squad leader (up to 8).
- `lead` (0..1, rank 1 and up): kept out of `Roster.SKILLS` so existing wages don't shift. It sets
  planner cadence (1.5-3.0 s), request timeouts (10-30 s), grid precision and whether he re-aims on
  his own.
- `traits` (Phase 3), `squad` (the hero squad id or "").

**Section key `"hc_squads"`:** id -> `{id, callsign, leader, members (in slot order), formed_day,
missions, kills, losses, cohesion, standing: {roe, mode, formation}}`, plus `next_id`.

**`class_name Company`** (new scripts/campaign/company.gd, pure static like Roster):
- `can_promote(m, rank)`: rank 1 at 6+ missions and nerve >= 0.55; rank 2 at 12+ missions and
  lead >= 0.5. `promote()` charges a fee (2000 / 5000) and sets `lead` to 0.25 + 0.4 x nerve.
- `form()`, `assign()`, `unassign()`, `disband()`, `rename()`, `size_of(rank)` ([0, 4, 8]). A member
  belongs to at most one hero squad; members of one not deploying can still be picked for the
  player squad.
- `authorized(contract)`, `ai_stats(member, squad, leader_up)`: discipline = `Roster.ai_stats()` +
  0.1 x cohesion + 0.1 x the leader's lead while he's up.
- `after_deployment(squad, outcome, rng)`: lead closes on 0.95 by 3-8% (more with objectives done
  and low losses); cohesion +0.1 a deployment, -0.15 per man lost or replaced; history lines.
- `debrief_lines()`; Phase 3: the traits loader (data/hero_traits.json) and `exfil_roll()` if the
  Captain wants it.

**Money:** `Roster.wage_of` adds `RANK_WAGE[rank]` (0 / 40 / 90 a day). Each authorized hero squad
costs an `hc_squad` support charge through `Economy.server_pay_support` (contract support budget
first, then cash); squads beyond the authorization are cash only. A price sits in
`data/prices.json` "supports" next to resupply (8000) and transport (6000): 5000 Proposed.

**Deployment:** `RosterDeployment.begin(..., hc_squads := [])` records `dep.hc_squads` (id,
callsign, hero, members, insertion, outcomes). Members go into `dep.spawned` through the existing
`mark_spawned`, so `resolve()` already settles them. `auto_squad()` and `member_for_slot()` skip
members of hero squads picked for this deployment. `BaseHub._on_briefing_started` spawns them beside
`_spawn_recovery_targets` through `HighCommand.server_spawn_squad`; `server_end_deployment`
collects `_outcome_of` for them. A squad that extracts on its own has its outcomes recorded then
(`mark_hc_out`) and its men despawn ("Hawk 2 is out").

**Traits** (Phase 3, the Captain's call: the design doc lists deep personalities and perk trees as
stretch). Each uses only knobs that act today:

| Trait | Effect |
|---|---|
| Aggressive | flank +0.08, assault +0.05; risk thresholds a step looser; may support without asking |
| Cautious | break +0.06, defend and hold +0.05; the last 150 m toward known enemies becomes a bound; asks to break sooner |
| Methodical | Attack always sets a base of fire first; bounds in contact; legs of 60 m |
| Steady | +0.08 discipline for his men; leader aura x1.5; denies break contact by default |
| Looks after his own | casualty +0.08; sets the CCP at the first casualty |
| Good on the radio | finer grids and counts; relay delay halved |
| Mentor | his men's skill growth x1.25 |
| One flaw each | Glory hound (assault +0.1, break -0.1) or Expensive (wage x1.2) |

Named veterans on the hiring board at higher reputation tiers, and memorial and history views,
come with Phase 3 if the Captain wants them.

## 9. Build now so the co-op fixes stay reusable

The co-op work in flight (the soak bot's player brain, the stuck-bots detour, the extraction
leave-behind warning, FOB ready-up, own-kit respawn) already holds most of what hero squads need.
These steps keep it reusable instead of rewriting it later. None needs a gameplay decision; each is
a small branch of its own, after the owning branch lands on dev (the soak harness belongs to the
coopsoak agent, extraction to coop-extract, squad.gd and squad_ai.gd to coop-respawn).

1. **Lift the soak bot's follow brain into game code: `FollowBrain`** (new
   scripts/ai/follow_brain.gd, pure static or RefCounted). Inputs: my position, the leader's
   position, yaw and vehicle, whether I'm in contact, the active extraction points, an offset table
   and near/far distances. Output: an action `{kind: walk|hold|board|exit|none, point, speed}`. It
   holds the decisions of `_follow_tick` and `_follow_spot` (10-25 m off the leader, turned his
   way; hold and fight in contact; board and leave his vehicle with him; get inside the point he
   stands in). `coop_soak.gd` calls it and keeps its own RPC actuator; hero squads call it with
   SquadAI as the actuator (the hero's `leg`) and bigger offsets (Follow 30-60 m, Support me
   60-120 m). One brain, tested two ways.
2. **Lift the stuck watch: `ProgressWatch`** (new scripts/ai/progress_watch.gd, pure). Feed it
   position, goal and time; it reports headway, "wedged" after `WEDGED_S`, a detour bearing (a
   different way each time, `DETOUR_DEG`), and "held up" / "unable" after its limits, with a state
   line for the log. It holds `_stuck_note` and `_track_wedge`. The soak uses it (its catch-up
   teleport stays in the test); SquadOrders uses it for section 4.3; later SquadAI followers can use
   it for player squadmates left behind, the same S0758 failure in real AI.
3. **Make dead ground knowledge-fair at the seam.** When `_dead_ground` / `_hidden_fraction` are
   lifted (into `HcOrders`), they take the threat points as an argument: the soak passes true posts,
   the game passes intel markers and `known` (section 5.6).
4. **Extraction by group.** Once `fix/coop-extraction` is on dev, a follow-up gives Extraction a
   group-shaped query, `missing_of(point, soldiers)` beside `missing_at`, and lets the leave-behind
   warning list extra groups. The soak's `_extract_with_human` (leave stragglers after 90 s) and hero
   squads then both use the game's rule, not their own.
5. **One squad marker and predicate (Phase 0, after coop-respawn lands).** The replicated
   `Soldier.hc_id`, `Squad.members()` scoped to its brains, and `Squad.is_squadmate(s)` in place of
   the recovery and vehicle-crew meta checks. This also hardens recovery targets and AAV crews.
6. **Command through the game's own seam.** Soak bots give squad orders through
   `_server_squad_command` (the RPC the command menu uses), and later `HighCommand._server_order`,
   so `coop_soak --hc` exercises the real validated path over the lossy relay.
7. **Group records in the soak recorder.** The recorder and `coop_soak_report.py` key positions,
   state and stuck notes by group (`hc_id`, "" for the player squad), so `--hc` needs no new report
   format. `[hc]` session-log lines follow the `[tactics]` style so the report can grep them.

## 10. UI

- **Map** (`map_view.gd` gets narrow hooks; drawing and command-mode input live in a new
  `scripts/ui/map_command.gd`, `MapCommandLayer`, so the 567-line view barely grows):
  - **Squad icon:** a friendly frame inspired by APP-6 (22x14 px, `SQUAD_COLOUR`, infantry X),
    callsign beside it ("HAWK 2"), strength under it ("4/4"), at the hero (members' centroid if he's
    down). States: moving (heading arrow), set (bar), in contact (red outline pulsing at 1 Hz),
    pending request (amber "!"), comms lost (grey dashed, "?"). Selected: yellow outline. Members as
    dots at close zoom when BFT is on.
  - **Order graphics:** move, a dashed blue line with arrowheads (queued legs at half alpha);
    defend, a circle with a sector arc; later attack (red arrow to an objective circle, the attack
    position as a small square), SBF (triangle, a red fan to the target, solid while firing), bound
    (chevrons), fall back ("FB"), extract (purple arrow). Go-gated orders carry A / B / C. A failed
    order flashes red for 3 s with its `why`. Phase 2 adds lanes as faint bands.
- **HC panel** (new `scripts/ui/hc_panel.gd`, placed like `MapExtractionPanel`, 320 px): squad cards
  (hero name, strength, bands, current order and phase); the selected squad's queue with cancel;
  posture and risk quick-sets; requests with Approve / Deny and a timeout bar; go-code buttons with
  waiting counts; the net log (clicking a line centres the map there). During the briefing the
  briefing panel keeps priority, with a tab to switch.
- **Command menu Squads mode** (Phase 2, `command_menu.gd`): an `HC_MENU` in the existing format;
  `_pick` sends `HighCommand.request_order` instead of `_server_squad_command`. Root: Move there,
  Attack there, Support by fire there, Defend there, Follow / Support me, Fall back, Extract,
  Status, Go codes, Open map. "There" is `crosshair_ground()`.
- **HUD:** a compact squads line under the squad lines ("HAWK 2 4/4 Moving | VIPER 3 2/4 Contact")
  and request prompts with the approve and deny keys.
- **Briefing:** per-squad insertion pick and H-hour orders (Phase 2); delegation (Phase 3).
- **FOB** (`base_ui.gd`): the Hero squads block on "Squad & deploy" (Phase 1); a **Company** page
  (Phase 3): squad cards, Promote, Form, Assign, Disband, callsign and standing orders.
- **Extraction panel and debrief:** hero squads in the leave-behind warning; a debrief section each.

## 11. Phases

Each step lands on its own work branch and goes to dev only through the CI gate. Phase 0 and the
section 9 lifts can go any time their owners' branches have landed. Phases 1 and up wait for the
movement and performance phase 1, per the current priorities.

**Phase 0: groundwork, no gameplay change.**
- G1-G11, the replicated `Soldier.hc_id`, `Squad.hc_id`, `Squad.is_squadmate`.
- A test hook that spawns an extra friendly Squad of 4.
- Acceptance: the player squad's orders, rebalance, HUD and F-keys ignore the extra squad; its own
  SquadTactics fights from its own picture; every existing suite is unchanged.

**Build-now lifts (section 9).** `FollowBrain`, `ProgressWatch`, the knowledge-fair dead-ground
seam, extraction by group, soak commands through the game's RPCs, group records. Acceptance: the
soak's behaviour is unchanged in a short `--human` replay, and the pure pieces have unit tests.

**Phase 1: MVP, one hero, one team.**
- One hero squad of 4 roster members (the hero plus 3), picked in prep, on contracts rated 4 and
  up; no promotion page, no traits, no cost yet.
- HighCommand and SquadOrders with Move (one point), Hold, Defend, Follow me / Support me (station
  keeping; no auto fire yet), Regroup, Extract, and Posture.
- `Intent.LEAD`, the resting-order rule, order biases, lanes, the progress watch, succession.
- Reports: copy, unable, set, done, contact (plus intel marker), man down, succession, held up,
  sitrep, at the LZ, out. Cross-squad contact sharing.
- Map Command mode with click-select and the right-click menu; the HC panel with cards and the net
  log. Authority "anyone"; no radio requirement.
- Extraction: hero squads in the leave-behind warning, then MIA; outcomes, history and debrief
  lines.
- Acceptance: a headless test drives every MVP order to `done` or a clean `failed` with a reason
  before any UI polish; a client can order through the RPC path; nothing stalls silently.

**Phase 2: tactics orders.**
- Attack (attack position, SBF set, `forced_plan` assault, lift and shift, consolidate, abort),
  Support by fire (with danger close), Bound, Fall back.
- Queues, routes, go codes, H-hour orders from the briefing; risk levels; requests (break contact,
  reinforce, CASEVAC) with timeouts.
- Support me sets up fire for the player's squad when it's hit.
- Command menu Squads mode, the HUD squads line; `lead_anchor()` if needed.

**Phase 3: campaign heroes and several squads.**
- The Company page: promotion (ranks 1 and 2, 8-man squads), forming and assigning, wages,
  cohesion, history, traits and flaws (if approved).
- Up to 3 squads by rating and zone; bringing extra at the company's cost; the support-budget
  charge; the friendly AI budget.
- Comms realism (`hc_needs_radio`, comms lost), the BFT setting, `hc_authority = "commander"` and
  delegation, the AI LOD, the initiative request, resupply requests.
- The abstract exfil roll for squads left in the field, if approved.

**Phase 4: coordination and scale.**
- The company mutual-support scorer (SBF for, flank for, reinforce, CASEVAC for another squad),
  leapfrog between squads, `after` sequencing.
- A knowledge-limited dead-ground route planner (corridor scoring) for Pathfinder heroes.
- Squads boarding AAVs and helicopters (from `FollowBrain`'s boarding), helicopter extraction for a
  squad, a jammer cutting high command.
- Travel LOD and sync visibility filters; parallel tasking (send a squad to auto-resolve an easy
  held contract: the design doc's LRRP "works another contract" seam).
- A co-op player leading or joining a hero squad.
- Reuse: wave 6 allied troops and the named, Nemesis-style hunter squads run on the same
  Squad + SquadOrders.

## 12. Tests

Headless only, short scenarios, every suite under 5 minutes, run in the background with a hang
watch; a failing suite is rerun alone once before blaming code. Most logic sits in pure classes so
the in-level scenarios can stay few and short.

- **Pure, fast:**
  - `HcOrders.validate` rejects unknown kinds, NaN and out-of-area points, a 17-point route, a ninth
    queued order, unknown options.
  - Lane clamping keeps flank and fall-back points inside the lane; the SBF spot search never picks
    a spot whose fire lane crosses a friendly.
  - `SquadTactics.score` with merged biases: Defend picks DEFEND where the unbiased score flanks;
    Attack makes ASSAULT or SUPPRESS_FLANK win; Extract makes BREAK_CONTACT win.
  - `FollowBrain` and `ProgressWatch` on staged inputs (station, contact hold, boarding, wedged,
    detour, held up, unable).
  - The planner's inputs are intel and `known` only (knowledge fairness).
  - New `tests/company_test.gd`: promotion gates and fees; rank gates size; one squad per member and
    exclusion from `auto_squad`; authorization by rating and zone; bounded cohesion and lead growth;
    seeded traits deterministic; wages include `RANK_WAGE`; a JSON round trip; older saves get
    defaults.
- **New `tests/hc_test.gd`** (suite "hc", compound level, host, like squad_test), with a squad of 4
  spawned 30 m from the player:
  - Phase 0 scoping: `members()`, `CommandMenu.roster()` and `MapNodes.squad_ai` leave it out;
    `rebalance_squad()` keeps it; its `assess().up` is 4; a "Reloading!" 200 m away doesn't reach
    the player (`Callouts.sent[].to`); its leader is in `stream_focus()`.
  - Validation: each bad order and sender (AI, downed, a second peer under "commander", 10 orders in
    a second) is refused with a reason and no order added.
  - Move: the hero arrives within the timeout, the men within `REGROUP_M`; the net log shows copy,
    set, done in order.
  - Stuck: an unreachable point gives "held up" then `failed` with a `why`, and the next queued
    order starts.
  - Defend at a building: the men get garrison tactics; the resting-order rule keeps them on HOLD.
  - Contact: a hostile in sight gives an intel marker with "Hawk 2" within 5 s, not again within the
    gap, and another squad's `known` gets it as heard after `NET_DELAY_S`.
  - Succession: kill the hero; the leader changes, a net line, the order continues.
  - Extract: the squad is despawned at the point and its outcomes recorded.
  - Phase 2: a go code holds an order in `waiting`; SBF men suppress while the target is known and
    lift with a friendly placed within `DANGER_CLOSE_M`; an attack on one known hostile ends
    "objective secure"; a request timeout resolves by trait.
  - Phase 3: removing the hero's radio refuses orders with "No comms"; the current order continues.
- **base_test / contracts_test:** a rated-4 contract authorizes 1; the deployment records
  `hc_squads`; the charge comes from the support budget then cash; a man outside the point goes MIA,
  a dead one DEAD; the hero's history gains its line; `server_revert_deployment` restores squads.
- **map_test:** in command mode a click selects; right-click on ground lists Move and Defend, on a
  building Defend (garrison); with no squads nothing errors; marker editing outside command mode is
  unchanged (`_test_map_mouse` still passes).
- **net_test:** a client order is applied on the host and the client sees "copy"; a spoofed or
  malformed order is dropped; a late joiner's snapshot holds the queue and net log;
  `Soldier.hc_id` replicates.
- **loop_test:** one contract end to end with one hero squad, through the debrief.
- **coop_soak `--hc`** (on the soak owner's terms): a bot commands a hero squad over the lossy relay;
  checks: acknowledgement within 3 s, every order ends `done` or `failed` with a reason, no squad
  stuck over 120 s, no friendly-fire hit between squads, nobody missing at extraction. Logs go to
  R#### in B:\Contractor-test-logs.
- **perf_timing:** an HC case (8 + 8 + 8 friendly AI in a hot zone) against a budget.

## 13. Risks

1. **Scattered one-squad assumptions** leak orders, delete hero squad men or garble comms.
   Mitigation: Phase 0 first with a test per item, one marker and predicate, and a grep audit of
   `faction == &"friendly"`, `squad_slot >= 0` and `MapNodes.squad_ai`.
2. **Weak execution makes high command feel bad.** Mitigation: short phase machines over tested
   primitives, a reason for every failure, the progress watch, requests that keep the player in the
   loop, and the MVP proven headless before UI polish.
3. **An AI leader in follow logic built for a human lead** (leash, halt spots, `fall_back_point`).
   Mitigation: `Intent.LEAD`, the hero kept in the base of fire, the resting-order rule, and
   `lead_anchor()` if the 30 m leash is too tight.
4. **Host CPU and bandwidth**, with no AI LOD today and per-soldier always-sync. Mitigation: one
   squad of 4 first, the AI budget, the LOD, `FrameCost` and `perf_timing`, streaming staggered,
   later visibility filters and the travel LOD.
5. **Long routes on 2-4 km zones** (nav chunking, the zone edge). Mitigation: per-leg paths, points
   clamped inside the map, the progress watch; road or module graph routing above the navmesh if
   needed.
6. **Friendly fire from support by fire.** Mitigation: lanes, the fire-lane check, danger close,
   lift and shift, `_friendly_in_line`.
7. **Radio and subtitle overload** with three squads. Mitigation: per-squad gaps, contact
   de-duplication, urgent lines first, voice range for shouts, the full log on the panel.
8. **Co-op command thrash.** Mitigation: the author on every order, the authority setting,
   delegation; Phase 3 asks to confirm when a different peer changes an order within 2 s.
9. **Economy and roster inflation** (wages for 16-24 members, MIA cascades, XP inflation).
   Mitigation: rank wages, the support-budget charge, one grouped recovery contract per squad,
   numbers in data files marked Proposed and set from playtests.
10. **Agency:** hero squads could complete objectives for the player. The Captain decides credit or
    a pay share (question 7).
11. **File ownership and timing:** squad.gd, squad_ai.gd and callouts.gd (coop-respawn),
    extraction.gd, roster_deployment.gd and base_hub.gd (coop-extract, coop-ready), the soak harness
    (coopsoak). Mitigation: Phase 0 and the lifts wait for those branches, and edits stay at the
    seams listed.
12. **Scope:** this competes with bug fixes and the movement and performance phase. Phase 0 and the
    lifts are cheap; the rest is sequenced after.

## 14. Open questions for the Captain

Each has a recommendation; the Captain's answer replaces it.

1. **Who are the men?** Roster members from the MVP (wages, permadeath, MIA: losses hurt), or
   contractors attached per contract with no persistence? *Recommended: roster members from the
   MVP; spawning roster members outside the slots and settling them already work.*
2. **Where do heroes come from?** Promoted veterans only, or also named veterans hired from the
   board at higher reputation? *Recommended: promotion first, the hiring board in Phase 3.*
3. **Squad size:** 4 then 8 by rank, or 8 from the start? *Recommended: 4 in the MVP, 8 with rank 2.*
4. **How many squads?** Rated 4 gives 1, rated 5 gives 2, hot +1, at most 3; bring extra at the
   company's cost; does the client's support budget pay for authorized ones? *Recommended: as
   written.*
5. **Who commands in co-op?** Anyone (today's squad rule) or one commander seat with delegation?
   *Recommended: anyone in the MVP, the commander seat as a setting in Phase 3.*
6. **A squad left in the field:** straight to MIA, or an abstract exfil roll (survivors home a day
   late, the rest MIA with one grouped recovery contract)? *Recommended: MIA in the MVP, decide the
   roll after playtests.*
7. **Objective credit:** when a hero squad clears or destroys a target, full credit, a pay share, or
   none?
8. **Radio and fog:** does high command need a radio (commander and hero), and are live squad
   positions shown by default with last-reported positions at higher difficulty? *Recommended: no
   radio and live positions in the MVP; both as settings in Phase 3.*
9. **Traits and flaws:** yes or no, and which? (The design doc lists personalities and perk trees
   as stretch.)
10. **Keys:** the `high_command` default (U proposed, checked against `Controls.KEYS`) and the
    approve / deny keys, avoiding the Ctrl and Alt menus.
11. **Callsigns:** the hero's own ("Hawk 2"), or the company's name plus a number ("Saber 2..4")
    with the player squad "Saber 1"?
12. **Later:** may a co-op player lead or join a hero squad, keeping the player-scalable rule at
    squad level?

## Sources

- The three judged designs (Command-First, AI-first, Heroes on the Books), 2026-10-14, and the
  judges' notes.
- dev `fc98665`: scripts/ai/squad.gd, tactics.gd, squad_ai.gd, doctrine.gd, roles.gd;
  scripts/ui/command_menu.gd, map_view.gd, map_screen.gd, map_markers.gd, map_nodes.gd,
  map_extraction_panel.gd, callouts.gd; scripts/player/hud.gd; scripts/actors/soldier.gd;
  scripts/world/compound_level.gd, zone_level.gd; scripts/campaign/roster.gd,
  roster_deployment.gd, base_hub.gd, contracts_gen.gd, economy.gd, enemy_response.gd,
  reinforcements.gd, extraction.gd, briefing.gd, radio_chatter.gd; data/prices.json;
  docs/squad_design.md, contractor_design_doc.md, mission_brainstorm.md, build_plan.md.
- `test/coop-soak` `33d3e87` and `test/coop-soak-stuckbots` `25dcf0c`: tests/coop_soak.gd.
- `fix/coop-extraction` `906053c`, `feat/fob-ready-up` `8ebcdc3`, `fix/respawn-own-kit` `2adab4f`
  (file lists and doc comments only).
