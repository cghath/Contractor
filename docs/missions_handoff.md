# Mission variety: handoff to cghath (2026-10-15)

The Captain asked for more mission variety ("I've been doing the same few missions for a while now
... it's boring") and handed this branch to cghath to finish. Branch `feat/mission-variety-1`, WIP
at e816d80, on top of dev v0.4.7 (9b1f774).

## The brief (Captain's picks, all four, build straight away)
1. **Convoy ambush / intercept:** an enemy convoy drives a road route; stop it and take the cargo, or destroy it.
2. **Defend / hold:** hold an outpost/village against waves from several bearings for a set time.
3. **Rescue downed helo crew:** a UH-60 wreck with wounded crew; enemies converge; get the crew to extraction.
4. **Sabotage / recon:** destroy a target (comms/fuel/AA), or observe/mark sites unseen (bonus if never spotted).

## What's built (untested in full)
- Contract types `convoy_ambush`, `defend_hold`, `crew_rescue`, `sabotage`, `recon` in `data/contracts.json`,
  generated on the board, with briefings and new objective kinds in `objectives.gd`.
- `scenario_gen.gd` (objectives and positions) and `mission_scenario.gd` (host-only runtime node that plays them).
- Touched: `contracts.gd`, `contracts_gen.gd`, `zone_level.gd`, `map_nodes.gd`, `objective_helper.gd`.
- Convoy: hostile vehicles with crews drive the route and drop a cargo crate when the truck is stopped;
  escaping fails the objective. Hold: waves, the position can fall. Rescue: wreck plus wounded crew,
  converging waves. Recon: observe sites, never-spotted bonus. Sabotage: destroy the target, unseen bonus.
- Test hooks (convoy/rescue can't run fast in tests): `server_advance`, `server_neutralize_convoy`,
  `server_spotted`, `server_mark_site`.

## What's left
1. `tests/contracts_test.gd` "every offer is sound ... a target module in the zone's layout" fails (R1214):
   the new types have no `site`/`module_id`. Give scenario types an exception there (or a real module).
2. Re-run `smoke missions contracts` (the route-with-fewer-than-3-points failure in R1212 was fixed in
   e816d80 but not re-run); check `world` and `loop` suites with the new types.
3. Playtest each type once in a real zone (convoy pathing on zone roads, wave spawn points, the wreck's
   placement), then tune pay and difficulty.
4. Write `docs/missions.md` (what each type does, its knobs).
5. Push, get CI green, then merge to dev.

Note: a hot-zone pass (`feat/hotzones`) is in progress on Captain's side and is meant to draw from
whatever contract types exist, so these new types should plug into hot zones once both land.
