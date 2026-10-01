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
png() {  # png <path under ROOT> <width> <height>
  mkdir -p "$(dirname "$ROOT/$1")"
  python3 "$SKILL/tests/png_fixture.py" "$ROOT/$1" "$2" "$3"
}
png shots/light-desktop/audit-empty.png 160 90
png actual/light-desktop/audit-empty.png 160 90
png actual/light-desktop/audit-new-state.png 160 90
png shots/dark-mobile/audit-loaded.png 39 84
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
[[ "$rc" == 2 ]] && grep -q 'must be an absolute path' "$TMP/rel.err" \
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
    printf '%s\n' "$2"
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
  printf '<section class="consult-group" id="E" data-id="E" data-title="The audit gallery"%s><div class="sec-head"><h2>The audit gallery</h2></div><p>The state matrix this block reviews, one row per screen state.</p>%s</section>' \
    "$1" "$2"
}
header='<header><p class="eyebrow">FIXTURE</p><h1>Claim</h1><p class="standfirst">The thesis.</p></header>'
notes='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><textarea></textarea></section>'
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

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: the gallery unit — generator, refusals, wrapped page and every RED control"
