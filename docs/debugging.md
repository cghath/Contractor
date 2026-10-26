# Debugging: how we run, log and look at things

Captain's rules (2026-10-12), for both sides (Captain's and cghath's) and every agent. Some of
this is built and on `feat/wave4b-hotzone` (soon `dev`); the rest is planned and listed at the
end so nobody builds it twice.

## The rule: every run keeps its logs, numbered, and nothing deletes them

Anything that runs the game or produces output (test suites, screenshot scripts, helper
scripts, test builds, playtest sessions) keeps its logs in **one parent folder outside the
repo**, by date, with a unique run number and PASS, FLAKY or FAIL in the folder's name:

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
  "R0012" or "S0004" names exactly one run on that machine. The counter is read and written
  under a lock, the folder `run_counter.lock` beside it (`run_log_number` in `tools/run_log.sh`,
  `SessionLog._next_number`): two runs started in the same second both got R0232 before it. A
  lock older than 10 s was left by a killed run and is taken over.
- **Folder names:** `<letter><number>-<HHMMSS>-<PASS|FLAKY|FAIL>-<branch or topic>-<sha>`. A folder
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
  folder is renamed PASS, FLAKY or FAIL when it ends; `index.txt` gets a line.
- **Three verdicts** (Captain, 2026-10-26): **green PASS**, every suite clean first time; **orange
  FLAKY**, a suite failed once and passed when the runner ran it again (a timing miss, not a red:
  the run exits 0 and goes on; the first try's logs stay as `<suite>.first-fail.log` for
  scrutiny; `summary.txt` and the `index.txt` line name the flaky suites); **red FAIL**, a suite
  failed twice, the import failed, or the run stopped. `RERUN_FLAKY=0` turns the rerun off (a
  first failure is then red). On a terminal the verdict prints in its colour.
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

**A suite that printed "PASSED (0 failures)" and then exited non-zero** (seen on CI's Linux runners for AI-heavy suites, with "instances leaked at exit") counts as passed, with a note in the summary: every check had passed, only the engine's shutdown failed. Finding why needs the full CI job log (repo admin).

Reading CI without `gh`: `curl -s "https://api.github.com/repos/cghath/Contractor/actions/runs?branch=<branch>&per_page=1"`
(status, conclusion); a failing job's last lines are its check run's `/annotations`. The
unauthenticated API allows 60 calls an hour: poll every few minutes, not in a tight loop.

### Scripts and builds: do the same by hand until they're wired in

Take the next number from `run_counter.txt` (by hand: `. tools/run_log.sh; run_log_number <parent>`,
which takes the lock), make
`<parent>/<date>/<letter><number>-<time>-RUNNING-<topic>-<sha>/`, run with output into it,
rename RUNNING to PASS, FLAKY or FAIL, add a line to `index.txt`. A `-s` SceneTree script should
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
| Insert | bug report (any build): note panel, saves report-<n>.txt and .png in the session folder |
| Delete | host: labels over AI within 80 m (intent, status, target, mode, suppression) and a line to where each is heading |
| Shift+End | during a deployment, extract everyone near you at once |
| End | open the contract board (any build) |
| Page Up | hot zones: show/hide the enemy readout (alert per area, last known position, reports, pressure and tier, patrols, QRF, hunters, coordination, enemy radio) |
| Page Down | hot zones: skip the enemy's clock 5 minutes |
| ] (right bracket) | call an AAV to you anywhere, free (wave 5b, `AavSupport`) |

New dev keys: put them behind `DevTools.on()`, list them here, and keep them off F1-F12 (the
squad command menu) and the game's keys (`autoload/controls.gd`).

**Smoke test of these tools** (in a window, not a CI suite):
`CONTRACTOR_SESSION_LOG=1 CONTRACTOR_PORT=<port> <godot> --path . res://tests/debug_tools_smoke.tscn`
opens a session, presses Insert (bug report, note, screenshot) and Delete (AI overlay) as a
player would, raises an anomaly (state dump) and ends the session (folder renamed, index line).
Run it after touching any of them.

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
- **Host-side event lines** (host only): `X went down (friendly): round (intermediate), chest, by
  Rahimi [Hostile3] (hostile) at 42 m` (also `died`; cause is a round class, fragment, blast,
  fall, burn, armor-stopped round, or bleed-out / cardiac arrest / "out: <causes>" when nothing
  hit them in the last 3 s, then "last hit by ..."; players, squad AI and enemies; a body
  spawned as one, a player's left behind or one restored from the zone save, isn't logged
  dying again); treatments, each with how far the casualty's body is (`Soldier.body_point`,
  as treatment reach measures it): `X treats Y: tourniquet on left thigh at 1.2 m, started
  (4.0 s)`, then `..., done`, or `interrupted: <why>` (`you moved 1.6 m`, `you went down`,
  `out of reach`, `they were moved: dragged by Rahimi [Bravo] (0.4 m)` / `carried by ...` /
  `put down by ...` / `nobody carried them (1.5 m, Wounded)`), or `refused: Too far away`
  (taking a tourniquet off is `tourniquet removal`); `Return to Base` and `Return to Base
  (revert)` from the Escape menu / debrief.
- **Names in the log** (`SessionLog.who`, `Soldier.log_name`): a player is `Player 1`; an AI is
  its name with its callsign, `Rahimi [Hostile3]`, so two hostiles who share a surname read
  apart; a body spawned as one gets a tag from its uid instead, the same across saves,
  `Player 1 [body 3fa2]`; a target dummy is `target dummy LightDummy`. The dumps' soldier
  lines use the same names.
- On quit the folder becomes **PASS** (nothing unexpected) or **FAIL**, with a line in
  `index.txt`. A folder still **RUNNING** means the game crashed or was killed.
- The pause menu shows the session number: send it with a playtest report ("P0047").
- **Where:** `CONTRACTOR_TEST_LOGS` if set; else the first `Contractor-test-logs` going up from
  the game (builds under `B:\Contractor\builds` find `B:\Contractor-test-logs`); else
  `user://session-logs` (a friend's machine).
- **Off** when headless (the suites) or running a `-s` script. `CONTRACTOR_SESSION_LOG=0` turns
  it off, `=1` on. Suite: `session_log`.

## Planned (Captain's side, first after 4B part 3: don't build these twice)

1. ~~**Bug-report key**~~: built (Insert; `BugReport`, saves report-<n>.txt/.png in the session folder; the log tail is in the state text). Original spec: in a playtest, one key saves a numbered folder (P....) with a screenshot,
   a note typed there, a state dump (every soldier's position; each AI's intent, target, combat
   mode and why; alert and pressure; the player's inventory and wounds; zone id and seed) and
   the last minutes of the log.
2. ~~**Session logs**~~: built, see "Session logs" above. The bug-report key should reuse
   `SessionLog.state_text()` for its dump and save into the session's folder.
3. ~~**AI debug overlay**~~: built (Delete, `AiOverlay`; intent, status, target, mode, suppression, line to its destination; no alert state yet). Original spec: over each AI its intent, target, combat mode and alert state,
   and a line to where it's going.
4. Built: **performance lines** in session logs (`SessionLog.perf_line`, every `PERF_S` = 60 s:
   frame time average and worst, fps, AI and players up, modules streamed in, nav rebakes,
   memory: the engine's own count, which is debug-only (a release build read 0 MB, P0362), else
   the process's resident memory where /proc gives it; video memory, the system's memory in use
   and the object and node counts, all release-safe and read with no child process; then what the
   worst frame went on: the systems `FrameCost` counts, costliest first (`ai`, `nav`, `sfx`,
   `voxels`; add a `FrameCost.spent` call to count another), and the engine's physics and process
   time, draw calls and primitives in that frame; a slow-frame line says the same; time no system
   counts is the uncounted rest; `tests/perf_timing.tscn` times the known hitches headless) and a **test history page** (`python tools/test_history.py` writes
   `<logs>/history.html`: pass/fail per suite over the last 40 runs, flaky suites flagged, the
   checks that fail most). The AI overlay also shows what each AI half-spotted and a hostile's
   alert state. Still later: **replay** a bug report (it saves a `Campaign.snapshot`; a headless test loads it,
   reproduces the bug and stays as a regression test).

When wave 5 adds systems (vehicles, supports, the FOB), please give them lines in the state
dump and the overlay when those land (a vehicle's driver, passengers, damage; a support call's
state), and put any test-only controls behind `DevTools.on()`.
