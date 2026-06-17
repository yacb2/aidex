---
name: aidex-reference
description: Use when the user wants to document how an existing, settled part of the system works as an evergreen `.context/references/` module — architecture, configuration, an operational runbook, a how-it-works guide. Fires on "create a reference for X", "document how X works", "write up the X architecture", "document the X configuration", "write a runbook for X". Not for: planning multi-step work (aidex-plan); recording a decision/ADR (aidex-decision); capturing a stakeholder request (aidex-request); investigating something not yet settled (aidex-research); deferring/parking an idea (aidex-backlog); ecosystem audits (aidex); project-state audits (aidex-audit).
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-reference"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Reference

Document how a settled part of the system works as an evergreen module in
`.context/references/<topic>/`. This skill is the single-purpose entry
point for **reference documentation**; the formatting canon lives in the
shared `aidex-conventions` reference package (not forked here).

## Workflow

1. Read the reference conventions canon:
   `~/.claude/skills/aidex-conventions/references/reference-conventions.md`
   (or `.claude/skills/aidex-conventions/references/reference-conventions.md`
   if a project-level copy exists).
2. Create a topic module: `.context/references/<topic>/` with `00-index.md`
   plus sequential `NN-<slug>.md` files. Reference filenames carry **no
   date** — references are evergreen, updated in place, **no `_archive/`**.
3. Front-matter per the canon: `title`, `status`, `created`, `updated`,
   `version` (semantic `X.Y.Z`). References are exempt from the
   status-vocabulary check.
4. Body per the canon module template: **Overview**, **Prerequisites**,
   main sections with language-hinted code blocks, **Verification**,
   **Version history**. Write the artifact in English (canon §Language).

## Boundaries

| The user wants to… | Route to |
|---|---|
| Plan multi-step / multi-phase implementation work | `aidex-plan` |
| Record a decision / ADR | `aidex-decision` |
| Capture a stakeholder/client request | `aidex-request` |
| Investigate / explore something not yet settled | `aidex-research` |
| Defer / park / shelve an idea for later | `aidex-backlog` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf/a11y) | `aidex-audit` |

## Related

- **aidex-conventions** — owns the shared documentation canon (this skill
  delegates into its `references/reference-conventions.md`).
