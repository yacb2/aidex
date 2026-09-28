#!/usr/bin/env bash
# test-contract-defects.sh — unit cells for scripts/dash/contract_defects.py (the
# twelve LOOP-006 source classes) and the shape of defect-gate.sh's output.
#
# Layer: unit, on source. Each class is decided by the script reading markup, so a
# mini-page per verdict is the lowest layer that sees the rule; no browser.
# Each class has pages that must FAIL (the defect's shape) and pages that must
# PASS (the kit's shape, or the declared exemption). The real pages each class
# was frozen on are private and live in the gate's registry, not here; what this
# repo carries is synthetic: these mini-pages and one kit-built good.html per
# class under fixtures/defect-classes/.
#
# Each good.html is built from its good.spec.md by spec_build.py on the current
# kit (style/script bodies emptied, line count kept); any finding on it is a FAIL.
#
# Run with: bash skills/artifact/tests/test-contract-defects.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CD="$HERE/../scripts/dash/contract_defects.py"
GOOD="$HERE/fixtures/defect-classes"

PASS=0 FAIL=0
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
# A finding is exit 1 exactly: a usage error (exit 2, e.g. an unknown --class)
# is not a finding and must not read as one.
fails()  { python3 "$CD" --class "$1" "$TMP/$2.html" >/dev/null 2>&1; [[ $? -eq 1 ]] && ok "$3" || bad "$3"; }
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
# A gallery SAMPLE asks nothing (BL-466): composer.js counts no gallery row
# without an .opts group, so neither does the class. A gallery row WITH an .opts
# group is a question like any other and still needs two options.
FIG='<div class="gal"><figure data-tile="after"><img src="a.png" alt="a"></figure></div>'
page c1-sample es "<section class=\"consult-item consult-gallery\" data-id=\"audit-x-sample\">$FIG<textarea></textarea></section>"
passes $C c1-sample "a gallery sample row (no .opts, BL-466) is not a question"
page c1-sample-tile es "<section class=\"consult-item\" data-id=\"audit-y-sample\"><figure data-tile=\"after\"><img src=\"a.png\" alt=\"a\"></figure><textarea></textarea></section>"
passes $C c1-sample-tile "a row that is a gallery row by its figure[data-tile] alone is judged the same"
page c1-gal-one es "<section class=\"consult-item consult-gallery\" data-id=\"audit-z\">$FIG$ONE_RADIO<textarea></textarea></section>"
fails $C c1-gal-one "a gallery pair row with one radio still fails"
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

echo "== decided-item-without-verdict =="
C=decided-item-without-verdict
CHECKED_RADIO='<div class="opts one"><label><input type="radio" name="Q1" data-label="Sí" checked>Sí</label>
<label><input type="radio" name="Q1" data-label="No">No</label></div>'
page c6-bare es "<section class=\"consult-item\" data-id=\"Q1\" data-title=\"¿Cerramos?\" data-decided>$RADIO<p>Decidido: sí.</p></section>"
fails $C c6-bare "a bare data-decided with nothing checked fails, even with the verdict in prose"
page c6-empty es '<section class="consult-item" data-id="Q1" data-decided="  "><textarea></textarea></section>'
fails $C c6-empty "a whitespace-only data-decided value is no verdict"
page c6-value es '<section class="consult-item" data-id="Q1" data-decided="Sí, en dos pasos"><textarea></textarea></section>'
passes $C c6-value "a non-empty data-decided value is the verdict"
page c6-checked es "<section class=\"consult-item\" data-id=\"Q1\" data-decided>$CHECKED_RADIO</section>"
passes $C c6-checked "a checked option is the verdict"
page c6-select es '<section class="consult-item" data-id="Q1" data-decided><select><option>Sí</option><option selected>No</option></select></section>'
passes $C c6-select "an explicitly selected option is the verdict"
page c6-select-default es '<section class="consult-item" data-id="Q1" data-decided><select><option>Sí</option><option>No</option></select></section>'
fails $C c6-select-default "a select with no explicit selected option is no verdict"
page c6-nested es "<section class=\"consult-item\" data-id=\"Q1\" data-decided><textarea></textarea>
<section class=\"consult-item\" data-id=\"Q1a\">$CHECKED_RADIO</section></section>"
passes $C c6-nested "a nested item's checked option shows in the outer fold (composer.js walks the whole subtree)"
page c6-placeholder es '<section class="consult-item" data-id="Q1" data-decided><select><option value="" selected>Elige…</option><option>Sí</option></select></section>'
fails $C c6-placeholder "a selected placeholder option with an empty value is no verdict"
for v in yes TRUE 1; do
  page c6-yes es "<section class=\"consult-item\" data-id=\"Q1\" data-decided=\"$v\">$RADIO</section>"
  fails $C c6-yes "data-decided=\"$v\" is no verdict: the fold would show a bare \"$v\""
done
page c6-round es "<section class=\"consult-item\" data-id=\"Q1\" data-decided-round=\"2\">$RADIO</section>"
passes $C c6-round "data-decided-round alone is not a decided item"

echo "== item-title-repeats-id =="
C=item-title-repeats-id
for t in "M1 · Matriz de estados" "M1: Matriz" "M1 - Matriz" "M1 — Matriz" "M1" "M1 Matriz"; do
  page c7-rep es "<section class=\"consult-item\" data-id=\"M1\" data-title=\"$t\">$RADIO</section>"
  fails $C c7-rep "a title that repeats its id fails: $t"
done
page c7-ok es "<section class=\"consult-item\" data-id=\"M1\" data-title=\"Matriz de estados\">$RADIO</section>"
passes $C c7-ok "a title without the id passes"
page c7-longer es "<section class=\"consult-item\" data-id=\"M1\" data-title=\"M10 sustituye a la matriz\">$RADIO</section>"
passes $C c7-longer "a title starting with a longer token (M10 vs M1) is not the id"
page c7-mid es "<section class=\"consult-item\" data-id=\"M1\" data-title=\"Qué cambia en M1\">$RADIO</section>"
passes $C c7-mid "the id later in the title is fine"
page c7-case es "<section class=\"consult-item\" data-id=\"M1\" data-title=\"m1 · Matriz\">$RADIO</section>"
fails $C c7-case "the id is matched case-insensitively"
page c7-dot es "<section class=\"consult-item\" data-id=\"M1\" data-title=\"M1. Matriz\">$RADIO</section>"
fails $C c7-dot "a period that is not followed by a digit is a separator"
page c7-sub es "<section class=\"consult-item\" data-id=\"M1\" data-title=\"M1.2 sustituye a la matriz\">$RADIO</section>"
passes $C c7-sub "M1.2 is a different token from M1"

echo "== lang-follows-profile =="
C=lang-follows-profile
PROJ="$TMP/proj"
mkdir -p "$PROJ/.context/reports" "$PROJ/.context/worklists/_archive" "$PROJ/.context/proofs"
printf '# Artifact style\n\nProse naming language: en in passing.\n\n## Language\n\n- language: es\n' > "$PROJ/.context/artifact-style.md"
page proj/.context/reports/en en '<main><p>Report.</p></main>'
fails $C proj/.context/reports/en "lang=en under a language: es profile fails"
page proj/.context/reports/nolang - '<main><p>Informe.</p></main>'
fails $C proj/.context/reports/nolang "no lang under a language: es profile fails"
page proj/.context/worklists/_archive/sweep-report en '<main><p>Close-out.</p></main>'
fails $C proj/.context/worklists/_archive/sweep-report "a worklists/_archive close-out report is not exempt"
page proj/.context/reports/es es '<main><p>Informe.</p></main>'
passes $C proj/.context/reports/es "lang=es under a language: es profile passes"
page proj/.context/reports/es-419 es-419 '<main><p>Informe.</p></main>'
passes $C proj/.context/reports/es-419 "a regional subtag of the profile language passes"
page proj/.context/proofs/human-verification en '<main><p>Record.</p></main>'
passes $C proj/.context/proofs/human-verification "human-verification.* stays exempt (owner question)"
page noprof en '<main><p>Report.</p></main>'
passes $C noprof "a page with no project profile is not judged"

echo "== decided-section-anchor =="
C=decided-section-anchor
DECIDED='<section class="consult-item" data-id="Q1" data-decided="Sí"><textarea></textarea></section>'
page c9-bare es "<main class=\"main\"><h1>Ronda 2</h1>$DECIDED</main>"
fails $C c9-bare "decided items with no header and no #sec-ledger fail"
page c9-deep es "<main class=\"main\"><section><header><h1>Ronda 2</h1></header></section>$DECIDED</main>"
fails $C c9-deep "a header that is not a direct child of .main is not the anchor"
page c9-header es "<main class=\"main\"><header class=\"masthead\"><h1>Ronda 2</h1></header>$DECIDED</main>"
passes $C c9-header "a header directly under .main is the anchor"
page c9-ledger es "<main class=\"main\"><h1>Ronda 2</h1><section id=\"sec-ledger\"></section>$DECIDED</main>"
passes $C c9-ledger "#sec-ledger is the anchor"
page c9-open es "<main class=\"main\"><h1>Ronda 1</h1><section class=\"consult-item\" data-id=\"Q1\">$RADIO</section></main>"
passes $C c9-open "a page with no decided item needs no anchor"
page c9-half es "<main class=\"main\"><h1>Ronda 2</h1><section class=\"consult-group\" id=\"G1\"><h2>Bloque</h2>
$DECIDED<section class=\"consult-item\" data-id=\"Q2\">$RADIO</section></section></main>"
passes $C c9-half "a decided item in a half-open group folds in place and needs no anchor"
page c9-group es "<main class=\"main\"><h1>Ronda 2</h1><section class=\"consult-group\" id=\"G1\"><h2>Bloque</h2>
$DECIDED<section class=\"consult-item\" data-id=\"Q2\" data-decided=\"No\"></section></section></main>"
fails $C c9-group "a fully decided group with no anchor fails"

echo "== img-src-portable =="
C=img-src-portable
for src in "file:///projects/x/shot.png" "FILE:/x.png" "/projects/x/shot.png" "C:/shots/x.png" 'C:\shots\x.png'; do
  page c10-bad es "<main><img src=\"$src\" alt=\"x\"></main>"
  fails $C c10-bad "a non-portable img src fails: $src"
done
for src in "shots/x.png" "./x.png" "../x.png" "data:image/png;base64,AAAA" "https://example.org/x.png" "//cdn.example.org/x.png"; do
  page c10-ok es "<main><img src=\"$src\" alt=\"x\"></main>"
  passes $C c10-ok "a portable img src passes: $src"
done
page c10-unc es '<main><img src="\\server\share\x.png" alt="x"></main>'
fails $C c10-unc "a UNC path fails"
page c10-srcset es '<main><img src="a.png" srcset="a.png 1x, file:///x/b.png 2x" alt="x"></main>'
fails $C c10-srcset "a file: candidate in srcset fails"
page c10-srcset-abs es '<main><img src="a.png" srcset="/abs/b.png 2x" alt="x"></main>'
fails $C c10-srcset-abs "an absolute path in srcset fails"
page c10-srcset-ok es '<main><img src="a.png" srcset="a.png 1x, shots/b.png 2x" alt="x"></main>'
passes $C c10-srcset-ok "relative srcset candidates pass"

echo "== unique-dom-ids =="
C=unique-dom-ids
page c11-dup es '<main><section id="a"></section><section id="a"></section></main>'
fails $C c11-dup "two elements with one id fail"
page c11-svg es '<main><svg><defs><marker id="mk-1"></marker></defs></svg><svg><defs><marker id="mk-1"></marker></defs></svg></main>'
fails $C c11-svg "a marker id repeated across two inline SVGs fails"
page c11-ok es '<main><section id="a"></section><section id="b"><svg><marker id="mk-1"></marker></svg></section></main>'
passes $C c11-ok "distinct ids pass"
page c11-empty es '<main><p id="">a</p><p id="">b</p></main>'
passes $C c11-empty "empty ids are not ids"

echo "== group-item-id-collision =="
C=group-item-id-collision
page c12-id es "<section class=\"consult-group\" id=\"W1\"><h2>Bloque</h2><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section>"
fails $C c12-id "a group id equal to an item data-id fails"
page c12-dataid es "<section class=\"consult-group\" data-id=\"W1\"><h2>Bloque</h2></section><section class=\"consult-item\" data-id=\"W1\">$RADIO</section>"
passes $C c12-dataid "a data-id-only group outside any container section gets no id at run time, so it cannot collide"
# composer.js groupEntry claims a data-id-only group's data-id as its id when the
# group sits inside a container section (.main > section[id]); it runs before the
# group's items, so the item is the one that yields to <id>-2.
page c12-nested es "<main class=\"main\"><section id=\"S1\"><h2>Contenedor</h2><section class=\"consult-group\" data-id=\"W1\"><h3>Bloque</h3><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section></section></main>"
fails $C c12-nested "a data-id-only group inside a container section takes that id at run time and collides"
page c12-nested-id es "<main class=\"main\"><section id=\"S1\"><h2>Contenedor</h2><section class=\"consult-group\" id=\"G1\" data-id=\"W1\"><h3>Bloque</h3><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section></section></main>"
passes $C c12-nested-id "a nested group with its own id keeps it, so its data-id cannot collide"
page c12-nested-noid es "<main class=\"main\"><section><h2>Sin id</h2><section class=\"consult-group\" data-id=\"W1\"><h3>Bloque</h3><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section></section></main>"
passes $C c12-nested-noid "a container section with no id is not indexed, so its group gets no id"
# Mirrors kit 27 exactly (composer.js:504-515): a container without an h2 is not
# walked, a group the composer moves into the decided section gets no entry, and
# an item that claimed the id before the group reached it keeps it.
page c12-nested-noh2 es "<main class=\"main\"><section id=\"S1\"><section class=\"consult-group\" data-id=\"W1\"><h3>Bloque</h3><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section></section></main>"
passes $C c12-nested-noh2 "a container section with no h2 is not walked, so its group gets no id"
page c12-nested-after es "<main class=\"main\"><section class=\"consult-group\" id=\"G0\"><h2>Antes</h2><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section><section id=\"S1\"><h2>Contenedor</h2><section class=\"consult-group\" data-id=\"W1\"><h3>Bloque</h3><section class=\"consult-item\" data-id=\"Q2\">$RADIO</section></section></section></main>"
passes $C c12-nested-after "an item that claimed the id before the nested group keeps it; the group yields"
page c12-nested-decided es "<main class=\"main\"><section id=\"S1\"><h2>Contenedor</h2><section class=\"consult-group\" data-id=\"W1\"><h3>Bloque</h3><section class=\"consult-item\" data-id=\"W1\" data-decided=\"Sí\">$RADIO</section></section></section></main>"
passes $C c12-nested-decided "a nested group whose every item is decided moves to the decided section and gets no id"
page c12-ok es "<section class=\"consult-group\" id=\"G1\" data-id=\"G1\"><h2>Bloque</h2><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section>"
passes $C c12-ok "distinct group and item ids pass"
page c12-eff es "<section class=\"consult-group\" id=\"G1\" data-id=\"W1\"><h2>Bloque</h2><section class=\"consult-item\" data-id=\"W1\">$RADIO</section></section>"
passes $C c12-eff "a group with an id is keyed by that id, not its data-id (composer.js:487)"
page c12-items es "<section class=\"consult-item\" data-id=\"Q1\">$RADIO</section><section class=\"consult-item\" data-id=\"Q1\">$RADIO</section>"
passes $C c12-items "two items sharing a data-id are check-artifact's duplicate-ids finding, not this class's"
page c12-other es "<div id=\"Q1\">Contexto</div><section class=\"consult-item\" data-id=\"Q1\">$RADIO</section>"
fails $C c12-other "an item data-id equal to another element's id fails"
page c12-self es "<section class=\"consult-item\" id=\"Q1\" data-id=\"Q1\">$RADIO</section>"
passes $C c12-self "an item's own id equal to its data-id is not a collision"

echo "== KIT_STRINGS lockstep: every kit chrome string is in contract_defects =="
# ui-string-language judges a page by KIT_STRINGS, a copy kept in the module on
# purpose. A string added to the kit's chrome and not to that copy is a label the
# class can no longer see in the wrong language. Sources: composer.js's CHROME
# keys (the labels it relabels) in STRINGS.en/.es, spec_build.STRINGS,
# gallery_items' notes box and md_body.CHROME (the chrome the wrap localises),
# which must also carry exactly composer.js's value for each of its keys.
missing="$(python3 - "$HERE/.." <<'PY'
import os, re, sys
root = sys.argv[1]
sys.path[:0] = [os.path.join(root, "scripts"), os.path.join(root, "scripts", "dash")]
import contract_defects, gallery_items, md_body, spec_build
js = open(os.path.join(root, "assets", "artifact-kit", "composer.js"), encoding="utf-8").read()
keys = re.findall(r"\[\s*'[^']*',\s*'(?:text|placeholder)',\s*'(\w+)'\s*\]", js)
body = js[js.index("var STRINGS = {"):]
want = []
for lang in ("en", "es"):
    block = re.search(r"\n    %s: \{(.*?)\n    \}" % lang, body, re.S).group(1)
    for k in keys:
        m = re.search(r"\n\s*%s: '((?:[^'\\]|\\.)*)'" % k, block)
        want.append((lang, "composer.js %s.%s" % (lang, k), m.group(1) if m else None))
        mine = md_body.CHROME.get(k, {}).get(lang)
        if m and mine != re.sub(r"\\u([0-9a-fA-F]{4})", lambda u: chr(int(u.group(1), 16)), m.group(1)):
            print("md_body CHROME.%s.%s = %r differs from composer.js" % (k, lang, mine))
for lang, table in spec_build.STRINGS.items():
    want += [(lang, "spec_build %s.%s" % (lang, k), v) for k, v in table.items()]
want += [(lang, "md_body CHROME.%s.%s" % (k, lang), v)
         for k, t in md_body.CHROME.items() for lang, v in t.items()]
for name in ("NOTES_LABEL", "NOTES_PLACEHOLDER"):
    want += [(lang, "gallery_items %s.%s" % (name, lang), v)
             for lang, v in getattr(gallery_items, name).items()]
unesc = lambda v: re.sub(r"\\u([0-9a-fA-F]{4})", lambda m: chr(int(m.group(1), 16)), v).replace("\\'", "'")
if len(keys) < 10:
    print("composer.js CHROME table read %d keys, expected 10+" % len(keys))
for lang, where, v in want:
    if v is None:
        print("%s: not found" % where)
    elif unesc(v) not in contract_defects.KIT_STRINGS[lang]:
        print("%s = %r is not in KIT_STRINGS[%r]" % (where, unesc(v), lang))
PY
)"; rc=$?
[[ $rc -eq 0 && -z "$missing" ]] && ok "every kit chrome string is in KIT_STRINGS" \
  || bad "KIT_STRINGS out of lockstep (rc=$rc): $missing"

echo "== good.html: every class clean on each class's kit-built page =="
for dir in "$GOOD"/*/; do
  slug="$(basename "$dir")"
  out="$(python3 "$CD" "$dir/good.html" 2>&1)"; rc=$?
  [[ $rc -eq 0 ]] && ok "$slug/good.html passes every source check" \
    || bad "$slug/good.html (rc=$rc): $(printf '%s\n' "$out" | grep '^FAIL')"
done
# the class-1 good page must exercise its rule: an options item and an open answer
g1="$GOOD/decision-item-without-options/good.html"
grep -q 'data-free' "$g1" && grep -q 'type="radio"' "$g1" \
  && ok "the class-1 good page carries a data-free item and an options item" \
  || bad "the class-1 good page does not exercise the rule"

echo "== check-artifact carries every finding as a blocking FAIL =="
# Layer: the CLI, because the wiring is the contract: check_artifact.check_file
# calls contract_defects instead of keeping copies, so on every mini-page above
# each (class, line) finding must come out of check-artifact as its own FAIL
# line — none dropped, none invented — and a page with one exits 1.
wiring="$(python3 - "$HERE/../scripts" "$TMP" <<'PY'
import os, re, subprocess, sys
scripts, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(scripts, "dash"))
import contract_defects as cd
pages = sorted(os.path.join(d, f) for d, _, fs in os.walk(tmp)   # .context too
               for f in fs if f.endswith(".html"))
classes, bad = set(), []
for p in pages:
    want = sorted((s, l) for s, l, _ in cd.findings(p))
    r = subprocess.run(["bash", os.path.join(scripts, "check-artifact.sh"), p],
                       capture_output=True, text=True)
    got = sorted((m.group(1), int(m.group(2))) for m in re.finditer(
        r"^  FAIL \[([\w-]+)\] [^:]+: line (\d+): ", r.stdout, re.M)
        if m.group(1) in cd.CHECKS)
    if got != want or (want and r.returncode != 1):
        bad.append("%s: rc=%d want %s got %s" % (os.path.basename(p), r.returncode, want, got))
    classes.update(s for s, _ in want)
missing = sorted(set(cd.CHECKS) - classes)
print("pages=%d classes=%d" % (len(pages), len(classes)))
for line in bad + (["no mini-page fails " + ", ".join(missing)] if missing else []):
    print(line)
PY
)"
if [[ "$(printf '%s\n' "$wiring" | wc -l | tr -d ' ')" == "1" ]]; then
  ok "check-artifact FAILs exactly the contract_defects findings ($wiring)"
else
  bad "check-artifact and contract_defects disagree: $wiring"
fi

echo "== census: the contract classes warn, the page being written fails =="
# Ruling 2026-09-28: a page nobody is editing was built by an older kit and is red
# by construction, so --census reports the classes as WARN (CENSUS_ADVISORY) and
# exits 0 on them; check-artifact on the named page stays blocking (cell above).
CEN="$TMP/census-root"; mkdir -p "$CEN/.context/reports"
cp "$TMP/c1-free.html" "$CEN/.context/reports/old.html"
cout="$(python3 "$HERE/../scripts/dash/check_artifact.py" --census "$CEN" 2>&1)"; crc=$?
printf '%s\n' "$cout" | grep -q 'WARN \[decision-item-without-options\] ' \
  && ! printf '%s\n' "$cout" | grep -q 'FAIL \[decision-item-without-options\]' \
  && ok "the census warns a contract finding instead of failing it" \
  || bad "the census did not demote the contract class to a warning: $cout"

echo "== lang-follows-profile at build time: only human-verification.* keeps --lang en =="
# Owner ruling (LOOP-006 Phase C): an explicit --lang that contradicts the
# profile is refused on every page but human-verification.*, the one page English
# by D-04 (the class exempts it by name). A close-out record under
# worklists/_archive/ follows the profile (BL-382, BL-482): no flag switches the
# check off at wrap time.
LP="$TMP/langproj"; mkdir -p "$LP/.context/reports" "$LP/.context/worklists/_archive"
printf -- '- language: es\n' > "$LP/.context/artifact-style.md"
EN_BODY='<div class="page"><main class="main"><h1>Report</h1><p>An English report on purpose, with enough words to read as English prose for the checker.</p></main></div>'
printf '%s\n' "$EN_BODY" | bash "$HERE/../scripts/wrap-report.sh" --title "English" --lang en \
  --out "$LP/.context/reports/en.html" >"$TMP/wrap.out" 2>&1; wrc=$?
[[ $wrc -ne 0 ]] && grep -q 'FAIL \[lang-follows-profile\]' "$TMP/wrap.out" \
  && ok "--lang en on a page under a language: es profile is refused" \
  || bad "a normal page kept --lang against the profile (rc=$wrc): $(cat "$TMP/wrap.out")"
REC="$LP/.context/worklists/_archive/sweep-report.html"
printf '%s\n' "$EN_BODY" | bash "$HERE/../scripts/wrap-report.sh" --title "English" --lang en \
  --out "$REC" >"$TMP/wrap.out" 2>&1; wrc=$?
[[ $wrc -ne 0 && ! -f "$REC" ]] && grep -q 'FAIL \[lang-follows-profile\]' "$TMP/wrap.out" \
  && ok "a close-out record under worklists/_archive/ with --lang en is refused" \
  || bad "the close-out record kept --lang en against the profile (rc=$wrc): $(cat "$TMP/wrap.out")"
HV="$LP/.context/reports/human-verification.html"
printf '%s\n' "$EN_BODY" | bash "$HERE/../scripts/wrap-report.sh" --title "English" --lang en \
  --out "$HV" >"$TMP/wrap.out" 2>&1; wrc=$?
[[ $wrc -eq 0 ]] && ! grep -q 'lang-follows-profile\|NOTE: --lang' "$TMP/wrap.out" \
  && ok "human-verification.* keeps its --lang en, with no note" \
  || bad "human-verification's --lang en was refused or noted (rc=$wrc): $(cat "$TMP/wrap.out")"
# A silent spec follows the profile; an explicit --lang es that contradicts it
# must still meet lang-follows-profile on the spec route.
SP="$TMP/specproj"; mkdir -p "$SP/.context/reports"
printf -- '- language: en\n' > "$SP/.context/artifact-style.md"
printf '::: masthead {eyebrow="Prueba" byline="aidex"}\n# Una página\n\nUna página escrita en español, con suficientes palabras para leerse como prosa.\n:::\n\nEl cuerpo sigue en español.\n' > "$SP/p.spec.md"
python3 "$HERE/../scripts/spec_build.py" "$SP/p.spec.md" --lang es -o "$SP/.context/reports/p.html" >"$TMP/sb.out" 2>&1; src=$?
[[ $src -ne 0 ]] && grep -q 'FAIL \[lang-follows-profile\]' "$TMP/sb.out" \
  && ok "a spec build whose lang contradicts the profile fails lang-follows-profile" \
  || bad "the spec build skipped lang-follows-profile (rc=$src): $(cat "$TMP/sb.out")"

echo "== defect-gate.sh =="
# The render classes and the corpus's render-probe run go through
# AIDEX_RENDER_PROBE, so these cells drive the gate with fake probes and never
# launch a browser. Contract (defect_gate.py): red = exit 1 AND a stdout line
# `CONTRACT <slug> findings=<n>` with n >= 1; green = exit 0 AND findings=0;
# anything else, a timeout included, is neither.
fake() {   # fake NAME BODY -> $TMP/NAME.sh
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TMP/$1.sh"
}
# red on original*.html, green on anything else, clean without --contract
fake probe-ok '[[ "$1" == --contract ]] || exit 0
case "$(basename "$3")" in original*) echo "CONTRACT $2 findings=1"; exit 1;; esac
echo "CONTRACT $2 findings=0"; exit 0'
fake probe-nomarker '[[ "$1" == --contract ]] || exit 0
exit 1'
fake probe-silent0 'exit 0'
fake probe-dirty '[[ "$1" == --contract ]] || exit 0
echo "CONTRACT $2 findings=2"; exit 1'
# clean on every answer, but only after 5 s: a timeout must turn that into an error
fake probe-slow 'sleep 5; [[ "$1" == --contract ]] && echo "CONTRACT $2 findings=0"; exit 0'

# One contract-valid page, built by the kit: clean on every source check and on
# check-artifact. English, so it is judged under an en profile or none.
printf 'A short report with one paragraph.\n\n## Findings\n\nNothing to decide here.\n' > "$TMP/clean.md"
bash "$HERE/../scripts/wrap-report.sh" --title "Clean page" --lang en --in "$TMP/clean.md" \
  --out "$TMP/clean.html" >/dev/null 2>&1 || bad "wrap-report could not build the clean page"

# The corpus line judges each corpus spec BUILT on the current kit, never the
# original page (STATE :71: old-kit pages stay red by construction). A corpus
# here is a corpus-sample.json plus corpus-specs/<project>__<page>.spec.md.
SPECS="$TMP/specs"; mkdir -p "$SPECS"
printf '::: masthead {eyebrow="Test" lang=en}\n# Clean page\n\nA short report with one paragraph.\n:::\n\n## Findings\n\nNothing to decide here.\n' \
  > "$SPECS/clean.spec.md"
# The builder refuses it: an item outside any group, and no notes item.
printf '::: masthead {eyebrow="Test" lang=en}\n# Loose item\n\nOne question with no block around it.\n:::\n\n::: item {#q1 title="Pick one"}\nWhich?\n\n- **A.** This\n- **B.** That\n:::\n' \
  > "$SPECS/refused.spec.md"
CORP="$TMP/corpus"
corpus() {   # corpus [PROJ/]SPEC... -> rows PROJ/<SPEC>.html, specs PROJ__<SPEC>.spec.md (PROJ: cproj)
  local rows="" s p; rm -rf "$CORP"; mkdir -p "$CORP/corpus-specs"
  for s in "$@"; do
    p=cproj; [[ "$s" == */* ]] && { p="${s%%/*}"; s="${s#*/}"; }
    rows+="${rows:+, }{\"path\": \"$p/$s.html\"}"
    [[ -f "$SPECS/$s.spec.md" ]] && cp "$SPECS/$s.spec.md" "$CORP/corpus-specs/${p}__$s.spec.md"
  done
  printf '{"root": "%s", "pages": [%s]}\n' "$TMP" "$rows" > "$CORP/corpus-sample.json"
}
gate() {   # gate REGISTRY [PROBE] — stdout only
  AIDEX_RENDER_PROBE="$TMP/${2:-probe-ok}.sh" AIDEX_DEFECT_REGISTRY="$1" \
    AIDEX_SPEC_CORPUS="$CORP" bash "$HERE/defect-gate.sh" 2>/dev/null
}

corpus clean
out="$(gate "")"; rc=$?
[[ "$(printf '%s\n' "$out" | head -1)" == "classes: 0/unknown" && $rc -ne 0 ]] \
  && ok "an unset registry reads classes: 0/unknown and fails" || bad "unset registry: rc=$rc $(printf '%q' "$out")"

echo "-- the corpus line: specs built on the current kit, full by default, source only on request"
[[ "$(gate "" | tail -1)" == "corpus: 1/1" ]] \
  && ok "a spec that builds clean on every gate is clean by default" || bad "clean spec: $(gate "" | tail -1)"
mkdir -p "$TMP/cproj"; cp "$TMP/c4-ok.html" "$TMP/cproj/clean.html"    # a dirty ORIGINAL at the sampled path
[[ "$(gate "" | tail -1)" == "corpus: 1/1" ]] \
  && ok "the gate judges the built spec, not the original page" || bad "read the original: $(gate "" | tail -1)"
rm -rf "$TMP/cproj"
[[ "$(gate "" probe-dirty | tail -1)" == "corpus: 0/1" ]] \
  && ok "the default holds a built page to every render class" || bad "dirty render: $(gate "" probe-dirty | tail -1)"
[[ "$(AIDEX_CORPUS_FAST=1 gate "" probe-dirty | tail -1)" == "corpus: 1/1 (source only)" ]] \
  && ok "AIDEX_CORPUS_FAST=1 reads source checks only and says so" || bad "fast: $(AIDEX_CORPUS_FAST=1 gate "" probe-dirty | tail -1)"
err="$(AIDEX_PROBE_TIMEOUT=1 AIDEX_RENDER_PROBE="$TMP/probe-slow.sh" AIDEX_DEFECT_REGISTRY= \
  AIDEX_SPEC_CORPUS="$CORP" bash "$HERE/defect-gate.sh" --verbose 2>&1)"
grep -q "^corpus: 0/1$" <<<"$err" && grep -q "cproj__clean.spec.md: render-probe timeout" <<<"$err" \
  && ok "a probe past its timeout is an error, not clean — and the probe is what timed out" \
  || bad "slow probe: $(printf '%q' "$err")"
# The page is built in a tree mirroring its project's profile, so that profile judges it: an
# en page in an es-profile project is refused by the wrap (lang-follows-profile).
mkdir -p "$TMP/esproj/.context"; printf -- '- language: es\n' > "$TMP/esproj/.context/artifact-style.md"
corpus esproj/clean
err="$(AIDEX_RENDER_PROBE="$TMP/probe-ok.sh" AIDEX_DEFECT_REGISTRY= AIDEX_SPEC_CORPUS="$CORP" \
  bash "$HERE/defect-gate.sh" --verbose 2>&1)"
grep -q "^corpus: 0/1$" <<<"$err" && grep -q "esproj__clean.spec.md: build refused: FAIL \[lang-follows-profile\]" <<<"$err" \
  && ok "a spec is built under a copy of its project's profile: that profile judges its lang" \
  || bad "profile not seen: $(printf '%q' "$err")"
[[ "$(ls -A "$TMP/esproj/.context")" == "artifact-style.md" ]] \
  && ok "a run writes nothing into the project's .context/" || bad "project written: $(ls -A "$TMP/esproj/.context")"
corpus clean
corpus refused
[[ "$(gate "" | tail -1)" == "corpus: 0/1" && "$(AIDEX_CORPUS_FAST=1 gate "" | tail -1)" == "corpus: 0/1 (source only)" ]] \
  && ok "a spec the builder refuses is a failing page, full and fast alike" || bad "refused: $(gate "" | tail -1)"
err="$(AIDEX_RENDER_PROBE="$TMP/probe-ok.sh" AIDEX_DEFECT_REGISTRY= AIDEX_SPEC_CORPUS="$CORP" \
  bash "$HERE/defect-gate.sh" --verbose 2>&1 >/dev/null)"
grep -q "cproj__refused.spec.md: build refused: FAIL \[consult-shape\]" <<<"$err" \
  && ok "--verbose names the refused spec and the builder's first reason" || bad "verbose refusal: $(printf '%q' "$err")"
corpus clean nospec
[[ "$(gate "" | tail -1)" == "corpus: 1/2" ]] \
  && ok "a sampled page with no spec counts in T and is not clean" || bad "no spec: $(gate "" | tail -1)"
err="$(AIDEX_RENDER_PROBE="$TMP/probe-dirty.sh" AIDEX_DEFECT_REGISTRY= AIDEX_SPEC_CORPUS="$CORP" \
  bash "$HERE/defect-gate.sh" --verbose 2>&1 >/dev/null)"
grep -q "cproj__nospec.spec.md: no spec" <<<"$err" && grep -q "cproj__clean.spec.md: text-style-drift (finding)" <<<"$err" \
  && ok "--verbose names a missing spec, and the render class a built page failed" || bad "verbose: $(printf '%q' "$err")"

# A rebuilt.html is judged as it sits, check-artifact included (the fast path skips it).
RB="$TMP/rbreg"; mkdir -p "$RB/ui-string-language"
cp "$TMP/c5-en-on-es.html" "$RB/ui-string-language/original.html"
cp "$TMP/c4-ok.html" "$RB/ui-string-language/rebuilt.html"
corpus
[[ "$(gate "$RB" | tail -1)" == "corpus: 0/1" && "$(AIDEX_CORPUS_FAST=1 gate "$RB" | tail -1)" == "corpus: 1/1 (source only)" ]] \
  && ok "a rebuilt page gets check-artifact by default; the fast path skips it" || bad "rebuilt c4-ok default/fast"
err="$(AIDEX_RENDER_PROBE="$TMP/probe-ok.sh" AIDEX_DEFECT_REGISTRY="$RB" AIDEX_SPEC_CORPUS="$CORP" \
  bash "$HERE/defect-gate.sh" --verbose 2>&1 >/dev/null)"
grep -q "rebuilt.html: check-artifact rc=1" <<<"$err" \
  && ok "--verbose names the gate a rebuilt page failed (check-artifact rc=1)" || bad "verbose rebuilt: $(printf '%q' "$err")"

echo "-- the registry"
REG="$TMP/reg"
mkdir -p "$REG/ui-string-language" "$REG/copy-control-placement" "$REG/no-such-class"
cp "$TMP/c5-en-on-es.html" "$REG/ui-string-language/original.html"
cp "$TMP/clean.html" "$REG/ui-string-language/rebuilt.html"
cp "$TMP/c4-ok.html" "$REG/copy-control-placement/original.html"     # not red
cp "$TMP/c4-ok.html" "$REG/no-such-class/original.html"              # no check
corpus clean refused
out="$(gate "$REG")"; rc=$?
# N = 12 source checks + 3 render classes + 1 folder with no check
want=$'classes: 2/16\nred: 1/16\ngreen: 1/16\ncorpus: 2/3'
[[ "$out" == "$want" ]] && ok "N is the union of the source checks, the render classes and the registry folders" \
  || bad "gate output was: $(printf '%q' "$out")"
[[ $rc -ne 0 ]] && ok "the gate exits non-zero while a count is short" || bad "gate exited 0 on short counts"

# A full registry under an en-profile project (lang-follows-profile judges a
# page by where it sits): every source class red on a mini-page, every render
# class red by the fake probe, every class green on the kit-built clean page.
EN="$TMP/enproj"; mkdir -p "$EN/.context"
printf '## Language\n\n- language: en\n' > "$EN/.context/artifact-style.md"
FULL="$EN/registry"
for pair in "decision-item-without-options c1-free" "decision-page-not-interactive c2-empty" \
            "mixed-content-types c3-codes" "copy-control-placement c4-main" "ui-string-language c5-en-on-es" \
            "decided-item-without-verdict c6-bare" "item-title-repeats-id c7-rep" \
            "lang-follows-profile proj/.context/reports/es" "decided-section-anchor c9-bare" \
            "img-src-portable c10-bad" "unique-dom-ids c11-dup" "group-item-id-collision c12-id" \
            "text-style-drift clean" "figure-text-contrast clean" "svg-label-outside-its-box clean"; do
  set -- $pair; mkdir -p "$FULL/$1"; cp "$TMP/$2.html" "$FULL/$1/original.html"
  cp "$TMP/clean.html" "$FULL/$1/rebuilt.html"
done
cp "$TMP/c1-rec.html" "$FULL/decision-item-without-options/original-2.html"
corpus clean
out="$(gate "$FULL")"; rc=$?
[[ "$out" == $'classes: 15/15\nred: 15/15\ngreen: 15/15\ncorpus: 16/16' && $rc -eq 0 ]] \
  && ok "the gate exits 0 when every count is full" || bad "full registry: rc=$rc $(printf '%q' "$out")"

out="$(gate "$FULL" probe-nomarker)"
[[ "$(sed -n 2p <<<"$out")" == "red: 12/15" ]] \
  && ok "a probe exiting 1 without its CONTRACT line is not red" || bad "no marker: $(printf '%q' "$out")"
out="$(gate "$FULL" probe-silent0)"
[[ "$(sed -n 3p <<<"$out")" == "green: 12/15" ]] \
  && ok "a probe exiting 0 without its CONTRACT line is not green" || bad "silent 0: $(printf '%q' "$out")"

cp "$TMP/c4-ok.html" "$FULL/decision-item-without-options/original-2.html"
out="$(gate "$FULL" | sed -n 2p)"
[[ "$out" == "red: 14/15" ]] && ok "a class is red only when every original fails" || bad "second original not red: $out"
cp "$TMP/c1-rec.html" "$FULL/decision-item-without-options/original-2.html"

: > "$FULL/mixed-content-types/rebuilt.html"
out="$(gate "$FULL" | sed -n 3p)"
[[ "$out" == "green: 14/15" ]] && ok "a 0-byte rebuilt.html is never green" || bad "empty rebuilt: $out"
page nomain es '<p>Sin estructura.</p>'
cp "$TMP/nomain.html" "$FULL/mixed-content-types/rebuilt.html"
out="$(gate "$FULL" | sed -n 3p)"
[[ "$out" == "green: 14/15" ]] && ok "a rebuilt.html with no <main> is never green" || bad "no-main rebuilt: $out"
cp "$TMP/clean.html" "$FULL/mixed-content-types/rebuilt.html"

rm -rf "$FULL/ui-string-language"
out="$(gate "$FULL")"; rc=$?
[[ "$(printf '%s\n' "$out" | head -1)" == "classes: 14/15" && $rc -ne 0 ]] \
  && ok "a registry missing a class reads 14/15 and fails" || bad "missing class: rc=$rc $(printf '%q' "$out")"

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
