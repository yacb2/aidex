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
echo "OK — request/decision close, superseded back-ref, refusals"
