# Audit part 3 — worlds, missions, vehicles and delivery

October 13, 2026. Baseline remains `dev`, `fcae676b8318b7534fdc3f2e4d17a9e9a228275f`. Gameplay source was not changed.

Part 3 is complete: **ten actionable findings, all medium priority (P2)**. Six were reproduced through gameplay paths, three are source-confirmed integration or delivery gaps, and one is a synthetic test-runner reproduction. The nine remaining standard suites all passed in R0006. A passing diagnostic observation means a bug was reproduced, not fixed.

## Scope

Reviewed seeded terrain and module construction, collision, streamed voxel edit replay and navigation, mission generation and objective polling, extraction reports and campaign consumers, vehicle damage/cargo/service/save paths, helicopters, AAVs and support ordering, AI world caches and doctrine integration, performance measurements, session diagnostics, test verdicts, CI, export presets and build tooling. This completes the three integration questions deferred from Part 2.

Validation used the installed Godot 4.7.2 Voxel Tools 1.7 editor, the repository runner, isolated test saves and port 24931. No new export was produced. Rendered performance, visual quality, input feel and remote-network conditions remain manual playtest work; localhost/headless checks do not establish them.

## Findings

### A3-01 — P2: clear-area bonuses complete before their garrison exists

Locations: [objectives.gd:403](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/objectives.gd:403>), [zone_level.gd:298](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/zone_level.gd:298>) and its streamed-in garrison callback.

Clear-area polling counts currently spawned, upright hostiles. After 20 seconds with none, it arms and completes the objective. Zone garrisons spawn only when their module streams in; the objective does not distinguish an unvisited target from a cleared one.

R0007 accepted and deployed a generated raid in `wadi_farm`, with AI enabled and the player 700 m from its target. The clear-area **bonus** completed before the module streamed in. Arrival then spawned five living enemies, while the objective stayed done. This proves an unearned objective/bonus, not completion of the raid's separate required cache objective.

Recommendation: wait for the target's garrison initialization before evaluating emptiness, and handle genuinely empty or previously cleared sites explicitly. Cover deployment while outside streaming range. This is distinct from A1-07's deliberately empty replication fixture.

### A3-02 — P2: grenade blast-only civilian injuries bypass casualty accounting

Location: [throwables.gd:104](<C:/Users/My Little Pony/Documents/Contractor/scripts/combat/throwables.gd:104>), with [people.gd:101](<C:/Users/My Little Pony/Documents/Contractor/scripts/people/people.gd:101>) consuming attacker records.

The grenade applies `server_blast()` before fragments. Only fragments call `Harm.note_hit()`. Burns or blast injuries without a successful fragment therefore have no new attacker record. The civilian ledger receives no wounded event; later death may have no attribution or retain an older attacker.

R0008 shielded every civilian fragment hitbox behind a wall. A nearby friendly grenade caused burns, with no fragment wounds, attacker record or casualty event. The positive control, noting the same friendly attacker, immediately created the event. Contract civilian fines/reputation consume that ledger, so this affects mission accounting. The probe follows the existing overpressure model; it does not assert that wall shielding should stop that model's blast effects.

Recommendation: record the source when blast causes qualifying injury, before any potentially fatal change, while preserving casualty deduplication. Cover blast-only and mixed blast/fragment damage. Compare the warhead implementation, which already records nearby blast attribution.

### A3-03 — P2: extraction banks corpse gear using the old capsule position

Locations: [extraction.gd:273](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/extraction.gd:273>) and the body report at line 366; [base_hub.gd:927](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:927>) banks those entries.

`_out_at()` checks `node.global_position`. A ragdoll can lie metres from that capsule; the established body reach helper is `Soldier.body_point()`.

R0008 displaced a friendly corpse 8 m. A 2 m extraction point around its visible body reported it left behind with its gear; a point around the empty old capsule instead extracted it. Carried and vehicle occupants have separate handling, but a laid-down body still hits this branch.

Recommendation: use the current body position for corpse extraction membership. Retain the vehicle/carried checks and the existing ragdoll fixes. Verify both directions so gear cannot be lost or banked from a distant body. Related command lookup: A2-09.

### A3-04 — P2: the AI building cache leaks between worlds

Location: [buildings.gd:53](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/buildings.gd:53>).

The static cache key includes rounded coordinates and radius, with a 20-second lifetime, but no world/navigation-map identity. No level-transition invalidation was found. A new level at the same coordinates can therefore inherit the previous level's rooms, entrances and firing ports.

R0008 built an actual enclosed navigable room in one `World3D` and an open floor at the same coordinates in another. The second world received the first world's cached building; clearing the cache made the same query correctly return none.

Recommendation: include world/map identity and invalidate scans on level retirement and relevant geometry/navigation changes. Keep the performance benefit of caching within one world.

### A3-05 — P2: streaming out closes destroyed walls in proxy collision

Locations: [zone_module.gd:111](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/zone_module.gd:111>), its pristine proxy construction at line 145, and [zone_nav.gd:86](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/zone_nav.gd:86>) for unloaded structures.

Stream-out restores the proxy built from the original module boxes. The retained destruction log is replayed on stream-in, but it is not reflected in the proxy. Unloaded navigation geometry likewise uses pristine boxes. Walls destroyed earlier can again block distant sight/rounds or planned paths until voxels return.

R0008 carved a wooden wall, confirmed its voxel was empty and the physics ray through the breach was clear, then streamed out the module. The same ray became blocked by the restored proxy. R0006's standard world suite verifies edit replay on return, which still works; it does not check the destroyed proxy while away.

Recommendation: preserve a coarse edited collision/navigation representation when unloading, or another representation that retains meaningful breaches without keeping full voxel modules resident.

### A3-06 — P2: vehicle work finishes after the vehicle leaves

Location: [vehicle.gd:1710](<C:/Users/My Little Pony/Documents/Contractor/scripts/vehicles/vehicle.gd:1710>), following the reach-checked service request at line 1669.

Work cancellation checks whether the actor moved from the starting spot or became incapacitated. It does not check whether the vehicle remains within reach. A driver can leave during service while a stationary mechanic completes the job remotely.

R0008 started a normal repair request beside a damaged technical, moved it 100 m away, verified reach failed, and advanced only the job deadline. Completion still repaired its engine and consumed the actor's part. The deadline was shortened for this diagnostic; the production completion path was used.

Recommendation: recheck vehicle reach during work and immediately before completion, with clear cancellation feedback. Cover repairs, refuelling and salvage.

### A3-07 — P2: numeric faction doctrine settings are not connected to AI

Locations: [doctrine.gd:38](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/doctrine.gd:38>), [doctrines.json:6](<C:/Users/My Little Pony/Documents/Contractor/data/doctrines.json:6>), [squad_ai.gd:134](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/squad_ai.gd:134>) and [tactics.gd:113](<C:/Users/My Little Pony/Documents/Contractor/scripts/ai/tactics.gd:113>).

The data and class comments describe faction-specific engagement range, reaction, aim, bursts, grenades, morale and movement. A repository search found no gameplay calls to `Doctrine.value()`. Those decisions still use existing constants. For example, the regular profile says 100 m, while hostile target selection uses the hardcoded 60 m sight range. The advertised per-unit `SquadAI.doctrine` property is also absent.

This is a source-confirmed incomplete integration, not a claim that all doctrines have no effect: `SquadTactics` does use doctrine ids for its own hardcoded option-score biases, and friendly sight already has a separate 120 m constant.

Recommendation: connect the intended numeric fields with explicit fallbacks and behavior checks, or mark this feature/data as pending so tuning changes are not mistaken for working gameplay.

### A3-08 — P2: an import script error can receive a passing runner verdict

Location: [run_tests.sh:129](<C:/Users/My Little Pony/Documents/Contractor/tools/run_tests.sh:129>).

The import step checks process exit status but does not inspect `import.log` for script errors. Suite logs have that check. An import process that returns zero while reporting a parse error can therefore pass if the selected scenes still print passing summaries.

R0010 used a synthetic engine that printed `SCRIPT ERROR: Parse Error: injected audit import failure` during import, returned zero, then printed a passing smoke summary. The production runner exited zero and retained a PASS result. This tests the verdict logic; it is not a real Godot smoke pass or evidence of a current broken production script. The existing runner self-check covers nonzero import failure, but not this case.

Recommendation: inspect import diagnostics as well as status, and add the successful-exit/import-error case to the runner self-check. Keep the documented exception for engine shutdown failure after completed suites separate.

### A3-09 — P2: CI discards the detailed logs needed to investigate failures

Locations: [tests.yml:64](<C:/Users/My Little Pony/Documents/Contractor/.github/workflows/tests.yml:64>), its failure rerun at line 71, and [run_tests.sh:35](<C:/Users/My Little Pony/Documents/Contractor/tools/run_tests.sh:35>).

CI does not set `CONTRACTOR_TEST_LOGS` or upload artifacts. The runner explicitly keeps nothing on GitHub Actions without that variable and deletes temporary logs on exit. Successful suites print summaries, and failed suites expose selected checks/tails, so the original complete host/client/import output is unavailable.

The fallback rerun invokes one process without the runner's host/client arguments. For world, vehicles, supports and AAV suites, that does not reproduce the original two-process test. Network is excluded from the fallback altogether. A transient replication failure can consequently leave only partial evidence.

Recommendation: retain and upload the original runner logs on every CI verdict, with run/commit metadata. Annotate those logs instead of relying on a differently configured rerun. Source-confirmed; no remote CI job was launched for this audit.

### A3-10 — P2: test builds overwrite earlier builds and discard export diagnostics

Location: [make_build.sh:14](<C:/Users/My Little Pony/Documents/Contractor/tools/make_build.sh:14>) and the export invocation at line 48; expected workflow: [debugging.md:75](<C:/Users/My Little Pony/Documents/Contractor/docs/debugging.md:75>).

The helper writes to `builds/<date>_<label>/`. Repeating a label on the same day reuses the directory and overwrites the pack, launcher and build metadata. Export stdout/stderr go to `/dev/null`; with `set -e`, a failed exporter exits before the later pack check and leaves no useful export log.

The documented shared run number, unique build folder and retained export log are not implemented by this helper. These are source-confirmed delivery gaps, not a failed export observed during this audit. The existing local preset excludes tests/tools/docs and includes JSON data; its standalone template path is machine-specific. The README accurately describes the pack launcher as requiring the custom editor.

Recommendation: allocate a unique build id/folder, capture exporter output in the shared log parent, retain failure details and tie the pack's metadata to that id. Preserve existing builds. Validate both the pack and standalone launch paths before distributing a new build.

## Validation and performance

| Run | Result and meaning |
| --- | --- |
| R0006 | PASS: materials, map, world, missions, vehicles, antiarmor, supports, AAV and sound; all applicable host/client checks passed. No script/engine errors found in these retained logs. |
| R0007 | Overall FAIL: first combined diagnostic had two corpse-position assertions fail because it did not wait for the displayed hitbox pose; its empty-world navigation fixture also queried an unsynchronized map. The separate real raid diagnostic passed and confirmed A3-01. The original logs remain retained. |
| R0008 | PASS: corrected waits/navigation fixture; all building-cache, civilian blast, corpse extraction, distant repair and edited-proxy observations confirmed, without script or engine errors. |
| S0009 | Excluded initial synthetic import check: restricted shell could not retain its temporary logs. Captured terminal result retained; repeated with established test access. |
| R0010 | Synthetic PASS that should have failed: import-error verdict gap reproduced. Not an engine/game test. |
| S0011 | Existing runner self-check passed all seven cases and its three retention checks. Audit copy only adjusts the working directory and preserves fake-engine fixtures instead of deleting them. |

Evidence: [R0006 summary](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-13/R0006-042527-PASS-dev-fcae676/summary.txt>), [R0007 raid log](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-13/R0007-044126-FAIL-dev-fcae676/audit_clear.log>), [R0008 diagnostic log](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-13/R0008-044339-PASS-dev-fcae676/audit_part3.log>), [R0010 import log](<C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs/2026-10-13/R0010-044459-PASS-dev-fcae676/import.log>).

The standard 1.92 km world benchmark generated in **320 ms** against a 1,500 ms budget. Streaming recorded **40.2 ms worst**, **7.0 ms average**, and **47 MB static memory** against budgets of 150 ms, 25 ms and 250 MB. These are one local headless test's measurements, with its controlled actors and route. They are not rendered FPS, GPU/VRAM or peak resident-memory measurements, and do not establish performance of a populated 4.096 km hot zone after a long session. Finest terrain meshes are retained as new areas are visited; a full traversal is an appropriate next graphics-memory measurement.

Generation determinism, collision-height consistency, edit replay on return, vehicle/cargo state and late joins, support flight/insertion/extraction, AAV coastal operations and sound data all held up in the exercised standard cases.

Reproduce gameplay probes through `docs/audits/diagnostic-engine.sh` with `AUDIT_REAL_GODOT` set to the editor, then run `tools/run_tests.sh audit_part3 audit_clear`. Use the isolated tag, port and retained log parent documented in this folder. The synthetic import check instead uses `import_error_engine.sh` as `GODOT`; its current false-green result is the observation under review.
