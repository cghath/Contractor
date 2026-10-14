#!/usr/bin/env bash
# Runs the headless test suites. Set GODOT to the Voxel Tools editor executable, e.g.
#   GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/run_tests.sh
# With arguments, runs only those suites:  tools/run_tests.sh smoke gameplay
# Suites are tests/<name>_test.tscn; "net", "world", "vehicles", "supports" and "aav" are two-process host/client tests.
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
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(smoke gameplay squad net wounds armor movement interaction roles comms medical logistics casualty materials animations scavenge contracts people map base world missions vehicles antiarmor session_log supports aav sound loop)
status=0
finished=""
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
keep_logs() {
	if [ -n "$keep" ]; then
		local verdict=PASS
		[ "$status" -ne 0 ] && verdict=FAIL
		[ -z "$finished" ] && { verdict=FAIL; note "stopped before it finished"; }
		note "result: $verdict"
		local done_dir="$run_day/$run_id-$run_time-$verdict-$run_tail"
		mv "$keep" "$done_dir" 2>/dev/null && keep="$done_dir"
		echo "$run_id $(date +%Y-%m-%d) $run_time $verdict $run_tail suites: ${SUITES[*]}" >>"$keep_root/index.txt"
		echo "run $run_id: $verdict, logs kept in $keep"
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
# (124 or 137: timed out).
engine() {
	local log="$1"; shift
	timeout -k 10 "$SUITE_TIMEOUT" "$GODOT" --headless --path . "$@" >"$log" 2>&1
}

# Judges a finished process: `name`, its log, its exit code, and the summary line it must
# print ("" for none, e.g. "NET TEST PASSED"). Prints the log's [FAIL], summary and script error
# lines (prefixed with `prefix`) and a reason when it fails; sets status. A script error is a
# SCRIPT ERROR line or a parse error, which the import can report without that prefix.
judge() {
	local name="$1" log="$2" code="$3" summary="$4" prefix="${5:-}"
	grep -E '\[FAIL\]|TEST (PASSED|FAILED)|SCRIPT ERROR|Parse Error' "$log" | sed "s/^/$prefix/"
	local why=""
	if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
		why="timed out after ${SUITE_TIMEOUT}s (hung?)"
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
		if [ -n "${GITHUB_ACTIONS:-}" ]; then  # job logs need repo admin rights; annotations don't
			# GitHub keeps only 10 error annotations per step: the reason first (a suite can print
			# PASSED and still fail: a script error earlier, or a crash on quit), then the first
			# failed checks and script errors wherever they are in the log, then the last lines.
			echo "::error title=$name::FAILED: $why"
			grep -E '\[FAIL\]' "$log" | head -n 3 | while IFS= read -r line; do echo "::error title=$name failed check::$line"; done
			grep -A1 -E 'SCRIPT ERROR|Parse Error' "$log" | grep -v '^--$' | head -n 3 | while IFS= read -r line; do echo "::error title=$name script error::$line"; done
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
for suite in "${SUITES[@]}"; do
	if [ "$suite" = net ] || [ "$suite" = world ] || [ "$suite" = vehicles ] || [ "$suite" = supports ] || [ "$suite" = aav ]; then
		# Two processes over ENet on localhost. net: the client prints the summary, the host
		# exits when the client leaves. world, vehicles and aav: the host runs its own checks first
		# (refusing connections), then lets the client in; both print a summary.
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
done

finished=1
exit $status
