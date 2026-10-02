#!/usr/bin/env bash
# test-gallery-readable.sh — a gallery row the owner can read by LOOKING
# (BL-577 title, BL-578 zoom label off the capture, BL-588 localized approve,
# BL-589 stacked pair, BL-594 variant once, BL-595 one instruction, BL-596
# highlight). Two layers on purpose: the generator's markup (rows JSON ->
# gallery-items.sh: text, counts, refusals) and the browser (rail text, where
# the label and the outline land in pixels, overflow at 390 px), because a
# stylesheet and a composer are what decide the second half. The reply parser
# is exercised on a reply headed as the titled page pastes it, since that
# heading is the contract gallery-reply.sh keys on.
# The browser half prints SKIP for itself when Playwright is missing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd -P)"
FIX="$HERE/fixtures/render-probe/gallery"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf '  ok: %s\n' "$*"; }

ROOT="$TMP/root"
png() { mkdir -p "$(dirname "$ROOT/$1")"; python3 "$HERE/png_fixture.py" "$ROOT/$1" "$2" "$3"; }
for d in shots actual; do
  png $d/users-list-menu.png 400 200
  png $d/new-screen.png 400 200
  png $d/phone.png 100 200
done
cat > "$TMP/rows.json" <<'JSON'
{"gallery": "audit", "variants": ["light-desktop", "dark-mobile"],
 "rows": [
  {"cell": "users-list-menu", "variant": "light-desktop", "kind": "review",
   "title": "Lista de usuarios: menú de acciones de un usuario invitado",
   "highlight": {"x": 40, "y": 20, "w": 80, "h": 40},
   "highlight_before": {"x": 200, "y": 100, "w": 100, "h": 50},
   "before": "shots/users-list-menu.png", "after": "actual/users-list-menu.png"},
  {"cell": "new-screen", "variant": "light-desktop", "kind": "review",
   "after": "actual/new-screen.png"},
  {"cell": "phone", "variant": "dark-mobile", "kind": "review",
   "before": "shots/phone.png", "after": "actual/phone.png"}
 ]}
JSON
gen() { bash "$SCRIPTS/gallery-items.sh" "${1:-$TMP/rows.json}" --root "$ROOT" --page "$TMP/page.html" \
          --group-id E --group-title "Revisión audit" "${@:2}"; }
item() { sed -n "/data-id=\"$1\"/,/<\/section>/p" "$2"; }
gen > "$TMP/g.html" 2> "$TMP/g.err" || { echo "FAIL: generator refused: $(cat "$TMP/g.err")"; exit 1; }
ROW=audit-users-list-menu-light-desktop
pair="$(item $ROW "$TMP/g.html")"

echo "== BL-577: a row's heading is its title; without one, a readable name =="
grep -qF '<h3>Lista de usuarios: menú de acciones de un usuario invitado</h3>' <<<"$pair" \
  && grep -qF 'data-heading="Lista de usuarios: menú de acciones de un usuario invitado"' <<<"$pair" \
  && ok "the title is the heading, with no slug id beside it" \
  || fail "the heading is not the title: $(head -3 <<<"$pair")"
grep -q 'data-title="audit · users-list-menu · light-desktop"' <<<"$pair" \
  && ok "data-title stays the machine key the reply parser reads" \
  || fail "data-title moved off the key"
new="$(item audit-new-screen-light-desktop "$TMP/g.html")"
grep -qF '<h3>New screen</h3>' <<<"$new" && ! grep -q '<h3>[^<]* · ' <<<"$new" \
  && ok "a row without a title reads its cell as words, never <gallery> · <cell> · <variant>" \
  || fail "the fallback heading is wrong: $(grep '<h3' <<<"$new")"

echo "== BL-594: the variant once, below the capture, in words =="
[[ "$(grep -c 'gal-variant' <<<"$pair")" == 1 ]] \
  && grep -qF '<p class="gal-variant">Vista: escritorio, tema claro</p>' <<<"$pair" \
  && [[ "$(grep -n 'class="gal' <<<"$pair" | sed -n 1p | cut -d: -f1)" -lt "$(grep -n 'gal-variant' <<<"$pair" | cut -d: -f1)" ]] \
  && ok "one 'Vista: escritorio, tema claro' line, after the captures" \
  || fail "the variant line is wrong: $pair"
grep -qF 'Vista: móvil, tema oscuro' <<<"$(item audit-phone-dark-mobile "$TMP/g.html")" \
  && ok "dark + mobile reads 'móvil, tema oscuro'" || fail "the mobile variant line is wrong"
gen "$TMP/rows.json" --lang en 2>/dev/null | grep >/dev/null -F '<p class="gal-variant">View: desktop, light theme</p>' \
  && ok "…and 'View: desktop, light theme' on an English page" || fail "the English variant line is wrong"
grep -qi 'claro · escritorio' "$TMP/g.html" \
  && fail "the jargon variant label is still on the page" || ok "the jargon label '<mode> · <viewport>' is gone"

echo "== BL-595: the instruction once, at the top =="
[[ "$(grep -c 'Marca tu respuesta' "$TMP/g.html")" == 1 ]] \
  && [[ "$(grep -n 'gal-intro' "$TMP/g.html" | cut -d: -f1)" -lt "$(grep -n 'consult-item' "$TMP/g.html" | sed -n 1p | cut -d: -f1)" ]] \
  && ! grep -q 'si necesita cambios' <<<"$pair" \
  && ok "'Marca tu respuesta' appears once, before the first row, and no row repeats it" \
  || fail "the instruction is not once at the top: $(grep -c 'Marca tu respuesta' "$TMP/g.html")"
grep -q 'una sola captura' "$TMP/g.html" && ok "the no-before note is in that one paragraph" || fail "the new-screen note is missing from the intro"

echo "== BL-588: the approve option says referencia, not baseline =="
grep -qF '<span>Aprobada: lo propuesto queda como referencia</span>' <<<"$pair" && ! grep -qi baseline "$TMP/g.html" \
  && ok "the Spanish approve text is localized" || fail "the approve text is wrong: $(grep -o 'Aprobada[^<]*' <<<"$pair")"

echo "== BL-596: highlight, in capture pixels =="
[[ "$(grep -o 'class="gal-hl"' <<<"$pair" | wc -l | tr -d ' ')" == 2 ]] \
  && [[ "$(grep -o 'left:10%;top:10%;width:20%;height:20%' <<<"$pair" | wc -l | tr -d ' ')" == 1 ]] \
  && [[ "$(grep -o 'left:50%;top:50%;width:25%;height:25%' <<<"$pair" | wc -l | tr -d ' ')" == 1 ]] \
  && ok "highlight 40,20 80x40 is 10%,10% 20%x20% on the after; highlight_before is its own box on the before" \
  || fail "the highlight markup is wrong: $(grep -o 'gal-hl[^>]*' <<<"$pair")"
python3 - "$TMP/rows.json" "$TMP/nob.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); del d["rows"][0]["highlight_before"]
json.dump(d, open(sys.argv[2], "w"))
PY
gen "$TMP/nob.json" > "$TMP/nob.html" 2>/dev/null
nob="$(item $ROW "$TMP/nob.html")"
[[ "$(grep -o 'class="gal-hl"' <<<"$nob" | wc -l | tr -d ' ')" == 1 ]] \
  && grep -q 'data-tile="after".*gal-hl' <<<"$nob" && ! grep -q 'data-tile="before".*gal-hl' <<<"$nob" \
  && ok "without highlight_before the before carries no outline" || fail "the before drew a highlight it was not given"
grep -q 'gal-hl' <<<"$new" && fail "a row without highlight draws one" || ok "no highlight, no overlay"
refuse() {  # refuse <label> <highlight json> <message part>
  python3 - "$TMP/rows.json" "$TMP/bad.json" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][0]["highlight"] = json.loads(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"))
PY
  msg="$(gen "$TMP/bad.json" 2>&1 >/dev/null)"; rc=$?
  [[ $rc == 2 && "$msg" == *"$3"* ]] && ok "$1" || fail "$1 (rc=$rc): $msg"
}
refuse "a region past the capture's edge is refused" '{"x":380,"y":0,"w":50,"h":10}' "runs outside"
refuse "a region with a missing key is refused" '{"x":1,"y":1,"w":5}' "highlight is"
refuse "a zero-size region is refused" '{"x":1,"y":1,"w":0,"h":5}' "w, h > 0"
refuse "an empty list is refused" '[]' "empty list"
python3 - "$TMP/rows.json" "$TMP/bad2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][0]["highlight_before"] = {"x": 390, "y": 0, "w": 50, "h": 10}
json.dump(d, open(sys.argv[2], "w"))
PY
msg="$(gen "$TMP/bad2.json" 2>&1 >/dev/null)"; [[ "$msg" == *"runs outside"* ]] \
  && ok "highlight_before is validated against the before capture" || fail "highlight_before not validated: $msg"

echo "== BL-607: \"highlight\": \"@name\" resolves from <capture>.regions.json =="
png shots/named.png 1600 900
png shots/named-before.png 1600 900
cat > "$ROOT/shots/named.regions.json" <<'JSON'
{"error": {"x": 120, "y": 340, "w": 200, "h": 24}, "bad": {"x": 1}, "lst": [{"x": 1, "y": 1, "w": 5, "h": 5}, {"x": 9, "y": 9, "w": 5, "h": 5}], "str": "@other", "wide": {"x": 1500, "y": 0, "w": 200, "h": 10}}
JSON
cat > "$ROOT/shots/named-before.regions.json" <<'JSON'
{"old": {"x": 800, "y": 450, "w": 160, "h": 90}}
JSON
named() {  # named <highlight json> [<highlight_before json>] -> rows file
  python3 - "$TMP/named.json" "$1" "${2:-}" <<'PY'
import json, sys
row = {"cell": "hlrow", "variant": "light-desktop", "kind": "review",
       "before": "shots/named-before.png", "after": "shots/named.png",
       "highlight": json.loads(sys.argv[2])}
if sys.argv[3]: row["highlight_before"] = json.loads(sys.argv[3])
json.dump({"gallery": "audit", "variants": ["light-desktop"], "rows": [row]}, open(sys.argv[1], "w"))
PY
}
named '"@error"' '"@old"'
gen "$TMP/named.json" > "$TMP/named.html" 2> "$TMP/named.err" \
  || fail "a named highlight was refused: $(cat "$TMP/named.err")"
nm="$(item audit-hlrow-light-desktop "$TMP/named.html")"
grep -q 'data-tile="after".*left:7.5%;top:37.778%;width:12.5%;height:2.667%' <<<"$nm" \
  && grep -q 'data-tile="before".*left:50%;top:50%;width:10%;height:10%' <<<"$nm" \
  && ok "@error is 120/1600, 340/900 and its size in percent on the after; @old on the before sidecar" \
  || fail "the named highlight markup is wrong: $(grep -o 'gal-hl[^>]*' <<<"$nm")"
named '{"x":120,"y":340,"w":200,"h":24}'
literal="$(gen "$TMP/named.json" 2>/dev/null | grep -o 'gal-hl" style="[^"]*"')"
[[ "$literal" == "$(grep -o 'gal-hl" style="[^"]*"' <<<"$(item audit-hlrow-light-desktop "$TMP/named.html")" | sed -n 2p)" ]] \
  && ok "the literal form still draws the same box" || fail "named and literal differ: $literal"
refuse_named() {  # refuse_named <label> <highlight json> <message part>
  named "$2"; msg="$(gen "$TMP/named.json" 2>&1 >/dev/null)"; rc=$?
  [[ $rc == 2 && "$msg" == *"row 'hlrow'"* && "$msg" == *"$3"* ]] && ok "$1" || fail "$1 (rc=$rc): $msg"
}
refuse_named "an unknown name is refused, naming the cell" '"@missing"' "is not in"
refuse_named "a malformed sidecar entry names the sidecar" '"@bad"' "named.regions.json"
refuse_named "a list sidecar entry is refused, not cut to its first box" '"@lst"' "named.regions.json"
refuse_named "a string sidecar entry is refused, not a traceback" '"@str"' "named.regions.json"
refuse_named "a region outside the capture is refused" '"@wide"' "runs outside"
refuse_named "a name that is not @name is refused" '"@a b"' "a named highlight is"
rm "$ROOT/shots/named.regions.json"
refuse_named "a missing sidecar is refused" '"@error"' "is missing"

echo "== layout: a pair sits side by side by default (owner 2026-10-01); stacked only on request =="
! grep -q 'gal stacked' <<<"$pair" && ! grep -q 'gal stacked' <<<"$(item audit-phone-dark-mobile "$TMP/g.html")" \
  && ok "a desktop pair and a mobile pair both sit side by side" || fail "the default layout is not side by side"

echo "== BL-577: a reply headed as the titled page pastes it still parses =="
python3 - "$TMP/reply.md" <<'PY'
import sys
open(sys.argv[1], "w").write("""## E · Revisión audit
### audit-users-list-menu-light-desktop · audit · users-list-menu · light-desktop

- Necesita cambios

El botón queda tapado.
""")
PY
bash "$SCRIPTS/gallery-reply.sh" "$TMP/reply.md" 2>&1 | python3 -c '
import json, sys
r = json.load(sys.stdin)["rows"]
sys.exit(0 if len(r) == 1 and r[0]["cell"] == "users-list-menu" and r[0]["verdict"] == "Necesita cambios" else 1)' \
  && ok "the row id, cell and verdict come back" || fail "the reply did not round-trip"

echo "== the browser: rail, label, outline, overflow =="
module=""
if [[ -n "${AIDEX_PLAYWRIGHT_DIR:-}" && -f "$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright/package.json" ]]; then
  module="$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright"
else
  g="$(npm root -g 2>/dev/null || true)"; [[ -n "$g" && -f "$g/playwright/package.json" ]] && module="$g/playwright"
fi
if [[ -z "$module" ]] || ! command -v node >/dev/null 2>&1; then
  echo "SKIP: Playwright not found — the browser half did not run"
else
  python3 - "$FIX/frame.html" "$TMP/g.html" "$TMP/body.html" <<'PY'
import sys
frame, group = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
open(sys.argv[3], "w", encoding="utf-8").write(frame.replace("<!-- GALLERY -->", group))
PY
  ( cd "$TMP" && bash "$SCRIPTS/wrap-report.sh" --title "Galería" --lang es --in "$TMP/body.html" --out "$TMP/page.html" ) >/dev/null 2>&1 \
    || { echo "FAIL: wrap-report failed"; exit 1; }
  json="$(AIDEX_PLAYWRIGHT_MODULE="$(dirname "$module")" node "$HERE/gallery_readable.mjs" "$TMP/page.html" 2>"$TMP/err")" \
    || { echo "FAIL: the probe crashed: $(cat "$TMP/err")"; exit 1; }
  check() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if eval(sys.argv[2]) else 1)' "$json" "$1" 2>/dev/null \
            && ok "$2" || fail "$2: $json"; }
  check 'd["desktop"]["rail"][1] == {"text": "Lista de usuarios: menú de acciones de un usuario invitado", "rid": False}' \
    "the rail lists the row by its title, with no slug beside it"
  check 'd["desktop"]["heading"].startswith("Lista de usuarios")' "the rendered heading is the title"
  check 'd["desktop"]["sideBySide"]' "after sits beside before at the same width"
  check 'd["desktop"]["frac"] == [10, 10, 20, 20] and d["desktop"]["fracBefore"] == [50, 50]' \
    "the outline lands on its own fraction of the after and of the before capture"
  check 'd["desktop"]["hlStyle"]["bg"] in ("rgba(0, 0, 0, 0)", "transparent") and d["desktop"]["hlStyle"]["outline"] == "solid" and float(d["desktop"]["hlStyle"]["offset"]) >= 3 and d["desktop"]["hlStyle"]["border"] == "0px"' \
    "the outline has no fill, no border and sits at least 3 px outside the region"
  check 'd["desktop"]["zoomLabelPosition"] == "static" and d["desktop"]["zoomLabel"] == "\"Ampliar\"" and d["desktop"]["figureBottom"] > d["desktop"]["imgBottom"]' \
    "Ampliar sits in the flow below the capture, covering none of it"
  check 'd["zoom"]["open"] and d["zoom"]["boxes"] == 1 and d["zoom"]["frac"] == [10, 10, 20, 20]' \
    "the zoom view draws the same outline over the enlarged capture"
  check 'd["phone"]["overflow"] <= 0 and not d["phone"]["imgPastEdge"]' "at 390 px nothing overflows the page"
fi

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: readable gallery rows — title, variant once, one instruction, highlight, pair side by side, localized approve"
