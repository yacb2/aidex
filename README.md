# aidex

> Keep your Claude Code ecosystem lean and consistent — skills, docs, and project context from one source of truth.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.29.0-blue.svg)](install.sh)
[![Built for Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-8A2BE2.svg)](https://docs.anthropic.com/en/docs/claude-code)

AI coding assistants reload their context every session. As your setup grows, skills get copy-pasted across projects and drift out of sync, every project organizes its `.context/` knowledge differently, and idle context quietly eats your token budget. **aidex** fixes that with a single-source skill store (symlinked, never duplicated), a standard `.context/` convention, and an auditor that flags bloat, broken symlinks, and stale docs before they cost you.

Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), but the architecture is tool-agnostic.

## Quick start

```bash
git clone https://github.com/yacb2/aidex.git
cd aidex && ./install.sh      # copies to ~/.aidex/, symlinks into ~/.claude/
# restart Claude Code
```

Then, in any project, just ask naturally — the right skill loads itself:

- *"Create a plan for the auth migration"* → scaffolds `.context/plans/…` with phases + checkboxes
- *"Audit my project's health"* → runs parallel auditors, returns a health score + suggested fixes
- *"/aidex-audit new ux login-redesign"* → scaffolds a UX audit with a methodology playbook
- *"/aidex init"* → bootstraps the `.context/` skeleton in a project that doesn't have one yet
- *"Render the backlog as an HTML board"* → `aidex-dash` generates a sortable, self-contained page

Something not firing? Run `./install.sh --doctor` from the repo checkout to health-check the install (symlinks, versions, exec bits, manifest).

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
├── rules/                               <-- Global session rules (symlinked into ~/.claude/rules/)
│   ├── aidex-conventions.md             <-- .context/ conventions canon (from aidex)
│   ├── autonomy.md                      <-- front-loaded autonomy: run start-to-finish (from aidex)
│   ├── artifacts-local-first.md         <-- local-first artifact contract (from aidex)
│   ├── database-protection.md           <-- destructive DB ops: real vs disposable (from aidex)
│   ├── e2e-testing.md                   <-- E2E targets a disposable DB (from aidex)
│   ├── memory-hygiene.md                <-- one file, one live fact; index budget (from aidex)
│   ├── verification-before-claims.md    <-- no completion claim without output (from aidex)
│   └── root-cause-first.md              <-- investigate before fixing (from aidex)
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
    ├── aidex-workflow/              <-- (from aidex)
    ├── aidex-worktree/              <-- (from aidex)
    ├── aidex-dash/                 <-- (from aidex)
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

### Global rules

Seven always-on rules are installed to `~/.aidex/rules/` and symlinked into `~/.claude/rules/` — the sole load surface, so nothing under `~/.aidex/` loads by itself. Each is a short normative summary (NEVER/ALWAYS); the full canon lives in the `aidex-conventions` skill.

| Rule | What it governs |
|------|-----------------|
| `aidex-conventions.md` | `.context/` conventions — date format, language, naming, status vocabulary, cross-references, archive policy |
| `autonomy.md` | Front-loaded autonomy: an unattended run asks its questions up front and then runs start to finish; only publishing (push/deploy/release) is gated |
| `artifacts-local-first.md` | Any requested artifact/report/dashboard is written locally first, anchored next to the work it documents, and published only when explicitly asked |
| `database-protection.md` | Destructive DB operations, split by target: **real** databases are never destroyed unattended and are not pre-authorizable; **disposable** ones (E2E clones, per-worktree throwaways) are routine work |
| `e2e-testing.md` | E2E runs against a **disposable** database, never a real one or the dev environment. The target gates, not the filename — no `test-e2e.sh` means establish a throwaway environment first, not fall back to dev |
| `memory-hygiene.md` | What qualifies as a memory versus a session log, the per-memory and always-on index word budgets, and eviction of work that closed. Audited read-only by `skills/aidex/scripts/memory-sweep.py` |
| `verification-before-claims.md` | No "tests pass" / "build succeeds" / "bug is fixed" without running the command and showing output; partial-success commands need before/after counts, not just exit code 0 |
| `root-cause-first.md` | Investigate before fixing, form a hypothesis before implementing, and after three failed attempts stop and question the architecture |

### 18 skills

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
| **`aidex-audit`** | User-invoked + context-triggered | Operates `.context/audits/`. Sub-actions: `/aidex-audit new <type> <slug>` · `/aidex-audit validate` · `/aidex-audit escalate <id>` · `/aidex-audit migrate` · `/aidex-audit coverage-matrix` · `/aidex-audit coverage-sweep` · `/aidex-audit affected-tests`. Ships 8 playbooks (ux, ai-opportunities, retest, security, perf, a11y, hitl, test-coverage). `affected-tests` also names any changed file that measurably breaks and has no E2E reaching it, before the change lands. |
| **`aidex-backlog`** | User-invoked + context-triggered | Creates consistent entries in `.context/backlog/` with origin tracking. Called by `/aidex-audit escalate` to close the audit→backlog loop. Also scores closed items' `estimate:` against the effort they actually cost — a read that gates nothing. |
| **`aidex-loop`** | User-invoked + context-triggered | Designs agentic loops — writes a `.context/loops/` loop-spec (goal + verifiable gate + state file + guardrails + engine), then hands off execution to native `/goal`, `/loop`, the ralph-loop plugin, or `claude -p`. Sub-actions: `/aidex-loop design` · `new` · `run`. |
| **`aidex-workflow`** | User-invoked + context-triggered | Designs one-shot multi-agent fan-out / decomposition orchestrations — writes a `.context/workflows/` spec (goal + fan-out shape + per-agent model table + gate policy) before the Workflow runs. |
| **`aidex-comm`** | User-invoked + context-triggered | Captures inbound/outbound communications into `.context/communications/{received,sent}/` — emails, WhatsApp, calls, meetings — with channel/direction/from/to front-matter. Body stays in the native language of the communication (exempt from English-only). |
| **`aidex-plan-exec`** | User-invoked + context-triggered | Executes a written multi-phase plan (typically a `.context/plans/` doc) phase-by-phase, enforcing between-phase discipline: code-review, commit, and handoff when context grows. Routes back to `aidex-plan` for plan creation. |
| **`aidex-review`** | User-invoked + context-triggered | Reviews code **as it stands** — a module, feature, path, or whole app — where every built-in instrument (`/code-review`, `/simplify`, `/security-review`) is anchored to a diff. Measures the target first (`resolve-review-target.sh`: files, LOC, security/perf surface, size class), proposes which finder angles are worth launching and what they cost, then fans out find→verify across four lenses (correctness · simplify · security · perf). Refuses an oversize target instead of sampling it. |
| **`aidex-bugfix`** | User-invoked + context-triggered | Guided TDD bug fixing: investigate → write a RED regression test → fix → GREEN → commit test and fix together. Detects test runners from project config; stack-agnostic. |
| **`aidex-worktree`** | User-invoked + context-triggered | Bootstraps and advises git-worktree setups — decides isolate-vs-share for env/DB/ports via topology detection plus a 4-axis interview, recording it in `.context/worktrees/`. |
| **`aidex-dash`** | User-invoked + context-triggered | Renders `.context/` boards as self-contained interactive HTML (backlog board, plan progress, audit inventory, coverage matrix) via deterministic scripts — ~0 recurring tokens; markdown stays canon, HTML is a regenerable sibling render. Never publishes unprompted; opens locally via `file://`, and can be published as a Claude Code Artifact only on explicit request. |

### How it works

**Creating things** — just ask naturally:
```
"Create a plan for the auth migration"
→ Claude loads aidex-plan, creates .context/plans/2026-04-02-auth-migration/
  with numbered files, phases, checkboxes, following all conventions

"Create a reference for the payment API"  
→ Claude loads aidex-reference, creates .context/references/payment-api/
  with 00-index.md + 01-overview.md

"/aidex-audit new ux login-redesign"
→ Scaffolds .context/audits/ux/2026-04-02-login-redesign/ with index, findings,
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
git clone https://github.com/yacb2/aidex.git
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

### Health check

```bash
./install.sh --doctor
```

Deterministic install diagnosis — checks the installed version against the repo, broken skill symlinks in `~/.claude/skills/`, executable bits on skill scripts, `python3` availability, `.manifest` integrity, and hook presence. Exit `0` = healthy; exit `1` lists exactly what to fix. Run it first whenever a skill "doesn't fire".

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
