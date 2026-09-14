# Review Angles — what to launch, and when it is worth launching

The angle catalog for `review`. Each angle is one finder agent with one job.
The skill body picks a subset from the measured target; this file is what it picks from.

> **These prompts are ours.** They deliberately do not vendor the built-in
> instruments' text — `review-scope-conventions.md` §3 forbids that, because those are
> undocumented internals pinned to a CLI version and would rot into a dead letter
> without anything noticing. What is reproduced here is the *shape* of the engine
> (independent finders, then one verifier per candidate), not its wording.

---

## The one thing that changes on a module scope

The difference is about **what the boundary is**, not about age. The built-in
`/code-review` already treats pre-existing defects as in scope (*"bugs in unchanged lines
of a touched function are in scope"*); it is the optional `code-review` **plugin** and
`/security-review` that restrict to newly added lines.

A diff carries its own boundary: the hunks, plus — for the built-in — the enclosing
functions those hunks touch. A finder can be told "review the diff" and know when to
stop. **A module has no such boundary.** Nothing was touched, so nothing marks what is
in scope, and a finder with no instruction will either drift into the whole repository
or default to the diff habit and report nothing.

So this is not an inversion of the built-ins' rubric — it is the instruction that
replaces a boundary the built-ins get for free, and every finder here needs it:

> The target file set **is** the scope; there is no diff and nothing here was "just
> changed". Age is not evidence of correctness — a defect that has been there for two
> years counts. Do not follow calls outside the target file set except to establish
> whether something inside it is wrong. What is out of scope is anything a linter,
> type-checker, or compiler already catches, and anything whose only argument is style.

Getting this wrong in either direction fails: too narrow and the review reads the module
and reports nothing; too wide and it reviews the repository and never finishes.

---

## Lenses and their angles

Four lenses. A lens is what the user asks for; an angle is one finder.

### `correctness` — defects that produce wrong behavior

| Angle | Finder's job |
|---|---|
| `data-flow` | Trace values through the module: unvalidated inputs reaching a sink, values that can be `None`/`undefined` at a use site, type or unit confusion across a boundary |
| `edge-and-error` | Empty/boundary inputs, error paths that swallow or mask failure, partial-failure states (the batch that reports success having skipped rows) |
| `contract-across-callers` | A function's contract as written vs how every call site actually uses it — the mismatch is the bug, in whichever of the two is wrong |
| `state-and-concurrency` | Shared mutable state, ordering assumptions, re-entrancy, cache/hash keys that miss a field the value depends on |

Default: `data-flow`, `edge-and-error`, `contract-across-callers`. Add
`state-and-concurrency` when the target has shared state, background jobs, or caching.

### `simplify` — code that works but should not exist in this shape

| Angle | Finder's job |
|---|---|
| `dead-code` | Unreferenced functions, unreachable branches, flags that are never false, exports nobody imports. **Report, never delete** — the caller decides |
| `duplication-and-reuse` | The same logic in more than one place, and existing helpers the module reimplements |
| `altitude` | Abstractions built for one caller, indirection that adds no option, configurability nobody asked for |
| `convention-drift` | Where the module diverges from the pattern its own neighbors use |

Default: `dead-code`, `duplication-and-reuse`. Add `altitude` when the module has more
files than it has responsibilities; add `convention-drift` when it is new relative to
its siblings.

**What is *not* refactorable is a finding too.** A duplication kept because the two
copies drift on purpose, or an abstraction load-bearing for a caller outside the target,
must be reported as `keep` with the reason — otherwise the next review re-raises it, and
the third one refactors it wrongly.

### `security` — exploitable defects in the code

This lens reads code. It is **not** the `audit` security playbook, which is an
OWASP-categories × assets program audit needing a threat model, staging, and dependency
scan output. Different instrument, different question — see the Boundaries table.

| Angle | Finder's job |
|---|---|
| `injection-and-input` | SQL/command/template injection, unsafe deserialization, path traversal, XSS sinks |
| `authz-and-secrets` | Missing or wrong permission checks, IDOR, hardcoded credentials, secrets in logs, weak crypto usage. When a flag or field gates privilege, enumerate that model's write/serialization layer **independently** — every class or schema bound to the model — rather than by grepping the flag name — a serializer that never mentions the flag is exactly the one that exposes it. Check public signup first |

Every finding carries the path from input to sink and a `severity` — that path is the
evidence, and it is what the verify phase refutes against. Report what you find and let
the merge and verify phases rank it; do not suppress a candidate at the find stage for
being hard to argue. DoS and rate-limiting findings are reported like any other, with
the severity they warrant; the report's ranking is what keeps them below the
input-to-sink defects.

### `perf` — work the code does that it does not need to do

Also a code-reading lens, distinct from the `audit` perf playbook (Lighthouse,
RUM, APM, budgets against a running system). This one cannot measure; it can only read.

| Angle | Finder's job |
|---|---|
| `query-patterns` | N+1 access, queries inside loops, missing `select_related`/`prefetch_related`/joins, unbounded result sets |
| `hot-path-waste` | Repeated work that could be hoisted, re-render churn, allocation in loops, sync work on an async path |

**Every finding carries a magnitude estimate at this module's scale** — the loop bound,
the row count, the call frequency. That estimate is the evidence, and a finding that
cannot supply one ranks lowest rather than going unreported.

---

## The verify phase

**`02-find-merge-verify.md` §3 (SKILL.md Step 3.3) owns the verifier's return shape** — the full field list, including
the severity that overrides the finder's and the reason a `PLAUSIBLE` must carry. Read it
there and author the prompt from it; this section holds only what the verdicts *mean* and
why the verifier is biased the way it is. Do not author a verifier prompt from this
section alone — the field list is not here.

One verifier per **merged** candidate — the merge runs first, in a barrier, because a
duplicate verified twice is paid for twice in the phase that dominates the run's cost.

What the three verdicts claim:

- `CONFIRMED` — it verified the failure path.
- `PLAUSIBLE` — real-looking, not verified. `02-find-merge-verify.md` §3 requires it to say which kind.
- `REFUTED` — it found the reason the code is actually fine. Dropped from the report.

Bias the verifier toward refuting: a module review has a far larger candidate surface
than a diff review, so the cost of a permissive verifier is a report nobody reads.

---

## Cost — the finder number is a floor, not an estimate of the run

> **This section owns the measurement.** SKILL.md Step 2 carries the ratio, because
> quoting it *is* the instruction there; the provenance, the n=1, and the caveat about
> which sizing rule it was taken under live here, and `resolve-review-target.sh` points
> here too. The figure is pending re-measurement — when it lands, this is the section it
> lands in, and the other two sites say so rather than carrying their own copy.

Finders: ~22k tokens per agent (measured in the plan-exec-as-workflow work, recorded in
`review-scope-conventions.md` §4). Knowable before the run, and the resolver prints it as
`finder_floor_ktokens_per_lens` so that the name itself says what it is. It follows
`finders_per_lens`, which comes from `source_loc` and can be raised with `--finders`.

**Verifiers dominate.** One per surviving candidate, count unknowable before the find
phase. Measured once — 2026-08-10, `register-item.sh`, 790 LOC, 3 lenses, 6 finders:
announced floor **132k**, actual spend **2.2M**, ~**17×**. n=1.

> **That floor was computed the old way** — on total LOC, before `source_loc` existed.
> The same target measures a different floor today, so reproduce the **ratio**, not the
> 132k. The ratio is the datum; the absolute number is an artifact of the sizing rule it
> was taken under.

**The model is the other half of the bill.** This skill is `model-policy:
inherit-session` — nothing is passed to any agent, so all of them run at the invoking
session's model and effort. On the measured run that was 34 agents at the session's tier.
It is the platform norm (`/code-review` inherits too; what its effort levels vary is the
prompt, not the model) but on a module review it is the dominant term, which is why
Step 2 has to name it beside the floor.

The cause is not waste, and the fix is not fewer verifiers. They did not opine: they stood
up sandboxes and reproduced the defects with real commands and exit codes, which is what
the refute-bias asks of them. The defect was in the *announcement* — a number that omits
the dominant term reads as a total. State the floor, call it a floor, and say what the one
measured run cost against it.

**Re-measured 2026-09-13 (Q9, aidex spike `2026-09-13-supervised-cheap-subagents`,
`08-programme-design.md` § Q9, `proofs/prog/q9/`).** One correctness finder per run, three
default angles, on three real modules snapshotted before eleven labelled shipped defects
(nine tier-1), 45 runs blind-graded: every cell from `sonnet/low` to `opus/medium` found 1
of 135 label-chances. What every cell finds instead is the same cluster of real,
low-severity, unlabelled defects; opus is not more precise, only more voluminous. Per run:
`opus/medium` 4-7 findings at $1.0-3.5 and 4-13 min; `fable/low` 5-7 at $0.9-3.6 and 4-8
min; `sonnet/medium` restricted 3-5 at $0.5-1.3 and 6-11 min; `sonnet/low` 2-3 at $0.3-0.6
and 1.5-4 min. Restricting opus's tools changed nothing measurable. Two consequences the
policy above has to carry: reviewer money buys volume of minor findings, not recall of the
class that ships (fenced-code paths, selector chains, branch order), which usage finds and
the bugfix regression test closes; and a finder on `sonnet/medium` restricted returns the
same class at a third of the price, with `fable/low` the cheaper-than-opus escalation when a
first pass returns fewer than 3 findings. Whether `inherit-session` yields to that row is a
policy decision, not a measurement, and is open (Q9 adoption). Limits: N=3 per cell, one
repository, one finder per run against production's 3 + verifier.

**The §4 figure does not transfer without this caveat.** That measurement is the *diff*
regime: hunks, a capped candidate count, Haiku verifiers. A module review has no such cap,
and the uncapped candidate surface is what moves the total.

## Angle accounting — three states, and only one of them is a broken promise

Where the finder count comes from is `resolve-review-target.sh`'s, and SKILL.md Step 1
narrates it — thresholds, the override and its clamp, and what an oversize target gets
instead of a wall. Do not restate any of that here; a second copy goes stale silently.
What the catalog owns is its own maximum of 4 angles, which is what the override clamps
against.

Angles beyond the finder count are cut in the order listed above. Report every angle
that produced no findings in exactly one of these:

| State | Means | Why it is reported this way |
|---|---|---|
| **not selected** | does not apply to this target | not a coverage gap — one clause |
| **dropped** | applies; the `finders_per_lens` cap cut it | a coverage gap, and recoverable by splitting the target — announced up front, so the user already knows |
| **fell** | launched, retried once, returned nothing | Step 2 announced it as covered. This is the only one that breaks a promise already made |

An unnamed drop is a review that claims coverage it did not have. A **fell** reported as a
drop is worse: it reads as a budget decision when it was a failure. The first live run lost
`data-flow` to a structured-output retry cap and the `correctness` lens finished with 1 of
2 angles — that is the case this table exists for.
