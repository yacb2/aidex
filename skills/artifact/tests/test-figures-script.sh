#!/usr/bin/env bash
# The § Figures DevTools script, run against fixtures in a real engine.
#
# It is canon that SHIPS: 02-local-first-artifacts.md tells the author to run it
# on the opened page before the wrap, and it is the check that settles a figure.
# Until this file nothing ever executed it, and it produced a wrong answer that
# was acted on — every one of Graphviz DOT's 16 marks in a seven-route
# comparison was the same artifact, the two lines of one wrapped node label
# whose boxes touch by a pixel. DOT read as "8 defects" against hand-SVG's 0
# when the true reading was 0 and 0 (BL-329).
#
# The script is EXTRACTED from the canon rather than copied here. A copy is a
# second source that drifts, and the thing under test is the text an author is
# told to paste.
#
# Skips loudly with no Chrome, like test-composer-functional.sh.
set -uo pipefail
SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CANON="$SKILL/references/02-local-first-artifacts.md"
TMP="$(mktemp -d /tmp/figscript-XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

CHROME=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "$(command -v google-chrome 2>/dev/null || true)" \
         "$(command -v chromium 2>/dev/null || true)"; do
  [[ -n "$c" && -x "$c" ]] && { CHROME="$c"; break; }
done
if [[ -z "$CHROME" ]]; then
  echo "SKIP: no Chrome/Chromium binary found — the figures script test DID NOT RUN"
  exit 0
fi

# The first ```js fence under the § Figures heading.
python3 - "$CANON" > "$TMP/fig.js" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
i = t.index("### Figures: the checker estimates, the browser measures")
m = re.search(r"```js\n(.*?)```", t[i:], re.S)
assert m, "no ```js fence under the Figures heading"
src = m.group(1)
assert "getBoundingClientRect" in src, "the extracted fence is not the measuring script"
sys.stdout.write(src)
PY
[[ -s "$TMP/fig.js" ]] || { fail "could not extract the script from the canon"; echo "1 failure(s)"; exit 1; }

# Three shapes in one page, so one run answers both directions:
#   fig 1 — a WRAPPED node label: two <text> under the node's own <g>, boxes
#           touching. The false positive. Must report nothing.
#   fig 2 — two <text> in one <g>, on top of each other. Must still report.
#   fig 3 — two independent <text> overlapping. Must still report.
cat > "$TMP/page.html" <<'HTML'
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>fig</title></head><body>
<svg width="400" height="120" viewBox="0 0 400 120" font-size="12" font-family="system-ui">
  <g><text x="100" y="40" text-anchor="middle">work hours kiosk</text>
     <text x="100" y="53" text-anchor="middle">stack (backend)</text></g>
</svg>
<svg width="400" height="120" viewBox="0 0 400 120" font-size="12" font-family="system-ui">
  <g><text x="30" y="40">alpha label here</text>
     <text x="30" y="41">beta label here</text></g>
</svg>
<svg width="400" height="120" viewBox="0 0 400 120" font-size="12" font-family="system-ui">
  <g><text x="30" y="40">gamma label here</text></g>
  <g><text x="60" y="42">delta label here</text></g>
</svg>
<script>
window.addEventListener('load', function () {
  var out;
  try { out = (FIGCHECK)(); } catch (e) { out = ['THREW: ' + e.message]; }
  document.title = 'FIG|' + JSON.stringify(out).replace(/[|<>]/g, ' ');
});
</script>
</body></html>
HTML
python3 - "$TMP/page.html" "$TMP/fig.js" <<'PY'
import sys
page = open(sys.argv[1], encoding="utf-8").read()
js = open(sys.argv[2], encoding="utf-8").read().strip()
open(sys.argv[1], "w", encoding="utf-8").write(page.replace("FIGCHECK", js))
PY

# The same watchdog test-composer-functional.sh carries, and for the same
# reason: Chrome's teardown after --dump-dom hangs nondeterministically on this
# machine — the DOM is fully written and the process never exits. Without it
# this test wedged for the full command timeout on its first run. Completion is
# detected by </html> in the FILE, so a hang costs seconds; perl's setpgrp makes
# Chrome a group leader so the kill takes its helpers with it.
: > "$TMP/dom.html"
perl -e 'setpgrp(0,0); exec @ARGV' \
  "$CHROME" --headless=new --disable-gpu --no-first-run --disable-extensions \
            --user-data-dir="$TMP/profile" --dump-dom "file://$TMP/page.html" \
  > "$TMP/dom.html" 2>/dev/null &
pid=$!
for ((i = 0; i < 60; i++)); do
  kill -0 "$pid" 2>/dev/null || break
  grep -q '</html>' "$TMP/dom.html" 2>/dev/null && break
  sleep 0.5
done
kill -TERM -- "-$pid" 2>/dev/null
sleep 1
kill -9 -- "-$pid" 2>/dev/null
wait "$pid" 2>/dev/null
t="$(grep -oE '<title>[^<]*</title>' "$TMP/dom.html" | head -1)"
[[ "$t" == *FIG* ]] || { fail "the script never ran: $t"; echo "$failures failure(s)"; exit 1; }
[[ "$t" == *THREW* ]] && fail "the canon's script threw: $t"

# BL-329: the two lines of one wrapped label are not an overlap.
[[ "$t" == *"work hours kiosk"* ]] \
  && fail "BL-329: the two lines of one wrapped node label are still reported as overlapping: $t"
# ...and the halves that must not be traded away.
[[ "$t" == *"alpha label here"* ]] \
  || fail "BL-329: two texts on top of each other inside one <g> stopped being reported: $t"
[[ "$t" == *"gamma label here"* ]] \
  || fail "BL-329: a genuine overlap between two independent labels stopped being reported: $t"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — the canon's § Figures script runs, reports a real overlap in and across groups, and no longer reports the two lines of one wrapped label"
