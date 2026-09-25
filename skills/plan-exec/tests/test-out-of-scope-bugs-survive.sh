#!/usr/bin/env bash
# A bug a batch phase agent reports but did not fix reaches the workflow's return value,
# whatever way the phase ends.
#
# The implementing forms tell each phase agent to leave a bug outside its phase unpatched
# and report it as an `OUT-OF-SCOPE BUG: ...` line in its summary; plan-exec routes those
# lines to a bugfix run after the batch returns. A line the result does not carry is a
# bug nobody routes: the agent obeyed, the finding is gone. The ways it can be dropped
# are every return path of CORE's runPhase — a pass whose reporting attempt was not the
# last one, a gate failure after retries, a blocked implementer the arbiter stops, a
# reported destructive action the arbiter stops.
#
# Each scenario runs the whole workflow script with stubbed workflow globals and checks
# the JSON it returns. The review form is not run: it has no implementer to report one.
#
# Run with: bash skills/plan-exec/tests/test-out-of-scope-bugs-survive.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
WF="$ROOT/skills/plan-exec/assets/workflows"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/probe.mjs" <<'PROBE'
// Runs a .workflow.js under one scenario and prints the JSON of what it returns.
import fs from 'fs'
const [file, scenario] = process.argv.slice(2)
const BUG = 'OUT-OF-SCOPE BUG: x'
const src = fs.readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
let execCalls = 0
// Only the FIRST implementer attempt reports the bug; later attempts do not repeat it.
const report = (extra) => ({ summary: execCalls === 1 ? `did the work\n${BUG}` : 'retried', ...extra })
const agent = async (prompt, opts) => {
  if (/^verify:/.test(opts.label)) return { passed: scenario !== 'fail', exit_code: scenario === 'fail' ? 1 : 0, evidence: 'e' }
  if (opts.label === 'arbiter') return { verdict: 'STOP', reason: 'stub stop' }
  execCalls++
  switch (scenario) {
    // attempt 1 is green but carries no proof, so the phase passes on attempt 2
    case 'pass':    return report(execCalls === 1 ? { done: true } : { done: true, proof: 'p.txt' })
    case 'fail':    return report({ done: true, proof: 'p.txt' })
    case 'blocked': return report({ done: false, blocked_reason: 'cannot continue' })
    case 'deny':    return report({ done: true, proof: 'p.txt', pending_actions: ['drop table users'] })
  }
}
const parallel = (fns) => Promise.all(fns.map((f) => f()))
const run = new Function('args', 'agent', 'parallel', 'phase', 'log', `return (async () => {\n${src}\n})()`)
const out = await run('{"planPath":"p","phases":[{"id":"a","spec":"s","gateCmd":"true"}]}',
  agent, parallel, () => {}, () => {})
console.log(JSON.stringify(out))
PROBE

fail=0
for wf in "$WF"/pipeline-with-gate.workflow.js "$WF"/fan-out-with-gate.workflow.js; do
  name="${wf##*/}"
  for scenario in pass fail blocked deny; do
    out="$(node "$TMP/probe.mjs" "$wf" "$scenario" 2>&1)" \
      || { printf 'FAIL: %s [%s] probe errored: %s\n' "$name" "$scenario" "$out"; fail=1; continue; }
    grep -qF 'OUT-OF-SCOPE BUG: x' <<<"$out" \
      || { printf 'FAIL: %s [%s] returns without the reported out-of-scope bug: %s\n' "$name" "$scenario" "$out"; fail=1; }
  done
done

[ "$fail" -eq 0 ] && echo "PASS: both implementing forms return a reported out-of-scope bug on pass, gate failure, blocked-STOP and deny-STOP" || exit 1
