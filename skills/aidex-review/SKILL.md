---
name: aidex-review
description: 'Use when the user wants code reviewed as it stands — a module, a feature, a path, or the whole app — rather than a diff or a pull request. Covers correctness/bug hunting, simplification and dead code, exploitable security defects, and performance waste, and it first proposes which finder agents are worth launching and what they will cost. Fires on "review this module", "review the X feature", "find bugs in this module", "what dead code is in X", "can this module be simplified", "security review of this code", "review the whole app", "review the changes since Friday / this weekend" (the changes pick the modules, reviewed as they stand). Not for: reviewing a diff, branch, or PR (the built-in /code-review, /simplify and /security-review already do that); auditing a running system against Lighthouse/OWASP program methodology (aidex-audit); fixing a specific known bug (aidex-bugfix).'
argument-hint: "[correctness|simplify|security|perf|all] (<path> | --app) [--finders N] [--include-tests] [--include-docs] [--go]"
disable-model-invocation: false
model-policy: inherit-session
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

Scope vocabulary for the *diff* case: `aidex-conventions/references/review-scope-conventions.md`.

## Step 1 — Resolve and measure the target (never skip)

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/resolve-review-target.sh" <path>   # or --app
```

There is **no default target**. If the user did not name one, ask — one line — and do
not fall back to the repo root.

**"Review the changes" resolves to the touched modules, not to a diff.** When the ask
is "review the changes since Friday / this weekend's changes / lo que cambió esta
semana", run `--touched-since <ref|date>` (no path): the changes decide WHICH modules,
and each owning module is measured and reviewed as it stands — the untouched files
included. A true diff review (a PR, a branch) still belongs to `/code-review`.

**Tests are measured apart from source.** The reviewed set excludes test files by
default and the size class comes from `source_loc`, not `loc` — otherwise a module is
refused for being well tested (measured: a 15,394-LOC module was 7,270 LOC of source and
8,124 of its own tests). `--include-tests` puts them back in the reviewed set *and*
sizes on the total, because a class that bounds cost has to bound what the finders read.
A target that is entirely tests keeps them: it was named deliberately.

**A skill is markdown, and the resolver knows it.** A directory carrying a `SKILL.md`
resolves its `.md` alongside its scripts (`skill_target=yes`) — otherwise reviewing a
skill returns one file and Step 1, the step that never gets skipped, cannot run at all.
Everywhere else markdown stays out unless you pass `--include-docs`: a correctness
finder reading every README is budget that never reached the code.

Read the exit code before the output:

- **2** — usage error or missing path. Fix and re-run.
- **3** — resolved to zero source files. Say that. It is a fact, never a clean result.
- **0** — proceed with the measurement.

**Depth is the caller's; admissibility is not.** `--finders N` overrides the count the
size class implies, clamped to the catalog's 4 angles. It exists because the class was
meant as a ceiling on cost and had become the floor on depth — to get 4 finders you had
to point at something *big*, which is the opposite of what "review this small file
thoroughly" wants. (`/code-review` scales angles by **effort** and treats diff size as a
precondition; we had the two swapped.) `--finders` can never override `oversize`: that
refusal answers whether the target can be covered at all, and one flag able to switch it
off would make it decorative.

`size_class=oversize` is a **refusal, not a warning**: `finders_per_lens=0`. Do not run
it anyway. Running the small-target finder count over a whole app produces a sample, and
reporting a sample as a review is the failure this whole step exists to stop.

**But do not stop at the wall — propose the split.** Re-run with `--partition`: one part
per immediate subdirectory, each measured like a target in its own right, plus a named
`(root)` part for files sitting directly in the target. Present that table, say which
parts you are covering now, and give the cost as the sum. The union of the parts is real
coverage where one sampled pass never was — which is why phasing is the answer here and
a bigger finder count is not.

Three things the partition tells you, and all three matter:

- `partitionable=no` with a `partition_note` — a flat target or a single file. There is
  nothing to split on; name a narrower target.
- `part.<name>.needs_split=yes` — that part is *still* oversize. Partition it in turn.
  Depth-1 does not always converge (measured: a 12,712-LOC part, over by 6%).
- The parts **cover** the whole: nothing the target had goes missing. They can total
  *more* than it, because each part is measured as a target in its own right — a part
  that is itself a skill counts its own markdown, which the parent excluded unless the
  parent was a skill too. If you re-derive a split by hand, keep the covering property;
  a partition that loses files is a completeness claim that is false.

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

**Read `~/.claude/skills/aidex-review/references/01-review-angles.md` before choosing
angles** — it holds the angle names per lens and the verbatim scope boundary every finder
must be given. Skip it and the run invents angle names and launches finders with no
boundary: too narrow and they read the module and report nothing, too wide and they
review the repository and never finish. Nothing errors either way.

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
the run spent 2.2M — ~17×, n=1. Quote the **ratio**, not the 132k: that floor was computed
on total LOC, before `source_loc`, so the same target measures a different floor today.
So say "≥ *floor*, and the one run we have measured came in around 17× its floor".
Printing the floor alone as the number is the failure this sentence exists to stop.
The ratio stays here because quoting it is the instruction; its provenance and the
caveat it carries are owned by `~/.claude/skills/aidex-review/references/01-review-angles.md` § Cost,
which is where a re-measurement lands.

**Name the model and effort in the same breath as the cost.** This skill is
`model-policy: inherit-session`: no `model`/`effort` is passed to any agent, so every
finder and every verifier runs at *this session's* model and effort. That is the
platform norm — `/code-review` inherits too; what its effort levels vary is the prompt,
not the model — but here it is the dominant cost term, because 34 agents reading a whole
module is not 8 agents reading a diff. Undeclared, it is a decision nobody made and the
reader cannot see at the moment they decide to run. So say it: *"N finders + one
verifier per candidate, all at &lt;model&gt;/&lt;effort&gt;, inherited from this session."*

Present: target, files/LOC, lenses chosen with their evidence, angles per lens, angles
dropped (and, separately, angles not selected), the cost floor stated as above, and the
inherited model/effort.

Then stop and let the user confirm or correct — **unless** `--go` was passed, in which
case launch what you judged and report the same table alongside the findings.

## Step 3 — Find, merge, then verify

Fan out with the `Workflow` tool (this skill body is the opt-in that makes it available).

0. **Every agent is read-only on the project, and this goes in every prompt verbatim.**
   The skill's own `allowed-tools` has no `Edit`/`Write`, but subagents do not inherit it
   — they get their own toolset, and on the one measured run the verifiers ran real
   commands and stood up sandboxes. That is what produced the quality; it is also an
   unbounded write surface on someone's real project.

   > You are reviewing, not changing. Do not edit, create or delete any file in the
   > project. Do not run migrations, `manage.py`/`rails`/`artisan` shells, seed or fixture
   > commands, or anything that writes to the application database in any environment.
   > Do not start or restart services. Reproduce a defect in a scratch copy under `_tmp/`
   > or outside the repo — never in place. If a candidate can only be confirmed by
   > mutating something real, that is `PLAUSIBLE` with the reason, not `CONFIRMED`.

   The last clause matters more than it looks: the first run returned zero `PLAUSIBLE`
   out of 27, and "I could not confirm this without touching real state" is exactly what
   that verdict is for.

   **Prove it afterwards rather than asserting it.** Capture `git status --porcelain` in
   the target repo before and after, and report the diff — "nothing was touched" is a
   claim, and this skill does not accept claims without output.

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

   **The verifier also returns `severity`, and it overrides the finder's.** A finder
   claims severity from the code it read; the verifier claims it after establishing what
   actually triggers and what the blast radius is, which is strictly more information.
   Measured 2026-08-10 on a real module: the verifiers downgraded **4 of 16** — three
   high→medium and one medium→low — and the report ranked by the finder's claim anyway,
   announcing four confirmed highs where verification supported one. A report that
   overstates what its own verify phase established is the failure this skill exists to
   stop, aimed at itself.

   `PLAUSIBLE` also returns **why**, as one of two:
   - `unreachable-trigger` — the mechanism is unrefuted but the trigger is a concurrent
     schedule, live service, or real database the run is forbidden to touch. Actionable:
     it can be settled in a disposable environment.
   - `undetermined` — the reviewer looked and could not tell. Not actionable as-is.

   They are not the same claim and must not share a line. On the measured run 5 of 7 were
   `unreachable-trigger`, all created by the read-only contract in step 0 — which is the
   contract working, not the review degrading.

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

5. **If `Workflow` is not available at all, do not error — and do not pretend.** Work
   every chosen angle yourself, sequentially, in this context, and do not skip angles for
   lack of fan-out. Then **say so in the report**: a single-pass inline review, not the
   multi-agent fan-out, so nobody is misled about what actually ran. This is the same
   rule as fell-vs-dropped one level up, and the built-in `/code-review` states it for
   itself in the same words — verified in 2.1.226.

## Step 4 — Report, then make it survive the session

Report with the `ReportFindings` tool when it is available, most-severe first, `verdict`
set from Step 3. It is the one piece of built-in machinery that transfers unchanged —
the input scope does not.

**Rank by the verifier's severity, and say that is what you ranked by.** The finder's
claim is an input to verification, not an output of it. Print `severity source: verifier`
in the arithmetic below, and where the two disagree, say so per finding — a downgrade is
a result, not an edit.

**It is not always available.** Its exposure is feature-gated and is off at low effort,
so check your own tool list rather than assuming. Absent it, print the same content as
a ranked list: `file:line`, severity, one-line claim, then the failure scenario. Never
drop a finding because the reporting surface was missing.

Then **offer to land the findings — and route, do not assume backlog.** Never land
silently. The two destinations are not interchangeable, and the count plus the verdict
mix picks between them:

| Land in | When | Why |
|---|---|---|
| **backlog** — `aidex-backlog` | a handful of findings, essentially all `CONFIRMED` | each is a unit of work; a queue is the right shape |
| **an audit run** — `aidex-audit` | many findings, or any real `PLAUSIBLE` tier | findings need a lifecycle and per-finding escalation later; a backlog drops `PLAUSIBLE` on the floor, and 7 of 16 unrefuted mechanisms is not floor material |

Backlog, one call each, real interface (verified 2026-08-10):

```bash
bash ~/.aidex/skills/aidex-backlog/scripts/register-item.sh \
  --origin manual --title "<the finding>" --type bug --priority P2 --estimate S
```

Audit run — **`aidex-audit` owns this format; do not grow a second writer here**:

```bash
bash ~/.aidex/skills/aidex-audit/scripts/new-audit.sh custom <slug>   # methodology run,
#   NOT --standalone: escalate-finding.sh resolves ids only through
#   audits/<methodology>/00-inventory.md, so a standalone run cannot be escalated by id
```
Then add one inventory row per finding and put the detail in the run's `findings.md`.
`PLAUSIBLE` findings go in too, carrying their verdict — that is the whole reason to
choose this destination.

**Then prove the landing, with `aidex-audit`'s own validator, not by looking:**

```bash
bash ~/.aidex/skills/aidex-audit/scripts/validate-audit.sh
```

An `audit-orphan-finding-ref` means the ids are in the journal and **not** in the
inventory — the write did not land. This is not hypothetical: on 2026-08-10 a hand-written
inventory seed silently no-op'd (the placeholder row it targeted did not match) and every
one of 16 ids was orphaned. The findings looked recorded and were not. That validator is
what caught it, which is exactly why the proof is delegated to it rather than reimplemented.

This step is not ceremony: verification that leaves no artifact does not accumulate —
measured across this ecosystem, 5 of 6 verification actions leave nothing behind. A review
whose findings live only in terminal scrollback has, a week later, not happened.

**Print the arithmetic. If the numbers are not in the output, the step above it did not
run.** That is the only check a prose instruction can carry, and each of these three lines
exists because the first live run skipped exactly the step it reconciles (2026-08-10):

| Print | Reconciles against | What it caught |
|---|---|---|
| angles **announced / launched / retried / returned** | Step 2's table | "6 / 6 / 1 / 5" is unmissable; a bare "6 angles" hid a finder that died mid-run. `retried` is there because **fell** is only a legitimate verdict after the one retry, and a run that skipped the retry reports it identically otherwise |
| candidates **raw / distinct after merge / confirmed** | Step 3.2 | 22 confirmed that were ~15 defects — the merge was specified and never executed |
| verdicts **confirmed / plausible-unreachable / plausible-undetermined / refuted** | Step 3.3 | one run reported 7 plausible as one bucket, hiding that 5 were settleable in a disposable env |
| **severity source: verifier** | Step 3.3 | the verifiers downgraded 4 of 16 and the report ranked by the finder anyway |
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
