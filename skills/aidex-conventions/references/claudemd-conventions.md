# CLAUDE.md Conventions

Standards for creating effective CLAUDE.md project context files.

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
├── README.md              # Overview + current phase
├── 00-phase-name.md       # Phase 0 details
├── 01-phase-name.md       # Phase 1 details
└── ...
```

Each phase file describes scope, deliverables, and status (planned/in-progress/done).

### Requests Structure

Change requests, meeting notes, and external asks:

```
.context/requests/
├── YYYYMMDD-brief-description.md
└── _archive/              # Completed requests
```

**Rule:** If a section in CLAUDE.md grows beyond 10 lines, move it to `.context/` and replace with a link.

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
