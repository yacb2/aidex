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

ROOT="$TMP/repo"
# The page every generated block is for: the captures are copied beside it,
# into $TMP/page-assets/gallery/ (BL-474).
PAGE="$TMP/page.html"
TILES='light-desktop dark-desktop light-mobile dark-mobile'

# --- the fixture rows document ------------------------------------------------
# The contract the project's emitter prints (gallery_board.py --rows-json): the
# variants the owner chose, and per row one cell in one variant as the pair
# baseline ("before") / the run's render ("after"). A new screen has no
# "before"; a cell that moved outside the change set is `kind: "unrequested"`.
# The generator opens every capture, so the checkout is real: tiny PNGs written
# here, at a desktop and a phone aspect.
png() {  # png <path under ROOT> <width> <height> [grey]
  mkdir -p "$(dirname "$ROOT/$1")"
  python3 "$SKILL/tests/png_fixture.py" "$ROOT/$1" "$2" "$3" ${4:-}
}
# A before differs from its after (grey 96 vs the default 128): a live pair with identical
# pixels is refused (LOOP-008 Q8).
png shots/light-desktop/audit-empty.png 160 90 96
png actual/light-desktop/audit-empty.png 160 90
png actual/light-desktop/audit-new-state.png 160 90
png shots/dark-mobile/audit-loaded.png 39 84 96
png actual/dark-mobile/audit-loaded.png 39 84
cat > "$TMP/rows.json" <<'JSON'
{
 "gallery": "audit", "variants": ["light-desktop"],
 "shots_dir": "shots", "actual_dir": "actual",
 "rows": [
  {"cell": "empty", "variant": "light-desktop", "kind": "review",
   "before": "shots/light-desktop/audit-empty.png", "after": "actual/light-desktop/audit-empty.png"},
  {"cell": "new-state", "variant": "light-desktop", "kind": "review",
   "after": "actual/light-desktop/audit-new-state.png"},
  {"cell": "loaded", "variant": "dark-mobile", "kind": "unrequested",
   "before": "shots/dark-mobile/audit-loaded.png", "after": "actual/dark-mobile/audit-loaded.png"}
 ]
}
JSON

gen() { bash "$GEN" "$TMP/rows.json" --root "$ROOT" --page "$PAGE" \
          --group-id E --group-title "Revisión audit" "$@"; }
item() { sed -n "/data-id=\"$1\"/,/<\/section>/p" "$2"; }

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
  || fail "the generator is not deterministic: $(diff "$TMP/group.html" "$TMP/group2.html" | sed -n 1,5p)"

grep -q '<section class="consult-group" id="E" data-id="E" data-title="Revisión audit" data-tiles="before after">' "$TMP/group.html" \
  && ok "the block declares its id, its title and the before/after pair in data-tiles" \
  || fail "the block's open tag is not the declared shape: $(head -1 "$TMP/group.html")"
grep -q '<h2>Revisión audit</h2>' "$TMP/group.html" \
  && ok "the block carries the h2 the rail indexes" || fail "the block has no h2"

# -- row ids: stable across rounds, from names only ---------------------------
# An id carrying a counter or the row's position would move when a row is
# added above it, and the reader's stored answer would land on another row.
ids="$(grep -o 'consult-item consult-gallery" data-id="[a-z0-9-]*"' "$TMP/group.html" \
       | sed 's/.*data-id="//; s/"//')"
[[ "$ids" == "audit-empty-light-desktop
audit-new-state-light-desktop
audit-loaded-dark-mobile-unrequested" ]] \
  && ok "ids are <gallery>-<cell>-<variant>, -unrequested on an unrequested row, in document order" \
  || fail "the item ids are not the declared shape: $ids"
python3 - "$TMP/rows.json" "$TMP/rows-reordered.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"].reverse()
d["rows"].insert(0, {"cell": "error", "variant": "light-desktop", "kind": "review",
                     "after": "actual/light-desktop/audit-new-state.png"})
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rows-reordered.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/reord.html" 2>/dev/null
[[ "$(item audit-empty-light-desktop "$TMP/reord.html")" == "$(item audit-empty-light-desktop "$TMP/group.html")" ]] \
  && ok "a row keeps its id and its markup when rows are added and reordered around it" \
  || fail "the empty row changed when the document around it did"

# -- the pair -----------------------------------------------------------------
pair="$(item audit-empty-light-desktop "$TMP/group.html")"
grep -q 'data-title="audit · empty · light-desktop" data-heading="Empty" data-variant="light-desktop">' <<<"$pair" \
  && ok "the item carries data-title '<gallery> · <cell> · <variant>' (the reply's key), its readable data-heading and its variant" \
  || fail "the pair's open tag is not the declared shape: $(head -1 <<<"$pair")"
grep -q 'data-tiles=' <<<"$pair" \
  && fail "a row with a before narrows the matrix — it must show the whole pair" \
  || ok "a row with a before keeps the block's before/after matrix"
[[ "$(grep -o 'figure data-tile="[a-z]*"' <<<"$pair" | tr '\n' ' ')" == 'figure data-tile="before" figure data-tile="after" ' ]] \
  && ok "the pair is two figures, before then after" \
  || fail "the pair is not before then after: $(grep -o 'figure data-tile="[a-z]*"' <<<"$pair")"
# Each src is the capture's copy beside the page, named by its content (BL-474).
copy() { printf 'page-assets/gallery/%s.png' "$(shasum -a 256 "$ROOT/$1" | cut -c1-16)"; }
grep -qF "<figure data-tile=\"before\"><img src=\"$(copy shots/light-desktop/audit-empty.png)\" alt=\"Empty · antes\" width=\"160\" height=\"90\" loading=\"lazy\"><figcaption>antes</figcaption></figure>" <<<"$pair" \
  && grep -qF "<figure data-tile=\"after\"><img src=\"$(copy actual/light-desktop/audit-empty.png)\"" <<<"$pair" \
  && grep -qF '<figcaption>propuesto</figcaption>' <<<"$pair" \
  && ok "before is the baseline labelled 'antes', after the run's render labelled 'propuesto', each with its own size" \
  || fail "the pair's figures are not the declared shape: $(grep figure <<<"$pair")"
grep -q '<p class="gal-variant">Vista: escritorio, tema claro</p>' <<<"$pair" \
  && ok "the row names its variant once, under the captures, in words of the page's language" \
  || fail "the row does not name its variant: $pair"

# -- a new screen: one capture ------------------------------------------------
new="$(item audit-new-state-light-desktop "$TMP/group.html")"
grep -q 'data-variant="light-desktop" data-tiles="after">' <<<"$new" \
  && ok "a row with no before narrows its matrix to after" \
  || fail "the new-screen row does not declare data-tiles=\"after\": $(head -1 <<<"$new")"
[[ "$(grep -c '<figure' <<<"$new")" == 1 ]] && grep -q '<figure data-tile="after">.*<figcaption>pantalla nueva</figcaption>' <<<"$new" \
  && ok "…and shows the one capture, labelled as a new screen" \
  || fail "the new-screen row is not one 'pantalla nueva' capture: $(grep figure <<<"$new")"

# -- the unrequested change ---------------------------------------------------
unreq="$(item audit-loaded-dark-mobile-unrequested "$TMP/group.html")"
grep -q '<p class="gal-flag">cambió sin que lo pidieras</p>' <<<"$unreq" \
  && ok "an unrequested row is marked 'cambió sin que lo pidieras'" \
  || fail "the unrequested row carries no marker: $unreq"
[[ "$(grep -c '<figure' <<<"$unreq")" == 2 && "$(grep -c 'type="radio"' <<<"$unreq")" == 3 ]] \
  && ok "…with the same pair and the same answer as a review row" \
  || fail "the unrequested row lost its pair or its answer"
[[ "$(grep -c 'gal-flag' "$TMP/group.html")" == 1 ]] \
  && ok "only the unrequested row carries the marker" \
  || fail "the marker is on $(grep -c 'gal-flag' "$TMP/group.html") rows"

# One unrequested row per CELL: `also` names the other variants where the same
# cell changed, so the owner answers the change once and still sees its reach.
python3 - "$TMP/rows.json" "$TMP/rows-also.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][2]["also"] = ["dark-desktop", "light-mobile"]
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rows-also.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/also.html" 2>"$TMP/also.err"
grep -qF '<p class="gal-flag">cambió sin que lo pidieras · también en: escritorio, tema oscuro; móvil, tema claro</p>' "$TMP/also.html" \
  && [[ -n "$(item audit-loaded-dark-mobile-unrequested "$TMP/also.html")" ]] \
  && ok "also adds 'también en: <variants>' to the marker, and the row id stays <gallery>-<cell>-<variant>-unrequested" \
  || fail "the also variants are not on the marker: $(grep gal-flag "$TMP/also.html") $(cat "$TMP/also.err")"
bash "$GEN" "$TMP/rows-also.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T --lang en 2>/dev/null \
  | grep >/dev/null -F '<p class="gal-flag">changed without you asking · also in: desktop, dark theme; mobile, light theme</p>' \
  && ok "…and 'also in: …' in English" \
  || fail "the English marker does not carry 'also in'"

# -- nothing about checks on the page ----------------------------------------
# The owner reviews rows; the gate's output lives in the Execution log. A
# summary line, a pass count or a "checks" heading on the page is noise the
# owner rejected (consultation 2026-09-27, D2).
python3 - "$TMP/rows.json" "$TMP/rows-clean.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"] = [r for r in d["rows"] if r["kind"] == "review"]
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rows-clean.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title "Revisión audit" > "$TMP/clean.html"
grep -qiE 'gate|check|comprobaci|meta:|passed|pasó|sin que lo pidieras' "$TMP/clean.html" \
  && fail "a page with no unrequested row still says something about checks: $(grep -iE 'gate|check|comprobaci|meta:|passed|pasó|pidieras' "$TMP/clean.html")" \
  || ok "with no unrequested row, nothing on the block is about checks"

# -- the verdict group and the notes box --------------------------------------
[[ "$(grep -c 'type="radio" name="audit-empty-light-desktop"' <<<"$pair")" == 3 ]] \
  && ok "one answer per row: three radios, all named after the row's id" \
  || fail "expected 3 radios named after the row's id"
for label in Aprobada 'Necesita cambios' 'No puedo juzgarla así'; do
  grep -qF "data-label=\"$label\"" <<<"$pair" \
    || fail "the Spanish verdict '$label' is not a data-label — the paste would carry the input value"
done
grep -q 'data-recommended' "$TMP/group.html" \
  && fail "a verdict option is marked data-recommended — the session has not seen the screenshots" \
  || ok "no option is recommended: the row is the reader's call, not the session's"
grep -q '<p class="fieldlabel">Notas sobre esta fila</p>' <<<"$pair" && grep -q '<textarea placeholder=' <<<"$pair" \
  && ok "the row's own notes box, under its own field label" \
  || fail "the row has no labelled notes textarea"

# -- a sample asks nothing (BL-466) -------------------------------------------
python3 - "$TMP/rows.json" "$TMP/rows-sample.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][0]["kind"] = "sample"
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rows-sample.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/sample.html" 2>"$TMP/sample.err"
smp="$(item audit-empty-light-desktop-sample "$TMP/sample.html")"
[[ -n "$smp" && "$(grep -c '<figure' <<<"$smp")" == 2 ]] && ! grep -q 'type="radio"' <<<"$smp" \
  && ok "a sample row shows the pair and carries no verdict radios" \
  || fail "the sample row is missing or carries radios: $smp $(cat "$TMP/sample.err")"

# -- untitled rows of one cell in two variants (BL-577) -------------------------
# A FOLDED row (decided or dropped) shows only its heading, so two untitled rows of
# one cell need the variant in it. An OPEN row already says the variant once, under
# the capture (BL-594): its heading stays plain. A one-variant cell keeps the plain one.
png actual/dark-desktop/audit-new-state.png 160 90
python3 - "$TMP/rows.json" "$TMP/rows-var.json" "$TMP/rows-var-open.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["variants"] = ["light-desktop", "dark-desktop"]
json.dump(d | {"rows": d["rows"] + [{"cell": "new-state", "variant": "dark-desktop", "kind": "review",
                  "after": "actual/dark-desktop/audit-new-state.png"}]}, open(sys.argv[3], "w"))
for r in d["rows"][:2]: r["decided"] = "Aprobado"
d["rows"].append({"cell": "new-state", "variant": "dark-desktop", "kind": "review",
                  "after": "actual/dark-desktop/audit-new-state.png", "decided": "Aprobado"})
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rows-var.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/var.html" 2>"$TMP/var.err"
bash "$GEN" "$TMP/rows-var-open.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/varo.html" 2>>"$TMP/var.err"
hl() { item "$1" "$2" | grep -o 'data-heading="[^"]*"' | sed -n 1,1p; }
[[ -n "$(hl audit-new-state-light-desktop "$TMP/var.html")" \
   && "$(hl audit-new-state-light-desktop "$TMP/var.html")" != "$(hl audit-new-state-dark-desktop "$TMP/var.html")" ]] \
  && [[ "$(hl audit-empty-light-desktop "$TMP/var.html")" == 'data-heading="Empty"' ]] \
  && ok "two untitled decided rows of one cell in two variants get different headings; a one-variant cell keeps the plain one" \
  || fail "headings: $(hl audit-new-state-light-desktop "$TMP/var.html") / $(hl audit-new-state-dark-desktop "$TMP/var.html") / $(hl audit-empty-light-desktop "$TMP/var.html") $(cat "$TMP/var.err")"
open_dark="$(item audit-new-state-dark-desktop "$TMP/varo.html")"
[[ "$(hl audit-new-state-dark-desktop "$TMP/varo.html")" == 'data-heading="New state"' \
   && "$(grep -c 'gal-variant' <<<"$open_dark")" == 1 && "$(grep -o 'escritorio, tema oscuro' <<<"$open_dark" | wc -l | tr -d ' ')" == 1 ]] \
  && ok "an open untitled row in a two-variant cell says its variant once (the line under the capture), heading plain" \
  || fail "open row repeats or lacks the variant: $(grep -n 'data-heading\|gal-variant\|<h3' <<<"$open_dark")"

# -- a declared cell the screen cannot reach ---------------------------------
# The emitter sends `{"cell", "notApplicable": reason}` for a changed cell the
# harness skips: no variant, no captures. The reason replaces the pair.
python3 - "$TMP/rows.json" "$TMP/rows-na.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"].append({"cell": "no-permission", "notApplicable": "Every role that reaches this screen holds the permission."})
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rows-na.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/na.html" 2>"$TMP/na.err"
na="$(item audit-no-permission-not-applicable "$TMP/na.html")"
grep -q 'data-id="audit-no-permission-not-applicable" data-title="audit · no-permission" data-heading="No permission">' <<<"$na" \
  && grep -q '<p class="gal-na">Every role that reaches this screen holds the permission.</p>' <<<"$na" \
  && ! grep -q '<figure' <<<"$na" && [[ "$(grep -c 'type="radio"' <<<"$na")" == 3 ]] \
  && ok "a notApplicable row is <gallery>-<cell>-not-applicable, its reason instead of captures, with one answer" \
  || fail "the notApplicable row is not the declared shape: $na $(cat "$TMP/na.err")"

# -- --lang en ----------------------------------------------------------------
gen --lang en > "$TMP/group-en.html" 2>/dev/null
for needle in 'data-label="Approved"' '<figcaption>before</figcaption>' \
              '<figcaption>proposed</figcaption>' '<figcaption>new screen</figcaption>' \
              '<p class="gal-flag">changed without you asking</p>' \
              '<p class="fieldlabel">Notes on this row</p>'; do
  grep -qF "$needle" "$TMP/group-en.html" || fail "--lang en did not produce $needle"
done
ok "--lang en swaps the verdicts, the captions, the marker and the field label"
grep -qE 'Aprobada|antes|propuesto|pidieras' "$TMP/group-en.html" \
  && fail "--lang en left Spanish text in the block" \
  || ok "…and leaves no Spanish behind"

# --- the generator's refusals -------------------------------------------------
# A malformed document is the caller's bug. Exit 2 with one line, and NOTHING on
# stdout: half a block pasted into a page is a defect that reaches the reader.
echo "== the generator: what it refuses =="
refuse() {  # refuse <label> <json> <pattern>
  printf '%s' "$2" > "$TMP/bad.json"
  rm -rf "$TMP/refused-assets"
  bash "$GEN" "$TMP/bad.json" --root "$ROOT" --page "$TMP/refused.html" --group-id E --group-title T \
    > "$TMP/bad.out" 2> "$TMP/bad.err"
  local rc=$?
  [[ "$rc" == 2 ]] || { fail "$1: expected exit 2, got $rc"; return; }
  grep -q "$3" "$TMP/bad.err" || { fail "$1: expected '$3' in: $(cat "$TMP/bad.err")"; return; }
  grep -qi 'Traceback' "$TMP/bad.err" && { fail "$1: refused with a traceback"; return; }
  [[ -s "$TMP/bad.out" ]] && { fail "$1: printed markup while refusing"; return; }
  [[ -e "$TMP/refused-assets" ]] && { fail "$1: copied captures while refusing"; return; }
  ok "$1"
}
A='"after":"actual/light-desktop/audit-empty.png"'
B='"before":"shots/light-desktop/audit-empty.png"'
V='"gallery":"audit","variants":["light-desktop"]'

refuse "the old matrix shape (no variants)" \
  '{"gallery":"audit","tiles":["light-desktop"],"rows":[]}' "no 'variants' key"
# D2: when every capture matches, the emitter prints `rows: []`. That is not a
# malformed document: the page carries no gallery block and says nothing.
printf '%s' "{$V,\"rows\":[]}" > "$TMP/empty.json"
bash "$GEN" "$TMP/empty.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T \
  > "$TMP/empty.out" 2> "$TMP/empty.err"
rc=$?
[[ "$rc" == 0 && ! -s "$TMP/empty.out" && ! -s "$TMP/empty.err" ]] \
  && ok "an empty rows list (everything matches) exits 0 and prints nothing — no block" \
  || fail "an empty rows list did not exit 0 with no output (exit $rc): $(cat "$TMP/empty.out" "$TMP/empty.err")"
refuse "rows that is not a list" \
  "{$V,\"rows\":{}}" "'rows' must be a list"
refuse "a row with no kind" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",$A}]}" "'kind' is None"
refuse "a row with an unknown kind" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"regression\",$A}]}" "'kind' is 'regression', not one of review, unrequested, sample"
refuse "a review row in a variant the owner did not choose" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"dark-mobile\",\"kind\":\"review\",$A}]}" "not one of the chosen variants"
refuse "a row with no after" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",$B}]}" "no 'after' capture"
refuse "a null before is a lost baseline, not a new screen" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"before\":null,$A}]}" "'before' path must be a string"
refuse "an empty before is a lost baseline, not a new screen" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"before\":\" \",$A}]}" "empty 'before' path"
refuse "one cell in one variant twice (requested and unrequested)" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",$A},{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"unrequested\",$B,$A}]}" "rows 1 and 2 are both cell 'x' in variant 'light-desktop'"
refuse "a notApplicable row that also carries a capture" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"notApplicable\":\"why\",$A}]}" "both captures and 'notApplicable'"
refuse "a null notApplicable (str(None) would render the word None as the reason)" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"notApplicable\":null}]}" "non-empty string"
refuse "a blank notApplicable" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"notApplicable\":\"  \"}]}" "non-empty string"
refuse "also on a review row" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",$A,\"also\":[\"dark-desktop\"]}]}" "'also' is only for an unrequested row"
refuse "an empty also" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"dark-mobile\",\"kind\":\"unrequested\",$A,\"also\":[]}]}" "'also' must be a non-empty list"
refuse "also naming the row's own variant" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"dark-mobile\",\"kind\":\"unrequested\",$A,\"also\":[\"dark-mobile\"]}]}" "names the row's own variant"
refuse "also naming a variant twice" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"dark-mobile\",\"kind\":\"unrequested\",$A,\"also\":[\"dark-desktop\",\"dark-desktop\"]}]}" "'also' names dark-desktop twice"
refuse "also naming a variant that is not a slug" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"dark-mobile\",\"kind\":\"unrequested\",$A,\"also\":[\"Dark Desktop\"]}]}" "'also' must be a non-empty list of variant names"
refuse "two unrequested rows for one cell" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"dark-mobile\",\"kind\":\"unrequested\",$A},{\"cell\":\"x\",\"variant\":\"dark-desktop\",\"kind\":\"unrequested\",$A}]}" "cell 'x' has two unrequested rows"
refuse "a cell name that is not a slug" \
  "{$V,\"rows\":[{\"cell\":\"With Data\",\"variant\":\"light-desktop\",\"kind\":\"review\",$A}]}" "lowercase slug"
refuse "a variant that is not a slug" \
  "{\"gallery\":\"audit\",\"variants\":[\"light desktop\"],\"rows\":[]}" "lowercase slugs"
refuse "a non-string variant" \
  "{\"gallery\":\"audit\",\"variants\":[\"light-desktop\",7],\"rows\":[]}" "lowercase slugs"
refuse "a variant named twice" \
  "{\"gallery\":\"audit\",\"variants\":[\"light-desktop\",\"light-desktop\"],\"rows\":[]}" "same variant twice"
# --root must be absolute: a file:// URL built from a relative path resolves
# nowhere, and the page renders broken images that look like missing captures.
bash "$GEN" "$TMP/rows.json" --root ../elsewhere --page "$PAGE" --group-id E --group-title T \
  > "$TMP/rel.out" 2> "$TMP/rel.err"
rc=$?
[[ "$rc" == 2 && "$(grep -c . "$TMP/rel.err")" == 1 ]] \
  && grep -q '^usage: gallery-items.sh .*must be an absolute path' "$TMP/rel.err" \
  && ok "a relative --root is refused" \
  || fail "a relative --root was accepted (exit $rc): $(cat "$TMP/rel.err")"
refuse "a capture path with no file under --root" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"after\":\"actual/light-desktop/audit-gone.png\"}]}" \
  "row 'x'.*'after' has no file.*actual/light-desktop/audit-gone.png"
refuse "a missing capture after a good row (nothing is copied for the good one)" \
  "{$V,\"rows\":[{\"cell\":\"ok\",\"variant\":\"light-desktop\",\"kind\":\"review\",$A},{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"after\":\"actual/light-desktop/audit-gone.png\"}]}" \
  "row 'x'.*'after' has no file"
printf 'not an image' > "$ROOT/shots/fake.png"
# --root / used to strip to "" and the capture was read relative to the CWD.
mkdir -p "$TMP/cwd/zz-cwd-only"
python3 "$SKILL/tests/png_fixture.py" "$TMP/cwd/zz-cwd-only/t.png" 4 4
( cd "$TMP/cwd" && bash "$GEN" <(printf '%s' "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"after\":\"zz-cwd-only/t.png\"}]}") \
    --root / --page "$PAGE" --group-id E --group-title T ) > "$TMP/rs.out" 2> "$TMP/rs.err"
rc=$?
[[ "$rc" == 2 ]] && grep -q "no file at /zz-cwd-only/t.png" "$TMP/rs.err" && [[ ! -s "$TMP/rs.out" ]] \
  && ok "--root / reads the capture under /, never relative to the working directory" \
  || fail "--root / resolved the capture against the cwd (exit $rc): $(cat "$TMP/rs.err")"
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/zero.png" 1 1
python3 - "$ROOT/shots/zero.png" <<'PY'
import struct, sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read())
b[16:24] = struct.pack(">II", 0, 0); open(p, "wb").write(bytes(b))
PY
refuse "a PNG whose header declares 0x0" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"after\":\"shots/zero.png\"}]}" \
  "row 'x'.*'after'.*0x0"
refuse "a capture that is not a PNG" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"before\":\"shots/fake.png\",$A}]}" \
  "row 'x'.*'before'.*not a PNG"
refuse "an absolute capture path" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"after\":\"/etc/passwd.png\"}]}" \
  "relative to the repo root"
refuse "a capture path that climbs out of the root" \
  "{$V,\"rows\":[{\"cell\":\"x\",\"variant\":\"light-desktop\",\"kind\":\"review\",\"after\":\"../../elsewhere/a.png\"}]}" \
  "relative to the repo root"
bash "$GEN" "$TMP/rows.json" --root "$ROOT" --page "$PAGE" --group-id 'E"><script>' --group-title T \
  > "$TMP/gid.out" 2> "$TMP/gid.err"
rc=$?
[[ "$rc" == 2 ]] && grep -q 'group-id' "$TMP/gid.err" \
  && ok "a --group-id that is not an html id is refused" \
  || fail "a --group-id of 'E\"><script>' was accepted (exit $rc): $(cat "$TMP/gid.err")"

# --- the generated block, wrapped and checked ---------------------------------
# The end of the generator's contract is not its own output but a PAGE: the
# block goes into a body with the minimum the template requires around it, and
# wrap-report.sh both wraps it and runs the contract — the new-screen row's
# narrowed matrix and the not-applicable row included.
echo "== the generated block passes the contract, wrapped =="
{
  printf '<div class="page"><main class="main">\n'
  printf '<header><p class="eyebrow">CONSULTA</p><h1>Contrato de interfaz</h1>'
  printf '<p class="standfirst">Cada fila de la galería es un ítem de esta misma página, con su respuesta y sus notas; el botón de copiar se lleva todas las respuestas de una vez.</p></header>\n'
  cat "$TMP/na.html"
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

# BL-474: the captures live where the project's runner wipes them. The page
# must not care: with the sources gone, every <img> still resolves beside it.
mv "$ROOT" "$ROOT.wiped"
srcs="$(grep -o '<img src="[^"]*"' "$TMP/page.html" | sed 's/<img src="//; s/"$//')"
broken=""
while IFS= read -r src; do
  [[ -f "$TMP/$src" ]] || broken="$broken $src"
done <<<"$srcs"
[[ -n "$srcs" && -z "$broken" ]] \
  && ok "every <img> on the page still resolves after the source captures are wiped" \
  || fail "the page lost its images with the captures:${broken:- (no <img> at all)}"
mv "$ROOT.wiped" "$ROOT"

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
    printf '%s\n' "$2" | python3 "$(dirname "${BASH_SOURCE[0]}")/link_labels.py"
    printf '</main><aside class="rail"><nav class="raillist" id="raillist"></nav>%s</aside></div>\n' "$railbar"
    printf '<script>var blank = 0;</script>\n</body>\n</html>\n'
  } > "$1"
}

figure() {  # figure <tile>
  printf '<figure data-tile="%s"><img src="page-assets/gallery/%s.png" alt="audit · with-data · %s" loading="lazy"><figcaption>%s</figcaption></figure>' \
    "$1" "$1" "$1" "$1"
}
galrow() {  # galrow <id> <inner-html>
  printf '<section class="consult-item consult-gallery" data-id="%s" data-title="audit row"><h3><span class="consult-id">%s</span>audit row</h3><p>The cells of this row.</p>%s<div class="opts one"><label><input type="radio" name="%s" data-label="Approved"><span>Approved</span></label><label><input type="radio" name="%s" data-label="Needs changes"><span>Needs changes</span></label></div><p class="fieldlabel">Notes on this row</p><textarea></textarea></section>' \
    "$1" "$1" "$2" "$1" "$1"
}
block() {  # block <data-tiles-attr> <items>
  printf '<section class="consult-group" id="E" data-id="E" data-title="The audit gallery"%s><div class="sec-head"><h2>The audit gallery</h2></div><p>The state matrix this block reviews, one row per screen state.</p>%s<div class="group-notes"><p class="fieldlabel">Notes on this block</p><textarea></textarea></div></section>' \
    "$1" "$2"
}
header='<header><p class="eyebrow">FIXTURE</p><h1>Claim</h1><p class="standfirst">The thesis.</p></header>'
notes='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><p class="fieldlabel">Notes for the whole page</p><textarea></textarea></section>'
bars='<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>'
railbar='<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div>'
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
plain='<section class="consult-item" data-id="q1" data-title="An ordinary item"><h3>An ordinary item</h3><div class="opts one"><label><input type="radio" name="q1" data-label="Yes"><span>Yes</span></label><label><input type="radio" name="q1" data-label="No"><span>No</span></label></div><p class="fieldlabel">Notes</p><textarea></textarea></section>'
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
grep -E '^\.gal img' "$KIT" | grep >/dev/null 'var(--line' \
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
  printf '<section class="consult-item" data-id="%s" data-title="audit row"><h3><span class="consult-id">%s</span>audit row</h3><p>The cells of this row.</p>%s<div class="opts one"><label><input type="radio" name="%s" data-label="Approved"><span>Approved</span></label><label><input type="radio" name="%s" data-label="Needs changes"><span>Needs changes</span></label></div><p class="fieldlabel">Notes on this row</p><textarea></textarea></section>' \
    "$1" "$1" "$2" "$1" "$1"
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

# (F4-F7) the documents the generator once turned into markup (absolute and
# climbing paths, null paths, names with whitespace) are refused above, in the
# generator's own section, against the rows contract.

# (lower) a data-tiles of nothing but spaces declares no matrix
page "$TMP/blank-tiles.html" "$(block ' data-tiles="   "' "$(galrow audit-with-data "<div class=\"gal\">$all_four</div>")")"
rc="$(run "$TMP/blank-tiles.html")"; red "a whitespace-only data-tiles declares no matrix" \
  "audit-with-data.*not inside a"

echo "== the second adversarial round (on the fix diff) =="

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
grep -E '^\.gal figure \{' "$KIT" | grep >/dev/null 'gap:' \
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

echo "== a row that narrows its block's matrix (new screen: after alone) =="

# The review block declares `before after`; a new screen has no baseline, so its
# row declares data-tiles="after" and is held to exactly that. Narrowing is the
# one exception the completeness rule makes, so each way it could be abused has
# a RED control: widening, a narrowed row that still shows the tile it dropped,
# and a pair row that drops "before" without saying so.
pair_attr=' data-tiles="before after"'
pfig() { printf '<figure data-tile="%s"><img src="page-assets/gallery/%s.png" alt="%s"><figcaption>%s</figcaption></figure>' "$1" "$1" "$1" "$1"; }
nrow() {  # nrow <item-attrs> <inner>
  printf '<section class="consult-item consult-gallery" data-id="audit-new-state-light-desktop" data-title="audit row"%s><h3>audit row</h3><p>The capture.</p>%s<div class="opts one"><label><input type="radio" name="audit-new-state-light-desktop" data-label="Approved"><span>Approved</span></label><label><input type="radio" name="audit-new-state-light-desktop" data-label="Needs changes"><span>Needs changes</span></label></div><p class="fieldlabel">Notes on this row</p><textarea></textarea></section>' \
    "$1" "$2"
}
page "$TMP/n1.html" "$(block "$pair_attr" "$(nrow ' data-tiles="after"' "<div class=\"gal\">$(pfig after)</div>")")"
rc="$(run "$TMP/n1.html")"
[[ "$rc" == 0 ]] && ok "N1 a row narrowed to after, showing after alone, passes" \
  || fail "N1 a narrowed new-screen row was rejected: $(cat "$TMP/out")"
page "$TMP/n2.html" "$(block "$pair_attr" "$(nrow '' "<div class=\"gal\">$(pfig after)</div>")")"
rc="$(run "$TMP/n2.html")"; red "N2 a pair row that drops before without narrowing fails" \
  "audit-new-state-light-desktop.*missing tile(s)\? before"
page "$TMP/n3.html" "$(block "$pair_attr" "$(nrow ' data-tiles="after"' "<div class=\"gal\">$(pfig before)$(pfig after)</div>")")"
rc="$(run "$TMP/n3.html")"; red "N3 a row narrowed to after that still shows before fails" \
  "audit-new-state-light-desktop.*its matrix does not declare: before"
page "$TMP/n4.html" "$(block "$pair_attr" "$(nrow ' data-tiles="after sepia"' "<div class=\"gal\">$(pfig after)$(pfig sepia)</div>")")"
rc="$(run "$TMP/n4.html")"; red "N4 a row may never widen its block's matrix" \
  "audit-new-state-light-desktop.*declares data-tiles=\"after sepia\".*only narrowing"
page "$TMP/n5.html" "$(block "$pair_attr" "$(nrow ' data-tiles="   "' "<div class=\"gal\">$(pfig after)</div>")")"
rc="$(run "$TMP/n5.html")"; red "N5 a whitespace-only row data-tiles narrows nothing (the block's pair holds)" \
  "audit-new-state-light-desktop.*missing tile(s)\? before"
page "$TMP/n6.html" "$(block "$pair_attr" "$(nrow ' data-tiles="after after"' "<div class=\"gal\">$(pfig after)</div>")")"
rc="$(run "$TMP/n6.html")"; red "N6 a row declaring a tile twice fails" \
  "audit-new-state-light-desktop.*declares data-tiles=\"after after\".*only narrowing"
# The ONE narrowing is a new screen: `after` alone in a `before after` block.
# Any other subset is a verdict on part of the row passed off as complete.
page "$TMP/n7.html" "$(block "$pair_attr" "$(nrow ' data-tiles="before"' "<div class=\"gal\">$(pfig before)</div>")")"
rc="$(run "$TMP/n7.html")"; red "N7 a row narrowed to before alone fails" \
  "audit-new-state-light-desktop.*declares data-tiles=\"before\".*only narrowing"
page "$TMP/n8.html" "$(block "$tiles_attr" "$(nrow ' data-tiles="light-desktop"' "<div class=\"gal\">$(figure light-desktop)</div>")")"
rc="$(run "$TMP/n8.html")"; red "N8 a row of a four-tile matrix narrowed to one tile fails" \
  "audit-new-state-light-desktop.*declares data-tiles=\"light-desktop\".*only narrowing"

# -- BL-609: a row's optional `note` -----------------------------------------
# Explain-why / reframe / more-examples had no slot but the one-line `look`, and
# the mixed-content check refused a four-clause look. `note` is a list of
# strings rendered as a <ul> right under the look line.
echo "== BL-609: the row note =="
mkdir -p "$TMP/nspec"
cp -R "$ROOT/shots" "$ROOT/actual" "$TMP/nspec/" 2>/dev/null
cat > "$TMP/nspec/note.json" <<'JSON'
{"gallery": "audit", "variants": ["light-desktop"],
 "shots_dir": "shots", "actual_dir": "actual",
 "rows": [
  {"cell": "empty", "variant": "light-desktop", "kind": "review",
   "look": "El estado vacío",
   "note": ["Qué cambió desde la ronda 1: el título; el botón; el icono; el color",
            "Si quitar falla: queda sin guía; se pierde el contexto",
            "Ejemplo: Diego abre la lista; no ve nada; pulsa crear"],
   "before": "shots/light-desktop/audit-empty.png", "after": "actual/light-desktop/audit-empty.png"}
 ]}
JSON
cat > "$TMP/nspec/n.spec.md" <<MD
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Galería

Una fila con nota.
:::

::: gallery {#G title="Revisión" rows="note.json" root="$ROOT"}
:::

::: notes {title="Notas generales"}
:::
MD
( cd "$TMP/nspec" && python3 "$SKILL/scripts/spec_build.py" n.spec.md -o n.html > "$TMP/nb.out" 2>&1 ); rc=$?
if [[ $rc == 0 && -f "$TMP/nspec/n.html" ]]; then
  python3 - "$TMP/nspec/n.html" <<'PY' && ok "BL-609 N-1 a row note builds from a spec (no mixed-content refusal) as a <ul> of 3 <li> right under the look line" || fail "BL-609 N-1 the note is not a 3-item <ul> under the look line (see above)"
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<p class="gal-look">.*?</p>\s*<ul class="gal-note">(.*?)</ul>', html, re.S)
if not m: sys.exit("no <ul class=gal-note> directly after the look line")
n = len(re.findall(r'<li>', m.group(1)))
if n != 3: sys.exit("expected 3 <li>, found %d" % n)
PY
else fail "BL-609 N-1 the spec with a note did not build: $(tail -3 "$TMP/nb.out")"; fi
for bad in '"note": "texto"' '"note": []' '"note": ["ok", ""]' '"note": ["ok", 3]' '"note": [" "]'; do
  python3 - "$TMP/nspec/note.json" "$TMP/nspec/bad.json" "$bad" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"][0].update(json.loads("{%s}" % sys.argv[3]))
json.dump(d, open(sys.argv[2], "w"))
PY
  bash "$GEN" "$TMP/nspec/bad.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/nspec/bad.out" 2> "$TMP/nspec/bad.err"; rc=$?
  if [[ $rc == 2 && ! -s "$TMP/nspec/bad.out" ]] && grep -q "row 'empty'.*note" "$TMP/nspec/bad.err"; then ok "BL-609 N-2 $bad is refused naming the cell"
  else fail "BL-609 N-2 $bad: exit $rc, stderr: $(cat "$TMP/nspec/bad.err")"; fi
done
# A not-applicable row is still a live question: a note there would be dropped
# silently, so it is refused.
python3 - "$TMP/nspec/note.json" "$TMP/nspec/na.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"] = [{"cell": "empty", "notApplicable": "no permission state", "note": ["x"]}]
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/nspec/na.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/nspec/na.out" 2> "$TMP/nspec/na.err"; rc=$?
if [[ $rc == 2 && ! -s "$TMP/nspec/na.out" ]] && grep -q "row 'empty'.*note" "$TMP/nspec/na.err"; then ok "BL-609 N-2 a note on a notApplicable row is refused naming the cell"
else fail "BL-609 N-2 notApplicable+note: exit $rc, stderr: $(cat "$TMP/nspec/na.err")"; fi
# N-3: a row without `note` carries no note markup, and the same row with a
# note differs only by its <ul class="gal-note"> block.
python3 - "$TMP/nspec/note.json" "$TMP/nspec/plain.json" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); del d["rows"][0]["note"]
json.dump(d, open(sys.argv[2], "w"))
PY2
G="--root $ROOT --page $PAGE --group-id E --group-title T"
bash "$GEN" "$TMP/nspec/plain.json" $G > "$TMP/nspec/plain.html" 2>/dev/null
bash "$GEN" "$TMP/nspec/note.json" $G | sed '/<ul class="gal-note">/,/<\/ul>/d' > "$TMP/nspec/stripped.html" 2>/dev/null
if [[ -s "$TMP/nspec/plain.html" ]] && ! grep -q gal-note "$TMP/nspec/plain.html" \
    && cmp -s "$TMP/nspec/plain.html" "$TMP/nspec/stripped.html"; then
  ok "BL-609 N-3 a row without note renders as before, the note adds only its <ul>"
else fail "BL-609 N-3 a no-note row changed: $(diff "$TMP/nspec/plain.html" "$TMP/nspec/stripped.html" | sed -n 1,4p)"; fi

# -- BL-610: a single capture that says why it has no before ------------------
# One capture used to be always "pantalla nueva". `noBefore` (a reason) lets a
# row say there is no before and why; the intro's "the screen is new" sentence
# then needs a row that is really new.
echo "== BL-610: noBefore =="
mkdir -p "$TMP/nb"
REASON='aprobada en la ronda 3; no se guardó el antes'
nbrun() {  # nbrun <name> <python expr editing d["rows"]> [lang args]
  python3 - "$TMP/rows.json" "$TMP/nb/$1.json" "$2" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(d, open(sys.argv[2], "w"))
PY2
  bash "$GEN" "$TMP/nb/$1.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/nb/$1.out" 2> "$TMP/nb/$1.err"
}
# Rows of the fixture: [0] empty (pair), [1] new-state (single), [2] loaded.
nbrun one "d['rows'][1]['noBefore'] = '$REASON'"; rc=$?
nbrow="$(item audit-new-state-light-desktop "$TMP/nb/one.out")"
if [[ "$(grep -c '<figure' <<<"$nbrow")" == 1 ]] && grep -q '<figure data-tile="after">' <<<"$nbrow" \
    && ! grep -qi 'pantalla nueva' <<<"$nbrow" \
    && grep -qF "<figcaption>sin antes: $REASON</figcaption>" <<<"$nbrow" \
    && grep -qF "alt=\"New state · sin antes: $REASON\"" <<<"$nbrow"; then
  ok "BL-610 1 a single capture with noBefore is one after figure, no 'pantalla nueva', the reason in the row"
else fail "BL-610 1 noBefore row: $nbrow"; fi
# 2: the fixture has exactly one single-capture row (new-state; the other two
# rows carry a before), so with noBefore on it the sentence goes; without it
# (group.html) the sentence stays.
if grep -q 'Donde hay una sola captura' "$TMP/group.html" && ! grep -q 'Donde hay una sola captura' "$TMP/nb/one.out"; then
  ok "BL-610 2 the 'la pantalla es nueva' intro sentence is emitted only while a single capture has no noBefore"
else fail "BL-610 2 intro sentence: with=$(grep -c 'Donde hay una sola' "$TMP/group.html") without=$(grep -c 'Donde hay una sola' "$TMP/nb/one.out")"; fi
# 2b: a plain single capture beside a noBefore row gets the sentence qualified;
# with no noBefore anywhere it is today's sentence (group.html, byte-checked).
nbrun two "d['rows'][1]['noBefore'] = '$REASON'; d['rows'].append({'cell': 'error', 'variant': 'light-desktop', 'kind': 'review', 'after': 'actual/light-desktop/audit-new-state.png'})"
if grep -qF 'la pantalla es nueva y no hay antes, salvo donde la fila dice por qué no hay antes.' "$TMP/nb/two.out" \
    && grep -qF 'Donde hay una sola captura, la pantalla es nueva y no hay antes.' "$TMP/group.html"; then
  ok "BL-610 2b a mixed gallery qualifies the intro sentence; a gallery with no noBefore keeps today's"
else fail "BL-610 2b mixed intro: $(grep -o 'Donde hay una sola[^<]*' "$TMP/nb/two.out")"; fi
# 1b: English page
bash "$GEN" "$TMP/nb/one.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T --lang en > "$TMP/nb/one-en.out" 2>/dev/null
grep -qF "<figcaption>no before: $REASON</figcaption>" "$TMP/nb/one-en.out" \
  && ok "BL-610 1b --lang en captions the row 'no before: <reason>'" \
  || fail "BL-610 1b english caption: $(grep -o '<figcaption>[^<]*' "$TMP/nb/one-en.out")"
# 3-4: refusals, exit 2, one line, nothing on stdout.
for case in \
  "both|d['rows'][0]['noBefore'] = 'x'" \
  "blank|d['rows'][1]['noBefore'] = '  '" \
  "nonstr|d['rows'][1]['noBefore'] = 3" \
  "na|d['rows'] = [{'cell': 'empty', 'notApplicable': 'no state', 'noBefore': 'x'}]" ; do
  name="${case%%|*}"
  nbrun "r$name" "${case#*|}"; rc=$?
  if [[ $rc == 2 && ! -s "$TMP/nb/r$name.out" && "$(wc -l < "$TMP/nb/r$name.err" | tr -d ' ')" == 1 ]] \
      && grep -q "row '[a-z-]*'.*noBefore" "$TMP/nb/r$name.err"; then
    ok "BL-610 3/4 noBefore ($name) is refused naming the cell, one line"
  else fail "BL-610 3/4 noBefore ($name): exit $rc, stderr: $(cat "$TMP/nb/r$name.err")"; fi
done

# alternatives row (document declares alternatives): refused naming the cell.
png shots/list-a.png 160 90
cat > "$TMP/nb/alt.json" <<'JSON'
{"gallery": "skel", "variants": ["light-desktop"],
 "alternatives": [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}],
 "rows": [{"cell": "x", "variant": "light-desktop", "kind": "alternatives", "noBefore": "why",
           "captures": {"a": "shots/list-a.png", "b": "shots/list-a.png"}}]}
JSON
bash "$GEN" "$TMP/nb/alt.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/nb/alt.out" 2> "$TMP/nb/alt.err"; rc=$?
if [[ $rc == 2 && ! -s "$TMP/nb/alt.out" && "$(wc -l < "$TMP/nb/alt.err" | tr -d ' ')" == 1 ]] && grep -q "row 'x'.*noBefore" "$TMP/nb/alt.err"; then
  ok "BL-610 5 noBefore on an alternatives row is refused naming the cell, one line"
else fail "BL-610 5 alternatives+noBefore: exit $rc, stderr: $(cat "$TMP/nb/alt.err")"; fi
# a dropped row does not read noBefore (like note): builds, carries no trace of it.
nbrun drp "d['rows'][1].update({'dropped': 'gone', 'noBefore': 'zzzmarker'})"; rc=$?
if [[ $rc == 0 ]] && ! grep -q zzzmarker "$TMP/nb/drp.out"; then ok "BL-610 6 noBefore on a dropped row is not read, not refused"
else fail "BL-610 6 dropped+noBefore: exit $rc $(cat "$TMP/nb/drp.err")"; fi

# -- BL-613: a row's optional `decided_note` ----------------------------------
# A reversible decision ("decidido, corrígeme si no") had no slot in a gallery,
# so builders crammed it into the Qué mirar line. `decided_note` renders as the
# kit's callout under the captures, never in the look line.
echo "== BL-613: decided_note =="
mkdir -p "$TMP/dn"
cp -R "$ROOT/shots" "$ROOT/actual" "$TMP/dn/" 2>/dev/null
cat > "$TMP/dn/dn.json" <<'JSON'
{"gallery": "audit", "variants": ["light-desktop"],
 "shots_dir": "shots", "actual_dir": "actual",
 "rows": [
  {"cell": "empty", "variant": "light-desktop", "kind": "review",
   "look": "El estado vacío",
   "decided_note": "Decidido, corrígeme si no: dejamos el icono actual zzzdecided",
   "before": "shots/light-desktop/audit-empty.png", "after": "actual/light-desktop/audit-empty.png"}
 ]}
JSON
cat > "$TMP/dn/d.spec.md" <<MD
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Galería

Una fila con decisión tomada.
:::

::: gallery {#G title="Revisión" rows="dn.json" root="$ROOT"}
:::

::: notes {title="Notas generales"}
:::
MD
( cd "$TMP/dn" && python3 "$SKILL/scripts/spec_build.py" d.spec.md -o d.html > "$TMP/dn/b.out" 2>&1 ); rc=$?
if [[ $rc == 0 && -f "$TMP/dn/d.html" ]]; then
  python3 - "$TMP/dn/d.html" <<'PY' && ok "BL-613 D-1 decided_note is a callout element after the gal-variant line; the Qué mirar line does not hold it" || fail "BL-613 D-1 decided_note is not a callout under the captures (see above)"
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<div class="callout[^"]*"[^>]*>(?:(?!</div>).)*zzzdecided(?:(?!</div>).)*</div>', html, re.S)
if not m: sys.exit("no callout element holds the decided note")
look = re.search(r'<p class="gal-look">.*?</p>', html, re.S).group(0)
if "zzzdecided" in look: sys.exit("the look line holds the decided note")
row = html[html.index('class="consult-item consult-gallery"'):]
if row.index("zzzdecided") < row.index('class="gal-variant"'): sys.exit("callout is not after the gal-variant line")
PY
  bash "$CHECK" "$TMP/dn/d.html" > "$TMP/dn/c.out" 2>&1; crc=$?
  if [[ $crc == 0 ]] && grep -q zzzdecided "$TMP/dn/d.html" && ! grep -q "consult-shape" "$TMP/dn/c.out"; then ok "BL-613 D-2 check-artifact.sh exits 0 and raises no consult-shape finding on the page"
  else fail "BL-613 D-2 consult-shape finding: $(grep consult-shape "$TMP/dn/c.out")"; fi
else fail "BL-613 D-1 the spec with a decided_note did not build: $(tail -3 "$TMP/dn/b.out")"; fi
for bad in '"decided": "Bien"' '"decided_note": ""' '"decided_note": " "' '"decided_note": ["x"]' '"decided_note": 3'; do
  python3 - "$TMP/dn/dn.json" "$TMP/dn/bad.json" "$bad" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"][0].update(json.loads("{%s}" % sys.argv[3]))
json.dump(d, open(sys.argv[2], "w"))
PY
  bash "$GEN" "$TMP/dn/bad.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/dn/bad.out" 2> "$TMP/dn/bad.err"; rc=$?
  if [[ $rc == 2 && ! -s "$TMP/dn/bad.out" ]] && grep -q "row 'empty'.*decided_note" "$TMP/dn/bad.err"; then ok "BL-613 D-3 $bad is refused naming the cell"
  else fail "BL-613 D-3 $bad: exit $rc, stderr: $(cat "$TMP/dn/bad.err")"; fi
done
# A notApplicable row is a live question with no captures: a decided_note there
# would be dropped silently, so it is refused; a dropped row does not read it.
python3 - "$TMP/dn/dn.json" "$TMP/dn/na.json" "$TMP/dn/dr.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"] = [{"cell": "empty", "notApplicable": "no permission state", "decided_note": "x"}]
json.dump(d, open(sys.argv[2], "w"))
d["rows"] = [{"cell": "empty", "notApplicable": "no permission state", "dropped": "gone", "decided_note": "zzzdecided"}]
json.dump(d, open(sys.argv[3], "w"))
PY
bash "$GEN" "$TMP/dn/na.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/dn/na.out" 2> "$TMP/dn/na.err"; rc=$?
if [[ $rc == 2 && ! -s "$TMP/dn/na.out" ]] && grep -q "row 'empty'.*decided_note" "$TMP/dn/na.err"; then ok "BL-613 D-3 a decided_note on a notApplicable row is refused naming the cell"
else fail "BL-613 D-3 notApplicable+decided_note: exit $rc, stderr: $(cat "$TMP/dn/na.err")"; fi
bash "$GEN" "$TMP/dn/dr.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/dn/dr.out" 2> "$TMP/dn/dr.err"; rc=$?
if [[ $rc == 0 ]] && ! grep -q zzzdecided "$TMP/dn/dr.out"; then ok "BL-613 D-4 decided_note on a dropped row is not read, not refused"
else fail "BL-613 D-4 dropped+decided_note: exit $rc $(cat "$TMP/dn/dr.err")"; fi

# -- BL-629: a decided row's optional `answer` ----------------------------------
# The reply to the owner's note on an approved row. It rides on a decided row only
# (the fold shows it); the row keeps its id, drops the verdict radios, and the page
# still passes the checker. Refusals name the cell.
echo "== BL-629: answer =="
mkdir -p "$TMP/an"
cat > "$TMP/an/an.json" <<'JSON'
{"gallery": "audit", "variants": ["light-desktop"],
 "shots_dir": "shots", "actual_dir": "actual",
 "rows": [
  {"cell": "empty", "variant": "light-desktop", "kind": "review",
   "look": "El estado vacío", "decided": "Aprobada en la ronda 2",
   "answer": "Respuesta zzzanswer a tu nota",
   "before": "shots/light-desktop/audit-empty.png", "after": "actual/light-desktop/audit-empty.png"}
 ]}
JSON
bash "$GEN" "$TMP/an/an.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/an/ok.out" 2> "$TMP/an/ok.err"; rc=$?
if [[ $rc == 0 ]] && grep -q 'data-answer="Respuesta zzzanswer a tu nota"' "$TMP/an/ok.out" \
   && grep -q 'data-id="audit-empty-light-desktop"' "$TMP/an/ok.out" && ! grep -q 'type="radio"' "$TMP/an/ok.out"; then
  ok "BL-629 A-1 a decided row with an answer renders data-answer, keeps its id, has no radios"
else fail "BL-629 A-1 decided+answer: exit $rc $(cat "$TMP/an/ok.err")"; fi
for bad in '"answer": ""' '"answer": " "' '"answer": ["x"]' '"answer": 3' '"decided": null' '"kind": "alternatives"'; do
  lab629="$bad"; [[ "$bad" == *null* ]] && lab629="answer without decided"
  python3 - "$TMP/an/an.json" "$TMP/an/bad.json" "$bad" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"][0].update(json.loads("{%s}" % sys.argv[3]))
if d["rows"][0].get("decided", 1) is None:   # an answer on a row that is not decided
    del d["rows"][0]["decided"]
json.dump(d, open(sys.argv[2], "w"))
PY
  bash "$GEN" "$TMP/an/bad.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/an/bad.out" 2> "$TMP/an/bad.err"; rc=$?
  if [[ $rc == 2 && ! -s "$TMP/an/bad.out" ]] && grep -q "row 'empty'.*answer" "$TMP/an/bad.err"; then ok "BL-629 A-2 ${lab629} is refused naming the cell"
  else fail "BL-629 A-2 $lab629: exit $rc, stderr: $(cat "$TMP/an/bad.err")"; fi
done
cp -R "$ROOT/shots" "$ROOT/actual" "$TMP/an/" 2>/dev/null
cat > "$TMP/an/a.spec.md" <<MD
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Galería

Una fila decidida con respuesta.
:::

::: gallery {#G title="Revisión" rows="an.json" root="$ROOT"}
:::

::: notes {title="Notas generales"}
:::
MD
( cd "$TMP/an" && python3 "$SKILL/scripts/spec_build.py" a.spec.md -o a.html > "$TMP/an/b.out" 2>&1 ); rc=$?
if [[ $rc == 0 && -f "$TMP/an/a.html" ]] && bash "$CHECK" "$TMP/an/a.html" > "$TMP/an/c.out" 2>&1 \
   && grep -q zzzanswer "$TMP/an/a.html"; then ok "BL-629 A-3 the built page with a decided answered row passes check-artifact"
else fail "BL-629 A-3 built page: $(tail -3 "$TMP/an/b.out") $(grep -v "^$" "$TMP/an/c.out" | sed -n 1,6p)"; fi
python3 - "$TMP/an/an.json" "$TMP/an/na.json" "$TMP/an/dr.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"] = [{"cell": "empty", "notApplicable": "no state", "decided": "Bien", "answer": "x"}]
json.dump(d, open(sys.argv[2], "w"))
d["rows"] = [{"cell": "empty", "variant": "light-desktop", "kind": "review", "dropped": "gone", "answer": "x"}]
json.dump(d, open(sys.argv[3], "w"))
PY
for f in na dr; do
  bash "$GEN" "$TMP/an/$f.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/an/$f.out" 2> "$TMP/an/$f.err"; rc=$?
  if [[ $rc == 2 && ! -s "$TMP/an/$f.out" ]] && grep -q "row 'empty'.*answer" "$TMP/an/$f.err"; then ok "BL-629 A-2 an answer on a $f row is refused naming the cell"
  else fail "BL-629 A-2 $f+answer: exit $rc, stderr: $(cat "$TMP/an/$f.err")"; fi
done

# -- a sample row says it asks nothing and carries no control (BL-693) --------
smp="$(item audit-empty-light-desktop-sample "$TMP/sample.html")"
grep -q 'type="radio"\|<textarea\|<input\|<select' <<<"$smp" \
  && fail "BL-693 a sample row carries an answer control: $smp" \
  || ok "BL-693 a sample row has no radio, no notes box, no input"
grep -q 'data-asks-nothing' <<<"$smp" && grep -q '<p class="gal-asks-nothing">Solo ilustra: no necesita respuesta</p>' <<<"$smp" \
  && ok "BL-693 a sample row says, where the options would be, that it asks nothing (es)" \
  || fail "BL-693 the sample row has no no-answer line: $smp"
en_sample="$(bash "$GEN" "$TMP/rows-sample.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T --lang en 2>/dev/null)"
grep -q 'Illustration only: no answer needed' <<<"$en_sample" \
  && ok "BL-693 the no-answer line is localized (en)" || fail "BL-693 no en no-answer line"

# -- a row that depends on an open consult item is context only (BL-690) -----
# The CLI sees no page, so it reads every dependency as open.
python3 - "$TMP/rows.json" "$TMP/rows-dep.json" "$TMP/rows-dep-bad.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"][0]["depends_on"] = "Q14"       # the review row
d["rows"][2]["depends_on"] = "Q14"       # the unrequested row
json.dump(d, open(sys.argv[2], "w"))
d["rows"] = [{"cell": "empty", "notApplicable": "no state", "depends_on": "Q14"}]
json.dump(d, open(sys.argv[3], "w"))
PY
bash "$GEN" "$TMP/rows-dep.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/dep.html" 2>"$TMP/dep.err"
dep="$(item audit-empty-light-desktop "$TMP/dep.html")"
[[ -n "$dep" && "$(grep -c '<figure' <<<"$dep")" == 2 ]] \
  && ! grep -q 'type="radio"\|<textarea\|<input\|<select' <<<"$dep" \
  && grep -q 'data-asks-nothing data-waits-on="Q14"' <<<"$dep" \
  && grep -q '<p class="gal-asks-nothing">Solo contexto: espera la decisión de Q14</p>' <<<"$dep" \
  && ok "BL-690 a review row waiting on an open item shows its pair, no controls, and one line naming the item" \
  || fail "BL-690 the waiting row is wrong: $dep $(cat "$TMP/dep.err")"
unreq="$(item audit-loaded-dark-mobile-unrequested "$TMP/dep.html")"
[[ -n "$unreq" ]] && ! grep -q 'data-decided' <<<"$unreq" && grep -q '<details class="gal-waiting">' <<<"$unreq" && grep -q 'data-waits-on="Q14"' <<<"$unreq" \
  && ! grep -q '<textarea\|<input\|<img' <<<"$unreq" \
  && grep -q 'Solo contexto: espera la decisión de Q14' <<<"$unreq" \
  && ok "BL-690 an unrequested row whose only change is the pending option keeps its id as a closed details, not decided, with no capture and no control" \
  || fail "BL-690 the waiting unrequested row is not the folded shape: $unreq"
grep -q 'Las filas que esperan una decisión abierta son solo contexto' "$TMP/dep.html" \
  && ok "BL-690 the block's intro says that waiting rows ask nothing" || fail "BL-690 no waiting-row intro"
bash "$GEN" "$TMP/rows-dep.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T --lang en 2>/dev/null \
  | grep >/dev/null 'Context only: waits for the decision on Q14' \
  && ok "BL-690 the waiting line is localized (en)" || fail "BL-690 no en waiting line"
bash "$GEN" "$TMP/rows-dep-bad.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/dep-bad.err"; rc=$?
[[ $rc == 2 ]] && grep -q "row 'empty'.*depends_on" "$TMP/dep-bad.err" \
  && ok "BL-690 depends_on on a notApplicable row is refused naming the cell" \
  || fail "BL-690 notApplicable+depends_on: exit $rc, $(cat "$TMP/dep-bad.err")"

# depends_on on the kinds that are a question of their own is refused; a sample and
# a decided row never wait (the CLI reads every dependency as open).
python3 - "$TMP/rows.json" "$TMP/rows-dep-alt.json" "$TMP/rows-dep-st.json" "$TMP/rows-dep-ex.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cap = "actual/light-desktop/audit-empty.png"
alt = dict(d, alternatives=[{"id": "a", "label": "A"}, {"id": "b", "label": "B"}],
           rows=[{"cell": "empty", "variant": "light-desktop", "kind": "alternatives",
                  "depends_on": "Q14", "captures": {"a": cap, "b": cap}}])
json.dump(alt, open(sys.argv[2], "w"))
st = dict(d, rows=[{"cell": "empty", "variant": "light-desktop", "kind": "states",
                    "depends_on": "Q14", "states": [{"id": "x", "label": "X", "capture": cap},
                                                    {"id": "y", "label": "Y", "capture": cap}]}])
json.dump(st, open(sys.argv[3], "w"))
ex = dict(d, rows=[
    {"cell": "empty", "variant": "light-desktop", "kind": "sample", "depends_on": "Q14",
     "before": "shots/light-desktop/audit-empty.png", "after": cap},
    {"cell": "new-state", "variant": "light-desktop", "kind": "review", "depends_on": "Q14",
     "decided": "Bien", "after": "actual/light-desktop/audit-new-state.png"}])
json.dump(ex, open(sys.argv[4], "w"))
PY
for f in alt st; do
  bash "$GEN" "$TMP/rows-dep-$f.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/dep-$f.err"; rc=$?
  [[ $rc == 2 ]] && grep -q "row 'empty'.*depends_on" "$TMP/dep-$f.err" \
    && ok "BL-690 depends_on on a $f row is refused naming the cell" \
    || fail "BL-690 $f+depends_on: exit $rc, $(cat "$TMP/dep-$f.err")"
done
bash "$GEN" "$TMP/rows-dep-ex.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/dep-ex.html" 2>"$TMP/dep-ex.err"
smpx="$(item audit-empty-light-desktop-sample "$TMP/dep-ex.html")"
decx="$(item audit-new-state-light-desktop "$TMP/dep-ex.html")"
grep -q 'Solo ilustra: no necesita respuesta' <<<"$smpx" && ! grep -q 'data-waits-on' <<<"$smpx" \
  && grep -q 'data-decided="Bien"' <<<"$decx" && ! grep -q 'data-waits-on' <<<"$decx" \
  && ok "BL-690 a sample and a decided row with depends_on never wait: sample line and decided fold are kept" \
  || fail "BL-690 sample/decided with depends_on: $smpx $decx $(cat "$TMP/dep-ex.err")"
# The built page with an open Q14 passes the whole gate, folded unrequested row included.
mkdir -p "$TMP/dp"; cp -R "$ROOT/shots" "$ROOT/actual" "$TMP/dp/"
cp "$TMP/rows-dep.json" "$TMP/dp/dp.json"
python3 - "$TMP/dp/dp.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for r in d["rows"]:
    r.setdefault("look", "La cabecera")
json.dump(d, open(sys.argv[1], "w"))
PY
cat > "$TMP/dp/dp.spec.md" <<MD
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Galería

Una decisión abierta y filas que dependen de ella.
:::

::: group {#G1 title="Decisión" eyebrow="Q"}
::: item {#Q14 title="Forma de Inicio"}
¿Qué forma?

- B
- C {recommended}
:::
:::

::: gallery {#G title="Revisión" rows="dp.json" root="$ROOT"}
:::

::: notes {title="Notas generales"}
:::
MD
( cd "$TMP/dp" && python3 "$SKILL/scripts/spec_build.py" dp.spec.md -o dp.html > "$TMP/dp/b.out" 2>&1 ); rc=$?
if [[ $rc == 0 ]] && bash "$CHECK" "$TMP/dp/dp.html" > "$TMP/dp/c.out" 2>&1 && grep -q 'data-waits-on="Q14"' "$TMP/dp/dp.html" \
   && ! grep -q 'consult-round1-decided' "$TMP/dp/b.out" "$TMP/dp/c.out"; then
  ok "BL-690 a round-1 page whose only candidate is a waiting row passes check-artifact with no consult-round1-decided warning"
else fail "BL-690 built waiting page: $(grep -v '^$' "$TMP/dp/b.out" | sed -n 1,8p | cut -c1-300) $(grep -v '^$' "$TMP/dp/c.out" | sed -n 1,6p)"; fi

# -- a row whose highlighted region repeats another row's is refused (BL-693) --
RR="$SKILL/tests/fixtures/redundant-region"
RRD="$ROOT/shots/rr"; mkdir -p "$RRD"; cp "$RR"/* "$RRD/"
cat > "$TMP/rr.json" <<'JSON'
{"gallery": "dashboard", "variants": ["light-desktop"], "shots_dir": "shots/rr", "actual_dir": "shots/rr",
 "rows": [
  {"cell": "skeleton-todo-al-dia", "variant": "light-desktop", "kind": "review",
   "look": "En calma las mismas tres tarjetas.", "highlight": "@avisos",
   "after": "shots/rr/dashboard-skeleton-todo-al-dia-darwin.png"},
  {"cell": "skeleton-sin-entregas", "variant": "light-desktop", "kind": "sample",
   "look": "La misma seccion tranquila.", "highlight": "@avisos",
   "after": "shots/rr/dashboard-skeleton-sin-entregas-darwin.png"}
 ]}
JSON
bash "$GEN" "$TMP/rr.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/rr.out" 2> "$TMP/rr.err"; rc=$?
if [[ $rc == 2 && ! -s "$TMP/rr.out" ]] && grep -q "skeleton-sin-entregas" "$TMP/rr.err" && grep -q "skeleton-todo-al-dia" "$TMP/rr.err" \
   && grep -qi "identical\|same" "$TMP/rr.err"; then
  ok "BL-693 round-5 replay: the sample row repeating todo-al-dia's highlighted region is refused naming both rows"
else fail "BL-693 round-5 replay: exit $rc, stderr: $(cat "$TMP/rr.err")"; fi
# Controls: the same two dimensions with different pixels pass; flat identical ones are refused.
for g in 100 200; do mkdir -p "$ROOT/shots/flat$g"; python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/flat$g/a.png" 400 700 "$g"
  python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/flat$g/b.png" 400 700 "$g"
  printf '{"avisos":{"x":10,"y":20,"w":300,"h":100}}' > "$ROOT/shots/flat$g/a.regions.json"
  printf '{"avisos":{"x":10,"y":20,"w":300,"h":100}}' > "$ROOT/shots/flat$g/b.regions.json"; done
mkrr() {  # mkrr <dirA> <dirB> <out>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
rows = [{"cell": c, "variant": "light-desktop", "kind": "review", "look": "x", "highlight": "@avisos",
         "after": "shots/%s/%s.png" % (d, f)} for c, d, f in (("uno", sys.argv[1], "a"), ("dos", sys.argv[2], "b"))]
json.dump({"gallery": "g", "variants": ["light-desktop"], "rows": rows}, open(sys.argv[3], "w"))
PY
}
mkrr flat100 flat200 "$TMP/rr-diff.json"
bash "$GEN" "$TMP/rr-diff.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-diff.err" \
  && ok "BL-693 rows whose same-sized regions differ in pixels are both kept" \
  || fail "BL-693 a non-redundant pair was refused: $(cat "$TMP/rr-diff.err")"
mkrr flat100 flat100 "$TMP/rr-same.json"
bash "$GEN" "$TMP/rr-same.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-same.err"; rc=$?
[[ $rc == 2 ]] && grep -q "uno" "$TMP/rr-same.err" && grep -q "dos" "$TMP/rr-same.err" \
  && ok "BL-693 two review rows with identical highlighted crops are refused (any kind, not only sample)" \
  || fail "BL-693 identical flat crops: exit $rc, $(cat "$TMP/rr-same.err")"

# A prior row already DECIDED still counts as shown: the knock-on that follows it is refused too.
python3 - "$TMP/rr.json" "$TMP/rr-decided.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][0]["decided"] = "Aprobada"
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rr-decided.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-dec.err"; rc=$?
[[ $rc == 2 ]] && grep -q "skeleton-sin-entregas" "$TMP/rr-dec.err" \
  && ok "BL-693 a sample repeating the region of an already decided row is refused" \
  || fail "BL-693 decided prior: exit $rc, $(cat "$TMP/rr-dec.err")"

# -- a live before/after pair with identical pixels is refused (owner, LOOP-008 Q8) --
mkpair() {  # mkpair <beforeDir/file> <afterDir/file> <out> [decided]
  python3 - "$1" "$2" "$3" "${4:-}" <<'PY'
import json, sys
row = {"cell": "inicial", "variant": "light-desktop", "kind": "review", "look": "Antes se asomaba el fondo; ahora no.",
       "highlight": "@avisos", "before": "shots/%s.png" % sys.argv[1], "after": "shots/%s.png" % sys.argv[2]}
if sys.argv[4]:
    row["decided"] = sys.argv[4]
json.dump({"gallery": "g", "variants": ["light-desktop"], "rows": [row]}, open(sys.argv[3], "w"))
PY
}
mkpair flat100/a flat100/b "$TMP/pair-same.json"
bash "$GEN" "$TMP/pair-same.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/pair-same.out" 2> "$TMP/pair-same.err"; rc=$?
[[ $rc == 2 && ! -s "$TMP/pair-same.out" ]] && grep -q "inicial" "$TMP/pair-same.err" && grep -qi "identical" "$TMP/pair-same.err" \
  && ok "Q8 a live review row whose before and after are pixel-identical is refused naming the row" \
  || fail "Q8 identical pair: exit $rc, $(cat "$TMP/pair-same.err")"
mkpair flat100/a flat100/a "$TMP/pair-file.json"
bash "$GEN" "$TMP/pair-file.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/pair-file.err"; rc=$?
[[ $rc == 2 ]] && grep -qi "identical" "$TMP/pair-file.err" \
  && ok "Q8 before and after naming the same file are refused" || fail "Q8 same file: exit $rc, $(cat "$TMP/pair-file.err")"
mkpair flat200/a flat100/b "$TMP/pair-diff.json"
bash "$GEN" "$TMP/pair-diff.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/pair-diff.err" \
  && ok "Q8 a pair whose pixels differ builds" || fail "Q8 differing pair refused: $(cat "$TMP/pair-diff.err")"
mkdir -p "$ROOT/shots/pg1" "$ROOT/shots/pg2"
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/pg1/a.png" 1400 900 100
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/pg2/b.png" 1400 900 100 "300,400,6,10,200"
printf '{"avisos":{"x":10,"y":10,"w":1312,"h":800}}' > "$ROOT/shots/pg2/b.regions.json"
mkpair pg1/a pg2/b "$TMP/pair-glyph.json"
bash "$GEN" "$TMP/pair-glyph.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/pair-glyph.err" \
  && ok "Q8 a pair differing by one 6x10 block builds" || fail "Q8 one-glyph pair refused: $(cat "$TMP/pair-glyph.err")"
mkpair flat100/a flat100/b "$TMP/pair-dec.json" "Aprobada"
bash "$GEN" "$TMP/pair-dec.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/pair-dec.err" \
  && ok "Q8 a decided row with an identical pair is settled and builds" || fail "Q8 decided pair refused: $(cat "$TMP/pair-dec.err")"

# -- the redundancy check: boundary, which row to drop, unreadable PNGs (BL-693) --
mkdir -p "$ROOT/shots/big1" "$ROOT/shots/big2" "$ROOT/shots/mix1" "$ROOT/shots/mix2"
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/big1/a.png" 1400 900 100
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/big2/b.png" 1400 900 100 "300,400,6,10,200"
for d in big1:a big2:b; do printf '{"avisos":{"x":10,"y":10,"w":1312,"h":800}}' > "$ROOT/shots/${d%%:*}/${d##*:}.regions.json"; done
mkrr big1 big2 "$TMP/rr-glyph.json"
bash "$GEN" "$TMP/rr-glyph.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-glyph.err" \
  && ok "BL-693 a single 6x10 block changed by 100/255 inside a 1312x800 region keeps both rows" \
  || fail "BL-693 a one-glyph change was called redundant: $(cat "$TMP/rr-glyph.err")"
# The row named for dropping is chosen by kind, not by position.
python3 - "$TMP/rr.json" "$TMP/rr-rev.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"].reverse()
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rr-rev.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-rev.err"; rc=$?
[[ $rc == 2 ]] && grep -q "Drop the row 'skeleton-sin-entregas" "$TMP/rr-rev.err" \
  && ok "BL-693 with the rows in the other order the sample is still the row to drop" \
  || fail "BL-693 reversed rows: exit $rc, $(cat "$TMP/rr-rev.err")"
# Two decided rows are settled: nothing live to refuse.
python3 - "$TMP/rr.json" "$TMP/rr-d2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][0]["decided"] = "Aprobada"; d["rows"][1]["decided"] = "Aprobada"
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rr-d2.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-d2.err" \
  && ok "BL-693 two decided rows with one region are not refused" \
  || fail "BL-693 two decided rows were refused: $(cat "$TMP/rr-d2.err")"
# Two identical RGBA captures are refused (the reader handles colour type 6).
mkdir -p "$ROOT/shots/rgba1" "$ROOT/shots/rgba2"
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/rgba1/a.png" 400 700 100 "0,0,1,1,100" rgba
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/rgba2/b.png" 400 700 100 "0,0,1,1,100" rgba
for d in rgba1:a rgba2:b; do printf '{"avisos":{"x":10,"y":20,"w":300,"h":100}}' > "$ROOT/shots/${d%%:*}/${d##*:}.regions.json"; done
mkrr rgba1 rgba2 "$TMP/rr-rgba.json"
bash "$GEN" "$TMP/rr-rgba.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-rgba.err"; rc=$?
[[ $rc == 2 ]] && grep -q "uno" "$TMP/rr-rgba.err" \
  && ok "BL-693 two identical RGBA captures are compared and refused" \
  || fail "BL-693 RGBA pair: exit $rc, $(cat "$TMP/rr-rgba.err")"
# Exactly one decided: the LIVE row is the one to drop, whatever the order or kind.
python3 - "$TMP/rr.json" "$TMP/rr-live1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"][0]["kind"] = "sample"; d["rows"][1]["kind"] = "review"; d["rows"][1]["decided"] = "Aprobada"
json.dump(d, open(sys.argv[2], "w"))
PY
bash "$GEN" "$TMP/rr-live1.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-live1.err"; rc=$?
[[ $rc == 2 ]] && grep -q "Drop the row 'skeleton-todo-al-dia" "$TMP/rr-live1.err" \
  && ok "BL-693 a live row beside a decided one is the row to drop, even when it comes first" \
  || fail "BL-693 live-first: exit $rc, $(cat "$TMP/rr-live1.err")"
# Two NAMED regions are the same place only by name.
mkdir -p "$ROOT/shots/nm1" "$ROOT/shots/nm2"
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/nm1/a.png" 400 700 100
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/nm2/b.png" 400 700 100
printf '{"banner":{"x":10,"y":20,"w":300,"h":100},"footer":{"x":10,"y":500,"w":300,"h":100}}' > "$ROOT/shots/nm1/a.regions.json"
printf '{"banner":{"x":10,"y":20,"w":300,"h":100},"footer":{"x":10,"y":500,"w":300,"h":100}}' > "$ROOT/shots/nm2/b.regions.json"
python3 - "$TMP/rr-names.json" <<'PY'
import json, sys
rows = [{"cell": c, "variant": "light-desktop", "kind": "review", "look": "x", "highlight": h,
         "after": "shots/%s/%s.png" % (d, f)} for c, d, f, h in (("uno", "nm1", "a", "@banner"), ("dos", "nm2", "b", "@footer"))]
json.dump({"gallery": "g", "variants": ["light-desktop"], "rows": rows}, open(sys.argv[1], "w"))
PY
bash "$GEN" "$TMP/rr-names.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-names.err" \
  && ok "BL-693 @banner and @footer of one size, both blank, are two regions: both rows kept" \
  || fail "BL-693 different named regions were compared by size: $(cat "$TMP/rr-names.err")"
# Raw rectangles compare only when equal; a name and a raw rectangle only when it resolves to it.
python3 - "$TMP/rr-raw.json" "$TMP/rr-nameraw.json" "$TMP/rr-nameraw-eq.json" <<'PY'
import json, sys
def doc(h1, h2):
    return {"gallery": "g", "variants": ["light-desktop"], "rows": [
        {"cell": c, "variant": "light-desktop", "kind": "review", "look": "x", "highlight": h,
         "after": "shots/%s/%s.png" % (d, f)} for c, d, f, h in (("uno", "nm1", "a", h1), ("dos", "nm2", "b", h2))]}
r1, r2 = {"x": 10, "y": 20, "w": 300, "h": 100}, {"x": 10, "y": 500, "w": 300, "h": 100}
json.dump(doc(r1, r2), open(sys.argv[1], "w"))
json.dump(doc("@banner", r2), open(sys.argv[2], "w"))
json.dump(doc("@banner", r1), open(sys.argv[3], "w"))
PY
bash "$GEN" "$TMP/rr-raw.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-raw.err" \
  && ok "BL-693 two raw rectangles of one size at y=20 and y=500 are two places: both rows kept" \
  || fail "BL-693 raw rects at different places were compared: $(cat "$TMP/rr-raw.err")"
bash "$GEN" "$TMP/rr-nameraw.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-nameraw.err" \
  && ok "BL-693 @banner (y=20) beside a raw rectangle at y=500: both rows kept" \
  || fail "BL-693 a name and a different raw rect were compared: $(cat "$TMP/rr-nameraw.err")"
bash "$GEN" "$TMP/rr-nameraw-eq.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-ne.err"; rc=$?
[[ $rc == 2 ]] && ok "BL-693 @banner beside the raw rectangle it resolves to is compared, and refused when blank" \
  || fail "BL-693 name vs equal raw rect: exit $rc, $(cat "$TMP/rr-ne.err")"
python3 - "$SKILL" <<'PY' && ok "BL-693 png_pixels.crop returns the exact bytes for PNG filter types 0-4, RGB and RGBA" || fail "BL-693 png_pixels.crop disagrees with the known pixels for a filter type"
import struct, sys, zlib
sys.path.insert(0, sys.argv[1] + "/scripts/dash")
import png_pixels as P
for BPP, CT in ((3, 2), (4, 6)):
  W, H = 7, 5
  pix = [bytes((x * 37 + y * 11 + c * 53) % 256 for x in range(W) for c in range(BPP)) for y in range(H)]
  def paeth(a, b, c):
      p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
      return a if pa <= pb and pa <= pc else (b if pb <= pc else c)
  def enc(ft, cur, prev):
      out = bytearray()
      for i, v in enumerate(cur):
          a = cur[i - BPP] if i >= BPP else 0
          b = prev[i]
          c = prev[i - BPP] if i >= BPP else 0
          pr = (0, a, b, (a + b) >> 1, paeth(a, b, c))[ft]
          out.append((v - pr) & 255)
      return bytes([ft]) + bytes(out)
  def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)
  for ft in range(5):
      raw = b"".join(enc(ft, pix[y], pix[y - 1] if y else bytes(W * BPP)) for y in range(H))
      data = P.SIGNATURE + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, CT, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
      got = P.crop(data, 2, 1, 4, 3)
      want = [pix[y][2 * BPP:6 * BPP] for y in range(1, 4)]
      assert got == want, (ft, got, want)
PY
# Two highlights on a row: one repeated, one changed by a 100/255 block is a different row.
mkdir -p "$ROOT/shots/two1" "$ROOT/shots/two2"
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/two1/a.png" 400 700 100
python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/two2/b.png" 400 700 100 "50,520,10,10,200"
python3 - "$TMP/rr-two.json" <<'PY'
import json, sys
hl = [{"x": 10, "y": 20, "w": 300, "h": 100}, {"x": 10, "y": 500, "w": 300, "h": 100}]
rows = [{"cell": c, "variant": "light-desktop", "kind": "review", "look": "x", "highlight": hl,
         "after": "shots/%s/%s.png" % (d, f)} for c, d, f in (("uno", "two1", "a"), ("dos", "two2", "b"))]
json.dump({"gallery": "g", "variants": ["light-desktop"], "rows": rows}, open(sys.argv[1], "w"))
PY
bash "$GEN" "$TMP/rr-two.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-two.err" \
  && ok "BL-693 a row with two highlights, one identical and one changed, is kept" \
  || fail "BL-693 two highlights, one changed: $(cat "$TMP/rr-two.err")"
# A missing capture is the render loop's refusal, never a traceback.
python3 - "$TMP/rr.json" "$TMP/rr-miss.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][1]["after"] = "shots/rr/not-there.png"
json.dump(d, open(sys.argv[2], "w"))
PY
cp "$ROOT/shots/rr/dashboard-skeleton-sin-entregas-darwin.regions.json" "$ROOT/shots/rr/not-there.regions.json"
bash "$GEN" "$TMP/rr-miss.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-miss.err"; rc=$?
[[ $rc == 2 ]] && grep -q "skeleton-sin-entregas" "$TMP/rr-miss.err" && ! grep -q Traceback "$TMP/rr-miss.err" \
  && ok "BL-693 a missing capture is refused naming its row, with no traceback" \
  || fail "BL-693 missing capture: exit $rc, $(cat "$TMP/rr-miss.err")"
# The tolerance is pinned: a block 4 off is the same pixels, 5 off is a change.
tolcase() {  # tolcase <level> -> exit code of a build of two flats, one with a 10x10 block at <level>
  mkdir -p "$ROOT/shots/tol1" "$ROOT/shots/tol2"
  python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/tol1/a.png" 400 700 100
  python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/tol2/b.png" 400 700 100 "50,50,10,10,$1"
  for d in tol1:a tol2:b; do printf '{"avisos":{"x":10,"y":20,"w":300,"h":100}}' > "$ROOT/shots/${d%%:*}/${d##*:}.regions.json"; done
  mkrr tol1 tol2 "$TMP/rr-tol.json"
  bash "$GEN" "$TMP/rr-tol.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T >/dev/null 2>"$TMP/rr-tol.err"
}
tolcase 104; rc=$?
[[ $rc == 2 ]] && grep -q "uno · light-desktop" "$TMP/rr-tol.err" && grep -q "dos · light-desktop" "$TMP/rr-tol.err" \
  && ok "BL-693 a block 4/255 off is the same pixels: refused, and the message names cell · variant" \
  || fail "BL-693 tolerance 4: exit $rc, $(cat "$TMP/rr-tol.err")"
tolcase 105; rc=$?
[[ $rc == 0 ]] && ok "BL-693 a block 5/255 off is a change: both rows kept" || fail "BL-693 tolerance 5: exit $rc, $(cat "$TMP/rr-tol.err")"
python3 - "$SKILL" <<'PY' && ok "BL-693 png_pixels reads None for a palette PNG, a corrupt IDAT and a short IHDR" || fail "BL-693 png_pixels did not return None for an unreadable file"
import struct, sys, zlib
sys.path.insert(0, sys.argv[1] + "/scripts/dash")
import png_pixels as P
def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)
def png(ctype, idat, ihdr=None):
    ihdr = ihdr if ihdr is not None else struct.pack(">IIBBBBB", 4, 4, 8, ctype, 0, 0, 0)
    return P.SIGNATURE + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
raw = zlib.compress(b"".join(b"\0" + b"\1" * 4 for _ in range(4)))
assert P.crop(png(3, raw), 0, 0, 2, 2) is None, "palette"
assert P.crop(png(0, raw), 0, 0, 2, 2) is not None, "control: the same bytes as greyscale read"
assert P.crop(png(0, b"not zlib at all"), 0, 0, 2, 2) is None, "corrupt idat"
assert P.crop(png(0, raw, ihdr=b"\0\0"), 0, 0, 2, 2) is None, "short ihdr"
PY

echo "== look, note and title are prose; a decision is not independent rows =="
mkdir -p "$TMP/pr"
prrun() {  # prrun <name> <python expr editing d["rows"]>
  python3 - "$TMP/rows.json" "$TMP/pr/$1.json" "$2" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1])); exec(sys.argv[3]); json.dump(d, open(sys.argv[2], "w"))
PY2
  bash "$GEN" "$TMP/pr/$1.json" --root "$ROOT" --page "$PAGE" --group-id E --group-title T > "$TMP/pr/$1.out" 2> "$TMP/pr/$1.err"
}
prrun look "d['rows'][0]['look'] = 'Look **here**, see [the spec](https://example.test/x).'"; rc=$?
if [[ $rc == 0 ]] && grep -qF '<a href="https://example.test/x">the spec</a>' "$TMP/pr/look.out" \
    && grep -qF '<strong>here</strong>' "$TMP/pr/look.out" && ! grep -qF '](https' "$TMP/pr/look.out"; then
  ok "a look line renders its link as <a> and its bold as <strong>"
else fail "look markup: exit $rc, $(grep -o 'gal-look[^\n]*' "$TMP/pr/look.out" | sed -n 1,1p) $(cat "$TMP/pr/look.err")"; fi
prrun note "d['rows'][0]['note'] = ['First **point**', 'Then \`code\` and [a link](https://example.test/y)']"; rc=$?
if [[ $rc == 0 ]] && grep -qF '<li>First <strong>point</strong></li>' "$TMP/pr/note.out" \
    && grep -qF '<code>code</code>' "$TMP/pr/note.out" \
    && grep -qF '<a href="https://example.test/y">a link</a>' "$TMP/pr/note.out"; then
  ok "a note line renders bold, code and a link"
else fail "note markup: exit $rc, $(cat "$TMP/pr/note.err")"; fi
prrun title "d['rows'][0]['title'] = 'A **bold** title with \`code\`'"; rc=$?
if [[ $rc == 0 ]] && grep -qF '<h3>A <strong>bold</strong> title with <code>code</code></h3>' "$TMP/pr/title.out" \
    && grep -qF 'data-heading="A bold title with code"' "$TMP/pr/title.out" \
    && ! grep -qF '**' "$TMP/pr/title.out"; then
  ok "a row title renders its markers in the heading and keeps them out of data-heading"
else fail "title markers: exit $rc, $(grep -o '<h3>[^<]*' "$TMP/pr/title.out" | sed -n 1,2p) $(cat "$TMP/pr/title.err")"; fi
prrun tlink "d['rows'][0]['title'] = 'See [the spec](https://example.test/x)'"; rc=$?
if [[ $rc == 2 && ! -s "$TMP/pr/tlink.out" ]] && grep -q "row 'empty'.*raw-link" "$TMP/pr/tlink.err"; then
  ok "a link in a row title is refused (raw-link), naming the row"
else fail "title link: exit $rc, $(cat "$TMP/pr/tlink.err")"; fi
SINGLE="{'cell': 'EXTRA', 'variant': 'light-desktop', 'kind': 'review', 'look': 'x', 'after': 'actual/light-desktop/audit-new-state.png'}"
mkdir -p "$TMP/pr/spec"; cp -R "$ROOT/shots" "$ROOT/actual" "$TMP/pr/spec/"
cat > "$TMP/pr/spec/p.spec.md" <<MD
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Galería

Filas de prueba.
:::

::: gallery {#G title="Revisión" rows="rows.json" root="$ROOT"}
:::

::: notes {title="Notas generales"}
:::
MD
specrun() {  # specrun <name> <python expr editing d["rows"]>
  prrun "$1" "$2" >/dev/null 2>&1
  cp "$TMP/pr/$1.json" "$TMP/pr/spec/rows.json"
  ( cd "$TMP/pr/spec" && python3 "$SKILL/scripts/spec_build.py" p.spec.md -o "$1.html" > "$TMP/pr/$1.sb" 2>&1 )
}
specrun props "d['rows'] = [dict($SINGLE, cell=c) for c in ('a', 'b', 'hoy')]"; rc=$?
if [[ $rc != 0 && ! -f "$TMP/pr/spec/props.html" ]] && grep -q '`gallery`' "$TMP/pr/props.sb" \
    && grep -q "alternatives" "$TMP/pr/props.sb" && grep -q "noBefore" "$TMP/pr/props.sb"; then
  ok "several single-capture rows with no noBefore are refused by the spec build, naming gallery, alternatives and noBefore"
else fail "proposals as rows: rc $rc, $(tail -3 "$TMP/pr/props.sb")"; fi
specrun onesingle "d['rows'] = [dict($SINGLE, cell='a')]"; rc=$?
[[ $rc == 0 && -f "$TMP/pr/spec/onesingle.html" ]] && ok "ONE single-capture row with no noBefore (a plain new screen) still builds from a spec" \
  || fail "one new screen: rc $rc, $(tail -3 "$TMP/pr/onesingle.sb")"
specrun states "d['rows'] = [dict($SINGLE, cell=c) for c in ('loading', 'empty', 'error')]"; rc=$?
[[ $rc == 0 && -f "$TMP/pr/spec/states.html" ]] && ok "several single-capture STATE rows (loading, empty, error: the manifest shape) still build from a spec" \
  || fail "state rows: rc $rc, $(tail -3 "$TMP/pr/states.sb")"
specrun hoyalone "d['rows'] = [dict($SINGLE, cell='hoy')]"; rc=$?
[[ $rc == 0 && -f "$TMP/pr/spec/hoyalone.html" ]] && ok "one bare 'hoy' row alone builds" || fail "hoy alone: rc $rc, $(tail -3 "$TMP/pr/hoyalone.sb")"
specrun hoya "d['rows'] = [dict($SINGLE, cell=c) for c in ('hoy', 'a')]"; rc=$?
[[ $rc != 0 && ! -f "$TMP/pr/spec/hoya.html" ]] && grep -q "current state" "$TMP/pr/hoya.sb" && grep -q "before" "$TMP/pr/hoya.sb" \
  && ok "'hoy' + one more bare cell is refused, telling to make it the before" || fail "hoy + a: rc $rc, $(tail -3 "$TMP/pr/hoya.sb")"
specrun hoydec "d['rows'] = [dict($SINGLE, cell='hoy', decided='Hoy se queda'), dict($SINGLE, cell='b')]"; rc=$?
[[ $rc == 0 && -f "$TMP/pr/spec/hoydec.html" ]] && ok "a DECIDED 'hoy' row beside one bare row builds" || fail "hoy decided: rc $rc, $(tail -3 "$TMP/pr/hoydec.sb")"
specrun hoyvars "d['variants'] = ['light-desktop', 'dark-desktop']; d['rows'] = [dict($SINGLE, cell='hoy'), dict($SINGLE, cell='hoy', variant='dark-desktop')]"; rc=$?
[[ $rc == 0 && -f "$TMP/pr/spec/hoyvars.html" ]] && ok "one 'hoy' cell in two variants is one screen and builds" || fail "hoy two variants: rc $rc, $(tail -3 "$TMP/pr/hoyvars.sb")"
specrun uistates "d['rows'] = [dict($SINGLE, cell=c) for c in ('before-submit', 'today-empty', 'current-user-menu', 'now-playing')]"; rc=$?
[[ $rc == 0 && -f "$TMP/pr/spec/uistates.html" ]] && ok "state cells before-submit, today-empty, current-user-menu, now-playing build" || fail "ui states: rc $rc, $(tail -3 "$TMP/pr/uistates.sb")"
prrun jslink "d['rows'][0]['look'] = 'See [x](javascript:alert(1)) now'"; rc=$?
if [[ $rc == 0 ]] && ! grep -qF 'href="javascript' "$TMP/pr/jslink.out" && grep -qF 'x (javascript:alert(1))' "$TMP/pr/jslink.out"; then
  ok "a javascript: link in a look is never an href, it shows as 'x (javascript:alert(1))'"
else fail "javascript link: exit $rc, $(grep -o 'gal-look[^\n]*' "$TMP/pr/jslink.out" | sed -n 1p)"; fi
specrun manynb "d['rows'] = [dict($SINGLE, cell=c, noBefore='new screen') for c in ('a', 'b', 'hoy')]"; rc=$?
[[ $rc == 0 && -f "$TMP/pr/spec/manynb.html" ]] && ok "several single-capture rows each with a noBefore reason still build from a spec" \
  || fail "several noBefore: rc $rc, $(tail -3 "$TMP/pr/manynb.sb")"
# A row title is user text: a '%' in it ('50% de' reads as a '% d' conversion)
# must reach the alt text literally, never be formatted a second time.
PCT='Más del 50% de filas y 100 %'
A1=actual/light-desktop/audit-empty.png; A2=actual/light-desktop/audit-new-state.png
specrun pctstates "d['rows'] = [{'cell': 'c', 'variant': 'light-desktop', 'kind': 'states', 'look': 'x', 'title': '$PCT', 'states': [{'id': 'a', 'label': 'A', 'capture': '$A1'}, {'id': 'b', 'label': 'B', 'capture': '$A2'}]}]"; rc_s=$?
specrun pctalts "d['alternatives'] = [{'id': 'a', 'label': 'A'}, {'id': 'b', 'label': 'B'}]; d['rows'] = [{'cell': 'c', 'variant': 'light-desktop', 'kind': 'alternatives', 'look': 'x', 'title': '$PCT', 'captures': {'a': '$A1', 'b': '$A2'}}]"; rc_a=$?
if [[ $rc_s == 0 && $rc_a == 0 ]] && grep -qF "alt=\"$PCT · B\"" "$TMP/pr/spec/pctstates.html" \
    && grep -qF "alt=\"$PCT · B\"" "$TMP/pr/spec/pctalts.html"; then
  ok "a '%' in a states or alternatives row title builds and reaches the alt text literally"
else fail "percent in title: states rc $rc_s, alternatives rc $rc_a, $(tail -1 "$TMP/pr/pctstates.sb") / $(tail -1 "$TMP/pr/pctalts.sb")"; fi

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: the gallery unit — generator, refusals, wrapped page and every RED control"
