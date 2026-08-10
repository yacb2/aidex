#!/usr/bin/env bash
# test-resolve-target.sh — cells for resolve-review-target.sh.
#
# The cells that matter are the refusals. A resolver that silently defaults to the
# repo root, or prints an empty set as if it were a clean result, is the failure mode
# this script exists to prevent — so "no target" and "empty target" get a cell each,
# and the oversize refusal gets one because a whole-app run is exactly where a sample
# would otherwise be reported as coverage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RESOLVER="$SCRIPT_DIR/../scripts/resolve-review-target.sh"
FAILURES=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

run() { bash "$RESOLVER" "$@" 2>/dev/null; }
run_code() { bash "$RESOLVER" "$@" >/dev/null 2>&1; echo $?; }
field() { local key="$1"; shift; run "$@" | grep "^$key=" | cut -d= -f2-; }

# ── Fixture: a small module with one source file and one test ─────────────────
mkdir -p "$TMP/mod/tests" "$TMP/mod/node_modules/pkg"
printf 'def f():\n    return 1\n' > "$TMP/mod/app.py"
printf 'def test_f():\n    assert True\n' > "$TMP/mod/tests/test_app.py"
printf 'var junk = 1;\n' > "$TMP/mod/node_modules/pkg/index.js"
printf 'notes\n' > "$TMP/mod/README.md"

echo "resolve-review-target cells:"

# 1. No target at all must be refused, never defaulted. This is the cell that
#    encodes "the projects root has no default and refuses to run without one".
[ "$(run_code)" = "2" ] || fail "no target: expected exit 2, got $(run_code)"

# 2. A nonexistent path is a usage error, not an empty review.
[ "$(run_code "$TMP/nope")" = "2" ] || fail "missing path: expected exit 2"

# 3. A path with no source files exits 3 — distinguishable from 'nothing found'.
mkdir -p "$TMP/docs"; printf 'text\n' > "$TMP/docs/a.md"
[ "$(run_code "$TMP/docs")" = "3" ] || fail "empty target: expected exit 3, got $(run_code "$TMP/docs")"

# 4. Two targets is a usage error (a silent second target would widen the review).
[ "$(run_code "$TMP/mod" "$TMP/docs")" = "2" ] || fail "two targets: expected exit 2"

# 5. --app takes no path.
[ "$(run_code --app "$TMP/mod")" = "2" ] || fail "--app with path: expected exit 2"

# 6. Generated and vendored trees are excluded; non-source files are not counted.
#    `files` is the REVIEWED set, which excludes tests by default (cell 12) — the test
#    is still resolved and still counted, in test_files.
files="$(field files "$TMP/mod")"
[ "$files" = "1" ] || fail "file count: expected 1 reviewed (app.py; the test is counted in test_files), got '$files'"
[ "$(field files --include-tests "$TMP/mod")" = "2" ] || fail "--include-tests should bring the count back to 2"
if run --files "$TMP/mod" | grep -q node_modules; then
  fail "node_modules leaked into the resolved file set"
fi
if run --files "$TMP/mod" | grep -q 'README.md'; then
  fail "a non-source file leaked into the resolved file set"
fi

# 7. Test files are counted separately — a module with no tests reviews differently
#    from one with tests, and the triage needs to see that.
[ "$(field test_files "$TMP/mod")" = "1" ] || fail "test_files: expected 1"

# 8. Size class bounds the finder count, and small targets get the cheap tier.
[ "$(field size_class "$TMP/mod")" = "small" ] || fail "size_class: expected small"
[ "$(field finders_per_lens "$TMP/mod")" = "2" ] || fail "finders_per_lens: expected 2 for small"

# 9. Oversize is a refusal with a zero finder count, so no caller can read it as a
#    normal run. Built as one big file so the cell does not depend on the repo.
mkdir -p "$TMP/big"
awk 'BEGIN { for (i = 0; i < 13000; i++) print "x = " i }' > "$TMP/big/huge.py"
[ "$(field size_class "$TMP/big")" = "oversize" ] || fail "size_class: expected oversize for 13k LOC"
[ "$(field finders_per_lens "$TMP/big")" = "0" ] || fail "oversize must yield 0 finders, not a default tier"
if ! bash "$RESOLVER" "$TMP/big" 2>&1 >/dev/null | grep -q "oversize"; then
  fail "oversize target printed no refusal on stderr"
fi

# 10. Surface probes count evidence and are never negative-asserting: a file that
#     mentions a secret is counted, and a file that does not is simply not counted.
printf 'API_KEY = "x"\ncursor.execute(q)\n' > "$TMP/mod/creds.py"
[ "$(field security_surface_files "$TMP/mod")" -ge 1 ] || fail "security surface probe found nothing in a file with API_KEY"

# 11. The cost key is a FLOOR and is named as one, and SKILL.md quotes the name the
#     script actually prints. Registry-lag drift — a heredoc key with one prose
#     consumer — is this repo's named failure mode, so the two are asserted together.
[ "$(field finder_floor_ktokens_per_lens "$TMP/mod")" = "44" ] \
  || fail "finder_floor_ktokens_per_lens: expected 44 (2 finders x 22k) for small"
if run "$TMP/mod" | grep -q 'est_ktokens_per_lens'; then
  fail "the old est_ktokens_per_lens key is still emitted — it reads as a total, which it is not"
fi
SKILL_MD="$(dirname "$RESOLVER")/../SKILL.md"
if ! grep -q 'finder_floor_ktokens_per_lens' "$SKILL_MD"; then
  fail "SKILL.md does not name the cost key the resolver prints"
fi

# 12. The size class bounds what the FINDERS READ, so it is computed on the source
#     files, not on source+tests. A module is otherwise refused for being well tested:
#     echo_lab's lab_timeline measured 15,394 LOC (oversize, 0 finders) against 7,270
#     LOC of source (large, 4 finders) — 8,124 of those lines were its own tests.
#     `loc` keeps meaning the total; `source_loc` is the number the class comes from.
mkdir -p "$TMP/tested/tests"
awk 'BEGIN { for (i = 0; i < 1200; i++) print "x = " i }' > "$TMP/tested/app.py"
awk 'BEGIN { for (i = 0; i < 4000; i++) print "assert " i }' > "$TMP/tested/tests/test_app.py"
[ "$(field loc "$TMP/tested")" = "5200" ] || fail "loc must stay the total, got $(field loc "$TMP/tested")"
[ "$(field source_loc "$TMP/tested")" = "1200" ] || fail "source_loc: expected 1200, got $(field source_loc "$TMP/tested")"
[ "$(field size_class "$TMP/tested")" = "medium" ] \
  || fail "class must come from source_loc (1200 = medium), got $(field size_class "$TMP/tested") — a well-tested module was penalised by its tests"
[ "$(field loc "$TMP/tested")" != "$(field source_loc "$TMP/tested")" ] \
  || fail "loc and source_loc collapsed to one number — the distinction is the fix"

# 13. ...and the class must bound what is read, so --include-tests puts the tests back
#     in the reviewed set AND sizes on the total. Sizing on source while the finders
#     read tests would be a cost bound that does not bound the cost.
[ "$(field files "$TMP/tested")" = "1" ] || fail "default reviewed set must exclude tests, got $(field files "$TMP/tested") files"
[ "$(field files --include-tests "$TMP/tested")" = "2" ] || fail "--include-tests must add the test files back"
[ "$(field size_class --include-tests "$TMP/tested")" = "large" ] \
  || fail "--include-tests must size on the total (5200 = large), got $(field size_class --include-tests "$TMP/tested")"

# 14. A target that is ENTIRELY tests was named deliberately — excluding them would
#     resolve it to zero files and report exit 3, which reads as "nothing to review"
#     on a directory full of code. Measured against echo_lab: lab_timeline/tests is
#     46 files, all of them tests.
mkdir -p "$TMP/onlytests"
printf 'def test_a():\n    assert True\n' > "$TMP/onlytests/test_a.py"
printf 'def test_b():\n    assert True\n' > "$TMP/onlytests/test_b.py"
[ "$(run_code "$TMP/onlytests")" = "0" ] || fail "an all-tests target must resolve, not exit 3"
[ "$(field files "$TMP/onlytests")" = "2" ] || fail "an all-tests target must keep its files"

# 15. Test detection: the named conventions the first pass missed, and no false
#     positives. Measured against four real repos — the misses were __tests__/ helpers
#     with no .test/.spec suffix and conftest.py (2 of 118 test files; the rest of the
#     apparent misses were under .venv, already excluded as vendored).
mkdir -p "$TMP/conv/__tests__" "$TMP/conv/src"
printf 'x = 1\n' > "$TMP/conv/__tests__/helper.ts"
printf 'x = 1\n' > "$TMP/conv/conftest.py"
printf 'x = 1\n' > "$TMP/conv/src/latest.ts"
printf 'x = 1\n' > "$TMP/conv/src/protest_utils.py"
[ "$(field test_files "$TMP/conv")" = "2" ] \
  || fail "expected __tests__/helper.ts + conftest.py counted as tests, got $(field test_files "$TMP/conv")"
[ "$(field source_loc "$TMP/conv")" = "2" ] \
  || fail "latest.ts and protest_utils.py must NOT be read as tests (false positives), source_loc=$(field source_loc "$TMP/conv")"

# 16. --finders decouples depth from size. The size class was meant as a ceiling on
#     cost and had silently become the floor on depth: to get 4 finders you had to
#     point at something big, which is the opposite of what "review this small file
#     thoroughly" wants. /code-review scales its angles by EFFORT and treats diff size
#     as a precondition; we had the two swapped.
[ "$(field finders_per_lens --finders 4 "$TMP/mod")" = "4" ] \
  || fail "--finders 4 on a small target: expected 4, got $(field finders_per_lens --finders 4 "$TMP/mod")"
[ "$(field finder_floor_ktokens_per_lens --finders 4 "$TMP/mod")" = "88" ] \
  || fail "the cost floor must follow the override (4 x 22k), got $(field finder_floor_ktokens_per_lens --finders 4 "$TMP/mod")"
[ "$(field size_class --finders 4 "$TMP/mod")" = "small" ] \
  || fail "--finders must not rewrite the measured size class"

# 17. It is capped at the angle catalog's own maximum. Asking for 8 finders cannot
#     produce 8 angles — correctness has 4 in the catalog and security has 2 — so an
#     uncapped override would announce coverage the catalog cannot supply.
[ "$(field finders_per_lens --finders 9 "$TMP/mod")" = "4" ] \
  || fail "--finders must clamp to the catalog max of 4, got $(field finders_per_lens --finders 9 "$TMP/mod")"
[ "$(run_code --finders 0 "$TMP/mod")" = "2" ] || fail "--finders 0 must be a usage error"
[ "$(run_code --finders abc "$TMP/mod")" = "2" ] || fail "--finders abc must be a usage error"

# 18. It must NOT override the oversize refusal. Depth and admissibility are different
#     questions: if --finders could buy its way past oversize, the refusal that stops a
#     sample being reported as coverage would be one flag away from useless.
[ "$(field finders_per_lens --finders 4 "$TMP/big")" = "0" ] \
  || fail "--finders bought its way past the oversize refusal"
[ "$(field size_class --finders 4 "$TMP/big")" = "oversize" ] || fail "oversize must survive --finders"

if [ "$FAILURES" -eq 0 ]; then
  echo "OK — resolve-review-target: 18 cells (3 refusals, 2 exclusions, 3 measurements, 2 bounds, 1 cost-floor lockstep, 4 test-vs-source, 3 depth-override)"
  exit 0
fi
echo "FAIL — $FAILURES cell(s)"
exit 1
