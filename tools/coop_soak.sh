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
# --jitter MS (30), --loss PCT (1.5), --clients 1-3 (3), --port P (default: a free one from 25400 up, a range no test suite uses; the relays
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
#
# Play WITH the bots (--human): the host listens on the game's own port (24680, what a build
# joins), 2 bot clients join it directly (no relay, nobody leaves or joins late), and the host
# waits up to 10 min for you before the first contract and for you at every extraction:
#   GODOT=... tools/coop_soak.sh --human                 # 120 min, bots from the newest build's commit
# then in the game: Join someone's session, host address 127.0.0.1 (another PC: this one's LAN IP).
#
# --build DIR|newest|none: run the bots from the commit a build in B:\Contractor\builds was made
# from (its BUILD.txt), so they run the same game code the build does (a build's pack leaves
# tests/ out, so the bots run in the editor on a checkout of that commit: a worktree
# ../Contractor-soakbuild-<sha>, with this harness's own files laid over it). Default: newest
# with --human, none (this checkout) otherwise.
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
MINUTES=10 MODE=lossy LATENCY=100 JITTER=30 LOSS=1.5 CLIENTS=3 PORT=25400 LATE=1 TAG="" HUMAN=0 BUILD="" WAIT_HUMAN=600
ALL_ARGS=("$@")
while [ $# -gt 0 ]; do
	case "$1" in
		--human) HUMAN=1 ;;
		--build) BUILD="$2"; shift ;;
		--wait-human) WAIT_HUMAN="$2"; shift ;;
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
if [ "$HUMAN" = 1 ]; then
	# Defaults for playing along, unless given: 120 min, 2 bots, the game's port, a direct link.
	printf '%s\n' "${ALL_ARGS[@]}" | grep -qx -- --minutes || MINUTES=120
	printf '%s\n' "${ALL_ARGS[@]}" | grep -qx -- --clients || CLIENTS=2
	printf '%s\n' "${ALL_ARGS[@]}" | grep -qx -- --port || PORT=24680
	MODE=clean LATE=0 TAG="${TAG:-human}"
	[ -z "$BUILD" ] && BUILD=newest
fi
if [ -n "$BUILD" ] && [ "$BUILD" != none ]; then
	builds="${CONTRACTOR_BUILDS:-/b/Contractor/builds}"
	if [ "$BUILD" = newest ]; then
		BUILD="$(ls -1d "$builds"/contractor-* 2>/dev/null | sort | tail -1)"
	fi
	[ -f "$BUILD/BUILD.txt" ] || { echo "no BUILD.txt in '$BUILD'"; exit 2; }
	sha="$(grep -oE 'commit [0-9a-f]{7,40}' "$BUILD/BUILD.txt" | head -1 | cut -d' ' -f2)"
	[ -n "$sha" ] || { echo "no commit in $BUILD/BUILD.txt"; exit 2; }
	here="$(pwd)"
	wt="$(cd .. && pwd)/Contractor-soakbuild-$sha"
	echo "bots run the game code of $(basename "$BUILD") (commit $sha) in $wt"
	if [ ! -d "$wt" ]; then
		git fetch -q origin 2>/dev/null
		git worktree add -q --detach "$wt" "$sha" || { echo "could not check out $sha"; exit 2; }
	fi
	[ "$(git -C "$wt" rev-parse HEAD)" = "$(git rev-parse "$sha^{commit}")" ] || { echo "$wt is not at $sha"; exit 2; }
	# The harness's own files (tests/ and tools/ never go into a build's pack) over that commit.
	for f in tests/coop_soak.gd tests/coop_soak.tscn tests/coop_soak.gd.uid tests/coop_soak_recorder.gd tests/coop_soak_recorder.gd.uid \
		tests/coop_replay.gd tests/coop_replay.tscn tests/coop_replay.gd.uid tools/coop_soak.sh tools/coop_relay.py tools/coop_soak_report.py tools/coop_replay.sh; do
		[ -f "$here/$f" ] && cp "$here/$f" "$wt/$f"
	done
	# Same options, this time without --build: the copy runs in that checkout.
	rest=()
	skip=0
	for a in "${ALL_ARGS[@]}"; do
		if [ "$skip" = 1 ]; then skip=0; continue; fi
		[ "$a" = --build ] && { skip=1; continue; }
		rest+=("$a")
	done
	exec bash "$wt/tools/coop_soak.sh" --build none "${rest[@]}"
fi
if [ "$MODE" = clean ]; then LATENCY=0; JITTER=0; LOSS=0; fi
# Free ports (S0651 failed hosting on a port another soak still held): unless --port was given,
# the first base from 25400 up (no test suite uses 25400-25499), in steps of 10, whose P..P+clients all bind and that no
# running soak's config.json names.
if ! printf '%s\n' "${ALL_ARGS[@]}" | grep -qx -- --port; then
	parent_for_ports="$(run_log_parent)"
	taken="$(cat "$parent_for_ports"/*/S*-RUNNING-coop-soak-*/config.json 2>/dev/null | grep -oE '"port": [0-9]+' | grep -oE '[0-9]+' | tr '\n' ' ')"
	PORT="$("$PYTHON" - "$PORT" "$CLIENTS" "$taken" <<'PY'
import socket, sys
base, n, taken = int(sys.argv[1]), int(sys.argv[2]), {int(t) for t in sys.argv[3].split()}
for k in range(40):
    p = base + 10 * k
    if any(q in taken for q in range(p - 3, p + n + 4)):
        continue
    socks = []
    try:
        for q in range(p, p + n + 1):
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.bind(("127.0.0.1", q))
            socks.append(s)
        print(p)
        break
    except OSError:
        pass
    finally:
        for s in socks:
            s.close()
else:
    print(base)
PY
)"
fi
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
if [ "$HUMAN" = 1 ]; then
	ips="$(ipconfig 2>/dev/null | grep -aE 'IPv4' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr '\n' ' ')"
	echo "PLAY ALONG: start the game build, Join someone's session, host address 127.0.0.1 (from another PC: one of $ips), port $PORT."
	echo "The bots wait up to $WAIT_HUMAN s for you before the first contract, and for you at each extraction. Ctrl+C here ends the session."
fi
cat >"$run/config.json" <<EOF
{"run_id": "$run_id", "mode": "$MODE", "minutes": $MINUTES, "latency_ms": $LATENCY, "jitter_ms": $JITTER, "loss_pct": $LOSS,
 "clients": $CLIENTS, "port": $PORT, "late": $LATE, "branch_sha": "$(run_log_tail)", "started": "$(date '+%Y-%m-%d %H:%M:%S')",
 "godot": "$(win "$GODOT")"}
EOF

# The bots' session takes only joiners with this token (Net._hello): another run's test that
# hits the port is refused. Not with --human (a player's build has no token to give).
token="soak-$run_id-$start_time"
[ "$HUMAN" = 1 ] && token=""
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
		CONTRACTOR_SESSION_TOKEN="$token" CONTRACTOR_PORT="$port" CONTRACTOR_TEST_TAG="_soak$PORT" CONTRACTOR_SESSION_LOG=1 CONTRACTOR_TEST_LOGS="$(win "$run/sessions/$dir")" \
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

human_args=()
[ "$HUMAN" = 1 ] && human_args=(--soak-human --soak-wait-human "$WAIT_HUMAN")
instance host "$PORT" --soak-role host --soak-bot 0 --soak-duration "$DURATION" --soak-expect $(( LATE == 1 && CLIENTS == 3 ? 2 : CLIENTS )) "${human_args[@]}"
for i in $(seq 1 90); do
	[ -f "$run/host_ready" ] && break
	grep -qE 'SCRIPT ERROR|Parse Error' "$run/host/stdout.log" 2>/dev/null && break
	sleep 1
done
if [ ! -f "$run/host_ready" ]; then
	echo "the host never came up: see $run/host/stdout.log"
fi
label="$(grep -m1 -aoE '^\[build\] .*' "$run/host/stdout.log" 2>/dev/null | cut -c9-)"
echo "the bots' game: ${label:-$(git rev-parse --short HEAD) (no build label in this commit)}"
[ "$HUMAN" = 1 ] && echo "Your game's main menu title must show the same commit, or the host turns you away (builds from before the build check just connect)."
for n in $(seq 1 "$CLIENTS"); do
	[ "$HUMAN" = 1 ] && break  # bots join the host directly, as the human does
	"$PYTHON" tools/coop_relay.py --listen $(( PORT + n )) --target "127.0.0.1:$PORT" --latency "$LATENCY" --jitter "$JITTER" --loss "$LOSS" \
		--seed $(( PORT + n )) --stats "$(win "$run/relay$n.jsonl")" >"$run/relay$n.log" 2>&1 &
	pids+=($!)
done
sleep 1
for n in $(seq 1 "$CLIENTS"); do
	[ "$n" = 3 ] && [ "$LATE" = 1 ] && continue
	extra=()
	[ "$n" = 2 ] && [ "$HUMAN" = 0 ] && extra=(--soak-reconnect)
	cport=$(( PORT + n ))
	[ "$HUMAN" = 1 ] && cport=$PORT
	instance "client$n" "$cport" --soak-role client --soak-bot "$n" "${extra[@]}"
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
# Something still holding a file in the folder (a viewer, a tail) blocks the rename on Windows:
# try for a minute, then say so (the folder stays RUNNING).
for i in $(seq 1 12); do
	mv "$run" "$final" 2>/dev/null && { run="$final"; break; }
	sleep 5
done
[ "$run" = "$final" ] || echo "could not rename $run to $final (a file in it is open): rename it by hand"
echo "$run_id $(date +%Y-%m-%d) $start_time $verdict $tail_name script: tools/coop_soak.sh ($MINUTES min $MODE, $CLIENTS clients)" >>"$parent/index.txt"
echo "co-op soak $run_id: $verdict, report: $run/report.md"
[ "$verdict" = PASS ]
