#!/usr/bin/env python3
"""quick-wins.py — a proposed attack order, read from front-matter and nothing else.

`triage.sh` already exists and answers a different question: item HEALTH — what is
malformed, stale, blocked, missing a field. It does not say what to do first. Nothing did
(RETRO-09 / BL-214).

This does, and the constraint is the feature: **it never opens a body.** Ordering forty
items by reading forty bodies is the expensive way to answer a question that `priority` and
`estimate` already answer, and an ordering that needed the bodies would be a judgement call
wearing a script's clothes. What comes out is a proposal to read in ten seconds, not a
decision.

Order: priority first (P0 -> P3), then cheapest estimate first inside each priority, then
oldest first — an old P2/XS has been cheap and ignored for longer than a new one.

Blocked items are listed apart. They are not quick wins whatever their estimate says, and
mixing them into the order is how a queue proposes work that cannot start.

Usage:
  quick-wins.py [<path-to-.context>] [--json OUT]

Exit 0 always: this proposes, it does not gate.
"""
import argparse, json, os, re, sys

PRIORITIES = ("P0", "P1", "P2", "P3")
ESTIMATES = ("XS", "S", "M", "L", "XL")
FIELD = {k: re.compile(rf"^{k}:\s*[\"']?(.*?)[\"']?\s*$", re.M)
         for k in ("id", "title", "status", "priority", "estimate", "blocked_by", "type")}


def read_frontmatter(path):
    """The front-matter block ONLY. Reads to the closing `---` and stops — the body is
    never touched, which is the whole point of this action rather than an implementation
    detail of it."""
    fields = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        if fh.readline().rstrip("\n") != "---":
            return fields
        block = []
        for line in fh:
            if line.rstrip("\n") == "---":
                break
            block.append(line)
    text = "".join(block)
    for key, rx in FIELD.items():
        m = rx.search(text)
        if m:
            fields[key] = m.group(1).strip()
    return fields


def sort_key(item):
    p = PRIORITIES.index(item["priority"]) if item["priority"] in PRIORITIES else len(PRIORITIES)
    e = ESTIMATES.index(item["estimate"]) if item["estimate"] in ESTIMATES else len(ESTIMATES)
    return (p, e, item["file"])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("context", nargs="?", default=None)
    ap.add_argument("--json", dest="json_out")
    args = ap.parse_args()

    ctx = os.path.abspath(args.context or ".context")
    base = os.path.join(ctx, "backlog")
    if not os.path.isdir(base):
        print(f"error: no backlog/ under {ctx}", file=sys.stderr)
        return 2

    items, blocked = [], []
    for name in sorted(os.listdir(base)):
        if not (name.endswith(".md") and not name.startswith("00-")):
            continue
        fm = read_frontmatter(os.path.join(base, name))
        if fm.get("status") not in ("open", "doing"):
            continue
        row = {"id": fm.get("id", "?"), "title": fm.get("title", ""),
               "priority": fm.get("priority", "?"), "estimate": fm.get("estimate", "?"),
               "type": fm.get("type", "?"), "status": fm.get("status", "?"),
               "blocked_by": fm.get("blocked_by", ""), "file": name}
        (blocked if row["blocked_by"] else items).append(row)

    items.sort(key=sort_key)
    blocked.sort(key=sort_key)

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump({"order": items, "blocked": blocked}, fh, indent=2)

    print(f"Proposed order — {len(items)} actionable, {len(blocked)} blocked "
          f"(front-matter only; no body was read)")
    if not items and not blocked:
        print("  nothing open")
        return 0

    cur = None
    for i, r in enumerate(items, 1):
        if r["priority"] != cur:
            cur = r["priority"]
            print(f"\n{cur}")
        print(f"  {i:2}. {r['id']:8} [{r['estimate']:2}] {r['type']:12} {r['title'][:64]}")

    if blocked:
        print(f"\nBlocked ({len(blocked)}) — not quick wins whatever the estimate says")
        for r in blocked:
            print(f"      {r['id']:8} [{r['estimate']:2}] blocked_by: {r['blocked_by'][:48]}")

    print("\n  A proposal, not a decision — `estimate` is what someone guessed, and this "
          "read no bodies.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
