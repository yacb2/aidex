#!/usr/bin/env bash
# Every subagent definition sets `model:` explicitly (BL-403, 2026-09-14), and every
# batch script forwards the toolset carrier `agentType` (BL-408, 2026-09-20), and every
# working agent prompt a batch script composes names the `aidex:testing` skill (2026-09-25).
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
// whether the options object carries an `agentType` key and its value. With a third
// argument, it also writes each working call's prompt there as JSON ({label: prompt}).
import fs from 'fs'
const [file, argsJson, promptsOut] = process.argv.slice(2)
const prompts = {}
const src = fs.readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const captured = []
const agent = (prompt, opts) => {
  captured.push(opts)
  prompts[opts.label] = prompt
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
if (promptsOut) fs.writeFileSync(promptsOut, JSON.stringify(
  Object.fromEntries(work.map((o) => [o.label, prompts[o.label]]))))
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

    # ---- the prompt a phase agent actually receives names the testing skill ----
    # A batch phase agent is fresh: the plan-exec session's context never reaches it, so the
    # testing core arrives only if the composed prompt points to it. An implementer must
    # also be told not to patch a bug outside its phase, and how to report it so the
    # orchestrator can route it (bugfix-opus) — an inline patch ships untested behaviour.
    prompts_json="$probe_dir/${name}.prompts.json"
    node "$probe" "$wf" "$WITHOUT" "$prompts_json" >/dev/null 2>&1 \
      || { printf 'FAIL: %s probe (prompt capture) errored\n' "$name"; failures=$((failures+1)); continue; }
    miss="$(node -e '
      const p = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
      const bad = []
      for (const [label, text] of Object.entries(p)) {
        if (!/aidex:testing/.test(text)) bad.push(label + " names no aidex:testing")
        if (/^exec:/.test(label) && !/OUT-OF-SCOPE BUG/.test(text)) bad.push(label + " has no out-of-scope bug report line")
        // A phase agent cannot resolve a path relative to a plugin root it is never told.
        if (/plugin root|(^|[^\/\w])skills\/testing\/SKILL\.md/.test(text)) bad.push(label + " points to testing by an unresolvable relative path")
      }
      if (!Object.keys(p).length) bad.push("no working agent prompt captured")
      console.log(bad.join("; "))' "$prompts_json")"
    [[ -z "$miss" ]] || { printf 'FAIL: %s: %s\n' "$name" "$miss"; failures=$((failures+1)); }
  done
else
  echo "SKIP: node not available — the agentType forwarding probe did not run"
fi

# ---- the tier definition Orient step 7 writes preloads the testing skill ----
# A restricted tier (e.g. `tools: Read`) has no Skill tool, so a batch phase agent running
# on it can reach `testing` only through its definition's `skills:` preload (measured
# honoured 12/12 with Read-only tools, 2026-09-25). Step 7 is the only place that says
# what such a definition carries.
step7="$(awk '/^7\. \*\*Set the run.s spend/{g=1} /^8\. /{g=0} g' "$ROOT/skills/plan-exec/SKILL.md" | tr '\n' ' ')"
[[ -n "$step7" ]] || { echo "FAIL: could not find Orient step 7 in plan-exec/SKILL.md"; failures=$((failures+1)); }
grep -qE '`skills: \[[^]]*aidex:testing' <<<"$step7" \
  || { echo "FAIL: plan-exec Orient step 7 does not make the tier definition preload skills: [aidex:testing]"; failures=$((failures+1)); }

[[ $failures -eq 0 ]] && echo "PASS: every agent definition sets model:, and all 3 batch scripts forward agentType (omitting the key when unset) and name aidex:testing in every working prompt" || exit 1
