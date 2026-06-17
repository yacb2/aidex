# Plan Conventions

Standards for implementation plans with checkbox tracking for multi-session work.

> **Read [`00-global.md`](00-global.md) first.** Filename dates, archive, language, cross-references, and minimum front-matter live there. This file only declares plan-specific structure.

---

## Structure pattern

### Multi-file plan (default for ≥3 phases)

```
.context/plans/YYYY-MM-DD-<feature>/
├── 00-index.md           # Master index
├── 01-<phase>.md         # Phase 1
├── 02-<phase>.md         # Phase 2
└── …
```

### Single-file plan (1–2 phases)

```
.context/plans/YYYY-MM-DD-<feature>.md
```

Folder/filename date: `YYYY-MM-DD` (D-01). Slug: kebab-case, describes the feature.

### Archive

Per D-05, completed plans move to `.context/plans/_archive/` on `status: done`. Inbound references resolve via the two-folder lookup in [`00-global.md` §3](00-global.md#3-cross-references-d-03), so no inbound edits are required.

---

## `00-index.md` template

```markdown
---
title: "Feature name"
status: open | doing | done | dropped
current-phase: 0
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# [Feature Name] Implementation Plan

**Goal:** [One sentence — what this builds]

**Architecture:**
- [Key decision 1]
- [Key decision 2]

**Tech Stack:**
- Backend: [technologies]
- Frontend: [technologies]

---

## Phases Overview

| Phase | File | Description | Tasks |
|---|---|---|---|
| 1 | [01-phase-name.md](01-phase-name.md) | Brief description | N |
| 2 | [02-phase-name.md](02-phase-name.md) | Brief description | N |

---

## Session Checkpoint

**Status:** [open/doing/done/dropped — matches front-matter]

**Phases:**
- [ ] Phase 1: [name] (N tasks)
- [ ] Phase 2: [name] (N tasks)

**Total:** X tasks across N phases.
**Next:** Phase 1, Task 1.1.
```

The `status` field uses the base lifecycle from [`00-global.md` §6](00-global.md#6-status-vocabulary): `open` (not started), `doing` (in progress), `done` (complete), `dropped` (abandoned). `blocked_by`, `escalated_to`, `superseded_by` are layered modifiers per §6.

---

## Phase file template

```markdown
# Phase N: [Phase Name]

[← Back to Index](00-index.md)

---

## Task N.1: [Task Name]

**Files:**
- Create: `exact/path/to/new-file.py`
- Modify: `exact/path/to/existing.py`

**Step 1: [Action description]**

\`\`\`python
# Full code snippet — not just a reference
\`\`\`

**Step 2: [Next action]**

[Continue with implementation steps…]

**Verify:**

\`\`\`bash
command-to-verify
\`\`\`

Expected: `OK`

> If a phase's Verify step is a machine gate the work should *iterate against*
> (e.g. "make all tests pass", "typecheck clean", "remove every call to X"),
> consider spawning a loop-spec via `aidex-loop` and handing off execution rather
> than hand-running the loop. This stays a pointer — do **not** add a per-phase
> loop-suitability field to the phase template; it fails the litmus for most phases.

---

## Task N.2: …

---

## Phase N Checkpoint

**Completed:**
- [ ] Task N.1: [brief]
- [ ] Task N.2: [brief]

**Next:** [Phase N+1](0N+1-phase-name.md)
```

---

## Task format rules

### Step granularity

Each step is **2–5 minutes** of work.

| Good (atomic) | Bad (too large) |
|---|---|
| Create directory structure | Implement authentication |
| Create serializer class | Add user management |
| Update `__init__.py` exports | Set up the backend |
| Verify import works | Fix all bugs |

### Code inclusion

Always include **full code** in steps, not references. Show the implementation, not "follow the pattern in `other_file.py`".

---

## Phase organization

Group tasks by layer (models → serializers → views → URLs → tests), feature area (one component end-to-end), or dependency order (what must exist before what). Example phase names: `01-backend-models.md`, `02-backend-api.md`, `03-frontend-components.md`, `04-testing-verification.md`.

---

## Session checkpoint

At end of each work session, update `00-index.md`'s checkpoint section:

```markdown
## Session Checkpoint

**Status:** doing
**Phase:** 2 (in progress)
**Updated:** 2026-05-14

**Completed:**
- [x] Phase 1
- [ ] Phase 2 (Task 2.3 in progress)

**Blockers:** None

**Next:**
- Finish Task 2.3
- Begin Task 2.4
```

Also bump the front-matter `updated:` date and `current-phase:` integer.

---

## Validation checklist

### Index file (`00-index.md`)
- [ ] Front-matter has `title`, `status`, `created`, `updated`, `current-phase`
- [ ] Title, Goal, Architecture, Tech Stack sections
- [ ] Phases Overview table with links
- [ ] Session Checkpoint section

### Phase files
- [ ] Phase title with number
- [ ] Link back to index
- [ ] Tasks numbered `N.1`, `N.2`, …
- [ ] Each task has Files section
- [ ] Each step has full code (not references)
- [ ] Phase Checkpoint at end

### Task checks
- [ ] Steps are atomic (2–5 minutes)
- [ ] Code is complete (not placeholders)
- [ ] Verification step included where appropriate

---

## Related

- [`00-global.md`](00-global.md) — shared rules.
- [`audit-conventions.md`](audit-conventions.md) — when work begins as an audit finding.
- [`request-decision-conventions.md`](request-decision-conventions.md) — when a plan supersedes a request.
