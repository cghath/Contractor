#!/usr/bin/env bash
# Checks tools/run_tests.sh against a fake engine (no Godot needed): a pass passes; an explicit
# failure, a script error with exit 0, a missing summary, a hang, a failed import and an import
# that reports a script or parse error but exits 0 each fail.
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
		# What the real editor prints when an autoload doesn't compile: the import still exits 0.
		[ "$FAKE_MODE" = import_script_error ] && { echo 'SCRIPT ERROR: Parse Error: Unexpected "Indent" in class body.'; echo "   at: GDScript::reload (res://autoload/broken.gd:3)"; exit 0; }
		[ "$FAKE_MODE" = import_parse_error ] && { echo "ERROR: res://autoload/broken.gd:3 - Parse Error: injected"; exit 0; }
		exit 0
	fi
done
case "$FAKE_MODE" in
	pass|import_script_error|import_parse_error) echo "  [ok] something"; echo "SMOKE TEST PASSED (0 failures)"; exit 0 ;;
	fail) echo "  [FAIL] something"; echo "SMOKE TEST FAILED (1 failures)"; exit 1 ;;
	script_error) echo "SCRIPT ERROR: Parse Error: injected"; exit 0 ;;
	script_error_after_pass) echo "SMOKE TEST PASSED (0 failures)"; echo "SCRIPT ERROR: injected at exit"; exit 0 ;;
	no_summary) echo "  [ok] something"; exit 0 ;;
	hang) sleep 30; exit 0 ;;
	slow) echo "  [ok] started"; sleep 6; echo "SMOKE TEST PASSED (0 failures)"; exit 0 ;;
	world) echo "  [ok] $*"; echo "WORLD TEST PASSED (0 failures)"; exit 0 ;;
esac
FAKE
chmod +x "$fake"
bad=0
# A run stopped part-way (killed, or CI's job cancelled or out of time) still has the logs it
# wrote so far and is a FAIL, never a PASS (its folder may stay RUNNING while the engine it
# started still holds its log open).
FAKE_MODE=slow GODOT="$fake" SUITE_TIMEOUT=10 CONTRACTOR_TEST_LOGS="$dir/kept-killed" tools/run_tests.sh smoke >/dev/null 2>&1 &
runner=$!
for _ in $(seq 50); do
	grep -qs started "$dir/kept-killed"/*/R0001-*/smoke.log && break
	sleep 0.2
done
kill -TERM "$runner" 2>/dev/null
wait "$runner" 2>/dev/null
kept="$(ls -d "$dir/kept-killed"/*/R0001-*/ 2>/dev/null | head -1)"
if [ -n "$kept" ] && [ -f "$kept/smoke.log" ] && grep -q "^stopped before it finished" "$kept/summary.txt" \
		&& grep -q "^result: FAIL" "$kept/summary.txt" && grep -q "^R0001 .* FAIL " "$dir/kept-killed/index.txt" \
		&& [ -z "$(ls -d "$dir/kept-killed"/*/R0001-*-PASS-*/ 2>/dev/null)" ]; then
	echo "ok   killed -> FAIL, its logs kept"
else
	echo "BAD  killed: a run stopped part-way must keep its logs and be a FAIL"
	bad=1
fi
for case in pass:0 fail:1 script_error:1 script_error_after_pass:1 no_summary:1 hang:1 import_fail:1 import_script_error:1 import_parse_error:1; do
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
# An import that reports a broken script fails the run before any suite starts, and says why
# (the engine's exit 0 and the suite's own PASSED line don't make it a pass).
for mode in import_script_error import_parse_error; do
	kept="$(ls -d "$dir/kept-$mode"/*/R0001-*-FAIL-*/ 2>/dev/null | head -1)"
	if [ -n "$kept" ] && grep -q "^import: FAILED: script error" "$kept/summary.txt" && [ ! -f "$kept/smoke.log" ]; then
		echo "ok   $mode -> import failed, no suite ran"
	else
		echo "BAD  $mode: no FAIL run with \"import: FAILED: script error\", or a suite still ran"
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
# On CI the workflow sets CONTRACTOR_TEST_LOGS and uploads it whatever the verdict, so the
# original logs survive: a two-process suite keeps the import, client and host logs, and the
# summary names the CI run and commit. A failure there still raises its annotations.
ci_env=(GITHUB_ACTIONS=true GITHUB_REPOSITORY=x/Contractor GITHUB_RUN_ID=4242 GITHUB_RUN_ATTEMPT=2 GITHUB_REF=refs/heads/ci-check GITHUB_SHA=0123abc)
env "${ci_env[@]}" FAKE_MODE=world GODOT="$fake" SUITE_TIMEOUT=10 CONTRACTOR_TEST_LOGS="$dir/kept-ci" tools/run_tests.sh world >/dev/null 2>&1
got=$?
kept="$(ls -d "$dir/kept-ci"/*/R0001-*-PASS-*/ 2>/dev/null | head -1)"
if [ "$got" -eq 0 ] && [ -n "$kept" ] && [ -f "$kept/import.log" ] && grep -q -- "--world-join" "$kept/world.log" \
		&& grep -q -- "--world-host" "$kept/world-host.log" && grep -q "^CI: x/Contractor run 4242 attempt 2, refs/heads/ci-check, commit 0123abc" "$kept/summary.txt"; then
	echo "ok   CI world -> import, client and host logs kept, with the CI run"
else
	echo "BAD  CI world: exited $got; no PASS run keeping import.log, world.log, world-host.log and the CI line in $dir/kept-ci"
	bad=1
fi
out="$(env "${ci_env[@]}" FAKE_MODE=fail GODOT="$fake" SUITE_TIMEOUT=2 CONTRACTOR_TEST_LOGS="$dir/kept-ci-fail" tools/run_tests.sh smoke 2>&1)"
if echo "$out" | grep -q "^::error title=smoke::FAILED" && echo "$out" | grep -q "^::error title=smoke failed check::" \
		&& [ -f "$(ls -d "$dir/kept-ci-fail"/*/R0001-*-FAIL-*/ 2>/dev/null | head -1)/smoke.log" ]; then
	echo "ok   CI fail -> annotations raised, logs kept"
else
	echo "BAD  CI fail: no ::error annotations, or no kept FAIL run with smoke.log"
	bad=1
fi
wf=.github/workflows/tests.yml
logs_path="$(grep -m1 'CONTRACTOR_TEST_LOGS:' "$wf" | sed 's/.*CONTRACTOR_TEST_LOGS: *//')"
if [ -n "$logs_path" ] && grep -A2 'if: always()' "$wf" | grep -q 'uses: actions/upload-artifact' && grep -qF "path: $logs_path" "$wf"; then
	echo "ok   $wf keeps CONTRACTOR_TEST_LOGS ($logs_path) as an artifact on every verdict"
else
	echo "BAD  $wf: the suite step must set CONTRACTOR_TEST_LOGS and an 'if: always()' upload-artifact step keep that path"
	bad=1
fi
[ "$bad" -eq 0 ] && echo "RUNNER CHECK PASSED" || echo "RUNNER CHECK FAILED"
exit $bad
