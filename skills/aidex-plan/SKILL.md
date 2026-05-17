---
name: aidex-plan
description: Use when the user is about to plan multi-step or multi-phase implementation work and it should become a written `.context/` plan before coding starts — a feature build, a migration, a refactor spanning backend/frontend/infra, or any task with phases and checkboxes. Fires on "create a plan for X", "let's plan X", "I want to plan X", "we need to plan X", "plan the migration of X", "quiero planificar X", "necesito un plan para X", "planifiquemos X", "hagamos un plan de X", "armemos un plan multi-fase". Not for: deferring or parking an idea for later (aidex-backlog-register); decisions/ADRs, stakeholder requests, research notes, or references (aidex-conventions); ecosystem audits (aidex); project-state audits (aidex-audit); direct implementation with no plan doc.
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

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
   - **Single-file** (`.context/plans/YYYYMMDD-<feature>.md`): ≤ 4 phases,
     < 20 tasks, small-medium scope.
   - **Multi-file** (`.context/plans/YYYYMMDD-<feature>/` with `00-index.md`):
     5+ phases, 20+ tasks, multi-layer (backend + frontend + infra), or phases
     executed by different sessions/teammates.
3. Follow the template in the canon: phases with checkboxes, exact file paths,
   verification step per phase.
4. Save under `.context/plans/` with the dated naming the canon specifies.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Defer / park / shelve an idea for later | `aidex-backlog-register` |
| Record a decision / ADR | `aidex-decision` |
| Capture a stakeholder/client request | `aidex-request` |
| Investigate / research how something works | `aidex-research` |
| Document a system reference | `aidex-reference` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf/a11y) | `aidex-audit` |
| Implement directly with no plan doc needed | (just do the work) |

## Related

- **aidex-conventions** — owns the shared documentation canon (this skill
  delegates into its `references/plan-conventions.md`).
