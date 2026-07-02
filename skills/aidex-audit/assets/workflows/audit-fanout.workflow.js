// audit-fanout.workflow.js — durable fan-out form for the aidex-audit skill.
//
// FORM: fan-out of analyst subagents over audit dimensions/shards, gated by STRUCTURED OUTPUT
// (a valid finding schema) instead of a Bash test, with a dedup/synthesis barrier, a
// completeness critic, and the conditional durability-arbiter at the escalate-to-backlog boundary.
//
// The per-analyst gate is a SCHEMA gate, not a Bash gate: agent() retries on invalid output
// against FINDING_SCHEMA, so each analyst is self-healing. There is no `gateCmd` / Bash verifier
// in the Analyze phase — the schema IS the pass criterion. The CORE's runPhase() / verify() are
// embedded (drift-lock requirement) but used only at the escalate boundary, not per analyst.
//
// CONTRACT: launched by the aidex-audit skill via the `Workflow` tool with
//   args = JSON.stringify({ dimensions: [{id, prompt}], autonomySurface, preAuthorized,
//                           maxRetries, escalateAction })
// `args` arrives as a JSON STRING -> parseArgs() does JSON.parse.
//
// CORE INVARIANT: the block between CORE:START/CORE:END is the canonical durability CORE,
// single-sourced at skills/aidex-conventions/references/workflow-core.md and enforced by
// skills/aidex-conventions/scripts/test_workflow_core_drift.sh. Do NOT edit it here; edit
// the canonical block and re-embed. Rationale: decision 2026-06-22-plan-exec-workflow-reusable-form.
//
// STATUS: catalog entry (audit durability build). The drift-lock test is this form's
// machine-checkable structural proof; the schema-gate + dedup + completeness-critic + arbiter
// at escalate shape is validated once against the audit skill's dimension set.

export const meta = {
  name: 'audit-fanout',
  description: 'Run an audit as a durable fan-out of analyst agents, schema-gated, with a completeness critic and arbiter at escalate',
  phases: [
    { title: 'Analyze', detail: 'one analyst per dimension, schema-gated' },
    { title: 'Synthesize', detail: 'dedup + completeness critic + escalate gate' },
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
   question at the end.
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
    if (proof && proof.passed) return { phaseId: phase.id, passed: true, attempts: attempt, proof, work, asks }
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
  return arbiter(`Pending action "${action}" crosses ${pub ? 'publication' : 'deny'}-set.`, ctx.autonomySurface)
}
// === CORE:END ===

// ── Case-specific part: the audit fan-out form ───────────────────────────────────────────────
// One analyst agent per dimension (schema-gated, self-healing). A plain-JS dedup barrier follows.
// A completeness critic reviews coverage across all dimensions. The arbiter gates the escalate step.

const cfg = parseArgs()
const ctx = {
  autonomySurface: cfg.autonomySurface || 'deny: destructive/data-loss. ask: push/publish/deploy/release. else: proceed+log.',
  preAuthorized: cfg.preAuthorized || [],
  maxRetries: cfg.maxRetries ?? 2,
}

// Schema that every analyst must satisfy. agent() retries on invalid output — this IS the gate.
const FINDING_SCHEMA = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'title', 'severity', 'evidence', 'dimension'],
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          severity: { enum: ['P1', 'P2', 'P3'] },
          evidence: { type: 'string' },
          dimension: { type: 'string' },
        },
        additionalProperties: false,
      },
    },
  },
  additionalProperties: false,
}

// Phase 1: Analyze — fan-out one analyst per dimension, schema-gated.
phase('Analyze')
const perDim = await parallel(
  (cfg.dimensions || []).map((d) => () =>
    agent(
      `You are an audit analyst for dimension: ${d.id}.\n\n${d.prompt}\n\nReturn every finding you can substantiate with evidence.`,
      { label: `analyze:${d.id}`, phase: 'Analyze', schema: FINDING_SCHEMA, model: 'sonnet', effort: 'medium' }
    )
  )
)

const found = perDim.filter(Boolean).flatMap((r) => r.findings)

// Barrier: dedup findings by `${dimension}::${title}` key (plain JS, not an agent).
const seen = new Set()
const deduped = []
for (const f of found) {
  const key = `${f.dimension}::${f.title}`
  if (!seen.has(key)) {
    seen.add(key)
    deduped.push(f)
  }
}
log(`dedup: ${found.length} raw -> ${deduped.length} unique findings`)

// Phase 2: Synthesize — completeness critic + arbiter at escalate gate.
phase('Synthesize')

// Completeness critic: identifies under-covered or missing dimensions.
const critic = await agent(
  `Audit completeness check. Covered dimensions: ${(cfg.dimensions || []).map((d) => d.id).join(', ')}. Deduped findings: ${JSON.stringify(deduped)}. Name any dimension that was not covered or looks under-covered.`,
  {
    label: 'completeness',
    phase: 'Synthesize',
    schema: {
      type: 'object',
      required: ['missing'],
      properties: {
        missing: { type: 'array', items: { type: 'string' } },
      },
      additionalProperties: false,
    },
    model: 'sonnet',
    effort: 'low',
  }
)
log(`completeness: missing [${(critic.missing || []).join(', ')}]`)

// Escalate gate: arbiter at the escalate-to-backlog boundary (mandated step -> CONTINUE).
const esc = await checkAction(cfg.escalateAction || 'escalate confirmed findings to backlog', ctx)
log(`escalate gate: ${esc.verdict}`)

return { findings: deduped, completeness: critic, escalate: esc }
