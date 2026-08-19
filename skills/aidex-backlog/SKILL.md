---
name: aidex-backlog
description: 'Use when the user wants to capture or defer something for later without acting on it now — add it to the backlog, park it, shelve it, queue it, track it, "we''ll do this later", "not now but don''t forget", a tech-debt entry, or moving an audit finding to the backlog. Fires on "add to the backlog", "add to the backlog the idea of X", "park this for later", "defer this one", "shelve the X idea", "queue this for later", "track this for later", "quick reminder so I don''t forget", "move finding <id> to the backlog", "show me the backlog", "list open backlog items", and /aidex-backlog commands. Not for: creating plans (aidex-plan), decisions (aidex-decision), or references (aidex-reference); auditing project state (aidex-audit); ecosystem audits (aidex).'
argument-hint: "[--list | --origin manual --title \"<title>\" | --origin audit --finding <id>]"
disable-model-invocation: false
allowed-tools: Bash Read Write Agent
model-policy: per-stage
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
| `/aidex-backlog --check-ids` | same | Read-only id guard: duplicate or non-`BL-NNN` ids. Exit 1 on any. Unlike `--reindex`, writes nothing |
| `bash scripts/start-item.sh <BL-id\|slug>` | [scripts/start-item.sh](scripts/start-item.sh) | Open the item for work: `status` → `doing` → stamp `updated` → rebuild index. **When the item carries `type: bug`, it prints the RED→GREEN route** — that front-matter field, not any bug-report phrasing, is what enters the procedure (BL-134) |
| `bash scripts/close-item.sh <BL-id> [--commit <sha>] [--status dropped] [--superseded-by <ref>] [--escalated-to <ref>]` | [scripts/close-item.sh](scripts/close-item.sh) | Atomically close one item: status → record commit → move to `_archive/` → rebuild index (D-10) |
| `bash scripts/defer-item.sh defer <BL-id\|slug> --reason "<blocker>"` | [scripts/defer-item.sh](scripts/defer-item.sh) | Move an open item to `backlog/_deferred/` (open-but-blocked): set/append `blocked_by` → stamp `updated` → rebuild index (`## Deferred` section). Not a close — `status` stays `open` |
| `bash scripts/defer-item.sh reactivate <BL-id\|slug>` | same | Move a deferred item back to the active queue: clear `blocked_by` → stamp `updated` → rebuild index |
| `/aidex-backlog worklist new\|advance\|close <args>` | [aidex-conventions/scripts/worklist-*.sh](../aidex-conventions/scripts/) | The run-queue lifecycle. Delegates to the canon hub's scripts, which is where they stay — a work-list is cross-source (backlog + plans + audits), so no single artifact skill owns its *content*. This skill owns the **entry point**, because "resolve these in a row" is what creates one (ADR 2026-08-06) |
| `/aidex-backlog triage [--quiet]` | [scripts/triage.sh](scripts/triage.sh) | **The backlog's health in one read-only pass**: id shape/duplicates + archive sweep + cross-artifact drift, one consolidated report. Prints the fix commands, runs none of them; exit 1 on anything actionable, so it can gate CI |
| `bash scripts/sweep.sh [--apply\|--check]` | [scripts/sweep.sh](scripts/sweep.sh) | Batch-archive items already marked done/dropped that linger in the active folder; rebuild index once. Dry-run by default; `--check` is the dry-run that exits 1 on findings |
| `bash scripts/reconcile.sh` | [scripts/reconcile.sh](scripts/reconcile.sh) | Read-only cross-artifact drift detector (shared): flags open backlog whose plan is done (close candidates) + done-without-commits. Exit 1 on actionable drift |
| `bash scripts/migrate-ids.sh [--apply]` | [scripts/migrate-ids.sh](scripts/migrate-ids.sh) | Backfill stable `id: BL-NNN` into items predating the id scheme (D-09). Idempotent. **Only safe where every existing id already conforms** — it skips any file that has an id, and feeds every id's digits into its max, so one legacy `BL-20260610` makes it mint `BL-20260611`. Use `renumber-ids.py` where that is the case |
| `python3 scripts/renumber-ids.py [--apply]` | [scripts/renumber-ids.py](scripts/renumber-ids.py) | Make the **open queue's** ids conforming: insert one where absent, replace a nonconforming one and rewrite every citation of the old code. `_archive/`/`_deferred/` keep theirs, so citations from closed work stay valid. New ids allocate above the project's highest conforming id. Dry-run by default; tars `.context/` to `_tmp/` before writing |
| `python3 scripts/migrate-filenames.py [--apply]` | [scripts/migrate-filenames.py](scripts/migrate-filenames.py) | Move open items to `YYYY-MM-DD-bl-nnn-<slug>.md` and rewrite every inbound reference in the same pass. Skips — and reports — items with a non-`BL-NNN` id, a duplicate id, or a filename cited in a git commit message. Proves itself by counting dangling backlog refs before and after and requiring them equal. Dry-run by default; same `_tmp/` backup |
| `bash scripts/install-commit-hook.sh` | [scripts/install-commit-hook.sh](scripts/install-commit-hook.sh) | Wire a repo-local post-commit hook that harvests commit SHAs from trailers into `commits:` (D-09). Idempotent; never global |
| `bash scripts/harvest-commit.sh [--sha <s>] [--message <m>]` | [scripts/harvest-commit.sh](scripts/harvest-commit.sh) | The harvester the hook calls; parses `Backlog:`/`Plan:` trailers and records the SHA. Cross-artifact |
| `bash scripts/migrate-priorities.sh [--apply]` | [scripts/migrate-priorities.sh](scripts/migrate-priorities.sh) | Idempotent: normalize legacy `**Priority**: High/Low/...` to P0–P3 codes. Dry-run by default |
| `python3 scripts/estimate-calibration.py [--from <dir>] [--project <p>]` | [scripts/estimate-calibration.py](scripts/estimate-calibration.py) | **A read, never a gate** (BL-131): scores closed items' `estimate:` against realized effort from the usage-retro miner, per bucket, with median **and** p90/max plus tail concentration. Prints no single accuracy number — one would average the flat middle with the spreading tail. Not wired into any lifecycle script and never blocks a run; it is measurement feedback, not a prompt for a better estimate. A full run mines the corpus (~4 min); `--from` reuses a previous run |

---

## Dispatch

```bash
# Bare-word sub-actions route to their own script; everything else is register-item.sh,
# which owns the flag interface. Without this, `/aidex-backlog triage` reached
# register-item.sh and died on "unknown option: triage".
case "${1:-}" in
  triage)   shift; bash "${CLAUDE_SKILL_DIR}/scripts/triage.sh" "$@" ;;
  worklist) sub="${2:-}"; shift 2
            bash "${CLAUDE_SKILL_DIR}/../aidex-conventions/scripts/worklist-${sub}.sh" "$@" ;;
  *)        bash "${CLAUDE_SKILL_DIR}/scripts/register-item.sh" "$@" ;;
esac
```

When invoked with no arguments, the script prompts interactively. When invoked with arguments, it runs non-interactively and is suitable for programmatic use by other skills.

---

## Autonomy — working / sweeping the backlog

When asked to **work several items in a row** ("resuelve los backlogs seguidos"), first
fix the order **once** via the `AskUserQuestion` survey → a durable
`.context/worklists/` work-list (`worklist-new.sh` — **read**
`~/.claude/skills/aidex-conventions/references/worklist-conventions.md` **before writing
one**: it holds the queue format, the gate-policy block, and which of the three classes
of mid-run question the queue is meant to absorb), then walk it with `worklist-advance.sh` instead of
pausing between items to ask "what next?" (the dominant un-governed stop). The survey
may fold in plan/audit refs too — the work-list is cross-source, not backlog-only.

**On each item the walk lands on, run `start-item.sh <BL-id>` before working it.**
That is the transition to `doing` and, for `type: bug`, the route into RED→GREEN —
`worklist-advance.sh` only names the next item, it does not open it.

When asked to **work or sweep the backlog autonomously**, resolve every safe + additive
item to completion before stopping. Do not halt with "the rest needs your decision":
classify each open item first, and for any you would otherwise pause on, **consult the
[durability-arbiter](../aidex-conventions/agents/durability-arbiter.md)** (Agent tool,
`model: sonnet`, `effort: high`, read-only — `model-policy: per-stage`, so the gate's
depth is pinned here and never inherited from the run asking to be judged) — pass the item + the standing autonomy surface + proof the
fix is safe. Implement the ones it returns `CONTINUE` for (commit per item; deps and
additive migrations are not gated), and **batch the `ASK`/`STOP` ones into a single
end-of-run list** — never stop the sweep on the first item that needs you. If the arbiter
errors, fall back to the [autonomy canon](../aidex-conventions/references/autonomy-conventions.md)
and proceed. This is the gate that turns "I resolved 2, the other 15 need you" into "I
resolved the 14 safe ones; here are the 3 that are genuinely yours."

---

## Entry format

Each entry is a single dated file: `.context/backlog/YYYY-MM-DD-bl-nnn-<slug>.md`, written by
`register-item.sh` — front-matter followed by a Context / Acceptance / Notes body.

The complete front-matter schema is the single-source **12-field table** in
[references/01-backlog-conventions.md](references/01-backlog-conventions.md#front-matter-required)
(`id` and `commits` are machine-required — the lifecycle breaks without them). Don't
re-copy the schema here; author entries via the script or straight from that table.

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
3. **doing** — active work, opened with `start-item.sh` rather than by editing
   `status` by hand. That script is also the **bug route**: an item with
   `type: bug` prints the RED→GREEN procedure on start, so bug work enters the
   regression-test-first cycle from the backlog lifecycle instead of depending on
   a bug-report phrasing that tracked work never uses (BL-134). A plan may exist in `.context/plans/` (link in Notes). If the item's acceptance criterion is machine-checkable (a gate the work should iterate against), it may instead link an `aidex-loop` loop-spec in `.context/loops/`. Default stays a plan.
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

## Self-check (mandatory close step)

Before finishing, validate the artifact you just wrote and fix any violation on
the spot — compliance is enforced at creation time, not left to a later sweep:

```bash
python3 ~/.claude/skills/aidex-conventions/scripts/validate.py --type backlog
```

If the project carries a ratchet baseline (`.context/.validate-baseline.json`),
a non-zero exit means you introduced a NEW violation — fix it before closing.

## Related

- **aidex-audit** — uses this skill for escalation (`/aidex-audit escalate`)
- **aidex-conventions** — parent convention for `.context/backlog/`
- **aidex-dash** — renders the backlog as an interactive HTML board on demand (`render.sh backlog`); publishing stays user-gated
