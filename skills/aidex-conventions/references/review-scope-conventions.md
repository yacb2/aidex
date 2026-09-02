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
| `/review` built-in | alias of `/code-review` | see below |
| `/code-review` built-in | the working diff, **or a `<pr#>`/`<branch>`/`<path>` target** — all resolved to a diff; effort-scaled angle engine | **feature-flag dependent** |
| `/simplify` | `git diff @{upstream}...HEAD` with fallbacks; accepts a `<target>` string | yes — **and it applies fixes** |
| `/security-review` | `git diff origin/HEAD...`, fixed at invocation | yes |

> **Re-measured 2026-08-10 against CLI 2.1.226** (binary extraction + published docs +
> one live invocation). The previous version of this table said `/code-review` computes
> "the working diff" and that it is "**no** — user-triggered", and generalized that into
> "the correctness engine is out of reach". Two of those three were wrong.
>
> **All three remain diff-anchored** — that part held, and it is why `aidex-review`
> exists. `/code-review`'s own scope agent is instructed verbatim that if the target
> "names a PR number, branch, ref range, or file path, build the matching git diff
> command for it".
>
> **Invocability is per-instrument, not a blanket.**
> - `/security-review` — built by a factory that hardcodes `disableModelInvocation:!1`.
>   **Confirmed empirically on 2026-08-10**: invoked from a model turn, it loaded and ran.
> - `/simplify` — registered with no `disableModelInvocation` key at all, so the `?? !1`
>   default applies. Invocable unconditionally.
> - `/code-review` — registered with `disableModelInvocation: bxv`, a *function*
>   installed as a live getter, where `bxv(){return !nt("tengu_dazzling_floyd", !1)}`.
>   Gate on ⇒ invocable; gate absent ⇒ **not** invocable. Published docs state it is
>   user-invoke-only as of v2.1.215. On this machine the flag is cached true, which is
>   why it appears in the session's skill listing at all — the listing filter drops any
>   built-in whose flag is set. So availability here is a **machine-and-flag state that
>   can flip without notice**, not a property of the tool.
>
> **`ultra` is not an effort level.** It is `subcommands:{ultra:"ultrareview"}`, a
> redirect to a separate command of type `local-jsx`/`local`, which the skill gate
> rejects categorically (`reason:"not_prompt_type"`). The prompt says so itself:
> *"Claude can't launch the cloud review directly."* The workflow-backed path is
> `high`/`xhigh`/`max`, which is a different thing from ultra and was previously
> conflated with it here.

**Reviewing code as it stands is out of scope for every row above**, because every row
resolves to a diff. That case — a module, feature, path, or whole app with no base ref —
belongs to `aidex-review`, which measures the target first (`resolve-review-target.sh`)
and then runs Mode B angles over it.

> **Correction, 2026-08-10.** This paragraph previously said `/code-review` discards
> "pre-existing issues" and findings "on lines the user did not modify", and that a
> module review inverts its rubric. **That attribution was wrong.** Those phrases belong
> to the optional `code-review` *plugin* and to `/security-review` (*"Do not comment on
> existing security concerns"* — verified firsthand by invoking it). The built-in
> `/code-review` states the opposite in its Angle A: *"bugs in unchanged lines of a
> touched function are in scope (the PR re-exposes or fails to fix them)"* — binary
> 2.1.226, offsets 259126974 and 265694334, verified directly, not via an agent.
>
> The gap is narrower and still real: a diff carries its own boundary (the hunks, plus
> the functions they touch), and **a module has none** — it includes files with zero
> hunks, which no diff-anchored instrument reaches at any effort level.

Two consequences drive every rule below.

**The correctness engine is conditionally out of reach.** `/code-review`'s
model-invocability rides a feature gate that is not ours and that defaults to *closed*
when absent — which is the expected end state once a rollout completes and the flag is
deleted. Published docs say user-invoke-only since v2.1.215. So an automated checkpoint
may not depend on it, and correctness review still has to be runnable by aidex itself.
**Detect, do not predict** (§5c).

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

Running all three angle sets on every phase is ruled out: it doubles review
cost. The split above is the cheap default: correctness
is per-phase because a bug compounds across phases; cleanup is once because
cleanup debt does not; security is conditional because most phases have no
security surface at all.

Cost, so the trade is explicit: roughly 22k tokens per agent (measured in the
plan-exec-as-workflow work), so a per-phase correctness pass runs about
80–100k tokens. `/simplify` at end of plan costs whatever the instrument costs.
Security costs zero on phases that do not touch a security surface.

## 5. Delegating a scope to `/simplify` — settled, and it is a mutation

Established 2026-08-10 by extraction, replacing the "not established" note that stood here.

`/simplify` declares `argumentHint:"[<target>]"`. The argument is trimmed and injected
verbatim as ``Review target: `<arg>` `` with **zero flag parsing** — there is no `--fix`
and no `--comment`. Its scope is not computed in code: it is prose in a "Phase 0 — Gather
the diff" block instructing the model to run `git diff @{upstream}...HEAD` with fallbacks.
So it accepts a target, and still reviews a diff.

**The rule that matters is not about scope.** `/simplify` has a "Phase 2 — Apply the
fixes" instructing it to *"fix each remaining one directly"*. There is no proposal step,
no confirmation gate, and no findings-reporting call in either of its two bodies (the
4-agent fan-out, and the single-pass fallback used when the Agent tool is unavailable).

Delegating to `/simplify` is therefore **committing to a mutation of the working tree**,
not requesting a review. Treat it as such: run it on a clean tree, from a state you can
`git checkout --`, and never inside a step whose caller believes it is read-only.

It reviews four quality angles only — Reuse, Simplification, Efficiency, Altitude — and
explicitly disclaims bug-hunting (*"Do not look for correctness bugs — that is what
`/code-review` is for"*). A fifth Conventions/CLAUDE.md angle exists in the binary but is
**not** referenced by either `/simplify` body, so CLAUDE.md adherence is not covered here.

## 5b. Which flags mutate — `/code-review --fix` and `--comment`

Established 2026-08-10 by extraction. `/simplify` is not the only instrument that writes.

`--fix` appends a block instructing the model to *"apply the findings to the working tree
instead of stopping at the report: fix each one directly"*. **No confirmation, no diff
preview, no dry run.** The registration declares no `allowedTools`, so the only thing
standing between it and an edit is the host permission layer. It is working-tree-only —
no stage, commit or push anywhere in that block.

`--comment` posts inline PR comments, preferring an MCP tool and **falling back to
`gh api …/pulls/{pr}/comments`**. That fallback is a Bash call, so a broad `Bash(gh:*)`
allow rule posts to a real pull request with no prompt.

**Both flags are reachable from a model-supplied args string.** The parser strips
`--fix`/`--comment` from anywhere in the argument text and makes no distinction between
user-typed and model-supplied args, and the Skill tool's `args` value reaches it verbatim.
So "the model invoked a review" and "the model edited the tree / commented on a PR" are
one keystroke apart.

Rule: never pass `--fix` or `--comment` on a delegated invocation. If a caller wants
fixes applied, that is a separate, named step the user authorized — not a flag smuggled
into a review.

## 5c. Detect, do not predict (invocability)

A script **cannot** reliably establish that a built-in skill *is* model-invocable; it can
reliably establish that it is *not*. Design for that asymmetry.

The gate reads `disableModelInvocation` as a **live getter** that evaluates a feature flag
on every read. The flag cache is real and readable (`~/.claude.json` →
`cachedGrowthBookFeatures`, refreshed on a ~6h jitter, and the probe would read the same
map the binary does — so ordinary staleness is fail-safe). But flag evaluation collapses
to the default entirely when `DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` or `DISABLE_GROWTHBOOK` is set, or when auth
is not first-party — and a probe cannot verify those for a *different* session. There is
no CLI surface for this either: a census of all 52 subcommands contains zero matching
"skill". And the flag→skill mapping lives only inside the minified binary, so any probe
must hardcode names that rotate on every update.

So: **attempt the delegation and handle the refusal.** It is structured and
machine-readable (`reason: "disable_model_invocation"`, `errorCode: 4`), which makes
detection sound where prediction is not. Ship only the negative probe, and treat a
refusal as the routing signal to Mode B.

## 6. Rules

### NEVER

- Invoke `/security-review` as the security gate for a non-PR scope. Its
  `origin/HEAD...` anchor is fixed at invocation and can resolve to zero files.
- Report a review as passing when the resolver exited 3. An empty scope is a
  fact to state, never a clean bill of health.
- Add a fifth scope to express a different base ref. Use `--base`.
- Copy the built-in instruments' prompt text into this repo. **One carve-out:**
  `/security-review`'s prompt is published by Anthropic under MIT at
  `anthropics/claude-code-security-review` (82 of its 83 substantive lines verified
  verbatim inside the shipped binary). That one may be cited and studied as a public
  source. The `/code-review` and `/simplify` prompts are published nowhere — the CLI is
  proprietary ("All rights reserved"), and the npm package is a 22.9 KB installer shim,
  not source.
- Route around a `disable-model-invocation` refusal. The gate's own message says
  *"Do not replicate this skill's workflow by other means — it is reserved for explicit
  user invocation."* Running it as `claude -p '/code-review …'` from Bash to dodge the
  refusal is exactly that; if the tool declines, surface it and let the user invoke.
- Delegate to `/simplify` from a step whose caller believes it is read-only. It applies
  fixes with no confirmation (§5).

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
