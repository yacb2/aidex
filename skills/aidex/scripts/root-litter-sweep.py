#!/usr/bin/env python3
"""root-litter-sweep.py — what has accumulated at the workspace root, and around it?

The ecosystem auditor's covered domains stop at a project's `.claude/` and `.context/`.
Everything outside them stays invisible to it, so the litter the user kept finding by hand
— holding folders that only grow, loose files dropped at the workspace root, a repo cloned
next to the projects and forgotten, permissions naming a command that is gone — was never
anything the auditor could report (RETRO-50 / BL-224).

READ-ONLY, and deliberately so. It reports and offers; it never deletes, never moves, never
rewrites a settings file. Several categories here are things a person may keep on purpose —
`_archive/` is a decision, not a mistake — and a sweep that acted on its own findings would
be wrong about some of them every time.

Each finding is classified `aidex` or `foreign`: whether aidex is known to create that
thing. That matters because "aidex left this behind" is a bug in aidex, while "you left
this here" is information. The two must not read the same.

Usage:
  root-litter-sweep.py [--root ~/Documents/projects] [--json OUT]

Exit 0 always: this is a census, not a gate.
"""
import argparse, json, os, shutil, sys, time

DEFAULT_ROOT = os.path.expanduser("~/Documents/projects")

# Folders at the WORKSPACE root that exist to hold things temporarily and, left alone,
# only grow. `_tmp/` inside a project is canonical scratch (claudemd-conventions.md);
# at the workspace root it belongs to nobody and nothing cleans it.
HOLDING_NAMES = {"_toDelete", "_todelete", "_backups", "_archive", "_sandbox",
                 "_smoke", "_tests", "_tmp", "_scratch", "_old"}

# Files aidex itself is known to create. Anything else at the root is `foreign`.
AIDEX_ARTIFACTS = {".aidex-backups"}

# A directory is a workspace PROJECT (not a stray repo) if it carries one of these.
PROJECT_MARKERS = ("CLAUDE.md", ".context", ".claude")

IGNORE_ROOT_FILES = {".DS_Store"}


def dir_stats(path):
    """(entry count, days since the newest entry was modified). Shallow on purpose —
    walking a multi-gigabyte `_backups/` to print one number is not worth the seconds."""
    try:
        entries = os.listdir(path)
    except OSError:
        return 0, None
    newest = 0.0
    for e in entries:
        try:
            newest = max(newest, os.path.getmtime(os.path.join(path, e)))
        except OSError:
            continue
    age = int((time.time() - newest) / 86400) if newest else None
    return len(entries), age


def find_in_project_backups(root):
    """The `.aidex-backups` regression guard. Its root cause was fixed in 1627663
    (backups moved to ~/.claude/aidex/backups/), so the expected count is zero — which is
    exactly why it is worth checking: a silent return of this is how the fix comes
    undone without anyone noticing."""
    out = []
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name, ".aidex-backups")
        if os.path.isdir(p):
            n, age = dir_stats(p)
            out.append({"category": "in-project-backups", "owner": "aidex", "path": p,
                        "detail": f"{n} entries, newest {age}d old" if age is not None else f"{n} entries",
                        "offer": "aidex writes backups to ~/.claude/aidex/backups/ since 1627663 — "
                                 "this predates that fix, or something recreated it"})
    return out


def find_holding_folders(root):
    out = []
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if not os.path.isdir(p) or name not in HOLDING_NAMES:
            continue
        n, age = dir_stats(p)
        out.append({"category": "holding-folder", "owner": "foreign", "path": p,
                    "detail": f"{n} entries, newest {age}d old" if age is not None else f"{n} entries",
                    "offer": "review and empty it, or rename it to something that says what it keeps"})
    return out


def find_loose_files(root):
    out = []
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if not os.path.isfile(p) or name in IGNORE_ROOT_FILES:
            continue
        owner = "aidex" if name in AIDEX_ARTIFACTS else "foreign"
        out.append({"category": "loose-file", "owner": owner, "path": p,
                    "detail": f"{os.path.getsize(p)} B",
                    "offer": "move it into the project it belongs to, or into a dated folder"})
    return out


def find_stray_repos(root):
    """A git repo sitting among the projects that is not itself a workspace project:
    no CLAUDE.md, no .context/, no .claude/. Usually a clone made once to read
    something. Reported, never judged — some are deliberate."""
    out = []
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if not os.path.isdir(p) or not os.path.isdir(os.path.join(p, ".git")):
            continue
        if any(os.path.exists(os.path.join(p, m)) for m in PROJECT_MARKERS):
            continue
        n, age = dir_stats(p)
        out.append({"category": "stray-repo", "owner": "foreign", "path": p,
                    "detail": f"git repo, {n} entries, newest {age}d old" if age is not None
                              else f"git repo, {n} entries",
                    "offer": "if it is a reference clone, move it under a folder that says so; "
                             "if it is a real project, give it a CLAUDE.md"})
    return out


def find_dead_permissions(root):
    """Permissions naming a command that is not installed.

    RETRO-50 phrased this as "dead `dt` permissions left behind by tooling that is
    gone". Checked 2026-08-24: `dt` IS on PATH and no settings file anywhere names it,
    so that specific instance no longer exists. Hardcoding it would ship a detector for
    a premise that is false. The mechanism generalises cleanly instead — a `Bash(x ...)`
    permission whose `x` cannot be found is dead whatever `x` is."""
    out = []
    for name in sorted(os.listdir(root)):
        proj = os.path.join(root, name)
        if not os.path.isdir(proj):
            continue
        for settings in ("settings.json", "settings.local.json"):
            sp = os.path.join(proj, ".claude", settings)
            if not os.path.isfile(sp):
                continue
            try:
                data = json.loads(open(sp, encoding="utf-8").read())
            except (OSError, ValueError):
                continue
            perms = data.get("permissions") or {}
            seen = set()
            for bucket in ("allow", "deny", "ask"):
                for entry in perms.get(bucket) or []:
                    if not (isinstance(entry, str) and entry.startswith("Bash(")):
                        continue
                    cmd = entry[5:].split(":", 1)[0].split(" ", 1)[0].strip(")").strip()
                    if not cmd or "/" in cmd or cmd in seen:
                        continue
                    seen.add(cmd)
                    if shutil.which(cmd) is None:
                        out.append({"category": "dead-permission", "owner": "foreign",
                                    "path": f"{sp}: {entry}",
                                    "detail": f"'{cmd}' is not on PATH",
                                    "offer": "the tool is gone or renamed — drop the entry, "
                                             "or reinstall the tool"})
    return out


SCANNERS = (find_in_project_backups, find_holding_folders, find_loose_files,
            find_stray_repos, find_dead_permissions)

CATEGORY_ORDER = ["in-project-backups", "stray-repo", "dead-permission",
                  "holding-folder", "loose-file"]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=DEFAULT_ROOT)
    ap.add_argument("--json", dest="json_out")
    args = ap.parse_args()

    root = os.path.expanduser(args.root)
    if not os.path.isdir(root):
        print(f"error: no such workspace root: {root}", file=sys.stderr)
        return 2

    findings = []
    for scan in SCANNERS:
        findings.extend(scan(root))

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump({"root": root, "findings": findings}, fh, indent=2)

    print(f"Workspace-root litter — {root}")
    if not findings:
        print("  nothing to report")
        return 0

    by_cat = {}
    for f in findings:
        by_cat.setdefault(f["category"], []).append(f)
    print(f"  {len(findings)} item(s) in {len(by_cat)} categor{'y' if len(by_cat) == 1 else 'ies'}"
          f" — read-only: nothing below was changed\n")

    for cat in CATEGORY_ORDER:
        rows = by_cat.get(cat)
        if not rows:
            continue
        print(f"{cat} ({len(rows)})")
        for f in rows:
            print(f"  [{f['owner']:7}] {f['path']}")
            print(f"            {f['detail']} — {f['offer']}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
