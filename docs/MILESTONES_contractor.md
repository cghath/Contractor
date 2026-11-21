# Contractor: Milestones

Status: draft, 2026-11-20. Sources: VISION_contractor.md (Captain's decisions), gates/contractor-decision.md, cheeno_next.md, handoff_2026-11-10_playtest_bugs.md.

How milestones work here: each milestone ends with /gate. A milestone is finishing passes, not new features. Nothing is cut; everything built stays in v1. Sizes are relative (S/M/L). No dates.

## M0: Stabilise (Size M)

Goal: a green dev that builds, with the gate must-fixes done.

- Green `loadout` and `interaction` suites; one full-suite CI run on dev. Owner: Cheeno. (Must-fix 1)
- Triage the 13 unmerged branches into dev in the order in cheeno_next.md section 2, green ones only. Owner: Cheeno. (Must-fix 2)
- Clamp buy `count` to 1..50 in `economy.gd` and `base_hub.gd`, including `server_buy`. Owner: Cheeno. (Must-fix 3)
- Port Fallen's accessibility tab, solo pause, subtitle toggle and text size; add Quit to the main menu. Owner: Cheeno. (Must-fix 5)
- Play one 20-minute contract on dev; fresh screenshots (soldier, day/dusk/rain, HUD, inventory, map); check the 45-degree camera yaw and ADS offset. Owner: Captain. (Must-fix 4)
- Current runs of the two-process suites (supports, vehicles, net, operations). Owner: Cheeno.
- `ci/release-on-tag`: a test tag builds and exports. Owner: Cheeno.

Exit criteria:
- Full-suite CI run on dev is green; `loadout` and `interaction` green on that same commit (run IDs cited).
- Each merged branch has a green CI run; dev stays green after each merge.
- Buy test with counts 0, 1, 50, 51 and a value near 2^63: host banks at most 50, no overflow (test output).
- In a run: solo pause stops the fight, and Quit exits the game.
- Test tag exports a build.

Risk: `loadout` has been red in 14 of 16 runs; flakes can hide real regressions. Merging the 27-commit `feat/vault-legs-svd` last may break the two-process suites. Unverified: whether the red suites are test-side or game-side (not yet known).

## M1: Infantry, medical and squad loop, then the first playtest (Size L)

Goal: one contract, start to finish, in the full game, with body compensation in place.

- Body compensation: heart rate rising with blood loss, and clotting. Owner: Captain (the wound model is his). Must land before the playtest.
- Squad slot leap F-463 (on `feat/vault-legs-svd`); tune SLOT_CATCHUP_MPS and BASE_WALK_MAX_MPS by play. Owner: Cheeno.
- Forearm clip ends the shot, F-485 (`fix/ci-flakes-nov`). Owner: Cheeno.
- Breach and clear order; tune DRAG_RAGDOLL_TRAIL_M (`feat/breach-and-clear`). Owner: Cheeno.
- Surrender and freed bodies (`fix/surrender-freed-body`); loadout buy (`feat/loadout-buy`). Owner: Cheeno.
- Campaign camera yaw and ADS offset, if M0 confirms them. Owner: Cheeno.
- STYLE.md, written from the M0 screenshots; re-judge art Majors 3-6. Owner: Captain.
- Hit kick and noise shake, after tester feedback. Owner: Captain.
- First playtest: one contract by Cheeno and friends; notes and session RPT go through /feedback.

Exit criteria:
- Body compensation merged with a test that cites heart-rate and clotting output.
- `breaching`, `roles`, `interaction`, `loadout` suites green three runs each on the same commit.
- SLOT_CATCHUP_MPS, BASE_WALK_MAX_MPS and DRAG_RAGDOLL_TRAIL_M no longer "Proposed" in their files.
- One non-builder finishes a contract; notes filed; RPT logs attached.

Risk: body compensation changes the wound model that every other system rests on. Squad AI regressions (F-463 has leapt in three runs before). Placeholder audio in the playtest build must be labelled.

## M2: Vehicles, supports and economy finishing passes (Size L)

Goal: the rest of the built game reaches the bar before v1.

- Enemy armour, `feat/enemy-armour`: CHARGE_ENGINE 0.6 tuned by play; F-496 (the 9M119M flies as a shell; AI crews fire only the coax). Owner: Cheeno.
- AAV landing with AAVs afloat, F-481. Owner: Cheeno.
- Helicopters, Blackhawk resupply and transport, extraction calls. Owner: Cheeno.
- Economy: `feat/economy-balance` is 495 commits behind and stale; rebase or rebuild is a Captain call. Owner: Cheeno, once Captain picks.
- Factions and territory shift. Owner: Cheeno.
- Woods render perf, `perf/woods-copses`: frame-time check. Owner: Cheeno.
- Bots joining a human-hosted game, `feat/bots-join-hosted`. Owner: Cheeno. Co-op is a bonus under Captain decision 2.

Exit criteria:
- `vehicles`, `armour`, `supports`, `net`, `operations` suites green three runs each on one commit.
- CHARGE_ENGINE and every other vehicle or support number listed in the code is tuned, with no "Proposed" left.
- Frame-time numbers recorded for the woods and city scenes.
- One non-builder vehicle and support session; notes via /feedback.

Risk: second-system bloat as new vehicle and support ideas arrive. Economy rebase may be large. Two-process suites are slow to get green.

## M3: v1 closed playtest (Size M)

Goal: the full game on the shipped commit, with an invite-only test group.

- Security minors 1-8 from cheeno_next.md section 4. Owner: Cheeno. Captain decides whether base money actions become host-only.
- Pad and Ctrl/Alt rebinding, and a keyboard-free tutorial path (UX Majors 3-4). In for v1: "no cuts" keeps every system, and rebinding finishes the controls rather than adding a feature (call made 2026-11-20; Captain can overrule). Owner: Cheeno.
- Final tuning pass on all remaining "Proposed" numbers. Owner: Cheeno.
- Invite text states solo first, co-op welcome. Owner: Captain.

Exit criteria:
- Full-suite CI green on the shipped commit, three runs.
- Exported build from a release tag.
- Zero "Proposed" numbers in the core loop files.
- The test group (Cheeno and friends) plays the full campaign; notes via /feedback; no open must-fix.

Risk: notes arrive after the freeze. Invite scope grows beyond what the test group can report on. Security minors matter more once more people join.
