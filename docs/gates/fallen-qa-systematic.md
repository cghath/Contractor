# QA #1 (systematic) gate report: FALLEN (branch fallen/nov10-playtest, HEAD daaaf2d1)

Verdict: FAIL for gate sign-off. The shipped HEAD has no test run I can see, and several owner-reported bugs are still open. The five suites that were run on 26fbc269 pass.
Method: RST / HTSM, risk-ranked. Oracles: docs/survival*.md, docs/handoff_2026-11-10_playtest_bugs.md, the suites, followups.md.
Absent: no VISION.md, MILESTONES.md or features.json; I used the survival docs and the handoff.
I ran no fresh Fallen suites. I judged the existing logs sufficient, and the Godot install and ports were in use by my Contractor run (R2931).

## Evidence
- R2930 (2026-11-19, fallen-nov10-playtest-26fbc269): worldsim, survival, fallenevents, firsthour, smoke all passed. Its twin R2929 failed 25 s earlier at import ("script error", no suite ran) on the same sha; I did not open its log, so the cause is unknown. HEAD commit daaaf2d1 (F-530 and F-531 review fixes to HordeClock and FallenConvoy) is stamped 07:07:50, after R2930 (07:03:32). I could not confirm whether R2930 ran with those changes in the working tree. Treat them as unverified by any suite run I can see.
- Playtests: P2902 FAIL (build B2900): an error about get_meta key rpg_at, and a warning about a duplicate item id cutting_torch; both are fixed in 44345756 per the handoff. P2916 (editor-4434575) PASS with 0 errors; I did not check how long the session ran. The handoff says build B2928 (26fbc269) is "Not playtested yet", and I found no later P-run.

## Findings
MAJOR-1 survival suite is the least reliable. Single-suite runs since 10-26 on survival/fallen lines: survival 24 FAIL, 4 FLAKY, 3 PASS (many fails were mid-development, R2607-R2628). On near-final sha 44345756 on 11-10 it failed R2918-R2923 (6 in a row), passed R2924, flaked R2925 and R2926, passed R2927. The handoff says it was failing before the fixes and that the cure was moving sight checks to open ground 30 m off the farm, so reliability rests on one chosen location. R2930 passed once; one green does not settle it.
MAJOR-2 HEAD daaaf2d1 is not in any run I can see. It changes horde marching, merging of a saved horde, WorldSim mutate write-through, convoy record persistence (rec.live) and road-block failure handling. These are save/load and worker-thread paths, which headless suites cover least.
MAJOR-3 Handoff "Not started" bugs: campaign first-person camera yaw about 45 degrees off the body, with ADS sight offset (the handoff says to check whether dev build B2897 has it; I found no result); ocean noise growing louder at the inland farm; bleeding-out characters turning dark. I did not verify any of these, and none is fixed.
MAJOR-4 Per the handoff, two new behaviours have no test: the cold-open barn walker spawning dormant, and the x0.75 tired-swing damage. I did not read firsthour_test to see whether it covers START_SAFE_M (120 m) and START_SAFE_H (2 h) or ZoneDead._push_off.
MINOR-1 Other suites since 10-26: nature 5 FAIL / 2 PASS (R2861, R2889, R2890 fail; R2892 pass); firsthour 3 FAIL / 1 FLAKY / 5 PASS (R2909 FAIL and R2915 FLAKY on 44345756); hands 1 FAIL (R2692, no re-run seen); building 1 FAIL / 1 FLAKY. On 11-10 the multi-suite runs R2907, R2913, R2918 failed and green came only from single-suite re-runs.
MINOR-2 Untracked in git: docs/handoff_2026-11-10_playtest_bugs.md and docs/gates/. The handoff is the only record of the "Not started" list.
MINOR-3 followups.md is shared with Contractor; its open items (F-01/F-02 building floors, F-120 mines, F-130 M320, F-233 slow city build, and so on) apply here as well. F-530 and F-531 are marked fixed (2026-11-19) but see MAJOR-2.

## Risk ranking (HTSM)
1. Time/Data: long-session survival state (needs, seasons, world sim, horde clock) and saves. HEAD touches these with one 5-suite pass as evidence.
2. Function: melee and zombie combat, retuned in 26fbc269 (damage curve, reach, stagger). The owner has not played B2928.
3. Interfaces: co-op (coop_fallen exists in scripts/survival). I saw no co-op or net run on a Fallen sha.
4. Platform: new audio (engine_soft range, zombie groans) and world sim cost. perfcases was not run on Fallen in anything I saw; GPU time is unmeasured (F-221, F-232).
5. Operations: first-hour experience. firsthour is 3 FAIL / 1 FLAKY / 5 PASS, and no human has played the fixes.

## Untested systems (name-grep, may miss indirect use)
scripts/survival files whose class or file name no test mentions: build_voxels, clothing_art, enclave_node, fallen_story, melee_input, nature_art, predators. My first grep wrongly flagged zombie_ai and companion_ai; a second grep shows tests name them, so they are not in this list. About 25 survival suites exist (survival, rpg, building, deadtime, wear, mind, body, seasons, nature, and others). I did not read their contents.

## Not done / missing, quality view
- No suite run on HEAD daaaf2d1; B2928 not playtested; nothing green after the hordes/convoy review fixes.
- Camera yaw, ocean loudness and dark bleeding bodies are open.
- survival suite stability and the cause of the R2929 import failure are not explained.
- No VISION / MILESTONES / features.json, so no ship criteria.
- Not checked by me: old-world save compatibility, co-op, low-end hardware, GPU performance.
