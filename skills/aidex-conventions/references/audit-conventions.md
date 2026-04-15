# Audit Conventions

Standards for cataloging the state of a project — bugs, gaps, opportunities, risks — and tracking their lifecycle from discovery to resolution.

## Purpose

An **audit** describes what **is** (the current state). A **plan** describes what **will be** (the intended work). These two are distinct and must not be mixed in the same document tree.

When audits and plans blur into each other, findings get lost, duplicated across audit runs, or silently outdated. The `.context/audits/` convention separates them cleanly.

## When to use what

| You have... | Create a... | Location |
|---|---|---|
| A project-wide review listing issues, gaps, or risks | Audit | `.context/audits/YYYYMMDD-<slug>/` |
| A specific bug, opportunity, or issue discovered during an audit | Finding (row in INVENTORY) | `.context/audits/INVENTORY.md` |
| An actionable unit of work to fix or ship something | Plan | `.context/plans/YYYYMMDD-<slug>/` |
| An architectural or product decision | Decision | `.context/decisions/YYYYMMDD-<slug>.md` |
| A stakeholder ask | Request | `.context/requests/YYYYMMDD-<slug>.md` |
| Evergreen project knowledge (architecture, conventions) | Reference | `.context/references/<topic>/` |

An audit produces findings → a finding escalated to work becomes a backlog entry or a plan. The audit entry stays as the historical record.

## Core Principles

### 1. Finding ≠ Issue ≠ Task

Three distinct objects with links, not copies:

- **Finding** — an observation in an audit (lives in `INVENTORY.md`, referenced from `findings.md` views)
- **Backlog entry** — the finding queued for later work (lives in `.context/backlog/`)
- **Task/plan** — active work executing on one or more findings (lives in `.context/plans/`)

A single finding may escalate to multiple tasks, or be dropped. Its state in INVENTORY reflects that.

**Status values (plain text, no emojis):** `open`, `triaged`, `escalated`, `in-progress`, `closed`, `dropped`.

### 2. INVENTORY as single source of truth

`INVENTORY.md` is the canonical deduplicated list of every finding across every audit run. Per-audit `findings.md` files are filtered **views** of INVENTORY, not independent copies.

- New audit run → add rows to INVENTORY, reference IDs from the audit's `findings.md`
- Re-test confirms finding persists → update status in INVENTORY, don't duplicate
- Finding closed → keep the row with status `closed`, never delete

### 3. Living methodology with CHANGELOG

`METHODOLOGY.md` is not frozen. As you learn what checks matter (or don't), update it and log the change in `CHANGELOG.md` following [Keep a Changelog](https://keepachangelog.com/).

This preserves the *why* behind every check. Without it, methodology rots into a checklist nobody follows.

### 4. Every finding is registered

Findings are never deleted, only transitioned:

- `open` — observed, not yet acted on
- `triaged` — assessed, priority assigned
- `escalated` — moved to backlog (link to entry)
- `in-progress` — active plan executing
- `closed` — verified fixed (link to commit or re-test audit)
- `dropped` — won't fix, with reason

This creates an audit trail of decisions.

### 5. Escalation flow

```
audit run → finding in INVENTORY → backlog entry → plan → commit → re-test audit → finding closed
```

Each step links forward and back. The INVENTORY row accumulates these links over the finding's life.

### 6. Shared concerns flagged

When a finding spans multiple modules, tag it `[SHARED]` in INVENTORY. Cross-module concerns tend to be structural and deserve visibility at the inventory level, not buried in one module's findings.

## Canonical Structure

```
.context/audits/
├── INVENTORY.md              # Master source of truth
├── METHODOLOGY.md            # Shared principles + index of playbooks
├── CHANGELOG.md              # Keep-a-Changelog for methodology evolution
├── methodology/              # Playbook per audit type
│   ├── ux-audit.md
│   ├── security-audit.md
│   └── ...
├── YYYYMMDD-<slug>/          # One folder per audit run (immutable)
│   ├── index.md              # Context, scope, dates, auditors
│   ├── findings.md           # Filtered view of INVENTORY for this run
│   └── (status.md, modules/ if needed)
└── _archive/                 # Implementation plans already executed (optional)
```

Why uppercase filenames (`INVENTORY.md`, `METHODOLOGY.md`, `CHANGELOG.md`)? UNIX convention — canonical, long-lived, authoritative files get uppercase (like `LICENSE`, `README`, `CONTRIBUTING`). They signal "this is the source of truth" at a glance.

## Audit Types

AIDEX ships with six playbook templates. Each sits in `methodology/<type>.md` of the audit directory and is generated on first use via `/audit new <type> <slug>`.

| Type | When to run | Playbook shape |
|---|---|---|
| `ux-audit` | Before major release, UX drift suspected | Modules × checks matrix |
| `ia-opportunities` | New AI capability scoped, phase end | Phases × `[AI-EXISTS / MISSING / FLOW]` |
| `retest` | After a batch of P0/P1 fixes lands | Original findings × validating commits |
| `security-audit` | Fixed cadence or post sensitive feature | OWASP-style checklist |
| `perf-audit` | Pre-release, pre-scaling | Lighthouse categories + backend metrics |
| `a11y-audit` | Fixed cadence or compliance requirement | WCAG criteria × page |

Custom types are allowed — pass `custom` as the type and provide your own playbook.

## ID Conventions

Two patterns, both valid. Pick one per project and stay consistent.

### Structured IDs

Format: `<CATEGORY>-<MODULE>-<N>`

Examples:
- `BUG-01-3` — bug in module 01, third one
- `IDEA-FF-2` — idea in "features" module, second one

**Use when:** modules/phases are stable and finite; visual grouping helps navigation; reviewers scan by module.

### Global IDs

Format: `<PREFIX>-<N>` (flat numbering)

Examples:
- `F-042` — finding number 42
- `BUG-127` — bug number 127

**Use when:** modules are fluid; cross-cutting findings dominate; simpler to enforce uniqueness.

## Document Templates

### INVENTORY row

```markdown
| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To |
|---|---|---|---|---|---|---|---|---|---|
| BUG-01-3 | bug | auth | Session token stored in URL | open | P1 | 20260410 | 20260415 | 20260410, 20260415 | — |
```

### Audit run `index.md`

```markdown
# [Audit type] — [slug]

**Date:** YYYY-MM-DD
**Type:** ux-audit | security-audit | ...
**Scope:** [what was covered]
**Auditor:** [who ran it]
**Method:** [brief — see methodology/<type>.md for full playbook]

---

## Summary

[One paragraph — key themes, counts, urgency]

## Findings

See [findings.md](findings.md) for filtered view, or [../INVENTORY.md](../INVENTORY.md) for canonical.

## Next steps

- [Who will triage]
- [When re-test happens]
```

### Audit run `findings.md`

Filtered view of INVENTORY, grouped by severity or module. Not a copy — a link table.

```markdown
# Findings — [slug] ([YYYY-MM-DD])

Filtered view of [../INVENTORY.md](../INVENTORY.md). Do not add findings directly here — add them to INVENTORY.

## P0 (Critical)

- **BUG-01-3** — Session token stored in URL ([INVENTORY](../INVENTORY.md#BUG-01-3))
- **BUG-05-1** — SQL injection in search ([INVENTORY](../INVENTORY.md#BUG-05-1))

## P1 (High)

...
```

## Lifecycle Summary

```
open --triage--> triaged --accept--> escalated
                                         |
                                     start work
                                         v
                  closed <--verify-- in-progress
```

Or from any state → `dropped` with a documented reason.

## Integration with Other Doc Types

- **From plans:** When a plan is completed, its closing commit(s) update the related findings' status in INVENTORY.
- **From decisions:** When an audit forces an architectural decision, cite the decision from the finding row (`Escalated To` can point to a decision file).
- **From backlog:** Backlog entries with `Origen: audit/<run>/<id>` create the back-reference. The `audit` skill enforces this when escalating.

## Tooling

The `audit` skill provides scaffolding and validation:

- `/audit new <type> <slug>` — scaffold a new audit run
- `/audit validate` — check coherence INVENTORY ↔ findings ↔ backlog
- `/audit escalate <finding-id>` — move finding to backlog
- `/audit migrate` — move legacy audit-like folders out of `plans/`

The `backlog-register` skill handles the other side of escalation:

- `/backlog-register --origin audit --finding <id>` — create backlog entry with correct origin

## Anti-patterns

- **Audits inside `plans/`** — mixes "what is" with "what will be". Migrate via `/audit migrate`.
- **Deleting findings** — breaks the audit trail. Use `dropped` with a reason.
- **Per-run findings files without INVENTORY link** — creates silent duplication. Always link to canonical IDs.
- **Methodology without CHANGELOG** — loses the *why*. Every methodology change must be logged.
- **Mixing ID conventions within a project** — inconsistent references break tooling. Pick one.

## Related

- **Skill `audit`** — operations (scaffold, validate, escalate, migrate)
- **Skill `backlog-register`** — registers items with audit origin
- **Skill `aidex`** — audits the audits directory itself for coherence
- **[plan-conventions.md](plan-conventions.md)** — how plans differ from audits
- **[request-decision-conventions.md](request-decision-conventions.md)** — how decisions cite findings
