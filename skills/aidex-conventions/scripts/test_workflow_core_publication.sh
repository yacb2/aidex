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
# Run:  bash skills/aidex-conventions/scripts/test_workflow_core_publication.sh
# Exit: 0 if both cases behave; 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="$REPO_ROOT/skills/aidex-conventions/references/workflow-core.md"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }
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
globalThis.agent = async (prompt, opts) => {
  const label = (opts && opts.label) || 'arbiter'
  calls.push(label)
  if (label.startsWith('verify:')) return { passed: true, exit_code: 0, evidence: 'gate ran' }
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
    implement: async () => ({ done: true, summary: 'work finished',
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
    implement: async () => ({ done: true, summary: 'work finished',
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
    implement: async () => ({ done: true, summary: 'work finished',
                              pending_actions: ['drop database ns_backoffice'] }),
  }
  const rDeny = await runPhase(phaseDeny, ctx)
  out.deny = {
    passed: rDeny.passed,
    reachedGate: calls.some((c) => c.startsWith('verify:')),
  }

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

echo ""
echo "workflow-core publication: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
