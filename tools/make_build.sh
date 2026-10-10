#!/usr/bin/env bash
# Leaves a playable test build in builds/<date>_<label>/:
#   contractor.pck  the game (about 130 KB)
#   play.bat        double-click to play; runs the pack with the Voxel Tools build of Godot
#   BUILD.txt       branch, commit and what to test
# Usage: GODOT=<voxel godot exe> tools/make_build.sh <label> ["what to test"]
# No export templates needed: the Voxel Tools editor binary runs the pack directly.
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
label="${1:?usage: tools/make_build.sh <label> [\"what to test\"]}"
notes="${2:-}"
dir="builds/$(date +%Y-%m-%d)_${label}"
mkdir -p "$dir"
"$GODOT" --headless --path . --export-pack "Windows Desktop" "$dir/contractor.pck" >/dev/null 2>&1
[ -s "$dir/contractor.pck" ] || { echo "export failed"; exit 1; }
cat > "$dir/play.bat" <<'BAT'
@echo off
rem Plays this build. Needs the Voxel Tools 1.7 build of Godot (see the README).
rem Set CONTRACTOR_GODOT to its path if it isn't in the default place.
rem Extra arguments go to the game, e.g.  play.bat -- --host   or   play.bat -- --join 127.0.0.1
setlocal
set "GODOT=%CONTRACTOR_GODOT%"
if not defined GODOT set "GODOT=%USERPROFILE%\Downloads\GodotVoxel_1.7\godot.windows.editor.x86_64.exe"
if not exist "%GODOT%" (
	echo Could not find the Voxel Tools build of Godot at:
	echo   %GODOT%
	echo Set CONTRACTOR_GODOT to the full path of godot.windows.editor.x86_64.exe and try again.
	pause
	exit /b 1
)
start "" "%GODOT%" --main-pack "%~dp0contractor.pck" %*
BAT
sed -i 's/$/\r/' "$dir/play.bat"
{
	echo "Contractor test build: $label"
	echo "Built $(date '+%Y-%m-%d %H:%M') from branch $(git branch --show-current), commit $(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . ':!builds' || echo ' plus uncommitted changes')"
	echo
	echo "Play: double-click play.bat, then click Play (host a session)."
	[ -n "$notes" ] && { echo; echo "What to test:"; echo "$notes"; }
} > "$dir/BUILD.txt"
echo "$dir"
