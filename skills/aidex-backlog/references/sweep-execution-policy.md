# Sweep execution policy — how to run a batch of XS/S items

Governs an **autonomous batch** of small backlog items, as distinct from working
one item (`start-item.sh` → `aidex-bugfix`) or ordering a cross-source queue
(`worklist-conventions.md`, which this policy sits on top of).

Every clause below is a fix for something measured, not a preference. The
measurement is `echo_lab_ws/.context/research/2026-08-24-small-sweep-throughput-analysis.md`:
34 items, 52 commits, 7.8 h active — of which **48 % was test execution** and
**55 of 66 E2E invocations produced no verdict at all**.

## 1. Acceptance is the entry gate, not the size

An item enters the run only when its `## Acceptance` block says what done means.
`scripts/sweep-eligible.py --size XS,S` partitions the open set; the
`NEEDS-DECISION` half — empty Acceptance, or `blocked_by` set — goes to the
**kickoff consultation** and never into the run.

Size was the wrong gate. An XS with no acceptance criteria is not small, it is
undefined: the two worst items in the measured sweep took four commits each
across two repos, and both had no Acceptance section.

This is the mechanical form of *"if it is not known exactly what to do, the user
decides."* Do not soften it by inferring acceptance from the Context block — if
you can write the criteria confidently from Context, write them into the item
first and say so in the commit; if you cannot, it is NEEDS-DECISION.

## 2. Verification ladder — per item, then once per batch

| Scope | Per item (XS/S/M) | Once, at end of batch, before merge |
|---|---|---|
| Backend | the touched test module or `-k <selector>` | full `pytest` (with the project's worker flags) |
| Frontend | the touched `*.test.ts` | full `vitest` |
| Types/build | — | production build, not just a type-check |
| E2E | only the spec(s) that cover the change | full isolated runner |

The per-item column is what a phase gate is for. The right column is the merge
gate, and it is **not** app-scoped. Running the right column per item is the
single largest recoverable cost: 2.3 of 3.7 test-hours in the measured sweep.

A bug fix still gets its RED→GREEN regression test per item. That is the
targeted test — it is not in tension with this ladder.

## 3. Any suite longer than the foreground tool ceiling runs detached

Launch with `run_in_background` and read the log **once** when the task reports
in. Never a foreground call that can be cut off at the ceiling, and never a
`until grep … sleep N` poll wrapper — the wrapper hits the same ceiling and
burns the full budget for nothing.

In the measured sweep five runs died at the 600 s ceiling and one poll wrapper
burned 602 s, for ~60 min of the working day and zero results. **Before
believing any green, grep the output for a spec count**; a runner that bails
early can exit 0 having run nothing.

## 4. Consultation is front-loaded, in one round

Everything the run cannot decide — the whole NEEDS-DECISION list — is surveyed
**once at kickoff**, via `AskUserQuestion` or a single decision artifact. After
that the run is headless. A consultation round that lands mid-sweep stalls the
chain for as long as the user takes to answer (~68 min, measured).

This is `rules/autonomy.md` applied to a batch: questions belong to the initial
phase; the run itself does not stop to ask.

## 5. Discovered work: absorb once, then defer

An XS/S defect found while working an item is **absorbed into the same item's
commit** when it is in the same file or the same behaviour. Beyond that — a
second discovery, or anything M or larger — register it and move on.

The cap exists so absorption cannot recurse. Without it the choice is between
an unbounded item and a queue that grows faster than the sweep drains it; the
measured run deferred five of six discovered S items, which is the safe failure
but leaves the queue growing.

## 6. What the run reports

- items closed, with the commit per item (`close-item.sh --commit`);
- the NEEDS-DECISION list, unchanged and unattempted;
- anything the run skipped mid-flight and why — a class-1 deferral outlives the
  run that made it, so it goes in the final summary, not only in a handoff.
