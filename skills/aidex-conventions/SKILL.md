---
name: aidex-conventions
description: NOT auto-invoked. Shared documentation-canon hub for the aidex-* family — holds the .context/ convention references (references/*.md) that the single-purpose sibling skills delegate into. Routing — plan multi-step work → aidex-plan; record a decision/ADR → aidex-decision; capture a stakeholder/client request → aidex-request; investigate/research how something works → aidex-research; document a settled system reference → aidex-reference; check a skill against house conventions → aidex-skill. This skill is the canon home, not an entry point; the siblings are the entry points.
disable-model-invocation: true
user-invocable: false
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

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

## Migrating an existing `.context/` to the unified canon

For projects that pre-date these conventions (mixed `YYYYMMDD-` / `YYYY-MM-DD-` filenames, missing front-matter, legacy status terms like `completed`/`Rejected`), run the migration helper:

```bash
# Dry-run (default) — prints every change without writing:
~/.aidex/skills/aidex-conventions/scripts/migrate-conventions.sh /path/to/project/.context

# Apply when satisfied:
~/.aidex/skills/aidex-conventions/scripts/migrate-conventions.sh /path/to/project/.context --apply
```

What it does (idempotent — re-running on a clean tree is a no-op):

- Renames legacy `YYYYMMDD-<slug>.md` → `YYYY-MM-DD-<slug>.md`. Sanitizes slugs (lowercase, `[a-z0-9-]+`). Prepends a date to files with none, using `created`/`date`/`updated` front-matter or today.
- Injects minimal front-matter (`title`, `status`, `created`, `updated`) where the YAML block is missing. Archived files default to `status: done`.
- Maps legacy status vocabulary: `completed` → `done`, `Rejected` → `dropped`, `Proposed` → `open`, `Pendiente` → `open`, `In Progress` → `doing`.
- Rewrites cross-references (front-matter fields + body) to renamed basenames.
- Creates `_archive/` directories in `backlog/`, `plans/`, `requests/`, `decisions/` if absent.

Recommended workflow:

1. Back up the project's `.context/` before applying (a `cp -r` or commit if tracked).
2. Run `--dry-run` and read the plan — pay attention to the front-matter changes and the cross-ref rewrites.
3. Apply with `--apply`.
4. Re-run the validator: `~/.aidex/skills/aidex-conventions/scripts/validate.sh /path/to/project/.context`. Expect 0 violations.

Edge cases the migration cannot decide for you:

- Custom legacy status values not in the table above — fix manually after dry-run.
- Audit folders that pre-date D-02 (single `INVENTORY.md` at root rather than per-methodology). The migration only normalizes filenames and front-matter; it does not restructure audit folders — do that by hand using the new templates in `audit/assets/templates/`.

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

**Interception behavior:** When the user wants to "review the state of X", "list bugs", "catalog gaps", or "audit UX/security/perf/accessibility", suggest creating an audit via the `aidex-audit` skill (`/aidex-audit new <type> <slug>`). Audits differ from issues (which are already-triaged and scoped to fix) and plans (which are active work).

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
