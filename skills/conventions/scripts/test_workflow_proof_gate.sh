#!/usr/bin/env bash
# test_workflow_proof_gate.sh — BL-208: the CORE gate must fail a phase whose
# implementer report carries no proof artifact, even when the machine gate
# passes. Rationale: 10 user-caught defects in the 2026-08-16..23 window
# arrived AFTER the first commit and proof_links adoption is 7.6% despite
# mandates — the rule layer is not where this fails, the mechanical gate is.
#
# The test extracts the canonical CORE block from workflow-core.md, wraps it
# with stub agents (verifier always green, arbiter always ASK), and runs
# runPhase twice: a proof-less report must not pass; a proofed one must.
#
# Run:  bash skills/conventions/scripts/test_workflow_proof_gate.sh
set -uo pipefail

command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="$REPO_ROOT/skills/conventions/references/workflow-core.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

awk '
  $0 == "// === CORE:START ===" { grab=1; next }
  $0 == "// === CORE:END ==="   { if (grab) exit }
  grab { print }
' "$CANON" > "$TMP/core.js"
[ -s "$TMP/core.js" ] || { echo "FAIL: could not extract CORE block"; exit 1; }

cat > "$TMP/harness.js" <<'JS'
// stubs the Workflow runtime provides
const args = undefined
const ARBITER_PROMPT = 'stub'
function log() {}
function phase() {}
const arbiterPrompts = []
let directorCalls = 0
async function agent(prompt, opts) {
  const label = (opts && opts.label) || ''
  if (!label.startsWith('verify:')) arbiterPrompts.push(prompt)
  if (label.startsWith('verify:')) return { passed: true, exit_code: 0, evidence: 'green' }
  // Director consultations (the first two) say CONTINUE so the phase reaches the gate path.
  if (arbiterPrompts.length <= directorCalls) return { verdict: 'CONTINUE', action: 'go on' }
  return { verdict: 'ASK', reason: 'stub arbiter' }
}
JS
cat "$TMP/core.js" >> "$TMP/harness.js"
cat >> "$TMP/harness.js" <<'JS'
;(async () => {
  const ctx = { autonomySurface: 'test', maxRetries: 0 }
  const bad = []
  const expect = (ok, msg) => { if (!ok) bad.push(msg) }
  const noProof = await runPhase({ id: 'p1', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'did it' }) }, ctx)
  expect(!noProof.passed, 'proof-less report passed the gate')
  const proofed = await runPhase({ id: 'p2', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'did it',
      proof: '.context/proofs/p2/pytest-output.txt' }) }, ctx)
  expect(proofed.passed, 'proofed report should pass')
  expect(proofed.proof && proofed.proof.passed === true, 'verifier proof missing from result')
  // plan-exec-c15: a green gate and a proof string do not pass a report that says done=false.
  const notDone = await runPhase({ id: 'p3', gateCmd: 'true',
    implement: async () => ({ done: false, summary: 'half way', proof: 'p.txt' }) }, ctx)
  expect(!notDone.passed, 'done=false report passed the gate')
  // The exhaustion ruling is told the truth about the last attempt.
  const ruling = async (impl) => {
    arbiterPrompts.length = 0
    await runPhase({ id: 'p4', gateCmd: 'true', implement: impl }, { autonomySurface: 'test', maxRetries: 1 })
    return arbiterPrompts.join('\n')
  }
  // plan-exec-c08: every gate green -> not "failed its machine gate"
  const r8 = await ruling(async () => ({ done: true, summary: 'did it' }))
  expect(!/failed its machine gate/.test(r8) && /proof artifact/.test(r8), 'c08 wrong exhaustion reason: ' + r8)
  // c15 path: after the director has redirected twice, the blocked_reason must reach the
  // EXHAUSTION ruling (not just the director prompt).
  directorCalls = 2
  arbiterPrompts.length = 0
  await runPhase({ id: 'p5', gateCmd: 'true',
    implement: async () => ({ done: false, summary: 's', blocked_reason: 'needs the API key', proof: 'p' }) },
    { autonomySurface: 'test', maxRetries: 1 })
  directorCalls = 0
  const r15 = arbiterPrompts.find((p) => /did not pass in/.test(p)) || ''
  expect(/needs the API key/.test(r15), 'blocked_reason missing from exhaustion ruling: ' + r15)
  // a null report is named as such, not as done=false
  const rNull = await ruling(async () => null)
  expect(!/done=false/.test(rNull) && /no report/.test(rNull), 'null report misdescribed: ' + rNull)
  if (bad.length) { console.log('FAIL: ' + bad.join('\n      FAIL: ')); process.exit(1) }
  console.log('OK — proof-less phase blocked, proofed phase passes, done=false blocked, exhaustion reason is truthful')
})().catch(e => { console.log('FAIL: harness error: ' + e.message); process.exit(1) })
JS

out="$(node "$TMP/harness.js")" || { echo "$out"; exit 1; }
case "$out" in
  OK*) echo "$out"; exit 0 ;;
  *)   echo "$out"; exit 1 ;;
esac
