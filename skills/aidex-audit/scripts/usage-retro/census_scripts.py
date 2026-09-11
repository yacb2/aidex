#!/usr/bin/env python3
"""
census_scripts.py — which suite scripts and skills actually run, per bucket and per
agent, over the transcript tool events.

Promoted from the session scratchpad that produced the 2026-09-11 consultation's
script table (usage-retro-facets, phase 1): a script outside the tracked tree has
no test the suite runs (BL-165).

Every number is per BUCKET (`aidex-dev` vs `real-usage`, from extract.bucket_for)
and per AGENT (`main` vs `sub`), and "calls" is kept apart from "sessions" because
one session retrying a command 300 times is one session. A `cat`/`sed`/`grep` of a
script path is a READ, reported in its own column and never as an execution.

Read-only. Prints the number of transcript files walked, so an empty walk is
visible as one.

Usage:
  census_scripts.py [--transcripts-root DIR] [--since 60d|ISO] [--until 7d|ISO] [--top N]
"""
import os, re, sys, glob, argparse, datetime, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mine_items
from extract import parse_ts


def parse_bound(s):
    if not s:
        return None
    m = re.fullmatch(r"(\d+)d", s.strip())
    if m:
        return (datetime.datetime.now(datetime.timezone.utc)
                - datetime.timedelta(days=int(m.group(1))))
    t = parse_ts(s)
    if t is None:
        sys.exit(f"ERROR: window bound must be <N>d or an ISO timestamp, got {s!r}")
    return t


def count_files(tx_root):
    return (len(glob.glob(tx_root.rstrip("/") + "/*/*.jsonl"))
            + len(glob.glob(tx_root.rstrip("/") + "/*/*/subagents/*.jsonl")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcripts-root", default=mine_items.TX_ROOT)
    ap.add_argument("--since", default="")
    ap.add_argument("--until", default="")
    ap.add_argument("--top", type=int, default=40)
    args = ap.parse_args()
    root = os.path.abspath(os.path.expanduser(args.transcripts_root))
    since, until = parse_bound(args.since), parse_bound(args.until)

    # key -> {(bucket, agent): calls / sessions / reads}
    calls = collections.defaultdict(collections.Counter)
    reads = collections.defaultdict(collections.Counter)
    sessions = collections.defaultdict(lambda: collections.defaultdict(set))
    skills = collections.defaultdict(collections.Counter)
    skill_sessions = collections.defaultdict(lambda: collections.defaultdict(set))
    n_events = 0
    for ev in mine_items.iter_tool_events(root, since=since, until=until):
        n_events += 1
        cell = (ev["bucket"], ev["agent"])
        if ev["tool"] == "Skill":
            skills[ev["command"]][cell] += 1
            skill_sessions[ev["command"]][cell].add(ev["session"])
            continue
        if not ev["script"]:
            continue
        if ev["read_only"]:
            reads[ev["script"]][cell] += 1
            continue
        calls[ev["script"]][cell] += 1
        sessions[ev["script"]][cell].add(ev["session"])

    print(f"transcript files walked: {count_files(root)}  ({n_events} tool events in window)")
    cells = [("aidex-dev", "main"), ("aidex-dev", "sub"), ("real-usage", "main"), ("real-usage", "sub")]
    head = "  ".join(f"{b[:5]}/{a}" for b, a in cells)

    print(f"\nskill fires — calls/sessions per bucket/agent\n{'skill':52} {head}")
    ranked = sorted(skills, key=lambda k: -sum(skills[k].values()))[:args.top]
    for k in ranked:
        row = "  ".join(f"{skills[k][c]:>4}/{len(skill_sessions[k][c]):<4}" for c in cells)
        print(f"{k[:52]:52} {row}")

    print(f"\nscript executions — calls/sessions per bucket/agent, reads apart\n"
          f"{'script':52} {head}  reads")
    keys = set(calls) | set(reads)
    ranked = sorted(keys, key=lambda k: -sum(calls[k].values()))[:args.top]
    for k in ranked:
        row = "  ".join(f"{calls[k][c]:>4}/{len(sessions[k][c]):<4}" for c in cells)
        print(f"{k[:52]:52} {row}  {sum(reads[k].values())}")
    if not keys:
        print("(no script paths in any tool event — nothing to rank)")


if __name__ == "__main__":
    main()
