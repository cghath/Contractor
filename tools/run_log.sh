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

# Takes the next number from <parent>/run_counter.txt and prints it. The read and the write
# happen under a lock: a folder beside the counter (run_counter.lock; mkdir either makes it or
# fails, so only one run holds it), which SessionLog._next_number takes the same way, so R, S,
# B and P numbers never repeat (two runs in the same second both got R0232). A lock older than
# RUN_LOCK_STALE_S (10 s; it's held for milliseconds) was left by a killed run: it's moved
# aside (a rename, so only one waiter takes it over) and removed. After RUN_LOCK_WAIT_S (30 s)
# of waiting on a live lock the run goes on without it and says so.
RUN_LOCK_STALE_S="${RUN_LOCK_STALE_S:-10}"
RUN_LOCK_WAIT_S="${RUN_LOCK_WAIT_S:-30}"
run_log_lock() {
	local lock="$1" start age mtime
	start=$(date +%s)
	until mkdir "$lock" 2>/dev/null; do
		# GNU stat -c, else BSD stat -f. Only a number counts: when the lock is let go and taken
		# again between the two, GNU's stat -f prints a filesystem report ("File: ...") instead.
		mtime=$(stat -c %Y "$lock" 2>/dev/null) || mtime=$(stat -f %m "$lock" 2>/dev/null) || mtime=""
		case "$mtime" in ''|*[!0-9]*) mtime="" ;; esac
		if [ -n "$mtime" ]; then
			age=$(( $(date +%s) - mtime ))
			if [ "$age" -ge "$RUN_LOCK_STALE_S" ] && mv "$lock" "$lock.stale.$$" 2>/dev/null; then
				rmdir "$lock.stale.$$" 2>/dev/null
				echo "run_log: took over a stale lock ($lock, ${age} s old)" >&2
				continue
			fi
		fi
		if [ $(( $(date +%s) - start )) -ge "$RUN_LOCK_WAIT_S" ]; then
			echo "run_log: $lock held for ${RUN_LOCK_WAIT_S} s; going on without it" >&2
			return 1
		fi
		sleep 0.1
	done
	return 0
}

run_log_number() {
	local parent="$1" lock="$1/run_counter.lock" n locked=0
	run_log_lock "$lock" && locked=1
	n="$(tr -dc 0-9 2>/dev/null <"$parent/run_counter.txt")"
	n=$(( 10#${n:-0} + 1 ))
	echo "$n" >"$parent/run_counter.txt"
	[ "$locked" = 1 ] && rmdir "$lock" 2>/dev/null
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
