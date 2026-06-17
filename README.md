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

### Pillar 1: Assistant Configuration (storage + symlinks + per-project overrides)

```
~/.aidex/                                <-- Canonical storage
├── .manifest                            <-- Tracks what aidex installed
├── rules/                               <-- Global session rules (auto-loaded by Claude Code)
│   └── aidex-conventions.md             <-- .context/ conventions canon (from aidex)
└── skills/
    ├── aidex/                       <-- The orchestrator (from aidex)
    ├── aidex-conventions/           <-- Canon hub, non-invocable (from aidex)
    ├── aidex-plan/                  <-- (from aidex)
    ├── aidex-decision/              <-- (from aidex)
    ├── aidex-request/               <-- (from aidex)
    ├── aidex-research/              <-- (from aidex)
    ├── aidex-reference/             <-- (from aidex)
    ├── aidex-skill/                 <-- (from aidex)
    ├── aidex-audit/                 <-- (from aidex)
    ├── aidex-backlog/      <-- (from aidex)
    ├── aidex-loop/                  <-- (from aidex)
    ├── aidex-comm/                  <-- (from aidex)
    ├── aidex-plan-exec/              <-- (from aidex)
    ├── aidex-bugfix/            <-- (from aidex)
    └── my-personal-skill/           <-- Your own (not in manifest)
        │
        │  symlinks
        ▼
~/.claude/skills/                        <-- What Claude Code reads
├── aidex -> ~/.aidex/skills/aidex
├── aidex-conventions -> ~/.aidex/skills/aidex-conventions
├── aidex-plan, aidex-decision, … -> ~/.aidex/skills/<each aidex skill>
├── my-personal-skill -> ~/.aidex/skills/my-personal-skill
└── ...

project/.claude/skills/                  <-- Project-specific (real files)
└── local-only-skill/SKILL.md

project/.claude/settings.local.json      <-- Per-project skill silencing
{ "skillOverrides": { "noisy-skill": "off", "doc-skill": "name-only" } }
```

| Scope | Location | Loaded in | Use for |
|-------|----------|-----------|---------|
| **Global** | `~/.aidex/skills/` symlinked into `~/.claude/skills/` | All projects | Personal + reusable skills |
| **Local** | `project/.claude/skills/` | That project only | Project-specific |
| **Per-project silencing** | `project/.claude/settings.local.json` `skillOverrides` | That project only | Hide a global skill where it's noise — values: `name-only`, `user-invocable-only`, `off`. Shipped in Claude Code 2.1.131. |

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
├── decisions/       # Architecture/product decision records
├── audits/          # Project-state catalogs (INVENTORY + per-run folders)
├── loops/           # Agentic-loop specs (goal + verifiable gate + guardrails)
└── communications/  # Inbound/outbound comms log (received/ + sent/, native language)
```

## What's included

### Global rule

`rules/aidex-conventions.md` is installed to `~/.aidex/rules/` and is auto-loaded by Claude Code into every session. It's a short normative summary (NEVER/ALWAYS) of the `.context/` conventions — date format, language, naming, status vocabulary, archive policy. The full canon lives in the `aidex-conventions` skill.

### 14 skills

| Skill | Type | What it does |
|-------|------|-------------|
| **`aidex`** | User-invoked + context-triggered | The orchestrator. Audits the Claude Code ecosystem — `.context/` (including `audits/`), skills, symlinks, MEMORY.md, plugins, and the session's idle context budget. Launches parallel subagents, reports findings, suggests and applies fixes. |
| **`aidex-conventions`** | Passive canon hub (non-invocable) | The canon. Full `.context/` and skill conventions that the invocable siblings below cite. Degraded to a non-invocable reference hub — it no longer auto-triggers; the siblings carry the triggers. |
| **`aidex-plan`** | User-invoked + context-triggered | Creates `.context/plans/` — multi-phase implementation plans with numbered files, phases, and checkbox tracking. |
| **`aidex-decision`** | User-invoked + context-triggered | Records `.context/decisions/` ADRs — what was chosen, why, the alternatives, and the consequences. |
| **`aidex-request`** | User-invoked + context-triggered | Captures incoming stakeholder/client requests into `.context/requests/` before anyone acts on them. |
| **`aidex-research`** | User-invoked + context-triggered | Investigation and spike notes into `.context/research/` before a plan or implementation. |
| **`aidex-reference`** | User-invoked + context-triggered | Evergreen how-it-works documentation into `.context/references/` (architecture, runbooks, configuration). |
| **`aidex-skill`** | User-invoked + context-triggered | Checks and structures a skill against this project's house skill conventions. |
| **`aidex-audit`** | User-invoked + context-triggered | Operates `.context/audits/`. Sub-actions: `/aidex-audit new <type> <slug>` · `/aidex-audit validate` · `/aidex-audit escalate <id>` · `/aidex-audit migrate`. Ships 6 playbooks (ux, ia-opportunities, retest, security, perf, a11y). |
| **`aidex-backlog`** | User-invoked + context-triggered | Creates consistent entries in `.context/backlog/` with origin tracking. Called by `/aidex-audit escalate` to close the audit→backlog loop. |
| **`aidex-loop`** | User-invoked + context-triggered | Designs agentic loops — writes a `.context/loops/` loop-spec (goal + verifiable gate + state file + guardrails + engine), then hands off execution to native `/goal`, `/loop`, the ralph-loop plugin, or `claude -p`. Sub-actions: `/aidex-loop design` · `new` · `run`. |
| **`aidex-comm`** | User-invoked + context-triggered | Captures inbound/outbound communications into `.context/communications/{received,sent}/` — emails, WhatsApp, calls, meetings — with channel/direction/from/to front-matter. Body stays in the native language of the communication (exempt from English-only). |
| **`aidex-plan-exec`** | User-invoked + context-triggered | Executes a written multi-phase plan (typically a `.context/plans/` doc) phase-by-phase, enforcing between-phase discipline: code-review, commit, and handoff when context grows. Routes back to `aidex-plan` for plan creation. |
| **`aidex-bugfix`** | User-invoked + context-triggered | Guided TDD bug fixing: investigate → write a RED regression test → fix → GREEN → commit test and fix together. Detects test runners from project config; stack-agnostic. |

### How it works

**Creating things** — just ask naturally:
```
"Create a plan for the auth migration"
→ Claude loads aidex-plan, creates .context/plans/20260402-auth-migration/
  with numbered files, phases, checkboxes, following all conventions

"Create a reference for the payment API"  
→ Claude loads aidex-reference, creates .context/references/payment-api/
  with 00-index.md + 01-overview.md

"/aidex-audit new ux login-redesign"
→ Scaffolds .context/audits/20260402-login-redesign/ with index, findings,
  and materializes INVENTORY/METHODOLOGY/CHANGELOG + ux-audit playbook on first use
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
  - plugin-auditor (haiku): flags unused plugin agents
  - context-cost-analyzer (haiku): attributes idle token cost

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
