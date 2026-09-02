# 01 — Core Principles: why the convention is shaped this way

**`aidex-conventions/references/audit-conventions.md` § Core principles states the six
principles.** This file does not restate them — it holds the *why* and the *practical*
under each, which is what a principle without its failure mode cannot carry. A second
copy of the convention here drifts from it, on the path an auditor reads before writing
the first finding.

Two other owners, for the same reason:

- **States and transitions** → `03-lifecycle.md`. Not repeated here.
- **The row shape and where findings live** → the methodology's `00-inventory.md` header
  table, rendered from `assets/templates/00-inventory.md.template`.

---

## 1. Finding ≠ Issue ≠ Task

**Why:** conflating them loses information. A finding may escalate to multiple tasks, be
dropped, or stay open indefinitely. Each object has its own lifecycle and audience.

**Practical:** never copy finding text into a backlog or plan. Always link. The finding
stays the authoritative description; the backlog entry captures scope; the plan describes
execution.

---

## 2. Per-methodology inventory as single source of truth

**Why:** without a canonical list, the same finding ends up in three per-run files, with
three slightly different wordings and three diverging statuses. Any update requires
editing three places — in practice, two of them rot.

**Practical:**

- A new run observes a finding → check the methodology's `00-inventory.md`. If it is
  there, append the run to `Audit Runs`; if not, add a row.
- Per-run `findings.md` cites ids and links back to the inventory.
- `/aidex-audit validate` catches findings mentioned in per-run files and missing from it.

---

## 3. Living methodology with a changelog

**Why:** methodology added without context accumulates into a checklist nobody
understands. When someone asks "why do we check this?" six months later, the answer lives
in the changelog.

**Practical:** when you modify `00-methodology.md`, add a `00-changelog.md` entry in the
same commit. The entry names the change and the *why* — incident, feedback, new threat
model, a library deprecated.

---

## 4. Every finding is registered, and none is deleted

**Why:** deletion breaks the audit trail. If a later audit re-observes the same thing, we
need to know whether it was previously present and dropped (keep it dropped),
reintroduced (a regression), or genuinely new.

**Practical:** dropping is a status change, never a removal, and it takes a reason in the
`Notes` cell. Closing takes a verifying reference — commit SHA, re-test run, decision doc.
The state names and their transitions are `03-lifecycle.md`'s.

---

## 5. Escalation flow

```
audit run
   │
   ▼
finding row in audits/<methodology>/00-inventory.md
   │
   ▼ (via /aidex-audit escalate)
backlog entry
   │
   ▼ (via planning)
plan
   │
   ▼ (via commits)
code changes
   │
   ▼ (via /aidex-audit new retest)
re-test audit
   │
   ▼
finding done
```

**Why:** the linear flow makes it obvious where a concern sits in its lifecycle. Any link
in the chain is queryable: "what is escalated but not yet planned?" is a row with an
`Escalated To` marker pointing at a backlog item and no plan — answerable in seconds.

**Practical:** each transition adds a marker back to the finding, in the `<type>/<filename>`
form (D-03) — never a relative markdown link. The inventory row accumulates them:

- `Escalated To: backlog/2026-04-12-export-csv.md` after `/aidex-audit escalate`
- `Escalated To: plan/2026-04-15-export.md` once planning starts
- the closing commit SHA in `Notes`, per the board's own header table

---

## 6. Shared concerns flagged

**Why:** cross-module findings are usually structural — auth everywhere uses the wrong
pattern, logging is inconsistent, a shared util has a bug. They deserve visibility at the
inventory level rather than being buried in one module's view.

**Practical:** `[SHARED]` findings are surfaced separately in `findings.md` views and
often become architectural decisions (`.context/decisions/`) rather than one-off fixes.

---

## Anti-patterns

| If you see... | Fix by... |
|---|---|
| Findings being edited in per-run `findings.md` files | Move the edits to the methodology's `00-inventory.md`, regenerate the view |
| A methodology change with no changelog entry | Add it retroactively; next time enforce it in review |
| Duplicate findings across runs with different ids | Consolidate: keep the oldest id, mark the newer ones as duplicates in their `Notes`, regenerate views |
| `Status: deleted`, or rows disappearing | Restore from git history and transition to `dropped` instead |
| Audits under `.context/plans/` | Run `/aidex-audit migrate` |
| A global board at the `audits/` root | Pre-D-02 layout — reshape into per-methodology inventories |
