---
name: aidex-plan
description: 'Use when implementation work should become a written `.context/` plan before coding starts — either multi-phase work (a feature build, a migration, a refactor spanning backend/frontend/infra) or a single scoped change where only the file list and acceptance criteria need pinning down; a triage step picks which. Fires on "create a plan for X", "let''s plan X", "I want to plan X", "we need to plan X", "plan the migration of X", "let''s build a multi-phase plan", "implement X minimally", "a small scoped change to X", "just the minimum to ship X". Not for: fixing a bug or regression, which needs a failing test first (aidex-bugfix); deferring or parking an idea for later (aidex-backlog); decisions/ADRs, stakeholder requests, research notes, or references (aidex-conventions); ecosystem audits (aidex); project-state audits (aidex-audit); direct implementation with no plan doc.'
disable-model-invocation: false
allowed-tools: Bash Read Write Agent
model-policy: inherit-session
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-plan"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Plan

Create a structured multi-step implementation plan in `.context/plans/` before
coding starts. This skill is the single-purpose entry point for **planning**;
the formatting canon lives in the shared `aidex-conventions` reference package
(not forked here).

## Triage — pick the mode before anything else

Runs on **every** invocation, before Step 0. Skip it in one line only when the user names
the mode outright ("plan this as scoped", "/aidex-plan full"). Canon:
`plan-conventions.md` §Plan mode.

The discriminator is **not size** — it is whether more than one viable design exists and
whether choosing wrong is expensive. Delegate the investigation to a **subagent**
(`Explore` or `general-purpose`, `model-policy: inherit-session` — a repo read at the
session's own depth, deliberately not pinned): it may read as much of the repo as it
needs, but its output contract is fixed — the five signals with their evidence, plus one recommended
outcome. No design sketches, no architectural alternatives. If it cannot decide from what
it read, the outcome is already `research`.

| Observable | If yes |
|---|---|
| An existing repo pattern this change repeats | scoped |
| Touches a shared contract, or an API another module consumes | full |
| Requires a migration or schema change | full |
| Reverts with a single `git revert` | scoped |
| Two or more viable designs where choosing wrong costs a rewrite | full |

Present the **evidence per signal**, then the recommendation — a bare verdict invites a
rubber stamp, which is the failure this replaces. The user ratifies or corrects in one
round. Four outcomes:

- **direct** — one file, trivial. Say so and do the work; no plan doc.
- **scoped** — go to Step 0 (scoped), below.
- **full** — go to Step 0 (full), below.
- **research** — the *how* is unknown. Hand off to `aidex-research`; planning now is invention.

## Step 0 (scoped) — one confirmation round

For `mode: scoped` only. The scope **is** the file list plus the acceptance criteria, so
Step 0 collapses to a single confirm-or-correct round on exactly those two — no
four-question interrogation, and **no adversarial design pass**: that already ran, once,
at triage.

Then, **before saving**, run the necessity recheck in both directions — file→criterion
and criterion→file (`plan-conventions.md` §The necessity recheck). "Is this necessary?"
asked of yourself always returns yes; the paired form is falsifiable.

Write the plan with `mode: scoped` in the front-matter, exactly one phase, `**Files:**`
enumerated, `**Out of scope:**` non-empty (one line), and ≥1 machine-checkable acceptance
criterion. `validate.py` enforces all four as violations — skip Step 3's decomposition
rules below, and go straight to the Self-check.

## Step 0 (full) — Align before planning (HITL — do not skip, do not automate)

Before writing any phases, establish a **shared design concept** with the user. This is the one
step that must stay human-in-the-loop: defining scope and success criteria is the judgment an
agent grading its own clarifying questions gets wrong, and it is exactly what the `aidex-plan-exec`
promotion threshold excludes from batch execution (a `hitl-align` phase, see below).

1. Ask **at most four** clarifying questions, **one at a time**, covering:
   - **Scope** — what is in, and the boundary of this work.
   - **Success criteria** — how we'll know each phase is done (prefer machine-checkable gates).
   - **Explicit non-goals** — what this plan will deliberately *not* do.
   - **Constraints** — stack, deadlines, compatibility, anything that can't change.
   Give each question a **recommended answer** to confirm or correct, so a well-scoped request
   resolves in one or two confirmations rather than an interrogation.
2. Synthesize the answers into a **one-paragraph shared design concept** and have the user
   **ratify it** before you write phases. If the request is already unambiguous and the
   recommended answers all stand, a single "confirm this concept?" round is enough.
3. Skip Step 0 only for a trivial, already-fully-specified plan — and say you're skipping it, and why.

## Workflow

1. Read the plan conventions canon:
   `~/.claude/skills/aidex-conventions/references/plan-conventions.md`
   (or `.claude/skills/aidex-conventions/references/plan-conventions.md` if a
   project-level copy exists).
2. Decide the structure per that canon:
   - **Scoped** (`mode: scoped`): always single-file, exactly one phase. The rest of
     this step does not apply.
   - **Single-file** (`.context/plans/YYYY-MM-DD-<feature>.md`): ≤ 4 phases,
     < 20 tasks, small-medium scope.
   - **Multi-file** (`.context/plans/YYYY-MM-DD-<feature>/` with `00-index.md`):
     5+ phases, 20+ tasks, multi-layer (backend + frontend + infra), or phases
     executed by different sessions/teammates.
3. Follow the template in the canon — **plans are specs, not scripts** (canon
   §Philosophy). Write the artifact in English (canon §Language). The authoring
   rules that matter:
   - **Carry the Step-0 ratified paragraph verbatim** into the plan's **Design
     concept** slot, plus **Non-goals** — that layer is the plan's durable core.
   - **Per phase: Goal + Acceptance** (2–4 observable behaviors, ≥1
     machine-checkable) **+ a machine gate**. Per task: Files + Spec (intent,
     pattern anchor, discovered constraints). **Do not pre-write implementation
     code** — literal code only in a **Contract** block where the exact text IS
     the spec (signatures, schemas, DDL, invariants). Anchor with symbol names,
     never bare line numbers.
   - **`afk-impl` phases declare `tests: unit | api | component | e2e | none`**
     (`none` needs a written reason) and name the single acceptance test that
     closes the phase, at that layer — write it **before** the implementation
     so it starts red; unit tests continue alongside it. `aidex-plan-exec`
     keeps that acceptance test red until the phase's gate passes.
   - **Investigate while planning and record the evidence**: the constraints and
     landmines you discover (existing patterns to mirror, cache/hash seams,
     dead code paths) go in each task's Spec — that investigation, not code, is
     what detailed planning is for.
   - **Proportionality**: every line must pass the removal test ("would the
     executor get this wrong without it?"). Small plans collapse to Goal +
     acceptance + phase list + gates. Soft budgets: single-file ≤ 8 KB, phase
     file ≤ 6 KB (Execution log excluded).
   **Decompose by vertical slices first** (each phase a thin end-to-end piece of
   behavior across layers), not by layer — slices are independently testable and let
   the executor parallelize. Reserve layer-ordering for genuine ordering constraints,
   and push back on a layer-only first phase (see canon §Phase organization). Mark each
   phase's real prerequisites with `depends_on: [...]` (omit/`[]` = independently
   grabbable) so `aidex-plan-exec` can choose parallel vs sequential execution, and
   give any depended-on phase a **Contract** block dependents can rely on.
4. **Front-load the autonomy surface** so execution needs no questions (see
   [autonomy-conventions.md](../aidex-conventions/references/autonomy-conventions.md)).
   This is the place to resolve every gate up front: which planned **migrations /
   dependency changes** exec may run autonomously (additive ones are autonomous by
   default — flag any destructive migration, which stays gated), any **deploy /
   publish / release** the user pre-authorizes for the run, and anything to keep in
   `deny`. Record it as a short **Autonomy** note in the plan so `aidex-plan-exec`
   runs start-to-finish without interrupting.
5. **Capture the isolation surface** if the plan could run parallel to other work.
   Check whether `.context/worktrees/00-index.md` exists in the target project: if it
   does not, invoke `aidex-worktree bootstrap` once, up front, as part of this same
   planning session (the initial-phase front-loading moment); if it exists, invoke
   `aidex-worktree suggest` with the plan's content (does it run migrations? which
   participants does it touch?) and record its recommendation verbatim as the plan's
   **Isolation** note. It is a recommendation the **user / project CLAUDE.md
   authorizes** (native worktree entry is opt-in). If the plan is not parallel to
   anything, omit this — just a branch.
6. Save under `.context/plans/` with the dated naming the canon specifies.
7. **Register it in the plans index.** Run the reindexer so the new plan shows up
   in the roll-up state of all plans (`.context/plans/00-index.md`):

   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/reindex-plans.sh"
   ```

   `00-index.md` is **auto-generated** from each plan's front-matter (do not
   hand-edit). It mirrors the backlog `00-index.md` pattern: active plans grouped by
   `## Doing` / `## Open`, closed plans rolled up from `_archive/`. `close-plan.sh`
   regenerates it automatically on close; this create-time call keeps it fresh on
   creation. Re-run it any time with `reindex-plans.sh`; `reindex-plans.sh --check`
   reports drift read-only (no write) and is what the shared `reconcile.sh` calls.

## Self-check (mandatory close step)

Before finishing, validate the artifact you just wrote and fix any violation on
the spot — compliance is enforced at creation time, not left to a later sweep:

```bash
python3 ~/.claude/skills/aidex-conventions/scripts/validate.py --type plans
```

If the project carries a ratchet baseline (`.context/.validate-baseline.json`),
a non-zero exit means you introduced a NEW violation — fix it before closing.

## Closing a plan

When a plan completes (or is superseded/dropped), close it atomically rather than
hand-editing `status` — this stamps `updated`, records resolving commits where the
work happened (D-09), and archives the plan to `plans/_archive/` (D-10):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/close-plan.sh" <slug> [--commit <sha>] [--status dropped] [--superseded-by <type/ref>]
```

It refuses to archive a plan that still carries an **unreconciled in-text deferral** —
a line reading "carry this to Phase 7", "follow-up", "should note" with no `BL-NNN` and
no explicit `CLOSE: <reason>` on it. Prose is not a mechanism: four deferrals written
that way vanished with their plan and two were still live. Register what is outstanding
(`register-item.sh --origin plan`) or write the `CLOSE` line; `--force` is for a line
that is prose *about* deferring.

After closing, run the shared `reconcile.sh` to surface upstream backlog items /
audit findings this plan resolved that may now be closeable (closure propagation).

## Offer to execute (multi-phase plans only)

After writing a plan with **≥ 2 phases**, offer phase-by-phase execution via
`aidex-plan-exec` (review → commit → handoff between phases). Single-phase or
trivial plans skip this — do not add noise. A `mode: scoped` plan is one phase by
construction, so it never reaches this step.

1. Detect whether `aidex-plan-exec` is installed: check `~/.claude/skills/aidex-plan-exec/`,
   `~/.claude/skills/aidex-plan-exec/`, and any installed plugins.
2. If present → offer: "Execute this plan phase-by-phase with review/commit/handoff
   via `aidex-plan-exec`?"
3. If absent → one-line mention only: a `aidex-plan-exec` skill exists for running
   multi-phase plans, if they want to install it.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Fix existing behavior that is wrong (a bug, a regression) | `aidex-bugfix` — it owns RED-first + regression test. A scoped plan is *new* behavior, minimally delivered; if there is something to reproduce, it is a bugfix, not a scoped plan |
| Defer / park / shelve an idea for later | `aidex-backlog` |
| Record a decision / ADR | `aidex-decision` |
| Capture a stakeholder/client request | `aidex-request` |
| Investigate / research how something works | `aidex-research` |
| Document a system reference | `aidex-reference` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf/a11y) | `aidex-audit` |
| Make one phase iterate-until-green against a machine gate (tests/typecheck/build) | `aidex-loop` (spec it, hand off execution) |
| Split one phase across parallel agents, or assign a model per agent | `aidex-workflow` (spec the fan-out first) |
| Execute / implement an already-written multi-phase plan | `aidex-plan-exec` |
| Implement directly with no plan doc needed | (just do the work) |

## Related

- **aidex-conventions** — owns the shared documentation canon (this skill
  delegates into its `references/plan-conventions.md`).
