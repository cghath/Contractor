#!/usr/bin/env bash
# Makes a build for testers to download: tools/make_build.sh's folder (contractor.pck, play.bat,
# Contractor.exe when the Voxel Tools release template is there, the .bat launchers, BUILD.txt),
# plus the licenses of everything in it that isn't ours and GET_GODOT.txt, zipped. Used by
# .github/workflows/release.yml (a pushed v* tag) and nightly.yml (dev, every night it moved);
# it runs the same on a PC:
#   GODOT=<voxel editor> [CONTRACTOR_TEMPLATE=<voxel release template>] \
#     tools/ci_build.sh <out dir> <label> [--version 0.7.2] [--no-zip] [--with-editor]
# <out dir> gets <build folder name>.zip (the build folder inside it), unless --no-zip.
# --with-editor also zips the Voxel Tools editor GODOT points at, with the same licenses, as
# <out dir>/GodotVoxel-<release>-windows-editor.zip: unzipped into the build folder, play.bat
# finds it there. The logs parent (export logs, B number) is make_build.sh's usual one
# (CONTRACTOR_TEST_LOGS, else the shared parent; on CI <out dir>/logs when it isn't set). On
# GitHub Actions the step outputs dir, name, zip and editor_zip are set.
#
# Licenses (all allow redistribution with their notices kept): Godot is MIT and lists its own
# third-party parts (tools/engine_licenses.gd writes them from the binary itself); Voxel Tools
# is MIT (Marc Gilleron), with FastNoiseLite and FastNoise2 (MIT), lz4 (BSD-2-Clause),
# meshoptimizer (MIT) and SQLite (public domain) inside it. Those files come from the Voxel
# Tools source at the same release tag (VOXEL_RELEASE, default v1.7).
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:?usage: tools/ci_build.sh <out dir> <label> [--version X.Y.Z] [--no-zip] [--with-editor]}"
label="${2:?usage: tools/ci_build.sh <out dir> <label> [--version X.Y.Z] [--no-zip] [--with-editor]}"
shift 2
version="" zip=1 editor=0
while [ $# -gt 0 ]; do
	case "$1" in
		--version) version="${2#v}"; shift 2 ;;
		--no-zip) zip=0; shift ;;
		--with-editor) editor=1; shift ;;
		*) echo "ci_build: unknown option $1" >&2; exit 2 ;;
	esac
done
: "${GODOT:?ci_build: set GODOT to the Voxel Tools editor}"
voxel="${VOXEL_RELEASE:-v1.7}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
# The logs parent: the usual one on a PC (docs/debugging.md); on CI, <out dir>/logs if not set.
if [ -z "${CONTRACTOR_TEST_LOGS:-}" ] && [ -n "${GITHUB_ACTIONS:-}" ]; then export CONTRACTOR_TEST_LOGS="$out/logs"; fi

# The build. make_build.sh prints the folder last; it fails loudly on its own.
notes=""
[ -n "${GITHUB_ACTIONS:-}" ] && notes="Built by GitHub Actions: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
made="$(VERSION="$version" bash tools/make_build.sh "$label" "$notes" | tee /dev/stderr | tail -n 1)"
dir="$(pwd)/$made"
[ -f "$dir/contractor.pck" ] || { echo "ci_build: make_build.sh gave no build folder ($made)" >&2; exit 1; }
name="$(basename "$dir")"

# Licenses: the engine's from the binary, Voxel Tools' from its source at the release tag.
lic="$dir/licenses"
mkdir -p "$lic/voxel_tools"
win_lic="$(cygpath -m "$lic" 2>/dev/null || echo "$lic")"
"$GODOT" --headless --path . -s res://tools/engine_licenses.gd -- "$win_lic/godot_engine.txt" >"$out/engine_licenses.log" 2>&1 || true
grep -q "Permission is hereby granted" "$lic/godot_engine.txt" 2>/dev/null || {
	echo "ci_build: the engine's licenses weren't written (see $out/engine_licenses.log)" >&2
	cat "$out/engine_licenses.log" >&2
	exit 1
}
raw="https://raw.githubusercontent.com/Zylann/godot_voxel/$voxel"
for f in LICENSE.md:LICENSE.md thirdparty/fast_noise_2/LICENSE:fast_noise_2_LICENSE thirdparty/lz4/LICENSE:lz4_LICENSE thirdparty/meshoptimizer/LICENSE.md:meshoptimizer_LICENSE.md; do
	curl -sSfL --retry 3 -o "$lic/voxel_tools/${f#*:}" "$raw/${f%%:*}" || { echo "ci_build: couldn't fetch $raw/${f%%:*}" >&2; exit 1; }
done
cat >"$lic/README.txt" <<EOF
What's in this build that isn't Contractor's own, and under which license:

- Contractor.exe (when it's here) is the Godot Engine release template with Voxel Tools built in,
  from https://github.com/Zylann/godot_voxel/releases/tag/$voxel. The Voxel Tools editor that
  play.bat runs is from the same release.
- Godot Engine: MIT. Its own notice and its third-party parts: godot_engine.txt (written from
  the engine binary itself).
- Voxel Tools (godot_voxel, Marc Gilleron): MIT, voxel_tools/LICENSE.md. Inside it:
  FastNoise2 (MIT, voxel_tools/fast_noise_2_LICENSE), lz4 (BSD-2-Clause,
  voxel_tools/lz4_LICENSE), meshoptimizer (MIT, voxel_tools/meshoptimizer_LICENSE.md),
  FastNoiseLite (MIT, its notice is in its source header:
  https://github.com/Zylann/godot_voxel/tree/$voxel/thirdparty/fast_noise) and SQLite (public
  domain).
EOF

# How to play without anything installed, or where the editor comes from for play.bat.
{
	echo "How to play this build"
	echo
	if [ -s "$dir/Contractor.exe" ]; then
		echo "Double-click Contractor.exe. Nothing else is needed. \"Contractor (dev tools).bat\" turns the"
		echo "dev keys on; \"Host campaign.bat\" hosts co-op (friends join with your IP, UDP 24680)."
		echo
		echo "play.bat runs the same pack through the Voxel Tools editor instead, which you only need for"
		echo "the editor's own tools. To use it, get the editor (below) and put it beside play.bat."
	else
		echo "This build has no Contractor.exe, so it runs through the Voxel Tools editor: play.bat."
	fi
	echo
	echo "The editor play.bat uses is Godot 4.7.2 with Voxel Tools ${voxel#v} built in (the stock Godot"
	echo "editor won't run this game). play.bat looks for godot.windows.editor.x86_64.exe beside itself, then"
	echo "in %USERPROFILE%\\Downloads\\GodotVoxel_1.7\\, or wherever CONTRACTOR_GODOT points. Get it from:"
	echo "  - the GodotVoxel-${voxel#v}-windows-editor.zip on this build's GitHub release, when there is"
	echo "    one: unzip it into this folder; or"
	echo "  - https://github.com/Zylann/godot_voxel/releases/tag/$voxel"
	echo "    (godot.windows.editor.x86_64.exe.zip): unzip it into this folder."
	echo
	echo "Licenses of the engine and Voxel Tools: the licenses folder."
} | sed 's/$/\r/' >"$dir/GET_GODOT.txt"

# Zips a folder: with its name at the top, or with "flat" its contents at the top (the editor's
# zip, so unzipping it into a build folder puts the exe where play.bat looks). 7-Zip (GitHub's
# Windows runners), zip (Linux), else Python's zipfile.
zip_folder() {
	local zipfile="$1" folder="$2" flat="${3:-}" py="" tool
	[ ! -e "$zipfile" ] || { echo "ci_build: $zipfile is already there" >&2; return 1; }
	if command -v 7z >/dev/null; then tool=7z
	elif command -v zip >/dev/null; then tool=zip
	else
		for p in python python3; do "$p" -c 'import zipfile' 2>/dev/null && { py="$p"; break; }; done
		[ -n "$py" ] || { echo "ci_build: no 7z, zip or python to zip with" >&2; return 1; }
		tool=py
	fi
	(
		if [ -n "$flat" ]; then cd "$folder"; what=(*); else cd "$(dirname "$folder")"; what=("$(basename "$folder")"); fi
		case "$tool" in
			7z) 7z a -tzip -bd -bso0 "$zipfile" "${what[@]}" ;;
			zip) zip -qr "$zipfile" "${what[@]}" ;;
			py) "$py" -m zipfile -c "$zipfile" "${what[@]}" ;;
		esac
	)
	[ -s "$zipfile" ]
}

zipfile=""
if [ "$zip" = 1 ]; then
	zipfile="$out/$name.zip"
	zip_folder "$zipfile" "$dir"
fi
editor_zip=""
if [ "$editor" = 1 ]; then
	stage="$out/GodotVoxel-${voxel#v}-windows-editor"
	mkdir "$stage"
	cp "$GODOT" "$stage/"
	cp -r "$lic" "$stage/licenses"
	editor_zip="$stage.zip"
	zip_folder "$editor_zip" "$stage" flat
fi

echo "ci_build: $dir"
[ -n "$zipfile" ] && echo "ci_build: $zipfile ($(du -h "$zipfile" | cut -f1))"
[ -n "$editor_zip" ] && echo "ci_build: $editor_zip ($(du -h "$editor_zip" | cut -f1))"
# Paths the next steps' actions read (upload-artifact, gh): Windows form on a Windows runner.
winpath() { [ -z "$1" ] || cygpath -m "$1" 2>/dev/null || echo "$1"; }
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "dir=$(winpath "$dir")"
		echo "name=$name"
		echo "zip=$(winpath "$zipfile")"
		echo "editor_zip=$(winpath "$editor_zip")"
	} >>"$GITHUB_OUTPUT"
fi
exit 0
