# Executive audit — Part 1 of 2

Audited October 19, 2026. Game source: local `dev`, `68a1b8336013a8170b22d2a4b66e15a626feb84b`.
Compared with the previous audit completion, `c39c36d`; that commit is an ancestor of this checkout.
The checkout was clean at entry. This audit changes no production code and publishes nothing.

**Result: eight confirmed defects, three high priority (P1) and five normal priority (P2).**
The campaign should not yet be considered reliable across travel and reloads. The basic smoke
and contract suites pass, but they miss these combinations of features.

## Scope and checkpoint

This is an executive, risk-based audit of the new local commits. Part 1 covers campaign
deployment, saved progress, linked-zone travel, extraction banking, campaign-day hooks and
rebel-support purchases/followers. It follows calls across BaseHub, Contracts, Objectives,
RosterDeployment, GameState, Campaign, MissionScenario, Extraction, PeopleLayer, DayNight,
HeliSupports, AlliedTroops, RebelCalls and RebelSupport, with economy/base-assault paths.

Part 2 subsequently completed combat and squad AI, driving/vehicle behavior, co-op authority
and replication, performance, and test/release tooling; see the linked report below. Existing linked-zone suite failures below
also need follow-up; they have not been counted as independently diagnosed defects.

Work paused after this part for the requested usage checkpoint. No fixes are implied by this
audit, and the existing local-only preference remains in effect.

## Findings

### A2-01 — P1: a raid inherits a prepared contract for another zone

Location: [base_hub.gd:1655](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:1655>), with
`server_cross_from_base`, `server_raid_by_air` and `_open_briefing`.

Both raid entry points pass `no_contract: true`. `server_deploy` uses that option only to skip
the missing-contract refusal; it still passes `prep.contract` to `RosterDeployment.begin`
and then clears the prep. `_open_briefing` subsequently opens the inherited contract and
starts its objectives, using that contract's zone id, even though the squad is physically in
the raid destination. This can activate a job in the wrong zone and apply contract rules and
settlement to an intended raid.

**Reproduction, R0041:** accept/prepare K0001 in Wadi Farm, then deploy a no-contract raid
into Harbour Yard through the real deployment API. The raid's stored contract is still
K0001, naming Wadi Farm. All setup assertions passed.

**Correction:** resolve the deployment's contract explicitly from `no_contract`; an unrelated
prepared job must stay held/prepared rather than being attached to the raid. Cover both air
raids and walking through a crossing to a different zone while a job is prepared.

### A2-02 — P1: saving a deployment omits current helicopter losses and cooldowns

Location: [base_hub.gd:268](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:268>);
[heli_supports.gd:78](<C:/Users/My Little Pony/Documents/Contractor/scripts/supports/heli_supports.gd:78>).

`_note_resume` checkpoints the zone, equipment and wounds, but never checkpoints the live
HeliSupports restrictions. Those are copied to `deployment.support_limits` only when crossing
on. On reload, HeliSupports restores that missing or stale copy. A helicopter lost since the
last crossing becomes available again, and cooldowns can disappear or revert to older values.

**Reproduction, R0041:** mark transport lost and resupply on a 300-second cooldown, verify the
loss is active, then successfully save while deployed. The actual campaign JSON contains
no support limits (`{}`). The loading path restores restrictions only from that field.

**Correction:** snapshot current support limits at every deployment save and restore the
remaining durations. Include both saving before any crossing and saving after another loss
or call in a later zone.

### A2-03 — P1: returning to a scenario leaves its objectives active without a controller

Location: [contracts.gd:183](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/contracts.gd:183>);
[mission_scenario.gd:47](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/mission_scenario.gd:47>).

Scenario progress lives only in `MissionScenario.runs`, under the level that is freed when
leaving a zone. The replacement node subscribes only to `contract_live`. Returning to a
contract's original zone, or a previously visited leg, emits `contract_returned`, and no code
restores the old runs. The objective list survives while its controller, timers and references
do not. Recon and hold objectives can no longer progress; convoy/rescue scenarios also lose
the state that evaluates them. Saved mid-deployment reloads have the same missing state.

**Reproduction, R0041:** start an active recon objective and verify its controller exists;
give it seven seconds of progress, save, and reload the remembered zone through the actual
level-switch path with the deployment still live. The objective remains `active`, but the
new scenario node has `runs=[]`.

**Correction:** persist and restore scenario state, reconnecting restored entities by stable
ids. Re-emitting the original start event alone would restart clocks or duplicate entities;
test partial progress, return visits and resumed saves for each scenario family.

### A2-04 — P2: contract days and board waits skip base-assault and rebel-week rules

Location: [base_hub.gd:2096](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:2096>);
[contracts.gd:832](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/contracts.gd:832>).

Base-assault booking and weekly rebel-support decay are called only by
`BaseHub.server_advance_days`. Contract debrief and the contract board's wait buttons call
`Economy.advance_days` directly. The shared `day_advanced` handler updates roster/hiring but
does not run those new rules. Advancing the same campaign day therefore has different world
consequences depending on the UI/path used; repeated contracts can avoid assault booking.

**Reproduction, R0041:** with no booked assault, no recent assault and heat still above its
threshold, advance a day through the exact economy API used by debrief. The day advances
and heat remains eligible, but no assault is booked. A later raid end using the BaseHub path
does book one.

**Correction:** put these effects on the shared day-advance path, once per applicable day/week,
and test contract debrief, board wait, base rest, travel and multi-day advances.

### A2-05 — P2: the second fighter upgrade charges for men it cannot spawn

Location: [rebel_calls.gd:133](<C:/Users/My Little Pony/Documents/Contractor/scripts/supports/rebel_calls.gd:133>);
[allied_troops.gd:259](<C:/Users/My Little Pony/Documents/Contractor/scripts/supports/allied_troops.gd:259>).

Rebel fighters are advertised as six, eight and ten men at upgrade levels 0, 1 and 2.
`_send_fighters` always requests an eight-man allied rifle element, then removes excess
members. It never creates members beyond those eight. The second upgrade costs six favours,
$12,000 and four salvage but provides no extra fighters in an ordinary contract zone.

**Reproduction, R0041:** call fighters with level 2 and sufficient support in a non-hot zone.
The successful call supplies eight men, not ten. Existing upgrade coverage checks the mortar's
first purchase, not the fighter upgrades' resulting force.

**Correction:** pass the desired force size into element creation, or explicitly add the
additional members. Cover every level and the hot-zone reduction.

### A2-06 — P2: rebel fighters become regular allied troops after following across a crossing

Location: [allied_troops.gd:119](<C:/Users/My Little Pony/Documents/Contractor/scripts/supports/allied_troops.gd:119>).

Follower records retain `kind`, `company` and the number standing, but omit rebel identity.
`server_follow_in` calls `server_call` with its default `rebel=false`. The replacement element
therefore gets regular allied marks, kit and employer rather than rebel marks and equipment.
The regional support feature changes identity and loadout simply by crossing a zone boundary.

**Reproduction, R0041:** verify the original fighters all have `iff=rebel`, serialize them
with the actual follower API, release the original element, then restore its follower record.
The replacements have `iff=allied`. They still do **not** count as company troops for Harm;
this finding does not claim their civilian casualties become the company's.

**Correction:** preserve element origin/faction and equipment identity in follower records and
restore those values explicitly. Also retain any intended surviving-member state.

### A2-07 — P2: raids fail to bank deposited loot and bodies brought out

Location: [base_hub.gd:1904](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:1904>).

Banking `report.deposited` and `report.bodies`, and removing their uids from the old zone,
all sit inside `if contract_ran`. A proper raid has no Contracts deployment, so its extraction
skips the entire banking block. Personal inventory returns through roster resolution, but
loose salvage left at the extraction point, carried-out bodies' equipment and applicable
helicopter/non-pool cargo do not enter the stash. Loose items also remain in the remembered
zone despite being listed as extracted.

**Reproduction, R0041:** drop one copper salvage item and include its actual uid in the real
raid end handler's deposited report. The stash stays at zero; the old zone saves one dropped
item. This uses a constructed extraction report to isolate the end handler; Extraction's
`build_report` produces that same deposited-entry shape.

**Correction:** bank and remove extracted non-personal goods independently of whether a paid
contract ran, while keeping contract settlement separate and preserving single banking.

### A2-08 — P2: a remembered zone overrides the incoming travel time with its old clock

Location: [day_night.gd:194](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/day_night.gd:194>);
[zone_level.gd:471](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/zone_level.gd:471>).

Crossing computes arrival hour from the current zone plus travel and puts it in the incoming
definition. Hosting the destination immediately loads its old zone save and `server_restore`
overwrites that hour with the hour saved when it was last visited. Returning to a remembered
zone can rewind the day/night cycle even though the deployment's travel time advances.

**Reproduction, R0041:** save the zone at 09:00 and reload it through the real switching path
with an incoming definition naming 17:00. The new zone's clock is 09:00. The probe supplies
the computed arrival value explicitly; the precedence error occurs in the destination loader.

**Correction:** distinguish a resume of that save from arrival after travel; the latter must
use the current campaign/travel clock while retaining appropriate saved weather/world state.

## Local validation and limits

These run numbers belong to the retained **Contractor-audit-logs** parent under the Codex
visualizations workspace, not the separate `Documents/Contractor-test-logs` counter.

| Run | Result |
| --- | --- |
| [R0040 summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0040-215715-FAIL-dev-68a1b83/summary.txt>) | Import, smoke and contracts passed. `base_zone` failed seven assertions: initial generation 6.015 s against a 5 s budget; cuffed-HVT accompaniment; and a refused return crossing with subsequent left-behind/recovery assertions cascading from it. These are not seven separately diagnosed game bugs. |
| [R0041 diagnostic](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-19/R0041-220300-FAIL-dev-68a1b83/audit2_campaign.log>) | Eight expected behavioral failures reproduce A2-01 through A2-08. All setup assertions passed; zero fixture failures and no script errors. The run is correctly retained as FAIL: it demonstrates defects, not passing regressions. |

The R0041 diagnostic sources are retained in that run's `probes` folder outside the Godot
project, so Godot will not import audit utilities during normal development. To reproduce,
copy its `.gd`/`.tscn` files into `tests`, use isolated test tag/port and retained logs, and run
`tools/run_tests.sh audit2_campaign` with the Voxel Godot editor. Remove them from the project
afterward by moving them back outside it; retain every run's logs.

This part does not claim a green full suite, rendered playtest coverage, remote co-op testing
or a release/export check. Production source remains at the audited commit. The eight defects
remain open. The subsequent Part 2 findings and combined priority list are in PART-2.md and README.md in this folder.
