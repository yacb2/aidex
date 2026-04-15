# 03 — Finding Lifecycle

State machine for findings in `INVENTORY.md`. Every row is always in exactly one state.

---

## States

| State | Meaning |
|---|---|
| `open` | Observed, not yet acted on |
| `triaged` | Assessed, severity assigned, decision pending |
| `escalated` | Accepted for work; backlog entry created |
| `in-progress` | Active plan is executing on this finding |
| `closed` | Verified fixed; has a verifying reference |
| `dropped` | Won't fix; has a documented reason |

All state values are plain text — no emojis, no decorations. The validator parses them as lowercase strings.

---

## Transitions

```
open --triage--> triaged --escalate--> escalated --start--> in-progress --verify--> closed
 |                 |                       |                      |
 +-----------------+-----------------------+----------------------+---> dropped (any state, with reason)

closed --regression--> new REGRESSION-<parent>-<n> row (state: open, links to parent)
```

---

## Required data per transition

### open → triaged

- Severity assigned (P0–P3)
- Optional: owner or triage notes

### triaged → escalated

- Backlog entry created
- `Escalated To:` column updated with link to the entry

### escalated → in-progress

- Plan started; link in `Escalated To:` updated to the plan folder/file

### in-progress → closed

- Verification: commit SHA, PR link, or re-test audit run
- `Escalated To:` appended with e.g. `fix:abc1234 · verified in audits/20260501-retest`

### any → dropped

- Reason in the row's notes (column "Dropped reason" or inline in Summary as `[DROPPED: <reason>]`)

### closed → regression

- Don't re-open the original row. Create a new row with ID `REGRESSION-<parent-id>-<n>`:
  - Type: `regression`
  - Notes: links back to the original ID
  - The original stays `closed`

---

## Enforcement

`/audit validate` checks:

- Every row with status `escalated`, `in-progress`, or `closed` has a non-empty `Escalated To:`
- Every `dropped` row has a reason recorded
- No backlog entry claims `origin_ref: audit/<run>/<id>` for an ID that doesn't exist in INVENTORY
- No per-run `findings.md` references an ID that doesn't exist in INVENTORY

Exit code `1` on any violation; `0` if clean.

---

## Reading the state at a glance

INVENTORY row format reminder:

```markdown
| BUG-01-3 | bug | auth | Session token in URL | open | P0 | 20260410 | 20260415 | 20260410,20260415 | — |
```

The `Status` column is what determines state. Every row has exactly one, in lowercase.

---

## Edge cases

### A finding reopens without being a regression

Rare but legal: the fix was reverted intentionally (conflict with another fix, strategic reversal).

- Keep the original row; transition back through states (`closed` → `in-progress` again if re-planning).
- Note the reversal in `First Seen` column's accompanying row as a new audit date.
- Document the *why* in `CHANGELOG.md` if it represents a methodology implication.

### A finding is partially fixed

One of two approaches:

- **Single row, severity dropped:** if the fix reduces severity (P0 → P2), update severity and leave open.
- **Split into multiple:** if the original finding was a bundle, split into cleaner findings. Original gets `dropped` with reason `[split: see F-045, F-046]`.

### Finding discovered inside a plan's execution

Still a finding — add to INVENTORY. Don't bury it in a plan's notes. If the plan was created to fix a different finding, this one gets its own row and own lifecycle.
