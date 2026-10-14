#!/usr/bin/env bash
# Renders a co-op soak run (tools/coop_soak.sh) to video: tests/coop_replay.tscn plays the host's
# replay.jsonl back in the real level (the client's beside it for divergence flags) and Godot's
# Movie Maker writes every frame to an AVI, then ffmpeg (if found) makes an mp4 of it.
#
#   GODOT=<Voxel Tools editor exe> tools/coop_replay.sh <run folder>                 # highlights, 2560x1600
#   GODOT=... tools/coop_replay.sh <run folder> --cut full --speed 8 --res 1280x800   # the whole run
#
# Options: --cut highlights|full (highlights), --speed N (full: 4), --res WxH (2560x1600, the
# Captain's native), --compare client1|client2|client3|none (client1), --gpu N (Vulkan GPU index,
# default 0: the RTX 4060 on this PC; 1 is the Radeon iGPU), --out NAME (coop-<cut>), --capsules.
# Videos go into <run folder>/video/. The window is a no-focus window placed off every screen (the
# Captain games on this PC: nothing may show up or take the focus); Movie Maker still renders it.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
RUN="${1:-}"
[ -z "$RUN" ] || [ ! -d "$RUN" ] && { echo "usage: tools/coop_replay.sh <run folder> [options]"; exit 2; }
shift
CUT=highlights SPEED="" RES=2560x1600 COMPARE=client1 GPU="${COOP_GPU_INDEX:-}" OUT="" EXTRA=()
while [ $# -gt 0 ]; do
	case "$1" in
		--cut) CUT="$2"; shift ;;
		--speed) SPEED="$2"; shift ;;
		--res) RES="$2"; shift ;;
		--compare) COMPARE="$2"; shift ;;
		--gpu) GPU="$2"; shift ;;
		--out) OUT="$2"; shift ;;
		--capsules) EXTRA+=(--capsules) ;;
		--from) EXTRA+=(--from "$2"); shift ;;
		--to) EXTRA+=(--to "$2"); shift ;;
		*) echo "unknown option $1"; exit 2 ;;
	esac
	shift
done
win() { cygpath -m "$1" 2>/dev/null || echo "$1"; }
RUN="$(cd "$RUN" && pwd)"
OUT="${OUT:-coop-$CUT}"
mkdir -p "$RUN/video"
args=(--replay "$(win "$RUN/host/replay.jsonl")" --cut "$CUT")
[ -n "$SPEED" ] && args+=(--speed "$SPEED")
if [ "$COMPARE" != none ] && [ -f "$RUN/$COMPARE/replay.jsonl" ]; then
	args+=(--compare "$(win "$RUN/$COMPARE/replay.jsonl")")
fi
args+=("${EXTRA[@]}")

# No focus for the render window (override.cfg is read at start; it is removed again after).
had_override=0
[ -f override.cfg ] && had_override=1
if [ "$had_override" = 0 ]; then
	trap 'rm -f override.cfg' EXIT
	printf '[display]\n\nwindow/size/no_focus=true\nwindow/energy_saving/keep_screen_on=false\n' >override.cfg
fi
render() {  # $1 = gpu index; writes $RUN/video/$OUT.avi, log $RUN/video/$OUT.log
	timeout -k 10 7200 "$GODOT" --path . --gpu-index "$1" --resolution "$RES" --position -20000,-20000 --fixed-fps 30 \
		--write-movie "$(win "$RUN/video/$OUT.avi")" res://tests/coop_replay.tscn -- "${args[@]}" >"$RUN/video/$OUT.log" 2>&1
}
device_line() { grep -m1 -E 'Vulkan .*Using Device|Using Device #' "$RUN/video/$OUT.log"; }
# This PC: Vulkan device 0 is the NVIDIA RTX 4060, 1 the Radeon 890M. Checked after the render
# from Godot's device line; set COOP_GPU_INDEX / --gpu elsewhere.
GPU="${GPU:-0}"
echo "rendering $CUT of $RUN on GPU $GPU at $RES"
render "$GPU"
code=$?
[ "$had_override" = 0 ] && rm -f override.cfg
echo "device: $(device_line)"
want=NVIDIA; [ "$GPU" = 1 ] && want=Radeon
device_line | grep -qiE "$want" || echo "WARNING: not rendered on the $want: pass --gpu <index> (see the device line above)"
grep -E '^\[replay\]' "$RUN/video/$OUT.log" | head -5
if [ "$code" != 0 ] || [ ! -s "$RUN/video/$OUT.avi" ]; then
	echo "render failed (exit $code): see $RUN/video/$OUT.log"
	exit 1
fi
FFMPEG="${FFMPEG:-}"
if [ -z "$FFMPEG" ]; then
	for f in ffmpeg "/c/Program Files/Shotcut/ffmpeg.exe" "/c/Program Files/ffmpeg/bin/ffmpeg.exe"; do
		command -v "$f" >/dev/null 2>&1 && { FFMPEG="$f"; break; }
	done
fi
if [ -n "$FFMPEG" ]; then
	"$FFMPEG" -hide_banner -loglevel error -y -i "$(win "$RUN/video/$OUT.avi")" -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p \
		-c:a aac -b:a 96k -movflags +faststart "$(win "$RUN/video/$OUT.mp4")" \
		&& rm -f "$RUN/video/$OUT.avi" && echo "video: $RUN/video/$OUT.mp4 ($(du -h "$RUN/video/$OUT.mp4" | cut -f1))"
else
	echo "video: $RUN/video/$OUT.avi (no ffmpeg found for an mp4)"
fi
