---
name: aidex-workflow
description: 'Use when the user wants to design or scaffold a one-shot multi-agent fan-out / decomposition orchestration — review code across N dimensions, migrate N call-sites in parallel, research N sources, or split an implementation into parallel agents with per-agent model/effort assignment — landing as a written `.context/workflows/` workflow-spec (goal + fan-out shape + per-agent model table + gate policy) before the Workflow runs. Fires on "design a workflow to review X across N angles", "fan out agents to migrate every call-site", "orchestrate a multi-agent review of X", "decompose this into parallel agents with different models". Not for: executing a written multi-phase plan (aidex-plan-exec — there is a plan doc); repeat-until-a-check-passes automation (aidex-loop); planning multi-step work without orchestration (aidex-plan); ecosystem audits (aidex); project-state audits (aidex-audit).'
argument-hint: "[design [slug] | new <slug> | run <slug>]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep Workflow Agent
model-policy: per-stage
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-workflow"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Workflow — Design Multi-Agent Orchestrations

Help the user **design and specify** a one-shot multi-agent fan-out before running
it, capture it as a `.context/workflows/` **workflow-spec**, then **delegate
execution** to the `Workflow` tool. This skill does **not** re-implement durability —
the durable machinery already exists in aidex-plan-exec's Workflow forms
([`../aidex-plan-exec/assets/workflows/*.workflow.js`](../aidex-plan-exec/assets/workflows/),
single-sourcing the durability CORE in
[`../aidex-conventions/references/workflow-core.md`](../aidex-conventions/references/workflow-core.md)).
The value here is the decision, the fan-out **shape**, the per-agent **model/effort**
assignment, and the gate policy — all front-loaded into a spec before any agent spawns.

**Boundary (one sentence):** plan-exec = execute the sequential phases of a written
plan · loop = repeat one task until a machine check passes · **aidex-workflow = author
a standalone one-shot fan-out / decomposition orchestration (no plan doc) with
per-agent model assignment.**

See [references/01-workflow-spec-conventions.md](references/01-workflow-spec-conventions.md)
for the artifact format and the fan-out shape catalog.

---

## Sub-actions

Dispatch by first argument:

| Command | Backed by | Purpose |
|---|---|---|
| `/aidex-workflow` | — | Show help + list existing `.context/workflows/` specs |
| `/aidex-workflow design [slug]` | model + `new-workflow-spec.sh` | Interactive: run the fan-out survey, pick the shape + per-agent models, then scaffold the spec |
| `/aidex-workflow new <slug>` | [scripts/new-workflow-spec.sh](scripts/new-workflow-spec.sh) | Scaffold an empty workflow-spec file (skip the interview) |
| `/aidex-workflow run <slug>` | model | Read a finished spec and launch it via the `Workflow` tool |

### Dispatch logic

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/new-workflow-spec.sh" "$@"
```

- `new <slug>` → `new-workflow-spec.sh new <slug>`
- `design [slug]` → run the interview below, then `new-workflow-spec.sh new <slug>` and fill it in
- `run <slug>` → no script; read the spec and follow [run](#run) below
- no args → list specs (`ls .context/workflows/*.md`) and show this help

---

## `design` — the survey

Run the survey **first and to completion** (the transversal front-loading principle:
`AskUserQuestion` is a planning-time survey, not a mid-run interrupt), then write the
spec and proceed headless. Walk these one at a time; do not skip step 0 or step 1.

**No interactive channel** (`claude -p`, cron, any non-interactive surface): do not
attempt the survey — take each step's recommended default and record in the spec that the
parameters were defaulted. Full rule:
[autonomy-conventions.md § When there is no interactive channel](../aidex-conventions/references/autonomy-conventions.md).

1. **Fan-out suitability (step 0).** Is the work genuinely **decomposable** into
   independent sub-units that gain from running concurrently or from different models?
   If it is really the *sequential phases of a written plan* → hand to `aidex-plan-exec`.
   If it is *repeat one task until a check passes* → hand to `aidex-loop`. If it is a
   single unit of work → just do it. Only a real fan-out / decomposition belongs here.
2. **Shape (step 1).** Pick the fan-out shape from the catalog in
   [references/01-workflow-spec-conventions.md](references/01-workflow-spec-conventions.md)
   §"Fan-out shape catalog": **review-by-dimension** · **migrate-N-sites** ·
   **research-N-sources** · **decompose-impl**. The shape fixes how items map to agents
   and whether stages pipeline or fan out behind a barrier.
3. **Work-list.** Enumerate the concrete items (dimensions / call-sites / sources /
   sub-tasks). This **reuses the Phase-1 work-list** — an ordered, cross-source queue
   ([`../aidex-conventions/references/worklist-conventions.md`](../aidex-conventions/references/worklist-conventions.md)).
   Fix the order once here; do not re-ask per item at run time.
4. **Per-agent model + effort.** For each stage, assign `model` + `effort` and say why
   (breadth → `sonnet/medium`; adversarial verify / synthesis → `opus/high`; mechanical
   transform → `sonnet/low`). This table is the spec's distinctive payload — see
   §"Per-agent model table" in the conventions.
5. **Stop condition + gate policy.** The machine gate each agent's output must pass, and
   the run's publication gate (`publish: ask | preauthorized`). Mirror the work-list's
   `gate-policy`.
6. **Autonomy surface (step 1.5).** Resolve the permission borders so the run is
   unattended. Use Claude Code's native `allow`/`ask`/`deny` — do NOT enumerate an
   allowlist. Pin: (a) any workflow-specific **deny**; (b) the **pre-authorized** ops;
   (c) the **always-ask** set (defaults: publication — push/publish/deploy/release and
   integrating a branch into the trunk; merging the trunk INTO the branch stays
   autonomous — NOT commit, deps, or additive migrations; the canon linked below owns
   the full list). Everything else safe + additive is autonomous:
   proceed, verify the assumption, log it. (See
   [`../aidex-conventions/references/autonomy-conventions.md`](../aidex-conventions/references/autonomy-conventions.md).)
7. **Isolation surface.** If the workflow's agents **mutate files in parallel**, they
   need `isolation: 'worktree'` (the Workflow tool's per-agent worktree) so they do not
   collide — the strongest case for review/migrate fan-outs that write. Read-only
   fan-outs (review-by-dimension, research) need none. Record it in the spec's Guardrails.
8. **Scaffold.** Run `new-workflow-spec.sh new <slug>`, then fill every section from the
   answers. Leave nothing as a placeholder. If a spec with that slug already exists
   (`new-workflow-spec.sh` refuses to overwrite), **refine the existing spec in place**.

## `run`

1. Read `.context/workflows/<date>-<slug>.md`.
2. Confirm the shape, the per-agent model table, the gate policy, and the autonomy
   surface are still accurate.
3. **Launch via the `Workflow` tool — do not rebuild durability.** Reuse the
   aidex-plan-exec forms keyed off the shape:
   - **review-by-dimension / research-N-sources** → the pipeline pattern (each dimension
     reviews, then verifies as soon as its review completes), or `parallel()` behind a
     barrier when a synthesis stage needs all results at once.
   - **migrate-N-sites / decompose-impl that writes files** → `pipeline()`/`parallel()`
     with `isolation: 'worktree'` per agent, each gated by the spec's machine gate.
   Translate the spec's per-stage **model/effort** directly into the `agent(prompt,
   {model, effort})` options, and the work-list into the items array. The two-stage gate
   (Bash verifier → conditional durability-arbiter) and kill-resume come from the
   plan-exec CORE.
   - **The spec is the binding carrier; the `.workflow.js` is generated here, at
     launch, and is disposable.** Write it into the session scratchpad (or an equivalent
     transient location), never `.context/workflows/`; do not commit it and do not keep
     it after the run. If it ever diverges from the spec, the spec wins — regenerate.
     (See §"Carrier authority — spec-only" in the conventions.)
   - **Any plan a generated prompt references must be by `plan/<slug>` type-ref resolved
     at launch** via the two-folder lookup, never a frozen active path — the active path
     dies when the plan archives.
4. **Model guard.** If the session model is a Sonnet-class model, **recommend a
   handoff to Opus before launching** — Sonnet-class models fail multi-agent
   Workflow orchestration in the field. State it with the launch plan, never
   mid-run.
5. Only execute the `Workflow` call if the user explicitly asks you to start it now;
   otherwise print the launch plan (form + args shape) for them to confirm.

### Run doctrine — autonomy during the run

Once the spec's **Autonomy surface** is declared, the workflow runs to its stop
condition without interrupting the user:

- **Do not pause** for anything outside the declared ask-set. Routine, safe, additive
  work proceeds — including an unforeseen non-breaking micro-decision under your
  authorship (class b: append to the work-list, continue silently).
- **Pause only** for the **deny** set and the **ask** set (push/publish/deploy/release,
  merging the branch into the trunk — not the trunk into the branch — plus any the
  spec declared). Commit, deps, and additive migrations are **not** gated.
- **Proceed + log, don't halt:** on a safe additive decision, verify the assumption
  (investigate, don't guess) and log it — do not stop.
- **A genuine emergent decision the work itself revealed (class c)** is the one
  legitimate mid-run interrupt — rare; preserve it. The goal is removing the *avoidable*
  "what next?" questions, not reaching zero.
- **Ambiguous consent point not in the ask-set → consult the durability-arbiter, do not
  deadlock.** Read
  [`../aidex-conventions/agents/durability-arbiter.md`](../aidex-conventions/agents/durability-arbiter.md),
  pass it to the Agent tool (`model: sonnet`, `effort: high`, read-only) with the situation + the spec's
  autonomy surface + proof, follow its verdict, batch any `ASK` to the end. If it errors,
  apply the rule above and proceed — never block on it. `model-policy: per-stage` is what
  that pin expresses, and it is the same policy the spec's per-agent model table sets for
  every agent the designed Workflow spawns.

This is the workflow's instance of the shared autonomy canon — full decision rule, the
`commit`-is-not-gated policy, the three-class model, and the durability-arbiter live in
[autonomy-conventions.md](../aidex-conventions/references/autonomy-conventions.md).

---

## Boundaries

| The user wants to… | Route to |
|---|---|
| Execute a written multi-phase plan (there is a plan doc) | `aidex-plan-exec` |
| Repeat one task until a machine check passes (tests/typecheck/build green) | `aidex-loop` |
| Plan multi-step work (no orchestration yet) | `aidex-plan` |
| Run a prompt on a recurring interval | native `/loop` |
| Record a decision / ADR | `aidex-decision` |
| Investigate how something works | `aidex-research` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf) | `aidex-audit` |
| A single unit of work, no fan-out | (just do the work) |

## Related

- **aidex-plan-exec** — owns the durable `Workflow` forms (pipeline / fan-out / review)
  and the durability CORE this skill delegates to. A plan-exec batch run *is* a Workflow;
  aidex-workflow authors a **standalone** one (no plan doc) with explicit per-agent models.
- **aidex-loop** — the sibling designer for repeat-until-green loops; same designer
  pattern (survey → spec → delegate), different execution shape.
- **aidex-conventions** — owns the shared `.context/` canon, the work-list, the autonomy
  surface, and `workflow-core.md`.
