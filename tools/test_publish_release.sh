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
# Never the real gh: if the double isn't the one found, stop before anything runs. No usable
# credentials or config either, and a tag no real release can have.
[ "$(command -v gh)" = "$(cd "$keep/bin" && pwd)/gh" ] || { echo "FAIL: gh isn't the inert double" >&2; exit 1; }
export GH_TOKEN=inert-test GH_CONFIG_DIR="$keep/gh-config"
tag=v0.0.0-inert-test
# A call the case must not make fails the check (set -e ignores a negated grep).
never() {
	if grep -Eq "$1" "$keep/calls-$mode.log"; then
		echo "FAIL: $mode made a call it must not: $1" >&2
		exit 1
	fi
}
touch "$keep/build.zip"
for mode in public draft missing error malformed; do
	export RELEASE_TEST_MODE="$mode"
	status=0
	bash tools/publish_release.sh "$tag" "$keep/build.zip" >"$keep/$mode.log" 2>&1 || status=$?
	case "$mode" in
		public|error|malformed)
			[ "$status" -ne 0 ]
			[ -f "$keep/calls-$mode.log" ]
			never '^release (upload|create)'
			;;
		draft)
			[ "$status" -eq 0 ]
			grep -q '^release upload .*--clobber$' "$keep/calls-$mode.log"
			never '^release create'
			;;
		missing)
			[ "$status" -eq 0 ]
			grep -q '^release create .*--draft' "$keep/calls-$mode.log"
			never '^release upload'
			;;
	esac
	echo "PASS: $mode" | tee -a "$keep/summary.txt"
done
