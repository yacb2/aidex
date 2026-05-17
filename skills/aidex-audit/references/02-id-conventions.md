# 02 — ID Conventions

Two patterns are supported. Pick one per project and stay consistent.

---

## Pattern A — Structured IDs

Format: `<CATEGORY>-<MODULE>-<N>`

Examples:
- `BUG-01-3` — bug, in module 01 (e.g., auth), third one
- `IDEA-FF-2` — idea, in module FF (e.g., features), second one
- `GAP-05-1` — gap, in module 05 (e.g., tests), first one

### When to use

- Modules / phases are stable and finite (e.g., a pipeline with fixed stages)
- Reviewers commonly scan by module ("show me all auth bugs")
- Visual grouping helps navigation of large INVENTORY
- Module abbreviations are meaningful and unambiguous

### Conventions

- **Categories:** choose from `BUG`, `GAP`, `IDEA`, `RISK`, `OPPORTUNITY`, `REGRESSION`
- **Modules:** use numeric codes (01, 02) or short alphabetic codes (AUTH, TEST, FF)
- **N:** increments per-module, not global

### Pros / cons

| Pros | Cons |
|---|---|
| Immediate visual grouping | Harder to add new modules mid-project |
| Review by module trivial | ID format coupling with module layout |
| Preserves hierarchy in text | Module renames orphan IDs |

---

## Pattern B — Global IDs

Format: `<PREFIX>-<N>` with flat numbering.

Examples:
- `F-042` — finding number 42
- `BUG-127` — bug number 127
- `UX-019` — UX-related finding number 19

### When to use

- Modules are fluid or cross-cutting findings dominate
- Simpler uniqueness enforcement (just max+1)
- Audit team is external and unfamiliar with internal module breakdown
- Project is small — module grouping adds no value

### Conventions

- **Single counter** (or one counter per category prefix)
- **N:** typically zero-padded to 3 or 4 digits for sort order
- **No module context in ID** — the `Module` column in INVENTORY tells you

### Pros / cons

| Pros | Cons |
|---|---|
| Simpler to assign | No visual grouping by ID |
| Module refactor doesn't affect IDs | Reviewers can't scan by module via ID |
| Works uniformly across project size | Loses semantic clue in references |

---

## Deciding

Ask:

1. **Are your modules stable?** If they change every release, use global.
2. **Do you ever file cross-module findings?** If >20% are `[SHARED]`, global is simpler.
3. **How big is INVENTORY likely to grow?** >500 findings, structured starts helping navigation.
4. **Who adds findings?** Mixed audiences benefit from simpler global format.

A safe default for new projects: **global IDs** (`F-NNN`). Switch to structured only when you feel the pain.

---

## Changing mid-project

You can change conventions, but it's work:

1. Add a `Legacy ID` column to INVENTORY temporarily.
2. Generate new IDs; map old → new.
3. Update every reference in `findings.md`, backlog, plans, decisions.
4. Record the change in `CHANGELOG.md`.
5. Keep the Legacy ID column for one cycle, then retire.

Worth it only if the current scheme is actively obstructing work.

---

## Never

- **Reuse IDs.** Once assigned, an ID is forever — even for dropped findings.
- **Mix conventions** within a project. Pick one and stick with it.
- **Put timestamp data in the ID.** That's what the `First Seen` column is for.
- **Embed severity in the ID.** Severity changes during triage; IDs don't.
