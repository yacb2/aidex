# Find, merge, then verify — the Step 3 procedure

The whole of `/aidex:review` Step 3: the read-only contract every agent carries, the
finder shape, the merge barrier, the verifier's return shape, fallen-angle accounting,
and the no-`Workflow` fallback.

Split out of `SKILL.md` on 2026-09-08 (BL-350), which sat 7 tokens under the maximum and
over the 300-line ideal. Same contract as `aidex/references/07-sweep-procedure.md`: the
SKILL documents *that* this step exists and routes here, this file is *how*. **Section 3
below owns the verifier's return shape** — `01-review-angles.md` § The verify phase
defers to it, and `tests/test-resolve-target.sh` #26 pins that.

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
   candidates with `file`, `line`, a one-line summary, a concrete `failure_scenario`,
   and a `severity` plus a `confidence` in its own claim.

   **A finder reports; it does not filter.** Ranking and refutation happen downstream
   (the merge in 3.2, the verifier in 3.3); a withheld candidate never reaches the phase
   built to settle it. `confidence` is how an unsure candidate is expressed.

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

