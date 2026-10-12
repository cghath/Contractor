# Debugging: how we run, log and look at things

Captain's rules (2026-10-12), for both sides (Captain's and cghath's) and every agent. Some of
this is built and on `feat/wave4b-hotzone` (soon `dev`); the rest is planned and listed at the
end so nobody builds it twice.

## The rule: every run keeps its logs, numbered, and nothing deletes them

Anything that runs the game or produces output (test suites, screenshot scripts, helper
scripts, test builds, playtest sessions) keeps its logs in **one parent folder outside the
repo**, by date, with a unique run number and PASS or FAIL in the folder's name:

```
<parent>/                                   e.g. B:\Contractor-test-logs (beside the main checkout)
  run_counter.txt                           the last number given out (shared by every kind of run)
  index.txt                                 one line per run: id, date, time, PASS/FAIL, branch-sha, what ran
  2026-10-12/
    R0001-025832-FAIL-feat-wave4b-hotzone-0e80746/    a test run: every suite's log + summary.txt
    S0004-032507-PASS-hotzone-shots-0e80746/          a screenshot run: the PNGs + script.log
    B0009-export.log                                  a build's export log
```

- **Letters:** R = test run (`tools/run_tests.sh`), S = screenshot or helper script, B = build,
  P = playtest session or bug report (planned). The number is one counter for all of them, so
  "R0012" or "S0004" names exactly one run on that machine.
- **Folder names:** `<letter><number>-<HHMMSS>-<PASS|FAIL>-<branch or topic>-<sha>`. A folder
  still named RUNNING was killed or hung.
- **Never delete the parent folder or anything in it.** Cleanups only ever remove temp copies.
- **Cite run numbers** in commit messages, handoffs, PR notes and Discord posts ("all suites
  pass: R0010"; "animations' pistol-draw fails on dev too: R0002").

### Tests: `tools/run_tests.sh` already does it

```bash
GODOT="<path to the Voxel Tools editor>" CONTRACTOR_PORT=24790 tools/run_tests.sh            # every suite
GODOT="..." CONTRACTOR_PORT=24790 tools/run_tests.sh missions world                          # some suites
```

- Logs land in `Contractor-test-logs` beside the **main checkout** (found through
  `git rev-parse --git-common-dir`, so every worktree shares one parent and one counter). Set
  `CONTRACTOR_TEST_LOGS=<folder>` to put them elsewhere, or `=none` to keep nothing.
- On CI (`GITHUB_ACTIONS`) nothing is kept unless `CONTRACTOR_TEST_LOGS` is set.
- `summary.txt` in each run lists every suite's verdict and every `[FAIL]` line; the run's
  folder is renamed PASS or FAIL when it ends; `index.txt` gets a line.
- Always run suites through `tools/run_tests.sh`, not bare `godot`: a bare run's output is
  gone when the terminal is. `tools/test_runner_check.sh` checks the runner keeps logs.
- Use your own `CONTRACTOR_PORT` (the game and other runs use 24680; two on one port looks
  like a hang) and one run at a time per machine.

### Which suites to run, and when CI does the rest (Captain, 2026-10-12)

A full local run takes 15-22 minutes and CI runs every suite on every push anyway (one job per
suite, in parallel), so:

1. **While working:** run the suites your change touches, plus `smoke`. A change to shared code
   (`soldier.gd`, `squad_ai.gd`, an autoload, `character_model.gd`) reaches further than it
   looks (the squad AI change of 2026-10-12 broke roles and casualty): add those suites.
2. **Push your work branch** to GitHub (no need to ask) and let CI run everything on it.
3. **Move `dev` forward only when the branch's CI is green**, on Captain's go: a fast-forward,
   or a merge you've tested. `dev` never goes red.
4. **A green CI run on the branch is "the full suite"** wherever a rule asks for one (cite the
   commit). Still run the full suite locally before merging the other side's work into yours
   and before exporting a test build.

Reading CI without `gh`: `curl -s "https://api.github.com/repos/cghath/Contractor/actions/runs?branch=<branch>&per_page=1"`
(status, conclusion); a failing job's last lines are its check run's `/annotations`. The
unauthenticated API allows 60 calls an hour: poll every few minutes, not in a tight loop.

### Scripts and builds: do the same by hand until they're wired in

Take the next number from `run_counter.txt`, make
`<parent>/<date>/<letter><number>-<time>-RUNNING-<topic>-<sha>/`, run with output into it,
rename RUNNING to PASS or FAIL, add a line to `index.txt`. A `-s` SceneTree script should
also quit itself after a deadline (a script error leaves it idling, not quitting).
Test build folders: `builds/contractor-<date>-<time>-B<number>-<topic>-<sha>/`.

## Dev tools in the game: `DevTools.on()`

Our exports use a release template, so `OS.is_debug_build()` is never true in a test build.
Anything for testing goes behind **`DevTools.on()`** (`scripts/ui/dev_tools.gd`) instead: true in
the editor and debug builds, and in any build started with **`--dev`**. Test builds ship a
`Contractor (dev tools).bat` that starts the game with `--dev`; a normal start has none of it.

Today's dev keys:

| Key | What |
|---|---|
| K | hurt yourself (going down, dying) |
| Shift+End | during a deployment, extract everyone near you at once |
| End | open the contract board (any build) |
| Page Up | hot zones: show/hide the enemy readout (alert per area, last known position, reports, pressure and tier, patrols, QRF, hunters, coordination, enemy radio) |
| Page Down | hot zones: skip the enemy's clock 5 minutes |

New dev keys: put them behind `DevTools.on()`, list them here, and keep them off F1-F12 (the
squad command menu) and the game's keys (`autoload/controls.gd`).

## Session logs: automatic in every playtest (`SessionLog`, built)

Every run that isn't headless (a playtest: the editor or any build, dev tools or not) opens a
numbered session, **P<number>**, from the same counter and in the same parent as the test runs:

```
<parent>/2026-10-12/P0047-071530-RUNNING-B0046-dev-983b844/
  session.log                every engine and script error and warning (with its script
                             backtrace), everything the game prints, slow frames (0.5 s+),
                             host/join/peers/disconnects, zone changes, every message the
                             player was shown ("Too far away", "Took ..."), and the verdict
  dump-01-error.txt          a state dump the first time each kind of issue happens: why,
  dump-01-error.png          every soldier (where, condition, the AI's intent, status, target,
                             combat mode, carrying, hands), the hot zone's readout, the last
                             200 log lines; and a screenshot (at most 20 per session)
```

- **Anything unexpected** counts: an engine or script error, a warning, or an anomaly the game
  notices (today: a soldier whose position isn't a number, or who fell out of the world). Call
  `SessionLog.anomaly(key, text)` for new ones; `SessionLog.note(text)` adds a plain line.
- On quit the folder becomes **PASS** (nothing unexpected) or **FAIL**, with a line in
  `index.txt`. A folder still **RUNNING** means the game crashed or was killed.
- The pause menu shows the session number: send it with a playtest report ("P0047").
- **Where:** `CONTRACTOR_TEST_LOGS` if set; else the first `Contractor-test-logs` going up from
  the game (builds under `B:\Contractor\builds` find `B:\Contractor-test-logs`); else
  `user://session-logs` (a friend's machine).
- **Off** when headless (the suites) or running a `-s` script. `CONTRACTOR_SESSION_LOG=0` turns
  it off, `=1` on. Suite: `session_log`.

## Planned (Captain's side, first after 4B part 3: don't build these twice)

1. **Bug-report key:** in a playtest, one key saves a numbered folder (P....) with a screenshot,
   a note typed there, a state dump (every soldier's position; each AI's intent, target, combat
   mode and why; alert and pressure; the player's inventory and wounds; zone id and seed) and
   the last minutes of the log.
2. ~~**Session logs**~~: built, see "Session logs" above. The bug-report key should reuse
   `SessionLog.state_text()` for its dump and save into the session's folder.
3. **AI debug overlay (dev tools):** over each AI its intent, target, combat mode and alert state,
   and a line to where it's going.
4. Later: **replay** a bug report (it saves a `Campaign.snapshot`; a headless test loads it,
   reproduces the bug and stays as a regression test), a **test history page** (pass/fail per
   suite over time from `index.txt`, flaky suites flagged), **performance lines** in session
   logs (frame time, AI count, navigation bake time, modules streamed in, once a minute).

When wave 5 adds systems (vehicles, supports, the FOB), please give them lines in the state
dump and the overlay when those land (a vehicle's driver, passengers, damage; a support call's
state), and put any test-only controls behind `DevTools.on()`.
