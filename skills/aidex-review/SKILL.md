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

Then choose angles per lens from the catalog, capped at `finders_per_lens`. **Name every
angle you dropped**, and why. An unnamed drop is a review claiming coverage it did not have.

Present: target, files/LOC, lenses chosen with their evidence, angles per lens, angles
dropped, and the token estimate (`est_ktokens_per_lens` × lenses, **plus one verifier per
candidate, which is not knowable in advance** — say so rather than printing a total that
quietly omits it).

Then stop and let the user confirm or correct — **unless** `--go` was passed, in which
case launch what you judged and report the same table alongside the findings.

## Step 3 — Run find-then-verify

Fan out with the `Workflow` tool (this skill body is the opt-in that makes it available).

1. **Find** — one agent per chosen angle, in parallel, over the resolved file list
   (`--files`). Give every finder the inversion rule from the catalog verbatim:
   pre-existing defects are in scope; age is not evidence of correctness. Each returns
   candidates with `file`, `line`, a one-line summary, and a concrete `failure_scenario`.
2. **Verify** — one agent per candidate, prompted to **refute**, returning `CONFIRMED` /
   `PLAUSIBLE` / `REFUTED`. Keep the first two. Pipeline it: a lens's candidates verify
   while another lens is still finding.
3. **Dedupe** across lenses by file+line before reporting — the same defect legitimately
   surfaces from more than one angle.

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

Say plainly what was **not** covered: angles dropped, lenses skipped, and for a split
target, the modules not reviewed in this run.

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
