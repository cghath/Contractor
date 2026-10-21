# Mission variety (2026-10-15)

The Captain: "I've been doing the same few missions for a while now ... it's boring." Five types
join raid / HVT capture / hostage rescue / intel grab. Definitions and knobs are in
`data/contracts.json` (`mission_types`, each scenario type's `scenario_knobs`; all numbers
Proposed). `ScenarioGen` (scripts/campaign/scenario_gen.gd) builds a scenario contract's objectives
with positions in zone metres; `MissionScenario` (scripts/campaign/mission_scenario.gd, one host-only
node per level, installed by `MapNodes.install`) plays them and marks objectives done or failed.
Everything is server-authoritative; vehicles, soldiers and people replicate like any others.

| Type | Objectives | Outcome |
|---|---|---|
| `convoy_ambush` | Required: stop the convoy (every cargo truck destroyed, disabled or its crew down). Bonus 20%: carry the cargo crate out. | A cargo truck reaching the route's far end = fail. Convoy sets out `depart_s` (7-10 min) after deployment: 1-2 `maxxpro` cargo trucks and 1-2 escort technicals with crews (the contract's true force, max 14). Any hit stops the convoy and the crews dismount and push to the ambush. The crate drops beside the first cargo truck when it is out. |
| `defend_hold` | Required: hold the module's position (`radius_m`) for `hold_s` (7-10 min). | The clock runs while one of ours stands in it. Waves (Reinforcements.server_send) from 3-4 bearings, first after 60 s, then every 80 s, only once the hold has started. Lost when none of ours is in it and the enemy is, for 15 s, or abandoned for 90 s. The module has no garrison (`no_garrison`). |
| `crew_rescue` | Required: get `need` (crew minus 1) of 2-4 crew out. Bonus 15%: all of them. | UH-60 wreck plus crew as friendly persons (HVT ids): one has a broken shin (carry), one an arm wound. Delivery and loss come through People (`server_hvt_delivered`/`lost`). Waves converge on the site from 150-240 s in, every 150 s. |
| `sabotage` | Required: take out the target, one of the module's sabotage sites: `fuel` (a fuel store: the compound's generators and drums, steel drum stores at the HQ and QRF base), `park` (a vehicle park: 2-3 technicals parked by an outpost, checkpoint, compound, QRF base or HQ) or `mast` (the comms site's mast). Bonuses: the AA gun (10%), never spotted (20%). | Fuel and mast: the cache logic (a placed charge within `charge_kill_m`, or voxels under `cache_destroyed_share`; steel shrugs off grenades). Park (`destroy_vehicles`, 2026-10-20): MissionScenario parks the vehicles when the contract goes live (hostile, empty, out of the zone save while whole) and marks it done once every one burns, is a wreck or can't drive (a charge stuck to each). A bridge waits for roads that cross water. |
| `recon` | Required: observe 2-4 sites (distinct modules) from `observe_m` for `dwell_s` with a line of sight. Bonus 25%: never spotted. | "Never spotted" (`undetected` kind): fails the moment any hostile is in contact with a friendly; stands at end of deployment (`Objectives.server_deployment_ending`). |

`defend_hold` and `crew_rescue` set `own_waves`: the standard reinforcement timer is pushed out
(`Contracts.reinforcement_tuning`) and MissionScenario sends the waves, aimed at the point. In hot
zones EnemyResponse keeps the aim. Convoy, rescue and recon have no module_id (no garrison inflated
by the true force); the defended module does. New objective kinds: `convoy`, `hold_point`,
`rescue_crew`, `recon_site`, `undetected` (Objectives); guidance text in `objective_helper.gd`.

A module site with its own `"kind"` plays that kind (the park); the sabotage template lists
`"site": ["fuel", "park", "mast"]` and the generator picks one the module has. The convoy's cargo
is a `supply_crate` (any carried out counts: a two-handed carry keeps no state).

Tests: `missions_test` "Mission variety: from the board, played through" (task 8, 2026-10-20) takes
each of the five as the board offers it in the hosted zone and plays it through the objective code
with no test hooks, sabotage once each at a fuel store, a vehicle park and a mast;
`contracts_test` "Mission variety on the board" checks they come up in fitting zones. Also
`missions_test` "Mission variety" (generation in every zone, then each type deployed to
success and failure with debrief and pay) and `contracts_test` (nine types on the board). Test hooks:
`MissionScenario.server_advance(s)`, `server_neutralize_convoy`, `server_mark_site`, `server_spotted`.

Not yet done: a real playtest of convoy pathing (straight waypoints, no zone roads), wreck placement,
and pay tuning.

# Missions 2 (Captain's list, 2026-10-20)

Three more types and night and weather contracts. Definitions are in `data/contracts.json`
(`hvt_kill`, `crash_site`, `overwatch`; settings `conditions`). All numbers are Proposed.
MissionScenario plays them in its own section ("Missions 2", the run kinds below).

| Type | Objectives | Outcome |
|---|---|---|
| `hvt_kill` | Required: `kill_hvt`, the commander dies (People ledger, `server_hvt_lost`) or is brought out (`server_hvt_delivered`). Proof: an optional `extract_item` with `proof` and `withheld_share` 0.4, his ID papers (`hvt_id_card`, carried on him, its own intel id). Bonus 10%: his phone. 90 min clock. | Run `hvt_kill`: the HVT (a person) walking between the module's buildings (`hvt_knobs.routine_sites`), with 2-4 guards in their own squad who follow him. Killed without the papers, the debrief holds back 40% of the pay (`withheld`). Brought out alive or dead, the man is the proof. |
| `crash_site` | Required: carry the flight recorder (`black_box`, 14 kg, two-handed) out. Bonuses: the crew's ID tags (10%), and the wreck denied (15%, `destroy_wreck`: a charge within 7 m). | Run `crash`: a wreck of `ah1z`, `uh60` or `vtol_petrel` 240 m from the module, with the recorder and the tags beside it. Waves come from 120-210 s, the gap shrinking 15 s a wave from 150 s down to 75 s. |
| `overwatch` | Required: `overwatch`, at least all-but-one of 1-2 friendly trucks through. Bonuses: every truck through (15%), ours on the position until it is through (10%, lost after 30 s off it). | Run `overwatch`: the route runs 110 m past the module, 2-3 ambush teams of 3-4 lie 45 m off the road, and the position sits 300 m the other side (moved to the highest ground within 120 m when the contract goes live). The convoy rolls after 20 s with ours on the position, or after 600 s at the latest. A truck that burns, is a wreck, can't drive or has its crew down is lost (its crew gets out). Crews are `vehicle_crew` and `allied_element`: no squad slot, and not counted in the debrief. |

Run kinds and their keys (checkpointed by `ScenarioCheckpoint`, nodes kept by identity):
- `hvt_kill`: `t`, `crew` [the HVT], `ambush` [his guards].
- `crash`: `t`, `wave`, `next_s`, `waves`, `wreck`. The items are WorldItems found by the
  params' `box_uid` and `tags_uid`; they are put back on a return only when gone and not picked up.
- `overwatch`: `t`, `phase`, `on_s`, `away_s`, `through`, `route`, `vehicles` (the enemy convoy's
  entry shape), `ambush`.

**Night and weather** (`ContractGen.roll_conditions`, rolled on its own generator so the boards
stay as they were):
- Night: chance 0.18 times the type's `night_type` weight. For example recon 45%, raid 31.5%,
  overwatch 11%, client escort 9%. The insertion hour is between 21:30 and 03:30.
- Weather: overcast 12%, fog 6%, rain 7%, storm 2%, each times the terrain preset's
  `weather_terrain` weight, rarest first, at most one. Fog: 11.8% on the coastal lowland, about
  1.5% on the salt flats.
- Pay share: night 10%, fog or rain 5%, storm 10%, overcast nothing. It goes into the base pay.
- Never for the safe job or in-zone (radio) contracts. The keys are `hour`, `weather` and
  `conditions` on the contract.
- The deployment's level is `BaseHub.contract_level_info`: the zone's layout with the contract's
  `hour`/`weather` and `DayNight.CONTRACT_SKY`, which DayNight takes over the zone's save. A
  resume of the save has no such key.

Tests: `contracts_test` "Missions 2 on the board" and "Night and weather contracts" (the rates
over 4000 rolls, the board, the pay, the level info); `missions_test` "Missions 2 ... played
through" (each type to success, plus a fail or pay-less case, with the debrief), "Missions 2:
checkpoints across return and reload", "Night and weather contracts: into the deployed zone's
DayNight".

Not done: a photo-with-a-camera proof (no camera item exists yet), a real playtest of the
friendly convoy's driving and the ambushers' reaction to it, and pay tuning.
