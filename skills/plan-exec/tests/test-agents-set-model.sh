#!/usr/bin/env bash
# Every subagent definition sets `model:` explicitly (BL-403, 2026-09-14), and every
# batch script forwards the toolset carrier `agentType` (BL-408, 2026-09-20).
#
# An agent file without a model line inherits the orchestrator's model; on the Work Hours
# chain that turned Fable/Opus into the de facto default for mechanical subagents. The rule
# lives in references/04-model-tiering.md; this guard makes an omission fail the suite.
#
# Run with: bash skills/plan-exec/tests/test-agents-set-model.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
failures=0
for f in "$ROOT"/skills/*/agents/*.md; do
  case "$f" in *.eval.md) continue ;; esac   # eval logs, not definitions
  head -1 "$f" | grep -q '^---$' || { printf 'FAIL: %s has no front matter\n' "${f#"$ROOT"/}"; failures=$((failures+1)); continue; }
  awk 'NR>1 && /^---$/ {exit} NR>1 {print}' "$f" | grep -q '^model: *[a-z]' \
    || { printf 'FAIL: %s sets no model: (inherits the orchestrator model)\n' "${f#"$ROOT"/}"; failures=$((failures+1)); }
done

# ---- the batch scripts forward `agentType`, and OMIT the key when absent ----
# A toolset reaches agent() only through `agentType` (agent() has no `tools` option), so a
# `mechanical` phase's restricted row has no effect unless the script passes it. The negative
# half is the one a static read misses: `agentType: undefined` is a present key, not an absent
# one, so the default path must stay byte-for-byte what it was. Asserted by RUNNING each script
# with a stubbed agent() and reading the options object it built.
WF="$ROOT/skills/plan-exec/assets/workflows"
if command -v node >/dev/null 2>&1; then
  probe_dir="$(mktemp -d)"
  probe="$probe_dir/probe.mjs"
  trap 'rm -rf "$probe_dir"' EXIT
  cat > "$probe" <<'PROBE'
// Runs a .workflow.js with stubbed workflow globals and prints, per non-gate agent call,
// whether the options object carries an `agentType` key and its value.
import fs from 'fs'
const [file, argsJson] = process.argv.slice(2)
const src = fs.readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const captured = []
const agent = (prompt, opts) => {
  captured.push(opts)
  if (/^verify:/.test(opts.label)) return Promise.resolve({ passed: true, exit_code: 0, evidence: 'ok' })
  if (opts.label === 'arbiter') return Promise.resolve({ verdict: 'CONTINUE', reason: 'ok' })
  if (opts.label === 'review') return Promise.resolve({ passed: true, findings: [], summary: 'ok' })
  return Promise.resolve({ done: true, summary: 'ok', proof: 'proof.txt' })
}
const parallel = (fns) => Promise.all(fns.map((f) => f()))
const run = new Function('args', 'agent', 'parallel', 'phase', 'log',
  `return (async () => {\n${src}\n})()`)
await run(argsJson, agent, parallel, () => {}, () => {})
const work = captured.filter((o) => !/^verify:/.test(o.label) && o.label !== 'arbiter')
console.log(work.map((o) => `${o.label}=${'agentType' in o ? (o.agentType ?? 'UNDEFINED') : 'ABSENT'}`).join(' '))
PROBE
  WITH='{"planPath":"p","phases":[{"id":"a","spec":"s","gateCmd":"true","agentType":"impl-restricted"}],
         "diffCmd":"d","successCriteria":"c","reviewAgentType":"impl-restricted"}'
  WITHOUT='{"planPath":"p","phases":[{"id":"a","spec":"s","gateCmd":"true"}],"diffCmd":"d","successCriteria":"c"}'
  for wf in "$WF"/*.workflow.js; do
    [[ -e "$wf" ]] || continue
    name="${wf##*/}"
    node --check "$wf" >/dev/null 2>&1 || { printf 'FAIL: %s does not parse (node --check)\n' "$name"; failures=$((failures+1)); continue; }
    out="$(node "$probe" "$wf" "$WITH" 2>&1)" || { printf 'FAIL: %s probe (carrier set) errored: %s\n' "$name" "$out"; failures=$((failures+1)); continue; }
    grep -q '=impl-restricted' <<<"$out" \
      || { printf 'FAIL: %s does not pass agentType to its working agent call: %s\n' "$name" "$out"; failures=$((failures+1)); }
    out="$(node "$probe" "$wf" "$WITHOUT" 2>&1)" || { printf 'FAIL: %s probe (carrier absent) errored: %s\n' "$name" "$out"; failures=$((failures+1)); continue; }
    case "$out" in
      *UNDEFINED*) printf 'FAIL: %s leaks an agentType: undefined key when no carrier is set: %s\n' "$name" "$out"; failures=$((failures+1)) ;;
      *=ABSENT*)   ;;
      *)           printf 'FAIL: %s: no working agent call observed without a carrier: %s\n' "$name" "$out"; failures=$((failures+1)) ;;
    esac
  done
else
  echo "SKIP: node not available — the agentType forwarding probe did not run"
fi

[[ $failures -eq 0 ]] && echo "PASS: every agent definition sets model:, and all 3 batch scripts forward agentType (omitting the key when unset)" || exit 1
