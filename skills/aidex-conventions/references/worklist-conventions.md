# Work-list Conventions

Standards for `.context/worklists/` — the **durable, ordered, cross-source run-queue**
that front-loads a chained multi-item session so execution does not stop to ask
"¿y ahora qué?".

> **Read [`00-global.md`](00-global.md) first** for filename dates, language, and
> cross-reference rules. A work-list is **execution-state, not knowledge** — it holds
> *ordered references + status + gate policy*, never duplicated item content. It is the
> runtime companion to the [`autonomy-conventions.md`](autonomy-conventions.md)
> chained-work-list rule, and unlike the knowledge artifacts it has its **own
> lightweight validator** (`scripts/validate-worklist.py`), not the conventions
> `validate.py`.

---

## When a work-list exists

A session that will work **more than one tracked item** (a backlog sweep, closing
several plans, reconciling audit areas) produces a work-list at its **initial phase**,
fixing the order and the gate policy once. Execution then walks it via
`worklist-advance.sh` — the per-item "what next?" question is resolved up front, not
re-asked. A single-item task needs no work-list.

## File shape

`.context/worklists/YYYY-MM-DD-<slug>.md` (kebab-case slug; date per `00-global.md`).
`.context/worklists/` is workspace-private (gitignored), like all `.context/`.

```yaml
---
title: "<run name>"
status: open | doing | done | dropped
created: YYYY-MM-DD
updated: YYYY-MM-DD
gate-policy:
  publish: ask | preauthorized   # the front-loaded publication gate for this run
  destructive: deny              # always deny (global DB/destructive rule)
---
```

Body — an **ordered** queue plus an emergent section:

```markdown
## Queue (in execution order)
1. [ ] BL-20260573 — apply reconcile_proforma_payments on prod   <!-- ref: backlog -->
2. [ ] plan:2026-06-11-propagation-pendings — close + archive     <!-- ref: plan -->
3. [ ] audit:20260528-full-security#RPT-TABLE-2 — escalate        <!-- ref: audit -->
4. [ ] inline — dedup Tier-2 IBAN helper                          <!-- ref: inline -->

## Deferred / emergent (class b: appended mid-run, never re-asked)
- [ ] inline — found 2 more stale bank_label rows (append 2026-06-29)
```

- **`## Queue`** is **numbered** and ordered; each item is `N. [ ]`/`N. [x]`, a short
  label, and a `<!-- ref: backlog|plan|audit|inline -->` comment naming its source.
- **`## Deferred / emergent`** is an unordered checklist appended to during the run.

## The three-class rule (from the autonomy canon)

The work-list is the mechanism for the autonomy canon's three-class model
([autonomy-conventions.md](autonomy-conventions.md) §"Chained work-lists"):

- **(a) Ordering of known items** → lives in `## Queue`, fixed once at the survey.
  **Never** asked mid-run.
- **(b) Emergent discovered work** → appended to `## Deferred / emergent` via
  `worklist-advance.sh --append` and continued. **Not** asked.
- **(c) Emergent decision** (options the work itself revealed) → the one legitimate
  mid-run interrupt. Rare; bias to allow it — trapping a real fork is worse.

## Creation survey (the front-loaded entry)

The owning skill (plan-exec Orient, audit kickoff, or backlog ad-hoc) builds the
work-list through a structured **`AskUserQuestion`** survey, **run first and to
completion**, then execution proceeds headless:

1. Enumerate candidate items (backlog/plans/audits + anything the user named).
2. One `AskUserQuestion` call (≤4 tabs) confirms, each with a recommended default:
   **order/selection**, **gate policy** (`publish: ask|preauthorized`), and any
   **scope toggle**. Deep architectural forks are discussed, not menu'd
   (transversal front-loading principle).
3. Feed the answers into `worklist-new.sh`.
4. Begin execution — walk the queue with `worklist-advance.sh`; append class-(b)
   work silently; only class-(c) and the publication gate may interrupt.

## Lifecycle

| Action | Script |
|---|---|
| Create from survey answers | `scripts/worklist-new.sh` |
| Mark head done, print next (+ `--append` emergent) | `scripts/worklist-advance.sh` |
| Close (status done/dropped, reconcile upstream) | `scripts/worklist-close.sh` |
| Validate shape | `scripts/validate-worklist.py` |

## Related

- [`autonomy-conventions.md`](autonomy-conventions.md) — the chained-work-list rule
  and the three-class model this artifact implements.
- [`backlog-conventions.md`](../../aidex-backlog/references/01-backlog-conventions.md) —
  the most common ref source; a work-list orders backlog items but does not own them.
