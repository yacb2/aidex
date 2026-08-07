#!/usr/bin/env python3
"""estimate-calibration.py — score closed items' `estimate:` against the effort
they actually cost.

BL-131. Item-level cost mining over 1,320 tracked items found `estimate: XS|S|M|L|XL`
carries essentially no information about realized effort: the medians are flat across
the whole scale (5-9 edits from XS to XL) and only p90/max spread. The felt problem —
"an item that described how to solve it still cost hours" — is a **tail-detection**
failure, not a spec-quality one.

READ, NEVER A GATE. This prints a calibration and exits 0. It is deliberately not
wired into register/start/close, and nothing here may block a run: per
`rules/autonomy.md`, questions belong to the initial phase and an unattended run does
not halt for a signal. It is also not a prompt for a better estimate — the study says
the human signal is the broken thing, so the remedy is measurement feedback, not a
more insistent ask. Adding a field to the spec template is explicitly out of scope.

NO SINGLE ACCURACY NUMBER, deliberately. One would average the flat median together
with the spreading tail and hide the only thing the measurement found.

Effort comes from the usage-retro miner (BL-132), over WORKING spans only — a span
counts as a working session when a user prompt named the item or it carries >=3 edits.
Without that rule "sessions per item" inflates about 2x.

Usage:
  estimate-calibration.py [--from <dir>] [--project <name>]
                          [--projects-root <p>] [--transcripts-root <p>]

  --from <dir>   reuse a previous miner run (a dir holding items.jsonl + spans.jsonl)
                 instead of mining again. A full run takes ~4 minutes.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
from collections import defaultdict

BUCKETS = ["XS", "S", "M", "L", "XL"]
MINER = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "..", "aidex-audit", "scripts", "usage-retro", "mine_items.py"))


def pct(values, q):
    """Nearest-rank percentile. Buckets get as small as n=5, where an interpolating
    percentile invents a value that no item ever cost."""
    if not values:
        return 0
    s = sorted(values)
    k = max(0, min(len(s) - 1, int(round(q * (len(s) - 1)))))
    return s[k]


def median(values):
    return pct(values, 0.5)


def run_miner(out_dir, args):
    cmd = [sys.executable, MINER, "--out", out_dir]
    if args.projects_root:
        cmd += ["--projects-root", args.projects_root]
    if args.transcripts_root:
        cmd += ["--transcripts-root", args.transcripts_root]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(f"ERROR: miner failed: {res.stderr.strip() or res.stdout.strip()}")


def load(d):
    def rows(name):
        path = os.path.join(d, name)
        if not os.path.isfile(path):
            sys.exit(f"ERROR: no {name} in {d} — run without --from to mine first")
        with open(path) as fh:
            return [json.loads(line) for line in fh if line.strip()]
    return rows("items.jsonl"), rows("spans.jsonl")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="from_dir", default="",
                    help="dir holding a previous run's items.jsonl + spans.jsonl")
    ap.add_argument("--project", default="", help="restrict to one project")
    ap.add_argument("--projects-root", default="")
    ap.add_argument("--transcripts-root", default="")
    args = ap.parse_args()

    tmp = None
    src = args.from_dir
    if not src:
        tmp = tempfile.mkdtemp(prefix="estimate-calibration-")
        run_miner(tmp, args)
        src = tmp
    items, spans = load(src)

    if args.project:
        items = [i for i in items if i["project"] == args.project]
        spans = [s for s in spans if s["project"] == args.project]

    # Working spans only: this is the strict-span rule the miner encodes as a field.
    effort = defaultdict(lambda: {"edits": 0, "turns": 0, "sessions": 0})
    for s in spans:
        if not s.get("working"):
            continue
        e = effort[(s["project"], s["slug"])]
        e["edits"] += s.get("edits", 0)
        e["turns"] += s.get("user_turns", 0)
        e["sessions"] += 1

    # Exclusions are COUNTED, never silently dropped — the same convention as
    # `waived: N` elsewhere. A calibration over a quietly-filtered population is
    # how a flat scale gets mistaken for a well-calibrated one.
    scored, n_open, n_noest, n_nowork = [], 0, 0, 0
    for it in items:
        if (it.get("status") or "").strip().lower() != "done":
            n_open += 1
            continue
        est = (it.get("estimate") or "").strip().upper()
        if est not in BUCKETS:
            n_noest += 1
            continue
        e = effort.get((it["project"], it["slug"]))
        if not e:
            n_nowork += 1
            continue
        scored.append((est, e))

    total = len(items)
    print(f"ESTIMATE CALIBRATION — {len(scored)} closed items with an estimate "
          f"and measurable work")
    print(f"  corpus: {total} items | excluded: {n_open} not closed, "
          f"{n_noest} no estimate, {n_nowork} no measurable work")
    if not scored:
        print("\nnothing to score. Not a finding — check the population above first.")
        return 0

    for label, key in (("EDITS", "edits"), ("USER TURNS", "turns"),
                       ("WORKING SESSIONS", "sessions")):
        print(f"\n  Realized {label} per item")
        print(f"  {'estimate':>8} {'n':>6} {'median':>8} {'p90':>6} {'max':>6}")
        for b in BUCKETS:
            vals = [e[key] for est, e in scored if est == b]
            if not vals:
                continue
            print(f"  {b:>8} {len(vals):6d} {median(vals):8d} "
                  f"{pct(vals, 0.9):6d} {max(vals):6d}")

    # Tail risk. The scale being flat at the median is only half the finding; the
    # other half is that a small number of items carries most of the cost, and a
    # per-bucket median cannot show that.
    print("\nTAIL RISK — a per-bucket median cannot show this")
    for label, key in (("edits", "edits"), ("user turns", "turns")):
        vals = sorted((e[key] for _, e in scored), reverse=True)
        tot = sum(vals)
        if not tot:
            continue
        top = vals[:max(1, len(vals) // 10)]
        print(f"  top decile absorbs {sum(top) / tot * 100:4.0f}% of all {label:<11}"
              f"(median item: {median(vals)})")

    print("\nHOW TO READ THIS. If the medians are flat across XS..XL while p90 and max "
          "spread,\nthe scale is not measuring size — it is a tail-detection problem. "
          "No single\naccuracy number is printed: averaging the flat middle with the "
          "spreading tail\nwould hide exactly that. This is a read; it gates nothing.")
    print("\nPOPULATION, stated because it moves the answer. Effort counts WORKING spans "
          "only\n(a user prompt named the item, or >=3 edits) over items whose status is "
          "`done`.\nMeasured 2026-08-07 on the full corpus, dropping that rule and "
          "counting every span\nflattens the medians from 6/7/10/17 to 5/6/7/14 — the "
          "same undated-denominator trap\nthat has now fired three times in this study. "
          "Never compare two runs across it.")
    if tmp:
        print(f"\n(miner output kept at {tmp} — pass --from to reuse it)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
