---
name: aidex-backlog-register
description: Use when the user wants to capture or defer something for later without acting on it now — add it to the backlog, park it, shelve it, queue it, track it, "we'll do this later", "not now but don't forget", a tech-debt entry, or moving an audit finding to the backlog. Fires on "add to the backlog", "add to the backlog the idea of X", "park this for later", "defer this one", "shelve the X idea", "queue this for later", "track this for later", "quick reminder so I don't forget", "move finding <id> to the backlog", "show me the backlog", "list open backlog items", and /aidex-backlog-register commands. Not for: creating plans, decisions, or references (aidex-conventions); auditing project state (aidex-audit); ecosystem audits (aidex).
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "$AIDEX_TRIGGER_EVAL_MARKER"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Backlog Register

Create consistent, machine-readable entries in `.context/backlog/` with origin tracking.

---

## Sub-actions

| Command | Script | Purpose |
|---|---|---|
| `/aidex-backlog-register` | [scripts/register-item.sh](scripts/register-item.sh) | Interactive: prompt for title, origin, priority |
| `/aidex-backlog-register --origin manual --title "<title>"` | same | Non-interactive manual entry |
| `/aidex-backlog-register --origin audit --finding <id>` | same | From an audit finding (called by `/aidex-audit escalate`) |
| `/aidex-backlog-register --origin issue --issue <id>` | same | From an issue tracker ID |
| `/aidex-backlog-register --list` | same | List open entries grouped by priority (P0 → P3 + Blocked) |
| `bash scripts/migrate-priorities.sh [--dry-run]` | [scripts/migrate-priorities.sh](scripts/migrate-priorities.sh) | Idempotent: normalize legacy `**Priority**: High/Low/...` to P0–P3 codes |

---

## Dispatch

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/register-item.sh" "$@"
```

When invoked with no arguments, the script prompts interactively. When invoked with arguments, it runs non-interactively and is suitable for programmatic use by other skills.

---

## Entry format

Each entry is a single dated file: `.context/backlog/YYYYMMDD-<slug>.md`.

```markdown
---
title: <one-line title>
status: open | doing | done | dropped
origin: manual | audit | issue | request
origin_ref: <reference — finding ID, issue ID, request file, or empty>
priority: P0 | P1 | P2 | P3   # code only, never free text — see references/01-backlog-conventions.md
blocked_by: ""                # optional, when waiting on third party (priority stays)
estimate: XS | S | M | L | XL
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# <title>

## Context

<what prompted this, why it's worth doing>

## Acceptance

- [ ] <criterion 1>
- [ ] <criterion 2>

## Notes

<any other relevant detail>
```

---

## Lifecycle

1. **open** — entry created, not yet scheduled
2. **doing** — active work; a plan may exist in `.context/plans/` (link in Notes)
3. **done** — shipped; typically archived after a cycle
4. **dropped** — won't do; reason in Notes

Transition by updating the `status` field and the `updated` date.

---

## Integration with audits

When called by `/aidex-audit escalate <id>`, the skill:

1. Creates the entry with `origin: audit`
2. Sets `origin_ref: audit/<audit-run>/<finding-id>` (e.g., `audit/20260415-login-redesign/BUG-01-3`)
3. Pulls the finding's summary from INVENTORY.md as the entry title
4. Returns the entry path for the caller to link back in INVENTORY

---

## References

- [references/01-backlog-conventions.md](references/01-backlog-conventions.md) — formatting rules, lifecycle, promotion to plan

## Related

- **aidex-audit** — uses this skill for escalation (`/aidex-audit escalate`)
- **aidex-conventions** — parent convention for `.context/backlog/`
