#!/usr/bin/env python3
"""read_artifacts.py — the residue reader of the `artifacts` facet.

This folder is NOT a package on purpose: a `facets/__init__.py` next to `facets.py`
shadows the spec loader on import (a package dir wins over a module of the same
name), so every reader here is a standalone script that adds its parent to sys.path.

Walks every dated artifact page under `<projects-root>/*/.context/` — the SAME set
`mine_items.page_files` joins to sessions, active and `_archive/` alike — and reports
what the pages themselves say: kit version, consult round, items and how many are
decided, and the verdict of `check-artifact.sh` run on each file.

Grouped by kit VERSION BAND on purpose: `check-artifact.sh --census` skips `_archive/`
and `.aidex-artifact-prev/` by design (the census is the quality gate for pages
being edited, not an instrument), and a v9 page failing a v18 rule is a finding about
v9–v12 pages, never "pages fail". The checker runs per file here for that reason.

Prints `pages processed: N` LAST, always — a reader that saw nothing must say 0.

usage: read_artifacts.py --projects-root DIR [--checker PATH]
"""
import os, re, sys, glob, argparse, subprocess, collections

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import mine_items  # noqa: E402  (page_files, add_root_args)

CHECKER = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "aidex-dash",
                                        "scripts", "check-artifact.sh"))
META = re.compile(r'<meta\s+name=["\']?(artifact-kit|consult-round)["\']?\s+content=["\']?(\d+)', re.I)
ITEM = re.compile(r'<[a-zA-Z][\w:-]*\b[^>]*\bdata-id\s*=', re.I | re.S)
DECIDED = re.compile(r'\bdata-decided\b', re.I)
FAIL = re.compile(r'^\s*FAIL \[([^\]]+)\]', re.M)


def read_page(path, checker):
    txt = open(path, errors="replace").read()
    meta = {k.lower(): int(v) for k, v in META.findall(txt)}
    band = f"v{meta['artifact-kit']}" if "artifact-kit" in meta else "pre-wrapper"
    r = subprocess.run(["bash", checker, path], capture_output=True, text=True)
    return {
        "path": path, "band": band, "version": meta.get("artifact-kit", 0),
        "round": meta.get("consult-round", 0),
        "items": len(ITEM.findall(txt)), "decided": len(DECIDED.findall(txt)),
        "archived": "_archive" in path.split(os.sep),
        "ok": r.returncode == 0, "fails": sorted(set(FAIL.findall(r.stdout))),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mine_items.add_root_args(ap)
    ap.add_argument("--checker", default=CHECKER, help="check-artifact.sh to run per page")
    args = ap.parse_args()
    mine_items.configure(args)
    mine_items.require_projects_root()

    pages = []
    for ctx in sorted(glob.glob(os.path.join(mine_items.PROJ_ROOT, "*", ".context"))):
        for f in mine_items.page_files(ctx):
            pages.append(read_page(f, args.checker))

    bands = collections.defaultdict(list)
    for p in pages:
        bands[(p["version"], p["band"])].append(p)
    print("band          pages  archived  consult  items  decided  checker-ok")
    for (_, band), ps in sorted(bands.items()):
        print(f"{band:<13} {len(ps):>5}  {sum(p['archived'] for p in ps):>8}  "
              f"{sum(1 for p in ps if p['round']):>7}  {sum(p['items'] for p in ps):>5}  "
              f"{sum(p['decided'] for p in ps):>7}  {sum(p['ok'] for p in ps):>10}")

    # Which versions fail which check: the band range is the finding's subject.
    by_check = collections.defaultdict(set)
    for p in pages:
        for c in p["fails"]:
            by_check[c].add(p["version"])
    for c, vs in sorted(by_check.items()):
        lo, hi = min(vs), max(vs)
        span = ("pre-wrapper" if lo == 0 else f"v{lo}") + ("" if lo == hi else f"–v{hi}")
        n = sum(1 for p in pages if c in p["fails"])
        print(f"fail [{c}]: {n} page(s), {span}")
    print(f"pages processed: {len(pages)}")


if __name__ == "__main__":
    main()
