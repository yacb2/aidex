# 01 — Core Principles

Six principles that shape the `.context/audits/` convention. Each addresses a specific failure mode observed when projects mix audits with plans or keep findings scattered.

---

## 1. Finding ≠ Issue ≠ Task

Three distinct objects at three distinct points in the lifecycle:

| Object | Lives in | Represents | Identity |
|---|---|---|---|
| **Finding** | `.context/audits/INVENTORY.md` | Observation: "this is how the system is" | `<CATEGORY>-<MODULE>-<N>` |
| **Backlog entry** | `.context/backlog/` | Queued work: "we plan to do something about this" | `YYYYMMDD-<slug>.md` |
| **Task / plan** | `.context/plans/` | Active work: "we are doing this now" | `YYYYMMDD-<slug>/` or `.md` |

**Why:** conflating them loses information. A finding may escalate to multiple tasks, be dropped, or stay open indefinitely. Each object has its own lifecycle and audience.

**Practical:** never copy finding text into a backlog or plan. Always link. The finding stays the authoritative description; the backlog entry captures scope; the plan describes execution.

---

## 2. INVENTORY as single source of truth

`INVENTORY.md` is the canonical, deduplicated table of every finding across every audit run. Per-run `findings.md` files are **filtered views** generated from it.

**Why:** without a canonical list, the same finding ends up in three per-run files, with three slightly different wordings and three diverging statuses. Any update requires editing three places — in practice, two of them rot.

**Practical:**
- New run observes a finding → check if it exists in INVENTORY. If yes, update `Audit Runs` column; if no, add a new row.
- Per-run `findings.md` cites IDs and links back to INVENTORY.
- `/audit validate` catches findings mentioned in per-run files but missing from INVENTORY.

---

## 3. Living methodology with CHANGELOG

`METHODOLOGY.md` evolves. Every change — adding a check, removing one, tightening severity thresholds — is recorded in `CHANGELOG.md` using [Keep a Changelog](https://keepachangelog.com/) format.

**Why:** methodology added without context accumulates into a checklist nobody understands. When someone asks "why do we check this?" six months later, the answer lives in the changelog.

**Practical:** when modifying METHODOLOGY.md, add a CHANGELOG entry in the same commit. The entry names the change and the *why* (incident, feedback, new threat model, deprecation of a library).

---

## 4. Findings are never deleted

Findings transition through states but are never removed. Dropping a finding is a status change (`dropped`), not a deletion.

**Why:** deletion breaks the audit trail. If a future audit re-observes the same thing, we need to know whether it was previously present and dropped (keep dropped), accidentally reintroduced (regression), or truly new.

**Practical:**
- States: `open` → `triaged` → `escalated` → `in-progress` → `closed` or `dropped`
- `dropped` requires a reason (last column: "Dropped: won't affect real users, cost to fix exceeds value")
- `closed` requires a verifying reference (commit SHA, re-test audit run, decision doc)

---

## 5. Escalation flow

```
audit run
   │
   ▼
INVENTORY finding
   │
   ▼ (via /audit escalate)
backlog entry
   │
   ▼ (via planning)
plan
   │
   ▼ (via commits)
code changes
   │
   ▼ (via /audit new retest)
re-test audit
   │
   ▼
finding closed
```

**Why:** the linear flow makes it obvious where a concern is in its lifecycle. Any link in the chain can be queried: "what findings are escalated but not yet planned?" (in INVENTORY with `escalated` status but no plan link) is answerable in seconds.

**Practical:** each transition adds a link back to the finding. The INVENTORY row accumulates these over the finding's life:
- `Escalated To: [backlog/20260412-csv.md](...)` after `/audit escalate`
- `Escalated To: [plans/20260415-export/](...)` when planning starts
- `Escalated To: fix:abc1234` when a commit closes it

---

## 6. Shared concerns flagged

When a finding spans multiple modules, tag it `[SHARED]` in the `Module` column.

**Why:** cross-module findings are usually structural (auth everywhere uses the wrong pattern, logging is inconsistent, a shared util has a bug). They deserve visibility at the inventory level, not buried in one module's view.

**Practical:** `[SHARED]` findings are surfaced separately in `findings.md` views and often become architectural decisions (`.context/decisions/`) rather than one-off bug fixes.

---

## Anti-patterns

| If you see... | Fix by... |
|---|---|
| Findings being edited in per-run `findings.md` files | Move edits to `INVENTORY.md`, regenerate view |
| METHODOLOGY changes without CHANGELOG entry | Add the entry retroactively, next time enforce via review |
| Duplicate findings across audit runs with different IDs | Consolidate: keep oldest ID, mark newer as duplicates in their Notes column, regenerate views |
| `Status: deleted` or rows disappearing | Restore from git history, transition to `dropped` instead |
| Audits under `.context/plans/` | Run `/audit migrate` |
