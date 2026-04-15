---
name: backlog-register
description: Register items in .context/backlog/ with consistent front-matter. Auto-detects origin when called from the audit skill. Triggers on /backlog-register, or phrases like "add to backlog", "park this", "defer", "queue for later", "backlog this idea". Do NOT use for creating plans (that's aidex-conventions) or for auditing.
disable-model-invocation: false
allowed-tools: Bash Read Write
---

# Backlog Register

Create consistent, machine-readable entries in `.context/backlog/` with origin tracking.

---

## Sub-actions

| Command | Script | Purpose |
|---|---|---|
| `/backlog-register` | [scripts/register-item.sh](scripts/register-item.sh) | Interactive: prompt for title, origin, priority |
| `/backlog-register --origin manual --title "<title>"` | same | Non-interactive manual entry |
| `/backlog-register --origin audit --finding <id>` | same | From an audit finding (called by `/audit escalate`) |
| `/backlog-register --origin issue --issue <id>` | same | From an issue tracker ID |
| `/backlog-register --list` | same | List current open entries |

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
priority: P0 | P1 | P2 | P3
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

When called by `/audit escalate <id>`, the skill:

1. Creates the entry with `origin: audit`
2. Sets `origin_ref: audit/<audit-run>/<finding-id>` (e.g., `audit/20260415-login-redesign/BUG-01-3`)
3. Pulls the finding's summary from INVENTORY.md as the entry title
4. Returns the entry path for the caller to link back in INVENTORY

---

## References

- [references/01-backlog-conventions.md](references/01-backlog-conventions.md) — formatting rules, lifecycle, promotion to plan

## Related

- **audit** — uses this skill for escalation (`/audit escalate`)
- **aidex-conventions** — parent convention for `.context/backlog/`
