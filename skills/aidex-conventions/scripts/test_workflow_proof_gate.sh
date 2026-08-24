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
# Run:  bash skills/aidex-conventions/scripts/test_workflow_proof_gate.sh
set -uo pipefail

command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="$REPO_ROOT/skills/aidex-conventions/references/workflow-core.md"
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
async function agent(prompt, opts) {
  const label = (opts && opts.label) || ''
  if (label.startsWith('verify:')) return { passed: true, exit_code: 0, evidence: 'green' }
  return { verdict: 'ASK', reason: 'stub arbiter' }
}
JS
cat "$TMP/core.js" >> "$TMP/harness.js"
cat >> "$TMP/harness.js" <<'JS'
;(async () => {
  const ctx = { autonomySurface: 'test', maxRetries: 0 }
  const noProof = await runPhase({ id: 'p1', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'did it' }) }, ctx)
  if (noProof.passed) { console.log('FAIL: proof-less report passed the gate'); process.exit(1) }
  const proofed = await runPhase({ id: 'p2', gateCmd: 'true',
    implement: async () => ({ done: true, summary: 'did it',
      proof: '.context/proofs/p2/pytest-output.txt' }) }, ctx)
  if (!proofed.passed) { console.log('FAIL: proofed report should pass'); process.exit(1) }
  if (!proofed.proof || proofed.proof.passed !== true) { console.log('FAIL: verifier proof missing from result'); process.exit(1) }
  console.log('OK — proof-less phase blocked, proofed phase passes')
})().catch(e => { console.log('FAIL: harness error: ' + e.message); process.exit(1) })
JS

out="$(node "$TMP/harness.js")" || { echo "$out"; exit 1; }
case "$out" in
  OK*) echo "$out"; exit 0 ;;
  *)   echo "$out"; exit 1 ;;
esac
