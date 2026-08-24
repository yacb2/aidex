---
name: aidex
description: 'Use when the user wants to audit, organize, clean up, or health-check their Claude Code setup — a messy or inconsistent .context/, a bloated or stale MEMORY.md, broken symlinks in .claude/skills, unused or misplaced skills, dead CLAUDE.md links, plugins inflating idle context, or "my project opens heavy / wastes context". Also fires on "audit my project", "organize my ecosystem", "what skills do I have", "check my project''s health", "I think I have broken symlinks", "my .context/ is a mess", "my new project has no .context / help me start with aidex", and the /aidex command. Not for: creating .context/ docs (aidex-conventions); project-state audits like UX or security (aidex-audit); backlog items (aidex-backlog).'
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
| **MEMORY.md** | `.claude/` or project root | Bloat, stale entries, inline content, externalization. Run `python3 ~/.claude/skills/aidex/scripts/memory-sweep.py` for the mechanical half — session logs saved as memories, untyped files, throwaway or duplicated memory directories, and an always-on index over budget (read-only; `rules/memory-hygiene.md` is the canon) |
| **CLAUDE.md** | `.claude/CLAUDE.md` or `./CLAUDE.md` | Size, security, structure, stale references |
| **Freshness** | `.context/references/`, `.context/docs/` | Last Updated vs recent commits, stale content |
| **Plugins** | `~/.claude/plugins/` | Always-loaded subagent cost vs. recent usage, uninstall candidates |
| **Auditor freshness** | `references/06-claude-code-surface.md` | Which Claude Code version each of the auditor's own recommendations was last verified against — `skillOverrides` values and cost model, MCP scoping, plugin handling, settings precedence. Run `python3 ~/.aidex/skills/aidex/scripts/surface-drift-check.py`. Exit 1 means "go look", never "something broke": a newer Claude Code makes a recommendation UNVERIFIED, not wrong |
| **Workspace root** | `~/Documents/projects/` (the folder holding the projects) | What has accumulated OUTSIDE any project's `.claude/` and `.context/`: holding folders that only grow (`_toDelete`, `_backups`, `_archive`), loose files dropped at the root, a repo cloned among the projects with no `CLAUDE.md`, an in-project `.aidex-backups` (a regression — backups moved to `~/.aidex/backups/` in `1627663`), and `Bash(x:*)` permissions naming a command no longer on PATH. Run `python3 ~/.aidex/skills/aidex/scripts/root-litter-sweep.py` — read-only, reports and offers, never deletes |
| **Context budget** | Session `/context` output | Idle token cost attribution across skills, MEMORY, CLAUDE.md, plugins, rules |

---

## Sub-action: `/aidex context`

Focused audit of the session's **idle token footprint** (everything loaded before the user
types anything). Fires when the user pastes `/context` output and asks why it is heavy,
reports a project opening at >20% context used, or asks to reduce initial tokens or audit
plugins.

**Read `~/.claude/skills/aidex/references/01-context-audit.md` and follow it.** It is the
whole procedure: the inputs, the 5-step flow (including which four agents launch in
parallel and what each is scoped to), the optional apply phase with its `[A]/[B]/[C]/[D]`
front-loaded gate, the per-patch autonomy-class table that decides what may be applied
unprompted, and the guardrails that make that safe. Running this sub-action from memory is
how a class-1 patch gets applied as if it were class 4.

## Sub-action: `/aidex init`

Bootstrap `.context/` in a project that doesn't have one. Runs [`scripts/init-context.sh`](scripts/init-context.sh) `[project-dir]` — idempotent, creates only the directories/files that are missing, seeds the backlog/plans indexes via the installed reindexers when present, writes `.context/references/01-project-commands.md` (skip-if-exists), then prints (never writes) a suggested CLAUDE.md block for the user to add themselves.

---

## Sub-action: `/aidex sweep`

Check the whole fleet for drift instead of one project at a time. Read-only — it
never writes to a project.

1. Run `bash ~/.aidex/skills/aidex/scripts/compliance-sweep.sh`. Add `--root <dir>`
   to scan somewhere other than `~/Documents/projects`, or name project paths to
   check only those. Add `--verbose` to also see the clean and skipped ones.
2. Read the output. **A clean run prints nothing and exits 0** — that is the whole
   point, so it is safe to schedule. Each drifting project prints its name and which
   of the three instruments fired: `validate` (`.context/` conformance, ratchet-checked),
   `reconcile` (closure that did not propagate, stale roll-up indexes), `sweep`
   (done/dropped items never archived, D-10).
3. Fix per project by running the named instrument there — nothing is fixed for you.
4. For rule-propagation drift specifically (a project restating a globally-owned
   rule, or `skillOverrides` that contradict one), run
   `python3 ~/.aidex/skills/aidex/scripts/conformance-sweep.py` instead.
5. For what has accumulated OUTSIDE the projects — at the workspace root itself — run
   `python3 ~/.aidex/skills/aidex/scripts/root-litter-sweep.py`. Each finding is
   labelled `aidex` or `foreign`: aidex leaving something behind is a bug in aidex,
   you leaving something behind is information, and the two must not read the same.
   **Report the categories and offer to act; never act on them yourself.** Several are
   things a person keeps on purpose — an `_archive/` is a decision, not a mistake.

6. Before trusting any of the auditor's own configuration advice — especially after
   updating Claude Code — run
   `python3 ~/.aidex/skills/aidex/scripts/surface-drift-check.py`. It names which
   recommendations have not been checked against the installed version. Re-verify the
   named rows (ask the `claude-code-guide` agent, not memory), then bump the version
   column in `references/06-claude-code-surface.md`. Unchanged behaviour is the normal
   outcome and bumping the column IS the work: it converts "nobody has looked" into
   "checked on this version". This exists because the auditor once recommended removing
   plugins that were fine, and nothing made that visible.

7. For done-but-not-archived across all four tiers of ONE project — plans, audits,
   requests, backlog — run
   `python3 ~/.aidex/skills/aidex-conventions/scripts/archive-sweep.py`. `sweep.sh`
   covers the backlog only, which is how D-10 came to be applied there and skipped in
   the other three. Dry run by default; `--check` exits 1 for a gate; `--apply` moves
   the terminal set and never the status-drift set.

Cadence and engine are yours to pick: it is a plain command, so schedule it with a
routine, cron, or `/loop`. Nothing about the schedule is baked into the script.

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

**Model, effort and tools are set here, not in the agent files.** These agents are launched
by reading their `.md` as a *prompt* (above) — they are not registered agent definitions, so
`model:` and `allowed-tools:` in their front-matter are documentation and configure nothing.
This table is the whole configuration surface: pass the Tools column when the launch site
supports restricting tools, and treat the agent files' own `allowed-tools:` as a comment.
Effort follows the suite heuristic
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

**Read the fix procedures before executing anything:**
`~/.claude/skills/aidex/references/04-fix-procedures.md`. It holds the step-by-step
procedure for each fix below — including which ones are destructive, what to back up
first, and the recovery path when one goes wrong. The list here names the actions; the
reference is how to perform them.

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

**Destructive actions (per-item approval — autonomy class 1, gated even under [A]/[B]):**
- Delete orphaned files
- Remove skills

Trimming duplicated content is **not** in this list: it is a class-4 edit covered by the
apply phase's backup, and listing it here is what made the two sections disagree.

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

