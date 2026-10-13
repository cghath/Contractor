# Audit part 1 — foundations, multiplayer and persistence

October 13, 2026. Baseline: `dev`, `fcae676b8318b7534fdc3f2e4d17a9e9a228275f`.

Part 1 found two high-priority save-loss problems, three other robustness problems, and two defects in test setup. The main recommendation is to fix save recovery before adding more persistent campaign features. Existing tests passing on normal saves does not cover the failure cases reproduced here.

## Scope and method

Reviewed the autoloads and scene startup, owner/host replication split, join authentication and level switching, disconnect handling, campaign/base/economy request paths, zone save restoration, and the RPC entry points for soldiers, people, map planning, weapons, vehicles and supports. Traced the callers and consumers relevant to each finding. This is not a claim that every gameplay routine in those files has been audited; that work belongs to parts 2 and 3.

The checkout has 143 gameplay/autoload GDScript files. A scan of 215 script and scene files found no missing literal `res://` references matching the resource extensions checked. The Voxel Tools editor imported the project successfully. Dynamic resource paths and export contents remain for part 3.

Ran the existing smoke, network, base, contracts and session-log suites. Added isolated audit probes for save failure cases and a malformed contract request. Used the repository's test runner, an isolated save tag and port 24931. Diagnostic controls inherit the existing tests and change only their setup, leaving gameplay source untouched.

Priority: P1 = high, because progress can be lost; P2 = medium, because a real error path or test defect needs fixing. Runtime reproductions and source-only findings are explicitly distinguished.

## Findings

### A1-01 — P1: an unreadable campaign is treated as permission to reset it

Location: [base_hub.gd:183](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:183>), with destructive reset at lines 157–160 and campaign-zone deletion at line 229.

`load_or_new()` calls `new_campaign()` whenever loading returns false. That includes a damaged primary and damaged backup, not just a campaign that has never existed. `new_campaign()` calls `Campaign.reset_campaign()` and deletes the campaign's zone primaries. The normal path also creates and saves a fresh economy/contracts state.

Reproduction: create deliberately unreadable primary and backup files under a unique test campaign name, plus a valid zone file for that campaign, then call `BaseHub.load_or_new()`. The audit probe confirmed a new campaign was started and both the campaign and zone primary files disappeared. Autosaving was disabled in the probe to avoid unrelated writes; the ordinary game's autosave would subsequently write fresh state.

Recommendation: return separate results for absent, successfully loaded, and unreadable/incompatible saves. On an unreadable save, preserve all files and offer an explicit recovery/reset choice. Starting a fresh campaign must not be the fallback for a load error.

Evidence: R0002, `audit_part1.log`. Runtime reproduced.

### A1-02 — P1: valid backups are ignored when the primary is missing

Locations: [campaign.gd:63](<C:/Users/My Little Pony/Documents/Contractor/autoload/campaign.gd:63>), [game_state.gd:75](<C:/Users/My Little Pony/Documents/Contractor/autoload/game_state.gd:75>), [contracts.gd:248](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/contracts.gd:248>).

Campaign loading returns immediately if the primary does not exist. Zone loading only tries the backup when the primary exists. The contract first-access path also gates loading on primary-file existence. Meanwhile, `write_safely()` renames the existing primary to `.bak` before renaming `.tmp` to the primary. A crash or failed second rename can therefore leave exactly the backup-only state these loaders fail to recover.

Reproduction: create a valid `.bak`, leave the primary absent, and load. The probe confirmed both campaign and zone progress were ignored. For a campaign, the next base load can enter the destructive fresh-start path in A1-01.

Recommendation: check the backup whenever the primary is absent or invalid, including the contract first-access path. Check every rename/remove result during rotation. Preserve the last known valid copy until the new primary is installed, and define how a completed temporary file is recovered after interruption.

Evidence: R0002, `audit_part1.log`. Runtime reproduced.

### A1-03 — P2: save validation stops before the data actually used by the game

Locations: [campaign.gd:90](<C:/Users/My Little Pony/Documents/Contractor/autoload/campaign.gd:90>), [game_state.gd:130](<C:/Users/My Little Pony/Documents/Contractor/autoload/game_state.gd:130>), [voxel_world.gd:506](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/voxel_world.gd:506>).

The campaign reader checks only the top-level dictionary and the outer `sections` dictionary. It ignores `SAVE_VERSION` and accepts nested sections with incompatible types. Even `{}` passes its check because a missing `sections` defaults to `{}`. This can bypass backup recovery, reset progress, or reach code expecting dictionaries and arrays of specific shapes.

The zone reader is stronger, but passes the voxel edit array through unchanged. For example, an edit `{"op":"carve","c":[],"r":1}` is accepted and later indexed as a three-number coordinate. Body records are accepted based on UID and position even when their gear has the wrong type; dropped-item state is similarly not shape-checked before typed restoration calls.

Reproduction: the probe confirmed a version-999 campaign loads and an economy array passes the campaign reader. The malformed zone examples were verified by tracing validation into replay/restoration; they were not executed against a live level.

Recommendation: validate versions and nested section shapes before publishing any loaded state. Validate edit operations, finite coordinates/radii and item/body/vehicle state. Reject an incompatible campaign and try its backup; skip isolated bad zone records with a clear diagnostic. Add regression cases for both.

Evidence: R0002 for campaign cases; source review for nested zone cases.

### A1-04 — P2: save failures still produce a “Campaign saved” message

Locations: [campaign.gd:57](<C:/Users/My Little Pony/Documents/Contractor/autoload/campaign.gd:57>), [base_hub.gd:210](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:210>), [base_hub.gd:1283](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:1283>), [base_hub.gd:1367](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/base_hub.gd:1367>).

`GameState.write_safely()` returns success/failure, but `Campaign.save_campaign()` discards that result. `BaseHub.server_save()` returns no result, and both the request handler and quick-save handler report success unconditionally. A full disk, permissions error or failed replacement therefore leaves the player believing their progress is safe.

Recommendation: return the write result through the save API and show success only after a successful write. Surface the failure to the player. Quit/menu paths should make the failure reviewable before progress is discarded.

Evidence: source review. The first restricted run produced actual denied save writes, confirming the lower-level failure path; its suite failures are excluded from gameplay conclusions.

### A1-05 — P2: a malformed contract request produces a host script error

Location: [contracts.gd:869](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/contracts.gd:869>), especially `_handle()` at line 875.

The remote request accepts an arbitrary `args` array, then recognized actions index it without checking argument count or types. `accept` reads elements 0 and 1; `sell` does the same; several others read element 0. A connected client sending `accept` with an empty array reaches an out-of-bounds access instead of a controlled rejection.

Recommendation: define required argument counts/types per action and reject malformed input before indexing or calling typed functions. Validate nested negotiation values as well. Use the same validation for local and remote callers.

Evidence: the dedicated `audit_rpc` probe invokes the handler with the same empty argument payload; its expected script error is retained in R0003. This demonstrates a handler error, not a proven whole-process crash or an unauthenticated exploit.

### A1-06 — P2: the network client deletes the host's save fixture

Locations: [net_test.gd:40](<C:/Users/My Little Pony/Documents/Contractor/tests/net_test.gd:40>), [compound_level.gd:426](<C:/Users/My Little Pony/Documents/Contractor/scripts/world/compound_level.gd:426>), [run_tests.sh:158](<C:/Users/My Little Pony/Documents/Contractor/tools/run_tests.sh:158>).

Both test processes use the same zone name and user-data directory and both call `GameState.delete_save()` on startup. The host writes its saved-body/edit fixture before starting the main scene. Hosting warms body-volume data before loading the fixture. The runner starts the client after a fixed four-second delay, so the client can delete the fixture while the host is still initializing.

Observed: the unrestricted baseline failed four saved-body/wall-edit assertions without a host write error. The control inherited the same network checks and moved deletion into the host-only branch. All network checks then passed.

Recommendation: let only the host manage the fixture, and replace the fixed launch delay with a readiness handshake. Do not classify these four failures as proof of broken replication.

Evidence: R0002 baseline versus R0003 network control. Runtime isolated.

### A1-07 — P2: the contracts replication test assumes an empty area stays active

Locations: [contracts_test.gd:668](<C:/Users/My Little Pony/Documents/Contractor/tests/contracts_test.gd:668>), [contracts_test.gd:730](<C:/Users/My Little Pony/Documents/Contractor/tests/contracts_test.gd:730>), [objectives.gd:403](<C:/Users/My Little Pony/Documents/Contractor/scripts/campaign/objectives.gd:403>).

The network phase starts a clear-compound objective in a test level with AI disabled, then launches a client and expects every objective to remain `active`. The objective system legitimately completes an empty area after its arming timeout, defaulting to 20 seconds. The baseline log shows the host completing the clear objective before the client's initial state assertion, while later objective replication assertions pass.

Recommendation: stage a persistent hostile or deliberately suspend automatic objective polling for this replication-only phase. Assert the host's expected state at the handshake; avoid assumptions about how long startup will take. Keep objective-completion behavior covered separately.

Evidence: R0002 baseline; R0003 diagnostic control suspends only the host's automatic polling during this phase, and all contracts checks then passed. This is a test-lifecycle defect, not evidence that the game should keep an empty area uncleared. Part 3 later confirmed a separate integration defect: an unvisited zone target is also counted as empty before its garrison spawns (A3-01 in part-3.md).

## Validation record

Logs are retained outside the checkout at:

`C:/Users/My Little Pony/.codex/visualizations/2026/10/13/01a1342e-614c-7411-8ee7-4e0451f2a59c/Contractor-audit-logs`

| Run | Purpose | Result |
| --- | --- | --- |
| R0001 | Smoke plus initial foundation suites | Smoke passed. Other suites were affected by sandbox denial of Godot's user-data writes. Available logs manually retained; this is not a trustworthy baseline for those suites. |
| R0002 | Rerun with user-data access: net, base, contracts, session_log, save probes | Base and session_log passed. Net failed four fixture assertions; contracts failed one active-objective assertion. All five save-failure observations were reproduced. |
| R0003 | Controls for the two failing test setups; malformed-request probe | Network and contracts controls both passed with zero failed assertions. The malformed request produced an out-of-bounds script error at contracts.gd:879; the runner correctly marked the run FAIL. |

No production fixes were applied. These are headless checks: rendering, player feel, sustained performance, internet latency, all four player slots and cross-machine profile/security behavior have not been validated here. CI was not queried and the full test suite was not run in part 1.

## What held up in the reviewed paths

- The player drives movement while `ServerSync` remains host-owned for wounds, inventory, gear and roster metadata.
- Soldier requests use the owning sender check; reviewed weapon/vehicle requests also enforce state, reach or numeric validation where appropriate.
- The join handshake loads the host's level before normal replication, and level retirement disconnects old session callbacks.
- The base suite passed campaign gear, stash, deployment, recovery and return transitions. The network control passed firing, reload, treatment, armor, late smoke/drag, saved bodies and voxel edits.
- Save replacement already uses a checked temporary file and keeps a previous copy. The remaining recovery and reporting gaps are concrete extensions of that mechanism.

Fix order: A1-01 and A1-02 first; then A1-03 and A1-04; then request validation and the two test setups. Parts 2 and 3 are now complete; see SUMMARY.md for combined priorities.
