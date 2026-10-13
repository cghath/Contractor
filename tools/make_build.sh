#!/usr/bin/env bash
# Leaves a playable test build in builds/<date>_<label>/:
#   contractor.pck  the game
#   Contractor.exe  the standalone game (when the Voxel Tools release template is installed; see below)
#   play.bat        double-click to play; runs the pack with the Voxel Tools build of Godot
#   BUILD.txt       branch, commit and what to test
# Usage: GODOT=<voxel godot exe> tools/make_build.sh <label> ["what to test"]
# builds/ is git-ignored: builds stay on the machine that made them.
# play.bat needs no export templates: the Voxel Tools editor binary runs the pack directly.
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
# A standalone Contractor.exe too, when the Voxel Tools release template for this editor is there
# (Zylann's godot.windows.template_release.x86_64.exe from the same release as the editor; set
# CONTRACTOR_TEMPLATE to it, or unzip it to template_release/ beside the editor). The exe reads the
# pack beside it, so nobody needs the editor to play. It's a release build: dev tools need --dev.
template="${CONTRACTOR_TEMPLATE:-$(dirname "$GODOT")/template_release/godot.windows.template_release.x86_64.exe}"
if [ -f "$template" ]; then
	win_template="$(cygpath -m "$template" 2>/dev/null || echo "$template")"
	sed -i "s|^custom_template/release=.*|custom_template/release=\"$win_template\"|" export_presets.cfg
	"$GODOT" --headless --path . --export-release "Windows Desktop" "$dir/Contractor.exe" >/dev/null 2>&1
	if [ -s "$dir/Contractor.exe" ]; then
		printf '@echo off\r\nrem Plays this build with the dev tools on (docs/debugging.md: K, Shift+End, Insert, Delete...).\r\nstart "" "%%~dp0Contractor.exe" --dev %%*\r\n' > "$dir/Contractor (dev tools).bat"
	else
		echo "Contractor.exe export failed (play.bat still works)"
	fi
fi
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
	if [ -s "$dir/Contractor.exe" ]; then
		echo "Play: double-click Contractor.exe (or \"Contractor (dev tools).bat\" for the dev keys)."
		echo "play.bat runs the same pack through the Voxel Tools editor (dev tools always on)."
	else
		echo "Play: double-click play.bat, then click Play (host a session)."
	fi
	[ -n "$notes" ] && { echo; echo "What to test:"; echo "$notes"; }
} > "$dir/BUILD.txt"
echo "$dir"
