// audit-fanout.workflow.js — durable fan-out form for the audit skill.
//
// FORM: fan-out of analyst subagents over audit dimensions/shards, gated by STRUCTURED OUTPUT
// (a valid finding schema) instead of a Bash test, with a dedup/synthesis barrier, a
// completeness critic, and the conditional arbiter prompt at the escalate-to-backlog boundary.
//
// The per-analyst gate is a SCHEMA gate, not a Bash gate: agent() retries on invalid output
// against FINDING_SCHEMA, so each analyst is self-healing. There is no `gateCmd` / Bash verifier
// in the Analyze phase — the schema IS the pass criterion. The CORE's runPhase() / verify() are
// embedded (drift-lock requirement) but this form never calls them. Only checkAction() runs, at
// the escalate boundary: the default escalate action matches neither the publication nor the
// deny set, so it returns CONTINUE without consulting the arbiter; a custom escalateAction that
// crosses one of them is put to the arbiter, except a publication action listed in preAuthorized,
// which also returns CONTINUE with no arbiter call (checkAction, CORE block).
//
// CONTRACT: launched by the audit skill via the `Workflow` tool with
//   args = JSON.stringify({ dimensions: [{id, prompt}], autonomySurface, preAuthorized,
//                           escalateAction })
// `args` arrives as a JSON STRING -> parseArgs() does JSON.parse.
//
// CORE INVARIANT: the block between CORE:START/CORE:END is the canonical durability CORE,
// single-sourced at skills/conventions/references/workflow-core.md and enforced by
// skills/conventions/scripts/test_workflow_core_drift.sh. Do NOT edit it here; edit
// the canonical block and re-embed. Rationale: decision 2026-06-22-plan-exec-workflow-reusable-form.
//
// STATUS: catalog entry (audit durability build). The drift-lock test is this form's
// machine-checkable structural proof; the schema-gate + dedup + completeness-critic + arbiter
// at escalate shape is validated once against the audit skill's dimension set.

export const meta = {
  name: 'audit-fanout',
  description: 'Run an audit as a durable fan-out of analyst agents, schema-gated, with a completeness critic and an escalate gate that consults the arbiter only for a publication or deny action',
  phases: [
    { title: 'Analyze', detail: 'one analyst per dimension, schema-gated' },
    { title: 'Synthesize', detail: 'dedup + completeness critic + escalate gate' },
  ],
}

// Arbiter prompt — single-sourced + drift-locked (see workflow-core.md "Canonical ARBITER block").
// Backtick-free rendering of the ARBITER block in workflow-core.md's decision policy; output matches VERDICT_SCHEMA.
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
3. Unauthorized publication or trunk integration (push, publish, deploy, release, merge into
   the trunk — NOT pre-authorized in the initial
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

// Arbiter verdict (mirrors the ARBITER block in workflow-core.md).
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
    asks: { type: 'array', items: { type: 'string' } },
  },
  additionalProperties: false,
}

const DENY_RE = /\b(drop|delete|destroy|truncate|rm -rf)\b/i

// Gate stage 1: a Bash-capable agent RUNS the machine gate and returns independent proof.
function verify(phaseId, gateCmd) {
  return agent(
    `Run exactly this command in the repo and report the result:\n\n    ${gateCmd}\n\n` +
    `Run it bare — never through a pipe: report the exit status of that command itself, ` +
    `not a pipeline's last stage.\n` +
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
  // A retry COUNT: K retries = K + 1 attempts. `args` arrives as JSON, so a string "3" is
  // coerced (unchecked it made K + 1 = "31"); anything not a non-negative integer is refused.
  const rawK = ctx.maxRetries ?? 2
  if (!/^\d+$/.test(String(rawK))) throw new Error(`maxRetries must be a non-negative integer, got ${JSON.stringify(rawK)}`)
  const K = Number(rawK)
  let feedback = ''
  let directed = 0
  const asks = []
  // The same question reported on several attempts is one question for the owner.
  const ask = (q) => { if (!asks.includes(q)) asks.push(q) }
  // One arbiter consultation per reported action: its wording varies call to call, so
  // consulting again on every attempt would batch the same question several times.
  const verdicts = new Map()
  // Why the last attempt did not pass: the arbiter is told the truth about it.
  let lastFailure = 'failed its machine gate'
  // Bugs the implementer reported instead of patching (an `OUT-OF-SCOPE BUG: ...` summary
  // line), from EVERY attempt, returned on EVERY path: the orchestrator routes them to a
  // bugfix run, so a line dropped here is a bug nobody routes.
  const outOfScopeBugs = []
  // Deny actions sent back as unvetted: a later attempt may drop one only with an `asks` line
  // for it, so the owner learns the run wanted it.
  const owed = new Set()
  for (let attempt = 1; attempt <= K + 1; attempt++) {
    const work = await phase.implement(feedback, attempt)
    // Owner-facing asks from EVERY attempt, kept on every path (the director path included).
    for (const q of (work && work.asks) || []) ask(q)
    for (const line of String((work && work.summary) || '').split('\n')) {
      const bug = line.trim()
      if (bug.startsWith('OUT-OF-SCOPE BUG:') && !outOfScopeBugs.includes(bug)) outOfScopeBugs.push(bug)
    }
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
        feedback = `Arbiter direction: ${v.action || v.reason} Do not stop for this; complete the phase's own work — a bug outside its scope stays unpatched and reported.`
        attempt--
        continue
      }
      return { phaseId: phase.id, passed: false, attempts: attempt, escalated: v || { verdict: 'ASK', reason: 'arbiter unavailable on blocked implementer', unavailable: true }, asks, outOfScopeBugs }
    }
    // Publication/deny path: actions the implementer REPORTED instead of performing.
    const reported = (work && work.pending_actions) || []
    for (const a of owed) {
      if (asks.some((q) => q.toLowerCase().includes(a.toLowerCase()))) owed.delete(a)
    }
    for (const action of reported) {
      // Only a real verdict is remembered: a null (transient arbiter failure) is asked again.
      let c = verdicts.get(action)
      if (!c) { c = await checkAction(action, ctx); if (c) verdicts.set(action, c) }
      if (c && c.verdict === 'STOP') return { phaseId: phase.id, passed: false, attempts: attempt, escalated: c, asks, outOfScopeBugs }
      if (c && c.verdict === 'ASK') ask(c.batched_question || `Authorize: ${action}?`)
      // A deny action with no verdict (arbiter unavailable) fails closed: never to the gate.
      if (c) owed.delete(action)
      else if (DENY_RE.test(action)) owed.add(action)
      // CONTINUE: pre-authorized or outside pub/deny — nothing to gate.
    }
    if (owed.size > 0) {
      if (attempt > K) return { phaseId: phase.id, passed: false, attempts: attempt, escalated: { verdict: 'STOP', reason: 'arbiter returned no verdict on a deny-set action; failing closed', unavailable: true }, asks, outOfScopeBugs }
      feedback = `Your reported deny-set action could not be ruled on: ${[...owed].map((a) => JSON.stringify(a)).join('; ')}. ` +
        'Re-report it with exactly this text, or add a line quoting it to asks (finishing the phase without it).'
      continue
    }
    let proof = await verify(phase.id, phase.gateCmd)
    if (!proof) proof = await verify(phase.id, phase.gateCmd) // null = transient verifier failure, not a gate verdict: one retry
    if (proof && proof.passed) {
      // A green machine gate is not enough — the phase result must carry
      // the implementer's own proof artifact (test output, request/response
      // payload, screenshot path, proof_links entry) BEFORE the phase commit.
      // 10 user-caught defects in one measured week arrived after the first
      // commit; proof_links adoption by prose mandate alone sat at 7.6%.
      // A report of done=false is unfinished work whatever the gate says.
      if (!(work && work.done === true)) {
        lastFailure = !work ? 'passed its machine gate but the implementer returned no report'
          : `passed its machine gate but its report said done=false${work.blocked_reason ? ` (blocked_reason: ${work.blocked_reason})` : ''}`
        feedback = `The gate passed but your report is missing or says done=false. Finish the phase's work and ` +
          `re-report done=true with its proof, or return blocked_reason if you are genuinely blocked.`
        log(`gate ${phase.id}: attempt ${attempt} green but report not done — retrying`)
        continue
      }
      if (!(typeof work.proof === 'string' && work.proof.trim())) {
        lastFailure = 'passed its machine gate but its report carried no proof artifact'
        feedback = `The gate passed but your report carries no proof artifact. Re-report with ` +
          `proof = a path or reference to the evidence (test output, payload capture, screenshot, ` +
          `proof_links entry). Do not re-implement; produce and name the artifact.`
        log(`gate ${phase.id}: attempt ${attempt} green but no proof artifact — retrying for proof`)
        continue
      }
      return { phaseId: phase.id, passed: true, attempts: attempt, proof, work, asks, outOfScopeBugs }
    }
    lastFailure = 'failed its machine gate'
    feedback = `Attempt ${attempt} failed the gate (exit ${proof ? proof.exit_code : 'n/a'}). Fix the root cause:\n${proof ? proof.evidence : 'verifier unavailable'}`
    log(`gate ${phase.id}: attempt ${attempt} failed (exit ${proof ? proof.exit_code : 'n/a'})`)
  }
  const v = await arbiter(
    `Phase ${phase.id} did not pass in ${K + 1} attempts; the last attempt ${lastFailure}. Decide STOP (clean halt) or ASK (escalate).`,
    ctx.autonomySurface
  )
  return { phaseId: phase.id, passed: false, attempts: K + 1, escalated: v, asks, outOfScopeBugs }
}

// Publication/deny trigger (decision Q2): consult the arbiter ONLY when a pending action
// crosses the publication-set (and is not pre-authorized) or the deny-set; else CONTINUE.
async function checkAction(action, ctx) {
  const pub = /\b(push|publish|deploy|release|merge)\b/i.test(action)
  const deny = DENY_RE.test(action)
  if (!pub && !deny) return { verdict: 'CONTINUE' }
  // Pre-authorization never covers the deny-set: a destructive action stays the arbiter's call.
  if (pub && !deny && (ctx.preAuthorized || []).includes(action)) return { verdict: 'CONTINUE' }
  // Actions are free text, so the exact match above rarely hits: the arbiter sees the list
  // (never for a deny-set action: pre-authorization does not cover it).
  const authorized = !deny && (ctx.preAuthorized || []).length
    ? ` Pre-authorized in the initial phase: ${JSON.stringify(ctx.preAuthorized)}.` : ''
  const v = await arbiter(`Pending action "${action}" crosses the ${deny ? 'deny' : 'publication'}-set.${authorized}`, ctx.autonomySurface)
  // A publication the implementer REPORTED instead of performing is a question, never a
  // halt. Nothing was published — declining and reporting is the behaviour CORE asks for —
  // and in a run whose surface is "local commits only" an unpushed commit is the DESIRED
  // END STATE. A STOP here kills the phase before its gate and blocks every descendant,
  // the arbiter once returned STOP while its own reason
  // named tier 3 (ASK). Downgrade it to the batched question the tier actually calls for.
  // The deny-set keeps its terminal STOP: an action that is destructive stays a halt.
  if (pub && !deny && v && v.verdict === 'STOP') {
    return { verdict: 'ASK', reason: v.reason,
             batched_question: v.batched_question || `Authorize: ${action}?` }
  }
  return v
}
// === CORE:END ===

// ── Case-specific part: the audit fan-out form ───────────────────────────────────────────────
// One analyst agent per dimension (schema-gated, self-healing). A plain-JS dedup barrier follows.
// A completeness critic reviews coverage across all dimensions. The escalate step consults the arbiter only when escalateAction crosses the publication or deny set.

const cfg = parseArgs()
const ctx = {
  autonomySurface: cfg.autonomySurface || 'deny: destructive/data-loss. ask: push/publish/deploy/release/merge-into-trunk. else: proceed+log.',
  preAuthorized: cfg.preAuthorized || [],
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
          severity: { enum: ['P0', 'P1', 'P2', 'P3'] },
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

// An analyst that returned nothing (null after its retries) is a coverage gap, not a clean
// dimension: name it, and tell the critic only about the dimensions that answered.
const dimensions = cfg.dimensions || []
const failedDimensions = dimensions.filter((d, i) => !perDim[i]).map((d) => d.id)
const coveredDimensions = dimensions.filter((d, i) => perDim[i]).map((d) => d.id)
if (failedDimensions.length) log(`analysts failed: [${failedDimensions.join(', ')}]`)
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

// Phase 2: Synthesize — completeness critic + escalate gate (arbiter only for a publication or deny action).
phase('Synthesize')

// Completeness critic: identifies under-covered or missing dimensions.
const critic = await agent(
  `Audit completeness check. Covered dimensions: ${coveredDimensions.join(', ')}.${failedDimensions.length ? ` Analyst failed, NOT covered: ${failedDimensions.join(', ')}.` : ''} Deduped findings: ${JSON.stringify(deduped)}. Name any dimension that was not covered or looks under-covered.`,
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
log(critic ? `completeness: missing [${(critic.missing || []).join(', ')}]` : 'completeness: critic returned nothing')

// Escalate gate: arbiter at the escalate-to-backlog boundary (mandated step -> CONTINUE).
const esc = await checkAction(cfg.escalateAction || 'escalate confirmed findings to backlog', ctx)
log(`escalate gate: ${esc ? esc.verdict : 'no ruling'}`)

return { findings: deduped, completeness: critic, escalate: esc, failedDimensions }
