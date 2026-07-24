---
name: aidex
description: Use when the user wants to audit, organize, clean up, or health-check their Claude Code setup — a messy or inconsistent .context/, a bloated or stale MEMORY.md, broken symlinks in .claude/skills, unused or misplaced skills, dead CLAUDE.md links, plugins inflating idle context, or "my project opens heavy / wastes context". Also fires on "audit my project", "organize my ecosystem", "what skills do I have", "check my project's health", "I think I have broken symlinks", "my .context/ is a mess", "my new project has no .context / help me start with aidex", and the /aidex command. Not for: creating .context/ docs (aidex-conventions); project-state audits like UX or security (aidex-audit); backlog items (aidex-backlog).
argument-hint: "[context]"
disable-model-invocation: false
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Aidex — Ecosystem Orchestrator

Single entry point for auditing, diagnosing, and fixing the AI assistant ecosystem.

## What It Covers

| Domain | Location | What it checks |
|--------|----------|---------------|
| **Context structure** | `.context/` | References, docs, plans, backlog (incl. `_deferred/`), issues, roadmap, requests, decisions, research, audits, loops, communications, worktrees — numbering, metadata, index coverage, reorganization suggestions. Optional tier (`data`, `diagrams`, `drafts`, `experiments`, `worklists`, `workflows`) reported at INFO only |
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

1. **Write audit doc.** Save the full report to `.context/audits/YYYY-MM-DD-context-and-memory-optimization.md` using the project's audit conventions (delegate to the `aidex-audit` skill if available, else write directly).
2. **Backup.** Before any mutation, copy to `~/.aidex/backups/<project-name>/<timestamp>/` (user-level, outside the project tree — keeps backups out of every project and consolidated under the central aidex engine):
   - `settings.local.json` (project and user, if touched)
   - the entire memory directory
   - any SKILL.md files about to be edited
   Derive `<project-name>` from the current project directory's basename. No `.gitignore` step is needed since the backup lives outside the project.
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

## Sub-action: `/aidex init`

Bootstrap `.context/` in a project that doesn't have one. Runs [`scripts/init-context.sh`](scripts/init-context.sh) `[project-dir]` — idempotent, creates only the directories/files that are missing, seeds the backlog/plans indexes via the installed reindexers when present, writes `.context/references/project-commands.md` (skip-if-exists), then prints (never writes) a suggested CLAUDE.md block for the user to add themselves.

---

## Phase 0: Discovery

Before launching any subagent, scan what exists in the project:

```
Check for:
- .context/ (references/, docs/, plans/, backlog/ [incl. _deferred/], issues/, roadmap/, requests/, decisions/, research/, audits/, loops/, communications/, worktrees/)
- .context/ optional tier (data/, diagrams/, drafts/, experiments/, worklists/, workflows/) — project-local, INFO-at-most, never deletion candidates
- .claude/ (skills/, CLAUDE.md, MEMORY.md)
- ~/.aidex/ (shared skills storage)
- ~/.claude/skills/ (global skills)
```

Build a quick inventory of what exists and its size. This determines which agents to launch.

**If nothing exists:** Suggest running `/aidex init` to bootstrap `.context/`.

---

## Phase 1: Parallel Audit

**CRITICAL: Launch ALL applicable agents in a SINGLE message with multiple Agent tool calls.** Each agent runs with `run_in_background: true` so they execute in parallel. Do NOT launch them sequentially.

Read each agent's instructions from `~/.aidex/skills/aidex/agents/` and pass them as the prompt. Include the project path in each prompt.

| Subagent | Launches when | Model | Effort | Tools |
|----------|--------------|-------|--------|-------|
| [context-auditor](agents/context-auditor.md) | `.context/` exists | haiku | medium | Read, Glob, Grep |
| [conventions-auditor](agents/conventions-auditor.md) | `.context/` exists AND `~/.aidex/skills/aidex-conventions/scripts/validate.sh` is installed | haiku | low | Read, Bash |
| [skills-auditor](agents/skills-auditor.md) | `.claude/skills/` exists | haiku | medium | Read, Glob, Grep |
| [symlink-checker](agents/symlink-checker.md) | Any symlinks found | haiku | low | Read, Glob, Bash |
| [memory-auditor](agents/memory-auditor.md) | MEMORY.md exists and >50 lines | sonnet | medium | Read, Glob, Grep |
| [freshness-checker](agents/freshness-checker.md) | `.context/references/`, `.context/docs/`, or `.context/roadmap/` exist | haiku | low | Read, Glob, Grep, Bash |
| [plugin-auditor](agents/plugin-auditor.md) | `~/.claude/plugins/installed_plugins.json` exists | haiku | low | Read, Glob, Grep, Bash |
| [context-cost-analyzer](agents/context-cost-analyzer.md) | User ran `/aidex context` or pasted `/context` output | haiku | low | Read, Glob, Grep, Bash |

**Model and effort are set here, not in the agent files.** These agents are launched by
reading their `.md` as a *prompt* (above) — they are not registered agent definitions, so
`model:` in their front-matter is documentation and configures nothing. This table is the
configuration surface. Effort follows the suite heuristic
([workflow-spec conventions](../aidex-workflow/references/01-workflow-spec-conventions.md)):
mechanical existence/parse checks → `low`; judgment over content quality or compliance →
`medium`.

Example launch pattern (all in one message):
```
Agent(description="Audit .context/ structure", model=haiku, effort=medium, run_in_background=true, prompt="[context-auditor instructions + project path]")
Agent(description="Audit skills", model=haiku, effort=medium, run_in_background=true, prompt="[skills-auditor instructions + project path]")
Agent(description="Check symlinks", model=haiku, effort=low, run_in_background=true, prompt="[symlink-checker instructions + project path]")
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
| Domain | Items | FAIL | WARN | INFO |
|--------|-------|------|------|------|
[one row per domain audited]

## Structural cleanup (safe)
[findings without CB- / PL-SCHEMA prefix, grouped by domain, severity-ordered]

## Token savings (prefer toggle)
[findings with CB- / PL-SCHEMA prefix, ordered by estimated savings descending; each annotated with risk: low | medium | high]

## Health Score
[X]% (100% = no issues, -10 per critical, -3 per warning)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Destructive-action checklist

Before emitting any finding that proposes deleting a file/directory, uninstalling a plugin, or removing a skill from disk, verify the four gates below. Failing **any** gate downgrades the proposal to a softer alternative or suppresses it.

1. **Canonical type?** If the target is an empty directory, is it in the canonical list (`audits, decisions, plans, requests, issues, references, research, backlog, roadmap, docs, loops, communications, worktrees`)? If yes → do not propose deletion (empty canonical = healthy). The `backlog/_deferred/` and `<type>/_archive/` subdirs are part of their parent's canonical lifecycle — treat as healthy, never orphan/delete candidates.
   **Acceptable-optional tier?** If the target is `data`, `diagrams`, `drafts`, `experiments`, `worklists`, or `workflows`, it is never required (some are scaffolded on demand — `worklists` by the worklist scripts, `workflows` by `aidex-workflow`; the rest are project-local, may be gitignored): INFO-at-most, never a deletion proposal. Only `.context/` dirs in NEITHER tier qualify as deletion candidates.
2. **Protected marketplace?** If the target is a plugin, is its marketplace in `PROTECTED_MARKETPLACES` (`claude-plugins-official`, `anthropics`)? If yes → downgrade to INFO, never propose disable/uninstall.
3. **Reversible local override exists?** Is there a softer alternative (`enabledPlugins: false`, `skillOverrides: name-only/off`, archive-instead-of-delete)? If yes → prefer it over the destructive action.
4. **`.git` ancestor present?** For any `.gitignore` suggestion in `.context/`, walk up to find `.git`. If absent (typical of `*_ws/` workspace roots) → suppress the finding.

---

## Phase 3: Suggest Actions

After the report, present actionable suggestions grouped by priority. **Be prescriptive, not just descriptive** — suggest the aidex way of organizing things, explain why, and let the user decide.

```
[FAIL] Critical (fix now):
  1. [description] → [what aidex will do]

[WARN] Recommended:
  2. [description] → [what aidex will do]
  3. Deep-sync [stale reference] → launches sync subagent
  4. Silence [N] irrelevant skills → emits skillOverrides patch for settings.local.json

[TIP] Reorganize:
  5. Consolidate bugs/ + fixes/ → issues/ with ISSUE-NNN format
  6. Remove references/README.md — modules have 00-index.md, CLAUDE.md is entry point
  7. Create .context/roadmap/ — project has active phases but no roadmap
  8. Restructure issues/ files to ISSUE-NNN with status+root cause+fix

[INFO] Optional:
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
- Memory cleanup (full workflow) → sonnet subagent

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

- [01-context-checks.md](references/01-context-checks.md) — Pointer to the `context-auditor` agent (the single carrier for .context/ checks)
- [02-skills-checks.md](references/02-skills-checks.md) — Pointer to the `skills-auditor` agent (the single carrier for skills checks + scope decision matrix)
- [03-memory-workflow.md](references/03-memory-workflow.md) — Memory classification and externalization workflow
- [04-fix-procedures.md](references/04-fix-procedures.md) — Safe and destructive fix procedures
- [05-context-budget.md](references/05-context-budget.md) — Idle token budget, drivers, and `/aidex context` heuristics
