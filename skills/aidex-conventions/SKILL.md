---
name: aidex-conventions
description: Documentation and skill conventions for AI assistant ecosystems. MUST be used whenever the user wants to create, structure, or organize project documentation — plans, references, docs, requests, decisions, research, issues, backlog, audits, or CLAUDE.md. Also activates when the user describes a new task, feature request, product requirement, or stakeholder ask (suggest creating a formal request or escalating to a plan). Activates when the user mentions a technical or architectural decision they made or need to make (suggest creating a decision record). Activates when the user wants to catalog the state of a project (bugs, gaps, opportunities) — suggest creating an audit. Use for any .context/ directory conventions, skill format questions, or plan templates. Do NOT use for auditing the Claude Code ecosystem (skills, symlinks, CLAUDE.md health) — use the aidex skill instead. For operating on audits (scaffold, validate, escalate findings), delegate to the audit skill.
user-invocable: false
---

# Documentation Standards

Standards for consistent documentation structure in Claude Code projects.

## Overview

This skill defines conventions for eight documentation types:

| Type | Purpose | Structure |
|------|---------|-----------|
| **References** | Project-specific guides (deployment, architecture) | Numbered files (`00-index.md`, `01-topic.md`) |
| **Docs** | Library/dependency documentation | Same as references |
| **Skills** | Claude capability extensions | `SKILL.md` + `references/`, <500 lines, tested triggers, gotchas, behavioral evals via `skill-creator` |
| **Plans** | Multi-session implementation tracking | Phases with checkboxes |
| **Requests** | Incoming tasks and product requirements | Single dated file |
| **Decisions** | Architecture/product decision records | Single dated file with context, options, outcome |
| **Audits** | State-of-project catalogs with INVENTORY + dated runs | `INVENTORY.md` + `METHODOLOGY.md` + `CHANGELOG.md` + `YYYYMMDD-<slug>/` folders |
| **CLAUDE.md** | Project context for Claude | Concise knowledge base |

## Quick Reference

| Type | Conventions |
|------|-------------|
| Reference module | [reference-conventions.md](references/reference-conventions.md) |
| Skill | [skill-conventions.md](references/skill-conventions.md) |
| Implementation plan | [plan-conventions.md](references/plan-conventions.md) |
| Request / Decision | [request-decision-conventions.md](references/request-decision-conventions.md) |
| Audit | [audit-conventions.md](references/audit-conventions.md) |
| Library docs | Uses reference conventions |
| CLAUDE.md | [claudemd-conventions.md](references/claudemd-conventions.md) |

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

All generated content uses **English** for consistency.

## Canonical File Locations

| Type | Location | Naming |
|------|----------|--------|
| Global skills | `~/.claude/skills/<name>/` | kebab-case |
| Project skills | `.claude/skills/<name>/` | kebab-case |
| Shared skills (aidex) | `~/.aidex/skills/<name>/` | kebab-case |
| Plans | `.context/plans/` | `YYYYMMDD-<feature>.md` or `YYYYMMDD-<feature>/` |
| Issues | `.context/issues/` | `ISSUE-NNN-description.md` + `00-index.md` |
| Roadmap | `.context/roadmap/` | `README.md` + `NN-phase-name.md` |
| Requests | `.context/requests/` | `YYYYMMDD-description.md` + `_archive/` |
| Decisions | `.context/decisions/` | `YYYYMMDD-description.md` + `_archive/` |
| Audits | `.context/audits/` | `INVENTORY.md` + `METHODOLOGY.md` + `CHANGELOG.md` + `YYYYMMDD-<slug>/` |
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

**Characteristics:** Dated file, origin (who asked), description, priority/urgency, outcome (became plan, deferred, rejected).

**Interception behavior:** When the user describes a new task, feature request, or product requirement during a conversation, suggest:
1. "Create a formal request?" → `.context/requests/YYYYMMDD-description.md`
2. "Or create a plan directly?" → `.context/plans/YYYYMMDD-description/`
3. "Or launch a research/investigation?" → `.context/research/`

### Decisions

Architecture or product decision records. Documents **what** was decided, **why**, what alternatives were considered, and the outcome. Prevents revisiting the same debates.

**Characteristics:** Dated file, context/problem, options considered, decision taken, rationale, status (active/superseded/reversed).

### Audits

State-of-project catalogs. An audit describes what **is** (findings, gaps, risks, opportunities), distinct from plans which describe what **will be**. Every finding lives in a canonical `INVENTORY.md` and is referenced (not copied) from per-run `findings.md` views.

**Characteristics:** `INVENTORY.md` as source of truth, `METHODOLOGY.md` as living playbook with `CHANGELOG.md`, dated per-run folders (`YYYYMMDD-<slug>/`), six ready-made playbooks (ux, ia-opportunities, retest, security, perf, a11y).

**Interception behavior:** When the user wants to "review the state of X", "list bugs", "catalog gaps", or "audit UX/security/perf/accessibility", suggest creating an audit via the `audit` skill (`/audit new <type> <slug>`). Audits differ from issues (which are already-triaged and scoped to fix) and plans (which are active work).

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
- **Audits:** Read [audit-conventions.md](references/audit-conventions.md); for scaffolding and validation, delegate to the `audit` skill
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
