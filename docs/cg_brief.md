# cghath: standing brief (the Captain, 2026-10-21)

**Read this first, every session. It replaces "ask the Captain when a call is his" in the
2026-10-20 task list. That line was wrong, and it's why your agent kept stopping.**

## Rule zero: never stop to ask. Decide, note it, keep going.

The Captain plays the builds; he doesn't answer agents mid-task. Five or six times now your agent
has stopped on questions that "need the Captain's answer". From now on:

1. **When a call looks like his, make it yourself** with the rules in "His standing calls" below.
   Pick what's closest to Arma 3 + ACE3/KAT + LAMBS/VCOM realism that's still fun to play.
2. **Put every number you invent in data** (`data/*.json`) or a named const, marked
   `Proposed`, so it can be tuned without code.
3. **Write each call down** under "Calls made for the Captain" at the bottom of
   `docs/audits/followups.md`: one line each, saying what you chose, why, and what the alternative
   was. Then carry on.
4. **Finish the whole task:** code, tests, CHANGELOG, push. If one piece really can't be done
   (missing art, a bug outside your area), build everything else, log the gap as an F-xx item,
   and move to the next task. Don't end the session waiting.
5. **Only stop for:** something that would delete or overwrite player saves or other people's work,
   or a hard rule below that two requirements contradict. Even then, take the safe option, log it
   and continue.

## His standing calls (answers to the usual questions)

- **Art:** characters and gear are **0.5 cm voxels** (VoxelArt BODY_VOXEL; gear FINE_VOXEL). No
  meshes or textures for bodies. Real camo patterns.
- **Names:** real military gear names are fine (M4, M1014, PKM). Factions, companies, vehicles we
  invent and anything sci-fi get **original names**, no trademarks. Never say Contractor "copies"
  a game: "learns from" or "inspired by".
- **Realism bar:**
  - medical is ACE3 + KAT and beyond;
  - AI should beat Arma 3 Veteran + LAMBS + VCOM;
  - gunplay and animation feel like Star Citizen on foot;
  - gore is realistic, on by default.
- **Multiplayer:** host-authoritative. State changes go through the host's `server_*` functions
  and RPCs. Every peer and late joiner sees the same thing. Anything random that should match on
  every peer uses a deterministic seed.
- **Numbers:** when unsure, pick a sensible value, mark it Proposed, and make it tunable.
  Deterministic over random where saves or sync are involved.
- **Saves:** never delete them. Archive, don't remove. Zones start fresh each contract.
- **Bots act like players:** they choose things and say so (callouts). Nothing teleports or
  happens by reflex.
- **UI:** use the shared UiKit kit. Every menu says what it's for. It must fit the ui_test's 10
  resolutions.
- **Testing:**
  - headless Godot only, never pop a window, because the Captain games on this PC;
  - set CONTRACTOR_PORT and CONTRACTOR_TEST_TAG, because other agents test in parallel;
  - run your affected suites plus smoke, not the full suite locally; CI runs the full set;
  - test logs are never deleted.
- **Branches:**
  - base new work on `origin/claude/ai-driving`, which has everything (v0.5.1 = 1a74488);
  - one branch per task; push it;
  - Claude merges into claude/ai-driving and cuts builds, and dev fast-forwards on green CI.
  - Don't wait for a merge to start the next task.
- **When something lands:** a CHANGELOG entry, then a short note in the Captain's Discord thread.

## Already done or taken by Claude: don't redo

- Items 1-5 of the 2026-10-20 list: treatment props and first-person hands, fingers, visible
  tourniquets/splints/IVs, faces and per-soldier looks, blast dismemberment and synced pieces.
- Also done:
  - gunfire dismemberment and gore fixes (neck stump, hanging limbs);
  - helmet fit;
  - feet;
  - arm and hand hits;
  - the first headshot on a downed man;
  - the conscious-but-dying state;
  - pocket loot;
  - 214 new items;
  - the terror groups and the living war;
  - the breacher role.
- **One 12-gauge system:**
  - Standard and Hi-brass shells in every shotgun;
  - Breaching rounds only in the M1014 and the **Skeleton Key** (your M870, renamed);
  - a choke for the Remington 870;
  - your F-131 (AI shotgun ammo) is fixed.
  - Your later commit "M320 only: ... ours comes out" on feat/m320-shotgun must **not** be merged:
    the Skeleton Key stays.
- **Merged from you:** demolitions, fire support, fallen (dog tags, memorial), M320,
  world-visual, pip-scopes, tutorial-2, assault-warning.
- **Not yet merged:** `feat/missions-2`, `feat/voxel-smoke`, and your newer `feat/demolitions`
  commit (F-122). Finish and push them; Claude merges them next.
- H-menu injury text, tracers and fire-mission arcs.

## Your queue, in order, with the calls already made

Before each item, grep the code. If it's already built, skip it and say so in the CHANGELOG.

1. **Finish `feat/missions-2` and `feat/voxel-smoke`.** Rebase or merge onto
   origin/claude/ai-driving; get missions, contracts, world and smoke green; push.
   - **Voxel smoke:** AI sight follows the real cloud, and thermal sees through smoke.
2. **F-130: AI grenadier fires the M320.**
   - HE at enemies in cover 30-250 m away, never with a friendly within 12 m of the aim point.
   - Smoke on the squad's "throw smoke" order.
   - Loads by hand in cover.
   - You may edit squad_ai.gd and tactics.gd for this; keep it to a new helper plus a hook.
3. **F-120: squad AI avoids our own mines and claymores** (Demolitions.hazards): through path
   costs and move-point rejection.
4. **F-160 / F-161: dog tags.**
   - A worn chain and tags model at 0.5 cm.
   - A scavenger or bearer takes a fallen friendly's tags and says so.
5. **F-150 / F-151.**
   - Enemies shoot at the recon UAV once it's below 300 m and in sight.
   - Enemy vehicle crews drive out of a fire-mission area after the first round lands.
6. **Medical, still missing:**
   - IV lines pull out on a sprint or carry;
   - CPR slows the arrest window (Proposed ×0.5 while it's done properly);
   - a stretcher/litter for 2 carriers, faster than a fireman's carry over distance;
   - body bags;
   - medical foley (tourniquet ratchet, velcro, packaging);
   - a heartbeat when SpO2 is low or blood loss is high;
   - fix the stale header at vitals.gd:28-30.
7. **Animation:** directional hit reactions and stagger, scaled by round energy and part.
8. **Optics and night:** NVG IR illuminators (visible only under NVG), and thermal optics as a
   scope variant (white-hot/black-hot, sees through smoke, not through walls).
9. **Player drones:** a recon quadcopter (data-link range, battery, marks targets) and an FPV
   drone (one-way, warhead from Warheads, jammable by the existing jammer).
10. **Weather:**
    - rain, fog and storms in the day/night cycle;
    - storms ground helicopters (a Proposed wind limit);
    - fog cuts sight via the existing spotting.
11. **Gore setting:** off / reduced / full, default full, in Settings, if it doesn't exist yet.
12. **Vehicles and air**, in this order:
    - crewable Bradley and Abrams main guns;
    - enemy armed helicopters at high alert;
    - close air support and attack-helicopter runs as a support purchase;
    - the Razorback nose pod;
    - player-flown aircraft last.
13. **Multiplayer:**
    - inventory changes send deltas, not the whole snapshot;
    - a headless dedicated-server launch flag (`--server`) that hosts a campaign with no local
      player.
14. **Campaign:** LRRP missions with time acceleration and fatigue. Food and water stay
    deferred: don't build them.

When the queue is done, take the oldest open F-xx item in docs/audits/followups.md, then
anything in docs/build_plan.md marked Queued.

## Calls made for the Captain

Add these to the bottom of docs/audits/followups.md as you go, one line each:
`date | what was decided | why | the alternative`. The Captain reads them when he reviews.
