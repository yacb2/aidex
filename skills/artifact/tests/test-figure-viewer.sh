#!/usr/bin/env bash
# test-figure-viewer.sh — every `figure` of an item opens the kit-zoom viewer
# (BL-597 one-at-a-time gallery walk with visible prev/next and a caption per
# image; BL-626 lone png, lone svg, mixed png+svg runs, svg text readable at 390,
# two adjacent figures side by side at 1280). Layer: the browser, because the
# viewer, its trusted keys, the rendered text size and the grid are what decide
# it; the page is built the normal route (spec -> spec_build -> wrap-report) so a
# builder that stops marking or grouping figures fails here too.
# Without Playwright it prints SKIP and exits 2 (a skip, never a pass).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf '  ok: %s\n' "$*"; }

module=""
if [[ -n "${AIDEX_PLAYWRIGHT_DIR:-}" && -f "$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright/package.json" ]]; then
  module="$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright"
else
  g="$(npm root -g 2>/dev/null || true)"
  [[ -n "$g" && -f "$g/playwright/package.json" ]] && module="$g/playwright"
fi
if [[ -z "$module" ]] || ! command -v node >/dev/null 2>&1; then
  echo "SKIP: Playwright not found (set AIDEX_PLAYWRIGHT_DIR or npm i -g playwright)"
  exit 2
fi

for n in 1 2 3 4 5 6 7 8; do python3 "$HERE/png_fixture.py" "$TMP/g$n.png" 800 500; done
python3 "$HERE/png_fixture.py" "$TMP/lone.png" 640 400
python3 "$HERE/png_fixture.py" "$TMP/t1.png" 400 1800
python3 "$HERE/png_fixture.py" "$TMP/t2.png" 400 1800
cat > "$TMP/nv.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="300" height="150"><rect width="300" height="150" fill="none" stroke="currentColor"/><text x="10" y="40" font-size="14" fill="currentColor">No viewBox</text></svg>
SVG
cat > "$TMP/wire.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 220"><rect x="10" y="10" width="380" height="200" fill="none" stroke="currentColor"/><rect class="acc" x="24" y="110" width="120" height="30" fill="none" stroke="currentColor"/><text x="24" y="50" font-size="14" fill="currentColor">Wireframe: users list</text><text x="24" y="90" font-size="12" fill="currentColor">Name   Role   Status</text></svg>
SVG
cp "$TMP/wire.svg" "$TMP/wire2.svg"
cp "$TMP/wire.svg" "$TMP/wireA.svg"
cat > "$TMP/portrait.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 491"><rect x="10" y="10" width="360" height="471" fill="none" stroke="currentColor"/><text x="24" y="50" font-size="13" fill="currentColor">Portrait flow</text></svg>
SVG
cat > "$TMP/tall.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 2000"><rect x="10" y="10" width="380" height="1980" fill="none" stroke="currentColor"/><text x="24" y="50" font-size="14" fill="currentColor">Tall wireframe</text></svg>
SVG
cp "$TMP/tall.svg" "$TMP/tallB.svg"
python3 - "$TMP" <<'PY'
import sys
d = sys.argv[1]
imgs = "".join('::: figure {src="g%d.png" alt="captura %d" title="Captura %d de 8"}\n:::\n\n' % (i, i, i) for i in range(1, 9))
open(d + "/page.spec.md", "w", encoding="utf-8").write('''::: masthead {visual="none: a viewer probe, nothing to draw"}
# Figure viewer probe

One item per figure shape.
:::

::: group {#G title="Grupo"}
::: item {#Q1 title="Galeria de 8"}
¿Cual captura es la correcta?

''' + imgs + '''- Primera — la primera
- Segunda — la segunda
:::

::: item {#Q2 title="Una captura sola"}
¿Se lee?

::: figure {src="lone.png" alt="sola" title="La captura sola"}
:::

- Si — si
- No — no
:::

::: item {#Q3 title="Wireframe de 400"}
¿Se lee el wireframe?

::: figure {src="wire.svg" title="Wireframe 400"}
:::

- Si — si
- No — no
:::

::: item {#Q4 title="Png y svg"}
¿Y el par?

::: figure {src="g1.png" alt="png del par" title="Png del par"}
:::

::: figure {src="wire2.svg" title="Svg del par"}
:::

- Si — si
- No — no
:::

::: item {#Q5 title="Svg alto"}
¿Cabe en la ventana?

::: figure {src="tall.svg" title="Svg alto"}
:::

- Si — si
- No — no
:::

::: item {#Q6 title="Svg sin viewBox"}
¿Se ve?

::: figure {src="nv.svg" title="Sin viewBox"}
:::

- Si — si
- No — no
:::

::: item {#Q7 title="Capturas altas"}
¿Cual?

::: figure {src="t1.png" alt="alta uno" title="Alta 1"}
:::

::: figure {src="t2.png" alt="alta dos" title="Alta 2"}
:::

- Si — si
- No — no
:::

::: item {#Q8 title="Svg vertical"}
¿Se ve grande?

::: figure {src="portrait.svg" title="Flujo vertical"}
:::

- Si — si
- No — no
:::

::: item {#Q9 title="Dos svg"}
¿Y el segundo?

::: figure {src="wireA.svg" title="Svg ancho"}
:::

::: figure {src="tallB.svg" title="Svg alto del par"}
:::

- Si — si
- No — no
:::
:::

::: notes {title="Notas generales"}
:::
''')
PY
python3 "$SCRIPTS/spec_build.py" "$TMP/page.spec.md" > "$TMP/body.html" 2> "$TMP/build.err" \
  || { echo "FAIL: the probe spec did not build: $(head -3 "$TMP/build.err")"; exit 1; }
# A gallery row (hand-written, as pages before the generator) whose tile is only an inline svg.
python3 - "$TMP/body.html" <<'ROWPY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
px = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
row = ('<section class="consult-group" id="R" data-id="R" data-title="Review" data-tiles="before after">'
       '<div class="sec-head"><h2>Review</h2></div>'
       '<section class="consult-item consult-gallery" data-id="svgrow-sample" data-title="svg &middot; row" data-variant="light-desktop">'
       '<h3><span class="consult-id">svgrow-sample</span>svg &middot; row</h3><p>A sample.</p><div class="gal">'
       '<figure data-tile="before"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"><rect width="40" height="20" fill="none" stroke="currentColor"/></svg><figcaption>antes</figcaption></figure>'
       '<figure data-tile="after"><img src="%s" alt="after"><figcaption>propuesto</figcaption></figure>'
       '</div><p class="fieldlabel">Notas</p><textarea></textarea></section>'
       '<div class="group-notes"><p class="fieldlabel">Notas de este bloque</p><textarea></textarea></div>'
       '</section>\n' % px)
mark = '<section class="consult-item consult-notes"'
assert mark in s
open(p, "w", encoding="utf-8").write(s.replace(mark, row + mark, 1))
ROWPY
( cd "$TMP" && bash "$SCRIPTS/wrap-report.sh" --title "Figuras" --lang es --in "$TMP/body.html" --out "$TMP/page.html" ) >/dev/null 2>&1 \
  || { echo "FAIL: wrap-report failed on the probe page"; exit 1; }

# The mixed png+svg grid (Q4) and the lone svg pass the contract on their own.
bash "$SCRIPTS/check-artifact.sh" "$TMP/page.html" > "$TMP/contract.out" 2>&1 \
  && ok "the page with a mixed png+svg grid and a lone svg passes check-artifact" \
  || fail "check-artifact refused the figure page: $(tail -3 "$TMP/contract.out")"

json="$(AIDEX_PLAYWRIGHT_MODULE="$(dirname "$module")" node "$HERE/figure_viewer.mjs" "$TMP/page.html" 2>"$TMP/err")" \
  || { echo "FAIL: the probe crashed: $(head -c 600 "$TMP/err")"; exit 1; }
check() {  # check <python expression over d> <label>
  if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if eval(sys.argv[2]) else 1)' "$json" "$1" 2>/dev/null
  then ok "$2"; else fail "$2: $json"; fi
}
for w in w1280 w390; do
  check "d['$w']['markers']['lonePng'] == 'button' and d['$w']['lonePng']['open'] and d['$w']['lonePng']['imgShown'] and d['$w']['lonePng']['tile'] == '1 / 1'" \
    "$w: a lone png gets Ampliar and opens the viewer"
  check "d['$w']['markers']['loneSvg'] == 'button' and d['$w']['markers']['label'] == '\"Ampliar\"' and d['$w']['loneSvg']['open'] and d['$w']['loneSvg']['svgShown'] and not d['$w']['loneSvg']['imgShown']" \
    "$w: a lone svg gets Ampliar and opens the viewer on the drawing itself"
  check "d['$w']['loneSvg']['svgText'] >= 11" \
    "$w: the smallest svg text in the dialog is at least 11 px"
  check "d['$w']['lonePng']['cap'] == 'La captura sola' and d['$w']['lonePng']['capShown'] and d['$w']['loneSvg']['cap'] == 'Wireframe 400' and not d['$w']['lonePng']['prevShown']" \
    "$w: the caption is the figure title; a single image offers no prev/next"
  check "d['$w']['pair1']['tile'] == '1 / 2' and d['$w']['pair2']['tile'] == '2 / 2' and d['$w']['pair2']['svgShown'] and d['$w']['pair2']['cap'] == 'Svg del par' and d['$w']['pairEnd']['tile'] == '2 / 2'" \
    "$w: a mixed png+svg run walks with the real Right key, shows each caption and does not wrap"
  check "d['$w']['pairPrev']['tile'] == '1 / 2' and d['$w']['pairPrev']['imgShown'] and d['$w']['pairPrev']['prevOff'] and d['$w']['pairNext']['tile'] == '2 / 2' and d['$w']['pairNext']['nextOff']" \
    "$w: the visible prev/next buttons walk the same run and disable at its ends"
  check "d['$w']['pairBack']['tile'] == '1 / 2' and d['$w']['pairNext']['focusInDialog']" \
    "$w: a real Left still walks after the Next button disabled itself (focus stayed in the dialog)"
  check "d['$w']['g1']['tile'] == '1 / 8' and d['$w']['g8']['tile'] == '8 / 8' and d['$w']['g8']['cap'] == 'Captura 8 de 8' and d['$w']['g8']['nextOff'] and d['$w']['g1']['prevOff']" \
    "$w: an 8-image gallery pages from 1 / 8 to 8 / 8 by the button, a caption each"
  check "d['$w']['loneSvg']['accColor'] == d['$w']['markers']['pageAcc'] and d['$w']['loneSvg']['accColor'] != d['$w']['loneSvg']['inkColor']" \
    "$w: a kit accent class on the drawing keeps its colour in the dialog"
  check "d['$w']['pair1']['native'] is False and d['$w']['pair2']['native'] == ('$w' == 'w390') and d['$w']['pairPrev']['native'] is False and d['$w']['pairPrev']['imgW'] <= d['$w']['pairPrev']['imgNatW'] and (d['$w']['pairPrev']['imgW'] < d['$w']['pairPrev']['imgNatW'] or '$w' == 'w1280')" \
    "$w: stepping png -> svg -> png sets each image's own size mode (raster Fit; svg the larger of Fit and drawn: Fit at 1280, drawn at 390), no leak"
  check "d['$w']['loneSvg']['body']['ox'] in ('auto', 'scroll') and d['$w']['loneSvg']['body']['svgLeft'] >= 0 and (d['$w']['loneSvg']['body']['sw'] > d['$w']['loneSvg']['body']['cw'] or '$w' == 'w1280') and d['$w']['loneSvgFit'] != 'none'" \
    "$w: the svg never clips (its box scrolls, starts at the left edge; it opens at 1:1 at 390, at Fit at 1280) and Fit caps the height"
  check "d['$w']['pair1']['btn']['prev'] == d['$w']['pair1']['btn']['close'] and d['$w']['pair1']['btn']['prev'] != 'rgb(239, 239, 239)'" \
    "$w: Previous/Next are styled like Close, not the browser default button"
  check "not d['$w']['lonePng']['tileShown'] and not d['$w']['lonePng']['keysShown'] and d['$w']['pair1']['tileShown'] and d['$w']['pair1']['keysShown']" \
    "$w: a single image shows no '1 / 1' counter and no walk hint; a run shows both"
  check "'tile' not in d['$w']['markers']['title'].lower()" \
    "$w: the figure's tooltip says image, not tile"
  check "d['$w']['focusAfterEsc'] == 1" \
    "$w: Esc after walking to image 2 returns the focus to figure 2"
  check "d['$w']['markers']['capAlign'] == 'center'" \
    "$w: a lone figure's caption is centred like the grid's"
  check "d['$w']['scrolled']['body']['sl'] > 0 or '$w' == 'w1280'" \
    "$w: the overflowing drawing really scrolled (so the next checks about scroll state mean something)"
  check "d['$w']['reopen']['body']['sl'] == 0 and d['$w']['reopen']['body']['svgLeft'] == 0 and d['$w']['pairNextScroll'] == 0" \
    "$w: no stale horizontal scroll across opens or across a walk back to the svg"
  check "abs(d['$w']['scrolled']['body']['svgLeft']) <= 1 or abs(d['$w']['scrolled']['body']['rightGap']) <= 1" \
    "$w: scrolled fully right the drawing ends flush with its scroller, which sits inside the dialog body's padding"
  check "d['$w']['scrolled']['body']['capInside'] is True" \
    "$w: the caption stays inside the dialog while the drawing scrolls"
  check "d['$w']['pair1']['nav']['prevColor'] == d['$w']['pair1']['nav']['nextColor'] and d['$w']['pair1']['nav']['prevOpacity'] != d['$w']['pair1']['nav']['nextOpacity']" \
    "$w: a disabled Previous differs from the enabled Next by opacity only, not by colour"
  check "d['$w']['tall']['bottom'] <= d['$w']['tall']['h'] and not d['$w']['tall']['native']" \
    "$w: a tall svg in Fit ends inside the window"
  check "d['$w']['q2toggled']['native'] and not d['$w']['q2reopen']['native']" \
    "$w: a fresh open starts at the image's default size, whatever the last open toggled"
  check "d['$w']['keepSize']['native'] and d['$w']['keepSize']['tile'] == '2 / 8'" \
    "$w: walking capture to capture keeps the reader's size"
  check "d['$w']['markers']['rowSvgTile']['role'] is None and d['$w']['markers']['rowSvgTile']['zoom'] is None and d['$w']['markers']['rowImgTile'] == 'button'" \
    "$w: a gallery-row tile holding only an inline svg gets no button and no Ampliar; its img sibling does"
  check "(d['$w']['tabGuard']['found'] or '$w' == 'w1280') and (not d['$w']['tabGuard']['found'] or (d['$w']['tabGuard']['left']['tile'] == '1 / 2' and d['$w']['tabGuard']['left']['focusInDialog'] and d['$w']['tabGuard']['right']['tile'] == '2 / 2'))" \
    "$w: Tab onto the overflowing scroller, then a walk to a picture that fits, keeps the focus in the dialog and the arrows alive"
  check "d['$w']['pair1']['nextRect'] == d['$w']['pair2']['nextRect']" \
    "$w: the Next button stays where it is across the walk (the dialog width does not follow the image)"
  check "'desliza' in d['$w']['pair1']['keysText'] and ('$w' == 'w1280' or 'desliza' not in d['$w']['pair2']['keysText'])" \
    "$w: the hint offers the swipe walk, and stops offering it when the drawing pans instead"
  check "d['$w']['clickLeft']['tile'] == '1 / 2' and d['$w']['clickLeft']['focusInDialog'] and d['$w']['clickRight']['tile'] == '2 / 2'" \
    "$w: after a click on the drawing the keys still walk (Left, then Right) and the focus stays in the dialog"
  check "d['$w']['tallRaster']['native'] and d['$w']['tallRaster']['st'] == 400 and d['$w']['tallStep']['tile'] == '2 / 2' and d['$w']['tallStep']['st'] == 400" \
    "$w: stepping between tall captures at 1:1 keeps the reader's scroll position"
  check "0 < d['$w']['noViewBox']['w'] <= 301 and d['$w']['noViewBox']['left'] >= 0" \
    "$w: an svg with no viewBox is shown at most at its width attribute, from the left edge"
  check "d['$w']['g1']['btnsInside'] and d['$w']['pair2']['btnsInside'] and d['$w']['layout']['overflow'] <= 0" \
    "$w: the header buttons stay inside the viewport and the page does not overflow"
done
check "d['w1280']['touch']['rasterSwipe']['tile'] == '2 / 2' and d['w390']['touch']['rasterSwipe']['tile'] == '2 / 2'" \
  "a REAL touch swipe (with ~20 px of finger drift) walks a capture at Fit"
check "d['w1280']['touch']['pinchScale'] > 1.05 and d['w390']['touch']['pinchScale'] > 1.05" \
  "two fingers spreading over a drawing pinch-zoom the page (touch-action allows pinch-zoom)"
check "d['w1280']['touch']['toSvg'] == '2 / 2' and d['w1280']['touch']['swipeBack']['tile'] == '1 / 2' and d['w1280']['touch']['swipeNext']['tile'] == '2 / 2'" \
  "1280: a REAL touch swipe (CDP touch events) walks the run through an svg that fits the dialog"
check "d['w390']['touch']['swipeBack']['tile'] == '2 / 2' and d['w390']['touch']['swipeNext']['tile'] == '2 / 2' and d['w390']['touch']['swipeNext']['sl'] > 0" \
  "390: a REAL touch swipe on an overflowing svg pans it (the walk stays on 2 / 2, the drawing scrolls)"
check "not d['w1280']['svgOpen']['native'] and d['w1280']['svgOpen']['svgW'] > d['w1280']['svgOpen']['vbW'] + 1 and d['w390']['svgOpen']['native']" \
  "Ampliar on a drawing opens it at the larger size: Fit, wider than its viewBox, where the dialog is wider (1280); drawn size where Fit would shrink it (390) (BL-712)"
check "abs(d['w1280']['svgFit']['body']['svgLeft'] - d['w1280']['svgFit']['body']['rightGap']) <= 2 and d['w1280']['svgFit']['svgW'] > d['w1280']['svgNative']['svgW'] + 1 and abs(d['w1280']['svgNative']['svgW'] - d['w1280']['svgNative']['vbW']) <= 1" \
  "1280: Fit on a drawing narrower than the dialog enlarges it and centres it (gaps within 2 px); 1:1 is the viewBox width (BL-713)"
check "not d['w1280']['loneFit']['native'] and d['w1280']['loneFit']['svgW'] > d['w1280']['loneFit']['vbW'] + 1 and abs(d['w1280']['loneFit']['body']['svgLeft'] - d['w1280']['loneFit']['body']['rightGap']) <= 2" \
  "1280: Fit on a lone drawing narrower than the window enlarges it past its viewBox width, centred (gaps within 2 px)"
check "abs(d['w1280']['loneToggle']['fit'] - d['w1280']['loneToggle']['native']) <= 1" \
  "1280: on a lone drawing the size button stays where it is across Fit -> 1:1 (the dialog does not re-centre on its height)"
check "not d['w1280']['portrait']['native'] and d['w1280']['portrait']['svgW'] > d['w1280']['portrait']['vbW'] + 1 and d['w1280']['portrait']['svgW'] < d['w1280']['portrait']['body']['cw'] - 100 and abs(d['w1280']['portrait']['body']['svgLeft'] - d['w1280']['portrait']['body']['rightGap']) <= 2" \
  "1280: a portrait drawing (380x491) opens at Fit, larger than drawn, capped by the height and centred in the wider dialog (BL-713)"
check "d['w1280']['stepTall']['tile'] == '2 / 2' and (d['w1280']['stepTall']['native'] or d['w1280']['stepTall']['svgW'] >= d['w1280']['stepTall']['vbW'] - 1)" \
  "1280: stepping from a drawing at Fit to a tall drawing picks the tall one's own size, never Fit shrunk below its drawn width"
check "abs(d['w1280']['svgFit']['svgW'] - d['w1280']['svgOpen']['svgW']) <= 2 and abs(d['w1280']['svgFit']['body']['svgLeft'] - d['w1280']['svgOpen']['body']['svgLeft']) <= 2" \
  "1280: Fit -> 1:1 -> Fit returns the drawing to the same box"
check "d['w390']['markers']['pageSvgText'] < 11" \
  "390: the page itself still shrinks the 400 px drawing below 11 px text (so the dialog is what makes it readable)"
check "not d['w390']['rasterNative']['dlgScrolls'] and d['w390']['rasterNative']['stackScrolls'] and not d['w390']['rasterNative']['headMoved'] and d['w390']['rasterNative']['capInside'] and abs(d['w390']['rasterNative']['rightGap']) <= 1" \
  "390: a lone raster at 1:1 scrolls inside the viewer — the dialog does not scroll sideways, header and caption stay put, it ends flush with its scroller"
check "d['w1280']['layout']['capsAligned']" \
  "1280 only (the pair stacks under 700 px): the mixed pair's captions share one line"
check "d['w1280']['layout']['sideBySide'] and d['w1280']['layout']['aW'] < 500 and d['w1280']['layout']['bW'] < 500" \
  "1280: two adjacent ~400 px figures (png + svg) sit side by side, not stacked"

# Spanish chrome never says "tile" (the owner reads captures and images).
python3 - "$HERE/../assets/artifact-kit/composer.js" <<'ESPY' && ok "no Spanish string says tile" || fail "a Spanish string still says tile"
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
es = s[s.index("    es: {"):]
es = es[:es.index("\n    }")]
bad = [l.strip() for l in es.splitlines() if re.search(r"\btiles?\b", l, re.I)]
print("\n".join(bad))
sys.exit(1 if bad else 0)
ESPY

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: every item figure opens the viewer — lone, mixed, svg, keys, buttons, captions, 390 and 1280"
