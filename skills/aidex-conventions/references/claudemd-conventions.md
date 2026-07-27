# CLAUDE.md Conventions

Standards for creating effective CLAUDE.md project context files.

> **Read [`00-global.md`](00-global.md) first** for shared rules (date format, archive, language, cross-references, front-matter minimum). This file declares CLAUDE.md-specific structure and size constraints.

## Purpose

CLAUDE.md provides concise project context for Claude. It is:

- **A knowledge base guide** - Points to detailed documentation
- **Not full documentation** - Avoids context bloat
- **Always loaded** - Sent with every conversation

## Size Constraints

| Level | Recommended | Maximum |
|-------|-------------|---------|
| Lines | < 150 | 300 |
| Tokens | < 2k | 4k |

**Why:** CLAUDE.md is loaded in every conversation. Large files waste context that could be used for actual work.

## Structure Pattern

```markdown
# Project Name

Brief project description (1-2 sentences).

## Tech Stack

- Frontend: [framework, key libraries]
- Backend: [framework, database]
- Infrastructure: [hosting, CI/CD]

## Project Structure

```
src/
├── components/    # React components
├── services/      # Business logic
└── utils/         # Shared utilities
```

## Critical Conventions

### [Convention Category 1]

- Rule 1
- Rule 2

### [Convention Category 2]

- Rule 1
- Rule 2

## Key Commands

```bash
npm run dev       # Start development
npm run test      # Run tests
npm run build     # Production build
```

## Documentation

- [Deployment Guide](.context/references/deployment/00-index.md)
- [API Reference](.context/docs/api/00-index.md)

## Important Notes

[Any critical information that doesn't fit above]
```

## What to Include

### Always Include

| Section | Content |
|---------|---------|
| Tech Stack | Languages, frameworks, key dependencies |
| Project Structure | High-level directory layout |
| Key Commands | Common development tasks |
| Critical Conventions | Rules that affect every change |

### Include When Relevant

| Section | When to Include |
|---------|-----------------|
| Architecture Overview | Complex multi-service projects |
| Database Notes | Projects with complex data models |
| Testing Approach | Projects with specific testing requirements |
| Documentation Links | When detailed docs exist elsewhere |

## What NOT to Include

### Never Include

- API keys or secrets
- Passwords or credentials
- Full API documentation
- Complete setup guides
- Verbose explanations
- Changelog or version history

### Move Elsewhere

| Content | Where It Belongs |
|---------|------------------|
| Deployment steps | `.context/references/deployment/` |
| API reference | `.context/docs/api/` |
| Library guides | `.context/docs/<library>/` |
| Architecture deep-dive | `.context/references/architecture/` |

## Project Context Directory (.context/)

CLAUDE.md should link to `.context/` for detailed documentation instead of inlining content:

### Canonical types (recognized by aidex)

All canonical types are **optional** — create only when relevant. Their **absence is not a problem**, and a canonical directory that exists but is empty also indicates health, not bloat. Auditors must NOT suggest deleting an empty canonical directory.

| Directory | Purpose |
|-----------|---------|
| `.context/references/` | Project-specific guides (deployment, architecture, setup) |
| `.context/docs/` | Library/dependency documentation |
| `.context/plans/` | Implementation plans with checkbox tracking |
| `.context/backlog/` | Pending work items, tech debt |
| `.context/research/` | Spikes, analysis, exploration |
| `.context/issues/` | Bugs, problems, and their fixes (see structure below) |
| `.context/roadmap/` | Project phases, milestones, what's next |
| `.context/requests/` | Change requests, meeting notes, external asks |
| `.context/decisions/` | Architectural / product decisions (status: `accepted` / `superseded` / `dropped`) |
| `.context/audits/` | Audit runs grouped by methodology (`audits/<methodology>/{00-methodology.md, 00-inventory.md, 00-changelog.md, <run>/}`) |
| `.context/loops/` | Agentic-loop specs (goal + stop condition + guardrails) |
| `.context/communications/` | Logged/drafted emails, meetings, calls (native language) |

### Acceptable non-canonical types

These are valid when needed but not recognized by aidex auditors. Acceptable if **gitignored** OR **documented in CLAUDE.md** with their purpose.

| Directory | Typical use |
|-----------|-------------|
| `.context/drafts/` | In-progress writing not yet ready for a canonical home |
| `.context/experiments/` | Throwaway exploration, prototypes |
| `.context/data/` | Sample data, fixtures, exported artifacts |
| `.context/diagrams/` | Diagram sources/exports (Mermaid, drawio, images) |

If an empty directory is **not** in either list above, the auditor may suggest removing it.

### Issues Structure

Issues include bugs and their fixes in a single file. Each issue tracks the full lifecycle:

```markdown
# ISSUE-NNN: Brief title

**Status:** open | investigating | fixed
**Severity:** critical | high | medium | low
**Date:** YYYY-MM-DD
**Fixed:** YYYY-MM-DD (when resolved)

## Problem
What's happening and how to reproduce.

## Root Cause
Why it happens (filled during investigation).

## Fix
What was done to resolve it (filled when fixed).
```

Naming: `ISSUE-NNN-brief-description.md` with `00-index.md` as registry.

### Roadmap Structure

Roadmap organizes work into phases or milestones:

```
.context/roadmap/
├── 00-index.md            # Overview + current phase
├── 00-phase-name.md       # Phase 0 details
├── 01-phase-name.md       # Phase 1 details
└── ...
```

Each phase file describes scope, deliverables, and status (planned/in-progress/done).

### Requests Structure

Change requests, meeting notes, and external asks:

```
.context/requests/
├── YYYY-MM-DD-brief-description.md
└── _archive/              # Completed/rejected requests
```

Filename date format is `YYYY-MM-DD` per D-01 ([`00-global.md` §1](00-global.md#1-naming--dates-d-01)).

**Rule:** If a section in CLAUDE.md grows beyond 10 lines, move it to `.context/` and replace with a link.

## Scratch Output (`_tmp/`)

`.context/` is for artifacts worth keeping. Ephemeral session output — verification screenshots, diagnostic probes, consumed sync reports, scratch files — goes in **`_tmp/` at the project (or workspace) root**. That name is canonical: it was the de-facto convention in every workspace surveyed (2026-07-24), so this codifies practice rather than inventing a name.

Seed it with this README (`init-context.sh` writes it for new projects, skip-if-exists):

```markdown
# _tmp — Disposable Artifacts

Single destination for ephemeral session output: verification screenshots,
diagnostic probes, consumed sync reports, scratch files.

**Contract**: anything in this folder can be deleted at any time without asking.
Do NOT create new ad-hoc folders at the workspace root for temporary artifacts.

If an artifact turns out to document a specific audit finding or bug worth
keeping long-term, move it into that audit's run folder
(`.context/audits/<methodology>/<run>/`) instead of leaving it here.
```

- **One bucket, one name.** No `.scratch/`, `tmp/`, `temp/`, `scratch/`, and no scratch directories inside `.context/`.
- **Scope: the project tree.** The rule forbids *inventing* a second scratch bucket under the project (or workspace) root. A harness-supplied session scratchpad is not one — it lives outside the project, is session-scoped, and is cleaned up by the harness. Write there when the harness itself owns the file's lifetime: the generated `.workflow.js` is the standing case, because the `Workflow` tool persists the script under the session directory and `resumeFromRunId` only resolves within that session, so relocating it to `_tmp/` would fight the tool that reads it. Everything whose lifetime the *project* owns still goes to `_tmp/`.
- **Deletable without asking.** That is the whole contract — nothing in `_tmp/` may be load-bearing.
- **Gitignore the contents, track the contract**: `_tmp/*` plus `!_tmp/README.md`.
- **Promotion is forward-looking.** When a scratch file turns out to be the evidence for a specific finding, move it at that moment into the audit run folder, or into `.context/proofs/<slug>/` when it backs a `proof_links` claim ([`00-global.md` §7.1](00-global.md)). Existing scratch buckets are never retro-classified by correlating dates and content — that is expensive and error-prone.

## Referencing Resources

### Link to Detailed Documentation

```markdown
## Documentation

- [Deployment Guide](.context/references/deployment/00-index.md)
- [Payload CMS Patterns](.claude/skills/payload-cms/SKILL.md)
- [Testing Conventions](.context/references/testing/00-index.md)
```

### Import Patterns

For very long project instructions, use rules directory:

```markdown
## Extended Guidelines

See `.claude/rules/` for additional project-specific rules.
```

Files in `.claude/rules/` are auto-loaded by Claude Code.

## Global vs Project CLAUDE.md

### Global (~/.claude/CLAUDE.md)

Contains:
- Personal preferences
- Cross-project conventions
- Skill usage tracking
- Global tool configurations

Example:
```markdown
# Global Rules & Preferences

## Git & Commits
- Do not add co-authorship in commits

## Workflow
- Always create plans before major changes

## Skill Usage Tracking
- Mention skills used at end of responses
```

### Project (.claude/CLAUDE.md)

Contains:
- Project-specific tech stack
- Project conventions
- Links to project documentation
- Project-specific commands

## Writing Guidelines

### Be Concise

```markdown
# Good
- Use TypeScript strict mode
- Run `npm test` before commits

# Bad
- We use TypeScript with strict mode enabled because it helps catch errors at compile time and improves code quality
- Before committing any changes, please run the test suite using npm test to ensure nothing is broken
```

### Use Lists Over Paragraphs

```markdown
# Good
## Conventions
- Prefix components with `App`
- Use `kebab-case` for files
- Export from index files

# Bad
## Conventions
Our project follows specific naming conventions. Components should be prefixed with App. File names use kebab-case format. We export all modules from index files.
```

### Structure for Scanning

Use clear headings that Claude can quickly parse:
- `## Tech Stack`
- `## Key Commands`
- `## Critical Conventions`
- `## Documentation`

## Validation Rules

### Size Checks

- [ ] Under 300 lines
- [ ] No verbose explanations
- [ ] No duplicated information

### Security Checks

- [ ] No API keys
- [ ] No passwords
- [ ] No tokens
- [ ] No credentials

### Structure Checks

- [ ] Has Tech Stack section
- [ ] Has Key Commands section
- [ ] Uses headings effectively
- [ ] Lists over paragraphs

### Reference Checks

- [ ] Links to detailed docs (not inline)
- [ ] All referenced files exist
- [ ] No orphaned sections

### Quality Checks

- [ ] Concise language
- [ ] Actionable content
- [ ] No outdated information
