# 02 — ID Conventions: which pattern to pick, and how to tell

**`aidex-conventions/references/audit-conventions.md` § ID conventions defines the two
patterns and their scope.** Read it there. Ids are scoped to a **methodology** — the
methodology folder is the namespace, so `BUG-01-3` in `ux/` and `BUG-01-3` in `security/`
are different findings — and the pattern is chosen once inside each methodology, not once
for the whole repository: `ux/` structured while `security/` is global is legal.

This file holds only the decision aid: the trade-offs, the questions that settle it, the
default, and what changing your mind later costs.

---

## Pattern A — Structured IDs · trade-offs

| Pros | Cons |
|---|---|
| Immediate visual grouping | Harder to add new modules mid-methodology |
| Review by module is trivial | The id format couples to the module layout |
| Preserves hierarchy in plain text | Module renames orphan ids |

Conventions inside the pattern: categories from `BUG`, `GAP`, `IDEA`, `RISK`,
`OPPORTUNITY`, `REGRESSION`; modules as numeric (`01`, `02`) or short alphabetic codes
(`AUTH`, `TEST`, `FF`); `N` increments per module, not globally.

## Pattern B — Global IDs · trade-offs

| Pros | Cons |
|---|---|
| Simpler to assign — max + 1 | No visual grouping from the id |
| A module refactor does not touch ids | Reviewers cannot scan by module via the id |
| Works uniformly at any size | Loses the semantic clue in references |

Conventions inside the pattern: one counter, or one per category prefix; `N` zero-padded
to 3–4 digits so text sorts correctly; no module context in the id — the `Module` column
carries it.

---

## Deciding

Ask, in this order:

1. **Are the modules stable?** If they change every release, go global.
2. **Do you file cross-module findings?** If more than ~20% are `[SHARED]`, global is
   simpler.
3. **How large will this methodology's inventory grow?** Past ~500 findings, structured
   starts earning its cost in navigation.
4. **Who adds findings?** Mixed audiences do better with the simpler global format.

A safe default for a new methodology: **global ids** (`F-NNN`). Move to structured only
when you feel the pain.

---

## Changing mid-flight

You can change the pattern, but it is work:

1. Add a `Legacy ID` column to the methodology's `00-inventory.md`, temporarily.
2. Generate the new ids; map old → new.
3. Update every reference — the runs' `findings.md`, backlog, plans, decisions.
4. Record the change in `00-changelog.md`.
5. Keep the `Legacy ID` column for one cycle, then retire it.

Worth it only when the current scheme is actively obstructing work.

---

## Never

- **Reuse an id.** Once assigned it is permanent, dropped findings included.
- **Mix patterns inside one methodology.** Across methodologies is fine — that is what
  the namespace is for.
- **Put a date in the id.** The first element of `Audit Runs` is when the finding was
  first seen; that is why the board carries no separate date column.
- **Embed severity in the id.** Severity changes during triage; ids do not.
