#!/usr/bin/env bash
# test-usage-retro.sh — the two load-bearing invariants of the usage-retro miners
# (BL-132), against the hand-written corpus fixture.
#
# WHY THIS SUITE EXISTS. Both invariants were undefended. Provenance-gating lived
# in mine_items.py with nothing pinning it; the strict-span rule lived nowhere at
# all — it was applied by hand in the 2026-08-07 study's analysis and did not
# survive it. Whatever is only in a docstring gets rewritten away.
#
# Scenarios:
#   (a) an item named ONLY inside a tool_result attributes to nothing
#   (b) a real user prompt naming an item DOES attribute
#   (c) strict-span: prompt + 1 edit -> working
#   (d) strict-span: no prompt + 2 edits -> NOT working
#   (e) strict-span: no prompt + 3 edits -> working
#   (f) is_working_span() is a pure predicate, callable without a corpus
#   (g) roots are real parameters: a bogus projects-root yields an empty registry
#   (h) the roots reach mine_defect_proneness through M.configure()
#
# Run with: bash skills/aidex-audit/tests/test-usage-retro.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RETRO="$TESTS_DIR/../scripts/usage-retro"
FIXTURE="$TESTS_DIR/fixtures/usage-retro-corpus.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

read -r PROJ TX <<< "$(bash "$FIXTURE")"
OUT="$(mktemp -d)"
cleanup() { rm -rf "$PROJ" "$TX" "$OUT"; }
trap cleanup EXIT

report="$(python3 "$RETRO/mine_items.py" --projects-root "$PROJ" \
  --transcripts-root "$TX" --out "$OUT" --min-mentions 1 2>&1)"

echo "$report" | grep -q 'registry: 4 tracked items' \
  || fail "(setup) expected 4 registry items: $report"

# span_field <slug> <field> — empty when the slug produced no span at all.
span_field() {
  python3 -c '
import json, sys
for line in open(sys.argv[1] + "/spans.jsonl"):
    s = json.loads(line)
    if s["slug"] == sys.argv[2]:
        print(s[sys.argv[3]]); break
' "$OUT" "$1" "$2"
}

# ---------------------------------------------------------------------------
# (a) THE PROVENANCE GATE. backlog/00-index.md lists every item, so a session
#     that merely READ the index would otherwise get the whole register
#     attributed to it. A slug seen only in a tool_result must produce no span.
#
#     ON MUTATION-TESTING THIS ONE, because the obvious attempt reads as vacuous:
#     the gate in user_text() is TWO layers — an early return on any tool_result
#     block, and a join that keeps only `type: "text"` blocks. Removing either
#     alone changes nothing, because the other still blocks it, so a single-layer
#     mutation leaves this assertion green and looks like a dead test. It is not:
#     removing BOTH (the realistic rewrite — "fold tool output into user text")
#     makes this fail, verified 2026-08-07. Do not "fix" this test on the strength
#     of a one-layer mutation.
# ---------------------------------------------------------------------------
[[ -z "$(span_field 2026-01-02-beta working)" ]] \
  || fail "(a) an item named only inside a tool_result must not attribute"

# The session still exists and still edits files — the gate has to be about
# provenance, not about the session being empty.
grep -q 'unrelated.py' "$TX"/*/s2.jsonl \
  || fail "(a) fixture drift: s2 should carry an edit, or (a) proves nothing"

# ---------------------------------------------------------------------------
# (b) the same mechanism must still attribute a REAL user prompt, or (a) would
#     pass by attributing nothing at all.
# ---------------------------------------------------------------------------
[[ "$(span_field 2026-01-01-alpha prompt_mentions)" == "1" ]] \
  || fail "(b) a user prompt naming the item should attribute"

# ---------------------------------------------------------------------------
# (c)(d)(e) THE STRICT-SPAN RULE: a working session is a user prompt naming the
#     item, OR >=3 edits. Without it "sessions per item" inflates ~2x.
# ---------------------------------------------------------------------------
[[ "$(span_field 2026-01-01-alpha working)" == "True" ]] \
  || fail "(c) prompt-mention + 1 edit should be a working span"
[[ "$(span_field 2026-01-03-gamma edits)" == "2" && \
   "$(span_field 2026-01-03-gamma working)" == "False" ]] \
  || fail "(d) no prompt + 2 edits must NOT be a working span"
[[ "$(span_field 2026-01-04-delta edits)" == "3" && \
   "$(span_field 2026-01-04-delta working)" == "True" ]] \
  || fail "(e) no prompt + 3 edits should be a working span (the edit rule)"

echo "$report" | grep -q '2 working, 1 below the strict-span rule' \
  || fail "(e) the run should report the working/non-working split: $report"

# ---------------------------------------------------------------------------
# (f) the rule is a predicate, not prose in a docstring. The boundary is 3.
# ---------------------------------------------------------------------------
out_f="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from mine_items import is_working_span as w
cases = [
    ({"prompt_mentions": 1, "edits": 0}, True),
    ({"prompt_mentions": 0, "edits": 2}, False),
    ({"prompt_mentions": 0, "edits": 3}, True),
    ({"prompt_mentions": 0, "edits": 0}, False),
]
bad = [c for c, want in cases if w(c) is not want]
print("BAD" if bad else "OK", bad)
' "$RETRO")"
[[ "$out_f" == OK* ]] || fail "(f) is_working_span boundary wrong: $out_f"

# ---------------------------------------------------------------------------
# (g) the roots must be real parameters. If --projects-root were ignored, every
#     scenario above would silently be measuring the author's real home
#     directory instead of the fixture — and would still look green.
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d)"
out_g="$(python3 "$RETRO/mine_items.py" --projects-root "$EMPTY" \
  --transcripts-root "$TX" --out "$OUT/g" --min-mentions 1 2>&1)"
rm -rf "$EMPTY"
echo "$out_g" | grep -q 'registry: 0 tracked items' \
  || fail "(g) --projects-root is not being honoured: $out_g"

# ---------------------------------------------------------------------------
# (h) the roots reach the consumers through M.configure(), not just mine_items.
#     A defect-proneness run over this corpus finds items but no bug items, so
#     it must say so rather than crash or read the real corpus.
# ---------------------------------------------------------------------------
out_h="$(python3 "$RETRO/mine_defect_proneness.py" --projects-root "$PROJ" \
  --transcripts-root "$TX" --denominator all --min-touches 1 2>&1)"
echo "$out_h" | grep -q 'base rate              : 0.0%' \
  || fail "(h) defect-proneness should see the fixture corpus (0% bug items): $out_h"
echo "$out_h" | grep -q 'items attributed       : 3' \
  || fail "(h) defect-proneness should attribute the same 3 items: $out_h"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — usage-retro: provenance gate (tool_result attributes nothing, real prompt does), strict-span rule at the 3-edit boundary, predicate pinned, roots honoured end-to-end"
