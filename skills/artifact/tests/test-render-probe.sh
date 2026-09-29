#!/usr/bin/env bash
# test-render-probe.sh — render-probe.sh fails each defect fixture with the right
# class and names the element, passes the clean one, writes both screenshots, keeps
# its two exemptions honest in both directions (consult-bar), runs each render contract
# class (--contract) on a failing and a passing fixture, exits 3 with the install
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

echo "== a gallery consultation, built the normal route =="
# Rows JSON -> gallery-items.sh -> body -> wrap-report.sh, over real PNGs at the
# sizes a project captures (1600x900 desktop, 390x844 phone), written here so no
# binary is committed. What it guards is the kit's gallery layout itself: the
# before/after pair, the new-screen single capture, the phone cap on a mobile
# variant and the unrequested marker, none of which any other fixture draws.
GROOT="$TMP/gallery-root"
for d in shots actual; do for cell in with-data empty; do
  for t in light-desktop dark-desktop; do
    mkdir -p "$GROOT/$d/$t" && python3 "$HERE/png_fixture.py" "$GROOT/$d/$t/audit-$cell.png" 1600 900
  done
  for t in light-mobile dark-mobile; do
    mkdir -p "$GROOT/$d/$t" && python3 "$HERE/png_fixture.py" "$GROOT/$d/$t/audit-$cell.png" 390 844
  done
done; done
if bash "$SCRIPTS/gallery-items.sh" "$FIX/gallery/rows.json" --root "$GROOT" --page "$TMP/gallery.html" \
     --group-id E --group-title "Galería audit" > "$TMP/gallery-group.html" 2>"$TMP/gallery-gen.err"; then
  ok "generated the gallery block from rows.json"
else
  bad "gallery-items.sh refused the fixture: $(cat "$TMP/gallery-gen.err")"
fi
python3 - "$FIX/gallery/frame.html" "$TMP/gallery-group.html" "$TMP/gallery-body.html" <<'PY'
import sys
frame, group = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
open(sys.argv[3], "w", encoding="utf-8").write(frame.replace("<!-- GALLERY -->", group))
PY
( cd "$TMP" && bash "$SCRIPTS/wrap-report.sh" --title "Galería" --lang es --in "$TMP/gallery-body.html" --out "$TMP/gallery.html" ) >/dev/null 2>&1 \
  && ok "wrapped the gallery consultation (contract OK)" || bad "wrap-report failed on the gallery consultation"
out="$(bash "$PROBE" --shots "$TMP/shots" "$TMP/gallery.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "the gallery consultation is clean at 1280 and 390 px" || bad "gallery exit $rc: $out"
[[ -s "$TMP/shots/gallery-1280.png" && -s "$TMP/shots/gallery-390.png" ]] \
  && ok "--shots writes gallery-1280.png and gallery-390.png" || bad "no gallery screenshots"

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

echo "== a path with no space to break at, in every kit box that carries prose =="
# A code path inside an item's h3 and inside the {recommended} option spilled at
# 390 px, and inside a verdict caption (small) at 1280 px: only p and li could
# break a word anywhere. The page h1 and the group/section h2 spilled the same way
# at 390 px (kit 30). The table cell, the callout and the bare-text div.note did
# not spill when this was written; their cells guard them. Built by spec_build.py,
# so the probe sees today's kit.
( cd "$TMP" && python3 "$SCRIPTS/spec_build.py" "$FIX/long-token.spec.md" -o "$TMP/long-token.html" ) >/dev/null 2>&1 \
  && ok "built long-token from its spec" || bad "spec_build.py failed on long-token.spec.md"
out="$(bash "$PROBE" "$TMP/long-token.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "the long-token page is clean at 1280 and 390 px" || bad "long-token exit $rc"
while read -r width elem; do
  hit="$(grep -E "^DEFECT long-token\.html @${width}px content-spills: $elem " <<<"$out" || true)"
  [[ -z "$hit" ]] && ok "no $elem spill at ${width}px" || bad "$hit"
done <<'EOF'
390 h3
390 div.opts
1280 small
390 h1
1280 h1
390 h2
1280 h2
390 td
1280 td
390 div.callout
1280 div.callout
390 div.note
1280 div.note
EOF

echo "== rail entries scrolled out of the index are not over the copy bar (BL-522.4) =="
# 24 items: at 1280x900 the rail's list scrolls inside its box, and the entries
# below its edge sit, unseen, under "Copiar mis respuestas" and the build line.
# The probe reported them as text-overlap (asset_lab BL-011: "Encontrado de paso"
# over the copy button at y=796); the screenshot shows the list clipped cleanly.
( cd "$TMP" && python3 "$SCRIPTS/spec_build.py" "$FIX/long-rail.spec.md" -o "$TMP/long-rail.html" ) >/dev/null 2>&1 \
  && ok "built long-rail from its spec" || bad "spec_build.py failed on long-rail.spec.md"
module="${AIDEX_PLAYWRIGHT_DIR:-}/node_modules/playwright"
[[ -f "$module/package.json" ]] || module="$g/playwright"
scrolls="$(PW="$module" node -e '
const { chromium } = require(process.env.PW);
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.goto("file://" + process.argv[1]);
  console.log(await p.evaluate(() => { const l = document.querySelector(".rail .raillist"); return l.scrollHeight > l.clientHeight + 100; }));
  await b.close();
})();' "$TMP/long-rail.html" 2>&1)"
[[ "$scrolls" == true ]] && ok "the fixture's rail list scrolls at 1280x900 (precondition)" || bad "the rail list does not scroll: $scrolls"
out="$(bash "$PROBE" "$TMP/long-rail.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "long-rail is clean at 1280 and 390 px" || bad "long-rail exit $rc: $(grep '^DEFECT' <<<"$out")"

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

echo "== a diagram built from a spec (must pass clean) =="
# The F-shape flow, built by the real spec_build.py so the page carries today's
# diagram renderer: lr at 1280, its tb twin at 390. Clean at both widths, and the
# drawn text measured in the browser: at least 11 px at 390, at most the 17 px body
# at 1280, in the kit's sans font, the narrow twin the one shown at 390.
( cd "$TMP" && python3 "$SCRIPTS/spec_build.py" "$FIX/diagram-flow.spec.md" -o "$TMP/diagram-flow.html" ) >/dev/null 2>&1 \
  && ok "built diagram-flow from its spec" || bad "spec_build failed on diagram-flow.spec.md"
out="$(bash "$PROBE" --shots "$TMP/shots" "$TMP/diagram-flow.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "diagram-flow exits 0 at 1280 and 390" || bad "diagram-flow exit $rc: $out"
[[ -s "$TMP/shots/diagram-flow-1280.png" && -s "$TMP/shots/diagram-flow-390.png" ]] \
  && ok "--shots writes both diagram-flow screenshots" || bad "no diagram-flow screenshots"
module="${AIDEX_PLAYWRIGHT_DIR:-}/node_modules/playwright"
[[ -f "$module/package.json" ]] || module="$g/playwright"
sizes="$(PW="$module" node -e '
const { chromium } = require(process.env.PW);
(async () => {
  const b = await chromium.launch();
  for (const width of [1280, 390]) {
    const p = await b.newPage({ viewport: { width, height: 900 } });
    await p.goto("file://" + process.argv[1]);
    console.log(width, await p.evaluate(() => {
      const px = [], shown = [];
      let tall = 0;
      for (const s of document.querySelectorAll("figure svg")) {
        if (getComputedStyle(s).display === "none") continue;
        shown.push(s.getAttribute("class"));
        const k = s.getBoundingClientRect().width / s.viewBox.baseVal.width;
        tall = Math.max(tall, s.getBoundingClientRect().height);
        for (const t of s.querySelectorAll("text")) px.push(parseFloat(t.getAttribute("font-size")) * k);
      }
      const sans = [...document.querySelectorAll("figure svg text")].every(t => !/mono/i.test(getComputedStyle(t).fontFamily));
      return [Math.min(...px).toFixed(1), Math.max(...px).toFixed(1), shown.join(",") || "-", sans, tall.toFixed(0)].join(" ");
    }));
  }
  await b.close();
})();' "$TMP/diagram-flow.html" 2>&1)"
read -r _ min1280 max1280 shown1280 sans1280 tall1280 <<<"$(grep '^1280 ' <<<"$sizes")"
read -r _ min390 max390 shown390 sans390 tall390 <<<"$(grep '^390 ' <<<"$sizes")"
[[ "$shown1280" == dg-wide && "$shown390" == dg-narrow ]] \
  && ok "the wide drawing shows at 1280, the narrow twin at 390" || bad "drawings shown: 1280=$shown1280 390=$shown390 ($sizes)"
awk -v a="$min390" 'BEGIN { exit !(a >= 11) }' \
  && ok "no diagram text under 11 px at 390 (smallest $min390 px)" || bad "diagram text at 390: smallest $min390 px ($sizes)"
awk -v a="$max1280" 'BEGIN { exit !(a <= 17) }' \
  && ok "no diagram text over the 17 px body at 1280 (largest $max1280 px)" || bad "diagram text at 1280: largest $max1280 px ($sizes)"
# F5's hand-drawn diagram was 407 px tall at 1280; a runaway route (a control point
# thousands of units out) passes every other check here and draws a 45,000 px figure.
awk -v a="$tall1280" 'BEGIN { exit !(a <= 610) }' \
  && ok "the diagram is at most 1.5x F5's height at 1280 (${tall1280} px)" || bad "diagram ${tall1280} px tall at 1280 ($sizes)"
[[ "$sans1280" == true && "$sans390" == true ]] \
  && ok "every diagram label resolves to the kit's sans font" || bad "a diagram label is in a monospace font ($sizes)"

echo "== a hand figure built from a spec is never drawn wider than its viewBox (BL-511) =="
# A 360-wide hand SVG with no width= attribute, the shape figure-sonnet ships. The
# kit's `figure svg { width: 100% }` stretched it to the 888 px column at 1280, about
# 2.5x, so 13 px text read near 32 px. The drawing must render at its own 360 px at
# 1280 (not a collapsed sliver either) and still shrink into the column at 390.
( cd "$TMP" && python3 "$SCRIPTS/spec_build.py" "$FIX/hand-figure.spec.md" -o "$TMP/hand-figure.html" ) >/dev/null 2>&1 \
  && ok "built hand-figure from its spec" || bad "spec_build failed on hand-figure.spec.md"
out="$(bash "$PROBE" "$TMP/hand-figure.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "hand-figure exits 0 at 1280 and 390" || bad "hand-figure exit $rc: $out"
fig="$(PW="$module" node -e '
const { chromium } = require(process.env.PW);
(async () => {
  const b = await chromium.launch();
  for (const width of [1280, 390]) {
    const p = await b.newPage({ viewport: { width, height: 900 } });
    await p.goto("file://" + process.argv[1]);
    console.log(width, await p.evaluate(() => {
      const s = document.querySelector("figure#mano svg");
      return [s.getBoundingClientRect().width.toFixed(1), document.querySelector(".main").clientWidth].join(" ");
    }));
  }
  await b.close();
})();' "$TMP/hand-figure.html" 2>&1)"
read -r _ w1280 col1280 <<<"$(grep '^1280 ' <<<"$fig")"
read -r _ w390 col390 <<<"$(grep '^390 ' <<<"$fig")"
awk -v a="$w1280" 'BEGIN { exit !(a >= 359 && a <= 360.5) }' \
  && ok "the 360-wide figure renders at its own width at 1280 (${w1280} px in a ${col1280} px column)" \
  || bad "the 360-wide figure renders ${w1280} px wide at 1280 (column ${col1280} px): scaled, not drawn at its size ($fig)"
awk -v a="$w390" -v c="$col390" 'BEGIN { exit !(a > 0 && a <= c) }' \
  && ok "the figure fits the ${col390} px column at 390 (${w390} px)" || bad "the figure is ${w390} px wide in a ${col390} px column at 390 ($fig)"

echo "== a graph is drawn at most at 1.2x its viewBox width (BL-513) =="
# The kit's `figure svg { width: 100% }` stretched a Graphviz graph to the 888 px
# column at 1280: a 62x404 vertical chain rendered 888 px wide, 14.3x, some 5,800 px
# tall. #cadena must render between 1.0x and 1.2x its viewBox width at 1280; #fila,
# wider than the 390 column can hold at 1.2x, must still shrink to exactly the column.
if ! command -v dot >/dev/null 2>&1; then
  echo "  SKIP: no Graphviz \`dot\` on PATH, the graph cases need it"
else
( cd "$TMP" && python3 "$SCRIPTS/spec_build.py" "$FIX/graph-scale.spec.md" -o "$TMP/graph-scale.html" ) >/dev/null 2>&1 \
  && ok "built graph-scale from its spec" || bad "spec_build failed on graph-scale.spec.md"
out="$(bash "$PROBE" "$TMP/graph-scale.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "graph-scale exits 0 at 1280 and 390" || bad "graph-scale exit $rc: $out"
gr="$(PW="$module" node -e '
const { chromium } = require(process.env.PW);
(async () => {
  const b = await chromium.launch();
  for (const width of [1280, 390]) {
    const p = await b.newPage({ viewport: { width, height: 900 } });
    await p.goto("file://" + process.argv[1]);
    console.log(width, await p.evaluate(() => {
      const col = document.querySelector(".main").clientWidth;
      return [col].concat(["cadena", "fila"].map(id => {
        const s = document.querySelector("figure#" + id + " svg");
        const w = s.getBoundingClientRect().width;
        return w.toFixed(1) + ":" + (w / s.viewBox.baseVal.width).toFixed(2);
      })).join(" ");
    }));
  }
  await b.close();
})();' "$TMP/graph-scale.html" 2>&1)"
read -r _ gcol1280 chain1280 row1280 <<<"$(grep '^1280 ' <<<"$gr")"
read -r _ gcol390 chain390 row390 <<<"$(grep '^390 ' <<<"$gr")"
for g in "cadena:$chain1280" "fila:$row1280"; do
  IFS=: read -r id w k <<<"$g"
  awk -v k="$k" 'BEGIN { exit !(k >= 1 && k <= 1.21) }' \
    && ok "#$id renders at ${k}x its viewBox width at 1280 (${w} px in a ${gcol1280} px column)" \
    || bad "#$id renders at ${k}x its viewBox width at 1280 (${w} px in a ${gcol1280} px column): over diagram's 1.2x cap ($gr)"
done
wc390="${chain390%%:*}" wr390="${row390%%:*}"
awk -v a="$wc390" -v c="$gcol390" 'BEGIN { exit !(a > 0 && a <= c) }' \
  && ok "#cadena fits the ${gcol390} px column at 390 (${wc390} px)" || bad "#cadena is ${wc390} px wide in a ${gcol390} px column at 390 ($gr)"
awk -v a="$wr390" -v c="$gcol390" 'BEGIN { d = a - c; exit !(d >= -1 && d <= 1) }' \
  && ok "#fila shrinks to the ${gcol390} px column at 390 (${wr390} px)" || bad "#fila is ${wr390} px wide in a ${gcol390} px column at 390, not shrunk to it ($gr)"
fi

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
scroll-overlap text-overlap p.sovfix 1280
scroll-overlap text-overlap span.sohfix 390
clip-escape text-overlap span.escfix 1280
clip-escape text-overlap p.insfix 1280
clip-escape text-overlap p.contfix 1280
clip-escape fixed-over-text span.lblclipfix 1280
style-drift text-style-drift p.note 1280
style-drift text-style-drift "nestedfix 1280
style-drift text-style-drift "inheritfix 1280
figure-contrast figure-text-contrast "fallaclaro 1280
figure-contrast figure-text-contrast "fallaoscuro 390
label-box svg-label-outside-its-box "cajafix 1280
label-box svg-label-outside-its-box "anchorfix 1280
figure-contrast figure-text-contrast "usefix 1280
EOF

echo "== the render contract classes (--contract) =="
# contract-pass holds the passing cell of each class: the kit's own .fieldlabel, .note
# and .ex inside a consult item (the kit's `.consult-item p` made all three 15.2 px
# until 2026-09-28), kit-stack svg families, an accent tint at fill-opacity 0.16, an
# oklch fill, a gradient and a label that fits its box.
out="$(bash "$PROBE" "$TMP/contract-pass.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "contract-pass is clean in the default run" || bad "contract-pass exit $rc: $(grep '^DEFECT' <<<"$out")"
grep -q '"unmeasured":' <<<"$out" && ok "text over a gradient is counted as unmeasured" || bad "no unmeasured count for the gradient label: $out"
# <fixture> <slug> <expected exit>: each failing fixture fails its own class only
while read -r fx slug want; do
  out="$(bash "$PROBE" --contract "$slug" "$TMP/$fx.html" 2>&1)"; rc=$?
  [[ $rc -eq $want ]] && ok "--contract $slug on $fx exits $want" || bad "--contract $slug on $fx exit $rc, expected $want: $(grep '^DEFECT' <<<"$out")"
  if [[ $want -eq 1 ]]; then
    others="$(grep '^DEFECT' <<<"$out" | grep -v " $slug: " || true)"
    [[ -z "$others" ]] && ok "--contract $slug reports only $slug" || bad "--contract $slug reported: $others"
  fi
  # the gate reads one last line, CONTRACT <slug> findings=<n>, n = the DEFECT lines
  n="$(grep -c '^DEFECT' <<<"$out")"
  [[ "$(grep -c '^CONTRACT ' <<<"$out")" -eq 1 && "$(tail -n 1 <<<"$out")" == "CONTRACT $slug findings=$n" ]] \
    && ok "--contract $slug on $fx ends with 'CONTRACT $slug findings=$n'" || bad "--contract $slug on $fx: no single final CONTRACT line for $n finding(s): $(tail -n 2 <<<"$out")"
done <<'EOF'
contract-pass text-style-drift 0
contract-pass figure-text-contrast 0
contract-pass svg-label-outside-its-box 0
style-drift text-style-drift 1
style-drift figure-text-contrast 0
figure-contrast figure-text-contrast 1
figure-contrast svg-label-outside-its-box 0
label-box svg-label-outside-its-box 1
label-box text-style-drift 0
drift-onpurpose text-style-drift 0
image-under figure-text-contrast 0
EOF
# sizes set on purpose (inline, a page rule restating the class, a scoped `.x .note`)
out="$(bash "$PROBE" "$TMP/drift-onpurpose.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "drift-onpurpose is clean in the default run" || bad "drift-onpurpose exit $rc: $(grep '^DEFECT' <<<"$out")"
# a label over an <image> is unmeasured (both schemes), not measured against the page
out="$(bash "$PROBE" "$TMP/image-under.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && grep -q '"width":1280,.*"unmeasured":2' <<<"$out" \
  && ok "a label over an <image> is counted unmeasured in both schemes" || bad "image-under exit $rc: $(grep '"width":1280' <<<"$out")"
# svg families are judged under --contract text-style-drift only, until the owner rules
# on author font overrides; the default run leaves them out
out="$(bash "$PROBE" "$TMP/style-drift.html" 2>&1)"
grep -q 'svg text in' <<<"$out" && bad "the default run judged svg families: $(grep 'svg text in' <<<"$out")" || ok "the default run leaves svg families out"
out="$(bash "$PROBE" --contract text-style-drift "$TMP/style-drift.html" 2>&1)"
grep -qE '^DEFECT style-drift\.html @390px text-style-drift: .*svg text in "helvetica, sans-serif"' <<<"$out" \
  && ok "--contract text-style-drift names the Helvetica family" || bad "no Helvetica family line under --contract: $(grep '^DEFECT' <<<"$out")"
# a kit rule scoped with :where() (`.chip:where(:not(svg *))`, kit 27) still declares its class's size
grep -qE '^DEFECT style-drift\.html @1280px text-style-drift: p\.chip .*\.chip declares 0\.66rem' <<<"$out" \
  && ok "--contract text-style-drift holds .chip to its :where()-scoped kit size" || bad "no .chip line under --contract: $(grep '^DEFECT' <<<"$out")"
# each scheme is judged on its own: the light-only chip is never reported in dark
out="$(bash "$PROBE" --contract figure-text-contrast "$TMP/figure-contrast.html" 2>&1)"
[[ "$(grep -c '"fallaclaro chip" [0-9.]*:1 in the light scheme' <<<"$out")" -eq 2 && "$(grep -c '"fallaclaro chip" .* in the dark scheme' <<<"$out")" -eq 0 ]] \
  && ok "the light-only chip fails in the light scheme only" || bad "fallaclaro lines: $(grep fallaclaro <<<"$out")"
[[ "$(grep -c '"fallaoscuro chip" [0-9.]*:1 in the dark scheme' <<<"$out")" -eq 2 && "$(grep -c '"fallaoscuro chip" .* in the light scheme' <<<"$out")" -eq 0 ]] \
  && ok "the dark-only oklch chip fails in the dark scheme only" || bad "fallaoscuro lines: $(grep fallaoscuro <<<"$out")"
out="$(bash "$PROBE" --contract text-style-drift "$TMP/crash.html" 2>&1)"; rc=$?
[[ $rc -eq 4 ]] && ok "a crash under --contract exits 4" || bad "--contract crash exit $rc, expected 4: $out"
grep -q '^CONTRACT ' <<<"$out" && bad "a crash under --contract printed a CONTRACT line: $out" || ok "a crash under --contract prints no CONTRACT line"
bash "$PROBE" --contract no-such-class "$TMP/clean.html" >/dev/null 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "an unknown --contract slug exits 2" || bad "unknown slug exit $rc, expected 2"

echo "== tiles and manifest on a tall page =="
# 3 items x 30 rows x 150 px = 13,500 px of bare HTML (the probe needs a page that loads,
# not a passing consultation), items in the order q-b, q-a, q-c (page order, not
# alphabetical). Each row carries a unique label so every tile's pixels differ: a clip
# that ignored its y would hash every tile alike.
{
  printf '<!doctype html><html><body style="margin:0">\n'
  n=0
  for id in q-b q-a q-c; do
    printf '<section data-id="%s"><h2>%s</h2>' "$id" "$id"
    for _ in $(seq 30); do
      n=$((n + 1))
      printf '<div style="height:150px;font:32px monospace">row-%03d-unique</div>' "$n"
    done
    printf '</section>\n'
  done
  printf '</body></html>\n'
} > "$TMP/tall.html"
# A tile of an earlier, taller build must be gone after this run. The grader only reads
# tiles the manifest lists, so a leftover is harmless to it; the deletion is kept as hygiene
# and this is its only check.
mkdir -p "$TMP/tall-shots" && : > "$TMP/tall-shots/tall-1280-t99.png"
out="$(bash "$PROBE" --shots "$TMP/tall-shots" "$TMP/tall.html" 2>&1)"
man="$TMP/tall-shots/tall-shots.json"
[[ -s "$man" ]] && ok "--shots writes tall-shots.json" || bad "no manifest: $out"
[[ ! -e "$TMP/tall-shots/tall-1280-t99.png" ]] && ok "a stale tile of an earlier build is deleted" || bad "stale tile kept"
chk="$(python3 - "$man" "$TMP/tall-shots" <<'PY'
import json, struct, sys, os, hashlib
m = json.load(open(sys.argv[1])); d = sys.argv[2]
vh = m["viewport_height"]
for w in ("1280", "390"):
    W = m["widths"][w]
    if W["page_height"] < 13000: print(f"page_height {w} only {W['page_height']}"); sys.exit()
    hashes = set()
    for t in W["tiles"]:
        p = os.path.join(d, t["file"])
        with open(p, "rb") as f:
            f.seek(16); wd, ht = struct.unpack(">II", f.read(8))
        if ht != vh or ht != t["height"]:
            print(f"tile {t['file']} height {ht} (manifest {t['height']}, want {vh})"); sys.exit()
        hashes.add(hashlib.sha256(open(p, "rb").read()).hexdigest())
    ys = [t["y"] for t in W["tiles"]]
    if ys[0] != 0 or ys[-1] != W["page_height"] - vh: print(f"tiles do not span the page: {ys[0]}..{ys[-1]}"); sys.exit()
    if any(b - a > vh - 100 or b <= a for a, b in zip(ys, ys[1:])): print(f"gaps or no progress: {ys}"); sys.exit()
    if len(hashes) != len(W["tiles"]): print(f"{w}: {len(W['tiles'])} tiles but {len(hashes)} distinct images"); sys.exit()
    if not any("q-a" in t["ids"] for t in W["tiles"]): print("q-a in no tile"); sys.exit()
if m["ids"] != ["q-b", "q-a", "q-c"]: print("ids", m["ids"]); sys.exit()
print("ok")
PY
)"
[[ "$chk" == ok ]] && ok "tiles span a 13,500 px page, each a full viewport, overlapping, all distinct, ids in page order" || bad "tall page manifest: $chk"
grep -q '^SHOTS run=' <<<"$out" && grep -q "^SHOT .*tall-shots.json$" <<<"$out" \
  && ok "the probe prints the run stamp and the files it wrote" || bad "no SHOTS lines: $out"
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["ids"]==[] else 1)' "$TMP/shots/clean-shots.json" \
  && ok "a page with no items has an empty id list" || bad "clean manifest: $(cat "$TMP/shots/clean-shots.json" 2>&1)"

# Two items exactly one viewport each, and a 1801 px page (the sliver case: [900,900,1]
# with a naive stride). Stride is 800, the last tile pinned to H-900.
printf '<!doctype html><html><body style="margin:0"><div data-id="a" style="height:900px">a</div><div data-id="b" style="height:900px">b</div></body></html>\n' > "$TMP/two.html"
printf '<!doctype html><html><body style="margin:0"><div style="height:1801px">x</div></body></html>\n' > "$TMP/h1801.html"
bash "$PROBE" --shots "$TMP/two-shots" "$TMP/two.html" >/dev/null 2>&1
bash "$PROBE" --shots "$TMP/two-shots" "$TMP/h1801.html" >/dev/null 2>&1
cat > "$TMP/chk-two.py" <<'PY'
import json, sys, os
d = sys.argv[1]
m = json.load(open(os.path.join(d, "two-shots.json")))
# H=1800: tiles at y 0, 800, 900. [0,900) holds a; [800,1700) both; [900,1800) b only.
want = [(0, ["a"]), (800, ["a", "b"]), (900, ["b"])]
for w in ("1280", "390"):
    W = m["widths"][w]
    got = [(t["y"], t["ids"]) for t in W["tiles"]]
    if W["page_height"] != 1800 or got != want or any(t["height"] != 900 for t in W["tiles"]):
        print(f"{w}: height {W['page_height']} tiles {got}"); sys.exit()
h = json.load(open(os.path.join(d, "h1801-shots.json")))
for w in ("1280", "390"):
    W = h["widths"][w]
    hs = [t["height"] for t in W["tiles"]]
    if W["page_height"] != 1801 or [t["y"] for t in W["tiles"]] != [0, 800, 901] or min(hs) < 900:
        print(f"1801 @{w}: {[(t['y'], t['height']) for t in W['tiles']]}"); sys.exit()
print("ok")
PY
chk="$(python3 "$TMP/chk-two.py" "$TMP/two-shots")"
[[ "$chk" == ok ]] && ok "stride 800: tiles touching only a or only b carry one id, the middle one both; an 1801 px page has no sliver" || bad "two-item / 1801 tiles: $chk"

echo "== fixed and sticky elements sit where a reader scrolled to the tile sees them =="
# A 3,000 px page with a fixed magenta bar along the bottom of the viewport and a sticky cyan
# rail down the left edge. Tiles clipped out of one scroll-0 capture draw both only on t01;
# tiles taken by scrolling draw both on every tile, the bar in the bottom band and nowhere else.
{
  printf '<!doctype html><html><body style="margin:0">\n'
  printf '<div id="bar" style="position:fixed;left:0;right:0;bottom:0;height:60px;background:#ff00ff"></div>\n'
  printf '<div style="display:flex"><div id="rail" style="position:sticky;top:0;align-self:flex-start;flex:none;width:40px;height:300px;background:#00ffff"></div><div style="flex:1">'
  for n in $(seq 20); do
    printf '<div style="height:150px;font:32px monospace">fixrow-%03d-unique</div>' "$n"
  done
  printf '</div></div></body></html>\n'
} > "$TMP/fixed.html"
bash "$PROBE" --shots "$TMP/fixed-shots" "$TMP/fixed.html" >/dev/null 2>&1
cat > "$TMP/chk-fixed.py" <<'PY'
import json, os, sys, zlib, struct, hashlib
d = sys.argv[1]
m = json.load(open(os.path.join(d, "fixed-shots.json")))

def decode(path):
    b = open(path, "rb").read()
    pos, idat, w, h, ct = 8, b"", 0, 0, 0
    while pos < len(b):
        n, typ = struct.unpack(">I4s", b[pos:pos + 8]); body = b[pos + 8:pos + 8 + n]; pos += 12 + n
        if typ == b"IHDR": w, h, depth, ct = struct.unpack(">IIBB", body[:10])
        elif typ == b"IDAT": idat += body
    bpp = {2: 3, 6: 4}[ct]
    raw = zlib.decompress(idat); stride = w * bpp; rows = []; prev = bytearray(stride); i = 0
    for _ in range(h):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0; c = prev[x - bpp] if x >= bpp else 0; u = prev[x]
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + u) & 255
            elif f == 3: line[x] = (line[x] + (a + u) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(u - c), abs(a - c), abs(a + u - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else u if pb <= pc else c)) & 255
        rows.append(line); prev = line
    return lambda x, y: tuple(rows[y][x * bpp:x * bpp + 3])

MAGENTA, CYAN = (255, 0, 255), (0, 255, 255)
for w in ("1280", "390"):
    W = m["widths"][w]; tiles = W["tiles"]; hashes = set()
    if len(tiles) < 3: print(f"{w}: only {len(tiles)} tiles"); sys.exit()
    for t in tiles:
        p = os.path.join(d, t["file"]); px = decode(p); h = t["height"]
        hashes.add(hashlib.sha256(open(p, "rb").read()).hexdigest())
        if px(int(w) // 2, h - 30) != MAGENTA: print(f"{t['file']}: no fixed bar in the bottom band"); sys.exit()
        if px(int(w) // 2, h // 2) == MAGENTA: print(f"{t['file']}: fixed bar drawn mid-tile"); sys.exit()
        if px(20, 150) != CYAN: print(f"{t['file']}: no sticky rail"); sys.exit()
    if len(hashes) != len(tiles): print(f"{w}: {len(tiles)} tiles but {len(hashes)} distinct images"); sys.exit()
print("ok")
PY
chk="$(python3 "$TMP/chk-fixed.py" "$TMP/fixed-shots" 2>&1 | tail -3)"
[[ "$chk" == ok ]] && ok "the fixed bar is in the bottom band and the sticky rail in every tile, at both widths, and the tiles still differ" || bad "fixed/sticky tiles: $chk"

echo "== reference-set.sh hands the grader the manifest and the run stamp =="
# The handoff is behaviour, so it is run: the set builds, the probe shoots it, and the last
# lines name a manifest that parses with tiles per width and a SHOTS run stamp (exit 1 = the
# probe found defects in the page, which is a score for a reference set, not a failure).
out="$(bash "$SCRIPTS/reference-set.sh" "$HERE/fixtures/reference-set" "$TMP/refset-out" 2>/dev/null)"; rc=$?
mf="$(sed -n 's/^manifest: //p' <<<"$out")"
[[ $rc -eq 0 && -n "$mf" && "$mf" == "$TMP/refset-out/reference-set-shots.json" ]] \
  && python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["widths"]["1280"]["tiles"] else 1)' "$mf" 2>/dev/null \
  && grep -q '^SHOTS run=' <<<"$out" \
  && ok "reference-set.sh prints a manifest with 1280 tiles and a SHOTS run stamp" \
  || bad "reference-set handoff (rc $rc): $(grep -v '^SHOT ' <<<"$out" | tail -5)"

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
