# Project audit — October 13, 2026

Requested as three parts, with a pause after each so the user can check usage.

| Part | Scope | Status |
| --- | --- | --- |
| 1 | Project structure, multiplayer authority, connection and level transitions, campaign and zone persistence, relevant test reliability | Complete; see part-1.md |
| 2 | Combat, wounds and treatment, inventory, squad and civilian AI, movement, interactions, menus and player-facing consistency | Complete; see part-2.md (9 findings; R0004/R0005) |
| 3 | Terrain and voxel worlds, missions, vehicles and supports, performance, diagnostics, CI, exports, documentation and overall readiness | Complete; see part-3.md (10 findings; R0006–R0010/S0011) |

All three parts are complete. Start with [SUMMARY.md](<C:/Users/My Little Pony/Documents/Contractor/docs/audits/SUMMARY.md>) for the 26 findings, repair priorities, test results and remaining playtest limits.

Baseline: `dev`, commit `fcae676b8318b7534fdc3f2e4d17a9e9a228275f`. Recheck the commit and working tree at the start of each later part. This is an audit, not a fix pass. Findings are recommendations; gameplay source was not changed.

The diagnostic scenes and scripts in this folder reproduce failures or isolate test setup. Their successful observations do **not** mean the production problems have been fixed. In particular, the malformed-request probe intentionally generates a script error.

To reproduce the diagnostic controls and save observations, use Git Bash, set `AUDIT_REAL_GODOT` to the Voxel Tools editor executable, and set `GODOT` to the absolute path of `docs/audits/diagnostic-engine.sh` (make the wrapper executable if needed). Give the run its own `CONTRACTOR_TEST_TAG`, `CONTRACTOR_PORT`, and retained `CONTRACTOR_TEST_LOGS` parent, then run:

```bash
bash tools/run_tests.sh net contracts audit_part1 audit_rpc
```

The wrapper substitutes the diagnostic scenes for those names. For unmodified baseline results, set `GODOT` directly to the editor and run only the normal suites. `audit_rpc` is expected to fail the runner with a script error until A1-05 is fixed. The probe files live entirely in this audit folder; no scenes were left in the normal tests folder.

For the Part 2 diagnostic observations, use the same wrapper/environment setup and run `bash tools/run_tests.sh audit_part2`. Its PASS result means the reported current bugs were reproduced. Part 2's unmodified baseline was `smoke gameplay wounds armor medical casualty squad scavenge movement interaction roles logistics animations people`, all passing in R0004.

For Part 3, use that wrapper and run `bash tools/run_tests.sh audit_part3 audit_clear`. The first scene checks separate-world building caches, blast-only civilian accounting, displaced-body extraction, vehicle repair reach and streamed-out edited collision. The second deploys a generated raid with AI enabled before its garrison streams in. The R0008 corrected probe waits for the displayed body pose and initializes both navigation maps. Its observations and R0007's raid result confirm the bugs, not repairs.

`import_error_engine.sh` is a synthetic engine for the import-verdict observation: use it as `GODOT` and run `bash tools/run_tests.sh smoke`; the current PASS despite its import script error is A3-08. This is not a real smoke test. `runner_check_retained.sh` copies the existing runner self-check with only a working-directory adjustment and fixture retention in `$CONTRACTOR_RUNNER_CHECK_KEEP/fixtures` instead of deletion; give it a retained helper-run folder before running.

**Where the probes are now (2026-10-13):** only the reports are in the repo. The diagnostic
scenes, scripts and wrappers were moved out of the project (so Godot doesn't import them) to
`Documents/Contractor-test-logs/audit-2026-10-13-probes/` beside the main checkout. To rerun one,
copy it back into `docs/audits/` in a scratch checkout, run as above, and don't commit it.
