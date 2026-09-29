#!/usr/bin/env bash
# Gallery rows for a REVIEW OF ALTERNATIVES (plan 2026-09-29-ui-contract-hardening,
# task 3.1; BL-516 1-4, BL-466 3-4).
#
# The first two real ui-contract runs showed the gallery could only say "before /
# proposed": two NEW skeleton variants were labelled antes/propuesto on every tile
# and the owner could not answer any row. This file pins what replaced that, at
# the layer that owns each decision (deterministic generator, checker, reply
# parser, spec builder; the composer's own behaviour is in
# test-composer-functional.sh):
#
#   the `alternatives` kind   N variants per cell, labels from the rows document,
#                             one which-one radio, NOT a relabelling of before/after
#   the compact answer        verdict + note visible, the rest inside <details>
#   the `look` line           required by the spec route, naming the row when absent
#   `sample` from the spec    a sample row reaches the page with no radios
#   the reply                 the chosen label comes back as the row's verdict
#   `dropped` / `decided`     an item or row leaves the question set, its id stays
#   the ordering              a gallery block may precede the questions that ask
#                             about it (a pin: the checker never refused it)
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$SKILL/scripts/gallery-items.sh"
REPLY="$SKILL/scripts/gallery-reply.sh"
CHECK="$SKILL/scripts/check-artifact.sh"
BUILD="$SKILL/scripts/spec_build.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf '  ok: %s\n' "$*"; }

ROOT="$TMP/repo"
mkdir -p "$ROOT" && git -C "$ROOT" init -q
png() { mkdir -p "$(dirname "$ROOT/$1")"; python3 "$SKILL/tests/png_fixture.py" "$ROOT/$1" "$2" "$3"; }
png shots/list-a.png 160 90
png shots/list-drawer.png 160 90
png shots/base.png 160 90
png shots/next.png 160 90

# The rows document of an alternatives review: the variants are declared ONCE
# (slug + the label the reader sees), every row shows each of them.
cat > "$TMP/alt.json" <<'JSON'
{"gallery": "skel", "variants": ["light-desktop"],
 "alternatives": [{"id": "a", "label": "Esqueleto A"}, {"id": "drawer", "label": "Con cajón"}],
 "rows": [
  {"cell": "list", "variant": "light-desktop", "kind": "alternatives",
   "look": "Dónde queda el botón de crear en cada una",
   "captures": {"a": "shots/list-a.png", "drawer": "shots/list-drawer.png"}}
 ]}
JSON
PAGE="$TMP/page.html"
gen() { bash "$GEN" "$1" --root "$ROOT" --page "$PAGE" --group-id E --group-title "Esqueletos" "${@:2}"; }
item() { sed -n "/data-id=\"$1\"/,/<\/section>/p" "$2"; }

echo "== the alternatives kind =="
gen "$TMP/alt.json" > "$TMP/alt.html" 2> "$TMP/alt.err" \
  && ok "an alternatives document generates" \
  || fail "an alternatives document was refused: $(cat "$TMP/alt.err")"
row="$(item skel-list-light-desktop-alternatives "$TMP/alt.html")"
[[ -n "$row" ]] && ok "the row id is <gallery>-<cell>-<variant>-alternatives" \
  || fail "no row with id skel-list-light-desktop-alternatives: $(grep -o 'data-id="[^"]*"' "$TMP/alt.html" | tr '\n' ' ')"
grep -q 'data-tiles="a drawer"' "$TMP/alt.html" \
  && ok "the block declares the alternatives as its tiles" \
  || fail "the block's data-tiles is not the declared alternatives: $(head -1 "$TMP/alt.html")"
for label in "Esqueleto A" "Con cajón"; do
  grep -q "<figcaption>$label</figcaption>" <<<"$row" \
    && ok "tile caption is the spec's label: $label" \
    || fail "no figcaption '$label' in the row"
  grep -q "data-label=\"$label\"" <<<"$row" \
    && ok "which-one radio carries the label: $label" \
    || fail "no radio data-label='$label' in the row"
done
if grep -qiwE 'antes|propuesto|before|proposed' <<<"$row"; then
  fail "the alternatives row still says antes/propuesto/before/proposed: $(grep -oiwE 'antes|propuesto|before|proposed' <<<"$row" | head -1)"
else ok "the row never says antes/propuesto/before/proposed"; fi
n="$(grep -o 'type="radio" name="skel-list-light-desktop-alternatives"' <<<"$row" | wc -l | tr -d ' ')"
[[ "$n" -eq 3 ]] && ok "one radio group named for the row (2 alternatives + none of them)" || fail "expected 3 radios in the row, found $n"
cat > "$TMP/three.json" <<'JSON'
{"gallery": "skel", "variants": ["light-desktop"],
 "alternatives": [{"id": "a", "label": "Esqueleto A"}, {"id": "b", "label": "Esqueleto B"}, {"id": "drawer", "label": "Con cajón"}],
 "rows": [{"cell": "list", "variant": "light-desktop", "kind": "alternatives", "look": "x",
   "captures": {"a": "shots/list-a.png", "b": "shots/base.png", "drawer": "shots/list-drawer.png"}}]}
JSON
gen "$TMP/three.json" > "$TMP/three.html" 2>/dev/null
python3 - "$TMP/three.html" <<'PY' && ok "3 alternatives: all 3 labelled radios visible, only 'none of them' collapsed" || fail "alternatives radios are not 3 visible + 1 collapsed (see above)"
import re, sys
row = re.search(r'data-id="skel-list-light-desktop-alternatives".*?</section>', open(sys.argv[1], encoding="utf-8").read(), re.S).group(0)
m = re.search(r'<details\b[^>]*>(.*?)</details>', row, re.S)
if not m: sys.exit("no details")
inside = re.findall(r'data-label="([^"]*)"', m.group(1))
outside = re.findall(r'data-label="([^"]*)"', row.replace(m.group(0), ""))
if inside != ["Ninguna"] or outside != ["Esqueleto A", "Esqueleto B", "Con cajón"]:
    sys.exit("inside=%r outside=%r" % (inside, outside))
PY
grep -q 'Qué mirar' <<<"$row" && grep -q 'Dónde queda el botón' <<<"$row" \
  && ok "the row carries its look line" || fail "the row does not show its look line"

echo "== refusals name the row =="
refuse() {  # refuse <label> <needle> <python that edits d>
  python3 - "$TMP/alt.json" "$TMP/bad.json" <<PY
import json, sys
d = json.load(open(sys.argv[1]))
$3
json.dump(d, open(sys.argv[2], "w"))
PY
  gen "$TMP/bad.json" > "$TMP/bad.out" 2> "$TMP/bad.err"; rc=$?
  if [[ $rc == 2 && ! -s "$TMP/bad.out" && "$(cat "$TMP/bad.err")" == *"$2"* ]]; then ok "$1"
  else fail "$1: exit $rc, stdout $(wc -c < "$TMP/bad.out")B, stderr: $(cat "$TMP/bad.err")"; fi
}
refuse "a row missing a declared alternative's capture" "row 'list' has no capture for 'drawer'" 'del d["rows"][0]["captures"]["drawer"]'
refuse "an alternatives row with no declared alternatives" "declares no 'alternatives'" 'del d["alternatives"]'
refuse "an alternative id that collides with a before/after tile" "alternative id 'before' is a before/after tile" 'd["alternatives"][0]["id"] = "before"'
refuse "duplicate labels (case-insensitive)" "same label twice" 'd["alternatives"][1]["label"] = "esqueleto a"'
refuse "a label equal to the none-of-them choice" "reserved" 'd["alternatives"][1]["label"] = "Ninguna"'
refuse "a label equal to the Other choice" "reserved" 'd["alternatives"][1]["label"] = "Otra — lo explico en las notas"'
refuse "a label shaped like a marker" "marker" 'd["alternatives"][1]["label"] = "[question]"'
refuse "a before/after row in a document that declares alternatives" "row 'old' is a review row" \
  'd["rows"].append({"cell": "old", "variant": "light-desktop", "kind": "review", "after": "shots/next.png"})'

echo "== the compact answer =="
cat > "$TMP/rev.json" <<'JSON'
{"gallery": "audit", "variants": ["light-desktop"],
 "rows": [{"cell": "empty", "variant": "light-desktop", "kind": "review",
   "before": "shots/base.png", "after": "shots/next.png"},
  {"cell": "muestra", "variant": "light-desktop", "kind": "sample", "after": "shots/next.png"}]}
JSON
gen "$TMP/rev.json" > "$TMP/rev.html" 2>/dev/null
python3 - "$TMP/rev.html" <<'PY' && ok "review row: two verdicts visible, the rest inside a collapsed details" || fail "review row is not compact (see above)"
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
row = re.search(r'data-id="audit-empty-light-desktop".*?</section>', html, re.S).group(0)
m = re.search(r'<details\b[^>]*>(.*?)</details>', row, re.S)
if not m: sys.exit("no <details> in the row")
inside = len(re.findall(r'type="radio"', m.group(1)))
outside = len(re.findall(r'type="radio"', row)) - inside
if (outside, inside) != (2, 1): sys.exit("radios outside/inside details = %d/%d, expected 2/1" % (outside, inside))
PY
sample="$(item audit-muestra-light-desktop-sample "$TMP/rev.html")"
[[ -n "$sample" ]] && ! grep -q 'type="radio"' <<<"$sample" \
  && ok "a sample row emits no radio inputs" || fail "a sample row is missing or carries radios"

echo "== the spec route: look is required, sample and alternatives are reachable =="
mkdir -p "$TMP/spec"
cp "$TMP/alt.json" "$TMP/spec/alt.json"
cat > "$TMP/spec/a.spec.md" <<'MD'
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Esqueletos

Dos variantes por celda.
:::

::: gallery {#G title="Esqueletos" rows="alt.json" root="ROOT"}
:::

::: group {#Q title="Preguntas" eyebrow="Bloque Q"}
El contexto.

::: item {#Q1 title="Cuál"}
¿Con cuál seguimos?

- A {recommended}
- Con cajón
:::
:::

::: notes {title="Notas generales"}
:::
MD
sed -i.bak "s#root=\"ROOT\"#root=\"$ROOT\"#" "$TMP/spec/a.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" a.spec.md -o a.html > "$TMP/b.out" 2>&1 ); rc=$?
[[ $rc == 0 && -f "$TMP/spec/a.html" ]] && ok "an alternatives gallery builds from a spec with -o" \
  || fail "the alternatives spec did not build: $(tail -3 "$TMP/b.out")"
bash "$CHECK" "$TMP/spec/a.html" > "$TMP/c.out" 2>&1 \
  && ok "the built page (gallery BEFORE the question) passes check-artifact" \
  || fail "the page with a gallery before its question fails the check: $(tail -3 "$TMP/c.out")"
python3 - "$TMP/spec/alt.json" "$TMP/spec/nolook.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); del d["rows"][0]["look"]
d["rows"].append({"cell": "second", "variant": "light-desktop", "kind": "alternatives", "look": "x",
                  "captures": {"a": "shots/list-a.png", "drawer": "shots/list-drawer.png"}})
json.dump(d, open(sys.argv[2], "w"))
PY
sed 's/rows="alt.json"/rows="nolook.json"/' "$TMP/spec/a.spec.md" > "$TMP/spec/nolook.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" nolook.spec.md --check -o nolook.html > "$TMP/n.out" 2>&1 ); rc=$?
[[ $rc != 0 && "$(cat "$TMP/n.out")" == *"'list'"*look* && "$(cat "$TMP/n.out")" != *"'second'"* ]] \
  && ok "--check fails the row with no look line and names it ('list', not 'second')" \
  || fail "a row with no look passed --check or the message does not name it (rc $rc): $(cat "$TMP/n.out")"
# sample kind through the spec
python3 - "$TMP/spec/alt.json" "$TMP/spec/sample.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
del d["alternatives"]
d["rows"] = [{"cell": "muestra", "variant": "light-desktop", "kind": "sample", "look": "El espaciado",
              "after": "shots/next.png"}]
json.dump(d, open(sys.argv[2], "w"))
PY
sed 's/rows="alt.json"/rows="sample.json"/' "$TMP/spec/a.spec.md" > "$TMP/spec/sample.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" sample.spec.md -o sample.html > "$TMP/s.out" 2>&1 ); rc=$?
if [[ $rc == 0 ]]; then
  s="$(item skel-muestra-light-desktop-sample "$TMP/spec/sample.html")"
  [[ -n "$s" ]] && ! grep -q 'type="radio"' <<<"$s" && grep -q 'El espaciado' <<<"$s" \
    && ok "a sample row built from a spec has its look line and no radios" \
    || fail "the sample row from the spec is missing, has radios or lacks its look"
else fail "the sample spec did not build: $(tail -2 "$TMP/s.out")"; fi

echo "== the reply parses the chosen alternative back =="
printf '### skel-list-light-desktop-alternatives · skel · list · light-desktop\n\n- Con cajón\n\nel botón queda mejor arriba\n' > "$TMP/r1.txt"
bash "$REPLY" --rows "$TMP/alt.json" "$TMP/r1.txt" > "$TMP/r1.json" 2> "$TMP/r1.err"
python3 - "$TMP/r1.json" <<'PY' && ok "the label of the chosen alternative comes back as the verdict, kind alternatives" || fail "alternatives verdict not parsed: $(cat "$TMP/r1.err")"
import json, sys
r = json.load(open(sys.argv[1]))["rows"]
assert len(r) == 1, r
r = r[0]
assert r["kind"] == "alternatives" and r["verdict"] == "Con cajón", r
assert r["notes"] == "el botón queda mejor arriba", r
PY
printf '### audit-empty-light-desktop · audit · empty · light-desktop\n\n- Con cajón\n' > "$TMP/r2.txt"
bash "$REPLY" "$TMP/r2.txt" 2>/dev/null | python3 -c "
import json, sys
r = json.load(sys.stdin)['rows'][0]
sys.exit(0 if r['verdict'] == '' and r['notes'] == '- Con cajón' else 1)" \
  && ok "a free label is only an answer on an alternatives row: on a review row it stays notes" \
  || fail "a free label was read as a verdict on a review row"

# The page's own labels decide what an answer is: bullets typed as notes on an
# UNANSWERED alternatives row are notes, never a fabricated verdict, and never
# a refusal that hides the rows after them.
printf '### skel-list-light-desktop-alternatives · skel · list · light-desktop\n\n- el botón arriba\n- el cajón más estrecho\n\n### Q1 · Cuál\n\n- A\n' > "$TMP/r3.txt"
bash "$REPLY" --rows "$TMP/alt.json" "$TMP/r3.txt" > "$TMP/r3.json" 2> "$TMP/r3.err"; rc=$?
python3 - "$TMP/r3.json" $rc <<'PY' && ok "two note bullets on an unanswered alternatives row stay notes; Q1 after it still parses" || fail "bullets on an unanswered row: rc $rc $(cat "$TMP/r3.err")"
import json, sys
assert sys.argv[2] == "0", "exit " + sys.argv[2]
d = json.load(open(sys.argv[1]))
r = d["rows"][0]
assert r["verdict"] == "" and r["notes"] == "- el botón arriba\n- el cajón más estrecho", r
assert [o["id"] for o in d["other"]] == ["Q1"], d["other"]
PY
printf '### skel-list-light-desktop-alternatives · skel · list · light-desktop\n\n- el botón arriba\n' > "$TMP/r4.txt"
bash "$REPLY" --rows "$TMP/alt.json" "$TMP/r4.txt" 2>/dev/null | python3 -c "
import json, sys
r = json.load(sys.stdin)['rows'][0]
sys.exit(0 if r['verdict'] == '' and r['notes'] == '- el botón arriba' else 1)" \
  && ok "one note bullet on an unanswered alternatives row is not a verdict" || fail "a lone bullet became a verdict"
printf '### skel-list-light-desktop-alternatives · skel · list · light-desktop\n\n- Ninguna\n' > "$TMP/r5.txt"
bash "$REPLY" --rows "$TMP/alt.json" "$TMP/r5.txt" 2>/dev/null | python3 -c "
import json, sys
sys.exit(0 if json.load(sys.stdin)['rows'][0]['verdict'] == 'Ninguna' else 1)" \
  && ok "the none-of-them choice is an answer" || fail "none-of-them not read as an answer"
bash "$REPLY" "$TMP/r1.txt" > /dev/null 2> "$TMP/r6.err"; rc=$?
[[ $rc == 2 && "$(cat "$TMP/r6.err")" == *"--rows"* ]] \
  && ok "an alternatives row with no --rows is refused, naming the flag (labels unknown)" \
  || fail "no-labels case: rc $rc $(cat "$TMP/r6.err")"

echo "== labels are validated and stored trimmed =="
python3 - "$TMP/alt.json" "$TMP/trim.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["alternatives"][0]["label"] = "  Esqueleto Z  "
json.dump(d, open(sys.argv[2], "w"))
PY
gen "$TMP/trim.json" 2>/dev/null | grep -q '<figcaption>Esqueleto Z</figcaption>' \
  && ok "a label is stored trimmed" || fail "a padded label was not trimmed"

echo "== dropped and decided: out of the question set, id kept =="
cat > "$TMP/spec/d.spec.md" <<'MD'
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Ronda

Una abierta, una descartada.
:::

::: group {#Q title="Preguntas" eyebrow="Bloque Q"}
El contexto.

::: item {#Q1 title="Cuál"}
¿Con cuál seguimos?

- A {recommended}
- B
:::

::: item {#Q2 title="Extra"}
¿Y el extra?

- Sí {recommended}
- No
:::
:::

::: notes {title="Notas generales"}
:::
MD
sed 's/^::: item {#Q2 title="Extra"}/::: item {#Q2 title="Extra" dropped="ya no aplica al esqueleto"}/' \
  "$TMP/spec/d.spec.md" > "$TMP/spec/d2.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" d.spec.md -o d1.html > "$TMP/d1.out" 2>&1 && python3 "$BUILD" d2.spec.md -o d2.html > "$TMP/d2.out" 2>&1 ); rc=$?
if [[ $rc == 0 ]]; then
  tag="$(grep -o '<section[^>]*data-id="Q2"[^>]*>' "$TMP/spec/d2.html")"
  [[ "$tag" == *'data-dropped="ya no aplica al esqueleto"'* && "$tag" == *'data-decided="Descartada: ya no aplica al esqueleto"'* ]] \
    && ok "a dropped item carries data-dropped and a decided line that says Descartada + the reason" \
    || fail "dropped item tag is wrong: $tag"
  bash "$CHECK" "$TMP/spec/d2.html" --prev "$TMP/spec/d1.html" > "$TMP/dc.out" 2>&1; rc=$?
  [[ $rc == 0 && "$(cat "$TMP/dc.out")" != *consult-ids* ]] \
    && ok "check-artifact --prev accepts an open item that became dropped (its id stays)" \
    || fail "--prev refused a dropped item (rc $rc): $(cat "$TMP/dc.out")"
else fail "the dropped spec did not build: $(tail -2 "$TMP/d1.out" "$TMP/d2.out")"; fi
sed 's/dropped="ya no aplica al esqueleto"/dropped="x" decided="y"/' "$TMP/spec/d2.spec.md" > "$TMP/spec/d3.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" d3.spec.md --check -o d3.html > "$TMP/d3.out" 2>&1 ); rc=$?
[[ $rc != 0 && "$(cat "$TMP/d3.out")" == *dropped*decided* ]] \
  && ok "an item that is both dropped and decided is refused" \
  || fail "dropped+decided was not refused (rc $rc): $(cat "$TMP/d3.out")"
sed 's/dropped="ya no aplica al esqueleto"/dropped=""/' "$TMP/spec/d2.spec.md" > "$TMP/spec/d4.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" d4.spec.md --check -o d4.html > "$TMP/d4.out" 2>&1 ); rc=$?
[[ $rc != 0 ]] && ok "a dropped item with no reason is refused" || fail "dropped=\"\" was accepted"

# A gallery row: dropped keeps its id and title but needs no captures; decided keeps its captures.
python3 - "$TMP/alt.json" "$TMP/spec/drop.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"].append({"cell": "old", "variant": "light-desktop", "kind": "alternatives",
                  "dropped": "la celda se fue del alcance"})
d["rows"].append({"cell": "done", "variant": "light-desktop", "kind": "alternatives", "look": "x",
                  "decided": "Con cajón",
                  "captures": {"a": "shots/list-a.png", "drawer": "shots/list-drawer.png"}})
json.dump(d, open(sys.argv[2], "w"))
PY
gen "$TMP/spec/drop.json" > "$TMP/drop.html" 2> "$TMP/drop.err" \
  && ok "a document with a dropped row (no captures) and a decided row generates" \
  || fail "dropped/decided rows refused: $(cat "$TMP/drop.err")"
tag="$(grep -o '<section[^>]*data-id="skel-old-light-desktop-alternatives"[^>]*>' "$TMP/drop.html")"
[[ "$tag" == *'data-title="skel · old · light-desktop"'* && "$tag" == *'data-dropped="la celda se fue del alcance"'* \
   && "$tag" == *'data-decided="Descartada: la celda se fue del alcance"'* ]] \
  && ok "the dropped row keeps its exact id and title and is marked dropped" \
  || fail "dropped row tag: $tag"
grep -q 'class="gal-na">la celda se fue del alcance' <<<"$(item skel-old-light-desktop-alternatives "$TMP/drop.html")" \
  && ok "the dropped row shows its reason where the tiles were" || fail "dropped row has no gal-na reason"
[[ "$(grep -o '<section[^>]*data-id="skel-done-light-desktop-alternatives"[^>]*>' "$TMP/drop.html")" == *'data-decided="Con cajón"'* ]] \
  && ok "a decided row carries data-decided with its verdict" || fail "decided row has no data-decided"
# The page holding them passes the contract, and --prev accepts the round.
sed 's/rows="alt.json"/rows="drop.json"/' "$TMP/spec/a.spec.md" > "$TMP/spec/drop.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" drop.spec.md -o drop.html > "$TMP/dp.out" 2>&1 ); rc=$?
[[ $rc == 0 ]] && ok "a page with a dropped and a decided gallery row builds and passes the contract" \
  || fail "the dropped/decided gallery page failed: $(tail -3 "$TMP/dp.out")"
bash "$CHECK" "$TMP/spec/drop.html" --prev "$TMP/spec/a.html" > "$TMP/dpc.out" 2>&1 \
  && ok "--prev: a round that adds a dropped row and keeps every earlier id passes" \
  || fail "--prev refused the dropped gallery round: $(tail -3 "$TMP/dpc.out")"

echo "== retiring a before/after row for alternatives of the same cell =="
python3 - "$TMP/spec" <<'PY'
import json, os
d = os.path.join(os.sys.argv[1])
json.dump({"gallery": "skel", "variants": ["light-desktop"],
           "rows": [{"cell": "list", "variant": "light-desktop", "kind": "review", "look": "x",
                     "before": "shots/base.png", "after": "shots/next.png"}]},
          open(os.path.join(d, "r1.json"), "w"))
json.dump({"gallery": "skel", "variants": ["light-desktop"],
           "alternatives": [{"id": "a", "label": "Esqueleto A"}, {"id": "drawer", "label": "Con cajón"}],
           "rows": [{"cell": "list", "variant": "light-desktop", "kind": "review", "dropped": "ahora son alternativas"},
                    {"cell": "list", "variant": "light-desktop", "kind": "alternatives", "look": "x",
                     "captures": {"a": "shots/list-a.png", "drawer": "shots/list-drawer.png"}}]},
          open(os.path.join(d, "r2.json"), "w"))
json.dump({"gallery": "skel", "variants": ["light-desktop"],
           "rows": [{"cell": "list", "variant": "light-desktop", "kind": "review", "dropped": "ya no aplica"}]},
          open(os.path.join(d, "r3.json"), "w"))
PY
for n in 1 2 3; do sed "s/rows=\"alt.json\"/rows=\"r$n.json\"/" "$TMP/spec/a.spec.md" > "$TMP/spec/ret$n.spec.md"
  ( cd "$TMP/spec" && python3 "$BUILD" ret$n.spec.md -o ret$n.html > "$TMP/ret$n.out" 2>&1 ) || fail "retirement page $n did not build: $(tail -2 "$TMP/ret$n.out")"; done
bash "$CHECK" "$TMP/spec/ret2.html" --prev "$TMP/spec/ret1.html" > "$TMP/retc.out" 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'data-id="skel-list-light-desktop"' "$TMP/spec/ret2.html" \
   && grep -q 'data-id="skel-list-light-desktop-alternatives"' "$TMP/spec/ret2.html"; then
  ok "page 2 (dropped review + alternatives row of the same cell) passes --prev against page 1, both ids present"
else fail "retirement round failed (rc $rc): $(tail -3 "$TMP/retc.out")"; fi
bash "$CHECK" "$TMP/spec/ret3.html" --prev "$TMP/spec/ret1.html" > "$TMP/retc3.out" 2>&1 \
  && ok "an open review row that becomes dropped, same kind, passes --prev" \
  || fail "open -> dropped same kind failed: $(tail -3 "$TMP/retc3.out")"
python3 - "$TMP/spec/r2.json" "$TMP/spec/dup.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"].append(dict(d["rows"][1]))
json.dump(d, open(sys.argv[2], "w"))
PY
gen "$TMP/spec/dup.json" > /dev/null 2> "$TMP/dup.err"; rc=$?
[[ $rc == 2 && "$(cat "$TMP/dup.err")" == *"'list'"* ]] \
  && ok "two LIVE rows for one cell and variant are still refused (dropped rows are the only exemption)" \
  || fail "duplicate live rows: rc $rc $(cat "$TMP/dup.err")"

echo "== dropped on a row whose variant left the chosen set, and on a not-applicable row =="
cat > "$TMP/dv.json" <<'JSON'
{"gallery": "audit", "variants": ["light-desktop"],
 "rows": [
  {"cell": "list", "variant": "light-desktop", "kind": "review", "look": "x", "after": "shots/next.png"},
  {"cell": "list", "variant": "dark-mobile", "kind": "review", "dropped": "dark-mobile left the chosen variants"},
  {"cell": "gone", "notApplicable": "cannot reach", "dropped": "cell removed"}]}
JSON
gen "$TMP/dv.json" > "$TMP/dv.html" 2> "$TMP/dv.err" \
  && ok "a dropped row in a variant that left the chosen set generates" \
  || fail "dropped row in a removed variant refused: $(cat "$TMP/dv.err")"
[[ "$(grep -o '<section[^>]*data-id="audit-list-dark-mobile"[^>]*>' "$TMP/dv.html")" == *'data-dropped="dark-mobile left the chosen variants"'* ]] \
  && ok "...and is marked dropped" || fail "removed-variant dropped row not marked"
[[ "$(grep -o '<section[^>]*data-id="audit-gone-not-applicable"[^>]*>' "$TMP/dv.html")" == *'data-dropped="cell removed"'* ]] \
  && ok "a not-applicable row can be dropped (data-dropped carried, never ignored)" \
  || fail "dropped on a notApplicable row was silently ignored"

echo "== a not-applicable row in an alternatives document =="
python3 - "$TMP/alt.json" "$TMP/naalt.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"].append({"cell": "off", "notApplicable": "unreachable in the demo"})
json.dump(d, open(sys.argv[2], "w"))
PY
gen "$TMP/naalt.json" > "$TMP/naalt.html" 2>/dev/null
if grep -qiwE 'antes|propuesto|before|proposed|baseline' "$TMP/naalt.html"; then
  fail "the alternatives document's block still says before/proposed/baseline: $(grep -oiwE 'antes|propuesto|before|proposed|baseline' "$TMP/naalt.html" | sort -u | tr '\n' ' ')"
else ok "no antes/propuesto/before/proposed/baseline anywhere in the block, not-applicable row included"; fi

echo "== not-applicable rows: decided, dropped+decided, duplicate ids =="
narow() {  # narow <label> <needle> <rows-json-fragment>
  printf '{"gallery": "audit", "variants": ["light-desktop"], "rows": [%s]}' "$3" > "$TMP/na.json"
  gen "$TMP/na.json" > "$TMP/na.out" 2> "$TMP/na.err"; rc=$?
  if [[ $rc == 2 && ! -s "$TMP/na.out" && "$(cat "$TMP/na.err")" == *"$2"* ]]; then ok "$1"
  else fail "$1: exit $rc, stdout $(wc -c < "$TMP/na.out")B, stderr: $(cat "$TMP/na.err")"; fi
}
printf '{"gallery": "audit", "variants": ["light-desktop"], "rows": [{"cell": "x", "notApplicable": "r", "decided": "Aprobada"}]}' > "$TMP/na.json"
gen "$TMP/na.json" > "$TMP/na.html" 2>/dev/null
[[ "$(grep -o '<section[^>]*data-id="audit-x-not-applicable"[^>]*>' "$TMP/na.html")" == *'data-decided="Aprobada"'* ]] \
  && ok "a decided not-applicable row carries data-decided" || fail "decided on a notApplicable row was ignored"
narow "dropped + decided on a not-applicable row is refused, naming the cell" "row 'x'" \
  '{"cell": "x", "notApplicable": "r", "dropped": "gone", "decided": "Aprobada"}'
narow "a dropped and a live not-applicable row of one cell are refused" "cell 'x'" \
  '{"cell": "x", "notApplicable": "r", "dropped": "gone"}, {"cell": "x", "notApplicable": "r"}'
narow "two live not-applicable rows of one cell are refused" "cell 'x'" \
  '{"cell": "x", "notApplicable": "r"}, {"cell": "x", "notApplicable": "r2"}'
refuse "a label equal to the none-of-them choice in another case" "reserved" 'd["alternatives"][1]["label"] = "ninguna"'
printf '### skel-list-light-desktop-alternatives · skel · list · light-desktop\n\n- Aprobada\n' > "$TMP/r7.txt"
bash "$REPLY" --rows "$TMP/alt.json" "$TMP/r7.txt" 2>/dev/null | python3 -c "
import json, sys
r = json.load(sys.stdin)['rows'][0]
sys.exit(0 if r['verdict'] == '' and r['notes'] == '- Aprobada' else 1)" \
  && ok "a review verdict word is not an answer on an alternatives row" || fail "'Aprobada' was read as an alternatives verdict"
printf '### skel-list-light-desktop-alternatives · skel · list · light-desktop\n\n- Otra — lo explico en las notas\n' > "$TMP/r8.txt"
bash "$REPLY" --rows "$TMP/alt.json" "$TMP/r8.txt" 2>/dev/null | python3 -c "
import json, sys
sys.exit(0 if json.load(sys.stdin)['rows'][0]['verdict'].startswith('Otra') else 1)" \
  && ok "the Other choice is still an answer on an alternatives row" || fail "Other lost on an alternatives row"

if [[ $failures -gt 0 ]]; then echo "FAILED: $failures"; exit 1; fi
echo "ok: gallery alternatives, compact answer, look, sample, reply, dropped and ordering"
