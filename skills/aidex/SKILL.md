---
name: aidex
description: AI ecosystem orchestrator — audits and fixes .context/, skills, symlinks, MEMORY.md, CLAUDE.md, and the skill registry. Use this skill whenever the user asks to audit project health, check documentation freshness, find broken symlinks, clean up MEMORY.md, list or inventory installed skills, verify CLAUDE.md links, reorganize .context/ structure, detect stale or outdated references, check skill relevance for the current project stack, or optimize their Claude Code ecosystem. Also activates when the user says their project is messy, disorganized, or needs cleanup. Triggers on /aidex. Do NOT use for creating documentation — use aidex-conventions instead.
disable-model-invocation: false
---

# Aidex — Ecosystem Orchestrator

Single entry point for auditing, diagnosing, and fixing the AI assistant ecosystem.

## What It Covers

| Domain | Location | What it checks |
|--------|----------|---------------|
| **Context structure** | `.context/` | References, docs, plans, backlog, issues, roadmap, requests, decisions — numbering, metadata, index coverage, reorganization suggestions |
| **Skills** | `.claude/skills/`, `~/.claude/skills/`, `~/.aidex/skills/` | Frontmatter, size, structure, scope placement |
| **Symlinks** | `.claude/skills/*`, `.claude/commands/*` | Targets exist, no broken/orphan links |
| **MEMORY.md** | `.claude/` or project root | Bloat, stale entries, inline content, externalization |
| **CLAUDE.md** | `.claude/CLAUDE.md` or `./CLAUDE.md` | Size, security, structure, stale references |
| **Registry** | `~/.aidex/skill-registry.json` | Stack detection, skill relevance, noise, migration candidates |
| **Freshness** | `.context/references/`, `.context/docs/` | Last Updated vs recent commits, stale content |

---

## Phase 0: Discovery

Before launching any subagent, scan what exists in the project:

```
Check for:
- .context/ (references/, docs/, plans/, backlog/, issues/, roadmap/, requests/, decisions/)
- .claude/ (skills/, CLAUDE.md, MEMORY.md)
- ~/.aidex/ (shared skills, registry)
- ~/.claude/skills/ (global skills)
```

Build a quick inventory of what exists and its size. This determines which agents to launch.

**If nothing exists:** Suggest initializing with `aidex-conventions` patterns (create `.context/`, etc.)

---

## Phase 1: Parallel Audit

**CRITICAL: Launch ALL applicable agents in a SINGLE message with multiple Agent tool calls.** Each agent runs with `run_in_background: true` so they execute in parallel. Do NOT launch them sequentially.

Read each agent's instructions from `~/.aidex/skills/aidex/agents/` and pass them as the prompt. Include the project path in each prompt.

| Subagent | Launches when | Model | Tools |
|----------|--------------|-------|-------|
| [context-auditor](agents/context-auditor.md) | `.context/` exists | haiku | Read, Glob, Grep |
| [skills-auditor](agents/skills-auditor.md) | `.claude/skills/` exists | haiku | Read, Glob, Grep |
| [symlink-checker](agents/symlink-checker.md) | Any symlinks found | haiku | Read, Glob, Bash |
| [memory-auditor](agents/memory-auditor.md) | MEMORY.md exists and >50 lines | haiku | Read, Glob, Grep |
| [freshness-checker](agents/freshness-checker.md) | `.context/references/` or `.context/docs/` exist | sonnet | Read, Glob, Grep, Bash |
| [registry-builder](agents/registry-builder.md) | `~/.aidex/skills/` exists | sonnet | Read, Glob, Grep, Bash |

Example launch pattern (all in one message):
```
Agent(description="Audit .context/ structure", model=haiku, run_in_background=true, prompt="[context-auditor instructions + project path]")
Agent(description="Audit skills", model=haiku, run_in_background=true, prompt="[skills-auditor instructions + project path]")
Agent(description="Check symlinks", model=haiku, run_in_background=true, prompt="[symlink-checker instructions + project path]")
Agent(description="Scan registry", model=sonnet, run_in_background=true, prompt="[registry-builder instructions + project path]")
```

**Wait for ALL launched agents to complete before proceeding to Phase 2.**

Also check inline (no subagent needed):
- CLAUDE.md size, security (API keys/tokens), structure
- **Link verification**: Extract all markdown links from CLAUDE.md. For each link to a local file (`.context/`, `.claude/`, relative paths), verify the target file exists. Report broken links as WARNING.
- **Anti-pattern detection**: If CLAUDE.md links to a `README.md` inside `references/` or `docs/`, flag as WARNING — convention says each module has `00-index.md` and CLAUDE.md is the entry point. The README is redundant.
- Cross-domain: skills referenced in CLAUDE.md exist? References mentioned in skills exist?

---

## Phase 2: Synthesize & Report

Collect all subagent reports. Produce unified report:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ECOSYSTEM AUDIT — [Project Name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Summary
| Domain | Items | ❌ | ⚠️ | ℹ️ |
|--------|-------|----|----|----|
[one row per domain audited]

## Findings
[grouped by domain, severity-ordered]

## Health Score
[X]% (100% = no issues, -10 per critical, -3 per warning)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 3: Suggest Actions

After the report, present actionable suggestions grouped by priority. **Be prescriptive, not just descriptive** — suggest the aidex way of organizing things, explain why, and let the user decide.

```
❌ Critical (fix now):
  1. [description] → [what aidex will do]

⚠️  Recommended:
  2. [description] → [what aidex will do]
  3. Deep-sync [stale reference] → launches sync subagent
  4. Migrate [N] irrelevant skills → removes global symlinks

💡 Reorganize:
  5. Consolidate bugs/ + fixes/ → issues/ with ISSUE-NNN format
  6. Remove references/README.md — modules have 00-index.md, CLAUDE.md is entry point
  7. Create .context/roadmap/ — project has active phases but no roadmap
  8. Restructure issues/ files to ISSUE-NNN with status+root cause+fix

ℹ️  Optional:
  9. [description]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [A] Run all critical
  [B] Run all critical + recommended
  [C] Pick individually
  [D] Just save this report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 4: Execute

For each approved action, execute directly or launch a specialized subagent:

**Direct execution (simple fixes):**
- Fix broken symlinks (remove or recreate)
- Add missing index links
- Add missing metadata headers
- Archive completed plans
- Remove stale MEMORY.md entries
- Condense inline MEMORY.md content to links

**Subagent execution (complex operations):**
- Deep-sync stale references → sonnet subagent with WebFetch + Context7
- Memory cleanup (full workflow) → haiku subagent
- Skill migration → sonnet subagent with Bash for symlink operations

**Destructive actions (per-item approval):**
- Delete orphaned files
- Remove skills
- Trim duplicated content

After execution, show before/after summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Audit complete. Health: [before]% → [after]%
  Next suggested audit: in ~20 conversations
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Context-Triggered Behavior

Besides explicit invocation (`/aidex`), this skill also activates when:

- Claude notices a broken symlink while reading `.claude/skills/`
- MEMORY.md is loaded and exceeds 80 lines
- A referenced file in a skill doesn't exist
- User asks about "project health", "ecosystem", "organize skills", "clean up"

In context-triggered mode, suggest a focused audit rather than a full one:
```
"I noticed MEMORY.md is 95 lines (target: <80). Want me to run a quick cleanup?"
```

---

## References

- [01-context-checks.md](references/01-context-checks.md) — Detailed .context/ audit checks (A-F)
- [02-skills-checks.md](references/02-skills-checks.md) — Skills audit checks (A-J) and scope decision matrix
- [03-memory-workflow.md](references/03-memory-workflow.md) — Memory classification and externalization workflow
- [04-registry-operations.md](references/04-registry-operations.md) — Registry scan, recommend, migrate operations
- [05-fix-procedures.md](references/05-fix-procedures.md) — Safe and destructive fix procedures
