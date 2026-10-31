# Captain's side: start here (2026-10-14 night)

> **2026-10-21, read first: [docs/cg_brief.md](cg_brief.md).** Don't stop to ask:
> decide with the decisions already made there, mark numbers Proposed, log the call in followups.md, and finish
> the task. It has your queue with the calls already made. It replaces "ask the Captain when a
> call is his".

For cghath and cghath's agent. dev now holds everything below. Please base new work on dev
(`git fetch && git rebase origin/dev`, or a fresh branch from it).

## 2026-10-20 evening: your branches, and the economy

- **Merged into claude/ai-driving** (not dev yet; dev moves when CI is green):
  - feat/world-visual, feat/pip-scopes, feat/tutorial-2 and feat/assault-warning;
  - on top of v0.5.0 (42ba3cc), the Captain's major batch.
  - What the merges needed:
    - the debrief's Continue is the UI pass's accent button, kept as `_continue` for the
      assault warning;
    - the assault-warning test listens to `Economy.bill_paid` (bills are daily now; `week_paid` is
      gone);
    - the tutorial's section list got a subtitle (every menu says what it's for); the step panel
      is exempt, like the objectives panel.
- **Your PR #14 (economy) is superseded.** The Captain chose claude/economy, which built the same
  proposal: same numbers, plus a few things beyond it.
  - Hot zones now start on the contracts taken; more come over the radio (his call: "with radios
    and villages entering hotzones with one or two objs will be good"). So hot pay stays x1.4.
  - The HVT case is $3,000 as intel.
  - Radio contracts pay on completion.
  - Intel is banked at extraction.
  - A money section and a Books tab.
  - Villagers' jobs join the live hot zone.
  - Your write-up and measurements are kept in docs/economy.md ("cghath's balance pass"). Please
    close #14 rather than merge it.
- **Your tutorial-2 medic step** ("a squadmate bandaging your leg") failed now and then on the merged
  branch. The squad saw the frozen TutorialTarget and, though holding fire, stayed "in contact"
  (bounding, in cover), so a graze waited. It wasn't one commit, it was timing. Fixed: the target
  carries `SquadAI.STAND_IN`, and a squad holding fire leaves it out of its picture
  (tutorial_guide.gd sets it).
- **The task list we sent you** (models, wounding, medical animations, dismemberment): the Captain
  has us building items 1-5 ourselves now, in parallel. Please don't start them:
  1. treatment props and first-person medic hands;
  2. fingers;
  3. visible tourniquets, splints and IVs;
  4. faces and per-soldier variety;
  5. blast dismemberment and synced pieces.
  Item 6, "the rest", is still open; check with the Captain before picking from it.

## Builds

Build names are now `v0.MINOR.PATCH`: `VERSION=v0.4.2 tools/make_build.sh`. Each build is a merge
commit on `integrate/v0.4.0` (v0.3.x on `integrate/oct15`); tag `v0.4.2` exists.

| Build | Commit | What it added |
|---|---|---|
| v0.3.0 | a31f9f5 | Heli infil/exfil, respawn in your own kit, red dot size, despawn/rejoin fix, fall-through-world fix |
| v0.3.1 | 057dba5 | Drag-stuck fix, medic restock short, debrief outcome fix, squad and loop test flakes |
| v0.4.0 | 4fb6c60 | Briefing map UI, terrain look rounds 1-4, calmer HVT bolt, low J-hook heli, shared UI theme, debrief/salvage UI, new loadout menu, downed loot/ragdoll/blood, item info, no numbered callsigns, foot exfil from the edge, heli route |
| v0.4.1 | b231543 | Harbour ship placement, salt flats look, infil music, squad spacing, player-launched fix, UI auto-scale, base hub, campaign screens, small screens, medical interaction UI, inventory, HUD pass, seated passengers |
| v0.4.2 | 72af08f | Heli cruise height, small playtest fixes (Oct 14), experimental forest test zone (denser copses on its own preset) |
| dev now | integrate/v0.4.0 tip | + town physics perf (`scripts/ai/buildings.gd`), docs: high command, AI bar gaps |

## New test suites

`ui` (screens fit at every size), `loadout`, `spacing` (squad spacing), `levelswitch`,
`heliflight`, `townperf` (town physics cost). All in `tools/run_tests.sh` and CI.

## UI rules

- One shared look: `themes/contractor_ui.tres` + `scripts/ui/ui_kit.gd` (UiKit). New or reworked
  screens use the kit, not hand-set colours and pixel sizes.
- `docs/ui_audit.md` has the audit, how scaling works, and the rules each screen follows.

## Tools

- The Captain's agents share a Godot slot queue (`agent-tools/godot_slot.sh`). It lives only on
  the Captain's machine, not in the repo; nothing to do on your side.

## Open work (branches not in dev)

- `fix/self-tourniquet`: in progress. Wounded AI put on their own tourniquet; casualty flake
  ("under fire, he puts his own tourniquet on at once") still shows up sometimes.
- `art/denser-copses`: all of it is on dev (its one commit, ea4d575e, is in dev's history; the
  wooded normal presets got the dense copses with the woods perf pass, bbef7e05, 2026-10-22).
  Nothing left on the branch (checked 2026-10-31, perf/woods-copses).
- `feat/squad-comms`: WIP, paused. Bots talk like players.
- `test/coop-fakehuman-checks`, `test/coop-soak`: co-op soak harness.
- `docs/high-command`, `docs/ai-bar-gaps`: proposals awaiting the Captain (also on dev as
  `docs/high_command.md`, `docs/ai_bar_gaps.md`).

## Next (Captain, 2026-10-14)

1. Woods/render perf pass: frame goes 4 -> 10 ms in woods, up to 1.5k draws, 1.4M prims. Then
   denser copses. **Measured, still open** (2026-10-22, bbef7e05: tiers, far blobs, no shadows
   from bushes, the dense copses on every wooded preset; 2026-10-31, perf/woods-copses: measured
   again, woods and open ground cases with vegetation draw budgets in perfcases;
   docs/performance.md, "Woods, 2026-10-31"). Windowed (S0771: partial numbers, a run stopped
   early, not a finished measurement), inside the densest wood the
   renderer makes about 60% more draws than on open ground (1036 against 646) and the frame is
   1.3 ms longer (10.1 against 8.9 ms; the GPU 0.7 ms in both); where those draws come from is
   F-366. The denser copses are already in.
2. AI awareness leaks through compound walls; one zone-wide hostile squad (ai_bar_gaps
   G-02/G-03). Tied to the infil problems.
3. Breaching charges make holes too small; add a "Breach and clear" team order through walls.
4. Buy missing kit from inside the loadout editor.
5. Full medic kit in the FOB starting stash? (open question)
6. In-game tutorial.
7. Bots joining a human-hosted game.
8. GitHub release workflow on tag.
