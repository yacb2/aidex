#!/usr/bin/env python3
"""Defect-prone changes — names the E2E gap on a file that measurably breaks,
while the change is still in the working tree.

Not a standalone entry point by design (BL-133 criterion 2). BL-135's finding was
that the affected-tests resolver already existed and *nothing routed to it*;
shipping a second wrapper nobody calls would reproduce that exactly. This module
is called from affected_tests.py's human-readable render, so it rides a moment
the work already traverses and costs no extra step.

CONSUMER ONLY. The producer is a defect-proneness miner (bug items touching a
file / all items touching it, against the corpus base rate). It writes:

    .context/audits/test-coverage/defect-prone.jsonl

    line 1 (optional): {"meta": {"denominator": "all", "base_rate": 0.15,
                                 "ratio": 2.0, "min_touches": 8}}
    line n:            {"file": "<project-dir>/<workspace-rel-path>",
                        "share": 0.46, "bug": 6, "touches": 13, "flagged": true}

Absent file -> silent no-op. Unlike `_coverage_lib.load_map`, this must never
hard-exit: every existing affected-tests caller runs in a project that has no
such data file, and breaking them to add an advisory section is not a trade.

TWO TRAPS THIS FILE EXISTS TO HANDLE

1. Path namespace. The producer emits paths carrying a leading project-directory
   segment (`aidex/skills/x.py`); affected_tests.py works in workspace-relative
   paths (`skills/x.py`). A naive intersection returns zero matches on every
   project — an implausibly total negative that reads as "nothing is defect-prone"
   and is really a broken join. Rows are therefore prefix-stripped against the
   workspace basename (worktree suffix collapsed, matching the producer), and a
   data file where NO row carries the prefix says so out loud.

2. The denominator. The producer's typed/all fork moves the base rate ~3x, and at
   the high end nothing can clear the 2x threshold, so a data file regenerated
   with the wrong one is empty and looks correct. The meta line carries the choice
   and `denominator: typed` is called out rather than consumed silently.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _coverage_lib as lib
from coverage_matrix import E2E_SPEC_RE

DATA_REL = os.path.join(".context", "audits", "test-coverage", "defect-prone.jsonl")

# A migration is touched during bug work but is not a surface an E2E spec can
# cover, so flagging it asks for a test that cannot be written. Handed forward
# from the measure as a known limitation; kept deliberately narrow — anything
# broader starts suppressing real surfaces. Suppressed files are COUNTED, never
# dropped, per the house `waived: N` / `ignored: N` idiom.
NOT_COVERABLE = re.compile(r"(^|/)migrations?/")

WT_SUFFIX = re.compile(r"-wt-[\w.-]+$")


def workspace_prefix(root):
    """Leading segment the producer stamps on this workspace's paths.

    A worktree checkout (`aidex-wt-foo`) collapses onto the main path, because the
    producer collapses it too — otherwise one file's history splits across every
    branch that touched it.
    """
    return WT_SUFFIX.sub("", os.path.basename(os.path.abspath(root))) + "/"


def load(root):
    """-> (meta, {workspace_rel_path: row}, n_rows) or None when there is no data file."""
    path = os.path.join(root, DATA_REL)
    if not os.path.isfile(path):
        return None
    prefix = workspace_prefix(root)
    meta, rows, n_rows = None, {}, 0
    try:
        fh = open(path, errors="replace")
    except OSError:
        return None
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if isinstance(obj, dict) and "meta" in obj and "file" not in obj:
                meta = obj["meta"] or {}
                continue
            fp = (obj or {}).get("file")
            if not fp:
                continue
            n_rows += 1
            if fp.startswith(prefix):
                rows[fp[len(prefix):]] = obj
    return meta, rows, n_rows


def gap_for(path, modules, tracked):
    """Why this file has no E2E cover, or None when it is covered.

    A file matching no module is the worse gap of the two and is reported as
    such: the map cannot even locate where its spec would go.
    """
    # An explicitly excluded path (BL-229) is declared test scaffolding, not an
    # E2E gap: without this it falls through to `mod is None` and is reported as
    # the WORSE of the two gaps, which is the opposite of what declaring it said.
    if any(lib.matches(path, m.get("src_exclude", []) or []) for m in modules):
        return None
    mod = next((m for m in modules if lib.src_matches(path, m)), None)
    if mod is None:
        return "no module in the map — the gap cannot even be located"
    e2e_globs = lib.e2e_globs(mod)
    if not e2e_globs:
        return f"module {mod['id']} — no e2e tests mapped"
    # A tracked file under the glob is not a spec (a route-constants table sits
    # there too); the name filter is the matrix's, so the two agree.
    if not any(E2E_SPEC_RE.search(f) and lib.matches(f, e2e_globs) for f in tracked):
        return f"module {mod['id']} — e2e mapped but no spec files exist"
    return None


def section(root, repos, modules, changed_files):
    """Report block for the defect-prone files in this diff, or None if silent."""
    loaded = load(root)
    if loaded is None:
        return None
    meta, rows, n_rows = loaded

    # No row carries this workspace's prefix. With rows present that is a join
    # failure (wrong workspace, or a producer run elsewhere), not an all-clear —
    # and an all-clear is exactly how it would otherwise read.
    if n_rows and not rows:
        return (f"DEFECT-PRONE DATA — {n_rows} row(s), none for this workspace "
                f"(expected paths under {workspace_prefix(root)!r}) — "
                f"the data file was produced elsewhere; nothing was checked")

    # Decided before the no-hits return: the typed NOTE exists for the file that
    # flagged nothing, so it must print exactly when there is nothing else to print.
    note = None
    if (meta or {}).get("denominator") == "typed":
        note = ("NOTE: this data file was produced with --denominator typed, which "
                "raises the base rate ~3x and can leave nothing flagged. Regenerate "
                "with --denominator all if the list looks empty.")
    elif meta is None:
        note = ("NOTE: data file carries no meta line — base rate and denominator "
                "unknown, so the threshold behind these flags is unverifiable.")

    hits = [(rows[f], f) for f in sorted(set(changed_files))
            if f in rows and rows[f].get("flagged")]
    if not hits:
        return f"DEFECT-PRONE DATA — nothing flagged in this diff. {note}" if note else None

    suppressed = [f for _, f in hits if NOT_COVERABLE.search(f)]
    candidates = [(r, f) for r, f in hits if not NOT_COVERABLE.search(f)]

    tracked = lib.list_files(root, repos) if candidates else []
    gaps, covered = [], 0
    for row, f in sorted(candidates, key=lambda rf: -(rf[0].get("share") or 0)):
        why = gap_for(f, modules, tracked)
        if why is None:
            covered += 1
        else:
            gaps.append((row, f, why))

    lines = []
    base = (meta or {}).get("base_rate")
    ratio = (meta or {}).get("ratio")
    scale = (f" above {ratio:g}x the base bug rate ({base * 100:.1f}%)"
             if base is not None and ratio is not None else "")
    lines.append(f"DEFECT-PRONE CHANGES — {len(hits)} changed file"
                 f"{'s' if len(hits) != 1 else ''} in this diff measure{scale}")

    for row, f, why in gaps:
        share = (row.get("share") or 0) * 100
        lines.append(f"  {share:3.0f}%  ({row.get('bug', '?')}/{row.get('touches', '?')})  {f}")
        lines.append(f"        NO E2E: {why}")
    if gaps:
        lines.append("  Write the E2E spec BEFORE this change lands. It runs against a "
                     "disposable database, never dev (rules/e2e-testing.md).")
    if covered:
        lines.append(f"  covered: {covered} flagged file"
                     f"{'s' if covered != 1 else ''} already reached by e2e specs")
    if suppressed:
        lines.append(f"  suppressed: {len(suppressed)} migration"
                     f"{'s' if len(suppressed) != 1 else ''} "
                     "(not a surface an E2E spec can cover)")
    if note:
        lines.append("  " + note)
    return "\n".join(lines)
