---
name: aidex-review
description: Use when the user wants code reviewed as it stands — a module, a feature, a path, or the whole app — rather than a diff or a pull request. Covers correctness/bug hunting, simplification and dead code, exploitable security defects, and performance waste, and it first proposes which finder agents are worth launching and what they will cost. Fires on "review this module", "review the X feature", "code review of src/panels", "find bugs in this module", "what dead code is in X", "can this module be simplified", "security review of this code", "review the whole app". Not for: reviewing a diff, branch, or PR (the built-in /code-review, /simplify and /security-review already do that); auditing a running system against Lighthouse/OWASP program methodology (aidex-audit); fixing a specific known bug (aidex-bugfix).
argument-hint: "[correctness|simplify|security|perf|all] (<path> | --app) [--go]"
disable-model-invocation: false
allowed-tools: Bash Read Grep Glob Workflow Agent ReportFindings
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-review"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Review — code as it stands, not as it changed

Every installed review instrument is anchored to a diff. `/code-review` accepts a
`<path>` target but its own scope agent turns it into *"build the matching git diff
command for it"*; `/simplify` reviews *"the changed code"*; `/security-review`
interpolates `git diff origin/HEAD...`, an anchor that can resolve to zero files while
the tree is dirty (measured 2026-07-27).

This skill answers the other question: **review this module as it is**, with no base ref.

Angle catalog and the finder/verifier prompts: [`references/01-review-angles.md`](references/01-review-angles.md).
Scope vocabulary for the *diff* case: `aidex-conventions/references/review-scope-conventions.md`.

## Step 1 — Resolve and measure the target (never skip)

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/resolve-review-target.sh" <path>   # or --app
```

There is **no default target**. If the user did not name one, ask — one line — and do
not fall back to the repo root.

Read the exit code before the output:

- **2** — usage error or missing path. Fix and re-run.
- **3** — resolved to zero source files. Say that. It is a fact, never a clean result.
- **0** — proceed with the measurement.

`size_class=oversize` is a **refusal, not a warning**: `finders_per_lens=0`. Do not run
it anyway. Split the target into modules, review them separately, and say which ones you
are covering now. Running the small-target finder count over a whole app produces a
sample, and reporting a sample as a review is the failure this whole step exists to stop.

## Step 2 — Triage: propose what to launch, with its cost

This is the step that makes the skill worth invoking rather than asking for a review in
prose. From the measurement and the requested lens, decide **which angles are worth
launching** and present the reasoning as evidence, not as a verdict.

Lens selection when the user said `all` (or named no lens):

| Lens | Launch it when | Skip it when |
|---|---|---|
| `correctness` | always — a defect here is the only kind that produces wrong behavior | never |
| `simplify` | the target has more files than responsibilities, or duplicated shapes | the target is one small file |
| `security` | `security_surface_files` > 0 **and** the module handles input, auth, secrets, or subprocesses | the probe found no surface — say "no signal", never "secure" |
| `perf` | `perf_surface_files` > 0 **and** the module is on a request/render path | it is a one-shot script or build tool |

Then choose angles per lens from the catalog, capped at `finders_per_lens`, and put every
catalog angle you did not choose into one of two states. They are not the same thing and
must not be reported as one:

- **not selected** — the angle does not apply to this target (no shared state, so no
  `state-and-concurrency`). Not a coverage gap. One clause is enough.
- **dropped** — it applies, and the `finders_per_lens` cap cut it. This *is* a coverage
  gap, and a budget-shaped one: splitting the target recovers it. Name it, and say that.

An unnamed drop is a review claiming coverage it did not have. A third state — **fell** —
exists but cannot appear until Step 3, because it means the angle launched and returned
nothing.

**Cost — announce the floor as a floor.** `finder_floor_ktokens_per_lens` × lenses is the
finder bill, and all of it is knowable now. Verifiers are one per surviving candidate,
their count is not knowable before the find phase, and **they dominate the run**: measured
once (2026-08-10, `register-item.sh`, 790 LOC, 3 lenses, 6 finders) the floor was 132k and
the run spent 2.2M — ~17×, n=1. So say "≥ *floor*, and the one run we have measured came
in around 17× its floor". Printing the floor alone as the number is the failure this
sentence exists to stop.

Present: target, files/LOC, lenses chosen with their evidence, angles per lens, angles
dropped (and, separately, angles not selected), and the cost floor stated as above.

Then stop and let the user confirm or correct — **unless** `--go` was passed, in which
case launch what you judged and report the same table alongside the findings.

## Step 3 — Find, merge, then verify

Fan out with the `Workflow` tool (this skill body is the opt-in that makes it available).

1. **Find** — one agent per chosen angle, in parallel, over the resolved file list
   (`--files`). Give every finder the inversion rule from the catalog verbatim:
   pre-existing defects are in scope; age is not evidence of correctness. Each returns
   candidates with `file`, `line`, a one-line summary, and a concrete `failure_scenario`.

2. **Merge — before verifying, and the barrier is the point.** The same defect
   legitimately surfaces from more than one angle, so a duplicate carried into the verify
   phase is paid for twice in the phase that dominates the run's cost. Key on **the defect
   claimed**, scoped by file, with line only as a tiebreaker: `file`+`line` alone misses
   what actually duplicated in the first live run, which was one defect reported at
   different lines by two angles. Merge provenance onto the survivor rather than dropping
   it — two angles agreeing is a confidence signal and costs nothing to keep. Hold on to
   both counts; Step 4 prints them.

   This is the one place a barrier beats the pipeline, and it is the `Workflow` tool's own
   stated criterion for one: dedup across the full result set ahead of the expensive stage.

3. **Verify** — one agent per *merged* candidate, prompted to **refute**, returning
   `CONFIRMED` / `PLAUSIBLE` / `REFUTED`. Keep the first two.

4. **Account for every angle that did not come back.** `agent()` returns `null` on a
   terminal error and `parallel()` maps a failing thunk to `null`; inside `pipeline()` a
   throwing stage drops the item to `null` and skips its remaining stages, so a dead finder
   takes its verifiers with it. The documented idiom `.filter(Boolean)` is therefore the
   line that erases a fallen angle — **count the nulls before filtering**, and map each
   back to its angle by index or label.

   Retry a fallen finder **once**; one finder is cheap against the verifier bill. If it
   falls again the angle **fell**: launched, announced in Step 2 as covered, returned
   nothing. Fell is not dropped — dropped was never launched and the user was told so up
   front, while fell is a promise Step 2 already made. Report them on separate lines.

## Step 4 — Report, then make it survive the session

Report with the `ReportFindings` tool when it is available, most-severe first, `verdict`
set from Step 3. It is the one piece of built-in machinery that transfers unchanged —
the input scope does not.

**It is not always available.** Its exposure is feature-gated and is off at low effort,
so check your own tool list rather than assuming. Absent it, print the same content as
a ranked list: `file:line`, severity, one-line claim, then the failure scenario. Never
drop a finding because the reporting surface was missing.

Then **offer to register the `CONFIRMED` findings** as backlog items — one call each,
using the real interface (verified 2026-08-10):

```bash
bash ~/.aidex/skills/aidex-backlog/scripts/register-item.sh \
  --origin manual --title "<the finding>" --type bug --priority P2 --estimate S
```

Do not register silently, and do not register `PLAUSIBLE` ones. This step is not
ceremony: verification that leaves no artifact does not accumulate — measured across
this ecosystem, 5 of 6 verification actions leave nothing behind. A review whose
findings live only in terminal scrollback has, a week later, not happened.

**Print the arithmetic. If the numbers are not in the output, the step above it did not
run.** That is the only check a prose instruction can carry, and each of these three lines
exists because the first live run skipped exactly the step it reconciles (2026-08-10):

| Print | Reconciles against | What it caught |
|---|---|---|
| angles **announced / launched / retried / returned** | Step 2's table | "6 / 6 / 1 / 5" is unmissable; a bare "6 angles" hid a finder that died mid-run. `retried` is there because **fell** is only a legitimate verdict after the one retry, and a run that skipped the retry reports it identically otherwise |
| candidates **raw / distinct after merge / confirmed** | Step 3.2 | 22 confirmed that were ~15 defects — the merge was specified and never executed |
| cost **floor / actual** | Step 2's floor | announced 132k, spent 2.2M |

Then say plainly what was **not** covered: angles **dropped** (the cap cut them) and angles
that **fell** (launched, returned nothing) as separate lines, lenses skipped, and for a
split target, the modules not reviewed in this run.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Review a diff, branch, or PR | the built-in `/code-review`, `/simplify`, `/security-review` — they own the diff case |
| Audit a running system against Lighthouse/RUM budgets or OWASP × assets, with lifecycle-tracked findings | `aidex-audit` (`perf` / `security` playbooks) — it measures a system; this skill reads code |
| Fix one known bug, test-first | `aidex-bugfix` |
| Turn findings into tracked work | `aidex-backlog` |
| Plan the work the findings imply | `aidex-plan` |
| Review the Claude Code setup rather than the code | `aidex` |

## Related

- **aidex-conventions** — owns `review-scope-conventions.md` (the diff-scope vocabulary,
  the Mode A / Mode B rule, and the prohibition on vendoring built-in prompt text).
- **aidex-audit** — owns methodology playbooks over a running system; this skill owns
  code-reading angles over a static target.
