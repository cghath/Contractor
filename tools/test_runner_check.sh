#!/usr/bin/env bash
# Checks tools/run_tests.sh against a fake engine (no Godot needed): a pass passes; an explicit
# failure, a script error with exit 0, a missing summary, a hang, a failed import and an import
# that reports a script or parse error but exits 0 each fail; a stopped run is a FAIL with its
# logs; CI keeps and uploads every log. And tools/make_build.sh against a fake exporter: every
# build gets its own numbered folder and kept export log, and a failed export fails it. And the
# run counter: runs numbered at once never share a number; a killed run's lock is taken over.
#   tools/test_runner_check.sh      (prints each case; exits non-zero if the runner misjudges one)
set -u
cd "$(dirname "$0")/.."
bash tools/check_ci_suites.sh || exit 1
. tools/run_log.sh
check_root="$(run_log_parent)"
[ -n "$check_root" ] || check_root="${RUNNER_TEMP:-/tmp}/contractor-test-logs"
check_id="$(printf 'S%04d' "$(run_log_number "$check_root")")"
check_day="$check_root/$(date +%Y-%m-%d)"
check_time="$(date +%H%M%S)"
dir="$check_day/$check_id-$check_time-RUNNING-runner-check-$(git rev-parse --short HEAD)"
mkdir -p "$dir"
# Normalize a Windows drive path for PATH/shebangs in the fake engine and exporter.
dir="$(cd "$dir" && pwd)"
exec 3>&1
exec > >(tee "$dir/check.log") 2>&1
log_pid=$!
finish_check() {
	code=$?
	verdict=PASS
	[ "$code" -eq 0 ] || verdict=FAIL
	# Close tee before renaming its directory (Windows locks an open output file).
	exec 1>&3 2>&3
	wait "$log_pid"
	mv "$dir" "${dir/RUNNING/$verdict}" || exit 1
	echo "$check_id $(date +%Y-%m-%d) $check_time $verdict runner-check" >>"$check_root/index.txt"
	echo "$check_id: $verdict (${dir/RUNNING/$verdict})"
}
trap finish_check EXIT
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
# tools/make_build.sh, in a copy of the tools outside git with a fake exporter: every build gets
# its own numbered folder (two builds never overwrite each other), a line in index.txt and its
# exporter output kept as B<number>-<time>-export.log; a failed export fails loudly.
proj="$dir/proj"
mkdir -p "$proj/tools"
cp tools/make_build.sh tools/run_log.sh "$proj/tools/"
touch "$proj/project.godot" "$dir/fake-template.exe"
exporter="$dir/fake-exporter.sh"
cat >"$exporter" <<'FAKE'
#!/usr/bin/env bash
# Fake Godot exporter for tools/test_runner_check.sh: behaves as FAKE_MODE says.
echo "fake exporter: $*"
while [ $# -gt 0 ]; do
	case "$1" in
		--export-pack|--export-release)
			kind="$1"; out="$3"
			[ "$FAKE_MODE" = pack_fail ] && [ "$kind" = --export-pack ] && { echo "ERROR: pack export broke"; exit 1; }
			[ "$FAKE_MODE" = exe_fail ] && [ "$kind" = --export-release ] && { echo "ERROR: exe export broke"; exit 1; }
			[ "$FAKE_MODE" = script_error ] && echo "SCRIPT ERROR: Parse Error: injected"
			echo "built by $kind" >"$out"
			exit 0 ;;
	esac
	shift
done
FAKE
chmod +x "$exporter"
blogs="$dir/kept-build"
build() {  # mode, template, label
	FAKE_MODE="$1" GODOT="$exporter" CONTRACTOR_TEMPLATE="$2" CONTRACTOR_TEST_LOGS="$blogs" "$proj/tools/make_build.sh" "$3" "check notes" >"$dir/build-$3.out" 2>&1
}
build ok "$dir/no-template.exe" same && build ok "$dir/no-template.exe" same
got=$?
b1="$(ls -d "$proj"/builds/contractor-*-B0001-same-*/ 2>/dev/null | head -1)"
b2="$(ls -d "$proj"/builds/contractor-*-B0002-same-*/ 2>/dev/null | head -1)"
if [ "$got" -eq 0 ] && [ -n "$b1" ] && [ -n "$b2" ] && [ "$b1" != "$b2" ] && [ "$(tail -n1 "$dir/build-same.out")/" = "builds/$(basename "$b2")/" ] \
		&& grep -q "built by --export-pack" "$b1/contractor.pck" && [ -f "$b1/play.bat" ] && [ -f "$b2/play.bat" ] \
		&& grep -q "build B0001" "$b1/BUILD.txt" && grep -q "build B0002" "$b2/BUILD.txt" && grep -q "check notes" "$b2/BUILD.txt" \
		&& grep -q 'call "%~dp0play.bat" --dev %\*' "$b1/Contractor (dev tools).bat" && [ ! -f "$b1/Contractor.exe" ] \
		&& [ "$(grep -c "^B000[12] .* PASS .* build same -> builds/contractor-" "$blogs/index.txt")" = 2 ] \
		&& grep -q "fake exporter: .*--export-pack Windows Desktop" "$blogs"/*/B0002-*-export.log && grep -q "^result: PASS" "$blogs"/*/B0001-*-export.log; then
	echo "ok   make_build twice -> B0001 and B0002 in their own folders, logs and index lines kept"
else
	echo "BAD  make_build twice: exited $got; expected two numbered builds (pack, play.bat, BUILD.txt, dev tools .bat calling play.bat --dev), two PASS index lines and their export logs"
	sed 's/^/     /' "$dir/build-same.out"
	bad=1
fi
build ok "$dir/fake-template.exe" exe
got=$?
b="$(ls -d "$proj"/builds/contractor-*-B0003-exe-*/ 2>/dev/null | head -1)"
if [ "$got" -eq 0 ] && [ -n "$b" ] && grep -q "built by --export-release" "$b/Contractor.exe" && [ -f "$b/play.bat" ] \
		&& grep -q 'Contractor.exe" --dev' "$b/Contractor (dev tools).bat" && grep -q "^== Contractor.exe: exit 0" "$blogs"/*/B0003-*-export.log; then
	echo "ok   make_build with the release template -> Contractor.exe, its dev tools .bat, and the exe export in the log"
else
	echo "BAD  make_build with the release template: exited $got"
	sed 's/^/     /' "$dir/build-exe.out"
	bad=1
fi
n=4
for case in pack_fail:"ERROR: pack export broke" exe_fail:"ERROR: exe export broke" script_error:"SCRIPT ERROR"; do
	mode="${case%%:*}"; text="${case#*:}"
	build "$mode" "$dir/fake-template.exe" "$mode"
	got=$?
	id="$(printf 'B%04d' "$n")"; n=$((n + 1))
	b="$(ls -d "$proj"/builds/contractor-*-"$id-$mode"-*/ 2>/dev/null | head -1)"
	if [ "$got" -ne 0 ] && grep -q "BUILD $id FAILED" "$dir/build-$mode.out" && grep -q "^$id .* FAIL .* build $mode " "$blogs/index.txt" \
			&& grep -qF "$text" "$blogs"/*/"$id"-*-export.log && grep -q "^result: FAIL" "$blogs"/*/"$id"-*-export.log && [ -f "$b/FAILED.txt" ]; then
		echo "ok   make_build $mode -> fails loudly, FAIL in index.txt, the exporter's error kept in $id's log"
	else
		echo "BAD  make_build $mode: exited $got; expected a loud failure, a FAIL index line and the exporter's \"$text\" in the log"
		sed 's/^/     /' "$dir/build-$mode.out"
		bad=1
	fi
done
b="$(ls -d "$proj"/builds/contractor-*-B0005-exe_fail-*/ 2>/dev/null | head -1)"
[ -n "$b" ] && [ -f "$b/play.bat" ] || { echo "BAD  make_build exe_fail: play.bat should still be made when only the exe fails"; bad=1; }
# The run counter (run_log_number, shared with SessionLog): runs started at the same moment each
# get their own number (two in the same second both got R0232), and a lock left by a killed run
# is taken over instead of holding everyone up.
cdir="$dir/counter"
mkdir -p "$cdir"
for k in $(seq 12); do
	( . tools/run_log.sh; run_log_number "$cdir" >"$cdir/got-$k" ) &
done
wait
got="$(cat "$cdir"/got-* | sort -n | tr '\n' ' ')"
if [ "$got" = "$(seq 12 | tr '\n' ' ')" ] && [ "$(cat "$cdir/run_counter.txt")" = 12 ] && [ ! -d "$cdir/run_counter.lock" ]; then
	echo "ok   12 runs numbered at once -> 1 to 12, none twice"
else
	echo "BAD  12 runs numbered at once got: $got (counter $(cat "$cdir/run_counter.txt"))"
	bad=1
fi
mkdir "$cdir/run_counter.lock"
touch -d "1 minute ago" "$cdir/run_counter.lock"
start=$(date +%s)
n="$(. tools/run_log.sh; run_log_number "$cdir" 2>/dev/null)"
if [ "$n" = 13 ] && [ $(( $(date +%s) - start )) -le 5 ] && [ ! -d "$cdir/run_counter.lock" ] && [ -z "$(ls -d "$cdir"/run_counter.lock.stale.* 2>/dev/null)" ]; then
	echo "ok   a stale lock (a killed run's) is taken over: the next run is 13 at once"
else
	echo "BAD  stale lock: got \"$n\" after $(( $(date +%s) - start )) s"
	bad=1
fi
mkdir "$cdir/run_counter.lock"  # a live lock: the run waits for it
( sleep 1; rmdir "$cdir/run_counter.lock" ) &
start=$(date +%s)
n="$(. tools/run_log.sh; run_log_number "$cdir")"
wait
if [ "$n" = 14 ] && [ $(( $(date +%s) - start )) -ge 1 ]; then
	echo "ok   a live lock is waited for: 14 once it's let go"
else
	echo "BAD  live lock: got \"$n\" after $(( $(date +%s) - start )) s"
	bad=1
fi
[ "$bad" -eq 0 ] && echo "RUNNER CHECK PASSED" || echo "RUNNER CHECK FAILED"
exit $bad
