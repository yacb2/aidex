---
name: aidex-skill
description: 'Use when the user wants an existing or in-progress skill checked or structured against THIS project''s house skill conventions — "what are our skill conventions", "review this skill against our standards", "does this skill follow our patterns", "structure this skill the way we do", "audit this skill''s front-matter/description for our rules". Not for: creating a skill from scratch, optimizing a skill''s description for triggering, or running skill evals (all skill-creator); planning (aidex-plan); decisions (aidex-decision); requests (aidex-request); research (aidex-research); references (aidex-reference); ecosystem audits (aidex).'
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-skill"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Skill Conventions

Surface and apply this project's house skill conventions to an existing or
in-progress skill. This skill COMPLEMENTS `skill-creator` (it does **not**
create skills from scratch); it reads the `skill-conventions.md` canon
READ-ONLY and never modifies it.

> **Critical** This skill reads skill-conventions.md and any references/*-conventions.md as READ-ONLY canon. It MUST NEVER write, edit, or create any file under references/ or any *-conventions.md. Writes are limited to the target skill's own files (its SKILL.md / evals).

## Workflow

1. Read the skill conventions canon:
   `~/.claude/skills/aidex-conventions/references/skill-conventions.md`
   (READ-ONLY — never write this file or any `references/*-conventions.md`;
   or the `.claude/skills/...` project-level copy if one exists).
2. Identify the target skill the user is reviewing or structuring.
3. Produce a gap report against the canon: front-matter (trigger-first
   `description`, char budget, **English-only `description`**,
   `disable-model-invocation`, `allowed-tools`), body structure, `evals/`
   presence, no per-skill `CHANGELOG.md`/`README.md`.
   - **English-only check** (canon `skill-conventions.md` rule 2): the
     `description` must contain no Spanish/other-language phrasings or accented
     tokens. The matcher bridges cross-lingually, so an English description still
     fires on non-English queries; native-language queries belong in the
     `evals/` query set, not the description. Detect with:
     ```bash
     desc=$(awk 'f&&/^[a-zA-Z_-]+:/{exit} /^description:/{f=1} f' <target>/SKILL.md)
     printf '%s' "$desc" | grep -nE '[áéíóúñ¿¡]' && echo "GAP: non-English tokens in description"
     ```
     Flag any hit as a gap and rewrite the description English-only, preserving
     semantic coverage (drop the foreign phrasings; keep their English equivalents).
4. Apply non-canon fixes to the target skill's **own files only** (its
   `SKILL.md` / `evals`) — never to `references/*-conventions.md`.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Create a skill from scratch / optimize a description / run skill evals | `skill-creator` |
| Plan multi-step / multi-phase implementation work | `aidex-plan` |
| Record a decision / ADR | `aidex-decision` |
| Capture a stakeholder/client request | `aidex-request` |
| Investigate / research how something works | `aidex-research` |
| Document a settled system reference | `aidex-reference` |
| Audit the Claude Code ecosystem | `aidex` |

## Related

- **skill-creator** — owns skill creation, description optimization, and
  eval running; this skill only checks/applies house conventions.
- **aidex-conventions** — owns the shared documentation canon (this skill
  reads its `references/skill-conventions.md` READ-ONLY).
