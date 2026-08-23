// fan-out-with-gate.workflow.js — catalog entry for durable plan execution with a DAG.
//
// FORM: fan-out-with-gate (vertical slices + dependency edges, each gated). Phases declare
// `depends_on: []`; edge-free phases run CONCURRENTLY, dependent phases run after their
// prerequisites complete. Every branch — parallel or sequential — keeps the full two-stage
// gate (Bash verifier -> conditional arbiter). This is the gated DAG, NOT Pocock's ungated
// Kanban: parallelism without a gate = unverified parallel failures (plan §"Why", hard guardrail).
//
// SCHEDULING: wave-based. Each iteration runs the set of not-yet-done phases whose `depends_on`
// are all satisfied as ONE parallel() barrier, then advances. This handles arbitrary DAG depth
// (a dependent-of-a-dependent waits its turn) without silently mis-ordering — not just depth-2.
// The barrier is load-bearing: the next wave reads prior outputs off disk ("filesystem IS the
// context"), so a wave must finish before its dependents start.
//
// CONTRACT: launched by the aidex-plan-exec skill via the `Workflow` tool with
//   args = JSON.stringify({ planPath, phases: [{ id, spec, gateCmd, model, effort, depends_on }],
//                           autonomySurface, preAuthorized, maxRetries })
// `args` arrives as a JSON STRING (Phase-1 gotcha) -> parseArgs() does JSON.parse.
// `depends_on` is a list of phase `id`s this phase needs done first (default [] = edge-free).
// `gateCmd` is VERIFIER-ONLY: it reaches the Bash verifier, never the implementer (see the
// KEYSTONE note on the implement closure) — the implementer satisfies `spec`, not a visible test.
//
// CORE INVARIANT: the block between CORE:START/CORE:END is the canonical durability CORE,
// single-sourced at skills/aidex-conventions/references/workflow-core.md and enforced by
// skills/aidex-conventions/scripts/test_workflow_core_drift.sh. Do NOT edit it here; edit
// the canonical block and re-embed. Rationale: decision 2026-06-22-plan-exec-workflow-reusable-form.
//
// STATUS: catalog entry (evolution plan Phase 2.2). The drift-lock test is this form's
// machine-checkable structural proof; the fan-out runtime shape (2 parallel + 1 after, gate on
// every branch, implementer gateCmd-free) is validated once against a synthetic 3-phase fixture.

export const meta = {
  name: 'plan-exec-fan-out-with-gate',
  description: 'Execute a multi-phase plan as a gated DAG: edge-free phases in parallel, dependents after',
  phases: [
    { title: 'Execute', detail: 'edge-free phases concurrently; dependents after their prerequisites' },
    { title: 'Gate', detail: 'Bash verifier -> conditional arbiter, on EVERY branch' },
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

// ── Case-specific part: the fan-out-with-gate form ───────────────────────────────────
// Vertical slices with `depends_on` edges. Edge-free phases run concurrently (one parallel()
// barrier per wave); dependent phases run once their prerequisites are in the completed set.
// Each phase — in any wave — runs the full runPhase() loop, so the two-stage gate fires on
// EVERY branch. KEYSTONE preserved: the implement closure passes `spec` but NEVER `gateCmd`,
// so the implementer cannot read the grading test (gateCmd reaches only the CORE verifier).

const cfg = parseArgs()
const ctx = {
  autonomySurface: cfg.autonomySurface || 'deny: destructive/data-loss. ask: push/publish/deploy/release. else: proceed+log.',
  preAuthorized: cfg.preAuthorized || [],
  maxRetries: cfg.maxRetries ?? 2,
}

const phases = cfg.phases || []

// Build the blind implementer for a phase (gateCmd is NOT in scope here — verifier-only).
// WORK_SCHEMA (director pattern): the implementer reports blocked_reason instead of stopping
// silently, and lists pub/deny actions in pending_actions instead of performing them —
// CORE's runPhase routes those through the arbiter/checkAction.
function makeImplement(p) {
  return (feedback, attempt) =>
    agent(
      `Plan: ${cfg.planPath}\nPhase ${p.id} (attempt ${attempt}).\n\n${p.spec}\n\n` +
      `Autonomy surface (binding): ${ctx.autonomySurface}\n` +
      `NEVER perform publication (push/publish/deploy/release) or destructive actions yourself — ` +
      `list them as pending_actions in your report instead. If genuinely blocked, return ` +
      `done=false with blocked_reason instead of guessing or stopping silently.\n` +
      `Read prior phase outputs from disk as needed; do NOT assume prior conversation.\n` +
      `Implement the spec's contract fully and correctly. A separate verifier will check your work; ` +
      `you are NOT shown that check, so satisfy the spec itself — do not target a test.\n` +
      (feedback ? `\nPrior attempt feedback (from the verifier):\n${feedback}\n` : ''),
      // No global phase('Execute') call: concurrent branches would race it. The per-agent
      // `phase: 'Execute'` opt groups the display safely (CORE's verify() does the same for 'Gate').
      { label: `exec:${p.id}`, phase: 'Execute', schema: WORK_SCHEMA, model: p.model || 'sonnet', effort: p.effort || 'medium' }
    )
}

const completed = new Set()
const blockedIds = new Set()
const results = []
const batchedAsks = []

// A failed phase blocks only its transitive DESCENDANTS — independent branches keep
// running (arbiter policy: finish all other safe work, batch questions at the end).
// This replaces the previous whole-DAG halt, which stopped branches unnecessarily.
function blockDescendants(id) {
  for (const q of phases) {
    if (!completed.has(q.id) && !blockedIds.has(q.id) && (q.depends_on || []).includes(id)) {
      blockedIds.add(q.id)
      blockDescendants(q.id)
    }
  }
}

while (completed.size + blockedIds.size < phases.length) {
  // A wave = every not-yet-done, not-blocked phase whose depends_on are all satisfied.
  // Phases in a wave have no edges between them by construction, so they run concurrently.
  const wave = phases.filter(
    (p) => !completed.has(p.id) && !blockedIds.has(p.id) &&
           (p.depends_on || []).every((d) => completed.has(d))
  )
  if (wave.length === 0) {
    // No runnable phase but not all accounted for -> a dependency cycle or a missing/typo'd id.
    // Surface it (no silent cap) rather than spin forever.
    const remaining = phases.filter((p) => !completed.has(p.id) && !blockedIds.has(p.id)).map((p) => p.id)
    log(`fan-out: no runnable phase — cycle or unsatisfiable depends_on among [${remaining.join(', ')}]`)
    break
  }
  log(`fan-out wave: [${wave.map((p) => p.id).join(', ')}] (${wave.length} concurrent)`)
  const waveResults = await parallel(
    wave.map((p) => () => runPhase({ id: p.id, gateCmd: p.gateCmd, implement: makeImplement(p) }, ctx))
  )
  for (let i = 0; i < wave.length; i++) {
    const r = waveResults[i]
    results.push(r)
    if (r && r.asks && r.asks.length) batchedAsks.push(...r.asks)
    if (r && r.passed) {
      completed.add(wave[i].id)
    } else {
      blockedIds.add(wave[i].id)
      blockDescendants(wave[i].id)
      log(`phase ${wave[i].id} did not pass -> ${r?.escalated?.verdict || 'dropped'}; ` +
          `blocking its descendants, continuing independent branches`)
    }
  }
}

const blocked = [...blockedIds].filter((id) => !results.some((r) => r && r.phaseId === id))
return { planPath: cfg.planPath, results, blocked, batchedAsks }
