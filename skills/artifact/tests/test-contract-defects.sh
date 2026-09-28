#!/usr/bin/env bash
# test-contract-defects.sh — unit cells for scripts/dash/contract_defects.py (the
# five LOOP-006 contract-defect classes) and the shape of defect-gate.sh's output.
#
# Layer: unit, on source. Each class is decided by the script reading markup, so a
# mini-page per verdict is the lowest layer that sees the rule; no browser.
# Each class has pages that must FAIL (the defect's shape) and pages that must
# PASS (the kit's shape, or the declared exemption). The real pages each class
# was frozen on are private and live in the gate's registry, not here; what this
# repo carries is synthetic: these mini-pages and one kit-built good.html per
# class under fixtures/defect-classes/.
#
# XFAIL: a good.html the CURRENT kit cannot build clean, printed by name. It is
# admitted for ONE finding shape only (the English railhead "Contents" on an es
# page); any other finding on a good page is a FAIL. Once Phase C fixes the kit
# and the good pages are rebuilt, the same cells print ok and the xfail count
# drops to 0.
#
# Run with: bash skills/artifact/tests/test-contract-defects.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CD="$HERE/../scripts/dash/contract_defects.py"
GOOD="$HERE/fixtures/defect-classes"

PASS=0 FAIL=0 XFAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

page() {   # page NAME LANG BODY -> $TMP/NAME.html  (LANG "-" = no lang attribute)
  local attr=""
  [[ "$2" != "-" ]] && attr=" lang=\"$2\""
  printf '<!doctype html><html%s><head><meta charset="utf-8"></head><body>\n%s\n</body></html>\n' \
    "$attr" "$3" > "$TMP/$1.html"
}
fails()  { python3 "$CD" --class "$1" "$TMP/$2.html" >/dev/null && bad "$3" || ok "$3"; }
passes() { python3 "$CD" --class "$1" "$TMP/$2.html" >/dev/null && ok "$3" || bad "$3"; }

RAIL_OK='<aside class="rail"><p class="railhead">Contenido</p><nav id="raillist"></nav>
<div class="consult-bar"><button id="consult-copy">Copiar mis respuestas</button></div></aside>'
END_OK='<div class="endbar"><button id="consult-copy-end">Copiar mis respuestas</button></div>'
RADIO='<div class="opts one"><label><input type="radio" name="Q1" data-label="Sí">Sí</label>
<label><input type="radio" name="Q1" data-label="No">No</label></div>'
ONE_RADIO='<div class="opts one"><label><input type="radio" name="Q1" data-label="Sí">Sí</label></div>'

echo "== decision-item-without-options =="
C=decision-item-without-options
page c1-free es '<section class="consult-item" data-id="Q1" data-title="¿Cerramos?"><h3>¿Cerramos?</h3>
<textarea placeholder="Lo que sea…"></textarea></section>'
fails $C c1-free "an item with only a textarea fails"
page c1-opts es "<section class=\"consult-item\" data-id=\"Q1\" data-title=\"¿Cerramos?\">$RADIO<textarea></textarea></section>"
passes $C c1-opts "an item with two radios passes"
page c1-one es "<section class=\"consult-item\" data-id=\"Q1\">$ONE_RADIO<textarea></textarea></section>"
fails $C c1-one "an item with a single radio is not a choice"
page c1-sel1 es '<section class="consult-item" data-id="Q1"><select><option>Sí</option></select></section>'
fails $C c1-sel1 "a select with one option is not a choice"
page c1-sel2 es '<section class="consult-item" data-id="Q1"><select><option>Sí</option><option>No</option></select></section>'
passes $C c1-sel2 "a select with two options passes"
page c1-exempt es '<section class="consult-item" data-id="Q1" data-free><textarea></textarea></section>
<section class="consult-item" data-id="Q2" data-decided="sí" data-decided-round="2"><textarea></textarea></section>
<section class="consult-item consult-notes" data-id="notes"><textarea></textarea></section>'
passes $C c1-exempt "data-free, data-decided and the notes item are exempt"
page c1-free-no es '<section class="consult-item" data-id="Q1" data-free="no"><textarea></textarea></section>'
fails $C c1-free-no "data-free=\"no\" does not exempt"
page c1-free-false es '<section class="consult-item" data-id="Q1" data-free="false"><textarea></textarea></section>'
fails $C c1-free-false "data-free=\"false\" does not exempt"
page c1-round es '<section class="consult-item" data-id="Q1" data-decided-round="2"><textarea></textarea></section>'
fails $C c1-round "data-decided-round alone is not data-decided"
page c1-nested es "<section class=\"consult-item\" data-id=\"Q1\"><textarea></textarea>
<section class=\"consult-item\" data-id=\"Q1a\">$RADIO</section></section>"
fails $C c1-nested "a nested item's options do not count for the outer item"
page c1-rec es '<ul><li>Me sirve así {recommended}</li><li>No</li></ul>'
fails $C c1-rec "a literal {recommended} in page text fails"
page c1-rec-attr es '<section class="consult-item" data-id="Q1"><div class="opts one">
<label><input type="radio" name="Q1" data-label="Sí {recommended}">Sí</label>
<label><input type="radio" name="Q1" data-label="No">No</label></div></section>'
fails $C c1-rec-attr "a literal {recommended} in data-label fails"
page c1-rec-code es '<p>El marcador <code>{recommended}</code> va al final.</p><pre>- Sí {recommended}</pre>'
passes $C c1-rec-code "{recommended} inside code or pre is a page about the marker"

echo "== decision-page-not-interactive =="
C=decision-page-not-interactive
page c2-empty es '<main><h2>Necesita decisión — sin cambios</h2><ul><li>BL-1</li></ul><h2>Métricas</h2>
<section class="consult-item" data-id="Q9">'"$RADIO"'</section></main>'
fails $C c2-empty "a decision heading whose section has no item fails, even with an item under the next h2"
page c2-en en '<h3>Pending decisions</h3><p>None drawn.</p>'
fails $C c2-en "the English vocabulary is read too"
page c2-imp en '<h2>Decide the export format</h2><p>Two options.</p>'
fails $C c2-imp "an imperative Decide heading counts"
page c2-h1 en '<h1>Pending decisions</h1><p>Listed below as prose.</p>'
fails $C c2-h1 "an h1 is read"
page c2-h4 es '<h4>Por decidir</h4><p>Tres cosas.</p>'
fails $C c2-h4 "an h4 is read"
page c2-tr es '<h2>Decisiones pendientes</h2><table><tr data-id="Q1"><td>¿Cerramos?</td></tr></table>'
fails $C c2-tr "a table row with a data-id is not a consult item"
page c2-ok es '<section class="consult-group" data-id="G1"><h2>Decisiones pendientes</h2>
<section class="consult-item" data-id="Q1"><h3>¿Cerramos?</h3>'"$RADIO"'</section></section>'
passes $C c2-ok "a decision heading followed by an item passes"
page c2-inside en '<section class="consult-item" data-id="Q1"><h3>Decide the export format</h3>'"$RADIO"'</section>'
passes $C c2-inside "an item title that reads as a decision is the item itself"
page c2-decided es '<h2>Decisiones tomadas</h2><p>Todo cerrado.</p>'
passes $C c2-decided "a heading about decisions already taken is not a pending decision"
for h in "Nada por decidir" "Nothing left to decide" "Nothing to decide" "Sin decisiones pendientes" "No pending decisions"; do
  page c2-neg es "<h2>$h</h2><p>Todo cerrado.</p>"
  passes $C c2-neg "a negated heading passes: $h"
done
page c2-word en '<h2>Needs a decisionmaker</h2><p>Who owns it.</p>'
passes $C c2-word "phrases match at word boundaries only"

echo "== mixed-content-types =="
C=mixed-content-types
page c3-codes es '<p>Qué hay: <code>a.py</code>, <code>b.py</code>, <code>c.sh</code> y <code>d.md</code>.</p>'
fails $C c3-codes "a paragraph with four <code> tokens fails"
page c3-three es '<p>Qué hay: <code>--lang</code>, <code>--out</code> y <code>--in</code>.</p>'
passes $C c3-three "three <code> tokens stay under the threshold"
page c3-clauses es '<p>uno; dos; tres; cuatro</p>'
fails $C c3-clauses "four semicolon-separated clauses fail"
page c3-entities es '<p>Acentuaci&oacute;n, canci&oacute;n, cami&oacute;n y le&iacute;do; una sola cl&aacute;usula.</p>'
passes $C c3-entities "character entities are not clauses (BL-324)"
page c3-code-semi es '<p>Corre <code>a; b; c; d</code> una vez.</p>'
passes $C c3-code-semi "semicolons inside <code> are not clauses"
page c3-paths en '<p>It touches skills/a/run.sh, skills/b/check.py and hooks/gate.sh today.</p>'
fails $C c3-paths "a run of three file paths in a sentence fails"
page c3-twopaths en '<p>It touches skills/a/run.sh and nothing else but hooks/gate.sh.</p>'
passes $C c3-twopaths "two paths apart are not a list"
page c3-dates es '<p>Rondas del 12/09, 14/09 y 20/09/2026.</p>'
passes $C c3-dates "dd/mm and dd/mm/yyyy dates are not paths"
page c3-bl es '<p>Siguen room_booking/BL-037, work_hours/BL-170 y maintenance_ops/BL-012.</p>'
passes $C c3-bl "BL-nnn backlog refs are not paths"
page c3-pre en '<pre>The gate reads every page twice. It never writes a file. Each count fails closed.</pre>'
fails $C c3-pre "three prose sentences inside <pre> fail"
page c3-code en '<pre>set -euo pipefail
HERE="$(cd "$(dirname "$0")" &amp;&amp; pwd)"
exec python3 "$HERE/gate.py" "$@"</pre>'
passes $C c3-code "real code inside <pre> passes"

echo "== copy-control-placement =="
C=copy-control-placement
ITEM="<section class=\"consult-item\" data-id=\"Q1\">$RADIO<textarea></textarea></section>"
page c4-ok es "<div class=\"page\"><main class=\"main\">$ITEM$END_OK</main>$RAIL_OK</div>"
passes $C c4-ok "the spec route's placement passes"
page c4-main es "<div class=\"page\"><main class=\"main\">$ITEM$END_OK<div class=\"consult-bar\"><button id=\"consult-copy\">Copiar</button></div></main>
<aside class=\"rail\"><nav id=\"raillist\"></nav></aside></div>"
fails $C c4-main "a rail copy control inside <main> fails"
page c4-loose es "<div class=\"page\"><main class=\"main\">$ITEM$END_OK</main><aside class=\"rail\"></aside></div>
<div class=\"consult-bar\"><button id=\"consult-copy\">Copiar</button></div>"
fails $C c4-loose "a consult-bar outside aside.rail fails"
page c4-twice es "<div class=\"page\"><main class=\"main\">$ITEM$END_OK$END_OK</main>$RAIL_OK</div>"
fails $C c4-twice "two #consult-copy-end fail"
page c4-endout es "<div class=\"page\"><main class=\"main\">$ITEM</main>$END_OK$RAIL_OK</div>"
fails $C c4-endout "#consult-copy-end outside <main> fails"
page c4-hidden es "<div class=\"page\"><main class=\"main\">$ITEM$END_OK</main>${RAIL_OK/<aside class=\"rail\">/<aside class=\"rail\" hidden>}</div>"
fails $C c4-hidden "a rail with the hidden attribute fails"
page c4-none es "<div class=\"page\"><main class=\"main\">$ITEM$END_OK</main>${RAIL_OK/<aside class=\"rail\">/<aside class=\"rail\" style=\"display: none\">}</div>"
fails $C c4-none "a rail with inline display:none fails"
page c4-report es '<main><h1>Informe</h1><p>Sin preguntas.</p></main>'
passes $C c4-report "a report with no consult item needs no copy control"

echo "== ui-string-language =="
C=ui-string-language
page c5-en-on-es es '<button id="consult-copy">Copy my answers</button>'
fails $C c5-en-on-es "\"Copy my answers\" on lang=es fails"
page c5-es-on-en en '<p class="railhead">Contenido</p>'
fails $C c5-es-on-en "a Spanish kit string on lang=en fails"
page c5-ph es '<textarea placeholder="Anything the options do not cover…"></textarea>'
fails $C c5-ph "an English kit placeholder on lang=es fails"
page c5-counter es '<button id="consult-copy">Copy my
   answers <span class="n">3</span></button>'
fails $C c5-counter "a child counter and folded whitespace do not hide the label"
page c5-ok es "<p class=\"fieldlabel\">Notas sobre esto</p><textarea placeholder=\"Lo que las opciones no cubren…\"></textarea>$RAIL_OK"
passes $C c5-ok "the page's own language passes"
page c5-prose es '<p>El botón dice Copy my answers en la versión inglesa.</p>'
passes $C c5-prose "a kit string quoted in prose is not chrome"
page c5-nolang - '<button id="consult-copy">Copiar mis respuestas</button><p class="railhead">Contents</p>'
passes $C c5-nolang "a page with no lang is skipped"
page c5-fr fr '<button id="consult-copy">Copy my answers</button>'
passes $C c5-fr "a lang other than es/en is skipped"

echo "== good.html: every class clean on each class's kit-built page =="
# The one finding shape the current kit is known to produce on an es page: the
# railhead "Contents" (spec_build.py:1342, md_body.py:483, wrap_report.py:489).
# Any OTHER finding on a good page is a FAIL.
KIT_XFAIL_TAG='ui-string-language: kit writes Contents on es'
for dir in "$GOOD"/*/; do
  slug="$(basename "$dir")"
  out="$(python3 "$CD" "$dir/good.html" 2>&1)"; rc=$?
  other="$(printf '%s\n' "$out" | grep '^FAIL' | grep -v '\[ui-string-language\].*"Contents" is en on a lang="es" page')"
  if [[ $rc -eq 0 ]]; then
    ok "$slug/good.html passes all five checks"
  elif [[ -z "$other" ]]; then
    printf '  XFAIL %s (%s/good.html)\n' "$KIT_XFAIL_TAG" "$slug"; XFAIL=$((XFAIL + 1))
  else
    bad "$slug/good.html: $other"
  fi
done
# the class-1 good page must exercise its rule: an options item and an open answer
g1="$GOOD/decision-item-without-options/good.html"
grep -q 'data-free' "$g1" && grep -q 'type="radio"' "$g1" \
  && ok "the class-1 good page carries a data-free item and an options item" \
  || bad "the class-1 good page does not exercise the rule"

echo "== defect-gate.sh =="
CORP="$TMP/corpus"; mkdir -p "$CORP"
printf '{"root": "%s", "pages": [{"path": "c4-ok.html"}, {"path": "c4-main.html"}]}\n' "$TMP" \
  > "$CORP/corpus-sample.json"
gate() { AIDEX_DEFECT_REGISTRY="$1" AIDEX_SPEC_CORPUS="$CORP" bash "$HERE/defect-gate.sh" 2>/dev/null; }

out="$(AIDEX_DEFECT_REGISTRY= AIDEX_SPEC_CORPUS="$CORP" bash "$HERE/defect-gate.sh" 2>/dev/null)"; rc=$?
[[ "$(printf '%s\n' "$out" | head -1)" == "classes: 0/unknown" && $rc -ne 0 ]] \
  && ok "an unset registry reads classes: 0/unknown and fails" || bad "unset registry: rc=$rc $(printf '%q' "$out")"

REG="$TMP/reg"
mkdir -p "$REG/ui-string-language" "$REG/copy-control-placement" "$REG/no-such-class"
cp "$TMP/c5-en-on-es.html" "$REG/ui-string-language/original.html"
cp "$TMP/c4-ok.html" "$REG/ui-string-language/rebuilt.html"
cp "$TMP/c4-ok.html" "$REG/copy-control-placement/original.html"     # not red
cp "$TMP/c4-ok.html" "$REG/no-such-class/original.html"              # no check
out="$(gate "$REG")"; rc=$?
want=$'classes: 2/6\nred: 1/6\ngreen: 1/6\ncorpus: 2/3'
[[ "$out" == "$want" ]] && ok "N is the union of the checks and the registry folders" \
  || bad "gate output was: $(printf '%q' "$out")"
[[ $rc -ne 0 ]] && ok "the gate exits non-zero while a count is short" || bad "gate exited 0 on short counts"

# A full registry: every class red on its original(s), green on its rebuilt.
FULL="$TMP/full"
for pair in "decision-item-without-options c1-free" "decision-page-not-interactive c2-empty" \
            "mixed-content-types c3-codes" "copy-control-placement c4-main" "ui-string-language c5-en-on-es"; do
  set -- $pair; mkdir -p "$FULL/$1"; cp "$TMP/$2.html" "$FULL/$1/original.html"
  cp "$TMP/c4-ok.html" "$FULL/$1/rebuilt.html"
done
cp "$TMP/c1-rec.html" "$FULL/decision-item-without-options/original-2.html"
printf '{"root": "%s", "pages": [{"path": "c4-ok.html"}]}\n' "$TMP" > "$CORP/corpus-sample.json"
out="$(gate "$FULL")"; rc=$?
[[ "$out" == $'classes: 5/5\nred: 5/5\ngreen: 5/5\ncorpus: 6/6' && $rc -eq 0 ]] \
  && ok "the gate exits 0 when every count is full" || bad "full registry: rc=$rc $(printf '%q' "$out")"

cp "$TMP/c4-ok.html" "$FULL/decision-item-without-options/original-2.html"
out="$(gate "$FULL" | sed -n 2p)"
[[ "$out" == "red: 4/5" ]] && ok "a class is red only when every original fails" || bad "second original not red: $out"
cp "$TMP/c1-rec.html" "$FULL/decision-item-without-options/original-2.html"

: > "$FULL/mixed-content-types/rebuilt.html"
out="$(gate "$FULL" | sed -n 3p)"
[[ "$out" == "green: 4/5" ]] && ok "a 0-byte rebuilt.html is never green" || bad "empty rebuilt: $out"
page nomain es '<p>Sin estructura.</p>'
cp "$TMP/nomain.html" "$FULL/mixed-content-types/rebuilt.html"
out="$(gate "$FULL" | sed -n 3p)"
[[ "$out" == "green: 4/5" ]] && ok "a rebuilt.html with no <main> is never green" || bad "no-main rebuilt: $out"
cp "$TMP/c4-ok.html" "$FULL/mixed-content-types/rebuilt.html"

rm -rf "$FULL/ui-string-language"
out="$(gate "$FULL")"; rc=$?
[[ "$(printf '%s\n' "$out" | head -1)" == "classes: 4/5" && $rc -ne 0 ]] \
  && ok "a registry missing a class reads 4/5 and fails" || bad "missing class: rc=$rc $(printf '%q' "$out")"

echo
echo "passed: $PASS  failed: $FAIL  xfail: $XFAIL"
[[ $FAIL -eq 0 ]]
