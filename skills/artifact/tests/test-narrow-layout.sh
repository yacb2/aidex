#!/usr/bin/env bash
# test-narrow-layout.sh — the kit's phone layout, measured in a real browser at 390 px:
#   BL-584  the content column is at least 350 px (it was 292: body padding plus the
#           100vw - 6rem cap took 96 px), and a 3-prose-column table stays short (7 lines a row at most; 9 with
#           the column fix alone, 16 before it);
#   BL-853  a 6-column table in a consultation item (built from a spec, so the builder's
#           data-label is part of what is measured) stacks at 390 px: no sideways scroll,
#           rows as label: value blocks;
#   BL-586  a sub-list item pitch is no larger than a top-level one, and an ol and a
#           ul share one left edge.
# Layer: browser, because the widths and gaps are what the cascade computes, not
# something a grep of the CSS can say. Headless Chrome dumps the DOM after a harness
# script wrote its numbers into <title>. Without Chrome it SKIPs (exit 2), never passes.
# --hide-scrollbars: a phone draws an overlay scrollbar, but the macOS headless shell
# draws a 15 px classic one when the system scroller style says so (BL-667), which took
# the column from 358 to 343 px on the same CSS.
# Run with: bash skills/artifact/tests/test-narrow-layout.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WRAP="$HERE/../scripts/wrap-report.sh"
TMP="$(mktemp -d /tmp/narrow-layout-XXXXXX)"
CHROME_PID=""
trap '[[ -n "$CHROME_PID" ]] && kill -9 -- "-$CHROME_PID" 2>/dev/null; rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

CHROME=""
for c in "${AIDEX_CHROME:-}" "$(command -v chrome-headless-shell 2>/dev/null || true)" \
         "$(ls -d "$HOME"/.cache/puppeteer/chrome-headless-shell/*/chrome-headless-shell-*/chrome-headless-shell 2>/dev/null | tail -1)" \
         "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "$(command -v google-chrome 2>/dev/null || true)" "$(command -v chromium 2>/dev/null || true)"; do
  [[ -n "$c" && -x "$c" ]] && { CHROME="$c"; break; }
done
[[ -z "$CHROME" ]] && { echo "SKIP: no Chrome/Chromium binary found; test-narrow-layout.sh DID NOT RUN"; exit 2; }

# A harness script on load writes the measurements into <title>.
{ cat "$HERE/fixtures/narrow-layout/page.html"; cat <<'JS'
<script>
window.addEventListener('load', function () {
  var r = function (e) { return e.getBoundingClientRect(); };
  var q = function (s) { return document.querySelector(s); };
  var lines = 0;
  document.querySelectorAll('.tw tbody tr').forEach(function (tr) {
    tr.querySelectorAll('td').forEach(function (td) {
      var cs = getComputedStyle(td);
      var n = Math.round((r(td).height - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom)) / parseFloat(cs.lineHeight));
      if (n > lines) lines = n;
    });
  });
  var cs = getComputedStyle(q('.main'));
  var cw = r(q('.main')).width - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
  var top = document.querySelectorAll('#lo > li'), sub = q('#lo-sub').children;
  document.title = 'NL|W=' + innerWidth + '|CW=' + Math.round(cw) + '|LINES=' + lines +
    '|TOPGAP=' + (r(top[1]).top - r(top[0]).top).toFixed(1) +
    '|SUBGAP=' + (r(sub[1]).top - r(sub[0]).top).toFixed(1) +
    '|OLX=' + r(q('#lo > li')).left.toFixed(1) + '|ULX=' + r(q('#lu > li')).left.toFixed(1) + '|';
});
</script>
JS
} > "$TMP/body.html"
bash "$WRAP" --title "narrow" --lang es --out "$TMP/page.html" < "$TMP/body.html" > "$TMP/wrap.log" 2>&1 \
  || fail "the fixture failed to wrap: $(sed -n 1,4p "$TMP/wrap.log")"

: > "$TMP/dom.html"
perl -e 'setpgrp(0,0); exec @ARGV' "$CHROME" --headless=new --disable-gpu --no-first-run --disable-extensions --hide-scrollbars \
  --window-size=390,900 --user-data-dir="$TMP/profile" --dump-dom "file://$TMP/page.html" > "$TMP/dom.html" 2>/dev/null &
CHROME_PID=$!
for ((i = 0; i < 90; i++)); do
  grep -q '</html>' "$TMP/dom.html" 2>/dev/null && break
  kill -0 "$CHROME_PID" 2>/dev/null || break
  sleep 0.5
done
kill -9 -- "-$CHROME_PID" 2>/dev/null; wait "$CHROME_PID" 2>/dev/null; CHROME_PID=""

t="$(grep -oE '<title>[^<]*</title>' "$TMP/dom.html" | sed -n 1p)"
[[ "$t" == *"NL|W=390|"* ]] || { fail "the harness did not run at 390 px: $t"; exit 1; }
g() { sed -nE "s/.*\|$1=([0-9.]+)\|.*/\1/p" <<<"$t"; }
cw="$(g CW)"; lines="$(g LINES)"; topgap="$(g TOPGAP)"; subgap="$(g SUBGAP)"; olx="$(g OLX)"; ulx="$(g ULX)"
echo "measured: $t"
awk -v v="$cw" 'BEGIN { exit !(v >= 350) }' || fail "BL-584: the content column is ${cw:-?}px at 390 px (want >= 350)"
awk -v v="$lines" 'BEGIN { exit !(v >= 1 && v <= 7) }' || fail "BL-584: a 3-column table row runs to ${lines:-?} lines at 390 px (want 1..7; it was 16)"
awk -v a="$subgap" -v b="$topgap" 'BEGIN { exit !(a != "" && b != "" && a <= b) }' || fail "BL-586: sub-item pitch ${subgap:-?}px exceeds the top-level pitch ${topgap:-?}px"
awk -v a="$olx" -v b="$ulx" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(a != "" && b != "" && d <= 1) }' || fail "BL-586: ol left edge ${olx:-?}px differs from ul ${ulx:-?}px"
# BL-853: the spec-built page, measured the same way.
python3 "$HERE/../scripts/spec_build.py" "$HERE/fixtures/narrow-layout/wide-table.spec.md" -o "$TMP/wide-built.html" > "$TMP/wide-build.log" 2>&1 \
  || fail "the wide-table spec failed to build: $(sed -n 1,4p "$TMP/wide-build.log")"
python3 - "$TMP/wide-built.html" "$TMP/wide.html" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
js = """<script>window.addEventListener('load', function () {
  var tw = document.querySelector('.consult-item .tw');
  var st = tw.querySelector('td strong'), nx = st.nextSibling, rg = document.createRange();
  rg.setStart(nx, 0); rg.setEnd(nx, 1);
  var ovf = tw.classList.contains('overflows');
  /* fitTables sets .overflows on a stacked table that still overflows; force it so the
     fade and the cue rules are measured in the one state where they matter. */
  tw.classList.add('overflows');
  document.title = 'WT|SCROLL=' + (tw.scrollWidth - tw.clientWidth) +
    '|ROW=' + getComputedStyle(tw.querySelector('tbody tr')).display +
    '|DOC=' + (document.documentElement.scrollWidth - innerWidth) +
    '|OVF=' + ovf +
    '|CUE=' + getComputedStyle(tw.nextElementSibling).display +
    '|MASK=' + getComputedStyle(tw).maskImage +
    '|GAP=' + Math.round(rg.getBoundingClientRect().left - st.getBoundingClientRect().right) + '|';
});</script></body>"""
open(sys.argv[2], "w", encoding="utf-8").write(s.replace("</body>", js, 1))
PY
: > "$TMP/dom2.html"
perl -e 'setpgrp(0,0); exec @ARGV' "$CHROME" --headless=new --disable-gpu --no-first-run --disable-extensions --hide-scrollbars \
  --window-size=390,900 --user-data-dir="$TMP/profile2" --dump-dom "file://$TMP/wide.html" > "$TMP/dom2.html" 2>/dev/null &
CHROME_PID=$!
for ((i = 0; i < 90; i++)); do
  grep -q '</html>' "$TMP/dom2.html" 2>/dev/null && break
  kill -0 "$CHROME_PID" 2>/dev/null || break
  sleep 0.5
done
kill -9 -- "-$CHROME_PID" 2>/dev/null; wait "$CHROME_PID" 2>/dev/null; CHROME_PID=""
t2="$(grep -oE '<title>[^<]*</title>' "$TMP/dom2.html" | sed -n 1p)"
echo "measured: $t2"
[[ "$t2" == *"WT|SCROLL=0|"* ]] || fail "BL-853: a 6-column table in a consultation item scrolls sideways at 390 px: $t2"
[[ "$t2" == *"|DOC=0|"* ]] || fail "BL-853: a long hash, URL or path widens the page past 390 px: $t2"
[[ "$t2" == *"|OVF=false|"* && "$t2" == *"|CUE=none|"* && "$t2" == *"|MASK=none|"* ]] || fail "BL-853: a stacked table shows the scroll fade or cue it cannot use: $t2"
gap="$(sed -E 's/.*\|GAP=(-?[0-9]+)\|.*/\1/' <<<"$t2")"
awk -v g="$gap" 'BEGIN { exit !(g >= -1 && g <= 6) }' || fail "BL-853: text after <strong> sits ${gap:-?}px from it (a flex cell splits inline formatting; want a space, 6 px at most): $t2"
[[ "$t2" == *"|ROW=block|"* ]] || fail "BL-853: its rows are not stacked (want display:block) at 390 px: $t2"
[[ $failures -eq 0 ]] && { echo "test-narrow-layout: ok"; exit 0; } || exit 1
