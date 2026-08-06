---
name: aidex-audit
description: Use when the user wants to assess the state of a feature, flow, or module — a UX, security, performance, or accessibility audit; cataloging bugs, gaps, and opportunities; retesting open findings; escalating a finding to the backlog; or updating audit methodology. Fires on "I want to do a UX / security / performance / accessibility audit", "before we ship I want to audit X", "audit the X flow or module", "catalog the state of X", "list bugs and gaps in X", "retest open findings", "register a finding under audit X", "escalate finding <id> to backlog", and /aidex-audit commands. Not for: auditing the Claude Code setup itself like skills or MEMORY.md (aidex); creating plans or decisions (aidex-conventions); generic backlog items not from a finding (aidex-backlog).
argument-hint: "[new <type|--standalone> <slug> | validate [path] | escalate <finding-id> [--loop] | close <run> | reindex | migrate [project-dir]]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-audit"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Audit — Project State Catalog

Operate the `.context/audits/` convention: scaffold new audit runs, validate coherence, escalate findings to backlog, migrate legacy folders out of `plans/`.

See [audit-conventions](../aidex-conventions/references/audit-conventions.md) for the full convention.

## Default autonomy

On run start, apply [Mode A autonomy](../aidex-conventions/references/autonomy-conventions.md)
automatically — do not wait for the user to grant it. Questions live in the
initial alignment moment only; after that the run proceeds start-to-finish per
the shared canon (deny/pre-authorized/mandated/autonomous). See "Sweep doctrine"
below for how this applies once a sweep is running.

---

## Sub-actions

Dispatch by first argument:

| Command | Script | Purpose |
|---|---|---|
| `/aidex-audit` | — | Show help + current state of `.context/audits/` |
| `/aidex-audit new <type> <slug>` | [scripts/new-audit.sh](scripts/new-audit.sh) | Scaffold a new audit run |
| `/aidex-audit validate [path]` | [scripts/validate-audit.sh](scripts/validate-audit.sh) | Check coherence INVENTORY ↔ findings ↔ backlog |
| `/aidex-audit escalate <finding-id>` | [scripts/escalate-finding.sh](scripts/escalate-finding.sh) | Move finding to backlog |
| `/aidex-audit escalate <finding-id> --loop` | [scripts/escalate-finding-to-loop.sh](scripts/escalate-finding-to-loop.sh) | Escalate a **bulk, machine-checkable** finding to an `aidex-loop` loop-spec instead of the backlog (see guard below) |
| `/aidex-audit migrate [project-dir]` | [scripts/migrate-audit.sh](scripts/migrate-audit.sh) | Move legacy audit-like folders from `plans/` |
| `/aidex-audit close <run> [--force]` | [scripts/close-audit.sh](scripts/close-audit.sh) | Archive a run folder on cycle close (D-10) once in-scope findings are resolved; rolling inventory stays. `--force` for upstream/out-of-scope findings |
| `/aidex-audit reindex` | [scripts/reindex-audits.sh](scripts/reindex-audits.sh) | Regenerate the run-level roll-up `00-index.md` (all runs + per-run finding counts). Auto-run by `new` and `close`. `--check` reports drift read-only (used by `validate` + shared `reconcile.sh`) |
| `/aidex-audit coverage-matrix` | [scripts/coverage-matrix.sh](scripts/coverage-matrix.sh) | Regenerate the breadth matrix (modules × tests; surface counts in the `.json`) from `module-map.json` — generated artifact, never hand-edited |
| `/aidex-audit coverage-sweep [--since ISO]` | [scripts/coverage-sweep.sh](scripts/coverage-sweep.sh) | Drift report: which modules changed without their tests moving since the last matrix — suggests re-runs, advisory only |
| `/aidex-audit affected-tests [--since <ref>]` | [scripts/affected-tests.sh](scripts/affected-tests.sh) | Map current diff → affected modules → which tests to run (module-level, advisory) |

> **`--loop` guard (anti-cargo-cult).** Use `--loop` **ONLY** when the finding is
> bulk + machine-checkable — a gate the machine can run to say pass/fail across many
> sites (lint clean / contrast ratios / type-clean / remove-all-X). Single fixes and
> ideas go to the backlog (plain `escalate`, no flag). **Never auto-loop**: the
> operator still writes the exact Stop condition and picks an engine before the loop
> runs. If there is no machine gate, it is not a loop — escalate to backlog.

### Supported audit types (for `new`)

`ux` · `ai-opportunities` · `security` · `perf` · `a11y` · `hitl` · `retest` ·
`test-coverage` · `docs-coverage` · `rule-ablation` · `custom` — short English names per
`decision/2026-07-02-audit-rebuild-canon-decisions`; the legacy `-audit`-suffixed and
`ia-opportunities` forms are accepted as input aliases and normalized, as is the
`coverage` short form for `test-coverage` and `docs`/`documentation` for `docs-coverage`. For a **one-shot analysis with no recurring
methodology**, use `new --standalone <slug>`: it scaffolds a dated run folder
directly under `audits/` with no boards (canon §Standalone one-shot runs).

See [references/04-playbooks.md](references/04-playbooks.md) for when to pick each.

---

## Dispatch logic

When invoked with arguments, the skill runs:

```bash
# escalate routes to the loop variant when --loop is present; otherwise the table maps 1:1.
if [ "$ACTION" = "escalate" ] && printf '%s\n' "$@" | grep -q -- '--loop'; then
  bash "${CLAUDE_SKILL_DIR}/scripts/escalate-finding-to-loop.sh" "$@"
else
  bash "${CLAUDE_SKILL_DIR}/scripts/${ACTION}.sh" "$@"
fi
```

Where `${ACTION}` maps from the first argument:

- `new` → `new-audit.sh <type> <slug>`
- `validate` → `validate-audit.sh [path]` — every finding prints its rule id; accept one by adding a line to `.context/.aidex-waivers` (same store and format as `validate.py`, canon `00-global.md` §10.1)
- `escalate` → `escalate-finding.sh <finding-id>` — unless `--loop` is present, then `escalate-finding-to-loop.sh <finding-id> --loop`
- `migrate` → `migrate-audit.sh [project-dir]`
- `reindex` → `reindex-audits.sh`
- `close` → `close-audit.sh <run> [--force]`
- `coverage-matrix` → `coverage-matrix.sh`
- `coverage-sweep` → `coverage-sweep.sh [--since ISO]`
- `affected-tests` → `affected-tests.sh [--since <ref>]`

If no arguments are given, show the help table above and run a status check:

```bash
# Quick status (when invoked with no args):
if [ -d .context/audits ]; then
  bash "${CLAUDE_SKILL_DIR}/scripts/reindex-audits.sh" >/dev/null 2>&1  # refresh roll-up
  cat .context/audits/00-index.md                                      # run-level state
  # Changelogs live per methodology (D-02). The root path is legacy-only —
  # migrate-audit.sh leaves it in place without --methodology — so it is a
  # fallback, not the primary read.
  for cl in .context/audits/*/00-changelog.md .context/audits/00-changelog.md; do
    [ -f "$cl" ] && { echo "== $cl"; head -15 "$cl"; }
  done
fi
```

---

## Workflows

### Starting fresh

```
/aidex-audit new ux login-redesign
```

Scaffolds the canon per-methodology layout (D-02):
- `.context/audits/ux/2026-07-02-login-redesign/index.md`
- `.context/audits/ux/2026-07-02-login-redesign/findings.md`
- `.context/audits/ux/00-inventory.md` (if missing)
- `.context/audits/ux/00-methodology.md` (if missing — seeded from the type's playbook)
- `.context/audits/ux/00-changelog.md` (if missing)

For a one-shot analysis (no recurring methodology):

```
/aidex-audit new --standalone usage-retro-q3
```

Scaffolds only `.context/audits/2026-07-02-usage-retro-q3/index.md` — no boards
(canon §Standalone one-shot runs; escalation uses `origin_ref: audit/<run>/<id>`).

### Running an audit

**Front-load the area order (work-list).** At kickoff, after scope/borders, emit the
audit's areas/findings in execution order as a durable
[`.context/worklists/`](../aidex-conventions/references/worklist-conventions.md)
work-list (via the `AskUserQuestion` survey → `worklist-new.sh`). The sweep then walks
areas with `worklist-advance.sh` instead of pausing to ask "next area?" between them —
the one ordering decision is fixed once, up front. (For a fan-out Workflow run below,
the same ordered areas become the shards.) **No interactive channel** (`claude -p`,
cron): skip the survey, emit the areas in the order scope/borders produced them, and note
the defaulting in the audit brief —
[autonomy-conventions.md § When there is no interactive channel](../aidex-conventions/references/autonomy-conventions.md).

> **Durable Workflow promotion (mandatory evaluation at kickoff).** At `/aidex-audit new`
> — the single sanctioned question point, before the sweep begins — classify whether the
> audit has enough independent dimensions or shards to amortize the ~22k/agent Workflow
> floor. If yes, **propose the durable fan-out Workflow form in one line, batched with the
> kickoff scope questions** — e.g. "12 independent dimensions -> run as a durable Workflow
> (fan-out of analysts, schema-gated, arbiter at the escalate gate)? else in-process sweep."
> A one-word "yes" is the opt-in: invoking this skill plus this proposal **is** the
> sanctioned authorization to call the `Workflow` tool — no `ultracode` needed.
> If the audit does not qualify (few dimensions, small scope, not unattended), run the
> normal in-process sweep and **do not ask**. This is a kickoff question, **never a
> mid-sweep interruption**.
>
> **Model guard (before launching the fan-out Workflow).** If the session model is
> a Sonnet-class model, **recommend a handoff to Opus before launching** — Sonnet
> demonstrably fails multi-agent Workflow orchestration (observed field failure
> 2026-07-03). Surface this with the kickoff proposal, never as a mid-sweep
> interruption; the in-process sweep is unaffected.
>
> The fan-out form ships as
> [`assets/workflows/audit-fanout.workflow.js`](assets/workflows/audit-fanout.workflow.js),
> which embeds the single-sourced durability CORE
> ([`../aidex-conventions/references/workflow-core.md`](../aidex-conventions/references/workflow-core.md))
> and is covered by the drift-lock test.

1. Open the `methodology/<type>.md` playbook.
2. Walk through checks in scope.
3. Add rows to `00-inventory.md` for each finding.
4. Reference IDs from this run's `findings.md` (filtered view).
5. Close out `index.md` summary.

> **Sweep doctrine (autonomy).** Scope and borders are set at kickoff
> (`/aidex-audit new`) — that is the initial phase where any question is asked.
> After that the run is an **uninterrupted sweep**: catalog each finding with your
> best-judgment severity and **log the assumption** — do not stop to ask whether
> something is worth noting. Escalation to backlog/loop is the explicit border (the
> separate `escalate` sub-action); for security audits, active exploitation or
> destructive verification is `deny`. Full rule:
> [autonomy-conventions.md](../aidex-conventions/references/autonomy-conventions.md).
>
> **Don't pause at the escalate gate.** When net-new findings exist, escalating the
> confirmed ones to backlog is the mandated next step — not an "escalate, or triage
> yourself?" question. If a specific finding is genuinely ambiguous to escalate,
> consult the [durability-arbiter](../aidex-conventions/agents/durability-arbiter.md)
> (Agent tool, `model: sonnet`, `effort: high`, read-only) per finding and batch any `ASK` to the
> end — never stall the whole sweep on one finding.
>
> **Isolation.** An audit is read-mostly — usually no worktree (Tier 0/1). The
> exception is a security audit that needs **destructive verification**: run it in an
> isolated worktree + DB (Tier 2) so it never mutates real state. See
> [worktree-conventions.md](../aidex-conventions/references/worktree-conventions.md).

### After the audit

```
/aidex-audit validate              # verify coherence
/aidex-audit escalate BUG-01-1     # one finding at a time → backlog
/aidex-audit escalate A11Y-02-1 --loop  # bulk, machine-checkable finding → loop-spec
```

### Re-testing

```
/aidex-audit new retest post-sprint-5
```

Open the retest playbook; for each previously-open finding, classify (fixed / still open / regression / new adjacent) and update INVENTORY in place.

### Legacy migration

If audits have accumulated inside `.context/plans/`:

```
/aidex-audit migrate
```

Launches the `audit-migrator` subagent to detect candidates, proposes moves, then runs `inventory-seeder` to generate initial INVENTORY from existing findings.

### When to run the sweep

`/aidex-audit coverage-sweep` is a drift check, not a calendar chore: run it at the
natural moments when src is likely to have outpaced tests —

- after a **feature push** on a tracked module,
- after **closing a plan** that touched tracked paths,
- after **any incident** (something broke → coverage was probably thin there).

It is advisory (always exits 0): a ranked table of modules whose src commits moved
without their tests since the last matrix. Act on the flagged rows with
`/aidex-audit new test-coverage <slug>` scoped to them, then regenerate the matrix.
`aidex-plan-exec` (at plan close) and `aidex-bugfix` (at GREEN) surface a one-line
suggestion to run it (Phase 6).

---

## Subagents

| Agent | Model | Purpose |
|---|---|---|
| [audit-migrator](agents/audit-migrator.md) | haiku | Detects audit-like folders in `.context/plans/` using file-presence heuristics. Read-only. |
| [inventory-seeder](agents/inventory-seeder.md) | sonnet | Reads scattered findings from legacy folders and generates INVENTORY rows in canonical format. |

Scripts delegate to these agents when needed. Direct use is also fine during manual migration work.

---

## Principles

Quick summary — full detail in [references/01-principles.md](references/01-principles.md):

1. **Finding ≠ Issue ≠ Task** — distinct objects with links, not copies
2. **INVENTORY as single source of truth** — per-run findings are views. The auto-generated `00-index.md` is the *run-level* roll-up (which runs exist, open/closed, finding counts) — complementary to `00-inventory.md`, which is the *finding-level* board. Do not hand-edit `00-index.md`.
3. **Living methodology** — CHANGELOG records every methodology change
4. **Findings never deleted** — use status transitions
5. **Escalation flow** — audit → backlog → plan → commit → re-test → closed
6. **Shared concerns flagged** `[SHARED]` in Module column

---

## References

- [01-principles.md](references/01-principles.md) — six core principles explained
- [02-id-conventions.md](references/02-id-conventions.md) — structured vs global IDs
- [03-lifecycle.md](references/03-lifecycle.md) — finding state machine
- [04-playbooks.md](references/04-playbooks.md) — when to pick which audit type
- [05-migration-guide.md](references/05-migration-guide.md) — moving from legacy `plans/` layout
- [audit-conventions.md](../aidex-conventions/references/audit-conventions.md) — full convention doc

## Templates

All templates in [assets/templates/](assets/templates/):

- Core: 00-inventory.md, 00-methodology.md, 00-changelog.md, index.md, findings.md
- Playbooks: `methodology/<type>.md.template` for each of nine stock types

## Related

- **aidex-conventions** — defines the audit convention itself
- **aidex-backlog** — handles the other side of escalation (`/aidex-backlog --origin audit --finding <id>`)
- **aidex-dash** — renders inventory boards and the coverage matrix as interactive HTML on demand (`render.sh audit <methodology>` / `render.sh coverage`); publishing stays user-gated
- **aidex** — audits the audits directory for coherence as part of overall ecosystem health
