# Workflow-spec Conventions

The `.context/workflows/` artifact written by `aidex-workflow`. Follows the shared
`.context/` canon (`aidex-conventions/references/00-global.md`); only the
workflow-specific rules are declared here.

> A workflow-spec is **design-time scaffold**, not runtime state — flat front-matter,
> body sections, like the sibling loop-spec. It has **no dedicated validator** (the
> work-list earned one because it carries a nested `gate-policy:` map as runtime state;
> the workflow-spec keeps gate-policy in the **body**, so the minimal canon parser is
> never asked to model it). `.context/workflows/` is workspace-private (gitignored),
> like all `.context/`, and is registered as an `OPTIONAL_TYPE` in `validate.py` so
> auditors never flag it.

---

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

## Fan-out shape catalog

The shape fixes how items map to agents and whether stages pipeline or sit behind a
barrier. Pick one:

| Shape | Items are… | Stage flow | Isolation | Typical models |
|---|---|---|---|---|
| **review-by-dimension** | review angles (bugs, perf, security…) | pipeline: each dimension reviews → verifies as it completes | none (read-only) | find: sonnet/medium · verify: opus/high |
| **migrate-N-sites** | call-sites / files to transform | fan-out: one agent per site, each gated | `worktree` per agent (parallel writes) | transform: sonnet/medium · gate: sonnet/low |
| **research-N-sources** | sources / sub-questions | fan-out → barrier → synthesis | none (read-only) | fetch: sonnet/medium · synth: opus/high |
| **decompose-impl** | independent implementation slices | fan-out (DAG on `depends_on`), each gated | `worktree` per agent if they write | impl: sonnet/medium · review: opus/high |

**Pipeline vs barrier:** default to `pipeline()` (an item verifies the moment its prior
stage completes — no wasted wall-clock). Use a barrier (`parallel()` then a synthesis
stage) **only** when the synthesis genuinely needs every result at once (dedup, a
cross-item merge, "0 found → skip"). This mirrors the aidex-plan-exec Workflow guidance.

## Per-agent model table

The user-facing reason this skill exists separate from a plan: explicit, per-stage model
and effort assignment. Each row maps a stage to `agent(prompt, {model, effort})`:

```markdown
| Stage | Agent | Model | Effort | Why |
|---|---|---|---|---|
| find | finders ×N | sonnet | medium | breadth, cheap |
| verify | skeptics ×3 | opus | high | adversarial, must be right |
| synth | synthesizer | opus | high | judgment |
```

Heuristic: breadth/mechanical → `sonnet` (`low` for pure transforms, `medium` for
search); adversarial verify, synthesis, or judgment → `opus/high`. Omit `model` to
inherit the session model — only set it when a different tier clearly fits.

### The advisor arrangement (worker + conditional escalation)

A stage pattern, not a fan-out shape — it composes with any shape above. A cheaper
executor does the work; a stronger model checks its plan and judges its output, and
**coaches only when needed**. Anthropic's published figure: Sonnet 5 with a Fable 5
advisor lands within 10% of Fable 5 on SWE-bench Pro at 63% of the price of running
Fable 5 throughout.

**The escalation trigger is the design question a spec must answer**, because it is the
whole economy of the pattern: advise on every step and you pay for two models to do one
job, inverting the saving. State the machine-checkable condition that fires the advisor.

Reference implementation already in the suite:
[`review-with-gate.workflow.js`](../../aidex-plan-exec/assets/workflows/review-with-gate.workflow.js)
— a fresh `opus/high` reviewer over the cumulative diff, with the arbiter invoked **only
on `passed=false`**, never per gate. Reuse its `CONTINUE / ASK / STOP` verdict contract
([`durability-arbiter.md`](../../aidex-conventions/agents/durability-arbiter.md)) rather
than inventing a new trigger vocabulary.

## Execution — delegated, never rebuilt

A workflow-spec is the **durable artifact**; execution is delegated to the `Workflow`
tool reusing aidex-plan-exec's forms
([`../../aidex-plan-exec/assets/workflows/*.workflow.js`](../../aidex-plan-exec/assets/workflows/))
and the single-sourced durability CORE
([`../../aidex-conventions/references/workflow-core.md`](../../aidex-conventions/references/workflow-core.md)).
The two-stage gate (Bash verifier → conditional durability-arbiter), kill-resume via
`resumeFromRunId`, and the ~22k/agent cost floor all come from there. The spec **cites**
that machinery; it does not re-author it.

## Carrier authority — spec-only

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
- **Prompts reference plans by type-ref, not frozen paths.** A pre-written agent
  prompt that names a plan must use the `plan/<slug>` type-ref resolved at launch via
  the two-folder lookup ([`00-global.md` §3](../../aidex-conventions/references/00-global.md)),
  never a hardcoded active path like `.context/plans/<slug>.md` — that path breaks the
  moment the plan archives.

Rationale: js-primary was rejected because the js cannot carry the design rationale
this skill exists to capture, and aidex-plan-exec's versioned Workflow forms already
own the js-as-committed-asset pattern. See
[`decisions/2026-07-19-workflow-spec-carrier.md`](../../../.context/decisions/2026-07-19-workflow-spec-carrier.md).

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
  sequential phases of a plan, use `aidex-plan` + `aidex-plan-exec` (which itself may
  launch a Workflow). If it is repeat-until-green, use `aidex-loop`.
- The **work-list** ([`../../aidex-conventions/references/worklist-conventions.md`](../../aidex-conventions/references/worklist-conventions.md))
  supplies the ordered items; the workflow-spec adds the shape, the per-agent models, and
  the launch form.
- The shape/model choice deserves its own ADR (`aidex-decision`) only if it sets a
  team-wide standard; a one-off workflow records its rationale inline in the Shape and
  model-table sections.
