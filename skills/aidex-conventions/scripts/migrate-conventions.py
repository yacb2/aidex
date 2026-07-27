#!/usr/bin/env python3
"""Migrate a `.context/` folder from legacy aidex conventions to the unified
canon (see plan `2026-05-14-aidex-conventions-unification`).

Operations (idempotent — re-running on a migrated tree is a no-op):

  1. Rename files matching `YYYYMMDD-<slug>.md` → `YYYY-MM-DD-<slug>.md`.
  2. Inject or repair front-matter on files missing the required block.
     Required fields: title, status, created, updated.
  3. Normalize front-matter date fields: `created`/`updated` written as
     `YYYY-MM-DD`. Legacy `date:` fields are read as fallback source for
     `created`/`updated` but left in place.
  4. Map legacy status vocabulary to the canon (D-04, D-07):
        completed -> done    Rejected -> dropped    Proposed -> open
        Pendiente -> open    In Progress -> doing
  5. Rewrite cross-references to renamed files across every `.md` under
     `.context/` — both in front-matter fields (escalated_to, superseded_by,
     blocked_by, origin_ref) and in body text (bare basename mentions).
  6. Create missing `_archive/` directories for every type that requires one
     (D-05). The list is imported from validate.py, never restated here.

Refuses rather than guesses: a decision's status (`accepted`/`superseded`/`dropped`)
cannot be derived from a file's location or its legacy value, so ADRs with no
front-matter, or with a status outside their vocabulary, are left untouched and
reported under `manual_review`.

CLI:
    migrate-conventions.py [<path>] [--apply] [--json]

Default is dry-run; `--apply` writes changes. Path defaults to auto-detected
`.context/` from cwd upward.

Exit codes: 0 OK · 1 changes pending (dry-run) or applied with warnings ·
            2 usage error.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path


# ---------- Conventions canon (imported from validate.py, never copied) ----------
#
# This block used to be a hand-copied mirror of validate.py's constants. It went 2.5 months
# stale without anything noticing: validate.py gained `loops` as a fifth archive type on
# 2026-07-01 and this list stayed at four from 2026-05-14, so `loops/_archive/` was never
# created and the validator kept warning about it. Importing removes the copy entirely —
# there is no second definition left to drift.

def _load_validator():
    import importlib.util
    path = Path(__file__).resolve().parent / "validate.py"
    spec = importlib.util.spec_from_file_location("validate", path)
    mod = importlib.util.module_from_spec(spec)
    # Mandatory: dataclasses resolves __module__ through sys.modules, and validate.py's
    # `@dataclass class Finding` raises AttributeError without this line.
    sys.modules["validate"] = mod
    spec.loader.exec_module(mod)
    return mod


_validate = _load_validator()

TYPES_WITH_ARCHIVE = tuple(sorted(_validate.TYPES_WITH_ARCHIVE))
BASE_STATUS = _validate.BASE_STATUS
DECISION_STATUS = _validate.DECISION_STATUS

# Types whose status this tool refuses to infer. A decision's status is a content judgment
# — `accepted` vs `superseded` vs `dropped` cannot be read off a file's location or its
# legacy value — so guessing one would turn "migrated" into a claim the tool cannot back.
# It declines and reports instead; see `manual_review` in the output.
TYPES_WITHOUT_INFERRABLE_STATUS = ("decisions",)

LEGACY_FILENAME = re.compile(r"^(\d{4})(\d{2})(\d{2})-(.+\.md)$")
ISO_FILENAME = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
FM_DELIM = re.compile(r"^---\s*$")
REQUIRED_FIELDS = ("title", "status", "created", "updated")

STATUS_MAP = {
    "completed": "done",
    "Completed": "done",
    "rejected": "dropped",
    "Rejected": "dropped",
    "proposed": "open",
    "Proposed": "open",
    "pendiente": "open",
    "Pendiente": "open",
    "in progress": "doing",
    "In Progress": "doing",
    "in-progress": "doing",
}


def artifact_type(context_dir: Path, p: Path) -> str:
    """The `.context/` type a file belongs to, or "" if it sits at the root."""
    parts = p.relative_to(context_dir).parts
    return parts[0] if len(parts) > 1 else ""


def legal_statuses(type_name: str) -> set[str]:
    """The status vocabulary for a type. Decisions are the one type not using the base
    vocabulary (request-decision-conventions.md § status)."""
    return DECISION_STATUS if type_name == "decisions" else BASE_STATUS


# ---------- Front-matter parser/writer (no pyyaml) ----------

def parse_frontmatter(text: str) -> tuple[dict | None, int, int]:
    """Return (fields, body_start_line, fm_end_line). If no FM, returns (None, 0, 0)."""
    lines = text.splitlines()
    if not lines or not FM_DELIM.match(lines[0]):
        return None, 0, 0
    end = None
    for i in range(1, len(lines)):
        if FM_DELIM.match(lines[i]):
            end = i
            break
    if end is None:
        return None, 0, 0
    fields: dict[str, str] = {}
    for raw in lines[1:end]:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][\w-]*)\s*:\s*(.*)$", raw)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        fields[key] = val
    return fields, end + 1, end


def rewrite_frontmatter_block(text: str, mutations: dict[str, str]) -> str:
    """Apply key→new-value rewrites inside the FM block, preserving formatting.
    Only rewrites simple `key: value` lines; ignores quoted/multi-line."""
    if not mutations:
        return text
    lines = text.splitlines(keepends=True)
    if not lines or not FM_DELIM.match(lines[0].rstrip("\n")):
        return text
    out: list[str] = [lines[0]]
    i = 1
    while i < len(lines) and not FM_DELIM.match(lines[i].rstrip("\n")):
        raw = lines[i]
        m = re.match(r"^([A-Za-z_][\w-]*)(\s*:\s*)(.*)$", raw.rstrip("\n"))
        if m and m.group(1) in mutations:
            new_val = mutations[m.group(1)]
            nl = "\n" if raw.endswith("\n") else ""
            out.append(f"{m.group(1)}{m.group(2)}{new_val}{nl}")
        else:
            out.append(raw)
        i += 1
    out.extend(lines[i:])
    return "".join(out)


def inject_frontmatter(text: str, fm: dict[str, str]) -> str:
    """Prepend a YAML FM block to a file that has none."""
    lines = ["---"]
    for k, v in fm.items():
        if any(c in v for c in (":", "#")) and not (v.startswith('"') and v.endswith('"')):
            v = f'"{v}"'
        lines.append(f"{k}: {v}")
    lines.append("---")
    lines.append("")
    return "\n".join(lines) + text


# ---------- Helpers ----------

def iso_from_legacy_name(name: str) -> str | None:
    m = LEGACY_FILENAME.match(name)
    if not m:
        return None
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"


def iso_from_field(val: str) -> str | None:
    if not val:
        return None
    if ISO_DATE.match(val):
        return val
    m = re.match(r"^(\d{4})(\d{2})(\d{2})$", val)
    if m:
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
    return None


def slug_from_title(title: str, fallback: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return s[:60] or fallback


def extract_h1(text: str) -> str | None:
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return None


# ---------- Change record ----------

@dataclass
class Change:
    kind: str               # rename | inject-fm | mutate-fm | rewrite-ref | create-dir
    path: str               # repo-relative
    detail: dict = field(default_factory=dict)


# ---------- Planner ----------

IGNORE_NAME = ".aidex-ignore"


def load_ignores(context_dir: Path) -> list[str]:
    """Path prefixes (relative to `.context/`) the migrator must not touch — the
    same `<context>/.aidex-ignore` file validate.py reads. Vendored/imported
    subtrees are not aidex artifacts, so renaming them would corrupt a third-party
    tree (BL-037). One prefix per line, `#` comments and blanks ignored, no globs."""
    ip = context_dir / IGNORE_NAME
    if not ip.is_file():
        return []
    prefixes: list[str] = []
    for raw in ip.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(".context/"):
            line = line[len(".context/"):]
        line = line.strip("/")
        if line:
            prefixes.append(line)
    return prefixes


def is_ignored(context_dir: Path, path: Path, prefixes: list[str]) -> bool:
    if not prefixes:
        return False
    try:
        rel = path.resolve().relative_to(context_dir.resolve()).as_posix()
    except (ValueError, OSError):
        return False
    return any(rel == p or rel.startswith(p + "/") for p in prefixes)


def iter_md(context_dir: Path):
    prefixes = load_ignores(context_dir)
    for p in context_dir.rglob("*.md"):
        if is_ignored(context_dir, p, prefixes):
            continue
        yield p


SLUG_INVALID = re.compile(r"[^a-z0-9-]+")
ISO_PREFIX = re.compile(r"^(\d{4}-\d{2}-\d{2})-(.+\.md)$")


def sanitize_slug(slug: str) -> str:
    """Lowercase + replace any non `[a-z0-9-]` run with `-`. Collapse repeats."""
    s = SLUG_INVALID.sub("-", slug.lower())
    s = re.sub(r"-+", "-", s).strip("-")
    return s


def file_is_exempt_from_rename(type_name: str, p: Path, context_dir: Path) -> bool:
    """Subdocs of modular plans/references/research and index files: no rename.

    Also exempt legacy audit-root files (INVENTORY/METHODOLOGY/CHANGELOG.md at
    `.context/audits/`) — restructuring those to the D-02 layout requires a
    human-chosen methodology slug and is handled manually, not by this script."""
    if p.name in ("00-index.md", "00-overview.md", "00-methodology.md",
                  "00-inventory.md", "00-changelog.md", "index.md", "findings.md"):
        return True
    if re.match(r"^\d{2}-[a-z0-9-]+\.md$", p.name):
        # NN-<slug>.md inside a topic folder — leave alone.
        if type_name in ("plans", "references", "research") and p.parent.name not in (
            type_name, "_archive",
        ):
            return True
    # Audits don't follow the YYYY-MM-DD-<slug>.md filename rule — they're a
    # structural type (00-* canonical files + NN-* run sub-docs). Legacy root
    # files (INVENTORY/METHODOLOGY/CHANGELOG.md) are surfaced as manual review.
    if type_name == "audits":
        return True
    return False


def plan_renames(context_dir: Path) -> dict[Path, Path]:
    """Map old absolute path → new absolute path for files that need renaming.

    Three cases handled:
      (a) `YYYYMMDD-<slug>.md`           → insert dashes in date
      (b) `YYYY-MM-DD-<bad-slug>.md`     → sanitize slug
      (c) `<no-date>-<slug>.md`          → prepend FM `created` (else today)
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    renames: dict[Path, Path] = {}
    for p in iter_md(context_dir):
        # Skip files outside the seven canonical type roots — they're not subject
        # to filename conventions (e.g. user-level scratch).
        rel_parts = p.relative_to(context_dir).parts
        if not rel_parts:
            continue
        type_name = rel_parts[0]
        if type_name not in ("backlog", "plans", "requests", "decisions",
                             "references", "research", "audits"):
            continue
        if file_is_exempt_from_rename(type_name, p, context_dir):
            continue

        name = p.name
        new_name: str | None = None

        # (a) Legacy YYYYMMDD
        m = LEGACY_FILENAME.match(name)
        if m:
            iso_date = f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
            slug_part = m.group(4)[:-3]  # strip .md
            slug_part = sanitize_slug(slug_part) or "untitled"
            new_name = f"{iso_date}-{slug_part}.md"
        else:
            mp = ISO_PREFIX.match(name)
            if mp:
                # (b) ISO date prefix already present — sanitize slug if needed.
                iso_date = mp.group(1)
                slug_part = mp.group(2)[:-3]
                clean = sanitize_slug(slug_part) or "untitled"
                if clean != slug_part:
                    new_name = f"{iso_date}-{clean}.md"
            else:
                # (c) No date prefix — derive one and prepend.
                text = p.read_text(encoding="utf-8", errors="replace")
                fm, _, _ = parse_frontmatter(text)
                iso_date = None
                if fm:
                    iso_date = iso_from_field(fm.get("created", "")) or \
                               iso_from_field(fm.get("date", "")) or \
                               iso_from_field(fm.get("updated", ""))
                iso_date = iso_date or today
                slug_part = sanitize_slug(name[:-3]) or "untitled"
                new_name = f"{iso_date}-{slug_part}.md"

        if new_name and new_name != name:
            renames[p] = p.with_name(new_name)
    return renames


def plan_frontmatter_repairs(
    context_dir: Path, renames: dict[Path, Path]
) -> tuple[list[Change], list[str]]:
    """For each .md, determine FM injection or mutation needed.

    Returns (changes, declined) — `declined` names files this tool refuses to repair
    because doing so would require inventing a value. They are reported under
    `manual_review` rather than silently skipped: a migration that leaves a violation
    behind without saying so is indistinguishable from one that succeeded.

    Operates on post-rename paths (we know the target name already)."""
    changes: list[Change] = []
    declined: list[str] = []
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    for p in iter_md(context_dir):
        rel_parts = p.relative_to(context_dir).parts
        if rel_parts and rel_parts[0] == "audits":
            # Audits use tabular/sub-document content — handle restructure
            # manually, surfaced via detect_manual_review().
            continue
        # The file may be a sub-document of a modular plan / reference / research topic.
        # validate.py treats `NN-<slug>.md` inside a subfolder as a subdocument with no FM
        # requirement — match the same exemption so we don't inject useless FM blocks.
        if re.match(r"^\d{2}-[a-z0-9-]+\.md$", p.name) and p.name not in (
            "00-index.md", "00-overview.md", "00-methodology.md", "00-inventory.md", "00-changelog.md",
        ):
            parent_type = p.parent.parent.name if p.parent.parent != context_dir else ""
            if parent_type in ("plans", "references", "research") and p.parent.name not in (
                parent_type, "_archive",
            ):
                continue

        text = p.read_text(encoding="utf-8", errors="replace")
        fm, _, _ = parse_frontmatter(text)

        target_name = renames.get(p, p).name
        iso_from_name = iso_from_legacy_name(p.name) or (
            target_name[:10] if ISO_FILENAME.match(target_name) else None
        )

        # status mapping (if FM exists)
        mutations: dict[str, str] = {}
        type_name = artifact_type(context_dir, p)
        legal = legal_statuses(type_name)

        if fm is None:
            if type_name in TYPES_WITHOUT_INFERRABLE_STATUS:
                # The stub would need a status, and for this type there is no value that can
                # be derived from the file's location or name. Injecting `open`/`done` here
                # is what produced illegal ADR statuses reported as a successful migration.
                declined.append(
                    f"{to_relative(context_dir, str(p))} has no front-matter and is a "
                    f"{type_name[:-1]}; its status must be one of "
                    f"{sorted(legal)}, which cannot be inferred from the file. "
                    "Add the front-matter block by hand — the rest of this file was migrated."
                )
                continue
            # Inject minimal stub.
            title = extract_h1(text) or p.stem
            iso = iso_from_name or today
            is_archived = "/_archive/" in str(p)
            status = "done" if is_archived else "open"
            new_fm = {
                "title": title,
                "status": status,
                "created": iso,
                "updated": iso,
            }
            changes.append(Change("inject-fm", str(p), {"fields": new_fm}))
            continue

        # FM exists. Compute mutations needed.
        # status mapping — the legacy table is base-vocabulary, so a mapped value is not
        # automatically legal for this type. Applying it blind rewrote `proposed` to `open`
        # on an ADR: one illegal status turned into a different illegal status, and reported
        # as applied. Only map when the result is legal here; otherwise decline out loud.
        if "status" in fm and fm["status"] in STATUS_MAP:
            mapped = STATUS_MAP[fm["status"]]
            if mapped in legal:
                mutations["status"] = mapped
            else:
                declined.append(
                    f"{to_relative(context_dir, str(p))} has status "
                    f"'{fm['status']}', which maps to '{mapped}' in the legacy table but is "
                    f"not legal for {type_name} (legal: {sorted(legal)}). Left unchanged — "
                    "choose the right value by hand."
                )
        elif (
            type_name in TYPES_WITHOUT_INFERRABLE_STATUS
            and "status" in fm
            and fm["status"] not in legal
        ):
            # Deliberately scoped to the types above rather than every type. validate.py does
            # not enforce a status vocabulary everywhere — optional types like `drafts/` and
            # sub-documents of modular plans are not checked — and reporting files it never
            # flags would make this tool the thing it is being fixed for: a checker that
            # raises findings nobody can act on. Verified against `validate.py --json`, which
            # reports zero `status-invalid` for exactly those files.
            declined.append(
                f"{to_relative(context_dir, str(p))} has status '{fm['status']}', which is "
                f"not legal for {type_name} (legal: {sorted(legal)}) and is not in the "
                "legacy mapping table. Left unchanged — choose the right value by hand."
            )

        # created
        if not fm.get("created"):
            src = iso_from_field(fm.get("date", "")) or iso_from_field(fm.get("completed", "")) or iso_from_name or today
            mutations["created"] = src
        elif not ISO_DATE.match(fm["created"]):
            iso = iso_from_field(fm["created"]) or iso_from_name or today
            mutations["created"] = iso

        # updated
        if not fm.get("updated"):
            src = iso_from_field(fm.get("date", "")) or iso_from_field(fm.get("completed", "")) or iso_from_name or today
            mutations["updated"] = src
        elif not ISO_DATE.match(fm["updated"]):
            iso = iso_from_field(fm["updated"]) or iso_from_name or today
            mutations["updated"] = iso

        # title (only if completely missing — H1 fallback)
        title_inject_needed = "title" not in fm and bool(extract_h1(text))

        if mutations or title_inject_needed:
            detail = {"mutations": dict(mutations)}
            if title_inject_needed:
                detail["inject_title"] = extract_h1(text) or p.stem
            # We add `created`/`updated` even if absent from FM — that requires
            # inject-style append, not pure mutate. Mark that case.
            need_append = []
            if "created" in mutations and "created" not in fm:
                need_append.append("created")
            if "updated" in mutations and "updated" not in fm:
                need_append.append("updated")
            if need_append:
                detail["append_fields"] = need_append
            if detail.get("mutations") or detail.get("inject_title") or detail.get("append_fields"):
                changes.append(Change("mutate-fm", str(p), detail))

    return changes, declined


def plan_crossref_rewrites(context_dir: Path, renames: dict[Path, Path]) -> list[Change]:
    """For each file in .context/, find references to renamed filenames and queue rewrites.
    Only rewrites bare basenames to avoid touching unrelated docs that quote the
    legacy pattern as an example."""
    if not renames:
        return []
    basename_map = {old.name: new.name for old, new in renames.items()}
    changes: list[Change] = []
    for p in iter_md(context_dir):
        text = p.read_text(encoding="utf-8", errors="replace")
        hits: dict[str, str] = {}
        for old_name, new_name in basename_map.items():
            if old_name in text:
                # Skip the file itself — we'll rename it, not edit references inside.
                if p.name == old_name:
                    continue
                hits[old_name] = new_name
        if hits:
            changes.append(Change("rewrite-ref", str(p), {"map": hits}))
    return changes


def detect_manual_review(context_dir: Path) -> list[str]:
    """Return human-readable warnings for cases the migration cannot auto-handle."""
    notes: list[str] = []
    audits = context_dir / "audits"
    if audits.is_dir():
        legacy = [n for n in ("INVENTORY.md", "METHODOLOGY.md", "CHANGELOG.md")
                  if (audits / n).is_file()]
        if legacy:
            notes.append(
                f"audits/ root contains legacy D-02 files ({', '.join(legacy)}). "
                "Move them under a per-methodology folder (audits/<methodology>/00-{inventory,methodology,changelog}.md) "
                "by hand — this requires a methodology slug only you can choose."
            )
    return notes


def plan_archive_dirs(context_dir: Path) -> list[Change]:
    changes: list[Change] = []
    for t in TYPES_WITH_ARCHIVE:
        base = context_dir / t
        if base.is_dir() and not (base / "_archive").is_dir():
            changes.append(Change("create-dir", str(base / "_archive"), {}))
    return changes


# ---------- Applier ----------

def apply_changes(
    context_dir: Path,
    renames: dict[Path, Path],
    fm_changes: list[Change],
    ref_changes: list[Change],
    dir_changes: list[Change],
) -> None:
    # 1. FM repairs (operate on pre-rename paths; we still have them on disk).
    for c in fm_changes:
        p = Path(c.path)
        text = p.read_text(encoding="utf-8", errors="replace")
        if c.kind == "inject-fm":
            new_text = inject_frontmatter(text, c.detail["fields"])
            p.write_text(new_text, encoding="utf-8")
        elif c.kind == "mutate-fm":
            mutations = c.detail.get("mutations", {})
            append_fields = c.detail.get("append_fields", [])
            inject_title = c.detail.get("inject_title")

            # Pure replacements first.
            in_place = {k: v for k, v in mutations.items() if k not in append_fields}
            if in_place:
                text = rewrite_frontmatter_block(text, in_place)

            # Title injection if completely missing.
            if inject_title:
                text = inject_field_after_delim(text, "title", inject_title)

            # Fields that were missing entirely need to be appended into FM block.
            for fname in append_fields:
                text = inject_field_into_block(text, fname, mutations[fname])

            p.write_text(text, encoding="utf-8")

    # 2. Cross-ref rewrites (work on current paths — same as FM since renames haven't run yet).
    for c in ref_changes:
        p = Path(c.path)
        text = p.read_text(encoding="utf-8", errors="replace")
        for old, new in c.detail["map"].items():
            text = text.replace(old, new)
        p.write_text(text, encoding="utf-8")

    # 3. Renames last.
    for old, new in renames.items():
        if old.exists() and not new.exists():
            shutil.move(str(old), str(new))

    # 4. Archive dirs.
    for c in dir_changes:
        Path(c.path).mkdir(parents=True, exist_ok=True)


def inject_field_into_block(text: str, key: str, value: str) -> str:
    """Append `key: value` just before the closing `---` of the FM block."""
    lines = text.splitlines(keepends=True)
    if not lines or not FM_DELIM.match(lines[0].rstrip("\n")):
        return text  # no FM; should not happen here
    for i in range(1, len(lines)):
        if FM_DELIM.match(lines[i].rstrip("\n")):
            nl = "\n" if lines[i - 1].endswith("\n") or i == 1 else ""
            lines.insert(i, f"{key}: {value}{nl}")
            return "".join(lines)
    return text


def inject_field_after_delim(text: str, key: str, value: str) -> str:
    """Insert `key: value` as the first field inside the FM block."""
    lines = text.splitlines(keepends=True)
    if not lines or not FM_DELIM.match(lines[0].rstrip("\n")):
        return text
    nl = "\n" if lines[0].endswith("\n") else ""
    lines.insert(1, f"{key}: {value}{nl}")
    return "".join(lines)


# ---------- Driver ----------

def find_context_dir(start: Path) -> Path | None:
    cur = start.resolve()
    while True:
        if (cur / ".context").is_dir():
            return cur / ".context"
        if cur.parent == cur:
            return None
        cur = cur.parent


def to_relative(context_dir: Path, abs_path: str) -> str:
    try:
        return str(Path(abs_path).resolve().relative_to(context_dir.resolve().parent))
    except ValueError:
        return abs_path


def main() -> int:
    p = argparse.ArgumentParser(description="Migrate .context/ to unified aidex conventions")
    p.add_argument("path", nargs="?", help="Path to .context/ (default: auto-detect)")
    p.add_argument("--apply", action="store_true", help="Write changes (default: dry-run)")
    p.add_argument("--json", action="store_true", help="Emit JSON plan/result")
    args = p.parse_args()

    if args.path:
        context_dir = Path(args.path)
        if context_dir.name != ".context" and (context_dir / ".context").is_dir():
            context_dir = context_dir / ".context"
    else:
        found = find_context_dir(Path.cwd())
        if not found:
            print("error: no .context/ found from cwd upward", file=sys.stderr)
            return 2
        context_dir = found

    if not context_dir.is_dir():
        print(f"error: not a directory: {context_dir}", file=sys.stderr)
        return 2

    renames = plan_renames(context_dir)
    fm_changes, declined = plan_frontmatter_repairs(context_dir, renames)
    ref_changes = plan_crossref_rewrites(context_dir, renames)
    dir_changes = plan_archive_dirs(context_dir)
    manual_notes = detect_manual_review(context_dir) + declined

    total = len(renames) + len(fm_changes) + len(ref_changes) + len(dir_changes)
    mode = "APPLY" if args.apply else "DRY-RUN"

    if args.json:
        out = {
            "context_dir": str(context_dir.resolve()),
            "mode": mode.lower(),
            "scanned_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "summary": {
                "renames": len(renames),
                "frontmatter_changes": len(fm_changes),
                "crossref_rewrites": len(ref_changes),
                "dirs_to_create": len(dir_changes),
            },
            "renames": [
                {"from": to_relative(context_dir, str(o)), "to": to_relative(context_dir, str(n))}
                for o, n in renames.items()
            ],
            "frontmatter_changes": [
                {"path": to_relative(context_dir, c.path), "kind": c.kind, "detail": c.detail}
                for c in fm_changes
            ],
            "crossref_rewrites": [
                {"path": to_relative(context_dir, c.path), "map": c.detail["map"]}
                for c in ref_changes
            ],
            "dirs_to_create": [to_relative(context_dir, c.path) for c in dir_changes],
            "manual_review": manual_notes,
        }
        json.dump(out, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(f"\nMigration plan ({mode}) — {context_dir}")
        print(f"  renames: {len(renames)} · fm-changes: {len(fm_changes)} · "
              f"crossref-rewrites: {len(ref_changes)} · dirs-to-create: {len(dir_changes)}\n")
        if renames:
            print("Renames:")
            for o, n in renames.items():
                print(f"  {to_relative(context_dir, str(o))}")
                print(f"    -> {to_relative(context_dir, str(n))}")
        if fm_changes:
            print("\nFront-matter changes:")
            for c in fm_changes:
                print(f"  [{c.kind}] {to_relative(context_dir, c.path)}")
                if c.kind == "inject-fm":
                    for k, v in c.detail["fields"].items():
                        print(f"      + {k}: {v}")
                else:
                    for k, v in c.detail.get("mutations", {}).items():
                        marker = "+" if k in c.detail.get("append_fields", []) else "~"
                        print(f"      {marker} {k}: {v}")
                    if c.detail.get("inject_title"):
                        print(f"      + title: {c.detail['inject_title']}")
        if ref_changes:
            print("\nCross-ref rewrites:")
            for c in ref_changes:
                print(f"  {to_relative(context_dir, c.path)}")
                for old, new in c.detail["map"].items():
                    print(f"    {old} -> {new}")
        if dir_changes:
            print("\nDirectories to create:")
            for c in dir_changes:
                print(f"  {to_relative(context_dir, c.path)}")
        if manual_notes:
            print("\nManual review required (not auto-migrated):")
            for note in manual_notes:
                print(f"  - {note}")
        if total == 0 and not manual_notes:
            print("OK — nothing to migrate")

    if args.apply and total > 0:
        apply_changes(context_dir, renames, fm_changes, ref_changes, dir_changes)
        if not args.json:
            print(f"\nApplied {total} change(s).")

    # Exit 1 covers both documented cases: changes still pending (dry-run) and applied with
    # warnings. Manual-review notes are warnings — returning 0 alongside them would report a
    # migration that left violations behind as a clean one.
    if manual_notes:
        return 1
    return 0 if total == 0 else (0 if args.apply else 1)


if __name__ == "__main__":
    sys.exit(main())
