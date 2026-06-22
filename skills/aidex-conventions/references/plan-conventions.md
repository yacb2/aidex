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
# Phase N: [Phase Name]   <!-- optional: (depends_on: [1, 2]) — omit or [] = independently grabbable -->

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

**Lead with vertical slices.** A vertical slice is one thin, end-to-end piece of behavior cut *across* all layers (one model field → its API field → its UI control → its test), shippable on its own. Prefer slicing the work this way: each slice is a phase that delivers working behavior, and **two slices that touch different features have no edge between them, so an executor can run them in parallel** (see `depends_on` below and the `fan-out-with-gate` execution form). Example phase names: `01-slice-create-todo.md`, `02-slice-mark-done.md`, `03-slice-filter-list.md`.

**Layer-ordering is the secondary pattern.** Grouping by layer (models → serializers → views → URLs → tests) is sometimes the honest shape — e.g. a schema migration that genuinely must land before anything reads it. But layer phases are inherently sequential (each layer waits on the one below), so they forfeit any parallelism and tend to defer working behavior to the last phase. **Pushback note:** if your first phase is a layer with no user-visible behavior (a "build all the models" phase), stop and ask whether a vertical slice would deliver something testable sooner — only keep the layer split when a real ordering constraint forces it. Feature-area and dependency-order groupings are fine variants of the slice pattern.

### Optional `depends_on` on a phase

A phase may declare which earlier phases must complete before it can start:

```markdown
# Phase N: [Phase Name]  (depends_on: [1, 2])
```

`depends_on: []` (or omitted) means the phase is **independently grabbable** — no prerequisites, eligible to run concurrently with any other edge-free phase. List the phase numbers/slugs a phase truly needs (it reads their output) and nothing more; spurious edges kill parallelism. The executor (`aidex-plan-exec`) reads this metadata to choose between sequential (`pipeline-with-gate`) and parallel (`fan-out-with-gate`) execution. Keep edges honest: an edge that isn't a real data dependency is a serialization you didn't need.

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
