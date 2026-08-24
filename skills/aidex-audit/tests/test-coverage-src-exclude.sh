#!/usr/bin/env bash
# test-coverage-src-exclude.sh — BL-229: a module's `src` globs must be able to
# exclude co-located test scaffolding, so a mocks/fixtures file next to the
# product code stops counting as product source and inflating `src_files`.
#
# Shape of the test, in the order the item's acceptance asks for it:
#   1. BEFORE — a co-located `__fixtures__` file counts as src (the bug).
#   2. AFTER  — with `src_exclude`, the same file is gone from `src_files`.
#   3. The excluded file is NOT silently added to the test set, and does not
#      surface as an unmapped test file either.
#   4. coverage_sweep reads the same definition: no phantom `+1 src` delta
#      against a matrix generated with the exclusion.
#   5. affected-tests deliberately does NOT honour the exclusion — a changed
#      fixture must still select the module's tests.
#   6. A malformed `src_exclude` is rejected by load_map, like `src` is.
#
# Run with: bash skills/aidex-audit/tests/test-coverage-src-exclude.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"
COV="$SCRIPTS_DIR/coverage"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

WS="$(bash "$TESTS_DIR/fixtures/coverage-workspace.sh")"
trap 'rm -rf "$WS"' EXIT

MAP="$WS/.context/audits/test-coverage/module-map.json"
JSON="$WS/.context/audits/test-coverage/coverage-matrix.json"

# --- co-located test scaffolding, committed as tracked source ---------------
# The field case (echo_lab_ws, 2026-08-24): EditorPage/__fixtures__/*.ts sits
# under the module's own src tree, so the src glob swallows it.
mkdir -p "$WS/frontend/src/billing/__fixtures__"
cat > "$WS/frontend/src/billing/__fixtures__/formMocks.ts" <<'EOF'
export const invoiceMock = { id: 1 };
EOF
git -C "$WS/frontend" add -A
GIT_AUTHOR_DATE="2020-01-02T00:00:00" GIT_COMMITTER_DATE="2020-01-02T00:00:00" \
  git -C "$WS/frontend" commit -q -m "billing: co-located test mocks"

src_files_of() {  # module id -> src_files in the generated matrix json
  python3 -c "
import json, sys
data = json.load(open('$JSON'))
mod = next(m for m in data['modules'] if m['id'] == sys.argv[1])
print(mod['src_files'])
" "$1"
}

# --- 1. BEFORE: the fixture file counts as product source -------------------
python3 "$COV/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero (before)"
before="$(src_files_of billing)"
[[ "$before" == "4" ]] \
  || fail "before: expected billing src_files=4 (3 real + 1 co-located mock), got $before"

# --- 2. AFTER: src_exclude drops it -----------------------------------------
python3 - "$MAP" <<'EOF'
import json, sys
path = sys.argv[1]
m = json.load(open(path))
mod = next(x for x in m["modules"] if x["id"] == "billing")
mod["src_exclude"] = ["frontend/src/billing/__fixtures__/**"]
with open(path, "w") as f:
    json.dump(m, f, indent=2)
EOF

python3 "$COV/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero (after)"
after="$(src_files_of billing)"
[[ "$after" == "3" ]] \
  || fail "after: expected billing src_files=3 with src_exclude, got $after (exclusion not honoured)"

# --- 3. the excluded file joins neither the test set nor the unmapped list ---
out="$(python3 -c "
import json
data = json.load(open('$JSON'))
b = next(m for m in data['modules'] if m['id'] == 'billing')
assert b['unit_files'] == 1, b['unit_files']
assert b['e2e_files'] == 2, b['e2e_files']
assert b['notes'] != 'NO TESTS', b['notes']
bad = [f for f in data['unmapped_test_files'] if 'formMocks' in f]
assert not bad, bad
print('OK')
" 2>&1)"
[[ "$out" == "OK" ]] || fail "excluded file leaked into the test set or unmapped list: $out"

# --- 4. sweep agrees with the matrix: no phantom src delta ------------------
sweep="$(python3 "$COV/coverage_sweep.py" "$WS" 2>&1)"
billing_row="$(printf '%s\n' "$sweep" | grep -E '^billing ')"
printf '%s\n' "$billing_row" | grep -qE '(\+|-)[0-9]+ src' \
  && fail "sweep reports a phantom surface delta for an excluded file: $billing_row"

# --- 5. affected-tests still attributes a changed fixture to the module ------
# Exclusion is coverage ACCOUNTING, not change ATTRIBUTION: editing a mock can
# break the tests that read it, so the module must still be selected.
echo 'export const extraMock = { id: 2 };' >> "$WS/frontend/src/billing/__fixtures__/formMocks.ts"
aff="$(python3 "$COV/affected_tests.py" "$WS" 2>&1)"
git -C "$WS/frontend" checkout -- src/billing/__fixtures__/formMocks.ts
printf '%s\n' "$aff" | grep -q 'billing' \
  || fail "affected-tests dropped a changed co-located fixture: $aff"
printf '%s\n' "$aff" | grep -qi 'unmapped' \
  && fail "affected-tests reported the changed fixture as unmapped: $aff"

# --- 6. a malformed src_exclude is rejected, like src is --------------------
python3 - "$MAP" <<'EOF'
import json, sys
path = sys.argv[1]
m = json.load(open(path))
mod = next(x for x in m["modules"] if x["id"] == "billing")
mod["src_exclude"] = "frontend/src/billing/__fixtures__/**"   # string, not list
with open(path, "w") as f:
    json.dump(m, f, indent=2)
EOF
if python3 "$COV/_coverage_lib.py" load "$WS" >/dev/null 2>&1; then
  fail "load_map accepted a string src_exclude (it iterates character by character)"
fi

if (( failures )); then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
printf 'PASS: test-coverage-src-exclude.sh\n'
