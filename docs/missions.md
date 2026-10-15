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
| `sabotage` | Required: destroy the target (the module's cache or radio mast). Bonuses: the AA gun (10%), never spotted (20%). | Existing charge/explosive destroy logic. |
| `recon` | Required: observe 2-4 sites (distinct modules) from `observe_m` for `dwell_s` with a line of sight. Bonus 25%: never spotted. | "Never spotted" (`undetected` kind): fails the moment any hostile is in contact with a friendly; stands at end of deployment (`Objectives.server_deployment_ending`). |

`defend_hold` and `crew_rescue` set `own_waves`: the standard reinforcement timer is pushed out
(`Contracts.reinforcement_tuning`) and MissionScenario sends the waves, aimed at the point. In hot
zones EnemyResponse keeps the aim. Convoy, rescue and recon have no module_id (no garrison inflated
by the true force); the defended module does. New objective kinds: `convoy`, `hold_point`,
`rescue_crew`, `recon_site`, `undetected` (Objectives); guidance text in `objective_helper.gd`.

Tests: `missions_test` "Mission variety" (generation in every zone, then each type deployed to
success and failure with debrief and pay) and `contracts_test` (nine types on the board). Test hooks:
`MissionScenario.server_advance(s)`, `server_neutralize_convoy`, `server_mark_site`, `server_spotted`.

Not yet done: a real playtest of convoy pathing (straight waypoints, no zone roads), wreck placement,
and pay tuning.
