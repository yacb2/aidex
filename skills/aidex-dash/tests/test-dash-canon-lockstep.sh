#!/usr/bin/env bash
# test-dash-canon-lockstep.sh — ties the dash renderers to aidex-audit's REAL
# templates/generator, so a canon-side rename can no longer render a
# confidently-wrong GENERATED board (the registry-lag failure at the parser
# layer). Unlike test-dash-render.sh, whose fixtures are hand-written and drift
# from the templates independently, this test scaffolds through the actual
# producers: an audit board via new-audit.sh (real templates) and a coverage
# matrix via coverage_matrix.py (real producer). It runs the dash renderers over
# both and asserts they parse; then the negative cells — rename a findings
# column -> render_audit dies; bump the coverage schema key -> render_coverage
# dies.
#
# Run with: bash skills/aidex-dash/tests/test-dash-canon-lockstep.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DASH="$TESTS_DIR/../scripts/dash/render.py"
AUDIT_SCRIPTS="$TESTS_DIR/../../aidex-audit/scripts"
COVERAGE_FIXTURE="$TESTS_DIR/../../aidex-audit/tests/fixtures/coverage-workspace.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

WS="$(mktemp -d)"
COV_WS=""
trap 'rm -rf "$WS" "${COV_WS:-}"' EXIT

# --- 1. audit board scaffolded from the REAL templates via new-audit.sh -------
mkdir -p "$WS/.context"
( cd "$WS" && bash "$AUDIT_SCRIPTS/new-audit.sh" ux lockstep-probe ) >/dev/null 2>&1 \
  || fail "new-audit.sh scaffold exited non-zero"
INV="$WS/.context/audits/ux/00-inventory.md"
[[ -f "$INV" ]] || fail "scaffold did not create $INV"

# positive: dash finds the findings table past the 'How to read' legend table
# and the EXAMPLE comment block that ship in the real template
python3 "$DASH" "$WS" audit ux >/dev/null 2>"$WS/err.txt" \
  || fail "render_audit died on a real scaffolded board: $(cat "$WS/err.txt")"
AU_HTML="$WS/.context/audits/ux/00-inventory.html"
[[ -f "$AU_HTML" ]] || fail "audit render produced no html"
head -1 "$AU_HTML" | grep -q '^<!-- GENERATED' || fail "audit html missing GENERATED header"
grep -qE 'EX-01-1|EX-FF-2|EX-05-1' "$AU_HTML" \
  && fail "template EXAMPLE rows leaked into the audit render"

# negative: a canon-side rename of a required findings column -> loud exit 2
python3 - "$INV" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
t = t.replace("| Status | Severity |", "| Status | Sev |")
open(p, "w").write(t)
PY
python3 "$DASH" "$WS" audit ux >/dev/null 2>"$WS/err2.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "renamed findings column should exit 2 (got $rc)"
grep -q '^ERROR:' "$WS/err2.txt" || fail "renamed column should print ERROR: on stderr"

# --- 2. coverage matrix produced by the REAL producer (coverage_matrix.py) -----
COV_WS="$(bash "$COVERAGE_FIXTURE")"
python3 "$AUDIT_SCRIPTS/coverage/coverage_matrix.py" "$COV_WS" >/dev/null 2>&1 \
  || fail "coverage_matrix.py exited non-zero"
COV_JSON="$COV_WS/.context/audits/test-coverage/coverage-matrix.json"
[[ -f "$COV_JSON" ]] || fail "producer wrote no coverage-matrix.json"
# the producer must stamp the pinned schema the consumer expects (lockstep)
grep -q '"schema": "coverage-matrix/1"' "$COV_JSON" \
  || fail "producer did not emit the pinned schema key render_coverage expects"

# positive: dash parses the real producer output
python3 "$DASH" "$COV_WS" coverage >/dev/null 2>"$COV_WS/err.txt" \
  || fail "render_coverage died on real producer output: $(cat "$COV_WS/err.txt")"
CO_HTML="$COV_WS/.context/audits/test-coverage/coverage-matrix.html"
[[ -f "$CO_HTML" ]] || fail "coverage render produced no html"
grep -q 'billing' "$CO_HTML" || fail "coverage render missing the billing module row"

# negative: an unknown schema value -> loud exit 2
python3 - "$COV_JSON" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["schema"] = "coverage-matrix/999"
json.dump(d, open(p, "w"), indent=2)
PY
python3 "$DASH" "$COV_WS" coverage >/dev/null 2>"$COV_WS/err2.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "unknown coverage schema should exit 2 (got $rc)"
grep -q '^ERROR:' "$COV_WS/err2.txt" || fail "unknown schema should print ERROR: on stderr"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — audit board (real templates) and coverage matrix (real producer) parse through dash; renamed findings column and unknown coverage schema both exit 2"
