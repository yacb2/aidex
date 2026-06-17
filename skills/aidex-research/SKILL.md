---
name: aidex-research
description: Use when the user needs to investigate, explore, or spike on how something works and the findings should land as written `.context/research/` notes before any plan or implementation. Fires on "research how X works", "investigate X", "spike on X", "look into how X is done", "I need to understand X before planning". Not for: planning multi-step work once the approach is known (aidex-plan); recording a decision/ADR (aidex-decision); capturing a stakeholder request (aidex-request); documenting a settled, stable reference (aidex-reference); deferring/parking an idea (aidex-backlog); ecosystem audits (aidex); project-state audits (aidex-audit).
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Research

Capture an investigation or spike as written notes in
`.context/research/<topic>/` before committing to a plan or
implementation. This skill is the single-purpose entry point for
**research notes**; the formatting canon lives in the shared
`aidex-conventions` reference package (not forked here).

## Workflow

1. Read the research conventions canon:
   `~/.claude/skills/aidex-conventions/references/reference-conventions.md`
   (it also covers `research/`; shared rules live in `00-global.md`. Or the
   `.claude/skills/...` project-level copy if one exists).
2. Create a topic module: `.context/research/<topic>/` with `00-index.md`
   (`00-overview.md` is the accepted alias in `research/` only) plus
   sequential `NN-<slug>.md` files. Research filenames carry **no date**;
   research is versioned in place — there is **no `_archive/`** in
   `research/`.
3. Front-matter per the canon: `title`, `status`, `created`, `updated`,
   `version`.
4. Body per the module template: **Overview**, **Prerequisites**, findings
   sections, **Verification**. If a spike's finding is mechanically verifiable
   (a benchmark or test the follow-up work should iterate against), link out to an
   `aidex-loop` loop-spec rather than describing a manual loop here.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Plan multi-step / multi-phase implementation work | `aidex-plan` |
| Record a decision / ADR | `aidex-decision` |
| Capture a stakeholder/client request | `aidex-request` |
| Document a settled system reference | `aidex-reference` |
| Defer / park / shelve an idea for later | `aidex-backlog` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf/a11y) | `aidex-audit` |

## Related

- **aidex-conventions** — owns the shared documentation canon (this skill
  delegates into its `references/reference-conventions.md` research rules).
