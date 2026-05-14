---
name: aidex
description: Audits and fixes the Claude Code ecosystem — skills, .context/ structure and conventions, symlinks, MEMORY.md, CLAUDE.md, plugins, and idle context budget. Triggers on /aidex, /aidex context, and natural asks like "audit my project / check my project's health / review the ecosystem / my project is messy / clean up MEMORY.md / find broken symlinks / stale documentation / check .context/ conventions / is my context folder consistent / audit my project's conventions / what skills do I have / verify CLAUDE.md links / reorganize .context/ / this project opens heavy / wastes too much context / reduce initial token cost / audit installed plugins / this skill doesn't apply to this stack / optimize my Claude Code setup / organize my ecosystem". Also auto-activates when Claude notices a broken symlink, MEMORY.md exceeds ~80 lines, or a referenced file in a skill is missing. Do NOT use for: creating documentation (plans, decisions, requests, references) → aidex-conventions; project-state audits (UX/security/perf/a11y) → audit; backlog entries → backlog-register.
disable-model-invocation: false
---

# Aidex — Ecosystem Orchestrator

Single entry point for auditing, diagnosing, and fixing the AI assistant ecosystem.

## What It Covers

| Domain | Location | What it checks |
|--------|----------|---------------|
| **Context structure** | `.context/` | References, docs, plans, backlog, issues, roadmap, requests, decisions, audits — numbering, metadata, index coverage, reorganization suggestions |
| **Skills** | `.claude/skills/`, `~/.claude/skills/`, `~/.aidex/skills/` | Frontmatter, size, structure, scope placement |
| **Symlinks** | `.claude/skills/*`, `.claude/commands/*` | Targets exist, no broken/orphan links |
| **MEMORY.md** | `.claude/` or project root | Bloat, stale entries, inline content, externalization |
| **CLAUDE.md** | `.claude/CLAUDE.md` or `./CLAUDE.md` | Size, security, structure, stale references |
| **Freshness** | `.context/references/`, `.context/docs/` | Last Updated vs recent commits, stale content |
| **Plugins** | `~/.claude/plugins/` | Always-loaded subagent cost vs. recent usage, uninstall candidates |
| **Context budget** | Session `/context` output | Idle token cost attribution across skills, MEMORY, CLAUDE.md, plugins, rules |

---

## Sub-action: `/aidex context`

Focused audit of the session's **idle token footprint** (everything loaded before the user types anything). Use when the user:

- Pastes `/context` output and asks why it's heavy.
- Reports a project opening at >20% context used.
- Asks to "reduce initial tokens", "audit plugins", or "why does this waste so much context".

### Inputs

- Pasted `/context` breakdown (text) OR path to a file containing it.
- Current project path (to locate project CLAUDE.md, local skills, MEMORY.md).

### Flow

1. **Parse** the breakdown inline (or defer to `context-cost-analyzer`). Surface idle total and per-category token counts immediately.
2. **Launch in parallel** (single message, `run_in_background: true`):
   - `context-cost-analyzer` — cross-references all drivers, produces priority-ordered savings list.
   - `plugin-auditor` — enumerates plugin agent cost vs. recent usage.
   - `memory-auditor` — focused on `CB-MD` (docs disguised as memory).
   - `skills-auditor` — focused on `CB-DU` (user↔project duplication) and `CB-SR` (stack relevance).
3. **Synthesize** a single report ordered by **estimated token savings descending**, annotating each with risk (low/medium/high).
4. **Never auto-execute**. Present runnable commands (`claude plugin uninstall ...`, `rm ...`, edit proposals) for user approval one by one.

Heuristics live in [references/05-context-budget.md](references/05-context-budget.md).

### Apply phase (optional)

After step 3 (synthesis), end with the menu `[A] apply all critical [B] apply all [C] pick individually [D] save report only`. If the user picks A/B/C, run this sequence:

1. **Write audit doc.** Save the full report to `.context/audits/YYYYMMDD-context-and-memory-optimization.md` using the project's audit conventions (delegate to the `audit` skill if available, else write directly).
2. **Backup.** Before any mutation, copy to `.aidex-backups/<timestamp>/`:
   - `settings.local.json` (project and user, if touched)
   - the entire memory directory
   - any SKILL.md files about to be edited
   Add `.aidex-backups/` to `.gitignore` if missing.
3. **Apply per-item.** Print a numbered diff and ask `apply? [y/n/skip]` per change. Never auto-apply. Patch order (highest savings first):
   - Plugin uninstall commands
   - SKILL.md `disable-model-invocation: true` flips for irrelevant skills
   - `settings.local.json` skillOverrides for `name-only` / `off`
   - Memory file deletes / MEMORY.md edits
   - CLAUDE.md trims
4. **Log.** Append each applied/skipped change to the audit doc's "Actions taken" section so the doc reflects final state.

**Guardrails for apply phase:**
- Always confirm per item. No batch apply without prompts.
- Never edit `feedback_*.md` files automatically (MEM-STALE is human-review only).
- Never delete large external trees outside the aidex-managed roots (`~/.aidex/`, `~/.claude/skills/`, `~/.claude/commands/`) — escalate to backlog instead.
- If `.context/decisions/` exists and an entry overlaps (MEM-DEC), prefer linking from MEMORY.md to the decision doc over deleting silently.
- For third-party plugin skills, do NOT propose `disable-model-invocation` flips — get overwritten on plugin update. Use `settings.local.json` overrides instead.

Memory-specific rules in [references/03-memory-workflow.md](references/03-memory-workflow.md).

---

## Phase 0: Discovery

Before launching any subagent, scan what exists in the project:

```
Check for:
- .context/ (references/, docs/, plans/, backlog/, issues/, roadmap/, requests/, decisions/, audits/)
- .claude/ (skills/, CLAUDE.md, MEMORY.md)
- ~/.aidex/ (shared skills storage)
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
| [conventions-auditor](agents/conventions-auditor.md) | `.context/` exists AND `~/.aidex/skills/aidex-conventions/scripts/validate.sh` is installed | haiku | Read, Bash |
| [skills-auditor](agents/skills-auditor.md) | `.claude/skills/` exists | haiku | Read, Glob, Grep |
| [symlink-checker](agents/symlink-checker.md) | Any symlinks found | haiku | Read, Glob, Bash |
| [memory-auditor](agents/memory-auditor.md) | MEMORY.md exists and >50 lines | haiku | Read, Glob, Grep |
| [freshness-checker](agents/freshness-checker.md) | `.context/references/`, `.context/docs/`, or `.context/roadmap/` exist | haiku | Read, Glob, Grep, Bash |
| [plugin-auditor](agents/plugin-auditor.md) | `~/.claude/plugins/installed_plugins.json` exists | haiku | Read, Glob, Grep, Bash |
| [context-cost-analyzer](agents/context-cost-analyzer.md) | User ran `/aidex context` or pasted `/context` output | haiku | Read, Glob, Grep, Bash |

Example launch pattern (all in one message):
```
Agent(description="Audit .context/ structure", model=haiku, run_in_background=true, prompt="[context-auditor instructions + project path]")
Agent(description="Audit skills", model=haiku, run_in_background=true, prompt="[skills-auditor instructions + project path]")
Agent(description="Check symlinks", model=haiku, run_in_background=true, prompt="[symlink-checker instructions + project path]")
```

**Wait for ALL launched agents to complete before proceeding to Phase 2.**

Also check inline (no subagent needed):
- CLAUDE.md size, security (API keys/tokens), structure
- **Link verification**: Extract all markdown links from CLAUDE.md. For each link to a local file (`.context/`, `.claude/`, relative paths), verify the target file exists. Report broken links as WARNING.
- **Anti-pattern detection**: If CLAUDE.md links to a `README.md` inside `references/` or `docs/`, flag as WARNING — convention says each module has `00-index.md` and CLAUDE.md is the entry point. The README is redundant.
- Cross-domain: skills referenced in CLAUDE.md exist? References mentioned in skills exist?

---

## Phase 2: Synthesize & Report

Collect all subagent reports. Produce unified report split into two top-level findings sections — **structural cleanup** (safe, mechanical fixes) vs **token savings** (toggle-preferred, reversible config). Each finding goes into one or the other based on its check code:

- **Structural cleanup** — codes WITHOUT `CB-` / `PL-SCHEMA` prefix: `[A]–[F]`, `[PA]–[PD]`, `[IA]–[ID]`, `[RA]–[RC]`, `[QA]–[QB]`, `[DA]–[DD]`, `[UA]–[UH]`, `[CV-*]` (from `conventions-auditor`), `[AG]`, `[AH]`, `[AI]`, `[F1]–[F6]`, `[V1]`, freshness, broken symlinks, missing indexes, pluralized names, anti-patterns. These are mechanical and reversible by editing one file at a time. `[CV-*]` findings are deterministic (produced by `validate.py`) — prefer them over heuristic codes when they overlap on the same file.
- **Token savings** — codes WITH `CB-` prefix (`CB-PL`, `CB-SR`, `CB-DU`, `CB-MD`, `CB-CM`, `CB-SKILL-DESC-RESIDENT`) and `PL-SCHEMA`. These suggest config toggles (`enabledPlugins: false`, `skillOverrides: name-only/off`, MEMORY trims, plugin manifest cleanup). Always **prefer toggle over uninstall/delete**.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ECOSYSTEM AUDIT — [Project Name]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Summary
| Domain | Items | ❌ | ⚠️ | ℹ️ |
|--------|-------|----|----|----|
[one row per domain audited]

## Limpieza estructural (segura)
[findings without CB- / PL-SCHEMA prefix, grouped by domain, severity-ordered]

## Ahorro de tokens (preferir toggle)
[findings with CB- / PL-SCHEMA prefix, ordered by estimated savings descending; each annotated with risk: low | medium | high]

## Health Score
[X]% (100% = no issues, -10 per critical, -3 per warning)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Destructive-action checklist

Before emitting any finding that proposes deleting a file/directory, uninstalling a plugin, or removing a skill from disk, verify the four gates below. Failing **any** gate downgrades the proposal to a softer alternative or suppresses it.

1. **Canonical type?** If the target is an empty directory, is it in the canonical list (`audits, decisions, plans, requests, issues, references, research, backlog, roadmap, docs`)? If yes → do not propose deletion (empty canonical = healthy).
2. **Protected marketplace?** If the target is a plugin, is its marketplace in `PROTECTED_MARKETPLACES` (`claude-plugins-official`, `anthropics`)? If yes → downgrade to INFO, never propose disable/uninstall.
3. **Reversible local override exists?** Is there a softer alternative (`enabledPlugins: false`, `skillOverrides: name-only/off`, archive-instead-of-delete)? If yes → prefer it over the destructive action.
4. **`.git` ancestor present?** For any `.gitignore` suggestion in `.context/`, walk up to find `.git`. If absent (typical of `*_ws/` workspace roots) → suppress the finding.

---

## Phase 3: Suggest Actions

After the report, present actionable suggestions grouped by priority. **Be prescriptive, not just descriptive** — suggest the aidex way of organizing things, explain why, and let the user decide.

```
❌ Critical (fix now):
  1. [description] → [what aidex will do]

⚠️  Recommended:
  2. [description] → [what aidex will do]
  3. Deep-sync [stale reference] → launches sync subagent
  4. Silence [N] irrelevant skills → emits skillOverrides patch for settings.local.json

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
- [04-fix-procedures.md](references/04-fix-procedures.md) — Safe and destructive fix procedures
- [05-context-budget.md](references/05-context-budget.md) — Idle token budget, drivers, and `/aidex context` heuristics
