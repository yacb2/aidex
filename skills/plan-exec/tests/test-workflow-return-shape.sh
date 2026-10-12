#!/usr/bin/env bash
# What the workflow forms RETURN when a phase does not simply pass: the orchestrator reads
# only that return value (results / blocked / batchedAsks / escalation), so a phase or a
# question missing from it is lost.
#   plan-exec-c05  fan-out: phases no wave can ever run (typo'd or cyclic depends_on) are in `blocked`
#   plan-exec-c19  fan-out: a phase whose runner crashed (parallel() gives null) has a result row, and
#                  is not listed in `blocked` as if a dependency had skipped it
#   plan-exec-c16  fan-out and pipeline: an arbiter ASK after retry exhaustion reaches `batchedAsks`
#   plan-exec-c09  review: a null verdict is escalated, not a TypeError; a `passed:true` verdict that
#                  carries a blocking finding fails the gate
# Each scenario runs the whole script with stubbed workflow globals (same harness idea as
# test-out-of-scope-bugs-survive.sh). Layer: unit over the script's return value.
#
# Run with: bash skills/plan-exec/tests/test-workflow-return-shape.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
WF="$ROOT/skills/plan-exec/assets/workflows"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/probe.mjs" <<'PROBE'
import fs from 'fs'
const [file, scenario] = process.argv.slice(2)
const src = fs.readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const gateFails = scenario === 'ask-after-exhaustion'
const agent = async (prompt, opts) => {
  const label = opts.label
  if (label.startsWith('verify:')) return { passed: !gateFails, exit_code: gateFails ? 1 : 0, evidence: 'e' }
  if (label === 'arbiter' && scenario === 'arbiter-down') return null
  if (label === 'arbiter') return { verdict: 'ASK', reason: 'blocker', batched_question: 'Provide the API key?' }
  if (label === 'review') {
    if (scenario === 'review-null') return null
    return { passed: true, summary: 's', findings: [{ severity: 'blocking', detail: 'breaks X' }] }
  }
  if (scenario === 'arbiter-down' || scenario === 'blocked-ask') return { done: false, summary: 's', blocked_reason: 'stuck' }
  if (scenario === 'crash' && label === 'exec:x') throw new Error('budget exhausted')
  return { done: true, summary: 'ok', proof: 'p.txt' }
}
// The runtime contract: a thunk that throws resolves to null.
const parallel = (fns) => Promise.all(fns.map((f) => f().catch(() => null)))
const phases = {
  unrunnable: [{ id: 'p2', spec: 's', gateCmd: 'true' }, { id: 'p3', spec: 's', gateCmd: 'true', depends_on: ['p1'] }],
  crash: [{ id: 'x', spec: 's', gateCmd: 'true' }, { id: 'y', spec: 's', gateCmd: 'true', depends_on: ['x'] },
          { id: 'z', spec: 's', gateCmd: 'true' }],
  'ask-after-exhaustion': [{ id: 'a', spec: 's', gateCmd: 'false' }],
  'blocked-ask': [{ id: 'a', spec: 's', gateCmd: 'true' }],
  'arbiter-down': [{ id: 'a', spec: 's', gateCmd: 'true' }],
}[scenario] || []
const cfg = { planPath: 'p', phases, maxRetries: 0, diffCmd: 'git diff', successCriteria: 'c' }
const run = new Function('args', 'agent', 'parallel', 'phase', 'log', `return (async () => {\n${src}\n})()`)
try { console.log(JSON.stringify(await run(JSON.stringify(cfg), agent, parallel, () => {}, () => {}))) }
catch (e) { console.log(JSON.stringify({ threw: String(e) })) }
PROBE

fail=0
# usage: check <description> <workflow> <scenario> <js expression over `o`, true when correct>
check() {
  local out
  out="$(node "$TMP/probe.mjs" "$WF/$2" "$3" 2>&1)" || { printf 'FAIL: %s: probe errored: %s\n' "$1" "$out"; fail=1; return; }
  node -e "const o=JSON.parse(process.argv[1]); process.exit(($4)?0:1)" "$out" \
    || { printf 'FAIL: %s\n        got: %s\n' "$1" "$out"; fail=1; }
}

FAN=fan-out-with-gate.workflow.js
check "c05 a phase waiting on an unknown dependency is reported blocked" $FAN unrunnable \
  "o.blocked.includes('p3') && o.results.some(r => r.phaseId==='p2' && r.passed)"
check "c19 a crashed phase has a result row naming it" $FAN crash \
  "o.results.some(r => r && r.phaseId==='x' && r.passed===false && r.error)"
check "c19 a crashed phase is not listed as dependency-blocked, its descendant is" $FAN crash \
  "!o.blocked.includes('x') && o.blocked.includes('y')"
check "c16 fan-out: arbiter ASK after exhaustion is batched" $FAN ask-after-exhaustion \
  "o.batchedAsks.includes('Provide the API key?')"
check "c16 pipeline: arbiter ASK after exhaustion is batched" pipeline-with-gate.workflow.js ask-after-exhaustion \
  "o.batchedAsks.includes('Provide the API key?')"
check "c16 fan-out: an unavailable-arbiter fallback is not batched as a question" $FAN arbiter-down \
  "o.batchedAsks.length === 0 && o.results[0].escalated.verdict === 'ASK'"
check "c16 pipeline: an unavailable-arbiter fallback is not batched as a question" pipeline-with-gate.workflow.js arbiter-down \
  "o.batchedAsks.length === 0 && o.results[0].escalated.verdict === 'ASK'"
check "c16 fan-out: a live arbiter ASK on a blocked implementer is batched" $FAN blocked-ask \
  "o.batchedAsks.includes('Provide the API key?')"
check "c16 pipeline: a live arbiter ASK on a blocked implementer is batched" pipeline-with-gate.workflow.js blocked-ask \
  "o.batchedAsks.includes('Provide the API key?')"
check "c09 review: a null verdict is escalated, not a TypeError" review-with-gate.workflow.js review-null \
  "!o.threw && o.escalation && o.escalation.verdict"
check "c09 review: passed:true with a blocking finding fails the gate" review-with-gate.workflow.js review-lying \
  "o.escalation && o.review.passed === false"

[ "$fail" -eq 0 ] && echo "PASS: unrunnable, crashed, exhausted-ASK and review-verdict outcomes all reach the return value" || exit 1
