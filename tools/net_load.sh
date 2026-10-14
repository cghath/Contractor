#!/usr/bin/env bash
# Network load probe (tests/net_load.gd): a host and one client over ENet on localhost, a
# 60 s squad-vs-garrison firefight, and the bytes a second the host sends the client, split by
# what they carry (the inventory's share, vitals, positions). Not a suite: it measures, it
# doesn't pass or fail on a number. Kept like any run (docs/debugging.md) as an S run:
#   GODOT="<voxel godot editor>" CONTRACTOR_PORT=25343 tools/net_load.sh
# The numbers are in the run folder's net_load.txt (and the host log's NETLOAD lines).
set -u
cd "$(dirname "$0")/.."
. tools/run_log.sh
GODOT="${GODOT:-godot}"
parent="$(run_log_parent)"
[ -z "$parent" ] && parent="$(mktemp -d)"
id="$(printf 'S%04d' "$(run_log_number "$parent")")"
tail="$(run_log_tail)"
day="$parent/$(date +%Y-%m-%d)"
time="$(date +%H%M%S)"
dir="$day/$id-$time-RUNNING-netload-$tail"
mkdir -p "$dir"
timeout -k 10 300 "$GODOT" --headless --path . --import >"$dir/import.log" 2>&1
NETLOAD_SHA="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- scripts scenes || echo '+changes')" \
	timeout -k 10 290 "$GODOT" --headless --path . res://tests/net_load.tscn >"$dir/host.log" 2>&1
code=$?
grep '^NETLOAD' "$dir/host.log" | grep -v 'client process' >"$dir/net_load.txt"
client_log="$(grep -o 'log .*net_load_client.*\.log' "$dir/host.log" | head -n 1 | sed 's/^log //')"
[ -n "$client_log" ] && [ -f "$client_log" ] && cp "$client_log" "$dir/client.log"
verdict=PASS
{ [ "$code" -ne 0 ] || ! grep -q 'NETLOAD DONE' "$dir/host.log" || grep -qE 'SCRIPT ERROR' "$dir/host.log"; } && verdict=FAIL
mv "$dir" "$day/$id-$time-$verdict-netload-$tail"
echo "$id $(date +%Y-%m-%d) $time $verdict $tail script: tests/net_load.gd (network load probe)" >>"$parent/index.txt"
cat "$day/$id-$time-$verdict-netload-$tail/net_load.txt"
echo "run $id: $verdict (exit $code), logs in $day/$id-$time-$verdict-netload-$tail"
[ "$verdict" = PASS ]
