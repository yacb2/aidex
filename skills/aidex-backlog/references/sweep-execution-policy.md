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

## 1b. Eligible is not the same as safe

`sweep-eligible.py` answers one question — is it defined. It cannot answer whether
the run is *allowed* to do it, and the two are independent: an item can carry a
perfect Acceptance block and still be a destructive op on a real database, a
production infra change, a cross-repo edit, or a message to a client.

`sweep-eligible.py` reports this as a third tier, **REVIEW** — items that are
defined but whose body carries a signal the run must read before starting. The
signals do not exclude, and that is a correction from the first trial: run as an
auto-exclusion they took 38 of 48 items, because a regex matches any passing
mention of the client or of the server the app runs on. A pattern over prose can
say *where to look*; it cannot say what a sentence means. Ten bodies read instead
of forty-eight, with the run still deciding, is the whole value.

Move to NEEDS-DECISION anything that is:

- **class 1** — touches real data or a production system (`... against <app>_prod`,
  firewall/DNS/server config, a destructive migration);
- **class 2** — publishes, deploys, or integrates a branch;
- **outside this repo** — another project's files, a boilerplate backport;
- **dependent on a third party** — needs client material, or *is* a message to one;
- **a decision, not a task** — the Acceptance says "decide whether…", and the run
  would be inventing the answer.

Where a `durability-arbiter` is available this is its call; where it is not, apply
the list above. Note what the signals still miss: an item titled "reactivate or
remove X" or "decide where Y reconnects" is a decision that no phrase in the list
matches, so a clean ELIGIBLE row is not a promise — it is the absence of a known
warning. Getting this wrong in the permissive direction is the incident the
autonomy canon exists to prevent, and an Acceptance block does not authorize
anything — only the user does.

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

### 2b. A test that DENIES something needs a different proof than one that asserts it

RED→GREEN proves the call site is load-bearing. It does **not** prove the
assertion can see the thing it denies. Where the regression test asserts an
absence — no dialog, no error toast, no second request, no leaked row — add the
mutation that makes the denied thing **appear**, and require the test to go red.

Two failure modes this catches, both observed closing BL-600 in `echo_lab_ws`:

- **A negative assertion samples; it does not wait.** `toHaveCount(0)` polls
  once, finds nothing, and passes. The suppressed modal there opened ~4 s after
  the spec's last `await`, so the first version of the spec passed while the
  bug was live.
- **A positive assertion in front of it is not enough**, which is the guidance
  that failed here. It only covers the denial if it settles *later* than the
  denied thing appears — and an app shell renders well before a lazily-loaded
  dialog mounts. Check the ordering rather than assuming it.

**Prefer an anchor to a settle.** Find an event that is strictly later than the
appearance — a specific response, `networkidle`, a rendered marker — and wait on
that; a fixed sleep is a constant that a loaded machine outgrows silently. If
you must keep a fixed tail, keep it short and let the anchor absorb the variance.

**Run the appearance-mutation in the configuration the spec will live in** — the
suite's worker count, alongside other specs, not solo on an idle machine. A
settle validated at one worker says nothing about the same spec under
contention, and going vacuous under load is invisible: the test still passes.

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

## 5b. Merge the trunk in BEFORE the end-of-batch gate, and expect it to cost

A gate run on a branch the trunk has moved past proves less than it looks. Merging
the trunk INTO the branch is routine class-4 work and ungated — do it first.

Budget for it, though, when another session has been working the same repo. On the
first trial the backend merged clean (the two sessions touched different apps) and
the frontend did not: the other session had **split the i18n catalogue into modules**
while this branch grew its copy, so git reported a 1,666-line conflict whose trunk
side was empty. Taking either side loses strings, and the failure is silent — a
dropped key renders as its own name.

The rule that follows: **a conflict whose resolution is per-key across a moved file
is not sweep work.** Abort it, register it with what was measured, and gate on the
un-merged branch saying so. Resolving it badly at the end of a long run is how a
sweep that closed nine items costs more than it saved.

## 6. What the run reports

- items closed, with the commit per item (`close-item.sh --commit`);
- the NEEDS-DECISION list, unchanged and unattempted;
- anything the run skipped mid-flight and why — a class-1 deferral outlives the
  run that made it, so it goes in the final summary, not only in a handoff.
