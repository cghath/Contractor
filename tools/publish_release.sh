#!/usr/bin/env bash
# Puts a finished build on GitHub as a DRAFT release (Captain, 2026-10-15: "share builds via
# GitHub releases"). Nothing goes public until someone presses Publish on the draft.
#
#   tools/publish_release.sh v0.4.25 B:/Contractor/builds/Contractor-v0.4.25-B1400-abc1234.zip ["notes"]
#
# Needs the gh CLI signed in with push rights to the repo. The tag must already be pushed
# (make_build.sh's usual flow: push dev + tag). The zip is the one make_build.sh made (with
# "Host campaign.bat" / "Host NEW campaign.bat" inside).
set -euo pipefail
tag="${1:?usage: publish_release.sh <tag> <build zip> [notes]}"
zip="${2:?usage: publish_release.sh <tag> <build zip> [notes]}"
notes="${3:-Playtest build $tag. Unzip, run play.bat (or Contractor.exe); hosts use "Host campaign.bat".}"
[ -f "$zip" ] || { echo "no such zip: $zip" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh CLI not found" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "tag $tag isn't here (fetch or make it first)" >&2; exit 1; }
# Read failures (including authentication and network errors) must stop before any mutation.
release_state="$(gh release list --limit 1000 --json tagName,isDraft --jq ".[] | select(.tagName == \"$tag\") | .isDraft")"
if [ "$release_state" = false ]; then
	echo "release $tag is public; this tool only updates drafts" >&2
	exit 1
elif [ "$release_state" = true ]; then
	gh release upload "$tag" "$zip" --clobber
	echo "uploaded $(basename "$zip") to the existing draft $tag"
elif [ -z "$release_state" ]; then
	gh release create "$tag" "$zip" --draft --title "Contractor $tag" --notes "$notes"
	echo "draft release $tag made with $(basename "$zip"): publish it on GitHub when ready"
else
	echo "could not verify the release state for $tag" >&2
	exit 1
fi
