# aidex

Developer experience toolkit for organizing AI coding assistant ecosystems — skills, documentation structure, and project context.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but the architecture is tool-agnostic.

## What this solves

AI coding assistants load context into every session. As your tooling grows, you end up with:

- **Noise**: Stack-specific skills loading in every project
- **No organization**: No way to know which skills exist or when they were last updated
- **Duplication**: Same skill copied across projects, drifting out of sync
- **No project context structure**: Each project organizes its knowledge differently

aidex solves this with two pillars:

1. **Centralized assistant configuration** — Skills managed from a single source with symlinks
2. **Structured project context** — A `.context/` convention for organizing project knowledge

## Architecture

### Pillar 1: Assistant Configuration (3 Scopes + Symlinks)

```
~/.aidex/                                <-- Installed copy (shared skills)
├── .manifest                            <-- Tracks what aidex installed
├── skills/
│   ├── aidex/                           <-- The orchestrator (from aidex)
│   ├── aidex-conventions/               <-- Conventions (from aidex)
│   └── my-personal-skill/              <-- Your own (not in manifest)
└── skill-registry.json
        │
        │  symlinks
        ▼
~/.claude/skills/                        <-- What Claude Code reads
├── aidex -> ~/.aidex/skills/aidex
├── aidex-conventions -> ~/.aidex/skills/aidex-conventions
├── my-personal-skill -> ~/.aidex/skills/my-personal-skill
└── ...

project/.claude/skills/                  <-- Project-specific (opt-in)
├── gsap-core -> ~/.aidex/skills/gsap-core
└── local-only-skill/SKILL.md
```

| Scope | Location | Loaded in | Use for |
|-------|----------|-----------|---------|
| **Global** | `~/.claude/skills/` (symlink) | All projects | Universal tools |
| **Library** | `~/.aidex/skills/` (no symlink) | Only projects that opt-in | Stack-specific |
| **Local** | `project/.claude/skills/` | That project only | Project-specific |

### Pillar 2: Structured Project Context (`.context/`)

A standard directory structure for project knowledge:

```
project/.context/
├── references/      # Internal technical documentation
├── docs/            # Library/dependency documentation
├── plans/           # Implementation plans with checkbox tracking
├── backlog/         # Pending work items, tech debt
├── research/        # Spikes, analysis, exploration
├── issues/          # Known bugs, pending decisions
├── requests/        # Incoming tasks and product requirements
└── decisions/       # Architecture/product decision records
```

## What's included

### 2 skills — that's it

| Skill | Type | What it does |
|-------|------|-------------|
| **`aidex`** | User-invoked + context-triggered | The orchestrator. Audits `.context/`, skills, symlinks, MEMORY.md, registry. Launches parallel subagents, reports findings, suggests and applies fixes. |
| **`aidex-conventions`** | Context-triggered (passive) | The brain. Conventions for creating and structuring references, docs, plans, skills, and CLAUDE.md. Activates when Claude detects you're creating or working with documentation. |

### How it works

**Creating things** — just ask naturally:
```
"Create a plan for the auth migration"
→ Claude loads aidex-conventions, creates .context/plans/20260402-auth-migration/
  with numbered files, phases, checkboxes, following all conventions

"Create a reference for the payment API"  
→ Creates .context/references/payment-api/ with 00-index.md + 01-overview.md
```

**Auditing** — ask or invoke `/aidex`:
```
"Check my project's documentation health"
→ aidex launches parallel subagents:
  - context-auditor (haiku): checks .context/ structure
  - skills-auditor (haiku): checks skill frontmatter, structure
  - symlink-checker (haiku): verifies all symlinks
  - memory-auditor (haiku): checks MEMORY.md bloat
  - freshness-checker (sonnet): detects stale docs
  - registry-builder (sonnet): analyzes skill placement

→ Reports findings with health score
→ Suggests fixes: "Want me to clean MEMORY.md? Archive old plans? Fix broken symlinks?"
→ Executes what you approve
```

## Installation

```bash
# Clone the repo anywhere
git clone https://github.com/YACB2/aidex.git
cd aidex

# Install (copies to ~/.aidex/, creates symlinks in ~/.claude/)
chmod +x install.sh
./install.sh

# Restart Claude Code to load everything
```

### Updating

```bash
cd /path/to/aidex
git pull
./install.sh --update
```

The updater shows what changed and lets you choose: apply all, review each diff, or cancel. It only touches files it installed — your personal skills in `~/.aidex/` are never modified.

### Adding your own tools

```bash
# Create a skill directly in ~/.aidex/ (not managed by the repo)
mkdir ~/.aidex/skills/my-custom-skill
# ... add SKILL.md

# Make it global (loads in all projects)
ln -s ~/.aidex/skills/my-custom-skill ~/.claude/skills/my-custom-skill

# Or make it project-only
cd ~/projects/my-app
ln -s ~/.aidex/skills/my-custom-skill .claude/skills/my-custom-skill
```

## Uninstall

```bash
./install.sh --uninstall
```

Interactive: choose to remove only symlinks, aidex-managed files, or everything.

## License

MIT
