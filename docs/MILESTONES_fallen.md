# Contractor: Fallen: Milestones

Status: draft, 2026-11-20. Sources: VISION_fallen.md (Captain's decisions), gates/fallen-decision.md, cheeno_next.md, handoff_2026-11-10_playtest_bugs.md, survival_*.md (list below).

How milestones work here: each milestone ends with /gate. A milestone is finishing passes, not new features. Nothing is cut; everything stays in v1. Sizes are relative (S/M/L). No dates.

## M0: Stabilise (Size S/M)

Goal: saving is safe, survival is green, and HEAD is built and played once.

- Save on quit: Esc > Quit, main menu and window close call `Survival.server_save`; reset `Survival.running` on return to menu (`pause_menu.gd:165-170`, `survival.gd:307`). Owner: Cheeno. (Must-fix 1)
- Clamp buy `count` to 1..50 on the shared RPC. Owner: Cheeno. (Must-fix 5)
- Find the code for ocean-louder-inland and bleeding-darker from Captain's trigger descriptions, not guesses. Owner: Cheeno. (Must-fix 4)
- Tests for the dormant cold-open barn walker and the x0.75 tired swing; `survival` and `firsthour` green. Owner: Cheeno.
- CI run on the pushed `fallen/nov10-playtest` HEAD (daaaf2d1), not yet checked. Owner: Cheeno.
- Review daaaf2d1; this is the sign-off on F-530 and F-531. Owner: Captain.
- Rebuild from committed HEAD; screen-recorded first hour; first screenshot set (survivor, zombies, farm, night, body screen, journal). Owner: Captain. (Must-fix 3)

Exit criteria:
- Quit test: continue a world, change loot within 5 minutes of the last autosave, quit, continue; kit, needs and clock match the moment of quit (test output).
- After return to menu, no survival code runs in a later non-survival session (RPT lines cited).
- `survival` and `firsthour` pass three runs in a row on HEAD (run IDs cited).
- Both bugs have a test or a repro in the RPT log.
- CI green on the pushed commit.
- Screen recording and screenshot set exist in the repo.

Risk: `survival` was red six runs in a row on 11-10, so flakes can hide regressions. The save fix changes the save path, so old worlds must be checked. Two bugs have no known trigger yet.

## M1: The fight (Size M)

Goal: melee and zombies read clearly, and the first fight is fun by Captain's definition.

- Melee swing animation and windup tell (`melee.gd:7` claims the arm goes back; no code animates it). Zombie 0.55 s lunge needs a visible tell. Owner: Captain (timings by feel).
- Knife and body numbers from the 11-10 handoff (UNDEAD_BODY_PTS_PER_J, HIT_STAGGER_S, head share, knife energy) tuned by play; label any new value "Proposed" until then. Owner: Captain.
- Hit sounds, shake, input latency and zombie audio (polish Majors 2-5), after the swing lands. Owner: unassigned.
- Gun feel: define "fun" in Captain's words (open question 3 in VISION_fallen.md). Owner: Captain.
- Hint timing and text scale (UX Majors 2-4) judged on Captain's replay. Owner: unassigned.

Exit criteria:
- Swing and lunge tells visible in a screen recording; Captain signs off.
- `melee`, `firsthour` suites green three runs each on one commit.
- No "Proposed" numbers in melee and zombie files.
- One non-builder plays the first hour after the fight changes; notes via /feedback.

Risk: melee and gun feel are subjective, and the only recorded playtest said "not fun yet". Timing changes can break the 0.55 s and x0.75 tests.

## M2: Survival loop and the night 1-7 slice (Size L)

Goal: the playtest slice (farm, one town, nights 1-7, one season, one horde type) reaches the bar.

- Horde rising close to players in small zones (`followups.md:2300-2301`). Owner: Cheeno.
- Groans vs far-tick timing (`followups.md:2301-2302`). Owner: Cheeno.
- Farm pickup inside a player wall in old worlds (`followups.md:2316-2317`). Owner: Cheeno.
- Convoys stalling on road dead (`followups.md:2317-2318`). Owner: Cheeno.
- Wear and jams, needs and medical, building, clothing, hands, RPG, events, deadtime, nature (`docs/survival_*.md`). Owner: unassigned.
- Seasons drawn on terrain for the slice (art Blocker 2). Owner: unassigned. Captain open question 2.

Exit criteria:
- The four follow-ups fixed, each with a test.
- `survival`, `worldsim`, `fallenevents`, `firsthour` green three runs each on one commit.
- No "Proposed" numbers in the listed survival files.
- One non-builder plays nights 1-7; notes via /feedback.

Risk: the gate recommended leaving the sim alone until outsiders had played the first hour; Captain decided otherwise (every system reaches the bar before the first outside session), so M3 follows straight on. The cost: the first outside notes arrive late, after every system is tuned. Seasons on terrain is unscoped (Captain's open question 2).

## M3: People, world and the remaining systems (Size L)

Goal: every frozen system reaches the bar before v1.

- Children; horses and farriers; mounts (`survival_children.md`, `survival_mounts.md`). Owner: unassigned.
- Gunsmithing, tanning, clothing (`survival_hands.md`, `survival_clothing.md`). Owner: unassigned.
- Bonds, people, mind, intel, enclave, settlement with a vote (`survival_bonds.md`, `survival_people.md`, `survival_mind.md`, `survival_intel.md`, `survival_enclave.md`). Owner: unassigned.
- World sim and polish (`survival_world.md`, `survival_polish.md`). Owner: unassigned.
- Co-op: does the invite include it (Captain open question 1). Owner: Captain.

Exit criteria:
- Each system's suite green three runs on one commit.
- Zero "Proposed" numbers in the core loop files.
- One non-builder session per system; notes via /feedback.

Risk: this is the largest scope in the plan, and freezing it has not stopped it growing. Children and animals need the most care in playtest.

## M4: v1 closed playtest (Size M)

Goal: Cheeno and friends play the full game on the shipped commit, starting from a new world.

- Security minors: join password, RPC rate limits, marker caps, settlement order caps, mod value bounds, mods-are-data-only line in `docs/fallen_modding.md`. Owner: Cheeno.
- Release build from a tag. Owner: Cheeno.
- Invite text (solo first, co-op if Captain's open question 1 says so; no store). Owner: Captain.

Exit criteria:
- Full-suite CI green on the shipped commit, three runs.
- The test group (Cheeno and friends, people who didn't build what they test) plays past the first week; notes and session logs via /feedback; no open must-fix.
- Zero "Proposed" numbers in the core loop files.

Risk: the first outside session is also the first real measure of the fun question, so a negative result late costs the most. Security minors matter once strangers join.
