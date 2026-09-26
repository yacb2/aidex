#!/usr/bin/env bash
# The GALLERY ROW: one screen state, one figure per tile of the matrix, with a
# verdict and notes of its own (plan 2026-09-22-artifact-gallery-review-unit,
# Phase 1).
#
# Two halves are under test and they are deliberately not the same test:
#
#   the GENERATOR (scripts/gallery-items.sh) turns the project's rows JSON into
#   the markup. It must be deterministic — two runs on one document are byte
#   identical, which is what makes a re-generated round a diff of what actually
#   changed — and it must REFUSE a malformed document with exit 2 and a plain
#   line rather than print half a block.
#
#   the CHECK (check_artifact.py gallery_findings) judges the markup on the
#   page, whoever wrote it. Every cell below has a RED control: the defect it
#   names is asserted to FAIL, with the message that names the row. Without
#   them the rule could be satisfied by a function that returns nothing — and a
#   gallery row is exactly the shape where that silence is invisible, because a
#   row missing a tile still has its options, its notes box and its stable id,
#   so every rule that existed before this one passes it.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
GEN="$SKILL/scripts/gallery-items.sh"
WRAP="$SKILL/scripts/wrap-report.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf '  ok: %s\n' "$*"; }

ROOT="$TMP/checkout"
TILES='light-desktop dark-desktop light-mobile dark-mobile'

# --- the fixture rows document ------------------------------------------------
# The generator opens every tile (it refuses a missing one and writes the
# capture's own width and height on the <img>), so the checkout is real: tiny
# PNGs written here, at a desktop and a phone aspect. The names carry no
# platform suffix — Playwright's `-darwin` is the project's naming, and a
# fixture that copied it read as if the kit depended on it.
png() {  # png <path under ROOT> <width> <height>
  mkdir -p "$(dirname "$ROOT/$1")"
  python3 "$SKILL/tests/png_fixture.py" "$ROOT/$1" "$2" "$3"
}
for cell in with-data empty; do
  png "shots/light-desktop/audit-$cell.png" 160 90
  png "shots/dark-desktop/audit-$cell.png" 160 90
  png "shots/light-mobile/audit-$cell.png" 39 84
  png "shots/dark-mobile/audit-$cell.png" 39 84
done
cat > "$TMP/rows.json" <<'JSON'
{
 "gallery": "audit",
 "shots_dir": "shots",
 "tiles": ["light-desktop", "dark-desktop", "light-mobile", "dark-mobile"],
 "rows": [
  {"cell": "with-data",
   "tiles": {"light-desktop": "shots/light-desktop/audit-with-data.png",
             "dark-desktop": "shots/dark-desktop/audit-with-data.png",
             "light-mobile": "shots/light-mobile/audit-with-data.png",
             "dark-mobile": "shots/dark-mobile/audit-with-data.png"}},
  {"cell": "empty",
   "tiles": {"light-desktop": "shots/light-desktop/audit-empty.png",
             "dark-desktop": "shots/dark-desktop/audit-empty.png",
             "light-mobile": "shots/light-mobile/audit-empty.png",
             "dark-mobile": "shots/dark-mobile/audit-empty.png"}},
  {"cell": "no-permission",
   "notApplicable": "Every role that reaches this screen holds the permission, so the state is unreachable in the demo."}
 ]
}
JSON

gen() { bash "$GEN" "$TMP/rows.json" --root "$ROOT" \
          --group-id E --group-title "Galería audit" "$@"; }

echo "== the generator: what it prints =="

gen > "$TMP/group.html" 2> "$TMP/gen.err"
rc=$?
[[ "$rc" == 0 ]] && ok "a well-formed document generates" \
  || fail "the generator refused a well-formed document (exit $rc): $(cat "$TMP/gen.err")"

# Determinism, asserted as a byte comparison rather than trusted: the output is
# read as a diff between rounds, and a set iteration or a timestamp in it makes
# every round look like a change.
gen > "$TMP/group2.html" 2>/dev/null
cmp -s "$TMP/group.html" "$TMP/group2.html" \
  && ok "two runs are byte identical" \
  || fail "the generator is not deterministic: $(diff "$TMP/group.html" "$TMP/group2.html" | head -5)"

# -- the block ---------------------------------------------------------------
grep -q "<section class=\"consult-group\" id=\"E\" data-id=\"E\" data-title=\"Galería audit\" data-tiles=\"$TILES\">" "$TMP/group.html" \
  && ok "the block declares its id, its title and its matrix in data-tiles" \
  || fail "the block's open tag is not the declared shape: $(head -1 "$TMP/group.html")"
grep -q '<div class="sec-head">' "$TMP/group.html" \
  && grep -q '<h2>Galería audit</h2>' "$TMP/group.html" \
  && ok "the block carries a sec-head with the h2 the rail indexes" \
  || fail "the block has no sec-head/h2"

# -- one item per row, in the document's order --------------------------------
ids="$(grep -o 'consult-item consult-gallery" data-id="[a-z0-9-]*"' "$TMP/group.html" \
       | sed 's/.*data-id="//; s/"//')"
[[ "$ids" == "audit-with-data
audit-empty
audit-no-permission" ]] \
  && ok "one item per row, ids are <gallery>-<cell>, in the document's order" \
  || fail "the item ids are not the rows in order: $ids"
grep -q '<section class="consult-item consult-gallery" data-id="audit-with-data" data-title="audit · with-data">' "$TMP/group.html" \
  && ok "the item carries data-title '<gallery> · <cell>'" \
  || fail "the item's data-title is not '<gallery> · <cell>'"
grep -q '<h3><span class="consult-id">audit-with-data</span>audit · with-data</h3>' "$TMP/group.html" \
  && ok "the h3 shows the id in a .consult-id span" \
  || fail "the h3 is not the declared shape"

# -- the tiles ---------------------------------------------------------------
tiles_seen="$(sed -n '/data-id="audit-with-data"/,/<\/section>/p' "$TMP/group.html" \
              | grep -o 'figure data-tile="[a-z-]*"' | sed 's/.*="//; s/"//' | tr '\n' ' ')"
[[ "$tiles_seen" == "light-desktop dark-desktop light-mobile dark-mobile " ]] \
  && ok "four figures, in the document's tile order" \
  || fail "the tiles are not the declared four in order: '$tiles_seen'"
# width and height are the capture's own pixels: a lazy image with no size
# reserves no box, so the page jumps as each one loads (DevTools flags every
# one of them) and the rail's current-section marker drifts with it.
grep -qF "<figure data-tile=\"light-mobile\"><img src=\"file://$ROOT/shots/light-mobile/audit-with-data.png\" alt=\"audit · with-data · light-mobile\" width=\"39\" height=\"84\" loading=\"lazy\"><figcaption>claro · móvil</figcaption></figure>" "$TMP/group.html" \
  && ok "the figure is a file:// img under --root, with alt, its own width and height, and loading=lazy" \
  || fail "the figure is not the declared shape: $(grep -m1 light-mobile "$TMP/group.html")"
[[ "$(grep -c 'src="file://' "$TMP/group.html")" == 8 ]] \
  && ok "two tiled rows x four tiles = eight images, and the N/A row has none" \
  || fail "expected 8 images, found $(grep -c 'src="file://' "$TMP/group.html")"

# -- the not-applicable row ---------------------------------------------------
na="$(sed -n '/data-id="audit-no-permission"/,/<\/section>/p' "$TMP/group.html")"
grep -q '<p class="gal-na">Every role that reaches this screen holds the permission' <<<"$na" \
  && ok "a notApplicable row carries its reason in a .gal-na" \
  || fail "the N/A row has no .gal-na reason: $na"
grep -q 'class="gal"' <<<"$na" \
  && fail "the N/A row also carries a tile grid — it must carry the reason INSTEAD" \
  || ok "…and no tile grid: the reason replaces the grid, never joins it"
grep -q '<textarea' <<<"$na" && grep -q 'class="opts one"' <<<"$na" \
  && ok "…while keeping the verdict group and the notes box every item needs" \
  || fail "the N/A row lost its verdict group or its notes box"

# -- the verdict group and the notes box --------------------------------------
row="$(sed -n '/data-id="audit-with-data"/,/<\/section>/p' "$TMP/group.html")"
grep -q '<div class="opts one">' <<<"$row" \
  && ok "the verdict group is an .opts one (the kit's only option wrapper)" \
  || fail "the verdict group is not .opts one"
[[ "$(grep -c 'type="radio" name="audit-with-data"' <<<"$row")" == 3 ]] \
  && ok "three radios, all named after the item's id" \
  || fail "expected 3 radios named audit-with-data, found $(grep -c 'type="radio" name="audit-with-data"' <<<"$row")"
for label in Aprobada 'Necesita cambios' 'No puedo juzgarla así'; do
  grep -qF "data-label=\"$label\"" <<<"$row" \
    || fail "the Spanish verdict '$label' is not a data-label — the paste would carry the input value"
done
ok "the three Spanish verdict labels are data-labels, which is what the paste carries"
grep -q 'data-recommended' "$TMP/group.html" \
  && fail "a verdict option is marked data-recommended — the session has not seen the screenshots" \
  || ok "no option is recommended: the row is the reader's call, not the session's"
grep -q '<p class="fieldlabel">Notas sobre esta fila</p>' <<<"$row" \
  && grep -q '<textarea placeholder=' <<<"$row" \
  && ok "the row's own notes box, under its own field label" \
  || fail "the row has no labelled notes textarea"

# -- --lang en ----------------------------------------------------------------
gen --lang en > "$TMP/group-en.html" 2>/dev/null
for needle in 'data-label="Approved"' 'data-label="Needs changes"' \
              'data-label="Cannot judge"' '<figcaption>light · desktop</figcaption>' \
              '<p class="fieldlabel">Notes on this row</p>'; do
  grep -qF "$needle" "$TMP/group-en.html" \
    || fail "--lang en did not produce $needle"
done
ok "--lang en swaps the verdict labels, the tile captions and the field label"
grep -q 'Aprobada' "$TMP/group-en.html" \
  && fail "--lang en left Spanish text in the block" \
  || ok "…and leaves no Spanish behind"

# --- the generator's refusals -------------------------------------------------
# A malformed document is the caller's bug. Exit 2 with one line, and NOTHING on
# stdout: half a block pasted into a page is a defect that reaches the reader.
echo "== the generator: what it refuses =="
refuse() {  # refuse <label> <json> <pattern>
  printf '%s' "$2" > "$TMP/bad.json"
  bash "$GEN" "$TMP/bad.json" --root "$ROOT" --group-id E --group-title T \
    > "$TMP/bad.out" 2> "$TMP/bad.err"
  local rc=$?
  [[ "$rc" == 2 ]] || { fail "$1: expected exit 2, got $rc"; return; }
  grep -q "$3" "$TMP/bad.err" || { fail "$1: expected '$3' in: $(cat "$TMP/bad.err")"; return; }
  grep -qi 'Traceback' "$TMP/bad.err" && { fail "$1: refused with a traceback"; return; }
  [[ -s "$TMP/bad.out" ]] && { fail "$1: printed markup while refusing"; return; }
  ok "$1"
}

refuse "a missing top-level key" \
  '{"gallery":"audit","rows":[]}' \
  "no 'tiles' key"
refuse "a row that is both shown and not applicable" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"a.png"},"notApplicable":"why"}]}' \
  "both 'tiles' and 'notApplicable'"
refuse "a tile the document does not declare" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"a.png","dark-mobile":"b.png"}}]}' \
  "does not declare: dark-mobile"
# Not one of the three the plan names, and it belongs with them: a row that
# simply OMITS a declared tile generates a block the checker then fails, and the
# author reads that failure on the page instead of on the document that caused it.
refuse "a row with no path for a declared tile" \
  '{"gallery":"audit","tiles":["light-desktop","dark-mobile"],"rows":[{"cell":"x","tiles":{"light-desktop":"a.png"}}]}' \
  "no path for tile"
refuse "a row with neither tiles nor a reason" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x"}]}' \
  "neither 'tiles' nor 'notApplicable'"
# --root must be absolute: a file:// URL built from a relative path resolves
# nowhere, and the page renders four broken images that look like missing
# screenshots rather than like a bad flag.
bash "$GEN" "$TMP/rows.json" --root ../elsewhere --group-id E --group-title T \
  > "$TMP/rel.out" 2> "$TMP/rel.err"
rc=$?
[[ "$rc" == 2 ]] && grep -q 'must be an absolute path' "$TMP/rel.err" \
  && ok "a relative --root is refused" \
  || fail "a relative --root was accepted (exit $rc): $(cat "$TMP/rel.err")"
# A tile path with no file behind it: the page used to build, pass the contract
# and show the reader a broken image where the screenshot should be — a row
# nobody can judge, looking like a capture that failed rather than a bad path.
refuse "a tile path with no file under --root" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"shots/light-desktop/audit-gone.png"}}]}' \
  "row 'x'.*tile 'light-desktop'.*no file.*shots/light-desktop/audit-gone.png"
# The width and height come from the PNG header, so a tile that is not a PNG is
# named rather than given a size nobody read.
printf 'not an image' > "$ROOT/shots/fake.png"
# --root / used to strip to "" and the tile was read relative to the CWD: a
# capture present only there was accepted, with the size of an unrelated file.
mkdir -p "$TMP/cwd/zz-cwd-only"
python3 "$SKILL/tests/png_fixture.py" "$TMP/cwd/zz-cwd-only/t.png" 4 4
( cd "$TMP/cwd" && bash "$GEN" <(printf '%s' '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"zz-cwd-only/t.png"}}]}') \
    --root / --group-id E --group-title T ) > "$TMP/rs.out" 2> "$TMP/rs.err"
rc=$?
[[ "$rc" == 2 ]] && grep -q "no file at /zz-cwd-only/t.png" "$TMP/rs.err" && [[ ! -s "$TMP/rs.out" ]] \
  && ok "--root / reads the tile under /, never relative to the working directory" \
  || fail "--root / resolved the tile against the cwd (exit $rc): $(cat "$TMP/rs.err")"
# A PNG header that declares 0x0 is no capture: width="0" height="0" hides it.
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/zero.png" 1 1
python3 - "$ROOT/shots/zero.png" <<'PY'
import struct, sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
b[16:24] = struct.pack(">II", 0, 0); open(p, "wb").write(bytes(b))
PY
refuse "a PNG whose header declares 0x0" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"shots/zero.png"}}]}' \
  "row 'x'.*tile 'light-desktop'.*0x0"
refuse "a tile that is not a PNG" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"shots/fake.png"}}]}' \
  "row 'x'.*tile 'light-desktop'.*not a PNG"

# --- the generated block, wrapped and checked ---------------------------------
# The end of the generator's contract is not its own output but a PAGE: the
# block goes into a body with the minimum the template requires around it — a
# header, the general-notes item, the two copy bars — and wrap-report.sh both
# wraps it and runs the contract.
echo "== the generated block passes the contract, wrapped =="
{
  printf '<div class="page"><main class="main">\n'
  printf '<header><p class="eyebrow">CONSULTA</p><h1>Contrato de interfaz</h1>'
  printf '<p class="standfirst">Cada fila de la galería es un ítem de esta misma página, con su veredicto y sus notas; el botón de copiar se lleva todas las respuestas de una vez.</p></header>\n'
  cat "$TMP/group.html"
  printf '<section class="consult-item consult-notes" data-id="notes" data-title="Notas generales"><h3><span class="consult-id">notes</span>Notas generales</h3><p class="fieldlabel">Lo que no encaja arriba</p><textarea placeholder="Lo que sea…"></textarea></section>\n'
  printf '<div class="endbar"><button type="button" id="consult-copy-end">Copiar mis respuestas</button><span class="consult-status" id="consult-status-end"></span></div>\n'
  printf '</main><aside class="rail"><nav class="raillist" id="raillist"></nav>'
  printf '<div class="consult-bar"><button type="button" id="consult-copy">Copiar mis respuestas</button><span class="consult-status" id="consult-status"></span></div></aside></div>\n'
} > "$TMP/body.html"

bash "$WRAP" --title "Contrato de interfaz" --lang es \
  --in "$TMP/body.html" --out "$TMP/page.html" > "$TMP/wrap.out" 2>&1
rc=$?
[[ "$rc" == 0 ]] && grep -q 'artifact contract OK' "$TMP/wrap.out" \
  && ok "a page built from the generated block passes check-artifact.sh" \
  || fail "the generated page failed the contract (exit $rc): $(cat "$TMP/wrap.out")"

# --- the RED controls: one per rule the check adds ----------------------------
# Each fixture is the passing page with ONE thing wrong. The assertion is the
# FAIL line, not merely a non-zero exit: a rule that fired for another reason
# would be indistinguishable from the one under test.
echo "== the check: a RED control per rule =="

mkpage() {  # mkpage <out> <body>
  {
    printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>Fixture</title>\n<style>\n'
    printf '@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#111; } }\n'
    printf ':root[data-theme="dark"] .consult-bar { background: #111; }\n'
    printf '</style>\n</head>\n<body>\n<div class="page"><main class="main">\n'
    printf '%s\n' "$2"
    printf '</main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>\n'
    printf '<script>var blank = 0;</script>\n</body>\n</html>\n'
  } > "$1"
}

figure() {  # figure <tile>
  printf '<figure data-tile="%s"><img src="file:///abs/checkout/shots/%s.png" alt="audit · with-data · %s" loading="lazy"><figcaption>%s</figcaption></figure>' \
    "$1" "$1" "$1" "$1"
}
galrow() {  # galrow <id> <inner-html>
  printf '<section class="consult-item consult-gallery" data-id="%s" data-title="audit row"><h3><span class="consult-id">%s</span>audit row</h3><p>The cells of this row.</p>%s<div class="opts one"><label><input type="radio" name="%s" data-label="Approved"><span>Approved</span></label></div><p class="fieldlabel">Notes on this row</p><textarea></textarea></section>' \
    "$1" "$1" "$2" "$1"
}
block() {  # block <data-tiles-attr> <items>
  printf '<section class="consult-group" id="E" data-id="E" data-title="The audit gallery"%s><div class="sec-head"><h2>The audit gallery</h2></div><p>The state matrix this block reviews, one row per screen state.</p>%s</section>' \
    "$1" "$2"
}
header='<header><p class="eyebrow">FIXTURE</p><h1>Claim</h1><p class="standfirst">The thesis.</p></header>'
notes='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><textarea></textarea></section>'
bars='<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div>'
tiles_attr=' data-tiles="light-desktop dark-desktop light-mobile dark-mobile"'
all_four="$(figure light-desktop)$(figure dark-desktop)$(figure light-mobile)$(figure dark-mobile)"

# Every fixture declares its visual: a row that is not applicable carries no
# image, so without the declaration those pages fail the visual gate instead of
# the rule under test — and a RED control that goes red for the wrong reason is
# not a control.
fixvisual='<meta name="consult-visual" content="none: the fixture carries only the tiles under test">'
page() {  # page <out> <group-html>
  mkpage "$1" "$fixvisual$header$2$notes$bars"
}
run() { bash "$CHECK" "$1" > "$TMP/out" 2>&1; echo $?; }
red() {  # red <label> <pattern>
  [[ "$rc" == 1 ]] || { fail "$1: expected exit 1, got $rc: $(cat "$TMP/out")"; return; }
  grep -q "$2" "$TMP/out" || { fail "$1: expected '$2' in output: $(cat "$TMP/out")"; return; }
  ok "$1 — $(grep -m1 "$2" "$TMP/out" | sed 's/^ *//' | cut -c1-110)"
}

# (0) the GREEN control: the same fixture with nothing wrong
page "$TMP/ok.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$all_four</div>")")"
rc="$(run "$TMP/ok.html")"
[[ "$rc" == 0 ]] && ok "the complete row passes" \
  || fail "the complete row was rejected: $(cat "$TMP/out")"

# (1) a missing tile — the defect every OTHER rule on the page passes
page "$TMP/missing.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$(figure light-desktop)$(figure dark-desktop)$(figure light-mobile)</div>")")"
rc="$(run "$TMP/missing.html")"; red "a missing tile fails" "audit-with-data.*missing tile(s)\? dark-mobile"

# (2) a duplicated tile: four figures, three distinct cells
page "$TMP/dupe.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$(figure light-desktop)$(figure dark-desktop)$(figure light-mobile)$(figure light-mobile)</div>")")"
rc="$(run "$TMP/dupe.html")"; red "a duplicated tile fails" "audit-with-data.*twice: light-mobile"

# (3) a tile the block does not declare
page "$TMP/unknown.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$all_four$(figure sepia-tv)</div>")")"
rc="$(run "$TMP/unknown.html")"; red "an undeclared tile fails" "audit-with-data.*does not declare: sepia-tv"

# (4) neither tiles nor a reason
page "$TMP/neither.html" "$(block "$tiles_attr" "$(galrow audit-with-data '')")"
rc="$(run "$TMP/neither.html")"; red "a row with neither a tile nor a reason fails" \
  "audit-with-data.*neither a tile nor a not-applicable reason"

# (5) both a grid and a reason
page "$TMP/both.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$all_four</div><p class=\"gal-na\">Unreachable.</p>")")"
rc="$(run "$TMP/both.html")"; red "a row with both a grid and a reason fails" \
  "audit-with-data.*both tiles and a not-applicable reason"

# (6) an id that is not <gallery>-<cell>
page "$TMP/badid.html" "$(block "$tiles_attr" "$(galrow E7 "<div class=\"gal\">$all_four</div>")")"
rc="$(run "$TMP/badid.html")"; red "an id that is not <gallery>-<cell> fails" \
  "E7.*not <gallery>-<cell>"

# (7) a gallery item in a block that declares no matrix — without the
#     declaration nothing can tell a complete row from a truncated one
page "$TMP/nomatrix.html" "$(block "" "$(galrow audit-with-data "<div class=\"gal\">$all_four</div>")")"
rc="$(run "$TMP/nomatrix.html")"; red "a gallery item under a block with no data-tiles fails" \
  "audit-with-data.*not inside a"

# (8) an empty not-applicable reason
page "$TMP/emptyna.html" "$(block "$tiles_attr" "$(galrow audit-no-permission '<p class="gal-na"> </p>')")"
rc="$(run "$TMP/emptyna.html")"; red "an empty gal-na fails" "audit-no-permission.*empty gal-na"

# (9) …and the not-applicable row that IS well formed passes
page "$TMP/na-ok.html" "$(block "$tiles_attr" "$(galrow audit-no-permission '<p class="gal-na">Every role that reaches this screen holds the permission.</p>')")"
rc="$(run "$TMP/na-ok.html")"
[[ "$rc" == 0 ]] && ok "a well-formed not-applicable row passes" \
  || fail "a well-formed N/A row was rejected: $(cat "$TMP/out")"

# (10) a page with no gallery item at all reports nothing here. The rule is
#      unconditional in check_file, so this is the cell that keeps it from
#      judging every ordinary consultation item.
plain='<section class="consult-item" data-id="q1" data-title="An ordinary item"><h3>An ordinary item</h3><div class="opts one"><label><input type="radio" name="q1" data-label="Yes"><span>Yes</span></label></div><p class="fieldlabel">Notes</p><textarea></textarea></section>'
mkpage "$TMP/plain.html" "<meta name=\"consult-visual\" content=\"none: fixtures have no shape to draw\">$header$(block "" "$plain")$notes$bars"
rc="$(run "$TMP/plain.html")"
[[ "$rc" == 0 ]] && ok "an ordinary consultation item is untouched by the gallery rules" \
  || fail "a page with no gallery item was judged by them: $(cat "$TMP/out")"

# (11) the CSS the rows need lives in the kit, not on the page. The round-5 page
#      carried these rules inline, and an inline copy is one page's copy: the
#      next gallery re-derives them and the two drift.
KIT="$SKILL/assets/artifact-kit/components.css"
for sel in '\.gal {' '\.gal img' '\.gal figcaption' '\.gal-na' 'data-tile\$="-mobile"' 'max-width: 700px'; do
  grep -q "$sel" "$KIT" || fail "components.css has no rule for $sel — the gallery grid is unstyled in the kit"
done
ok "components.css carries the grid, the image frame, the mobile cap, the N/A line and the narrow fallback"
grep -nE '\.gal[ -{]' "$KIT" | grep -E '#[0-9a-fA-F]{3,6}' \
  && fail "a .gal rule hard-codes a colour — the kit's tokens are what a project overrides" \
  || ok "…and none of them hard-codes a colour"
grep -E '^\.gal img' "$KIT" | grep -q 'var(--line' \
  && fail "the .gal img border still names --line, a token tokens.css never defines" \
  || ok "the image border uses --rule, the kit's real line token"

# (12) the template documents the block and says it is generated
TPL="$SKILL/assets/templates/consultation-block.html.template"
grep -q 'consult-item consult-gallery' "$TPL" \
  && grep -q 'data-tiles=' "$TPL" \
  && grep -q 'gallery-items.sh' "$TPL" \
  && ok "the template documents the gallery block and names the script that writes it" \
  || fail "the template does not carry a documented gallery block"

# --- the adversarial round: seven ways the first version was satisfiable ------
# Every cell below passed the version shipped on 2026-09-22. They are the shape
# the rule exists to catch, reached from the side the rule was not looking at:
# the row nobody generated, the tag nobody closed, the comment, and four
# documents the generator turned into markup instead of refusing.
echo "== the adversarial round =="

# (F1) THE RULE CANNOT KEY ON A CLASS THE AUTHOR HAS TO REMEMBER. A row written
# by hand — which is how block E existed for five rounds — carries `.gal` and
# `<figure data-tile>` and no `consult-gallery`, and the whole battery went
# silent on it. A gallery item is what a gallery item LOOKS like.
plain_gal() {  # plain_gal <id> <inner>
  printf '<section class="consult-item" data-id="%s" data-title="audit row"><h3><span class="consult-id">%s</span>audit row</h3><p>The cells of this row.</p>%s<div class="opts one"><label><input type="radio" name="%s" data-label="Approved"><span>Approved</span></label></div><p class="fieldlabel">Notes on this row</p><textarea></textarea></section>' \
    "$1" "$1" "$2" "$1"
}
page "$TMP/f1-handmade.html" "$(block "$tiles_attr" "$(plain_gal audit-with-data "<div class=\"gal\">$(figure light-desktop)$(figure dark-desktop)$(figure light-mobile)</div>")")"
rc="$(run "$TMP/f1-handmade.html")"; red "F1 a hand-made row with no consult-gallery class is still judged" \
  "audit-with-data.*missing tile(s)\? dark-mobile"

# …and the figure that carries no data-tile at all: four figures, three tiles,
# and the count the reader sees is right while the matrix is not.
page "$TMP/f1-untiled.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$(figure light-desktop)$(figure dark-desktop)$(figure light-mobile)<figure><img src=\"file:///abs/checkout/shots/x.png\" alt=\"x\"><figcaption>x</figcaption></figure></div>")")"
rc="$(run "$TMP/f1-untiled.html")"; red "F1 a figure inside .gal with no data-tile fails" \
  "audit-with-data.*figure.*no data-tile"

# …while a `.gal-na` is NOT a `.gal` grid: the class token, never the substring.
page "$TMP/f1-na-token.html" "$(block "$tiles_attr" "$(plain_gal audit-no-permission '<p class="gal-na">Every role that reaches this screen holds the permission.</p>')")"
rc="$(run "$TMP/f1-na-token.html")"
[[ "$rc" == 0 ]] && ok "F1 …and .gal-na is read as a reason, not as an empty grid" \
  || fail "F1: .gal-na was read as a .gal grid: $(cat "$TMP/out")"

# (F2) AN UNCLOSED TAG IS NOT A REASON. `_subtree` answers an unclosed element
# with the rest of the item, so `<p class="gal-na">` followed by the options
# read as a reason whose text was the verdict labels — a row with no reason and
# no tiles passing as not applicable.
page "$TMP/f2-unclosed.html" "$(block "$tiles_attr" "$(galrow audit-no-permission '<p class="gal-na">')")"
rc="$(run "$TMP/f2-unclosed.html")"; red "F2 an unclosed gal-na is an empty reason, not the rest of the item" \
  "audit-no-permission.*empty gal-na"

# (F3) A COMMENT IS NOT MARKUP, and every other scan in this file strips them
# first. A previous round's row left commented out failed the page it was
# removed from.
commented="<!-- $(galrow audit-empty "<div class=\"gal\">$(figure light-desktop)$(figure dark-desktop)$(figure light-mobile)</div>") -->"
page "$TMP/f3-comment.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$all_four</div>")$commented")"
rc="$(run "$TMP/f3-comment.html")"
[[ "$rc" == 0 ]] && ok "F3 a commented-out row does not fail the page it was removed from" \
  || fail "F3: a commented-out row was judged: $(cat "$TMP/out")"

# (F4-F7) FOUR DOCUMENTS THE GENERATOR TURNED INTO MARKUP. Each produced a page
# that passed the contract and showed the reader nothing, or something it should
# never have been able to show.
refuse "F4 an absolute row path" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"/etc/passwd.png"}}]}' \
  "relative to the repo root"
refuse "F4 a row path that climbs out of the root" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":"../../elsewhere/a.png"}}]}' \
  "relative to the repo root"
refuse "F5 a null tile path" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light-desktop":null}}]}' \
  "must be a string"
refuse "F6 a tile name with whitespace in the document" \
  '{"gallery":"audit","tiles":["light desktop"],"rows":[]}' \
  "space-separated list"
refuse "F6 a tile name with whitespace in a row" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","tiles":{"light desktop":"a.png"}}]}' \
  "space-separated list"
refuse "F7 a non-string entry in tiles" \
  '{"gallery":"audit","tiles":["light-desktop",7],"rows":[]}' \
  "must be a string"
refuse "a cell name that is not a slug" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"With Data","tiles":{"light-desktop":"a.png"}}]}' \
  "lowercase slugs"

# (lower) --group-id becomes an HTML id and a data-id; anything that is not one
bash "$GEN" "$TMP/rows.json" --root "$ROOT" --group-id 'E"><script>' --group-title T \
  > "$TMP/gid.out" 2> "$TMP/gid.err"
rc=$?
[[ "$rc" == 2 ]] && grep -q 'group-id' "$TMP/gid.err" \
  && ok "a --group-id that is not an html id is refused" \
  || fail "a --group-id of 'E\"><script>' was accepted (exit $rc): $(cat "$TMP/gid.err")"

# (lower) a data-tiles of nothing but spaces declares no matrix
page "$TMP/blank-tiles.html" "$(block ' data-tiles="   "' "$(galrow audit-with-data "<div class=\"gal\">$all_four</div>")")"
rc="$(run "$TMP/blank-tiles.html")"; red "a whitespace-only data-tiles declares no matrix" \
  "audit-with-data.*not inside a"

echo "== the second adversarial round (on the fix diff) =="

# (R1) `str(None)` IS A NON-EMPTY REASON. The fix round gave tile names and
# paths an isinstance guard and left the sibling field in the same row without
# one, so `"notApplicable": null` rendered the word "None" as the reason.
refuse "R1 a null notApplicable" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","notApplicable":null}]}' \
  "notApplicable.*string"
refuse "R1 a non-string notApplicable" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[{"cell":"x","notApplicable":false}]}' \
  "notApplicable.*string"

# (R2) THE UNTILED SCAN LOOKED ONLY INSIDE `.gal` GRIDS, so the hand-made shape
# the F1 fix admitted (tiles with no grid) hid a fifth, unplaceable figure.
page "$TMP/r2-nogrid-untiled.html" "$(block "$tiles_attr" "$(plain_gal audit-with-data "$all_four<figure><img src=\"file:///abs/checkout/shots/x.png\" alt=\"x\"><figcaption>x</figcaption></figure>")")"
rc="$(run "$TMP/r2-nogrid-untiled.html")"; red "R2 an untiled figure outside any .gal grid fails" \
  "audit-with-data.*figure.*no data-tile"

# (R3) AN UNCLOSED gal-na WITH TEXT IS STILL UNCLOSED: the browser swallows the
# radios and the notes into it. F2 covered only the case with no text at all.
page "$TMP/r3-unclosed-text.html" "$(block "$tiles_attr" "$(galrow audit-no-permission '<div class="gal-na">The role never reaches this screen.')")"
rc="$(run "$TMP/r3-unclosed-text.html")"; red "R3 an unclosed gal-na that carries text is an empty reason" \
  "audit-no-permission.*empty gal-na"

# (R4) A BLOCK THAT DECLARES A TILE TWICE hides a missing one: four names, three
# cells, and the row with three tiles passes as complete.
page "$TMP/r4-dupe-decl.html" "$(block 'data-tiles="light-desktop light-desktop dark-desktop light-mobile"' "$(galrow audit-with-data "<div class=\"gal\">$(figure light-desktop)$(figure dark-desktop)$(figure light-mobile)</div>")")"
rc="$(run "$TMP/r4-dupe-decl.html")"; red "R4 a block declaring a tile twice fails" \
  "declares tile(s)\? twice: light-desktop"

# (lower) the dead declaration on .gal figure
grep -E '^\.gal figure \{' "$KIT" | grep -q 'gap:' \
  && fail "the .gal figure rule still sets a gap it does not use" \
  || ok "the .gal figure rule carries no dead declaration"

echo "== the hidden marks channel (Phase 4) =="

# The composer injects <textarea class="kit-marks" hidden> at runtime; a page may
# also carry one (a decided row keeps the marks it was decided with). It is a
# channel into the paste, never the reader's notes box.
marks_ta='<textarea class="kit-marks" hidden>[mark light-desktop 10.0,10.0 20.0x20.0] recorded</textarea>'
nonotes_row="<section class=\"consult-item consult-gallery\" data-id=\"audit-with-data\" data-title=\"audit row\"><h3><span class=\"consult-id\">audit-with-data</span>audit row</h3><p>The cells of this row.</p><div class=\"gal\">$all_four</div><div class=\"opts one\"><label><input type=\"radio\" name=\"audit-with-data\" data-label=\"Approved\"><span>Approved</span></label></div>$marks_ta</section>"
page "$TMP/m1-marks-only.html" "$(block "$tiles_attr" "$nonotes_row")"
rc="$(run "$TMP/m1-marks-only.html")"; red "M1 a hidden kit-marks textarea is not the notes box" \
  "audit-with-data.*no notes box"
# ...and a bare `hidden` textarea is not one either, whatever its class.
page "$TMP/m1b-hidden-only.html" "$(block "$tiles_attr" "${nonotes_row/class=\"kit-marks\" /}")"
rc="$(run "$TMP/m1b-hidden-only.html")"; red "M1b a hidden textarea is not the notes box" \
  "audit-with-data.*no notes box"
# GREEN: the same channel beside the visible notes box passes.
page "$TMP/m2-marks-and-notes.html" "$(block "$tiles_attr" "$(galrow audit-with-data "<div class=\"gal\">$all_four</div>$marks_ta")")"
rc="$(run "$TMP/m2-marks-and-notes.html")"
[[ "$rc" == 0 ]] && ok "M2 a kit-marks textarea beside the notes box passes" \
  || fail "M2 a row with its notes box and a kit-marks textarea was rejected: $(cat "$TMP/out")"

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: the gallery unit — generator, refusals, wrapped page and every RED control"
