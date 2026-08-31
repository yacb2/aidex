#!/usr/bin/env python3
"""Build the memory-cleanup work-list from an audit run, and verify it was applied.

The work-list is GENERATED, never transcribed: a hand parse of the same verdict
tables reproduced the published totals only to within a few counts, which is the
drift this script removes.

Two outputs, deliberately separate files:

  <run>-memory-cleanup.md           roster-derived, stable, carries the `ratified:`
                                    stamp. `--check` diffs this one.
  <run>-memory-cleanup-appendix.md  disk-derived, regenerated at the start of every
                                    cleanup phase. Never ratified, never executed.

The split exists because disk is an input that changes under us (other sessions
write memories while this runs), and a reconciliation that invalidated the
ratified table would make every cleanup phase re-ask for approval.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import sys
from pathlib import Path

# The rubric's closed vocabulary. A verdict outside it is an auditor violation,
# not a dialect to extend: it goes to the appendix and is never executed.
VERDICTS = [
    "KEEP",
    "REWRITE",
    "DELETE-DUP",
    "DELETE-CLOSED",
    "DELETE-LOG",
    "MOVE-BACKLOG",
    "MOVE-CLAUDEMD",
    "MOVE-REFERENCE",
    "MOVE-DECISION",
    "MOVE-RESEARCH",
    "MOVE-SKILL",
    "MOVE-GLOBAL",
]
# Verdicts that leave the source memory file on disk.
SURVIVES = {"KEEP", "REWRITE"}

MEMORY_ROOT = Path(os.environ.get("AIDEX_MEMORY_ROOT", Path.home() / ".claude" / "projects"))
BACKUP_ROOT = Path(
    os.environ.get("AIDEX_BACKUP_ROOT", Path.home() / ".claude" / "aidex" / "backups" / "memory")
)

# The slug runs to the first `·`; it may itself name several directories separated
# by " / " (`# -a / -b / -c  ·  3 memories each`), which a `\S+` capture drops silently.
HEADER_RE = re.compile(r"^#\s+(?P<slug>-[^·]*?)\s+·\s+(?P<rest>.*)$")
PATH_RE = re.compile(r"project path:\s*(?P<path>\S+)")


class Row:
    __slots__ = ("slug", "filename", "verdict", "destination", "raw_verdict", "problem")

    def __init__(self, slug, filename, verdict, destination, raw_verdict, problem=""):
        self.slug = slug
        self.filename = filename
        self.verdict = verdict
        self.destination = destination
        self.raw_verdict = raw_verdict
        self.problem = problem

    @property
    def key(self):
        return (self.slug, self.filename)


def _cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def parse_run(run_dir: Path) -> tuple[list[Row], list[Row], list[str]]:
    """Return (executable rows, unplaceable rows, notes)."""
    ok: list[Row] = []
    bad: list[Row] = []
    notes: list[str] = []

    for src in sorted(run_dir.glob("*.md")):
        if src.name == "RUBRIC.md":
            continue
        slug = None
        multi_slug = False
        matched_any = False
        in_verdicts = False
        for line in src.read_text(encoding="utf-8").splitlines():
            if line.startswith("# "):
                in_verdicts = False
                m = HEADER_RE.match(line)
                if m:
                    raw_slug = m.group("slug")
                    multi_slug = " / " in raw_slug
                    slug = raw_slug.split(" / ")[0].strip()
                    matched_any = True
                else:
                    slug = None
                continue
            if line.startswith("## "):
                in_verdicts = line.startswith("## Verdicts")
                continue
            if not (in_verdicts and slug and line.startswith("|")):
                continue
            cells = _cells(line)
            if len(cells) < 5:
                continue
            if cells[0].lower() == "file" or set(cells[0]) <= {"-", ":"}:
                continue
            filename, verdict = cells[0], cells[3]
            destination = cells[4] if len(cells) > 4 else ""
            # Auditors wrote the filename bare, in backticks, or as a link.
            filename = filename.strip("`").strip()
            if multi_slug:
                bad.append(Row(slug, filename, None, destination, verdict,
                               "ambiguous slug: section header names several directories"))
            elif verdict in VERDICTS:
                ok.append(Row(slug, filename, verdict, destination, verdict))
            else:
                bad.append(Row(slug, filename, None, destination, verdict,
                               "verdict outside the rubric vocabulary"))
        if not matched_any:
            notes.append(f"{src.name}: no project header matched")
    return ok, bad, notes


def _front_matter_field(path: Path, field: str) -> str:
    if not path.exists():
        return ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("---") and line.strip() == "---" and field == "":
            break
        if line.startswith(f"{field}:"):
            return line.split(":", 1)[1].strip()
        if line.strip() == "---" and line != "---":
            break
    return ""


def render_worklist(run_date: str, rows: list[Row], bad: list[Row], ratified: str) -> str:
    by_slug: dict[str, dict[str, int]] = {}
    for r in rows:
        by_slug.setdefault(r.slug, {}).setdefault(r.verdict, 0)
        by_slug[r.slug][r.verdict] += 1

    out = []
    out.append("---")
    out.append(f'title: "Memory cleanup work-list {run_date}"')
    out.append("status: open")
    out.append(f"created: {run_date}")
    out.append(f"updated: {run_date}")
    out.append(f"source: _tmp/memory-audit-{run_date}/")
    out.append("generated_by: skills/aidex/scripts/build-memory-worklist.py")
    out.append(f"ratified: {ratified}")
    out.append("---")
    out.append("")
    out.append(f"# Memory cleanup work-list — {run_date}")
    out.append("")
    out.append("Generated. Do not hand-edit: `--check` regenerates and diffs, and an edit")
    out.append("here would be erased. The `ratified:` stamp is preserved across regeneration.")
    out.append("")
    out.append("## Approval table")
    out.append("")
    out.append("One row per project, one column per verdict class. Approval is granted once")
    out.append("over the whole table; it is granular per project × class, its collection is not.")
    out.append("")
    out.append("| slug | " + " | ".join(VERDICTS) + " | total |")
    out.append("|---" * (len(VERDICTS) + 2) + "|")
    totals = {v: 0 for v in VERDICTS}
    for slug in sorted(by_slug):
        counts = by_slug[slug]
        cells = []
        for v in VERDICTS:
            n = counts.get(v, 0)
            totals[v] += n
            cells.append(str(n) if n else "")
        out.append(f"| `{slug}` | " + " | ".join(cells) + f" | {sum(counts.values())} |")
    out.append("| **TOTAL** | " + " | ".join(str(totals[v]) for v in VERDICTS)
               + f" | {sum(totals.values())} |")
    out.append("")
    out.append(f"Projects: {len(by_slug)} · executable rows: {len(rows)} · "
               f"survives on disk (KEEP/REWRITE): {sum(1 for r in rows if r.verdict in SURVIVES)} · "
               f"leaves disk: {sum(1 for r in rows if r.verdict not in SURVIVES)}")
    out.append("")
    out.append("## Files")
    out.append("")
    out.append("The executable rows. Phases 6-8 walk this table.")
    out.append("")
    out.append("| slug | file | verdict | destination |")
    out.append("|---|---|---|---|")
    for r in sorted(rows, key=lambda r: (r.slug, r.filename)):
        dest = r.destination.replace("|", "\\|")
        out.append(f"| `{r.slug}` | `{r.filename}` | {r.verdict} | {dest} |")
    out.append("")
    out.append("## Unplaceable — excluded from execution")
    out.append("")
    out.append("Rows the parser refused to place. They are NOT deleted, NOT moved, and NOT")
    out.append("counted above; they are reported at close-out for the owner to decide.")
    out.append("")
    if bad:
        out.append("| slug | file | raw verdict | why |")
        out.append("|---|---|---|---|")
        for r in sorted(bad, key=lambda r: (r.slug, r.filename)):
            raw = r.raw_verdict.replace("|", "\\|")
            out.append(f"| `{r.slug}` | `{r.filename}` | {raw} | {r.problem} |")
    else:
        out.append("None.")
    out.append("")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------- disk

def disk_slugs() -> dict[str, list[str]]:
    """slug -> sorted list of memory filenames (excluding MEMORY.md)."""
    found = {}
    if not MEMORY_ROOT.exists():
        return found
    for d in sorted(MEMORY_ROOT.iterdir()):
        mem = d / "memory"
        if mem.is_dir():
            found[d.name] = sorted(
                p.name for p in mem.glob("*.md") if p.name != "MEMORY.md"
            )
    return found


def reconcile(rows: list[Row], bad: list[Row], run_date: str) -> str:
    roster = {r.key for r in rows} | {r.key for r in bad}
    roster_slugs = {r.slug for r in rows} | {r.slug for r in bad}
    disk = disk_slugs()

    gone, appeared, empty = [], [], []
    for slug in sorted(roster_slugs):
        if slug not in disk:
            empty.append(slug)
    for slug, files in disk.items():
        for fn in files:
            if (slug, fn) not in roster:
                appeared.append((slug, fn))
    for (slug, fn) in sorted(roster):
        if fn not in disk.get(slug, []):
            gone.append((slug, fn))

    checks = _load_checks()
    out = []
    out.append("---")
    out.append(f'title: "Memory cleanup appendix (disk reconciliation) {run_date}"')
    out.append("status: open")
    out.append(f"created: {run_date}")
    out.append(f"updated: {run_date}")
    out.append("generated_by: skills/aidex/scripts/build-memory-worklist.py --reconcile")
    out.append("---")
    out.append("")
    out.append(f"# Appendix — roster vs. disk, regenerated {run_date}")
    out.append("")
    out.append("Regenerated at the start of every cleanup phase. NOT ratified and NOT")
    out.append("executed: a memory written by a parallel session must never be deleted as")
    out.append("an unlisted row.")
    out.append("")
    out.append(f"Roster rows: {len(roster)} · on disk now: {sum(len(v) for v in disk.values())} "
               f"across {len(disk)} directories")
    out.append("")
    out.append("## On disk, not in the roster — classified by the Phase 1 content tests")
    out.append("")
    if appeared:
        out.append("| slug | file | content tests | route |")
        out.append("|---|---|---|---|")
        for slug, fn in sorted(appeared):
            ids = _run_checks(checks, slug, MEMORY_ROOT / slug / "memory" / fn)
            route = "KEEP (passes)" if not ids else "appendix row"
            out.append(f"| `{slug}` | `{fn}` | {', '.join(ids) if ids else 'pass'} | {route} |")
    else:
        out.append("None.")
    out.append("")
    out.append("## In the roster, not on disk — no-op")
    out.append("")
    if gone:
        out.append("| slug | file |")
        out.append("|---|---|")
        for slug, fn in gone:
            out.append(f"| `{slug}` | `{fn}` |")
    else:
        out.append("None.")
    out.append("")
    out.append("## Roster slugs with no memory directory on disk")
    out.append("")
    out.append(", ".join(f"`{s}`" for s in empty) if empty else "None.")
    out.append("")
    return "\n".join(out) + "\n"


def _load_checks():
    """Import CHECKS from the sweep. One implementation, several consumers."""
    import importlib.util

    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("memory_sweep", here / "memory-sweep.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _run_checks(mod, slug: str, path: Path) -> list[str]:
    """The Phase 1 content tests, run through the sweep's own CHECKS — not reimplemented."""
    try:
        body = path.read_text(encoding="utf-8")
    except OSError:
        return ["unreadable"]
    memdir = str(path.parent)
    siblings = sorted(str(q) for q in path.parent.glob("*.md")
                      if q.name not in (path.name, "MEMORY.md"))
    ctx = mod.Ctx(slug, memdir, siblings)
    ids = []
    for name, fn in mod.CHECKS.items():
        try:
            for finding in fn(str(path), body, ctx) or []:
                ids.append(finding["rule"])
        except Exception as exc:                       # a check that errors must not
            ids.append(f"{name}:error")                # silently look like a pass
    return sorted(set(ids))


# ------------------------------------------------------------------------- backup

def do_backup(rows: list[Row], run_date: str) -> int:
    dest_root = BACKUP_ROOT / run_date
    dest_root.mkdir(parents=True, exist_ok=True)
    manifest = [("slug", "file", "verdict", "sha256")]
    copied = 0
    for r in sorted(rows, key=lambda r: (r.slug, r.filename)):
        if r.verdict == "KEEP":
            continue
        src = MEMORY_ROOT / r.slug / "memory" / r.filename
        if not src.exists():
            continue
        dst = dest_root / r.slug / r.filename
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        manifest.append((r.slug, r.filename, r.verdict,
                         hashlib.sha256(src.read_bytes()).hexdigest()))
        copied += 1
    # Everything else on disk too: files a parallel session wrote are not in the
    # roster, and the backup is what makes these deletions reversible rather than
    # class 1. Costing ~2 MB, "back up only what we plan to touch" is the wrong trade.
    rostered = {(r.slug, r.filename) for r in rows}
    for slug, files in sorted(disk_slugs().items()):
        for fn in files:
            if (slug, fn) in rostered:
                continue
            src = MEMORY_ROOT / slug / "memory" / fn
            dst = dest_root / slug / fn
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            manifest.append((slug, fn, "UNROSTERED",
                             hashlib.sha256(src.read_bytes()).hexdigest()))
            copied += 1
    for slug in sorted(disk_slugs()):
        src = MEMORY_ROOT / slug / "memory" / "MEMORY.md"
        if src.exists():
            dst = dest_root / slug / "MEMORY.md"
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            manifest.append((slug, "MEMORY.md", "INDEX",
                             hashlib.sha256(src.read_bytes()).hexdigest()))
            copied += 1
    (dest_root / "MANIFEST.tsv").write_text(
        "\n".join("\t".join(r) for r in manifest) + "\n", encoding="utf-8"
    )
    os.chmod(dest_root / "MANIFEST.tsv", 0o600)
    print(f"backup: {copied} files -> {dest_root}")
    return 0


def verify_backup(run_date: str) -> int:
    """Restore one file from the backup to a scratch path and compare shas."""
    import random
    import tempfile

    dest_root = BACKUP_ROOT / run_date
    manifest = dest_root / "MANIFEST.tsv"
    if not manifest.exists():
        print(f"FAIL: no manifest at {manifest}")
        return 1
    lines = [l.split("\t") for l in manifest.read_text().splitlines()[1:] if l.strip()]
    if not lines:
        print("FAIL: manifest is empty")
        return 1
    slug, fn, verdict, sha = random.choice(lines)
    src = dest_root / slug / fn
    with tempfile.TemporaryDirectory() as tmp:
        restored = Path(tmp) / fn
        shutil.copy2(src, restored)
        got = hashlib.sha256(restored.read_bytes()).hexdigest()
    if got != sha:
        print(f"FAIL: restored {slug}/{fn} sha {got[:12]} != manifest {sha[:12]}")
        return 1
    print(f"restore verified: {slug}/{fn} ({verdict}) sha {sha[:12]} matches after restore")
    return 0


# ------------------------------------------------------------------ verify-applied

def parse_worklist(path: Path) -> tuple[str, list[Row]]:
    ratified = ""
    rows: list[Row] = []
    in_files = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("ratified:"):
            ratified = line.split(":", 1)[1].strip()
        if line.startswith("## "):
            in_files = line.startswith("## Files")
            continue
        if not (in_files and line.startswith("|")):
            continue
        cells = _cells(line)
        if len(cells) < 3 or cells[0] == "slug" or set(cells[0]) <= {"-", ":"}:
            continue
        rows.append(Row(cells[0].strip("`"), cells[1].strip("`"), cells[2],
                        cells[3] if len(cells) > 3 else "", cells[2]))
    return ratified, rows


def verify_applied(path: Path, only_slug: str | None) -> int:
    if not path.exists():
        print(f"REFUSE: no work-list at {path}")
        return 2
    ratified, rows = parse_worklist(path)
    if not ratified:
        print("REFUSE: work-list carries no `ratified:` stamp — nothing may be applied "
              "against an unapproved table")
        return 2
    if not rows:
        # A parser that reads zero rows would otherwise return 0 and let every
        # destructive phase pass green having done nothing.
        print("FAIL: parsed zero rows from the work-list — vacuous verification")
        return 2
    if only_slug:
        rows = [r for r in rows if r.slug == only_slug]
        if not rows:
            print(f"FAIL: no rows for slug {only_slug}")
            return 2
    unapplied = []
    for r in rows:
        src = MEMORY_ROOT / r.slug / "memory" / r.filename
        if r.verdict in SURVIVES:
            if not src.exists():
                unapplied.append((r, "expected to survive, but is gone"))
        else:
            if src.exists():
                unapplied.append((r, "still on disk"))
    scope = f" for {only_slug}" if only_slug else ""
    if unapplied:
        print(f"FAIL: {len(unapplied)} of {len(rows)} rows unapplied{scope}")
        for r, why in unapplied[:40]:
            print(f"  {r.slug}/{r.filename} [{r.verdict}] {why}")
        if len(unapplied) > 40:
            print(f"  ... and {len(unapplied) - 40} more")
        return 1
    print(f"OK: all {len(rows)} rows applied{scope} (ratified {ratified})")
    return 0


# --------------------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--run", default="2026-08-31", help="audit run date (input dir suffix)")
    ap.add_argument("--repo", default=None, help="repo root (default: this script's repo)")
    ap.add_argument("--check", action="store_true",
                    help="regenerate and diff; exit 1 on any difference")
    ap.add_argument("--reconcile", action="store_true",
                    help="regenerate the disk appendix only")
    ap.add_argument("--backup", action="store_true", help="copy every non-KEEP file + indexes")
    ap.add_argument("--verify-backup", action="store_true",
                    help="restore one sampled file and compare its sha")
    ap.add_argument("--verify-applied", action="store_true")
    ap.add_argument("--ratify", metavar="DATE", help="write the ratified: stamp")
    ap.add_argument("--project", default=None, help="--project=<slug>, scopes --verify-applied")
    args = ap.parse_args()

    repo = Path(args.repo) if args.repo else Path(__file__).resolve().parents[3]
    run_dir = repo / "_tmp" / f"memory-audit-{args.run}"
    out = repo / ".context" / "worklists" / f"{args.run}-memory-cleanup.md"
    appendix = repo / ".context" / "worklists" / f"{args.run}-memory-cleanup-appendix.md"

    if args.verify_applied:
        return verify_applied(out, args.project)

    if not run_dir.is_dir():
        print(f"FAIL: no audit run at {run_dir}")
        return 2
    rows, bad, notes = parse_run(run_dir)
    for n in notes:
        print(f"note: {n}", file=sys.stderr)

    if args.verify_backup:
        return verify_backup(args.run)
    if args.backup:
        return do_backup(rows, args.run)

    if args.reconcile:
        appendix.parent.mkdir(parents=True, exist_ok=True)
        appendix.write_text(reconcile(rows, bad, args.run), encoding="utf-8")
        print(f"appendix: {appendix}")
        return 0

    ratified = _front_matter_field(out, "ratified")
    if args.ratify:
        ratified = args.ratify

    text = render_worklist(args.run, rows, bad, ratified)
    if args.check:
        if not out.exists():
            print(f"FAIL: {out} does not exist")
            return 1
        if out.read_text(encoding="utf-8") != text:
            print(f"FAIL: {out} differs from a fresh generation")
            import difflib
            for line in list(difflib.unified_diff(
                    out.read_text(encoding="utf-8").splitlines(),
                    text.splitlines(), "on-disk", "regenerated", lineterm=""))[:40]:
                print(line)
            return 1
        print(f"OK: {out} reproduces byte-for-byte ({len(rows)} rows, {len(bad)} unplaceable)")
        return 0

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(f"wrote {out}: {len(rows)} executable rows, {len(bad)} unplaceable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
