#!/usr/bin/env bash
# Runs the headless test suites. Set GODOT to the Voxel Tools editor executable, e.g.
#   GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/run_tests.sh
# With arguments, runs only those suites:  tools/run_tests.sh smoke gameplay
# Suites are tests/<name>_test.tscn; "net", "levelswitch", "world", "vehicles", "supports", "aav", "props", "operations" and "optypes" are two-process host/client tests.
# Parallel runs (separate worktrees) should set CONTRACTOR_TEST_TAG (keeps test saves apart)
# and CONTRACTOR_PORT (keeps the net test's port apart).
#
# A suite passes only if its process exits 0, prints "<NAME> TEST PASSED", prints no
# "TEST FAILED", and logs no SCRIPT ERROR (a script that fails to compile or crashes mid-test
# can still exit 0, or never exit at all). Each process gets SUITE_TIMEOUT seconds (default
# 480); one that runs past it is killed and fails as hung. The import must succeed too: exit 0
# and no SCRIPT ERROR or parse error in its log (an import can report a broken script and still
# exit 0). Exits non-zero if any suite fails. tools/test_runner_check.sh checks these rules.
#
# Every run's logs are kept (Captain, 2026-10-12) in their own folder outside the repo, which
# nothing here ever deletes, all under one parent: CONTRACTOR_TEST_LOGS (default:
# Contractor-test-logs beside the main checkout, shared by every worktree, e.g.
# B:\Contractor-test-logs). Each run gets a number (run_counter.txt there, counting up forever,
# unique across worktrees) and a folder by date:
#   <parent>/<date>/R<number>-<time>-<PASS|FAIL>-<branch>-<sha>/
# (RUNNING while it runs; a folder left RUNNING was killed outright). Inside: every suite's log,
# written there as it runs (so a run stopped part-way still has them), and summary.txt (run id,
# CI run and commit on CI, suites, each verdict and [FAIL] line). A run stopped before it
# finishes (killed, or CI's job cancelled or out of time) is a FAIL. index.txt at the top lists
# every run, one line each. On CI (GITHUB_ACTIONS) nothing is kept unless CONTRACTOR_TEST_LOGS
# is set (.github/workflows/tests.yml sets it and uploads the folder); CONTRACTOR_TEST_LOGS=none
# keeps nothing. tools/run_log.sh finds the parent, the number and the branch-sha.
set -u
cd "$(dirname "$0")/.."
. tools/run_log.sh
GODOT="${GODOT:-godot}"
SUITE_TIMEOUT="${SUITE_TIMEOUT:-480}"
# Suites that need longer than SUITE_TIMEOUT. supports: its host runs ~160 checks of its own
# (about 460 s) before it lets the late-joining client in, and the client's resupply then
# flies in, drops its pallet and leaves (about 2 min more), all inside each process's one
# timeout, so 480 s killed both mid-flight and it read as a hang (R1500, R1503).
suite_timeout() {
	case "$1" in
		supports) echo $(( SUITE_TIMEOUT > 780 ? SUITE_TIMEOUT : 780 )) ;;
		# vehicles: its host runs ~30 sections, and squad driving (convoys, carries, unstuck, 2026-10-20)
		# took it past 480 s: killed in "Squad drivers part 2" with two sections to go (R2353, CI too).
		vehicles) echo $(( SUITE_TIMEOUT > 780 ? SUITE_TIMEOUT : 780 )) ;;
		# vehiclefx: its host runs ~10 sections (fires, kills with physics settling, smoke clouds
		# growing and clearing), then a client process joins and checks the wreck and the next kill.
		vehiclefx) echo $(( SUITE_TIMEOUT > 780 ? SUITE_TIMEOUT : 780 )) ;;
		# armourlog: its host runs ~14 sections (rearming, repairs, the motor pool, a tow driven), then
		# a client process joins and checks the packages, tiles, racks and the tow (A8).
		armourlog) echo $(( SUITE_TIMEOUT > 780 ? SUITE_TIMEOUT : 780 )) ;;
		# armourdrive: a river valley zone hosted, ~14 sections on its slab and in its river and on its
		# bridges (A6), then a client process joins and checks the rolled, flooded and stalled vehicles.
		armourdrive) echo $(( SUITE_TIMEOUT > 1080 ? SUITE_TIMEOUT : 1080 )) ;;
		# perfcases: five zones hosted and their visuals built, 20-45 s measured in each (perf pass).
		perfcases) echo $(( SUITE_TIMEOUT > 1200 ? SUITE_TIMEOUT : 1200 )) ;;
		# invasion: an 8 km operation zone hosted with its visuals, three cases measured in it (the 6.2.3
		# load, a drive and a flight across it), then ridge_hot with the same load (cg_brief 3.1, D2).
		invasion) echo $(( SUITE_TIMEOUT > 1200 ? SUITE_TIMEOUT : 1200 )) ;;
		# fallen: Contractor: Fallen's perf case (a survival night: the live cap of the dead, a crowd, a horde) on perfcases' meter.
		fallen) echo $(( SUITE_TIMEOUT > 900 ? SUITE_TIMEOUT : 900 )) ;;
		# operations: an 8 km operation zone hosted with an operation running in it (its OOB out, phases
		# played by the clock, a save and load), then a client joins it late and loads the zone too (D3).
		operations) echo $(( SUITE_TIMEOUT > 1440 ? SUITE_TIMEOUT : 1440 )) ;;
		# optypes: the five operation types played one after another, each in its own 8 km zone (offered,
		# phases, mechanic, pay, a save, the debrief), a client joining late in the first and following
		# the host into each (cg_brief 3.3, D4/D5).
		optypes) echo $(( SUITE_TIMEOUT > 1700 ? SUITE_TIMEOUT : 1700 )) ;;
		*) echo "$SUITE_TIMEOUT" ;;
	esac
}
timeout_s="$SUITE_TIMEOUT"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(smoke gameplay squad spacing net levelswitch wounds armor exo mech movement mantle interaction roles medical devices logistics casualty materials animations scavenge contracts people map base world missions vehicles antiarmor armour maingun gunnery vehiclehud vehiclefx armourlog armourdrive session_log supports heliflight bay aav sound loop ui loadout weapons ballistics forest townperf markers pallets voice compass audit_fixes garrison daynight nvg attachments controller base_zone loot tutorial lhd_home story virtualization gore firesupport demolitions water landmarks perfcases high_command side_command requests context smokecloud props terrain city roads income invasion operations optypes survival fallen rpg building fallenpeople settlement worldsim intel enclave mounts body)
status=0
finished=""
# Three verdicts (Captain, 2026-10-26: "orange for a flaky test that isn't outright failing, red
# for a failed and green for a full pass"): a suite that fails is run once more (RERUN_FLAKY=0
# turns that off); passing the rerun it's FLAKY (orange: a timing miss, not a red: its first
# logs are kept as <suite>.first-fail.log for scrutiny) and the run goes on and exits 0; failing
# again it's FAIL (red). PASS (green) is every suite clean first time.
flaky=0
flaky_suites=()
keep_root="$(run_log_parent)"
keep=""
run_id=""
if [ -n "$keep_root" ]; then
	run_id="$(printf 'R%04d' "$(run_log_number "$keep_root")")"
	run_tail="$(run_log_tail)"
	run_day="$keep_root/$(date +%Y-%m-%d)"
	run_time="$(date +%H%M%S)"
	keep="$run_day/$run_id-$run_time-RUNNING-$run_tail"
	mkdir -p "$keep" || keep=""
fi
# The logs go straight into the kept folder; with none, into a temp folder that goes at the end.
logs="$keep"
[ -z "$logs" ] && logs="$(mktemp -d)"
# The kept folder never goes: it's renamed PASS or FAIL.
verdict_colour() {  # green, orange, red on a terminal; plain in a log
	local v="$1"
	if [ -t 1 ]; then
		case "$v" in
			PASS) printf '\033[32m%s\033[0m' "$v" ;;
			FLAKY) printf '\033[33m%s\033[0m' "$v" ;;
			*) printf '\033[31m%s\033[0m' "$v" ;;
		esac
	else
		printf '%s' "$v"
	fi
}
keep_logs() {
	if [ -n "$keep" ]; then
		local verdict=PASS
		[ "$flaky" -gt 0 ] && verdict=FLAKY
		[ "$status" -ne 0 ] && verdict=FAIL
		[ -z "$finished" ] && { verdict=FAIL; note "stopped before it finished"; }
		[ "$flaky" -gt 0 ] && note "flaky (failed once, passed the rerun): ${flaky_suites[*]}"
		note "result: $verdict"
		local done_dir="$run_day/$run_id-$run_time-$verdict-$run_tail"
		mv "$keep" "$done_dir" 2>/dev/null && keep="$done_dir"
		local flaky_note=""
		[ "$flaky" -gt 0 ] && flaky_note=" flaky: ${flaky_suites[*]}"
		echo "$run_id $(date +%Y-%m-%d) $run_time $verdict $run_tail suites: ${SUITES[*]}$flaky_note" >>"$keep_root/index.txt"
		echo "run $run_id: $(verdict_colour "$verdict")$flaky_note, logs kept in $keep"
	else
		rm -rf "$logs"
	fi
}
trap keep_logs EXIT
# One line per verdict in the kept folder's summary.txt.
note() {
	[ -n "$keep" ] && echo "$1" >>"$keep/summary.txt"
}
note "run $run_id, $(date '+%Y-%m-%d %H:%M:%S'), ${run_tail:-}"
[ -n "${GITHUB_ACTIONS:-}" ] && note "CI: ${GITHUB_REPOSITORY:-} run ${GITHUB_RUN_ID:-} attempt ${GITHUB_RUN_ATTEMPT:-}, ${GITHUB_REF:-}, commit ${GITHUB_SHA:-}"
note "suites: ${SUITES[*]}  (port ${CONTRACTOR_PORT:-default}, timeout ${SUITE_TIMEOUT}s)"

# Runs the engine with "$@" under the timeout, output to log file $1. Returns the exit code
# (124 or 137: timed out). On CI an engine still running QUIT_GRACE_S after its summary line is
# hung in its shutdown (seen on the Linux runners: nvg and exo printed PASSED, then sat until the
# timeout): it's sent SIGSEGV so Godot's crash handler prints where it's stuck into its log, and
# "<log>.hung" notes it for judge. Locally (no gdb-free way to ask a Windows process) it just runs.
QUIT_GRACE_S="${QUIT_GRACE_S:-60}"
engine() {
	local log="$1"; shift
	rm -f "$log.hung"
	if [ -z "${GITHUB_ACTIONS:-}" ]; then
		timeout -k 10 "$timeout_s" "$GODOT" --headless --path . "$@" >"$log" 2>&1
		return
	fi
	timeout -k 10 "$timeout_s" "$GODOT" --headless --path . "$@" >"$log" 2>&1 &
	local runner=$!
	(
		seen=""
		while kill -0 "$runner" 2>/dev/null; do
			sleep 5
			if [ -z "$seen" ] && grep -qE 'TEST (PASSED|FAILED)' "$log" 2>/dev/null; then
				seen=$SECONDS
			elif [ -n "$seen" ] && [ $((SECONDS - seen)) -ge "$QUIT_GRACE_S" ]; then
				echo "still running ${QUIT_GRACE_S}s after its summary line: sent SIGSEGV for a backtrace" >"$log.hung"
				pkill -SEGV -P "$runner" 2>/dev/null
				sleep 20
				pkill -KILL -P "$runner" 2>/dev/null
				break
			fi
		done
	) &
	local watch=$!
	wait "$runner"
	local code=$?
	kill "$watch" 2>/dev/null
	wait "$watch" 2>/dev/null
	return "$code"
}

# Judges a finished process: `name`, its log, its exit code, and the summary line it must
# print ("" for none, e.g. "NET TEST PASSED"). Prints the log's [FAIL], summary and script error
# lines (prefixed with `prefix`) and a reason when it fails; sets status. A script error is a
# SCRIPT ERROR line or a parse error, which the import can report without that prefix.
judge() {
	local name="$1" log="$2" code="$3" summary="$4" prefix="${5:-}"
	grep -E '\[FAIL\]|TEST (PASSED|FAILED)|SCRIPT ERROR|Parse Error' "$log" | sed "s/^/$prefix/"
	local why=""
	if [ -f "$log.hung" ]; then
		why="hung after its summary line (engine shutdown; its backtrace is at the end of the log)"
	elif [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
		why="timed out after ${timeout_s}s (hung?)"
	elif grep -qE 'SCRIPT ERROR|Parse Error' "$log"; then
		why="script error (see above)"
	elif grep -q 'TEST FAILED' "$log"; then
		why="exit $code"
	elif [ "$code" -ne 0 ] && [ -n "$summary" ] && grep -q "$summary (0 failures)" "$log"; then
		# Every check passed and the summary printed; only the engine's exit after it failed
		# (seen on CI's Linux runners for AI-heavy suites, with "instances leaked at exit"):
		# a pass, noted, so a real failure still stands out. See docs/debugging.md.
		note "$name: passed (but the engine exited $code after its summary)"
	elif [ "$code" -ne 0 ]; then
		why="exit $code"
	elif [ -n "$summary" ] && ! grep -q "$summary" "$log"; then
		why="no \"$summary\" line: the test never finished"
	fi
	if [ -z "$why" ]; then
		note "$name: passed"
	else
		note "$name: FAILED: $why"
	fi
	grep -E '\[FAIL\]' "$log" | sed "s/^/  $name /" | while IFS= read -r line; do note "$line"; done
	if [ -n "$why" ]; then
		echo "$name: $why"
		echo "  last lines of its output:"
		tail -n 40 "$log" | sed "s/^/  | /"
		if [ -n "${GITHUB_ACTIONS:-}" ] && [ -z "${FIRST_TRY:-}" ]; then  # job logs need repo admin rights; annotations don't (a first try's failure may be a flake: the rerun's gets them)
			# GitHub keeps only 10 error annotations per step: the reason first (a suite can print
			# PASSED and still fail: a script error earlier, or a crash on quit), then the first
			# failed checks and script errors wherever they are in the log, then the last lines.
			echo "::error title=$name::FAILED: $why"
			grep -E '\[FAIL\]' "$log" | head -n 3 | while IFS= read -r line; do echo "::error title=$name failed check::$line"; done
			# The first script error with its whole backtrace (which caller) as one annotation (%0A:
			# a new line in it), then the next one's line.
			local first
			first="$(grep -n -m1 -E 'SCRIPT ERROR|Parse Error' "$log" | cut -d: -f1)"
			if [ -n "$first" ]; then
				echo "::error title=$name first script error::$(sed -n "${first},$((first + 14))p" "$log" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
				grep -E 'SCRIPT ERROR|Parse Error' "$log" | sed -n 2p | while IFS= read -r line; do echo "::error title=$name script error::$line"; done
			fi
			if [ -f "$log.hung" ]; then
				echo "::error title=$name hung at exit::$(tail -n 45 "$log" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
			fi
			tail -n 3 "$log" | while IFS= read -r line; do echo "::error title=$name::$line"; done
		fi
		status=1
	fi
}

# The import is judged like a suite with no summary line: a non-zero exit, a hang, or a SCRIPT
# ERROR or parse error in its log (a broken script can be reported while the import still exits
# 0) fails the run before any suite starts.
engine "$logs/import.log" --import
judge import "$logs/import.log" $? ""
[ "$status" -ne 0 ] && { finished=1; exit 1; }
run_suite() {
	local suite="$1"
	timeout_s="$(suite_timeout "$suite")"
	if [ "$suite" = net ] || [ "$suite" = levelswitch ] || [ "$suite" = world ] || [ "$suite" = vehicles ] || [ "$suite" = supports ] || [ "$suite" = aav ] || [ "$suite" = props ] || [ "$suite" = operations ] || [ "$suite" = optypes ]; then
		# Two processes over ENet on localhost. net: the client prints the summary, the host
		# exits when the client leaves. world, vehicles and aav: the host runs its own checks first
		# (refusing connections), then lets the client in; both print a summary. levelswitch: both
		# print a summary too, and the host starts a third process itself (B-04).
		summary="$(echo "$suite" | tr '[:lower:]' '[:upper:]') TEST PASSED"
		host_arg="--host"; join_arg="--join"; host_summary=""
		if [ "$suite" != net ]; then host_arg="--$suite-host"; join_arg="--$suite-join"; host_summary="$summary"; fi
		engine "$logs/$suite-host.log" "res://tests/${suite}_test.tscn" -- "$host_arg" &
		host=$!
		sleep 4
		engine "$logs/$suite.log" "res://tests/${suite}_test.tscn" -- "$join_arg" 127.0.0.1
		judge "$suite" "$logs/$suite.log" $? "$summary"
		wait "$host"
		judge "$suite host" "$logs/$suite-host.log" $? "$host_summary" "[$suite host] "
	else
		engine "$logs/$suite.log" "res://tests/${suite}_test.tscn"
		judge "$suite" "$logs/$suite.log" $? "$(echo "$suite" | tr '[:lower:]' '[:upper:]') TEST PASSED"
	fi
}
for suite in "${SUITES[@]}"; do
	before=$status
	FIRST_TRY=1 run_suite "$suite"
	if [ "$status" -ne "$before" ] && [ "${RERUN_FLAKY:-1}" != 0 ]; then
		note "$suite: failed once; run again to tell a flake (a timing miss) from a red"
		echo "$suite: failed once; running it again"
		for f in "$logs/$suite.log" "$logs/$suite-host.log"; do
			[ -f "$f" ] && mv "$f" "${f%.log}.first-fail.log"
			[ -f "$f.hung" ] && mv "$f.hung" "${f%.log}.first-fail.log.hung"
		done
		status=$before
		run_suite "$suite"
		if [ "$status" -eq "$before" ]; then
			flaky=$((flaky + 1))
			flaky_suites+=("$suite")
			note "$suite: FLAKY (failed once, passed the rerun)"
			echo "$suite: $(verdict_colour FLAKY) (failed once, passed the rerun; its first logs: $suite.first-fail.log)"
		fi
	fi
done

finished=1
exit $status
