---
name: aidex-research
description: 'Use when the user needs to investigate, explore, or spike on how something works and the findings should land as written `.context/research/` notes before any plan or implementation. Fires on "research how X works", "investigate X", "spike on X", "look into how X is done", "I need to understand X before planning". Not for: planning multi-step work once the approach is known (aidex-plan); recording a decision/ADR (aidex-decision); capturing a stakeholder request (aidex-request); documenting a settled, stable reference (aidex-reference); deferring/parking an idea (aidex-backlog); ecosystem audits (aidex); project-state audits (aidex-audit).'
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-research"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Research

Capture an investigation or spike as written notes in
`.context/research/<topic>/` before committing to a plan or
implementation. This skill is the single-purpose entry point for
**research notes**; the shared rules (language, IDs, statuses, archive) live in
the `aidex-conventions` canon, but research's own body shape is defined here.

## Workflow

1. Read the shared documentation canon:
   `~/.claude/skills/aidex-conventions/references/00-global.md` (language,
   IDs, statuses, archive rules. Or the `.claude/skills/...` project-level copy
   if one exists). Research has its **own** body shape (below) — it does **not**
   borrow the reference runbook/MODULE template.
2. Pick the shape by size (ADR `decision/2026-07-02-research-artifact-shape`):
   a **single-document spike** is one flat dated file
   (`.context/research/YYYY-MM-DD-<slug>.md` — no folder); a **multi-document
   topic** is a dated folder (`.context/research/YYYY-MM-DD-<slug>/`) with
   `00-index.md` (`00-overview.md` is the accepted alias in `research/` only)
   plus sequential `NN-<slug>.md` files. When a spike gains a second document,
   promote it: create the dated folder and move the spike in as `00-index.md`.
3. Front-matter = the global minimum only: `title`, `status`, `created`,
   `updated`. No `version` — a dated spike is a point-in-time investigation, not
   an evergreen doc that gets revised.
4. Body = research's own minimal shape, three sections:
   - **Question / Scope** — what you set out to answer and its bounds.
   - **Findings** — free-form; number them, subsection them, whatever the
     investigation needs. No fixed Overview/Prerequisites/Verification skeleton.
   - **Answer / Recommendation** — mandatory closing section that states what the
     spike concluded and what it recommends doing next. A spike is not done until
     this section answers the question.

   If a finding is mechanically verifiable (a benchmark or test the follow-up
   work should iterate against), link out to an `aidex-loop` loop-spec rather than
   describing a manual loop here. Write the artifact in English (canon §Language).

## Closing a spike

A spike closes when its question is answered — the **Answer / Recommendation**
section is written. On close:

- Set `status: done` and stamp `updated`. `done` is the terminal state; do not
  invent `answered`, `complete`, or `superseded-by-result` — those are not in
  the base status vocabulary the validator enforces.
- Link what it feeds: `escalated_to` a plan or decision the research spawned, or
  set `origin_ref` on the artifact it produced back to this spike.
- Research is versioned in place — there is **no `_archive/`** step for
  `research/` (unlike decisions/requests, which archive on close per D-10).

## Self-check (mandatory close step)

Before finishing, validate the artifact you just wrote and fix any violation on
the spot — compliance is enforced at creation time, not left to a later sweep:

```bash
python3 ~/.claude/skills/aidex-conventions/scripts/validate.py --type research
```

If the project carries a ratchet baseline (`.context/.validate-baseline.json`),
a non-zero exit means you introduced a NEW violation — fix it before closing.

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

- **aidex-conventions** — owns the shared documentation canon (`00-global.md`:
  language, IDs, statuses, archive rules).
