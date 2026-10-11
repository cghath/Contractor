#!/usr/bin/env bash
# Runs the headless test suites. Set GODOT to the Voxel Tools editor executable, e.g.
#   GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/run_tests.sh
# With arguments, runs only those suites:  tools/run_tests.sh smoke gameplay
# Suites are tests/<name>_test.tscn; "net" and "world" are two-process host/client tests.
# Parallel runs (separate worktrees) should set CONTRACTOR_TEST_TAG (keeps test saves apart)
# and CONTRACTOR_PORT (keeps the net test's port apart).
#
# A suite passes only if its process exits 0, prints "<NAME> TEST PASSED", prints no
# "TEST FAILED", and logs no SCRIPT ERROR (a script that fails to compile or crashes mid-test
# can still exit 0, or never exit at all). Each process gets SUITE_TIMEOUT seconds (default
# 480); one that runs past it is killed and fails as hung. The import must succeed too.
# Exits non-zero if any suite fails. tools/test_runner_check.sh checks these rules.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SUITE_TIMEOUT="${SUITE_TIMEOUT:-480}"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(smoke gameplay squad net wounds armor movement interaction roles medical logistics casualty materials animations scavenge contracts people map base world)
status=0
logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

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
	if [ -n "$why" ]; then
		echo "$name: $why"
		status=1
	fi
}

if ! engine "$logs/import.log" --import; then
	echo "import: failed"
	grep -E 'SCRIPT ERROR|ERROR' "$logs/import.log" | head -20
	exit 1
fi
for suite in "${SUITES[@]}"; do
	if [ "$suite" = net ] || [ "$suite" = world ]; then
		# Two processes over ENet on localhost. net: the client prints the summary, the host
		# exits when the client leaves. world: the host runs its own checks first (refusing
		# connections), then lets the client in; both print a summary.
		summary="$(echo "$suite" | tr '[:lower:]' '[:upper:]') TEST PASSED"
		host_arg="--host"; join_arg="--join"; host_summary=""
		if [ "$suite" = world ]; then host_arg="--world-host"; join_arg="--world-join"; host_summary="$summary"; fi
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
