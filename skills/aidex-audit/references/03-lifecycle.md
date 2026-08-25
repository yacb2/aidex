# 03 — Finding Lifecycle

State machine for findings in the per-methodology `00-inventory.md`. Every row is
always in exactly one **base status** (canon `00-global.md` §6); lifecycle
modifiers live in their own columns, never embedded in the status.

---

## States (canon base vocabulary)

| Status | Meaning |
|---|---|
| `open` | Observed, not yet acted on. Triage (severity assigned, decision pending) is a **sub-state**: stays `open`, note in the `Notes` column. |
| `doing` | An active plan is executing on this finding. |
| `done` | Terminal-and-tracked: either verified fixed (verifying commit / re-test run in `Notes`) **or** escalated — the work is now tracked elsewhere and the `Escalated To` column carries the marker (`backlog/<…>`, `plan/<…>`, or `loop/<…>` for a bulk machine-checkable finding via `escalate --loop`). |
| `dropped` | Won't fix; documented reason in `Notes`. |

All status values are plain lowercase text — no emojis, no decorations.

### Legacy vocabulary (read-only tolerance)

Boards written by pre-rebuild tooling may still carry the legacy 6-state enum.
The migration map (canon `audit-conventions.md` §Status map) is authoritative:
`triaged → open (+note)` · `escalated → done + Escalated To` · `in-progress →
doing` · `closed → done`. Tooling **reads** legacy values (with a warning) but
only ever **writes** base vocabulary; `/aidex-audit migrate` converts boards.

---

## Transitions

```
open --plan starts--> doing --verify--> done (verifying ref in Notes)
open --escalate-----> done + Escalated To: backlog/<…> | loop/<…>
open --remediate----> doing + Escalated To: loop/<…>   (run-level, whole run)
any  --won't fix----> dropped (reason in Notes)

done --regression--> new REGRESSION-<parent>-<n> row (status: open, links to parent)
```

### Required data per transition

- **open → done (escalate):** backlog entry created — or, for a bulk
  machine-checkable finding, an `aidex-loop` loop-spec (`escalate --loop`). The
  `Escalated To` column gets the **canon marker** (`backlog/<filename>`,
  `loop/<filename>` — D-03 format, never a relative markdown link), and the
  created artifact gets the back-link `origin_ref:
  audit/<methodology>/<run>/<finding-id>` (standalone runs: `audit/<run>/<id>`).
- **open → doing:** plan started; `Escalated To` updated to `plan/<…>` — or a
  run-level remediation loop-spec started (`/aidex-audit remediate <run>`),
  which sets `loop/<…>` on every unresolved row of that run. It stops at
  `doing` on purpose: emitting them `done` would satisfy the loop's own gate
  before any work happened, and the write-back that closes each row would
  have nothing left to move. The single-finding `escalate --loop` path is the
  other direction and still goes straight to `done` — there the loop-spec IS
  where the work is tracked from then on.
- **doing → done (verified):** the verification **marker** in `Notes` — commit
  SHA, PR link, or re-test run (`verified in audit/retest/2026-05-01-post-fixes`)
  — plus an optional proof pointer. `Notes` stays one line; the resolution
  narrative lives in the run's `findings.md` (its role as the per-run journal) or
  `.context/proofs/<id>/`, not in the cell. On close, compress `Notes` to
  `Closed: <commit|run> — <one line>` (canon `audit-conventions.md` §Notes
  discipline).
- **any → dropped:** reason in `Notes`.
- **done → regression:** don't re-open the original row. New row with ID
  `REGRESSION-<parent-id>-<n>`, type `regression`, `Notes` linking the parent.
  The original stays `done`.

---

## Enforcement

`/aidex-audit validate` checks:

- Every `done` row has **either** a non-empty `Escalated To` **or** a verifying
  reference in `Notes` — a bare `done` with neither is flagged.
- Every `doing` row has a non-empty `Escalated To` (the plan doing the work).
- Every `dropped` row has a reason in `Notes`.
- Legacy status values are reported as warnings ("run /aidex-audit migrate"),
  never crashes, and counted under their mapped base status.
- No backlog entry claims `origin_ref: audit/<methodology>/<run>/<id>` for an ID
  that doesn't exist in the inventory.
- No per-run `findings.md` references an ID that doesn't exist in the inventory.

Exit code `1` on any violation; `0` if clean.

---

## Reading the state at a glance

Inventory row format (dates ISO per D-01, `Audit Runs` = comma-separated run-folder slugs (`YYYY-MM-DD-<slug>`)):

```markdown
| BUG-01-3 | bug | auth | Session token in URL | open | P0 | 2026-04-10 | 2026-04-15 | 2026-04-10-pre-release | — | — |
```

The `Status` column determines state. Every row has exactly one, lowercase.

---

## Edge cases

### A finding reopens without being a regression

Rare but legal: the fix was reverted intentionally (conflict with another fix,
strategic reversal). Keep the original row; transition back (`done → doing` if
re-planning). Add the new audit date to `Audit Runs`; document the *why* in
`00-changelog.md` if it has methodology implications.

### A finding is partially fixed

- **Single row, severity dropped:** if the fix reduces severity (P0 → P2),
  update severity and leave `open`.
- **Split into multiple:** if the original was a bundle, split into cleaner
  findings. Original gets `dropped` with reason `[split: see F-045, F-046]`.

### Finding discovered inside a plan's execution

Still a finding — add it to the inventory. Don't bury it in a plan's notes. If
the plan was created to fix a different finding, this one gets its own row and
lifecycle.
