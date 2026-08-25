#!/usr/bin/env python3
"""Validate .context/ artifacts against aidex conventions.

CLI:
    validate.py [<path>] [--type <type>] [--json]

Default scans the .context/ folder found by walking up from cwd.
Exit codes: 0 OK · 1 violations found · 2 usage error.

JSON schema documented in:
    .context/plans/2026-05-14-aidex-conventions-unification/04-validators.md
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

# ---------- Conventions canon ----------

TYPES = ["backlog", "plans", "requests", "decisions", "references", "research", "audits",
         "communications", "loops", "worktrees"]
TYPES_WITH_ARCHIVE = {"backlog", "plans", "requests", "decisions", "loops"}
TYPES_WITH_INDEX = {"plans": True, "references": True, "research": True, "backlog": True}
# Acceptable-optional .context/ dirs: never required, may be gitignored. Some ARE
# scaffolded on demand (worklists by the worklist scripts, workflows by aidex-workflow);
# the rest are project-local. The validator neither requires nor flags them — listed here
# so the canonical model is explicit (auditors must not propose deleting these even when
# empty). Keep in lockstep with 00-global.md §9 (guarded by test_registry_lockstep.py).
OPTIONAL_TYPES = {"data", "diagrams", "drafts", "experiments", "worklists", "workflows"}
# Communications front-matter vocab (artifacts are EXEMPT from English-only; body is native).
COMM_CHANNELS = {"email", "whatsapp", "call", "meeting", "other"}
COMM_DIRECTIONS = {"received", "sent"}          # async, directional (from/to)
COMM_MEETING_DIR = "meetings"                   # synchronous, participant-based (no direction)
COMM_ASYNC_CHANNELS = {"email", "whatsapp", "other"}
COMM_MEETING_CHANNELS = {"meeting", "call"}
COMM_STATUS = {"draft", "sent"}
COMM_REQUIRED_FIELDS = ("channel", "direction", "from", "to", "subject", "date", "status",
                        "created", "updated")
# Synchronous records (meetings/) replace direction/from/to with a participants list.
COMM_MEETING_REQUIRED_FIELDS = ("channel", "participants", "subject", "date", "status",
                                "created", "updated")
# Pre-canonical body filenames, mapped to what they should become. The canonical
# layout shipped in 1898b60 but nothing enforced it, so entries written after that
# commit still used these names (RETRO-49). `migrate-communications.sh` renames them.
COMM_LEGACY_BODY_FILES = {"email.md": "body.md", "conversation.md": "body.md"}

BASE_STATUS = {"open", "doing", "done", "dropped"}
DECISION_STATUS = {"accepted", "superseded", "dropped"}
# P0-P3 only. "Blocked" is a lifecycle MODIFIER, not a priority: the canon says
# to keep the priority and set blocked_by (01-backlog-conventions.md:147), and the
# index renders a "## Blocked" section from that field. Accepting it here let an
# item hide its real urgency in the one value migrate-priorities.sh cannot repair.
BACKLOG_PRIORITIES = {"P0", "P1", "P2", "P3"}
# Backlog work-kind facet (ADR 2026-07-23-backlog-single-queue-type-facet): one
# queue, a closed/small type facet. Absent is warn-then-ratchet (existing items
# are not retro-fixed); a present value outside the enum is a violation.
BACKLOG_TYPES = {"bug", "improvement", "task", "idea"}

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ISO_FILENAME = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$")
ISO_FOLDER = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(-[a-z0-9]+)*$")
LEGACY_FILENAME = re.compile(r"^\d{8}-")
CROSSREF_FIELDS = ("escalated_to", "superseded_by", "blocked_by", "origin_ref")
CROSSREF_FORMAT = re.compile(r"^(audit|backlog|plan|request|decision|reference|research|communication|loop|worktree)/.+$")
# External refs (BL-070): stable identifiers whose target does not live in THIS
# .context/ — an issue-tracker id, or a backlog item in another repo (written by
# aidex-backlog's --escalate-to handshake). Format-checked, never existence-checked.
EXTERNAL_ISSUE_FORMAT = re.compile(r"^issue/\S+$")
CROSS_REPO_FORMAT = re.compile(r"^[A-Za-z0-9._-]+/BL-\d+$")
REQUIRED_FIELDS = ("title", "status", "created", "updated")
# Audit "board" files: living dashboards (per-methodology rollups), not work items.
AUDIT_BOARD_FILES = {"00-methodology.md", "00-inventory.md", "00-changelog.md"}
# Pre-00-* uppercase board names still parse everywhere (aidex-audit's
# validate-audit.sh semantics); the canonical-form check downgrades them to a
# migration warning instead of a filename violation.
AUDIT_LEGACY_BOARD_FILES = {"INVENTORY.md": "00-inventory.md",
                            "METHODOLOGY.md": "00-methodology.md",
                            "CHANGELOG.md": "00-changelog.md"}

# D-04 enforcement heuristic (BL-047): knowledge artifacts are always English; a
# body is flagged Spanish-dominant only on a conservative stopword-density test.
# The Spanish set avoids tokens that are also common English words ("no", "a",
# "he", "me", "sin", "con") so bilingual bodies with quoted Spanish never trip it.
SPANISH_STOPWORDS = {
    "el", "la", "los", "las", "una", "uno", "unas", "unos", "de", "del", "al",
    "que", "es", "son", "está", "están", "fue", "era", "ser", "hay", "como",
    "pero", "más", "para", "por", "sobre", "también", "porque", "cuando",
    "donde", "entre", "desde", "hasta", "según", "muy", "ya", "cada", "todo",
    "toda", "todos", "todas", "esta", "este", "esto", "estas", "estos", "se",
    "sus", "les", "nos", "tiene", "tienen", "puede", "pueden", "debe", "deben",
    "así", "aquí", "durante", "después",
}
ENGLISH_STOPWORDS = {
    "the", "and", "of", "to", "in", "is", "that", "for", "with", "on", "as",
    "are", "this", "be", "it", "by", "from", "or", "an", "not", "at", "was",
    "we", "if", "has", "have", "will", "which", "when", "can", "should",
    "must", "each", "all", "into", "than", "then", "these", "those", "there",
    "any", "only", "also", "after", "before", "over", "under", "between",
    "while", "where", "how", "what", "who", "but", "do", "does", "did", "so",
    "such", "may", "might", "would", "could", "about", "through", "per",
    "via", "within", "without", "no", "new", "once", "here", "now",
}
# Flag only clearly-Spanish bodies: at least this many Spanish stopword hits AND
# at least this ratio over English hits (borderline bilingual text stays silent).
LANG_MIN_SPANISH_HITS = 10
LANG_SPANISH_RATIO = 3

# ---------- Finding type ----------

@dataclass
class Finding:
    type: str
    file: str
    rule: str
    severity: str  # "violation", "warning", or "info"
    message: str

# ---------- Front-matter parser (no pyyaml dependency) ----------

FM_DELIM = re.compile(r"^---\s*$")

def parse_frontmatter(text: str) -> dict | None:
    """Return dict of front-matter fields, or None if missing/malformed.

    Minimal YAML — supports `key: value` and `key: "quoted value"`. Does not
    support nested mappings. Cross-reference fields are always single-line.
    """
    lines = text.splitlines()
    if not lines or not FM_DELIM.match(lines[0]):
        return None
    end = None
    for i in range(1, len(lines)):
        if FM_DELIM.match(lines[i]):
            end = i
            break
    if end is None:
        return None
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
        else:
            # YAML semantics: an unquoted scalar ends at ` #` (inline comment).
            # Field regression 2026-07-02: `channel: call  # meeting | call` must
            # parse as `call`, not the whole line.
            val = re.split(r"\s+#", val, maxsplit=1)[0].rstrip()
        fields[key] = val
    return fields

# ---------- Resolver ----------

TYPE_FOLDER_TO_PREFIX = {
    "backlog": "backlog",
    "plans": "plan",
    "requests": "request",
    "decisions": "decision",
    "references": "reference",
    "research": "research",
    "audits": "audit",
    "communications": "communication",
    "loops": "loop",
    "worktrees": "worktree",
}
PREFIX_TO_FOLDER = {v: k for k, v in TYPE_FOLDER_TO_PREFIX.items()}

def is_external_ref(ref: str) -> bool:
    """True for refs that point outside this .context/ (BL-070): `issue/<id>` for
    an external tracker, and `<repo>/BL-NNN` for a cross-repo backlog counterpart.
    Both are stable identifiers, so the format is checked but existence is not —
    the target is not on this filesystem tree. A `<type>/…` ref is never external:
    local types stay resolvable, so a typo in one is still caught."""
    if EXTERNAL_ISSUE_FORMAT.match(ref):
        return True
    prefix = ref.split("/", 1)[0]
    return prefix not in PREFIX_TO_FOLDER and bool(CROSS_REPO_FORMAT.match(ref))

def crossref_target_exists(context_dir: Path, ref: str) -> bool:
    """ref format: <type>/<filename-or-path>. Search active and _archive."""
    if "/" not in ref:
        return False
    prefix, rest = ref.split("/", 1)
    if rest == "pending":
        return True  # sentinel handled by caller as warning
    folder = PREFIX_TO_FOLDER.get(prefix)
    if not folder:
        return False
    base = context_dir / folder
    # Accept both bare slug (no extension) and explicit filename
    candidates = [rest, rest + ".md"]
    for cand in candidates:
        if (base / cand).exists():
            return True
        if (base / "_archive" / cand).exists():
            return True
        # Modular plan folder (no extension expected)
        if (base / cand).is_dir():
            return True
    # Audit references include methodology/<run>/<finding-id> — we can't fully
    # resolve finding IDs from filesystem; settle for directory existence.
    if folder == "audits":
        # Every position a run folder can occupy. D-10 archives a finished run
        # precisely so inbound refs keep resolving, so the archived shapes are
        # not a fallback here — they are the steady state of any closed run.
        def audit_run_exists(run: str) -> bool:
            if (base / run).exists():
                return True
            if (base / "_archive" / run).exists():          # audits/_archive/<run>
                return True
            head, _, tail = run.rpartition("/")             # audits/<meth>/_archive/<run>
            if head and (base / head / "_archive" / tail).exists():
                return True
            # audits/_archive/<run>, reached by a ref that still names the methodology.
            # archive-sweep.py flattens a grouped run into the root archive (D-10 and
            # 00-global §5 both put it there), while the ref that points at it keeps the
            # `<meth>/<run>` shape it was written with. Applying the sweep's own proposal
            # otherwise turns clean items into violations — the housekeeping punishing
            # itself, which is the failure D-10 exists to prevent (2026-08-25).
            return bool(head) and (base / "_archive" / tail).exists()

        if audit_run_exists(rest):
            return True
        # Strip trailing finding-id segment and retry on the run folder: a finding
        # id is not a path, so it never resolves on its own.
        parts = rest.split("/")
        if len(parts) > 1 and audit_run_exists("/".join(parts[:-1])):
            return True
    return False

# ---------- Ignored subtrees (BL-037) ----------

IGNORE_NAME = ".aidex-ignore"

def load_ignores(context_dir: Path) -> list[str]:
    """Read `<context>/.aidex-ignore`: one path prefix per line, relative to
    `.context/` (a leading `.context/` is tolerated), `#` comments and blanks
    ignored. No globs — a line matches a path equal to it or under it.

    The escape hatch for vendored/imported subtrees (a third-party repo dropped
    under `research/<topic>/`): their files are not aidex artifacts, so neither
    the validator nor the migrator may judge or rename them."""
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

# ---------- Tooling state that is not an artifact ----------

# `wrap_report.py` keeps the last version that PASSED the artifact contract in a
# `.aidex-artifact-prev/` sibling of the report it wrapped. Its contents are
# tooling state, not a `.context/` tier: every file there is a superseded copy of
# a page already judged at its canonical path, so judging the snapshot too reports
# the same page twice. A waiver cannot settle it either — the waiver anchor hashes
# a file that the next passing run replaces, so the line goes stale by design.
#
# Skipped in the walkers, the way `audits/_archive/` is, rather than counted as an
# `.aidex-ignore` exemption: that count reports subtrees the USER declared, and
# this one is ours.
BASELINE_DIR_NAME = ".aidex-artifact-prev"


def is_baseline_snapshot(path: Path) -> bool:
    return BASELINE_DIR_NAME in path.parts


# ---------- File walkers ----------

# Rendered reports are the artifacts most often READ, and they were invisible to
# every rule because the walkers only ever yielded `*.md`. Only ONE check runs on
# them — the language check — because filename and front-matter rules do not apply
# to a rendered page, and a census found zero filename violations among them.
#
# Enumerated PER TYPE rather than by a single rglob over .context/, so
# check_body_language's `if type_name == "communications": return None` carries.
# A flat rglob would flag every Spanish `email.html` twin, which D-04 exempts by
# name — the language check would start contradicting the language canon.
HTML_BLOCK_RE = re.compile(r"<(script|style)\b.*?</\1>", re.S | re.I)
HTML_TAG_RE = re.compile(r"<[^>]+>")


# `- language: es` in the project's artifact style profile. The regex is a COPY of
# aidex-dash's `LANG_FIELD` (scripts/dash/wrap_report.py) on purpose: that script is
# what writes the field and turns it into `<html lang>`, so the checker must read it
# exactly as the writer does or it silences the wrong set. A field, not prose — the
# profile's own body says "language, favicon, tone" and must not match.
ARTIFACT_LANG_FIELD = re.compile(r"^\s*[-*]?\s*language\s*:\s*([A-Za-z][A-Za-z0-9-]*)", re.M)

# Languages `check_body_language` can actually detect. The profile silences only what
# it authorises: declaring `fr` does not make a Spanish page acceptable, and declaring
# `en` leaves the rule exactly as it was.
SPANISH_LANG_CODES = frozenset({"es", "spa", "spanish"})


def declared_artifact_language(context_dir: Path) -> str | None:
    """The language this project declares for its RENDERED artifacts, or None.

    Scope is artifacts. `.context/` markdown stays English (D-04) whatever this
    says — see check_body_language, which is where the scoping is enforced.
    """
    profile = context_dir / "artifact-style.md"
    try:
        text = profile.read_text(encoding="utf-8", errors="replace")
    except OSError:
        # The profile is an optimisation, not a contract: an unreadable one falls
        # back to "nothing declared" rather than aborting the run.
        return None
    m = ARTIFACT_LANG_FIELD.search(text)
    return m.group(1).lower() if m else None


def strip_html(text: str) -> str:
    """Visible text of a page: script/style contents removed, then tags."""
    return HTML_TAG_RE.sub(" ", HTML_BLOCK_RE.sub(" ", text))


def iter_html_for_type(context_dir: Path, type_name: str) -> Iterable[Path]:
    base = context_dir / type_name
    if not base.is_dir():
        return
    for path in sorted(base.rglob("*.html")):
        # Mirror the .md walker's archive policy for this type, so a page and its
        # markdown twin are never judged differently. Only `audits` skips its
        # archive (plans, backlog, requests and decisions all walk theirs), and
        # that outlier is not this change's to settle — following it keeps the
        # two walkers consistent, which is the whole point.
        if type_name == "audits" and "/_archive/" in str(path):
            continue
        if is_baseline_snapshot(path):
            continue
        yield path


def iter_files_for_type(context_dir: Path, type_name: str) -> Iterable[Path]:
    """Public walker: `_iter_md_by_type` minus the baseline snapshots. Filtered
    here rather than at each of the eleven `yield` sites below it."""
    for path in _iter_md_by_type(context_dir, type_name):
        if is_baseline_snapshot(path):
            continue
        yield path


def _iter_md_by_type(context_dir: Path, type_name: str) -> Iterable[Path]:
    base = context_dir / type_name
    if not base.is_dir():
        return
    if type_name == "audits":
        # Per-run index.md and per-methodology canonical files
        for path in base.rglob("*.md"):
            if "/_archive/" in str(path):
                continue
            yield path
        return
    if type_name in ("references", "research"):
        for path in base.rglob("*.md"):
            yield path
        return
    if type_name == "communications":
        # communications/{received,sent}/<YYYY-MM-DD>-<slug>/body.md
        for path in base.rglob("*.md"):
            if "/_archive/" in str(path):
                continue
            yield path
        return
    if type_name == "worktrees":
        idx = base / "00-index.md"
        if idx.is_file():
            yield idx
        for path in sorted(base.glob("[0-9][0-9]-*.md")):
            if path.name == "00-index.md":
                continue  # already yielded above; the NN-*.md glob also matches it
            yield path
        return
    if type_name == "plans":
        # Both single-file and modular plans
        for path in base.iterdir():
            if path.is_file() and path.suffix == ".md":
                yield path
            elif path.is_dir() and path.name != "_archive":
                for sub in path.glob("*.md"):
                    yield sub
        # Archive
        archive = base / "_archive"
        if archive.is_dir():
            for path in archive.rglob("*.md"):
                yield path
        return
    # backlog, requests, decisions: flat folder with _archive/
    for path in base.glob("*.md"):
        yield path
    archive = base / "_archive"
    if archive.is_dir():
        for path in archive.glob("*.md"):
            yield path
    # backlog/_deferred/: open-but-blocked items (known dir, like _archive/, never orphan).
    if type_name == "backlog":
        deferred = base / "_deferred"
        if deferred.is_dir():
            for path in deferred.glob("*.md"):
                yield path

# ---------- Checks ----------

def in_comm_entry_folder(path: Path) -> bool:
    """True when `path` sits directly inside a well-formed communication entry folder
    (`{received,sent,meetings}/<YYYY-MM-DD>-<slug>/`). Says nothing about the filename."""
    parent = path.parent
    return (parent.parent.name in (COMM_DIRECTIONS | {COMM_MEETING_DIR})
            and bool(ISO_FOLDER.match(parent.name)))

def is_comm_attachment(type_name: str, path: Path) -> bool:
    """A non-body.md file inside a valid dated communication folder is an attachment
    (transcript, slides, summary, action items) — canon explicitly allows files
    alongside body.md. Attachments are free-form: no shape/front-matter checks."""
    if type_name != "communications" or path.name == "body.md":
        return False
    return in_comm_entry_folder(path)

def is_loop_state_sidecar(type_name: str, path: Path) -> bool:
    """Loop engines keep an operational state sidecar (`<spec-basename>-STATE.md`)
    next to the spec. It is working state, not a knowledge artifact: exempt from
    dated-filename and front-matter rules (renaming live state breaks running loops)."""
    return type_name == "loops" and path.name.endswith("-STATE.md")

def check_filename(type_name: str, path: Path) -> Finding | None:
    name = path.name
    # A stray README.md inside a .context/ type folder is not canonical — the only
    # index name is 00-index.md (canon §2; field friction 2026-06-29).
    if name == "README.md":
        return Finding(type_name, str(path), "readme-in-context", "violation",
                       "README.md is not a canonical .context/ file — the index name is 00-index.md "
                       "(move the content into 00-index.md or a dated artifact)")
    # Exemptions: index files, NN-numbered files inside reference/research topic folders,
    # per-methodology audit canonical files.
    if name in ("00-index.md", "00-overview.md"):
        return None
    if name in ("00-methodology.md", "00-inventory.md", "00-changelog.md"):
        return None
    if is_loop_state_sidecar(type_name, path):
        return None
    if type_name in ("references", "research", "worktrees") and re.match(r"^\d{2}-[a-z0-9-]+\.md$", name):
        return None
    if type_name == "plans":
        # Modular plan internal files: NN-<slug>.md
        if path.parent.name != "plans" and path.parent.name != "_archive":
            if re.match(r"^\d{2}-[a-z0-9-]+\.md$", name):
                return None
    if type_name == "communications":
        # Dated unit is the <YYYY-MM-DD>-<slug>/ folder; the main file is body.md,
        # with attachments allowed alongside (canon: transcript/slides/summary).
        # The folder lives under received/, sent/ (async) or meetings/ (synchronous).
        # A pre-canonical body name (email.md, conversation.md) would otherwise pass as
        # a free-form attachment — checked FIRST so the exemption cannot swallow it.
        if name in COMM_LEGACY_BODY_FILES and in_comm_entry_folder(path):
            return Finding(type_name, str(path), "communication-legacy-body-name", "violation",
                           f"{name!r} is a pre-canonical body filename — rename it to "
                           f"{COMM_LEGACY_BODY_FILES[name]!r} "
                           f"(bash ~/.claude/skills/aidex-comm/scripts/migrate-communications.sh)")
        if is_comm_attachment(type_name, path):
            return None
        if name == "body.md":
            parent = path.parent
            if parent.parent.name in (COMM_DIRECTIONS | {COMM_MEETING_DIR}) and ISO_FOLDER.match(parent.name):
                return None
            return Finding(type_name, str(path), "communication-shape-invalid", "violation",
                           "expected communications/{received,sent,meetings}/<YYYY-MM-DD>-<slug>/body.md")
        return Finding(type_name, str(path), "communication-shape-invalid", "violation",
                       f"unexpected file {name!r} outside a dated folder; communications use "
                       f"body.md (+ attachments) in {{received,sent,meetings}}/<YYYY-MM-DD>-<slug>/")
    if type_name == "audits":
        if path.name in ("index.md", "findings.md"):
            return None
        # Legacy uppercase boards warn instead of hard-failing the filename check
        # (aligned with aidex-audit's validate-audit.sh / test-canonical-filenames.sh).
        # Boards live at audits/ root or a methodology root — an uppercase name
        # INSIDE a dated run folder is a free-form working note, not a board
        # (review 2026-07-04): the subdoc exemption must win there.
        if path.name in AUDIT_LEGACY_BOARD_FILES \
           and not _is_audit_run_folder(path.parent.name):
            return Finding(type_name, str(path), "audit-legacy-board-name", "warning",
                           f"legacy board name {path.name!r} — canonical is "
                           f"{AUDIT_LEGACY_BOARD_FILES[path.name]!r}; run /aidex-audit migrate")
        # Run-internal sub-documents (notes, logs, stage write-ups) are free-form;
        # the dated naming applies to the run folder, not files within it.
        if is_audit_subdoc(type_name, path):
            return None
    if LEGACY_FILENAME.match(name):
        return Finding(type_name, str(path), "filename-format", "violation",
                       f"filename uses legacy YYYYMMDD format; expected YYYY-MM-DD-<slug>.md")
    if not ISO_FILENAME.match(name):
        return Finding(type_name, str(path), "filename-format", "violation",
                       f"filename {name!r} does not match YYYY-MM-DD-<slug>.md")
    return None

def _is_audit_run_folder(name: str) -> bool:
    """A dated audit run folder (canonical YYYY-MM-DD-<slug> or legacy YYYYMMDD*).
    Boards never live inside one — files there are run-internal sub-documents."""
    return bool(ISO_FOLDER.match(name) or re.match(r"^\d{8}", name))

def is_audit_subdoc(type_name: str, path: Path) -> bool:
    """An audit file nested inside a run/methodology folder (parent is not `audits`
    itself) and not a canonical board file is a working sub-document — free-form
    run write-ups, logs, stage notes. The dated unit is the run folder, not these.
    """
    if type_name != "audits":
        return False
    if path.name in AUDIT_BOARD_FILES:
        return False
    return path.parent.name != "audits"

def is_subdocument(type_name: str, path: Path) -> bool:
    """NN-*.md files inside modular plan folders, references/<topic>/, research/<topic>/
    are sub-documents of the topic's 00-index.md and don't require their own front-matter.
    """
    if not re.match(r"^\d{2}-[a-z0-9-]+\.md$", path.name):
        return False
    if path.name in ("00-index.md", "00-overview.md"):
        return False
    if type_name in ("references", "research"):
        return path.parent.name not in (type_name, "_archive")
    if type_name == "plans":
        return path.parent.name not in ("plans", "_archive")
    return False

def check_frontmatter(type_name: str, path: Path, text: str, fm: dict | None) -> list[Finding]:
    findings: list[Finding] = []
    if type_name == "audits" and (path.name in AUDIT_BOARD_FILES
                                  or path.name in AUDIT_LEGACY_BOARD_FILES):
        return findings  # tabular/freeform board (modern or legacy name) — exempt
    if is_audit_subdoc(type_name, path):
        return findings  # run-internal note/log/write-up — exempt
    if is_comm_attachment(type_name, path) or is_loop_state_sidecar(type_name, path):
        return findings  # free-form companion files — exempt
    if path.name == "README.md":
        return findings  # already condemned by readme-in-context; don't double-report
    # Type-level aggregator index (e.g. backlog/00-index.md) is auto-generated
    # by register-item.sh / similar tooling and intentionally carries no front-matter.
    # Sub-folder indexes (plans/<date>-feature/00-index.md, references/<topic>/00-index.md)
    # are NOT exempt — those are the artifact's main file and must declare metadata.
    if path.name == "00-index.md" and path.parent.name == type_name:
        return findings
    if is_subdocument(type_name, path):
        return findings  # sub-document of a 00-index.md
    if fm is None:
        findings.append(Finding(type_name, str(path), "frontmatter-missing", "violation",
                                "no YAML front-matter block (--- ... ---)"))
        return findings
    if type_name == "communications":
        is_meeting = path.parent.parent.name == COMM_MEETING_DIR
        if is_meeting:
            # Synchronous record: participants replace direction/from/to.
            for field_name in COMM_MEETING_REQUIRED_FIELDS:
                # participants is a YAML list — the minimal parser only sees the bare
                # key (value on following lines), so check key presence, not a scalar.
                if field_name == "participants":
                    if field_name not in fm:
                        findings.append(Finding(type_name, str(path), "frontmatter-field-missing", "violation",
                                                "required field 'participants' missing"))
                    continue
                if field_name not in fm or not fm[field_name]:
                    findings.append(Finding(type_name, str(path), "frontmatter-field-missing", "violation",
                                            f"required field '{field_name}' missing or empty"))
            ch = fm.get("channel", "")
            if ch and ch not in COMM_MEETING_CHANNELS:
                findings.append(Finding(type_name, str(path), "communication-channel-invalid", "violation",
                                        f"channel={ch!r} not in {sorted(COMM_MEETING_CHANNELS)} for meetings/"))
        else:
            for field_name in COMM_REQUIRED_FIELDS:
                if field_name not in fm or not fm[field_name]:
                    findings.append(Finding(type_name, str(path), "frontmatter-field-missing", "violation",
                                            f"required field '{field_name}' missing or empty"))
            ch = fm.get("channel", "")
            if ch and ch not in COMM_ASYNC_CHANNELS:
                findings.append(Finding(type_name, str(path), "communication-channel-invalid", "violation",
                                        f"channel={ch!r} not in {sorted(COMM_ASYNC_CHANNELS)}"))
            # Canon: `direction` mirrors the folder it lives in. Stated since the
            # layout shipped, enforced by nobody — which is how `sent/` entries with
            # `direction: received` accumulated (RETRO-49).
            folder = path.parent.parent.name
            dr = fm.get("direction", "")
            if dr and folder in COMM_DIRECTIONS and dr != folder:
                findings.append(Finding(type_name, str(path), "communication-direction-mismatch", "violation",
                                        f"direction={dr!r} but the entry lives under {folder}/ — "
                                        f"direction mirrors the folder (move the entry or fix the field)"))
        st = fm.get("status", "")
        if st and st not in COMM_STATUS:
            findings.append(Finding(type_name, str(path), "communication-status-invalid", "violation",
                                    f"status={st!r} not in {sorted(COMM_STATUS)}"))
        for date_field in ("created", "updated", "date"):
            val = fm.get(date_field, "")
            if val and not ISO_DATE.match(val):
                findings.append(Finding(type_name, str(path), "date-format-invalid", "violation",
                                        f"{date_field}={val!r} is not YYYY-MM-DD"))
        return findings
    for field_name in REQUIRED_FIELDS:
        # references/ are documentation, not work items — status is optional (canon §6 exemption)
        if type_name == "references" and field_name == "status":
            continue
        if field_name not in fm or not fm[field_name]:
            findings.append(Finding(type_name, str(path), "frontmatter-field-missing", "violation",
                                    f"required field '{field_name}' missing or empty"))
    for date_field in ("created", "updated"):
        val = fm.get(date_field, "")
        if val and not ISO_DATE.match(val):
            findings.append(Finding(type_name, str(path), "date-format-invalid", "violation",
                                    f"{date_field}={val!r} is not YYYY-MM-DD"))
    return findings

def check_status(type_name: str, path: Path, fm: dict | None) -> Finding | None:
    if fm is None or "status" not in fm:
        return None
    if type_name == "references":
        return None  # canon §6: references are documentation, not work items
    if type_name == "communications":
        return None  # comms status vocab (draft|sent) validated in check_frontmatter
    # Non-work-item files don't own a task status — the owning artifact does:
    #   - plan phase files / research|reference sub-sections → the topic 00-index.md
    #   - audit board files (00-inventory/changelog/methodology) → living dashboards
    #   - audit run sub-documents → notes inside a dated run
    if is_subdocument(type_name, path) or is_audit_subdoc(type_name, path) \
            or (type_name == "audits" and (path.name in AUDIT_BOARD_FILES
                                           or path.name in AUDIT_LEGACY_BOARD_FILES)):
        return None
    val = fm["status"]
    if type_name == "decisions":
        if val not in DECISION_STATUS:
            return Finding(type_name, str(path), "status-invalid", "violation",
                           f"status={val!r} not in {sorted(DECISION_STATUS)} (ADR vocab)")
    else:
        if val not in BASE_STATUS:
            return Finding(type_name, str(path), "status-invalid", "violation",
                           f"status={val!r} not in {sorted(BASE_STATUS)}")
    return None

def check_crossrefs(type_name: str, path: Path, fm: dict | None,
                    context_dir: Path) -> list[Finding]:
    findings: list[Finding] = []
    if fm is None:
        return findings
    for field_name in CROSSREF_FIELDS:
        ref = fm.get(field_name, "")
        if not ref:
            continue
        # External refs (issue/<id>, <repo>/BL-NNN) are accepted on format alone —
        # this branch must precede the format check, whose <type>/ enum rejects them.
        if is_external_ref(ref):
            continue
        # blocked_by may be free text (canon §7) — validate only when it is a typed
        # ref or clearly ATTEMPTS one via a path form. Free text containing a slash
        # ("FCM/APNs credentials") must not be flagged (field regression 2026-07-02).
        if field_name == "blocked_by" and not CROSSREF_FORMAT.match(ref):
            path_attempt = ref.startswith(".context/") or any(
                ref.startswith(folder + "/") for folder in TYPE_FOLDER_TO_PREFIX)
            if not path_attempt:
                continue
        if not CROSSREF_FORMAT.match(ref):
            findings.append(Finding(type_name, str(path), "cross-ref-format-invalid", "violation",
                                    f"{field_name}={ref!r} does not match <type>/<filename>"))
            continue
        if ref.endswith("/pending"):
            findings.append(Finding(type_name, str(path), "cross-ref-pending", "warning",
                                    f"{field_name}={ref!r} is a placeholder sentinel"))
            continue
        if not crossref_target_exists(context_dir, ref):
            findings.append(Finding(type_name, str(path), "cross-ref-target-missing", "violation",
                                    f"{field_name}={ref!r} resolves to no file in active or _archive/"))
    return findings

def check_backlog_priority(path: Path, fm: dict | None) -> Finding | None:
    if fm is None or "priority" not in fm:
        return None
    val = fm["priority"]
    if val and val not in BACKLOG_PRIORITIES:
        hint = ""
        if str(val).strip().lower() == "blocked":
            hint = (" — Blocked is a modifier, not a priority: keep the real "
                    "priority and set blocked_by")
        return Finding("backlog", str(path), "backlog-priority-invalid", "violation",
                       f"priority={val!r} not in {sorted(BACKLOG_PRIORITIES)}{hint}")
    return None

def check_backlog_type(path: Path, fm: dict | None) -> Finding | None:
    """Backlog `type:` facet (ADR 2026-07-23). A present value must be in the
    closed enum (violation otherwise). An absent value on an active item is a
    warn-then-ratchet nudge — register-item.sh stamps `type` going forward, and
    existing items are not retro-fixed; archived items are terminal, so exempt."""
    if fm is None:
        return None
    val = fm.get("type", "")
    if val and val not in BACKLOG_TYPES:
        return Finding("backlog", str(path), "backlog-type-invalid", "violation",
                       f"type={val!r} not in {sorted(BACKLOG_TYPES)}")
    if not val and "_archive" not in path.parts:
        return Finding("backlog", str(path), "backlog-type-missing", "warning",
                       f"no type facet — add one of {sorted(BACKLOG_TYPES)} "
                       f"(default 'task'); register-item.sh assigns it going forward")
    return None

def check_deferred_blocked_by(path: Path, fm: dict | None) -> Finding | None:
    """Items in backlog/_deferred/ are open-but-blocked: blocked_by MUST be populated.
    Warn (not error) if it's missing so existing deferred items aren't hard-failed.
    """
    if "/_deferred/" not in str(path).replace(os.sep, "/"):
        return None
    if fm and fm.get("blocked_by"):
        return None
    return Finding("backlog", str(path), "deferred-missing-blocked-by", "warning",
                   "deferred item has no blocked_by — _deferred/ items must record their blocker")

def check_archive_status_open(type_name: str, path: Path, fm: dict | None) -> Finding | None:
    """A file under _archive/ of an archive-bearing type whose status is still
    open/doing is archived-but-not-closed: the location says terminal, the status
    says active (dual-carried lifecycle drift). Warning, not violation — retrofit
    check: existing boards without a ratchet baseline must not hard-fail. Sub-documents
    and loop STATE sidecars don't own a status (check_status skips them too) — exempt.
    """
    if type_name not in TYPES_WITH_ARCHIVE:
        return None
    if "_archive" not in path.parts:
        return None
    if is_subdocument(type_name, path) or is_loop_state_sidecar(type_name, path):
        return None
    if fm and fm.get("status") in ("open", "doing"):
        return Finding(type_name, str(path), "archive-status-open", "warning",
                       f"archived but status={fm['status']!r} — set done/dropped or move it "
                       f"back to the active queue")
    return None

BACKLOG_PLACEHOLDER_RE = re.compile(r"<!--\s*(?:Why is this worth doing|concrete, verifiable criterion)")

def check_backlog_placeholder_body(path: Path, text: str) -> Finding | None:
    """An active backlog entry still carrying register-item.sh's template placeholder
    HTML comments was never filled in. Warning (additive, ratchet-absorbed): the
    close self-check catches empty-body items instead of archiving them unnoticed.
    Archived items are exempt — the drift is only actionable before close."""
    if "_archive" in path.parts:
        return None
    if BACKLOG_PLACEHOLDER_RE.search(text):
        return Finding("backlog", str(path), "backlog-placeholder-body", "warning",
                       "entry still contains register-template placeholder comments — fill in "
                       "Context/Acceptance before closing")
    return None

def check_plan_current_phase(plan_dir: Path) -> Finding | None:
    index = plan_dir / "00-index.md"
    if not index.is_file():
        return None
    text = index.read_text(encoding="utf-8", errors="replace")
    fm = parse_frontmatter(text)
    if not fm or "current-phase" not in fm:
        return None
    try:
        current = int(fm["current-phase"])
    except (ValueError, TypeError):
        return Finding("plans", str(index), "plan-current-phase-out-of-range", "violation",
                       f"current-phase={fm['current-phase']!r} is not an integer")
    phases = sorted(p.name for p in plan_dir.glob("[0-9][0-9]-*.md") if p.name != "00-index.md")
    max_phase = 0
    for name in phases:
        m = re.match(r"^(\d{2})-", name)
        if m:
            max_phase = max(max_phase, int(m.group(1)))
    if current > max_phase + 1:  # +1 for "phase N complete, ready to start N+1"
        return Finding("plans", str(index), "plan-current-phase-out-of-range", "violation",
                       f"current-phase={current} exceeds max phase file index ({max_phase})")
    return None

def check_archive_folder(context_dir: Path, type_name: str) -> Finding | None:
    if type_name not in TYPES_WITH_ARCHIVE:
        return None
    base = context_dir / type_name
    if not base.is_dir():
        return None
    if not (base / "_archive").is_dir():
        return Finding(type_name, str(base), "archive-folder-missing", "warning",
                       f"_archive/ folder absent — required by D-05 (legal if no finished artifacts yet)")
    return None

def check_index_files(context_dir: Path, type_name: str) -> list[Finding]:
    findings: list[Finding] = []
    base = context_dir / type_name
    if not base.is_dir():
        return findings
    # 00-index.md is canonical. 00-overview.md is accepted as an alias for research
    # modules only (flagged at INFO, not a violation); misplaced elsewhere is a violation.
    if type_name == "research":
        for path in base.rglob("00-overview.md"):
            findings.append(Finding(type_name, str(path), "index-overview-alias", "info",
                                    "00-overview.md accepted as a research index alias for 00-index.md"))
    else:
        for path in base.rglob("00-overview.md"):
            findings.append(Finding(type_name, str(path), "index-overview-misplaced", "violation",
                                    "00-overview.md is only valid inside research/<topic>/"))
    return findings

# ---------- Body-language check (D-04 enforcement, BL-047) ----------

FENCED_CODE_RE = re.compile(r"(?ms)^[ \t]*```.*?^[ \t]*```[ \t]*$")
WORD_RE = re.compile(r"[a-záéíóúñü]+")
# Paste-unsafe markdown in an outgoing email body (RETRO-23). The table pattern needs a
# header row AND a delimiter row, so a lone `|` in prose is not a table; the quote pattern
# is the ordinary blockquote indent range.
COMM_MD_TABLE_RE = re.compile(r"^[ \t]*\|.*\|[ \t]*\n[ \t]*\|?[ \t]*:?-{3,}", re.M)
COMM_MD_QUOTE_RE = re.compile(r"^[ \t]{0,3}>", re.M)

def body_after_frontmatter(text: str) -> str:
    """Body text only — front-matter values are exempt from the language check
    (titles/subjects may legitimately be native-language)."""
    lines = text.splitlines()
    if lines and FM_DELIM.match(lines[0]):
        for i in range(1, len(lines)):
            if FM_DELIM.match(lines[i]):
                return "\n".join(lines[i + 1:])
    return text

def check_comm_paste_safe(path: Path, text: str, fm: dict | None) -> list[Finding]:
    """An outgoing email body is pasted into Outlook or Gmail, which render neither
    markdown tables nor blockquotes — both have shipped to real recipients as literal
    `|` grids and `>` characters (RETRO-23). Prose or bullets are the substitute.

    Scoped deliberately to `sent/` + `channel: email`. A `received/` body is a faithful
    capture of what arrived: a table in it is CORRECT, and `>`-prefixed lines are the
    normal quoted-thread shape. WhatsApp and meetings are not pasted anywhere."""
    if fm is None or path.name != "body.md":
        return []
    if path.parent.parent.name != "sent" or fm.get("channel", "") != "email":
        return []
    body = FENCED_CODE_RE.sub("", body_after_frontmatter(text))
    findings: list[Finding] = []
    for rule_line, label, substitute in (
            (COMM_MD_TABLE_RE, "markdown table", "a bulleted list or short labelled lines"),
            (COMM_MD_QUOTE_RE, "markdown blockquote", "plain prose, or 'X wrote:' before the text")):
        m = rule_line.search(body)
        if m:
            n = body[:m.start()].count("\n") + 1
            findings.append(Finding("communications", str(path), "communication-paste-unsafe",
                                    "violation",
                                    f"{label} at body line ~{n} — Outlook/Gmail do not render it; "
                                    f"use {substitute}"))
    return findings

def check_body_language(type_name: str, path: Path, text: str,
                        declared_language: str | None = None) -> Finding | None:
    """Warn when a knowledge artifact's body reads Spanish-dominant (D-04:
    knowledge artifacts are always English). Conservative by design — flags
    clearly-Spanish bodies only, never borderline bilingual quotes.
    communications/ are exempt (native language per D-04); loop STATE sidecars
    (operational working state) and fenced code blocks are skipped.

    SEVERITY IS `warning`, DELIBERATELY (BL-227, decided 2026-08-24). The finding
    that raised it is right that a rule which cannot fail the exit code is a
    convention rather than enforcement — the decision rests on what the standing
    waivers turned out to be, not on disagreeing with that. All 43 in this repo were
    audited and none is a D-04 violation parked out of sight:

      - 31 were rendered .html artifacts the project writes in Spanish ON PURPOSE, by
        the `language:` field of its own `.context/artifact-style.md`. Reading the
        profile was named there as the fix for those rather than a harsher severity,
        and it SHIPPED as BL-231 (2026-08-25): those artifacts are now silent at the
        source and their 32 waiver lines are gone (waived 52 -> 20). The severity
        argument below is unaffected — it rests on the other two groups, which have
        no such fix.
      - 9 are frozen historical markdown (pre-enforcement research and plans from
        2026-04/05) that nobody will rewrite.
      - 1 is a verbatim corpus of the user's own Spanish prompts, quoted as evidence.
        Translating it destroys the thing it exists to carry, so there is no remedy a
        violation could demand.

    Two mechanics also argue against it. Archive-on-close (D-10) is mandatory and
    moves files, orphaning path-keyed waivers — 2 of the 43 were already dead from
    exactly that within days, and one had started warning. Promotion would turn
    routine archiving into a hard build failure at an unrelated moment. And the slice
    where language leakage actually mattered, the backlog, already gates at exit 1
    through aidex-backlog/scripts/normalize-language.sh (BL-226), which filters this
    rule's JSON rather than reimplementing it.

    The middle option — `violation` for .md, `warning` for .html — was considered and
    rejected: it adds a second severity axis to a rule whose value is being one rule,
    and all ten markdown waivers are the frozen-or-verbatim cases above, so the split
    would hard-fail every one of them with no correct fix available.

    Revisit if the waiver set starts accumulating LIVE markdown that could simply have
    been written in English. That, not the raw count, is the signal."""
    if type_name == "communications":
        return None
    if is_loop_state_sidecar(type_name, path):
        return None
    # A project declaring Spanish artifacts is not a project with 31 parked
    # violations (BL-231). `declared_language` is passed ONLY from the two rendered
    # (.html) call sites, so the markdown walker cannot reach this branch: D-04 keeps
    # knowledge artifacts English whatever the profile says, and a profile that could
    # opt out of it would be a bypass rather than a fix.
    if declared_language and declared_language.lower() in SPANISH_LANG_CODES:
        return None
    body = FENCED_CODE_RE.sub("", body_after_frontmatter(text))
    tokens = WORD_RE.findall(body.lower())
    spanish = sum(1 for t in tokens if t in SPANISH_STOPWORDS)
    english = sum(1 for t in tokens if t in ENGLISH_STOPWORDS)
    if spanish >= LANG_MIN_SPANISH_HITS and spanish >= LANG_SPANISH_RATIO * english:
        return Finding(type_name, str(path), "body-language-not-english", "warning",
                       f"body reads Spanish-dominant ({spanish} Spanish vs {english} English "
                       f"stopwords) — knowledge artifacts are English (D-04); communications/ are exempt")
    return None

# ---------- Audit layout canonical-form checks (BL-047) ----------

def check_audit_folders(context_dir: Path) -> list[Finding]:
    """Folder-level audit checks, aligned with aidex-audit's validate-audit.sh
    semantics (test-canonical-filenames.sh): duplicate modern+legacy boards and
    legacy YYYYMMDD run-folder names are migration WARNINGS; a dated run folder
    that is not YYYY-MM-DD-<slug> is a violation. Non-dated folders are
    methodologies — never flagged by name."""
    findings: list[Finding] = []
    base = context_dir / "audits"
    if not base.is_dir():
        return findings

    def check_boards(d: Path) -> None:
        for legacy, modern in AUDIT_LEGACY_BOARD_FILES.items():
            if (d / legacy).is_file() and (d / modern).is_file():
                findings.append(Finding("audits", str(d / legacy), "audit-board-duplicate", "warning",
                                        f"both {modern} and {legacy} exist — remove the legacy "
                                        f"file after confirming content is migrated"))

    def check_run_name(d: Path) -> None:
        name = d.name
        if re.match(r"^\d{8}-", name):
            findings.append(Finding("audits", str(d), "audit-run-legacy-name", "warning",
                                    f"run folder {name!r} uses legacy YYYYMMDD naming — run /aidex-audit migrate"))
        elif re.match(r"^\d{4}-\d{2}-\d{2}", name) and not ISO_FOLDER.match(name):
            findings.append(Finding("audits", str(d), "audit-run-name-invalid", "violation",
                                    f"run folder {name!r} does not match YYYY-MM-DD-<slug>"))

    check_boards(base)
    for entry in sorted(base.iterdir()):
        if not entry.is_dir() or entry.name.startswith((".", "_")):
            continue
        if re.match(r"^\d", entry.name):
            check_run_name(entry)  # dated folder at the root: standalone/legacy run
            continue
        check_boards(entry)        # methodology folder: boards + dated runs inside
        for run in sorted(entry.iterdir()):
            if run.is_dir() and not run.name.startswith((".", "_")):
                check_run_name(run)
    return findings

# ---------- Plan phase-gate presence (workflow promotion threshold) ----------

# Phase 7 (tests: field, ADR forthcoming): the vocabulary an afk-impl phase's
# `tests:` field may declare. Kept in lockstep with plan-conventions.md's
# `tests: unit  # unit | api | component | e2e | none` canon line by
# test_validate.py's check_canon_lockstep.
PLAN_TESTS_VOCAB = {"unit", "api", "component", "e2e", "none"}

PHASE_HEADING_RE = re.compile(r"(?m)^#{1,4}[ \t]+Phase\b[^\n]*$")

def _is_checkpoint_heading(heading: str) -> bool:
    """'## Phase N Checkpoint' matches the Phase regex but is a tracking
    section, not a phase (regression 2026-07-19: the acceptance/gate checks
    flagged checkpoint sections). Still used as a body boundary — only skipped
    as a phase."""
    return bool(re.search(r"Checkpoint[ \t]*$", heading))

def _phase_type(heading: str, fm: dict | None) -> str:
    """afk-impl (default) unless an inline annotation or front-matter says hitl-align."""
    m = re.search(r"phase-type:\s*(hitl-align|afk-impl)", heading)
    if m:
        return m.group(1)
    if fm and fm.get("phase-type") in ("hitl-align", "afk-impl"):
        return fm["phase-type"]
    return "afk-impl"

def _phase_has_gate(heading: str, body: str, fm: dict | None) -> bool:
    """A machine-checkable gate is present if declared inline/front-matter as `gate:`,
    or the phase body carries a Verify block / an explicit machine-checkable success line."""
    if re.search(r"gate:\s*\S", heading):
        return True
    if fm and fm.get("gate"):
        return True
    if re.search(r"(?im)\*\*\s*verify", body):
        return True
    if re.search(r"(?i)machine-checkable", body):
        return True
    return False

def check_plan_phase_gates(path: Path, text: str, fm: dict | None) -> list[Finding]:
    """Warn when an afk-impl phase declares no machine-checkable gate.

    Only afk-impl phases are batch-eligible (the aidex-plan-exec promotion threshold);
    a batched phase with no gate means AI output for it is unconstrained. hitl-align
    phases are exempt — they run interactively and expect no machine gate."""
    findings: list[Finding] = []
    # Archived plans are finished work — the gateless warning is only actionable
    # before execution (field: 52/53 warnings in a real project were _archive/ noise).
    if "_archive" in path.parts:
        return findings
    headings = list(PHASE_HEADING_RE.finditer(text))
    for i, m in enumerate(headings):
        heading = m.group(0)
        start = m.end()
        end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
        body = text[start:end]
        if _is_checkpoint_heading(heading):
            continue
        if _phase_type(heading, fm) != "afk-impl":
            continue
        if not _phase_has_gate(heading, body, fm):
            label = heading.lstrip("#").strip()
            findings.append(Finding("plans", str(path), "plan-phase-gateless-afk", "warning",
                f"afk-impl phase {label!r} has no machine-checkable gate — AI output for this "
                f"phase is unconstrained; add tests/type-check/build before implementing"))
    return findings

# ---------- Plan `tests:` field (Phase 7, tests-field programme) ----------

_TESTS_ANNOTATION_RE = re.compile(r"\(([^()]*)\)")
_TESTS_VALUE_RE = re.compile(r"tests:\s*(\[[^\]]*\]|[^,\)\n#]+)")
_TESTS_REASON_RE = re.compile(r"tests:\s*none[^\n]*?#\s*reason:\s*([^\n\)]+)")

def _parse_tests_values(raw: str) -> list[str]:
    """`unit` -> ["unit"]; `[unit, api]` -> ["unit", "api"]. Strips quotes/whitespace."""
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        raw = raw[1:-1]
    return [p.strip().strip("\"'") for p in raw.split(",") if p.strip()]

def _frontmatter_raw_block(text: str) -> str:
    """The front-matter block's raw lines (inline comments intact), or "" if none.
    Needed because parse_frontmatter strips each value's trailing `# ...` comment —
    the `tests: none  # reason: ...` reason lives only in the raw text."""
    lines = text.splitlines()
    if not lines or not FM_DELIM.match(lines[0]):
        return ""
    for i in range(1, len(lines)):
        if FM_DELIM.match(lines[i]):
            return "\n".join(lines[1:i])
    return ""

def _phase_tests(heading: str, fm: dict | None, fm_raw: str) -> tuple[list[str] | None, str | None]:
    """The phase's `tests:` values and, if `tests: none`, its written reason (else
    None for both). Inline heading annotation (single-file carrier) wins; falls
    back to front-matter (multi-file carrier) — same precedence as `_phase_type`.

    The value search is restricted to the heading's `(key: value, ...)` annotation
    blob(s), not the whole heading line — a phase title that happens to mention
    "tests:" in prose (as this very field's own phase does) must not be read as a
    declaration."""
    values = None
    for blob in _TESTS_ANNOTATION_RE.findall(heading):
        m = _TESTS_VALUE_RE.search(blob)
        if m:
            values = _parse_tests_values(m.group(1))
            break
    if values is not None:
        reason_m = _TESTS_REASON_RE.search(heading)
        return values, (reason_m.group(1).strip() if reason_m else None)
    if fm and fm.get("tests"):
        values = _parse_tests_values(fm["tests"])
        reason_m = _TESTS_REASON_RE.search(fm_raw)
        return values, (reason_m.group(1).strip() if reason_m else None)
    return None, None

def check_plan_tests_field(path: Path, text: str, fm: dict | None) -> list[Finding]:
    """Warn when an afk-impl phase's `tests:` field is missing, out of vocabulary,
    or `tests: none` with no written reason.

    Only afk-impl phases carry the field (hitl-align is exempt, same as the gate
    rule); one acceptance test per phase, at the layer `tests:` names, written up
    front and left red (aidex-plan / aidex-plan-exec, Phase 7)."""
    findings: list[Finding] = []
    if "_archive" in path.parts:
        return findings
    fm_raw = _frontmatter_raw_block(text)
    headings = list(PHASE_HEADING_RE.finditer(text))

    def _check(heading: str, label: str) -> None:
        if _phase_type(heading, fm) != "afk-impl":
            return
        values, reason = _phase_tests(heading, fm, fm_raw)
        # A declared-but-empty field ([] — e.g. `tests: )`, where the value
        # regex admits a bare space) is the same defect as no field, and must
        # not validate cleaner than either the missing or the invalid case.
        if not values:
            findings.append(Finding("plans", str(path), "plan-phase-tests-missing", "warning",
                f"afk-impl phase {label!r} declares no `tests:` field — name the test "
                f"layer (unit | api | component | e2e | none) that closes this phase"))
            return
        if "none" in values and len(values) > 1:
            findings.append(Finding("plans", str(path), "plan-phase-tests-invalid", "warning",
                f"afk-impl phase {label!r} mixes `none` with other `tests:` values "
                f"{values!r} — `none` must stand alone"))
            return
        invalid = [v for v in values if v not in PLAN_TESTS_VOCAB]
        if invalid:
            findings.append(Finding("plans", str(path), "plan-phase-tests-invalid", "warning",
                f"afk-impl phase {label!r} declares `tests:` value(s) {invalid!r} outside "
                f"the vocabulary (unit | api | component | e2e | none)"))
            return
        if values == ["none"] and not reason:
            findings.append(Finding("plans", str(path), "plan-phase-tests-none-no-reason", "warning",
                f"afk-impl phase {label!r} declares `tests: none` with no written reason "
                f"— add `# reason: <why no acceptance test applies>`"))

    for i, m in enumerate(headings):
        heading = m.group(0)
        if _is_checkpoint_heading(heading):
            continue
        _check(heading, heading.lstrip("#").strip())

    # Multi-file phase file whose metadata lives entirely in front-matter, with
    # no in-file "# Phase N" heading to annotate (mirrors check_plan_spec_shape).
    if not headings and _plan_file_kind(path) == "phase":
        _check("", path.name)

    return findings

# ---------- Plan spec-shape checks (spec-first canon, ADR 2026-07-19-plan-spec-first) ----------

EXEC_LOG_SECTION_RE = re.compile(r"(?ms)^##[ \t]+Execution [Ll]og\b.*?(?=^##[ \t]|\Z)")
PLAN_SIZE_BUDGETS = {"single": 8 * 1024, "phase": 6 * 1024}
PLAN_CODE_HEAVY_RATIO = 0.5
PLAN_CODE_HEAVY_MIN_BYTES = 2048

def _plan_file_kind(path: Path) -> str | None:
    """'single' for plans/<date>-<slug>.md, 'phase' for NN-*.md inside a modular
    plan folder, None for indexes and anything else."""
    if path.name == "00-index.md":
        return None
    if path.parent.name == "plans":
        return "single"
    if path.parent.parent.name == "plans" and re.match(r"^\d{2}-", path.name):
        return "phase"
    return None

def _plan_spec_body(text: str) -> str:
    """Plan body with front-matter and the Execution log section stripped —
    the log is journaling, excluded from spec-shape budgets by canon."""
    return EXEC_LOG_SECTION_RE.sub("", body_after_frontmatter(text))

def check_plan_spec_shape(path: Path, text: str, fm: dict | None) -> list[Finding]:
    """Spec-first shape warnings: afk-impl phases must declare Acceptance;
    plan files should stay inside the soft size budget; a file whose body is
    mostly fenced code is an implementation script, not a spec (allowed only
    for tier: mechanical batch phases)."""
    findings: list[Finding] = []
    if "_archive" in path.parts:
        return findings
    kind = _plan_file_kind(path)

    # Per-phase Acceptance presence (same phase-splitting as the gates check).
    headings = list(PHASE_HEADING_RE.finditer(text))
    for i, m in enumerate(headings):
        heading = m.group(0)
        start = m.end()
        end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
        body = text[start:end]
        if _is_checkpoint_heading(heading):
            continue
        if _phase_type(heading, fm) != "afk-impl":
            continue
        if not re.search(r"(?im)^\s*\*\*\s*acceptance", body):
            label = heading.lstrip("#").strip()
            findings.append(Finding("plans", str(path), "plan-phase-missing-acceptance", "warning",
                f"afk-impl phase {label!r} declares no **Acceptance** block — spec-first plans "
                f"carry 2-4 observable behaviors per phase (>=1 machine-checkable)"))
    # Phase files with no in-file heading (front-matter-carried metadata) still
    # need Acceptance somewhere in the body.
    if kind == "phase" and not headings and _phase_type("", fm) == "afk-impl":
        if not re.search(r"(?im)^\s*\*\*\s*acceptance", text):
            findings.append(Finding("plans", str(path), "plan-phase-missing-acceptance", "warning",
                f"phase file declares no **Acceptance** block — spec-first plans carry "
                f"2-4 observable behaviors per phase (>=1 machine-checkable)"))

    if kind is None:
        return findings
    spec_body = _plan_spec_body(text)
    spec_bytes = len(spec_body.encode("utf-8", errors="replace"))
    budget = PLAN_SIZE_BUDGETS[kind]
    if spec_bytes > budget:
        findings.append(Finding("plans", str(path), "plan-file-oversize", "warning",
            f"spec content is {spec_bytes} B against the ~{budget} B soft budget "
            f"(Execution log excluded) — over-budget plans usually carry derivable "
            f"code or narration; apply the removal test"))

    code_bytes = sum(len(m.group(0).encode("utf-8", errors="replace"))
                     for m in FENCED_CODE_RE.finditer(spec_body))
    if (code_bytes > PLAN_CODE_HEAVY_MIN_BYTES
            and spec_bytes > 0 and code_bytes / spec_bytes > PLAN_CODE_HEAVY_RATIO):
        findings.append(Finding("plans", str(path), "plan-code-heavy", "warning",
            f"fenced code is {code_bytes}/{spec_bytes} B ({code_bytes * 100 // spec_bytes}%) of "
            f"spec content — plans are specs, not scripts; literal code belongs only in "
            f"Contract blocks (exception: tier: mechanical batch phases)"))
    return findings

# ---------- Scoped-mode structural gate (plan-conventions.md § Plan mode) ----------

def _real_phase_headings(text: str) -> list[re.Match]:
    """Phase headings excluding '## Phase N Checkpoint' — same splitting the
    gates and spec-shape checks use, so a checkpoint never counts as a phase."""
    return [m for m in PHASE_HEADING_RE.finditer(text)
            if not _is_checkpoint_heading(m.group(0))]

def check_plan_scoped_shape(path: Path, text: str, fm: dict | None) -> list[Finding]:
    """Structural gate for `mode: scoped` plans — violations, not warnings.

    The soft proportionality budget (PLAN_SIZE_BUDGETS) was already canon and was
    measured to be dead letter: prose asking a plan to stay small loses to a process
    designed to expand. The scoped mode's guarantee is mechanical or it is nothing,
    so these four are violations. Size stays a warning via check_plan_spec_shape —
    a byte cap is a proxy that gets met by compressing prose or by dropping the
    discovered constraints that make a plan worth reading.

    Plans without `mode: scoped` are untouched (backwards compatible), and _archive/
    is exempt for the same reason its siblings are: archived plans are finished work.
    """
    findings: list[Finding] = []
    if not fm or fm.get("mode") != "scoped":
        return findings
    if "_archive" in path.parts:
        return findings

    # The canon is "exactly one phase", so this is `!= 1`, not `> 1`. A `> 1` test
    # passes a plan with ZERO phases — which carries no Goal and no Acceptance for the
    # necessity recheck to pair files against, and whose gate check then matches any
    # stray **Verify:** in the body. Found by reviewing this function with aidex-review.
    phases = _real_phase_headings(text)
    if len(phases) > 1:
        labels = ", ".join(repr(m.group(0).lstrip("#").strip()) for m in phases[:3])
        findings.append(Finding("plans", str(path), "plan-scoped-phase-count", "violation",
            f"mode: scoped declares {len(phases)} phases ({labels}...) — a scoped plan is "
            f"exactly one phase; either drop to one or re-triage the plan as mode: full"))
    elif not phases:
        findings.append(Finding("plans", str(path), "plan-scoped-phase-count", "violation",
            "mode: scoped declares no phase at all — a scoped plan is exactly one phase, "
            "and without it there is no Goal or Acceptance for the necessity recheck to "
            "pair the file contract against"))

    body = body_after_frontmatter(text)
    if not re.search(r"(?im)^\s*\*\*\s*files\s*:?\s*\*\*", body):
        findings.append(Finding("plans", str(path), "plan-scoped-no-file-contract", "violation",
            "mode: scoped declares no **Files:** block — the enumerated file list is the "
            "contract that bounds the blast radius; without it the mode guarantees nothing"))

    # Content is either on the header's own line, or a genuine list item under it.
    # The bullet alternative needs `[-*][ \t]+` — `[-*]\s*` also matched the `*` of a
    # following `**Files:**` header, which read an empty boundary as filled.
    boundary_hdr = r"^[ \t]*\*\*[ \t]*out of scope[ \t]*:?[ \t]*\*\*[ \t]*:?"
    if not re.search(boundary_hdr + r"[ \t]*\S", body, re.I | re.M) and \
       not re.search(boundary_hdr + r"[ \t]*\n+[ \t]*[-*][ \t]+\S", body, re.I | re.M):
        findings.append(Finding("plans", str(path), "plan-scoped-no-boundary", "violation",
            "mode: scoped declares no non-empty **Out of scope:** — optional elsewhere, "
            "required here: it is what stops the excluded work from being re-litigated"))

    if not _phase_has_gate("".join(m.group(0) for m in phases), body, fm):
        findings.append(Finding("plans", str(path), "plan-scoped-no-machine-gate", "violation",
            "mode: scoped declares no machine-checkable acceptance (no `gate:`, no **Verify** "
            "block) — the acceptance criteria are what the necessity recheck pairs files "
            "against, and at least one must be machine-checkable"))
    return findings

# ---------- Driver ----------

def find_context_dir(start: Path) -> Path | None:
    cur = start.resolve()
    while True:
        if (cur / ".context").is_dir():
            return cur / ".context"
        if cur.parent == cur:
            return None
        cur = cur.parent

def validate(context_dir: Path, type_filter: str | None) -> tuple[list[Finding], dict]:
    findings: list[Finding] = []
    summary_by_type: dict[str, dict] = {}
    files_scanned = 0
    ignore_prefixes = load_ignores(context_dir)
    files_ignored = 0
    # Read once per run, not once per page: the profile is one file and the
    # rendered walkers touch it for every artifact they yield.
    artifact_language = declared_artifact_language(context_dir)
    types_to_scan = [type_filter] if type_filter else TYPES

    for type_name in types_to_scan:
        base = context_dir / type_name
        type_files = 0
        type_v = 0
        type_w = 0
        type_i = 0

        # Folder-level checks
        folder_findings: list[Finding] = []
        f = check_archive_folder(context_dir, type_name)
        if f:
            folder_findings.append(f)
        folder_findings.extend(check_index_files(context_dir, type_name))
        if type_name == "audits":
            folder_findings.extend(check_audit_folders(context_dir))

        # Plan-level: current-phase per modular plan
        if type_name == "plans" and base.is_dir():
            for plan_dir in base.iterdir():
                if plan_dir.is_dir() and plan_dir.name != "_archive":
                    pf = check_plan_current_phase(plan_dir)
                    if pf:
                        folder_findings.append(pf)

        # Per-file checks
        for path in iter_files_for_type(context_dir, type_name):
            # Ignored subtrees are skipped before ANY rule runs, so the exemption
            # is uniform across every check rather than per-rule (BL-037).
            if is_ignored(context_dir, path, ignore_prefixes):
                files_ignored += 1
                continue
            type_files += 1
            files_scanned += 1
            text = ""
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError as e:
                findings.append(Finding(type_name, str(path), "io-error", "violation", str(e)))
                continue
            fm = parse_frontmatter(text)

            file_findings: list[Finding] = []
            ff = check_filename(type_name, path)
            if ff:
                file_findings.append(ff)
            file_findings.extend(check_frontmatter(type_name, path, text, fm))
            sf = check_status(type_name, path, fm)
            if sf:
                file_findings.append(sf)
            file_findings.extend(check_crossrefs(type_name, path, fm, context_dir))
            lf = check_body_language(type_name, path, text)
            if lf:
                file_findings.append(lf)
            af = check_archive_status_open(type_name, path, fm)
            if af:
                file_findings.append(af)
            if type_name == "backlog":
                bf = check_backlog_priority(path, fm)
                if bf:
                    file_findings.append(bf)
                tf = check_backlog_type(path, fm)
                if tf:
                    file_findings.append(tf)
                df = check_deferred_blocked_by(path, fm)
                if df:
                    file_findings.append(df)
                bpf = check_backlog_placeholder_body(path, text)
                if bpf:
                    file_findings.append(bpf)
            if type_name == "communications":
                file_findings.extend(check_comm_paste_safe(path, text, fm))
            if type_name == "plans":
                file_findings.extend(check_plan_phase_gates(path, text, fm))
                file_findings.extend(check_plan_tests_field(path, text, fm))
                file_findings.extend(check_plan_spec_shape(path, text, fm))
                file_findings.extend(check_plan_scoped_shape(path, text, fm))
            findings.extend(file_findings)
            for fnd in file_findings:
                if fnd.severity == "violation":
                    type_v += 1
                elif fnd.severity == "info":
                    type_i += 1
                else:
                    type_w += 1

        # Rendered pages: the language check only. Same type_name, so the
        # communications exemption applies here exactly as it does to bodies.
        for path in iter_html_for_type(context_dir, type_name):
            if is_ignored(context_dir, path, ignore_prefixes):
                files_ignored += 1
                continue
            type_files += 1
            files_scanned += 1
            try:
                html = path.read_text(encoding="utf-8", errors="replace")
            except OSError as e:
                findings.append(Finding(type_name, str(path), "io-error", "violation", str(e)))
                continue
            lf = check_body_language(type_name, path, strip_html(html),
                                     declared_language=artifact_language)
            if lf:
                findings.append(lf)
                type_w += 1

        # Aggregate folder findings
        for fnd in folder_findings:
            findings.append(fnd)
            if fnd.severity == "violation":
                type_v += 1
            elif fnd.severity == "info":
                type_i += 1
            else:
                type_w += 1

        summary_by_type[type_name] = {"files": type_files, "violations": type_v,
                                      "warnings": type_w, "info": type_i}

    # `.context/reports/` is where the anchorless artifact fallback lands, so it
    # holds pages the owner reads — but it is not an artifact TYPE and must not
    # become one: adding it to TYPES would drag `reports/` through every filename
    # and front-matter rule, and OPTIONAL_TYPES is not consulted on this path at
    # all. Only the language check runs, and only on a full (unscoped) run, since
    # a --type run is asking about one type and this is not one.
    if not type_filter:
        for path in iter_html_for_type(context_dir, "reports"):
            if is_ignored(context_dir, path, ignore_prefixes):
                files_ignored += 1
                continue
            files_scanned += 1
            try:
                html = path.read_text(encoding="utf-8", errors="replace")
            except OSError as e:
                findings.append(Finding("reports", str(path), "io-error", "violation", str(e)))
                continue
            lf = check_body_language("reports", path, strip_html(html),
                                     declared_language=artifact_language)
            if lf:
                findings.append(lf)

    summary = {
        "files_scanned": files_scanned,
        "violations": sum(1 for f in findings if f.severity == "violation"),
        "warnings":   sum(1 for f in findings if f.severity == "warning"),
        "info":       sum(1 for f in findings if f.severity == "info"),
        "by_type": summary_by_type,
    }
    if files_ignored:
        summary["ignored"] = files_ignored
    return findings, summary

def to_relative(context_dir: Path, finding: Finding) -> Finding:
    try:
        rel = str(Path(finding.file).resolve().relative_to(context_dir.resolve().parent))
    except ValueError:
        rel = finding.file
    return Finding(finding.type, rel, finding.rule, finding.severity, finding.message)

BASELINE_NAME = ".validate-baseline.json"
BASELINE_VERSION = 2

def baseline_key(f: Finding) -> str:
    """v2 key: file|rule|message. The message is the only discriminator left inside
    one file+rule pair — with the v1 file|rule key, a file already dirty for rule X
    masked every NEW rule-X violation in that same file (BL-043)."""
    return f"{f.file}|{f.rule}|{f.message}"

def legacy_baseline_key(f: Finding) -> str:
    """v1 key. Still honoured for baselines frozen before v2 so an existing
    baseline never silently turns its whole accepted set into NEW violations."""
    return f"{f.file}|{f.rule}"

def load_baseline(context_dir: Path) -> tuple[set[str], int] | None:
    """Ratchet baseline: the frozen set of violation keys a legacy project accepts.
    Present -> the enforceable rule becomes 'zero NEW violations'. Returns
    (keys, version); version 1 means the file predates per-message keys."""
    bp = context_dir / BASELINE_NAME
    if not bp.is_file():
        return None
    try:
        data = json.loads(bp.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    version = data.get("version", 1)
    if not isinstance(version, int) or version < 1:
        version = 1
    return set(data.get("keys", [])), version

def write_baseline(context_dir: Path, violations: list[Finding]) -> Path:
    bp = context_dir / BASELINE_NAME
    data = {
        "version": BASELINE_VERSION,
        "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "note": "validate.py ratchet baseline — runs report/exit only on violations NOT in this set. Refresh explicitly with --baseline.",
        "keys": sorted({baseline_key(f) for f in violations}),
    }
    bp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return bp

# ---------- Waivers (accepted findings, BL-048) ----------

WAIVERS_NAME = ".aidex-waivers"
WAIVER_ANCHOR_RE = re.compile(r"^sha256:([0-9a-f]{8,64})$")

@dataclass
class Waiver:
    rule: str
    path: str    # project-root-relative, exactly as validate.py prints it
    anchor: str  # "sha256:<hex-prefix>" of file content, or "-" for none
    reason: str
    date: str

def load_waivers(context_dir: Path) -> tuple[list[Waiver], int]:
    """Parse <context>/.aidex-waivers. Line format (# comments / blanks ignored):

        <rule> | <path> | <anchor> | <reason> [| <date>]

    Returns (waivers, unparseable_line_count) — bad lines are counted, never
    silently swallowed."""
    wp = context_dir / WAIVERS_NAME
    waivers: list[Waiver] = []
    parse_errors = 0
    if not wp.is_file():
        return waivers, parse_errors
    for raw in wp.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 4 or not parts[0] or not parts[1]:
            parse_errors += 1
            continue
        # Reason is free text and may itself contain "|" — the date, when present,
        # is the last field and must be ISO; everything between anchor and it is reason.
        tail = parts[3:]
        if len(tail) > 1 and ISO_DATE.match(tail[-1]):
            reason, date = " | ".join(tail[:-1]), tail[-1]
        else:
            reason, date = " | ".join(tail), ""
        waivers.append(Waiver(parts[0], parts[1], parts[2] or "-", reason, date))
    return waivers, parse_errors

def waiver_anchor_matches(w: Waiver, project_root: Path) -> bool:
    """No anchor ("-") always matches. An anchored waiver matches only while the
    file's sha256 still starts with the recorded prefix — any content change
    (or a missing file) resurfaces the finding."""
    if w.anchor in ("", "-"):
        return True
    m = WAIVER_ANCHOR_RE.match(w.anchor)
    if not m:
        return False
    target = project_root / w.path
    if not target.is_file():
        return False
    try:
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
    except OSError:
        return False
    return digest.startswith(m.group(1))

def waiver_state(w: Waiver, project_root: Path) -> str:
    """The state of the file the waiver NAMES: matched | stale-anchor | path-missing.

    Three states, because the format already implies three (BL-232) and only one of
    them used to be visible. `waiver_anchor_matches` collapses the last two into
    False, which is right for suppression and wrong for reporting: a content change
    is the anchor doing its job, a moved path is the anchor being unable to.
    """
    target = project_root / w.path
    if not target.is_file():
        return "path-missing"
    if w.anchor in ("", "-"):
        return "matched"
    m = WAIVER_ANCHOR_RE.match(w.anchor)
    if not m:
        return "stale-anchor"
    try:
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
    except OSError:
        return "stale-anchor"
    return "matched" if digest.startswith(m.group(1)) else "stale-anchor"


def apply_waivers(findings: list[Finding], waivers: list[Waiver],
                  project_root: Path) -> tuple[list[Finding], list[tuple[Finding, Waiver]],
                                               list[tuple[str, str, str]], list[Waiver]]:
    """Split findings into (active, waived), and report what happened to the waivers
    that did not simply match: `moved` as (rule, old_path, new_path), `orphaned` as
    the lines that now suppress nothing.

    A waiver keys on (rule, path). Archive-on-close (D-10) is mandatory and moves
    files, so that key breaks routinely — measured 2026-08-24, 2 of this repo's 43
    lines were already dead from it within days, one of them producing a live
    unwaived warning nobody had noticed. The failure is quiet in the worse direction:
    an orphaned waiver does not error, it stops suppressing.

    Decided explicitly, because the acceptance offered either: a moved waiver **keeps
    applying AND is reported**. Applying alone would auto-heal silently, which the
    three-state report is supposed to make impossible; reporting alone would leave
    the finding live in the meantime, punishing exactly the housekeeping the canon
    mandates. Relocation is keyed on the ANCHOR, never on the rule alone — so a file
    that also changed content does not get followed, which is the property the anchor
    exists to provide.
    """
    by_key: dict[tuple[str, str], Waiver] = {}
    moved: list[tuple[str, str, str]] = []
    unresolved: list[Waiver] = []
    for w in waivers:
        state = waiver_state(w, project_root)
        if state == "matched":
            by_key.setdefault((w.rule, w.path), w)
        elif state == "path-missing":
            unresolved.append(w)
        # stale-anchor: the content changed. Unchanged behaviour — the finding
        # resurfaces, which is the whole point of anchoring.

    # Relocate by content: for a waiver whose path is gone, look for a finding of the
    # same rule whose file still hashes to the recorded anchor. Bounded by construction
    # — only path-missing anchored lines reach here, and only same-rule findings are
    # hashed.
    if unresolved:
        by_rule: dict[str, list[Finding]] = {}
        for f in findings:
            by_rule.setdefault(f.rule, []).append(f)
        digests: dict[str, str | None] = {}
        still_unresolved: list[Waiver] = []
        for w in unresolved:
            m = WAIVER_ANCHOR_RE.match(w.anchor) if w.anchor not in ("", "-") else None
            hit = None
            if m:
                for f in by_rule.get(w.rule, []):
                    if f.file == w.path:
                        continue
                    if f.file not in digests:
                        t = project_root / f.file
                        try:
                            digests[f.file] = hashlib.sha256(t.read_bytes()).hexdigest()
                        except OSError:
                            digests[f.file] = None
                    d = digests[f.file]
                    if d and d.startswith(m.group(1)):
                        hit = f.file
                        break
            if hit:
                by_key.setdefault((w.rule, hit), w)
                moved.append((w.rule, w.path, hit))
            else:
                # Nothing to relocate by: an anchorless line has no content to match,
                # and an anchored one whose content is nowhere is simply dead. Either
                # way it suppresses nothing and must be said out loud.
                still_unresolved.append(w)
        unresolved = still_unresolved

    active: list[Finding] = []
    waived: list[tuple[Finding, Waiver]] = []
    for f in findings:
        w = by_key.get((f.rule, f.file))
        if w:
            waived.append((f, w))
        else:
            active.append(f)
    return active, waived, moved, unresolved

def main() -> int:
    p = argparse.ArgumentParser(description="Validate .context/ artifacts against aidex conventions")
    p.add_argument("path", nargs="?", help="Path to .context/ (default: auto-detect from cwd)")
    p.add_argument("--type", choices=TYPES, help="Validate only this artifact type")
    p.add_argument("--json", action="store_true", help="Emit JSON to stdout")
    p.add_argument("--baseline", action="store_true",
                   help="Freeze current violations as the ratchet baseline "
                        f"(<context>/{BASELINE_NAME}); later runs report/exit only on NEW violations")
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

    # A scoped run cannot see the other types' accepted debt, so it must never be
    # allowed to freeze one (deep audit 2026-07-25): `--type X --baseline` used to write
    # a baseline holding only type X, unfreezing every other type's accepted violations
    # so they returned as NEW (rc=1) on the next full run — reachable by following the
    # scoped commands 8 SKILL.md files prescribe.
    if args.baseline and args.type:
        print("error: --baseline cannot be combined with --type. A scoped run only sees "
              f"'{args.type}', so freezing it would discard every other type's accepted "
              "debt and report it as NEW. Run --baseline unscoped.", file=sys.stderr)
        return 2

    findings, summary = validate(context_dir, args.type)
    findings = [to_relative(context_dir, f) for f in findings]

    # Pre-waiver snapshot: the ratchet must remember what the tree actually contains.
    # Waivers have their own reversible lifecycle and their own `waived: N` report, so
    # they must not mutate the frozen set — otherwise deleting a waiver line promotes an
    # already-accepted finding to NEW.
    prewaiver_violations = [f for f in findings if f.severity == "violation"]

    # Waivers: accepted findings recorded in <context>/.aidex-waivers are
    # suppressed from counts and exit code, but always reported under a
    # "waived: N" summary — never silently dropped (BL-048).
    waivers, waiver_parse_errors = load_waivers(context_dir)
    waived: list[tuple[Finding, Waiver]] = []
    waiver_moved: list[tuple[str, str, str]] = []
    waiver_orphaned: list[Waiver] = []
    if waivers:
        findings, waived, waiver_moved, waiver_orphaned = apply_waivers(
            findings, waivers, context_dir.resolve().parent)
        sev_key = {"violation": "violations", "warning": "warnings", "info": "info"}
        for f, _ in waived:
            summary[sev_key[f.severity]] -= 1
            bt = summary["by_type"].get(f.type)
            if bt:
                bt[sev_key[f.severity]] -= 1
    summary["waived"] = len(waived)
    if waiver_moved:
        summary["waiver_paths_moved"] = [
            {"rule": r, "from": a, "to": b} for r, a, b in waiver_moved]
    if waiver_orphaned:
        summary["waiver_paths_orphaned"] = [
            {"rule": w.rule, "path": w.path, "anchor": w.anchor} for w in waiver_orphaned]
    if waiver_parse_errors:
        summary["waiver_parse_errors"] = waiver_parse_errors

    violations_list = [f for f in findings if f.severity == "violation"]

    if args.baseline:
        bp = write_baseline(context_dir, prewaiver_violations)
        keys = len({baseline_key(f) for f in prewaiver_violations})
        print(f"baseline written: {bp} "
              f"(v{BASELINE_VERSION}, {keys} accepted keys from "
              f"{len(prewaiver_violations)} violations)")
        return 0

    # Ratchet: with a baseline present, only violations NOT in the frozen set count.
    loaded = load_baseline(context_dir)
    new_violations: list[Finding] | None = None
    baseline_version = BASELINE_VERSION
    resolved_keys: list[str] = []
    if loaded is not None:
        baseline, baseline_version = loaded
        key_of = baseline_key if baseline_version >= BASELINE_VERSION else legacy_baseline_key
        new_violations = [f for f in violations_list if key_of(f) not in baseline]
        # Refresh policy: report accepted keys that no longer occur so the baseline
        # can be tightened. Reporting only — a validation run never mutates state.
        # Suppressed on a scoped run: a --type run cannot distinguish "fixed" from
        # "not scanned", so claiming either is a lie that advises a destructive refresh.
        #
        # Computed against PREWAIVER violations, matching what `--baseline` freezes
        # a few lines above. Against the post-waiver list, waiving a baselined finding
        # made it read as "no longer present" — so the two suppression mechanisms
        # cancelled out and the advised refresh would drop a violation that is still
        # in the tree. Pinned by test_validate.py::check_waived_is_not_resolved.
        resolved_keys = ([] if args.type
                         else sorted(baseline - {key_of(f) for f in prewaiver_violations}))
        summary["baseline"] = {"present": True, "version": baseline_version,
                               "accepted": len(baseline),
                               "new_violations": len(new_violations),
                               "resolved": len(resolved_keys)}

    if args.json:
        out = {
            "context_dir": str(context_dir.resolve()),
            "scanned_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "summary": summary,
            "violations": [asdict(f) for f in findings if f.severity == "violation"],
            "warnings":   [asdict(f) for f in findings if f.severity == "warning"],
            "info":       [asdict(f) for f in findings if f.severity == "info"],
        }
        if waived:
            out["waived"] = [dict(asdict(f), reason=w.reason, waived=w.date) for f, w in waived]
        if new_violations is not None:
            out["new_violations"] = [asdict(f) for f in new_violations]
        json.dump(out, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(f"\nConventions validation — {context_dir}")
        # `ignored` is surfaced here, not only in --json: two always-on promises depend on
        # it (rules/aidex-conventions.md "Skipped files are reported as an `ignored: N`
        # count" and 00-global.md "visible rather than silent"). Before the 2026-07-25 fix
        # a fully-exempted tree printed "scanned: 0 · violations: 0" + "OK — no violations",
        # while the sibling suppression mechanism (`waived`) was printed correctly.
        ignored_n = summary.get("ignored") or 0
        ignored_txt = f" · ignored: {ignored_n}" if ignored_n else ""
        print(f"  scanned: {summary['files_scanned']} files · "
              f"violations: {summary['violations']} · warnings: {summary['warnings']} · "
              f"info: {summary['info']}{ignored_txt}\n")
        if ignored_n:
            prefixes = load_ignores(context_dir)
            print(f"ignored: {ignored_n} file(s) exempted by {IGNORE_NAME}:")
            for pref in prefixes:
                print(f"  {pref}")
            print()
        if not findings:
            print("OK — no violations")
        else:
            violations = [f for f in findings if f.severity == "violation"]
            warnings = [f for f in findings if f.severity == "warning"]
            info = [f for f in findings if f.severity == "info"]
            if violations:
                print(f"Violations ({len(violations)}):")
                for f in violations:
                    print(f"  [{f.rule}] {f.file}: {f.message}")
            if warnings:
                print(f"\nWarnings ({len(warnings)}):")
                for f in warnings:
                    print(f"  [{f.rule}] {f.file}: {f.message}")
            if info:
                print(f"\nInfo ({len(info)}):")
                for f in info:
                    print(f"  [{f.rule}] {f.file}: {f.message}")
        if waived:
            print(f"\nwaived: {len(waived)}")
            for f, w in waived:
                date = f" ({w.date})" if w.date else ""
                print(f"  [{f.rule}] {f.file}: {w.reason}{date}")
        if waiver_moved:
            print(f"\nwaiver paths moved: {len(waiver_moved)} (still applied — the content "
                  f"anchor still matches; fix the path so the line keeps meaning something)")
            for rule, old_p, new_p in waiver_moved:
                print(f"  [{rule}] {old_p} -> {new_p}")
        if waiver_orphaned:
            print(f"\nwaiver paths orphaned: {len(waiver_orphaned)} (suppressing nothing — "
                  f"the path does not resolve and nothing can relocate the line)")
            for w in waiver_orphaned:
                why = "no anchor to relocate by" if w.anchor in ("", "-") else "no file matches the anchor"
                print(f"  [{w.rule}] {w.path}: {why}")
        if waiver_parse_errors:
            print(f"\nwaiver file: {waiver_parse_errors} unparseable line(s) ignored")
        if new_violations is not None:
            print(f"\nRatchet (baseline v{baseline_version}, {len(baseline)} accepted): "
                  f"{len(new_violations)} NEW violation(s)")
            for f in new_violations:
                print(f"  [NEW:{f.rule}] {f.file}: {f.message}")
            if baseline_version < BASELINE_VERSION:
                print(f"  note: v{baseline_version} baseline keys on file|rule, so a NEW violation of "
                      f"an already-accepted rule in the same file stays hidden — "
                      f"refresh with --baseline for per-message granularity")
            if resolved_keys:
                print(f"  {len(resolved_keys)} accepted violation(s) no longer present — "
                      f"refresh with --baseline to tighten the ratchet")

    if new_violations is not None:
        return 1 if new_violations else 0
    return 1 if summary["violations"] > 0 else 0

if __name__ == "__main__":
    sys.exit(main())
