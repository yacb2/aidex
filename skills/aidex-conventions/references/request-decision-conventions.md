# Request & Decision Conventions

Standards for capturing incoming requirements and recording architectural/product decisions.

> **Read [`00-global.md`](00-global.md) first.** Filename dates, archive, language, cross-references, and minimum front-matter live there. This file only declares what is specific to requests and decisions.

---

## Requests

### Purpose

A request captures an incoming task, feature request, or product requirement. It is always a **single file** — not a module. If a request needs deeper analysis, it escalates to a plan or research.

### Location & naming

```
.context/requests/
├── YYYY-MM-DD-<slug>.md
└── _archive/
    └── YYYY-MM-DD-<slug>.md
```

Date format `YYYY-MM-DD` (D-01). Slug kebab-case.

### Front-matter

```yaml
---
title: "Add CSV export to dashboard"
status: open
created: 2026-05-14
updated: 2026-05-14
origin: stakeholder
origin_ref: ""
priority: medium
escalated_to: ""
blocked_by: ""
---
```

| Field | Values | Notes |
|---|---|---|
| `title` | Free text, quoted | H1 heading derives from this. |
| `status` | `open` · `doing` · `done` · `dropped` | Base lifecycle from [`00-global.md` §6](00-global.md#6-status-vocabulary). |
| `origin` | `manual` · `stakeholder` · `meeting` · `user-feedback` | Where it came from. |
| `origin_ref` | `<type>/<filename>` or empty | If the origin is another artifact. |
| `priority` | `high` · `medium` · `low` | Lowercase. |
| `escalated_to` | `<type>/<filename>` or empty | If escalated to a plan, research, or decision. |
| `blocked_by` | Free text or `<type>/<filename>` | When deferred pending something. |

### Legacy status mapping

Owned by [`00-global.md` §6](00-global.md#6-status-vocabulary), under *Type-specific
mappings*, which carries the request rows alongside every other type's.

### Body template

```markdown
# [Request Title]

## Description

[What is being requested. Be specific — what problem does this solve for the requester?]

## Context

[Why this came up now. Any constraints, deadlines, dependencies.]

## Acceptance Criteria

- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Outcome

[What happened with this request. Link to plan/research if escalated. Mirror the front-matter `escalated_to` here for readers who don't expand front-matter.]
```

### Lifecycle

```
open ──▶ doing ──▶ done
  │        │
  └────────┴────▶ dropped
```

- **Open:** captured, not yet acted on.
- **Doing:** being worked on directly (simple enough, no plan needed).
- **Done + `escalated_to: plan/<…>`:** too complex for direct work, formalized as a plan.
- **Open + `blocked_by: <…>`:** valid but deferred.
- **Dropped:** won't do; document why in Outcome.

Per D-05 as amended by D-10, completed requests (`done`, `dropped`) move to `_archive/`
on close, not after a delay.

---

## Decisions

### Purpose

A decision record documents **what** was decided, **why**, what alternatives were considered, and the rationale. This prevents the cycle of deciding → reverting → re-deciding without remembering the original reasoning.

Inspired by the ADR pattern, adapted for broader use (product, tech, workflow).

### Location & naming

```
.context/decisions/
├── YYYY-MM-DD-<slug>.md
└── _archive/
    └── YYYY-MM-DD-<slug>.md
```

Date format `YYYY-MM-DD` (D-01). Slug kebab-case.

### Front-matter

```yaml
---
title: "Use Postgres over MySQL"
status: accepted
created: 2026-05-14
updated: 2026-05-14
superseded_by: ""
---
```

Decisions are the **only artifact type** that does not use the base `open/doing/done/dropped` vocabulary. They use the ADR-standard enum:

| Value | Meaning |
|---|---|
| `accepted` | Current decision in effect (synonym for the legacy `Active`). |
| `superseded` | Replaced by a newer decision; set `superseded_by: decision/<filename>`. |
| `dropped` | Reversed without replacement (legacy `Reversed`). |

Other optional fields:

| Field | Purpose |
|---|---|
| `superseded_by` | Pointer to newer decision (`decision/<filename>`). |
| `origin` / `origin_ref` | If the decision came from an audit, request, or research. |

### Body template

**Context**, **Decision**, and **Consequences** are the mandated triad. The
Options-Considered / Pros-Cons scaffold is **conditional**: include it only when
two or more alternatives were genuinely weighed and the head-to-head is the
anti-re-litigation payload. For a decision with one obvious verdict plus
reasoning, a one-line Alternatives note inside Decision is enough — do not
inflate it with empty Pros/Cons ceremony.

```markdown
# [Decision Title]

## Context

[What situation or problem prompted this decision? What constraints exist?]

## Options Considered  <!-- include only when >=2 real alternatives were weighed -->

### Option A: [Name]
- **Pros:** [advantages]
- **Cons:** [disadvantages]

### Option B: [Name]
- **Pros:** [advantages]
- **Cons:** [disadvantages]

### Option C: [Name] (if applicable)

## Decision

[The choice, and why it won — the deciding factor. When no separate Options
Considered section is warranted, fold the alternatives here in prose:
"Considered X and Y; chose Z because …".]

## Consequences

- [What this enables]
- [What this limits or trades off]
- [What to watch for — when would we revisit this?]
```

### Lifecycle

```
accepted ──▶ superseded   (newer decision replaces it)
   │
   └───────▶ dropped       (reversed without replacement)
```

Per D-05 as amended by D-10, decisions in `superseded` or `dropped` status move to
`_archive/` on close.

### When to create a decision

- Choosing between technologies, libraries, or approaches.
- Changing an established pattern or convention.
- Trade-off decisions where the reasoning isn't obvious from the code.
- Any decision you've reversed before or might reverse again.

### When NOT to create one

- Obvious choices with no real alternatives.
- Implementation details self-evident from the code.
- Temporary/throwaway decisions during prototyping.

---

## Related

- [`00-global.md`](00-global.md) — shared rules.
- [`plan-conventions.md`](plan-conventions.md) — when a request escalates to a plan.
- [`audit-conventions.md`](audit-conventions.md) — when a decision is forced by an audit finding.
