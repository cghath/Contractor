#!/usr/bin/env bash
# Runs the headless test suites. Set GODOT to the Voxel Tools editor executable, e.g.
#   GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/run_tests.sh
# With arguments, runs only those suites:  tools/run_tests.sh smoke gameplay
# Suites are tests/<name>_test.tscn; "net", "world" and "vehicles" are two-process host/client tests.
# Parallel runs (separate worktrees) should set CONTRACTOR_TEST_TAG (keeps test saves apart)
# and CONTRACTOR_PORT (keeps the net test's port apart).
#
# A suite passes only if its process exits 0, prints "<NAME> TEST PASSED", prints no
# "TEST FAILED", and logs no SCRIPT ERROR (a script that fails to compile or crashes mid-test
# can still exit 0, or never exit at all). Each process gets SUITE_TIMEOUT seconds (default
# 480); one that runs past it is killed and fails as hung. The import must succeed too.
# Exits non-zero if any suite fails. tools/test_runner_check.sh checks these rules.
#
# Every run's logs are kept (Captain, 2026-10-12) in their own folder outside the repo, which
# nothing here ever deletes, all under one parent: CONTRACTOR_TEST_LOGS (default:
# Contractor-test-logs beside the main checkout, shared by every worktree, e.g.
# B:\Contractor-test-logs). Each run gets a number (run_counter.txt there, counting up forever,
# unique across worktrees) and a folder by date:
#   <parent>/<date>/R<number>-<time>-<PASS|FAIL>-<branch>-<sha>/
# (RUNNING while it runs; a folder left RUNNING was killed). Inside: every suite's log and
# summary.txt (run id, suites, each verdict and [FAIL] line). index.txt at the top lists every
# run, one line each. On CI (GITHUB_ACTIONS) nothing is kept unless CONTRACTOR_TEST_LOGS is set;
# CONTRACTOR_TEST_LOGS=none keeps nothing.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SUITE_TIMEOUT="${SUITE_TIMEOUT:-480}"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(smoke gameplay squad net wounds armor movement interaction roles medical logistics casualty materials animations scavenge contracts people map base world missions vehicles antiarmor session_log)
status=0
logs="$(mktemp -d)"
keep_root="${CONTRACTOR_TEST_LOGS:-}"
if [ -z "$keep_root" ] && [ -z "${GITHUB_ACTIONS:-}" ]; then
	# One parent for every worktree (beside the main checkout), so run numbers are unique
	# across them; a copy outside git keeps its own beside its folder.
	common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
	if [ -n "$common" ]; then keep_root="$(cd "$common/../.." && pwd)/Contractor-test-logs"; else keep_root="$(cd .. && pwd)/Contractor-test-logs"; fi
fi
keep=""
run_id=""
if [ -n "$keep_root" ] && [ "$keep_root" != none ] && mkdir -p "$keep_root"; then
	n=$(( $(cat "$keep_root/run_counter.txt" 2>/dev/null || echo 0) + 1 ))
	echo "$n" >"$keep_root/run_counter.txt"
	run_id="$(printf 'R%04d' "$n")"
	branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')"
	sha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
	run_tail="${branch:-nobranch}-$sha"
	run_day="$keep_root/$(date +%Y-%m-%d)"
	run_time="$(date +%H%M%S)"
	keep="$run_day/$run_id-$run_time-RUNNING-$run_tail"
	mkdir -p "$keep" || keep=""
fi
# The temp folder goes; the kept copy never does. The run's folder is renamed PASS or FAIL.
keep_logs() {
	if [ -n "$keep" ]; then
		cp "$logs"/*.log "$keep"/ 2>/dev/null
		local verdict=PASS
		[ "$status" -ne 0 ] && verdict=FAIL
		note "result: $verdict"
		local done_dir="$run_day/$run_id-$run_time-$verdict-$run_tail"
		mv "$keep" "$done_dir" 2>/dev/null && keep="$done_dir"
		echo "$run_id $(date +%Y-%m-%d) $run_time $verdict $run_tail suites: ${SUITES[*]}" >>"$keep_root/index.txt"
		echo "run $run_id: $verdict, logs kept in $keep"
	fi
	rm -rf "$logs"
}
trap keep_logs EXIT
# One line per verdict in the kept folder's summary.txt.
note() {
	[ -n "$keep" ] && echo "$1" >>"$keep/summary.txt"
}
note "run $run_id, $(date '+%Y-%m-%d %H:%M:%S'), ${run_tail:-}"
note "suites: ${SUITES[*]}  (port ${CONTRACTOR_PORT:-default}, timeout ${SUITE_TIMEOUT}s)"

# Runs the engine with "$@" under the timeout, output to log file $1. Returns the exit code
# (124 or 137: timed out).
engine() {
	local log="$1"; shift
	timeout -k 10 "$SUITE_TIMEOUT" "$GODOT" --headless --path . "$@" >"$log" 2>&1
}

# Judges a finished process: `name`, its log, its exit code, and the summary line it must
# print ("" for none, e.g. "NET TEST PASSED"). Prints the log's [FAIL], summary and SCRIPT ERROR
# lines (prefixed with `prefix`) and a reason when it fails; sets status.
judge() {
	local name="$1" log="$2" code="$3" summary="$4" prefix="${5:-}"
	grep -E '\[FAIL\]|TEST (PASSED|FAILED)|SCRIPT ERROR' "$log" | sed "s/^/$prefix/"
	local why=""
	if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
		why="timed out after ${SUITE_TIMEOUT}s (hung?)"
	elif grep -q 'SCRIPT ERROR' "$log"; then
		why="script error (see above)"
	elif grep -q 'TEST FAILED' "$log"; then
		why="exit $code"
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
			tail -n 12 "$log" | while IFS= read -r line; do echo "::error title=$name::$line"; done
		fi
		status=1
	fi
}

if ! engine "$logs/import.log" --import; then
	echo "import: failed"
	note "import: FAILED"
	status=1
	grep -E 'SCRIPT ERROR|ERROR' "$logs/import.log" | head -20
	exit 1
fi
for suite in "${SUITES[@]}"; do
	if [ "$suite" = net ] || [ "$suite" = world ] || [ "$suite" = vehicles ]; then
		# Two processes over ENet on localhost. net: the client prints the summary, the host
		# exits when the client leaves. world and vehicles: the host runs its own checks first
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

exit $status
