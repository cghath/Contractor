# Contractor — completed three-part audit

October 13, 2026 · `dev` · `fcae676b8318b7534fdc3f2e4d17a9e9a228275f`

> **Status (2026-10-13, cghath's side):** all 26 dealt with on branch `fix/audit-2026-10-13`: 25 fixed, A3-07 marked pending (doctrine numbers left to Captain's tactics work). Each has a regression check; all 27 suites pass (R0119). Details in CHANGELOG.md.

**26 actionable findings: 3 high priority (P1), 23 medium priority (P2).** Gameplay source was not changed. Reports and diagnostic fixtures are in this folder; logs are retained outside the repository. Findings remain open.

| Part | Findings | Report |
| --- | --- | --- |
| 1: foundations, multiplayer and persistence | 7: two P1, five P2 | [Part 1](<C:/Users/My Little Pony/Documents/Contractor/docs/audits/part-1.md>) |
| 2: gameplay, AI and interfaces | 9: one P1, eight P2 | [Part 2](<C:/Users/My Little Pony/Documents/Contractor/docs/audits/part-2.md>) |
| 3: worlds, missions, vehicles and delivery | 10: ten P2 | [Part 3](<C:/Users/My Little Pony/Documents/Contractor/docs/audits/part-3.md>) |

> **Follow-ups (added 2026-10-13, Captain's side):** three new tasks in
> [followups.md](followups.md): F-01 the AI building scan only sees one floor (upper floors and
> roofs of the new multi-storey buildings are never garrisoned or cleared), F-02 town garrison
> posts are all on the ground floor, F-03 doctrine `engage_m` sits below the new sight ranges.

## What to fix first

1. **Protect campaign progress.** A1-01 resets an unreadable campaign and deletes its zone saves; A1-02 ignores usable backups if the primary is absent. Preserve damaged files and recover backup-only state before creating fresh state. Then strengthen validation and report failed writes (A1-03/A1-04).
2. **Restore item conservation.** A2-01 duplicates medical supplies when looting a backpack with an attached aid bag. Verify all transfers retain exactly the original quantities and state.
3. **Correct gameplay outcomes.** Fix unvisited clear-area bonuses, blast-only civilian accounting and corpse extraction locations (A3-01/02/03), then blocked IV sites, hidden medical options and item identity during reload/pack recovery.
4. **Make world state consistent.** Scope building caches to their world, preserve destroyed geometry in streamed-out proxies/navigation, and recheck vehicle work reach.
5. **Make verification dependable.** Repair the two test setups, reject import script errors, retain original CI logs, and make build outputs unique and diagnosable. Connect numeric doctrine tuning or explicitly mark it pending.

## Finding index

| Id | Priority | Problem |
| --- | --- | --- |
| A1-01 | P1 | Unreadable campaign triggers destructive reset |
| A1-02 | P1 | Missing primary prevents recovery from a valid backup |
| A1-03 | P2 | Save validation does not cover versions/nested consumed data |
| A1-04 | P2 | Failed save still reports success |
| A1-05 | P2 | Empty contract RPC arguments cause a host script error |
| A1-06 | P2 | Network client deletes the shared host fixture |
| A1-07 | P2 | Contracts replication test races automatic objective completion |
| A2-01 | P1 | Backpack aid-bag contents duplicated by loot-all |
| A2-02 | P2 | Old reload completes on a replacement gun of the same model |
| A2-03 | P2 | IV placement bypasses blocked-site rules |
| A2-04 | P2 | Hearing-loss filter survives into a healthy session |
| A2-05 | P2 | Medical actions fall beyond an unscrollable row limit |
| A2-06 | P2 | Equipped launcher has no inventory slot controls |
| A2-07 | P2 | Dragging ground pack into a container swaps worn packs |
| A2-08 | P2 | AI pack recovery can take someone else's same-model pack |
| A2-09 | P2 | Scavenge command searches capsule instead of visible corpse |
| A3-01 | P2 | Clear-area bonus completes before target garrison spawns |
| A3-02 | P2 | Blast-only civilian injuries omit attacker/casualty accounting |
| A3-03 | P2 | Corpse extraction uses old capsule position |
| A3-04 | P2 | Building cache leaks across worlds |
| A3-05 | P2 | Streamed-out proxy restores destroyed wall collision |
| A3-06 | P2 | Repair finishes after vehicle drives away |
| A3-07 | P2 | Numeric doctrine profiles are not consumed by AI |
| A3-08 | P2 | Import script error can receive a passing verdict |
| A3-09 | P2 | CI loses original detailed host/client/import logs |
| A3-10 | P2 | Build helper overwrites same-day outputs and discards errors |

Each detailed report gives source locations, conditions, impact, recommendations and whether the evidence is runtime, source-only or synthetic. Related body-location findings concern different gameplay consumers; they should be repaired consistently using the existing body-position helper.

## Test result and readiness

All **27 existing suites were exercised across the three parts** on the unchanged gameplay baseline. **25 passed unmodified.** The network suite failed four save-fixture assertions and the contracts suite failed one timing assertion in R0002. Their setup-only diagnostic controls passed in R0003. That isolates those failures, but does not turn the unmodified baseline into a green 27-suite run.

R0004 passed all fourteen gameplay suites; R0006 passed all nine remaining world/vehicle/support suites. R0005 and R0008 reproduced the targeted gameplay bugs. R0007 confirmed the unvisited-raid bonus with AI enabled; its first corpse probe was corrected and passed in R0008. The malformed RPC's script error in R0003 was intentional. R0010 is a synthetic false-green runner verdict, and S0011 passed the runner's existing self-check. Initial environment failures are excluded and recorded in the individual reports.

The game has substantial working coverage for combat, medical care, inventory, squads, persistence's normal paths, large worlds, vehicles and supports. **The save-loss and duplication findings should be fixed before relying on long campaign playtests.** Fixing the remaining confirmed defects and test/delivery gaps will make broader playtests more useful.

The headless 1.92 km world benchmark stayed within its budgets: 320 ms generation, 7.0 ms average/40.2 ms worst streaming frame, and 47 MB static memory. A populated 4.096 km hot zone, full terrain traversal, rendered GPU performance, UI readability/control feel, standalone exports and real remote co-op still need manual measurement. No new build or remote CI run was produced, and this audit does not certify those conditions.

Audit logs: [retained run index](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/index.txt>). The local checkout's tracked files remain unchanged; only `docs/audits/` was added.
