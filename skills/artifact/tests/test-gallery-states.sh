#!/usr/bin/env bash
# The gallery `states` row kind (BL-659): N locator-scoped captures of ONE
# component in ONE item, a checkbox per state, a reply that says which states
# were approved. Layer: deterministic generator + reply parser + checker, the
# same layer test-gallery-alternatives.sh pins `alternatives` at; the browser
# half (ticking, the copy button) is the e2e row of BL-659, not here.
#
#   the row           4 captures -> 1 item, 4 figures, 4 checkboxes, no radio
#   the reply         --rows: 4 states, 2 approved; no --rows: refused;
#                     lenient (save_reply): the ticked labels only
#   the refusals      one state, duplicate id, missing capture, a states row in
#                     an alternatives document
#   the page          a spec-built page holding a states row passes check-artifact
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
mkdir -p "$ROOT/shots"
i=0
for s in default hover loading disabled; do
  i=$((i + 1)); python3 "$SKILL/tests/png_fixture.py" "$ROOT/shots/$s.png" $((100 + i)) 40
done

cat > "$TMP/st.json" <<'JSON'
{"gallery": "btn", "variants": ["light-desktop"],
 "rows": [
  {"cell": "save", "variant": "light-desktop", "kind": "states",
   "look": "Cada estado del botón, solo",
   "states": [
    {"id": "default", "label": "Reposo", "capture": "shots/default.png"},
    {"id": "hover", "label": "Hover", "capture": "shots/hover.png"},
    {"id": "loading", "label": "Cargando", "capture": "shots/loading.png"},
    {"id": "disabled", "label": "Deshabilitado", "capture": "shots/disabled.png"}]}
 ]}
JSON
PAGE="$TMP/page.html"
gen() { bash "$GEN" "$1" --root "$ROOT" --page "$PAGE" --group-id B --group-title "Botón" "${@:2}"; }
ID=btn-save-light-desktop-states

echo "== the row =="
gen "$TMP/st.json" > "$TMP/st.html" 2> "$TMP/st.err" \
  && ok "a states document generates" || fail "a states document was refused: $(cat "$TMP/st.err")"
n="$(grep -c 'consult-item consult-gallery' "$TMP/st.html")"
[[ "$n" -eq 1 ]] && ok "one item for the whole component" || fail "expected 1 item, found $n"
grep -q "data-id=\"$ID\"" "$TMP/st.html" && ok "the id is <gallery>-<cell>-<variant>-states" \
  || fail "no item $ID: $(grep -o 'data-id="[^"]*"' "$TMP/st.html" | tr '\n' ' ')"
n="$(grep -c '<figure ' "$TMP/st.html")"
[[ "$n" -eq 4 ]] && ok "4 figures" || fail "expected 4 figures, found $n"
n="$(grep -c 'type="checkbox"' "$TMP/st.html")"
[[ "$n" -eq 4 ]] && ok "4 checkboxes" || fail "expected 4 checkboxes, found $n"
python3 - "$TMP/st.html" <<'PY' && ok "figures and checkboxes follow the declared order and labels" || fail "figures/checkboxes are not in the declared order with the state labels"
import re, sys
h = open(sys.argv[1]).read()
caps = re.findall(r"<figcaption>([^<]*)</figcaption>", h)
boxes = re.findall(r'type="checkbox"[^>]*data-label="([^"]*)"', h)
want = ["Reposo", "Hover", "Cargando", "Deshabilitado"]
assert caps == want and boxes == want, (caps, boxes)
PY
grep -q 'type="radio"' "$TMP/st.html" && fail "a states row carries a verdict radio" || ok "no verdict radio"
grep -qiwE 'antes|propuesto' "$TMP/st.html" && fail "the states row says antes/propuesto" || ok "no before/after pair"
grep -q '<textarea' "$TMP/st.html" && ok "the notes textarea is there" || fail "no notes textarea"
grep -q 'Marca cada estado que apruebas' "$TMP/st.html" && ok "the intro has the states sentence (es)" || fail "no states sentence in the es intro"
gen "$TMP/st.json" --lang en 2>/dev/null | grep -q 'Tick each state you approve' \
  && ok "the intro has the states sentence (en)" || fail "no states sentence in the en intro"
# The sentence is emitted only when the block holds a states row.
python3 - "$TMP/st.json" "$TMP/rev.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["rows"] = [{"cell": "page", "variant": "light-desktop", "kind": "review",
              "before": "shots/default.png", "after": "shots/hover.png"}]
json.dump(d, open(sys.argv[2], "w"))
PY
gen "$TMP/rev.json" 2>/dev/null | grep -q 'Marca cada estado que apruebas' \
  && fail "a block with no states row carries the states sentence" || ok "no states sentence without a states row"

echo "== the reply =="
printf '## B · Botón\n### %s · btn · save · light-desktop\n\n- Hover\n- Cargando\n\nque el hover sea más claro\n' "$ID" > "$TMP/r.md"
bash "$REPLY" --rows "$TMP/st.json" "$TMP/r.md" > "$TMP/r.json" 2> "$TMP/r.err" \
  && ok "the states reply parses with --rows" || fail "the states reply was refused: $(cat "$TMP/r.err")"
python3 - "$TMP/r.json" <<'PY' && ok "4 declared states come back, 2 approved, notes kept" || fail "the parsed states are not 4 declared with 2 approved"
import json, sys
r = json.load(open(sys.argv[1]))["rows"][0]
assert r["kind"] == "states" and r["verdict"] == "", r
assert [(s["id"], s["label"], s["approved"]) for s in r["states"]] == [
    ("default", "Reposo", False), ("hover", "Hover", True),
    ("loading", "Cargando", True), ("disabled", "Deshabilitado", False)], r["states"]
assert r["notes"] == "que el hover sea más claro", r["notes"]
PY
bash "$REPLY" "$TMP/r.md" > /dev/null 2> "$TMP/r2.err"; rc=$?
[[ $rc == 2 && "$(wc -l < "$TMP/r2.err" | tr -d ' ')" == 1 ]] && grep -q "$ID" "$TMP/r2.err" \
  && ok "without --rows the states row is refused in one line naming it" \
  || fail "without --rows: exit $rc, $(cat "$TMP/r2.err")"
python3 - "$SKILL/scripts/dash" "$TMP/r.md" <<'PY' && ok "lenient parse returns the ticked labels only" || fail "lenient parse does not return the ticked labels only"
import sys
sys.path.insert(0, sys.argv[1])
import gallery_reply
r = gallery_reply.parse(open(sys.argv[2]).read(), lenient=True)["rows"][0]
assert r["states"] == [{"label": "Hover", "approved": True},
                       {"label": "Cargando", "approved": True}], r["states"]
PY
printf '## B · Botón\n### %s · btn · save · light-desktop\n\nnada me convence\n' "$ID" > "$TMP/r0.md"
bash "$REPLY" --rows "$TMP/st.json" "$TMP/r0.md" 2>/dev/null | python3 -c '
import json, sys
s = json.load(sys.stdin)["rows"][0]["states"]
assert len(s) == 4 and not any(x["approved"] for x in s), s' \
  && ok "a reply with nothing ticked returns all 4 states unapproved" || fail "nothing ticked did not give 4 unapproved states"

echo "== the refusals =="
refuse() { # <name> <python mutation of d / r> <expected fragment>
  python3 - "$TMP/st.json" "$TMP/bad.json" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); r = d["rows"][0]
exec(sys.argv[3])
json.dump(d, open(sys.argv[2], "w"))
PY
  gen "$TMP/bad.json" > /dev/null 2> "$TMP/bad.err"; rc=$?
  [[ $rc == 2 && "$(wc -l < "$TMP/bad.err" | tr -d ' ')" == 1 ]] && grep -q "$3" "$TMP/bad.err" \
    && ok "refused: $1" || fail "$1: exit $rc, stderr: $(cat "$TMP/bad.err")"
}
refuse "one state" 'r["states"] = r["states"][:1]' "at least two"
refuse "a duplicate id" 'r["states"][1]["id"] = "default"' "'default' twice"
refuse "a duplicate label" 'r["states"][1]["label"] = "reposo"' "used by two states"
refuse "a state named like a tile" 'r["states"][0]["id"] = "before"' "tile name"
refuse "a [marker] label" 'r["states"][0]["label"] = "[question]"' "reserved"
refuse "the Other label" 'r["states"][0]["label"] = "Otra — lo explico en las notas"' "reserved"
refuse "a missing capture" 'r["states"][2]["capture"] = "shots/nope.png"' "has no file"
refuse "a states row in an alternatives document" 'd["alternatives"] = [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}]' "alternatives"

echo "== the reply, round 2 =="
# A label with stray whitespace: the generator strips it, so must the parser.
python3 - "$TMP/st.json" "$TMP/sp.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["rows"][0]["states"][0]["label"] = "Reposo "
json.dump(d, open(sys.argv[2], "w"))
PY
printf '## B · Botón\n### %s · btn · save · light-desktop\n\n- Reposo\n' "$ID" > "$TMP/rs.md"
bash "$REPLY" --rows "$TMP/sp.json" "$TMP/rs.md" 2>/dev/null | python3 -c '
import json, sys
r = json.load(sys.stdin)["rows"][0]
assert r["states"][0]["approved"] is True and r["notes"] == "", r' \
  && ok "a label with trailing space still reads as ticked" || fail "a stripped label did not read as ticked"
printf '## B · Botón\n### %s · btn · save · light-desktop\n\n- Fantasma\n' "$ID" > "$TMP/rg.md"
bash "$REPLY" --rows "$TMP/st.json" "$TMP/rg.md" 2>&1 >/dev/null | grep -q 'warning: row .*"Fantasma" is not a label' \
  && ok "an undeclared bullet in a states answer warns (stale --rows)" || fail "no stale --rows warning for an undeclared states bullet"
printf '## B · Botón\n### %s · btn · save · light-desktop\n\n- Hover\n- Otra — lo explico en las notas\n\nel reposo no\n' "$ID" > "$TMP/ro.md"
bash "$REPLY" --rows "$TMP/st.json" "$TMP/ro.md" 2>/dev/null | python3 -c '
import json, sys
r = json.load(sys.stdin)["rows"][0]
assert r["verdict"] == "Otra — lo explico en las notas", r
assert [s["label"] for s in r["states"] if s["approved"]] == ["Hover"], r
assert r["notes"] == "el reposo no", r' \
  && ok "Other is the verdict under --rows, never a state" || fail "Other was read as a state or lost under --rows"
python3 - "$SKILL/scripts/dash" "$TMP/ro.md" "$ID" "$TMP/r.md" "$TMP/r0.md" <<'PY' && ok "lenient: Other is the verdict and save_reply owes other-verdict; notes owe needs-changes; nothing ticked, no notes owes nothing" || fail "lenient Other / notes duties are wrong"
import sys
sys.path.insert(0, sys.argv[1])
import gallery_reply, save_reply
ro, ident = open(sys.argv[2]).read(), sys.argv[3]
r = gallery_reply.parse(ro, lenient=True)["rows"][0]
assert r["verdict"] == "Otra — lo explico en las notas", r
assert r["states"] == [{"label": "Hover", "approved": True}], r["states"]
assert (ident, "other-verdict", save_reply.GALLERY_OTHER_DUTY) in save_reply.gallery_duties_for(ro)
rn = open(sys.argv[4]).read()                       # ticked + notes
assert (ident, "needs-changes", save_reply.GALLERY_NEEDS_DUTY) in save_reply.gallery_duties_for(rn)
none = "## B · Botón\n### %s · btn · save · light-desktop\n\n- Hover\n" % ident
assert save_reply.gallery_duties_for(none) == [], save_reply.gallery_duties_for(none)
zero = "## B · Botón\n### %s · btn · save · light-desktop\n" % ident
assert save_reply.gallery_duties_for(zero) == [], save_reply.gallery_duties_for(zero)
PY
printf '## B · Botón\n### %s · btn · save · light-desktop\n\n- Hover\n\n[mark hover 10.0,10.0 20.0x20.0] borde\n' "$ID" > "$TMP/rm.md"
bash "$REPLY" --rows "$TMP/st.json" --tiles "before after" "$TMP/rm.md" 2>/dev/null | python3 -c '
import json, sys
m = json.load(sys.stdin)["rows"][0]["marks"]
assert len(m) == 1 and m[0]["tile"] == "hover", m' \
  && ok "a mark on a state parses though --tiles is the block's before/after" || fail "a mark on a state was refused under --tiles"
sed 's/mark hover/mark before/' "$TMP/rm.md" > "$TMP/rmb.md"
bash "$REPLY" --rows "$TMP/st.json" --tiles "before after" "$TMP/rmb.md" >/dev/null 2>"$TMP/rmb.err"; rc=$?
[[ $rc == 2 ]] && grep -q "tile 'before'" "$TMP/rmb.err" \
  && ok "a mark on 'before' is refused on a states row" || fail "a mark on 'before' in a states row: exit $rc, $(cat "$TMP/rmb.err")"

echo "== the page =="
mkdir -p "$TMP/spec"; cp "$TMP/st.json" "$TMP/spec/st.json"
cat > "$TMP/spec/s.spec.md" <<'MD'
::: masthead {eyebrow="Fixture" byline="Fuente: fixture" visual="none: fixture"}
# Botón

Estados del botón.
:::

::: gallery {#G title="Estados" rows="st.json" root="ROOT"}
:::

::: notes {title="Notas generales"}
:::
MD
sed -i.bak "s#root=\"ROOT\"#root=\"$ROOT\"#" "$TMP/spec/s.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" s.spec.md -o s.html > "$TMP/b.out" 2>&1 ); rc=$?
[[ $rc == 0 && -f "$TMP/spec/s.html" ]] && ok "a states gallery builds from a spec" \
  || fail "the states spec did not build: $(tail -3 "$TMP/b.out")"
bash "$CHECK" "$TMP/spec/s.html" > "$TMP/c.out" 2>&1 \
  && ok "the built page passes check-artifact" || fail "check-artifact refuses the states page: $(tail -4 "$TMP/c.out")"
# The item's matrix is its own states: a page that drops one figure still fails.
python3 - "$TMP/spec/s.html" "$TMP/spec/short.html" <<'PY'
import re, sys
h = open(sys.argv[1]).read()
h = re.sub(r'<figure data-tile="hover">.*?</figure>', '', h, count=1, flags=re.S)
open(sys.argv[2], "w").write(h)
PY
bash "$CHECK" "$TMP/spec/short.html" > "$TMP/c2.out" 2>&1 \
  && fail "check-artifact passes a states item that lost a figure" \
  || { grep -q 'missing tile(s) hover' "$TMP/c2.out" && ok "a states item missing a figure fails the check" \
       || fail "wrong failure for a missing state figure: $(tail -3 "$TMP/c2.out")"; }

# Mutants of the page: the item's own matrix must stay as strict as the block's.
cat > "$TMP/spec/rows2.json" <<'JSON'
{"gallery": "btn", "variants": ["light-desktop"],
 "rows": [
  {"cell": "save", "variant": "light-desktop", "kind": "states", "look": "x",
   "states": [
    {"id": "default", "label": "Reposo", "capture": "shots/default.png"},
    {"id": "hover", "label": "Hover", "capture": "shots/hover.png"},
    {"id": "loading", "label": "Cargando", "capture": "shots/loading.png"}]},
  {"cell": "page", "variant": "light-desktop", "kind": "review", "look": "x",
   "before": "shots/default.png", "after": "shots/hover.png"}]}
JSON
sed 's/rows="st.json"/rows="rows2.json"/' "$TMP/spec/s.spec.md" > "$TMP/spec/m.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" m.spec.md -o m.html > "$TMP/m.out" 2>&1 ) \
  && bash "$CHECK" "$TMP/spec/m.html" > /dev/null 2>&1 \
  && ok "a states row beside a review row builds and passes" || fail "states + review in one document: $(tail -3 "$TMP/m.out")"
mutant() { # <name> <python over h (the page html)> <expected failure fragment>
  python3 - "$TMP/spec/m.html" "$TMP/spec/mut.html" "$2" <<'PY'
import re, sys
h = open(sys.argv[1]).read()
def item(h, ident):                     # (start, end) of one consult item
    a = h.index('data-id="%s"' % ident); a = h.rindex("<section", 0, a)
    return a, h.index("</section>", a)
def drop(h, ident, tile):
    a, b = item(h, ident)
    seg = re.sub(r'<figure data-tile="%s">.*?</figure>' % tile, "", h[a:b], count=1, flags=re.S)
    return h[:a] + seg + h[b:]
def tag(h, ident, attr):                # add an attribute to the item's open tag
    a, _ = item(h, ident)
    return h[:a] + h[a:].replace("<section ", "<section %s " % attr, 1)
S, R = "btn-save-light-desktop-states", "btn-page-light-desktop"
exec(sys.argv[3])
open(sys.argv[2], "w").write(h)
PY
  bash "$CHECK" "$TMP/spec/mut.html" > "$TMP/mut.out" 2>&1 \
    && fail "check-artifact passes the mutant: $1" \
    || { grep -q "$3" "$TMP/mut.out" && ok "check-artifact refuses: $1" \
         || fail "the mutant '$1' fails for the wrong reason: $(head -2 "$TMP/mut.out")"; }
}
mutant "a review item shrinking its matrix with data-states" 'h = tag(drop(h, R, "before"), R, "data-states=\"after\"")' "not a states row"
mutant "a states item repeating a state id" 'h = tag(drop(drop(h, S, "default"), S, "loading"), S, "data-states=\"hover hover\"")' "at least two distinct"
mutant "a states item with one state" 'h = tag(drop(drop(h, S, "default"), S, "loading"), S, "data-states=\"hover\"")' "at least two distinct"
mutant "a states item naming a block tile" 'h = tag(drop(h, S, "loading").replace("data-tile=\"default\"", "data-tile=\"before\""), S, "data-states=\"before hover\"")' "none of them a block tile"

# A review row whose generated data-id merely CONTAINS the text "data-states".
cat > "$TMP/spec/rows3.json" <<'JSON'
{"gallery": "data", "variants": ["light-desktop"],
 "rows": [{"cell": "states", "variant": "light-desktop", "kind": "review", "look": "x",
           "before": "shots/default.png", "after": "shots/hover.png"}]}
JSON
sed 's/rows="st.json"/rows="rows3.json"/' "$TMP/spec/s.spec.md" > "$TMP/spec/d.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" d.spec.md -o d.html > "$TMP/d.out" 2>&1 ) \
  && bash "$CHECK" "$TMP/spec/d.html" > /dev/null 2>&1 \
  && ok "a review row whose id contains 'data-states' builds and passes" \
  || fail "a review row with id data-states-... was refused: $(tail -3 "$TMP/d.out")"

echo "== what save_reply owes, read against the page's own states =="
python3 - "$SKILL/scripts/dash" "$TMP/spec/s.html" "$ID" <<'PY' && ok "states duties: partial or bullets-only owe needs-changes; all ticked, or nothing at all, owe nothing; Other wins" || fail "save_reply states duties are wrong"
import sys
sys.path.insert(0, sys.argv[1])
import save_reply
page, ident = open(sys.argv[2]).read(), sys.argv[3]
st = save_reply.states_in_page(page)
assert [s["label"] for s in st[ident]] == ["Reposo", "Hover", "Cargando", "Deshabilitado"], st
def duties(body):
    return [d[1] for d in save_reply.gallery_duties_for(
        "## B · Botón\n### %s · btn · save · light-desktop\n%s" % (ident, body), states=st)]
assert duties("\n- el reposo debe ser más claro\n- el hover sin sombra\n") == ["needs-changes"], duties("\n- el reposo debe ser más claro\n- el hover sin sombra\n")
assert duties("\n- Hover\n") == ["needs-changes"]                       # 1 of 4, no notes
assert duties("\n- Reposo\n- Hover\n- Cargando\n- Deshabilitado\n\nperfecto así\n") == []
assert duties("\n") == []                                              # blank row: like a review row with no verdict
assert duties("\n- Hover\n- Otra — lo explico en las notas\n") == ["other-verdict"]
PY

mkdir -p "$TMP/sv" && cp "$TMP/spec/s.html" "$TMP/sv/s.html"
printf '## B · Botón\n### %s · btn · save · light-desktop\n\n- el reposo debe ser más claro\n- el hover sin sombra\n' "$ID" > "$TMP/sv/reply.md"
python3 - "$SKILL/scripts/dash" "$TMP/sv/s.html" "$TMP/sv/reply.md" "$ID" <<'PY' && ok "save_reply on the real page: a bullets-only states reply owes needs-changes" || fail "save_reply did not read the page's states for a bullets-only reply"
import sys
sys.path.insert(0, sys.argv[1])
import save_reply
duties = save_reply.save_reply(sys.argv[2], open(sys.argv[3]).read())[0]
assert (sys.argv[4], "needs-changes", save_reply.GALLERY_NEEDS_DUTY) in duties, duties
PY

# A block whose own id ends in -states (a natural name) is not a states row.
sed 's/{#G title/{#button-states title/' "$TMP/spec/s.spec.md" > "$TMP/spec/b.spec.md"
( cd "$TMP/spec" && python3 "$BUILD" b.spec.md -o b.html > "$TMP/bb.out" 2>&1 ) || fail "the #button-states spec did not build: $(tail -3 "$TMP/bb.out")"
python3 - "$SKILL/scripts/dash" "$TMP/spec/b.html" "$ID" <<'PY' && ok "a block id ending in -states is no states row; the real row's labels are read, partial owes needs-changes, all ticked owes nothing" || fail "states_in_page / duties confused a -states block with the row"
import sys
sys.path.insert(0, sys.argv[1])
import save_reply
page, ident = open(sys.argv[2]).read(), sys.argv[3]
assert 'data-id="button-states"' in page
st = save_reply.states_in_page(page)
assert st == {ident: [{"id": "default", "label": "Reposo"}, {"id": "hover", "label": "Hover"},
                      {"id": "loading", "label": "Cargando"}, {"id": "disabled", "label": "Deshabilitado"}]}, st
head = "## B · Botón\n### %s · btn · save · light-desktop\n" % ident
d = save_reply.gallery_duties_for(head + "\n- Hover\n", states=st)
assert (ident, "needs-changes", save_reply.GALLERY_NEEDS_DUTY) in d, d
assert save_reply.gallery_duties_for(head + "\n- Reposo\n- Hover\n- Cargando\n- Deshabilitado\n\nperfecto así\n", states=st) == []
PY

if [[ $failures -gt 0 ]]; then echo "FAILED: $failures"; exit 1; fi
echo "ok: gallery states row, reply, refusals and page"
