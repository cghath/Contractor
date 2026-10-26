#!/usr/bin/env python3
"""UDP relay for the co-op soak (tools/coop_soak.sh): sits between one client and the host
and adds latency, jitter and packet loss to every datagram, both ways, like a bad internet
link. ENet runs over UDP, so the game sees exactly what a remote player would.

    python tools/coop_relay.py --listen 25348 --target 127.0.0.1:25347 \
        --latency 100 --jitter 30 --loss 1.5 --stats relay1.jsonl

--latency is one-way (ms); each packet's delay is latency +- jitter (uniform), never sooner
than the packet before it in the same direction (no reordering, as on most real links; pass
--reorder to let jitter reorder). --loss drops that percent of packets each way. With all
three at 0 ("clean LAN") it only forwards and counts. Every --stats-every seconds a JSON line
goes to --stats: bytes and packets each way, dropped, and the delays used. Runs until killed
or --seconds pass. Standard library only.

Each client address gets its own socket toward the host (like a NAT), so the host sees every
client as its own peer: a stray client from another run that hits this port is a separate
peer the host's private session turns away (no token), not traffic mixed into our bot's link
(BUGLIST B-15: test clients that reached a soak host through its relays).
"""
import argparse
import heapq
import json
import random
import select
import socket
import sys
import time


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--listen", type=int, required=True, help="UDP port the client connects to")
    ap.add_argument("--target", required=True, help="host:port of the game host")
    ap.add_argument("--latency", type=float, default=100.0, help="one-way delay, ms")
    ap.add_argument("--jitter", type=float, default=30.0, help="+- ms around the delay")
    ap.add_argument("--loss", type=float, default=1.5, help="percent of packets dropped each way")
    ap.add_argument("--reorder", action="store_true", help="let jitter reorder packets")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--stats", default="", help="JSON-lines stats file")
    ap.add_argument("--stats-every", type=float, default=5.0)
    ap.add_argument("--seconds", type=float, default=0.0, help="stop after this long (0: run until killed)")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    host, port = a.target.rsplit(":", 1)
    target = (host, int(port))

    front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)  # the client's side
    front.bind(("127.0.0.1", a.listen))
    front.setblocking(False)
    def bufs(s):
        try:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 22)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 22)
        except OSError:
            pass
    bufs(front)
    backs = {}  # client address -> its own socket toward the host
    owner = {}  # back socket -> client address

    def back_for(addr):
        s = backs.get(addr)
        if s is None:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.bind(("127.0.0.1", 0))
            s.setblocking(False)
            bufs(s)
            backs[addr] = s
            owner[s] = addr
            print(f"[relay] new client {addr[0]}:{addr[1]} (link {len(backs)})", flush=True)
        return s
    queue = []  # (due, seq, direction, data)
    seq = 0
    last_due = {"up": 0.0, "down": 0.0}
    zero = {"bytes": 0, "packets": 0, "dropped": 0, "delay_sum": 0.0}
    window = {"up": dict(zero), "down": dict(zero)}
    total = {"up": dict(zero), "down": dict(zero)}
    stats = open(a.stats, "a", encoding="utf-8") if a.stats else None
    start = time.time()
    next_stats = start + a.stats_every
    print(f"[relay] {a.listen} -> {a.target}: {a.latency} ms +- {a.jitter}, {a.loss}% loss", flush=True)

    def schedule(direction: str, data: bytes, addr) -> None:
        nonlocal seq
        for d in (window[direction], total[direction]):
            d["packets"] += 1
            d["bytes"] += len(data)
        if a.loss > 0 and rng.random() * 100.0 < a.loss:
            window[direction]["dropped"] += 1
            total[direction]["dropped"] += 1
            return
        now = time.time()
        delay = max(0.0, a.latency + (rng.uniform(-a.jitter, a.jitter) if a.jitter > 0 else 0.0)) / 1000.0
        due = now + delay
        if not a.reorder:
            due = max(due, last_due[direction])
            last_due[direction] = due
        window[direction]["delay_sum"] += due - now
        if due <= now and not queue:
            send(direction, data, addr)
            return
        seq += 1
        heapq.heappush(queue, (due, seq, direction, data, addr))

    def send(direction: str, data: bytes, addr) -> None:
        try:
            if direction == "up":
                back_for(addr).sendto(data, target)
            else:
                front.sendto(data, addr)
        except OSError:
            pass  # the far side is gone for now (ENet retries)

    try:
        while True:
            now = time.time()
            if a.seconds and now - start > a.seconds:
                break
            timeout = 0.05
            if queue:
                timeout = max(0.0, min(timeout, queue[0][0] - now))
            readable, _, _ = select.select([front] + list(owner), [], [], timeout)
            for s in readable:
                while True:
                    try:
                        data, addr = s.recvfrom(65536)
                    except (BlockingIOError, ConnectionResetError, OSError):
                        break
                    if s is front:
                        back_for(addr)
                        schedule("up", data, addr)
                    else:
                        schedule("down", data, owner[s])
            now = time.time()
            while queue and queue[0][0] <= now:
                _, _, direction, data, addr = heapq.heappop(queue)
                send(direction, data, addr)
            if now >= next_stats:
                if stats:
                    row = {"t": round(now, 3)}
                    for direction in ("up", "down"):
                        w = window[direction]
                        sent = w["packets"] - w["dropped"]
                        row[direction] = {"bytes": w["bytes"], "packets": w["packets"], "dropped": w["dropped"],
                                          "avg_delay_ms": round(w["delay_sum"] / sent * 1000.0, 1) if sent else 0.0}
                    stats.write(json.dumps(row) + "\n")
                    stats.flush()
                window = {"up": dict(zero), "down": dict(zero)}
                next_stats = now + a.stats_every
    except KeyboardInterrupt:
        pass
    finally:
        print(f"[relay] {a.listen}: up {total['up']['packets']} packets ({total['up']['dropped']} dropped), "
              f"down {total['down']['packets']} ({total['down']['dropped']} dropped)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
