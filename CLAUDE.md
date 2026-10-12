# Contractor: notes for agents

- **Debugging and logs (Captain's rule, 2026-10-12): read [docs/debugging.md](docs/debugging.md).**
  Every run keeps its logs, numbered (R/S/B/P + number), by date, PASS or FAIL in the folder
  name, under one parent outside the repo, and nothing deletes them. Run suites only through
  `tools/run_tests.sh` with your own `CONTRACTOR_PORT`, cite run numbers when you report
  results, and put test-only controls behind `DevTools.on()`.
- **Reach to bodies and where a body lies (Captain's rule, 2026-10-12): understand it before
  you touch it.** Read the code as it is on dev and these commits' messages: `7fe9e3e` (the
  reach fix; its diff also holds half-done revive edits swept in by mistake, which `8a165b7`
  took back out, so don't copy code from that diff), `8a165b7`, and `e17f739` (stand where the
  ragdoll lay). A downed or dead body's ragdoll can rest metres from its capsule,
  which stays where it fell, so reach to a body is measured to `Soldier.body_point()` (the
  ragdoll's chest while it lies as one), never to its `global_position`: loot, carry/drag and
  treatment reach in `soldier.gd`, and AI medics, bearers and scavengers walking to a body in
  `squad_ai.gd`. Measuring to the capsule again brings back "Too far away" at the body (the
  CI looting flake). In `tests/animations_test.gd` "Looting", the ragdoll moved `SLID` off on
  purpose and the right-handed pin in `_ready` (a player's left-handed `settings.cfg` broke
  the pistol draw) stay. Never rewrite these commits (no rebase, amend or force-push over them).
  If this code needs work: say what and why in the commit, keep the "Looting" checks passing,
  and run the full suite (cite the run number). The same goes for its follow-up: when the
  ragdoll goes (revived, lifted), the body stands where it lay (`Ragdoll.rest_spot`,
  `Soldier._stand_where_ragdoll_lay`), and a ragdoll carries its parts along with any
  placement, even before its first physics step (`_root_last` set in `Ragdoll.start`); keep the
  animations checks "Standing up where the ragdoll lay" and "takes its ragdoll along".
- Plans and who owns what: [docs/build_plan.md](docs/build_plan.md) and
  [docs/ChrisPlan_handoff.md](docs/ChrisPlan_handoff.md) (cghath's agent: the note at the top
  of "Wave 5").
