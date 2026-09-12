---
name: aidex
description: 'Use when the user wants to audit, organize, clean up, or health-check their Claude Code setup — a messy or inconsistent .context/, a bloated or stale MEMORY.md, broken symlinks in .claude/skills, unused or misplaced skills, dead CLAUDE.md links, plugins inflating idle context, or "my project opens heavy / wastes context". Also fires on "audit my project", "organize my ecosystem", "what skills do I have", "check my project''s health", "I think I have broken symlinks", "my .context/ is a mess", "my new project has no .context / help me start with aidex", and the /aidex:aidex command. Not for: creating .context/ docs (/aidex:plan, /aidex:decision, /aidex:reference, /aidex:research, /aidex:request); project-state audits like UX or security (/aidex:audit); backlog items (/aidex:backlog).'
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
| **Skills** | `.claude/skills/`, `${CLAUDE_PLUGIN_ROOT}/skills/` | Frontmatter, size, structure, scope placement |
| **Symlinks** | `.claude/skills/*`, `.claude/commands/*` | Targets exist, no broken/orphan links |
| **Memory** | `~/.claude/projects/<slug>/memory/` + its `MEMORY.md` index | Session logs saved as memories, secrets, closed subjects, duplicates, content in the always-on index. See `/aidex:aidex memory` |
| **CLAUDE.md** | `.claude/CLAUDE.md` or `./CLAUDE.md` | Size, security, structure, stale references |
| **Freshness** | `.context/references/`, `.context/docs/` | `updated` vs recent commits, stale content |
| **Plugins** | `~/.claude/plugins/` | Always-loaded subagent cost vs. recent usage, uninstall candidates |
| **Auditor freshness** | `references/06-claude-code-surface.md` | Which Claude Code version each of the auditor's own recommendations was last verified against. See `/aidex:aidex sweep` step 6 |
| **Workspace root** | the workspace root (`$AIDEX_WORKSPACE_ROOT`, default `~/Documents/projects`) | What has accumulated OUTSIDE any project's `.claude/` and `.context/` — holding folders, loose files, an unmarked cloned repo, stale `Bash(x:*)` permissions. See `/aidex:aidex sweep` step 5 |
| **Context budget** | `scripts/context-snapshot.py` — Claude Code's own `/context` + `/skill-doctor` via `claude -p`, zero tokens | Measured idle cost per category, memory file, skill and MCP tool, plus per-skill usage |

---

## Sub-action: `/aidex:aidex context`

Focused audit of the project's **idle token footprint** (everything loaded before the user
types anything), measured by `scripts/context-snapshot.py` — Claude Code's own `/context`
and `/skill-doctor` run through `claude -p` in the project cwd, no model call. Fires when
the user asks why a project opens heavy, wants to reduce initial tokens, or asks to audit
plugins; a pasted `/context` from a live session is the fallback input.

**Read `${CLAUDE_PLUGIN_ROOT}/skills/aidex/references/01-context-audit.md` and follow it.** It is the
whole procedure: the inputs, the 5-step flow (including which four agents launch in
parallel and what each is scoped to), the optional apply phase with its `[A]/[B]/[C]/[D]`
front-loaded gate, the per-patch autonomy-class table that decides what may be applied
unprompted, and the guardrails that make that safe. Running this sub-action from memory is
how a class-1 patch gets applied as if it were class 4.

## Sub-action: `/aidex:aidex memory`

Audits the memory **files** in `~/.claude/projects/<slug>/memory/`, not just the
`~/.claude/projects/<slug>/memory/MEMORY.md` index. Three forms, on `$ARGUMENTS`:

- **bare** — `scripts/memory-sweep.py` for the mechanical half, then
  [`memory-auditor`](agents/memory-auditor.md) per project for the reading half.
  Report only.
- **`<project>`** — scoped: `--project=<slug>`. The `=` is required; every slug starts
  with `-`, which argparse reads as a flag.
- **`--apply`** — route each verdict below. Deletions need the backup *and* the ratified
  project x verdict-class table.

Each verdict routes to exactly one destination, and that mapping lives in ONE place —
[`references/03-memory-workflow.md`](references/03-memory-workflow.md) § Where each
verdict goes. Read it before applying; the agent returns the verdict and nothing else.

An unlisted verdict is a `KEEP`. Every MOVE writes its destination **before** the memory
is deleted, and `DELETE-{DUP,CLOSED,LOG}` backs up before removing the file and its index
line. On completion re-run the sweep with `--stamp`: that silences the 30-day
SessionStart nudge until the directory changes again. Budgets are words, never lines —
800 per memory, 1,200 for the index. Canon: [`references/memory-hygiene.md`](references/memory-hygiene.md); detail:
[`references/03-memory-workflow.md`](references/03-memory-workflow.md).

## Sub-action: `/aidex:aidex init`

Bootstrap `.context/` in a project that doesn't have one. Runs [`scripts/init-context.sh`](scripts/init-context.sh) `[project-dir]` — idempotent, creates only the directories/files that are missing, seeds the backlog/plans indexes via the installed reindexers when present, writes `.context/references/01-project-commands.md` (skip-if-exists), then prints (never writes) a suggested CLAUDE.md block for the user to add themselves.

**It has one question, and you ask it** — in the Bash tool stdin is never a terminal, so
the script prints `no TTY — skipped the artifact-style.md question` instead of prompting.
On that line ask the user whether this project wants a `.context/artifact-style.md`, and
in which language its HTML artifacts are written; re-run (idempotent) with
`--artifact-style <lang>` or `--no-artifact-style`. Never created unasked; either answer
is recorded in the marker aidex-artifact's mid-artifact offer reads, so neither asks twice.

---

## Sub-action: `/aidex:aidex sweep`

Check the whole fleet for drift instead of one project at a time. Read-only — it never
writes to a project. Entry point:
`bash ${CLAUDE_PLUGIN_ROOT}/skills/aidex/scripts/compliance-sweep.sh`.

**Read `${CLAUDE_PLUGIN_ROOT}/skills/aidex/references/07-sweep-procedure.md` and follow it.** It is
the whole procedure: all seven instruments and what each one attributes, the read-only
rule for workspace-root litter (`aidex` vs `foreign` findings — reported and offered,
never acted on), the auditor-freshness re-verification loop behind
`06-claude-code-surface.md`, and the cadence note.

---

## Phase 0: Discovery

Before launching any subagent, scan what exists in the project:

```
Check for:
- .context/ (references/, docs/, plans/, backlog/ [incl. _deferred/], issues/, roadmap/, requests/, decisions/, research/, audits/, loops/, communications/, worktrees/)
- .context/ optional tier (data/, diagrams/, drafts/, experiments/, worklists/, workflows/) — project-local, INFO-at-most, never deletion candidates
- .claude/ (skills/, CLAUDE.md)
- ~/.claude/projects/<slug>/memory/ (memory files + MEMORY.md; slug = the project path
  with `/` and `_` turned into `-`)
- ~/.claude/aidex/manifest (what the suite installed; anything else in ~/.claude/skills is the user's)
- ${CLAUDE_PLUGIN_ROOT}/skills/ (global skills)
```

Build a quick inventory of what exists and its size. This determines which agents to launch.

**If nothing exists:** Suggest running `/aidex:aidex init` to bootstrap `.context/`.

---

## Phase 1: Parallel Audit

Launch every applicable agent in a single message with multiple Agent tool calls, each with `run_in_background: true`, so they execute in parallel.

Read each agent's instructions from `${CLAUDE_PLUGIN_ROOT}/skills/aidex/agents/` and pass them as the prompt. Include the project path in each prompt.

| Subagent | Launches when | Model | Effort | Tools |
|----------|--------------|-------|--------|-------|
| [context-auditor](agents/context-auditor.md) | `.context/` exists | haiku | medium | Read, Glob, Grep, Bash |
| [conventions-auditor](agents/conventions-auditor.md) | `.context/` exists AND `${CLAUDE_PLUGIN_ROOT}/skills/aidex-conventions/scripts/validate.sh` is installed | haiku | low | Read, Bash |
| [skills-auditor](agents/skills-auditor.md) | `.claude/skills/` exists | haiku | medium | Read, Glob, Grep |
| [symlink-checker](agents/symlink-checker.md) | Any symlinks found | haiku | low | Read, Glob, Bash |
| [memory-auditor](agents/memory-auditor.md) | `~/.claude/projects/<slug>/memory/` exists and holds at least one memory file | sonnet | medium | Read, Glob, Grep |
| [freshness-checker](agents/freshness-checker.md) | `.context/references/`, `.context/docs/`, or `.context/roadmap/` exist | haiku | low | Read, Glob, Grep, Bash, WebFetch |
| [plugin-auditor](agents/plugin-auditor.md) | `~/.claude/plugins/installed_plugins.json` exists | haiku | low | Read, Glob, Grep, Bash |
| [context-cost-analyzer](agents/context-cost-analyzer.md) | `/aidex:aidex context` — after `scripts/context-snapshot.py` has written the snapshot | haiku | low | Read, Glob, Grep, Bash |

**Model, effort and tools are set here, not in the agent files.** These agents are launched
by reading their `.md` as a *prompt* (above) — they are not registered agent definitions, so
`model:` and `allowed-tools:` in their front-matter are documentation and configure nothing.
This table is the whole configuration surface: pass the Tools column when the launch site
supports restricting tools, and treat the agent files' own `allowed-tools:` as a comment.
Effort follows the suite heuristic
([workflow-spec conventions](../aidex-workflow/references/01-workflow-spec-conventions.md)):
mechanical existence/parse checks → `low`; judgment over content quality or compliance →
`medium`.

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
- **Token savings** — codes WITH `CB-` prefix (`CB-PL`, `CB-SR`, `CB-DU`, `CB-MD`, `CB-CM`, `CB-RF`) and `PL-SCHEMA`. These suggest config toggles (`enabledPlugins: false`, `skillOverrides: name-only/off`, MEMORY trims, plugin manifest cleanup). Note: `skillOverrides` does not apply to plugin skills (see `references/09-plugin-skill-naming.md`), so it cannot target aidex's own skills. Always **prefer toggle over uninstall/delete**.

The report's literal shape — summary table, the two findings sections, health score —
is `references/08-report-shapes.md` § Phase 2.

### Destructive-action checklist

Before emitting any finding that proposes deleting a file/directory, uninstalling a plugin, or removing a skill from disk, verify the four gates below. Failing **any** gate downgrades the proposal to a softer alternative or suppresses it.

1. **Canonical type?** If the target is an empty directory, is it in the canonical list (`audits, decisions, plans, requests, issues, references, research, backlog, roadmap, docs, loops, communications, worktrees`)? If yes → do not propose deletion (empty canonical = healthy). The `backlog/_deferred/` and `<type>/_archive/` subdirs are part of their parent's canonical lifecycle — treat as healthy, never orphan/delete candidates.
   **Acceptable-optional tier?** If the target is `data`, `diagrams`, `drafts`, `experiments`, `worklists`, or `workflows`, it is never required (some are scaffolded on demand — `worklists` by the worklist scripts, `workflows` by `aidex-workflow`; the rest are project-local, may be gitignored): INFO-at-most, never a deletion proposal. Only `.context/` dirs in NEITHER tier qualify as deletion candidates.
2. **Protected marketplace?** If the target is a plugin, is its marketplace in `PROTECTED_MARKETPLACES` (`claude-plugins-official`, `anthropics`)? If yes → downgrade to INFO, never propose disable/uninstall.
3. **Reversible local override exists?** Is there a softer alternative (`enabledPlugins: false`, `skillOverrides: name-only/off`, archive-instead-of-delete)? (`skillOverrides` is not available for plugin skills — `references/09-plugin-skill-naming.md`) If yes → prefer it over the destructive action.
4. **`.git` ancestor present?** For any `.gitignore` suggestion in `.context/`, walk up to find `.git`. If absent (typical of `*_ws/` workspace roots) → suppress the finding.

---

## Phase 3: Suggest Actions

After the report, present actionable suggestions grouped by priority. **Be prescriptive,
not just descriptive** — suggest the aidex way of organizing things, explain why, and let
the user decide. The list's shape is `references/08-report-shapes.md` § Phase 3.

Terminate it with this menu, which IS the front-loaded gate the apply phase must not
re-ask per item:

```
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
`${CLAUDE_PLUGIN_ROOT}/skills/aidex/references/04-fix-procedures.md`. It holds the step-by-step
procedure for each fix below — including which ones are destructive, what to back up
first, and the recovery path when one goes wrong. The list here names the actions; the
reference is how to perform them.

For each approved action, execute directly or launch a specialized subagent:

**Direct execution (simple fixes):**
- Fix broken symlinks (remove or recreate)
- Add missing index links
- Add missing metadata headers
- Archive completed plans

**Subagent execution (complex operations):**
- Deep-sync stale references → sonnet subagent with WebFetch + Context7
- Memory cleanup (full workflow) → `/aidex:aidex memory --apply`

**Destructive actions (per-item approval — autonomy class 1, gated even under [A]/[B]):**
- Delete orphaned files
- Remove skills

Trimming duplicated content is **not** in this list: it is a class-4 edit, covered by the
apply phase's backup.

After execution, show the before/after summary — its shape, including the health delta
and the next-audit line, is `references/08-report-shapes.md` § Phase 4.

---

## Context-Triggered Behavior

Besides explicit invocation (`/aidex:aidex`), this skill also activates when:

- Claude notices a broken symlink while reading `.claude/skills/`
- `memory-sweep.py` reports a finding, or the always-on MEMORY.md index is over its word budget
- A referenced file in a skill doesn't exist
- User asks about "project health", "ecosystem", "organize skills", "clean up"

In context-triggered mode, suggest a focused audit rather than a full one:
```
"The MEMORY.md index here is 1,540 words (budget: 1,200), loaded every session.
Want me to run `/aidex:aidex memory`?"
```

