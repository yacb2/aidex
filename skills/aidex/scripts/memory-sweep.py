#!/usr/bin/env python3
"""memory-sweep.py — audit every Claude Code memory directory against rules/memory-hygiene.md.

READ-ONLY BY CONSTRUCTION. It prints findings and the exact command that would fix each
one; it never deletes, moves or rewrites anything. That is deliberate: memory files are
unversioned and ungitignored-by-nature, so a wrong sweep is unrecoverable (the reason
`.aidex-waivers` was lost on 2026-08-03 was a tool that wrote where it was only asked to
read).

Checks, each keyed to a clause of the rule:

  MEM-LOG    a memory over the word budget — a session log wearing a memory's front-matter
  MEM-TYPE   no `type:` front-matter, so recall cannot classify it
  MEM-TMP    a memory directory under a throwaway project path (/tmp, /private/var/folders)
  MEM-DUP    byte-identical memory directories — a project-path slug collision
  MEM-INDEX  a MEMORY.md index over the always-on budget

Exit 0 when clean, 1 when any finding exists, so a hook or CI step can gate on it.

Usage:
  memory-sweep.py                 # every project
  memory-sweep.py --project aidex # substring match on the project slug
  memory-sweep.py --json out.json
"""
from __future__ import annotations

import argparse
import collections
import glob
import hashlib
import json
import os
import re
import sys

# Overridable so the sweep can be tested against a fixture tree. A checker with no
# adversarial test is the exact pattern the 2026-07-25 audit named ("checkers lie by
# omission"), so this one ships with one.
PROJECTS = os.environ.get("AIDEX_MEMORY_ROOT") or os.path.expanduser("~/.claude/projects")

# Budgets. Both come from rules/memory-hygiene.md — keep them in lockstep with it.
# 800 is the p90 of the 416 memories measured 2026-08-06 (median 277w): it flags the
# tail where session logs actually live without burying it in 113 dense-but-legitimate
# facts, which is what a 400w budget did on the first run.
MEMORY_WORD_BUDGET = 800
INDEX_WORD_BUDGET = 1200

TYPE_RX = re.compile(r"^\s*type:\s*(\S+)", re.M)
TEMP_MARKERS = ("-private-tmp", "-private-var-folders", "-tmp-", "-var-folders")


def words(path: str) -> int:
    try:
        return len(open(path, errors="replace").read().split())
    except OSError:
        return 0


def memory_dirs(filter_sub: str | None) -> list[str]:
    out = []
    for d in sorted(glob.glob(os.path.join(PROJECTS, "*", "memory"))):
        if not os.path.isdir(d):
            continue
        if filter_sub and filter_sub not in d:
            continue
        out.append(d)
    return out


def project_of(path: str) -> str:
    """The project slug a memory dir belongs to (its parent directory's name)."""
    return os.path.basename(os.path.dirname(path.rstrip("/")))


def sweep(dirs: list[str]) -> list[dict]:
    findings: list[dict] = []
    by_digest: dict[str, list[str]] = collections.defaultdict(list)

    for d in dirs:
        proj = project_of(d)

        if any(m in proj for m in TEMP_MARKERS):
            findings.append({
                "rule": "MEM-TMP", "project": proj, "path": d,
                "detail": "memory directory under a throwaway project path — the harness "
                          "wrote it, no session will ever read it",
                "fix": f'rm -rf "{d}"',
            })

        files = sorted(glob.glob(os.path.join(d, "*.md")))
        digest = hashlib.sha256()
        for f in files:
            if os.path.basename(f) == "MEMORY.md":
                continue
            with open(f, "rb") as fh:
                digest.update(fh.read())
            w = words(f)
            body = open(f, errors="replace").read()
            if w > MEMORY_WORD_BUDGET:
                findings.append({
                    "rule": "MEM-LOG", "project": proj, "path": f,
                    "detail": f"{w}w (budget {MEMORY_WORD_BUDGET}) — read it: if it narrates "
                              f"a run, it belongs in .context/, not memory",
                    "fix": "split into one-fact files, or move the narrative to .context/",
                })
            if not TYPE_RX.search(body):
                findings.append({
                    "rule": "MEM-TYPE", "project": proj, "path": f,
                    "detail": "no `type:` front-matter (user | feedback | project | reference)",
                    "fix": "add a type: line to the front-matter",
                })
        if files:
            by_digest[digest.hexdigest()].append(d)

        index = os.path.join(d, "MEMORY.md")
        if os.path.isfile(index):
            iw = words(index)
            if iw > INDEX_WORD_BUDGET:
                findings.append({
                    "rule": "MEM-INDEX", "project": proj, "path": index,
                    "detail": f"{iw}w always-on (budget {INDEX_WORD_BUDGET}) — every line is "
                              f"paid for in every session of this project",
                    "fix": "shorten hooks to one line each; drop entries whose work has closed",
                })

    for group in by_digest.values():
        if len(group) > 1:
            findings.append({
                "rule": "MEM-DUP", "project": project_of(group[0]),
                "path": ", ".join(project_of(g) for g in group),
                "detail": f"{len(group)} byte-identical memory directories — a project-path "
                          f"slug collision, not {len(group)} projects",
                "fix": "keep the directory whose project path still exists; remove the others",
            })

    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", help="substring match on the project slug")
    ap.add_argument("--json", help="write findings to this path as JSON")
    args = ap.parse_args()

    dirs = memory_dirs(args.project)
    findings = sweep(dirs)

    total_files = sum(
        1 for d in dirs for f in glob.glob(os.path.join(d, "*.md"))
        if os.path.basename(f) != "MEMORY.md"
    )
    print(f"{len(dirs)} memory director{'y' if len(dirs) == 1 else 'ies'} · "
          f"{total_files} memories", flush=True)

    if args.json:
        with open(args.json, "w") as fh:
            json.dump({"dirs": len(dirs), "memories": total_files,
                       "findings": findings}, fh, indent=1)

    if not findings:
        print("clean — nothing over budget, every memory typed, no throwaway or duplicate dirs")
        return 0

    by_rule = collections.defaultdict(list)
    for f in findings:
        by_rule[f["rule"]].append(f)
    for rule in ("MEM-TMP", "MEM-DUP", "MEM-INDEX", "MEM-LOG", "MEM-TYPE"):
        rows = by_rule.get(rule)
        if not rows:
            continue
        print(f"\n[{rule}] {len(rows)}")
        for r in rows:
            print(f"  {r['project']}")
            print(f"    {r['path']}")
            print(f"    {r['detail']}")
            print(f"    fix: {r['fix']}")

    print(f"\n{len(findings)} finding(s). Nothing was changed — this sweep only reports.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
