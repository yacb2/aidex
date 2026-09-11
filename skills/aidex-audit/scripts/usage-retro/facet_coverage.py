#!/usr/bin/env python3
"""
facet_coverage.py — the coverage ledger of facet runs.

A facet run reads an explicit [from, to) window and records it here; the general
weekly cursor (`cursor.json`) is a watermark and is NEVER read or written by this
script. A cursor cannot say which windows were read on purpose; a ledger can.

Ledger shape (`.context/audits/.usage-retro/coverage.json`):
  { "<facet>": [ {"from": ISO, "to": ISO, "run": "<run folder name>"}, ... ] }

Usage:
  facet_coverage.py window --facet NAME [--since X] [--until Y] [--ledger PATH]
      -> prints "FROM TO label"; the default window is end of the facet's last
         covered window -> now; with no ledger or no entry it is `--since 60d`.
  facet_coverage.py record --facet NAME --from X --to Y --run DIR [--ledger PATH]
  facet_coverage.py gap    --facet NAME [--ledger PATH]
      -> days since the facet's last `to`, or "never".
"""
import argparse, datetime, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract import parse_bound   # one parser for `Nd` / ISO, shared with extract.py

DEFAULT_LEDGER = ".context/audits/.usage-retro/coverage.json"
DEFAULT_SINCE = "60d"

def now():
    return datetime.datetime.now(datetime.timezone.utc)

def load(path):
    """The ledger, or {} when the file does not exist. An unreadable file is a
    HARD ERROR, mirroring extract.resolve_cutoff on the cursor: guessing the
    window is the one thing a coverage instrument must not do."""
    if not os.path.exists(path):
        return {}
    try:
        data = json.load(open(path))
    except Exception as e:
        raise SystemExit(f"ERROR: coverage ledger {path} is unreadable or not valid "
                         f"JSON ({e}). Refusing to guess the window; repair or "
                         f"delete the ledger, or pass an explicit --since/--until.")
    if not isinstance(data, dict):
        raise SystemExit(f"ERROR: coverage ledger {path} is not a JSON object.")
    return data

def last_to(ledger, facet):
    spans = ledger.get(facet) or []
    tos = [parse_bound(s["to"]) for s in spans if s.get("to")]
    return max(tos) if tos else None

def bound(s, flag):
    t = parse_bound(s)
    if not t:
        raise SystemExit(f"ERROR: {flag} {s!r} is neither <N>d nor ISO.")
    return t

def cmd_window(a):
    ledger = load(a.ledger)
    until = bound(a.until, "--until") if a.until else now()
    if a.since:
        frm, label = bound(a.since, "--since"), "set by --since"
    else:
        prev = last_to(ledger, a.facet)
        if prev:
            frm, label = prev, "resumed from coverage ledger"
        else:
            frm = bound(DEFAULT_SINCE, "--since")
            label = (f"DEFAULT last {DEFAULT_SINCE}: no coverage recorded for "
                     f"facet {a.facet!r}" + ("" if os.path.exists(a.ledger)
                                             else f" ({a.ledger} does not exist)"))
    print(f"{frm.isoformat()} {until.isoformat()} {label}")

def cmd_record(a):
    ledger = load(a.ledger)
    frm, to = bound(a.frm, "--from"), bound(a.to, "--to")
    ledger.setdefault(a.facet, []).append(
        {"from": frm.isoformat(), "to": to.isoformat(), "run": a.run})
    d = os.path.dirname(a.ledger)
    if d:
        os.makedirs(d, exist_ok=True)
    json.dump(ledger, open(a.ledger, "w"), indent=2)
    print(f"recorded {a.facet}: {frm.isoformat()} -> {to.isoformat()} ({a.run}); "
          f"{len(ledger[a.facet])} window(s) on record")

def cmd_gap(a):
    prev = last_to(load(a.ledger), a.facet)
    print("never" if not prev else str((now() - prev).days))

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("window", "record", "gap"):
        p = sub.add_parser(name)
        p.add_argument("--facet", required=True)
        p.add_argument("--ledger", default=DEFAULT_LEDGER)
    sub.choices["window"].add_argument("--since")
    sub.choices["window"].add_argument("--until")
    sub.choices["record"].add_argument("--from", dest="frm", required=True)
    sub.choices["record"].add_argument("--to", required=True)
    sub.choices["record"].add_argument("--run", required=True)
    a = ap.parse_args()
    {"window": cmd_window, "record": cmd_record, "gap": cmd_gap}[a.cmd](a)

if __name__ == "__main__":
    main()
