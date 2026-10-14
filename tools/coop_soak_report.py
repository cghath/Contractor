#!/usr/bin/env python3
"""Co-op soak report (tools/coop_soak.sh runs it at the end; run it again on any run folder):

    python tools/coop_soak_report.py <run folder> [--pos-tol 2.5] [--slack-s 0.6]

Reads what each peer wrote (host/, client1/ ...: snapshots.jsonl, metrics.jsonl, bot.log,
stdout.log; host/cycles.jsonl; relay*.jsonl; config.json) and writes report.md and
divergences.jsonl into the run folder. Prints the verdict line last ("VERDICT PASS|FAIL ...").

Divergence: on each 5 s mark a client's snapshot is compared with the host's (both are taken
on the same wall-clock mark on one machine). Per soldier: missing on the client, extra on the
client (a ghost), position off by more than --pos-tol metres plus how far the host saw it move
in --slack-s (latency and interpolation), up/down/dead differing, a player's ammo or inventory
hash differing; per peer: level, objectives, world items, debrief count. A mismatch that is gone
on the next mark is "transient" (in flight when the mark was taken); one that is still there on
the next mark is "persistent". Marks where either side is switching level or the client is
offline are skipped (counted).
Standard library only.
"""
import argparse
import collections
import json
import math
import os
import re
import sys

PEERS = ["host", "client1", "client2", "client3"]
F_UP, F_DOWNED, F_DEAD = 1, 2, 4


def jsonl(path):
    out = []
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def read(path):
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def state_of(flags):
    if flags & F_DEAD:
        return "dead"
    if flags & F_DOWNED:
        return "down"
    if flags & F_UP:
        return "up"
    return "?"


def spark(values, width=48):
    """A unicode sparkline of `values` squeezed to `width` columns (max per column)."""
    bars = " ▁▂▃▄▅▆▇█"
    vals = [v for v in values if v is not None]
    if not vals:
        return ""
    if len(values) > width:
        step = len(values) / width
        values = [max([v for v in values[int(i * step):int((i + 1) * step)] if v is not None] or [0]) for i in range(width)]
    top = max(vals) or 1
    return "".join(bars[min(8, int(round((v or 0) / top * 8)))] for v in values)


def compare(host, client, args, host_prev):
    """Mismatches between a host snapshot and a client snapshot on the same mark: a list of
    (key, kind, detail)."""
    out = []
    if host.get("level") != client.get("level"):
        out.append(("level", "level", f"host {host.get('level')} / client {client.get('level')}"))
        return out
    hs, cs = host.get("soldiers", {}), client.get("soldiers", {})
    for key, h in hs.items():
        c = cs.get(key)
        if key.startswith("Bodies/"):
            if c is None:
                out.append((key, "missing", "body not on the client"))
            continue
        if c is None:
            out.append((key, "missing", f"not on the client (host at {h['p']})"))
            continue
        moved = 0.0
        prev = host_prev.get(key) if host_prev else None
        if prev is not None:
            dt = max(host.get("t", 0) - host_prev.get("__t", 0), 1e-3)
            moved = dist(prev["p"], h["p"]) / dt * args.slack_s
        tol = args.pos_tol + moved
        hp = h["bp"] if not (h["f"] & F_UP) else h["p"]
        cp = c["bp"] if not (c["f"] & F_UP) else c["p"]
        d = dist(hp, cp)
        if d > tol:
            out.append((key, "position", f"{d:.1f} m apart (tolerance {tol:.1f}): host {hp} client {cp}"))
        if state_of(h["f"]) != state_of(c["f"]):
            out.append((key, "condition", f"host {state_of(h['f'])} / client {state_of(c['f'])}"))
        # Counters that change fast (a burst, a reload) are compared only when the host's value
        # held since the previous mark: else the client is just a relay delay behind (B-08:
        # every S0706 ammo mismatch was +1 on a mark where the host's count had just changed).
        hp_row = prev if prev is not None else None
        steady_rounds = hp_row is not None and hp_row.get("rounds") == h.get("rounds")
        steady_inv = hp_row is not None and hp_row.get("inv") == h.get("inv")
        if "rounds" in h and steady_rounds and h.get("rounds") != c.get("rounds"):
            out.append((key, "ammo", f"host {h.get('rounds')} / client {c.get('rounds')} in the rifle"))
        if "inv" in h and steady_inv and h.get("inv") != c.get("inv"):
            out.append((key, "inventory", f"hash host {h.get('inv')} / client {c.get('inv')}"))
    for key in cs:
        if key not in hs:
            out.append((key, "ghost", f"on the client only (at {cs[key]['p']})"))
    if host.get("objectives") != client.get("objectives"):
        out.append(("objectives", "objectives", f"host {host.get('objectives')} / client {client.get('objectives')}"))
    if host.get("items_hash") != client.get("items_hash"):
        hi = collections.Counter((i[0], i[1]) for i in host.get("items", []))
        ci = collections.Counter((i[0], i[1]) for i in client.get("items", []))
        diff = (hi - ci) + (ci - hi)
        out.append(("items", "items", f"host {host.get('items_n')} / client {client.get('items_n')} world items; differing: {dict(list(diff.items())[:6])}"))
    if host.get("debriefs") != client.get("debriefs"):
        out.append(("debrief", "debrief", f"host {host.get('debriefs')} / client {client.get('debriefs')}"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--pos-tol", type=float, default=2.5)
    ap.add_argument("--slack-s", type=float, default=0.6)
    args = ap.parse_args()
    run = args.run
    config = {}
    if os.path.exists(os.path.join(run, "config.json")):
        config = json.loads(read(os.path.join(run, "config.json")))
    peers = [p for p in PEERS if os.path.isdir(os.path.join(run, p))]
    snaps = {p: jsonl(os.path.join(run, p, "snapshots.jsonl")) for p in peers}
    metrics = {p: jsonl(os.path.join(run, p, "metrics.jsonl")) for p in peers}
    cycles = jsonl(os.path.join(run, "host", "cycles.jsonl"))
    host_by_k = {s["k"]: s for s in snaps.get("host", [])}
    t0 = min([s["t"] for p in peers for s in snaps[p]] or [0])
    problems = []

    # --- Divergences --------------------------------------------------------------------
    divergences = []
    per_kind = collections.Counter()
    persistent_kind = collections.Counter()
    skipped = collections.Counter()
    compared = collections.Counter()
    for p in peers:
        if p == "host":
            continue
        by_k = {s["k"]: s for s in snaps[p]}
        prev_found = {}
        for k in sorted(by_k):
            c = by_k[k]
            h = host_by_k.get(k)
            if h is None or not c.get("online"):
                skipped[p] += 1
                continue
            hp = host_by_k.get(k - 1)
            host_prev = None
            if hp is not None and hp.get("level") == h.get("level"):
                host_prev = {key: v for key, v in hp.get("soldiers", {}).items()}
                host_prev["__t"] = hp.get("t", 0)
            found = compare(h, c, args, host_prev)
            compared[p] += 1
            for key, kind, detail in found:
                divergences.append({"peer": p, "k": k, "t": c["t"], "at_s": round(c["t"] - t0, 1), "phase": h.get("phase"),
                                    "key": key, "kind": kind, "detail": detail})
            prev_found[k] = {(key, kind) for key, kind, _ in found}
        # persistent: the same (key, kind) on the next mark too
        for d in divergences:
            if d["peer"] != p:
                continue
            nxt = prev_found.get(d["k"] + 1)
            d["persistent"] = bool(nxt and (d["key"], d["kind"]) in nxt)
    for d in divergences:
        per_kind[(d["peer"], d["kind"])] += 1
        if d.get("persistent"):
            persistent_kind[(d["peer"], d["kind"])] += 1
    with open(os.path.join(run, "divergences.jsonl"), "w", encoding="utf-8") as f:
        for d in divergences:
            f.write(json.dumps(d) + "\n")

    # Persistent streaks: the same (peer, key, kind) on consecutive marks, as one line each.
    streaks = []
    by_id = collections.defaultdict(list)
    for d in divergences:
        by_id[(d["peer"], d["key"], d["kind"])].append(d)
    for ident, ds in by_id.items():
        ds.sort(key=lambda d: d["k"])
        run_start = ds[0]
        last = ds[0]
        for d in ds[1:] + [None]:
            if d is not None and d["k"] == last["k"] + 1:
                last = d
                continue
            n = last["k"] - run_start["k"] + 1
            if n >= 2:
                streaks.append({"peer": ident[0], "key": ident[1], "kind": ident[2], "from_s": run_start["at_s"], "to_s": last["at_s"],
                                "marks": n, "phase": run_start["phase"], "first": run_start["detail"], "last": last["detail"]})
            if d is not None:
                run_start = last = d
    streaks.sort(key=lambda s: (-s["marks"], s["from_s"]))

    # --- Errors and warnings (stdout of every instance) -----------------------------------
    err_re = re.compile(r"^(SCRIPT ERROR|ERROR|WARNING|USER ERROR|USER WARNING)[:]? (.*)")
    errors = {}
    crash = {}
    for p in peers:
        text = read(os.path.join(run, p, "stdout.log"))
        counter = collections.Counter()
        where = {}
        lines = text.splitlines()
        for i, line in enumerate(lines):
            m = err_re.match(line.strip())
            if m:
                msg = f"{m.group(1)}: {m.group(2)}"[:220]
                counter[msg] += 1
                if msg not in where and i + 1 < len(lines) and lines[i + 1].strip().startswith("at:"):
                    where[msg] = lines[i + 1].strip()[:200]
        errors[p] = (counter, where)
        if "CrashHandlerException" in text or "Program crashed" in text:
            crash[p] = True
    session_dirs = []
    for root, dirs, files in os.walk(os.path.join(run, "sessions")):
        for fn in files:
            if fn == "session.log":
                session_dirs.append(os.path.relpath(os.path.join(root, fn), run))

    # --- Joins, leaves, lost connections ----------------------------------------------------
    events = []
    for p in peers:
        for line in read(os.path.join(run, p, "bot.log")).splitlines():
            if any(w in line for w in ("joined", "left", "lost the connection", "leaving", "PROBLEM", "finished", "TIMED OUT", "could not join")):
                events.append(f"{p}: {line}")
    exits = {}
    for p in peers:
        e = read(os.path.join(run, p, "exit_code")).strip()
        exits[p] = e if e else "?"

    # --- Report ------------------------------------------------------------------------------
    total_persistent = sum(persistent_kind.values())
    serious_persistent = sum(n for (p, kind), n in persistent_kind.items() if kind not in ("position",))
    out = []
    title = config.get("run_id", os.path.basename(run.rstrip("/\\")))
    out.append(f"# Co-op soak {title}")
    out.append("")
    if config:
        out.append(f"- Mode: **{config.get('mode')}** ({config.get('latency_ms')} ms one-way +- {config.get('jitter_ms')} ms jitter, "
                   f"{config.get('loss_pct')}% loss each way, per client, through tools/coop_relay.py)" if config.get("mode") != "clean"
                   else f"- Mode: **clean** (relay forwards only: no added latency or loss)")
        out.append(f"- Branch/commit: {config.get('branch_sha')}; asked duration {config.get('minutes')} min; "
                   f"started {config.get('started')}; host port {config.get('port')}")
        out.append(f"- Peers: host + {config.get('clients')} clients (client2 leaves and rejoins in the first fight; client3 joins late, "
                   f"once the first deployment is under way)")
    if snaps.get("host"):
        out.append(f"- Ran {(snaps['host'][-1]['t'] - t0) / 60:.1f} min of host snapshots ({len(snaps['host'])} marks); exit codes: "
                   + ", ".join(f"{p} {exits[p]}" for p in peers))
    out.append("")

    out.append("## Contracts played (host's cycles)")
    out.append("")
    out.append("| # | took | contract | accepted / picked by | revive | extraction | debrief | ok |")
    out.append("|---|---|---|---|---|---|---|---|")
    for c in cycles:
        con = c.get("contract", {})
        rv = c.get("revive", {})
        rv_text = ("down, back up in %.0f s" % rv.get("seconds", 0)) if rv.get("up") else (
            "never went down" if rv.get("went_down") is False else ("died" if rv.get("dead") else f"still down ({rv.get('still_down', '?')}: {rv.get('why_unconscious', '')})" if rv else "-"))
        if rv:
            rv_text = f"peer {rv.get('victim')} by {rv.get('medic')}: " + rv_text
        ex = c.get("extract", {})
        ex_text = ("gathered" if ex.get("gathered") else f"NOT gathered (missing {ex.get('missing')})") + (
            f", left behind {ex.get('left_behind')}" if ex.get("left_behind") else "") + (f", confirmed by {ex.get('confirmed_by')}" if ex else "")
        db = c.get("debrief", {})
        db_text = f"{db.get('outcome', '-')}, seen {db.get('seen', {})}" if db else "-"
        out.append(f"| {c.get('cycle')} | {c.get('seconds')} s | {con.get('title', '-')} ({con.get('type', '')}) | {con.get('accepted_by', '-')} / {con.get('picked_by', '-')} | "
                   f"{rv_text} | {ex_text if ex else '-'} | {db_text} | {'yes' if c.get('ok') else 'NO: ' + str(c.get('why'))} |")
    if not cycles:
        out.append("| - | | no cycle finished | | | | | |")
        problems.append("no contract cycle finished")
    for c in cycles:
        if not c.get("ok"):
            problems.append(f"cycle {c.get('cycle')} failed: {c.get('why')}")
        for b, seen in c.get("debrief", {}).get("seen", {}).items():
            if not seen:
                problems.append(f"cycle {c.get('cycle')}: {b} never got the debrief")
    out.append("")
    if cycles:
        out.append("Kit after kitting up, per bot (cycle 1): " + json.dumps(cycles[0].get("kit", {})))
        out.append("")

    out.append("## Divergences (client vs host, on the same 5 s marks)")
    out.append("")
    out.append(f"Tolerance: {args.pos_tol} m plus what the host saw the soldier move in {args.slack_s} s. "
               f"Compared marks: " + ", ".join(f"{p} {compared[p]} (skipped {skipped[p]})" for p in peers if p != "host"))
    out.append("")
    out.append("| peer | kind | marks with it | of which persistent (still there 5 s later) |")
    out.append("|---|---|---|---|")
    for (p, kind), n in sorted(per_kind.items()):
        out.append(f"| {p} | {kind} | {n} | {persistent_kind.get((p, kind), 0)} |")
    if not per_kind:
        out.append("| - | none | 0 | 0 |")
    out.append("")
    if streaks:
        out.append("Longest persistent divergences (same soldier/thing, consecutive marks; time from the run's start):")
        out.append("")
        out.append("| peer | what | kind | from | to | marks | phase | first seen | last seen |")
        out.append("|---|---|---|---|---|---|---|---|---|")
        for s in streaks[:25]:
            out.append(f"| {s['peer']} | {s['key']} | {s['kind']} | {s['from_s']} s | {s['to_s']} s | {s['marks']} | {s['phase']} | {s['first'][:110]} | {s['last'][:110]} |")
        out.append("")
        out.append(f"All divergences, with timestamps: divergences.jsonl ({len(divergences)} lines).")
        out.append("")

    out.append("## Disconnects, joins and the bots' problems")
    out.append("")
    for e in events[:80]:
        out.append(f"- {e}")
    if not events:
        out.append("- none")
    out.append("")

    out.append("## Errors and warnings (every instance's output)")
    out.append("")
    any_err = False
    for p in peers:
        counter, where = errors[p]
        if not counter:
            continue
        any_err = True
        out.append(f"**{p}** ({sum(counter.values())} lines, {len(counter)} kinds)")
        out.append("")
        out.append("| count | line | at |")
        out.append("|---|---|---|")
        for msg, n in counter.most_common(20):
            out.append(f"| {n} | `{msg.replace('|', '/')}` | {where.get(msg, '').replace('|', '/')} |")
        out.append("")
        if any(m.startswith("SCRIPT ERROR") for m in counter):
            problems.append(f"{p}: script errors")
    if not any_err:
        out.append("None.")
        out.append("")
    for p in crash:
        problems.append(f"{p} crashed")
    if session_dirs:
        out.append("Session logs (SessionLog, one per instance): " + ", ".join(session_dirs))
        out.append("")

    out.append("## Bandwidth, frames and memory over time")
    out.append("")
    out.append("Per peer, per minute: ENet bytes sent and received (KB/s, all of ENet's traffic incl. headers), frame time average and worst "
               "(headless: simulation only, no rendering), static memory, soldiers in the level.")
    out.append("")
    summary_rows = []
    for p in peers:
        ms = metrics[p]
        if not ms:
            continue
        per_min = collections.OrderedDict()
        for m in ms:
            minute = int((m["t"] - t0) // 60)
            per_min.setdefault(minute, []).append(m)
        out.append(f"### {p}")
        out.append("")
        out.append("| min | phase | up KB/s | down KB/s | inv. changes/s | inv. KB/s | vitals KB/s | frame avg ms | frame worst ms | mem MB | soldiers | RTT ms | loss % |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for minute, rows in per_min.items():
            secs = 5.0 * len(rows)
            sent = sum(r.get("sent_bytes", 0) for r in rows) / 1024 / secs
            recv = sum(r.get("recv_bytes", 0) for r in rows) / 1024 / secs
            invc = sum(r.get("inv_changes", 0) for r in rows) / secs
            invb = sum(r.get("inv_bytes", 0) for r in rows) / 1024 / secs
            vitb = sum(r.get("vit_bytes", 0) for r in rows) / 1024 / secs
            favg = sum(r.get("frame_avg_ms", 0) for r in rows) / len(rows)
            fmax = max(r.get("frame_max_ms", 0) for r in rows)
            mem = rows[-1].get("mem_static_mb", 0)
            sol = rows[-1].get("soldiers", 0)
            rtts = [v.get("rtt_ms", 0) for r in rows for v in r.get("peers", {}).values()]
            losses = [v.get("loss", 0) for r in rows for v in r.get("peers", {}).values()]
            phase = rows[len(rows) // 2].get("phase", "")
            out.append(f"| {minute} | {phase} | {sent:.1f} | {recv:.1f} | {invc:.1f} | {invb:.2f} | {vitb:.2f} | {favg:.1f} | {fmax:.0f} | {mem:.0f} | {sol} | "
                       f"{(sum(rtts) / len(rtts)) if rtts else 0:.0f} | {(sum(losses) / len(losses) * 100) if losses else 0:.2f} |")
        out.append("")
        sent_series = [m.get("sent_bytes", 0) / 5120 for m in ms]
        recv_series = [m.get("recv_bytes", 0) / 5120 for m in ms]
        frame_series = [m.get("frame_max_ms", 0) for m in ms]
        mem_series = [m.get("mem_static_mb", 0) for m in ms]
        out.append("```")
        out.append(f"up KB/s    {spark(sent_series)}  max {max(sent_series or [0]):.1f}")
        out.append(f"down KB/s  {spark(recv_series)}  max {max(recv_series or [0]):.1f}")
        out.append(f"worst ms   {spark(frame_series)}  max {max(frame_series or [0]):.0f}")
        out.append(f"memory MB  {spark(mem_series)}  {mem_series[0] if mem_series else 0:.0f} -> {mem_series[-1] if mem_series else 0:.0f}")
        out.append("```")
        out.append("")
        secs = 5.0 * len(ms)
        summary_rows.append((p, sum(m.get("sent_bytes", 0) for m in ms) / 1024 / secs, sum(m.get("recv_bytes", 0) for m in ms) / 1024 / secs,
                             max(m.get("sent_bytes", 0) for m in ms) / 5120, max(m.get("recv_bytes", 0) for m in ms) / 5120,
                             sum(m.get("frame_avg_ms", 0) for m in ms) / len(ms), max(frame_series or [0]),
                             mem_series[0] if mem_series else 0, max(mem_series or [0]), mem_series[-1] if mem_series else 0,
                             sum(m.get("inv_changes", 0) for m in ms) / secs, sum(m.get("inv_bytes", 0) for m in ms) / 1024 / secs,
                             sum(m.get("vit_changes", 0) for m in ms) / secs, sum(m.get("vit_bytes", 0) for m in ms) / 1024 / secs))
    relays = sorted(f for f in os.listdir(run) if f.startswith("relay") and f.endswith(".jsonl"))
    if relays:
        out.append("### Relays (what crossed each client's link)")
        out.append("")
        out.append("| relay | up KB/s avg | down KB/s avg | up packets dropped | down packets dropped | avg added delay up/down ms |")
        out.append("|---|---|---|---|---|---|")
        for fn in relays:
            rows = jsonl(os.path.join(run, fn))
            if not rows:
                continue
            secs = 5.0 * len(rows)
            up = sum(r["up"]["bytes"] for r in rows) / 1024 / secs
            down = sum(r["down"]["bytes"] for r in rows) / 1024 / secs
            upd = sum(r["up"]["dropped"] for r in rows)
            dnd = sum(r["down"]["dropped"] for r in rows)
            upp = sum(r["up"]["packets"] for r in rows) or 1
            dnp = sum(r["down"]["packets"] for r in rows) or 1
            dly_u = [r["up"]["avg_delay_ms"] for r in rows if r["up"]["packets"]]
            dly_d = [r["down"]["avg_delay_ms"] for r in rows if r["down"]["packets"]]
            out.append(f"| {fn} | {up:.1f} | {down:.1f} | {upd} ({upd / upp * 100:.2f}%) | {dnd} ({dnd / dnp * 100:.2f}%) | "
                       f"{(sum(dly_u) / len(dly_u)) if dly_u else 0:.0f} / {(sum(dly_d) / len(dly_d)) if dly_d else 0:.0f} |")
        out.append("")

    out.append("## Summary per peer")
    out.append("")
    out.append("| peer | up KB/s avg | down KB/s avg | up peak | down peak | frame avg ms | frame worst ms | memory start / peak / end MB | inventory replacements/s | inventory KB/s | vitals replacements/s | vitals KB/s |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in summary_rows:
        out.append(f"| {r[0]} | {r[1]:.1f} | {r[2]:.1f} | {r[3]:.1f} | {r[4]:.1f} | {r[5]:.1f} | {r[6]:.0f} | {r[7]:.0f} / {r[8]:.0f} / {r[9]:.0f} | {r[10]:.1f} | {r[11]:.2f} | {r[12]:.1f} | {r[13]:.2f} |")
    out.append("")
    out.append("Inventory columns are the baseline for net/ammo-delta: every inventory change replaces the soldier's whole `Inventory.net_state` "
               "and ServerSync sends it whole; \"inventory KB/s\" is the encoded size (`var_to_bytes`) of the replacements this peer saw, "
               "per peer, before ENet's headers. The vitals columns count `Vitals.net_state` the same way (the next big one).")
    out.append("")
    for (p, kind), n in persistent_kind.items():
        if kind in ("condition", "ammo", "inventory", "objectives", "level", "missing", "ghost", "debrief"):
            problems.append(f"{p}: {n} persistent {kind} divergence mark(s)")
    for p in peers:
        if exits.get(p) not in ("0", "?"):
            problems.append(f"{p} exited {exits[p]}")
    verdict = "PASS" if not problems else "FAIL"
    out.insert(2, f"**Verdict: {verdict}**" + ("" if not problems else " — " + "; ".join(problems[:12])))
    out.insert(3, "")
    with open(os.path.join(run, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"report: {os.path.join(run, 'report.md')}")
    print(f"VERDICT {verdict} " + "; ".join(problems[:12]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
