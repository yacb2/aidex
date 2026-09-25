#!/usr/bin/env bash
# test-render-probe.sh — render-probe.sh fails each defect fixture with the right
# class and names the element, passes the clean one, writes both screenshots, keeps
# its two exemptions honest in both directions (consult-bar), exits 3 with the install
# command when Playwright or its Chromium cannot be found, and exits 4 (not 1, not 0)
# when the probe itself crashes.
#
# The .html fixtures under fixtures/render-probe/ are page BODIES; each is wrapped
# here with the real wrap-report.sh, so every run probes a page carrying the current
# kit rather than a frozen copy of an old one. The .spec.md ones are built with
# spec_build.py, which wraps them itself.
#
# The exit-3 case runs always. The rest needs Playwright (AIDEX_PLAYWRIGHT_DIR or a
# global install); without it the test prints SKIP and exits 2, which run-all.sh
# reports as a skip, never as a pass.
#
# Run with: bash skills/artifact/tests/test-render-probe.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd -P)"
PROBE="$SCRIPTS/render-probe.sh"
FIX="$HERE/fixtures/render-probe"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== Playwright missing =="
# Both lookups pointed at nothing: no AIDEX_PLAYWRIGHT_DIR hit and an npm prefix
# whose global root is empty.
out="$(AIDEX_PLAYWRIGHT_DIR="$TMP/none" npm_config_prefix="$TMP/none" bash "$PROBE" "$FIX/clean.html" 2>&1)"; rc=$?
[[ $rc -eq 3 ]] && ok "exits 3 without Playwright" || bad "exit $rc without Playwright, expected 3"
grep -q 'npm i -g playwright' <<<"$out" && ok "prints the install command" || bad "no install command in: $out"

# Is Playwright reachable the way the wrapper looks for it?
have=0
[[ -n "${AIDEX_PLAYWRIGHT_DIR:-}" && -f "$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright/package.json" ]] && have=1
g="$(npm root -g 2>/dev/null || true)"
[[ -n "$g" && -f "$g/playwright/package.json" ]] && have=1
if [[ $have -eq 0 ]]; then
  echo "SKIP: Playwright not found (set AIDEX_PLAYWRIGHT_DIR or npm i -g playwright); only the exit-3 case ran ($PASS ok, $FAIL failed)"
  [[ $FAIL -eq 0 ]] && exit 2 || exit 1
fi

echo "== wrap the fixtures with the kit =="
# From an empty directory, so no project style profile is picked up.
for f in "$FIX"/*.html; do
  n="$(basename "$f" .html)"
  ( cd "$TMP" && bash "$SCRIPTS/wrap-report.sh" --title "$n" --lang es --in "$f" --out "$TMP/$n.html" ) >/dev/null 2>&1 \
    && ok "wrapped $n" || bad "wrap-report failed on $n"
done

echo "== clean page =="
out="$(bash "$PROBE" --shots "$TMP/shots" "$TMP/clean.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "clean fixture exits 0" || bad "clean fixture exit $rc: $out"
[[ -s "$TMP/shots/clean-1280.png" && -s "$TMP/shots/clean-390.png" ]] \
  && ok "--shots writes clean-1280.png and clean-390.png" || bad "--shots did not write both screenshots"
[[ "$(grep -c '^{' <<<"$out")" -eq 2 ]] && ok "one JSON line per width" || bad "expected 2 JSON lines: $out"

echo "== a chart built from a spec: the F-shape data =="
# Four bands x three series, -36.23 .. +272.87: the chart whose arm-B build cut
# its tick labels at the svg edge. Built by spec_build.py (a kit-wrapped page),
# never frozen, so the probe always sees what chart_svg.py draws today.
( cd "$TMP" && python3 "$SCRIPTS/spec_build.py" "$FIX/chart-f5.spec.md" -o "$TMP/chart-f5.html" ) >/dev/null 2>&1 \
  && ok "built chart-f5 from its spec" || bad "spec_build.py failed on chart-f5.spec.md"
out="$(bash "$PROBE" --shots "$TMP/shots" "$TMP/chart-f5.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "the F-shape chart is clean at 1280 and 390 px" || bad "chart-f5 exit $rc: $out"
[[ -s "$TMP/shots/chart-f5-1280.png" && -s "$TMP/shots/chart-f5-390.png" ]] \
  && ok "--shots writes chart-f5-1280.png and chart-f5-390.png" || bad "no chart-f5 screenshots"

echo "== a chart whose names have no space to break at =="
# A 48-character model id as a series name, a URL as y-title, a long category
# label and twelve months: each ran past the 300-unit narrow svg or lost a label
# before the review round.
( cd "$TMP" && python3 "$SCRIPTS/spec_build.py" "$FIX/chart-long-word.spec.md" -o "$TMP/chart-long-word.html" ) >/dev/null 2>&1 \
  && ok "built chart-long-word from its spec" || bad "spec_build.py failed on chart-long-word.spec.md"
out="$(bash "$PROBE" "$TMP/chart-long-word.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "the long-word chart is clean at 1280 and 390 px" || bad "chart-long-word exit $rc: $out"

echo "== the kit's own rows pass clean (must-pass, Phase 5) =="
# kit-rows.html is B-R-2's key/value ledger, the same ledger at 390 px, long
# unbreakable paths in a list and in prose, and a page taller than the viewport.
# Each of the four kit rules it guards was verified load-bearing by mutation
# (2026-09-25): back to minmax(20rem, 1fr) -> div.ledger content-spills @390;
# no overflow-wrap on p/li -> li and p content-spills @390; the key/value rules
# back to theirs (key shrinks to 1.8rem and cannot wrap, value has no 60% floor)
# -> span.k text-overlap; the theme pill fixed bottom-left again
# -> fixed-over-text at both widths.
out="$(bash "$PROBE" --shots "$TMP/shots" "$TMP/kit-rows.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "kit-rows fixture exits 0" || bad "kit-rows fixture exit $rc: $(grep '^DEFECT' <<<"$out")"
[[ -s "$TMP/shots/kit-rows-1280.png" && -s "$TMP/shots/kit-rows-390.png" ]] \
  && ok "--shots writes kit-rows-1280.png and kit-rows-390.png" || bad "no kit-rows screenshots"

echo "== crash and missing browser =="
# A page that breaks the measuring code: getComputedStyle is gone, so evaluate throws.
printf '<!doctype html><title>x</title><p>x</p><script>window.getComputedStyle = null</script>' > "$TMP/crash.html"
out="$(bash "$PROBE" "$TMP/crash.html" 2>&1)"; rc=$?
[[ $rc -eq 4 ]] && ok "a crash while measuring exits 4" || bad "crash exit $rc, expected 4: $out"
grep -q 'CRASH' <<<"$out" && ok "a crash says CRASH" || bad "no CRASH message in: $out"
mkdir -p "$TMP/no-browsers"
out="$(PLAYWRIGHT_BROWSERS_PATH="$TMP/no-browsers" bash "$PROBE" "$TMP/clean.html" 2>&1)"; rc=$?
[[ $rc -eq 3 ]] && ok "Playwright without its Chromium exits 3" || bad "no-browser exit $rc, expected 3: $out"
grep -q 'npx playwright install chromium' <<<"$out" && ok "prints the browser install command" || bad "no browser install command in: $out"

echo "== one fixture per defect class =="
# <fixture> <class> <text that names the offending element> <width>
while read -r fx class elem width; do
  out="$(bash "$PROBE" "$TMP/$fx.html" 2>&1)"; rc=$?
  [[ $rc -eq 1 ]] && ok "$fx exits 1" || bad "$fx exit $rc, expected 1"
  if grep -E "^DEFECT $fx\.html @${width}px $class: " <<<"$out" | grep -qF "$elem"; then
    ok "$fx: $class at ${width}px names $elem"
  else
    bad "$fx: no '$class' at ${width}px naming $elem in: $out"
  fi
done <<'EOF'
svg-clipped svg-text-clipped "272.87 1280
text-overlap text-overlap span.k 1280
spill content-spills div.boxfix 390
fixed-over fixed-over-text button.fixfix 1280
hscroll page-hscroll svg.hsfix 390
fixed-internal text-overlap span.tb1 390
fixed-hanging fixed-over-text span.lblfix 390
cut-and-spill content-cut div.cutfix 1280
cut-and-spill content-spills div.nwfix 1280
consult-bar text-overlap span.b1 390
consult-bar text-overlap p.railhead 1280
EOF

echo "== the consultation bar exemption does not hide body text only =="
# At 390 the body runs under the bottom-pinned bar; the only 390 overlap allowed is the
# pair drawn inside the bar. Verified load-bearing: without the exemption, body
# paragraphs are reported against both bar labels here.
out="$(bash "$PROBE" "$TMP/consult-bar.html" 2>&1)"
n390="$(grep -c '^DEFECT consult-bar\.html @390px text-overlap: ' <<<"$out")"
nbar="$(grep '^DEFECT consult-bar\.html @390px text-overlap: ' <<<"$out" | grep -c 'span.b1 .* over span.b2 ')"
[[ $n390 -eq 1 && $nbar -eq 1 ]] && ok "at 390 px body under the bar is not flagged, the in-bar pair is" \
  || bad "at 390 px expected exactly the in-bar overlap, got: $(grep '@390px' <<<"$out")"

echo "== usage =="
bash "$PROBE" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "no page exits 2" || bad "no page exit $rc, expected 2"
bash "$PROBE" "$TMP/missing.html" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "missing page exits 2" || bad "missing page exit $rc, expected 2"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
