# Backlog Conventions

Rules for entries in `.context/backlog/`.

---

## Location & naming

```
.context/backlog/
├── YYYYMMDD-<slug>.md
├── YYYYMMDD-<slug>.md
└── _archive/
    └── YYYYMMDD-<slug>.md
```

- **Date**: `YYYYMMDD` (no dashes). This is the creation date, not the date the work starts.
- **Slug**: kebab-case, short (3–6 words max). Describes *what*, not the status.

---

## Front-matter (required)

```yaml
---
title: "Export dashboard as CSV"
status: open
origin: audit
origin_ref: audit/20260415-ux-review/IDEA-FF-2
priority: P2
blocked_by: ""
estimate: M
created: 2026-04-15
updated: 2026-04-15
---
```

| Field | Values / format | Notes |
|---|---|---|
| `title` | Free text, one line | Becomes the H1 heading |
| `status` | `open` · `doing` · `done` · `dropped` | Use transitions, don't skip |
| `origin` | `manual` · `audit` · `issue` · `request` | Where this came from |
| `origin_ref` | Reference string or empty | Format depends on origin — see below |
| `priority` | `P0` · `P1` · `P2` · `P3` | Use the code, never free text. See [Priority taxonomy](#priority-taxonomy) below |
| `blocked_by` | Free text or empty | Optional modifier — when set, priority stays but item is parked waiting on third party |
| `estimate` | `XS` · `S` · `M` · `L` · `XL` | T-shirt sizing, not hours. Independent of priority |
| `created` | `YYYY-MM-DD` | Immutable |
| `updated` | `YYYY-MM-DD` | Updated on every status change |

---

## Priority taxonomy

The `priority` field is a **code**, never free text. Four levels plus a `blocked_by` modifier.

| Level | Label | Criteria | Target time |
|---|---|---|---|
| **P0** | Critical | Production bug breaking operations · active security breach · CI blocked · data loss | This week |
| **P1** | High | Blocking feature for a flow · data quality/correctness · severe regression · external commitment | Next 2 weeks |
| **P2** | Medium | Important non-blocking improvement · scoped tech debt · significant UX issue | Next release |
| **P3** | Low | Nice-to-have · cosmetic refactor · pull-driven | No date |

**Blocked modifier:** when an item is waiting on a third party or unresolved dependency, keep its `priority` (do NOT downgrade) and set `blocked_by: "<who/what>"`. Listings surface it under a separate "Blocked" section.

Re-evaluate priorities every two weeks. If you find yourself wanting `P1.5` or `Medium-High`, pick one — the taxonomy is intentionally coarse.

### Legacy mapping (auto-applied by `migrate-priorities.sh`)

| Legacy value | → | New code |
|---|---|---|
| `Critical`, `Urgent`, `URGENT` | → | `P0` |
| `High`, `high` | → | `P1` |
| `Medium`, `medium`, `Planned` | → | `P2` |
| `Low`, `low` | → | `P3` |

### `origin_ref` formats

| Origin | Format | Example |
|---|---|---|
| `manual` | empty | — |
| `audit` | `audit/<run>/<finding-id>` | `audit/20260415-ux-review/IDEA-FF-2` |
| `issue` | `issue/<id>` | `issue/ISSUE-042` |
| `request` | `request/<file>` | `request/20260410-export-feature.md` |

---

## Body structure

After the front-matter:

```markdown
# <title>

## Context

<2–5 sentences: why this is worth doing, what's the value, what's the alternative>

## Acceptance

- [ ] <concrete, verifiable criterion>
- [ ] <another one>

## Notes

<optional: links to related findings, plans, discussions>
```

Keep the entry short. If it needs more than one screen of content, it probably belongs in a plan.

---

## Lifecycle

```
open ──▶ doing ──▶ done
  │        │
  └────────┴────▶ dropped
```

### open → doing

Typically happens when someone starts work. Update `status: doing`, `updated:` to today. If a plan exists, link it in Notes:

```markdown
## Notes

- Active plan: `.context/plans/20260420-csv-export/`
```

### doing → done

Entry represents completed work. Options:

1. **Archive**: move to `.context/backlog/_archive/` — common after a release cycle
2. **Keep visible**: update `status: done` and leave in place — useful for recent completions

### * → dropped

Set `status: dropped` and add the reason to Notes:

```markdown
## Notes

- **Dropped 2026-04-20:** duplicate of `20260415-export-csv.md` (merged there)
```

---

## Promoting to a plan

When a backlog entry grows beyond one-screen scope, promote to a plan:

1. Create `.context/plans/YYYYMMDD-<slug>/` with phases
2. Update backlog entry:
   - `status: doing`
   - Notes: "Plan: `.context/plans/YYYYMMDD-<slug>/`"
3. Keep the backlog entry — it becomes the "why" while the plan becomes the "how"
4. When the plan completes, update backlog entry to `done`

Don't delete the backlog entry — it's the origin trail.

---

## When NOT to create a backlog entry

- **Work starting this session:** just do it; no entry needed
- **Something with no acceptance criteria:** that's an idea, not a backlog item. Capture it in an audit as `opportunity` first.
- **One-line bug fixes** you're doing right now: commit it, reference the finding in the commit message
- **Stakeholder asks:** those go to `.context/requests/` first, then become backlog only when accepted

---

## Anti-patterns

- **Duplicate entries** — search first (`grep -r "similar title" .context/backlog/`)
- **Entry without origin** — always fill `origin`, even if `manual`
- **Changing priority without updating `updated`** — keeps the sort order sane
- **Leaving `done` entries forever** — archive quarterly
