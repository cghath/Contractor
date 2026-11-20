# QA #1 (systematic) gate report: CONTRACTOR (dev 54ccc3d0, 2026-10-30)

Verdict: FAIL. Two suites are red on the exact gate commit, and the commit has no full-suite green run.
Method: RST / HTSM, risk-ranked. Oracles: the suites' own claims, design docs, followups.md, earlier runs of the same suite.
Absent: no VISION.md, MILESTONES.md or features.json in the checkout. I judged against contractor_design_doc.md, build_plan.md, FEATURES.md and followups.md. I did not read the design docs end to end.

## Fresh evidence I ran (read-only, one invocation, three suites)
R2931, 2026-11-20, HEAD-54ccc3d0, suites loadout side_command interaction, result FAIL.
- side_command: passed.
- loadout: FAILED exit 3. [FAIL] "on your own soldier, his model and kit in 3D (m0001)"; "the draft starts as what he wears"; "Apply fits the draft through the host: the NVG is on his helmet". See B:\Contractor-test-logs\2026-11-20\R2931-*\loadout.log lines 88-89. The host/client net half passed (CLIENT PASSED, 0 failures), so the fault is in the 3D editor, not the net.
- interaction: FAILED exit 1. [FAIL] "shot through the hips (body, through: false)" (interaction.log:177, section "A downed enemy").
- Caveat: one run each. I did not isolate the cause or re-run to test for flakiness.

## Findings
MAJOR-1 loadout suite is red on dev HEAD, and has been red before. R2931 shows the same 3 failures as R2849 (2026-10-27, claude-v070-fixes-02682fa8, which was 8 FAILs in a row, R2842-R2849). index.txt: loadout single-suite runs since 10-22 are 14 FAIL vs 2 PASS (mostly claude-loadout-3d and v070-fixes branches). I found no PASS of loadout on 54ccc3d0 and no recorded fix. Risk: the 3D editor and Apply are the player-facing kit flow; a draft that does not match worn kit could mean deploying with the wrong kit. I did not check whether the bug is test-side or game-side.
MAJOR-2 interaction: "shot through the hips" fails on dev HEAD (R2931). History: 9 single-suite FAIL vs 4 PASS since 10-22, mostly on claude-model-realism-c65b5aa3 (R2819-R2834, ~10 FAIL in a row on 10-27) with PASS on HEAD-98418fdb (R2826, R2829) and on later model-realism runs (R2832, R2835). I cannot tell flaky from regression. Through-and-through hits on a downed body are part of the core wound model.
MAJOR-3 no full-suite run on the gate commit. The only index entries naming 54ccc3d0 are build B2897, playtest P2899 (PASS, 0 errors) and my R2931. Last wide green: R2837 (integrate-oct27-54f46444, 11 suites). R2883 (claude-vault-legs-fb49ddc9, supports + vehicles) FAILED on 10-27 and I found no later non-Fallen supports/vehicles run. I did not open the R2883 log, so I do not know why it failed. The two-process suites (supports, vehicles, net, operations) have no recent evidence on dev.
MAJOR-4 13 branches are not in dev (list in the task), including fix/city-stall, fix/ai-awareness-walls, fix/dynamicsim-sleepers, feat/enemy-armour, fix/ci-flakes-nov, ci/release-on-tag. Several look aimed at open stall and flake classes (F-211, F-233, F-08, F-90, F-80). I did not diff them.
MINOR-1 Flakiness hotspots (index.txt, non-survival, non-Fallen, since 10-22, single-suite runs; branches mixed): side_command 14 FAIL / 4 PASS (branch claude-ca-b1-side-picture; passed in my R2931); income 3 FAIL / 6 PASS, same sha fails then passes (flaky); perfcases 6 FAIL / 33 PASS (F-233 says city streaming is slow on CI); garrison 3 FAIL / 2 PASS; firsthour R2854 FAIL right after R2853 PASS on HEAD-40c8d075; roles R2869-R2871 FAIL, R2873 PASS after dev-reds fixes.
MINOR-2 Open P2 follow-ups with game impact: F-01 and F-02 (AI scans one floor, garrisons on ground floor only), F-03 (engage_m below sight ranges), F-08 (squadmate stuck pushing an obstacle), F-120 (squad walks onto own mines and claymores), F-130 (AI grenadier never fires M320), F-122 (first late join to vehicle range drops the link), F-178, F-192, F-210 (city streets not paved), F-211 (150-450 ms AI scan hitch in cities), F-214, F-222, F-230 (3x movement cost in city), F-231 (async nav map: "watch in game"), F-233 (city blocks may not build for minutes on CI). Open P3: F-131, F-150, F-151, F-160, F-161, F-163, F-191, F-193, F-212, F-213, F-215, F-216, F-217, F-221, F-223, F-232.
MINOR-3 BUGLIST.md (log-watcher, written against integrate/oct14) lists B-01 (downed player never revived), B-04 (clients see players at 0,0,0 after level switch), B-09 (same treatment repeated). I did not verify whether dev fixed them.

## Risk ranking (HTSM)
1. Function/Data: kit and loadout flow (loadout red); wound and hit model (interaction red).
2. Interfaces/Time: multiplayer host+client suites (net, levelswitch, supports, vehicles, operations, soak_wedge) and the B-04 level-switch bug; no fresh green on dev.
3. Platform: perf. perfcases mostly passes headless, but GPU frame time is unmeasured (F-221, F-232) and low-end hardware is not covered at all.
4. Operations: long campaign sessions and save/load. Only unit-level suites; I saw no multi-hour soak result on dev (coop_soak files exist in tests/; I did not look for runs).
5. AI squad stuck and pathing (F-08, F-90, F-80; CI-only flakes).

## Untested or thin systems (name-grep of tests/ vs scripts/, so indirect coverage may be missed)
No test file names: ai_lod, demographics, contracts_debrief, contracts_gen, defence_placer, economy_prices, scenario_checkpoint, binocular_view, gun_light_rig, launcher_sight, context_menu, item_icons, loadout_preview, map_command, map_hc_panel, map_markers, mortar_panel, convoy_column, grass_carpet, perf_warm. The economy has an economy_sim tool but no gate suite naming contracts_gen or economy_prices. tests/ has 126 files; about 82 are _test suites.

## Not done / missing, quality view
- No full-suite green run on 54ccc3d0.
- loadout and interaction red on the gate commit. The 3D loadout editor is a new, large UI feature.
- 13 unmerged branches, some holding fixes to open flakes and stalls; ci/release-on-tag not in dev.
- No VISION / MILESTONES / features.json, so no written definition of done.
- Playtest evidence is a single 0-error session (P2899, build B2897), not a structured test.
- Not checked by me: save/load compatibility, gamepad, low-end hardware, the other ~80 suites on this commit.
