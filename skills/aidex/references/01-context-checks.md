# Context Audit Checks (.context/)

Detailed checks for `.context/references/`, `.context/docs/`, `.context/plans/`, `.context/backlog/`, `.context/issues/`, `.context/roadmap/`, `.context/requests/`, `.context/decisions/`, and `.context/audits/`.

## Inventory Phase

For each module, collect:

| Module | Type | Files | Has 00-index | Lines (largest) |
|--------|------|-------|-------------|-----------------|
| `auth` | reference | 6 | ✓ | 280 |

## Checks A-F (References & Docs)

### A. Root-Level Clutter
Any `.md` file directly in `.context/references/` or `.context/docs/` (not inside a subdirectory) is clutter. Exception: `README.md`.

### B. Index Coverage
Every module must have `00-index.md` that links to **every other file** in the module. Flag any file not linked from the index.

### C. Numbering Gaps
Files follow `NN-topic.md` with no gaps. Sequence `00 01 02 04` has a gap at `03`.

### D. Metadata Headers
Every file (except `00-index.md`) should include:
```markdown
**Version:** X.Y
**Last Updated:** YYYY-MM-DD
**Context:** One-line description
```

### E. Cross-Reference Integrity
All internal links between modules must resolve to existing files.

### F. Naming Convention
All files must match `NN-topic-name.md` (two digits, kebab-case).

## Checks PA-PD (Plans)

### PA. Naming
Files match `YYYYMMDD-<name>.md` or directory with `00-index.md`.

### PB. Index
Multi-file plans have `00-index.md` linking all phase files.

### PC. Checkboxes
Plans contain `- [ ]` or `- [x]` task markers.

### PD. Staleness
All checkboxes checked + status completed + last-updated significantly in the past → candidate for archive.

## Checks IA-ID (Issues)

### IA. Index
Has `00-index.md` as registry of all issues.

### IB. Naming
Files match `ISSUE-NNN-description.md` pattern.

### IC. Status Field
Each issue has a Status field (open / investigating / fixed).

### ID. Stale Open
Issues with status "open" older than 30 days → flag for review.

## Checks RA-RC (Roadmap)

### RA. Entry Point
Has `README.md` with overview and current phase indicator.

### RB. Phase Files
Follow `NN-phase-name.md` numbering pattern.

### RC. Status Tracking
Each phase indicates status (planned / in-progress / done).

## Checks QA-QB (Requests)

### QA. Naming
Files match `YYYYMMDD-description.md` pattern.

### QB. Archive
Completed requests moved to `_archive/` subdirectory.

## Checks DA-DD (Decisions)

### DA. Naming
Files match `YYYYMMDD-description.md` pattern.

### DB. Status Field
Each decision has a Status field (Active / Superseded / Reversed).

### DC. Superseded Link
Decisions with status "Superseded" must include a `Superseded by:` link to the newer decision.

### DD. Archive
Reversed or superseded decisions moved to `_archive/` subdirectory (optional — may keep in main dir for visibility).

## Checks UA-UH (Audits)

### UA. Canonical Files
`INVENTORY.md`, `METHODOLOGY.md`, `CHANGELOG.md` all present at the root of `.context/audits/`.

### UB. Run Folder Naming
Subfolders follow `YYYYMMDD-<slug>/` pattern. Exceptions allowed only for `methodology/` and `_archive/`.

### UC. Run Folder Content
Each `YYYYMMDD-<slug>/` contains both `index.md` and `findings.md`.

### UD. INVENTORY Integrity
- No duplicate IDs in INVENTORY
- Every row has a non-empty Status
- Rows with status `escalated`, `in-progress`, or `closed` have non-empty `Escalated To` column

### UE. Orphan Finding References
IDs mentioned in per-run `findings.md` must exist in INVENTORY (detects findings added to a view but not to the canonical source).

### UF. Orphan Backlog References
Backlog entries with `origin: audit` must point at finding IDs that exist in INVENTORY (check `origin_ref: audit/<run>/<id>`).

### UG. Playbook For Declared Type
If a run's `index.md` declares `Type: <type>` with a known type, `methodology/<type>.md` must exist.

### UH. CHANGELOG Freshness
`CHANGELOG.md` present and non-empty. Warn if last entry > 6 months old AND INVENTORY has grown >20% since — likely methodology has evolved without being logged.

### Fast implementation hint
Prefer shelling out to `~/.aidex/skills/audit/scripts/validate-audit.sh --json <audits-dir>` when available; it produces the same violations in JSON. Fall back to manual checks only when the script is missing.

## Report Format

```
🔴 CRITICAL  [A] Loose file `.context/docs/NOTES.md` — move to module or delete
⚠️  WARNING   [B] `backend` index missing link to `08-tasks.md`
⚠️  WARNING   [C] `frontend` has gap: 01→02→04 (missing 03)
⚠️  WARNING   [D] `deployment/03-backend.md` missing metadata header
ℹ️  INFO      `old-module` not updated in months — may be stale
```
