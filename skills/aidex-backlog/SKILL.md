---
name: aidex-backlog
description: Use when the user wants to capture or defer something for later without acting on it now — add it to the backlog, park it, shelve it, queue it, track it, "we'll do this later", "not now but don't forget", a tech-debt entry, or moving an audit finding to the backlog. Fires on "add to the backlog", "add to the backlog the idea of X", "park this for later", "defer this one", "shelve the X idea", "queue this for later", "track this for later", "quick reminder so I don't forget", "move finding <id> to the backlog", "show me the backlog", "list open backlog items", and /aidex-backlog commands. Not for: creating plans (aidex-plan), decisions (aidex-decision), or references (aidex-reference); auditing project state (aidex-audit); ecosystem audits (aidex).
argument-hint: "[--list | --origin manual --title \"<title>\" | --origin audit --finding <id>]"
disable-model-invocation: false
allowed-tools: Bash Read Write
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-backlog"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Backlog

Create and manage consistent, machine-readable entries in `.context/backlog/` with origin tracking and lifecycle (register · list · close).

---

## Sub-actions

| Command | Script | Purpose |
|---|---|---|
| `/aidex-backlog` | [scripts/register-item.sh](scripts/register-item.sh) | Interactive: prompt for title, origin, priority |
| `/aidex-backlog --origin manual --title "<title>"` | same | Non-interactive manual entry |
| `/aidex-backlog --origin audit --finding <id>` | same | From an audit finding (called by `/aidex-audit escalate`) |
| `/aidex-backlog --origin issue --issue <id>` | same | From an issue tracker ID |
| `/aidex-backlog --list` | same | List open entries grouped by priority (P0 → P3 + Blocked) |
| `bash scripts/close-item.sh <BL-id> [--commit <sha>] [--status dropped] [--superseded-by <ref>] [--escalated-to <ref>]` | [scripts/close-item.sh](scripts/close-item.sh) | Atomically close one item: status → record commit → move to `_archive/` → rebuild index (D-10) |
| `bash scripts/defer-item.sh defer <BL-id\|slug> --reason "<blocker>"` | [scripts/defer-item.sh](scripts/defer-item.sh) | Move an open item to `backlog/_deferred/` (open-but-blocked): set/append `blocked_by` → stamp `updated` → rebuild index (`## Deferred` section). Not a close — `status` stays `open` |
| `bash scripts/defer-item.sh reactivate <BL-id\|slug>` | same | Move a deferred item back to the active queue: clear `blocked_by` → stamp `updated` → rebuild index |
| `bash scripts/sweep.sh [--apply]` | [scripts/sweep.sh](scripts/sweep.sh) | Batch-archive items already marked done/dropped that linger in the active folder; rebuild index once. Dry-run by default |
| `bash scripts/reconcile.sh` | [scripts/reconcile.sh](scripts/reconcile.sh) | Read-only cross-artifact drift detector (shared): flags open backlog whose plan is done (close candidates) + done-without-commits. Exit 1 on actionable drift |
| `bash scripts/migrate-ids.sh [--apply]` | [scripts/migrate-ids.sh](scripts/migrate-ids.sh) | Backfill stable `id: BL-NNN` into items predating the id scheme (D-09). Idempotent |
| `bash scripts/install-commit-hook.sh` | [scripts/install-commit-hook.sh](scripts/install-commit-hook.sh) | Wire a repo-local post-commit hook that harvests commit SHAs from trailers into `commits:` (D-09). Idempotent; never global |
| `bash scripts/harvest-commit.sh [--sha <s>] [--message <m>]` | [scripts/harvest-commit.sh](scripts/harvest-commit.sh) | The harvester the hook calls; parses `Backlog:`/`Plan:` trailers and records the SHA. Cross-artifact |
| `bash scripts/migrate-priorities.sh [--dry-run]` | [scripts/migrate-priorities.sh](scripts/migrate-priorities.sh) | Idempotent: normalize legacy `**Priority**: High/Low/...` to P0–P3 codes |

---

## Dispatch

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/register-item.sh" "$@"
```

When invoked with no arguments, the script prompts interactively. When invoked with arguments, it runs non-interactively and is suitable for programmatic use by other skills.

---

## Autonomy — working / sweeping the backlog

When asked to **work or sweep the backlog autonomously**, resolve every safe + additive
item to completion before stopping. Do not halt with "the rest needs your decision":
classify each open item first, and for any you would otherwise pause on, **consult the
[durability-arbiter](../aidex-conventions/agents/durability-arbiter.md)** (Agent tool,
`model: sonnet`, read-only) — pass the item + the standing autonomy surface + proof the
fix is safe. Implement the ones it returns `CONTINUE` for (commit per item; deps and
additive migrations are not gated), and **batch the `ASK`/`STOP` ones into a single
end-of-run list** — never stop the sweep on the first item that needs you. If the arbiter
errors, fall back to the [autonomy canon](../aidex-conventions/references/autonomy-conventions.md)
and proceed. This is the gate that turns "I resolved 2, the other 15 need you" into "I
resolved the 14 safe ones; here are the 3 that are genuinely yours."

---

## Entry format

Each entry is a single dated file: `.context/backlog/YYYY-MM-DD-<slug>.md`.

```markdown
---
title: <one-line title>
id: BL-NNN                      # stable short id for commit-trailer refs (D-09)
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

```
open ⇄ _deferred (blocked) → doing → done / dropped
```

1. **open** — entry created, not yet scheduled
2. **_deferred (blocked)** — open but cannot start: an external blocker exists. The
   item is moved to `backlog/_deferred/`, `status` stays `open`, and `blocked_by`
   MUST be populated. It is **not** in the active queue and is **not** `_archive/`
   (archive is terminal). Use `defer` to park it and `reactivate` to bring it back.
3. **doing** — active work; a plan may exist in `.context/plans/` (link in Notes). If the item's acceptance criterion is machine-checkable (a gate the work should iterate against), it may instead link an `aidex-loop` loop-spec in `.context/loops/`. Default stays a plan.
4. **done** — shipped; archived to `_archive/` **on close** (D-10), not after a delay
5. **dropped** — won't do; reason in Notes; archived on close

Deferring is reversible (open ⇄ `_deferred/`); closing is terminal (→ `_archive/`).

- **Defer/reactivate** moves the file between the active root and `backlog/_deferred/`,
  sets/clears `blocked_by`, stamps `updated`, and rebuilds the index. The `00-index.md`
  lists deferred items under `## Deferred`. Use the `defer` / `reactivate` sub-actions
  rather than moving files or editing `blocked_by` by hand.
- **Closing** an item is an atomic operation (status → record commit → move to
  `_archive/` → rebuild index). Use the `close` sub-action rather than editing
  `status` by hand. The `00-index.md` keeps a one-liner per closed item under
  `## Closed`; full bodies live in `_archive/`.

---

## Commit provenance (D-09)

Record the commits that resolved an item so closure is verifiable, not just
asserted. **Commits live where the work happened:** in the backlog item when fixed
directly (no plan); in the **plan** (per phase) when escalated — never both.

- **Hybrid capture.** Auto-harvest via a commit-message trailer + repo-local
  post-commit hook (`install-commit-hook.sh`); `close-item.sh --commit <sha>` is the
  manual fallback.
- **Trailers:** `Backlog: BL-007` (fixed directly) · `Plan: <slug>#<phase>` (escalated).
- The harvester is idempotent and a silent no-op when no trailer is present.

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
