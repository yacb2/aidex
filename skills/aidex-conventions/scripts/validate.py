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
         "communications"]
TYPES_WITH_ARCHIVE = {"backlog", "plans", "requests", "decisions"}
TYPES_WITH_INDEX = {"plans": True, "references": True, "research": True, "backlog": True}
# Acceptable-optional .context/ dirs: project-local, not scaffolded by any skill, may be
# gitignored. The validator neither requires nor flags them — listed here so the canonical
# model is explicit (auditors must not propose deleting these even when empty).
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

BASE_STATUS = {"open", "doing", "done", "dropped"}
DECISION_STATUS = {"accepted", "superseded", "dropped"}
BACKLOG_PRIORITIES = {"P0", "P1", "P2", "P3", "Blocked"}

ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
ISO_FILENAME = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(-[a-z0-9]+)*\.md$")
ISO_FOLDER = re.compile(r"^\d{4}-\d{2}-\d{2}-[a-z0-9]+(-[a-z0-9]+)*$")
LEGACY_FILENAME = re.compile(r"^\d{8}-")
CROSSREF_FIELDS = ("escalated_to", "superseded_by", "blocked_by", "origin_ref")
CROSSREF_FORMAT = re.compile(r"^(audit|backlog|plan|request|decision|reference|research|communication)/.+$")
REQUIRED_FIELDS = ("title", "status", "created", "updated")
# Audit "board" files: living dashboards (per-methodology rollups), not work items.
AUDIT_BOARD_FILES = {"00-methodology.md", "00-inventory.md", "00-changelog.md"}

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
}
PREFIX_TO_FOLDER = {v: k for k, v in TYPE_FOLDER_TO_PREFIX.items()}

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
        if (base / rest).exists() or (base / rest).is_dir():
            return True
        # Strip trailing finding-id segment and retry on the run folder.
        parts = rest.split("/")
        if len(parts) > 1 and (base / "/".join(parts[:-1])).exists():
            return True
    return False

# ---------- File walkers ----------

def iter_files_for_type(context_dir: Path, type_name: str) -> Iterable[Path]:
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

def check_filename(type_name: str, path: Path) -> Finding | None:
    name = path.name
    # Exemptions: index files, NN-numbered files inside reference/research topic folders,
    # per-methodology audit canonical files.
    if name in ("00-index.md", "00-overview.md"):
        return None
    if name in ("00-methodology.md", "00-inventory.md", "00-changelog.md"):
        return None
    if type_name in ("references", "research") and re.match(r"^\d{2}-[a-z0-9-]+\.md$", name):
        return None
    if type_name == "plans":
        # Modular plan internal files: NN-<slug>.md
        if path.parent.name != "plans" and path.parent.name != "_archive":
            if re.match(r"^\d{2}-[a-z0-9-]+\.md$", name):
                return None
    if type_name == "communications":
        # Dated unit is the <YYYY-MM-DD>-<slug>/ folder; the file inside is body.md.
        # The folder lives under received/, sent/ (async) or meetings/ (synchronous).
        if name == "body.md":
            parent = path.parent
            if parent.parent.name in (COMM_DIRECTIONS | {COMM_MEETING_DIR}) and ISO_FOLDER.match(parent.name):
                return None
            return Finding(type_name, str(path), "communication-shape-invalid", "violation",
                           "expected communications/{received,sent,meetings}/<YYYY-MM-DD>-<slug>/body.md")
        return Finding(type_name, str(path), "communication-shape-invalid", "violation",
                       f"unexpected file {name!r}; communications use body.md in a dated folder")
    if type_name == "audits":
        if path.name in ("index.md", "findings.md"):
            return None
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
    if type_name == "audits" and path.name in AUDIT_BOARD_FILES:
        return findings  # tabular/freeform board — exempt
    if is_audit_subdoc(type_name, path):
        return findings  # run-internal note/log/write-up — exempt
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
            or (type_name == "audits" and path.name in AUDIT_BOARD_FILES):
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
        # blocked_by may be free text — only validate if it looks like a typed ref
        if field_name == "blocked_by" and "/" not in ref:
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
        return Finding("backlog", str(path), "backlog-priority-invalid", "violation",
                       f"priority={val!r} not in {sorted(BACKLOG_PRIORITIES)}")
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

# ---------- Plan phase-gate presence (workflow promotion threshold) ----------

PHASE_HEADING_RE = re.compile(r"(?m)^#{1,4}[ \t]+Phase\b[^\n]*$")

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
    headings = list(PHASE_HEADING_RE.finditer(text))
    for i, m in enumerate(headings):
        heading = m.group(0)
        start = m.end()
        end = headings[i + 1].start() if i + 1 < len(headings) else len(text)
        body = text[start:end]
        if _phase_type(heading, fm) != "afk-impl":
            continue
        if not _phase_has_gate(heading, body, fm):
            label = heading.lstrip("#").strip()
            findings.append(Finding("plans", str(path), "plan-phase-gateless-afk", "warning",
                f"afk-impl phase {label!r} has no machine-checkable gate — AI output for this "
                f"phase is unconstrained; add tests/type-check/build before implementing"))
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

        # Plan-level: current-phase per modular plan
        if type_name == "plans" and base.is_dir():
            for plan_dir in base.iterdir():
                if plan_dir.is_dir() and plan_dir.name != "_archive":
                    pf = check_plan_current_phase(plan_dir)
                    if pf:
                        folder_findings.append(pf)

        # Per-file checks
        for path in iter_files_for_type(context_dir, type_name):
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
            if type_name == "backlog":
                bf = check_backlog_priority(path, fm)
                if bf:
                    file_findings.append(bf)
                df = check_deferred_blocked_by(path, fm)
                if df:
                    file_findings.append(df)
            if type_name == "plans":
                file_findings.extend(check_plan_phase_gates(path, text, fm))
            findings.extend(file_findings)
            for fnd in file_findings:
                if fnd.severity == "violation":
                    type_v += 1
                elif fnd.severity == "info":
                    type_i += 1
                else:
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

    summary = {
        "files_scanned": files_scanned,
        "violations": sum(1 for f in findings if f.severity == "violation"),
        "warnings":   sum(1 for f in findings if f.severity == "warning"),
        "info":       sum(1 for f in findings if f.severity == "info"),
        "by_type": summary_by_type,
    }
    return findings, summary

def to_relative(context_dir: Path, finding: Finding) -> Finding:
    try:
        rel = str(Path(finding.file).resolve().relative_to(context_dir.resolve().parent))
    except ValueError:
        rel = finding.file
    return Finding(finding.type, rel, finding.rule, finding.severity, finding.message)

def main() -> int:
    p = argparse.ArgumentParser(description="Validate .context/ artifacts against aidex conventions")
    p.add_argument("path", nargs="?", help="Path to .context/ (default: auto-detect from cwd)")
    p.add_argument("--type", choices=TYPES, help="Validate only this artifact type")
    p.add_argument("--json", action="store_true", help="Emit JSON to stdout")
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

    findings, summary = validate(context_dir, args.type)
    findings = [to_relative(context_dir, f) for f in findings]

    if args.json:
        out = {
            "context_dir": str(context_dir.resolve()),
            "scanned_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "summary": summary,
            "violations": [asdict(f) for f in findings if f.severity == "violation"],
            "warnings":   [asdict(f) for f in findings if f.severity == "warning"],
            "info":       [asdict(f) for f in findings if f.severity == "info"],
        }
        json.dump(out, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print(f"\nConventions validation — {context_dir}")
        print(f"  scanned: {summary['files_scanned']} files · "
              f"violations: {summary['violations']} · warnings: {summary['warnings']} · "
              f"info: {summary['info']}\n")
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

    return 1 if summary["violations"] > 0 else 0

if __name__ == "__main__":
    sys.exit(main())
