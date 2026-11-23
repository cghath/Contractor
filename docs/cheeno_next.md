# Cheeno's next list: Contractor and Contractor: Fallen (2026-11-20, updated 2026-11-23)

Cheeno, this is the list from the 2026-11-20 gate. The gate was a NO-GO for outside playtesters on both games, because nobody has played them since the last reports and the care scores are 6/10 (Contractor) and 6.5/10 (Fallen). Everything below is yours unless it sits under "Not yours (Captain's)". Work the must-fixes in order, and make the calls yourself as the handoff says; log them in docs/audits/followups.md and mark any new numbers Proposed.

The branch commit counts and the F-ids below were checked against git on 2026-11-20. The full gate reports are in `docs/gates/` on both lines: `contractor-*.md` and `fallen-*.md`, all in `docs/gates/` on this branch.

## 1. Must-fixes

Contractor (`dev`, gate commit 54ccc3d0):

1. **Green the red suites, then run the full suite on dev.** Where: `tests/loadout_test.gd` and `tests/interaction_test.gd`. Gate run R2931 failed on loadout (`B:\Contractor-test-logs\2026-11-20\R2931-*\loadout.log` lines 88-89) and on interaction ("shot through the hips", interaction.log:177). Loadout has been red in 14 of 16 single runs since 10-22. Find out first whether each failure is test-side or game-side. Done when: a full-suite CI run on dev is green, and the loadout and interaction runs are green on that same commit. Also check the two-process suites (supports, vehicles, net, operations), which have no recent evidence.
2. **Triage the 13 unmerged branches into dev, green ones only.** Where: see section 2. Done when: each merged branch has a green CI run, and dev is still green after each merge.
3. **Clamp buy `count` to 1..50.** Where: `economy.gd:791-794` (`_rq_buy`) and `base_hub.gd:3496-3497` (buy). Also clamp in `server_buy` (economy.gd:560, base_hub.gd:2766, both per the security report). The sell path already clamps at economy.gd:750 and 761; copy that. Done when: a test sends count values of 0, 1, 50, 51 and a huge value (near 2^63 / price), and the host banks at most 50 with no overflow. (Suspected overflow, per the security report; not reproduced.)
4. **Port Fallen's accessibility tab and solo pause, and add Quit to the main menu.** Where: Fallen has `scripts/survival/accessibility.gd` and `scripts/survival/solo_pause.gd`. Contractor has no colour-blind mode, no subtitle toggle (`scripts/ui/callouts.gd:545` always shows subtitles), no text-size setting (`settings_menu.gd:218` scales layout too), and the pause text says "nothing pauses" (`pause_menu.gd:32`). The main menu (`scripts/ui/menu.gd`) has no Quit. Done when: a solo player's pause stops the fight (checked in the run), and a Quit button exits the game.

Fallen (branch `fallen/nov10-playtest`, pushed; HEAD daaaf2d1. It's `claude/fallen-build` plus Captain's Nov 10 playtest fixes, your hordes and convoys, and the review fixes, so it's the line to build on now):

5. **Save the survivor on quit.** Where: `pause_menu.gd:165-170` (quit calls only `GameState.save_zone()`), `survival.gd:307` (`server_stop`, which no code calls), `survival.gd:293` (`server_save`), `main.gd:44` and `main.gd:49`. Also reset `Survival.running` on return to menu (`survival.gd:46` is the flag; only `server_stop` clears it). Done when: a test continues a world, changes loot within 5 minutes of the last autosave, quits, continues, and finds the kit, needs and clock as they were at quit. Then reset `running` and confirm no survival code runs in a later non-survival session.
6. **Fix the ocean-louder-inland and bleeding-darker bugs, and make survival and firsthour green repeatedly.** Where: the bug text is in `docs/handoff_2026-11-10_playtest_bugs.md:70-72`. I could not find the code location for either bug, so the first step is to find it, working from Captain's description of the triggers. Add tests for the dormant cold-open barn walker (`cold_open.gd:76`) and the x0.75 tired swing. Done when: `survival` and `firsthour` pass three runs in a row on HEAD, and the two bugs have a test or a repro in the RPT log. (The survival suite was 6 red in a row on 11-10.)
7. **Clamp buy `count` to 1..50 (shared RPC).** Same fix as Contractor item 3. Do it once in the shared code and merge it into the Fallen line. Done when: the same test as Contractor item 3 passes on the Fallen branch.

## 2. Land your branches

Triage each branch into dev only if its CI is green. Merge in the order shown. The first items fix stalls and flakes, and `ci/release-on-tag` is needed for an exported build.

| Branch | What | Suggested order | Check before merging |
|---|---|---|---|
| fix/ci-flakes-nov | CI flake fixes (3 commits) | 1 | Full-suite CI green |
| fix/city-stall | City stall fix (10) | 2 | perfcases and city suites green; the F-211/F-233 notes |
| fix/ai-awareness-walls | AI awareness through walls (6) | 3 | ai_bar_gaps G-02/G-03 checks |
| fix/dynamicsim-sleepers | Sleeper sim fix (1) | 4 | World suite green |
| feat/enemy-armour | Enemy armour (2) | 5 | vehicles and armour suites green |
| ci/release-on-tag | Release workflow on tags (4) | 6 | A test tag builds and exports |
| fix/surrender-freed-body | Surrender and freed bodies (3) | 7 | interaction suite green (see Must-fix 1) |
| feat/d8-staging | Staging (2) | 8 | Full-suite CI green |
| perf/woods-copses | Woods render perf and denser copses (4) | 9 | Frame-time check; no new red |
| feat/bots-join-hosted | Bots joining a human-hosted game (3) | 10 | net and coop checks; two-process suites green |
| feat/breach-and-clear | Breach and clear order (12) | 11 | Breaching tests; roles suite green |
| feat/loadout-buy | Loadout buy (9) | 12 | Run after Must-fix 1 (loadout green) |
| feat/vault-legs-svd | Vault legs and SVD model (27) | 13 (last) | Largest branch: split it if it's not green; loadout and interaction green |

Do not merge `feat/economy-balance` (495 commits behind dev, stale). Do not touch the `wip/` and `claude/` leftover branches in the handoff without checking them first.

Fallen branches: `feat/fallen-hordes` and `feat/fallen-convoy-drive` are already merged into `fallen/nov10-playtest` with the review fixes (daaaf2d1). Nothing to merge. Please review daaaf2d1 yourself: your review counts as the sign-off on the F-530 and F-531 changes. Run R2930 (worldsim, survival, fallenevents, firsthour, smoke: PASS) ran on exactly those changes before they were committed; CI on the pushed branch is the full check (not looked at yet).

## 3. Your open items

From your own recent commits (they live on your unmerged branches, which is why they're not in dev or Fallen yet):

- **F-463 squad slot leap** (no straight way): the "aim" fix went in, out and back; R0886/R0895/R0896 still leapt; round 8 added a slot-step check (`10034d0a`, feat/vault-legs-svd).
- **F-481 AAV landing with AAVs still afloat loses allied squads** and **F-485 a round that clips a forearm ends the shot on that body**: both logged open in `2b5fd999` (fix/ci-flakes-nov).
- **F-496 the 9M119M flies as a shell, and AI crews fire only the coax** (`53ded7a9`, feat/enemy-armour).

Proposed numbers to tune by play once they land: CHARGE_ENGINE 0.6 (`vehicle.gd`, feat/enemy-armour), SLOT_CATCHUP_MPS and BASE_WALK_MAX_MPS (`scripts/ai/squad.gd`, feat/vault-legs-svd), DRAG_RAGDOLL_TRAIL_M (feat/breach-and-clear).

Fallen follow-ups from the 19 Nov review (`docs/audits/followups.md`, F-530 and F-531 "Open" lines):

- Horde rising close to players in small zones: a small zone with no site START_MIN_M from everyone takes the farthest site, which can be inside the crowd's live range (followups.md:2300-2301).
- Groans vs far-tick timing: the groans run on real seconds, the arrival on far ticks, so sleep can end the march before the groans (followups.md:2301-2302).
- Farm pickup inside a player wall in old worlds: `_truck_spot` only avoids the site's own things (followups.md:2316-2317).
- Convoys stalling on road dead: a zombie within `dead_block_m` halts a column (followups.md:2317-2318). The 6 h timeout still ends it.

## 4. Milestone work (owners set 2026-11-21)

After the must-fixes, these are yours. The full plan, with exit criteria, is in `docs/MILESTONES_contractor.md` and `docs/MILESTONES_fallen.md`; Captain's goals for both games are in `docs/VISION_contractor.md` and `docs/VISION_fallen.md`. Read the four pillars in each vision before adding anything: every change should serve one.

Contractor:
- M1: campaign camera yaw and ADS offset, once Captain's M0 contract confirms them.
- M2: helicopters, Blackhawk resupply and transport, extraction calls; factions and territory shift; the economy (rebase or rebuild `feat/economy-balance`, after Captain picks which).
- M3: pad and Ctrl/Alt rebinding and a keyboard-free tutorial path; the final tuning pass on every remaining "Proposed" number.

Fallen:
- M1: wire the hit sounds and zombie audio once Captain sets the feel; fix hint timing and text scale (Captain judges on a replay). Captain's test for fun (decision 7): more interactive, more intense.
- M2: wear and jams, building, clothing, hands, RPG, events, deadtime, nature.
- M3: children, horses, farriers and mounts; gunsmithing and tanning; bonds, people, mind, intel, enclave and settlement; the world sim and polish.
- M4: the security minors in section 5, and a release build from a tag. The playtest invite is solo only (Captain, 2026-11-21), so co-op needs no v1 work.

Seasons (`feat/fallen-seasons`, latest `cc61fe7f`): Captain's session is building the full seasonal look (snow, bare and turning trees, ground tint, ice you can walk on). Plan: `plans/fallen-seasons.md` on that branch. Your part:
- Review the branch when Captain's session says it's done; your review is the sign-off before it merges into `fallen/nov10-playtest`.
- The spike-pit check failed in run R3007. The season session reports it as an older failure, not caused by its changes; that is not yet confirmed. Confirm on `fallen/nov10-playtest` and fix it.

## 5. When there's time

These are the security minors. The test group is invited, not public, so they wait until the must-fixes are done.

1. Join password, and kick a peer that never says hello after HELLO_WAIT_S (`net.gd:122-146`).
2. Rate limits and per-peer caps on reliable RPCs (`map_markers.gd:158` caps neither text length nor count).
3. Base money actions (hire, buy, medbay, pick, role, certify) are open to any peer; "deploy" and "release" are host-only (`base_hub.gd:3473-3497`). Design call: make the money actions host-only too? Ask Captain or log the call.
4. Remote barter: `_server_trade` has no proximity check (Fallen `intel.gd:305-315`).
5. Map marks: cap at about 100 per player and check `pos.is_finite()` (Fallen `survival_map.gd:150-154`, `335-355`).
6. Settlement orders: cap `WorkOrders.server_add` (`work_orders.gd:59-74`) and check the size of `args[0]` in `order_remove` (`settlement.gd:931-974`).
7. Mod value ranges: `modkit.gd:290-315` checks types only; add bounds on n, count and pool.
8. Mod-match check and a doc line saying mods are data-only (`docs/fallen_modding.md`).

## Not yours (Captain's)

- Contractor must-fix 4: play one 20-minute contract on current dev, capture fresh screenshots (soldier, day/dusk/rain, HUD, inventory, map), and check the campaign camera's 45-degree yaw and ADS offset (`B2897` check).
- Fallen must-fix 2: melee swing animation and windup tell (`melee.gd:7`); Captain sets the timings by feel.
- Fallen must-fix 3: rebuild from committed HEAD, play the first hour with screen recording, and capture the first Fallen screenshot set.
- From the 2026-11-21 owners: body compensation (heart rate and clotting), Fallen needs and medical, STYLE.md and the art re-judge, hit kick and shake feel, and the sign-off on the four-season screenshots.
