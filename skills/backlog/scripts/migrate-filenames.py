#!/usr/bin/env python3
"""migrate-filenames.py — move open backlog items to YYYY-MM-DD-bl-nnn-<slug>.md.

Renames the active queue only (`backlog/` root; never `_archive/` or `_deferred/`)
and rewrites every inbound reference in the same pass. Dry-run unless --apply.

Three things gate an item, all reported rather than silently skipped:

  * no conforming `BL-NNN` id — there is nothing to put in the name. Run
    `--check-ids` and fix those first.
  * the filename appears in a git commit message — commit messages are the one
    surface nothing can rewrite, so those items stay where they are.
  * a duplicate id anywhere in the project — `--reindex` would fail afterwards.

Reference rewriting is literal on the stem, which also covers extension-less
`backlog/<stem>` refs and `[[wiki]]` links. Where a stem collides with the name of
some other artifact, the match is anchored on a `backlog/` prefix instead.

Usage:
  migrate-filenames.py [--root <path>] [--apply]
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time
from pathlib import Path

CONFORMING = re.compile(r"^BL-\d{3}$")
ID_FIELD = re.compile(r'^\s*id:\s*"?([^"\s]+)"?\s*$', re.M)
SCAN_SUFFIXES = {".md", ".html", ".json", ".txt", ".yml", ".yaml"}
SCAN_NAMES = {".aidex-waivers"}


def find_root(start: Path) -> Path:
    d = start.resolve()
    while d != d.parent:
        if (d / ".context").is_dir():
            return d
        d = d.parent
    return start.resolve()


def read_id(path: Path):
    m = ID_FIELD.search(path.read_text(errors="replace")[:4000])
    return m.group(1) if m else None


def memory_dir(root: Path):
    base = "-" + str(root).lstrip("/").replace("/", "-")
    for slug in (base, base.replace("_", "-")):
        d = Path.home() / ".claude" / "projects" / slug / "memory"
        if d.is_dir():
            return d
    return None


def commit_message_corpus(root: Path) -> str:
    out = []
    for git in root.rglob(".git"):
        if "node_modules" in str(git):
            continue
        try:
            r = subprocess.run(
                ["git", "-C", str(git.parent), "log", "--all", "--format=%B"],
                capture_output=True, text=True, timeout=180,
            )
            out.append(r.stdout)
        except Exception:
            pass
    return "\n".join(out)


def non_backlog_names(ctx: Path) -> set:
    """Every artifact name outside backlog/ — files by stem, folders by name."""
    names = set()
    for p in ctx.rglob("*"):
        s = str(p)
        if "/backlog/" in s or "/_tmp/" in s:
            continue
        if p.is_dir():
            names.add(p.name)
        elif p.suffix == ".md":
            names.add(p.stem)
    return names


def scan_targets(root: Path, ctx: Path):
    files = []
    for p in ctx.rglob("*"):
        if not p.is_file() or "/_tmp/" in str(p):
            continue
        if p.suffix in SCAN_SUFFIXES or p.name in SCAN_NAMES:
            files.append(p)
    claude_md = root / "CLAUDE.md"
    if claude_md.is_file():
        files.append(claude_md)
    md = memory_dir(root)
    if md:
        files.extend(p for p in md.rglob("*.md"))
    return files


def dangling_refs(ctx: Path) -> int:
    """Typed backlog/<file> refs whose target does not exist. The success criterion
    is that this number is unchanged, not that it is zero."""
    pat = re.compile(r"backlog/((?:_archive/|_deferred/)?\d{4}-\d{2}-\d{2}-[a-z0-9\-]+\.md)")
    present = set()
    for sub in (".", "_archive", "_deferred"):
        d = ctx / "backlog" / sub
        if d.is_dir():
            present |= {f.name for f in d.glob("*.md")}
    n = 0
    for p in ctx.rglob("*.md"):
        if "/_tmp/" in str(p):
            continue
        for m in pat.finditer(p.read_text(errors="replace")):
            if m.group(1).split("/")[-1] not in present:
                n += 1
    return n


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

    # --- classify the active queue -------------------------------------------
    items = [f for f in sorted(bl.glob("*.md")) if f.name != "00-index.md"]
    all_ids = {}
    for sub in (".", "_archive", "_deferred"):
        d = bl / sub
        if d.is_dir():
            for f in d.glob("*.md"):
                if f.name == "00-index.md":
                    continue
                i = read_id(f)
                if i:
                    all_ids.setdefault(i, []).append(f)
    dupes = {k for k, v in all_ids.items() if len(v) > 1}

    corpus = commit_message_corpus(root)
    rename, skipped = {}, []
    for f in items:
        i = read_id(f)
        if not i or not CONFORMING.match(i):
            skipped.append((f.name, f"id is {i or 'absent'}, not BL-NNN"))
            continue
        if i in dupes:
            skipped.append((f.name, f"id {i} is duplicated in this project"))
            continue
        if f.stem in corpus:
            skipped.append((f.name, "filename cited in a git commit message"))
            continue
        seg = i.lower()
        date, rest = f.name[:10], f.name[11:]
        if rest.startswith(seg + "-"):
            continue  # already migrated
        rename[f] = bl / f"{date}-{seg}-{rest}"

    print(f"to rename: {len(rename)}   skipped: {len(skipped)}   already done: "
          f"{len(items) - len(rename) - len(skipped)}")
    for name, why in skipped:
        print(f"  skip  {name}\n        {why}")
    if not rename:
        print("\nnothing to do")
        return 0

    # --- reference plan -------------------------------------------------------
    collide = non_backlog_names(ctx)
    stem_map = {f.stem: p.stem for f, p in rename.items()}
    # longest first so no stem can be rewritten inside another
    ordered = sorted(stem_map, key=len, reverse=True)
    anchored = {s for s in ordered if s in collide}

    targets = scan_targets(root, ctx)
    edits = {}
    for p in targets:
        try:
            txt = p.read_text(errors="replace")
        except Exception:
            continue
        new = txt
        for s in ordered:
            if s not in new:
                continue
            if s in anchored:
                new = re.sub(r"(backlog/(?:_archive/|_deferred/)?)" + re.escape(s),
                             lambda m: m.group(1) + stem_map[s], new)
            else:
                new = new.replace(s, stem_map[s])
        if new != txt:
            edits[p] = (txt, new, sum(txt.count(s) for s in ordered if s in txt))

    total_refs = sum(v[2] for v in edits.values())
    print(f"\nreferences: {total_refs} occurrence(s) across {len(edits)} file(s)")
    if anchored:
        print(f"  {len(anchored)} stem(s) anchored on a backlog/ prefix "
              f"(name collides with another artifact): {', '.join(sorted(anchored))}")

    base = dangling_refs(ctx)
    print(f"dangling backlog refs before: {base}")

    if not args.apply:
        print("\n(dry-run — re-run with --apply to write)")
        return 0

    # --- backup, then write ---------------------------------------------------
    tmp = root / "_tmp"
    tmp.mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = tmp / f"backlog-rename-{stamp}.tar.gz"
    with tarfile.open(backup, "w:gz") as tar:
        tar.add(ctx, arcname=".context")
    print(f"\nbackup: {backup}")

    for p, (_, new, _) in edits.items():
        p.write_text(new)
    for old, new in rename.items():
        old.rename(new)
    print(f"renamed {len(rename)} file(s), rewrote {total_refs} reference(s)")

    reindex = Path(__file__).with_name("register-item.sh")
    r = subprocess.run(["bash", str(reindex), "--reindex"], cwd=root,
                       capture_output=True, text=True)
    print(f"--reindex exit={r.returncode}")
    if r.returncode != 0:
        print(r.stdout[-800:] or r.stderr[-800:])

    after = dangling_refs(ctx)
    print(f"dangling backlog refs after:  {after}  "
          f"({'unchanged — OK' if after == base else 'CHANGED — investigate'})")
    return 0 if after == base and r.returncode == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
