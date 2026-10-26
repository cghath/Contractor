#!/usr/bin/env bash
# Watch a co-op soak (tools/coop_soak.sh, also --human) live, in a window: tests/coop_replay.tscn
# --live follows the host's replay.jsonl as it is written (about a second behind), in the real
# level, with every soldier's name and health, the contract's objective, and client 1's view
# beside it for divergence flags (magenta). It joins nothing: no player, no body, can't be shot,
# and the session doesn't know it's there. Opens once; close it with Esc.
#
#   GODOT=<Voxel Tools editor exe> tools/coop_watch.sh                 # the newest running soak
#   GODOT=... tools/coop_watch.sh <run folder> [--gpu N] [--windowed WxH]
#
# Keys: Tab next player, 1-4 a player, A automatic camera, O big map, mouse wheel zoom,
# right-drag orbit, Esc quit.
# --gpu: Vulkan device index (this PC: 0 the RTX 4060, 1 the Radeon 890M; default 0, the
# Captain's pick for watching). Default fullscreen at the screen's own resolution.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
RUN="" GPU="${COOP_WATCH_GPU:-0}" WINDOWED=""
while [ $# -gt 0 ]; do
	case "$1" in
		--gpu) GPU="$2"; shift ;;
		--windowed) WINDOWED="$2"; shift ;;
		*) RUN="$1" ;;
	esac
	shift
done
. tools/run_log.sh
if [ -z "$RUN" ]; then
	parent="$(run_log_parent)"
	RUN="$(ls -1dt "$parent"/*/S*-RUNNING-coop-soak-* 2>/dev/null | head -1)"
	[ -n "$RUN" ] || { echo "no running co-op soak found under $parent"; exit 2; }
fi
[ -f "$RUN/host/replay.jsonl" ] || { echo "no host/replay.jsonl in $RUN"; exit 2; }
win() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
# Play it in the checkout the soak runs in (the level is generated again from its definition, so
# the game code should match): a --build worktree if there is one for the run's commit.
sha="$(basename "$RUN" | grep -oE '[0-9a-f]{7}$')"
project="$(pwd)"
if [ -n "$sha" ] && [ -d "../Contractor-soakbuild-$sha" ]; then
	project="$(cd "../Contractor-soakbuild-$sha" && pwd)"
	for f in tests/coop_replay.gd tests/coop_replay.tscn tests/coop_replay.gd.uid; do
		[ -f "$f" ] && cp "$f" "$project/$f"
	done
fi
args=(--replay "$(win "$RUN/host/replay.jsonl")" --live)
[ -f "$RUN/client1/replay.jsonl" ] && args+=(--compare "$(win "$RUN/client1/replay.jsonl")")
view=(--fullscreen)
[ -n "$WINDOWED" ] && view=(--windowed --resolution "$WINDOWED")
log="${TMPDIR:-/tmp}/coop-watch-$(basename "$RUN")-$(date +%H%M%S).log"  # not in the run folder: an open file there blocks its final rename
echo "watching $(basename "$RUN") from $project on GPU $GPU (log: $log)"
"$GODOT" --path "$(win "$project")" --gpu-index "$GPU" "${view[@]}" res://tests/coop_replay.tscn -- "${args[@]}" >"$log" 2>&1 &
sleep 8
grep -m1 -E 'Using Device' "$log" || echo "(no device line yet: see $log)"
