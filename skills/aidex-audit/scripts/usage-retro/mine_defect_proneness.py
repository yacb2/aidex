#!/usr/bin/env python3
"""
mine_defect_proneness.py — which production files actually break, normalized.

BL-133 criterion 1. Raw recurrence counts rank the files we TOUCH most, not the
files that BREAK most: in this corpus the i18n locale files lead the raw bug-item
count (38 each) and are unremarkable once normalized (23%, near the base rate).
Any measure that would flag them is measuring centrality.

    defect-proneness(file) = bug items touching it / all items touching it

compared against the corpus base rate (the share of items that are bug items).
A file at 2x base with enough touches to be meaningful is defect-prone; a file
that merely appears everywhere lands near base by construction.

Attribution is inherited from mine_items.py and is provenance-gated: an item
counts as worked in a session only when its slug/ID appears in a real user prompt,
assistant text, or tool_use input — never inside a tool_result, because
backlog/00-index.md lists every item and would attribute the whole register to any
session that read the index.

TRAPS HANDLED
  - Worktree copies collapse onto the main path (`proj_ws-wt-slug/x` -> `proj_ws/x`),
    otherwise one file's history splits across every branch that touched it and no
    file ever clears the touch threshold.
  - Test files, .context/ artifacts and non-code are excluded: this measures
    production defect-proneness, and a test file changing is the response to a bug,
    not evidence the file is fragile.
  - `type:` is absent on older items (warn-then-ratchet, never retro-fixed), so the
    denominator is restricted to items that CARRY a type. Counting untyped items as
    non-bug would deflate every share toward zero. The excluded count is reported.
  - A minimum touch count applies (default 6): with 2 touches, one bug item reads
    as 50% and outranks everything real.

Read-only. Prints a report; writes nothing unless --out is given.
"""
import os, re, glob, json, argparse, sys
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mine_items as M

CODE = re.compile(r'\.(py|ts|tsx|js|jsx|vue|go|rs|java|rb|php|sql)$')
TESTISH = re.compile(r'(^|/)(tests?|spec|specs|__tests__|e2e)(/|$)|\.(spec|test)\.[a-z]+$')
WT = re.compile(r'^([\w.-]+?)(-wt-[\w.-]+)?/')
SCRATCH = re.compile(r'(^|/)(_tmp|scratchpad|node_modules|\.venv|dist|build)(/|$)|^/?(private/)?tmp/')


def is_production_code(fp):
    """Production source only. Scratch output is not production code and would
    otherwise top the ranking: `_tmp/analyze_render_loudness.py` at 80% and a
    session scratchpad's `mutants.py` at 50% both flagged before this filter,
    which is what throwaway diagnostic scripts look like by construction."""
    if not fp or not CODE.search(fp):
        return False
    if '/.context/' in fp or SCRATCH.search(fp):
        return False
    return not TESTISH.search(fp)


def collapse_worktree(path):
    """~/Documents/projects/echo_lab_ws-wt-foo/backend/x.py -> echo_lab_ws/backend/x.py"""
    marker = "/projects/"
    i = path.find(marker)
    rel = path[i + len(marker):] if i >= 0 else path.lstrip("/")
    return WT.sub(lambda m: m.group(1) + "/", rel, count=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-touches", type=int, default=6)
    ap.add_argument("--ratio", type=float, default=2.0, help="multiple of base rate")
    ap.add_argument("--out", default="")
    ap.add_argument("--denominator", choices=("typed", "all"), default="typed",
                    help="'typed': only items carrying a type: field (unbiased label, "
                         "biased sample). 'all': every attributed item, untyped counted "
                         "as non-bug (full sample, deflated label). They disagree by 3x; "
                         "see the report footer.")
    M.add_root_args(ap)
    args = ap.parse_args()
    M.configure(args)

    items = M.build_registry()
    # slug and id both address an item; either mention attributes the session.
    by_token, typed, bug, all_items = {}, set(), set(), set()
    for it in items:
        key = (it["project"], it["slug"])
        by_token[it["slug"]] = key
        if it.get("id"):
            by_token[it["id"]] = key
        # build_registry() does not carry `type` — reading it from the item dict
        # silently yielded an empty typed set and a "nothing to measure" result
        # that looked like a finding. Re-parse the front-matter for it.
        fm, _ = M.parse_fm(it["path"])
        t = ((fm or {}).get("type") or "").strip().lower()
        all_items.add(key)
        if t:
            typed.add(key)
            if t == "bug":
                bug.add(key)

    population = typed if args.denominator == "typed" else all_items
    projects = sorted({it["project"] for it in items})
    # file -> set of item keys that touched it
    touched = defaultdict(set)
    seen_items = set()

    for proj in projects:
        for f in [x for d in M.tx_dirs_for(proj) for x in glob.glob(d + "*.jsonl")]:
            mentioned, files = set(), set()
            try:
                fh = open(f, errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    try:
                        o = json.loads(line)
                    except (ValueError, TypeError):
                        continue
                    if o.get("type") == "user":
                        for tok in M.TOKEN.findall(M.user_text(o) or ""):
                            if tok in by_token:
                                mentioned.add(by_token[tok])
                    elif o.get("type") == "assistant":
                        txt, tools = M.assistant_parts(o)
                        for tok in M.TOKEN.findall(txt or ""):
                            if tok in by_token:
                                mentioned.add(by_token[tok])
                        # assistant_parts yields (name, searchable, file_path, command)
                        for name, searchable, fp, _cmd in tools:
                            for tok in M.TOKEN.findall(searchable):
                                if tok in by_token:
                                    mentioned.add(by_token[tok])
                            if name in ("Edit", "Write", "NotebookEdit") and fp \
                                    and is_production_code(fp):
                                files.add(collapse_worktree(fp))
            # A session that worked several items attributes its files to each; that
            # is the same convention mine_items uses and it is why the threshold matters.
            for key in mentioned & population:
                seen_items.add(key)
                for fp in files:
                    touched[fp].add(key)

    if not seen_items:
        print("no typed items attributed — nothing to measure")
        return 1

    base = len(seen_items & bug) / len(seen_items)
    print(f"denominator            : {args.denominator}")
    print(f"items attributed       : {len(seen_items)}  "
          f"(bug {len(seen_items & bug)})")
    print(f"base rate              : {base*100:.1f}% of items are bug items")
    print(f"production files        : {len(touched)}  "
          f"(threshold >={args.min_touches} touches, flag >={args.ratio}x base)\n")

    rows = []
    for fp, keys in touched.items():
        n = len(keys)
        if n < args.min_touches:
            continue
        b = len(keys & bug)
        rows.append((b / n, b, n, fp))
    rows.sort(reverse=True)

    thresh = base * args.ratio
    flagged = [r for r in rows if r[0] >= thresh]
    print(f"flagged: {len(flagged)} of {len(rows)} files above {thresh*100:.1f}%\n")
    print(f"{'share':>7} {'bug':>4} {'all':>4}  file")
    for share, b, n, fp in flagged[:30]:
        print(f"{share*100:6.0f}% {b:4d} {n:4d}  {fp}")

    print("\n== does it generalise? flagged files per project ==")
    per = defaultdict(lambda: [0, 0])
    for share, b, n, fp in rows:
        p = fp.split("/", 1)[0]
        per[p][1] += 1
        if share >= thresh:
            per[p][0] += 1
    print(f"{'project':26} {'flagged':>8} {'eligible':>9} {'rate':>7}")
    for p, (fl, tot) in sorted(per.items(), key=lambda kv: -kv[1][0]):
        print(f"{p:26} {fl:8d} {tot:9d} {fl/tot*100:6.0f}%")

    if args.out:
        with open(args.out, "w") as fh:
            # Leading meta line: the consumer (aidex-audit coverage/defect_prone.py)
            # needs the denominator to refuse a `typed` run, which flags 0 of 201 and
            # is therefore indistinguishable from a clean result without it.
            fh.write(json.dumps({"meta": {
                "denominator": args.denominator, "base_rate": base,
                "ratio": args.ratio, "min_touches": args.min_touches}}) + "\n")
            for share, b, n, fp in rows:
                fh.write(json.dumps({"file": fp, "share": share, "bug": b,
                                     "touches": n, "flagged": share >= thresh}) + "\n")
        print(f"\nwrote {len(rows)} rows -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
