#!/usr/bin/env bash
# Runs the headless test suites. Set GODOT to the Voxel Tools editor executable, e.g.
#   GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/run_tests.sh
# With arguments, runs only those suites:  tools/run_tests.sh smoke gameplay
# Suites are tests/<name>_test.tscn; "net" is the two-process host/client test.
# Parallel runs (separate worktrees) should set CONTRACTOR_TEST_TAG (keeps test saves apart)
# and CONTRACTOR_PORT (keeps the net test's port apart).
# Exits non-zero if any suite fails.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(smoke gameplay squad net wounds armor movement interaction roles medical logistics casualty animations)
status=0

run() {
	local name="$1"; shift
	"$GODOT" --headless --path . "$@" 2>&1 | grep -E '\[FAIL\]|TEST (PASSED|FAILED)|SCRIPT ERROR'
	local code=${PIPESTATUS[0]}
	[ "$code" -eq 0 ] || { echo "$name: exit $code"; status=1; }
}

"$GODOT" --headless --path . --import >/dev/null 2>&1
for suite in "${SUITES[@]}"; do
	if [ "$suite" = net ]; then
		# A host and a client talking over ENet on localhost.
		"$GODOT" --headless --path . res://tests/net_test.tscn -- --host >/dev/null 2>&1 &
		host=$!
		sleep 4
		run net res://tests/net_test.tscn -- --join 127.0.0.1
		wait "$host" || { echo "net host: failed"; status=1; }
	else
		run "$suite" "res://tests/${suite}_test.tscn"
	fi
done

exit $status
