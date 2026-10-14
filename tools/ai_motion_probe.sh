#!/usr/bin/env bash
# AI movement-quality probe (tests/ai_motion_probe.tscn): imports, runs the probe headless and
# keeps its log as an S run (shared counter, docs/debugging.md) under the logs parent:
#   <parent>/<date>/S<number>-<time>-<PASS|FAIL>-aimotion-<label>-<branch>-<sha>/probe.log
# Usage: GODOT=<voxel godot exe> tools/ai_motion_probe.sh [label]   (env PROBE_RUN_S, PROBE_SEED)
# Not a pass/fail suite: it prints per-unit and per-side numbers ("PROBE SUMMARY" lines).
set -u
cd "$(dirname "$0")/.."
. tools/run_log.sh
GODOT="${GODOT:-godot}"
label="${1:-probe}"
parent="$(run_log_parent)"
dir="$(mktemp -d)"
if [ -n "$parent" ]; then
	id="$(printf 'S%04d' "$(run_log_number "$parent")")"
	day="$parent/$(date +%Y-%m-%d)"
	t="$(date +%H%M%S)"
	dir="$day/$id-$t-RUNNING-aimotion-$label-$(run_log_tail)"
	mkdir -p "$dir"
fi
timeout -k 10 600 "$GODOT" --headless --path . --import >"$dir/import.log" 2>&1
timeout -k 10 "${PROBE_TIMEOUT:-420}" "$GODOT" --headless --path . res://tests/ai_motion_probe.tscn >"$dir/probe.log" 2>&1
code=$?
grep -E "^probe:|PROBE|SCRIPT ERROR" "$dir/probe.log"
verdict=PASS
{ [ "$code" -ne 0 ] || ! grep -q "PROBE DONE" "$dir/probe.log"; } && verdict=FAIL
if [ -n "$parent" ]; then
	done_dir="${dir/RUNNING/$verdict}"
	mv "$dir" "$done_dir" && dir="$done_dir"
	echo "$id $(date +%Y-%m-%d) $t $verdict aimotion-$label-$(run_log_tail)" >>"$parent/index.txt"
fi
echo "probe $verdict (exit $code), log in $dir"
