# Local repairs after the executive audit

These repairs follow the audit of `68a1b8336013a8170b22d2a4b66e15a626feb84b`.
They remain local working-tree changes; no push, merge or publication was performed.
The audit reports describe the original checkout. This file tracks subsequent repairs.

**Progress: three of five P1 findings fixed locally (A2-01, A2-02, A2-03); A2-09 and A2-12 remain open.**

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

No remote CI or full default suite is claimed. The two remaining P1 findings are A2-09
(heavy-suit takeover) and A2-12 (stale casualty-care claims after boarding). All changes remain
local and uncommitted, on branch `cghath/exec-audit-2026-10-19`.
