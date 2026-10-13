#!/usr/bin/env bash
# test-audit-fanout-workflow.sh — audit-fanout.workflow.js behaviour outside the CORE block
# (the CORE is locked by skills/conventions/scripts/test_workflow_core_drift.sh):
#   audit-c18  the finding schema accepts P0 (the canon severity ladder starts there)
#   audit-c19  a null critic or a null escalate ruling does not crash the run after the analysts worked
#   audit-c20  a dimension whose analyst failed is reported, and the critic is not told it was covered
#
# Layer: unit. The decision lives in plain JS; the workflow runtime (agent, parallel, phase,
# log, args) is stubbed, so nothing here launches an agent.
# Run with: bash skills/audit/tests/test-audit-fanout-workflow.sh
set -uo pipefail

command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 2; }

WF="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/workflows" && pwd -P)/audit-fanout.workflow.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The workflow is a top-level script (await, return, export): wrap it in an async function.
{
  cat <<'JS'
const log = (m) => logs.push(m), phase = () => {}
const parallel = (fns) => Promise.all(fns.map((f) => f().catch(() => null)))  // the runtime: a failed agent is null
const logs = []
const calls = []
let script = {}
async function agent(prompt, opts) {
  calls.push({ prompt, opts })
  const r = script[opts.label]
  return typeof r === 'function' ? r(prompt, opts) : r
}
async function run(args, s) {
  script = s; calls.length = 0; logs.length = 0
JS
  sed -e 's/^export const meta/const meta/' "$WF" | sed -e 's/^const args = .*//'
  cat <<'JS'
}
const bad = []
const expect = (ok, msg) => { if (!ok) bad.push(msg) }
const dims = [{ id: 'sec', prompt: 'p' }, { id: 'ux', prompt: 'p' }]
const cfg = (extra) => JSON.stringify({ dimensions: dims, ...extra })
const finding = (d) => ({ findings: [{ id: d + '-1', title: 't ' + d, severity: 'P0', evidence: 'e', dimension: d }] })
;(async () => {
  // c18
  await run(cfg({}), { 'analyze:sec': finding('sec'), 'analyze:ux': finding('ux'), completeness: { missing: [] } })
  const sev = calls.find((c) => c.opts.label === 'analyze:sec').opts.schema.properties.findings.items.properties.severity.enum
  expect(sev.includes('P0'), 'c18: schema severity enum lacks P0: ' + JSON.stringify(sev))

  // c19: critic returns null
  let r
  try { r = await run(cfg({}), { 'analyze:sec': finding('sec'), 'analyze:ux': finding('ux'), completeness: null }) }
  catch (e) { expect(false, 'c19: null critic crashed the run: ' + e.message) }
  expect(r && r.findings && r.findings.length === 2, 'c19: findings not returned after a null critic')
  expect(logs.some((m) => /completeness: critic returned nothing/.test(m)), 'c19: a null critic was logged like a clean one: ' + logs.join(' | '))
  // c19: arbiter returns null at a publication boundary
  r = undefined
  try { r = await run(cfg({ escalateAction: 'publish findings' }), { 'analyze:sec': finding('sec'), 'analyze:ux': finding('ux'),
    completeness: { missing: [] }, arbiter: null }) }
  catch (e) { expect(false, 'c19: null escalate ruling crashed the run: ' + e.message) }
  expect(r && r.findings && r.findings.length === 2, 'c19: findings not returned after a null escalate ruling')

  // c20: the sec analyst fails
  r = await run(cfg({}), { 'analyze:sec': null, 'analyze:ux': finding('ux'), completeness: { missing: [] } })
  const critic = calls.find((c) => c.opts.label === 'completeness').prompt
  const covered = (critic.match(/Covered dimensions: ([^.]*)\./) || [])[1] || ''
  expect(!/\bsec\b/.test(covered), 'c20: the critic was told the failed dimension was covered: ' + covered)
  expect(r.failedDimensions && r.failedDimensions.join() === 'sec', 'c20: result does not name the failed dimension: ' + JSON.stringify(r.failedDimensions))
  await run(cfg({}), { 'analyze:sec': finding('sec'), 'analyze:ux': finding('ux'), completeness: { missing: [] } })
  expect(/Covered dimensions: sec, ux\./.test(calls.find((c) => c.opts.label === 'completeness').prompt), 'c20: healthy run lost its covered list')

  if (bad.length) { bad.forEach((m) => console.log('FAIL: ' + m)); console.log(bad.length + ' failure(s)'); process.exit(1) }
  console.log('OK — P0 accepted, null critic/escalate survive, a failed analyst is reported and not called covered')
})().catch((e) => { console.log('FAIL: harness: ' + e.stack); process.exit(1) })
JS
} > "$TMP/harness.js"

node "$TMP/harness.js"
