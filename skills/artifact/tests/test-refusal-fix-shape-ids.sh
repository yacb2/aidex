#!/usr/bin/env bash
# test-refusal-fix-shape-ids.sh — Phase C of LOOP-009: the two biggest refusals
# (consult-shape 158 rows, consult-ids 140 in the 2026-09..10 census) name the exact
# fix and, on a page built from a spec, the spec line of the offender. Each case
# also pins that the page is STILL refused (same check name, exit 1) and that
# applying the named fix makes it pass: the message may not be the only thing that
# changed, and the check may not have been relaxed.
#
# Layer: integration over the real spec_build.py / spec_verbs.py / check-artifact.sh
# (the spec line comes from the spec file beside the page and the fix is a verb
# of another script, so mocking either would test the mock).
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
BUILD="$SKILL/scripts/spec_build.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

D="$TMP/my proj/.context/reports"; mkdir -p "$D"

# newpage <stem>: every case owns a page, ids never leave a baseline.
newpage() { PAGE="$D/$1.html"; SPEC="$D/$1.spec.md"; STEM="$1"; }
build() { python3 "$BUILD" "$SPEC" -o "$PAGE" > "$TMP/build.out" 2>&1; }
line_of() { grep -n -m1 -F -- "$1" "$SPEC" | cut -d: -f1; }

MAST='::: masthead {visual="none: short questions, nothing to draw" title="Dos preguntas"}
Una decision y una pregunta.
:::
'
G1='::: group {#G1 title="Lo que falta cerrar"}
::: item {#Q1 title="¿Cerramos el item ahora?"}
¿Cerramos el item ahora o lo dejamos para otra ronda?

- Sí: cerrarlo ahora {recommended}
- No: dejarlo para otra ronda
:::
:::
'
G2='::: group {#G2 title="Lo siguiente"}
::: item {#Q2 title="¿Aplazamos el segundo item?"}
¿Aplazamos el segundo item a la próxima ronda?

- Sí: aplazarlo {recommended}
- No: intentarlo ahora
:::
::: item {#Q3 title="¿Y el tercero?"}
¿Hacemos el tercero ahora?

- Sí: hacerlo {recommended}
- No: dejarlo
:::
:::
'
NOTES='::: notes {title="Notas generales"}
:::
'
CTX='::: group {#G0 title="Lo que encontre" heading="Hechos y prior art"}
Un contexto largo que no pregunta nada.
:::
'
SEC_HEAD='::: section {#sec-hechos heading="Hechos y prior art"}
Un contexto largo que no pregunta nada.
:::
'
ORPHAN='::: item {#Q9 title="¿Una decision suelta?"}
¿Hacemos la decision suelta?

- Sí: hacerla {recommended}
- No: omitirla
:::
'

# refused <label> <check> <rc> <pattern>...: the build is still refused by <check>
# (exit != 0, `FAIL [<check>]`) and every pattern is in that check's FAIL lines.
refused() {
  local label="$1" check="$2" rc="$3"; shift 3
  [[ "$rc" != 0 ]] || { fail "$label: expected the build to be refused, rc=0"; return 1; }
  grep "FAIL \[$check\]" "$TMP/build.out" > "$TMP/fails" \
    || { fail "$label: expected FAIL [$check]: $(cat "$TMP/build.out")"; return 1; }
  local p
  for p in "$@"; do
    grep -qF -- "$p" "$TMP/fails" \
      || { fail "$label: expected '$p' in: $(head -3 "$TMP/fails")"; return 1; }
  done
  return 0
}

# --- 0. a correct page passes -------------------------------------------------
newpage good
printf '%s\n%s\n%s\n%s\n' "$MAST" "$G1" "$G2" "$NOTES" > "$SPEC"
build && ok "0. a correct page (two blocks, notes) passes" || fail "0. $(cat "$TMP/build.out")"

# --- 1. a block that carries no decision --------------------------------------
newpage nodec
printf '%s\n%s\n%s\n%s\n' "$MAST" "$G1" "$CTX" "$NOTES" > "$SPEC"
build; rc=$?
L="$(line_of '::: group {#G0')"; M="$(line_of '::: group {#G1')"
refused "1. no decision" consult-shape "$rc" "carries no decision" "nodec.spec.md:$L" \
  "::: item" "::: section" "below the \`::: notes\`" "#G1 at nodec.spec.md:$M" \
  && ok "1. a block with no decision: still refused, names the spec line and the three fixes"
# the named remedy, applied, passes: the context as a section below the notes
newpage nodec-fixed
printf '%s\n%s\n%s\n%s\n' "$MAST" "$G1" "$NOTES" "$SEC_HEAD" > "$SPEC"
build && ok "1b. the context written as a section below the notes passes" \
  || fail "1b. $(cat "$TMP/build.out")"
# ... and the shortcut a builder auto-fix would take (group -> section in place)
# is NOT lossless: the section between blocks is the next refusal, so no auto-fix.
newpage nodec-inplace
printf '%s\n%s\n%s\n%s\n%s\n' "$MAST" "$G1" "$SEC_HEAD" "$G2" "$NOTES" > "$SPEC"
build; rc=$?
refused "1c. in-place section" consult-shape "$rc" "prose between blocks" \
  && ok "1c. group -> section left in place is refused (why this is a message, not an auto-fix)"

# --- 2. an item outside any block ---------------------------------------------
newpage orphan
printf '%s\n%s\n%s\n%s\n' "$MAST" "$G1" "$ORPHAN" "$NOTES" > "$SPEC"
build; rc=$?
L="$(line_of '::: item {#Q9')"
refused "2. orphan item" consult-shape "$rc" "item 'Q9'" "sits outside any block" \
  "orphan.spec.md:$L" "inside the \`::: group\`" \
  && ok "2. an item outside any block: still refused, names the spec line and the fix"
newpage orphan-fixed
printf '%s\n%s\n%s\n' "$MAST" "$G1" "$NOTES" > "$SPEC"
python3 - "$SPEC" "$ORPHAN" <<'PY'
import sys
p, orphan = sys.argv[1], sys.argv[2]
t = open(p).read()
i = t.index("::: notes")
# the item moves INSIDE the group: before the group's closing fence
j = t.rindex(":::\n", 0, i)
open(p, "w").write(t[:j] + orphan + t[j:])
PY
build && ok "2b. the item inside its group passes" || fail "2b. $(cat "$TMP/build.out")"

# --- 3. prose before the first block ------------------------------------------
newpage before
printf '%s\n%s\n%s\n%s\n' "$MAST" "$SEC_HEAD" "$G1" "$NOTES" > "$SPEC"
build; rc=$?
L="$(line_of '::: section {#sec-hechos')"
refused "3. prose before" consult-shape "$rc" "prose before the first block" \
  '"Hechos y prior art"' "before.spec.md:$L" "below the \`::: notes\`" \
  && ok "3. prose before the first block: still refused, names the section's spec line"

# --- 4. prose between blocks --------------------------------------------------
newpage between
printf '%s\n%s\n%s\n%s\n%s\n' "$MAST" "$G1" "$SEC_HEAD" "$G2" "$NOTES" > "$SPEC"
build; rc=$?
L="$(line_of '::: section {#sec-hechos')"
refused "4. prose between" consult-shape "$rc" "prose between blocks" \
  '"Hechos y prior art"' "between.spec.md:$L" "below the \`::: notes\`" \
  && ok "4. prose between blocks: still refused, names the section's spec line"

# --- 5. a hand-written page (no spec): the HTML line, never a spec name -------
mkpage() {
  {
    printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>Fixture</title>\n<style>\n'
    printf '@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#111; } }\n'
    printf ':root[data-theme="dark"] .consult-bar { background: #111; }\n'
    printf '</style>\n</head>\n<body>\n<div class="page"><main class="main">\n'
    printf '%s\n' "$2" | python3 "$(dirname "${BASH_SOURCE[0]}")/link_labels.py"
    printf '</main></div>\n<script>var blank = 0;</script>\n</body>\n</html>\n'
  } > "$1"
}
visual='<meta name="consult-visual" content="none: fixtures have no shape to draw">'
header='<header><p class="eyebrow">FIXTURE</p><h1>Claim</h1><p class="standfirst">The thesis.</p></header>'
item='<section class="consult-item" data-id="Q1" data-title="First" data-free><h3>First</h3><p class="fieldlabel">Free text</p><textarea></textarea></section>'
group='<section class="consult-group" id="G1" data-id="G1" data-title="Context"><div class="sec-head"><p class="eyebrow">Block G1</p><h2>Context</h2></div><p>Shared context.</p>'"$item"'<div class="group-notes"><p class="fieldlabel">Notes on this block</p><textarea></textarea></div></section>'
notes='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><p class="fieldlabel">Notes for the whole page</p><textarea></textarea></section>'
bars='<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div><aside class="rail"><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside>'
pre='<section id="sec-intro"><div class="sec-head"><h2>What changed this round</h2></div><p>Context the questions depend on.</p></section>'
mkpage "$D/hand.html" "$visual$header$pre$group$notes$bars"
bash "$CHECK" "$D/hand.html" > "$TMP/build.out" 2>&1; rc=$?
hl="$(grep -n 'What changed this round' "$D/hand.html" | sed -n 1p | cut -d: -f1)"
refused "5. hand-written page" consult-shape "$rc" "prose before the first block" "line $hl" \
  && ! grep -q "spec.md" "$TMP/fails" \
  && ok "5. a page with no spec beside it names its HTML line and no spec file" \
  || fail "5. $(cat "$TMP/fails")"

# --- 6. id reused for a different claim ---------------------------------------
build_round1() {  # build_round1 <stem>: Q1 in G1, Q2+Q3 in G2
  newpage "$1"
  printf '%s\n%s\n%s\n%s\n' "$MAST" "$G1" "$G2" "$NOTES" > "$SPEC"
  build || fail "round 1 of $1 did not build: $(cat "$TMP/build.out")"
}
VERBS="$SKILL/scripts/spec_verbs.py"

build_round1 reused
sed -i.bak 's/title="¿Cerramos el item ahora?"/title="¿Que hacemos con el cierre?"/' "$SPEC"
build; rc=$?
L="$(line_of '::: item {#Q1')"
refused "6. reused id" consult-ids "$rc" "id reused for a different claim — Q1" \
  "reused.spec.md:$L" "Same question reworded" "--retitle Q1" \
  "next free: Q4" \
  && ok "6. a reworded kept id: still refused, names --retitle, the spec line and the next free id"
# the named command, run as printed, lets the same build pass
run_named() {  # run_named <flag>: eval the backticked command exactly as printed
  local cmd
  cmd="$(grep -m1 -o "python3 [^\`]*$1[^\`]*" "$TMP/fails")"
  [[ -n "$cmd" ]] || { echo "no backticked command in: $(head -2 "$TMP/fails")"; return 1; }
  eval "$cmd"
}
run_named --retitle > "$TMP/verb.out" 2>&1 \
  && ok "6b. the printed --retitle command, evaled as is under a path with a space, makes the page pass" \
  || fail "6b. $(cat "$TMP/verb.out")"

# --- 7. id dropped between rounds ---------------------------------------------
build_round1 dropped
python3 - "$SPEC" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
a = t.index("::: group {#G2")
b = t.index("::: notes")
open(p, "w").write(t[:a] + t[b:])
PY
build; rc=$?
refused "7. dropped ids" consult-ids "$rc" "id dropped between rounds — Q2" \
  "id dropped between rounds — Q3" "--drop G2" "--drop Q2" "--drop Q3" \
  "restore it in dropped.spec.md" \
  && ok "7. dropped ids: still refused, one paste-ready command lists every dropped id"
[[ "$(grep -o 'restore it in\|new-round' "$TMP/fails" | sed -n 1p)" == "restore it in" ]] \
  && ok "7a. the message offers restoring the item before the --drop command" \
  || fail "7a. restore does not come first: $(head -1 "$TMP/fails")"
run_named --drop > "$TMP/verb.out" 2>&1 \
  && ok "7b. the printed --drop command, evaled as is, makes the page pass" \
  || fail "7b. $(cat "$TMP/verb.out")"

# --- 8. no spec beside the pages: the HTML declarations, never a verb ---------
item2='<section class="consult-item" data-id="Q2" data-title="Second" data-free><h3>Second</h3><p class="fieldlabel">Free text</p><textarea></textarea></section>'
item1b='<section class="consult-item" data-id="Q1" data-title="Something else entirely" data-free><h3>Something else entirely</h3><p class="fieldlabel">Free text</p><textarea></textarea></section>'
grp() { printf '%s' "${group/$item/$1}"; }
mkpage "$D/prev.html" "$visual$header$(grp "$item$item2")$notes$bars"
mkpage "$D/reword.html" "$visual$header$(grp "$item1b$item2")$notes$bars"
bash "$CHECK" "$D/reword.html" --prev "$D/prev.html" > "$TMP/build.out" 2>&1; rc=$?
refused "8. reworded id, no spec" consult-ids "$rc" "id reused for a different claim — Q1" \
  '<meta name="consult-retitled" content="Q1">' "next free: Q3" \
  && ! grep -q "spec_verbs\|spec.md" "$TMP/fails" \
  && ok "8. hand-written reworded id: still refused, names the meta declaration" \
  || fail "8. $(cat "$TMP/fails")"
mkpage "$D/gone.html" "$visual$header$(grp "$item")$notes$bars"
bash "$CHECK" "$D/gone.html" --prev "$D/prev.html" > "$TMP/build.out" 2>&1; rc=$?
refused "8b. dropped id, no spec" consult-ids "$rc" "id dropped between rounds — Q2" \
  '<meta name="consult-dropped" content="Q2">' \
  && ! grep -q "spec_verbs\|spec.md" "$TMP/fails" \
  && ok "8b. hand-written dropped id: still refused, names the meta declaration" \
  || fail "8b. $(cat "$TMP/fails")"

# --- 9. a dropped id is not "free": R1 Q1-Q3, R2 drops Q3, R3 rewords Q1 -----
build_round1 freeid
python3 - "$SPEC" <<'PY'
import sys
p = sys.argv[1]
t = open(p).read()
a = t.index("::: item {#Q3")
b = t.index(":::\n", t.index("- No: dejarlo", a)) + 4
open(p, "w").write(t[:a] + t[b:])
PY
python3 "$VERBS" new-round "$SPEC" --drop Q3 > "$TMP/verb.out" 2>&1 || fail "9. R2 drop: $(cat "$TMP/verb.out")"
sed -i.bak 's/title="¿Cerramos el item ahora?"/title="¿Que hacemos con el cierre?"/' "$SPEC"
build; rc=$?
refused "9. next free skips a dropped id" consult-ids "$rc" "id reused for a different claim — Q1" "next free: Q4" \
  && ok "9. next free id is Q4, not the dropped Q3"
sed -i.bak 's/title="¿Que hacemos con el cierre?"/title="¿Cerramos el item ahora?"/' "$SPEC"
python3 "$VERBS" add-item "$SPEC" --group G1 --id Q4 --title "¿Una nueva?" --body "¿Hacemos la nueva?" \
  --option "Sí: hacerla" --option "No: omitirla" > "$TMP/verb.out" 2>&1 \
  && ok "9b. the suggested id Q4 is accepted by add-item" \
  || fail "9b. $(cat "$TMP/verb.out")"

# --- 10. a retitle declared last round is not renewed (BL-611) ----------------
build_round1 oneround
sed -i.bak 's/title="¿Cerramos el item ahora?"/title="¿Que hacemos con el cierre?"/' "$SPEC"
python3 "$VERBS" new-round "$SPEC" --retitle Q1 > "$TMP/verb.out" 2>&1 || fail "10. R2 retitle: $(cat "$TMP/verb.out")"
sed -i.bak 's/title="¿Aplazamos el segundo item?"/title="¿Que pasa con el segundo?"/' "$SPEC"
build; rc=$?
refused "10. retitle list" consult-ids "$rc" "id reused for a different claim — Q2" "--retitle Q2" \
  && ! grep -q -- "--retitle Q1" "$TMP/fails" \
  && ok "10. the command lists only the id reworded this round" \
  || fail "10. $(cat "$TMP/fails")"

# --- 11. gallery rows never enter the command; an unparsable spec still has a name
row() { printf '<section class="consult-item consult-gallery" data-id="row-a" data-title="%s" data-free><h3>%s</h3><p class="fieldlabel">Free text</p><textarea></textarea></section>' "$1" "$1"; }
printf 'not a spec\n' > "$D/rowpg.spec.md"
mkpage "$D/rowprev.html" "$visual$header$(grp "$item$(row 'Row A')")$notes$bars"
mkpage "$D/rowpg.html" "$visual$header$(grp "$item1b$(row 'Row B')")$notes$bars"
bash "$CHECK" "$D/rowpg.html" --prev "$D/rowprev.html" > "$TMP/build.out" 2>&1; rc=$?
refused "11. reworded row" consult-ids "$rc" "id reused for a different claim — row-a" "--retitle Q1" \
  && ! grep -q -- "--retitle row-a" "$TMP/fails" \
  && ok "11. a reworded gallery row is not put in the --retitle command" \
  || fail "11. $(cat "$TMP/fails")"
mkpage "$D/rowpg.html" "$visual$header$(grp "$item2")$notes$bars"
bash "$CHECK" "$D/rowpg.html" --prev "$D/rowprev.html" > "$TMP/build.out" 2>&1; rc=$?
refused "11b. dropped row" consult-ids "$rc" "id dropped between rounds — row-a" "restore it in rowpg.spec.md" "--drop Q1" \
  "gallery row ids (row-a)" \
  && ! grep -q -- "--drop Q1 --drop row-a" "$TMP/fails" \
  && ok "11b. a dropped gallery row is not in the --drop command; the spec is named though it does not parse" \
  || fail "11b. $(cat "$TMP/fails")"

if (( failures )); then printf '\n%d failure(s)\n' "$failures"; exit 1; fi
printf '\nALL OK\n'
