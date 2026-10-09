#!/usr/bin/env bash
# test-no-anchor-fallback-lockstep.sh — where a page with no anchor lands must be named on
# Route S, the default route, and not only in route-b.md § 6. LOOP-012 round 1: asked for a
# throwaway test page, an agent read Route S, found only "next to where the page will live"
# and built the spec and page at the project root.
#
# Layer: reference text — the failure is an agent reading a section that names no location.
#
# Run with: bash skills/artifact/tests/test-no-anchor-fallback-lockstep.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REFS="$HERE/../references"
STEM='.context/reports/YYYY-MM-DD-<slug>'
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# The Route S slice: from its heading to the next top-level heading (the slice
# artifact-sonnet reads, review_night_gate.py READING_SLICE).
slice="$(awk '/^## Route S/{on=1; print; next} on && /^## /{exit} on' "$REFS/02-local-first-artifacts.md")"
[[ -n "$slice" ]] || fail "02-local-first-artifacts.md has no '## Route S' heading — the slice moved"

grep -qF -- "$STEM" <<<"$slice" \
  || fail "02 § Route S never names the no-anchor location '$STEM' — a throwaway page lands at the project root"
grep -qF -- "$STEM" "$REFS/route-b.md" \
  || fail "route-b.md § 6 no longer names '$STEM' — the two routes disagree on the fallback"

[[ "$failures" -eq 0 ]] && echo "PASS: no-anchor fallback named on Route S and Route B" || { echo "FAILED: $failures"; exit 1; }
