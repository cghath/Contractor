# Handoff to Cheeno: Contractor and Contractor: Fallen (2026-10-30)

Captain is handing both lines over to you for a while. Everything he had is now on GitHub
(`cghath/Contractor`). This page says where each piece is, what state it's in, and what was left
open. Agents: read [CLAUDE.md](../CLAUDE.md) first; its rules still hold.

## Where everything is

| What | Branch | State |
|---|---|---|
| **Contractor** (the tactical shooter) | `dev` | Tip `6a52a7f` (2026-10-27). Last build v0.7.1 (B2851, `872f964`). |
| **Contractor: Fallen** (the open-world survival game) | `claude/fallen-build` | Tip `a635893` (2026-10-30): all of Fallen plus everything on `dev`. Last build "fallen slice k2" (B2856, `cacdcc0`). |
| Unfinished work | about 20 small branches | Each one is listed under "Leftover branches" below. Everything is pushed; none of it is in `dev`. |

- Fallen is built **on top of** Contractor: same engine code, plus 190-odd commits of survival
  systems. It stays on its own branch on purpose; it has **not** been merged into `dev`.
  To keep it current: `git merge origin/dev` into `claude/fallen-build` (it merged cleanly on
  2026-10-30).
- The `claude/survival-*` lane branches (about 35 of them: `survival-body`, `survival-seasons`,
  `survival-firsthour`, ...) are all already merged into `claude/fallen-build`. Keep them for
  history; build new work on `claude/fallen-build`, not on them.
- Builds live on Captain's machine (`B:\Contractor\builds`), not in the repo. Make your own with
  `VERSION=v0.x.y tools/make_build.sh` (see [captain_side_now.md](captain_side_now.md) "Builds").

## Getting set up

- **Engine:** Godot **4.7.2 with Zylann's Voxel Tools 1.7 built in** (the custom editor build;
  the stock editor fails on `VoxelTerrain` and similar). Forward+ renderer, Vulkan GPU. The
  [README](../README.md) has the download links.
- **Tests:** only through `tools/run_tests.sh`. Set `GODOT` to the Voxel Tools editor and give
  each agent its own `CONTRACTOR_PORT`. With arguments it runs only those suites
  (`tools/run_tests.sh smoke survival`). Suites are `tests/<name>_test.tscn`.
- **Logs:** every run gets a number (R/S/B/P + number) and keeps its logs forever, outside the
  repo. Cite run numbers when you report results. See [debugging.md](debugging.md).
- **CI is the full check.** Locally, run the suites you touched plus `smoke`. Push your branch
  and let CI run everything. Move `dev` only once that branch is green, so `dev` never goes red.
  Run the full suite locally before merging the other side's work and before exporting a build.
- **Commit messages and docs** are in plain prose: what changed and why, with the run number
  (R2807 PASS, ...). Match it.

## Contractor (`dev`): where it stands

The game: command an 8-slot squad (up to 4 players, AI fills the rest) through a persistent
campaign, with physical inventory, blood-and-wound medicine and voxel destruction.

**Design and plans:**
- [contractor_handoff.md](contractor_handoff.md) is the design authority: Captain's decisions.
- [cg_brief.md](cg_brief.md) is your queue with the calls already made.
- Also [build_plan.md](build_plan.md), [captain_side_now.md](captain_side_now.md) and
  [cheeno_tasks.md](cheeno_tasks.md).

**Last few days on `dev` (2026-10-26 to 27):**
- **Model realism** (`claude/model-realism`): soldiers in their armour and kit, body
  proportions, clothing and camo. It also fixed the decapitation neck and limbs not coming off
  to RPG/AT4 hits. It has landed, so the hold in cheeno_tasks.md on `voxel_art.gd`,
  `gear_rig.gd`, `voxel_armor.gd`, `feet.gd` and `face_art.gd` is over.
- **Wounds inside the body:** real cavities along the round's path. Notes in
  [wounds_visual.md](wounds_visual.md).
- **The body carries weight:** inertia, landings, planted turns, foot IK, vaults, load sway.
- **v0.7.0 fixes, then v0.7.1.**
- **Roles: bounding by pairs.** One pair bounds while the fire team's other pair covers, and
  "Covering!" is only called after a "Moving!" that was heard. The commit before it was marked
  "WIP dev reds: roles still red". The last commit says it fixed that, but nobody re-checked CI
  afterwards. **Check that `roles` passes on `dev` first.**
- **City perf:** AI-only squads keep their formation slots while the lead barely moves. This
  halved the slot work-outs, and AI runs about 10% cheaper. `PERF_AI_PROF=1` in perfcases
  prints the AI phases.

**Still open** (from captain_side_now.md "Next"; some may already be done, check the code):
- woods render perf, then denser copses (`art/denser-copses`);
- AI awareness leaking through compound walls (ai_bar_gaps G-02/G-03);
- breaching holes too small, and a "Breach and clear" order;
- bots joining a human-hosted game;
- a GitHub release workflow on tags.

## Contractor: Fallen (`claude/fallen-build`): where it stands

An open, persistent world overrun by the dead, built on Contractor's engine. Start with
[survival.md](survival.md) (on the Fallen branch). Its top section, "Where the build is", lists
every lane with its run number. Each system has its own doc: `survival_people.md`,
`survival_world.md`, `survival_firsthour.md`, `survival_wear.md`, `survival_hands.md`,
`survival_events.md` and so on. Mods: [fallen_modding.md](fallen_modding.md).

**Built:** phases A to D (the map, metabolism, people, building, settlement, body and medicine,
seasons, world sim), and then nearly the whole calls table:
- **Nature:** fauna and flora; the dead over time (decay, dress, nests); the nerve meter and the mind.
- **Kit:** condition and wear (1 and 2), clothing layers, the gear editor for companions and
  pouches, third person.
- **World:** world events and the live convoy; loot states and the early loot curve; drop-in
  co-op; the mod kit.
- **People:** children, faith and letters; bonds and gunsmithing; holding or fleeing, and
  claiming places.
- **The rest:** audio and the tension layer; the first hour (a start farmstead, the first-day
  thread, control hints); polish (wait an hour, the world list, navmesh with builds,
  accessibility).

**Last work (2026-10-28):** camo that's actually worn is what the eye sees (call 122); tear a
garment into rags; roast meat and fish on a stick; bows and arrows (the archery line); survival
CI reds fixed (50 survival items priced, quick melee on the pad, the intel by-type check; CI
#1445).

**Known soft spots:** a few checks have flaked under load and passed their reruns: survival's
stealth-kill and footsteps checks, fallenpeople's take-over, and settlement's haul check (red
since the firsthour merge). Run reports in survival.md are marked FLAKY where it happened.

**Voiced lines:** the renderer is wired up (Piper by default, Kokoro or XTTS-v2 by config), but
no clips have been rendered yet ([survival_audio.md](survival_audio.md)).

## Leftover branches (pushed, not in `dev`)

Commits marked "WIP ... saved for the handoff; untested" were uncommitted edits in Captain's
worktrees, saved on 2026-10-30 so nothing was lost. Treat them as notes, not finished work.

| Branch | What's in it |
|---|---|
| `claude/vault-legs` | Vault hand plant and hitboxes on the drawn legs (2026-10-27). Probably wanted. |
| `claude/svd-model` | The SVD's own model (thumbhole stock, 10-round mag). Probably wanted. |
| `claude/loadout-buy-direct-7330b2` | The loadout editor offers catalog items the stash lacks, plus WIP edits to `soldier.gd`, `ballistics.gd`, `tracer.gd`, `compound_level.gd`. |
| `claude/objective-driscoll-bdd64c` | WIP edits to `helicopter.gd` and `vehicle.gd`. |
| `wip/w6-on-pr2` | Wave 6 groundwork that was staged on top of your PR #2 and never committed (15 files: campaign, economy, contracts, factions). `dev` has since moved on; diff it against [wave6_groundwork.md](wave6_groundwork.md) on dev before using any of it. |
| `fix/weapon-model-ground` | WIP: weapons lying on the ground (`voxel_art.gd`, weapons test, `weapon_shots`). |
| `feat/zone-dynamism` | Squad-sized fighting positions and trench network: a doc and its WIP edits. |
| `feat/terrain-presets`, `feat/mission-variety-1` | A WIP preset screenshot test; WIP loop and missions test edits. |
| `feat/squad-comms` | Squad comms MVP (bots talk like players), paused mid-build. |
| `perf/frame-rate`, `fix/drag-direction`, `ai/movement-quality` | Handoffs at "96% usage", unfinished and untested (2026-10-14). |
| `fix/s1-objective-wipe`, `fix/loot-flake`, `fix/b08-*`, `test/coop-*`, `wip/s1soak-checks`, `wip/frame-bench-viewer-lod`, `exp/forest-zone` | Oct 13-14 co-op soak and flake work. Mostly superseded; check before reviving. |
| `vehicle-models`, `art/gear-fit`, `docs/handoff-oct13-late` | Older (Oct 9-13); dev has moved well past them. |

**Not pushed:** `local/contractor-f-gear` ("Contractor F", an AER9 and T-60 gear rebuild) is
marked local-only and stays on Captain's machine.

## House rules worth repeating (full text in CLAUDE.md)

- **Bodies:** measure reach to a body with `Soldier.body_point()`, never its
  `global_position`. Never rewrite commits `7fe9e3e`, `8a165b7`, `e17f739` or `ad5378c`. Keep
  the "Looting" and "Standing up where the ragdoll lay" checks passing.
- **Pushing:** push your own work branches freely. `dev` only moves on a green CI.
- **Make the call and keep going:** decide using cg_brief.md, mark new numbers Proposed, and log
  the call in docs/audits/followups.md.
- **Captain is his name, not a rank.** Write about him plainly.
