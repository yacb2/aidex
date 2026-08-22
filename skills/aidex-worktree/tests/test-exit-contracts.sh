#!/usr/bin/env bash
# test-exit-contracts.sh — two exit-code contracts this skill kept breaking.
#
# Both defects below were reported green by the full suite, which is the whole
# reason they are pinned here rather than left to review.
#
# 1. THE SKIP CONTRACT. run-all.sh counts a test as skipped only when it exits 2
#    AND prints a line starting with SKIP. A test that prints SKIP and exits 0 is
#    counted as a PASS — so a check that never ran is indistinguishable, in the
#    suite's own summary, from one that ran and held.
#
# 2. A PREDICATE THAT EXITS. `assert_services_running` in worktree.sh is called
#    two ways: `|| exit 2` from `up`, and `|| parity_rc=3` from `new`, whose
#    adjacent comment says the failure is deliberately reported AFTER the
#    worktree handle is printed. One of its failure branches called `exit 2`
#    directly, which bypasses that entirely and strands a half-finished worktree
#    — the exact failure the comment claims to have fixed.
#
#    This is checked at the CALL SITES as well as in the body, on purpose: a
#    body-level assertion once passed while `up`'s call site was uncovered.
#
# Run with: bash skills/aidex-worktree/tests/test-exit-contracts.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$DIR/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# --- 1. a test that announces SKIP must exit 2 ------------------------------
# Forced by stubbing docker to fail, which is the precondition every one of
# these tests declares. Whatever a test decides to do, the pairing is the rule:
# if it says SKIP, run-all.sh must be able to see that it skipped.
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
printf '#!/bin/sh\nexit 1\n' > "$STUB/docker"; chmod +x "$STUB/docker"

checked=0
for t in "$SKILL"/scripts/test-*.sh "$SKILL"/tests/test-*.sh; do
  [[ -f "$t" ]] || continue
  [[ "$(basename "$t")" == "$(basename "${BASH_SOURCE[0]}")" ]] && continue
  grep -q 'SKIP' "$t" || continue
  checked=$((checked + 1))
  out="$(PATH="$STUB:$PATH" bash "$t" 2>&1)"; rc=$?
  grep -q '^SKIP' <<<"$out" || continue      # it chose not to skip; nothing to assert
  [[ "$rc" -eq 2 ]] \
    || fail "$(basename "$t"): announced SKIP but exited $rc — run-all.sh counts that as a PASS"
done
[[ "$checked" -gt 0 ]] || fail "skip contract: examined 0 tests — the glob matched nothing"

# --- 2. assert_services_running must RETURN, never exit ---------------------
WT="$SKILL/scripts/worktree.sh"
start="$(grep -n '^assert_services_running()' "$WT" | cut -d: -f1)"
[[ -n "$start" ]] || fail "assert_services_running: function not found in worktree.sh"
if [[ -n "$start" ]]; then
  # The body runs to the first line that closes it at column 0.
  end="$(awk -v s="$start" 'NR>s && /^}/ {print NR; exit}' "$WT")"
  [[ -n "$end" ]] || fail "assert_services_running: could not find the closing brace"
  if [[ -n "$end" ]]; then
    bad="$(sed -n "${start},${end}p" "$WT" | grep -nE '^[[:space:]]*exit[[:space:]]' || true)"
    [[ -z "$bad" ]] \
      || fail "assert_services_running: a predicate must not exit; found:${bad//$'\n'/ }"
  fi
fi

# --- 3. and both call sites must handle its return code --------------------
# Named individually rather than counted: a count stays satisfied when one call
# site is deleted and another is duplicated.
grep -qE 'assert_services_running "\$DEST" \|\| exit 2' "$WT" \
  || fail "up's call site must be 'assert_services_running \"\$DEST\" || exit 2'"
grep -qE 'assert_services_running "\$DEST" \|\| parity_rc=3' "$WT" \
  || fail "new's call site must be 'assert_services_running \"\$DEST\" || parity_rc=3'"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — exit contracts: SKIP pairs with exit 2, and assert_services_running returns at both call sites"
