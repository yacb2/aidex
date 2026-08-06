---
name: aidex-conventions
description: NOT auto-invoked. Shared documentation-canon hub for the aidex-* family — holds the .context/ convention references (references/*.md) that the single-purpose sibling skills delegate into. Routing — plan multi-step work → aidex-plan; record a decision/ADR → aidex-decision; capture a stakeholder/client request → aidex-request; investigate/research how something works → aidex-research; document a settled system reference → aidex-reference; defer/park an idea for later → aidex-backlog; capture/draft a communication received or to send → aidex-comm; check a skill against house conventions → aidex-skill. This skill is the canon home, not an entry point; the siblings are the entry points.
disable-model-invocation: true
user-invocable: false
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-conventions"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Documentation Standards

> **Canon hub — NOT model-invoked (`disable-model-invocation: true`).** This
> skill is no longer an entry point. It exists to **own and host the shared
> `.context/` convention canon** in `references/*.md`, which the single-purpose
> sibling skills read and delegate into. To actually create an artifact, the
> matching sibling fires: planning → **aidex-plan**, decisions →
> **aidex-decision**, requests → **aidex-request**, research →
> **aidex-research**, references → **aidex-reference**, skill-conventions
> checks → **aidex-skill**. Everything below is the canon index, not an
> active workflow.

Standards for consistent documentation structure in Claude Code projects.

## Overview

This skill defines conventions for thirteen documentation types:

| Type | Purpose | Structure |
|------|---------|-----------|
| **References** | Project-specific guides (deployment, architecture) | Numbered files (`00-index.md`, `01-topic.md`) |
| **Docs** | Library/dependency documentation | Same as references |
| **Skills** | Claude capability extensions | `SKILL.md` + `references/`, <500 lines, tested triggers, gotchas, behavioral evals via `skill-creator` |
| **Plans** | Multi-session implementation tracking | Phases with checkboxes |
| **Requests** | Incoming tasks and product requirements | Single dated file |
| **Decisions** | Architecture/product decision records | Single dated file with context, options, outcome |
| **Backlog** | Deferred/parked ideas queued for later | Single dated file (`YYYY-MM-DD-<slug>.md`) |
| **Research** | Investigation/spike notes captured before planning | Numbered files in a dated topic folder |
| **Audits** | State-of-project catalogs with inventory + dated runs | `<methodology>/` with `00-inventory.md` + `00-methodology.md` + `00-changelog.md` + `YYYY-MM-DD-<slug>/` runs |
| **Communications** | Log of emails/messages/calls/meetings received, sent, or held | `{received,sent,meetings}/<YYYY-MM-DD>-<slug>/body.md` (native language) |
| **Loops** | Agentic loop-specs (goal + stop condition + engine) | Single dated file, via `aidex-loop` |
| **Worktrees** | Per-project worktree/isolation procedure | Evergreen `worktrees/00-index.md`, via `aidex-worktree` |
| **CLAUDE.md** | Project context for Claude | Concise knowledge base |

## Quick Reference

**This table is a dispatch table, not a reading list.** Find the row for the artifact
kind you are about to write or judge, and **read that one file in full before writing
anything** — the files live in `~/.claude/skills/aidex-conventions/references/`. Working
from the summary in `rules/aidex-conventions.md` is enough to *recognize* a convention
and never enough to *apply* one: the per-type file owns the front-matter schema, the
status vocabulary and the archive rule that `validate.py` actually enforces.

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
| Worktrees & isolation (parallel work) | [worktree-conventions.md](references/worktree-conventions.md) |
| Worklist (run-queue) | [worklist-conventions.md](references/worklist-conventions.md) |
| Workflow CORE (single-sourced blocks) | [workflow-core.md](references/workflow-core.md) |
| Review scope (what am I reviewing?) | [review-scope-conventions.md](references/review-scope-conventions.md) |
| Library docs | Uses reference conventions |
| CLAUDE.md | [claudemd-conventions.md](references/claudemd-conventions.md) |

## Migrating an existing `.context/` to the unified canon

For a project that pre-dates these conventions — mixed `YYYYMMDD-` filenames, missing
front-matter, legacy status terms, no roll-up indexes — **read**
`~/.claude/skills/aidex-conventions/references/migration-guide.md` **and follow it**.
It holds the `migrate-conventions.py` invocation and its dry-run-by-default contract,
what the migration does and deliberately does not restructure, the manual-review cases
it declines out loud, and the separate backfill for `plans/00-index.md` and
`audits/00-index.md` including the safety rule that a hand-made index is skipped, not
clobbered.

## Core Principles

### Progressive Disclosure

1. **Index/overview first** - Always visible, provides navigation
2. **Detailed modules** - Loaded as needed
3. **Cross-references** - Enable discovery without bloating context

### Metadata Headers

All documents include consistent metadata:

```markdown
**Version:** X.Y.Z
**Last Updated:** YYYY-MM-DD
**Context:** Brief description
```

### Cross-References

Use relative markdown links with anchors:

```markdown
[Description](./NN-filename.md#section-anchor)
```

### Language

Language is **scoped by artifact kind** (see [`00-global.md` §4](references/00-global.md#4-language-d-04)):

- **Knowledge artifacts → English (always):** plans, decisions, requests, research, references, docs, audits, backlog, loops, CLAUDE.md, and skill prose. This keeps cross-project uniformity and skill matching predictable.
- **Communications → the language of the communication:** `communications/` bodies follow the interlocutor's language (never translate a Spanish client email to English). Front-matter keys stay English; values are as-is. See [communication-conventions.md](references/communication-conventions.md).
- **Code + code comments → English** (unchanged).

Skill **descriptions** stay English-only regardless (D-11). The assistant continues to *reply* in the user's spoken language; only the written artifacts above are constrained.

## Canonical File Locations

| Type | Location | Naming |
|------|----------|--------|
| Global skills | `~/.claude/skills/<name>/` | kebab-case |
| Project skills | `.claude/skills/<name>/` | kebab-case |
| Shared skills (aidex) | `~/.aidex/skills/<name>/` | kebab-case |
| Plans | `.context/plans/` | `YYYY-MM-DD-<feature>.md` or `YYYY-MM-DD-<feature>/` |
| Issues | `.context/issues/` | `ISSUE-NNN-description.md` + `00-index.md` |
| Roadmap | `.context/roadmap/` | `README.md` + `NN-phase-name.md` |
| Requests | `.context/requests/` | `YYYY-MM-DD-description.md` + `_archive/` |
| Decisions | `.context/decisions/` | `YYYY-MM-DD-description.md` + `_archive/` |
| Backlog | `.context/backlog/` | `YYYY-MM-DD-<slug>.md` + `_archive/` |
| Research | `.context/research/` | `<topic>/` with numbered files (`00-index.md`, `01-*.md`) |
| Audits | `.context/audits/` | `<methodology>/` with `00-inventory.md` + `00-methodology.md` + `00-changelog.md` + `YYYY-MM-DD-<slug>/` |
| Communications | `.context/communications/` | `{received,sent,meetings}/<YYYY-MM-DD>-<slug>/body.md` |
| Global references | `~/.context/references/<topic>/` | Numbered (00-index.md, 01-*.md) |
| Project references | `.context/references/<topic>/` | Numbered |
| Library docs | `.context/docs/<library>/` | Numbered |
| Global CLAUDE.md | `~/.claude/CLAUDE.md` | - |
| Project CLAUDE.md | `.claude/CLAUDE.md` | - |

> **Resolution:** Project-level skills override global skills of the same name. When updating a skill, verify its location first.

## When to Use Each Type

### References

Project-specific multi-step guides: deployment procedures, architecture documentation, setup/configuration guides, operational runbooks.

**Characteristics:** Numbered files, sequential or modular organization, verification steps.

### Docs

Library or dependency documentation: API reference, integration guides, framework-specific patterns.

**Characteristics:** Same as references, focused on external tools.

### Skills

Claude capability extensions: domain expertise, workflow automation, tool integrations.

**Characteristics:** SKILL.md entry point, references/ for details, <500 lines, negative triggers in description, testing & validation guidance.

### Plans

Complex multi-session work: feature implementations, large refactoring projects, migration tasks.

**Characteristics:** Checkboxes for tracking, phases, exact file paths.

### CLAUDE.md

Project context: tech stack overview, critical conventions, links to detailed docs.

**Characteristics:** Concise (<300 lines), reference-focused.

### Requests

Incoming tasks, product requirements, or change requests from stakeholders. A request is a **single document** — if it needs deeper analysis, escalate to a plan or research.

**Characteristics:** Dated file, origin (who asked), description, priority/urgency, outcome (became plan, dropped).

**Interception behavior:** When the user describes a new task, feature request, or product requirement during a conversation, suggest:
1. "Create a formal request?" → `.context/requests/YYYY-MM-DD-description.md`
2. "Or create a plan directly?" → `.context/plans/YYYY-MM-DD-description/`
3. "Or launch a research/investigation?" → `.context/research/`

### Decisions

Architecture or product decision records. Documents **what** was decided, **why**, what alternatives were considered, and the outcome. Prevents revisiting the same debates.

**Characteristics:** Dated file, context/problem, options considered, decision taken, rationale, status (accepted/superseded/dropped).

### Audits

State-of-project catalogs. An audit describes what **is** (findings, gaps, risks, opportunities), distinct from plans which describe what **will be**. Every finding lives in a canonical `00-inventory.md` and is referenced (not copied) from per-run `findings.md` views.

**Characteristics:** per-methodology `00-inventory.md` as source of truth, `00-methodology.md` as living playbook with `00-changelog.md`, dated per-run folders (`YYYY-MM-DD-<slug>/`), nine ready-made playbooks (ux, ai-opportunities, retest, security, perf, a11y, hitl).

**Interception behavior:** When the user wants to "review the state of X", "list bugs", "catalog gaps", or "audit UX/security/perf/accessibility", suggest creating an audit via the `aidex-audit` skill (`/aidex-audit new <type> <slug>`). Audits differ from issues (which are already-triaged and scoped to fix) and plans (which are active work).

### Backlog

Deferred or parked ideas: work the team intends to do later but is not acting on now. A backlog entry captures the idea, why it is deferred, and what would trigger picking it up — created via the `aidex-backlog` skill.

**Characteristics:** Single dated file, `status` lifecycle (`open` → `doing` → `done`/`dropped`), priority, optional link to the plan or loop-spec that picks it up.

### Research

Investigation or spike notes captured before a plan or implementation exists: how something works, what the options are, what an experiment found — created via the `aidex-research` skill.

**Characteristics:** Numbered files in a dated topic folder (`<topic>/00-index.md`, `01-*.md`), findings referenced (not duplicated) by later plans/decisions.

### Communications

A log of emails, WhatsApp messages, calls, and meetings — received from or sent to a stakeholder/client, or held synchronously — captured so the thread is searchable and cross-linkable to plans/decisions/requests. Created via the `aidex-comm` skill.

**Characteristics:** `{received,sent,meetings}/<YYYY-MM-DD>-<slug>/body.md` (attachments alongside; synchronous records live in `meetings/` with a `participants` list instead of `direction`/`from`/`to`), front-matter (`channel`, `direction`, `from`/`to`, `subject`, `date`, `status` for the sent side, `related: []`, `created`, `updated`). Body text is in the **native language of the communication** — communications are exempt from the English-only rule (front-matter keys stay English). See [communication-conventions.md](references/communication-conventions.md).

### Plan: Modular vs Single-File

**Single-file** (default):
- Up to 4 phases
- Less than 20 tasks total
- Small-medium project

**Multi-file** (directory with 00-index.md):
- 5+ phases
- 20+ tasks
- Large or multi-layer project (backend + frontend + infra)
- Phases executed by different sessions/teammates

## Workflow Integration

aidex-conventions provides structural conventions for documentation. To create or validate documentation:

- **Plans:** Read [plan-conventions.md](references/plan-conventions.md), follow the template, save to `.context/plans/`
- **Skills:** Read [skill-conventions.md](references/skill-conventions.md), follow the template
- **References/Docs:** Read [reference-conventions.md](references/reference-conventions.md), follow numbered file structure
- **Requests/Decisions:** Read [request-decision-conventions.md](references/request-decision-conventions.md), follow the template
- **Audits:** Read [audit-conventions.md](references/audit-conventions.md); for scaffolding and validation, delegate to the `aidex-audit` skill
- **CLAUDE.md:** Read [claudemd-conventions.md](references/claudemd-conventions.md), validate against conventions

Complementary skills (e.g., skill-creator for behavioral testing, TDD workflows) can extend these conventions with execution tracking.

## Syncing Documentation

When documentation needs updating from official sources:

**For skills:** Extract version + Resources section from SKILL.md → resolve Context7 library ID → fetch latest → compare → report changes → apply with approval.

**For references (code-based):** Compare documented file paths and code snippets against actual project code → flag drift.

**For docs (library-based):** Compare documented library version against package.json/pyproject.toml → detect minor/feature/major version changes → incremental sync or full regeneration.

## Related

- **Auditing and fixing:** Use the `aidex` skill (`/aidex`) for ecosystem audits and automated fixes
- **Agent definitions:** `aidex` skill contains the subagent specifications used during audits
