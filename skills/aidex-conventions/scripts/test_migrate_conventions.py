#!/usr/bin/env python3
"""Round-trip + lockstep tests for migrate-conventions.py.

BL-097 (and BL-039, folded in): `migrate-conventions.py` is a 618-line **in-place**
rewriter and, before this file, zero tests referenced it — the last untested rewriter in
the suite. Its `# ---------- Conventions canon (mirror validate.py) ----------` block was a
hand-copied duplicate with no guard, and it had gone 2.5 months stale.

Two defects lived in that block, both of the "mutator fakes success" shape:

  A. Type-blind statuses. STATUS_MAP was applied with no type check, but decisions use a
     different vocabulary (`accepted`/`superseded`/`dropped`, not `open`/`doing`/`done`).
     `status: proposed` on an ADR was rewritten to `status: open` and reported as
     "Applied" — one illegal status turned into a different illegal status. The broader
     path was FM injection: an ADR with no front-matter got `status: open` (live) or
     `status: done` (archived) with no legacy-vocab precondition at all.
  B. Missing `loops`. TYPES_WITH_ARCHIVE was frozen at four types on 2026-05-14 while
     validate.py grew a fifth on 2026-07-01, so `loops/_archive/` was never created and
     validate kept warning `archive-folder-missing`.

Design note on what "fixed" means for A: migrate does **not** guess a decision's status.
`accepted` vs `superseded` vs `dropped` is a content judgment no rewriter can make, and
guessing is precisely the failure being fixed. It declines and says so in `manual_review`.
So the round-trip contract asserted here is not "0 violations unconditionally" — it is:

    every violation surviving the migration must be one the migration explicitly declined,
    naming that file in manual_review.

That contract is what makes silent failure impossible. A migration that quietly leaves a
violation behind fails here just as loudly as one that writes a bad value.

Run with: python3 skills/aidex-conventions/scripts/test_migrate_conventions.py
"""
from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
MIGRATE_PY = SCRIPT_DIR / "migrate-conventions.py"
SKILL_MD = SCRIPT_DIR.parent / "SKILL.md"

failures: list[str] = []


def fail(msg: str) -> None:
    print(f"  [FAIL] {msg}")
    failures.append(msg)


def ok(msg: str) -> None:
    print(f"  [PASS] {msg}")


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    # MANDATORY: without this, validate.py crashes at `@dataclass class Finding` with an
    # AttributeError, because dataclasses resolves __module__ through sys.modules.
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


validate_mod = _load("validate", SCRIPT_DIR / "validate.py")
migrate_mod = _load("migrate_conventions", MIGRATE_PY)


# ---------- fixture ----------

def build_fixture(root: Path) -> Path:
    """A hostile but realistic legacy `.context/`, covering each documented repro."""
    ctx = root / ".context"
    for d in ("decisions", "decisions/_archive", "loops", "backlog"):
        (ctx / d).mkdir(parents=True)

    # A-1: legacy status that is legal base vocab but ILLEGAL for a decision.
    (ctx / "decisions" / "2026-07-01-use-postgres.md").write_text(
        "---\ntitle: Use Postgres\nstatus: proposed\ncreated: 2026-07-01\n"
        "updated: 2026-07-01\n---\n\n# Use Postgres\n",
        encoding="utf-8",
    )
    # A-1b: an out-of-vocabulary status that the legacy table does not even cover, so the
    # mapping branch never sees it. Must still be declined, not silently kept.
    (ctx / "decisions" / "2026-07-06-use-redis.md").write_text(
        "---\ntitle: Use Redis\nstatus: pending\ncreated: 2026-07-06\n"
        "updated: 2026-07-06\n---\n\n# Use Redis\n",
        encoding="utf-8",
    )
    # A-2: no front-matter at all, live and archived. The strictly broader path — it fires
    # with no legacy-vocab precondition, and it is SKILL.md's headline use case.
    (ctx / "decisions" / "2026-07-02-drop-redis.md").write_text(
        "# Drop Redis\n\nWe removed the cache layer.\n", encoding="utf-8")
    (ctx / "decisions" / "_archive" / "2026-07-03-old-choice.md").write_text(
        "# Old Choice\n\nSuperseded long ago.\n", encoding="utf-8")

    # B: loops/ exists with no _archive/ — reachable in any project that ran new-loop-spec.sh.
    (ctx / "loops" / "2026-07-04-green-build.md").write_text(
        "---\ntitle: Green build loop\nstatus: open\ncreated: 2026-07-04\n"
        "updated: 2026-07-04\n---\n\n# Green build loop\n",
        encoding="utf-8",
    )

    # Ordinary work the migration must still do: legacy filename + inbound cross-reference.
    (ctx / "backlog" / "20260705-fix-the-thing.md").write_text(
        "---\ntitle: Fix the thing\nstatus: completed\ncreated: 2026-07-05\n"
        "updated: 2026-07-05\n---\n\n# Fix the thing\n",
        encoding="utf-8",
    )
    (ctx / "backlog" / "00-index.md").write_text(
        "---\ntitle: Backlog index\nstatus: open\ncreated: 2026-07-05\n"
        "updated: 2026-07-05\n---\n\n# Backlog\n\n- 20260705-fix-the-thing.md\n",
        encoding="utf-8",
    )
    return ctx


def run_migrate(ctx: Path, *flags: str) -> dict:
    proc = subprocess.run(
        [sys.executable, str(MIGRATE_PY), str(ctx), "--json", *flags],
        capture_output=True, text=True,
    )
    if not proc.stdout.strip():
        raise AssertionError(f"migrate produced no JSON (rc={proc.returncode}): {proc.stderr}")
    return json.loads(proc.stdout)


def statuses_on_disk(ctx: Path) -> dict[str, str]:
    out = {}
    for p in sorted(ctx.rglob("*.md")):
        fm = validate_mod.parse_frontmatter(p.read_text(encoding="utf-8"))
        if fm and "status" in fm:
            out[str(p.relative_to(ctx))] = fm["status"]
    return out


# ---------- tests ----------

def test_vocab_derived_not_mirrored() -> None:
    """The canon block must be derived from validate.py, not hand-copied."""
    print("\ntest: vocabulary is derived from validate.py, not mirrored")

    for const in ("TYPES_WITH_ARCHIVE", "BASE_STATUS", "DECISION_STATUS"):
        mine = getattr(migrate_mod, const, None)
        theirs = getattr(validate_mod, const, None)
        if mine is None:
            fail(f"migrate-conventions.py exposes no {const}")
        elif set(mine) != set(theirs):
            fail(f"{const} disagrees with validate.py: migrate={sorted(set(mine))} "
                 f"validate={sorted(set(theirs))}")
        else:
            ok(f"{const} matches validate.py ({len(set(theirs))} entries)")

    # A derived constant that is still a literal will pass the equality check today and
    # rot tomorrow, which is exactly the 2.5-month staleness this item is about.
    src = MIGRATE_PY.read_text(encoding="utf-8")
    if "mirror validate.py" in src:
        fail("the source still declares itself a 'mirror validate.py' — the whole defect class")
    elif "spec_from_file_location" not in src:
        fail("no import of validate.py found: the constants may match today but nothing holds them")
    else:
        ok("constants are imported from validate.py at run time")

    # Three sites held the stale four-type list; a literal-only patch leaves two lying.
    flat = " ".join(src.split())
    if 'backlog, plans, requests, decisions per D-05' in flat:
        fail("the module docstring still lists the stale four archive types")
    else:
        ok("module docstring no longer hard-codes the stale four-type list")
    skill = " ".join(SKILL_MD.read_text(encoding="utf-8").split())
    if "Creates `_archive/` directories in `backlog/`, `plans/`, `requests/`, `decisions/`" in skill:
        fail("aidex-conventions/SKILL.md still lists the stale four archive types (loops missing)")
    else:
        ok("SKILL.md no longer hard-codes the stale four-type list")
    # Code -> doc lockstep, derived rather than phrase-matched: whatever the code declines
    # to migrate must appear in SKILL.md's "Edge cases the migration cannot decide for you"
    # list. Before this fix that list never mentioned decisions, so the skill promised
    # "Expect 0 violations" for a case it could not deliver.
    declined = getattr(migrate_mod, "TYPES_WITHOUT_INFERRABLE_STATUS", None)
    if declined is None:
        fail("migrate-conventions.py exposes no TYPES_WITHOUT_INFERRABLE_STATUS — nothing "
             "states which artifact types it refuses to assign a status to")
    else:
        raw = SKILL_MD.read_text(encoding="utf-8")
        start = raw.find("Edge cases the migration cannot decide for you")
        section = " ".join(raw[start:].split("\n##")[0].split()) if start >= 0 else ""
        if not section:
            fail("SKILL.md has no 'Edge cases the migration cannot decide for you' section")
        for t in declined:
            if t in section:
                ok(f"SKILL.md's edge-case list names the declined type '{t}'")
            else:
                fail(f"the code declines to assign a status for '{t}', but SKILL.md's "
                     f"edge-case list never mentions it — the skill promises a clean "
                     f"migration it cannot deliver")


def test_round_trip() -> None:
    """hostile input -> --apply -> validate: nothing survives unannounced."""
    print("\ntest: round-trip (migrate --apply, then validate)")

    with tempfile.TemporaryDirectory() as td:
        ctx = build_fixture(Path(td))

        before = statuses_on_disk(ctx)
        plan = run_migrate(ctx)

        # --- B: loops must be in the archive-dir plan ---
        dirs = plan["dirs_to_create"]
        if any(d.rstrip("/").endswith("loops/_archive") for d in dirs):
            ok("loops/_archive is planned (TYPES_WITH_ARCHIVE includes loops)")
        else:
            fail(f"loops/_archive missing from dirs_to_create: {dirs}")

        run_migrate(ctx, "--apply")
        applied = run_migrate(ctx)          # re-plan: the migration must be idempotent
        notes = " ".join(applied["manual_review"])

        if not (ctx / "loops" / "_archive").is_dir():
            fail("loops/_archive was not created on disk after --apply")
        else:
            ok("loops/_archive exists on disk")

        # --- A: the migration must never WRITE an illegal status ---
        # An illegal status may legitimately survive: the design is to decline rather than
        # guess. What must never happen is the migration producing one. The two are told
        # apart by whether the value changed — an untouched legacy value that is reported is
        # a decline; a value the tool put there is the defect (`proposed` -> `open` on an
        # ADR was reported as "Applied").
        bad_status = False
        for rel, status in statuses_on_disk(ctx).items():
            legal = (validate_mod.DECISION_STATUS if rel.startswith("decisions/")
                     else validate_mod.BASE_STATUS)
            if status in legal:
                continue
            bad_status = True
            if rel not in before:
                fail(f"{rel} had no status and the migration wrote '{status}', which is "
                     f"illegal for its type (legal: {sorted(legal)})")
            elif before[rel] != status:
                fail(f"{rel}: the migration rewrote status '{before[rel]}' -> '{status}', "
                     f"still illegal for its type (legal: {sorted(legal)}) — one bad value "
                     f"turned into another and reported as applied")
            elif Path(rel).name not in notes:
                fail(f"{rel} keeps illegal status '{status}' and is not named in "
                     f"manual_review — declined silently is indistinguishable from missed")
            else:
                ok(f"{rel}: illegal status '{status}' left untouched and declined out loud")
        if not bad_status:
            ok("no illegal status anywhere on disk")

        # --- ordinary work still happens ---
        renamed = ctx / "backlog" / "2026-07-05-fix-the-thing.md"
        if not renamed.is_file():
            fail("the legacy YYYYMMDD backlog filename was not renamed")
        else:
            ok("legacy filename renamed to ISO form")
            fm = validate_mod.parse_frontmatter(renamed.read_text(encoding="utf-8")) or {}
            if fm.get("status") != "done":
                fail(f"legacy status 'completed' was not mapped to 'done' (got {fm.get('status')!r})")
            else:
                ok("legacy base-vocab status mapped (completed -> done)")
        idx = (ctx / "backlog" / "00-index.md").read_text(encoding="utf-8")
        if "20260705-fix-the-thing.md" in idx:
            fail("the inbound cross-reference to the renamed file was not rewritten")
        else:
            ok("inbound cross-reference rewritten to the new basename")

        # --- the contract: every survivor must have been declined out loud ---
        findings, _ = validate_mod.validate(ctx, None)
        survivors = [f for f in findings if f.severity == "violation"]
        unannounced = [f for f in survivors if Path(f.file).name not in notes]
        if unannounced:
            for f in unannounced:
                fail(f"violation survived the migration unannounced: "
                     f"{f.file} [{f.rule}] {f.message}")
        else:
            ok(f"all {len(survivors)} surviving violation(s) are named in manual_review")

        if not notes.strip():
            fail("the fixture contains two front-matter-less ADRs, which no rewriter can "
                 "assign a status — manual_review must say so, and it is empty")
        else:
            ok("manual_review is non-empty and names what was declined")


if __name__ == "__main__":
    if not MIGRATE_PY.is_file():
        sys.exit(f"FAIL: {MIGRATE_PY} not found")
    test_vocab_derived_not_mirrored()
    test_round_trip()
    print()
    if failures:
        print(f"FAILED — {len(failures)} assertion(s)")
        sys.exit(1)
    print("all migrate-conventions round-trip + lockstep tests passed")
