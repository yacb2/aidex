#!/usr/bin/env bash
# test-close-dated-artifact.sh — lifecycle test for close-dated-artifact.sh in an
# isolated temp project: request close (default done), decision close (superseded
# with back-ref, dropped), status validation, not-found and double-close refusal.
#
# Run with: bash skills/aidex-conventions/scripts/test-close-dated-artifact.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/close-dated-artifact.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/requests" "$TMP/.context/decisions"
cd "$TMP"

mk() { # $1=path
  printf -- '---\ntitle: "t"\nstatus: %s\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\nbody\n' "$2" > "$1"
}
mk ".context/requests/2026-01-01-export-feature.md" open
mk ".context/decisions/2026-01-02-old-choice.md" accepted
mk ".context/decisions/2026-01-03-bad-idea.md" accepted

# request: default done
out="$(bash "$SCRIPT" requests export-feature 2>/dev/null)" || fail "request close exited non-zero"
[[ "$out" == CLOSED*"_archive/2026-01-01-export-feature.md" ]] || fail "request: expected CLOSED archive path, got: $out"
grep -q "^status: done" ".context/requests/_archive/2026-01-01-export-feature.md" || fail "request: status not done"
grep -q "^updated: $(date +%F)" ".context/requests/_archive/2026-01-01-export-feature.md" || fail "request: updated not stamped"

# decision: superseded requires --superseded-by
bash "$SCRIPT" decisions old-choice --status superseded >/dev/null 2>&1 && fail "decision: superseded without --superseded-by should fail"
bash "$SCRIPT" decisions old-choice --status superseded --superseded-by decision/2026-07-02-new-choice >/dev/null 2>&1 || fail "decision superseded close exited non-zero"
grep -q "^superseded_by: decision/2026-07-02-new-choice" ".context/decisions/_archive/2026-01-02-old-choice.md" || fail "decision: superseded_by not written"

# decision: dropped; decisions require explicit status
bash "$SCRIPT" decisions bad-idea >/dev/null 2>&1 && fail "decision: close without --status should fail"
bash "$SCRIPT" decisions bad-idea --status dropped >/dev/null 2>&1 || fail "decision dropped close exited non-zero"
grep -q "^status: dropped" ".context/decisions/_archive/2026-01-03-bad-idea.md" || fail "decision: status not dropped"

# refusals: bad status, not found, double close
bash "$SCRIPT" requests whatever --status accepted >/dev/null 2>&1 && fail "requests: invalid status accepted should fail"
bash "$SCRIPT" requests no-such-slug >/dev/null 2>&1 && fail "not-found should exit non-zero"
bash "$SCRIPT" requests export-feature >/dev/null 2>&1 && fail "double close should fail (already archived / not found in active)"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi

# --- the EXACT filename resolves, not only a fragment -----------------------
# The lookup was `ls "$DIR/"*"$ARG"*.md`, so passing the full filename — the form every
# error message and every directory listing prints — expanded to `*<name>.md*.md` and
# matched nothing. Field-hit 2026-09-07 while closing a superseded ADR by the name the
# validator had just printed.
mk ".context/decisions/2026-02-02-exact-name.md" accepted
bash "$SCRIPT" decisions 2026-02-02-exact-name.md --status superseded \
  --superseded-by decision/2026-02-03-other.md >/dev/null 2>&1
[[ -f ".context/decisions/_archive/2026-02-02-exact-name.md" ]] \
  || fail "the exact filename did not resolve — the glob was *\$ARG*.md, so <name>.md matched nothing"

# The gate. Without it this file ended on an unconditional `echo`, so it printed OK and
# exited 0 with failures on screen — a suite that cannot fail, which is worse than no
# suite because the sweep that runs it reports green. Found 2026-09-07 while adding the
# exact-filename cell above: the FAIL line printed and the run still passed.
if [[ "$failures" -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
echo "OK — request/decision close, superseded back-ref, refusals"
