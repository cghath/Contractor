#!/usr/bin/env bash
# Checks tools/run_tests.sh against a fake engine (no Godot needed): a pass passes; an explicit
# failure, a script error with exit 0, a missing summary, a hang and a failed import each fail.
#   tools/test_runner_check.sh      (prints each case; exits non-zero if the runner misjudges one)
set -u
cd "$(dirname "$0")/.."
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
fake="$dir/fake-engine.sh"
cat >"$fake" <<'FAKE'
#!/usr/bin/env bash
# Fake Godot for tools/test_runner_check.sh: behaves as FAKE_MODE says.
for a in "$@"; do
	if [ "$a" = --import ]; then
		[ "$FAKE_MODE" = import_fail ] && { echo "ERROR: import broke"; exit 1; }
		exit 0
	fi
done
case "$FAKE_MODE" in
	pass) echo "  [ok] something"; echo "SMOKE TEST PASSED (0 failures)"; exit 0 ;;
	fail) echo "  [FAIL] something"; echo "SMOKE TEST FAILED (1 failures)"; exit 1 ;;
	script_error) echo "SCRIPT ERROR: Parse Error: injected"; exit 0 ;;
	script_error_after_pass) echo "SMOKE TEST PASSED (0 failures)"; echo "SCRIPT ERROR: injected at exit"; exit 0 ;;
	no_summary) echo "  [ok] something"; exit 0 ;;
	hang) sleep 30; exit 0 ;;
esac
FAKE
chmod +x "$fake"
bad=0
for case in pass:0 fail:1 script_error:1 script_error_after_pass:1 no_summary:1 hang:1 import_fail:1; do
	mode="${case%%:*}"; want="${case##*:}"
	out="$(FAKE_MODE="$mode" GODOT="$fake" SUITE_TIMEOUT=2 CONTRACTOR_TEST_LOGS="$dir/kept-$mode" tools/run_tests.sh smoke 2>&1)"
	got=$?
	[ "$got" -ne 0 ] && got=1
	if [ "$got" = "$want" ]; then
		echo "ok   $mode -> $([ "$want" = 0 ] && echo pass || echo fail)"
	else
		echo "BAD  $mode: runner exited $got, expected $want"
		echo "$out" | sed 's/^/     /'
		bad=1
	fi
done
# Every run's logs are kept (Captain, 2026-10-12): numbered, by date, PASS or FAIL in the name;
# the cleanup never takes the kept copy.
for case in pass:PASS fail:FAIL import_fail:FAIL; do
	mode="${case%%:*}"; want="${case##*:}"
	kept="$(ls -d "$dir/kept-$mode"/*/R0001-*-"$want"-*/ 2>/dev/null | head -1)"
	if [ -n "$kept" ] && [ -f "$kept/import.log" ] && grep -q "^result: $want" "$kept/summary.txt" \
			&& grep -q "^R0001 .* $want " "$dir/kept-$mode/index.txt" && [ "$(cat "$dir/kept-$mode/run_counter.txt")" = 1 ]; then
		echo "ok   $mode -> logs kept as $(basename "$kept")"
	else
		echo "BAD  $mode: no kept run R0001 marked $want in $dir/kept-$mode"
		bad=1
	fi
done
[ "$bad" -eq 0 ] && echo "RUNNER CHECK PASSED" || echo "RUNNER CHECK FAILED"
exit $bad
