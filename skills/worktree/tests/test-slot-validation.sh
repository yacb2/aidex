#!/usr/bin/env bash
# test-slot-validation.sh — the slot number is an untrusted value that reaches
# a bash ARITHMETIC context, and it was never validated.
#
# port_env computes `$(( base + slot * WT_PORT_STRIDE ))`. Arithmetic evaluation
# performs command substitution on its operands, so a slot carrying `$(...)`
# executes it. The slot arrives from three places, none of them a person typing
# a digit: the `--slot` flag, the `$DEST/.wt-slot` file, and the BASENAME of a
# claim file under a shared /tmp directory.
#
# Separately, `--slot 0` was accepted as a number. Slot 0 is the main tree: the
# worktree is handed dev's exact ports and writes them into its own .env.
#
# Every fixture below runs with its own TMPDIR, so no real project's slot claims
# are read or written. No daemon is needed: every case must be refused before
# the script reaches Docker.
#
# Run with: bash skills/worktree/tests/test-slot-validation.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PROJ="$TMP/slotproj"
mkdir -p "$PROJ/.context/worktrees" "$PROJ/backend/.git"
cat > "$PROJ/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_PORT_VARS="DB_PORT=6400 BACKEND_PORT=6401"
WT_PORT_STRIDE=100
WT_MAX_SLOTS=4
ENV

run_wt() {  # run_wt <args...> -> prints output, sets RC
  local slots="$TMP/slots"; mkdir -p "$slots"
  out="$( cd "$PROJ" && TMPDIR="$slots" bash "$WT" "$@" 2>&1 )"; RC=$?
}

# These assertions are deliberately NOT "rc is non-zero". The fixture fails later
# anyway (no real git repo), so a bare rc check passes whether or not the slot was
# ever validated -- an assertion that cannot fail, which is the defect class this
# whole review turned on. Each case asserts the refusal MESSAGE, and asserts that
# the ports for the bad slot were never computed.

# --- 1. slot 0 is the MAIN tree, never a worktree ---------------------------
run_wt new zero-slot --branch wt/zero --slot 0
grep -q 'must be an integer in 1\.\.' <<<"$out" \
  || fail "slot 0: must be refused with the valid range, got: $out"
grep -q 'DB_PORT=6400' <<<"$out" \
  && fail "slot 0: the main tree's own dev ports were handed to a worktree"

# --- 2. a slot beyond WT_MAX_SLOTS is refused -------------------------------
run_wt new big-slot --branch wt/big --slot 99
grep -q 'must be an integer in 1\.\.' <<<"$out" \
  || fail "slot 99: must be refused against WT_MAX_SLOTS=4, got: $out"
grep -q 'slot 99 ->' <<<"$out" \
  && fail "slot 99: an out-of-range slot was allocated anyway"

# --- 2b. BL-776: 2^64+1 wraps to 1 in bash arithmetic; 03 is not slot 3 -----
# (its claim file would be slot-03, never found by a lookup of slot-3).
for bad in 18446744073709551617 03; do
  run_wt new wrap-slot --branch wt/wrap --slot "$bad"
  grep -q "invalid --slot '$bad': must be an integer in 1\.\." <<<"$out" \
    || fail "slot $bad: must be refused with the valid range, got: $out"
done

# --- 3. a non-numeric slot must never reach arithmetic ----------------------
# `$(( base + slot * stride ))` is a code-execution sink, but not via the naive
# `$(cmd)` payload -- bash rejects that as "operand expected" without running it.
# The form that DOES run is an array subscript: `a[$(cmd)]` is substituted during
# arithmetic evaluation, verified directly. That is the payload used here, and it
# is why "the operand is not a bare $(...)" is not a defence.
MARKER="pwned"
run_wt new inject-slot --branch wt/inject --slot 'a[$(touch '"$MARKER"')]'
[[ ! -e "$PROJ/$MARKER" ]] || fail "injection: a --slot payload EXECUTED — $PROJ/$MARKER was created"
[[ "$RC" -ne 0 ]] || fail "injection: a non-numeric slot must be refused, got rc=0: $out"

# --- 4. a claim file with a non-numeric name is not a slot ------------------
# CLAIMED_SLOT returns `basename` minus the `slot-` prefix, so a file planted in
# the shared /tmp claim directory supplies the arithmetic operand directly.
slots="$TMP/slots/aidex-wt-slots-slotproj"
mkdir -p "$slots" || fail "claim: could not create $slots"
# The payload carries no slash: it becomes part of a FILENAME.
printf '%s %s\n' "$$" "claimed-slug" > "$slots/slot-a[\$(touch pwned2)]"
run_wt list
[[ ! -e "$PROJ/pwned2" ]] || fail "claim: a planted claim FILENAME executed — $PROJ/pwned2 was created"
rm -f "$slots"/slot-*

# --- 5. worktree-c08: `up` validates the slot it READS, not only --slot ------
# `up` took $DEST/.wt-slot (or the claim) as-is: 0 handed the worktree dev's own
# ports and wrote a slot-0 claim, an array-subscript payload executed, and an
# EMPTY file -- what `new --no-infra` writes -- suppressed the claim fallback.
# Docker is stubbed: the valid case starts a (stub) stack and must exit 0.
UPBIN="$TMP/upbin"; mkdir -p "$UPBIN"
printf '#!/bin/sh\nexit 0\n' > "$UPBIN/docker"; chmod +x "$UPBIN/docker"
SD="$TMP/slots/aidex-wt-slots-slotproj"; mkdir -p "$SD"
D="$TMP/slotproj-wt-rs"; mkdir -p "$D"
run_up() { out="$( cd "$PROJ" && TMPDIR="$TMP/slots" PATH="$UPBIN:$PATH" bash "$WT" up rs 2>&1 )"; RC=$?; }

echo 0 > "$D/.wt-slot"
run_up
[[ "$RC" -eq 2 ]] || fail "up .wt-slot=0: must exit 2, got $RC: $out"
grep -q "error: invalid slot '0' in $D/.wt-slot: must be an integer in 1\.\.4" <<<"$out" \
  || fail "up .wt-slot=0: must be refused naming the file and the range: $out"
[[ ! -e "$SD/slot-0" ]] || fail "up .wt-slot=0: a slot-0 claim was written for the main tree's ports"

printf '%s\n' 'WT_PORT_STRIDE[$(touch pwned3)]' > "$D/.wt-slot"
run_up
[[ ! -e "$PROJ/pwned3" ]] || fail "up .wt-slot payload: it EXECUTED -- $PROJ/pwned3 was created"
[[ "$RC" -eq 2 ]] || fail "up .wt-slot payload: must exit 2, got $RC: $out"
grep -q "error: invalid slot 'WT_PORT_STRIDE\[" <<<"$out" || fail "up .wt-slot payload: must be refused as an invalid slot: $out"

echo 5 > "$D/.wt-slot"   # above WT_MAX_SLOTS=4: the upper bound, not only 0
run_up
[[ "$RC" -eq 2 ]] || fail "up .wt-slot=5: must exit 2, got $RC: $out"
grep -q "error: invalid slot '5' in $D/.wt-slot: must be an integer in 1\.\.4" <<<"$out" \
  || fail "up .wt-slot=5: must be refused against WT_MAX_SLOTS=4: $out"
[[ ! -e "$SD/slot-5" ]] || fail "up .wt-slot=5: a claim beyond WT_MAX_SLOTS was written"

: > "$D/.wt-slot"; printf '%s rs\n' "$$" > "$SD/slot-2"
run_up
[[ "$RC" -eq 0 ]] || fail "up empty .wt-slot: must fall back to the claim and exit 0, got $RC: $out"
grep -q 'stack up: slotproj-wt-rs (slot 2)' <<<"$out" || fail "up empty .wt-slot: must resume on the claimed slot 2: $out"
rm -f "$SD"/slot-*

# BL-776: a .wt-slot that is not a slot falls back to the claim, the way `list`
# reads it; the refusals above are for "neither source is a slot".
echo abc > "$D/.wt-slot"; printf '%s rs\n' "$$" > "$SD/slot-2"
run_up
[[ "$RC" -eq 0 ]] || fail "up .wt-slot=abc with claim 2: must fall back to the claim and exit 0, got $RC: $out"
grep -q 'stack up: slotproj-wt-rs (slot 2)' <<<"$out" || fail "up .wt-slot=abc: must resume on the claimed slot 2: $out"
[[ "$(cat "$D/.wt-slot")" == 2 ]] \
  || fail "up .wt-slot=abc: .wt-slot must be rewritten to the claimed slot 2, reads '$(cat "$D/.wt-slot")'"
rm -f "$SD"/slot-*

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — slot validation: 0 and out-of-range refused, no non-numeric slot reaches arithmetic, and up validates the slot it reads"
