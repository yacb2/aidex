# Request & Decision Conventions

Standards for capturing incoming requirements and recording architectural/product decisions.

## Requests

### Purpose

A request captures an incoming task, feature request, or product requirement. It is always a **single file** — not a module. If a request needs deeper analysis, it escalates to a plan or research.

### Location & Naming

```
.context/requests/
├── YYYYMMDD-description.md
├── YYYYMMDD-description.md
└── _archive/
    └── YYYYMMDD-description.md
```

- Date format: `YYYYMMDD` (no dashes, e.g., `20260402`)
- Description: kebab-case (e.g., `20260402-add-export-csv.md`)

### Template

```markdown
# [Request Title]

**Date:** YYYY-MM-DD
**Origin:** [Who requested — person, team, meeting, user feedback]
**Priority:** High | Medium | Low
**Status:** Open | In Progress | Escalated to Plan | Deferred | Rejected

---

## Description

[What is being requested. Be specific — what problem does this solve for the requester?]

## Context

[Why this came up now. Any constraints, deadlines, or dependencies.]

## Acceptance Criteria

- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Outcome

**Decision:** [What happened with this request]
**Escalated to:** [Link to plan/research if applicable]
```

### Lifecycle

1. **Open** — Captured, not yet acted on
2. **In Progress** — Being worked on directly (simple enough, no plan needed)
3. **Escalated to Plan** — Too complex for direct work → link to `.context/plans/`
4. **Deferred** — Valid but not now → stays in requests with reason
5. **Rejected** — Won't do → document why, move to `_archive/`
6. Completed requests → move to `_archive/`

### Interception Behavior

When aidex-conventions detects the user describing something that sounds like a product requirement, task assignment, or change request, it should offer a routing choice:

> "This sounds like a new requirement. Would you like to:"
> 1. **Create a formal request** — quick capture in `.context/requests/`
> 2. **Create a plan directly** — if you already know the scope and want to break it into phases
> 3. **Launch a research/investigation** — if this needs exploration before committing to a plan

This keeps the user in control of the depth of formalization.

---

## Decisions

### Purpose

A decision record documents **what** was decided, **why**, what alternatives were considered, and the rationale. This prevents the cycle of deciding → reverting → re-deciding without remembering the original reasoning.

Inspired by the ADR (Architecture Decision Record) pattern, adapted for broader use (product decisions, tech choices, workflow changes).

### Location & Naming

```
.context/decisions/
├── YYYYMMDD-description.md
├── YYYYMMDD-description.md
└── _archive/
    └── YYYYMMDD-description.md
```

- Date format: `YYYYMMDD` (no dashes, e.g., `20260402`)
- Description: kebab-case (e.g., `20260402-use-postgres-over-mysql.md`)

### Template

```markdown
# [Decision Title]

**Date:** YYYY-MM-DD
**Status:** Active | Superseded | Reversed
**Superseded by:** [Link to newer decision, if applicable]

---

## Context

[What situation or problem prompted this decision? What constraints exist?]

## Options Considered

### Option A: [Name]
- **Pros:** [advantages]
- **Cons:** [disadvantages]

### Option B: [Name]
- **Pros:** [advantages]
- **Cons:** [disadvantages]

### Option C: [Name] (if applicable)
- **Pros:** [advantages]
- **Cons:** [disadvantages]

## Decision

**Chosen:** [Option X]

**Rationale:** [Why this option won. What was the deciding factor?]

## Consequences

- [What this decision enables]
- [What this decision limits or trades off]
- [What to watch for — when would we revisit this?]
```

### Status Lifecycle

1. **Active** — Current decision in effect
2. **Superseded** — Replaced by a newer decision (link to it)
3. **Reversed** — Went back on this decision (document why in a new decision)

### When to Create a Decision Record

- Choosing between technologies, libraries, or approaches
- Changing an established pattern or convention
- Trade-off decisions where the reasoning isn't obvious from the code
- Any decision you've reversed before or might reverse again

### When NOT to Create One

- Obvious choices with no real alternatives
- Implementation details that are self-evident from the code
- Temporary/throwaway decisions during prototyping
