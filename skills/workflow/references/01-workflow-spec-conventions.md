# Workflow-spec Conventions

The `.context/workflows/` artifact written by `workflow`. Follows the shared
`.context/` canon (`conventions/references/00-global.md`); only the
workflow-specific rules are declared here.

> A workflow-spec is **design-time scaffold**, not runtime state — flat front-matter,
> body sections, like the sibling loop-spec. It has **no dedicated validator** (the
> work-list earned one because it carries a nested `gate-policy:` map as runtime state;
> the workflow-spec keeps gate-policy in the **body**, so the minimal canon parser is
> never asked to model it). `.context/workflows/` is tracked like the rest of
> `.context/` (a workspace root repo versions it), and is registered as an `OPTIONAL_TYPE` in `validate.py` so
> auditors never flag it.

---

## Contents

- [Location & naming](#location--naming)
- [Front-matter (flat — mirrors loop-spec)](#front-matter-flat--mirrors-loop-spec)
- [Required body sections](#required-body-sections)
- [Fan-out shape catalog](#fan-out-shape-catalog)
- [Per-agent model table](#per-agent-model-table)
- [Optional sections](#optional-sections)
- [Execution — delegated, never rebuilt](#execution--delegated-never-rebuilt)
- [Carrier authority — spec-only, versioned script optional](#carrier-authority--spec-only-versioned-script-optional)
- [Gotchas](#gotchas)
- [Lifecycle](#lifecycle)
- [Relationship to other artifacts](#relationship-to-other-artifacts)

## Location & naming

- One file per workflow: `.context/workflows/YYYY-MM-DD-<slug>.md` (ISO date, kebab
  slug, per D-01). The date is the creation date.
- `id`: `WF-NNN`, sequential across active + `_archive/` (never reused — stable for
  commit-trailer refs, per D-09).

## Front-matter (flat — mirrors loop-spec)

```yaml
id: WF-001
title: "<slug>"
status: doing          # base lifecycle: open | doing | done | dropped
shape: undecided       # review-by-dimension | migrate-N-sites | research-N-sources | decompose-impl | undecided
created: YYYY-MM-DD
updated: YYYY-MM-DD
```

## Required body sections

In order: **Goal · Fan-out suitability · Shape · Work-list · Per-agent model+effort ·
Stop condition + gate policy · Autonomy surface · Guardrails · End-to-end verification ·
Launch · Notes**. The **Per-agent model + effort** table is the heart — a workflow-spec
without explicit model assignment is just a plan with extra words.

The shape enum is unchanged: the haiku tier below is a model choice, not a fifth shape
(a sweep of N items through extract -> verify is research-N-sources or review-by-dimension).

## Fan-out shape catalog

The shape fixes how items map to agents and whether stages pipeline or sit behind a
barrier. Pick one:

| Shape | Items are… | Stage flow | Isolation | Typical models |
|---|---|---|---|---|
| **review-by-dimension** | review angles (bugs, perf, security…) | pipeline: each dimension reviews → verifies as it completes | none (read-only) | find: haiku/medium or sonnet/medium · verify: opus/high |
| **migrate-N-sites** | call-sites / files to transform | fan-out: one agent per site, each gated | `worktree` per agent (parallel writes) | transform: sonnet/medium · gate: sonnet/low |
| **research-N-sources** | sources / sub-questions | fan-out → barrier → synthesis | none (read-only) | fetch: haiku/medium (or sonnet/medium) · synth: opus/high |
| **decompose-impl** | independent implementation slices | fan-out (DAG on `depends_on`), each gated | `worktree` per agent if they write | impl: sonnet/medium · review: opus/high |

**Pipeline vs barrier:** default to `pipeline()` (an item verifies the moment its prior
stage completes — no wasted wall-clock). Use a barrier (`parallel()` then a synthesis
stage) **only** when the synthesis genuinely needs every result at once (dedup, a
cross-item merge, "0 found → skip"). This mirrors the plan-exec Workflow guidance.

## Per-agent model table

The user-facing reason this skill exists separate from a plan: explicit, per-stage model,
effort and **toolset** assignment. Each row maps a stage to
`agent(prompt, {model, effort, agentType?})`:

```markdown
| Stage | Agent | Model | Effort | Tools / skills | Why |
|---|---|---|---|---|---|
| find | finders ×N | sonnet | medium | Read Grep Glob | breadth, cheap |
| verify | skeptics ×3 | opus | high | Read Grep Glob Bash | adversarial, must be right |
| synth | synthesizer | opus | high | Read | judgment |
```

**The Tools column is a cost line, not decoration.** A workflow agent's fixed prefix is
paid on every turn, and most of it is tool schema: on sonnet, 14k with `tools: [Bash]`,
24k adding `Skill` (the skill catalog lives in that tool's description), 32k with the
default set headless, 49k in an interactive session with MCP servers (measured
2026-09-13, `references/claude-code-runtime/04-subagent-gotchas.md` in the aidex
workspace). `agent()` has **no `tools` option**: the restriction travels through
`agentType`, naming a registered agent definition that carries `tools:` (and `skills:`
for a body the stage needs). A row whose Tools cell is "default" is declaring that it
pays the full prefix, and says why.

Heuristic: extraction/worker tier behind a stronger verifier → `haiku`; breadth/mechanical
→ `sonnet` (`low` for pure transforms, `medium` for search); adversarial verify, synthesis,
or judgment → `opus/high`. Omit `model` to
inherit the session model — only set it when a different tier clearly fits.

**The haiku tier.** Haiku 5.5 is the extraction/worker tier **when a stronger verifier sits
behind it** (it proposes, the verifier decides). Measured in WF-001 (doc sweep, 2026-10-08):
the same precision as Sonnet at `low` (96.7 vs 96.7 pooled), higher recall, about 1/16 the
extraction cost. Two conditions: (1) the verifier is not optional, because haiku's value is
cheap recall, not final judgment; (2) its price steps up 5x above 100K prompt tokens per
request, so **cap the per-agent input** (a unit that fits well under 100K, or a file the
agent reads in slices). It honours a declared `effort`; declare it like any other tier.

| Row | Model/effort | Use when |
|---|---|---|
| extract / worker | `haiku/medium` | many small units, a verifier behind it, input capped < 100K |
| breadth / search | `sonnet/medium` | the worker also has to judge relevance |
| verify / synth | `opus/high` | the answer ships |

### The advisor arrangement (worker + conditional escalation)

A stage pattern, not a fan-out shape — it composes with any shape above. A cheaper
executor does the work; a stronger model checks its plan and judges its output, and
**coaches only when needed**. Example pairing: a Sonnet 5.5 worker with an Opus 5.5
advisor, priced as the worker throughout plus the advisor on the escalated fraction only.
(No published figure is quoted here: measure the escalated fraction in your first run and
put it in the cost estimate.)

**The escalation trigger is the design question a spec must answer**, because it is the
whole economy of the pattern: advise on every step and you pay for two models to do one
job, inverting the saving. State the machine-checkable condition that fires the advisor.

Reference implementation already in the suite:
[`review-with-gate.workflow.js`](../../plan-exec/assets/workflows/review-with-gate.workflow.js)
— a fresh `opus/high` reviewer over the cumulative diff, with the arbiter invoked **only
on `passed=false`**, never per gate. Reuse its `CONTINUE / ASK / STOP` verdict contract
(the ARBITER block of [`workflow-core.md`](../../conventions/references/workflow-core.md)) rather
than inventing a new trigger vocabulary.

## Optional sections

Add these to a spec that is an **experiment** or a repeated run; omit them from a one-off.
Fix the arms, measures and criteria **before run 2** (a measure chosen after seeing the
results is not a measure).

- **Experiment arms:** one row per arm (model/effort/tools/prompt variant), same inputs.
- **Measures and decision criteria:** what is counted (precision, recall, cost per unit)
  and the threshold that picks an arm, written before the second run.
- **Cost estimate:** agents x per-agent floor (from the Tools column) + expected output;
  price by unique message id (see Gotchas).
- **Run log:** one row per run: date, arm, run id, result, cost, what changed.

## Execution — delegated, never rebuilt

A workflow-spec is the **durable artifact**; execution is delegated to the `Workflow`
tool reusing plan-exec's forms
([`../../plan-exec/assets/workflows/*.workflow.js`](../../plan-exec/assets/workflows/))
and the single-sourced durability CORE
([`../../conventions/references/workflow-core.md`](../../conventions/references/workflow-core.md)).
The two-stage gate (Bash verifier → conditional arbiter prompt) and kill-resume via
`resumeFromRunId` come from there. The per-agent cost floor is **~14k-49k tokens by
toolset** (see the Tools column above); WF-001 measured **~20k cache write per agent** with
`Read Grep Glob`. Budget with the row's toolset, not one number. The spec **cites**
that machinery; it does not re-author it.

## Carrier authority — spec-only, versioned script optional

The `Workflow` tool executes a `.workflow.js`, never the markdown. That makes two
carriers unavoidable; **the spec is the authoritative one**:

- **The `.md` workflow-spec is the single binding carrier.** It holds the design
  rationale, the shape choice, the per-agent model table, the work-list, the gate
  policy, and the autonomy surface — the payload no launchable script can carry.
- **The `.workflow.js` is generated at launch from the spec and is disposable.**
  It is **spec-only** derived: never committed, never hand-maintained, never stored
  in `.context/workflows/`. Generate it into the session scratchpad (or an equivalent
  transient location) at run time and discard it when the run ends. If the two ever
  diverge, **the spec wins** — regenerate the js, never patch it and back-port.
- **Versioned script (opt-in).** A spec MAY keep its `.workflow.js` in the repo and launch
  by `scriptPath` when runs must be **repeated**: A/B arms need the identical script on
  every run, a scheduled run needs a script that exists before the session starts, and a
  resume needs the script the first run used. State it in the spec's Launch section (path
  and why). The default stays disposable; the spec still holds the rationale and wins on
  any divergence of intent, and the script is then a maintained file, so edit it on purpose
  (an edit before a resume has a cost, see Gotchas).
- **Prompts reference plans by type-ref, not frozen paths.** A pre-written agent
  prompt that names a plan must use the `plan/<slug>` type-ref resolved at launch via
  the two-folder lookup ([`00-global.md` §3](../../conventions/references/00-global.md)),
  never a hardcoded active path like `.context/plans/<slug>.md` — that path breaks the
  moment the plan archives.

Rationale for the default: js-primary was rejected because the js cannot carry the design rationale
this skill exists to capture, and plan-exec's versioned Workflow forms already
own the js-as-committed-asset pattern. See
[`decisions/2026-07-19-workflow-spec-carrier.md`](../../../.context/decisions/2026-07-19-workflow-spec-carrier.md).

## Gotchas

Found running WF-001 (the first real workflow-spec); each costs a run if missed.

- **No filesystem in a Workflow script.** Deterministic stages (listing files, batching,
  hashing) run **pre-launch** in the session. Large inputs go in **files the prompt names**
  (the agent reads them), not in `args`.
- **One throwing `agent()` fails the whole run** (no StructuredOutput, `maxTurns` hit).
  Wrap every call:
  ```js
  const safe = async (p, o) => {
    try { return await agent(p, o) } catch (e) { return { error: String(e) } }
  }
  ```
  and handle `error` results downstream.
- **Resume is not free after a script edit.** Only top-level calls are cached; agents
  inside `pipeline()`/`parallel()` re-run. Do not edit a script mid-experiment and resume.
- **One aggregation agent over everything can hit `maxTurns`.** Aggregate per unit, then
  combine in script code.
- **Workflow transcripts repeat `usage` per content-block line.** Price by **unique message
  id**, or the cost reads several times too high.
- **Project agent types created mid-session are invisible** to `agentType` until a fresh
  session. Create the agent files, then restart before launching.

## Lifecycle

- `doing` while the workflow is designed or running; `done` when the goal's end-to-end
  verification passes; `dropped` if abandoned or superseded.
- **Archive on close** (D-05/D-10): move `done`/`dropped` specs to
  `.context/workflows/_archive/`. Cross-references resolve via the two-folder lookup.
- **Close with the origin plan.** When a workflow-spec's origin plan closes, the spec
  must be closed **in the same motion** — `done` if the workflow launched, `dropped` if
  it was superseded (e.g. the work shipped via ordinary plan execution) — and archived.
  A spec must never outlive the plan it wraps: an unclosed spec pointing at an archived
  plan is a stale, unlaunchable dead letter.
- The **Notes / iteration log** captures observed agent failures — each repeatable
  failure is a prompt-tuning signal for the spec's stage prompts.

## Relationship to other artifacts

- A workflow-spec is **orchestration discipline**, not a plan. If the work is the
  sequential phases of a plan, use `plan` + `plan-exec` (which itself may
  launch a Workflow). If it is repeat-until-green, use `loop`.
- The **work-list** ([`../../conventions/references/worklist-conventions.md`](../../conventions/references/worklist-conventions.md))
  supplies the ordered items; the workflow-spec adds the shape, the per-agent models, and
  the launch form.
- The shape/model choice deserves its own ADR (`decision`) only if it sets a
  team-wide standard; a one-off workflow records its rationale inline in the Shape and
  model-table sections.
