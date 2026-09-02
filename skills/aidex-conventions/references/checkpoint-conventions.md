# The between-unit checkpoint

Shared canon. Consumers: `aidex-plan-exec` (§2, between phases) and `aidex-backlog`'s
sweep run mode (between clusters, every ~5 items). Neither restates it — a restated
protocol is a second place to drift. Guarded by
`scripts/test_checkpoint_lockstep.sh`: the canon must carry the load-bearing parts named
below, and each consumer must point here instead of carrying its own numbered copy.

## The unit

The checkpoint fires **between units of work**. The unit is the consumer's:

| Consumer | Unit | Execution-log home |
|---|---|---|
| `aidex-plan-exec` | a phase | the plan's `00-index.md` |
| `aidex-backlog sweep` | ~5 items, or any cluster boundary | the work-list (`## Checkpoints`) and the sweep report |

Everything below is identical for both. It runs after the unit passes its verification
and before the next unit starts.

## The four moves, in order

### 1. Code-review the diff — scope first, verdict with its anchor

**Resolve the scope first.** Run
`~/.claude/skills/aidex-conventions/scripts/resolve-review-scope.sh --files working-diff`
so what is being reviewed is a recorded fact, not an assumption. **When the unit spans
commits, resolve from the merge base** — `--base <merge-base> branch-vs-main` — never
from a phrase like "since the last review": a review over the wrong diff reads as a
passing review over the right one.

**Exit 3 means the scope is empty: say so, and never report it as a passing review.**

Then run the **correctness** angles over that scope, and the cleanup and security angles
only where the scope routing sends them — **read
`~/.claude/skills/aidex-conventions/references/review-scope-conventions.md` before picking
the reviewer**; it owns which instrument covers which scope, and why `/security-review`
must not be delegated to for a non-PR scope. Address findings. For a high-risk or
ambiguous unit, route the diff through more than one reviewer (the project's review
command plus an independent second model) and treat any disagreement between them as a
high-priority finding to resolve before committing.

**Record the review evidence before the commit step**, one Execution-log line in the
consumer's log home:

```
review: <verdict> · <n> findings · scope=<scope> anchor=<anchor>
```

e.g. `review: PASS · 0 findings · scope=working-diff anchor=head`. **A verdict without an
anchor is not auditable.** This is what makes a skipped review structurally visible
instead of a silent gap.

### 2. Commit

Use the project's own commit command if one exists (a `/commit`-style helper); otherwise a
conventional message in the project's style. Stage only the files of the completed unit.
One commit per unit is the default; in a sweep, one commit per item with its `Backlog:`
trailer, and a `MERGE` cluster closes in one commit carrying several trailers.

### 3. Defer what the unit uncovered — register it, never discuss it

Emergent work (autonomy class b) is registered and the run continues:
`register-item.sh --origin plan --plan <slug>` from a plan, `register-item.sh --origin
sweep` from a sweep. `origin_ref` survives the run's archival, which is why the marker is
never a path. **No pause**, and the deferral is its own commit, kept out of the unit's
diff (`aidex-plan-exec/references/03-deferring-emergent-work.md`). A deferral must outlive
the run that made it: it also goes in the run's final record (the plan's Execution log; the
sweep report) — not only in a handoff seed, which is exactly what a handoff drops.

### 4. Context check → auto-handoff, never asked

Estimate session context growth. If the conversation has grown substantially (long tool
outputs, many file reads, several units in one session), **hand off between units
automatically** — handoff is a mandated step of the running process, never a question
(`rules/autonomy.md` class 3). If a session-handoff skill is installed, invoke it and
**auto-compose the seed** yourself; otherwise `/compact` or continue in-session. Never
hard-depend on any handoff skill.

The seed carries: the run's path (plan file, or work-list), the current position (first
unchecked box; the item just closed), what was just completed, what is next, the
**autonomy surface / mode** in effect, the **language rule**, baseline-failure notes,
and — for a sweep — **what ran and with which exit codes, and what is ungated**.
**Environment and data claims carry their standing — VERIFIED (re-checked now, check
named) or ASSUMED — never bare fact**: an arriving session repeats the seed as truth, and
seeds have asserted a DB state that was false and a UI control that did not exist.

**The seed's `slug:` line names the chain and comes from the run's own name** — the plan's
name, or the work-list's — with the unit appended; never a phrase composed at this hop.
A chain that renames itself renders as unrelated rows in the `--resume` picker.

**Where a chain ledger exists, two things go to it as DELTA lines, never as seed text:**
`CHARTER` (once, at the first handoff) and `OPEN OWED` (a decision the run deferred rather
than took — a class-1 skip, a class-2 publication left unpublished). A deferral carried
only as seed summary text is gone one link later, with no record that it was owed.

Context exhaustion is not a judgment call: it never routes to the durability-arbiter — it
just hands off.
