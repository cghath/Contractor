# Executive audit fixes — October 17, 2026

Fix branch: `codex/executive-audit-fixes`, based on v0.4.36 (`38f5825`).

| Finding | Change | Verification |
| --- | --- | --- |
| E-01 | Corpses retain the original spawn id; a separate saved fallen-post ledger survives cleanup and extraction. Older callsign-labelled saves migrate on load. | `audit_fixes`, R0022 |
| E-02 | Cleanup measures player proximity to `Soldier.body_point()`, preserving displaced visible bodies and carried bodies. | `audit_fixes`, R0022 |
| E-03 | QRF waves and hunters reserve their planned actual headcount, respect remaining reserves and return unspawned allocations. Reinforcement pairs also return partial allocations. | `audit_fixes`, R0022 |
| E-04 | HQ commanders register at spawn; death, cuffs, surrender and delivery before the first command tick cause headlessness. Discovery also recognizes dead commanders. | `audit_fixes`, R0022 |
| E-05 | Crow's Pass uses Meridian as client; generation rejects hostile/unknown employers and excludes self-targeting. | `contracts`, R0016; `audit_fixes`, R0022 |
| E-06 | Draft publishing reads release state before mutations, refuses public releases and stops on failed or malformed reads. | Inert publisher checks, S0018 |

CI now includes voice, compass and `audit_fixes`. A parity check fails if its matrix differs from the default local suites. Runner self-check fixtures and output retain numbered logs (S0021 passed).

Mission/world checks now recognize generated module variants and the intended back rows, outward-facing back streets, indoor defenders and elevated street posts. The pressure boundary handles clock rounding. Mission response checks release already-tested patrol slots before asserting an authorized QRF launch. Command behavior has separate regression coverage. Cache-spawner paths are relative during construction, and building queries wait for the first navigation synchronization.

## Urban performance

Building probes index nearby navigation regions instead of searching the whole map. Query caches evict individual old entries; building descriptors share actual geometry across query heights; formation checks skip detailed room/port construction. Navigation chunks use their aligned vertex joins instead of a costly proximity-edge pass. A regression checks unobstructed paths across chunk seams, and squad checks compare indexed surface queries against the original query across floors and tile boundaries.

Godot documents the distinction and cost of [vertex merging versus proximity edge connections](https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_optimizing_performance.html), and provides [region-specific closest-surface queries](https://docs.godotengine.org/en/4.7/classes/class_navigationserver3d.html#class-navigationserver3d-method-region-get-closest-point).

| Measure | Earlier repeat, R0015 | Fixed, R0027 | Existing limit |
| --- | --- | --- | --- |
| Average physics tick | 21.66 ms | 17.98 ms | 20 ms |
| 95th-percentile physics tick | 52.24 ms | 27.91 ms | 40 ms |
| Building scans per second of combat | 137 ms | 77 ms | 120 ms |
| Average engine step | 2.79 ms | 1.09 ms | 6 ms |

R0027 passed every benchmark check, including ragdoll settling and support, plus 50 unobstructed chunk-seam paths. Limits, actor counts and fight duration were preserved. Rare cold-scan spikes remain (349 ms worst tick in this run); passing these budgets does not establish hitch-free rendering on every frame.

## Final validation

Full regression verification is in progress. R0022 passed the new audit regressions, missions and squad; R0016 passed smoke, contracts and both world peers. S0018 passed all five inert publishing cases; S0021 passed runner and CI coverage checks. Failed experiments and their logs are retained; the navigation batching, bounded path-query and disabled-solver experiments were removed.

Old saves that already lost the original guard identity or the death record cannot reconstruct that missing history. The new ledger prevents future loss. Rendered play, microphone capture, exports and remote four-player play are outside this automated validation.
