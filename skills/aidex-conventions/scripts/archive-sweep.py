#!/usr/bin/env python3
"""archive-sweep.py — one pass over every tier that has an `_archive/`, not four by hand.

D-10 says a `done` / `dropped` / `superseded` artifact moves to its tier's `_archive/`
immediately on close. Enforcement existed for exactly one tier: `aidex-backlog/sweep.sh`
batch-archives backlog items. Plans, audits and requests each have their own `_archive/`
and no sweep at all, so closing out a cycle meant walking four tiers and remembering four
conventions — which is how D-10 ends up applied to the backlog and skipped everywhere else
(RETRO-13 / BL-215).

Two reports, because "not archived" and "should not still be open" are different mistakes:

  unarchived  — status is terminal, the artifact is still in the active folder
  status-drift — status is still `open`/`doing`, but every commit the artifact cites has
                 landed in git. Not proof it is done; proof nobody looked since.

DEFAULT IS A DRY RUN. `--apply` moves the unarchived set and nothing else — status drift is
never resolved automatically, because deciding an item is finished is a judgement about the
work, not about git.

Usage:
  archive-sweep.py [<path-to-.context>] [--apply] [--check] [--json OUT]

  --check  dry run that EXITS 1 when anything would move, for a gate. The plain dry run
           exits 0 whatever it finds, which is right for a human and useless to a caller.

Exit 0 clean or after --apply; 1 under --check with pending moves; 2 on a usage error.
"""
import argparse, json, os, re, shutil, subprocess, sys

TERMINAL = {"done", "dropped", "superseded"}
ACTIVE = {"open", "doing"}
FM_STATUS = re.compile(r"^status:\s*[\"']?([a-z-]+)[\"']?\s*$", re.M)
FM_COMMITS = re.compile(r"^commits:\s*[\"']?(.*?)[\"']?\s*$", re.M)
SHA = re.compile(r"\b[0-9a-f]{7,40}\b")


def frontmatter(path):
    """status and cited commits, read from the first front-matter block only. Deliberately
    not a YAML parse: this walks whole trees, and every other script here reads the same
    two fields the same shallow way."""
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read(8192)
    except OSError:
        return None, []
    if not text.startswith("---"):
        return None, []
    end = text.find("\n---", 3)
    block = text[3:end] if end != -1 else text
    s = FM_STATUS.search(block)
    c = FM_COMMITS.search(block)
    return (s.group(1) if s else None), (SHA.findall(c.group(1)) if c else [])


def commit_landed(repo, sha):
    try:
        r = subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{sha}^{{commit}}"],
                           capture_output=True, timeout=10)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def tier_units(ctx, tier):
    """The archivable UNIT per tier, which is not the same shape in each one.

    plans/  a plan is either one .md or a whole modular folder — the folder is the unit,
            and its status lives in 00-index.md.
    audits/ the unit is a dated run folder under audits/<methodology>/, and D-10 archives
            it to audits/_archive/, not into the methodology folder.
    backlog/, requests/  flat .md files.

    Yields (unit_path, status_file, archive_dir).
    """
    base = os.path.join(ctx, tier)
    if not os.path.isdir(base):
        return
    archive = os.path.join(base, "_archive")

    if tier in ("backlog", "requests"):
        for name in sorted(os.listdir(base)):
            p = os.path.join(base, name)
            if os.path.isfile(p) and name.endswith(".md") and not name.startswith("00-"):
                yield p, p, archive
        return

    if tier == "plans":
        for name in sorted(os.listdir(base)):
            p = os.path.join(base, name)
            if name in ("_archive", "00-index.md"):
                continue
            if os.path.isfile(p) and name.endswith(".md"):
                yield p, p, archive
            elif os.path.isdir(p):
                idx = os.path.join(p, "00-index.md")
                if os.path.isfile(idx):
                    yield p, idx, archive
        return

    if tier == "audits":
        for meth in sorted(os.listdir(base)):
            mp = os.path.join(base, meth)
            if meth == "_archive" or not os.path.isdir(mp):
                continue
            for run in sorted(os.listdir(mp)):
                rp = os.path.join(mp, run)
                if not os.path.isdir(rp):
                    continue
                idx = os.path.join(rp, "index.md")
                if os.path.isfile(idx):
                    yield rp, idx, archive


TIERS = ("plans", "audits", "requests", "backlog")


def scan(ctx, repo):
    unarchived, drift = [], []
    for tier in TIERS:
        for unit, status_file, archive in tier_units(ctx, tier):
            status, commits = frontmatter(status_file)
            if status is None:
                continue
            rel = os.path.relpath(unit, ctx)
            if status in TERMINAL:
                unarchived.append({"tier": tier, "path": rel, "status": status,
                                   "archive_to": os.path.relpath(
                                       os.path.join(archive, os.path.basename(unit)), ctx)})
            elif status in ACTIVE and commits and repo:
                landed = [c for c in commits if commit_landed(repo, c)]
                if landed and len(landed) == len(commits):
                    drift.append({"tier": tier, "path": rel, "status": status,
                                  "commits": landed})
    return unarchived, drift


# The `<type>/` marker a cross-reference uses is not the folder name (§3 of
# 00-global). Mirrors validate.py's TYPE_FOLDER_TO_PREFIX for the tiers this
# script walks; anything else yields no companion lookup rather than a wrong one.
TIER_PREFIX = {"plans": "plan", "audits": "audit", "requests": "request",
               "backlog": "backlog"}


def _archive_companions(ctx, rel_path, archive_to):
    """Move an artifact's rendered .html companions in after it.

    Delegates to `_lib.sh`'s archive_companions rather than re-deriving which page
    belongs to which entry. That mapping is the artifact-anchor `<meta>` contract,
    already implemented twice — validate.py owns the regexes and _lib.sh carries a
    deliberate second copy bound to it by comment. A third copy here is how the
    prompt-classifier and parse_ts forks happened, so this shells out instead.

    Why it is needed at all: `shutil.move` above takes the .md and nothing else,
    and both walkers match `*.md` exclusively, so a companion page was never even a
    candidate. Detection did not cover it either — crossref_target_exists searches
    _archive/ as well, so the stranded page's anchor still resolves and
    artifact-anchor-target-missing stays quiet. Never fails the sweep: a companion
    that cannot move is reported, not a reason to undo an archive that happened.
    """
    tier = rel_path.split("/", 1)[0]
    prefix = TIER_PREFIX.get(tier)
    if not prefix:
        return ""
    ref = f"{prefix}/{os.path.basename(rel_path)}"
    dest = os.path.join(ctx, os.path.dirname(archive_to))
    lib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_lib.sh")
    try:
        r = subprocess.run(["bash", "-c",
                            f'. "$1"; archive_companions "$2" "$3" "$4"',
                            "_", lib, ctx, ref, dest],
                           capture_output=True, text=True, timeout=60)
        return (r.stdout or "") + (r.stderr or "")
    except (OSError, subprocess.SubprocessError) as e:
        return f"companion sweep skipped for {ref}: {e}\n"


def apply_moves(ctx, unarchived):
    moved, refused = [], []
    for row in unarchived:
        src = os.path.join(ctx, row["path"])
        dst = os.path.join(ctx, row["archive_to"])
        if os.path.exists(dst):
            refused.append((row["path"], "destination already exists"))
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        try:
            shutil.move(src, dst)
            moved.append(row["path"])
        except OSError as e:
            refused.append((row["path"], str(e)))
            continue
        # AFTER the move: archive_companions reads current paths, so a page that
        # travelled inside a moved folder is recognised and left alone.
        out = _archive_companions(ctx, row["path"], row["archive_to"])
        if out.strip():
            sys.stderr.write(out)
    return moved, refused


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("context", nargs="?", default=None)
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--json", dest="json_out")
    args = ap.parse_args()

    if args.apply and args.check:
        print("error: --apply and --check are opposites; pick one", file=sys.stderr)
        return 2

    ctx = os.path.abspath(args.context or ".context")
    if not os.path.isdir(ctx):
        print(f"error: no .context/ at {ctx}", file=sys.stderr)
        return 2
    repo = os.path.dirname(ctx)
    # `.git` is tested with `exists`, not `isdir`: in a linked worktree it is a FILE
    # holding a gitdir pointer, and isdir() there disabled this half silently (BL-351,
    # the same predicate BL-344 fixed in memory-sweep.py).
    if not os.path.exists(os.path.join(repo, ".git")):
        repo = None  # status drift needs git; without it, report the other half only

    unarchived, drift = scan(ctx, repo)

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump({"context": ctx, "unarchived": unarchived, "status_drift": drift},
                      fh, indent=2)

    print(f"Archive sweep — {ctx}")
    if not unarchived and not drift:
        print("  every tier is clean: nothing terminal left unarchived, no status drift")
        return 0

    if unarchived:
        by_tier = {}
        for r in unarchived:
            by_tier.setdefault(r["tier"], []).append(r)
        verb = "moving" if args.apply else "would move"
        print(f"\nunarchived ({len(unarchived)}) — terminal status, still in the active "
              f"folder (D-10); {verb}:")
        for tier in TIERS:
            for r in by_tier.get(tier, []):
                print(f"  [{r['status']:10}] {r['path']}")
                print(f"               -> {r['archive_to']}")

    if drift:
        print(f"\nstatus-drift ({len(drift)}) — still open, but every commit it cites has "
              f"landed.\n  Not proof it is done; proof nobody looked since. Never moved "
              f"automatically:")
        for r in drift:
            print(f"  [{r['status']:10}] {r['path']}  ({', '.join(c[:8] for c in r['commits'])})")

    if repo is None:
        print("\n  note: no git repo above .context/, so status drift was not checked at all")

    if args.apply:
        moved, refused = apply_moves(ctx, unarchived)
        print(f"\napplied: {len(moved)} moved, {len(refused)} refused")
        for path, why in refused:
            print(f"  REFUSED {path} — {why}")
        print("  indexes are NOT regenerated here — run each tier's own reindexer "
              "(register-item.sh --reindex, reindex-plans.sh, reindex-audits.sh)")
        return 0

    if args.check and unarchived:
        return 1
    print("\n  dry run — nothing was moved. Re-run with --apply to archive the first list.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
