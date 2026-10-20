# Local repairs after the executive audit

These repairs follow the audit of `68a1b8336013a8170b22d2a4b66e15a626feb84b`.
They remain local working-tree changes; no push, merge or publication was performed.
The audit reports describe the original checkout. This file tracks subsequent repairs.

**Progress: 10 findings fixed on branch `cghath/exec-audit-2026-10-19`. A2-10, A2-11 and A2-12 sit in Claude's files, so they are logged as F-05, F-06 and F-04 in `docs/audits/followups.md`, with a ready fix on branch `fix/a2-ai-vehicles`.**

## A2-01 — raids inherit an unrelated prepared contract

**Status: fixed locally.**

The local fix resolves the deployment's contract explicitly: `no_contract` deployments
carry an empty contract, and the session log reports that actual selection. Only a deployment
using the prepared contract consumes its contract and level preparation. A raid leaves the
job accepted and prepared for later.

Production change: [base_hub.gd](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:1626>).
Regression coverage: [base_test.gd](<C:/Users/My Little Pony/Documents/Contractor/tests/base_test.gd:1438>).
The existing base suite now launches both a helicopter raid and a crossing raid while a job
for another zone is prepared. Twelve checks cover successful arrival, raid rules without a
contract, no contract briefing/objectives, and intact preparation both during the raid and
after returning home. The ordinary contract loop then verifies that the same prepared job
still opens its briefing and activates objectives normally.

Validation:

- R0041 reproduced the original defect through the real deployment API before this repair.
- R0046 was stopped after sandbox restrictions blocked retained-log and isolated save writes.
  Its logs were retained; this attempt does not validate the repair.
- R0047: import, smoke, base (including the new regression) and contracts passed with no
  failures. The broader `base_zone` suite failed five expectations around helicopter arrival,
  returning through the crossing, deployment settlement, missing-person recovery and raid
  standing. The audit's original R0040 also failed that suite, with a different failure set;
  these results do not establish a green linked-zone suite.
- R0048: unchanged production source at `68a1b83` reproduced all five R0047 linked-zone
  failures, plus the base load-time budget failure (5,062 ms against 5,000 ms). The same
  `Exponent too high` warning appeared in both runs. This comparison confirms those five
  failures also occur without the repair; their underlying causes remain unresolved. The
  fixed source was automatically restored afterward and verified against its saved copy.

Retained logs: [R0047, fixed source](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0047-225502-FAIL-dev-68a1b83/summary.txt>)
and [R0048, unchanged-source comparison](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0048-230348-FAIL-dev-68a1b83/summary.txt>).

## A2-02 — deployment saves omit current helicopter restrictions

**Status: fixed locally.**

Every deployment save now snapshots the live helicopter system's losses and cooldowns into
`deployment.support_limits`, replacing an absent or stale crossing snapshot. The existing
loader restores cooldowns as seconds remaining. Expired timers are omitted by the existing
snapshot method, so saving after a timer expires no longer leaves its earlier crossing value
available to restart on reload. The save format and support-call rules are unchanged.

Production change: [base_hub.gd:278](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:278>).
Regression coverage: [base_test.gd:1341](<C:/Users/My Little Pony/Documents/Contractor/tests/base_test.gd:1341>).
The test uses its own deployment, writes and reads the actual campaign JSON, reloads the
campaign through `load_or_new`, and recreates the zone using its resume information and the
normal level switch. It checks both saving before any crossing and saving in a later zone
after a new loss, a changed cooldown and expiry of the earlier timer.

Validation:

- R0041 reproduced the original missing-loss snapshot before this repair.
- R0049: import and smoke passed. The first save/reload scenario passed; a formatting error
  in the new test's two-loss message interrupted the second scenario and caused subsequent
  fixture failures. That message was corrected. The independent `base_zone` suite passed its
  travel behavior checks but failed its 5-second base-load budget (5,446 ms). This budget also
  failed without these repairs in R0040 and R0048; it remains unresolved. The existing
  `Exponent too high` warning was also logged.
- R0050: both support-save scenarios passed. The overall base suite failed one earlier
  late-join expectation and three whole-preparation comparisons after the new reload test
  ran inside the raid fixture. The prepared job still opened its normal briefing. The exact
  preparation mismatch through reload was not diagnosed; no claim that reload preserves
  every prepared-job field follows from that run. The final test runs the support-save
  deployment separately, retaining the original raid fixture's strict comparisons.
- **R0051: import and the full base suite passed, zero failures and no script errors.** All
  **24 A2-02 assertions** passed, including disk contents, reconstructed support restrictions,
  stale crossing-state replacement and expired-timer removal. Both A2-01 raid routes and the
  subsequent normal contract briefing/objectives also passed. Production code was unchanged
  between R0049, R0050 and R0051; only the new test fixture was corrected and separated.

Retained logs: [R0049, smoke and linked zones](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0049-231128-FAIL-dev-68a1b83/summary.txt>),
[R0050, combined-fixture diagnostic](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0050-231743-FAIL-dev-68a1b83/summary.txt>),
and [R0051, final base verification](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0051-232225-PASS-dev-68a1b83/summary.txt>).

## A2-03 — scenario objectives lose their controller after a return or reload

**Status: fixed locally.**

Scenario runs are checkpointed into the deployment (`deployment.scenario_runs`, by objective
id) whenever the zone is saved, and restored when the squad comes back. `GameState.save_zone`
asks the level's `MissionScenario` for a checkpoint first. The new `ScenarioCheckpoint`
(`scripts/campaign/scenario_checkpoint.gd`) stores plain values and stable identities instead
of node references: crews, ambush teams and waves by body uid, and convoy vehicles by vehicle id,
with their seats and driving path. On restore it reuses what the zone's own memory has already
brought back (the zone restores bodies and AI before `Contracts.server_arrived` runs), and it
spawns only what is missing. It never recreates someone carried out, removed or delivered.

`MissionScenario` now also listens to `contract_returned`. It starts only active objectives
that belong to this level and have no run yet, so repeated arrivals change nothing. An objective
with no checkpoint (an older save) starts fresh as before. Hold and rescue waves are recorded
on the run so that they survive too. The public deployment sent to clients leaves the
checkpoints out (`Contracts._public`).

Production changes: [mission_scenario.gd](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/mission_scenario.gd:111>),
[scenario_checkpoint.gd](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/scenario_checkpoint.gd>),
[game_state.gd](<C:/Users/My Little Pony/Documents/Contractor/autoload/game_state.gd:70>),
[contracts.gd](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/contracts.gd:1295>).
Regression coverage: `_test_scenario_resume` in [missions_test.gd](<C:/Users/My Little Pony/Documents/Contractor/tests/missions_test.gd:2020>):

- It covers recon, defend/hold, convoy ambush, crew rescue and PSD escort, each with partial
  progress: a save to disk, the controller and its entities freed, a campaign load and a return.
- It checks the clocks and phase are kept, every tracked entity returns exactly once, convoy
  vehicles keep their ids and crews regain their seats, and a second return duplicates nothing.
- Completed objectives and other zones' objectives stay inactive.
- A real level replacement restores a partial recon, which can then finish.

Validation (shared log counter, `Documents/Contractor-test-logs`):

- **R0194:** smoke and missions passed, including all 62 A2-03 lines. Base failed one A2-02
  check: "the disk save contains the remaining medevac cooldown (180.00 s)". The value was
  right. `until - now` came back a float rounding above 180 when nothing had elapsed, and the
  check allowed at most exactly 180. The check now allows 0.001 s over. This is a test-only change.
- **R0195:** base (with A2-01 and A2-02) and contracts passed, zero failures.

Not covered: two-process co-op. Clients never receive the checkpoints, and the host
restores the scenario state.

## A2-04 to A2-13 (October 20)

**Captain's tasking (2026-10-19):** findings in Claude's files (`scripts/ai/squad_ai.gd`,
`scripts/ai/tactics.gd`, `scripts/ai/gun_team.gd`, `scripts/combat/static_weapons.gd`,
`scripts/vehicles/`, `scripts/world/dynamic_sim.gd`, the garrison and gun-team parts of
`zone_level.gd`) are written up in `docs/audits/followups.md`, not fixed here. A2-10, A2-11 and
A2-12 are in those files, so they are F-05, F-06 and F-04 there. Their fix and tests stay on
`fix/a2-ai-vehicles` (`184f408`), and this branch leaves those files as they are on `dev`. The
table below still lists them, for the record.

Four agents worked in parallel, each on its own branch from `3e5a1ee`, grouped by file:
`fix/a2-campaign` (c4edc4a), `fix/a2-rebels` (d0407bd), `fix/a2-exo-assist` (e1a7efc) and
`fix/a2-ai-vehicles` (184f408). All four are merged into `cghath/exec-audit-2026-10-19`. Every
finding has a regression test, and each agent saw its tests fail on the unfixed code before fixing it.

| Finding | Root cause | Fix | Regression | Failed before / passes |
| --- | --- | --- | --- | --- |
| A2-04 (P2) | Assault booking and the rebel week ran only in `BaseHub.server_advance_days`; debriefs and board waits call `Economy.advance_days` directly | Both rules moved into `BaseHub._on_day_advanced`, which every clock advance reaches; the rebel decay runs once per week boundary passed | `base_zone_test._test_every_clock_books` | R0207 / R0205 |
| A2-05 (P2) | `RebelCalls._send_fighters` called an 8-man rifle squad and could only free extras | `AlliedTroops.server_call(..., men)` spawns the count asked for: 6/8/10 by level (4/5/6 in a hot zone), as the upgrade text and `FIGHTERS` intend | `base_zone_test._test_rebel_fighters` | R0199 / R0203 |
| A2-06 (P2) | Element and follower records dropped the rebel flag; follow-in spawned the kind's size | `"rebel"` kept on the element and follower records and passed back on follow-in, with exactly the men still up | same test, "following over a crossing" | R0199 / R0203 |
| A2-07 (P2) | Banking of deposited loot and bodies' gear, and their removal from the zone, sat inside `if contract_ran` | Built for every extraction; a raid banks them as "carried out", a contract through its debrief as before | `base_zone_test._test_raid_banks` | R0207 / R0205 |
| A2-08 (P2) | `DayNight.server_restore` let a remembered zone's saved hour beat the travel hour | `server_cross_on` marks the arrival `DayNight.TRAVELLED`; marked arrivals keep the travel hour, a resumed save keeps the saved one | `base_test._test_travel_clock` | R0207 / R0205 |
| A2-09 (P1) | `climb_in_body_problem` never checked the new pilot's exo slot; `put_on` failed after the suit came off the casualty | One pilot check (`ExoMech._pilot_problem`: exo slot, hands, carrying, vehicle) for parked suits and takeovers, re-run in the same frame before the suit comes off; refused with "Take off your exo frame first"; the menu shows why | `mech_test._test_take_over` | R0197 / R0204 |
| A2-10 (P2) | `VehicleLayer.server_board` ordered the walk through the commander's main squad, which skips element men | The order goes through the man's own squad, falling back to the main squad | `vehicles_test._test_squad_drivers`, distant element medics | R0198 / R0208 |
| A2-11 (P2) | The belt handoff dropped the belt's `rounds` state and ignored a failed `take` | `_maybe_resupply_gunner` hands the entry over with its state (as magazines do); the bearer keeps it when the gunner has no room | `roles_test._test_ammo_bearer`, 7/0/100-round belts and no room | R0198 / R0208 |
| A2-12 (P1) | Boarding turned the carer's brain off with his care job and the casualty's `care_by` still set | `Vehicle.server_enter` calls `SquadAI.drop_care()` (the existing `_end_care`); `_carer_of` ignores a seated AI carer | `casualty_test._test_carer_boards` | R0198 / R0206 |
| A2-13 (P2) | `Assists.slowdown_near` took any other-faction soldier, with no line of sight | Non-combatants (`Person.is_noncombatant`) are skipped, and a clear line to the target is required (`Squad.sees`' heights, `Throwables.clear_line`) | `controller_test._test_slowdown_targets` | R0201 / R0204 |

Choices made along the way, for review:

- **A2-04:** a debrief's days pass while the deployment is still running. An assault that falls
  due then is handled as "squad out": near the base it holds out, otherwise it resolves off-screen.
- **A2-08:** after travel, the travel hour also beats a contract's own `"hour"`. That hour isn't
  tied to a zone, so it used to rewind the clock in any fresh zone after a crossing. Walking out of
  the base into a contract zone is unaffected. If the contract's hour should win, it's a one-line
  change in `DayNight.server_restore`.
- **A2-09:** wearing an LX-3, a takeover is refused rather than the LX-3 being moved. Worn gear
  only ever comes off by the wearer's own action.
- **A2-10:** when it gives the order, `server_board` names the high-command player as the element
  squad's leader, as `server_squad_dismount` and AlliedTroops already do.

**Combined run, R0209 at `54a1c45`:** all four branches merged. These 15 passed with zero
failures: smoke, base, contracts, daynight, missions, mech, exo, controller, interaction,
casualty, medical, squad, logistics, roles and scavenge. base_zone failed only its load
budget (5,333 ms). vehicles failed only its known co-op checks, and this time the client ran out
of its 480 s before the last of them, "mans the M-ATV's turret".

Known failures elsewhere, which these fixes don't touch:

- vehicles' two-process co-op part fails 7 client checks and 1 host check. The audit's R0042 on
  `68a1b83` shows the same list (R0208).
- base_zone's 5 s load budget is borderline on this machine: 5,017 to 7,659 ms while other agents
  ran Godot, but it passed in R0200 and R0205.
- One roles check, "halted squadmates crouch (6 of 7)", failed once (R0206) and passed in R0208.

Left open:

- Raids don't haul tagged pallet lots home.
- Only the count and the rebel flag cross with rebel followers, not their wounds or kit.
- A rebel element's call message and map label still say "Allied".
- The aim slowdown sees through vehicle hulls, as `Squad.sees` does.
- No full default suite or CI run has been made on the combined branch yet; CI on a pushed branch would be the full check.
