#!/usr/bin/env bash
# The property-test guidance is optional advice that lives in two places: the reviewer's
# step 5 and the coverage best-practices reference. Each must name the four shapes, and the
# reference must also name both libraries and point at the in-house example, so an edit that
# drops one of them fails here.
#
# Run with: bash tests/test-property-test-guidance.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REVIEWER="${REVIEWER:-$ROOT/agents/review-diff-opus.md}"
BEST="${BEST:-$ROOT/skills/coverage/references/02-best-practices.md}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

for f in "$REVIEWER" "$BEST"; do
  [[ -f "$f" ]] || { err "missing $f"; continue; }
  for shape in 'round trip' 'invariant' 'idempotency' 'equivalence'; do
    grep -qi "$shape" "$f" || err "$(basename "$f") does not name the shape '$shape'"
  done
done
if [[ -f "$BEST" ]]; then
  for lib in Hypothesis fast-check rounds_gate.py; do
    grep -q "$lib" "$BEST" || err "$(basename "$BEST") does not name '$lib'"
  done
fi

[[ $fail -eq 0 ]] && echo "PASS: reviewer and best-practices name the four property shapes; best-practices names both libraries" || exit 1
