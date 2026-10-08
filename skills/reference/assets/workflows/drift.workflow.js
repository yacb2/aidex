// drift.workflow.js — /aidex:reference drift: which references no longer match the code.
//
// Launched by the reference skill via the Workflow tool with scriptPath, never regenerated per run.
// A Workflow script has no filesystem: the pre-launch step (skills/reference/scripts/drift/prepare.py)
// writes the work dir, and prompts below name files in it instead of inlining content.
//
// ARGS (object or JSON string):
//   root    absolute project root (the code and .context/references live here)
//   work    absolute work dir written by prepare.py: <work>/manifest.json, <work>/units/<slug>.txt
//   date    ISO date of the run (logged only)
//   units   array of unit slugs to run, taken from manifest.json (keep it a list of slugs, not objects)
//   verify  optional boolean, default true; false skips the verify stage and compare gets every extracted fact
//
// PER UNIT: extract (aidex:drift-extract) -> verify (aidex:drift-verify) -> compare (aidex:drift-compare).
// Every agent call goes through safe(): a stage that throws or returns no structured output is logged
// and the unit stops there, status "failed"; the run completes with the other units.
// Compare receives only `confirmed` facts (when verify is false: the extracted `traced` facts, flagged to the comparer as not verified). One compare per unit.
// No plan, concept, write or refute stage; nothing is ever edited.
// Do not resume a run after editing this script: inner pipeline calls re-run and are paid twice.
//
// RESULT (returned, JSON):
//   { run: {root, work, date, verify},
//     units: [{ slug, status: "ok"|"failed", failed_stage: null|"extract"|"verify"|"compare"|"unknown",
//               facts_extracted, facts_confirmed (null when verify is off), facts_dropped_inferred (verify off),
//               facts_to_compare (what compare was given), not_covered (count), findings }],
//     findings: [{ type: "stale"|"wrong"|"missing", reference, reference_line, detail,
//                  evidence: "file:line", unit: slug }] }
// A unit with zero facts (and no uncovered files) or zero confirmed facts is "ok" with findings 0 (compare is skipped).
// A unit whose extract read nothing while files stayed uncovered, or whose verdict indices are not exactly 0..N-1, is "failed".

export const meta = {
  name: 'reference-drift',
  description: 'Find .context/references modules that no longer match the code: extract, verify and compare per code unit',
  whenToUse: 'Launched by /aidex:reference drift after prepare.py wrote the work dir',
  phases: [
    { title: 'Units', detail: 'per unit: extract (haiku) -> verify (sonnet) -> compare (sonnet)' },
  ],
}

// Embedded below, unused here: the drift-lock guard (skills/conventions/scripts/test_workflow_core_drift.sh)
// requires every workflow asset to carry the canonical ARBITER and CORE blocks verbatim. This form
// has no gate, arbiter or escalate step; only parseArgs() is called. Do not edit the blocks.
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
  },
  additionalProperties: false,
}

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
  const K = ctx.maxRetries ?? 2
  let feedback = ''
  let directed = 0
  const asks = []
  // Bugs the implementer reported instead of patching (an `OUT-OF-SCOPE BUG: ...` summary
  // line), from EVERY attempt, returned on EVERY path: the orchestrator routes them to a
  // bugfix run, so a line dropped here is a bug nobody routes.
  const outOfScopeBugs = []
  for (let attempt = 1; attempt <= K + 1; attempt++) {
    const work = await phase.implement(feedback, attempt)
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
      return { phaseId: phase.id, passed: false, attempts: attempt, escalated: v || { verdict: 'ASK', reason: 'arbiter unavailable on blocked implementer' }, asks, outOfScopeBugs }
    }
    // Publication/deny path: actions the implementer REPORTED instead of performing.
    for (const action of (work && work.pending_actions) || []) {
      const c = await checkAction(action, ctx)
      if (c && c.verdict === 'STOP') return { phaseId: phase.id, passed: false, attempts: attempt, escalated: c, asks, outOfScopeBugs }
      if (c && c.verdict === 'ASK') asks.push(c.batched_question || `Authorize: ${action}?`)
      // CONTINUE: pre-authorized or outside pub/deny — nothing to gate.
    }
    let proof = await verify(phase.id, phase.gateCmd)
    if (!proof) proof = await verify(phase.id, phase.gateCmd) // null = transient verifier failure, not a gate verdict: one retry
    if (proof && proof.passed) {
      // A green machine gate is not enough — the phase result must carry
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
      return { phaseId: phase.id, passed: true, attempts: attempt, proof, work, asks, outOfScopeBugs }
    }
    feedback = `Attempt ${attempt} failed the gate (exit ${proof ? proof.exit_code : 'n/a'}). Fix the root cause:\n${proof ? proof.evidence : 'verifier unavailable'}`
    log(`gate ${phase.id}: attempt ${attempt} failed (exit ${proof ? proof.exit_code : 'n/a'})`)
  }
  const v = await arbiter(
    `Phase ${phase.id} failed its machine gate ${K + 1} times. Decide STOP (clean halt) or ASK (escalate).`,
    ctx.autonomySurface
  )
  return { phaseId: phase.id, passed: false, attempts: K + 1, escalated: v, asks, outOfScopeBugs }
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

const A = parseArgs()
const useVerify = A.verify !== false
const str = { type: 'string' }
const int = { type: 'integer' }

const FACTS = { type: 'object', required: ['facts', 'not_covered'], properties: {
  facts: { type: 'array', items: { type: 'object',
    required: ['claim', 'symbol', 'file', 'line_start', 'line_end', 'kind', 'provenance'],
    properties: { claim: str, symbol: str, file: str, line_start: int, line_end: int,
      kind: { enum: ['api', 'behavior', 'config', 'invariant', 'relation'] },
      provenance: { enum: ['traced', 'inferred'] }, evidence: str } } },
  not_covered: { type: 'array', items: str } } }
const VERDICTS = { type: 'object', required: ['verdicts'], properties: {
  verdicts: { type: 'array', items: { type: 'object', required: ['i', 'verdict', 'evidence'],
    properties: { i: int, verdict: { enum: ['confirmed', 'refuted', 'unverifiable'] }, evidence: str } } } } }
const COMPARE = { type: 'object', required: ['items'], properties: {
  items: { type: 'array', items: { type: 'object',
    required: ['type', 'reference', 'reference_line', 'detail', 'evidence'],
    properties: { type: { enum: ['stale', 'wrong', 'missing'] }, reference: str, reference_line: { type: 'integer', minimum: 1 },
      detail: str, evidence: str } } } } }

// A stage that fails (schema never returned, maxTurns hit) drops its unit and is logged;
// it never fails the whole run (pilot run 3, 2026-10-08: one compare agent killed 30 finished agents).
async function safe(prompt, opts) {
  try { return await agent(prompt, opts) }
  catch (e) { log(`FAILED ${opts.label}: ${String(e && e.message || e).slice(0, 200)}`); return null }
}

const factLine = (f, i) => `${i}. [${f.file}:${f.line_start}-${f.line_end} · ${f.symbol}] ${f.claim}`

const extractPrompt = slug => `Project root: ${A.root}
Unit: ${slug}
The unit's files, one path per line relative to the project root, are listed in ${A.work}/units/${slug}.txt. Read that list, then read each file in it once.
Return up to 40 facts, most important first, in the schema. Paths in "file" are relative to the project root.`

const verifyPrompt = facts => `Project root: ${A.root}
Refute or confirm each numbered fact below against the code it cites. One verdict per index, ${facts.length} in total.

${facts.map(factLine).join('\n')}`

const comparePrompt = (slug, facts) => `Project root: ${A.root}
Unit: ${slug}
The candidate references (matched by path or symbol) for this unit, one path per line relative to the project root, are listed in ${A.work}/units/${slug}.refs.txt. Read only those references. Set \`reference\` in every item to the path exactly as written in that file.
${useVerify
  ? 'Each fact below was confirmed against the current code.'
  : 'The facts below were extracted and NOT verified: check each one in the code before you report anything against it, and drop any you cannot confirm.'}
Report, with the reference path and line: "stale" = the reference says something the facts show has changed; "wrong" = the reference contradicts a fact; "missing" = a fact a reader of that reference would need and it lacks, reported only against a reference whose subject is this unit's code (a candidate that merely mentions the unit is not one). Cite code evidence as file:line for every item. Open the code to settle any doubt. Nothing else.

${facts.map(factLine).join('\n')}`

const done = (slug, status, failed_stage, extra) => ({ slug, status, failed_stage, facts_extracted: 0,
  facts_confirmed: useVerify ? 0 : null, facts_dropped_inferred: 0, facts_to_compare: 0, not_covered: 0, findings: [], ...extra })

phase('Units')
if (!Array.isArray(A.units) || !A.units.length) throw new Error('args.units must be a non-empty list of unit slugs from manifest.json')
const slugs = A.units
log(`drift ${A.date || ''}: ${slugs.length} units, verify ${useVerify}`)

const results = await pipeline(slugs,
  async slug => {
    const r = await safe(extractPrompt(slug), { label: `extract:${slug}`, phase: 'Units',
      agentType: 'aidex:drift-extract', schema: FACTS })
    if (!r) return done(slug, 'failed', 'extract')
    const info = { facts_extracted: r.facts.length, not_covered: r.not_covered.length }
    // Nothing read while files stayed uncovered: the unit was not examined, so it is not "ok".
    if (!r.facts.length && r.not_covered.length) return done(slug, 'failed', 'extract', info)
    // Without verify, a fact deduced from a name or comment must not reach compare.
    const facts = useVerify ? r.facts : r.facts.filter(f => f.provenance === 'traced')
    return done(slug, 'ok', null, { ...info, facts, facts_dropped_inferred: r.facts.length - facts.length })
  },
  async (st, slug) => {
    if (st.status === 'failed') return st
    if (!useVerify || !st.facts.length) return { ...st, confirmed: st.facts }
    const v = await safe(verifyPrompt(st.facts), { label: `verify:${slug}`, phase: 'Units',
      agentType: 'aidex:drift-verify', schema: VERDICTS })
    const fail = () => done(slug, 'failed', 'verify', { facts_extracted: st.facts_extracted, not_covered: st.not_covered })
    if (!v) return fail()
    // The verdict indices must be exactly 0..N-1: anything else means the verifier answered a different list.
    const idx = new Set(v.verdicts.map(x => x.i))
    if (v.verdicts.length !== st.facts.length || idx.size !== st.facts.length || !st.facts.every((f, i) => idx.has(i))) {
      log(`verify:${slug}: verdict indices are not exactly 0..${st.facts.length - 1}`)
      return fail()
    }
    const byI = new Map(v.verdicts.map(x => [x.i, x.verdict]))
    return { ...st, confirmed: st.facts.filter((f, i) => byI.get(i) === 'confirmed') }
  },
  async (st, slug) => {
    if (st.status === 'failed') return st
    const base = { facts_extracted: st.facts_extracted, not_covered: st.not_covered,
      facts_dropped_inferred: st.facts_dropped_inferred, facts_to_compare: st.confirmed.length,
      facts_confirmed: useVerify ? st.confirmed.length : null }
    if (!st.confirmed.length) return done(slug, 'ok', null, base)
    const c = await safe(comparePrompt(slug, st.confirmed), { label: `compare:${slug}`, phase: 'Units',
      agentType: 'aidex:drift-compare', schema: COMPARE })
    if (!c) return done(slug, 'failed', 'compare', base)
    return done(slug, 'ok', null, { ...base, findings: c.items.map(it => ({ ...it, unit: slug })) })
  })

const rows = results.filter(Boolean)
const failed = rows.filter(r => r.status === 'failed')
if (failed.length) log(`${failed.length} unit(s) failed: ${failed.map(r => `${r.slug}@${r.failed_stage}`).join(', ')}`)
// A unit the pipeline itself dropped (null) is reported as failed so no unit vanishes silently.
const seen = new Set(rows.map(r => r.slug))
const lost = slugs.filter(s => !seen.has(s)).map(s => done(s, 'failed', 'unknown'))

return {
  run: { root: A.root, work: A.work, date: A.date, verify: useVerify },
  units: [...rows, ...lost].map(r => ({ slug: r.slug, status: r.status, failed_stage: r.failed_stage,
    facts_extracted: r.facts_extracted, facts_confirmed: r.facts_confirmed, facts_dropped_inferred: r.facts_dropped_inferred,
    facts_to_compare: r.facts_to_compare, not_covered: r.not_covered,
    findings: r.findings.length })),
  findings: [...rows, ...lost].flatMap(r => r.findings),
}
