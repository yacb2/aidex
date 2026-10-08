#!/usr/bin/env bash
# drift.workflow.js behaviour under stubbed workflow globals (agent, pipeline, log, phase).
#
# A Workflow script has no runner in this repo, so each row runs the whole script with stubs
# and checks the JSON it returns and the prompts it sent. Rows pin the ways a unit could
# look healthy while nothing was checked: no units, an extract that read nothing, a verify
# whose verdicts do not cover every fact, a verify-off run that calls facts confirmed.
#
# Run with: bash skills/reference/tests/test-drift-workflow.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
WF="$ROOT/skills/reference/assets/workflows/drift.workflow.js"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/probe.mjs" <<'PROBE'
import fs from 'fs'
import assert from 'assert'
const src = fs.readFileSync(process.argv[2], 'utf8').replace(/^export const meta/m, 'const meta')
const fact = (n, prov = 'traced') => ({ claim: 'c' + n, symbol: 's', file: 'f.py', line_start: n, line_end: n + 1,
  kind: 'api', provenance: prov })
const finding = { type: 'stale', reference: 'r.md', reference_line: 3, detail: 'd', evidence: 'f.py:1' }

// behaviours: unit slug -> {extract, verify, compare}; each is a value, null (no output) or 'throw'
async function run(args, beh) {
  const prompts = []
  const agent = async (prompt, o) => {
    prompts.push({ type: o.agentType, label: o.label, prompt, schema: o.schema })
    const slug = o.label.split(':')[1]
    const stage = o.agentType.replace('aidex:drift-', '')
    const b = beh[slug][stage]
    if (b === 'throw') throw new Error('boom')
    return b
  }
  const pipeline = (items, ...st) => Promise.all(items.map(async it => { let v = it; for (const s of st) v = await s(v, it); return v }))
  const fn = new Function('args', 'agent', 'pipeline', 'parallel', 'phase', 'log',
    `return (async () => {\n${src}\n})()`)
  const out = await fn(JSON.stringify(args), agent, pipeline, null, () => {}, () => {})
  return { out, prompts }
}
const base = { root: '/r', work: '/w', date: 'd' }
const unit = (out, slug) => out.units.find(u => u.slug === slug)
const rows = {}

rows['no units throws'] = async () => {
  await assert.rejects(run({ ...base, units: [] }, {}), /units/)
  await assert.rejects(run({ ...base }, {}), /units/)
}
rows['empty extract with not_covered is failed at extract'] = async () => {
  const { out } = await run({ ...base, units: ['u'] }, { u: { extract: { facts: [], not_covered: ['a.py'] } } })
  assert.deepStrictEqual([unit(out, 'u').status, unit(out, 'u').failed_stage], ['failed', 'extract'])
}
rows['not_covered count is carried per unit'] = async () => {
  const { out } = await run({ ...base, units: ['u'] }, { u: {
    extract: { facts: [fact(1)], not_covered: ['a.py', 'b.py'] },
    verify: { verdicts: [{ i: 0, verdict: 'confirmed', evidence: 'e' }] }, compare: { items: [] } } })
  assert.strictEqual(unit(out, 'u').not_covered, 2)
  assert.strictEqual(unit(out, 'u').status, 'ok')
}
rows['empty extract with nothing uncovered is ok and skips compare'] = async () => {
  const { out, prompts } = await run({ ...base, units: ['u'] }, { u: { extract: { facts: [], not_covered: [] } } })
  assert.strictEqual(unit(out, 'u').status, 'ok')
  assert.strictEqual(prompts.length, 1)
}
const verdictRow = (verdicts) => async () => {
  const { out, prompts } = await run({ ...base, units: ['u'] }, { u: {
    extract: { facts: [fact(1), fact(2)], not_covered: [] }, verify: { verdicts }, compare: { items: [finding] } } })
  assert.deepStrictEqual([unit(out, 'u').status, unit(out, 'u').failed_stage], ['failed', 'verify'])
  assert.ok(!prompts.some(p => p.type === 'aidex:drift-compare'))
}
rows['verdicts: [] fails verify'] = verdictRow([])
rows['1-based verdicts fail verify'] = verdictRow([{ i: 1, verdict: 'confirmed', evidence: 'e' }, { i: 2, verdict: 'confirmed', evidence: 'e' }])
rows['a missing verdict index fails verify'] = verdictRow([{ i: 0, verdict: 'confirmed', evidence: 'e' }])
rows['a duplicated verdict index fails verify'] = verdictRow([{ i: 0, verdict: 'confirmed', evidence: 'e' }, { i: 0, verdict: 'refuted', evidence: 'e' }])
rows['exact verdicts: compare gets only confirmed facts, candidate wording'] = async () => {
  const { out, prompts } = await run({ ...base, units: ['u'] }, { u: {
    extract: { facts: [fact(1), fact(2)], not_covered: [] },
    verify: { verdicts: [{ i: 0, verdict: 'refuted', evidence: 'e' }, { i: 1, verdict: 'confirmed', evidence: 'e' }] },
    compare: { items: [finding] } } })
  const u = unit(out, 'u')
  assert.deepStrictEqual([u.status, u.facts_extracted, u.facts_confirmed, u.findings], ['ok', 2, 1, 1])
  assert.strictEqual(out.findings[0].unit, 'u')
  const p = prompts.find(x => x.type === 'aidex:drift-compare').prompt
  assert.ok(p.includes('c2') && !p.includes('c1'))
  assert.ok(p.includes('candidate references (matched by path or symbol)'))
  assert.ok(p.includes('whose subject is this unit'))
}
rows['verify:false skips verify, says unverified, drops inferred, confirmed is null'] = async () => {
  const { out, prompts } = await run({ ...base, units: ['u'], verify: false }, { u: {
    extract: { facts: [fact(1), fact(2, 'inferred')], not_covered: [] }, compare: { items: [] } } })
  assert.ok(!prompts.some(p => p.type === 'aidex:drift-verify'))
  const p = prompts.find(x => x.type === 'aidex:drift-compare').prompt
  assert.ok(/NOT verified/.test(p) && !/confirmed against the current code/.test(p))
  assert.ok(p.includes('c1') && !p.includes('c2'))
  assert.strictEqual(unit(out, 'u').facts_confirmed, null)
  assert.strictEqual(unit(out, 'u').facts_extracted, 2)
}
rows['a compare that throws fails that unit only'] = async () => {
  const ok = { extract: { facts: [fact(1)], not_covered: [] }, verify: { verdicts: [{ i: 0, verdict: 'confirmed', evidence: 'e' }] },
    compare: { items: [finding] } }
  const { out } = await run({ ...base, units: ['a', 'b'] }, { a: { ...ok, compare: 'throw' }, b: ok })
  assert.deepStrictEqual([unit(out, 'a').status, unit(out, 'a').failed_stage], ['failed', 'compare'])
  assert.strictEqual(unit(out, 'b').status, 'ok')
  assert.strictEqual(out.findings.length, 1)
}

rows['compare schema requires reference_line >= 1'] = async () => {
  const { prompts } = await run({ ...base, units: ['u'] }, { u: {
    extract: { facts: [fact(1)], not_covered: [] },
    verify: { verdicts: [{ i: 0, verdict: 'confirmed', evidence: 'e' }] }, compare: { items: [] } } })
  const s = prompts.find(x => x.type === 'aidex:drift-compare').schema
  assert.strictEqual(s.properties.items.items.properties.reference_line.minimum, 1)
}

rows['3 facts confirmed/unverifiable/refuted: compare gets only the confirmed one'] = async () => {
  const { out, prompts } = await run({ ...base, units: ['u'] }, { u: {
    extract: { facts: [fact(1), fact(2), fact(3)], not_covered: [] },
    verify: { verdicts: [{ i: 0, verdict: 'confirmed', evidence: 'e' }, { i: 1, verdict: 'unverifiable', evidence: 'e' },
      { i: 2, verdict: 'refuted', evidence: 'e' }] }, compare: { items: [] } } })
  const p = prompts.find(x => x.type === 'aidex:drift-compare').prompt
  assert.ok(p.includes('c1') && !p.includes('c2') && !p.includes('c3'))
  assert.strictEqual(unit(out, 'u').facts_confirmed, 1)
  assert.strictEqual(unit(out, 'u').facts_to_compare, 1)
}
rows['verify:false reports dropped inferred facts and what compare got'] = async () => {
  const { out } = await run({ ...base, units: ['u'], verify: false }, { u: {
    extract: { facts: [fact(1), fact(2, 'inferred'), fact(3, 'inferred')], not_covered: [] }, compare: { items: [] } } })
  const u = unit(out, 'u')
  assert.deepStrictEqual([u.facts_extracted, u.facts_dropped_inferred, u.facts_to_compare], [3, 2, 1])
}
rows['compare prompt tells the comparer to copy the reference path as written in refs.txt'] = async () => {
  const { prompts } = await run({ ...base, units: ['u'] }, { u: {
    extract: { facts: [fact(1)], not_covered: [] },
    verify: { verdicts: [{ i: 0, verdict: 'confirmed', evidence: 'e' }] }, compare: { items: [] } } })
  assert.ok(/exactly as written in/.test(prompts.find(x => x.type === 'aidex:drift-compare').prompt))
}

let bad = 0
for (const [name, f] of Object.entries(rows)) {
  try { await f(); console.log('ok   ' + name) } catch (e) { bad++; console.log('FAIL ' + name + ': ' + String(e.message).split('\n')[0]) }
}
process.exit(bad ? 1 : 0)
PROBE

if node "$TMP/probe.mjs" "$WF"; then
  echo "PASS: drift.workflow.js rows"
else
  exit 1
fi
