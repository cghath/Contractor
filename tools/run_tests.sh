#!/usr/bin/env bash
# Runs every headless test suite. Set GODOT to the Voxel Tools editor executable, e.g.
#   GODOT="$HOME/Downloads/GodotVoxel_1.7/godot.windows.editor.x86_64.exe" tools/run_tests.sh
# Exits non-zero if any suite fails.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
status=0

run() {
	local name="$1"; shift
	if "$GODOT" --headless --path . "$@" 2>&1 | grep -E '\[FAIL\]|TEST (PASSED|FAILED)|SCRIPT ERROR'; then :; fi
	local code=${PIPESTATUS[0]}
	[ "$code" -eq 0 ] || { echo "$name: exit $code"; status=1; }
}

"$GODOT" --headless --path . --import >/dev/null 2>&1
run smoke res://tests/smoke_test.tscn
run gameplay res://tests/gameplay_test.tscn
run squad res://tests/squad_test.tscn

# Network: a host and a client talking over ENet on localhost.
"$GODOT" --headless --path . res://tests/net_test.tscn -- --host >/dev/null 2>&1 &
host=$!
sleep 4
run net res://tests/net_test.tscn -- --join 127.0.0.1
wait "$host" || { echo "net host: failed"; status=1; }

exit $status
