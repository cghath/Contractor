# Contractor — executive audit of the new local commits

**Remediation:** implementation and current validation are recorded in [FIXES.md](FIXES.md). The findings below describe the original audited commit.

**October 17, 2026 · v0.4.36 · `dev` at `38f5825526761df877f01bc5a9483520f7f383ed`**

## Executive decision

**Continue controlled development playtests; hold broader release until the persistence, publishing and verification problems below are resolved.**

The project has made substantial progress: the earlier save-recovery checks pass, the aid-bag duplication is fixed, and current exosuit and VTOL boarding/firing checks pass. However, this review confirmed **six new gameplay/tooling defects**, including killed garrison posts returning alive after restoration and the draft-release helper accepting a published release. Urban combat also missed its performance targets in two local runs.

Of **10 selected standard suites, six passed and four failed**. This is an executive review of the current local integration, not a repeat of the full October 13 audit or a certification of all new code.

## Major findings

| Id | Priority | Finding and consequence |
| --- | --- | --- |
| E-01 | **P1 — high** | **Killed garrisons can return alive after a save is restored.** Bodies save a human display name, while spawn exclusion expects the stable post id. A restored corpse and a new living soldier can occupy the same post. Cleanup additionally removes the only saved death record. |
| E-02 | P2 — medium | **Cleanup can delete the corpse a player is beside.** Its proximity guard checks the old capsule position rather than the displaced ragdoll. The audit reproduced deletion while the player stood at the visible body. |
| E-03 | P2 — medium | **Finite reserves do not limit actual QRF strength.** A later wave spawned eight soldiers with three reserves left. Approval spends a fixed nominal cost and spawning is capped by other budgets, rather than the actual remaining reserves. |
| E-04 | P2 — medium | **A commander killed before discovery is never recognized as the commander.** Discovery skips dead HVTs; killing a newly spawned HQ commander before the next command tick leaves command active. Discovering him first makes the same death correctly cause the headless state. |
| E-05 | P2 — medium | **Crow's Pass can generate self-targeting contracts from an invalid employer.** The seeded board produced a sabotage job with `black_ridge` as both employer and target. That faction is explicitly excluded from the employer list. This explains the contracts suite's validity failure. |
| E-06 | **P1 — high** | **The draft-release helper can publish to or overwrite an existing public release.** It tests only whether a release exists, then uploads with `--clobber`. A local mock reporting a published release reproduced that path. No real upload was made. |

P1 denotes a progress-integrity or externally visible delivery risk to address before broad distribution. P2 denotes a confirmed gameplay/accounting defect. The following performance and verification gaps are additional release risks, separate from the six defect findings.

## Performance and verification

**Urban combat is still over budget on this machine.** Two runs of the same 42-soldier town benchmark at this commit produced:

| Measure | Target | R0012 | R0015 repeat |
| --- | --- | --- | --- |
| Average physics tick, scripts + engine | ≤20 ms | 21.34 ms | 21.66 ms |
| 95th percentile physics tick | ≤40 ms | 51.60 ms | 52.24 ms |
| Building-scan work per second of simulated fight | ≤120 ms | 141 ms | 137 ms |
| Worst individual physics tick | Observational | 604.92 ms | 656.43 ms |

Average script time was 18.2–18.9 ms versus 2.8–3.2 ms for the engine step. Profile the script spikes and AI/navigation work before changing budgets. These are headless physics measurements, not rendered FPS or a comparison on identical hardware with a previous release. Ragdoll settling and supported-body checks passed in both runs.

**Verification has fallen behind the new features.** R0012 failed `contracts`, `missions`, the `world` host, and `townperf`:

- `contracts`: one genuine data inconsistency, E-05.
- `missions`: four assertions and four script errors. Raw `m.type == "outpost"` fixture lookups no longer find grown variants, so several test sections abort. Pressure/firefight and QRF assertions also failed; they still need individual isolation rather than blanket dismissal as stale tests.
- `world`: seven host assertions failed, including exact original module types, old town-size/streets expectations, and the upper-floor garrison share. Some expectations predate the new layouts; the measured high-post share was 18%, below the test's roughly one-third requirement. The late-join client passed.
- `townperf`: the same three performance thresholds failed twice.

The local default runner lists **43 suites; CI lists 41**, omitting `voice` and `compass`. No direct assertions for `EnemyCommand` or `UrbanDefence` were found in the existing test suites. The new audit probes cover the specific failures above, not the complete command/urban systems. A current green remote CI run was not verified.

## What improved since the previous audit

The comparison covers **568 commits, including merges**, since `fcae676`: 1,463 changed files and 216 changed GDScript files. Many changed files are audio assets/imports; those totals are not a count of independently reviewed behaviors.

The history contains fixes for 25 original findings and explicitly defers A3-07's numeric doctrine integration. This audit independently verified the highest-risk cases: the base suite passed missing-primary backup recovery, interrupted-save recovery, malformed/versioned save rejection and preservation of unreadable files; the old aid-bag reproduction now conserves two bandages as two. Reviewed source also contains the earlier body-position extraction fix, launcher inventory controls, per-world building caching, retained CI logs and numbered build outputs. This does not declare every old finding freshly retested.

`smoke`, `base`, `exo`, `bay`, `voice` and `compass` passed. The VTOL bay checks include boarding and player/AI fire from door seats for the Petrel and Razorback. Standard 1.92 km streaming remained inside its budgets: approximately 7.3 ms average, 41.3 ms worst, and 98 MB static memory. That does not establish populated hot-zone rendering performance.

Two feature boundaries remain explicit in source: numeric doctrine weights are pending, and the voice-order input uses a typed stand-in; microphone speech recognition is not connected. Passing the voice suite verifies phrase routing, not speech recognition.

## Recommended order

1. Preserve stable garrison identity independently of display names and physical corpse lifetime. Fix cleanup reach alongside it, with save/restore tests before and after cleanup.
2. Make the publisher refuse published releases unless an explicitly separate update operation is requested. Test both draft and published existing-release cases.
3. Correct Crow's Pass's employer and validate generated employer/target combinations.
4. Register commander identity on spawn and consume death/capture events; reserve and settle the actual reinforcement headcount, including multi-base launches and failed spawns.
5. Repair the broken fixture selectors and resolve each remaining assertion, add command/urban coverage and align CI with the runner. Profile the repeatable urban performance failures, then require the relevant suites and a fresh full check before release.

## Technical evidence and reproduction notes

**E-01:** [soldier.gd:2217](<C:/Users/My Little Pony/Documents/Contractor/scripts/actors/soldier.gd:2217>) saves `label: display_name()` without the original post id. [zone_level.gd:533](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/zone_level.gd:533>) compares those labels to `_garrison_callsign()`. [compound_level.gd:658](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/compound_level.gd:658>) has the same exclusion pattern. R0015 saved `audit_compound_H1` as `Kakar`, restored its actual body record through `server_spawn_body()`, and ran the normal garrison initializer. The corpse remained and that post spawned alive. This exercises production restoration/initialization in the same hosted scene, rather than driving a full UI reload. [game_state.gd:46](<C:/Users/My Little Pony/Documents/Contractor/autoload/game_state.gd:46>) rebuilds body records from the live dead-body group, so cleanup also erases the persisted death fact. A stable killed-post ledger should outlive corpse despawning and extraction.

**E-02:** [zone_cleanup.gd:49](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/zone_cleanup.gd:49>) uses `b.global_position`. R0015 displaced the restored ragdoll 30 m, put the player beside its visible body, and advanced only the cleanup sweep's age argument beyond its normal lifetime. The body was queued for deletion. Use the established `Soldier.body_point()` helper and preserve the existing carrying protection.

**E-03:** [enemy_command.gd:517](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/enemy_command.gd:517>) checks a threat ratio, then subtracts fixed `HUNT_COST`; [enemy_response.gd:364](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/enemy_response.gd:364>) launches waves without using remaining reserves as the headcount cap. R0015 set a neutral-caution commander to three reserves, supplied a current one-person contact and selected a later-wave counter, retaining normal wave sizing/default caps. Eight hostiles spawned; reserves clamped to zero. This simulates later-wave state without waiting through six prior waves. Authorize the planned count and settle actual successful spawns, rather than treating ratio approval as a headcount reservation.

**E-04:** [enemy_command.gd:422](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/enemy_command.gd:422>) discovers only living HQ HVTs; [people_layer.gd:376](<C:/Users/My Little Pony/Documents/Contractor/scripts/people/people_layer.gd:376>) identifies commanders at spawn without registering them with command. R0015 killed one before command's next check and another after discovery. Only the latter caused headlessness. Tests disabled automatic command processing to isolate the two orderings; both used real spawned HVTs and production handlers.

**E-05:** [contracts.json:186](<C:/Users/My Little Pony/Documents/Contractor/data/contracts.json:186>) sets `pass_hot.faction` to `black_ridge`; [contracts_gen.gd:130](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/contracts_gen.gd:130>) uses that as the employer. [missions.gd:259](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/missions.gd:259>) excludes hostile factions from employers, while the enemy pool includes `black_ridge`. The exact board seed 1234 used by the failing standard test produced “Sabotage: Crow's Pass,” employer and target both `black_ridge`. Define the intended paying faction; supporting hostile clients would require an explicit policy change rather than weakening this test alone.

**E-06:** [publish_release.sh:17](<C:/Users/My Little Pony/Documents/Contractor/tools/publish_release.sh:17>) never inspects draft state on the existing-release branch. S0014's inert `gh` mock returned an existing release with `isDraft: false`; the helper requested `release upload ... --clobber`. Its payload was an inert local fixture. The mock made no network calls and no release was changed.

## Validation record

| Run | Outcome |
| --- | --- |
| R0012 | Current standard suites: six pass, four fail as described above. Import passes. No gameplay modifications. |
| R0013 | Initial audit probe: confirmed commander, reserves and visible-body cleanup; one assertion wrongly expected saved `label` to equal the post id. That observation exposed E-01. The log is retained. |
| S0014 | Synthetic publisher observation confirmed, using only the inert mock. |
| R0015 | Corrected probe identifies body records by UID, then explicitly checks the label/post mismatch. All probe observations pass, including old duplication fix, both garrison-restoration paths, cleanup, command death ordering and reserve overspawn. Town performance repeat fails the same three targets. Overall run FAIL. |

Probe PASS means the reported current behavior was observed, not repaired. The probe and standard world logs also contain startup/cache-spawner or early-navigation engine errors; successful assertions are not a clean-engine-log certification. Logs preserve those messages.

Evidence: [R0012 summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-17/R0012-172223-FAIL-dev-38f5825/summary.txt>), [R0015 gameplay observations](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-17/R0015-173509-FAIL-dev-38f5825/executive_audit.log>), [R0015 town performance](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-17/R0015-173509-FAIL-dev-38f5825/townperf.log>), [S0014 mocked publisher calls](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-17/S0014-173455-PASS-release-probe-38f5825/gh-calls.log>).

To repeat the game probe, set `AUDIT_REAL_GODOT` to the installed Voxel Tools editor and `GODOT` to this folder's `diagnostic-engine.sh`, then use `tools/run_tests.sh executive_audit` with an isolated tag, port and retained log parent. To repeat the publisher mock, set `AUDIT_RELEASE_KEEP` to a retained helper-run directory and run this folder's `release_probe.sh`; ensure its `mock-bin/gh` is executable. It substitutes only the GitHub CLI.

The review used the existing local checkout. Gameplay, tests, CI and release helpers were not edited; no commit, push, export or real publication was made. The three pre-existing untracked UID files were left alone. Only this dated audit folder was added. Manual rendered play, microphone input, standalone launch and remote four-player co-op were not validated.
