# Unattended / batch execution (opt-in, gated)

> The progressive-disclosure half of `SKILL.md` — read it when a run is actually going
> unattended. The interactive path in `SKILL.md` does not need any of it.
>
> Paths in this file are relative to the skill root (`../`), not to this directory.

The default path above is **interactive** (you run the plan turn-by-turn). For
**unattended/batch** runs ("execute the whole plan while I'm away"), this skill can launch
the plan as a **durable `Workflow`** instead — each phase a fresh bounded agent, a two-stage
gate (Bash verifier → conditional arbiter) per phase, crash-resumable via the journal. Use
this only when the work is **decomposable + machine-verifiable + unattended** and the user
opted in (the `Workflow` tool is gated and token-heavy). § Promotion at Orient below owns how
that opt-in is resolved.

### Promotion threshold (when batching actually pays off)

Promote a plan (or a phase) to a `Workflow` only when **all** hold:

- **Decomposable** — phases are separable units whose inputs/outputs live on disk.
- **Machine-verifiable** — every batched phase has a machine-checkable gate (it is `afk-impl`).
- **Unattended** — the user opted into an away-from-keyboard run.
- **Value > overhead** — each phase's real work is large enough to amortize the per-agent fixed cost.

**The cost model (measured).** Every fresh phase agent re-pays its own system prompt + full tool
schemas — a fixed floor of **~22k tokens/agent** (measured range ~21k–23.5k). The often-quoted
~1.4–2× premium is about re-paying *shared plan context*; for **small** phases the fixed per-agent
floor dominates instead, so the ratio is worse and a workflow only pays off when each phase's work
dwarfs that ~22k floor. Toy fixtures only ever exercise the floor, so they cannot measure the
promotion ratio; until per-phase spend is captured on a genuine plan and compared against a
single-agent baseline of that same plan, the threshold is the structural rule above.

- The forms ship as versioned assets, all embedding the single-sourced durability CORE
  (see [`../aidex-conventions/references/workflow-core.md`](../../aidex-conventions/references/workflow-core.md)):
  - [`assets/workflows/pipeline-with-gate.workflow.js`](../assets/workflows/pipeline-with-gate.workflow.js)
    — **sequential** dependent phases, each gated. Use when the plan is a chain (each phase
    needs the previous one).
  - [`assets/workflows/fan-out-with-gate.workflow.js`](../assets/workflows/fan-out-with-gate.workflow.js)
    — **gated DAG**: edge-free phases run concurrently, dependent phases after their
    prerequisites (wave-scheduled, arbitrary depth). Use when the plan has independent phases
    (vertical slices with no edge between them). **Every parallel branch keeps the full
    two-stage gate** — this is the gated DAG, not an ungated Kanban.
  - [`assets/workflows/review-with-gate.workflow.js`](../assets/workflows/review-with-gate.workflow.js)
    — **terminal clean-context review**: a fresh `opus/high` reviewer judges the cumulative diff
    against the plan's success criteria + an optional **pushed** `standards_ref`, never the
    implementation transcript. Its `passed` boolean is the gate (mirrors `proof.passed`); a
    failing review routes to the conditional arbiter. Run it **after** the implementing form when
    you want a review that is not contaminated by the implementer's grown session.
- **Choose the form by plan shape** (see "Deriving `args`" below): if **every** phase has a
  non-empty `depends_on` forming a single chain → `pipeline-with-gate`; if two or more phases
  are edge-free (empty/omitted `depends_on`) and can run in parallel → `fan-out-with-gate`.
  When unsure, the sequential pipeline is the safe default (it never mis-orders).
- **Launch:** read the chosen asset and hand it to the `Workflow` tool, passing the plan as
  `args = JSON.stringify({ planPath, phases: [{ id, spec, gateCmd, model, effort, depends_on }],
  autonomySurface, preAuthorized, maxRetries })`. `depends_on` is a list of phase `id`s a phase
  needs done first (omit/`[]` = edge-free); the pipeline form ignores it, the fan-out form
  schedules on it. `args` arrives as a JSON **string** — the script `JSON.parse`s it. Iterate
  via `{scriptPath}` re-invoke (picks up edits, runs fresh).
- **Review form launch (separate invocation, after implementation):**
  `args = JSON.stringify({ planPath, diffCmd, successCriteria, standards_ref, reviewModel,
  reviewEffort, autonomySurface, preAuthorized, maxRetries })`. `diffCmd` is the Bash command the
  reviewer runs to get the cumulative diff (e.g. `cd <repo> && git diff <base>...HEAD`).
  `standards_ref` is the **push** side of push/pull — a standard/rule text handed **only** to the
  reviewer, so it can enforce a rule the implementer was never shown; omit it to review against the
  success criteria alone. The implementer **pulls** any standard it needs through its own phase
  spec in the implementing form — never push a standard into an implementer.
- The arbiter is **conditional and directing**: the JS loop's `if (!proof.passed) retry` is the
  `verify_first` carrier in batch; the arbiter fires on retry-budget exhaustion, a **blocked
  implementer** (the director path: implementers return structured `WORK_SCHEMA` reports, a
  `blocked_reason` consults the arbiter *before* burning a gate attempt, and a `CONTINUE`
  re-launches the implementer with the arbiter's direction — max 2 redirects per phase), an
  un-pre-authorized publication, or a deny-class action (implementers *report* pub/deny actions
  in `pending_actions` — never perform them — and `runPhase` routes each through `checkAction`:
  `ASK` collects a batched question while the phase continues; `STOP` escalates). In the
  fan-out form a failed phase blocks only its **descendants** — independent branches keep
  running and questions batch at the end.

### Deriving `args` from the plan

You (the skill) build the `args` object from the plan you already read at Orient — no parser,
no codegen. **Multi-file plans:** Orient reads only the *current* phase file, but a batch run
executes **every** unchecked phase, so first read `00-index.md` **plus each unchecked phase file
it points to** and flatten them into one `phases[]` array (take each phase file's gate → `gateCmd`,
its tier → `model`/`effort`, its body → `spec`). All phase-metadata fields (`depends_on`,
`tier`, `gate`, `phase-type`, `tests`) share **one canonical carrier** per the plan canon
([plan-conventions.md](../../aidex-conventions/references/plan-conventions.md) §"Optional phase metadata"):
**inline `(key: value)` on the phase heading** in single-file plans, **front-matter** in multi-file
phase files. Read whichever carrier the plan uses — there is no third place to look.
For each unchecked phase, in order:
- `id` — a short slug for the phase (e.g. `1.2-validate`).
- `spec` — the phase's task text **plus pointers to prior phases' output files** (paths, not
  contents). Do not paste prior conversation; a fresh phase agent reads what it needs off disk.
  Append the sketch rule to every spec: *"code blocks in this spec are illustrative
  sketches frozen at plan-write time — validate against the current repo before applying;
  Contract blocks are binding; the gate is the contract."*
- `gateCmd` — the phase's declared verification command (the test/type-check/build the plan
  names). If the plan declares no machine gate for a phase, that phase is **not** batch-eligible
  — run it in the interactive path instead; do not invent a gate.
- `model` / `effort` — from the phase's tier hint (below).
- `depends_on` — the phase's prerequisite phases (from the plan's `(depends_on: [...])` metadata;
  omit/`[]` = edge-free). This decides the form and the schedule. **Referent rule (load-bearing):**
  the plan writes `depends_on` in human terms (phase **numbers** like `[1, 2]`, or slugs); you must
  **rewrite each entry to the exact `id` string you assigned that phase** before passing args. The
  fan-out scheduler matches `depends_on` entries against phase `id`s — if they don't match (e.g. plan
  says `1` but you assigned id `1.2-validate`), no dependent phase ever becomes runnable and the DAG
  stalls. Keep `id` and the `depends_on` referents in the same vocabulary.

**Batch-eligibility filter (`phase-type`) — apply before building `phases[]`.** Drop every
`hitl-align` phase from the batch: those run in the **interactive** path, never in a `Workflow`
(defining scope/criteria/design is the human-in-the-loop judgment the promotion threshold
excludes). Batch **only** `afk-impl` phases (the default when a phase declares no `phase-type`).
A phase that is `afk-impl` but declares **no machine gate** is also not batch-eligible — run it
interactively; do not invent a gate. So `phases[]` contains exactly the gated `afk-impl` phases,
in plan order; a plan whose remaining phases are all `hitl-align`/gateless has nothing to batch.

**The acceptance test stays red until the phase closes.** A phase's `tests:` value names the
layer of its acceptance test (unit/api/component/e2e), written up front per `aidex-plan`'s
authoring step. That test is expected to be red when the phase's implementer starts and green
only once the gate passes — do not treat an already-green acceptance test as satisfying the
phase (it means the wrong test was picked, or the phase was already done). The phase gate
(`gateCmd`) must run that acceptance test as part of what it checks; a gate that skips it is
not proving the phase's Acceptance block. `tests: none` phases (a written reason required) have
no acceptance test to track — the declared `gateCmd` is still the sole gate.

**Pick the form from the derived `depends_on` shape.** Once every phase's `depends_on` is filled,
look at the dependency graph: if it is a single chain (each phase depends on the prior), use
`pipeline-with-gate`. If two or more phases are edge-free (or the graph has a wave wider than one),
use `fan-out-with-gate` so independent slices run in parallel. The fan-out form wave-schedules on
`depends_on`; the pipeline form runs the array in order and ignores it. Default to the pipeline
when the shape is genuinely a chain — don't fan out a plan with no real parallelism.

Pass `planPath`, the run's `autonomySurface` (from the plan), `preAuthorized` (any publish the
plan pre-authorized), and `maxRetries` (default 2). To **resume** a crashed/stopped run, re-invoke
`Workflow` with `{scriptPath, resumeFromRunId}` — completed phases replay from the journal.

### Phase tier hint (model/effort)

A phase declares its tier via the unified phase-metadata carrier (`tier: mechanical|standard|hard`).
Map it: `mechanical → sonnet/low`, `standard → sonnet/medium`, `hard → opus/high`. No hint →
`standard`. The gate/verifier always runs `sonnet/low` (it only runs a command and reports). This
hint is now part of the plan template (plan canon §"Optional phase metadata").

### When a phase fails the gate

The conditional arbiter rules at retry-exhaustion. On `STOP` (deny-class / stop-condition): halt
and document. On `ASK` (un-pre-authorized publish, or a genuine blocker): the pipeline halts that
branch; **escalate the blocked phase to the backlog** (`aidex-backlog` if installed) with the
failing proof, and surface the batched question at the end — never mid-run. Bound total spend with
`maxRetries` plus the turn's `Workflow` token budget; do not let a failing phase retry unbounded.

## Promotion at Orient

- **Evaluate batch-promotion at Orient (mandatory, one line).** Before phase 1,
  classify each phase's `phase-type` and apply the promotion threshold
  (the promotion threshold above). When the plan's `afk-impl` phases form a
  decomposable, machine-gated chain/DAG whose per-phase work dwarfs the ~22k/agent
  floor, check whether the kickoff **already grants run-to-completion autonomy**:
  don't-stop language ("sin detenerte", "hasta terminar", "todo el plan"), the
  `ultracode` keyword, or an autonomy note in the plan doc. If it does, **promote
  by default — call the `Workflow` tool directly and state the decision in one
  line, do not ask** — e.g. *"Phases 2–3 are afk-impl with machine gates →
  launching as a durable Workflow (arbiter-gated, kill-resumable); P1/P4
  hitl-align stay interactive."* Invoking this skill under a run-to-completion
  kickoff **is** the sanctioned opt-in to call the `Workflow` tool. Only when the
  kickoff did **not** grant autonomy, **propose the durable `Workflow` form as a
  single line, batched with the other Orient questions**; a one-word "yes" is the
  opt-in — no `ultracode` needed. If the plan does not qualify (no machine gate per
  phase, not decomposable, phases too small to amortize the floor, or attended), run
  interactive with the arbiter and **do not ask**. This is a kickoff decision,
  **never a mid-run interruption**.
- **Model guard (before launching any multi-agent form) — takes precedence over
  promote-by-default.** If the session model is Sonnet-class, recommend a handoff to
  Opus before launching, stated with the launch plan, never mid-run
  (`workflow-core.md` § Orchestrator model guard). Until the handoff happens, fall back
  to the interactive-with-arbiter path: a blocked launch is not an over-stop, the run
  continues interactively and only the batch promotion waits for the Opus session.
