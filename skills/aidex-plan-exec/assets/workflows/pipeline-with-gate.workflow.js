// pipeline-with-gate.workflow.js — seed catalog entry for durable plan execution.
//
// FORM: pipeline-with-gate (dependent phases, sequential, each gated). Each plan phase
// runs as a fresh bounded subagent; a two-stage gate (Bash verifier -> conditional
// arbiter) decides continuation; the JS loop is the verify_first carrier in batch.
//
// CONTRACT: launched by the aidex-plan-exec skill via the `Workflow` tool with
//   args = JSON.stringify({ planPath, phases: [{ id, spec, gateCmd, model, effort }],
//                           autonomySurface, preAuthorized, maxRetries })
// `args` arrives as a JSON STRING (Phase-1 gotcha) -> parseArgs() does JSON.parse.
// `gateCmd` is VERIFIER-ONLY: it reaches the Bash verifier, never the implementer (see the
// KEYSTONE note on the implement closure) — the implementer satisfies `spec`, not a visible test.
//
// CORE INVARIANT: the block between CORE:START/CORE:END is the canonical durability CORE,
// single-sourced at skills/aidex-conventions/references/workflow-core.md and enforced by
// skills/aidex-conventions/scripts/test_workflow_core_drift.sh. Do NOT edit it here; edit
// the canonical block and re-embed. Rationale: decision 2026-06-22-plan-exec-workflow-reusable-form.
//
// STATUS: form skeleton (decision Task 2.2). End-to-end runtime re-validation is Phase 3;
// the drift-lock test is this phase's machine-checkable proof.

export const meta = {
  name: 'plan-exec-pipeline-with-gate',
  description: 'Execute a multi-phase plan as gated, dependent phases (each a fresh agent)',
  phases: [
    { title: 'Execute', detail: 'one agent per plan phase, in order' },
    { title: 'Gate', detail: 'Bash verifier -> conditional arbiter' },
  ],
}

// Abbreviated arbiter stub (summarizes skills/aidex-conventions/agents/durability-arbiter.md).
// Verbatim embedding + runtime single-sourcing of the full prompt are deferred to plan Phase 4.
const ARBITER_PROMPT = `You are the durability-arbiter. A running executor is about to stop and ask the user.
Decide CONTINUE / ASK / STOP with the user's standing posture. Deny-class -> STOP;
stop-condition met -> STOP; un-pre-authorized publication -> ASK (batch to the end);
mandated step of the running skill -> CONTINUE; safe + additive -> CONTINUE. Return only the verdict JSON.`

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

// ── Case-specific part: the pipeline-with-gate form ──────────────────────────────────
// Dependent phases run in order; each fresh phase agent gets only its spec + pointers to
// prior outputs on disk (never prior conversation). Each phase carries its own model/effort.

const cfg = parseArgs()
const ctx = {
  autonomySurface: cfg.autonomySurface || 'deny: destructive/data-loss. ask: push/publish/deploy/release. else: proceed+log.',
  preAuthorized: cfg.preAuthorized || [],
  maxRetries: cfg.maxRetries ?? 2,
}

const results = []
for (const p of cfg.phases || []) {
  phase('Execute')
  const phaseSpec = {
    id: p.id,
    gateCmd: p.gateCmd,
    // KEYSTONE (evolution Phase 1): the implementer receives `p.spec` but NEVER `p.gateCmd`.
    // gateCmd goes only to the verifier (CORE `verify()`), so the implementer cannot read the
    // grading test and optimize to it — it must satisfy the spec's contract. This closes the
    // prior plan's "spec-only vs test-visible implementer" leak at the source.
    implement: (feedback, attempt) =>
      agent(
        `Plan: ${cfg.planPath}\nPhase ${p.id} (attempt ${attempt}).\n\n${p.spec}\n\n` +
        `Read prior phase outputs from disk as needed; do NOT assume prior conversation.\n` +
        `Implement the spec's contract fully and correctly. A separate verifier will check your work; ` +
        `you are NOT shown that check, so satisfy the spec itself — do not target a test.\n` +
        (feedback ? `\nPrior attempt feedback (from the verifier):\n${feedback}\n` : ''),
        { label: `exec:${p.id}`, phase: 'Execute', model: p.model || 'sonnet', effort: p.effort || 'medium' }
      ),
  }
  const r = await runPhase(phaseSpec, ctx)
  results.push(r)
  if (!r.passed) {
    log(`phase ${p.id} did not pass after retries -> ${r.escalated?.verdict}; halting pipeline`)
    break   // dependent phases: a failed phase blocks the rest
  }
}

return { planPath: cfg.planPath, results }
