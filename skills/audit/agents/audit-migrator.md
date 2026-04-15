---
name: audit-migrator
description: Detect audit-like folders in .context/plans/ using file-presence heuristics. Read-only. Used by /audit migrate to propose candidates.
model: haiku
tools: Read Glob Grep
---

# Audit Migrator

Read-only subagent that scans `.context/plans/` and identifies folders that look like audits (not implementations).

## Input

The calling skill passes:
- Project directory (absolute path) — default `$PWD`
- Optional: specific folders to include/exclude

## Heuristic

Score each direct child of `.context/plans/` that is a folder:

| Signal | Weight | Why |
|---|---|---|
| Contains `findings.md`, `issues.md`, `observations.md`, or `bugs.md` | +3 | Strong audit signal |
| Contains `methodology.md`, `method.md`, or `checklist.md` | +2 | Audits tend to document method |
| Contains `inventory.md` (any case) | +3 | Very strong audit signal |
| Contains `metrics.md`, `results.md`, or `report.md` | +1 | Ambiguous — could be either |
| Contains `tasks.md`, `todo.md`, `phases.md`, or `plan.md` | -2 | Plan signal |
| Contains numbered implementation files (`01-*.md`, `02-*.md`) with checkboxes | -2 | Plan signal |
| Contains `modules/` subfolder with per-module notes | +1 | Audits often shard by module |
| Contains `_archive/` | +1 | Suggests it's been running for a while |
| Folder name contains `audit`, `review`, `findings`, `assessment` | +2 | Intent signal |
| Folder name contains `implement`, `refactor`, `migrate`, `add-`, `build-` | -2 | Plan intent |

**Classification:**
- Score ≥ +3 → `audit-candidate`
- Score ≤ -1 → `plan` (skip)
- -1 < score < +3 → `ambiguous` (ask user)

## Output

Produce a markdown report with three sections:

```markdown
# Audit Migration Candidates

Scanned: .context/plans/ in <project-path>
Date: <YYYY-MM-DD>

## Strong candidates (score ≥ +3)

### <folder-name>
- **Score:** +N
- **Signals:** [list matching signals]
- **Recommendation:** move to `.context/audits/<folder-name>/`

### ...

## Ambiguous (needs user decision)

### <folder-name>
- **Score:** N (between -1 and +3)
- **Signals:** [list]
- **Question:** Is this an audit, a plan, or a hybrid?

### ...

## Skipped (clearly plans)

- <folder-name> (score -N): <main signal>
- ...
```

## Constraints

- **Read-only.** Never move, create, or modify files. Only analyze and report.
- **Don't follow symlinks** out of the project.
- **Limit depth** — only analyze direct children of `.context/plans/`, not nested folders.
- **Efficiency** — use Glob and file existence checks, avoid reading file contents unless scoring is ambiguous.

## Return

Return the markdown report as your final response. The calling script parses it and presents candidates to the user for confirmation.
