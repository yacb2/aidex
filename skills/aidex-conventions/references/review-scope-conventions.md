# Review Scope Conventions

How aidex points review work at the code that actually changed, when the
installed review instruments each hard-code a scope of their own.

Owner of the mechanism: `scripts/resolve-review-scope.sh`.
Consumer: `aidex-plan-exec` (between-phase checkpoint and final phase).

## 1. The problem this solves

The installed instruments are not interchangeable, and two of them cannot see a
non-PR change at all:

| Instrument | Scope it computes | Model-invocable |
|---|---|---|
| `code-review` plugin | `gh pr diff` on a pull request, comments back on it | yes |
| `/review` built-in | a GitHub pull request | yes |
| `/code-review` built-in | the working diff, **or a `<pr#>`/`<branch>`/`<path>` target** — all resolved to a diff; effort-scaled angle engine | **unresolved** — see below |
| `/simplify` | the changed code | yes |
| `/security-review` | `git diff origin/HEAD...`, fixed at invocation | yes |

> **Updated 2026-08-10 (CLI 2.1.226).** `/code-review` now advertises
> `[<pr#>|<branch>|<path>]`, which the row above previously recorded as "the working
> diff" only. A `<path>` target does **not** review that path as it stands: the skill's
> own scope agent is instructed, verbatim, that if the target "names a PR number,
> branch, ref range, or file path, build the matching git diff command for it". So the
> table's shape is unchanged — every instrument here is diff-anchored — but the row was
> stale on the capability, which is registry lag in the one file whose job is recording
> what these instruments can do.
>
> The "not model-invocable" claim is **downgraded to unresolved**: it was measured
> before this CLI version, the `ultra` path is separately gated and billed, and the
> inline path was not re-tested. Treat it as a check at invocation, not an assumption —
> the same standard §5 already applies to `/simplify`.

**Reviewing code as it stands is out of scope for every row above**, because every row
resolves to a diff. That case — a module, feature, path, or whole app with no base ref —
belongs to `aidex-review`, which measures the target first (`resolve-review-target.sh`)
and then runs Mode B angles over it. Note that its false-positive rubric **inverts**:
`/code-review` discards "pre-existing issues" and findings "on lines the user did not
modify", which on a module review are precisely the target.

Two consequences drive every rule below.

**The correctness engine is out of reach.** The instrument that reviews a
working diff with the find-then-verify angle engine is user-triggered only. No
automated checkpoint can invoke it. Correctness review therefore has to be run
by aidex itself — this is a constraint, not a design preference.

**`/security-review`'s anchor can be dead.** It interpolates
`git diff origin/HEAD...` when invoked, and that ref is baked in; it cannot be
repointed. On a repo whose work lands on the default branch and is then pushed,
it resolves to zero files while the tree is dirty, and the review reports "no
findings" without having read anything. Measured in the aidex repo on
2026-07-27: `git diff --name-only origin/HEAD...` returned 0 paths with 1 dirty
path in `git status --short`. Delegating to it would be delegating that bug.

This is the "checkers lie by omission" failure the 2026-07-25 suite audit named:
a gate that passes because it examined nothing.

## 2. The scope enum

Four scopes, closed set. `scripts/resolve-review-scope.sh` accepts exactly these
and rejects anything else rather than defaulting:

| Scope | Means |
|---|---|
| `working-diff` | uncommitted tracked changes vs `HEAD` |
| `branch-vs-main` | this branch's cumulative work vs the default branch |
| `worktree-cumulative` | a linked worktree's cumulative work vs its fork point |
| `module-path <path>` | changes under `<path>`, over the widest non-empty base |

**A base ref is a parameter, not an enum member.** `--base <ref>` overrides the
resolved base for any scope, so "the diff of this phase" and "since the last
commit" are presets over the same resolver instead of new scopes. Every enum
member added is another site that can silently fall out of lockstep; the
parameter costs nothing.

The resolver never returns a silently-empty anchor. It reports the anchor it
actually used (`merge-base` · `head` · `last-commit` · `explicit`), and a
genuinely empty scope exits 3 instead of printing nothing — so a caller can tell
"nothing changed" apart from "wrong base ref". That distinction is the whole
point; without it a review over a dead anchor is indistinguishable from a clean
bill of health.

## 3. Two modes, and when each applies

**Mode A — delegate.** Invoke the instrument; it spawns its own agents and owns
its own angles. Available only where the instrument is model-invocable *and* the
scope it computes is the one wanted.

**Mode B — define.** aidex authors the finder and verifier prompts and runs them
as subagents over the resolved scope. Required where no instrument is invocable,
or where the invocable one bakes in a scope that cannot be repointed.

Mode B reproduces the *shape* of the built-in engine, not its text: a find phase
of independent angles, each returning candidates with `file`, `line`, a one-line
summary and a concrete `failure_scenario`; then a verify phase of one vote per
candidate returning CONFIRMED / PLAUSIBLE / REFUTED, keeping the first two.
Do not vendor the built-in prompts into this repo — they are undocumented
internals, pinned to a CLI version, and would rot silently into a dead letter.

## 4. Routing table

| Angle set | When | Mode | Agents |
|---|---|---|---|
| **correctness** | every phase, over that phase's diff | **B** | 3 Sonnet finders on distinct angles (data flow · edge cases and error paths · contract broken across call sites), up to 6 candidates each; 1 Haiku verifier per candidate; cap 8 findings |
| **cleanup / altitude / conventions** | end of plan, plus size-gated mid-plan | **A** — `/simplify` | defined by the instrument; aidex supplies only the resolved scope |
| **security** | conditional: only when the resolved diff touches a security surface (auth, input parsing, subprocess, secrets, path handling) | **B** | 2 Sonnet finders (injection and input validation · authz, secrets, crypto), >80% exploitability threshold, excluding DoS and rate-limiting; 1 verifier |

Running all three angle sets on every phase is what the BL-073 acceptance rules
out as doubling review cost. The split above is the cheap default: correctness
is per-phase because a bug compounds across phases; cleanup is once because
cleanup debt does not; security is conditional because most phases have no
security surface at all.

Cost, so the trade is explicit: roughly 22k tokens per agent (measured in the
plan-exec-as-workflow work), so a per-phase correctness pass runs about
80–100k tokens. `/simplify` at end of plan costs whatever the instrument costs.
Security costs zero on phases that do not touch a security surface.

## 5. Delegating a scope to `/simplify`

Whether `/simplify` accepts a caller-supplied scope or always computes its own
is **not established** — it cannot be determined without invoking it. Treat it as
a check at invocation, not an assumption: supply the resolved scope, and if the
instrument reviews something other than what was supplied, that case falls back
to Mode B. Do not record it as working until observed.

## 6. Rules

### NEVER

- Invoke `/security-review` as the security gate for a non-PR scope. Its
  `origin/HEAD...` anchor is fixed at invocation and can resolve to zero files.
- Report a review as passing when the resolver exited 3. An empty scope is a
  fact to state, never a clean bill of health.
- Add a fifth scope to express a different base ref. Use `--base`.
- Copy the built-in instruments' prompt text into this repo.

### ALWAYS

- Resolve the scope through `scripts/resolve-review-scope.sh` before any review,
  so what was reviewed is a recorded fact rather than an assumption.
- Record the anchor alongside the verdict in the plan's Execution log — e.g.
  `review: PASS · 0 findings · scope=branch-vs-main anchor=head`. A verdict
  without an anchor cannot be audited later.
- Prefer Mode A wherever the instrument's own scope already matches; build a
  Mode B fan-out only for what nothing covers.
- Route a **module-as-it-stands** review to `aidex-review`, not to a scope in the enum
  above. `module-path` here means "the changes under `<path>`" and still returns a base
  ref; it is not the same question.
