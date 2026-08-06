# Context Budget Audit

Heuristics for diagnosing a bloated initial `/context` footprint in Claude Code sessions. Complements the per-domain checks (skills, MEMORY.md, CLAUDE.md) with a **cross-domain cost analysis** that treats the 200k context window as a budget.

## When to run

- Project opens at >20% context used (>40k tokens) before any user message.
- User pastes `/context` output asking "why is this so heavy?".
- User mentions "bloated context", "initial tokens", "wasted budget".

## Budget targets (reference)

| Category | Soft target | Hard ceiling | Notes |
|---|---:|---:|---|
| System prompt | ~10k | — | Not tunable |
| System tools | ~10k | — | Not tunable |
| Memory files | <8k | 12k | CLAUDE.md (global + project) + MEMORY.md + rules |
| Skills | <6k | 10k | Metadata only; bodies load on demand |
| Custom agents | <1k | 4k | Plugin subagents always loaded |
| MCP tools | 0 at idle | 4k | Deferred servers cost ~0 until a tool is searched for; a resident server pays its whole schema every session |
| **Total idle** | **<30k** | **45k** | Everything before first user message |

Breaching a hard ceiling → CRITICAL. Between soft and hard → WARNING.

## Two remedies, not one: remove and defer

The obvious remedy for an expensive footprint is to **remove** — uninstall the plugin,
disable the server, silence the skill. It is not the only one, and reaching for it first is
how a useful capability gets deleted to save tokens it was not really costing.

**Deferral is the tool-layer instance of progressive disclosure**: the thing stays
available and costs ~0 until something asks for it. Prefer it whenever the capability is
occasionally wanted — removal is correct only when it is never wanted.

| Layer | Deferred form (cheap, still available) | Removed form (gone) |
|---|---|---|
| Skills | Metadata only; the body loads on invocation. This is already the default | delete / unlink the skill |
| Skills, per project | `skillOverrides: name-only` or `user-invocable-only` — **these are deferrals, not removals**; the skill is still reachable | `skillOverrides: off` |
| MCP servers | Tools listed by name; schemas fetched on demand via `ToolSearch` | disable the server |
| Plugin subagents | No deferred form — an installed plugin's `agents/*.md` load every session | uninstall the plugin |

The last row is why plugins rank first among the cost drivers: they are the one layer with
no middle option, so their cost is the least avoidable and the most worth acting on.

**How to tell whether an MCP server is actually deferred.** Read the session's own
signals rather than the config: a deferred server's tools arrive as *names only* in a
system-reminder and must be loaded with `ToolSearch` before they can be called, while a
resident server's full tool schemas are present from the first turn. `/context` shows the
difference directly — `MCP tools: 0 tokens` at idle means deferred. A server showing a
non-zero idle cost is resident: defer it before considering disabling it, and only disable
it if its tools were not wanted at all.

## Cost drivers (ranked by impact)

### 1. Plugins with always-loaded subagents

Each `agents/*.md` inside an installed plugin costs ~500–700 tokens of metadata loaded on every session, regardless of whether the plugin's commands are invoked.

- Count files matching `~/.claude/plugins/cache/*/*/*/agents/*.md` grouped by plugin.
- Plugin with N agents ≈ N × 600 tokens fixed cost.
- Candidate for uninstall if: N ≥ 3 **AND** no invocation of the plugin's commands in the last 30 days of transcripts (`~/.claude/projects/*/*.jsonl`).
- Built-in skills like `/simplify` are harness-level (0 tokens extra) — do not confuse with homonymous plugin subagents (e.g., `pr-review-toolkit`'s `code-simplifier`).

### 2. User↔project skill duplication

When a project places a skill under `.claude/skills/<name>/` that shadows a global skill with the same `name` field, both pay metadata cost (global loader still lists it).

- Cross-reference `~/.claude/skills/<name>/SKILL.md` frontmatter `name:` with `.claude/skills/<name>/SKILL.md`.
- Compare `description` fields: Jaccard similarity on word sets >0.7 → duplicate.
- Resolution: either delete the local copy (accept global) or unlink the global (keep local override). Don't keep both.

### 3. MEMORY.md "docs disguised as memory"

Auto-memory is for **user facts, feedback, project state, references** (4 canonical types). Entries that describe **code patterns, architecture, gotchas, fix recipes, or conventions** are documentation — they belong in `.context/references/` (loaded on demand), not in MEMORY.md (loaded every turn).

Signals that an entry is disguised documentation:

- Body mentions file paths, function names, or class names as the subject (not as context).
- Body describes "how X works" or "when editing X, do Y" beyond a one-line gotcha.
- Entry title contains "Patterns", "Gotchas", "Architecture", "How to", "Stack", "Workflow".
- Entry exceeds 3 lines of substantive prose.

Route: move content to `.context/references/<topic>/NN-topic.md`, replace MEMORY entry with a 1-line link or delete it.

### 4. CLAUDE.md verbosity

Project CLAUDE.md above ~3k tokens (~300 lines) typically contains movable content:

- Full directory trees → move to `.context/references/architecture/00-index.md`.
- Command catalogs with >5 entries → move to `.context/references/commands/`.
- Stack tables with versions → keep a one-liner, move detail out.
- Keep in CLAUDE.md: active constraints, critical gotchas that change behavior, entry points to references.

### 5. Global rules fragmentation

`~/.claude/CLAUDE.md` + `~/.aidex/rules/*.md` + `~/.claude/rules/*.md` often overlap. Each is imported into every session.

- Flag rules whose titles or first paragraphs overlap across the three locations.
- Canonical home: `~/.aidex/rules/` for AIDEX-managed, `~/.claude/CLAUDE.md` for personal.

### 6. Stack-irrelevant global skills

A skill loaded globally but unused for the current project stack still pays metadata cost.

- Detect project stack from `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `docker-compose.yml`, and the project's `CLAUDE.md` Tech Stack section as a tiebreaker.
- For each global skill in `~/.claude/skills/` whose domain doesn't match the stack, propose a per-project `skillOverrides` patch in `<project>/.claude/settings.local.json` (`name-only` for cross-cutting plausible skills; `off` when categorically excluded). The skill stays installed, just silenced for this project. See `skills-auditor` for the full decision matrix.

## Parsing `/context` output

The user typically pastes the breakdown table from the `/context` command. Expected lines look like:

```
⎿ System prompt: 9,567 tokens (4.8%)
⎿ System tools: 9,612 tokens (4.8%)
⎿ Memory files: 12,134 tokens (6.1%)
⎿ Custom agents: 3,923 tokens (2.0%)
⎿ MCP tools: 0 tokens
⎿ Messages: ...
```

Extract per-category token counts with a tolerant regex (tokens may appear with or without commas; label text varies between Claude Code versions). If a file path is given instead of pasted text, read the file.

## Output shape

The analyzer should produce:

```
DOMAIN: context-budget
IDLE TOKENS: N,NNN (P%)

BREAKDOWN:
- system-prompt: ... (not tunable)
- system-tools:  ... (not tunable)
- memory-files:  ... [status]
- skills:        ... [status]
- custom-agents: ... [status]
- mcp-tools:     ... [status]

DRIVERS:
❌ CRITICAL [code] Description — estimated savings: ~N,NNN tokens
⚠️  WARNING  [code] ...
ℹ️  INFO     [code] ...

SUGGESTED ACTIONS (ordered by savings):
1. [defer|remove] [action] — ~N,NNN tokens — risk: low|medium|high
2. ...

COUNTS: critical=N warning=N info=N
```

Every suggested action is tagged **defer** or **remove**. When both are possible for the
same driver, propose the deferral and name the removal as the fallback — never the reverse.
A suggestion list that only ever says "remove" is the failure this section exists to
prevent.

Check codes: `CB-PL` plugin cost, `CB-DU` skill duplication, `CB-MD` memory docs, `CB-CM` CLAUDE.md verbosity, `CB-RF` rules fragmentation, `CB-SR` stack relevance.

## Validation case

The heuristics were calibrated against a real session (`ns_backoffice_ws`, 2026-04-20) with a 22% idle footprint:

- `pr-review-toolkit` plugin: 6 agents × ~600 = ~3.6k tokens, zero recent use → CB-PL CRITICAL.
- MEMORY.md "Key Patterns & Gotchas" entry (>20 lines inline) → CB-MD CRITICAL, move to `.context/references/`.
- Project `test-runner` skill shadowing global `test-runner` with near-identical description → CB-DU WARNING.
- CLAUDE.md (4.4k tokens) with full workspace directory tree → CB-CM WARNING.

Any new heuristic added here should be validated against a second real case before merge.
