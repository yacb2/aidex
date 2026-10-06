#!/usr/bin/env bash
# test-no-bare-mktemp.sh — skill scripts create temp files under $TMPDIR, never with
# a bare `mktemp`.
#
# Regression (BL-704, 2026-10-06): on macOS a bare `mktemp` ignores TMPDIR and always
# writes under /var/folders/.../T/. The Claude Code sandbox denies that path, so
# reindex-audits.sh and reindex-plans.sh died on `mkstemp failed ... Operation not
# permitted` and never wrote their 00-index.md (0/3 runs each in the r4 eval sweep).
#
#   (a) static: no shipped script calls `mktemp` without a template
#   (b) behaviour: both reindex scripts write their index when only $TMPDIR is
#       writable — a PATH shim stands in for the sandbox and refuses any call
#       without a template, which is what lands outside TMPDIR on macOS.
#
# Run with: bash tests/test-no-bare-mktemp.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# (a) Shipped scripts only: tests, evals and fixtures may use bare mktemp freely.
hits="$(grep -rnE 'mktemp( -d)?\)' "$REPO_ROOT/skills" "$REPO_ROOT/hooks" \
  | grep -vE '/tests?/|/test[-_][^/]*:|/evals?/|/fixtures/')"
[ -z "$hits" ] || fail "bare mktemp in shipped scripts:
$hits"

# (b) Sandbox stand-in.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/tmpdir"
REAL_MKTEMP="$(command -v mktemp)"
cat > "$TMP/bin/mktemp" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in */*) exec "$REAL_MKTEMP" "\$@" ;; esac; done
echo "mktemp: mkstemp failed on /var/folders/x/T/tmp.XXXX: Operation not permitted" >&2
exit 1
EOF
chmod +x "$TMP/bin/mktemp"

run_reindex() {  # $1 = kind (plans|audits), $2 = script
  local p="$TMP/$1"
  mkdir -p "$p/.context/$1"
  (cd "$p" && PATH="$TMP/bin:$PATH" TMPDIR="$TMP/tmpdir" bash "$2" >/dev/null 2>"$TMP/$1.err")
  [ -f "$p/.context/$1/00-index.md" ] \
    || fail "$1 index not written under sandboxed TMPDIR: $(cat "$TMP/$1.err")"
}
run_reindex plans "$REPO_ROOT/skills/plan/scripts/reindex-plans.sh"
run_reindex audits "$REPO_ROOT/skills/audit/scripts/reindex-audits.sh"

if [ "$failures" -eq 0 ]; then echo "PASS: test-no-bare-mktemp (static + 2 sandboxed reindexes)"; exit 0; fi
echo "FAILED: $failures"; exit 1
