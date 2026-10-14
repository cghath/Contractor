#!/usr/bin/env bash
# Frame-rate benchmark (tests/frame_bench.gd): a garrisoned town in a hot zone, four player
# bodies, the squad in a firefight, civilians and bodies, a fixed camera path; prints the
# average, 1% low and worst frame, CPU (process, physics, render) vs GPU time, draw calls,
# primitives and counts. Not a suite: it measures. Needs a real window (fullscreen by default).
# Kept like any run (docs/debugging.md) as an S run:
#   GODOT="<voxel godot editor>" tools/frame_bench.sh <label> [bench args] [-- godot args]
# Bench args: --windowed 1920x1080 (else exclusive fullscreen at the screen's size), --vsync.
# Godot args after "--", e.g. --gpu-index 1 (the Vulkan device line in bench.log names the GPU).
# With CONTRACTOR_TEMPLATE set to the Voxel Tools release template the test builds use
# (tools/make_build.sh: Contractor.exe), the bench runs as players run the game: a release exe
# with the project and the bench packed beside it (builds/frame_bench/, a "Frame bench" export
# preset added to the git-ignored export_presets.cfg if missing). Otherwise in the editor binary,
# whose debug GDScript is slower (compare like with like).
# Results: bench.txt, frames.csv, street/orbit/far.png and bench.log in the run folder.
set -u
cd "$(dirname "$0")/.."
. tools/run_log.sh
GODOT="${GODOT:-godot}"
label="${1:-bench}"; shift || true
bench_args=()
godot_args=()
while [ $# -gt 0 ]; do
	if [ "$1" = "--" ]; then shift; godot_args=("$@"); break; fi
	bench_args+=("$1"); shift
done
parent="$(run_log_parent)"
[ -z "$parent" ] && parent="$(mktemp -d)"
id="$(printf 'S%04d' "$(run_log_number "$parent")")"
tail="$(run_log_tail)"
day="$parent/$(date +%Y-%m-%d)"
time="$(date +%H%M%S)"
dir="$day/$id-$time-RUNNING-framebench-$label-$tail"
mkdir -p "$dir"
timeout -k 10 300 "$GODOT" --headless --path . --import >"$dir/import.log" 2>&1
out="$(cygpath -w "$dir" 2>/dev/null || echo "$dir")"
run=("$GODOT" --path .)
scene=(res://tests/frame_bench.tscn)
build="release"
if [ -n "${CONTRACTOR_TEMPLATE:-}" ] && [ -f "$CONTRACTOR_TEMPLATE" ]; then
	if ! grep -q 'name="Frame bench"' export_presets.cfg 2>/dev/null; then
		n="$(grep -c '^\[preset\.[0-9]*\]$' export_presets.cfg 2>/dev/null)"
		cat >> export_presets.cfg <<CFG

[preset.${n:-0}]

name="Frame bench"
platform="Windows Desktop"
runnable=false
dedicated_server=false
custom_features="frame_bench"
export_filter="all_resources"
include_filter="data/*.json"
exclude_filter="tools/*, screenshots/*, builds/*, docs/*"
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.${n:-0}.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=false
binary_format/architecture="x86_64"
CFG
	fi
	mkdir -p builds/frame_bench
	timeout -k 10 400 "$GODOT" --headless --path . --export-pack "Frame bench" builds/frame_bench/frame_bench.pck >"$dir/export.log" 2>&1
	cp -f "$CONTRACTOR_TEMPLATE" builds/frame_bench/frame_bench.exe
	run=(builds/frame_bench/frame_bench.exe)
	scene=()  # a release exe takes no scene path: the preset's frame_bench feature makes the bench its main scene (project.godot)
else
	build="editor"
fi
echo "binary: ${run[0]} ($build)" >"$dir/binary.txt"
BENCH_SHA="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- scripts scenes tests || echo '+changes') $build" \
	timeout -k 10 400 "${run[@]}" "${godot_args[@]}" "${scene[@]}" -- --out "$out" "${bench_args[@]}" >"$dir/bench.log" 2>&1 &
pid=$!
# A script that doesn't compile never quits by itself (its deadline timer never starts): stop it.
while kill -0 "$pid" 2>/dev/null; do
	if grep -qE 'Parse Error|Failed to load script' "$dir/bench.log" 2>/dev/null; then
		powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.CommandLine -like '*frame_bench.tscn*$id-*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" >/dev/null 2>&1
		break
	fi
	sleep 2
done
wait "$pid"
code=$?
verdict=PASS
{ [ "$code" -ne 0 ] || ! grep -q 'BENCH DONE' "$dir/bench.log" || grep -qE 'SCRIPT ERROR' "$dir/bench.log"; } && verdict=FAIL
done_dir="$day/$id-$time-$verdict-framebench-$label-$tail"
mv "$dir" "$done_dir"
echo "$id $(date +%Y-%m-%d) $time $verdict $tail script: tests/frame_bench.gd ($label: ${bench_args[*]} ${godot_args[*]})" >>"$parent/index.txt"
grep -E 'Vulkan|Using Device' "$done_dir/bench.log" | head -n 3
grep '^BENCH' "$done_dir/bench.log"
echo "run $id: $verdict (exit $code), logs in $done_dir"
[ "$verdict" = PASS ]
