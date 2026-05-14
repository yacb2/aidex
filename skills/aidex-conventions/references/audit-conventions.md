# Audit Conventions

Standards for cataloging the state of a project — bugs, gaps, opportunities, risks — and tracking their lifecycle from discovery to resolution.

> **Read [`00-global.md`](00-global.md) first.** This document only declares what is genuinely audit-specific. Filename dates, archive policy, cross-reference format, language, and minimum front-matter all live in `00-global.md`.

---

## Purpose

An **audit** describes what **is** (the current state). A **plan** describes what **will be** (the intended work). These two are distinct and must not be mixed in the same document tree.

When audits and plans blur into each other, findings get lost, duplicated across audit runs, or silently outdated. The `.context/audits/` convention separates them cleanly.

---

## When to use what

| You have… | Create a… | Location |
|---|---|---|
| A project-wide review listing issues, gaps, or risks for one methodology | Audit run | `.context/audits/<methodology>/YYYY-MM-DD-<slug>/` |
| A specific bug, opportunity, or issue discovered during a run | Finding (row) | `.context/audits/<methodology>/00-inventory.md` |
| An actionable unit of work to fix or ship something | Plan | `.context/plans/YYYY-MM-DD-<slug>/` |
| An architectural or product decision | Decision | `.context/decisions/YYYY-MM-DD-<slug>.md` |
| A stakeholder ask | Request | `.context/requests/YYYY-MM-DD-<slug>.md` |
| Evergreen project knowledge (architecture, conventions) | Reference | `.context/references/<topic>/` |

A finding escalated to work becomes a backlog entry or a plan via `escalated_to: backlog/<…>` or `escalated_to: plan/<…>`. The finding row stays as the historical record.

---

## Canonical structure (D-02)

ADR: [`2026-05-14-audit-grouped-by-methodology.md`](../../../.context/decisions/2026-05-14-audit-grouped-by-methodology.md)

Audits are grouped **by methodology**. There is no global `INVENTORY.md`, `METHODOLOGY.md`, or `CHANGELOG.md` at `.context/audits/`.

```
.context/audits/
├── ux/
│   ├── 00-methodology.md            # Playbook for UX audits in this project
│   ├── 00-inventory.md              # Canonical findings list — ALL UX findings
│   ├── 00-changelog.md              # Keep-a-Changelog for the methodology
│   └── 2026-05-14-pre-release/      # One audit run (immutable)
│       ├── index.md
│       └── findings.md              # Filtered view of 00-inventory.md
├── security/
│   ├── 00-methodology.md
│   ├── 00-inventory.md
│   ├── 00-changelog.md
│   └── 2026-05-01-owasp-baseline/
└── perf/
    └── …
```

**Why per-methodology?** A P0 in security ("auth bypass") and a P0 in UX ("primary CTA hidden on mobile") share a label but not a meaning. Comparing them in one inventory is misleading. Each methodology has its own severity rubric, cadence, and owner.

**Why lowercase `00-*.md` filenames?** Aligns with `00-index.md` everywhere else; the leading `00-` keeps them sorted to the top of the methodology folder.

**Audit run folder name:** `YYYY-MM-DD-<slug>/` per D-01.

---

## Core principles

### 1. Finding ≠ Issue ≠ Task

Three distinct objects with links, not copies:

- **Finding** — observation in an audit. Lives in `audits/<methodology>/00-inventory.md`, surfaced from a run's `findings.md`.
- **Backlog entry** — the finding queued for later work. Lives in `.context/backlog/`.
- **Task/plan** — active work executing on one or more findings. Lives in `.context/plans/`.

A single finding may escalate to multiple tasks, or be dropped. Its row in the per-methodology inventory reflects that.

### 2. Per-methodology inventory as single source of truth

`00-inventory.md` inside a methodology folder is the canonical deduplicated list of every finding across every run of that methodology. Per-run `findings.md` files are **filtered views**, not independent copies.

- New audit run → add rows to `00-inventory.md`, link IDs from the run's `findings.md`.
- Re-test confirms a finding persists → update the row, don't duplicate.
- Finding closed → row stays with `status: done`, never delete.

### 3. Living methodology with `00-changelog.md`

`00-methodology.md` is not frozen. As you learn which checks matter (or don't), update it and log the change in `00-changelog.md` following [Keep a Changelog](https://keepachangelog.com/). This preserves the *why* behind every check.

### 4. Every finding is registered

Findings are never deleted, only transitioned. See §"Status map" below.

### 5. Escalation flow

```
audit run → finding row → backlog entry → plan → commit → re-test audit → finding done
```

Each step links forward and back via `escalated_to` and `origin_ref` (D-03 format).

### 6. Shared concerns flagged

When a finding spans multiple modules within the methodology, tag it `[SHARED]` in the inventory `Module` column.

---

## ID conventions

IDs are **scoped to a methodology** so that `BUG-01-3` in `ux/` and `BUG-01-3` in `security/` are different findings without ambiguity. The methodology folder is the namespace.

Two patterns, both valid. Pick one per methodology and stay consistent inside that methodology.

### Structured IDs

Format: `<CATEGORY>-<MODULE>-<N>`

Examples:
- `BUG-01-3` — bug in module 01, third one
- `IDEA-FF-2` — idea in "features" module, second one

**Use when:** modules/phases are stable and finite; visual grouping helps; reviewers scan by module.

### Global IDs

Format: `<PREFIX>-<N>` (flat numbering inside the methodology)

Examples:
- `F-042` — finding number 42 in this methodology
- `BUG-127` — bug number 127 in this methodology

**Use when:** modules are fluid; cross-cutting findings dominate.

---

## Status map

Audit findings use the base lifecycle (`open` · `doing` · `done` · `dropped`) from [`00-global.md` §6](00-global.md#6-status-vocabulary). The legacy audit vocabulary maps as follows:

| Legacy | Maps to | Notes |
|---|---|---|
| `open` | `status: open` | — |
| `triaged` | `status: open` | Add an internal note in the row's `Notes` column. Triage is a sub-state, not a top-level status. |
| `escalated` | `status: done` + `escalated_to: backlog/<…>` (or `plan/<…>`) | The finding's work is now tracked elsewhere. |
| `in-progress` | `status: doing` | — |
| `closed` | `status: done` | Link the verifying commit or re-test run in `Notes`. |
| `dropped` | `status: dropped` | Reason in `Notes`. |

---

## Document templates

### `00-inventory.md` row

Audit findings are **exempt** from per-file front-matter (D-07). They live in this table.

```markdown
| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| BUG-01-3 | bug | auth | Session token stored in URL | open | P1 | 2026-04-10 | 2026-04-15 | 2026-04-10, 2026-04-15 | — | — |
| BUG-02-1 | bug | search | SQL injection in q param | done | P0 | 2026-04-10 | 2026-04-20 | 2026-04-10, 2026-04-20 | backlog/2026-04-10-fix-sqli-search | Closed: commit abc123 |
```

Dates are `YYYY-MM-DD` (D-01). The `Escalated To` column uses the cross-reference format from [`00-global.md` §3](00-global.md#3-cross-references-d-03).

### Audit run `index.md`

```markdown
---
title: "UX audit — pre-release 2026-05-14"
status: done
created: 2026-05-14
updated: 2026-05-14
methodology: ux
---

# UX audit — pre-release 2026-05-14

**Scope:** [what was covered]
**Auditor:** [who ran it]
**Method:** see [../00-methodology.md](../00-methodology.md)

---

## Summary

[One paragraph — key themes, counts, urgency]

## Findings

See [findings.md](findings.md) for the filtered view, or [../00-inventory.md](../00-inventory.md) for canonical.

## Next steps

- [Who will triage]
- [When re-test happens]
```

### Audit run `findings.md`

Filtered view of `00-inventory.md`, grouped by severity or module. Not a copy — a link table.

```markdown
# Findings — pre-release 2026-05-14

Filtered view of [../00-inventory.md](../00-inventory.md). Do not add findings directly here.

## P0

- **BUG-02-1** — SQL injection in search ([inventory](../00-inventory.md#BUG-02-1))

## P1

- **BUG-01-3** — Session token in URL ([inventory](../00-inventory.md#BUG-01-3))
```

---

## Audit types (methodologies)

AIDEX ships playbook templates for the following methodologies. Each becomes a folder under `.context/audits/<methodology>/` on first use via `/audit new <methodology> <slug>`.

| Methodology | When to run | Playbook shape |
|---|---|---|
| `ux` | Before major release, UX drift suspected | Modules × checks matrix |
| `ai-opportunities` | New AI capability scoped, phase end | Phases × `[AI-EXISTS / MISSING / FLOW]` |
| `retest` | After a batch of P0/P1 fixes lands | Original findings × validating commits |
| `security` | Fixed cadence or post sensitive feature | OWASP-style checklist |
| `perf` | Pre-release, pre-scaling | Lighthouse categories + backend metrics |
| `a11y` | Fixed cadence or compliance requirement | WCAG criteria × page |

Custom methodologies are allowed — `/audit new custom <slug>` with your own playbook.

---

## Integration with other doc types

- **From plans:** when a plan completes, its closing commit(s) update the related findings' status in the methodology inventory.
- **From decisions:** when an audit forces an architectural decision, cite the decision from the finding's `Escalated To` column.
- **From backlog:** backlog entries with `origin: audit` and `origin_ref: audit/<methodology>/<run>/<id>` create the back-reference. The `audit` skill enforces this on escalation.

---

## Tooling

- `/audit new <methodology> <slug>` — scaffold a new audit run inside the methodology folder.
- `/audit validate` — check coherence inventory ↔ run findings ↔ backlog.
- `/audit escalate <finding-id>` — move finding to backlog.
- `/audit migrate` — move legacy audit-like folders out of `plans/` and reshape into the per-methodology layout.

`/backlog-register --origin audit --finding <id>` creates the backlog entry with the correct `origin_ref`.

---

## Anti-patterns

- **Audits inside `plans/`** — mixes "what is" with "what will be". Use `/audit migrate`.
- **Global `INVENTORY.md`** — pre-D-02 layout; reshape into per-methodology inventories.
- **Deleting findings** — breaks the audit trail. Use `status: dropped` with reason.
- **Per-run findings files without a link to the methodology inventory** — silent duplication.
- **Methodology without `00-changelog.md`** — loses the *why*.
- **Mixing ID conventions inside one methodology** — pick one (structured or global) per methodology.

---

## Related

- [`00-global.md`](00-global.md) — shared rules.
- [`plan-conventions.md`](plan-conventions.md) — how plans differ.
- [`request-decision-conventions.md`](request-decision-conventions.md) — how decisions cite findings.
- Skill `audit` — operations.
- Skill `backlog-register` — registers items with audit origin.
