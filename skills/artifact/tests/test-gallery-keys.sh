#!/usr/bin/env bash
# test-gallery-keys.sh — the gallery zoom dialog's keyboard marks under REAL key
# presses (Playwright, trusted events). Layer: the browser, because what is under
# test is the browser's own default action — the synthetic keys of
# test-composer-functional.sh reach the page's handlers but not those, so Esc
# against the dialog's native close and Enter on a focused dialog button are only
# provable here. This file owns those two contracts; the synthetic harness keeps
# the handler arithmetic (move, resize, clamp).
#
# The page is a gallery consultation built the normal route (rows JSON ->
# gallery-items.sh -> wrap-report.sh) over PNGs written at test time.
# Without Playwright (AIDEX_PLAYWRIGHT_DIR or a global install) it prints SKIP
# and exits 2, which run-all.sh reports as a skip, never as a pass.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd -P)"
FIX="$HERE/fixtures/render-probe/gallery"
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

GROOT="$TMP/root"
for d in shots actual; do for cell in with-data empty; do
  for t in light-desktop dark-desktop; do
    mkdir -p "$GROOT/$d/$t" && python3 "$HERE/png_fixture.py" "$GROOT/$d/$t/audit-$cell.png" 400 200
  done
  for t in light-mobile dark-mobile; do
    mkdir -p "$GROOT/$d/$t" && python3 "$HERE/png_fixture.py" "$GROOT/$d/$t/audit-$cell.png" 100 200
  done
done; done
# A states row rides along: its arrows walk ITS states, not the block's before/after.
for st in default hover loading; do python3 "$HERE/png_fixture.py" "$GROOT/shots/btn-$st.png" 120 60; done
python3 - "$FIX/rows.json" "$TMP/rows.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"].append({"cell": "btn", "variant": "light-desktop", "kind": "states",
                  "states": [{"id": i, "label": i.title(), "capture": "shots/btn-%s.png" % i}
                             for i in ("default", "hover", "loading")]})
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$SCRIPTS/gallery-items.sh" "$TMP/rows.json" --root "$GROOT" --page "$TMP/page.html" --group-id E \
  --group-title "Galería audit" > "$TMP/group.html" || { echo "FAIL: gallery-items.sh refused the fixture"; exit 1; }
python3 - "$FIX/frame.html" "$TMP/group.html" "$TMP/body.html" <<'PY'
import sys
frame, group = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
open(sys.argv[3], "w", encoding="utf-8").write(frame.replace("<!-- GALLERY -->", group))
PY
( cd "$TMP" && bash "$SCRIPTS/wrap-report.sh" --title "Galería" --lang es --in "$TMP/body.html" --out "$TMP/page.html" ) >/dev/null 2>&1 \
  || { echo "FAIL: wrap-report failed on the gallery page"; exit 1; }

json="$(AIDEX_PLAYWRIGHT_MODULE="$(dirname "$module")" node "$HERE/gallery_keys.mjs" "$TMP/page.html" 2>"$TMP/err")" \
  || { echo "FAIL: the key probe crashed: $(cat "$TMP/err")"; exit 1; }
check() {  # check <python expression over d> <label>
  if python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if eval(sys.argv[2]) else 1)' "$json" "$1" 2>/dev/null
  then ok "$2"; else fail "$2: $json"; fi
}
check 'd["arrow"]["drafts"] == 1 and d["arrow"]["left"] == "41%" and d["arrow"]["tile"] == "before"' \
  "a real ArrowRight moves the draft one percent and does not walk the tile"
check 'd["states"]["next"] == "loading" and d["states"]["back"] == "hover"' \
  "a real ArrowRight/ArrowLeft in the zoom dialog walks a states row's own states"
check 'd["esc"]["zoom"] and d["esc"]["drafts"] == 0 and d["esc"]["marks"] == ""' \
  "a real Esc during a draft drops the draft and leaves the dialog open"
check 'd["enter"]["note"] and d["enter"]["zoom"]' \
  "a real Enter during a draft asks for the region's note"
check 'd["noteEsc"]["zoom"] and not d["noteEsc"]["note"] and d["noteEsc"]["drafts"] == 0 and d["noteEsc"]["marks"] == ""' \
  "a real Esc on the note dialog cancels it, keeps the zoom open and stores nothing"
check 'not d["closeEnter"]["zoom"] and not d["closeEnter"]["note"] and d["closeEnter"]["drafts"] == 0 and d["closeEnter"]["marks"] == ""' \
  "a real Enter on the focused Close button during a draft presses Close, never saves the region"

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: real Esc, Enter and arrows on the zoom dialog's keyboard marks"
