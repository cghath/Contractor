#!/usr/bin/env bash
# Leaves a playable test build in its own folder, never reused (docs/debugging.md):
#   builds/contractor-<date>-<time>-B<number>-<label>-<sha>/
#     contractor.pck                 the game
#     play.bat                       double-click to play; runs the pack with the Voxel Tools build of Godot
#     Contractor.exe                 the standalone game (when the Voxel Tools release template is installed; see below)
#     Contractor (dev tools).bat     the same with the dev tools on (--dev): Contractor.exe's, or play.bat's without one
#     BUILD.txt                      build number, branch, commit, export log and what to test
# Usage: GODOT=<voxel godot exe> [VERSION=0.3.1] tools/make_build.sh <label> ["what to test"]
# VERSION (Captain, 2026-10-14: builds go by version, v0.MINOR.PATCH: minor for a feature
# build, patch for a fix-only one) names the folder builds/contractor-v<VERSION>-B<number>-<sha>/
# instead; the B<number> stays in it (the run-log id; SessionLog reads the build label from it).
# The number is the next one from run_counter.txt in the logs parent the test runs use
# (tools/run_log.sh: Contractor-test-logs beside the main checkout, or CONTRACTOR_TEST_LOGS),
# and the build gets a line in its index.txt, PASS or FAIL. Both exports' output (the pack and
# Contractor.exe) is kept there as <date>/B<number>-<time>-export.log. A failed export fails
# the build loudly (exit 1, the reason, the log's last lines, FAILED.txt in the build folder).
# builds/ is git-ignored: builds stay on the machine that made them.
# play.bat needs no export templates: the Voxel Tools editor binary runs the pack directly.
set -eu
cd "$(dirname "$0")/.."
. tools/run_log.sh
GODOT="${GODOT:-godot}"
label="${1:?usage: tools/make_build.sh <label> [\"what to test\"]}"
notes="${2:-}"
parent="$(run_log_parent)"
[ -n "$parent" ] || { echo "make_build: no logs parent to number the build and keep its export log (set CONTRACTOR_TEST_LOGS to a folder)"; exit 1; }
id="$(printf 'B%04d' "$(run_log_number "$parent")")"
day="$(date +%Y-%m-%d)"
time="$(date +%H%M%S)"
run_tail="$(run_log_tail)"
sha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
topic="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '-')"
version="${VERSION:-}"
version="${version#v}"
if [ -n "$version" ]; then
	dir="builds/contractor-v$version-$id-$sha"
else
	dir="builds/contractor-$day-$time-$id-$topic-$sha"
fi
mkdir -p "$parent/$day"
log="$parent/$day/$id-$time-export.log"
why=""
finished=""
echo "build $id ($label), $day $time, $run_tail -> $dir" >"$log"

# Whatever happens: the verdict goes in the log and index.txt; a failure says why, loudly.
finish() {
	local code=$? verdict=PASS
	{ [ "$code" -ne 0 ] || [ -z "$finished" ] || [ -n "$why" ]; } && verdict=FAIL
	[ "$verdict" = FAIL ] && [ -z "$why" ] && why="stopped (exit $code)"
	echo "result: $verdict${why:+: $why}" >>"$log"
	echo "$id $day $time $verdict $run_tail build $topic -> $dir" >>"$parent/index.txt"
	if [ "$verdict" = PASS ]; then
		echo "build $id: PASS, export log $log"
		echo "$dir"
	else
		[ -d "$dir" ] && echo "This build failed ($why). Export log: $log" >"$dir/FAILED.txt"
		echo "BUILD $id FAILED: $why"
		echo "  export log: $log"
		tail -n 30 "$log" | sed 's/^/  | /'
		exit 1
	fi
}
trap finish EXIT

# Runs one export ("what", then the engine's arguments) with its output appended to the log.
# Fails on a non-zero exit or a script error in the log (an export can report a script that
# doesn't compile and still exit 0, packing the broken script).
export_step() {
	local what="$1" code=0
	shift
	echo "== $what: $GODOT --headless --path . $*" >>"$log"
	"$GODOT" --headless --path . "$@" >>"$log" 2>&1 || code=$?
	echo "== $what: exit $code" >>"$log"
	[ "$code" -eq 0 ] && ! grep -qE 'SCRIPT ERROR|Parse Error' "$log"
}

mkdir -p builds
mkdir "$dir"
# The preset is git-ignored (local paths); write a minimal one if this checkout has none.
if ! grep -q 'name="Windows Desktop"' export_presets.cfg 2>/dev/null; then
	[ -f export_presets.cfg ] && { why="export_presets.cfg has no \"Windows Desktop\" preset; add one or rename yours"; exit 1; }
	cat > export_presets.cfg <<'CFG'
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="data/*.json"
exclude_filter="tests/*, tools/*, screenshots/*, builds/*, docs/*"
export_path=""
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/embed_pck=false
binary_format/architecture="x86_64"
CFG
fi
if ! export_step "pack" --export-pack "Windows Desktop" "$dir/contractor.pck" || [ ! -s "$dir/contractor.pck" ]; then
	why="the pack export failed"
	exit 1
fi
cat > "$dir/play.bat" <<'BAT'
@echo off
rem Plays this build. Needs the Voxel Tools 1.7 build of Godot (see the README or GET_GODOT.txt).
rem Looks for it beside this file (or unzipped into a folder here), then in Downloads\GodotVoxel_1.7;
rem set CONTRACTOR_GODOT to its path if it's somewhere else.
rem Extra arguments go to the game, e.g.  play.bat -- --host   or   play.bat -- --join 127.0.0.1
setlocal
set "EXE=godot.windows.editor.x86_64.exe"
set "GODOT=%CONTRACTOR_GODOT%"
if not defined GODOT for %%G in ("%~dp0%EXE%" "%~dp0GodotVoxel-1.7-windows-editor\%EXE%" "%~dp0%EXE%\%EXE%""%USERPROFILE%\Downloads\GodotVoxel_1.7\%EXE%") do if not defined GODOT if exist "%%~G" if not exist "%%~G\" set "GODOT=%%~G"
if not defined GODOT set "GODOT=%USERPROFILE%\Downloads\GodotVoxel_1.7\%EXE%"
if not exist "%GODOT%" (
	echo Could not find the Voxel Tools build of Godot at:
	echo   %GODOT%
	echo Put %EXE% beside play.bat, or set CONTRACTOR_GODOT to its full path, and try again.
	echo Download: https://github.com/Zylann/godot_voxel/releases/tag/v1.7  ^(godot.windows.editor.x86_64.exe.zip^)
	pause
	exit /b 1
)
start "" "%GODOT%" --main-pack "%~dp0contractor.pck" %*
BAT
sed -i 's/$/\r/' "$dir/play.bat"
# A standalone Contractor.exe too, when the Voxel Tools release template for this editor is there
# (Zylann's godot.windows.template_release.x86_64.exe from the same release as the editor; set
# CONTRACTOR_TEMPLATE to it, or unzip it to template_release/ beside the editor). The exe reads the
# pack beside it, so nobody needs the editor to play. It's a release build: dev tools need --dev.
template="${CONTRACTOR_TEMPLATE:-$(dirname "$GODOT")/template_release/godot.windows.template_release.x86_64.exe}"
if [ -f "$template" ]; then
	win_template="$(cygpath -m "$template" 2>/dev/null || echo "$template")"
	sed -i "s|^custom_template/release=.*|custom_template/release=\"$win_template\"|" export_presets.cfg
	if export_step "Contractor.exe" --export-release "Windows Desktop" "$dir/Contractor.exe" && [ -s "$dir/Contractor.exe" ]; then
		printf '@echo off\r\nrem Plays this build with the dev tools on (docs/debugging.md: K, Shift+End, Insert, Delete...).\r\nstart "" "%%~dp0Contractor.exe" --dev %%*\r\n' > "$dir/Contractor (dev tools).bat"
	else
		why="the Contractor.exe export failed (play.bat still works)"
	fi
fi
if [ ! -s "$dir/Contractor.exe" ]; then
	# No exe: play.bat's own command, with the dev tools on.
	printf '@echo off\r\nrem Plays this build with the dev tools on (docs/debugging.md: K, Shift+End, Insert, Delete...).\r\ncall "%%~dp0play.bat" --dev %%*\r\n' > "$dir/Contractor (dev tools).bat"
fi
# One-click co-op hosting (Captain, 2026-10-15: "always ready for local play" over LAN/ZeroTier):
# host the campaign at the FOB on UDP 24680, or archive it (moved, never deleted) and host a new one.
if [ -s "$dir/Contractor.exe" ]; then
	printf '@echo off\r\nrem Hosts the campaign at the FOB (UDP 24680). Friends join with Contractor.exe and the host IP.\r\nstart "" "%%~dp0Contractor.exe" -- --campaign %%*\r\n' > "$dir/Host campaign.bat"
	printf '@echo off\r\nrem Archives the current campaign (moved, never deleted) and hosts a NEW one at the FOB.\r\nstart "" "%%~dp0Contractor.exe" -- --new-campaign %%*\r\n' > "$dir/Host NEW campaign.bat"
fi
{
	if [ -n "$version" ]; then
		echo "Contractor v$version (test build $id): $label"
	else
		echo "Contractor test build $id: $label"
	fi
	branch="$(git branch --show-current 2>/dev/null || true)"
	# A tag's checkout on CI has no branch: name the tag (or the ref) instead.
	[ -n "$branch" ] || branch="${GITHUB_REF_NAME:-unknown}"
	echo "Built $(date '+%Y-%m-%d %H:%M') from branch $branch, commit $sha$(git diff --quiet HEAD -- . ':!builds' 2>/dev/null || echo ' plus uncommitted changes')"
	echo "Export log: $log"
	echo
	if [ -s "$dir/Contractor.exe" ]; then
		echo "Play: double-click Contractor.exe (or \"Contractor (dev tools).bat\" for the dev keys)."
		echo "play.bat runs the same pack through the Voxel Tools editor (dev tools always on)."
	else
		echo "Play: double-click play.bat (or \"Contractor (dev tools).bat\" for the dev keys), then click Play (host a session)."
	fi
	[ -n "$notes" ] && { echo; echo "What to test:"; echo "$notes"; }
} > "$dir/BUILD.txt"
basename "$dir" > "$dir/build_label.txt"  # the game's build label (BuildInfo), even if the folder is renamed
[ -n "$why" ] && exit 1
finished=1
