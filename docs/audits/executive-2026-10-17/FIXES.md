# Executive audit fixes — October 17, 2026

Fix branch: `codex/executive-audit-fixes`, based on v0.4.36 (`38f5825`).

Local remediation and follow-up validation completed October 18, 2026. All six executive findings are implemented. The full run and subsequent focused checks are distinguished below.

| Finding | Change | Verification |
| --- | --- | --- |
| E-01 | Corpses retain the original spawn id; a separate saved fallen-post ledger survives cleanup and extraction. Older callsign-labelled saves migrate on load. | `audit_fixes`, R0036 |
| E-02 | Cleanup measures player proximity to `Soldier.body_point()`, preserving displaced visible bodies and carried bodies. | `audit_fixes`, R0036 |
| E-03 | QRF waves and hunters reserve their planned actual headcount, respect remaining reserves and return unspawned allocations. Reinforcement pairs also return partial allocations. | `audit_fixes`, R0036 |
| E-04 | HQ commanders register at spawn; death, cuffs, surrender and delivery before the first command tick cause headlessness. Discovery also recognizes dead commanders. | `audit_fixes`, R0036 |
| E-05 | Crow's Pass uses Meridian as client; generation rejects hostile/unknown employers and excludes self-targeting. | `contracts` and `audit_fixes`, R0036 |
| E-06 | Draft publishing reads release state before mutations, refuses public releases and stops on failed or malformed reads. | Inert publisher checks, S0018 |

CI now includes all 44 local suites, including voice, compass and `audit_fixes`. A parity check fails if its matrix differs from the default local suites. Runner self-check fixtures and output retain numbered logs, and CI uploads those logs even on failure (S0030 passed). Remote CI was not run: the user requested that fixes stay local.

Mission/world checks now recognize generated module variants and the intended back rows, outward-facing back streets, indoor defenders and elevated street posts. The pressure boundary handles clock rounding. Mission response checks release already-tested patrol slots before asserting an authorized QRF launch. Command behavior has separate regression coverage. Cache-spawner paths are relative during construction, and building queries wait for the first navigation synchronization.

## Urban performance

Building probes index nearby navigation regions instead of searching the whole map. Query caches evict individual old entries; building descriptors share actual geometry across query heights; formation checks skip detailed room/port construction. Navigation chunks use their aligned vertex joins instead of a costly proximity-edge pass. A regression checks unobstructed paths across chunk seams, and squad checks compare indexed surface queries against the original query across floors and tile boundaries.

Godot documents the distinction and cost of [vertex merging versus proximity edge connections](https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_optimizing_performance.html), and provides [region-specific closest-surface queries](https://docs.godotengine.org/en/4.7/classes/class_navigationserver3d.html#class-navigationserver3d-method-region-get-closest-point).

| Measure | Earlier repeat, R0015 | Fixed, R0036 | Existing limit |
| --- | --- | --- | --- |
| Average physics tick | 21.66 ms | 17.86 ms | 20 ms |
| 95th-percentile physics tick | 52.24 ms | 29.09 ms | 40 ms |
| Building scans per second of combat | 137 ms | 60 ms | 120 ms |
| Average engine step | 2.79 ms | 1.19 ms | 6 ms |

R0036 passed every benchmark check, including ragdoll settling and support, plus 50 unobstructed chunk-seam paths. Limits, 42 soldiers and the 900-tick fight duration were preserved. Rare spikes remain: the worst tick was 338 ms and the 99th percentile was 55.86 ms. Passing these budgets does not establish hitch-free rendering on every frame.

The optimization is scoped to individual zone regions, so it does not change a subsequent base map's settings. Squad checks matched the indexed query against the original navigation query on 27 surfaces across floors and tile boundaries.

## Additional corrections

- A late joiner's already-held casualty uses the held pose immediately instead of replaying the newly-downed slump.
- A packed massive neck wound can advance to a clamp instead of repeatedly requesting ineffective gauze.
- Escort care overrides escort-intent hysteresis. The escort retains care until the approaching medic reaches the actual body; the approach retains smoke, suppression and blocked-route handling.
- The commander records a first sighting before the response requests permission to launch.
- The experimental forest briefing recognizes generated compound and village variants.
- Helicopter clearance includes the tilted airframe's offset and two metres of contour-lag allowance. The measured clearance requirement is unchanged; the harbour approach passed at 5.3 m.
- A bullet that wounds a body before being stopped by a vehicle, soft armour or another body retains the earlier body-hit feedback. Trajectory, penetration and damage calculations are unchanged.

Fixtures now aim close shots from the physical muzzle, wait for seated hitboxes, use the actual ragdoll position for treatment reach and give-up helper distance, distinguish penetration edits from downstream marks, respect the crouch hold and installed callout recordings, and use a genuine zone-edge foot extraction for recovery. The give-up fixture checks the actual helper/body distance without changing the game's 50 m rule.

## Validation

Run numbers in this file (R0012-R0039, S0014-S0030) come from the audit tool's own log parent (`.codex/.../Contractor-audit-logs`), not the shared `Documents/Contractor-test-logs` counter, where the same numbers name other runs. The follow-up review (October 18) cites shared-counter runs.

| Run | Result |
| --- | --- |
| [R0036 summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-18/R0036-004857-FAIL-codex-executive-audit-fixes-e6a1ce3/summary.txt>), `e6a1ce3` | Full 44-suite run with unchanged game/test source: 43 passed; the vehicle host failed the passenger hit-reporting assertion. All audit regressions, protected body-position checks, support/flight checks and performance budgets passed. The selected list exactly matches the default suite set. |
| [R0037 reproduction](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-18/R0037-015504-FAIL-codex-executive-audit-fixes-3c48b3d/vehicles-host.log>), `3c48b3d` | Expected negative regression: both male and female targets were wounded, and the fresh armoured vehicle stopped the exiting round, but old feedback said `vehicle`. The rounds-only diagnostic omitted wreck setup, so its client wreck assertion is not a full-suite result. |
| [R0038 summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-18/R0038-015722-FAIL-codex-executive-audit-fixes-417dd83/summary.txt>), `417dd83` | Full vehicles (both peers, including the new regressions), net, weapons, materials, armour, anti-armour, people, sound and smoke passed after the feedback correction. Gameplay failed its give-up isolation fixture; nine of ten suites passed. |
| [R0039 summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-18/R0039-021306-PASS-codex-executive-audit-fixes-571d5cd/summary.txt>), `571d5cd` | Gameplay and smoke passed with the helper placed relative to the actual downed body. This final change is test-only; game code is unchanged from R0038. |
| S0018 | All five inert publishing cases passed; no real release was changed. |
| S0030 | Runner, CI parity and log-artifact configuration checks passed. |

The only subsequent game-code change after R0036 is three stop-result guards in `Ballistics._trace`; the new vehicle regression covers both body types. All ten affected suite families have passing follow-up results across R0038/R0039. The entire 44-suite list has not been repeated after that feedback-only change; this is not a claim of one green full run at the final commit. Earlier diagnostic, failed and stopped runs remain in the retained log index.

The work branch stays local at the user's request. No remote push, publication or integration-branch update has occurred; validation uses the local runner.

Old saves that already lost the original guard identity or the death record cannot reconstruct that missing history. The new ledger prevents future loss. Rendered play, microphone capture, exports and remote four-player play are outside this automated validation.

## Review follow-up (October 18, 2026, cghath's side)

Three independent code reviews of the fix branch (persistence and command; reserves, combat, AI
and helicopter; navigation, tooling and tests) found the six findings fixed at the root and most
fixture changes justified. They also found problems, now fixed on this branch:

| Problem | Fix |
| --- | --- |
| **Blocker:** `tests.yml` used `${{ runner.temp }}` in a job's `env`, which GitHub rejects, so no CI job would start | The runner job's `CONTRACTOR_TEST_LOGS` moved into its two steps; the runner self-check reads the suite job only |
| A two-base QRF approved per base, recorded two ops and could refuse its own second wave (tier 2, `MAX_OPS` 2) | Approved once per launch; later waves paid silently (`EnemyCommand.reserve_men`); short reserves still ask, so the denial is recorded and a stale-LKP hunter still probes |
| While one medic walked in on an escort's HVT, every free medic converged on it | A pending handoff is marked on the HVT; others skip it; a downed or reassigned medic frees it |
| Building answers depended on which scan height came first (raised structures with no entrance) | A building's ground is measured from its own floor, not the scan's reach; LRU eviction fixed |
| Chunks baked from a module's proxy were never rebaked once its voxels were built; a breach on such a seam detoured | ZoneNav records proxy-baked chunks and rebakes them when the module is built; the seam test samples every 1.5 m on every floor, with breach and proxy/voxel cases |
| The publish test's `! grep` "never" checks were ignored by `set -e`; it could reach real GitHub | `never()` fails the check (proved against a publisher that uploads to a public release); it requires the inert `gh` double, an unusable token and a fake tag |
| `missions_test` turned the enemy commander off for the whole suite | Off only around hand-driven sections; a new end-to-end QRF launch with command on checks spent = spawned |
| Probe scripts committed inside the project (Godot imports `docs/`) | Moved to `Contractor-test-logs/audit-2026-10-17-probes/`; reports only in the repo |

Validation on the shared log counter (`Documents/Contractor-test-logs`): R0159 at `dc92b82` passed
smoke, townperf, audit_fixes, missions, people, squad, spacing, casualty, medical, world, forest,
contracts and roles. Town benchmark: average tick 17.65 ms, p95 25.79 ms, building scans 90 ms a
second, engine step 0.89 ms (budgets 20 / 40 / 120); seams join after a breach and after proxy
rebakes. Runner self-check S0143 and the CI suite parity check pass. The full 44-suite set is left to
CI. On this machine `map` and `ui` fail even on untouched dev 38f5825 (R0146) and pass on CI.

Still open: a breach on a seam can detour about 3 m while its module is streamed out; killed
civilians and HVTs can still return after a reload once their body record is cleaned up (E-01's
cause, people side); v0.4.10 to v0.4.36 saves may duplicate a garrison post once; Noah's "proxy
navmesh while a town builds" (cccc0c7) never takes effect (`_structures_readable` is false until
the world is built); dev's own CI is red on 15 suites at 38f5825, most of them fixtures this branch
updates.
