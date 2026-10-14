#!/usr/bin/env bash
# Co-op soak: a stand-in for a group playtest on one machine. Starts one headless host and up to
# three headless clients (tests/coop_soak.tscn, each its own process), a UDP relay
# (tools/coop_relay.py) between each client and the host, lets the bots play contracts together
# for the asked time, then writes the report (tools/coop_soak_report.py).
#
#   GODOT=<Voxel Tools editor exe> tools/coop_soak.sh                      # 10 min, lossy link
#   GODOT=... tools/coop_soak.sh --minutes 30 --mode lossy --latency 100 --jitter 30 --loss 1.5
#   GODOT=... tools/coop_soak.sh --minutes 10 --mode clean                 # relays forward only
#
# Options: --minutes N (10), --mode lossy|clean (lossy), --latency MS (100, one-way),
# --jitter MS (30), --loss PCT (1.5), --clients 1-3 (3), --port P (25347: the host; the relays
# take P+1..P+3), --no-late (client 3 joins at the start), --tag TOPIC (folder name).
# Client 1 accepts the contracts and confirms extraction, client 2 picks the squad and leaves
# and rejoins in the first fight, client 3 joins late once the first deployment is under way.
#
# Logs (Captain's rule, docs/debugging.md): an S run in the shared logs parent,
#   <parent>/<date>/S<number>-<HHMMSS>-<PASS|FAIL>-coop-soak-<mode>-<branch>-<sha>/
#     report.md  divergences.jsonl  config.json  phase.json  relay<N>.jsonl  relay<N>.log
#     host/ client1/ ...: stdout.log (all engine output), bot.log, snapshots.jsonl, metrics.jsonl,
#                         replay.jsonl (tests/coop_replay.gd plays it back), exit_code
#     sessions/: each instance's SessionLog folder (CONTRACTOR_SESSION_LOG=1)
# A line goes to index.txt. Nothing here deletes a log. Exits 0 on PASS.
set -u
cd "$(dirname "$0")/.."
. tools/run_log.sh
GODOT="${GODOT:-godot}"
PYTHON="${PYTHON:-}"
if [ -z "$PYTHON" ]; then
	for p in "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe" python3 python; do
		if "$p" -c "import sys" >/dev/null 2>&1; then PYTHON="$p"; break; fi
	done
fi
MINUTES=10 MODE=lossy LATENCY=100 JITTER=30 LOSS=1.5 CLIENTS=3 PORT=25347 LATE=1 TAG=""
while [ $# -gt 0 ]; do
	case "$1" in
		--minutes) MINUTES="$2"; shift ;;
		--mode) MODE="$2"; shift ;;
		--latency) LATENCY="$2"; shift ;;
		--jitter) JITTER="$2"; shift ;;
		--loss) LOSS="$2"; shift ;;
		--clients) CLIENTS="$2"; shift ;;
		--port) PORT="$2"; shift ;;
		--no-late) LATE=0 ;;
		--tag) TAG="$2"; shift ;;
		*) echo "unknown option $1"; exit 2 ;;
	esac
	shift
done
if [ "$MODE" = clean ]; then LATENCY=0; JITTER=0; LOSS=0; fi
DURATION=$(( MINUTES * 60 ))

parent="$(run_log_parent)"
[ -z "$parent" ] && parent="$(pwd)/../Contractor-test-logs"
mkdir -p "$parent"
run_id="$(printf 'S%04d' "$(run_log_number "$parent")")"
tail_name="coop-soak-${TAG:-$MODE}-$(run_log_tail)"
day="$parent/$(date +%Y-%m-%d)"
start_time="$(date +%H%M%S)"
run="$day/$run_id-$start_time-RUNNING-$tail_name"
mkdir -p "$run/host" "$run/sessions"
win() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
echo "co-op soak $run_id: $MINUTES min, $MODE, $CLIENTS clients, logs in $run"
cat >"$run/config.json" <<EOF
{"run_id": "$run_id", "mode": "$MODE", "minutes": $MINUTES, "latency_ms": $LATENCY, "jitter_ms": $JITTER, "loss_pct": $LOSS,
 "clients": $CLIENTS, "port": $PORT, "late": $LATE, "branch_sha": "$(run_log_tail)", "started": "$(date '+%Y-%m-%d %H:%M:%S')",
 "godot": "$(win "$GODOT")"}
EOF

pids=()
cleanup() {
	for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null; done
	# Killing a subshell doesn't reach the Godot it started: each instance wrote its own pid.
	for f in "$run"/*/pid; do
		[ -f "$f" ] || continue
		[ -f "$(dirname "$f")/exit_code" ] && continue  # it quit by itself: the pid may be someone else's now
		if command -v taskkill >/dev/null 2>&1; then taskkill //F //PID "$(cat "$f")" >/dev/null 2>&1
		else kill "$(cat "$f")" 2>/dev/null; fi
	done
}
trap cleanup EXIT

# One Godot instance: role, bot number, port it talks to, extra args. Its exit code goes to
# <its folder>/exit_code.
instance() {
	local dir="$1" port="$2"; shift 2
	mkdir -p "$run/$dir"
	(
		CONTRACTOR_PORT="$port" CONTRACTOR_TEST_TAG="_soak$PORT" CONTRACTOR_SESSION_LOG=1 CONTRACTOR_TEST_LOGS="$(win "$run/sessions/$dir")" \
			timeout -k 10 $(( DURATION + 1800 )) "$GODOT" --headless --path . res://tests/coop_soak.tscn -- --soak-run "$(win "$run")" "$@" \
			>"$run/$dir/stdout.log" 2>&1
		echo $? >"$run/$dir/exit_code"
	) &
	pids+=($!)
}

# The import first (a fresh worktree has none; a broken script fails here, not as a hang).
timeout 600 "$GODOT" --headless --path . --import >"$run/import.log" 2>&1
if grep -qE 'SCRIPT ERROR|Parse Error' "$run/import.log"; then
	echo "import failed: see $run/import.log"
fi

instance host "$PORT" --soak-role host --soak-bot 0 --soak-duration "$DURATION" --soak-expect $(( LATE == 1 && CLIENTS == 3 ? 2 : CLIENTS ))
for i in $(seq 1 90); do
	[ -f "$run/host_ready" ] && break
	grep -qE 'SCRIPT ERROR|Parse Error' "$run/host/stdout.log" 2>/dev/null && break
	sleep 1
done
if [ ! -f "$run/host_ready" ]; then
	echo "the host never came up: see $run/host/stdout.log"
fi
for n in $(seq 1 "$CLIENTS"); do
	"$PYTHON" tools/coop_relay.py --listen $(( PORT + n )) --target "127.0.0.1:$PORT" --latency "$LATENCY" --jitter "$JITTER" --loss "$LOSS" \
		--seed $(( PORT + n )) --stats "$(win "$run/relay$n.jsonl")" >"$run/relay$n.log" 2>&1 &
	pids+=($!)
done
sleep 1
for n in $(seq 1 "$CLIENTS"); do
	[ "$n" = 3 ] && [ "$LATE" = 1 ] && continue
	extra=()
	[ "$n" = 2 ] && extra=(--soak-reconnect)
	instance "client$n" $(( PORT + n )) --soak-role client --soak-bot "$n" "${extra[@]}"
	sleep 2
done
host_pid="${pids[0]}"
late_started=0
deadline=$(( $(date +%s) + DURATION + 1800 ))
while kill -0 "$host_pid" 2>/dev/null && [ "$(date +%s)" -lt "$deadline" ]; do
	if [ "$CLIENTS" -ge 3 ] && [ "$LATE" = 1 ] && [ "$late_started" = 0 ] && grep -qE '"phase": ?"(advance|fight)"' "$run/phase.json" 2>/dev/null; then
		echo "first deployment under way: client 3 joins late"
		instance client3 $(( PORT + 3 )) --soak-role client --soak-bot 3 --soak-late
		late_started=1
	fi
	sleep 2
done
# The host has quit (or the deadline passed): give the clients a moment, then stop everything.
for i in $(seq 1 30); do
	alive=0
	for pid in "${pids[@]:1}"; do kill -0 "$pid" 2>/dev/null && alive=1; done
	[ "$alive" = 0 ] && break
	sleep 1
done
cleanup
sleep 2
"$PYTHON" tools/coop_soak_report.py "$(win "$run")" | tee "$run/report.log"
verdict=FAIL
grep -q '^VERDICT PASS' "$run/report.log" && verdict=PASS
final="$day/$run_id-$start_time-$verdict-$tail_name"
mv "$run" "$final" 2>/dev/null && run="$final"
echo "$run_id $(date +%Y-%m-%d) $start_time $verdict $tail_name script: tools/coop_soak.sh ($MINUTES min $MODE, $CLIENTS clients)" >>"$parent/index.txt"
echo "co-op soak $run_id: $verdict, report: $run/report.md"
[ "$verdict" = PASS ]
