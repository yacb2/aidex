---
name: aidex-decision
description: Use when the user has made an architectural, technical, or product decision and wants it recorded as a written `.context/decisions/` ADR — what was chosen, why, the alternatives, and the consequences — so the team does not re-litigate it later. Fires on "we decided X", "document this decision", "write an ADR", "record the decision to X", "log why we chose X", "we settled on X, write it up". Not for: planning multi-step work (aidex-plan); deferring or parking an idea for later (aidex-backlog); capturing a stakeholder/client request (aidex-request), research notes (aidex-research), or a settled reference (aidex-reference); ecosystem audits (aidex); project-state audits (aidex-audit).
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-decision"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Decision

Record an architectural, technical, or product decision as an ADR in
`.context/decisions/` so it is not re-litigated later. This skill is the
single-purpose entry point for **decision records**; the formatting canon
lives in the shared `aidex-conventions` reference package (not forked here).

## Workflow

1. Read the decision conventions canon:
   `~/.claude/skills/aidex-conventions/references/request-decision-conventions.md`
   (Decisions section; or `.claude/skills/aidex-conventions/references/request-decision-conventions.md`
   if a project-level copy exists).
2. Create a single dated file: `.context/decisions/YYYY-MM-DD-<slug>.md`
   (slug kebab-case; date `YYYY-MM-DD`).
3. Front-matter per the canon — decisions use the ADR status enum
   (`accepted` · `superseded` · `dropped`), **not** the base
   open/doing/done vocabulary. Set `superseded_by: decision/<filename>` when
   one decision replaces another.
4. Body per the canon template: **Context**, **Decision** (Chosen +
   Rationale), **Consequences**. Capture the alternatives considered and the
   deciding factor, not just the verdict. Write the artifact in English
   (canon §Language).

## Closing a decision

Decisions close only when superseded or dropped (an `accepted` ADR stays active
in place). Close atomically (stamps `updated`, sets status + `superseded_by`,
archives per D-10) instead of hand-editing:

```bash
bash ~/.claude/skills/aidex-conventions/scripts/close-dated-artifact.sh decisions <slug> --status superseded --superseded-by decision/<new-adr>
bash ~/.claude/skills/aidex-conventions/scripts/close-dated-artifact.sh decisions <slug> --status dropped
```

## Self-check (mandatory close step)

Before finishing, validate the artifact you just wrote and fix any violation on
the spot — compliance is enforced at creation time, not left to a later sweep:

```bash
python3 ~/.claude/skills/aidex-conventions/scripts/validate.py --type decisions
```

If the project carries a ratchet baseline (`.context/.validate-baseline.json`),
a non-zero exit means you introduced a NEW violation — fix it before closing.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Plan multi-step / multi-phase implementation work | `aidex-plan` |
| Defer / park / shelve an idea for later | `aidex-backlog` |
| Capture a stakeholder/client request | `aidex-request` |
| Investigate / research how something works | `aidex-research` |
| Document a system reference | `aidex-reference` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf/a11y) | `aidex-audit` |

## Related

- **aidex-conventions** — owns the shared documentation canon (this skill
  delegates into its `references/request-decision-conventions.md`).
