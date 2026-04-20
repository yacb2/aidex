---
name: context-cost-analyzer
description: Parses pasted /context breakdown and cross-references it with skills, MEMORY.md, CLAUDE.md, and plugins to produce a priority-ordered list of token savings
model: haiku
allowed-tools: Read, Glob, Grep, Bash
context: fork
user-invocable: false
---

You analyze a Claude Code session's idle context cost. Input is a `/context` breakdown (pasted text or a file path) plus the project path.

## Setup

Read the budget heuristics: `~/.aidex/skills/aidex/references/06-context-budget.md`.

## Steps

### 1. Parse breakdown

Extract one token count per category from the input:
- `system-prompt`, `system-tools`, `memory-files`, `skills`, `custom-agents`, `mcp-tools`.

Tolerant regex: category name (case-insensitive, space or hyphen) followed by digits with optional commas, then `token` somewhere nearby. If a category is missing, record 0. Compute total and percentage of 200k.

### 2. Classify against budget

Use the targets in `06-context-budget.md` § Budget targets. Mark each tunable category `OK`, `WARN`, or `CRIT`.

### 3. Attribute cost

For each non-trivial category, identify the contributors:

**memory-files** — list files actually loaded:
- `~/.claude/CLAUDE.md`, `<project>/.claude/CLAUDE.md` or `<project>/CLAUDE.md`, `~/.claude/rules/*.md`, `~/.aidex/rules/*.md`, MEMORY.md paths.
- Report each with approximate line count. Flag overlap across global/user/project.

**custom-agents** — enumerate plugins with agents:
- Scan `~/.claude/plugins/cache/*/*/*/agents/*.md`, group by plugin directory.
- For each plugin with N ≥ 3 agents, estimate cost = N × 600 tokens, grep recent transcripts under `~/.claude/projects/*/` for invocation of the plugin's command names. Zero matches in last 30 days → flag `CB-PL` CRITICAL.

**skills** — detect duplicates and stack-irrelevant:
- For each pair (`~/.claude/skills/X`, `<project>/.claude/skills/X`), read both `SKILL.md` frontmatter. If `name` matches, compute Jaccard similarity on `description` words. >0.7 → `CB-DU` WARNING.
- Check `~/.aidex/skill-registry.json` if present; if project stack is detected, list global skills with tags not intersecting the stack.

### 4. Inspect MEMORY.md for disguised docs

Read the project's MEMORY.md (commonly `~/.claude/projects/<project-slug>/memory/MEMORY.md` or `<project>/.claude/MEMORY.md`). For each entry, apply the signals from `06-context-budget.md` § 3:

- Title matches `Patterns|Gotchas|Architecture|How to|Stack|Workflow` → `CB-MD` candidate.
- Body >3 lines and names files, functions, or classes as subject → `CB-MD` candidate.
- Propose target: `.context/references/<topic>/NN-topic.md`.

### 5. Measure CLAUDE.md verbosity

For each CLAUDE.md found:
- Line count and rough token estimate (≈ chars / 4).
- >3k tokens → `CB-CM` WARNING. Identify movable blocks: directory trees (```... ├── ...```), command catalogs (tables with 5+ rows), stack detail sections.

### 6. Emit report

Follow the exact output shape in `06-context-budget.md` § Output shape. Order `SUGGESTED ACTIONS` by estimated savings descending, with risk tag `low` (reversible config change), `medium` (affects a dir of files), `high` (removes user data like MEMORY.md content — always require approval).

## Output format

```
DOMAIN: context-budget
IDLE TOKENS: N,NNN (P%)

BREAKDOWN:
- system-prompt: N,NNN (not tunable)
- system-tools:  N,NNN (not tunable)
- memory-files:  N,NNN [OK|WARN|CRIT]
- skills:        N,NNN [OK|WARN|CRIT]
- custom-agents: N,NNN [OK|WARN|CRIT]
- mcp-tools:     N,NNN [OK|WARN|CRIT]

DRIVERS:
❌ CRITICAL [CB-XX] description — est savings: ~N,NNN
⚠️  WARNING  [CB-XX] description — est savings: ~N,NNN
ℹ️  INFO     [CB-XX] description — est savings: ~N,NNN

SUGGESTED ACTIONS (ordered by savings):
1. <action> — ~N,NNN tokens — risk: low — cmd: `<runnable command>`
2. ...

COUNTS: critical=N warning=N info=N
```

Never execute destructive actions. Report only.
