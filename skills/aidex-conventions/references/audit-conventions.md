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

### Standalone one-shot runs (ADR `decision/2026-07-02-audit-rebuild-canon-decisions`)

A one-shot analysis with no recurring methodology (a usage retro, a suite-wide
review, a spike-shaped investigation of project state) lives as a **dated run
folder directly under `audits/`**:

```
.context/audits/
├── 2026-07-02-suite-analysis/     # standalone one-shot run
│   └── 00-report.md (or index.md) # carries its own front-matter
├── ux/                            # recurring methodology (boards + runs)
│   └── …
```

- **No boards required** — `00-inventory.md`/`00-methodology.md`/`00-changelog.md`
  exist only for recurring methodologies (they hold the rolling, cross-run state a
  one-shot doesn't have).
- The run's main file carries canon front-matter; findings that outlive the
  analysis escalate to `backlog/` the same way (`origin_ref:
  audit/<run-folder>/<finding-id>` — no methodology segment for standalone runs).
- **The distinction is positional**: directly under `audits/` = standalone;
  under `audits/<methodology>/` = part of that methodology. If a one-shot starts
  repeating, promote it: create the methodology folder, move the runs in, and
  seed the boards from their findings.
- Auditors/validators treat both as canon — a standalone run is never a layout
  violation.

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

> **Run-level roll-up vs finding-level inventory.** `00-inventory.md` is the *finding-level* board (one row per finding). Alongside it, `aidex-audit` auto-generates `00-index.md` — the *run-level* roll-up (which runs exist, active/archived, and each run's open/total finding counts derived from the inventory). They are complementary; do **not** hand-edit `00-index.md` (regenerate via `reindex-audits.sh`, which runs on `new`/`close`).

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
| BUG-01-3 | bug | auth | Session token stored in URL | open | P1 | 2026-04-10 | 2026-04-15 | 2026-04-10-pre-release | — | — |
| BUG-02-1 | bug | search | SQL injection in q param | done | P0 | 2026-04-10 | 2026-04-20 | 2026-04-10-pre-release, 2026-04-20-retest | backlog/2026-04-10-fix-sqli-search | Closed: abc123 — sqli patched |
```

Dates are `YYYY-MM-DD` (D-01). The `Escalated To` column uses the cross-reference format from [`00-global.md` §3](00-global.md#3-cross-references-d-03). `Audit Runs` is comma-separated run-folder slugs (`YYYY-MM-DD-<slug>`).

**Notes discipline.** `Notes` is a bounded **state note**, not a journal: one line carrying the verification marker (closing commit SHA, re-test run ref, or drop reason) plus an optional **proof pointer**. The resolution narrative — root cause, test counts, review verdicts, transcripts — lives in the run's `findings.md` (its role as the per-run journal) or `.context/proofs/<id>/`, never inside the table cell.

**Closed-row compaction.** On close, compress `Notes` to `Closed: <commit|run> — <one line>` and move any surviving narrative to the run's `findings.md`/proofs. This keeps the single-source-of-truth board at open-set size instead of accumulating fix war-stories forever.

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

A per-run **scope manifest and journal**, not a second board: the IDs this run recorded, re-observed, or resolved (one line each, linking the inventory row) plus free-form run notes. It carries **no status or severity of its own** — those live only in `00-inventory.md`. This is where the resolution narrative belongs (root cause, evidence, caveats); larger captures go to `.context/proofs/<id>/`.

```markdown
# Findings — pre-release 2026-05-14

Scope manifest for this run. Canonical state lives in
[../00-inventory.md](../00-inventory.md); do not restate status/severity here.

## Findings this run

- BUG-02-1 — SQL injection in search ([inventory](../00-inventory.md#BUG-02-1))
- BUG-01-3 — session token in URL ([inventory](../00-inventory.md#BUG-01-3))

## Run journal

What was walked, root-cause narrative, verification evidence, caveats.
```

---

## Audit types (methodologies)

AIDEX ships playbook templates for the following methodologies. Each becomes a folder under `.context/audits/<methodology>/` on first use via `/aidex-audit new <methodology> <slug>`.

| Methodology | When to run | Playbook shape |
|---|---|---|
| `ux` | Before major release, UX drift suspected | Modules × checks matrix |
| `ai-opportunities` | New AI capability scoped, phase end | Phases × `[AI-EXISTS / MISSING / FLOW]` |
| `retest` | After a batch of P0/P1 fixes lands | Original findings × validating commits |
| `security` | Fixed cadence or post sensitive feature | OWASP-style checklist |
| `perf` | Pre-release, pre-scaling | Lighthouse categories + backend metrics |
| `a11y` | Fixed cadence or compliance requirement | WCAG criteria × page |
| `hitl` | Flows/processes need human sign-off page-by-page | Pages × roles, split agent-automated vs human-judgment, resumable checklist |
| `test-coverage` | Post-incident, after a feature push, or when `coverage-sweep` flags drift | Modules × breadth (generated matrix) + depth (judgment) |
| `docs-coverage` | Surfaces outpaced their docs, `.context/references/` was reorganized, or a gap surfaced by luck | Census axes × breadth (generated matrix) + depth (judgment) |

Custom methodologies are allowed — `/aidex-audit new custom <slug>` with your own playbook.

---

## Integration with other doc types

- **From plans:** when a plan completes, its closing commit(s) update the related findings' status in the methodology inventory.
- **From decisions:** when an audit forces an architectural decision, cite the decision from the finding's `Escalated To` column.
- **From backlog:** backlog entries with `origin: audit` and `origin_ref: audit/<methodology>/<run>/<id>` create the back-reference. The `aidex-audit` skill enforces this on escalation.

---

## Tooling

- `/aidex-audit new <methodology> <slug>` — scaffold a new audit run inside the methodology folder.
- `/aidex-audit validate` — check coherence inventory ↔ run findings ↔ backlog.
- `/aidex-audit escalate <finding-id>` — move finding to backlog.
- `/aidex-audit migrate` — move legacy audit-like folders out of `plans/` and reshape into the per-methodology layout.

`/aidex-backlog --origin audit --finding <id>` creates the backlog entry with the correct `origin_ref`.

---

## Anti-patterns

- **Audits inside `plans/`** — mixes "what is" with "what will be". Use `/aidex-audit migrate`.
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
- Skill `aidex-audit` — operations.
- Skill `aidex-backlog` — registers items with audit origin.
