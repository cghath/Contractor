#!/usr/bin/env bash
# Inert gh/git doubles: no account, network, tag or release is changed.
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/run_log.sh
root="$(run_log_parent)"
[ -n "$root" ] || root="${RUNNER_TEMP:-/tmp}/contractor-test-logs"
id="$(printf 'S%04d' "$(run_log_number "$root")")"
day="$root/$(date +%Y-%m-%d)"
time="$(date +%H%M%S)"
keep="$day/$id-$time-RUNNING-publish-release-$(git rev-parse --short HEAD)"
mkdir -p "$keep/bin"
finish() {
	code=$?
	verdict=PASS
	[ "$code" -eq 0 ] || verdict=FAIL
	mv "$keep" "${keep/RUNNING/$verdict}"
	echo "$id $(date +%Y-%m-%d) $time $verdict publish-release" >>"$root/index.txt"
	echo "$id: $verdict (${keep/RUNNING/$verdict})"
}
trap finish EXIT
export RELEASE_TEST_KEEP="$keep"
cat >"$keep/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RELEASE_TEST_KEEP/calls-$RELEASE_TEST_MODE.log"
if [ "$1 $2" = 'release list' ]; then
	case "$RELEASE_TEST_MODE" in
		public) echo false ;;
		draft) echo true ;;
		missing) : ;;
		error) echo 'authentication/network failed' >&2; exit 1 ;;
		malformed) echo unknown ;;
	esac
fi
FAKE
cat >"$keep/bin/git" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
chmod +x "$keep/bin/gh" "$keep/bin/git"
export PATH="$(cd "$keep/bin" && pwd):$PATH"
touch "$keep/build.zip"
for mode in public draft missing error malformed; do
	export RELEASE_TEST_MODE="$mode"
	status=0
	bash tools/publish_release.sh v0.4.36 "$keep/build.zip" >"$keep/$mode.log" 2>&1 || status=$?
	case "$mode" in
		public|error|malformed)
			[ "$status" -ne 0 ]
			[ -f "$keep/calls-$mode.log" ]
			! grep -Eq '^release (upload|create)' "$keep/calls-$mode.log"
			;;
		draft)
			[ "$status" -eq 0 ]
			grep -q '^release upload .*--clobber$' "$keep/calls-$mode.log"
			! grep -q '^release create' "$keep/calls-$mode.log"
			;;
		missing)
			[ "$status" -eq 0 ]
			grep -q '^release create .*--draft' "$keep/calls-$mode.log"
			! grep -q '^release upload' "$keep/calls-$mode.log"
			;;
	esac
	echo "PASS: $mode" | tee -a "$keep/summary.txt"
done
