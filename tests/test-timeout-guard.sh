#!/usr/bin/env bash
# test-timeout-guard.sh — the eval harness must be BOUNDED on the platform it runs on.
#
# `eval-local-first-behavior.sh` drives real headless `claude -p` sessions and
# documents a 600s cap per scenario. The cap resolved as
# `timeout` -> `gtimeout` -> **run bare**, and this repo's own machine has
# neither binary: macOS ships no GNU coreutils. So the documented bound silently
# did not exist, and a scenario that never returns hung until something outside
# killed it — observed 2026-08-17, killed at 10 minutes with no output.
#
# That is this repo's named failure mode, "checkers lie by omission": a guard
# whose absent branch is indistinguishable from a guard that passed. The fix is a
# fallback that cannot be absent — perl ships with macOS and every Linux — so
# this pins BOTH halves: the helper really interrupts, and no branch runs unbounded.
#
# Run with: bash tests/test-timeout-guard.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMO="$REPO_ROOT/tests/lib/tmo.pl"
EVAL_SH="$REPO_ROOT/tests/eval-local-first-behavior.sh"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

# --- the portable fallback exists and actually bounds a run -------------------
if [[ -f "$TMO" ]]; then
  ok "a portable timeout helper is shipped (tests/lib/tmo.pl)"
else
  bad "no portable timeout helper — the 600s cap depends on a binary macOS lacks"
fi

if [[ -f "$TMO" ]]; then
  start=$(date +%s)
  perl "$TMO" 2 sleep 30 >/dev/null 2>&1
  rc=$?
  elapsed=$(( $(date +%s) - start ))
  [[ $rc -eq 124 ]] && ok "it interrupts an over-running command with exit 124" \
                    || bad "a 30s sleeper under a 2s cap exited $rc, not 124"
  [[ $elapsed -lt 10 ]] && ok "it interrupts at the cap, not after the command finishes ($elapsed s)" \
                        || bad "the cap did not fire: $elapsed s elapsed"

  # A timeout wrapper that eats the child's exit code turns every failing
  # scenario into a passing one, which is worse than having no wrapper.
  perl "$TMO" 30 sh -c 'exit 7' >/dev/null 2>&1
  [[ $? -eq 7 ]] && ok "it passes the child's exit code through" \
                 || bad "the child's exit code was not preserved"

  out="$(perl "$TMO" 30 printf 'hello' 2>/dev/null)"
  [[ "$out" == "hello" ]] && ok "it passes the child's stdout through" \
                          || bad "stdout was swallowed: '$out'"

  perl "$TMO" 30 /no/such/binary >/dev/null 2>&1
  [[ $? -ne 0 ]] && ok "a missing command is a failure, not a silent pass" \
                 || bad "an unrunnable command exited 0"
fi

# --- and no branch of the eval may run unbounded ------------------------------
# Anchored on the mechanism (an assignment that empties the runner), not on prose.
if [[ ! -f "$EVAL_SH" ]]; then
  bad "eval-local-first-behavior.sh not found"
else
  if grep -qE '^\s*else\s+TO=""' "$EVAL_SH"; then
    bad "the eval still falls back to running UNBOUNDED when no timeout binary exists"
  else
    ok "no unbounded fallback branch remains"
  fi
  if grep -q "tmo.pl" "$EVAL_SH"; then
    ok "the eval uses the portable helper as its floor"
  else
    bad "the eval does not reference the portable helper — its cap is still binary-dependent"
  fi
fi

echo
echo "timeout guard: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
