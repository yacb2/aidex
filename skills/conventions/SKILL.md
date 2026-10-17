---
name: conventions
description: NOT auto-invoked. Shared documentation-canon hub for the aidex-* family — holds the .context/ convention references (references/*.md) that the single-purpose sibling skills delegate into. Routing — plan multi-step work → plan; record a decision/ADR → decision; capture a stakeholder/client request → request; investigate/research how something works → research; document a settled system reference → reference; defer/park an idea for later → backlog; capture/draft a communication received or to send → comm; check a skill against house conventions → skill. This skill is the canon home, not an entry point; the siblings are the entry points.
disable-model-invocation: true
user-invocable: false
---

# Documentation Standards

> **Canon hub, not model-invoked.** The shared `.context/` convention canon lives in
> `references/*.md`; the sibling entry-point skills read and delegate into it.

## Quick Reference

**This table is a dispatch table, not a reading list.** Find the row for the artifact
kind you are about to write or judge, and **read that one file in full before writing
anything** — the files live in `${CLAUDE_PLUGIN_ROOT}/skills/conventions/references/`. There
is no always-on summary any more (the `rules/` folder retired with the plugin migration):
this skill carries the recognition itself, and the sibling entry-point skills' own
descriptions are what fire on a `.context/` ask. [`00-global.md`](references/00-global.md)
is the recognition surface — read it to know *that* a convention applies — and the per-type
file below is the application surface: it owns the front-matter schema, the status
vocabulary and the archive rule that `validate.py` actually enforces.

| Type | Conventions |
|------|-------------|
| Global rules (all types) | [00-global.md](references/00-global.md) |
| Reference module | [reference-conventions.md](references/reference-conventions.md) |
| Skill | [skill-conventions.md](references/skill-conventions.md) |
| Skill trigger evals | [skill-trigger-eval-methodology.md](references/skill-trigger-eval-methodology.md) |
| Implementation plan | [plan-conventions.md](references/plan-conventions.md) |
| Request / Decision | [request-decision-conventions.md](references/request-decision-conventions.md) |
| Audit | [audit-conventions.md](references/audit-conventions.md) |
| Communication | [communication-conventions.md](references/communication-conventions.md) |
| Autonomy (proceed vs. pause) | [autonomy-conventions.md](references/autonomy-conventions.md) |
| Database lifecycle (real vs. disposable) | [database-protection.md](references/database-protection.md) |
| Worktrees & isolation (parallel work) | [worktree-conventions.md](references/worktree-conventions.md) |
| Worklist (run-queue) | [worklist-conventions.md](references/worklist-conventions.md) |
| Workflow CORE (single-sourced blocks) | [workflow-core.md](references/workflow-core.md) |
| Review scope (what am I reviewing?) | [review-scope-conventions.md](references/review-scope-conventions.md) |
| Between-unit checkpoint (review · commit · defer · handoff) | [checkpoint-conventions.md](references/checkpoint-conventions.md) |
| Human verification (what only a person can judge) | [human-verification-conventions.md](references/human-verification-conventions.md) |
| Measurement (machine load, unattended stop conditions) | [measurement-conventions.md](references/measurement-conventions.md) |
| Library docs | Uses reference conventions |
| CLAUDE.md | [claudemd-conventions.md](references/claudemd-conventions.md) |

## Migrating an existing `.context/` to the unified canon

For a project that pre-dates these conventions — mixed `YYYYMMDD-` filenames, missing
front-matter, legacy status terms, no roll-up indexes — **read**
`${CLAUDE_PLUGIN_ROOT}/skills/conventions/references/migration-guide.md` **and follow it**.
It holds the `migrate-conventions.py` invocation and its dry-run-by-default contract,
what the migration does and deliberately does not restructure, the manual-review cases
it declines out loud, and the separate backfill for `plans/00-index.md` and
`audits/00-index.md` including the safety rule that a hand-made index is skipped, not
clobbered.
