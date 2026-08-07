#!/usr/bin/env python3
"""renumber-ids.py — make the open backlog queue's ids conforming BL-NNN.

Two cases, one pass:

  * an item with no `id:` at all   -> a fresh id is inserted after `title:`
  * an item with a nonconforming id -> a fresh id replaces it, and every citation
    of the old code is rewritten with it

`_archive/` and `_deferred/` items keep whatever id they carry. That is the point:
their codes are the ones cited from closed work, and leaving them alone keeps those
citations valid. New ids are allocated above the highest conforming id anywhere in
the project, so they can never collide with one.

This exists because migrate-ids.sh cannot do it. That script skips any file that
already has an id, and it feeds every id's digits into its max — so one legacy
`BL-20260610` pushes the sequence into the millions and every id it then mints is
nonconforming too (ns_backoffice would have minted BL-20260623, loom_lab
BL-202607056).

Citation rewriting is boundary-anchored, so `BL-20260705` never matches inside
`BL-20260705-3`.

Usage:
  renumber-ids.py [--root <path>] [--apply]
"""

import argparse
import re
import subprocess
import sys
import tarfile
import time
from pathlib import Path

CONFORMING = re.compile(r"^BL-\d{3}$")
ID_FIELD = re.compile(r'^(\s*id:\s*)"?([^"\s]+)"?\s*$', re.M)
TITLE_LINE = re.compile(r"^title:.*$", re.M)
SCAN_SUFFIXES = {".md", ".html", ".json", ".txt", ".yml", ".yaml"}
SCAN_NAMES = {".aidex-waivers"}


def find_root(start: Path) -> Path:
    d = start.resolve()
    while d != d.parent:
        if (d / ".context").is_dir():
            return d
        d = d.parent
    return start.resolve()


def front_matter_id(text: str):
    end = text.find("\n---", 4)
    head = text[: end if end > 0 else 4000]
    m = ID_FIELD.search(head)
    return m.group(2) if m else None


def memory_dir(root: Path):
    base = "-" + str(root).lstrip("/").replace("/", "-")
    for slug in (base, base.replace("_", "-")):
        d = Path.home() / ".claude" / "projects" / slug / "memory"
        if d.is_dir():
            return d
    return None


def scan_targets(root: Path, ctx: Path):
    files = [p for p in ctx.rglob("*")
             if p.is_file() and "/_tmp/" not in str(p)
             and (p.suffix in SCAN_SUFFIXES or p.name in SCAN_NAMES)]
    if (root / "CLAUDE.md").is_file():
        files.append(root / "CLAUDE.md")
    md = memory_dir(root)
    if md:
        files.extend(md.rglob("*.md"))
    return files


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=None)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    root = find_root(Path(args.root) if args.root else Path.cwd())
    ctx = root / ".context"
    bl = ctx / "backlog"
    if not bl.is_dir():
        print(f"no backlog dir at {bl}", file=sys.stderr)
        return 1

    print(f"project: {root}")
    print(f"mode:    {'APPLY' if args.apply else 'dry-run'}\n")

    # highest conforming id anywhere — new ids go above it so none can collide
    high = 0
    for sub in (".", "_archive", "_deferred"):
        d = bl / sub
        if not d.is_dir():
            continue
        for f in d.glob("*.md"):
            if f.name == "00-index.md":
                continue
            i = front_matter_id(f.read_text(errors="replace"))
            if i and CONFORMING.match(i):
                high = max(high, int(i[3:]))

    items = [f for f in sorted(bl.glob("*.md")) if f.name != "00-index.md"]
    assign, backfill = {}, {}      # path -> new id  (rewrite an old code / insert one)
    for f in items:
        txt = f.read_text(errors="replace")
        cur = front_matter_id(txt)
        if cur and CONFORMING.match(cur):
            continue
        if not TITLE_LINE.search(txt):
            print(f"  skip  {f.name}\n        no title: line in front-matter")
            continue
        high += 1
        new = f"BL-{high:03d}"
        (assign if cur else backfill)[f] = (cur, new)

    print(f"legacy ids to replace: {len(assign)}   ids to backfill: {len(backfill)}")
    for f, (old, new) in sorted(assign.items()):
        print(f"  {old:>16} -> {new}   {f.name}")
    for f, (_, new) in sorted(backfill.items()):
        print(f"  {'(none)':>16} -> {new}   {f.name}")
    if not assign and not backfill:
        print("\nnothing to do")
        return 0

    # --- citation rewrite plan for the replaced codes -------------------------
    code_map = {old: new for (old, new) in assign.values()}
    edits = {}
    if code_map:
        # boundary-anchored so BL-20260705 cannot match inside BL-20260705-3
        pat = re.compile(
            r"(?<![A-Za-z0-9-])(" + "|".join(re.escape(c) for c in
                                             sorted(code_map, key=len, reverse=True))
            + r")(?![A-Za-z0-9-])")
        for p in scan_targets(root, ctx):
            try:
                txt = p.read_text(errors="replace")
            except Exception:
                continue
            new_txt, n = pat.subn(lambda m: code_map[m.group(1)], txt)
            if n:
                edits[p] = (new_txt, n)
    total = sum(n for _, n in edits.values())
    print(f"\ncitations of replaced codes: {total} across {len(edits)} file(s)")

    if not args.apply:
        print("\n(dry-run — re-run with --apply to write)")
        return 0

    tmp = root / "_tmp"
    tmp.mkdir(exist_ok=True)
    backup = tmp / f"renumber-ids-{time.strftime('%Y%m%d-%H%M%S')}.tar.gz"
    with tarfile.open(backup, "w:gz") as tar:
        tar.add(ctx, arcname=".context")
    print(f"\nbackup: {backup}")

    # citation rewrite first — it also updates each renumbered item's own id: line
    for p, (new_txt, _) in edits.items():
        p.write_text(new_txt)
    # then insert ids where none existed
    for f, (_, new) in backfill.items():
        txt = f.read_text(errors="replace")
        f.write_text(TITLE_LINE.sub(lambda m: m.group(0) + f"\nid: {new}", txt, count=1))
    print(f"renumbered {len(assign)}, backfilled {len(backfill)}, "
          f"rewrote {total} citation(s)")

    check = Path(__file__).with_name("register-item.sh")
    r = subprocess.run(["bash", str(check), "--check-ids"], cwd=root,
                       capture_output=True, text=True)
    remaining = [l for l in (r.stdout + r.stderr).splitlines() if l.strip()]
    if remaining:
        print("--check-ids still reports (expected: only _archive/_deferred legacy):")
        for l in remaining[:8]:
            print("  " + l)
    else:
        print("--check-ids: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())
