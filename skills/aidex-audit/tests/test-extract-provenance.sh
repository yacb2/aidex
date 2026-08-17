#!/usr/bin/env bash
# test-extract-provenance.sh — pins the front of the usage-retro pipeline.
#
# WHY THIS SUITE EXISTS. `prompt_kinds.py` shipped as the one classifier that
# decides what counts as a typed prompt, and `extract.py` kept its own fork of
# that logic — written before prompt_kinds existed, with no provenance check and
# no expanded-command-body pattern. So machine text re-entered the corpus at the
# FRONT of the pipeline, upstream of every miner that had already been fixed:
# 7 of the first 37 standing-preference candidates were `# /handoff` bodies.
#
# The fix was applied in the workspace and could not be pinned, because the file
# lived outside the tracked tree and hardcoded `~/.claude/projects`, so no fixture
# corpus could be pointed at it. Both are why this file exists (BL-165).
#
# Run with: bash skills/aidex-audit/tests/test-extract-provenance.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
EXTRACT="$HERE/../scripts/usage-retro/extract.py"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TX="$(bash "$HERE/fixtures/extract-corpus.sh")"
OUT="$(mktemp -d)"
trap 'rm -rf "$TX" "$OUT"' EXIT

# A ten-year window: the fixture's timestamps are fixed, so the test must not
# start failing because the calendar moved.
run_out="$(python3 "$EXTRACT" --out "$OUT/dataset.jsonl" --cursor "$OUT/cursor.json" \
                  --since 3650d --transcripts-root "$TX" 2>&1)"
rc=$?

[[ $rc -eq 0 ]] && ok "extract runs against a fixture corpus" \
                || bad "extract failed on the fixture: $run_out"

# --- the root is a parameter, which is what makes everything below possible ---
[[ -s "$OUT/dataset.jsonl" ]] && ok "--transcripts-root is honoured (a dataset was written)" \
                              || bad "--transcripts-root produced no records — the root is still hardcoded"

prompts() { python3 -c '
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    if line.strip():
        print(json.loads(line)["prompt"].replace("\n", " "))
' "$OUT/dataset.jsonl"; }

# --- machine-authored bodies must not be in the dataset (BL-165 acceptance) ---
if prompts | grep -q "notes field"; then ok "a typed prompt is kept"
else bad "the typed prompt was dropped — the classifier is now too strict"; fi

if prompts | grep -q "/handoff"; then
  bad "an expanded slash-command body entered the dataset as a user prompt"
else ok "an expanded command body is excluded"; fi

if prompts | grep -qi "security vulnerabilities"; then
  bad "an injected harness body entered the dataset as a user prompt"
else ok "an injected harness body is excluded"; fi

if prompts | grep -qi "durability-arbiter\|design lead"; then
  bad "a session of pure machine records still produced prompts"
else ok "a machine-only session contributes nothing"; fi

# --- the handoff kickoff is machine; the real prompt after it is not ---
# Keyed on the kickoff's own timestamp, not on the word: "continue" is also a
# thing users legitimately type (s8), so a text match here stopped discriminating
# the moment the corpus grew a real one.
kickoff_n="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and json.loads(l)["ts"].startswith("2026-01-02T09:00:01")))
' "$OUT/dataset.jsonl")"
[[ "$kickoff_n" == "0" ]] && ok "the wrapper kickoff is excluded" \
  || bad "the handoff wrapper's kickoff positional was counted as a typed prompt"

if prompts | grep -q "mide el recall"; then ok "a real prompt in a seeded session is kept"
else bad "the seeded session's real prompt was dropped with its kickoff"; fi

# --- the count is REPORTED, never silently smaller ---
if grep -qE "machine-authored prompts excluded: [1-9]" <<<"$run_out"; then
  ok "machine exclusions are reported as a visible non-zero count"
else bad "the machine-exclusion count is missing or zero: $run_out"; fi

# --- look-ahead attribution: the load-bearing one -----------------------------
# The typed prompt is followed by aidex-plan, THEN a machine body with its own
# skill fire, THEN another. A look-ahead that does not stop at a machine record
# walks past both and credits all three to the human prompt. This is the defect
# that survives every fix applied downstream, because it is applied here.
fired="$(python3 -c '
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    r = json.loads(line)
    if "notes field" in r["prompt"]:
        print(",".join(r["skills_fired"]))
        break
' "$OUT/dataset.jsonl")"
if [[ "$fired" == "aidex-plan" ]]; then
  ok "skill fires stop at the next prompt of ANY kind"
else
  bad "skill fires were credited across a machine body: got '$fired', want 'aidex-plan'"
fi

# --- one thing said once is one record (BL-170) -------------------------------
# A resumed session is written to a NEW transcript file with its earlier records
# replayed, so a file-walking extractor counts those prompts once per file. In
# the 90-day corpus that was 20 of 4,688 records — 0.4% overall, but 2 of the 32
# standing-preference candidates, because the smaller the class the more a
# duplicate distorts it.
n_mockup="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and "usa siempre mockups" in json.loads(l)["prompt"]))
' "$OUT/dataset.jsonl")"
[[ "$n_mockup" == "1" ]] && ok "a prompt replayed into a resumed session counts once" \
                         || bad "the replayed prompt produced $n_mockup records, want 1"

if prompts | grep -q "fase dos"; then ok "the new prompt in the resumed file survives dedup"
else bad "dedup dropped the second file's genuinely new prompt"; fi

n_same_ts="$(python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and "pregunta distinta" in json.loads(l)["prompt"]))
' "$OUT/dataset.jsonl")"
[[ "$n_same_ts" == "2" ]] && ok "two different prompts sharing a timestamp both survive" \
                          || bad "$n_same_ts of 2 same-timestamp prompts survived — the dedup key is too coarse"

grep -qE "duplicate|replayed" <<<"$run_out" \
  && ok "collapsed duplicates are reported, not silently dropped" \
  || bad "the duplicate count is not reported: $run_out"

# The fork whose replay carries a FRESH timestamp — the mode an exact-ts key
# cannot see. The observed pair was 4.19s apart across two session files.
count_of() { python3 -c '
import json, sys
print(sum(1 for l in open(sys.argv[1], encoding="utf-8")
          if l.strip() and sys.argv[2] in json.loads(l)["prompt"]))
' "$OUT/dataset.jsonl" "$1"; }

n_long="$(count_of "usa graficos o mockups para apoyarte")"
[[ "$n_long" == "2" ]] && ok "a near-simultaneous replay collapses, a later re-ask does not ($n_long)" \
                       || bad "want 2 records (one collapsed pair + one genuine re-ask), got $n_long"

# Short prompts are the ones that legitimately repeat. Collapsing by text alone
# would erase them, and "continue" twice in a row is real user behaviour.
n_cont="$(count_of "continue")"
[[ "$n_cont" == "2" ]] && ok "two genuine 'continue' prompts both survive" \
                       || bad "$n_cont of 2 short repeated prompts survived — the window ignores length"

echo
echo "extract provenance: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
