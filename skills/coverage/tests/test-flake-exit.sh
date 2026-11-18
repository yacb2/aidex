#!/usr/bin/env bash
# test-flake-exit.sh — reference 15 section 9 keeps its exit for a flake with no race and
# no polluter: delete the test and write down why. Without it the section only offers
# retries and longer timeouts, which it names as the failure.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REF="${1:-$HERE/../references/15-green-that-proves-nothing.md}"
if ! grep -q 'No race and no polluter found: delete the test and write down why' "$REF"; then
  echo "FAIL: section 9 of $REF lost the delete-and-write-down exit"; exit 1
fi
echo "OK - flake section keeps the delete-and-write-down exit"
