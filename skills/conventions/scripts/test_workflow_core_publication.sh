#!/usr/bin/env bash
# test_workflow_core_publication.sh — BL-202 regression.
#
# A phase whose implementer REPORTS an unauthorized publication (instead of performing it)
# must still reach its gate. The report is the correct behaviour, and in a run whose
# autonomy surface is "local commits only" an unpushed commit is the DESIRED END STATE,
# never a stop condition. The question belongs in the end-of-run batch.
#
# Observed 2026-08-23 (run wf_23683fa9-f5b, plan/2026-08-22-suite-speed-and-coverage-rollout):
# Phase 2 finished its work, listed `git push` in pending_actions exactly as CORE asks, and
# the arbiter answered STOP while its own reason named tier 3 -- which is ASK. runPhase
# treats STOP as terminal, so the phase was recorded failed BEFORE its gate ran a second
# time, and blockDescendants then blocked Phase 9, which had nothing to do with publishing.
# The gate, re-run by hand with no further changes: 192 passed, exit 0.
#
# The deny-set keeps its terminal STOP: this test asserts BOTH directions, because a fix
# that lets a destructive action through would be worse than the bug.
#
# Run:  bash skills/conventions/scripts/test_workflow_core_publication.sh
# Exit: 0 if both cases behave; 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="$REPO_ROOT/skills/conventions/references/workflow-core.md"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 2; }
[ -f "$CANON" ] || { echo "FAIL: canonical doc not found: $CANON" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The CORE block is plain JS with no imports, so it runs verbatim once the ambient
# helpers it calls (agent/log) are provided. Extracting rather than re-typing is the
# point: this test exercises the SHIPPED code, not a paraphrase of it.
extract_block() {
  awk -v name="$2" '
    $0 == "// === " name ":START ===" { grab=1; next }
    $0 == "// === " name ":END ==="   { if (grab) exit }
    grab { print }
  ' "$1"
}

# ARBITER first: CORE's arbiter() closes over ARBITER_PROMPT, which lives in that block.
# Prepending the real one rather than stubbing it keeps the harness faithful and stops
# this test from needing a patch every time CORE reaches for something new.
extract_block "$CANON" "ARBITER" >  "$WORK/core.js"
extract_block "$CANON" "CORE"    >> "$WORK/core.js"
grep -q "function runPhase" "$WORK/core.js" || { echo "FAIL: no CORE block between markers in $CANON" >&2; exit 1; }

cat > "$WORK/run.js" <<'JS'
const fs = require('fs')
const path = process.argv[2]

let calls = []
// Ambient helpers the CORE block calls. `agent` is dispatched on the label so each
// stage can be steered independently; every call is recorded so the assertions can
// check what actually ran rather than only what was returned.
globalThis.log = () => {}
globalThis.args = undefined
globalThis.parallel = (thunks) => Promise.all(thunks.map((t) => t()))

let scenario = null
let arbiterPrompts = []
globalThis.agent = async (prompt, opts) => {
  const label = (opts && opts.label) || 'arbiter'
  calls.push(label)
  if (label === 'arbiter') arbiterPrompts.push(prompt)
  if (label.startsWith('verify:')) return { passed: true, exit_code: 0, evidence: 'gate ran' }
  if (scenario === 'flaky') { // first arbiter call fails transiently (null), later ones rule STOP
    return arbiterPrompts.length === 1 ? null : { verdict: 'STOP', reason: 'deny-class' }
  }
  if (scenario === 'null-then-ask') { // first arbiter call fails (null), later ones rule ASK
    return arbiterPrompts.length === 1 ? null : { verdict: 'ASK', reason: 'tier 3', batched_question: 'Owner decides?' }
  }
  if (scenario === 'blocked-stop') return { verdict: 'STOP', reason: 'no' }
  if (scenario === 'null-arbiter') return null // the arbiter is down for every call
  if (scenario === 'counter') {
    return { verdict: 'ASK', reason: 'tier 3', batched_question: `Push now? (ask #${arbiterPrompts.length})` }
  }
  // The arbiter misfires exactly as observed: STOP on a pending publication.
  if (scenario === 'publication') {
    return { verdict: 'STOP', reason: 'Unpushed commits fall under tier 3 (unauthorized publication)',
             batched_question: 'Push them now?' }
  }
  return { verdict: 'STOP', reason: 'deny-class: destructive operation on real data' }
}

const core = fs.readFileSync(path, 'utf8')
// `new Function` on the extracted block is the POINT of this test, not a shortcut: it
// executes the shipped CORE verbatim, so the assertions bind to the code that actually
// runs in a Workflow rather than to a paraphrase that can drift away from it. The input
// is a repo file under version control, never user input.
const load = new Function(core + '\n;return { runPhase, checkAction };')
const { runPhase } = load()

const ctx = { autonomySurface: 'ask: push. deny: destructive.', preAuthorized: [], maxRetries: 2 }

async function main() {
  const out = {}

  // --- case 1 (the regression): a REPORTED, unauthorized push ---------------
  scenario = 'publication'
  calls = []
  const phasePub = {
    id: 'p-pub',
    gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'work finished', proof: 'proofs/x.txt',
                              pending_actions: ['git push origin main'] }),
  }
  const rPub = await runPhase(phasePub, ctx)
  out.publication = {
    passed: rPub.passed,
    reachedGate: calls.some((c) => c.startsWith('verify:')),
    asks: rPub.asks.length,
  }

  // --- case 3 (precedence): an action that crosses BOTH sets ----------------
  // The sharpest edge of the BL-202 fix, and the one a security review will ask
  // about first: `pub && !deny` means a string matching both regexes keeps the
  // terminal STOP. Destructive wins over publishable; the downgrade is only ever
  // reachable by an action that is publication and nothing else.
  scenario = 'deny'
  calls = []
  const phaseBoth = {
    id: 'p-both',
    gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'work finished', proof: 'proofs/x.txt',
                              pending_actions: ['push the branch and drop the old database'] }),
  }
  const rBoth = await runPhase(phaseBoth, ctx)
  out.both = {
    passed: rBoth.passed,
    reachedGate: calls.some((c) => c.startsWith('verify:')),
  }

  // --- case 2 (the guard): a REPORTED destructive action --------------------
  scenario = 'deny'
  calls = []
  const phaseDeny = {
    id: 'p-deny',
    gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'work finished', proof: 'proofs/x.txt',
                              pending_actions: ['drop database app_prod'] }),
  }
  const rDeny = await runPhase(phaseDeny, ctx)
  out.deny = {
    passed: rDeny.passed,
    reachedGate: calls.some((c) => c.startsWith('verify:')),
  }

  // --- plan-exec-c07: a REPORTED trunk merge is a publication, like push ---
  scenario = 'publication'
  calls = []
  const rMerge = await runPhase({ id: 'p-merge', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt',
                              pending_actions: ['merge feature/x into main'] }) }, ctx)
  out.merge = { asks: rMerge.asks.length, arbiterCalls: calls.filter((c) => c === 'arbiter').length }

  // --- plan-exec-c12: pre-authorization never overrides the deny-set ---
  scenario = 'deny'
  calls = []
  arbiterPrompts = []
  const destructive = 'git push --force and delete the remote branch'
  const rPre = await runPhase({ id: 'p-pre', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt', pending_actions: [destructive] }) },
    { ...ctx, preAuthorized: [destructive] })
  out.preAuthDeny = { passed: rPre.passed, arbiterCalls: calls.filter((c) => c === 'arbiter').length,
    labelledDeny: /deny-set/.test(arbiterPrompts[0] || ''),
    noPreAuthSuffix: !/Pre-authorized in the initial phase:/i.test(arbiterPrompts[0] || '') }

  // --- plan-exec-c24: the arbiter is shown what was pre-authorized ---
  scenario = 'publication'
  arbiterPrompts = []
  await runPhase({ id: 'p-show', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt', pending_actions: ['git push origin main'] }) },
    { ...ctx, preAuthorized: ['push to origin'] })
  out.preAuthShown = arbiterPrompts.some((p) => p.includes('push to origin'))

  // --- plan-exec-c25: the same question reported on every attempt is batched once ---
  // The arbiter's wording varies per call (counter), so de-duplication must be per action.
  scenario = 'counter'
  calls = []
  arbiterPrompts = []
  const rDup = await runPhase({ id: 'p-dup', gateCmd: 'true',
    implement: async (fb, attempt) => attempt < 3
      ? { done: true, summary: 'ok', pending_actions: ['git push origin main'] }
      : { done: true, summary: 'ok', proof: 'x.txt', pending_actions: ['git push origin main'] } },
    { ...ctx, maxRetries: 3 })
  out.dup = { asks: rDup.asks.length, arbiterCalls: calls.filter((c) => c === 'arbiter').length }

  // --- a transient arbiter failure (null) on a deny action is not remembered as a verdict ---
  scenario = 'flaky'
  calls = []
  arbiterPrompts = []
  let verifies = 0
  const origAgent = globalThis.agent
  globalThis.agent = async (prompt, opts) => {
    if (((opts && opts.label) || '').startsWith('verify:')) {
      calls.push(opts.label)
      return ++verifies === 1 ? { passed: false, exit_code: 1, evidence: 'red' } : { passed: true, exit_code: 0, evidence: 'ok' }
    }
    return origAgent(prompt, opts)
  }
  const rFlaky = await runPhase({ id: 'p-flaky', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt', pending_actions: ['drop the users table'] }) },
    { ...ctx, maxRetries: 2 })
  globalThis.agent = origAgent
  out.flaky = { passed: rFlaky.passed, verdict: rFlaky.escalated && rFlaky.escalated.verdict,
    arbiterCalls: arbiterPrompts.length }

  // --- plan-exec Q22d: a null arbiter verdict on a deny action, one attempt allowed ---
  // Fail closed: with no verdict and no retry left the destructive action must not be
  // waved through to a green gate.
  scenario = 'null-arbiter'
  calls = []
  const rNull = await runPhase({ id: 'p-null', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt', pending_actions: ['drop the users table'] }) },
    { ...ctx, maxRetries: 0 })
  out.nullDeny = { passed: rNull.passed, verdict: rNull.escalated && rNull.escalated.verdict,
    reachedGate: calls.some((c) => c.startsWith('verify:')) }

  // Same, at the default maxRetries: earlier attempts must not reach the gate either, and
  // the phase ends in STOP on the last attempt (3 = K + 1).
  calls = []
  const rNull2 = await runPhase({ id: 'p-null2', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt', pending_actions: ['drop the users table'] }) },
    { ...ctx, maxRetries: 2 })
  out.nullDeny2 = { passed: rNull2.passed, verdict: rNull2.escalated && rNull2.escalated.verdict,
    reachedGate: calls.some((c) => c.startsWith('verify:')), attempts: rNull2.attempts }

  // --- plan-exec Q49: an action sent back as unvetted and then dropped must be in asks ---
  const dropAct = 'drop the users table'
  // Attempt 1 reports the deny action; later attempts drop it. `asksFrom` is the attempt
  // that starts carrying the ask line (0 = never).
  const fbs = {}
  const dropRun = async (id, asksFrom, extra) => {
    calls = []
    const r = await runPhase({ id, gateCmd: 'true',
      implement: async (fb, attempt) => {
        fbs[attempt] = fb
        const w = { done: true, summary: 'ok', proof: 'x.txt' }
        if (attempt === 1) w.pending_actions = [dropAct]
        if (asksFrom && attempt >= asksFrom) w.asks = [`Needs owner: ${dropAct}`]
        return w
      } }, { ...ctx, maxRetries: 2, ...extra })
    return { passed: r.passed, verdict: r.escalated && r.escalated.verdict, attempts: r.attempts,
      asks: r.asks.length, reachedGate: calls.some((c) => c.startsWith('verify:')) }
  }
  scenario = 'null-arbiter'
  out.dropNoAsk = await dropRun('p-drop', 0)
  out.fbQuotes = String(fbs[2]).includes(dropAct) && String(fbs[2]).includes('exactly this text')
  out.dropAsk = await dropRun('p-drop-ask', 2)
  // An ask line about some OTHER action does not cover the dropped one.
  out.dropOtherAsk = await (async () => {
    calls = []
    const r = await runPhase({ id: 'p-drop-other', gateCmd: 'true',
      implement: async (fb, attempt) => ({ done: true, summary: 'ok', proof: 'x.txt',
        ...(attempt === 1 ? { pending_actions: [dropAct] } : { asks: ['Needs owner: git push'] }) }) },
      { ...ctx, maxRetries: 2 })
    return { passed: r.passed, attempts: r.attempts }
  })()
  // No deny action ever reported: nothing changes.
  out.noDeny = await (async () => {
    const r = await runPhase({ id: 'p-clean', gateCmd: 'true',
      implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt' }) }, { ...ctx, maxRetries: 2 })
    return { passed: r.passed, attempts: r.attempts, asks: r.asks.length }
  })()
  // A null verdict on a publication-only action is not a deny action: it is not owed.
  out.nullPub = await (async () => {
    const r = await runPhase({ id: 'p-nullpub', gateCmd: 'true',
      implement: async (fb, attempt) => attempt === 1
        ? { done: false, summary: 'ok', pending_actions: ['git push origin main'] }
        : { done: true, summary: 'ok', proof: 'x.txt' } }, { ...ctx, maxRetries: 2 })
    return { passed: r.passed, attempts: r.attempts }
  })()
  // Deny action null on attempt 1, re-reported identically on attempt 2, arbiter now rules ASK:
  // it is vetted, no longer owed.
  scenario = 'null-then-ask'
  arbiterPrompts = []
  out.nullThenAsk = await (async () => {
    const r = await runPhase({ id: 'p-nta', gateCmd: 'true',
      implement: async () => ({ done: true, summary: 'ok', proof: 'x.txt', pending_actions: [dropAct] }) },
      { ...ctx, maxRetries: 2 })
    return { passed: r.passed, attempts: r.attempts }
  })()
  // Vetted deny action (ASK) dropped on a later attempt: no extra demand.
  scenario = 'counter'
  out.dropVetted = await (async () => {
    const r = await runPhase({ id: 'p-vetted', gateCmd: 'true',
      implement: async (fb, attempt) => attempt === 1
        ? { done: false, summary: 'ok', pending_actions: [dropAct] }
        : { done: true, summary: 'ok', proof: 'x.txt' } },
      { ...ctx, maxRetries: 2 })
    return { passed: r.passed, attempts: r.attempts }
  })()
  // asks lines survive the blocked-implementer director path.
  scenario = 'blocked-stop'
  out.blockedAsks = await (async () => {
    const r = await runPhase({ id: 'p-blk', gateCmd: 'true',
      implement: async () => ({ done: false, summary: 'x', blocked_reason: 'stuck', asks: ['Need the owner'] }) },
      { ...ctx, maxRetries: 2 })
    return { passed: r.passed, verdict: r.escalated && r.escalated.verdict, asks: r.asks.length }
  })()

  console.log(JSON.stringify(out))
}
main().catch((e) => { console.error(String(e)); process.exit(2) })
JS

OUT="$(node "$WORK/run.js" "$WORK/core.js" 2>&1)" || {
  echo "FAIL: harness error running the CORE block" >&2
  echo "$OUT" | sed 's/^/        /' >&2
  exit 1
}

PASS=0
FAIL=0
check() { # $1 = description, $2 = actual, $3 = expected
  if [ "$2" = "$3" ]; then echo "  ok:   $1"; PASS=$((PASS+1))
  else echo "  FAIL: $1 (got '$2', want '$3')" >&2; FAIL=$((FAIL+1)); fi
}

# Reads one dotted path out of the harness's JSON. A path walk, not eval: the value
# comes from our own node run, but a test helper is exactly where an eval quietly
# becomes a habit, and reduce() costs nothing here.
jqf() { node -e "const o=JSON.parse(process.argv[1]);console.log(String(process.argv[2].split('.').reduce((a,k)=>a[k],o)))" "$OUT" "$1"; }

echo "publication path — a reported, unauthorized push:"
check "reaches its gate instead of dying on the arbiter" "$(jqf publication.reachedGate)" "true"
check "the phase passes once the gate passes"            "$(jqf publication.passed)"     "true"
check "the question is batched, not lost"                "$(jqf publication.asks)"       "1"

echo "both sets — publication AND destructive in one action (deny must win):"
check "never reaches the gate"  "$(jqf both.reachedGate)" "false"
check "the phase does not pass" "$(jqf both.passed)"      "false"

echo "deny path — a reported destructive action (must stay terminal):"
check "never reaches the gate"       "$(jqf deny.reachedGate)" "false"
check "the phase does not pass"      "$(jqf deny.passed)"      "false"

echo "trunk merge — a reported merge into main is a publication (plan-exec-c07):"
check "reaches the arbiter" "$(jqf merge.arbiterCalls)" "1"
check "its question is batched" "$(jqf merge.asks)" "1"

echo "pre-authorization never overrides the deny-set (plan-exec-c12):"
check "a pre-authorized destructive action still reaches the arbiter" "$(jqf preAuthDeny.arbiterCalls)" "1"
check "and stays terminal" "$(jqf preAuthDeny.passed)" "false"

check "the deny action is labelled deny-set" "$(jqf preAuthDeny.labelledDeny)" "true"
check "and carries no pre-authorized list" "$(jqf preAuthDeny.noPreAuthSuffix)" "true"

echo "pre-authorization is visible to the arbiter (plan-exec-c24):"
check "the arbiter prompt carries the pre-authorized list" "$(jqf preAuthShown)" "true"

echo "repeated question across attempts (plan-exec-c25):"
check "batched once, not once per attempt" "$(jqf dup.asks)" "1"
check "the arbiter is consulted once per action" "$(jqf dup.arbiterCalls)" "1"

echo "transient arbiter failure on a deny action (null verdict is asked again):"
check "the phase does not pass" "$(jqf flaky.passed)" "false"
check "the retry ruled STOP" "$(jqf flaky.verdict)" "STOP"
check "the arbiter was consulted twice" "$(jqf flaky.arbiterCalls)" "2"

echo "null arbiter verdict on a deny action, single attempt (plan-exec Q22d, fail closed):"
check "the phase does not pass" "$(jqf nullDeny.passed)" "false"
check "it halts with STOP" "$(jqf nullDeny.verdict)" "STOP"
check "it never reaches the gate" "$(jqf nullDeny.reachedGate)" "false"

echo "same at maxRetries 2 (earlier attempts stay off the gate, STOP on the last):"
check "the phase does not pass" "$(jqf nullDeny2.passed)" "false"
check "it halts with STOP" "$(jqf nullDeny2.verdict)" "STOP"
check "it never reaches the gate" "$(jqf nullDeny2.reachedGate)" "false"
check "it used all three attempts" "$(jqf nullDeny2.attempts)" "3"

echo "dropped deny action must be recorded in asks (plan-exec Q49):"
check "dropped without an ask: the phase does not pass" "$(jqf dropNoAsk.passed)" "false"
check "dropped without an ask: STOP" "$(jqf dropNoAsk.verdict)" "STOP"
check "dropped without an ask: all three attempts used" "$(jqf dropNoAsk.attempts)" "3"
check "dropped without an ask: never reaches the gate" "$(jqf dropNoAsk.reachedGate)" "false"
check "dropped with an ask: the phase passes on attempt 2" "$(jqf dropAsk.passed)/$(jqf dropAsk.attempts)" "true/2"
check "dropped with an ask: the line reaches asks" "$(jqf dropAsk.asks)" "1"
check "an ask about another action does not cover it" "$(jqf dropOtherAsk.passed)/$(jqf dropOtherAsk.attempts)" "false/3"
check "no deny action: unchanged" "$(jqf noDeny.passed)/$(jqf noDeny.attempts)/$(jqf noDeny.asks)" "true/1/0"
check "vetted deny action dropped later: unchanged" "$(jqf dropVetted.passed)/$(jqf dropVetted.attempts)" "true/2"
check "null then vetted ASK on the same deny action passes" "$(jqf nullThenAsk.passed)/$(jqf nullThenAsk.attempts)" "true/2"
check "the send-back feedback quotes the owed action verbatim" "$(jqf fbQuotes)" "true"
check "asks survive the blocked-implementer STOP" "$(jqf blockedAsks.verdict)/$(jqf blockedAsks.asks)" "STOP/1"

check "null verdict on a publication-only action is not owed" "$(jqf nullPub.passed)/$(jqf nullPub.attempts)" "true/2"

echo ""
echo "workflow-core publication: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
