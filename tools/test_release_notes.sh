#!/usr/bin/env bash
# Checks tools/release_notes.sh on a throwaway repo (no tag or release anywhere else is touched):
# a version's section with 600 KB of older sections after it (the SIGPIPE case that once ended
# the script with no notes), a section past GitHub's limit (cut with a pointer), a version with
# no section (the commits since the last tag), and a commit with no CHANGELOG.md at all.
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/run_log.sh
root="$(run_log_parent)"
[ -n "$root" ] || root="${RUNNER_TEMP:-/tmp}/contractor-test-logs"
id="$(printf 'S%04d' "$(run_log_number "$root")")"
day="$root/$(date +%Y-%m-%d)"
time="$(date +%H%M%S)"
keep="$day/$id-$time-RUNNING-release-notes-$(git rev-parse --short HEAD)"
mkdir -p "$keep/repo/tools"
finish() {
	code=$?
	verdict=PASS
	[ "$code" -eq 0 ] || verdict=FAIL
	rm -rf "$keep/repo"
	mv "$keep" "${keep/RUNNING/$verdict}"
	echo "$id $(date +%Y-%m-%d) $time $verdict release-notes" >>"$root/index.txt"
	echo "$id: $verdict (${keep/RUNNING/$verdict})"
}
trap finish EXIT
cp tools/release_notes.sh "$keep/repo/tools/"
repo="$keep/repo"
g() { git -C "$repo" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false -c core.autocrlf=false "$@"; }
g init -q
g commit -q --allow-empty -m "first commit"
g tag v0.7.0
# Unreleased, a small 0.7.2, a 0.7.1 of ~150 KB, then ~450 KB of older sections and the links.
{
	printf '# Changelog\n\n## [Unreleased]\n\n- not released yet\n\n'
	printf '## [0.7.2] - 2026-10-31\n\n- SECTION-0.7.2 first line\n- SECTION-0.7.2 last line\n\n'
	printf '## [0.7.1] - 2026-10-30\n\n'
	for i in $(seq 1 1500); do printf -- '- SECTION-0.7.1 line %04d padding padding padding padding padding padding padding padding\n' "$i"; done
	for v in $(seq 60 -1 1); do
		printf '\n## [0.6.%d] - 2026-10-01\n\n' "$v"
		for i in $(seq 1 80); do printf -- '- older line %d padding padding padding padding padding padding padding padding\n' "$i"; done
	done
	printf '\n[Unreleased]: https://example.invalid/compare\n[0.7.2]: https://example.invalid/0.7.2\n'
} >"$repo/CHANGELOG.md"
[ "$(wc -c <"$repo/CHANGELOG.md")" -gt 500000 ]
g add CHANGELOG.md
g commit -q -m "a changelog"
g commit -q --allow-empty -m "a commit after the changelog"
notes() { bash "$repo/tools/release_notes.sh" "$@"; }
# set -e ignores a negated grep, so a line that must not be there fails by hand.
absent() {
	if grep -q "$1" <<<"$out"; then
		echo "FAIL: '$1' is in the notes" >&2
		exit 1
	fi
}

# A small section with old ones after it: exit 0, the whole section and nothing past it.
out="$(notes v0.7.2 HEAD)"
printf '%s\n' "$out" >"$keep/v0.7.2.md"
grep -q '^## \[0.7.2\] - 2026-10-31$' <<<"$out"
grep -q 'SECTION-0.7.2 last line' <<<"$out"
absent 'SECTION-0.7.1\|older line\|example.invalid'
echo "PASS: a section followed by 600 KB of older ones" | tee -a "$keep/summary.txt"

# Past 100,000 characters: cut, with the pointer.
out="$(notes v0.7.1 HEAD)"
printf '%s\n' "$out" >"$keep/v0.7.1.md"
grep -q '^(cut here; the rest is in CHANGELOG.md at v0.7.1)$' <<<"$out"
absent 'older line'
echo "PASS: a long section is cut" | tee -a "$keep/summary.txt"

# No section: the commits since v0.7.0.
out="$(notes v0.9.9 HEAD)"
printf '%s\n' "$out" >"$keep/v0.9.9.md"
grep -q '^the commits since v0.7.0' <<<"$out"
grep -q '^- [0-9a-f]* a commit after the changelog$' <<<"$out"
grep -q '^- [0-9a-f]* a changelog$' <<<"$out"
echo "PASS: no section, the commits since the last tag" | tee -a "$keep/summary.txt"

# No CHANGELOG.md at the ref: the commits stand in, not a failure.
out="$(notes v0.7.2 v0.7.0)"
printf '%s\n' "$out" >"$keep/no-changelog.md"
grep -q '^## What changed$' <<<"$out"
grep -q '^- [0-9a-f]* first commit$' <<<"$out"
echo "PASS: no CHANGELOG.md at the ref" | tee -a "$keep/summary.txt"
