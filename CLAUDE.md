# Contractor: notes for agents

- **Debugging and logs (Captain's rule, 2026-10-12): read [docs/debugging.md](docs/debugging.md).**
  Every run keeps its logs, numbered (R/S/B/P + number), by date, PASS or FAIL in the folder
  name, under one parent outside the repo, and nothing deletes them. Run suites only through
  `tools/run_tests.sh` with your own `CONTRACTOR_PORT`, cite run numbers when you report
  results, and put test-only controls behind `DevTools.on()`.
- Plans and who owns what: [docs/build_plan.md](docs/build_plan.md) and
  [docs/ChrisPlan_handoff.md](docs/ChrisPlan_handoff.md) (cghath's agent: the note at the top
  of "Wave 5").
