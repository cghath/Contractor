# Wave 4B handoff: wire the mission loop end to end, and the hot zone

**For:** Noah (Captain's side), 2026-10-11. **From:** cghath's side, after wave 4A landed on
`dev` (5f5eb0e, all 20 suites passing).

Read [build_plan.md](build_plan.md) (the agent rules and "Waves 3 to 7") and the design doc's
"Core loop", "Missions: contract zones and hot zones", "NPC squad and roster" and "Player
faction supports" first. This file only says what 4A left loose and what 4B has to join.

## Goal

One playable loop, hosted from the main menu, that a friend can join at any point:

**base (FOB) -> contract board -> negotiate -> prep (kit up, squad, roles, supplies) -> map
briefing -> deploy into a generated zone -> objectives (and civilians, HVTs, intel) ->
reinforcements build -> extraction -> debrief (pay, salvage, reputation) -> back at the base
-> days pass (wages, recovery, hiring pool)**, then the next contract. Then the **hot zone**:
one deployment, several contracts.

## What 4A built (each works and is tested on its own)

| Part | Entry point today | Main code |
|---|---|---|
| World scale | Main menu **Host test zone**, or `--zone [id]` | `scripts/world/zone_*.gd`, `ZoneLevel` (extends `CompoundLevel`), `ZoneDef` (`data/zones.json`, `generate(seed, size_m, types, count)`), `ZoneModule` (`point(kind, i)`, `points(kind)`), `ZoneModules` (`POINTS`, `GARRISON`, `LOOT`), `ZoneNav` |
| Contracts and economy | Main menu **Contract board (offline)** | Autoloads `Economy` (`scripts/campaign/economy.gd`) and `Contracts` (`contracts.gd`, `contracts_gen.gd`, `contracts_debrief.gd`), `MissionRegistry` (`missions.gd`, `data/contracts.json`), `Objectives` (`objectives.gd`), UI `contract_board.gd`, `debrief.gd`, `shop.gd`, `objectives_panel.gd` |
| People | Main menu **people** checkbox (compound only) | Autoload `People` (`scripts/people/people.gd`), `person.gd`, `hvt_ai.gd`, `delivery_point.gd`, `people_layer.gd` |
| Base hub and roster | Main menu **Campaign: host at the base (FOB)** | `BaseHub` (`base_hub.gd`), `BaseLevel`, `Roster`, `Hiring`, `RosterDeployment`, `BaseArmory`, `BaseTerminal`, `BaseEconomy` |
| Map, briefing, extraction | **M**; main menu **Play the test contract** | `Briefing` (`briefing.gd`, `debug_open`), `BriefingScreen`, `Extraction` (`extraction.gd`, `END_GROUP` handlers), `Reinforcements` (`reinforcements.gd`), `scripts/ui/map_*.gd` |
| Joining | every level | `LevelSwitch.load_level(parent, info)`: the only level swap and join handshake (host sends `level_info()` + campaign flag; client builds the same level first). `BaseHub.server_switch_level(info, zone_id)` swaps for everyone. |

The campaign save is the `Campaign` autoload, one section per part (`economy`, `contracts`,
`roster`, `base`...). Zone saves are per zone id (`BaseHub.zone_save_id`).

## The seams 4B has to join (found by reading the merged code)

1. **Base money runs on a stand-in.** `BaseEconomy` (base_economy.gd) calls `Economy.funds()`,
   `try_spend()`, `credit()`, `item_price()`, `shop_catalog()`, `pay_wages(amount, days)`,
   `charge()`, `request_recovery_contract(info)`, `respawn_price()`, and falls back to its own
   cash when a method is missing. The real `Economy` names them `cash()`, `spend()`,
   `add_cash()`, `price_of()`, `weekly_bill()`/`pay_week()`, ... and has a `wages_provider`
   hook. Join them (adapter methods on `Economy`, or point `BaseEconomy` at the real names) so
   there is one bank, the roster's wages feed `Economy.weekly_bill()` through
   `wages_provider`, the base terminal's shop is `Economy.server_buy` with `purchase_sink`
   putting goods in the armory stash, and an MIA squadmate opens a recovery contract
   (`Contracts.server_add_offer`).
2. **The board doesn't go through the base.** `contract_board.gd` calls
   `Contracts.server_start_deployment([cid])` straight away and has a debug "end deployment".
   Instead: accept on the board -> `BaseHub.begin_prep(contract, zone_kind, zone_id, "",
   level_info)` -> prep at the base -> `Briefing.server_open(contract, zone)` -> on the
   briefing's start, `BaseHub.server_deploy({"level": level_info})` and
   `Contracts.server_start_deployment(cids, zone_id, origin)` together.
3. **Contracts don't know the generated zones.** `data/contracts.json` lists zones whose
   `modules` are all `["compound"]`, and `MissionRegistry` only has sites for the compound.
   `data/zones.json`/`ZoneDef.generate` know the real modules (compound, outpost, village,
   checkpoint) and `ZoneModules.POINTS` has their objective, cache and intel points. Make a
   contract's zone a `ZoneDef` (fixed from zones.json, or generated from the contract's seed),
   give every module type sites the mission types can use, and place each objective at its
   module's point plus the module origin (`Contracts.server_start_deployment(..., origin)`
   already offsets one module; make it per module).
4. **Insertion and extraction points.** `ZoneLevel.insertion_points()` and
   `extraction_points()` exist but nothing uses them. The briefing offers insertion points and
   `Extraction` makes landing zones: feed both from the zone. Spawn the squad at the chosen
   insertion point.
5. **People don't reach the contract.** `People` emits `civilian_casualty`, `hvt_delivered`,
   `intel_banked`; `Contracts` has `server_civilian_casualty(info)`,
   `server_hvt_delivered(hvt_id, alive)`, `server_hvt_lost`, `server_items_banked(items)`,
   `server_cache_destroyed(id)`. Nothing connects them yet. Also spawn civilians, the HVT and
   intel in the zone's modules for the contract (the people layer is compound-only today).
6. **Who ends a deployment.** `Extraction` emits `deployment_ended(report)` and calls every
   node in `END_GROUP`. Make the debrief and the base both take that one report:
   `Contracts.server_end_deployment(report)` (pay, salvage, debrief on every peer) and
   `BaseHub.server_end_deployment(extracted, return_to_base)` (MIA, roster gear home, days,
   back to the base), in that order, once.
7. **Reinforcements** start with the deployment (`Reinforcements.server_start(tuning)`), sized
   from `Contracts.enemy_force(cid)` (the true threat, which the briefing may have
   understated), and spawn at the zone's edge (`edge_point` uses the level).
8. **Days pass.** A deployment's days (contract `days`), travel and recovery go through
   `Economy.advance_days(days, reason)` once, and the base's recovery days and hiring pool
   refresh follow `Economy.day_advanced` (today `BaseHub.day()` keeps its own count: make it
   read the economy's clock).
9. **Respawns** in a deployment use `BaseHub.server_count_respawn()` (4 free in a contract
   zone, 8 in a hot zone, then bought through the economy).

## The hot zone (after the loop works)

From the design doc ("Missions: contract zones and hot zones", decided unless marked):

- One faction offers every contract in the zone; the squad holds several at once, takes more
  inside the zone (radio contracts: `Contracts.server_radio_contract`), resupplies and banks
  loot mid-zone, and the deployment ends at extraction. No reputation minimum, considerably
  harder.
- Size 8-16 km² (being confirmed: twice the area of a contract zone; if Captain meant twice the
  width it's 16-32 km²). `ZoneDef.generate(seed, size_m, ...)` takes the size; check streaming
  and navigation hold up at that scale.
- Layout (proposed): one enemy HQ, 3-6 outposts, road checkpoints, roaming patrols, 1-2 QRF
  bases with vehicles (vehicles are wave 5: leave the QRF on foot until then). Contracts sit
  on or near those sites. Destroying parts weakens the enemy across the zone: a QRF base
  stops its reinforcements, a comms site slows their response, killing officers makes
  patrols less coordinated.
- Alert level: starts calm; noise, sightings and losses raise it (more patrols, closed
  checkpoints, QRFs on standby); it eases when the squad goes quiet. No meter on screen:
  players read it from patrols and checkpoints (and radio chatter, if a looted enemy radio is
  in: optional here).
- Enemy pressure rises the longer the squad stays (bigger QRFs, hunter teams). The
  reinforcement timer is the start of that.
- Staged insertion at the zone edge (helicopter and AAV insertion are wave 5).

## Suggested split (the same file ownership as 4A, so parallel agents don't collide)

1. **Loop wiring** (`base_hub.gd`, `base_economy.gd`, `economy.gd`, `contract_board.gd`,
   `briefing.gd`): seams 1, 2, 6, 8, 9.
2. **Missions in zones** (`missions.gd`, `contracts.gd`, `data/contracts.json`,
   `data/zones.json`, `zone_modules.gd`, `people_layer.gd`): seams 3, 4, 5, 7.
3. **Hot zone** (new hot-zone files, `ZoneDef` hot layouts, alert level, faction pressure),
   after 1 and 2 merge.

## Acceptance (new checks, two processes where it says client)

- Host a new campaign at the base; a client joins; accept a contract on the board; prep; the
  briefing opens for both; pick an insertion point; deploy: both are in the generated zone at
  that point with the roster squad.
- Objectives sit in the zone's modules; clearing, carrying out intel, delivering a cuffed HVT
  and destroying a cache each complete their objective on both peers.
- A civilian killed by the squad shows in the debrief as a fine; the 8th voids the contract.
- Extraction at a zone landing zone: the debrief shows pay, salvage, casualties and
  reputation on both peers; everyone is back at the base; a squadmate left behind is MIA and
  a recovery contract is on the board; the cash in the base terminal is the economy's cash.
- Days advance once per deployment; wages are paid weekly from the roster; a wounded
  squadmate's recovery counts down with the same clock.
- Save at the base, quit, load: cash, roster, stash, board and held contracts come back.
- Hot zone: two contracts in one deployment, a radio contract arrives, the alert level rises
  with noise and losses and falls when quiet, and destroying a QRF site stops its waves.

## Rules that still hold

- No revive, ever (the medical rules are Captain's side's; 4B doesn't touch them).
- Values the design doc doesn't fix are named constants or data marked "Proposed:".
- The host decides everything shared; every new state replicates to all peers and late
  joiners (use `LevelSwitch` for any level change).
- Mission types stay placeholders (clear a compound, recover an HVT, retrieve intel, destroy a
  cache) behind `MissionRegistry`, ready for Captain's mission types and the mission
  brainstorm doc.
- Tests: `GODOT=... tools/run_tests.sh` (20 suites; set `CONTRACTOR_TEST_TAG` and
  `CONTRACTOR_PORT` when running two at once). CI runs every suite on push.

## Open questions for Captain

1. A voided contract (8 civilian casualties): does it claw back the 30% advance? Today it
   does (`void_claws_back_advance` in `data/contracts.json`).
2. In a hot zone with several contracts, is the 8-casualty void counted per contract or across
   the deployment? Today: across the deployment.
3. Hot zone size: 8-16 km² (twice the area) or 16-32 km² (twice the width)?
4. Should the contract board stay reachable anywhere but the base (a laptop at the FOB only,
   or also from the main menu offline as now)?

### Captain's answers (2026-10-11)

1. **Voided contract and the advance:** each contract states its clawback term on the board,
   the advance follows it on a void: **none** (keep it all), **prorated** (keep the share of
   objectives done) or **full** (give it all back). Strict clients use full; shady clients use
   none but pay less. This replaces the single `void_claws_back_advance` flag. Later (not 4B):
   adjust it by intent, collateral against deliberate.
2. **The 8-casualty void** counts **across the deployment** (as today).
3. **Hot zone size:** 8-16 km² for now, **10-20 km² at most**. **Update (2026-10-12): start at 16 km²** (a 4,096 m square; sides are multiples of 128 m).
4. **The contract board:** at the FOB, on the LHD, and **in the field with a field radio**
   (builds on `Contracts.server_radio_contract`).
5. **Role kits:** players do **not** deploy in their role kit (`player_role_kits` stays off).
6. **Roster identity** (already on `dev` as 4B groundwork): a hire is one person, rolled at
   hiring and kept by the roster (`Names.person`, `Roster.identity`).

## Progress (Captain's side)

### Part 1, loop wiring (seams 1, 2, 6, 8, 9): done (2026-10-11, `feat/wave4b-loop`)

- **One bank (1):** `BaseEconomy` is a thin adapter onto `Economy` (no stand-in cash):
  `funds` = `Economy.cash()`, spending and charges go through its ledger, the shop's prices and
  catalogue are `Prices`, the base terminal's purchases are `Economy.server_buy` with
  `purchase_sink` putting them in the armory stash, salvage and what's brought out land there
  through `stash_sink`, and an MIA squadmate opens a recovery contract
  (`Contracts.server_add_recovery`). The respawn price is `prices.json` "respawn".
- **One clock (8):** `BaseHub.day()` is `Economy.day()`; resting is `Economy.advance_days`;
  the roster's recovery and the hiring board follow `Economy.day_advanced`; the roster's wages
  are the weekly bill's (`Economy.wages_provider`), with upkeep and loans. A deployment's days
  pass once, in the contract's debrief. Saves from before keep working (their base "day" gives
  way to the economy's).
- **Board -> base (2), with one change of order:** accepting a contract starts the prep at the
  base (`BaseHub.begin_prep_contract`; the board's "Prepare deployment" and the base screen's
  "Prep" pick another held one). Deploy takes the squad into the zone and **the briefing opens
  there**, not at the base: the map draws the loaded level, so a briefing at the FOB would show
  the FOB. Its start makes the contract live (`Contracts.server_start_deployment`); the
  briefing's own flow moves the squad to the insertion point, opens extraction and starts the
  reinforcement timer.
- **One end (6):** `BaseHub.end_deployment(report)` (an `Extraction.END_GROUP` handler) turns
  extraction's report into the debrief's (`Contracts.report_from_level` for who got out, HVTs,
  and a "bank" list for bodies carried in and items set down: people bring their own gear
  home), then `Contracts.server_end_deployment` (pay, clawback, fines, reputation, days), then
  `BaseHub.server_end_deployment` (MIA, recovery contracts, gear home) and back to the base.
- **Respawns (9):** `BaseHub.server_count_respawn` on the one bank (4 free / 8 in a hot zone).
- **Clawback terms (Captain's answer 1):** every contract carries "clawback": "none",
  "prorated" (the share of required objectives not done) or "full", shown on the board and
  in the briefing; fixers' jobs are none, the safe job full, the rest rolled
  (`contracts.json` "clawback_terms": weights and the lower pay of a lenient client).
- **Recovery contracts:** a squadmate left behind alive gets a recovery contract on the board
  (pays nothing, runs `recovery_offer_days`). Deployed on it, they wait where they were left,
  join the player who reaches them, and count as brought out inside the extraction point;
  completed brings them back, anything else (or the offer running out) writes them off.
- Tests: the base suite's "The loop" runs board -> prep -> briefing -> extraction -> debrief
  -> base and a recovery end to end; contracts suite for the clawback terms.

### Part 2, missions in zones (seams 3, 4, 5, 7): done (2026-10-11, `feat/wave4b-missions`)

Built from `docs/mission_brainstorm.md` ("First mission types to build": raid, HVT capture,
hostage rescue, intel grab). Details in CHANGELOG "Wave 4B part 2".

- **Mission types:** the four placeholders are replaced by Captain's first four. A type lists
  the module types it plays in; a contract picks one of its zone's modules as its target
  (`module_id`) and each objective a site of it (a raid picks the AA gun or the cache). HVT
  capture and hostage rescue run on a forgiving clock (90 and 75 min, Proposed).
- **Zones (3):** every contract zone is a generated `ZoneDef` (`contracts.json` "def": seed,
  size; `MissionRegistry.zone_def`), the same layout every visit. Accepting a contract preps it
  with that level, and its objectives sit at the target module's sites wherever the module
  stands (`Contracts.module_origin`, per contract, also for radio contracts). Every module type
  has sites (`contracts.json` "modules"); the outpost got an AA emplacement, the village and
  checkpoint crate caches. Hot zones use the same at contract-zone size until part 3.
- **Insertion and extraction (4):** part 1 already feeds the briefing the zone's insertion
  points and landing zones and moves the squad to the chosen one; part 2 makes each landing
  zone a delivery point (HVTs delivered, intel banked as soon as they're there).
- **People (5):** `Contracts.contract_live` -> `PeopleLayer.server_contract_content`: the HVT or
  hostage, intel pieces with their own ids, civilians in the zone's modules. The People ledger
  feeds `Contracts` (deliveries, intel carried out, civilian casualties once each, a dead HVT
  via the new `People.hvt_lost`); `People.reset_deployment` at each deployment's start.
- **Reinforcements (7):** `Contracts.reinforcement_tuning(cid)` from the true force, applied
  when the contract goes live; waves enter at the zone's edge nearest the squad but 350 m out.
- **Breaching charges** (Captain, mid-part): placed like Arma Reforger's with a ghost, on any
  surface, riding people and moving bodies (`scripts/combat/charges.gd`). Suicide bombers on
  foot and VBIEDs (Captain: "that allows suicide bombers on foot and in vehicles in the ME")
  are an AI behaviour for later: the charge side is ready.
- Tests: new `missions` suite (generation, a four-contract deployment in a zone, deliveries,
  intel ids, a civilian counted once, a raid by charge, charges on the ground and riding a
  person, a dead HVT, the clock, reinforcement sizing and the edge, the briefing's markers).

Captain's answers (2026-10-11), built on `feat/wave4b-followups`: target garrisons = the
contract's true enemy count (other modules 4); zip cuffs stay a base-shop buy, but an HVT
capture works without them (an uncuffed captive bolts when left alone; lootable cuffs in zones
are on the ChrisPlan backlog); real names for HVTs, hostages and civilians; suicide bombers and
VBIEDs go in wave 6. Up to 2 AI squadmates escort an HVT (command menu), and a wounded HVT is a medical
priority (escorts treat him until a medic takes over). See CHANGELOG.

### Part 3, the hot zone: in progress (Captain's side, 2026-10-12)

Started while cghath's side starts wave 5. Size: 16 km² (4,096 m square). The base hub stays
as it is through part 3; wave 5 makes it the first friendly FOB (see the wave 5 note in
`ChrisPlan_handoff.md`). QRF bases stay on foot until wave 5's vehicles; part 3 leaves hooks for
vehicle QRFs and helicopter or AAV insertion.

**Captain's part 3 decisions (2026-10-12).** Numbers are Proposed.

- **Layout:** one enemy HQ, 3-6 outposts, road checkpoints, roaming patrols, 1-2 QRF bases
  (on foot until wave 5's vehicles).
- **Alert (realistic: the enemy knows only what its people see, hear and report):**
  - Local first: the unit that sees or hears reacts at once; the zone learns only when it
    radios in (15-60 s by quality, longer under fire). Killed before reporting, nobody knows.
  - Sound: unsuppressed rifle fire heard to about 400-800 m (terrain and buildings), suppressed
    about 50-100 m, explosions about 1-1.5 km. Hearing gives a rough direction, not who.
  - Check-ins every 15-20 min per post and patrol; a missed one gets a call, then a look.
    Bodies and blown sites are found by passing patrols and reported.
  - The enemy works from a last known position with an uncertainty circle that grows with
    time; searches and hunter teams go there.
  - Comms: destroying the comms site slows or stops reports; a jammer stops a unit reporting.
  - States per area and for the zone: Normal, Suspicious (stand-to, a patrol goes to look),
    Alerted (posts manned, checkpoints closed, QRF on standby, patrols doubled), Engaged (QRF
    launches to the reported position). Cooldown is slow: Engaged to Alerted after about 20
    min without contact, Alerted to Suspicious after 1-2 hours; a zone you were loud in stays
    twitchy for the deployment.
  - No meter on screen: players read it from behaviour and from **looted enemy radio chatter,
    which is in part 3** (hear the zone's alert and sometimes patrol or QRF moves until they
    switch frequencies).
- **Pressure (long term, from what the squad does, not the clock):** firefights +2 each (more if
  long), kills +0.5, a patrol wiped out or not reporting +3, explosions +1, objectives +5, an
  outpost or checkpoint destroyed +8, an alarm raised +3; quiet: -1 per 10 min; time only +1
  per 30 min. At 10: bigger QRF waves, patrols in pairs. At 20: a second QRF, checkpoints
  closed. At 35: hunter teams (4-6 good troops to the last known position: track, flank,
  smoke). At 50+: more hunters, the HQ reinforces its sites. A destroyed QRF base removes its
  waves; a destroyed comms site halves pressure gain; dead officers make hunters less
  coordinated. Generic hunters here; named Nemesis-style hunters with wave 6. Staying longer
  pays more (decided).
- **Radio contracts need a field radio item** in the squad (the board in the field).
- **Insertion:** on foot from 2-3 edge points picked in the briefing; each point keeps a
  "method" field (foot now; helicopter and AAV in wave 5); the first point out of sight of the
  nearest outpost. AI hold while the briefing is open (on dev).
- **The base hub stays as it is** until wave 5 makes it the first friendly FOB.

**Stage 4 as built (2026-10-12).** Numbers are Proposed.
- `RadioChatter` (`scripts/campaign/radio_chatter.gd`, hot zones, host): a new item
  `enemy_radio` (tags `radio`, `enemy_radio`; not in the shop, priced $250 for selling) goes to one man in four of
  every garrison (`ZoneLevel.RADIO_EVERY`). While a player or squad AI not dead carries one, the
  squad hears the enemy net as subtitles (Callouts, speaker "Enemy radio"): reports ("Outpost 2:
  shots heard, to the north."), the zone standing to or down, and 60% of QRF waves setting out.
  Compass words only, north is -Z; 85% of lines are caught, one per 5 s.
- The switch: a body or missed check-in reported after the radio was taken changes frequency
  300-600 s later ("go to alternate. Out."). The radios held then are stale; one more radio
  taken off a body listens in again (dropping a stale set and picking it up again also does:
  kept forgiving). Patrol moves aren't heard yet (EnemyResponse has no hook for it).
- Radio contracts: `Contracts.radio_contract_problem()` ("" or a reason) gates
  `server_radio_contract`: hot zone and a field radio in the squad (tagged `radio`, not
  `enemy_radio`: a looted set can't reach the employer). No board UI calls it yet.
