#!/usr/bin/env bash
# The consultation SHAPE is checkable, and this is what is checked (BL-247).
#
# §8.4 ("the explanation lives inside the item") was declared not
# machine-checked because every proxy for item QUALITY is satisfiable without
# satisfying it. BL-240's page kept the letter of the rule — items of 350-700
# words — under a 1,553-word preamble two questions depended on. What IS a fact
# of the DOM, and not a proxy, is WHERE things sit:
#   - every consult-item (bar the general-notes one) lives inside a
#     `.consult-group` — one context with the decisions it yields;
#   - a group carries at least one decision (a context with nothing to answer
#     is the old preamble wearing a class);
#   - no prose section sits between the first group and the general-notes item;
#   - before the first group only the header, a visual section and the ledger
#     may appear — the strongest claim goes in the standfirst, reference
#     material goes AFTER the questions;
#   - a group id kept across regenerations still names the same context.
# Word counts stay out, deliberately (BL-243).
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

mkpage() {
  local out="$1" body="$2"
  {
    printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>Fixture</title>\n<style>\n'
    printf '@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#111; } }\n'
    printf ':root[data-theme="dark"] .consult-bar { background: #111; }\n'
    printf '</style>\n</head>\n<body>\n<div class="page"><main class="main">\n'
    printf '%s\n' "$body" | python3 "$(dirname "${BASH_SOURCE[0]}")/link_labels.py"
    printf '</main></div>\n<script>var blank = 0;</script>\n</body>\n</html>\n'
  } > "$out"
}

visual='<meta name="consult-visual" content="none: fixtures have no shape to draw">'
header='<header><p class="eyebrow">FIXTURE</p><h1>Claim</h1><p class="standfirst">The thesis.</p></header>'
ledger='<section id="sec-ledger"><div class="sec-head"><h2>Settled</h2></div><div class="ledger"><div><span class="k">d1</span><span class="v"><b>Done.</b> x</span></div></div></section>'
notes='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><p class="fieldlabel">Notes for the whole page</p><textarea></textarea></section>'
bars='<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div><aside class="rail"><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside>'
ref='<section id="sec-ref"><div class="sec-head"><h2>Where the figures come from</h2></div><p>Measured.</p></section>'
# Fixtures obey the page contract (contract_defects.py, blocking since LOOP-006)
# so a case fails only for the rule it tests: an optionless item is a declared
# open answer (data-free), and the rail's copy control sits in aside.rail.
item() {  # item <id> <title>
  printf '<section class="consult-item" data-id="%s" data-title="%s" data-free><h3>%s</h3><p class="fieldlabel">Free text</p><textarea></textarea></section>' "$1" "$2" "$2"
}
group() {  # group <id> <title> <items-html>
  printf '<section class="consult-group" id="%s" data-id="%s" data-title="%s"><div class="sec-head"><p class="eyebrow">Block %s</p><h2>%s</h2></div><p>The context this block shares.</p>%s<div class="group-notes"><p class="fieldlabel">Notes on this block</p><textarea></textarea></div></section>' "$1" "$1" "$2" "$1" "$2" "$3"
}

run() { bash "$CHECK" "$@" > "$TMP/out" 2>&1; echo $?; }
expect_fail() {  # expect_fail <label> <pattern>
  [[ "$rc" == 1 ]] || fail "$1: expected exit 1, got $rc: $(cat "$TMP/out")"
  grep -q "$2" "$TMP/out" || fail "$1: expected '$2' in output: $(cat "$TMP/out")"
}

# --- the shape that passes ----------------------------------------------------
good="$visual$header$ledger$(group G1 'Context one' "$(item Q1 'First')$(item Q2 'Second')")$(group G2 'Context two' "$(item Q3 'Third')")$notes$bars$ref"
mkpage "$TMP/good.html" "$good"
rc="$(run "$TMP/good.html")"
[[ "$rc" == 0 ]] || fail "the block shape passes: $(cat "$TMP/out")"

# --- an item outside any group ------------------------------------------------
mkpage "$TMP/loose.html" "$visual$header$(group G1 'Context' "$(item Q1 'First')")$(item Q2 'Loose')$notes$bars"
rc="$(run "$TMP/loose.html")"; expect_fail "item outside a group" "Q2.*outside"

# --- a group with no decision -------------------------------------------------
mkpage "$TMP/empty.html" "$visual$header$(group G1 'Context' "$(item Q1 'First')")$(group G2 'Prose only' '')$notes$bars"
rc="$(run "$TMP/empty.html")"; expect_fail "group without a decision" "G2.*no decision"

# --- prose between two groups -------------------------------------------------
between='<section id="sec-aside"><div class="sec-head"><h2>Meanwhile, some context</h2></div><p>That belongs in a block.</p></section>'
mkpage "$TMP/between.html" "$visual$header$(group G1 'Context' "$(item Q1 'First')")$between$(group G2 'Two' "$(item Q2 'Second')")$notes$bars"
rc="$(run "$TMP/between.html")"; expect_fail "prose between groups" "between"

# --- prose before the ledger (the BL-240 preamble) ----------------------------
preamble='<section id="sec-intro"><div class="sec-head"><h2>What changed this round</h2></div><p>Fifteen hundred words of context the questions depend on.</p></section>'
mkpage "$TMP/preamble.html" "$visual$header$preamble$ledger$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/preamble.html")"; expect_fail "prose before the ledger" "before the first block"

# ...while a visual section and the ledger before the first group are allowed,
# and so is the reference section AFTER the notes (good.html above carries all
# three). A visual section is one whose content is a figure:
figsec='<section id="sec-shape"><div class="sec-head"><h2>The shape</h2></div><figure><svg viewBox="0 0 10 10"></svg><figcaption>What it shows.</figcaption></figure></section>'
mkpage "$TMP/fig.html" "$header$figsec$ledger$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/fig.html")"
[[ "$rc" == 0 ]] || fail "a visual section before the ledger passes: $(cat "$TMP/out")"

# --- BL-426: the ledger exemption is a SHAPE, not a class name ----------------
# `.ledger` is a grid built for rows of `.k`/`.v` (components.css:107). A writer
# that meets the "prose before the first block" FAIL can wrap the prose in
# `<div class="ledger">` and pass, and the grid then lays the h2 and the table
# side by side with the table clipped (2026-09-20, the owner-decisions page).
lsec() {  # lsec <ledger-children>
  printf '<section id="sec-ledger"><div class="sec-head"><h2>Carried in</h2></div><div class="ledger">%s</div></section>' "$1"
}
row='<div><span class="k">d1</span><span class="v"><b>Done.</b> x</span></div>'

# (1) an h2 + a table laundered into the ledger
mkpage "$TMP/led-table.html" "$visual$header$(lsec '<h2>Summary</h2><table><tr><td>x</td></tr></table>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-table.html")"; expect_fail "h2 + table inside div.ledger" "not a ledger"
grep -q "h2, table" "$TMP/out" || fail "the ledger failure does not name the shape: $(cat "$TMP/out")"

# (2) one valid row plus a stray child
mkpage "$TMP/led-mixed.html" "$visual$header$(lsec "$row<p>A loose paragraph.</p>")$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-mixed.html")"; expect_fail "a ledger mixing a row with a stray child" "not a ledger"

# (3) a row with a key and no value
mkpage "$TMP/led-nov.html" "$visual$header$(lsec '<div><span class="k">d1</span></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-nov.html")"; expect_fail "a ledger row with .k and no .v" "not a ledger"

# (4) the well-formed ledger still passes
mkpage "$TMP/led-ok.html" "$visual$header$(lsec "$row$row")$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-ok.html")"
[[ "$rc" == 0 ]] || fail "a well-formed ledger was rejected: $(cat "$TMP/out")"

# (5) an empty ledger, and the first page of a thread with no ledger at all
mkpage "$TMP/led-empty.html" "$visual$header$(lsec '')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-empty.html")"
[[ "$rc" == 0 ]] || fail "an empty ledger was rejected: $(cat "$TMP/out")"
mkpage "$TMP/led-none.html" "$visual$header$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-none.html")"
[[ "$rc" == 0 ]] || fail "a first page with no ledger was rejected: $(cat "$TMP/out")"

# --- BL-426 round 2: the row is a SHAPE, not a containment test ---------------
# Every cell below passed the first predicate, which asked only whether `.k` and
# `.v` appeared ANYWHERE inside the row: a heading and a table keyed `k`/`v`
# deep inside satisfy that and still break the grid.

# (A1) a heading standing beside the key and the value
mkpage "$TMP/led-a1.html" "$visual$header$(lsec '<div><h2>Resumen</h2><span class="k"></span><span class="v"></span></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a1.html")"; expect_fail "a heading beside the row's k and v" "not a ledger"

# (A2) the heading and the table hidden INSIDE a well-formed value
mkpage "$TMP/led-a2.html" "$visual$header$(lsec '<div><span class="k">R</span><span class="v"><h2>R</h2><table><tr><td>x</td></tr></table></span></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a2.html")"; expect_fail "a heading and a table inside .v" "not a ledger"

# (A3) class values that merely START with k/v are not the tokens
mkpage "$TMP/led-a3.html" "$visual$header$(lsec '<div><h2 class="k-1">R</h2><table class="v-align"><tr><td>x</td></tr></table></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a3.html")"; expect_fail "k-1 and v-align are not the k and v tokens" "not a ledger"

# (A4) the keys carried by a table's cells rather than by the row
mkpage "$TMP/led-a4.html" "$visual$header$(lsec '<div><h2>R</h2><table><tr><td class="k">a</td><td class="v">b</td></tr></table></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a4.html")"; expect_fail "a table whose cells carry k and v" "not a ledger"

# (A6) a cell that is neither the key nor the value
mkpage "$TMP/led-a6.html" "$visual$header$(lsec '<div><span class="k">d1</span><span>stray</span><span class="v">x</span></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a6.html")"; expect_fail "a third cell beside the key and the value" "not a ledger"

# (A7) a table alone inside the value — a table is the one element a grid cell
# cannot cap, so it is banned at any depth, heading or no heading
mkpage "$TMP/led-a7.html" "$visual$header$(lsec '<div><span class="k">R</span><span class="v"><table><tr><td>x</td></tr></table></span></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a7.html")"; expect_fail "a table alone inside .v" "not a ledger"

# (A8) a heading alone inside the value
mkpage "$TMP/led-a8.html" "$visual$header$(lsec '<div><span class="k">R</span><span class="v"><h3>Resumen</h3> x</span></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a8.html")"; expect_fail "a heading alone inside .v" "not a ledger"

# (A9) the same near-miss tokens on two otherwise well-shaped cells: the class
# is a list of TOKENS, and `k-1` is not `k` however a substring test reads it
mkpage "$TMP/led-a9.html" "$visual$header$(lsec '<div><span class="k-1">d1</span><span class="v-align">x</span></div>')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a9.html")"; expect_fail "cells classed k-1 and v-align" "not a ledger"

# (A5) loose prose text as the ledger's own content
mkpage "$TMP/led-a5.html" "$visual$header$(lsec 'Un resumen suelto, sin filas.')$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-a5.html")"; expect_fail "loose text as the ledger's content" "not a ledger"

# --- BL-426 round 2: the pre-first-block region that sits in NO section --------
# The four 2026-09-20 report pages put the h1, the standfirst and the ledger
# directly under <main>, with no wrapping <section> — and the section loop above
# never looked there, so the whole rule was one wrapper away from silent.
mkpage "$TMP/bare-led.html" "$visual$header<div class=\"ledger\"><h2>Resumen</h2><table><tr><td>x</td></tr></table></div>$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/bare-led.html")"; expect_fail "a bare ledger under <main> laundering an h2 + table" "not a ledger"

mkpage "$TMP/bare-p.html" "$visual$header<p>Fifteen hundred words of preamble, in no section at all.</p>$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/bare-p.html")"; expect_fail "a bare preamble under <main>" "before the first block"

mkpage "$TMP/bare-h2.html" "$visual$header<h2>Resumen</h2><table><tr><td>x</td></tr></table>$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/bare-h2.html")"; expect_fail "a bare h2 + table under <main>" "before the first block"

# --- BL-426 round 2: what the stricter predicate must keep accepting ----------
# (B1) a commented-out row is not markup
mkpage "$TMP/led-b1.html" "$visual$header$(lsec "$row<!-- <p>old note</p> -->")$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-b1.html")"
[[ "$rc" == 0 ]] || fail "a commented-out child failed the ledger: $(cat "$TMP/out")"

# (B2) a void element between two rows
mkpage "$TMP/led-b2.html" "$visual$header$(lsec "$row<br>$row")$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-b2.html")"
[[ "$rc" == 0 ]] || fail "a <br> between two rows failed the ledger: $(cat "$TMP/out")"

# (B3) the shape the four report pages are written in: h1, eyebrow, standfirst
# and a well-formed ledger, all bare under <main>.
mkpage "$TMP/bare-ok.html" "$visual<p class=\"eyebrow\">CONSULTA</p><h1>Claim</h1><p class=\"standfirst\">The thesis, with <code>code</code> in it.</p><div class=\"ledger\">$row$row</div>$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/bare-ok.html")"
[[ "$rc" == 0 ]] || fail "the report pages' bare header + ledger was rejected: $(cat "$TMP/out")"

# (B4) inline markup inside the value
vrich='<div><span class="k">d1</span><span class="v"><b>Done.</b> see <a href="#x"><code>file.py</code></a><br>and the rest</span></div>'
mkpage "$TMP/led-b4.html" "$visual$header$(lsec "$vrich")$(group G1 'Context' "$(item Q1 'First')")$notes$bars"
rc="$(run "$TMP/led-b4.html")"
[[ "$rc" == 0 ]] || fail "inline markup inside .v was rejected: $(cat "$TMP/out")"

# (F3, BL-734) a commented-out item outside a block, and one after the
# general-notes item, are not items: the page is valid.
mkpage "$TMP/cm-loose.html" "$visual$header$(group G1 'Context' "$(item Q1 'First')")<!-- $(item Q9 'Retired') -->$notes$bars"
rc="$(run "$TMP/cm-loose.html")"
[[ "$rc" == 0 ]] || fail "a commented-out item outside a block failed the shape: $(cat "$TMP/out")"
mkpage "$TMP/cm-after.html" "$visual$header$(group G1 'Context' "$(item Q1 'First')")$notes<!-- $(item Q9 'Retired') -->$bars"
rc="$(run "$TMP/cm-after.html")"
[[ "$rc" == 0 ]] || fail "a commented-out item after the general-notes item failed the shape: $(cat "$TMP/out")"
mkpage "$TMP/cm-live.html" "$visual$header$(group G1 'Context' "$(item Q1 'First')")$(item Q9 'Live loose')$notes$bars"
rc="$(run "$TMP/cm-live.html")"; expect_fail "a live loose item still fails beside the commented ones" "Q9.*outside"

# --- a read page (no items) is untouched by the shape rules -------------------
mkpage "$TMP/read.html" "$header<section id=\"a\"><h2>One</h2><p>x</p></section><section id=\"b\"><h2>Two</h2><p>y</p></section>"
rc="$(run "$TMP/read.html")"
[[ "$rc" == 0 ]] || fail "a read page has no shape rules: $(cat "$TMP/out")"

# --- a group relabelled across rounds is a note, not a failure (BL-612) --------
# A block's title is a label, not a claim a reply points at: --prev reports it
# and passes. An item retitled under the same id still fails (consult-ids).
# --- BL-714: profile="study" lifts ONLY the two prose rules ---------------------
smeta='<meta name="consult-profile" content="study">'
sec1='<section id="sec-t1"><div class="sec-head"><h2>Teaching one</h2></div><p>The idea.</p></section>'
sec2='<section id="sec-t2"><div class="sec-head"><h2>Teaching two</h2></div><p>The next idea.</p></section>'
studybody() {  # studybody <meta> <extra-before-first-group>
  printf '%s' "$1$visual$header$2$sec1$(group G1 'Check one' "$(item Q1 'First')")$sec2$(group G2 'Check two' "$(item Q2 'Second')")$notes$bars"
}
mkpage "$TMP/st-ok.html" "$(studybody "$smeta" '')"
rc="$(run "$TMP/st-ok.html")"
[[ "$rc" == 0 ]] || fail "study: section, check, section, check passes: $(cat "$TMP/out")"
mkpage "$TMP/st-none.html" "$(studybody '' '')"
rc="$(run "$TMP/st-none.html")"; expect_fail "same page without the study meta (between)" "prose between blocks"
grep -q "prose before the first block" "$TMP/out" || fail "same page without the study meta: no preamble FAIL: $(cat "$TMP/out")"
# (i) the ledger-shape rule still runs on a study page
badled='<div class="ledger"><p>x</p></div>'
mkpage "$TMP/st-led.html" "$(studybody "$smeta" "$badled")"
rc="$(run "$TMP/st-led.html")"; expect_fail "study page, non-ledger before the first group" "is not a ledger"
# (ii) a bare item between sections is still outside any block
mkpage "$TMP/st-loose.html" "$smeta$visual$header$sec1$(group G1 'Check one' "$(item Q1 'First')")$sec2$(item Q2 'Loose')$notes$bars"
rc="$(run "$TMP/st-loose.html")"; expect_fail "study page, bare item between sections" "sits outside any block"
# (iii) the value is read exactly
for v in study-off STUDY; do
  mkpage "$TMP/st-$v.html" "$(studybody "<meta name=\"consult-profile\" content=\"$v\">" '')"
  rc="$(run "$TMP/st-$v.html")"; expect_fail "content=$v is not the study profile" "prose between blocks"
done
mkpage "$TMP/st-name.html" "$(studybody '<meta name="consult-profile-x" content="study">' '')"
rc="$(run "$TMP/st-name.html")"; expect_fail "name=consult-profile-x is not the profile meta" "prose between blocks"
mkpage "$TMP/st-data.html" "$(studybody '<meta data-name="consult-profile" content="study">' '')"
rc="$(run "$TMP/st-data.html")"; expect_fail "data-name= is not the profile meta" "prose between blocks"
# (iv) the meta only inside a <script> does not relax the page
mkpage "$TMP/st-script.html" "$(studybody '<script>var m = &#39;<meta name="consult-profile" content="study">&#39;;</script>' '')"
sed -i.x "s/&#39;/'/g" "$TMP/st-script.html"
rc="$(run "$TMP/st-script.html")"; expect_fail "profile meta inside a script" "prose between blocks"

mkpage "$TMP/v1.html" "$good"
mkpage "$TMP/v2.html" "$visual$header$ledger$(group G1 'A different context' "$(item Q1 'First')$(item Q2 'Second')")$(group G2 'Context two' "$(item Q3 'Third')")$notes$bars$ref"
rc="$(run "$TMP/v2.html" --prev "$TMP/v1.html")"
[[ "$rc" == 0 ]] || fail "group relabelled: expected exit 0, got $rc: $(cat "$TMP/out")"
grep -q 'NOTE \[consult-ids\].*G1: block relabelled' "$TMP/out" || fail "group relabelled: no NOTE naming G1: $(cat "$TMP/out")"

# --- the group is not counted as an item ---------------------------------------
# It carries data-id/data-title for --prev; it has no reply surface of its own
# and must not be reported as an item the reader cannot answer.
grep -q "G1.*no reply surface\|G1.*no notes" "$TMP/out" && fail "a group was judged as an item"
rc="$(run "$TMP/good.html")"
grep -q "G1\|G2" "$TMP/out" && fail "a group was reported on a passing page: $(cat "$TMP/out")"

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: consultation shape (35 cases)"
