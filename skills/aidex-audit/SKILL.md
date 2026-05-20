---
name: aidex-audit
description: Use when the user wants to assess the state of a feature, flow, or module — a UX, security, performance, or accessibility audit; cataloging bugs, gaps, and opportunities; retesting open findings; escalating a finding to the backlog; or updating audit methodology. Fires on "I want to do a UX / security / performance / accessibility audit", "before we ship I want to audit X", "audit the X flow or module", "catalog the state of X", "list bugs and gaps in X", "retest open findings", "register a finding under audit X", "escalate finding <id> to backlog", and /aidex-audit commands. Not for: auditing the Claude Code setup itself like skills or MEMORY.md (aidex); creating plans or decisions (aidex-conventions); generic backlog items not from a finding (aidex-backlog-register).
argument-hint: "[new <type> <slug> | validate [path] | escalate <finding-id> | migrate [project-dir]]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Audit — Project State Catalog

Operate the `.context/audits/` convention: scaffold new audit runs, validate coherence, escalate findings to backlog, migrate legacy folders out of `plans/`.

See [audit-conventions](../aidex-conventions/references/audit-conventions.md) for the full convention.

---

## Sub-actions

Dispatch by first argument:

| Command | Script | Purpose |
|---|---|---|
| `/aidex-audit` | — | Show help + current state of `.context/audits/` |
| `/aidex-audit new <type> <slug>` | [scripts/new-audit.sh](scripts/new-audit.sh) | Scaffold a new audit run |
| `/aidex-audit validate [path]` | [scripts/validate-audit.sh](scripts/validate-audit.sh) | Check coherence INVENTORY ↔ findings ↔ backlog |
| `/aidex-audit escalate <finding-id>` | [scripts/escalate-finding.sh](scripts/escalate-finding.sh) | Move finding to backlog |
| `/aidex-audit migrate [project-dir]` | [scripts/migrate-audit.sh](scripts/migrate-audit.sh) | Move legacy audit-like folders from `plans/` |

### Supported audit types (for `new`)

`ux-audit` · `ia-opportunities` · `retest` · `security-audit` · `perf-audit` · `a11y-audit` · `custom`

See [references/04-playbooks.md](references/04-playbooks.md) for when to pick each.

---

## Dispatch logic

When invoked with arguments, the skill runs:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/${ACTION}.sh" "$@"
```

Where `${ACTION}` maps from the first argument:

- `new` → `new-audit.sh <type> <slug>`
- `validate` → `validate-audit.sh [path]`
- `escalate` → `escalate-finding.sh <finding-id>`
- `migrate` → `migrate-audit.sh [project-dir]`

If no arguments are given, show the help table above and run a status check:

```bash
# Quick status (when invoked with no args):
if [ -d .context/audits ]; then
  ls -1 .context/audits/*/index.md 2>/dev/null | wc -l  # audit run count
  grep -c "^| " .context/audits/INVENTORY.md 2>/dev/null  # finding count
  head -30 .context/audits/CHANGELOG.md 2>/dev/null  # latest methodology changes
fi
```

---

## Workflows

### Starting fresh

```
/aidex-audit new ux login-redesign
```

Scaffolds:
- `.context/audits/YYYYMMDD-login-redesign/index.md`
- `.context/audits/YYYYMMDD-login-redesign/findings.md`
- `.context/audits/INVENTORY.md` (if missing)
- `.context/audits/METHODOLOGY.md` (if missing)
- `.context/audits/CHANGELOG.md` (if missing)
- `.context/audits/methodology/ux-audit.md` (if missing)

### Running an audit

1. Open the `methodology/<type>.md` playbook.
2. Walk through checks in scope.
3. Add rows to `INVENTORY.md` for each finding.
4. Reference IDs from this run's `findings.md` (filtered view).
5. Close out `index.md` summary.

### After the audit

```
/aidex-audit validate          # verify coherence
/aidex-audit escalate BUG-01-1 # one finding at a time → backlog
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
2. **INVENTORY as single source of truth** — per-run findings are views
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

- Core: INVENTORY.md, METHODOLOGY.md, CHANGELOG.md, index.md, findings.md
- Playbooks: `methodology/<type>.md.template` for each of six stock types

## Related

- **aidex-conventions** — defines the audit convention itself
- **aidex-backlog-register** — handles the other side of escalation (`/aidex-backlog-register --origin audit --finding <id>`)
- **aidex** — audits the audits directory for coherence as part of overall ecosystem health
