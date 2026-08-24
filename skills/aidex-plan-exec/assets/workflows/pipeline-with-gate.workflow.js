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

// Arbiter prompt — single-sourced + drift-locked (see workflow-core.md "Canonical ARBITER block").
// Backtick-free rendering of agents/durability-arbiter.md's decision policy; output matches VERDICT_SCHEMA.
// === ARBITER:START ===
const ARBITER_PROMPT = `You are the durability-arbiter. A running executor (a plan execution, a
loop, an audit, a backlog sweep) is about to stop and ask the user. Before it does, it asks you.
Keep it working autonomously as long as that is correct — you are the user's standing proxy
("don't stop yet, you can do this, continue") — but with criterion. You decide; you do not do the
work. Default posture: interrupting the user is the expensive action; authorize CONTINUE unless
the operation is genuinely the user's call or unsafe.

Classify the pending action, in order:
1. Deny-class (destructive / irreversible-with-data-loss: dropping or deleting data, DB deletion,
   a destructive migration, or conflict with a registered ADR) -> STOP; tell the executor to skip
   and document it.
2. Stop condition met (loop/sweep target reached, or no safe work left) -> STOP.
3. Unauthorized publication (push, publish, deploy, release NOT pre-authorized in the initial
   phase) -> ASK; do not authorize mid-run; finish all other safe work and surface ONE batched
   question at the end. This tier is ASK and never STOP, including when the executor reports
   MANY unpublished units across MANY repositories: it is telling you it declined to publish,
   which is the behaviour you want, and in a run whose surface is "local commits only" an
   unpushed commit is the desired end state rather than a hazard. Answering STOP here kills a
   phase that already did its work and blocks every phase downstream of it. Reserve STOP for
   tier 1 and tier 2.
4. Mandated step of the running skill (code-review, commit, commit-message authoring, handoff,
   escalate-to-backlog) -> CONTINUE; never let the executor re-confirm these.
5. Safe + additive (dependency changes, additive migrations, an unforeseen non-breaking decision)
   -> CONTINUE; log the bifurcation.
A genuine hard blocker (missing credentials, truly unknowable intended behavior) is not yours to
override -> ASK, noting it is a blocker, not a permission ask.

Verification gate: a CONTINUE on a state-mutating action requires proof it is safe (tests green,
additive, reversible). If the action mutates state and no proof is provided, still lean CONTINUE
but name the exact check the executor must run and pass first. The gate is "is there proof this is
safe?", not merely "is it in the allow-set?".

Bias to CONTINUE; never invent a reason to stop; be terse. Return ONLY the verdict JSON
(verdict = CONTINUE | ASK | STOP; reason = one sentence on which tier fired; batched_question =
for ASK, the single question to surface at the end; log = one line to record). No prose outside
the JSON.`
// === ARBITER:END ===

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
    action: { type: 'string' },
    batched_question: { type: 'string' },
    log: { type: 'string' },
  },
  additionalProperties: false,
}

// Structured implementer report: lets the arbiter DIRECT a blocked implementer
// mid-phase (instead of ruling post-mortem on retry exhaustion) and routes
// publication/deny actions through checkAction instead of the implementer
// performing them. Every implementing form's agent MUST use this schema.
const WORK_SCHEMA = {
  type: 'object',
  required: ['done', 'summary'],
  properties: {
    done: { type: 'boolean' },
    summary: { type: 'string' },
    proof: { type: 'string' },
    blocked_reason: { type: 'string' },
    pending_actions: { type: 'array', items: { type: 'string' } },
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

// Durable per-phase loop: implement -> (director on blocked / pending actions) ->
// verify -> retry K -> conditional arbiter on exhaustion.
async function runPhase(phase, ctx) {
  const K = ctx.maxRetries ?? 2
  let feedback = ''
  let directed = 0
  const asks = []
  for (let attempt = 1; attempt <= K + 1; attempt++) {
    const work = await phase.implement(feedback, attempt)
    // Director path: a blocked implementer consults the arbiter BEFORE burning a gate
    // attempt; CONTINUE re-launches it with the direction (max 2 redirects per phase).
    if (work && work.blocked_reason && !work.done && directed < 2) {
      const v = await arbiter(
        `Implementer of phase ${phase.id} reports it is blocked: ${work.blocked_reason}. ` +
        `If the block is not genuine, direct it to continue (CONTINUE with action); else STOP/ASK.`,
        ctx.autonomySurface
      )
      if (v && v.verdict === 'CONTINUE') {
        directed++
        feedback = `Arbiter direction: ${v.action || v.reason} Do not stop for this; complete the phase.`
        attempt--
        continue
      }
      return { phaseId: phase.id, passed: false, attempts: attempt, escalated: v || { verdict: 'ASK', reason: 'arbiter unavailable on blocked implementer' }, asks }
    }
    // Publication/deny path: actions the implementer REPORTED instead of performing.
    for (const action of (work && work.pending_actions) || []) {
      const c = await checkAction(action, ctx)
      if (c && c.verdict === 'STOP') return { phaseId: phase.id, passed: false, attempts: attempt, escalated: c, asks }
      if (c && c.verdict === 'ASK') asks.push(c.batched_question || `Authorize: ${action}?`)
      // CONTINUE: pre-authorized or outside pub/deny — nothing to gate.
    }
    let proof = await verify(phase.id, phase.gateCmd)
    if (!proof) proof = await verify(phase.id, phase.gateCmd) // null = transient verifier failure, not a gate verdict: one retry
    if (proof && proof.passed) {
      // BL-208: a green machine gate is not enough — the phase result must carry
      // the implementer's own proof artifact (test output, request/response
      // payload, screenshot path, proof_links entry) BEFORE the phase commit.
      // 10 user-caught defects in one measured week arrived after the first
      // commit; proof_links adoption by prose mandate alone sat at 7.6%.
      if (!(work && typeof work.proof === 'string' && work.proof.trim())) {
        feedback = `The gate passed but your report carries no proof artifact. Re-report with ` +
          `proof = a path or reference to the evidence (test output, payload capture, screenshot, ` +
          `proof_links entry). Do not re-implement; produce and name the artifact.`
        log(`gate ${phase.id}: attempt ${attempt} green but no proof artifact — retrying for proof`)
        continue
      }
      return { phaseId: phase.id, passed: true, attempts: attempt, proof, work, asks }
    }
    feedback = `Attempt ${attempt} failed the gate (exit ${proof ? proof.exit_code : 'n/a'}). Fix the root cause:\n${proof ? proof.evidence : 'verifier unavailable'}`
    log(`gate ${phase.id}: attempt ${attempt} failed (exit ${proof ? proof.exit_code : 'n/a'})`)
  }
  const v = await arbiter(
    `Phase ${phase.id} failed its machine gate ${K + 1} times. Decide STOP (clean halt) or ASK (escalate).`,
    ctx.autonomySurface
  )
  return { phaseId: phase.id, passed: false, attempts: K + 1, escalated: v, asks }
}

// Publication/deny trigger (decision Q2): consult the arbiter ONLY when a pending action
// crosses the publication-set (and is not pre-authorized) or the deny-set; else CONTINUE.
async function checkAction(action, ctx) {
  const pub = /\b(push|publish|deploy|release)\b/i.test(action)
  const deny = /\b(drop|delete|destroy|truncate|rm -rf)\b/i.test(action)
  if (!pub && !deny) return { verdict: 'CONTINUE' }
  if (pub && (ctx.preAuthorized || []).includes(action)) return { verdict: 'CONTINUE' }
  const v = await arbiter(`Pending action "${action}" crosses ${pub ? 'publication' : 'deny'}-set.`, ctx.autonomySurface)
  // A publication the implementer REPORTED instead of performing is a question, never a
  // halt. Nothing was published — declining and reporting is the behaviour CORE asks for —
  // and in a run whose surface is "local commits only" an unpushed commit is the DESIRED
  // END STATE. A STOP here kills the phase before its gate and blocks every descendant,
  // which is BL-202: observed 2026-08-23, the arbiter returned STOP while its own reason
  // named tier 3 (ASK). Downgrade it to the batched question the tier actually calls for.
  // The deny-set keeps its terminal STOP: an action that is destructive stays a halt.
  if (pub && !deny && v && v.verdict === 'STOP') {
    return { verdict: 'ASK', reason: v.reason,
             batched_question: v.batched_question || `Authorize: ${action}?` }
  }
  return v
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
const batchedAsks = []
for (const p of cfg.phases || []) {
  phase('Execute')
  const phaseSpec = {
    id: p.id,
    gateCmd: p.gateCmd,
    // KEYSTONE (evolution Phase 1): the implementer receives `p.spec` but NEVER `p.gateCmd`.
    // gateCmd goes only to the verifier (CORE `verify()`), so the implementer cannot read the
    // grading test and optimize to it — it must satisfy the spec's contract. This closes the
    // prior plan's "spec-only vs test-visible implementer" leak at the source.
    // WORK_SCHEMA (director pattern): the implementer reports blocked_reason instead of
    // stopping silently, and lists pub/deny actions in pending_actions instead of
    // performing them — CORE's runPhase routes those through the arbiter/checkAction.
    implement: (feedback, attempt) =>
      agent(
        `Plan: ${cfg.planPath}\nPhase ${p.id} (attempt ${attempt}).\n\n${p.spec}\n\n` +
        `Autonomy surface (binding): ${ctx.autonomySurface}\n` +
        `NEVER perform publication (push/publish/deploy/release) or destructive actions yourself — ` +
        `list them as pending_actions in your report instead. Report proof = a reference to the\n` +
        `evidence artifact for this phase (test output path, payload capture, screenshot, \n` +
        `proof_links entry) — a phase without one does not pass, however green the gate. If genuinely blocked, return ` +
        `done=false with blocked_reason instead of guessing or stopping silently.\n` +
        `Read prior phase outputs from disk as needed; do NOT assume prior conversation.\n` +
        `Implement the spec's contract fully and correctly. A separate verifier will check your work; ` +
        `you are NOT shown that check, so satisfy the spec itself — do not target a test.\n` +
        (feedback ? `\nPrior attempt feedback (from the verifier):\n${feedback}\n` : ''),
        { label: `exec:${p.id}`, phase: 'Execute', schema: WORK_SCHEMA, model: p.model || 'sonnet', effort: p.effort || 'medium' }
      ),
  }
  const r = await runPhase(phaseSpec, ctx)
  results.push(r)
  if (r && r.asks && r.asks.length) batchedAsks.push(...r.asks)
  if (!r.passed) {
    log(`phase ${p.id} did not pass after retries -> ${r.escalated?.verdict}; halting pipeline`)
    break   // dependent phases (a chain): a failed phase blocks everything downstream
  }
}

return { planPath: cfg.planPath, results, batchedAsks }
