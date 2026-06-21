---
name: aidex-plan
description: Use when the user is about to plan multi-step or multi-phase implementation work and it should become a written `.context/` plan before coding starts — a feature build, a migration, a refactor spanning backend/frontend/infra, or any task with phases and checkboxes. Fires on "create a plan for X", "let's plan X", "I want to plan X", "we need to plan X", "plan the migration of X", "let's build a multi-phase plan". Not for: deferring or parking an idea for later (aidex-backlog); decisions/ADRs, stakeholder requests, research notes, or references (aidex-conventions); ecosystem audits (aidex); project-state audits (aidex-audit); direct implementation with no plan doc.
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-plan"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Plan

Create a structured multi-step implementation plan in `.context/plans/` before
coding starts. This skill is the single-purpose entry point for **planning**;
the formatting canon lives in the shared `aidex-conventions` reference package
(not forked here).

## Workflow

1. Read the plan conventions canon:
   `~/.claude/skills/aidex-conventions/references/plan-conventions.md`
   (or `.claude/skills/aidex-conventions/references/plan-conventions.md` if a
   project-level copy exists).
2. Decide single-file vs modular per that canon:
   - **Single-file** (`.context/plans/YYYY-MM-DD-<feature>.md`): ≤ 4 phases,
     < 20 tasks, small-medium scope.
   - **Multi-file** (`.context/plans/YYYY-MM-DD-<feature>/` with `00-index.md`):
     5+ phases, 20+ tasks, multi-layer (backend + frontend + infra), or phases
     executed by different sessions/teammates.
3. Follow the template in the canon: phases with checkboxes, exact file paths,
   verification step per phase. Write the artifact in English (canon §Language).
4. **Front-load the autonomy surface** so execution needs no questions (see
   [autonomy-conventions.md](../aidex-conventions/references/autonomy-conventions.md)).
   This is the place to resolve every gate up front: which planned **migrations /
   dependency changes** exec may run autonomously (additive ones are autonomous by
   default — flag any destructive migration, which stays gated), any **deploy /
   publish / release** the user pre-authorizes for the run, and anything to keep in
   `deny`. Record it as a short **Autonomy** note in the plan so `aidex-plan-exec`
   runs start-to-finish without interrupting.
5. **Capture the isolation surface** if the plan could run parallel to other work
   (see [worktree-conventions.md](../aidex-conventions/references/worktree-conventions.md)).
   Decide and record a short **Isolation** note: is this plan parallel to other
   in-flight work? If so, **Tier 1** (code-only worktree — pure code, no services/DB)
   or **Tier 2** (full environment isolation — runs migrations / needs the stack live /
   risks DB-state collision), and for Tier 2 which `worktree-up` recipe. *Suggest* the
   tier from the plan's content; it is a recommendation the **user / project CLAUDE.md
   authorizes** (native worktree entry is opt-in). If the plan is not parallel to
   anything, omit this — just a branch.
6. Save under `.context/plans/` with the dated naming the canon specifies.

## Closing a plan

When a plan completes (or is superseded/dropped), close it atomically rather than
hand-editing `status` — this stamps `updated`, records resolving commits where the
work happened (D-09), and archives the plan to `plans/_archive/` (D-10):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/close-plan.sh" <slug> [--commit <sha>] [--status dropped] [--superseded-by <type/ref>]
```

After closing, run the shared `reconcile.sh` to surface upstream backlog items /
audit findings this plan resolved that may now be closeable (closure propagation).

## Offer to execute (multi-phase plans only)

After writing a plan with **≥ 2 phases**, offer phase-by-phase execution via
`aidex-plan-exec` (review → commit → handoff between phases). Single-phase or
trivial plans skip this — do not add noise.

1. Detect whether `aidex-plan-exec` is installed: check `~/.claude/skills/aidex-plan-exec/`,
   `~/.aidex/skills/aidex-plan-exec/`, and any installed plugins.
2. If present → offer: "Execute this plan phase-by-phase with review/commit/handoff
   via `aidex-plan-exec`?"
3. If absent → one-line mention only: a `aidex-plan-exec` skill exists for running
   multi-phase plans, if they want to install it.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Defer / park / shelve an idea for later | `aidex-backlog` |
| Record a decision / ADR | `aidex-decision` |
| Capture a stakeholder/client request | `aidex-request` |
| Investigate / research how something works | `aidex-research` |
| Document a system reference | `aidex-reference` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf/a11y) | `aidex-audit` |
| Make one phase iterate-until-green against a machine gate (tests/typecheck/build) | `aidex-loop` (spec it, hand off execution) |
| Execute / implement an already-written multi-phase plan | `aidex-plan-exec` |
| Implement directly with no plan doc needed | (just do the work) |

## Related

- **aidex-conventions** — owns the shared documentation canon (this skill
  delegates into its `references/plan-conventions.md`).
