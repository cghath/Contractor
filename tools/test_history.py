"""Test history page (docs/debugging.md, planned item 4): pass/fail per suite over the kept runs,
flaky suites flagged, the checks that fail most.

    python tools/test_history.py [logs folder] [runs to show]

Reads every <logs>/<date>/R*/summary.txt (tools/run_tests.sh writes them; the folder defaults to
Contractor-test-logs beside the main checkout, as the runner finds it) and writes
<logs>/history.html. Standard library only. A suite is flaky when it both passed and failed on
the same commit; one that fails every time on a commit is broken there, not flaky. (A local run on
uncommitted edits is named after its base commit, so those can look flaky too.)
"""
import html
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

HEADER = re.compile(r"^run (R\d+), (\S+) (\S+), (.*)$")
VERDICT = re.compile(r"^([a-z_]+(?: host)?): (.+)$")
FAIL_LINE = re.compile(r"^\s+([a-z_]+(?: host)?)\s+\[FAIL\] (.*)$")


def logs_folder() -> str:
    if len(sys.argv) > 1:
        return sys.argv[1]
    env = os.environ.get("CONTRACTOR_TEST_LOGS", "")
    if env and env != "none":
        return env
    try:
        common = subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True).strip()
        main = os.path.dirname(os.path.abspath(common))
        return os.path.join(os.path.dirname(main), "Contractor-test-logs")
    except (OSError, subprocess.CalledProcessError):
        return "Contractor-test-logs"


def read_runs(parent: str) -> list:
    runs = []
    for day in sorted(os.listdir(parent)):
        folder = os.path.join(parent, day)
        if not os.path.isdir(folder):
            continue
        for name in os.listdir(folder):
            summary = os.path.join(folder, name, "summary.txt")
            if not name.startswith("R") or not os.path.isfile(summary):
                continue
            run = {"suites": {}, "fails": defaultdict(list)}
            with open(summary, encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.rstrip("\n")
                    m = HEADER.match(line)
                    if m:
                        run.update(id=m.group(1), date=m.group(2), time=m.group(3), branch=m.group(4))
                        continue
                    m = FAIL_LINE.match(line)
                    if m:
                        run["fails"][m.group(1)].append(m.group(2).strip())
                        continue
                    m = VERDICT.match(line)
                    if m and m.group(1) not in ("suites", "result"):
                        run["suites"][m.group(1)] = m.group(2).strip() == "passed"
            if "id" in run and run["suites"]:
                run["sha"] = run["branch"].rsplit("-", 1)[-1]
                runs.append(run)
    runs.sort(key=lambda r: int(r["id"][1:]))
    return runs


def build(runs: list, show: int) -> str:
    suites = sorted({s for r in runs for s in r["suites"]})
    by_sha = defaultdict(lambda: defaultdict(set))
    for r in runs:
        for s, ok in r["suites"].items():
            by_sha[s][r["sha"]].add(ok)
    flaky = {s: sorted(sha for sha, seen in by_sha[s].items() if seen == {True, False}) for s in suites}
    rate = {}
    for s in suites:
        seen = [r["suites"][s] for r in runs if s in r["suites"]]
        rate[s] = (sum(seen), len(seen))
    common = Counter((s, t) for r in runs for s, lines in r["fails"].items() for t in lines)
    recent = runs[-show:]
    esc = html.escape
    rows = []
    for s in suites:
        cells = []
        for r in recent:
            if s not in r["suites"]:
                cells.append('<td class="none"></td>')
            elif r["suites"][s]:
                cells.append('<td class="ok" title="%s passed"></td>' % esc(r["id"]))
            else:
                why = "; ".join(r["fails"].get(s, [])) or "failed"
                cells.append('<td class="bad" title="%s: %s"></td>' % (esc(r["id"]), esc(why)))
        passed, total = rate[s]
        tag = ' <span class="flaky" title="passed and failed on %s">flaky</span>' % esc(", ".join(flaky[s])) if flaky[s] else ""
        rows.append('<tr><th>%s%s</th><td class="rate">%d/%d</td>%s</tr>' % (esc(s), tag, passed, total, "".join(cells)))
    head = "".join('<th class="run" title="%s %s %s">%s</th>' % (esc(r["date"]), esc(r["time"]), esc(r["branch"]), esc(r["id"][1:]))
                   for r in recent)
    fails = "".join("<li><b>%s</b> %s <span class=\"n\">x%d</span></li>" % (esc(s), esc(t), n) for (s, t), n in common.most_common(25))
    flaky_list = "".join("<li><b>%s</b>: on %s</li>" % (esc(s), esc(", ".join(v))) for s, v in flaky.items() if v) or "<li>none</li>"
    return """<!doctype html><html><head><meta charset="utf-8"><title>Test history</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root{--bg:#f7f7f4;--fg:#1f1f1c;--muted:#6b6b63;--ok:#3f8f4f;--bad:#c2412d;--none:#e4e4dd;--line:#d6d6cd}
@media (prefers-color-scheme: dark){:root{--bg:#18181a;--fg:#e8e8e2;--muted:#9a9a92;--ok:#4caf62;--bad:#e05a44;--none:#2a2a2d;--line:#333336}}
body{background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,sans-serif;margin:16px}
h1{font-size:20px;margin:0 0 4px}p{color:var(--muted);margin:0 0 16px}
.wrap{overflow-x:auto}table{border-collapse:separate;border-spacing:2px}
th{text-align:left;font-weight:600;white-space:nowrap;padding-right:8px}
th.run{font-weight:400;color:var(--muted);font-size:11px;writing-mode:vertical-rl;transform:rotate(180deg);padding:0}
td{width:14px;height:18px;border-radius:3px}td.ok{background:var(--ok)}td.bad{background:var(--bad)}td.none{background:var(--none)}
td.rate{width:auto;color:var(--muted);font-size:12px;padding-right:8px;white-space:nowrap}
.flaky{background:#d9a400;color:#1f1f1c;border-radius:3px;padding:0 4px;font-size:11px;font-weight:600}
h2{font-size:16px;margin:24px 0 6px}ul{margin:0;padding-left:18px}li{margin:2px 0}.n{color:var(--muted)}
</style></head><body>
<h1>Test history</h1><p>%d runs kept, the last %d shown (oldest left). Hover a cell for its run and failing checks.</p>
<div class="wrap"><table><tr><th></th><th></th>%s</tr>%s</table></div>
<h2>Flaky: passed and failed on the same commit</h2><ul>%s</ul>
<h2>Checks that failed most</h2><ul>%s</ul>
</body></html>""" % (len(runs), len(recent), head, "".join(rows), flaky_list, fails or "<li>none</li>")


def main() -> None:
    parent = logs_folder()
    show = int(sys.argv[2]) if len(sys.argv) > 2 else 40
    runs = read_runs(parent)
    out = os.path.join(parent, "history.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(build(runs, show))
    print("test_history: %d runs, page written to %s" % (len(runs), out))


if __name__ == "__main__":
    main()
