#!/usr/bin/env bash
# Prints the release notes for a version tag (.github/workflows/release.yml): how to play the
# build, then CHANGELOG.md's section for that version ("## [0.7.2] - <date>" or "## [v0.7.2]").
# When CHANGELOG.md has no section for it yet (most builds so far kept everything under
# Unreleased), the commits since the previous v* tag stand in, one line each, so the notes are
# never empty.
#   tools/release_notes.sh v0.7.2 [<ref>]      <ref>: the commit to read (default: the tag, else HEAD)
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?usage: tools/release_notes.sh <tag> [<ref>]}"
ref="${2:-}"
[ -n "$ref" ] || { git rev-parse -q --verify "refs/tags/$tag" >/dev/null && ref="$tag" || ref=HEAD; }
version="${tag#v}"
voxel="${VOXEL_RELEASE:-v1.7}"

cat <<EOF
**Contractor $tag**, a playtest build for Windows (Godot 4.7.2 with Voxel Tools ${voxel#v}).

**To play:** download the \`contractor-$tag-*.zip\` below, unzip it anywhere and double-click
\`Contractor.exe\` (\`Contractor (dev tools).bat\` for the dev keys). To host co-op, use
\`Host campaign.bat\`; friends join with the host's IP (UDP 24680). If there's no
\`Contractor.exe\` in the zip, unzip the \`GodotVoxel-*-windows-editor.zip\` below into the same
folder and double-click \`play.bat\`. \`BUILD.txt\` says which commit this is; the engine's and
Voxel Tools' licenses are in the zip's \`licenses\` folder.

EOF

# The section: from its heading to the next "## [" heading (or the link list at the end).
section="$(git show "$ref:CHANGELOG.md" 2>/dev/null | awk -v v="$version" '
	BEGIN { a = "## [" v "]"; b = "## [v" v "]" }
	index($0, a) == 1 || index($0, b) == 1 { on = 1; print; next }
	on && /^## \[/ { exit }
	on && /^\[[^]]+\]: / { exit }
	on { print }
')"
if [ -n "$section" ]; then
	# Release notes stop at 125,000 characters on GitHub; a long section is cut with a pointer.
	if [ "${#section}" -gt 100000 ]; then
		printf '%s\n' "${section:0:100000}"
		echo
		echo "(cut here; the rest is in CHANGELOG.md at $tag)"
	else
		printf '%s\n' "$section"
	fi
else
	prev="$(git describe --tags --abbrev=0 --match 'v*' "$ref^" 2>/dev/null || true)"
	echo "## What changed"
	echo
	echo "CHANGELOG.md has no section for $version yet (it's all still under Unreleased), so here are"
	if [ -n "$prev" ]; then
		echo "the commits since $prev (newest first, the first line of each, cut at 200 characters):"
		range="$prev..$ref"
	else
		echo "the last commits (newest first, the first line of each, cut at 200 characters):"
		range="$ref"
	fi
	echo
	total="$(git rev-list --no-merges --count "$range")"
	git log --no-merges --format='%h %s' -n 150 "$range" | cut -c1-200 | sed 's/^/- /'
	[ "$total" -gt 150 ] && echo "- ... and $((total - 150)) older commits"
fi
exit 0
