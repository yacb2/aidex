#!/usr/bin/env bash
# BL-873: a plan Workflow phase with agentType 'aidex:gallery-builder' AND firstBuild === true
# also launches aidex:gallery-builder-shadow (once per phase, with a sketchBranch); a re-capture, another/miscased
# agentType, or firstBuild as a non-boolean does not. The shadow never reaches pass/fail: a
# shadow that throws or returns junk leaves the phase passing, and its brief never carries gateCmd.
# Each scenario runs a whole template with stubbed workflow globals (same harness idea as
# test-workflow-return-shape.sh). Layer: unit over the script's agent calls and return value.
#
# Run with: bash skills/plan-exec/tests/test-workflow-shadow-arm.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
WF="$ROOT/skills/plan-exec/assets/workflows"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/probe.mjs" <<'PROBE'
import fs from 'fs'
const [file, phasesJson, shadowMode] = process.argv.slice(2)
const src = fs.readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const calls = []
let verifies = 0
let execs = 0
// Deliberately NOT async: a synchronous throw from agent() must be survivable.
const agent = (prompt, opts) => {
  calls.push({ label: opts.label, agentType: opts.agentType, model: opts.model, effort: opts.effort, prompt })
  if (opts.label.startsWith('shadow:') && shadowMode === 'syncthrow') throw new Error('agent type not found')
  return (async () => {
    if (opts.label === 'arbiter') return { verdict: 'CONTINUE', reason: 'r', action: 'go' }
    if (opts.label.startsWith('shadow:')) {
      if (shadowMode === 'slow') await new Promise((r) => setTimeout(r, 50))
      if (shadowMode === 'throw') throw new Error('shadow crashed')
      return { junk: true }
    }
    if (opts.label.startsWith('verify:')) return { passed: shadowMode === 'retry' ? ++verifies > 1 : true, exit_code: 0, evidence: 'e' }
    if (opts.label.startsWith('exec:') && shadowMode === 'blocked' && ++execs === 1) return { done: false, summary: 'x', blocked_reason: 'stuck' }
    if (opts.label.startsWith('exec:') && (shadowMode === 'livereject' || shadowMode === 'slow')) throw new Error('live crashed')
    return { done: true, summary: 'ok', proof: 'p.txt' }
  })()
}
const parallel = (fns) => Promise.all(fns.map((f) => f().catch(() => null)))
const cfg = { planPath: process.env.PLAN_PATH || 'p', phases: JSON.parse(phasesJson), maxRetries: shadowMode === 'retry' ? 1 : 0, successCriteria: 'c' }
const run = new Function('args', 'agent', 'parallel', 'phase', 'log', `return (async () => {\n${src}\n})()`)
try {
  const ret = await run(JSON.stringify(cfg), agent, parallel, () => {}, () => {})
  console.log(JSON.stringify({ ret, calls }))
} catch (e) { console.log(JSON.stringify({ threw: String(e), calls })) }
PROBE

fail=0
# usage: check <description> <workflow> <phases json> <shadow mode> <js over `o`>
check() {
  local out
  out="$(node "$TMP/probe.mjs" "$WF/$2" "$3" "$4" 2>&1)" || { printf 'FAIL: %s: probe errored: %s\n' "$1" "$out"; fail=1; return; }
  node -e "const o=JSON.parse(process.argv[1]); process.exit(($5)?0:1)" "$out" \
    || { printf 'FAIL: %s\n        got: %s\n' "$1" "$out"; fail=1; }
}

P() { printf '[{"id":"a","spec":"%s","gateCmd":"%s",%s}]' "$1" "$2" "$3"; }
FB='"agentType":"aidex:gallery-builder","firstBuild":true,"sketchBranch":"sketch/x"'
for T in pipeline-with-gate.workflow.js fan-out-with-gate.workflow.js; do
  n="${T%%-with*}"
  S='o.calls.filter(c => c.label.startsWith("shadow:"))'
  check "$n: first-build launches the shadow once, sonnet/medium, named worktree/branch/base, no gateCmd" $T \
    "$(P LIVE-BRIEF SECRET-GATE "$FB")" ok \
    "$S.length === 1 && $S[0].agentType === 'aidex:gallery-builder-shadow' && $S[0].model === 'sonnet' && $S[0].effort === 'medium' && $S[0].prompt.includes('LIVE-BRIEF') && !$S[0].prompt.includes('SECRET-GATE') && $S[0].prompt.includes('.gbshadow/') && $S[0].prompt.includes('worktree.sh new gbshadow-p-a --branch gbshadow/p-a --base sketch/x')"
  check "$n: shadows[] is filled after the shadow settles, with result and live attempts" $T \
    "$(P s true "$FB")" ok \
    "o.ret.shadows.length === 1 && o.ret.shadows[0].phase === 'a' && o.ret.shadows[0].worktree === 'gbshadow-p-a' && o.ret.shadows[0].branch === 'gbshadow/p-a' && o.ret.shadows[0].settled === true && o.ret.shadows[0].base === 'sketch/x' && o.ret.shadows[0].result === '{\"junk\":true}' && o.ret.shadows[0].error === null && o.ret.shadows[0].liveAttempts === 1"
  check "$n: the live builder starts before the shadow, at opus/high" $T \
    "$(P s true "$FB")" ok \
    "o.calls.findIndex(c => c.label === 'exec:a') >= 0 && o.calls.findIndex(c => c.label === 'exec:a') < o.calls.findIndex(c => c.label === 'shadow:a') && o.calls.find(c => c.label === 'exec:a').model === 'opus' && o.calls.find(c => c.label === 'exec:a').effort === 'high'"
  check "$n: a plan tier cell does not override opus/high on a first build" $T \
    "$(P s true "$FB,\"model\":\"haiku\",\"effort\":\"low\"")" ok \
    "o.calls.find(c => c.label === 'exec:a').model === 'opus' && o.calls.find(c => c.label === 'exec:a').effort === 'high'"
  check "$n: a re-capture keeps the plan's own model and effort" $T \
    "$(P s true '"agentType":"aidex:gallery-builder","model":"haiku","effort":"low"')" ok \
    "o.calls.find(c => c.label === 'exec:a').model === 'haiku' && o.calls.find(c => c.label === 'exec:a').effort === 'low'"
  check "$n: the live prompt is identical with and without firstBuild" $T \
    "[{\"id\":\"a\",\"spec\":\"s\",\"gateCmd\":\"true\",\"agentType\":\"aidex:gallery-builder\",\"firstBuild\":true,\"sketchBranch\":\"b\"},{\"id\":\"b\",\"spec\":\"s\",\"gateCmd\":\"true\",\"agentType\":\"aidex:gallery-builder\"}]" ok \
    "o.calls.find(c => c.label === 'exec:a').prompt.replace(/Phase a/, 'Phase X') === o.calls.find(c => c.label === 'exec:b').prompt.replace(/Phase b/, 'Phase X')"
  check "$n: firstBuild without sketchBranch launches no shadow and records why" $T \
    "$(P s true '"agentType":"aidex:gallery-builder","firstBuild":true')" ok \
    "$S.length === 0 && o.ret.shadows.length === 1 && o.ret.shadows[0].phase === 'a' && o.ret.shadows[0].error === 'no sketchBranch' && o.ret.results[0].passed === true"
  for variant in '"agentType":"aidex:gallery-builder","firstBuild":false' \
                 '"agentType":"aidex:gallery-builder","firstBuild":"true"' \
                 '"agentType":"aidex:gallery-builder","firstBuild":"false"' \
                 '"agentType":"aidex:Gallery-Builder","firstBuild":true' \
                 '"agentType":"gallery-builder","firstBuild":true' \
                 '"agentType":"aidex:other","firstBuild":true' \
                 '"firstBuild":true' \
                 '"agentType":"aidex:gallery-builder"'; do
    check "$n: no shadow for {$variant}" $T "$(P s true "$variant,\"sketchBranch\":\"b\"")" ok \
      "$S.length === 0 && o.ret.shadows.length === 0"
  done
  check "$n: a retried phase launches the shadow once and reports the live attempts" $T \
    "$(P s true "$FB")" retry \
    "o.calls.filter(c => c.label === 'exec:a').length === 2 && $S.length === 1 && o.ret.shadows[0].liveAttempts === 2"
  check "$n: a shadow that throws asynchronously leaves the phase passing and is recorded" $T \
    "$(P s true "$FB")" throw \
    "!o.threw && o.ret.results[0].passed === true && o.ret.shadows[0].error.includes('shadow crashed') && o.ret.shadows[0].result === null"
  check "$n: a shadow whose agent() throws synchronously does not stop the live unit" $T \
    "$(P s true "$FB")" syncthrow \
    "!o.threw && o.calls.some(c => c.label === 'exec:a') && o.ret.results[0].passed === true && o.ret.shadows[0].error.includes('agent type not found')"
  check "$n: the shadow result is not merged into the unit's work" $T \
    "$(P s true "$FB")" ok \
    "o.ret.results[0].passed === true && !('junk' in o.ret.results[0].work)"
done
for T in pipeline-with-gate.workflow.js fan-out-with-gate.workflow.js; do
  n="${T%%-with*}"
  check "$n: an arbiter-directed relaunch counts as a live attempt" $T "$(P s true "$FB")" blocked \
    "o.calls.filter(c => c.label === 'exec:a').length === 2 && o.ret.shadows.length === 1 && o.ret.shadows[0].liveAttempts === 2 && o.ret.results[0].attempts === 1"
  check "$n: a non-string or blank sketchBranch launches no shadow" $T "$(P s true '"agentType":"aidex:gallery-builder","firstBuild":true,"sketchBranch":true')" ok \
    "o.calls.every(c => !c.label.startsWith('shadow:')) && o.ret.shadows[0].error === 'no sketchBranch'"
  check "$n: a blank-string sketchBranch launches no shadow" $T "$(P s true '"agentType":"aidex:gallery-builder","firstBuild":true,"sketchBranch":"  "')" ok \
    "o.calls.every(c => !c.label.startsWith('shadow:')) && o.ret.shadows[0].error === 'no sketchBranch'"
  check "$n: an unsafe phase id launches no shadow" $T "[{\"id\":\"1.2 build/screen\",\"spec\":\"s\",\"gateCmd\":\"true\",$FB}]" ok \
    "o.calls.every(c => !c.label.startsWith('shadow:')) && o.ret.shadows[0].error === 'unsafe id' && o.ret.results[0].passed === true"
  check "$n: a sketchBranch with shell metacharacters launches no shadow" $T "$(P s true '"agentType":"aidex:gallery-builder","firstBuild":true,"sketchBranch":"x; rm -rf ~"')" ok \
    "o.calls.every(c => !c.label.startsWith('shadow:')) && o.ret.shadows[0].error === 'unsafe sketchBranch' && o.ret.results[0].passed === true"
  check "$n: a sketchBranch starting with a dash or holding .. launches no shadow" $T "$(P s true '"agentType":"aidex:gallery-builder","firstBuild":true,"sketchBranch":"--force"')" ok \
    "o.ret.shadows[0].error === 'unsafe sketchBranch'"
  check "$n: an id holding .. launches no shadow" $T "[{\"id\":\"..\",\"spec\":\"s\",\"gateCmd\":\"true\",$FB}]" ok \
    "o.calls.every(c => !c.label.startsWith('shadow:')) && o.ret.shadows[0].error === 'unsafe id'"
  check "$n: a dotted safe id still gets a shadow" $T "[{\"id\":\"1.2\",\"spec\":\"s\",\"gateCmd\":\"true\",$FB}]" ok \
    "o.ret.shadows[0].worktree === 'gbshadow-p-1.2'"
done
check "fan-out: a live crash returns the still-running shadow as unsettled" fan-out-with-gate.workflow.js \
  "$(P s true "$FB")" slow "o.ret.shadows.length === 1 && o.ret.shadows[0].worktree === 'gbshadow-p-a' && o.ret.shadows[0].settled === false && o.ret.results[0].passed === false"
for T in pipeline-with-gate.workflow.js fan-out-with-gate.workflow.js; do
  n="${T%%-with*}"
  PLAN_PATH=/ check "$n: a degenerate planPath does not crash a plan with no gallery phase" $T "$(P s true '"agentType":"aidex:impl-sonnet"')" ok \
    "!o.threw && o.ret.results[0].passed === true"
  PLAN_PATH=.context/plans/2026-10-25-foo.md check "$n: the plan slug is the planPath basename without extension" $T "$(P s true "$FB")" ok \
    "o.ret.shadows[0].worktree === 'gbshadow-2026-10-25-foo-a'"
done
check "pipeline: a live builder that rejects still fails the run as before" pipeline-with-gate.workflow.js \
  "$(P s true "$FB")" livereject "/live crashed/.test(o.threw)"
check "fan-out: a live builder that rejects still gives a crashed result row" fan-out-with-gate.workflow.js \
  "$(P s true "$FB")" livereject "o.ret.results[0].passed === false && /crashed/.test(o.ret.results[0].error)"

[ "$fail" -eq 0 ] && echo "PASS: the shadow arm launches only for a first-build gallery-builder phase and never gates" || exit 1
