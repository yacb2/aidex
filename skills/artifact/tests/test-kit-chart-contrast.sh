#!/usr/bin/env bash
# svg-contrast warns "no figure text could be measured" when it measured nothing.
# A spec-built page with a kit `chart` or `diagram` hit that on every build (LOOP-012:
# 9 of 31 runs): the kit emitters paint labels with currentColor on purpose, and the
# rendered contrast of those is render-probe's figure-text-contrast (6.02:1 light,
# 7.65:1 dark for the chart's ink at .7). The static check does not resolve
# currentColor, so it now leaves labels inside kit-drawn svgs (root class chart-w,
# chart-n, dg-wide, dg-narrow) out of the unmeasured count. Author SVG still counts.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
BUILD="$SKILL/scripts/spec_build.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

for spec in chart-sample chart-stacked diagram-sample; do
  python3 "$BUILD" "$SKILL/tests/fixtures/$spec.spec.md" -o "$TMP/$spec.html" >/dev/null 2>&1 \
    || fail "$spec: the fixture did not build"
  out="$(bash "$CHECK" "$TMP/$spec.html" 2>&1)"
  grep -q "svg-contrast" <<<"$out" \
    && fail "$spec: a kit-drawn figure raised svg-contrast: $out"
done

inject() {  # inject <svg markup> into the built chart page
  python3 - "$TMP/chart-sample.html" "$2" "$1" <<'P'
import sys
t = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write(t.replace('</main>', sys.argv[3] + '</main>', 1))
P
}

# Kit chart plus ONE author label the check cannot read: still warns, count 1.
inject '<svg viewBox="0 0 200 40" role="img" aria-label="x"><text x="5" y="20" font-size="12" fill="currentColor">author label</text></svg>' "$TMP/mixed.html"
out="$(bash "$CHECK" "$TMP/mixed.html" 2>&1)"
grep -q "WARN \[svg-contrast\].*measured 0 text node(s).*, 1 unmeasurable" <<<"$out" \
  || fail "kit chart + an author currentColor label lost its warning or its count: $out"

# Author-only page: unchanged, the whole count is the author's.
python3 - "$SKILL/tests/fixtures/chart-sample.spec.md" "$TMP/plain.spec.md" <<'P'
import re, sys
t = open(sys.argv[1]).read()
open(sys.argv[2], 'w').write(re.sub(r'::: chart.*?\n:::\n', '', t, flags=re.S))
P
python3 "$BUILD" "$TMP/plain.spec.md" -o "$TMP/plain.html" >/dev/null 2>&1 || fail "plain page did not build"
python3 - "$TMP/plain.html" "$TMP/author-only.html" <<'P'
import sys
t = open(sys.argv[1]).read()
svg = '<svg viewBox="0 0 200 40" role="img" aria-label="x"><text x="5" y="20" font-size="12" fill="currentColor">a</text><text x="5" y="35" font-size="12" fill="var(--ink)">b</text></svg>'
open(sys.argv[2], 'w').write(t.replace('</main>', svg + '</main>', 1))
P
out="$(bash "$CHECK" "$TMP/author-only.html" 2>&1)"
grep -q "WARN \[svg-contrast\].*measured 0 text node(s).*, 2 unmeasurable" <<<"$out" \
  || fail "author-only page changed its svg-contrast count: $out"

# Guard: a literal low-contrast author fill still FAILS in dark.
inject '<svg viewBox="0 0 200 40" role="img" aria-label="x"><text x="5" y="20" font-size="12" fill="#191D1A">author slate</text></svg>' "$TMP/slate.html"
out="$(bash "$CHECK" "$TMP/slate.html" 2>&1)"
grep -q "FAIL \[svg-contrast\].*'author slate'.*dark" <<<"$out" \
  || fail "author SVG with a literal low-contrast fill no longer fails: $out"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — kit-drawn figures do not trip svg-contrast; author SVG is still counted and judged"
