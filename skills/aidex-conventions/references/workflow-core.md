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
- **Implementer is blind to the gate** — `runPhase` calls `phase.implement(feedback, attempt)`
  (no gateCmd) and `verify(id, gateCmd)` (gateCmd → verifier only). Every form's `implement`
  closure MUST pass `spec` but **never** `gateCmd` to the implementer agent, so it cannot read
  the grading test and optimize to it (it satisfies the contract, not a visible test). The
  verifier's proof evidence is the only gate signal the implementer sees, and only as retry
  feedback. (Evolution Phase 1 keystone — closes the "test-visible implementer" leak.)
- **Reviewer is blind to the implementation** — the `review-with-gate` form spawns a **fresh**
  reviewer whose only inputs are the cumulative diff + the plan's success criteria + an optional
  **pushed** `standards_ref`; it is never handed the implementation transcript (it reviews from a
  clean context, not the implementer's grown "dumb zone" session). `standards_ref` is the **push**
  side of push/pull and reaches only the reviewer — an implementer that needs a standard **pulls** a
  targeted one via its phase spec, so the reviewer can enforce a rule the implementer was never shown.
  The review verdict's machine-checkable `passed` boolean (not its prose findings) is the gate
  trigger, mirroring the Bash verifier's `proof.passed`. (Evolution Phase 3 — clean-context review.)
- **`verify_first` carried by the JS loop** in batch — `if (!proof.passed) retry`. The arbiter
  is the carrier only in the interactive (Stop-hook) host.
- **Conditional arbiter** — invoked **only** on machine-checkable triggers (retry budget
  exhausted; a blocked implementer; publication-set not pre-authorized; deny-set), never per gate.
- **Arbiter as director, not just post-mortem judge** — implementers return structured
  `WORK_SCHEMA` output; a `blocked_reason` consults the arbiter *before* burning a gate
  attempt, and a `CONTINUE` re-launches the implementer with the arbiter's direction
  (max 2 redirects per phase). The implementer never stops silently mid-phase.
- **Publication/deny actually gated in batch** — implementers are told to *report*
  pub/deny actions in `pending_actions` (never perform them); `runPhase` routes each
  through `checkAction`: pre-authorized → proceed, `ASK` → batched question collected
  while the phase continues, `STOP` → escalate. This is the carrier `checkAction` was
  designed for (it was previously defined but never called).
- **No proof artifact, no phase pass (BL-208)** — a passed result additionally requires the
  implementer's `WORK_SCHEMA.proof`: a reference to the evidence artifact (test output,
  payload capture, screenshot, `proof_links` entry) produced before the phase commit. A green
  gate with no artifact is retried for the artifact, never passed — this is the mechanical
  carrier of the `proof_links` mandate, which prose alone left at 7.6% adoption.
- **Transient verifier failure ≠ gate verdict** — a `null` proof (verifier agent died)
  gets one verifier retry before counting as a failed attempt.

## Canonical CORE block

Each asset defines its own `export const meta` and embeds **two** single-sourced, drift-locked
blocks verbatim: the **CORE block** below and the **ARBITER block** (the next section). Both are
checked by `test_workflow_core_drift.sh`. The CORE block is everything strictly between the two
marker lines:

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
```

## Canonical ARBITER block

The batch arbiter prompt (`ARBITER_PROMPT`, used by CORE's `arbiter()`) is **single-sourced
here and re-embedded verbatim** in every asset, exactly like the CORE block — the same drift-lock
covers both. This replaces the per-asset abbreviated stubs that could silently diverge.

**Why it is a backtick-free rendering, not `durability-arbiter.md` byte-for-byte.** The
interactive (Stop-hook) host reads
[`../agents/durability-arbiter.md`](../agents/durability-arbiter.md) directly. The batch host
must hold the prompt as a **JS template literal**, and any backtick (or the agent doc's ```json
fence) would terminate that literal — so the markdown agent doc cannot be embedded byte-identically
under the no-`import` constraint. The block below is therefore a faithful, backtick-free rendering
of that doc's **decision policy** (the part that must not drift across hosts), and its requested
output matches CORE's `VERDICT_SCHEMA` (`verdict`/`reason`/`batched_question`/`log`). When the
policy in `durability-arbiter.md` changes, update this block in lockstep —
`test_arbiter_policy_lockstep.sh` guards against a one-sided edit (it asserts both hosts still
carry all five decision tiers + the verdict enum, without requiring byte-identity). The block is
everything strictly between the two marker lines:

```js
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
```

## Adding a catalog entry

1. Copy the CORE block and the ARBITER block above verbatim (markers included) into the new asset.
2. Add `export const meta = { ... }` (pure literal — no variables/calls/spreads).
3. Write only the case-specific part (the form: pipeline-with-gate, fan-out, review, loop-until-green,
   single+arbiter) that calls `parseArgs` / `runPhase` / `checkAction`.
4. Run the drift-lock: `bash skills/aidex-conventions/scripts/test_workflow_core_drift.sh` (it
   checks both the CORE and ARBITER blocks).
5. Run the behaviour guard: `bash skills/aidex-conventions/scripts/test_workflow_core_publication.sh`.
   It extracts CORE from this file and executes it against a mocked `agent()`, so it catches
   what the drift-lock structurally cannot: a CORE that is internally consistent across every
   asset and still wrong. It pins both directions of `checkAction` — a REPORTED publication
   reaches its gate and batches its question (BL-202), a REPORTED destructive action stays a
   terminal STOP.

## Four things a large Workflow run does not tell you

Measured on a cross-project classification run over ~185 rows and 264 verified
candidates.

**Never end a workflow with one synthesis agent emitting the whole result.** A final
agent asked for three large structures in a single structured output froze mid-generation
— 17 minutes, zero bytes, no retry — while all ten upstream agents had completed and
cached. Return the raw per-agent structures and merge them in a deterministic script
afterwards. The merge is mechanical; do not pay an agent to do it, and do not give one
the chance to hang holding every result.

**`args` is not threaded into a workflow on resume.** `Workflow({resumeFromRunId, args})`
left the script's `args` global undefined, so `(args && args.floor) || 'P1'` silently
collapsed to the default and the re-run behaved like the original. Anything a resume
needs must live in the script body or be re-derivable — never only in `args`.

**A prompt's hardcoded instruction silently overrides a dynamic parameter.** The same
run passed a severity floor that a task prompt contradicted in prose, so a "verify
everything down to P3" run only ever verified P0/P1 and deferred the rest. The tell-tale
was a deferred count that never reached zero. When a parameter exists, grep the prompts
for a sentence that states its value.

**A wider re-run can REGRESS what a narrower one verified.** Coverage of 259/259
guarantees a finding is in *some* bucket, never which one: two findings the narrow run
had verified into a high-value shared cluster fell into a catch-all on the wider re-run.
After any re-run, diff the correction sets and check the high-value ids by name. Agents
also drop three or four findings nondeterministically per run — a different set each
time — so the assembler needs a coverage check against source, not against the last run.

**Recovering a run:** the authoritative output is under `result` in the task's `.output`
file. Parse that, rather than scraping the per-agent `.jsonl`.
