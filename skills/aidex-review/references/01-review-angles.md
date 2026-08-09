# Review Angles — what to launch, and when it is worth launching

The angle catalog for `aidex-review`. Each angle is one finder agent with one job.
The skill body picks a subset from the measured target; this file is what it picks from.

> **These prompts are ours.** They deliberately do not vendor the built-in
> instruments' text — `review-scope-conventions.md` §3 forbids that, because those are
> undocumented internals pinned to a CLI version and would rot into a dead letter
> without anything noticing. What is reproduced here is the *shape* of the engine
> (independent finders, then one verifier per candidate), not its wording.

---

## The one thing that changes on a module scope

The built-in instruments review a **diff**, and their false-positive rubric says so
explicitly: `code-review` lists *"Pre-existing issues"* and *"Real issues, but on lines
that the user did not modify"* as false positives to discard.

On a module review, **those are the target.** Every finding is on a line nobody
just modified — that is the point of reviewing a module as it stands.

So the filtering rule inverts, and it is the single most important instruction to give
every finder here:

> Pre-existing defects are IN scope. Age is not evidence of correctness. What is out of
> scope is anything a linter, type-checker, or compiler already catches, and anything
> whose only argument is style.

Getting this backwards produces a review that reads the module and reports nothing.

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

This lens reads code. It is **not** the `aidex-audit` security playbook, which is an
OWASP-categories × assets program audit needing a threat model, staging, and dependency
scan output. Different instrument, different question — see the Boundaries table.

| Angle | Finder's job |
|---|---|
| `injection-and-input` | SQL/command/template injection, unsafe deserialization, path traversal, XSS sinks |
| `authz-and-secrets` | Missing or wrong permission checks, IDOR, hardcoded credentials, secrets in logs, weak crypto usage |

Threshold: report only what the finder can argue is **exploitable**, with the path from
input to sink. Exclude DoS and rate-limiting — they are real, but they flood the output
and drown the findings someone would act on.

### `perf` — work the code does that it does not need to do

Also a code-reading lens, distinct from the `aidex-audit` perf playbook (Lighthouse,
RUM, APM, budgets against a running system). This one cannot measure; it can only read.

| Angle | Finder's job |
|---|---|
| `query-patterns` | N+1 access, queries inside loops, missing `select_related`/`prefetch_related`/joins, unbounded result sets |
| `hot-path-waste` | Repeated work that could be hoisted, re-render churn, allocation in loops, sync work on an async path |

**Every finding must name why it matters at this module's scale.** A perf finding with
no argument about magnitude is a style opinion, and this lens produces them by the dozen
if it is not held to that.

---

## The verify phase

One verifier per candidate, prompted to **refute**. It returns `CONFIRMED` (it verified
the failure path), `PLAUSIBLE` (real-looking, not verified), or `REFUTED` (it found the
reason the code is actually fine). Keep the first two; drop `REFUTED`.

Bias the verifier toward refuting: a module review has a far larger candidate surface
than a diff review, so the cost of a permissive verifier is a report nobody reads.

---

## Cost

~22k tokens per agent (measured in the plan-exec-as-workflow work, recorded in
`review-scope-conventions.md` §4). Finders are known before the run; verifiers are one
per candidate and therefore **not** knowable in advance — never present a total that
silently omits them.

`resolve-review-target.sh` sets the finder count from the target's LOC (small 2 /
medium 3 / large 4 / oversize refuse). Angles beyond that count are dropped in the order
listed above, and **the skill must name which angles it dropped** — an unnamed drop is a
review that claims coverage it did not have.
