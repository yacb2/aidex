// review-with-gate.workflow.js — catalog entry for a clean-context review stage.
//
// FORM: review-with-gate (terminal, clean-context review). After implementation phases land,
// a FRESH reviewer (opus/high by default) reviews the cumulative diff against the plan's success
// criteria + an optional PUSHED standards_ref — and NEVER the implementation transcript. A reviewer
// running in the implementer's grown session reviews "from the dumb zone"; this form spawns a clean
// context whose only inputs are the diff + criteria + standards (synthesis §5b). The review verdict's
// machine-checkable `passed` boolean is the gate (it mirrors the Bash verifier's `proof.passed`):
// on passed=false the conditional arbiter rules STOP/ASK. Uses parseArgs + arbiter from CORE;
// it implements no phases, so it does not call runPhase/verify.
//
// PUSH/PULL (synthesis §5e): `standards_ref` is the PUSH side — a standard/rule text passed ONLY
// to the reviewer. The implementer never sees it; an implementer that needs a standard PULLS a
// targeted one via its phase spec (in the implementing forms). Keeping standards push-only to the
// reviewer is what lets the reviewer enforce a rule the implementer was never shown.
//
// CONTRACT: launched by the aidex-plan-exec skill via the `Workflow` tool with
//   args = JSON.stringify({ planPath, diffCmd, successCriteria, standards_ref,
//                           reviewModel, reviewEffort, autonomySurface, preAuthorized, maxRetries })
// `args` arrives as a JSON STRING (Phase-1 gotcha) -> parseArgs() does JSON.parse.
// - `diffCmd` — a Bash command the reviewer runs to obtain the cumulative diff under review
//   (e.g. "cd <repo> && git diff main...HEAD"). The script can't run bash; the reviewer is a
//   Bash-capable agent that runs it in its own fresh context.
// - `standards_ref` — optional pushed standard (see PUSH/PULL above). Omitted => criteria alone.
//
// CORE INVARIANT: the block between CORE:START/CORE:END is the canonical durability CORE,
// single-sourced at skills/aidex-conventions/references/workflow-core.md and enforced by
// skills/aidex-conventions/scripts/test_workflow_core_drift.sh. Do NOT edit it here; edit
// the canonical block and re-embed. Rationale: decision 2026-06-22-plan-exec-workflow-reusable-form.
//
// STATUS: catalog entry (evolution plan Phase 3). The drift-lock test is this form's structural
// proof; the review behavior (flags a pushed-standard violation; arbiter fires on passed=false) is
// validated once against a synthetic diff carrying a house-rule violation, with a negative cell
// (same diff, no standards_ref -> not flagged) proving standards_ref is load-bearing.

export const meta = {
  name: 'plan-exec-review-with-gate',
  description: 'Clean-context review: a fresh reviewer judges the cumulative diff vs criteria + pushed standards',
  phases: [
    { title: 'Review', detail: 'fresh opus/high reviewer over the diff + criteria + pushed standards' },
    { title: 'Gate', detail: 'review verdict passed=false -> conditional arbiter' },
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

// ── Case-specific part: the review-with-gate form ────────────────────────────────────
// A fresh reviewer judges the cumulative diff against success criteria + pushed standards,
// never the implementation transcript. Its `passed` boolean is the machine-checkable gate
// trigger (mirrors PROOF_SCHEMA.passed); on passed=false the conditional arbiter rules.

const REVIEW_SCHEMA = {
  type: 'object',
  required: ['passed', 'findings', 'summary'],
  properties: {
    passed: { type: 'boolean' }, // false iff at least one blocking finding
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'detail'],
        properties: {
          severity: { enum: ['blocking', 'minor', 'nit'] },
          detail: { type: 'string' },
          location: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
    summary: { type: 'string' },
  },
  additionalProperties: false,
}

// Fresh reviewer: clean context, inputs are ONLY the diff + success criteria + pushed standards.
// It is NEVER handed the implementation transcript (synthesis §5b). standards_ref is push-only.
function review(cfg) {
  const standards = cfg.standards_ref
    ? `\n\n## Project standards to enforce (in addition to the criteria)\n${cfg.standards_ref}`
    : ''
  return agent(
    `You are a fresh, independent code reviewer. You did NOT write this code and have NOT seen how ` +
    `it was implemented — judge ONLY what the diff shows.\n\n` +
    `Obtain the cumulative diff under review by running exactly this command:\n\n    ${cfg.diffCmd}\n\n` +
    `Review that diff against:\n\n## Success criteria\n${cfg.successCriteria}${standards}\n\n` +
    `Report every violation as a finding with a severity (blocking | minor | nit) and cite the ` +
    `specific criterion or standard it breaks. Set passed=false if and only if there is at least ` +
    `one blocking finding. Do not assume any prior conversation.`,
    {
      label: 'review',
      phase: 'Review',
      schema: REVIEW_SCHEMA,
      model: cfg.reviewModel || 'opus',
      effort: cfg.reviewEffort || 'high',
    }
  )
}

const cfg = parseArgs()
const ctx = {
  autonomySurface: cfg.autonomySurface || 'deny: destructive/data-loss. ask: push/publish/deploy/release. else: proceed+log.',
  preAuthorized: cfg.preAuthorized || [],
  maxRetries: cfg.maxRetries ?? 2,
}

phase('Review') // single sequential stage -> the global phase() call is safe (no concurrency here)
const verdict = await review(cfg)
log(`review: passed=${verdict.passed}, ${verdict.findings.length} finding(s)`)

// Gate: the verdict's machine-checkable `passed` boolean is the trigger (mirrors proof.passed),
// NOT the prose findings -> consistent with CORE's "arbiter only on machine-checkable triggers".
let escalation = null
if (!verdict.passed) {
  phase('Gate')
  const blocking = verdict.findings.filter((f) => f.severity === 'blocking')
  escalation = await arbiter(
    `Clean-context review FAILED its gate (passed=false) with ${blocking.length} blocking finding(s): ` +
      blocking.map((f) => f.detail).join(' | ') +
      `\nDecide STOP (clean halt) or ASK (escalate).`,
    ctx.autonomySurface
  )
  log(`review gate failed -> arbiter ${escalation?.verdict}`)
}

return { planPath: cfg.planPath, review: verdict, escalation }
