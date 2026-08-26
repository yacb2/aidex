# Plan Conventions

Standards for implementation plans with checkbox tracking for multi-session work.

> **Read [`00-global.md`](00-global.md) first.** Filename dates, archive, language, cross-references, and minimum front-matter live there. This file only declares plan-specific structure.

---

## Philosophy: plans are specs, not scripts

A plan records **what to build, how to know it's built, and what was discovered
while scoping it** — not the implementation itself. The executor (a frontier
model reading the live repo) derives the *how* at execution time; the plan's job
is to make that derivation unambiguous and verifiable.

Decided by ADR `decision/2026-07-19-plan-spec-first` (adversarial analysis,
26 confirmed findings): pre-written implementation code in plans was measured to
be (a) ignored by the best-executed plans in the corpus, (b) transcribed
verbatim *with latent bugs* where it was followed, (c) unread by the execution
machinery below phase level, and (d) a ~4× lifecycle token multiplier — every
KB of plan is re-read 3–6× (Orient, handoffs, batch agents).

The operative rules:

- **Contract-first code inclusion.** Include literal code **only where the exact
  text IS the specification**: API/type signatures other phases rely on, data
  shapes, migration DDL, a regex or config block, a security invariant, a
  genuinely non-derivable algorithm. Everything else is *spec + pointer*: intent,
  exact file paths, a pattern anchor ("mirror `speed_override` in
  `segment_serializers.py`"), and acceptance criteria. Never write code the
  executor can derive from the repo — it goes stale, it anchors the executor to
  an unverified design, and it converts a frontier model into a transcriber.
- **Investigation evidence is mandatory; its code is not.** The real value of
  detailed planning is what scoping *forces you to discover* — existing
  patterns, landmines, constraints ("the params hash must gain the new keys or
  cached audio silently collides"). Record those discoveries explicitly in each
  task's Spec. Anchor them with **stable references** (symbol names, "after the
  `speed_override` field") — never bare line numbers, which go stale on the
  first intervening commit. `file:line` is acceptable only as a supplement to a
  symbol anchor.
- **The task is the atomic unit.** A task is one nameable outcome, small enough
  that its completion is independently verifiable and a fresh session can resume
  after it. There is no minute-based step granularity: the executor plans its
  own micro-steps. Numbered steps inside a task are optional ordering guidance,
  reserved for `tier: mechanical` phases or genuinely order-sensitive sequences
  (migrations). Task-sizing test:

  | Good (one nameable outcome) | Bad (a project, not a task) |
  |---|---|
  | Create the serializer + its test | Implement authentication |
  | Add the reset-password endpoint | Add user management |
  | Wire the new field through the UI form | Set up the backend |

- **Proportionality (the removal test).** Every line of plan content must pass:
  *"would the executor get this wrong without it?"* Small plans collapse to
  Goal + acceptance criteria + phase list + gates. Reserve full task elaboration
  for multi-file plans and mechanical-tier batch phases. Soft size budgets
  (validator-warned, Execution log excluded): **single-file plan ≤ 8 KB, phase
  file ≤ 6 KB**. A plan over budget is usually carrying derivable code or
  narration.
- **Detail depth is tier-conditional.** `tier: mechanical` batch phases run on
  weaker models with no conversation history — they may carry prescriptive
  steps and fuller code. `standard`/`hard` phases run on frontier models that
  outrank the plan text — give them contracts, anchors, and gates, not
  implementations.

**Invariant (do not despecify these):** per-phase machine gates, the
`depends_on`/`tier`/`gate`/`phase-type` metadata, exact file paths, vertical-slice
decomposition, Step-0 HITL ratification, autonomy/isolation front-loading, and
the plan/executor session split all stay. The spec-first rule changes *what
fills the phases*, not the execution machinery.

---

## Plan mode: triage before structure

Two modes, chosen by a triage step that runs at the top of **every** `aidex-plan`
invocation (skipped in one line when the user names the mode outright).

**The discriminator is not size.** A two-file change that alters a contract another
module consumes deserves the full adversarial pass; an eight-file change repeating an
established pattern does not. What discriminates is: **is there more than one viable
design, and is choosing wrong expensive?** When the *how* is settled and only the
*where* needs pinning down, there is nothing to be adversarial about.

### The five signals

| Observable | If yes |
|---|---|
| An existing repo pattern this change repeats | scoped |
| Touches a shared contract, or an API another module consumes | full |
| Requires a migration or schema change | full |
| Reverts with a single `git revert` | scoped |
| Two or more viable designs where choosing wrong costs a rewrite | full |

### The four outcomes

- **direct** — one file, trivial. Do not plan; do the work.
- **scoped** — one phase, declared file contract. Below.
- **full** — everything else in this document.
- **research** — the *how* is unknown; planning now is invention. Route to `aidex-research`.

**Run the triage as a subagent.** It may read as much of the repo as it needs, but its
output contract is fixed: the five signals with their evidence, plus one recommended
outcome — no design sketches, no architectural alternatives. If it cannot decide from
what it read, the correct outcome is already `research`. The unbounded read stays inside
the subagent; the planning session receives five booleans.

The user ratifies the **evidence**, not the label. A recommendation presented as a bare
verdict becomes a rubber stamp — which is the failure mode of the silent
auto-classification this deliberately replaces.

### Scoped plans

`mode: scoped` in the front-matter (omitted or `mode: full` = everything below this
section). A scoped plan delivers the **complete** solution to what was asked; it is not
a stopgap, and the necessity recheck is what proves it.

Structural rules, enforced by `validate.py` as **violations, not warnings** — the soft
proportionality budget above was already canon and was measured to be dead letter, so
this mode's guarantee is mechanical or it is nothing:

- Exactly **one phase**. A scoped plan is therefore never batch-eligible, and
  `aidex-plan` does not offer `aidex-plan-exec` for it — the existing ≥2-phase rule
  already covers that.
- **`**Files:**` enumerated and non-empty** — the file contract, written before the
  tasks. This is the blast radius, declared.
- **`**Out of scope:**` non-empty.** Optional in the phase template above; required
  here. Its job is to stop *re-litigation*, not scope creep — acceptance says the search
  filters the scripts panel, a reader asks "and the timeline?", and this field answers
  without reopening the design. One line. It does **not** spawn backlog items: a scoped
  plan's premise is that what it contains is what the request needs.
- **At least one machine-checkable acceptance criterion.**
- Size stays informational. A byte cap is a proxy, and a tight proxy gets met by
  compressing prose or by dropping the discovered constraints that make a plan worth
  reading.

**Alignment collapses to one round** — no four-question Step 0. The scope *is* the file
list plus the acceptance criteria; confirm those and write.

**No adversarial design pass.** It already ran, once, at triage, against the question
"is this scoped?" — the same rigor, applied where it changes a decision.

#### The necessity recheck

Run it in **both** directions before saving. "Is this what's necessary?", answered by
the agent that just wrote the plan, is self-grading and always returns yes; the paired
form is falsifiable:

- For each file in the contract → which acceptance criterion requires it? No answer:
  **surplus**.
- For each acceptance criterion → which file delivers it? No answer: **missing**.

This also replaces RED-first. A scoped plan reproduces no bug, so writing the test first
has nothing to bite on — but a test written after the code, by the same agent, can pass
vacuously by asserting whatever the code happens to do. The acceptance criteria are
written *before* implementation and paired to files here, so the test validates a
criterion that predates it. Tests ship in the same commit; their order is not mandated.

#### Deviation from the file contract

Execution will sometimes need a file the contract does not list — the contract is
written with deliberately incomplete investigation. The contract makes deviation
**visible, not impossible**:

1. Log the file in the Execution log, one line.
2. Re-apply the five triage signals **to that file**. If any flips to `full`, stop and
   re-triage the whole plan.
3. Independently: if the file list has **doubled**, stop and re-triage. Six extra
   trivial files trip no signal but mean the contract misread the change — a different
   failure, invisible to rule 2.

#### Accumulation — the unbuilt tripwire

The standing risk of a cheap mode is that everything becomes scoped and the codebase
accretes point solutions that never receive an architectural pass. The observable:
**the same file appearing in the contracts of three consecutive scoped plans** — that
module needed a design pass and got three patches instead. Nothing counts this today;
each plan lists its files, so the data exists once there are enough scoped plans
(~10) to measure. Do not build the counter before then.

---

## Structure pattern

Threshold (ADR `decision/2026-07-02-plan-modular-threshold`): **single-file is the
default up to 4 phases and <20 tasks**; go multi-file at 5+ phases, 20+ tasks,
multi-layer scope (backend + frontend + infra), when phases are executed by
different sessions/teammates — or when a single file would blow the size budget
above even in spec form.

### Single-file plan (default: up to 4 phases, <20 tasks)

```
.context/plans/YYYY-MM-DD-<feature>.md
```

### Multi-file plan (5+ phases, 20+ tasks, or multi-layer)

```
.context/plans/YYYY-MM-DD-<feature>/
├── 00-index.md           # Master index
├── 01-<phase>.md         # Phase 1
├── 02-<phase>.md         # Phase 2
└── …
```

Folder/filename date: `YYYY-MM-DD` (D-01). Slug: kebab-case, describes the feature.

### Archive

Per D-05, completed plans move to `.context/plans/_archive/` on `status: done`. Inbound references resolve via the two-folder lookup in [`00-global.md` §3](00-global.md#3-cross-references-d-03), so no inbound edits are required.

### Plans roll-up index (`plans/00-index.md`)

`.context/plans/00-index.md` is the **auto-generated roll-up of state across all plans** (active grouped by `## Doing` / `## Open`, closed rolled up from `_archive/`) — the plans analogue of `backlog/00-index.md`. Do **not** hand-edit it; the `aidex-plan` skill regenerates it (`scripts/reindex-plans.sh`) on plan creation and on `close-plan.sh`.

> **Two different `00-index.md` files, no collision.** The top-level `plans/00-index.md` (this roll-up) is distinct from a *modular plan's* internal `plans/<slug>/00-index.md` (the master index of one plan's phases, below). They live at different paths; consumers that glob plans skip the top-level one by basename.

---

## `00-index.md` template

> This template is the **modular plan's internal** master index (`plans/<slug>/00-index.md`), not the top-level roll-up described above. A single-file plan carries the same sections (minus the phase-file table) at its top.

```markdown
---
title: "Feature name"
status: open | doing | done | dropped
mode: scoped | full          # optional; omitted = full
current-phase: 0
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# [Feature Name] Implementation Plan

**Goal:** [One sentence — what this builds]

**Design concept:** [The Step-0 ratified paragraph, verbatim — scope, success
criteria, constraints as the user confirmed them. This is the plan's durable
core: when implementation detail drifts, this is what the executor re-derives
from.]

**Non-goals:**
- [What this plan deliberately does not do]

**Architecture:**
- [Key decision 1 — and the discovered constraint that forced it]

**Autonomy:** [gates resolved up front — pre-authorized publishes, flagged
destructive migrations; see autonomy-conventions.md]

**Isolation:** [worktree recommendation if parallel to other work — omit otherwise]

---

## Phases Overview

| Phase | File | Description | Tasks |
|---|---|---|---|
| 1 | [01-phase-name.md](01-phase-name.md) | Brief description | N |
| 2 | [02-phase-name.md](02-phase-name.md) | Brief description | N |

---

## Session Checkpoint

**Status:** [open/doing/done/dropped — matches front-matter]
**Phase:** [current phase + short state]
**Next:** [first unchecked task]
```

The `status` field uses the base lifecycle from [`00-global.md` §6](00-global.md#6-status-vocabulary): `open` (not started), `doing` (in progress), `done` (complete), `dropped` (abandoned). `blocked_by`, `escalated_to`, `superseded_by` are layered modifiers per §6.

> **Checkbox state has one carrier.** Task/phase checkboxes live in the phase
> checkpoints (below). The Session Checkpoint is a pointer (status / phase /
> next), not a second checkbox list — duplicated checkboxes drift.

---

## Phase file template

```markdown
---
depends_on: [1]
tier: standard
gate: "pytest tests/test_phase2.py"
phase-type: afk-impl
tests: api
---

# Phase N: [Phase Name]

[← Back to Index](00-index.md)

**Goal:** [One sentence — the behavior this phase delivers.]

**Acceptance:**
- [2–4 observable behaviors — at least one machine-checkable, and the gate
  command must prove a subset of these]
- [e.g. "a user with an expired token sees the resend screen, not a 500"]

**Out of scope:** [per-phase non-goals — omit if nothing surprising]

---

## Task N.1: [Task Name]

**Files:**
- Create: `exact/path/to/new-file.py`
- Modify: `exact/path/to/existing.py` (`ClassName.method` — after the `speed_override` field)

**Spec:** [2–6 lines: the behavior to build, the pattern to mirror ("mirror
`test_user_invitation.py`"), and the constraints scoping discovered ("the send
helper raises on failure — no bool return; a pre-existing test expects bool and
must be reconciled").]

**Contract:** *(only when other phases/tasks rely on the exact shape)*

\`\`\`python
def send_reset_email(user: User) -> None:  # raises on failure
\`\`\`

**Verify:**

\`\`\`bash
command-to-verify
\`\`\`

Expected: `OK`

> If a phase's Verify step is a machine gate the work should *iterate against*
> (e.g. "make the module's tests pass", "typecheck clean", "remove every call to X"),
> consider spawning a loop-spec via `aidex-loop` and handing off execution rather
> than hand-running the loop.

---

## Task N.2: …

---

## Phase N Checkpoint

**Completed:**
- [ ] Task N.1: [brief]
- [ ] Task N.2: [brief]

**Next:** [Phase N+1](0N+1-phase-name.md)
```

**The gate is first-class in single-file plans too.** In a single-file plan,
either declare `gate:` in the phase-heading annotation or make the **first line
of the Verify block a fenced command**. A prose-only Verify ("manual
confirmation of Task 3.1") silently drops the phase out of batch eligibility —
if that is intended, mark the phase `phase-type: hitl-align` explicitly.

---

## Phase organization

**Lead with vertical slices.** A vertical slice is one thin, end-to-end piece of behavior cut *across* all layers (one model field → its API field → its UI control → its test), shippable on its own. Prefer slicing the work this way: each slice is a phase that delivers working behavior, and **two slices that touch different features have no edge between them, so an executor can run them in parallel** (see `depends_on` below and the `fan-out-with-gate` execution form). Example phase names: `01-slice-create-todo.md`, `02-slice-mark-done.md`, `03-slice-filter-list.md`.

**Layer-ordering is the secondary pattern.** Grouping by layer (models → serializers → views → URLs → tests) is sometimes the honest shape — e.g. a schema migration that genuinely must land before anything reads it. But layer phases are inherently sequential (each layer waits on the one below), so they forfeit any parallelism and tend to defer working behavior to the last phase. **Pushback note:** if your first phase is a layer with no user-visible behavior (a "build all the models" phase), stop and ask whether a vertical slice would deliver something testable sooner — only keep the layer split when a real ordering constraint forces it. Feature-area and dependency-order groupings are fine variants of the slice pattern.

### Optional phase metadata (and how it is carried)

A phase may declare the optional fields below that the executor (`aidex-plan-exec`) reads to drive batch execution. **All of them share one carrier rule:**

- **Single-file plan** → inline on the phase heading, as `(key: value)` annotations:
  `# Phase N: [Phase Name]  (depends_on: [1, 2], tier: standard, phase-type: afk-impl, tests: api)`
- **Multi-file plan** → in the phase file's **front-matter**, one key per line:
  ```yaml
  ---
  depends_on: [1, 2]
  tier: standard
  gate: "pytest tests/test_phase2.py"
  phase-type: afk-impl
  tests: unit  # unit | api | component | e2e | none
  ---
  ```

Use one carrier per plan consistently; the derivation reads whichever the plan uses (this is the unified carrier shape — there is no third place to look). The fields:

- **`depends_on: []`** — earlier phases this one needs (it reads their output). Omitted/`[]` = **independently grabbable**, eligible to run concurrently with any other edge-free phase. List only real data dependencies — a spurious edge is a serialization you didn't need, and it kills parallelism. Drives sequential (`pipeline-with-gate`) vs parallel (`fan-out-with-gate`) execution. **At batch time these entries become scheduler ids** — `aidex-plan-exec` rewrites each entry to the exact phase `id` it assigns, so keep them unambiguous (phase numbers or slugs, used consistently). A phase other phases depend on should expose what they may rely on in a **Contract** block — dependents read shapes from the contract (or off disk), never from prose.
- **`tier: mechanical | standard | hard`** — the per-phase model/effort hint (`mechanical → sonnet/low`, `standard → sonnet/medium`, `hard → opus/high`). Omitted = `standard`. Tier also sets detail depth (see Philosophy): mechanical phases may carry prescriptive steps/code; hard phases get contracts + gates only.
- **`gate:`** — the phase's machine-checkable verification command (the test/type-check/build it must pass). A phase with no gate is not batch-eligible. In single-file plans the gate is the first fenced command of the phase's **Verify** block if not declared inline.
- **`phase-type: hitl-align | afk-impl`** — the execution mode:
  - **`afk-impl`** (default if omitted) — an implementation phase that can run unattended/batched: it has a machine gate and needs no human judgment mid-phase. **Only `afk-impl` phases are batch-eligible** as a `Workflow`.
  - **`hitl-align`** — a phase that requires human-in-the-loop alignment (defining scope, success criteria, or a design concept; see `aidex-plan` Step 0). It is **never** promoted into a Workflow — the executor runs it interactively. Defining a phase's own spec/gate is the judgment an agent grading its own questions gets wrong, so it stays human-gated.
- **`tests: unit | api | component | e2e | none`** — `afk-impl`-only: which test layer's acceptance test closes this phase (API or E2E, whichever describes what the phase promises; unit tests still run in parallel regardless). Write that one acceptance test up front and leave it red — see `aidex-plan` Step 3 and `aidex-plan-exec`'s batch gate. A list is allowed when more than one layer genuinely closes the phase. `none` requires a written reason: `tests: none  # reason: <why no acceptance test applies>`. `hitl-align` phases are exempt, same as the gate rule.

---

## Execution log (canonical journaling home)

Execution evidence — per-phase proofs, bifurcations taken under the do+document
autonomy policy, gate outputs, follow-up commits — lands in **one** append-only
section at the bottom of the plan (single-file) or of `00-index.md` (modular):

```markdown
## Execution log

- 2026-07-19 · Phase 1 green (`pytest …` 14 passed) · commit `abc1234`
- 2026-07-19 · Bifurcation: send helper raises instead of returning bool —
  pre-existing test reconciled (do+document)
```

Do **not** scatter execution notes into header blockquotes, front-matter prose,
or per-task appendices — three carriers was the measured bloat driver, not code.
Larger captures go to `.context/proofs/<slug>/` with a link. **Orient-time reads
may skip Execution log entries for completed phases**; the log is excluded from
the size budgets above.

---

## Session checkpoint

At end of each work session, update the Session Checkpoint pointer:

```markdown
## Session Checkpoint

**Status:** doing
**Phase:** 2 (Task 2.3 in progress)
**Updated:** 2026-05-14
**Blockers:** None
**Next:** finish Task 2.3, then Task 2.4
```

Also bump the front-matter `updated:` date and `current-phase:` integer. Task
checkboxes live in the phase checkpoints only.

---

## Validation checklist

### Index file (`00-index.md`)
- [ ] Front-matter has `title`, `status`, `created`, `updated`, `current-phase`
- [ ] Title, Goal, Design concept, Non-goals, Architecture sections
- [ ] Phases Overview table with links
- [ ] Session Checkpoint pointer (status/phase/next — no duplicate checkbox list)

### Phase files
- [ ] Phase title with number; link back to index
- [ ] **Goal** (one sentence) and **Acceptance** (≥1 machine-checkable behavior)
- [ ] Machine gate present (`gate:` or fenced command in Verify) for every `afk-impl` phase
- [ ] Tasks numbered `N.1`, `N.2`, … — each with Files + Spec
- [ ] Phase Checkpoint with task checkboxes at end

### Scoped plans (`mode: scoped`)
- [ ] Exactly one phase
- [ ] **Files:** enumerated and non-empty (the file contract)
- [ ] **Out of scope:** non-empty (one line — required in this mode)
- [ ] ≥1 machine-checkable acceptance criterion
- [ ] Necessity recheck run in both directions (file→criterion, criterion→file)

### Spec-shape checks
- [ ] Anchors are stable (symbol names / "after field X"), not bare line numbers
- [ ] Literal code appears only in Contract blocks or where the exact text is the spec
- [ ] Content passes the removal test; file within soft size budget (Execution log excluded)
- [ ] Discovered constraints/landmines recorded in the relevant task's Spec

---

## Related

- [`00-global.md`](00-global.md) — shared rules.
- [`audit-conventions.md`](audit-conventions.md) — when work begins as an audit finding.
- [`request-decision-conventions.md`](request-decision-conventions.md) — when a plan supersedes a request.
