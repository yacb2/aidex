# Workflow CORE — the single-sourced durability invariant

**Why this file exists / rationale:** see decision `2026-06-22-plan-exec-workflow-reusable-form`
(workspace-local `.context/decisions/`, gitignored). The `Workflow` tool requires
**self-contained scripts (no `import`)**, so a runtime CORE library is impossible. "Single
source" therefore means: **one canonical CORE block here + mechanical re-embedding into
each asset + a drift-lock test** — not a runtime import.

Every workflow asset under `skills/<skill>/assets/workflows/*.workflow.js` is a **complete,
standalone `Workflow` script** that embeds the block below **verbatim** between its
`CORE:START` / `CORE:END` markers. A drift-lock test
(`skills/aidex-conventions/scripts/test_workflow_core_drift.sh`) diffs each asset's embedded
block against this canonical one and fails on any mismatch.

## What the CORE guarantees (the invariant)

- **`JSON.parse(args)`** — Phase-1 gotcha: `args` arrives as a JSON **string**.
- **Two-stage gate** — a Bash **verifier** agent runs the phase's machine gate and returns
  independent proof; the arbiter never grades its own pass.
- **`verify_first` carried by the JS loop** in batch — `if (!proof.passed) retry`. The arbiter
  is the carrier only in the interactive (Stop-hook) host.
- **Conditional arbiter** — invoked **only** on machine-checkable triggers (retry budget
  exhausted; publication-set not pre-authorized; deny-set), never per gate.

## Canonical CORE block

The asset supplies `ARBITER_PROMPT` (the `durability-arbiter` body; runtime single-sourcing
of that prompt is deferred — see plan Phase 4) and defines its own `export const meta`. The
block is everything strictly between the two marker lines:

```js
// === CORE:START ===
// Gotcha (Phase 1): `args` arrives as a JSON STRING, not a parsed object.
function parseArgs() {
  if (args === undefined || args === null) return {}
  return typeof args === 'string' ? JSON.parse(args) : args
}

// Proof the Bash verifier returns: machine-checkable, never prose.
const PROOF_SCHEMA = {
  type: 'object',
  required: ['passed', 'exit_code', 'evidence'],
  properties: {
    passed: { type: 'boolean' },
    exit_code: { type: 'integer' },
    evidence: { type: 'string' },
  },
  additionalProperties: false,
}

// Arbiter verdict (mirrors durability-arbiter.md).
const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'reason'],
  properties: {
    verdict: { enum: ['CONTINUE', 'ASK', 'STOP'] },
    reason: { type: 'string' },
    batched_question: { type: 'string' },
    log: { type: 'string' },
  },
  additionalProperties: false,
}

// Gate stage 1: a Bash-capable agent RUNS the machine gate and returns independent proof.
function verify(phaseId, gateCmd) {
  return agent(
    `Run exactly this command in the repo and report the result:\n\n    ${gateCmd}\n\n` +
    `Return passed=true ONLY if it exits 0. Put the last ~20 lines of output in evidence.`,
    { label: `verify:${phaseId}`, phase: 'Gate', schema: PROOF_SCHEMA, model: 'sonnet', effort: 'low' }
  )
}

// Conditional arbiter (decision Q2): invoked ONLY on machine-checkable triggers, never per gate.
function arbiter(situation, autonomySurface) {
  return agent(
    `${ARBITER_PROMPT}\n\n## This consultation\n${situation}\n\n## Autonomy surface\n${autonomySurface}`,
    { label: 'arbiter', phase: 'Gate', schema: VERDICT_SCHEMA, model: 'sonnet', effort: 'low' }
  )
}

// Durable per-phase loop: implement -> verify -> retry K -> conditional arbiter on exhaustion.
async function runPhase(phase, ctx) {
  const K = ctx.maxRetries ?? 2
  let feedback = ''
  for (let attempt = 1; attempt <= K + 1; attempt++) {
    const work = await phase.implement(feedback, attempt)
    const proof = await verify(phase.id, phase.gateCmd)
    if (proof.passed) return { phaseId: phase.id, passed: true, attempts: attempt, proof, work }
    feedback = `Attempt ${attempt} failed the gate (exit ${proof.exit_code}). Fix the root cause:\n${proof.evidence}`
    log(`gate ${phase.id}: attempt ${attempt} failed (exit ${proof.exit_code})`)
  }
  const v = await arbiter(
    `Phase ${phase.id} failed its machine gate ${K + 1} times. Decide STOP (clean halt) or ASK (escalate).`,
    ctx.autonomySurface
  )
  return { phaseId: phase.id, passed: false, attempts: K + 1, escalated: v }
}

// Publication/deny trigger (decision Q2): consult the arbiter ONLY when a pending action
// crosses the publication-set (and is not pre-authorized) or the deny-set; else CONTINUE.
async function checkAction(action, ctx) {
  const pub = /\b(push|publish|deploy|release)\b/i.test(action)
  const deny = /\b(drop|delete|destroy|truncate|rm -rf)\b/i.test(action)
  if (!pub && !deny) return { verdict: 'CONTINUE' }
  if (pub && (ctx.preAuthorized || []).includes(action)) return { verdict: 'CONTINUE' }
  return arbiter(`Pending action "${action}" crosses ${pub ? 'publication' : 'deny'}-set.`, ctx.autonomySurface)
}
// === CORE:END ===
```

## Adding a catalog entry

1. Copy the block above verbatim (markers included) into the new asset.
2. Add `export const meta = { ... }` (pure literal — no variables/calls/spreads) and an
   `ARBITER_PROMPT` constant.
3. Write only the case-specific part (the form: pipeline-with-gate, fan-out, loop-until-green,
   single+arbiter) that calls `parseArgs` / `runPhase` / `checkAction`.
4. Run the drift-lock: `bash skills/aidex-conventions/scripts/test_workflow_core_drift.sh`.
