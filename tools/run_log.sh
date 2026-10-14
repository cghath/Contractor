#!/usr/bin/env bash
# Where every run keeps its logs (Captain, 2026-10-12; docs/debugging.md), shared by
# tools/run_tests.sh (R runs) and tools/make_build.sh (B builds). Sourced, not run:
#   . tools/run_log.sh
#   parent="$(run_log_parent)"        the logs parent, or "" when nothing is kept
#   n="$(run_log_number "$parent")"   the next run number (R/S/B/P share one counter)
#   tail="$(run_log_tail)"            "<branch>-<sha>" of this checkout, for folder names
# The parent is CONTRACTOR_TEST_LOGS if set (=none keeps nothing); else Contractor-test-logs
# beside the main checkout (found through git's common dir, so every worktree shares one parent
# and one counter; a copy outside git keeps its own beside its folder). On CI (GITHUB_ACTIONS)
# nothing is kept unless CONTRACTOR_TEST_LOGS is set. Nothing here ever deletes a log.

# Prints the logs parent (made if missing), or nothing when no logs are kept.
run_log_parent() {
	local root="${CONTRACTOR_TEST_LOGS:-}" common=""
	if [ -z "$root" ] && [ -z "${GITHUB_ACTIONS:-}" ]; then
		common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
		if [ -n "$common" ]; then root="$(cd "$common/../.." && pwd)/Contractor-test-logs"; else root="$(cd .. && pwd)/Contractor-test-logs"; fi
	fi
	[ "$root" = none ] && return 0
	[ -n "$root" ] && mkdir -p "$root" && echo "$root"
	return 0
}

# Takes the next number from <parent>/run_counter.txt and prints it. A short lock (a folder
# beside the counter) keeps two runs starting at once from getting the same number; one left
# behind by a killed run is ignored after about ten seconds.
run_log_number() {
	local parent="$1" lock="$1/run_counter.lock" tries=0 n
	until mkdir "$lock" 2>/dev/null; do
		tries=$((tries + 1))
		[ "$tries" -ge 50 ] && break
		sleep 0.2
	done
	n=$(( $(cat "$parent/run_counter.txt" 2>/dev/null || echo 0) + 1 ))
	echo "$n" >"$parent/run_counter.txt"
	rmdir "$lock" 2>/dev/null || true
	echo "$n"
}

# "<branch>-<sha>" of the checkout (slashes in the branch become dashes). On CI's detached
# checkout of a pull request the branch is the pull request's.
run_log_tail() {
	local branch sha
	branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
	[ "$branch" = HEAD ] && [ -n "${GITHUB_ACTIONS:-}" ] && branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-HEAD}}"
	sha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
	echo "${branch:-nobranch}-$sha" | tr '/' '-'
}
