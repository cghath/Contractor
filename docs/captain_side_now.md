# Captain's side: start here (2026-10-14 night)

For cghath and cghath's agent. dev now holds everything below. Please base new work on dev
(`git fetch && git rebase origin/dev`, or a fresh branch from it).

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
- `art/denser-copses`: held for the woods perf pass. The forest test zone already uses its code.
- `feat/squad-comms`: WIP, paused. Bots talk like players.
- `test/coop-fakehuman-checks`, `test/coop-soak`: co-op soak harness.
- `docs/high-command`, `docs/ai-bar-gaps`: proposals awaiting the Captain (also on dev as
  `docs/high_command.md`, `docs/ai_bar_gaps.md`).

## Next (Captain, 2026-10-14)

1. Woods/render perf pass: frame goes 4 -> 10 ms in woods, up to 1.5k draws, 1.4M prims. Then
   denser copses.
2. AI awareness leaks through compound walls; one zone-wide hostile squad (ai_bar_gaps
   G-02/G-03). Tied to the infil problems.
3. Breaching charges make holes too small; add a "Breach and clear" team order through walls.
4. Buy missing kit from inside the loadout editor.
5. Full medic kit in the FOB starting stash? (open question)
6. In-game tutorial.
7. Bots joining a human-hosted game.
8. GitHub release workflow on tag.
