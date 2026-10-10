#!/usr/bin/env bash
# Leaves a playable test build in builds/<date>_<label>/:
#   contractor.pck  the game (about 130 KB)
#   play.bat        double-click to play; runs the pack with the Voxel Tools build of Godot
#   BUILD.txt       branch, commit and what to test
# Usage: GODOT=<voxel godot exe> tools/make_build.sh <label> ["what to test"]
# builds/ is git-ignored: builds stay on the machine that made them.
# No export templates needed: the Voxel Tools editor binary runs the pack directly.
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
label="${1:?usage: tools/make_build.sh <label> [\"what to test\"]}"
notes="${2:-}"
dir="builds/$(date +%Y-%m-%d)_${label}"
mkdir -p "$dir"
# The preset is git-ignored (local paths); write a minimal one if this checkout has none.
if ! grep -q 'name="Windows Desktop"' export_presets.cfg 2>/dev/null; then
	[ -f export_presets.cfg ] && { echo "export_presets.cfg has no \"Windows Desktop\" preset; add one or rename yours"; exit 1; }
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
