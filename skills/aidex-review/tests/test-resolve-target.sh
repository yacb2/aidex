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
files="$(field files "$TMP/mod")"
[ "$files" = "2" ] || fail "file count: expected 2 (app.py, tests/test_app.py), got '$files'"
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

if [ "$FAILURES" -eq 0 ]; then
  echo "OK — resolve-review-target: 11 cells (3 refusals, 2 exclusions, 3 measurements, 2 bounds, 1 cost-floor lockstep)"
  exit 0
fi
echo "FAIL — $FAILURES cell(s)"
exit 1
