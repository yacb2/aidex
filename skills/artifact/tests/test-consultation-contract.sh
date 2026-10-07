#!/usr/bin/env bash
# The consultation contract counts ITEMS, not <textarea> occurrences.
#
# v1 keyed everything off the number of reply boxes, which made two correct pages
# fail and one incorrect page pass:
#   - an item whose reply surface is a radio group, a select or a short text
#     input carried no textarea, so it was invisible to the count and the page was
#     told it had ids for boxes that did not exist;
#   - once the kit injects composer.js into every page, the clipboard fallback's
#     `createElement('textarea')` matched the detection grep, so a READ page with
#     no questions at all was judged as a consultation and failed for lacking a
#     copy button it has no use for.
#
# v2: a page is a consultation when it carries a reply surface in its markup, OR
# a data-id item, OR the composer's own button id. Detection stays an OR — a
# hand-rolled page with nine boxes and zero ids (BL-168) is exactly the case the
# first arm exists to catch, and keying only off data-id would have dropped it.
# Per-item requirements then key off items: every item needs a title and at least
# one reply surface of any kind, and an item with none fails.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
KIT="$SKILL/assets/artifact-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# A complete document, so the non-§8 checks (doctype, charset, viewport, title,
# themes) never mask what a case is actually testing.
mkpage() {
  local out="$1" body="$2"
  {
    printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>Fixture</title>\n<style>\n'
    printf '@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#111; } }\n'
    printf ':root[data-theme="dark"] .consult-bar { background: #111; }\n'
    printf '</style>\n</head>\n<body>\n'
    printf '%s\n' "$body" | python3 "$(dirname "${BASH_SOURCE[0]}")/link_labels.py"
    printf '</body>\n</html>\n'
  } > "$out"
}

# The page-level general-notes item. Every consultation fixture that is not
# testing its absence carries it, the way the template ships it.
notesitem='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><p class="fieldlabel">Notes for the whole page</p><textarea></textarea></section>'
gopen='<section class="consult-group" id="G1" data-id="G1" data-title="The context"><div class="sec-head"><h2>The context</h2></div><p>What the decisions below share.</p>'
gnotes='<div class="group-notes"><p class="fieldlabel">Notes on this block</p><textarea></textarea></div>'
gclose="$gnotes</section>"
# The copy controls where the page contract puts them (copy-control-placement,
# blocking since LOOP-006): one in the rail's .consult-bar, one at the end of <main>.
bars='<main><div class="endbar"><button type="button" id="consult-copy-end">Copy</button></div></main><aside class="rail"><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside>'
visual='<meta name="consult-visual" content="none: the subject is a single number, so there is no shape to draw">'
# The WHOLE kit, exactly as wrap-report.sh injects it. Inlining the composer
# alone would have missed the real defect: a comment in components.css spelled
# an id in its attribute form, so the injected stylesheet made every read page
# match the consultation detection.
kit="$(printf '<style>\n'; cat "$KIT/tokens.css"; printf '</style>\n<style>\n'; \
       cat "$KIT/components.css"; printf '</style>\n')"
composer="$kit$(printf '<script>\n'; cat "$KIT/composer.js"; printf '</script>\n')"

run() { bash "$CHECK" "$@" > "$TMP/out" 2>&1; echo $?; }

# ---- 1. a radio group plus its notes box passes --------------------------
mkpage "$TMP/radios.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Pick one\">
  <h3>Pick one</h3>
  <div class=\"opts\">
    <label><input type=\"radio\" name=\"Q1\" data-label=\"A\"><span>A</span></label>
    <label><input type=\"radio\" name=\"Q1\" data-label=\"B\"><span>B</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea placeholder=\"Anything the options do not cover\"></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/radios.html")"
[[ "$rc" == "0" ]] || fail "1. an answered-and-annotatable item rejected: $(cat "$TMP/out")"

# ---- 2. an item with no reply surface at all fails ------------------------
mkpage "$TMP/empty-item.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"Pick one\">
  <h3>Pick one</h3>
  <p>Nothing to answer with.</p>
</section>
$gclose
$bars
$composer"
rc="$(run "$TMP/empty-item.html")"
[[ "$rc" == "1" ]] || fail "2. an item with no reply surface passed"
grep -qi 'Q1' "$TMP/out" || fail "2. the failure does not name the item that has no reply surface"

# ---- 3. a READ page with the kit composer injected passes -----------------
# The case that forced the contract change: the composer ships on every page for
# the rail, and its clipboard fallback creates a textarea. A page with no
# questions must stay a read.
mkpage "$TMP/read.html" "<div class=\"page\"><main class=\"main\">
  <section id=\"s1\"><h2>A section</h2><p>Prose only.</p></section>
</main><aside class=\"rail\"><nav class=\"raillist\" id=\"raillist\"></nav></aside></div>
$composer"
rc="$(run "$TMP/read.html")"
[[ "$rc" == "0" ]] || fail "3. a read page with the kit composer was judged a consultation: $(cat "$TMP/out")"

# ---- 4. BL-168: reply boxes, zero stable ids, still fails -----------------
mkpage "$TMP/handrolled.html" "$visual
<div><p>What do you think?</p><textarea></textarea></div>
<div><p>And this?</p><textarea></textarea></div>"
rc="$(run "$TMP/handrolled.html")"
[[ "$rc" == "1" ]] || fail "4. a hand-rolled page with reply boxes and no data-id passed"
grep -qi 'data-id' "$TMP/out" || fail "4. the failure does not say the ids are missing"

# ---- 5. a lone reply surface with no items fails, and names what is missing
mkpage "$TMP/lone-select.html" "$visual
<label>Filter <select><option>all</option><option>open</option></select></label>"
rc="$(run "$TMP/lone-select.html")"
[[ "$rc" == "1" ]] || fail "5. a page with a bare reply surface and no items passed"
grep -qiE 'data-id|consult-copy' "$TMP/out" || fail "5. the failure names neither the missing ids nor the missing composer"

# ---- 6. --prev still catches an id reused for a different claim -----------
mkpage "$TMP/prev.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"The first claim\">
  <h3>Q1</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
$gclose
$notesitem
$bars
$composer"
mkpage "$TMP/now.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"A completely different claim\">
  <h3>Q1</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/now.html" --prev "$TMP/prev.html")"
[[ "$rc" == "1" ]] || fail "6. --prev no longer catches an id reused for a different claim"
grep -qi 'id reused' "$TMP/out" || fail "6. the --prev failure message changed shape"

# ---- 8. a choice with nowhere to qualify it fails -------------------------
# The reported defect: "si quiero mencionar algo más, además de la selección que
# realicé, sea simple o múltiple, tengo que tener el espacio para comentarlo".
# A radio group, a checkbox set and a select are all closed lists; the answer
# that does not fit one of them is lost unless the item carries free text.
mkpage "$TMP/no-notes.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Pick one\">
  <h3>Pick one</h3>
  <div class=\"opts\">
    <label><input type=\"radio\" name=\"Q1\" data-label=\"A\"><span>A</span></label>
    <label><input type=\"radio\" name=\"Q1\" data-label=\"B\"><span>B</span></label>
  </div>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/no-notes.html")"
[[ "$rc" == "1" ]] || fail "8. an item with a closed choice and no notes box passed"
grep -qi 'Q1' "$TMP/out" || fail "8. the failure does not name the item that has no notes box"

# ---- 9. a consultation with no general-notes item fails -------------------
# The reply that fits no question has to land somewhere. The fixture carries the
# WHOLE kit, which defines `.consult-notes` in components.css: the check must key
# off the markup, not off the injected stylesheet, or it passes every page.
mkpage "$TMP/no-general.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"Pick one\">
  <h3>Pick one</h3><p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$bars
$composer"
rc="$(run "$TMP/no-general.html")"
[[ "$rc" == "1" ]] || fail "9. a consultation with no general-notes item passed (or the check was satisfied by components.css)"
grep -qi 'consult-notes' "$TMP/out" || fail "9. the failure does not name the missing general-notes item"

# ---- 9c. BL-457: the general-notes item is the LAST consult item -----------
# A codefilm page shipped its notes between the first block and the decisions.
# The invariant is last CONSULT ITEM, not last block: reference sections after
# the questions are the contract (consult-shape), so one after the notes passes.
mkpage "$TMP/notes-mid.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"Pick one\">
  <h3>Pick one</h3><p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
<section class=\"consult-group\" id=\"G2\" data-id=\"G2\" data-title=\"More\"><div class=\"sec-head\"><h2>More</h2></div>
<section class=\"consult-item\" data-id=\"Q2\" data-free data-title=\"Pick again\">
  <h3>Pick again</h3><p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$bars
$composer"
rc="$(run "$TMP/notes-mid.html")"
[[ "$rc" == "1" ]] || fail "9c. a general-notes item followed by a block passed: $(cat "$TMP/out")"
grep -q "FAIL \[consult-shape\].*notes.*'G2'" "$TMP/out" || fail "9c. the failure does not name the block after the notes: $(cat "$TMP/out")"

mkpage "$TMP/notes-then-ref.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"Pick one\">
  <h3>Pick one</h3><p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
<section id=\"ref\"><h2>Reference</h2><p>Material read after the questions.</p></section>
$bars
$composer"
rc="$(run "$TMP/notes-then-ref.html")"
[[ "$rc" == "0" ]] || fail "9c. a reference section after the notes item was refused: $(cat "$TMP/out")"

# The notes item inside the last block, before that block's remaining item.
mkpage "$TMP/notes-in-group.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"Pick one\">
  <h3>Pick one</h3><p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$notesitem
<section class=\"consult-item\" data-id=\"Q2\" data-free data-title=\"Pick again\">
  <h3>Pick again</h3><p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$bars
$composer"
rc="$(run "$TMP/notes-in-group.html")"
[[ "$rc" == "1" ]] || fail "9c. an item after the notes inside the same block passed: $(cat "$TMP/out")"
grep -q "FAIL \[consult-shape\].*notes.*'Q2'" "$TMP/out" || fail "9c. the failure does not name the item after the notes: $(cat "$TMP/out")"

# The notes item is the class TOKEN consult-notes: `consult-notes-hint` is not it.
mkpage "$TMP/notes-hint.html" "$visual
$gopen
<p class=\"consult-notes-hint\">Anything else goes in the general notes.</p>
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"Pick one\">
  <h3>Pick one</h3><p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/notes-hint.html")"
[[ "$rc" == "0" ]] || fail "9c. a consult-notes-hint class was read as the notes item: $(cat "$TMP/out")"

# ---- 7. the template ships the full component set ------------------------
# ---- 8. BL-198: an id in the ledger AND still LIVE in the question set fails --
# The ledger is the only declaration of decidedness the page carries as prose,
# so the intersection is what a checker can reach. BL-359 narrowed it: the item
# itself may say so too, with `data-decided`, and then keeping it is not the
# obligation half-done — it is the reference's DEFAULT shape.
ledger_ok='<div class="ledger"><div><span class="k">c1</span><span class="v"><b>Done.</b> Settled last round.</span></div></div>'
ledger_bad='<div class="ledger"><div><span class="k">c1 &middot; BL-265</span><span class="v"><b>Done.</b> Settled last round.</span></div></div>'
# An optionless item is a declared open answer (data-free): the page contract
# fails one that is not (decision-item-without-options, LOOP-006).
item() { printf '<section class="consult-item" data-id="%s" data-title="A question" data-free><h3>A question</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>' "$1"; }

mkpage "$TMP/ledger-clean.html" "$visual
$ledger_ok
$gopen
$(item c2)
$notesitem
$bars
$gclose
$composer"
rc="$(run "$TMP/ledger-clean.html")"
[[ "$rc" == "0" ]] || fail "8. a ledger disjoint from the question set was rejected: $(cat "$TMP/out")"

mkpage "$TMP/ledger-dirty.html" "$visual
$ledger_bad
$gopen
$(item c1)
$notesitem
$bars
$gclose
$composer"
rc="$(run "$TMP/ledger-dirty.html")"
[[ "$rc" == "1" ]] || fail "8. a decided item left in the question set passed"
grep -qi 'decided but still asked' "$TMP/out" \
  || fail "8. the failure does not name the shape: $(cat "$TMP/out")"
grep -qi 'c1' "$TMP/out" || fail "8. the failure does not name the id"

# The mandated general-notes item can never leave the question set, so a ledger
# key that tokenizes to it must not raise a failure nobody can clear.
mkpage "$TMP/ledger-notes.html" "$visual
<div class=\"ledger\"><div><span class=\"k\">c1 &middot; notes</span><span class=\"v\">Settled.</span></div></div>
$gopen
$(item c2)
$notesitem
$bars
$gclose
$composer"
rc="$(run "$TMP/ledger-notes.html")"
[[ "$rc" == "0" ]] || fail "8. a ledger key naming 'notes' flagged the mandated general-notes item: $(cat "$TMP/out")"

# A ledger keyed 1/2/3 is a numbered list, not item ids — and `.ledger` is also
# used as a plain grid with no `.k` at all. Neither may be read as a decision.
# The plain grid sits AFTER the blocks: id harvesting still tolerates it, but
# since BL-426 consult-shape no longer EXEMPTS a non-row grid before the first
# block, and this case is about ids, not about the preamble.
mkpage "$TMP/ledger-numbered.html" "$visual
<div class=\"ledger\"><div><span class=\"k\">1</span><span class=\"v\">A numbered row.</span></div></div>
$gopen
$(item c1)
$notesitem
$bars
$gclose
<div class=\"ledger\"><article><p>A grid row with no key at all.</p></article></div>
$composer"
rc="$(run "$TMP/ledger-numbered.html")"
[[ "$rc" == "0" ]] || fail "8. a numbered or keyless ledger was read as item ids: $(cat "$TMP/out")"

# ---- 8b. BL-359: a `data-decided` item named in the ledger is the DEFAULT ----
# `02-local-first-artifacts.md` § Update in place calls it out in a two-row
# table: keep the item, add `data-decided`, state the verdict in its body — "the
# page stays a record of the reasoning rather than only of the outcome". The kit
# already implements it (components.css greys the losing options and disables
# the inputs; composer.js `isDecided()` takes the item out of the paste, the
# counters and the answer store). The checker was the only one of the three that
# had not been told, and it FAILED the shape its own reference names the default
# — which forced a real page to hand-roll a `.settled` section the kit does not
# define, in breach of gate 1.
# The verdict in data-decided, where the fold shows it (decided-item-without-verdict).
decided() { printf '<section class="consult-item" data-decided="the first option won" data-id="%s" data-title="A question"><h3>A question</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>' "$1"; }

mkpage "$TMP/ledger-decided.html" "$visual
$ledger_bad
$gopen
$(decided c1)
$notesitem
$bars
$gclose
$composer"
rc="$(run "$TMP/ledger-decided.html")"
grep -qi 'decided but still asked' "$TMP/out" \
  && fail "8b. BL-359: a data-decided item named in the ledger was reported as 'decided but still asked' — the checker fails the shape the reference calls the default: $(cat "$TMP/out")"
[[ "$rc" == "0" ]] \
  || fail "8b. BL-359: the default settled shape did not pass the contract: $(cat "$TMP/out")"
# The block keeping its decided item still carries a decision, so demoting the
# whole block to reference material — the second effect BL-359 recorded — is no
# longer forced either.
grep -qi 'carries no decision' "$TMP/out" \
  && fail "8b. BL-359: the block holding only a decided item was reported as carrying no decision: $(cat "$TMP/out")"
# The MUTATION that keeps the rule load-bearing: the SAME page with the same
# ledger and the attribute removed must still fail. A fix that simply dropped
# the still-asked rule would clear 8b and look identical from the outside.
mkpage "$TMP/ledger-decided-mut.html" "$visual
$ledger_bad
$gopen
$(item c1)
$notesitem
$bars
$gclose
$composer"
rc="$(run "$TMP/ledger-decided-mut.html")"
grep -qi 'decided but still asked' "$TMP/out" \
  || fail "8b. BL-359: with data-decided removed the page stopped failing — the still-asked rule was dropped, not narrowed: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "8b. BL-359: the live item named in the ledger did not fail the wrap: $(cat "$TMP/out")"
# LOOP-006 decided-item-without-verdict: the advice is the fix, so it names the
# verdict's real place. "State the verdict in its body" produced the defect:
# the fold hides the body and shows the title alone.
grep -q 'decided but still asked.*data-decided="<the verdict>"' "$TMP/out" \
  || fail "8b. the still-asked message does not point at data-decided=\"<verdict>\": $(cat "$TMP/out")"
grep -qi 'verdict in its body' "$TMP/out" \
  && fail "8b. the still-asked message still tells the author to put the verdict in the body: $(cat "$TMP/out")"

# ---- 8c. BL-421: the STAMP is not the mark ----------------------------------
# `data-decided-round` is written next to `data-decided`, never instead of it —
# but `\bdata-decided\b` is satisfied by the hyphen, so an item carrying only the
# stamp read as settled and the still-asked rule went silent on a live question.
stamped_only() { printf '<section class="consult-item" data-decided-round="3" data-id="%s" data-title="A question"><h3>A question</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>' "$1"; }
mkpage "$TMP/ledger-stamp-only.html" "$visual
$ledger_bad
$gopen
$(stamped_only c1)
$notesitem
$bars
$gclose
$composer"
rc="$(run "$TMP/ledger-stamp-only.html")"
grep -qi 'decided but still asked' "$TMP/out" \
  || fail "8c. BL-421: an item carrying only data-decided-round was read as decided — the round stamp is not the decision: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "8c. BL-421: the stamp-only item named in the ledger did not fail the wrap: $(cat "$TMP/out")"


TPL="$SKILL/assets/templates/consultation-block.html.template"
for needle in 'type="radio"' 'type="checkbox"' '<select' 'type="text"' '<textarea' \
              'id="consult-copy"' 'id="consult-copy-end"' 'consult-notes'; do
  grep -qF "$needle" "$TPL" || fail "7. the consultation template is missing $needle"
done
# The CLOSING tag: the prose above explains that there is no style block any
# more, and a grep for the opening tag matches that sentence.
grep -q '</style>' "$TPL" \
  && fail "7. the consultation template still carries a <style> block — the kit supplies it now"
grep -q '</script>' "$TPL" \
  && fail "7. the consultation template still carries a <script> block — the kit supplies the composer"
# Every block the template offers carries free text: an author copying the
# select block or the checkbox block must not have to remember to add it.
# A block (`consult-group`) carries data-id for --prev but is not an item.
n_tpl_id="$(grep -viE 'consult-group' "$TPL" | grep -oiE 'data-id=' | wc -l | tr -d ' ')"
n_tpl_area="$(grep -oiE '<textarea' "$TPL" | wc -l | tr -d ' ')"
[[ "$n_tpl_area" -ge "$n_tpl_id" ]] \
  || fail "7. the template has $n_tpl_id item(s) and only $n_tpl_area notes box(es) — a copied block would ship a choice with nowhere to qualify it"

# ---- 10. the WARN channel: reports without failing, and only where it should
#
# Both shapes below shipped on the SAME page in one round and passed everything
# above. They are warnings rather than violations on purpose — neither makes a
# page unanswerable — so the load-bearing assertion is the EXIT CODE: a warning
# that failed the wrap would block a correct page, and one that printed nothing
# would be the silence it exists to break.
mkpage "$TMP/warn-opts.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Wrapped right\">
  <h3>Wrapped right</h3>
  <div class=\"opts one\">
    <label><input type=\"radio\" name=\"Q1\" data-label=\"A\"><span>A</span></label>
    <label><input type=\"radio\" name=\"Q1\" data-label=\"B\"><span>B</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q2\" data-title=\"Hand-rolled wrapper\">
  <h3>Hand-rolled wrapper</h3>
  <div class=\"consult-options\">
    <label><input type=\"radio\" name=\"Q2\" data-label=\"B (recomendada)\"><span>B</span></label>
    <label><input type=\"radio\" name=\"Q2\" data-label=\"C\"><span>C</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/warn-opts.html")"
[[ "$rc" == "0" ]] \
  || fail "10. a warning changed the exit code — a correct page would be blocked: $(cat "$TMP/out")"
grep -q 'WARN \[consult-opts\].*Q2' "$TMP/out" \
  || fail "10. BL-244: options outside .opts were not reported: $(cat "$TMP/out")"
grep -q 'WARN \[consult-opts\].*Q1' "$TMP/out" \
  && fail "10. BL-244: a correctly wrapped group was reported — the check is a presence test, not an ancestor walk: $(cat "$TMP/out")"
grep -q 'WARN \[consult-rec\].*Q2' "$TMP/out" \
  || fail "10. BL-245: '(recomendada)' inside data-label was not reported: $(cat "$TMP/out")"
grep -q 'WARN \[consult-rec\].*Q1' "$TMP/out" \
  && fail "10. BL-245: an ordinary data-label was reported as carrying a recommendation: $(cat "$TMP/out")"

# ---- 10a. a consult item with no options (BL-468, LOOP-006) ---------------
# Findings H1-H5 shipped as bare textareas while Q1-Q5 asked the same decisions
# with options: the reader answered each one twice. BL-468 made that a warning;
# LOOP-006 made it a FAILURE owned by contract_defects.py
# (decision-item-without-options, at least two options), which check-artifact
# calls instead of keeping its own copy. Exempt: data-free, settled, notes.
mkpage "$TMP/warn-free.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"H1\" data-title=\"Finding with no options\">
  <h3>Finding with no options</h3>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"H2\" data-title=\"Declared free\" data-free>
  <h3>Declared free</h3>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"H3\" data-title=\"Settled\" data-decided=\"answered in H9\">
  <h3>Settled</h3>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"With options\">
  <h3>With options</h3>
  <div class=\"opts one\">
    <label><input type=\"radio\" name=\"Q1\" data-label=\"A\"><span>A</span></label>
    <label><input type=\"radio\" name=\"Q1\" data-label=\"B\"><span>B</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/warn-free.html")"
[[ "$rc" == "1" ]] \
  || fail "10a. an item with no options did not fail the wrap: $(cat "$TMP/out")"
grep -q "FAIL \[decision-item-without-options\] warn-free.html: line [0-9]*: item 'H1'" "$TMP/out" \
  || fail "10a. BL-468: an item with no options was not reported as a FAIL with its line: $(cat "$TMP/out")"
grep -Eq "\[decision-item-without-options\].*'(H2|H3|Q1|G1|notes)'" "$TMP/out" \
  && fail "10a. BL-468: a free, settled, optioned, group or notes item was reported: $(cat "$TMP/out")"
grep -q 'consult-free' "$TMP/out" \
  && fail "10a. the BL-468 copy still runs beside contract_defects — two owners of one rule: $(cat "$TMP/out")"

# ---- 10a3. a literal {recommended} has one owner (LOOP-006) ----------------
# contract_defects' decision-item-without-options reports the leaked marker;
# check-artifact's own rec-leak copy (BL-481) is gone, so one leak is one FAIL.
mkpage "$TMP/rec-leak.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Leaked\">
  <h3>Leaked</h3>
  <div class=\"opts one\">
    <label><input type=\"radio\" name=\"Q1\" data-label=\"A\"><span>A {recommended}</span></label>
    <label><input type=\"radio\" name=\"Q1\" data-label=\"B\"><span>B</span></label>
  </div>
  <p>Quoted, it is not a leak: <code>{recommended}</code>.</p>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/rec-leak.html")"
[[ "$rc" == "1" ]] || fail "10a3. a leaked {recommended} did not fail the wrap: $(cat "$TMP/out")"
[[ "$(grep -c '{recommended}' "$TMP/out")" == "1" ]] \
  && grep -q "FAIL \[decision-item-without-options\].*literal {recommended} shows as page text" "$TMP/out" \
  || fail "10a3. one leak is not exactly one decision-item-without-options FAIL: $(cat "$TMP/out")"

# ---- 10b. facts written as a paragraph, inside an ITEM (BL-270) ---------
# BL-269 scoped the rule to the block context; one day later the same shape
# shipped inside an item body (Q15: ~20 skills across three layers, 9 <code>
# tokens in one paragraph). Shape, not word count (BL-243): four or more
# <code> tokens or `;`-joined clauses in one <p>. Reported once, under the
# innermost owner; an explanatory paragraph in the same block stays silent.
mkpage "$TMP/warn-facts.html" "$visual
<section class=\"consult-group\" id=\"G1\" data-id=\"G1\" data-title=\"The context\"><div class=\"sec-head\"><h2>The context</h2></div>
<p>Four things happened: the map grew; the index moved; the hint changed; the gate closed.</p>
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"Dense\">
  <h3>Dense</h3>
  <p>The boilerplate suite takes <code>a</code>, <code>b</code>, <code>c</code> and <code>d</code>; myskills keeps <code>e</code>.</p>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q2\" data-free data-title=\"Plain\">
  <h3>Plain</h3>
  <p>One explanatory paragraph that names <code>one</code> thing and says why it matters, at length; nothing else.</p>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q3\" data-free data-title=\"Code semicolons\">
  <h3>Code semicolons</h3>
  <p>The hook runs <code>a; b; c; d</code> once per session.</p>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q4\" data-free data-title=\"Source line\">
  <h3>Source line</h3>
  <p>Fuente: sección 4; sección 5; <code>a.py</code>, <code>b.py</code>, <code>c.py</code>, <code>run.sh; exit</code>.</p>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/warn-facts.html")"
# The same paragraph is also mixed-content-types (a), which LOOP-006 made
# blocking on every paragraph of the page: the shape now fails the wrap.
[[ "$rc" == "1" ]] \
  || fail "10b. a code-dense paragraph did not fail the wrap: $(cat "$TMP/out")"
grep -q "FAIL \[mixed-content-types\].*5 <code> tokens" "$TMP/out" \
  || fail "10b. the code-dense paragraph was not a mixed-content-types FAIL: $(cat "$TMP/out")"
grep -q "FAIL \[mixed-content-types\].*4 semicolon-separated clauses" "$TMP/out" \
  || fail "10b. BL-270: the clause-dense block context was not a mixed-content-types FAIL: $(cat "$TMP/out")"
# One owner per finding: where mixed-content-types FAILs a paragraph, the
# consult-facts WARN on it is a second report of the same thing and is dropped.
grep -Eq "WARN \[consult-facts\].*'(Q1|G1)'" "$TMP/out" \
  && fail "10b. consult-facts still warns a paragraph mixed-content-types already fails: $(cat "$TMP/out")"
# What the FAIL does not cover stays a warning: semicolons inside <code> are
# code to mixed-content-types, and still clauses to consult-facts.
grep -q "WARN \[consult-facts\].*'Q3' carries a paragraph with 4 semicolon-separated clauses" "$TMP/out" \
  || fail "10b. the paragraph only consult-facts sees lost its warning: $(cat "$TMP/out")"
# BL-643: a Fuente LINE may list several paths, so its <code> count is no FAIL; the
# semicolons inside <code> still make the consult-facts warning, named by clauses.
grep -q "WARN \[consult-facts\].*'Q4' carries a paragraph with 4 semicolon-separated clauses" "$TMP/out" \
  || fail "10b. BL-643: a Fuente line with in-code semicolons lost its clause warning: $(cat "$TMP/out")"
grep -q "'Q4'.*<code> tokens\|mixed-content-types.*sección 4" "$TMP/out" \
  && fail "10b. BL-643: a Fuente line was reported by code count: $(cat "$TMP/out")"
grep -q "\[mixed-content-types\].*a; b; c; d\|\[mixed-content-types\].*The hook runs" "$TMP/out" \
  && fail "10b. semicolons inside <code> were counted as clauses by mixed-content-types: $(cat "$TMP/out")"
grep -q "WARN \[consult-facts\].*'Q2'" "$TMP/out" \
  && fail "10b. an explanatory paragraph was reported — the proxy is too wide: $(cat "$TMP/out")"

# The declared affordance is the thing the warning points AT, so it must be
# silent: a page that complied and still got warned teaches authors to ignore it.
mkpage "$TMP/warn-clean.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Declared properly\">
  <h3>Declared properly?</h3>
  <div class=\"opts one\">
    <label><input type=\"radio\" name=\"Q1\" data-label=\"A\" data-recommended><span>A</span></label>
    <label><input type=\"radio\" name=\"Q1\" data-label=\"B\" data-recommended=\"no\"><span>B</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/warn-clean.html")"
[[ "$rc" == "0" ]] || fail "10. the compliant page failed: $(cat "$TMP/out")"
grep -q 'WARN' "$TMP/out" \
  && fail "10. the page using data-recommended and .opts was still warned: $(cat "$TMP/out")"

# A read page never enters the channel at all — the whole battery is gated on
# the consultation gate, and warnings must not widen it.
mkpage "$TMP/warn-read.html" "<p>A report with no questions.</p>
<table><tr><td>x</td></tr></table>
$composer"
rc="$(run "$TMP/warn-read.html")"
[[ "$rc" == "0" ]] || fail "10. a read page failed: $(cat "$TMP/out")"
grep -q 'WARN' "$TMP/out" && fail "10. a read page collected warnings: $(cat "$TMP/out")"

# ---- 9b. BL-331: a consultation that RAN OUT of questions could not stop
# being one. By §8's own model a decided item leaves the question set, so a page
# whose last item was answered has zero items — and then the gate fires on the
# copy bar still sitting in its body, while the `consult-surfaces` escape is
# skipped for the same reason (CONSULT_STRUCTURE matched `id="consult-copy"`).
# The failure message even pointed at the declaration the page was already
# carrying. Hit closing the figure-route bench page on 2026-09-07.
surfaces='<meta name="consult-surfaces" content="none: every question was answered; the decisions are in the ledger">'
mkpage "$TMP/decided-out.html" "$visual
$surfaces
<div class=\"page\"><main class=\"main\"><h1>Closed</h1>
<p>The thread is closed and the decisions are below.</p>
<div class=\"ledger\"><div><span class=\"k\">d1</span><span class=\"v\">Decided.</span></div></div>
$bars
</main></div>
$composer"
rc="$(run "$TMP/decided-out.html")"
[[ "$rc" == "0" ]] \
  || fail "BL-331: a page with no items and consult-surfaces: none still fails — the declared escape is unreachable behind the copy bar: $(cat "$TMP/out")"

# The half that must not be traded away: a page with REAL items gets the whole
# battery, declaration or not. Otherwise the escape becomes a way to opt out of
# §8 by writing one meta tag.
mkpage "$TMP/decided-out-items.html" "$visual
$surfaces
<div class=\"page\"><main class=\"main\">
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Still open\">
  <h3>Still open</h3>
  <div class=\"opts one\"><label><input type=\"radio\" name=\"Q1\" data-label=\"A\"><span>A</span></label><label><input type=\"radio\" name=\"Q1\" data-label=\"B\"><span>B</span></label></div>
</section>
$gclose
$bars
</main></div>
$composer"
rc="$(run "$TMP/decided-out-items.html")"
[[ "$rc" == "0" ]] \
  && fail "BL-331: consult-surfaces waved a page with real items past the whole §8 battery: $(cat "$TMP/out")"

# ---- 10b2. BL-324: consult-facts counted `;` in the RAW SOURCE, so every
# `&iacute;` was a clause separator. Measured on a Spanish translation: a
# paragraph with ONE real semicolon and five accent entities was reported as
# "7 semicolon-separated clauses", and twelve warnings fired on a page whose
# English original fired none. Rewriting the accents as literal UTF-8 cleared
# all twelve without touching a sentence — the warnings were measuring the
# encoding, not the prose.
mkpage "$TMP/warn-entities.html" "$visual
<div class=\"page\"><main class=\"main\">
<section class=\"consult-group\" id=\"G9\" data-id=\"G9\" data-title=\"Acentos\">
<div class=\"sec-head\"><h2>Acentos</h2></div>
<section class=\"consult-item\" data-id=\"e1\" data-free data-title=\"Una sola clausula\">
  <h3><span class=\"consult-id\">e1</span>Una sola clausula</h3>
  <p>La p&aacute;gina se public&oacute; en espa&ntilde;ol con acentos codificados; eso es todo.</p>
  <p class=\"fieldlabel\">Notes on this one</p><textarea></textarea>
</section>
$gnotes
</section>
$notesitem
$bars
</main></div>
$composer"
rc="$(run "$TMP/warn-entities.html")"
[[ "$rc" == "0" ]] || fail "10b2. the entity page failed the contract: $(cat "$TMP/out")"
grep -q "WARN \[consult-facts\]" "$TMP/out" \
  && fail "10b2. BL-324: entity-encoded accents were counted as clause separators: $(cat "$TMP/out")"

# ---- 10b3. BL-463: an item placed BEFORE the evidence it asks about. The
# codefilm round-4 page put each `::: item` above the videos the owner had to
# judge, so the answer box rendered first and the material after. The signal a
# checker can read without guessing is evidence left AFTER a block's last item:
# evidence between two items is the next item's (evidence -> item, per
# decision, is the prescribed order) and must stay silent. Evidence is a
# figure, img, svg, video, table (also inside `.tw`), or a `@@VIDEO` marker
# paragraph that a project's post-build step turns into <video>.
mkpage "$TMP/warn-order.html" "$visual
<section class=\"consult-group\" id=\"G1\" data-id=\"G1\" data-title=\"Videos\"><div class=\"sec-head\"><h2>Videos</h2></div>
<p>What both films share.</p>
<section class=\"consult-item\" data-id=\"V1\" data-free data-title=\"Approve F1\"><h3>Approve F1</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
<p>F1 before and after:</p>
$gnotes
<p>@@VIDEO a.mp4|F1 before@@</p>
</section>
<section class=\"consult-group\" id=\"G2\" data-id=\"G2\" data-title=\"Numbers\"><div class=\"sec-head\"><h2>Numbers</h2></div>
<section class=\"consult-item\" data-id=\"T1\" data-free data-title=\"Pick\"><h3>Pick</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
<div class=\"tw\"><table><tr><td>x</td></tr></table></div>
$gnotes
</section>
<section class=\"consult-group\" id=\"G3\" data-id=\"G3\" data-title=\"Frames\"><div class=\"sec-head\"><h2>Frames</h2></div>
<section class=\"consult-item\" data-id=\"F1\" data-free data-title=\"Look\"><h3>Look</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
<video src=\"b.mp4\" controls></video>
$gnotes
</section>
$notesitem
$bars
$composer"
rc="$(run "$TMP/warn-order.html")"
[[ "$rc" == "0" ]] || fail "10b3. consult-order changed the exit code — it is a warning: $(cat "$TMP/out")"
for pair in "G1.*'V1'" "G2.*'T1'" "G3.*'F1'"; do
  grep -q "WARN \[consult-order\].*$pair" "$TMP/out" \
    || fail "10b3. BL-463: evidence after the last item of a block was not reported ($pair): $(cat "$TMP/out")"
done

mkpage "$TMP/order-clean.html" "$visual
<section class=\"consult-group\" id=\"G1\" data-id=\"G1\" data-title=\"Videos\"><div class=\"sec-head\"><h2>Videos</h2></div>
<p>What both films share.</p>
<div class=\"tw\"><table><tr><td>x</td></tr></table></div>
<p>@@VIDEO a.mp4|F1 before@@</p>
<section class=\"consult-item\" data-id=\"V1\" data-free data-title=\"Approve F1\"><h3>Approve F1</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
<video src=\"b.mp4\" controls></video>
<section class=\"consult-item\" data-id=\"V2\" data-free data-title=\"Approve F2\"><h3>Approve F2</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
<p>A closing sentence is prose, not evidence.</p>
<p><svg width=\"8\" height=\"8\"></svg> an inline legend swatch is decoration, not evidence.</p>
$gnotes
</section>
$notesitem
$bars
$composer"
rc="$(run "$TMP/order-clean.html")"
[[ "$rc" == "0" ]] || fail "10b3. the evidence-first page failed: $(cat "$TMP/out")"
grep -q "WARN \[consult-order\]" "$TMP/out" \
  && fail "10b3. evidence placed before each item was reported: $(cat "$TMP/out")"

# ---- 10b4. BL-503: an item whose FIRST sentence cites an internal id (BL-/M095
# style id, backticked path, HTTP verb, "fila N", "gate N") reached the owner
# as document reconciliation, not as a product situation; 7 of 11 items on one
# page came back as "explain". The lead must be plain prose; ids go on a
# trailing "Fuente:" line. WARN only (exit 0). Boundary: only the first
# sentence of the lead paragraph counts; an id later in the lead, or on a
# Fuente: line, must stay silent.
idem() {  # id, lead paragraph html, [second paragraph html]
  printf '<section class=\"consult-item\" data-id=\"%s\" data-free data-title=\"T %s\"><h3>T %s</h3><p>%s</p>%s<p class=fieldlabel>Free text</p><textarea></textarea></section>' "$1" "$1" "$1" "$2" "${3:+<p>$3</p>}"
}
mkpage "$TMP/lead-ids.html" "$visual
$gopen
$(idem A1 'Decision M095 says that the manager cannot delete the project.')
$(idem A2 'Today <code>backend/api/voices.py</code> returns 200 to the manager.')
$(idem A3 'GET on the profile returns 200 for the manager.')
$(idem A4 'According to fila 170 the manager cannot delete projects.')
$(idem A5 'The gate 3 says the manager cannot delete projects.')
$(idem A6 'Ana, a manager, opens the project and presses Delete. Today the button does not appear (BL-503, GET /x).' 'Fuente: ADR fila 170, M095, <code>a/b.py</code>, gate 3.')
$(idem A7 'Ana, a manager, opens the project and does not see the Delete button.')
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/lead-ids.html")"
[[ "$rc" == "0" ]] || fail "10b4. consult-lead-id changed the exit code — it is a warning: $(cat "$TMP/out")"
for id in A1 A2 A3 A4 A5; do
  grep -q "WARN \[consult-lead-id\].*'$id'" "$TMP/out" \
    || fail "10b4. BL-503: an id in the first sentence of $id was not reported: $(cat "$TMP/out")"
done
for id in A6 A7; do
  grep -q "WARN \[consult-lead-id\].*'$id'" "$TMP/out" \
    && fail "10b4. BL-503: $id has a prose lead (ids only after it or on Fuente:) and must not warn: $(cat "$TMP/out")"
done

# 10b4 review round: skipped paragraphs, fieldlabel, sentence split, same-page
# ids, block contexts, gate/gates.
fl='<p class="fieldlabel">'
rawitem() {  # id, inner html (paragraphs)
  printf '<section class=\"consult-item\" data-id=\"%s\" data-free data-title=\"T %s\"><h3>T %s</h3>%s<p class=fieldlabel>Free text</p><textarea></textarea></section>' "$1" "$1" "$1" "$2"
}
mkpage "$TMP/lead-ids2.html" "$visual
$gopen
$(rawitem C1 '<p>Fuente: M095.</p><p>BL-4 says the manager cannot delete.</p>')
$(rawitem C2 '<p>Fuente: M095, gate 3.</p>')
$(rawitem C3 '<p></p><p>BL-4 says the manager cannot delete.</p>')
$(rawitem C4 "$fl"'Notes on BL-4</p><p>Ana, a manager, opens the project and sees no Delete button.</p>')
$(rawitem C5 '<p>Mr. Lopez sees BL-4 today.</p>')
$(rawitem C6 '<p>For example, e.g. BL-12 shows up.</p>')
$(rawitem C7 '<p>Ana opens the project. Then BL-4 applies.</p>')
$(rawitem C8 '<p>It depends on your answer to Q2.</p>')
$(rawitem C9 '<p>It depends on your answer to Q9.</p>')
$(rawitem C10 '<p>The gates 3 and 4 say the manager cannot delete.</p>')
$(rawitem Q2 '<p>Ana, a manager, opens the project and sees no Delete button.</p>')
$gclose
<section class=\"consult-group\" id=\"G7\" data-id=\"G7\" data-title=\"Ctx\"><div class=\"sec-head\"><h2>Ctx</h2></div><p>M095 and BL-4 frame everything below.</p>
$(rawitem D1 '<p>Ana, a manager, opens the project and sees no Delete button.</p>')
$gnotes
</section>
$notesitem
$bars
$composer"
rc="$(run "$TMP/lead-ids2.html")"
[[ "$rc" == "0" ]] || fail "10b4b. consult-lead-id changed the exit code: $(cat "$TMP/out")"
for id in C1 C3 C5 C6 C9 C10; do
  grep -q "WARN \[consult-lead-id\].*'$id'" "$TMP/out" \
    || fail "10b4b. $id should have warned: $(cat "$TMP/out")"
done
for id in C2 C4 C7 C8 D1 G7; do
  grep -q "WARN \[consult-lead-id\].*'$id'" "$TMP/out" \
    && fail "10b4b. $id must not warn: $(cat "$TMP/out")"
done

# 10b4c. The same check on a page built from a spec: the builder turns an item's
# first paragraph into its <h3> question, so a lead read only from <p> never
# fired on the main route (echo_lab round 1 replay, 2026-09-29: 0 WARNs on a page
# whose leads opened with "La fila M095", "`GET /voices/profiles/`", "Gate 3").
cat > "$TMP/built-lead.spec.md" <<'SPEC'
::: masthead {lang="en" visual="none: consultation"}
# Built leads
:::

::: group {#G1 title="Leads"}
::: item {#E1 title="Id lead"}
Row M095 gets a 403 when it mutes a track.

- Allow it {recommended}
- Keep the 403
:::

::: item {#E2 title="Prose lead"}
Ana, an observer, mutes a track and gets an error. Fuente: M095.

- Allow it {recommended}
- Keep the error
:::

::: item {#E3 title="Situation lead"}
Row M095 gets a 403 when it mutes a track. Should an observer mute?

- Allow it {recommended}
- Keep the 403
:::
:::

::: notes {title="Anything else"}
:::
SPEC
( cd "$TMP" && python3 "$SKILL/scripts/spec_build.py" "$TMP/built-lead.spec.md" -o "$TMP/built-lead.html" ) >/dev/null 2>&1 \
  || fail "10b4c. spec_build failed on the lead fixture"
rc="$(run "$TMP/built-lead.html")"
[[ "$rc" == "0" ]] || fail "10b4c. consult-lead-id changed the exit code: $(cat "$TMP/out")"
grep -q "WARN \[consult-lead-id\].*'E1'" "$TMP/out" \
  || fail "10b4c. a built item whose question opens with M095 did not warn: $(cat "$TMP/out")"
grep -q "WARN \[consult-lead-id\].*'E2'" "$TMP/out" \
  && fail "10b4c. a built item with a prose question must not warn: $(cat "$TMP/out")"
# BL-514: the h3 now holds only the closing question; the lead is the
# situation paragraph below it, and that is what the check must read.
grep -q "WARN \[consult-lead-id\].*'E3'" "$TMP/out" \
  || fail "10b4c. a situation lead opening with M095 above its question did not warn: $(cat "$TMP/out")"

# 10b4d. BL-631: a product name with a number ("Los Simpson T8") is not an id.
# A bare letter+digits counts only after an id word or as a Q/M095 prefix, and
# never right after a capitalized proper-noun word.
mkpage "$TMP/lead-ids3.html" "$visual
$gopen
$(idem F1 'Ana sube el archivo X al proyecto Los Simpson T8 y al día siguiente llega E0804_v2.')
$(idem F2 'La decisión B10 fija el límite del proyecto.')
$(idem F3 'The Q3 decides the scope of the project.')
$(idem F4 'Per M095 the manager cannot delete the project.')
$(idem F5 'Ana buys a Samsung Q80 and plugs it in.')
$(idem F6 'The decisions B10 and B11 set the project limit.')
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/lead-ids3.html")"
[[ "$rc" == "0" ]] || fail "10b4d. consult-lead-id changed the exit code: $(cat "$TMP/out")"
grep -q "WARN \[consult-lead-id\].*'F1'" "$TMP/out" \
  && fail "10b4d. BL-631: a product name with a number is not an id, F1 must not warn: $(cat "$TMP/out")"
grep -q "WARN \[consult-lead-id\].*'F2'" "$TMP/out" \
  || fail "10b4d. BL-631: 'La decisión B10' must still warn: $(cat "$TMP/out")"
for id in F3 F4 F6; do
  grep -q "WARN \[consult-lead-id\].*'$id'" "$TMP/out" \
    || fail "10b4d. BL-631: $id opens with a known id and must warn: $(cat "$TMP/out")"
done
grep -q "WARN \[consult-lead-id\].*'F5'" "$TMP/out" \
  && fail "10b4d. BL-631: F5 (Samsung Q80) is a product name and must not warn: $(cat "$TMP/out")"

# 10b4e. BL-623: a Fuente line made only of short codes / untranslated English
# words on a Spanish page, and an item with options whose h3 states instead of
# asking. WARN only. A real word beside the code ("decisión d4 ... fase 8") and
# an English page ("phase") stay clean. mkpage is lang=en, so sed swaps it.
qitem() {  # id, h3 text, fuente text
  printf '<section class=\"consult-item\" data-id=\"%s\" data-title=\"T %s\"><h3>%s</h3><p>Ana abre el proyecto y no ve el botón.</p><p>%s</p><div class=\"opts\"><label><input type=\"radio\" name=\"%s\" data-label=\"A\"><span>A</span></label><label><input type=\"radio\" name=\"%s\" data-label=\"B\"><span>B</span></label></div><p class=fieldlabel>Free text</p><textarea></textarea></section>' "$1" "$1" "$2" "$3" "$1" "$1"
}
mkpage "$TMP/fuente-es.html" "$visual
$gopen
$(qitem H1 '¿Mostramos el botón?' 'Fuente: d4, M4, phase 8.')
$(qitem H2 'La columna Idiomas muestra el texto cortado.' 'Fuente: decisión d4 del contrato de pantallas, fase 8.')
$(qitem H3 '¿Mostramos el botón?' 'Fuente: decisión d4 del contrato de pantallas, fase 8.')
$gclose
$notesitem
$bars
$composer"
sed -i.bak -e 's/<html lang="en">/<html lang="es">/' -e 's/Notes on this block/Notas de este bloque/' -e 's/Notes for the whole page/Notas de la página/' "$TMP/fuente-es.html"
rc="$(run "$TMP/fuente-es.html")"
[[ "$rc" == "0" ]] || fail "10b4e. the new warnings changed the exit code: $(cat "$TMP/out")"
grep -q "WARN \[consult-fuente-unreadable\].*'H1'" "$TMP/out" \
  || fail "10b4e. BL-623: 'Fuente: d4, M4, phase 8.' on a Spanish page was not reported: $(cat "$TMP/out")"
grep -q "WARN \[consult-heading-statement\].*'H2'" "$TMP/out" \
  || fail "10b4e. BL-623: an item with options and a statement h3 was not reported: $(cat "$TMP/out")"
for id in H2 H3; do
  grep -q "WARN \[consult-fuente-unreadable\].*'$id'" "$TMP/out" \
    && fail "10b4e. BL-623: $id has a readable Fuente and must not warn: $(cat "$TMP/out")"
done
for id in H1 H3; do
  grep -q "WARN \[consult-heading-statement\].*'$id'" "$TMP/out" \
    && fail "10b4e. BL-623: $id heading is a question and must not warn: $(cat "$TMP/out")"
done
# 10b4e review round: gallery rows and decided items are not asked, backlog-id
# Fuente lines are what consult-lead-id tells authors to write.
radios2='<div class="opts"><label><input type="radio" name="g" data-label="A"><span>A</span></label><label><input type="radio" name="g" data-label="B"><span>B</span></label></div>'
mkpage "$TMP/fuente-es2.html" "$visual
$gopen
<section class=\"consult-item consult-gallery\" data-id=\"g-a-b\" data-title=\"g · a · b\"><h3>Lista vacía</h3>$radios2<p class=fieldlabel>Free text</p><textarea></textarea></section>
$(qitem K1 'La columna muestra el texto cortado.' 'Fuente: decisión d4 del contrato.' | sed 's/data-title=/data-decided=\"Aprobada\" data-title=/')
$(qitem K2 '¿Mostramos el botón?' 'Fuente: BL-617.')
$(qitem K3 '¿Mostramos el botón?' 'Fuente: BL-716, BL-708, P11.')
$gclose
$notesitem
$bars
$composer"
sed -i.bak -e 's/<html lang="en">/<html lang="es">/' -e 's/Notes on this block/Notas de este bloque/' -e 's/Notes for the whole page/Notas de la página/' "$TMP/fuente-es2.html"
rc="$(run "$TMP/fuente-es2.html")"
grep -q "WARN \[consult-heading-statement\].*'g-a-b'" "$TMP/out" \
  && fail "10b4e. BL-623: a gallery row heading is a state name and must not warn: $(cat "$TMP/out")"
grep -q "WARN \[consult-heading-statement\].*'K1'" "$TMP/out" \
  && fail "10b4e. BL-623: a decided item is not asked and must not warn: $(cat "$TMP/out")"
grep -q "WARN \[consult-fuente-unreadable\].*'K2'" "$TMP/out" \
  && fail "10b4e. BL-623: 'Fuente: BL-617.' is what consult-lead-id asks for and must stay clean: $(cat "$TMP/out")"
grep -q "WARN \[consult-fuente-unreadable\].*'K3'" "$TMP/out" \
  || fail "10b4e. BL-623: 'Fuente: BL-716, BL-708, P11.' was not reported: $(cat "$TMP/out")"
mkpage "$TMP/fuente-en.html" "$visual
$gopen
$(qitem J1 'Do we show the button?' 'Source: d4, M4, phase 8.')
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/fuente-en.html")"
grep -q "WARN \[consult-fuente-unreadable\]" "$TMP/out" \
  && fail "10b4e. BL-623: 'phase' on an English page is not untranslated: $(cat "$TMP/out")"

# 10b4f. BL-650: a raw gallery-row slug, or a bare "notes" label, in the visible
# prose of a Spanish page WARNs (consult-raw-label). The same strings inside a
# Fuente line, <code> or a data attribute stay clean, and so does ordinary
# hyphenated content (a date, BL-123, a file name, a URL, an e-mail).
slug='users-list-actions-menu-invited-light-desktop'
mkpage "$TMP/raw-label-es.html" "$visual
$(printf '%s' "$gopen" | sed 's/data-title=\"The context\"/data-title=\"The context\" data-tiles=\"light-desktop\"/')
<section class=\"consult-item consult-gallery\" data-id=\"$slug\" data-title=\"users · list\"><h3><span class=\"consult-id\">$slug</span>Menú de acciones</h3><p class=\"gal-na\">No aplica a este estado.</p>$radios2<p class=fieldlabel>Free text</p><textarea></textarea></section>
<section class=\"consult-item\" data-id=\"R1\" data-title=\"Titulo 1\"><h3>¿Cambiamos el menú?</h3><p>Ana abre la lista. La fila $slug se ve cortada.</p>$radios2<p class=fieldlabel>Free text</p><textarea></textarea></section>
<section class=\"consult-item\" data-id=\"R2\" data-title=\"Titulo 2\"><h3>¿Mostramos el botón?</h3><p>Ana abre el proyecto.</p><label>notes</label><div class=\"opts\"><label><input type=\"radio\" name=\"R2\" data-label=\"A\"><span>A</span></label><label><input type=\"radio\" name=\"R2\" data-label=\"B\"><span>B</span></label></div><p class=fieldlabel>Free text</p><textarea></textarea></section>
<section class=\"consult-item\" data-id=\"R3\" data-title=\"Titulo 3\"><h3>¿Mostramos el botón?</h3><p>Ana abre el proyecto; ver <code>$slug</code>.</p><p>Fuente: $slug, notes.</p><p>Fuente: <em>notes</em></p><p data-x=\"$slug\">Sin ids a la vista.</p><div class=\"opts\"><label><input type=\"radio\" name=\"R3\" data-label=\"A\"><span>A</span></label><label><input type=\"radio\" name=\"R3\" data-label=\"B\"><span>B</span></label></div><p class=fieldlabel>Free text</p><textarea></textarea></section>
<section class=\"consult-item\" data-id=\"R4\" data-title=\"Titulo 4\"><h3>¿Mostramos el botón?</h3><p>Ana abre el proyecto. Desde 2026-10-02 (BL-123) el archivo foo-bar-baz.md y https://x.dev/a-b-c-d no cambian; escríbenos a e-mail@x.dev. Es un cambio socio-económico.</p><div class=\"opts\"><label><input type=\"radio\" name=\"R4\" data-label=\"A\"><span>A</span></label><label><input type=\"radio\" name=\"R4\" data-label=\"B\"><span>B</span></label></div><p class=fieldlabel>Free text</p><textarea></textarea></section>
$gclose
$(printf '%s' "$notesitem" | sed 's|<h3>General notes</h3>|<h3><span class="consult-id">notes</span>Notas generales</h3>|')
$bars
$composer"
sed -i.bak -e 's/<html lang="en">/<html lang="es">/' -e 's/Notes on this block/Notas de este bloque/' -e 's/Notes for the whole page/Notas de la página/' "$TMP/raw-label-es.html"
rc="$(run "$TMP/raw-label-es.html")"
[[ "$rc" == "0" ]] || fail "10b4f. BL-650: consult-raw-label changed the exit code — it is a warning: $(cat "$TMP/out")"
grep -q "WARN \[consult-raw-label\].*'R1'.*$slug" "$TMP/out" \
  || fail "10b4f. BL-650: a row slug in visible prose was not reported: $(cat "$TMP/out")"
grep -q "WARN \[consult-raw-label\].*'R2'.*'notes'" "$TMP/out" \
  || fail "10b4f. BL-650: a bare notes label on a Spanish page was not reported: $(cat "$TMP/out")"
for id in "$slug" R3 R4 notes; do
  grep -q "WARN \[consult-raw-label\] [^:]*: '$id' shows" "$TMP/out" \
    && fail "10b4f. BL-650: $id has only Fuente/code/attribute/ordinary hyphens and must stay clean: $(cat "$TMP/out")"
done

sed -i.bak 's/<html lang="es">/<html lang="en">/' "$TMP/raw-label-es.html"
rc="$(run "$TMP/raw-label-es.html")"
grep -q "WARN \[consult-raw-label\]" "$TMP/out" \
  && fail "10b4f. BL-650: an English page is not judged for a Spanish label: $(cat "$TMP/out")"

# A hand-written row id of fewer than three segments ("vacio") is ordinary prose
# elsewhere; the gallery contract FAILs such a page, but the WARN must not add noise.
mkpage "$TMP/raw-short.html" "$visual
$(printf '%s' "$gopen" | sed 's/data-title=\"The context\"/data-title=\"The context\" data-tiles=\"light-desktop\"/')
<section class=\"consult-item consult-gallery\" data-id=\"vacio\" data-title=\"vacio\"><h3>Estado vacío</h3><p class=\"gal-na\">No aplica a este estado.</p>$radios2<p class=fieldlabel>Free text</p><textarea></textarea></section>
<section class=\"consult-item\" data-id=\"S1\" data-title=\"Titulo S1\"><h3>¿Mostramos el botón?</h3><p>Ana abre la lista y se ve vacio hoy.</p>$radios2<p class=fieldlabel>Free text</p><textarea></textarea></section>
$gclose
$notesitem
$bars
$composer"
sed -i.bak -e 's/<html lang="en">/<html lang="es">/' -e 's/Notes on this block/Notas de este bloque/' -e 's/Notes for the whole page/Notas de la página/' "$TMP/raw-short.html"
rc="$(run "$TMP/raw-short.html")"
grep -q "WARN \[consult-raw-label\]" "$TMP/out" \
  && fail "10b4f. BL-650: a gallery id of fewer than three segments is prose and must not warn: $(cat "$TMP/out")"

# ---- 10c. BL-310: SVG text that overlaps, leaves the viewBox or outgrows
# its box. A consultation shipped with two hand-authored figures whose labels
# collided and two labels wider than their boxes, and passed 'artifact
# contract OK': the contract read the DOM shape and never the geometry. No
# renderer at wrap time, so the check is a static estimate on viewBox
# coordinates (font-size x per-character width); a WARN, because an estimate
# that failed the wrap would block a page that renders fine.
mkpage "$TMP/warn-svg.html" "<div class=\"page\"><main class=\"main\">
<figure><svg viewBox=\"0 0 960 200\" role=\"img\" aria-label=\"probe\">
  <g font-size=\"12\">
    <text x=\"100\" y=\"40\">alpha label here</text>
    <text x=\"130\" y=\"42\">beta label here</text>
    <text x=\"900\" y=\"100\">runs off the right edge</text>
    <rect x=\"300\" y=\"60\" width=\"60\" height=\"30\" fill=\"none\" stroke=\"currentColor\"/>
    <text x=\"330\" y=\"80\" text-anchor=\"middle\">much too long for this box</text>
    <text x=\"100\" y=\"150\">left</text>
    <text x=\"400\" y=\"150\">right</text>
    <g transform=\"rotate(-90)\"><text x=\"-100\" y=\"20\">rotated axis label that the estimate cannot place</text></g>
  </g>
</svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg.html")"
[[ "$rc" == "0" ]] \
  || fail "10c. svg-text changed the exit code — it is a warning: $(cat "$TMP/out")"
grep -q "WARN \[svg-text\].*'alpha label here'.*'beta label here'" "$TMP/out" \
  || fail "10c. BL-310: two intersecting labels were not reported as a pair: $(cat "$TMP/out")"
grep -q "WARN \[svg-text\].*'runs off the right edge'.*viewBox" "$TMP/out" \
  || fail "10c. BL-310: a label leaving the viewBox was not reported: $(cat "$TMP/out")"
grep -q "WARN \[svg-text\].*'much too long for this box'.*wider than" "$TMP/out" \
  || fail "10c. BL-310: a label wider than its enclosing rect was not reported: $(cat "$TMP/out")"
grep -qE "WARN \[svg-text\].*'(left|right|rotated axis)" "$TMP/out" \
  && fail "10c. a well-placed or rotated label was reported — the estimate is too wide: $(cat "$TMP/out")"

# ---- 10c2. BL-411: a label that starts INSIDE its box and runs past its right
# edge. The real figure (a1-t2-figure.svg): three 10.5 px labels at x=342 in a
# 200 px rect at x=330, 208-219 px wide in Chrome, so 28-30 px past the edge on
# three pages the owner read. The check compared label WIDTH to rect WIDTH and
# never where the label sits, and the per-character table put r/t/f at 0.3 em,
# 8 % under the browser on this label set.
mkpage "$TMP/warn-svg-edge.html" "<div class=\"page\"><main class=\"main\">
<figure><svg viewBox=\"0 0 720 230\" role=\"img\" aria-label=\"probe\">
  <rect x=\"330\" y=\"88\" width=\"200\" height=\"56\" fill=\"none\" stroke=\"currentColor\"/>
  <g font-size=\"12\"><text x=\"342\" y=\"110\">subagente fresco, tools:[…]</text></g>
  <g font-size=\"10.5\"><text x=\"342\" y=\"128\">crea 14k (49k sin restringir); modelo barato</text></g>
</svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-edge.html")"
[[ "$rc" == "0" ]] || fail "10c2. svg-text changed the exit code: $(cat "$TMP/out")"
grep -q "WARN \[svg-text\].*'crea 14k (49k sin restringir); modelo barato'.*past the right edge" "$TMP/out" \
  || fail "10c2. BL-411: a label running past its box edge was not reported: $(cat "$TMP/out")"
grep -q "'subagente fresco, tools:\[…\]'" "$TMP/out" \
  && fail "10c2. a label that fits its box (156 px in 188) was reported: $(cat "$TMP/out")"

# ---- 10c3. BL-511: a figure drawn taller than a screen. A hand figure of a
# four-box chain (viewBox 360x600) made the reader scroll inside one drawing.
# Static, on the intrinsic viewBox height of the figure's ROOT svg: over 500 units
# warns. The 600- and 652-unit hand figures of the owner's page go over; so do
# engine figures that stack many boxes in one column (a 7-box `diagram` row forced
# `dir=tb` lays out 508 tall; unforced it wraps into rows since BL-515), which is why
# the advice names columns and layouts, not hand work.
mkpage "$TMP/warn-tall.html" "<div class=\"page\"><main class=\"main\">
<figure id=\"alta\"><svg viewBox=\"0 0 360 600\" role=\"img\" aria-label=\"tall\"><rect x=\"10\" y=\"10\" width=\"20\" height=\"20\" fill=\"none\" stroke=\"currentColor\"/></svg></figure>
<figure id=\"baja\"><svg viewBox=\"0 0 360 500\" role=\"img\" aria-label=\"short\"><rect x=\"10\" y=\"10\" width=\"20\" height=\"20\" fill=\"none\" stroke=\"currentColor\"/></svg></figure>
<figure id=\"n\"><svg viewBox=\"0 0 800 200\" role=\"img\" aria-label=\"nested\"><svg width=\"20\" height=\"20\" viewBox=\"0 0 10 900\"/></svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-tall.html")"
[[ "$rc" == "0" ]] || fail "10c3. figure-tall changed the exit code — it is a warning: $(cat "$TMP/out")"
grep -q "WARN \[figure-tall\].*alta.*600" "$TMP/out" \
  || fail "10c3. BL-511: a 600-unit-tall figure was not reported: $(cat "$TMP/out")"
grep -q "WARN \[figure-tall\].*baja" "$TMP/out" \
  && fail "10c3. a figure at the 500-unit threshold was reported: $(cat "$TMP/out")"
grep -q "WARN \[figure-tall\].*#n:" "$TMP/out" \
  && fail "10c3. a nested svg's viewBox (900) was judged as the figure's (200): $(cat "$TMP/out")"
# An engine figure: a 7-box `diagram` row, built by the real spec_build.py.
{ printf '::: masthead {eyebrow="x" byline="aidex"}\n# Siete cajas\n\nUna fila larga.\n:::\n\n'
  printf '::: diagram {#siete shape=row dir=tb title="Siete pasos"}\n'
  for i in 1 2 3 4 5 6 7; do printf 'b%d: Paso %d\n' "$i" "$i"; done
  for i in 1 2 3 4 5 6; do printf 'b%d -> b%d\n' "$i" "$((i + 1))"; done
  printf ':::\n'; } > "$TMP/siete.spec.md"
( cd "$TMP" && python3 "$SKILL/scripts/spec_build.py" "$TMP/siete.spec.md" -o "$TMP/siete.html" ) >/dev/null 2>&1 \
  || fail "10c3. spec_build failed on the 7-box diagram"
rc="$(run "$TMP/siete.html")"
grep -q "WARN \[figure-tall\].*#siete:.*fewer boxes per column, or a wider layout" "$TMP/out" \
  || fail "10c3. a 7-box diagram (508 units) did not warn with advice that fits an engine figure: $(cat "$TMP/out")"

# BL-620: the same verdict on a bare .svg file (root element <svg>), so the
# figure drawer's own gate run sees it. 1200x820 and 960x508 warn, 960x500 does not.
for dims in "1200 820" "960 508" "960 500"; do
  set -- $dims
  printf '<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-label="bare"><rect x="1" y="1" width="9" height="9"/></svg>\n' "$1" "$2" > "$TMP/bare-$2.svg"
done
# A UTF-8 BOM before the prolog is a valid deliverable (the embedder accepts it).
{ printf '\xef\xbb\xbf'; cat "$TMP/bare-820.svg"; } > "$TMP/bare-bom.svg"
grep -q "WARN \[figure-tall\].*820 units tall" <(bash "$CHECK" "$TMP/bare-bom.svg" 2>&1) \
  || fail "10c3. BL-620: a BOM-prefixed bare 1200x820 svg file got no figure-tall verdict"
grep -q "WARN \[figure-tall\].*820 units tall" <(bash "$CHECK" "$TMP/bare-820.svg" 2>&1) \
  || fail "10c3. BL-620: a bare 1200x820 svg file got no figure-tall verdict"
grep -q "WARN \[figure-tall\].*508 units tall" <(bash "$CHECK" "$TMP/bare-508.svg" 2>&1) \
  || fail "10c3. BL-620: a bare 960x508 svg file got no figure-tall verdict"
grep -q "WARN \[figure-tall\]" <(bash "$CHECK" "$TMP/bare-500.svg" 2>&1) \
  && fail "10c3. BL-620: a bare svg at the 500-unit cap was reported"

# ---- 10d. BL-330: an embedded <style> is a stylesheet in the PAGE, and the
# text nobody measured. Reported by the owner on a bench page: "los textos que
# están en un azul no se leen prácticamente". One figure's own
# `text { fill: #1F2937 }` was painting every <text> on the page, last-one-wins,
# and 26 of 26 figures measured below 4.5:1 in dark with every gate green — the
# contract read geometry and never colour.
mkpage "$TMP/warn-svgscope.html" "<div class=\"page\"><main class=\"main\">
<figure><svg id=\"fig-a\" viewBox=\"0 0 400 100\" role=\"img\" aria-label=\"a\">
  <style>text { fill: #1F2937; font-size: 12px } .lbl { font-weight: 600 } #fig-a rect { fill: none }</style>
  <text x=\"10\" y=\"40\">painted by a document selector</text>
</svg></figure>
<figure><svg id=\"fig-b\" viewBox=\"0 0 400 100\" role=\"img\" aria-label=\"b\">
  <style>#fig-b text { fill: currentColor; font-size: 12px }</style>
  <text x=\"10\" y=\"40\">scoped and legible</text>
</svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svgscope.html")"
# The leaking rule paints #1F2937 on every <text> in the document, which is
# 1.29:1 in dark — so since v15 this page FAILS, on `svg-contrast`. That is the
# defect caught end to end: before, the leak was advisory and the colour it
# produced was measured by nothing. What stays pinned here is that `svg-scope`
# ITSELF is still advisory — it reports the selector, it never fails the file.
[[ "$rc" == "1" ]] \
  || fail "10d. the leaking fill did not fail the page — v15 catches the colour the leak produces: $(cat "$TMP/out")"
grep -q "FAIL \[svg-scope\]" "$TMP/out" \
  && fail "10d. svg-scope became a violation — it reports the selector and stays a warning: $(cat "$TMP/out")"
grep -q "WARN \[svg-scope\].*text" "$TMP/out" \
  || fail "10d. BL-330: a bare element selector inside an SVG <style> was not reported: $(cat "$TMP/out")"
grep -q "WARN \[svg-scope\].*#fig-b" "$TMP/out" \
  && fail "10d. BL-330: an already-scoped selector was reported: $(cat "$TMP/out")"
grep -q "WARN \[svg-scope\].*\.lbl" "$TMP/out" \
  && fail "10d. BL-330: a class selector was reported — the rule is about ELEMENT selectors: $(cat "$TMP/out")"

# ---- 10a2. BL-375: a checkbox group whose options are each a distinct tracked
# id is several decisions drawn as one item. Reported by the owner on a live
# page: 'discard BL-010, BL-013 and BL-067?' as one checkbox group; every box was
# its own question with its own evidence, and the round was re-shaped into three
# radios. A checkbox group is for FACETS of one decision; a group of ids is a
# proxy for the wrong shape, and the rewrite (one radio item per id) clears it.
mkpage "$TMP/warn-independent.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Discard these?\">
  <h3>Discard these?</h3>
  <div class=\"opts\">
    <label><input type=\"checkbox\" name=\"Q1\" data-label=\"BL-010 stale premise\"><span>BL-010</span></label>
    <label><input data-label=\"BL-013 superseded\" name=\"Q1\" type=\"checkbox\"><span>BL-013</span></label>
    <label><input type=\"checkbox\" name=\"Q1\" data-label=\"BL-067 no owner\"><span>BL-067</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q2\" data-title=\"Which parts of the export?\">
  <h3>Which parts of the export?</h3>
  <div class=\"opts\">
    <label><input type=\"checkbox\" name=\"Q2\" data-label=\"Front-matter\"><span>Front-matter</span></label>
    <label><input type=\"checkbox\" name=\"Q2\" data-label=\"Body\"><span>Body</span></label>
    <label><input type=\"checkbox\" name=\"Q2\" data-label=\"Figures\"><span>Figures</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q3\" data-title=\"Discard BL-010?\">
  <h3>Discard BL-010?</h3>
  <div class=\"opts one\">
    <label><input type=\"radio\" name=\"Q3\" data-label=\"Discard BL-010\" data-recommended><span>Discard</span></label>
    <label><input type=\"radio\" name=\"Q3\" data-label=\"Keep BL-010\"><span>Keep</span></label>
  </div>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$TMP/warn-independent.html")"
[[ "$rc" == "0" ]] \
  || fail "10a2. a warning changed the exit code: $(cat "$TMP/out")"
grep -q 'WARN \[consult-independent\].*Q1' "$TMP/out" \
  || fail "10a2. BL-375: a checkbox group of distinct tracked ids was not reported: $(cat "$TMP/out")"
grep -q 'WARN \[consult-independent\].*Q2' "$TMP/out" \
  && fail "10a2. BL-375: a checkbox group of facets was reported — the proxy is distinct ids, not checkboxes: $(cat "$TMP/out")"
grep -q 'WARN \[consult-independent\].*Q3' "$TMP/out" \
  && fail "10a2. BL-375: the rewrite (one radio per id) was reported — it is what clears the warning: $(cat "$TMP/out")"

# ---- 10d2. BL-367: a leaked CLASS-headed descendant rule leaks exactly like a
# bare element one — `.note text { fill }` is a document stylesheet too — but the
# head test only looked at SVG_PAINTED, so it was never reported. Two exemptions
# keep the widening from flooding: a root class carrying a generator hash
# (d2's `.d2-<digits>`) is de-facto scoping, and generator class vocabulary
# (graphviz/mermaid `.node`, `.edge`, `.cluster`, `.actor`...) is pasted output,
# not a rule the author wrote. Measured 2026-09-08 over every page in .context/:
# the naive widening adds 648 warnings, the exemptions leave 8, all hand-written.
mkpage "$TMP/warn-svgscope-class.html" "<div class=\"page\"><main class=\"main\">
<figure><svg id=\"fig-c\" viewBox=\"0 0 400 100\" role=\"img\" aria-label=\"c\">
  <style>.caption text { fill: currentColor } #fig-c .callout text { fill: currentColor } .d2-3785483509 text { fill: currentColor } .node polygon { stroke: currentColor }</style>
  <g class=\"caption\"><text x=\"10\" y=\"40\">class-headed leak</text></g>
</svg></figure>
</main></div>
$composer"
run "$TMP/warn-svgscope-class.html" >/dev/null
grep -q "WARN \[svg-scope\].*'\.caption text'" "$TMP/out" \
  || fail "10d2. BL-367: a leaked class-headed descendant rule was not reported: $(cat "$TMP/out")"
grep -q "WARN \[svg-scope\].*#fig-c" "$TMP/out" \
  && fail "10d2. BL-367: the control — the same rule scoped to the figure id — was reported: $(cat "$TMP/out")"
grep -q "WARN \[svg-scope\].*\.d2-" "$TMP/out" \
  && fail "10d2. BL-367: a generator hash-class root was reported — it is de-facto scoping: $(cat "$TMP/out")"
grep -q "WARN \[svg-scope\].*\.node" "$TMP/out" \
  && fail "10d2. BL-367: generator class vocabulary was reported — pasted output is not a rule the author wrote: $(cat "$TMP/out")"

# ---- 10e. BL-330: figure text below 4.5:1, in EITHER theme, and the count it
# measured. A gate that silently measured nothing is green and indistinguishable
# from a gate that passed, so the finding line has to carry its own denominator.
mkpage "$TMP/warn-contrast.html" "<div class=\"page\"><main class=\"main\">
<figure><svg id=\"fig-c\" viewBox=\"0 0 400 200\" role=\"img\" aria-label=\"c\">
  <style>#fig-c text { font-size: 12px }</style>
  <text x=\"10\" y=\"40\" fill=\"#1F2937\">dark slate on the page ground</text>
  <rect x=\"0\" y=\"60\" width=\"400\" height=\"60\" fill=\"#FFFFFF\"/>
  <text x=\"10\" y=\"100\" fill=\"#E8E8E8\">pale grey on its own white box</text>
  <text x=\"10\" y=\"100\" fill=\"#191D1A\">ink on its own light box</text>
  <text x=\"10\" y=\"170\" fill=\"currentColor\">inherits the page ink</text>
</svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-contrast.html")"
# v15 (Q3): a named file FAILS on figure text below the floor. The census keeps
# the old severity, and the pair is pinned in 10g below.
[[ "$rc" == "1" ]] \
  || fail "10e. svg-contrast did not fail the wrap — since v15 a below-floor finding is a violation, not a warning: $(cat "$TMP/out")"
# #1F2937 is the reported case: fine on the light ground, 1.15 on the dark one.
grep -q "FAIL \[svg-contrast\].*'dark slate on the page ground'.*dark" "$TMP/out" \
  || fail "10e. BL-330: text that only fails in the dark theme was not reported: $(cat "$TMP/out")"
# A hard-coded box makes the pair theme-independent, so it fails in both.
grep -q "FAIL \[svg-contrast\].*'pale grey on its own white box'" "$TMP/out" \
  || fail "10e. BL-330: pale text on its own painted rect was not reported: $(cat "$TMP/out")"
# The escape hatch, and the one the bench page's fix actually used: a figure
# that draws the box its text sits on no longer depends on the theme.
grep -q "\[svg-contrast\].*'ink on its own light box'" "$TMP/out" \
  && fail "10e. BL-330: dark text on the light box the figure draws itself was reported: $(cat "$TMP/out")"
# currentColor is the OTHER right answer, and it is unmeasurable by design —
# reported as a count, never invented as a pass.
grep -q "\[svg-contrast\].*'inherits the page ink'" "$TMP/out" \
  && fail "10e. BL-330: a currentColor label was judged — the check must not invent the colour it cannot read: $(cat "$TMP/out")"
grep -qE "FAIL \[svg-contrast\].*measured 3 text node\(s\).*1 unmeasurable" "$TMP/out" \
  || fail "10e. BL-330: the finding does not carry its own denominator — a gate that saw nothing reads the same as one that passed: $(cat "$TMP/out")"

# ---- 10f. BL-330: the figure is judged against what it is PAINTED on, and on
# a real page that is an HTML wrapper, not an SVG rect. Measured on the bench
# page: 25 of 26 figures sit in `figure.cell.litebox .figbox { background:
# #F6F7F5 }`, and judging them against the page ground reported 12 figures where
# the browser found 9. Reading the wrapper brought it to 6 figures / 65 nodes
# against the browser's 61.
mkpage "$TMP/warn-figbox.html" "<style>figure.cell.litebox .figbox { background: #F6F7F5 }</style>
<div class=\"page\"><main class=\"main\">
<figure class=\"cell litebox\"><div class=\"figbox\"><svg id=\"fig-d\" viewBox=\"0 0 400 100\" role=\"img\" aria-label=\"d\">
  <style>#fig-d text { font-size: 12px }</style>
  <text x=\"10\" y=\"40\" fill=\"#1F2937\">dark slate on the light box</text>
</svg></div></figure>
<figure><svg id=\"fig-e\" viewBox=\"0 0 400 100\" role=\"img\" aria-label=\"e\">
  <style>#fig-e text { font-size: 12px }</style>
  <text x=\"10\" y=\"40\" fill=\"#1F2937\">the same slate on the page ground</text>
</svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-figbox.html")"
[[ "$rc" == "1" ]] || fail "10f. the bare-ground fill did not fail the wrap: $(cat "$TMP/out")"
grep -q "\[svg-contrast\].*'dark slate on the light box'" "$TMP/out" \
  && fail "10f. BL-330: text on the light box its wrapper paints was reported — the checker is not reading the wrapper: $(cat "$TMP/out")"
grep -q "FAIL \[svg-contrast\].*'the same slate on the page ground'" "$TMP/out" \
  || fail "10f. BL-330: the identical fill on the bare page ground was NOT reported — the wrapper lookup is over-applying: $(cat "$TMP/out")"

# ---- 10g. Q3: svg-contrast is the one check with TWO severities. It FAILS a
# named file (the wrap, where the author can still fix it) and only WARNS in
# `--census` (a page nobody is editing, where the finding is noise no one can
# clear). Before v15 it warned in both, and a warning that fired on 26 of 26
# figures on one page is a warning the reader learns to discount.
census_dir="$TMP/census-ctx/.context/reports"
mkdir -p "$census_dir"
cp "$TMP/warn-figbox.html" "$census_dir/drift.html"
cout="$TMP/census-out"
python3 "$SKILL/scripts/dash/check_artifact.py" --census "$TMP/census-ctx" > "$cout" 2>&1
crc=$?
[[ "$crc" == "0" ]] \
  || fail "10g. Q3: the census failed on a contrast finding — it must warn there, not fail: $(cat "$cout")"
grep -q "WARN \[svg-contrast\].*'the same slate on the page ground'" "$cout" \
  || fail "10g. Q3: the census dropped the contrast finding instead of warning it: $(cat "$cout")"
grep -q "FAIL \[svg-contrast\]" "$cout" \
  && fail "10g. Q3: the census reported the contrast finding as a violation: $(cat "$cout")"

# ---- 10h. BL-346: a rect inside a TEMPLATE container is never painted, so it is
# not a label's background. D2 and Graphviz put a knockout rect inside <mask>
# under every edge label so the edge line does not run through the glyphs; the
# checker read those as fill=black and reported 36 labels at 4.02:1 on the route
# bench page, 11 of which the browser measures as legible. <defs> was already
# skipped; its siblings mask, clipPath, pattern, symbol and marker were not.
# The figure sits in a litebox wrapper (10f) so the ground is light in BOTH
# themes and the ink below clears the floor on it. Every label is then the same
# ink on the same ground, and the only thing that varies is the wrapper of the
# rect beneath it — so a verdict that differs can only come from that wrapper.
mkpage "$TMP/warn-svg-template.html" "<style>figure.cell.litebox .figbox { background: #F6F7F5 }</style>
<div class=\"page\"><main class=\"main\">
<figure class=\"cell litebox\"><div class=\"figbox\"><svg id=\"fig-h\" viewBox=\"0 0 400 700\" role=\"img\" aria-label=\"h\">
  <style>#fig-h text { font-size: 12px }</style>
  <mask id=\"m-h\"><rect x=\"0\" y=\"20\" width=\"400\" height=\"40\" fill=\"#000000\"/></mask>
  <text x=\"10\" y=\"45\" fill=\"#191D1A\">knocked out by a mask</text>
  <clipPath id=\"c-h\"><rect x=\"0\" y=\"120\" width=\"400\" height=\"40\" fill=\"#000000\"/></clipPath>
  <text x=\"10\" y=\"145\" fill=\"#191D1A\">clipped not painted</text>
  <pattern id=\"p-h\" width=\"400\" height=\"40\"><rect x=\"0\" y=\"220\" width=\"400\" height=\"40\" fill=\"#000000\"/></pattern>
  <text x=\"10\" y=\"245\" fill=\"#191D1A\">a pattern tile is a template</text>
  <symbol id=\"s-h\"><rect x=\"0\" y=\"320\" width=\"400\" height=\"40\" fill=\"#000000\"/></symbol>
  <text x=\"10\" y=\"345\" fill=\"#191D1A\">a symbol is drawn by use</text>
  <marker id=\"a-h\"><rect x=\"0\" y=\"420\" width=\"400\" height=\"40\" fill=\"#000000\"/></marker>
  <text x=\"10\" y=\"445\" fill=\"#191D1A\">an arrowhead is not a backdrop</text>
  <g><rect x=\"0\" y=\"520\" width=\"400\" height=\"40\" fill=\"#000000\"/></g>
  <text x=\"10\" y=\"545\" fill=\"#191D1A\">really on a black rect</text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-template.html")"
# The MUTATION that keeps the five absences honest: the identical rect in a
# plain <g> under the sixth label. Same ink, same geometry, same page — if the
# skip over-applies, or the rect/label pairing stopped running at all, this one
# goes quiet too and the whole block would pass having proved nothing.
grep -q "FAIL \[svg-contrast\].*'really on a black rect'.*against the rect it sits on" "$TMP/out" \
  || fail "10h. BL-346: the control label on a rect in a plain <g> was NOT reported — the five absences below prove nothing: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "10h. BL-346: the control pair did not fail the wrap: $(cat "$TMP/out")"
for lbl in "knocked out by a mask" "clipped not painted" "a pattern tile is a template" \
           "a symbol is drawn by use" "an arrowhead is not a backdrop"; do
  grep -q "\[svg-contrast\].*'$lbl'" "$TMP/out" \
    && fail "10h. BL-346: '$lbl' was reported — the rect under it lives in a template container and is never painted: $(cat "$TMP/out")"
done
# And the labels are still SEEN. A fix that skipped the <text> as well, or one
# that stopped reading this figure at all, would clear every finding above and
# be indistinguishable from a correct one.
grep -qE "FAIL \[svg-contrast\].*measured 6 text node\(s\)" "$TMP/out" \
  || fail "10h. BL-346: the six labels were not all measured — the skip is dropping text, not just unpainted rects: $(cat "$TMP/out")"

# ---- 10i. BL-347: the glyphs live in the <tspan>, so that is where the fill is
# read. Mermaid's sequenceDiagram paints the actor RECT with `.actor{fill:#eee}`
# and the label inside it with `text.actor>tspan{fill:#333}`; the checker read
# the `.actor` rule off the enclosing <text> and reported all 10 actor labels on
# the route bench page at 1.04:1, where the browser measures 0 of 20 failing.
# The `.noteText>tspan{fill:#fff}` rule below is not decoration: it is the LAST
# tspan rule in mermaid's own stylesheet, so a fix that keys tspan fills flat on
# the element name would paint every label white and fail this fixture instead.
mkpage "$TMP/warn-svg-tspan.html" "<style>figure.cell.litebox .figbox { background: #F6F7F5 }</style>
<div class=\"page\"><main class=\"main\">
<figure class=\"cell litebox\"><div class=\"figbox\"><svg id=\"fig-i\" viewBox=\"0 0 400 500\" role=\"img\" aria-label=\"i\">
  <style>#fig-i text { font-size: 12px }
         #fig-i .actor { fill: #eee }
         #fig-i .dark { fill: #333 }
         #fig-i text.actor>tspan { fill: #333 }
         #fig-i .noteText,#fig-i .noteText>tspan { fill: #fff }
         #fig-i tspan.legend { fill: #ffffff }</style>
  <rect x=\"0\" y=\"20\" width=\"200\" height=\"40\" fill=\"#eaeaea\"/>
  <text class=\"actor\" x=\"10\" y=\"45\"><tspan x=\"10\" dy=\"0\">rule paints the tspan</tspan></text>
  <rect x=\"0\" y=\"120\" width=\"200\" height=\"40\" fill=\"#eaeaea\"/>
  <text class=\"actor\" x=\"10\" y=\"145\"><tspan x=\"10\" fill=\"#333333\">attribute paints the tspan</tspan></text>
  <rect x=\"0\" y=\"220\" width=\"200\" height=\"40\" fill=\"#eaeaea\"/>
  <text class=\"actor\" x=\"10\" y=\"245\"><tspan x=\"10\" fill=\"#eeeeee\">tspan repeats the pale fill</tspan></text>
  <rect x=\"0\" y=\"320\" width=\"200\" height=\"40\" fill=\"#eaeaea\"/>
  <text class=\"actor\" x=\"10\" y=\"345\">no tspan at all</text>
  <rect x=\"0\" y=\"420\" width=\"200\" height=\"40\" fill=\"#eaeaea\"/>
  <text class=\"dark\" x=\"10\" y=\"445\"><tspan x=\"10\">plain tspan inherits its text</tspan></text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-tspan.html")"
# The fix itself: a rule and an attribute on the tspan both override the <text>.
for lbl in "rule paints the tspan" "attribute paints the tspan"; do
  grep -q "\[svg-contrast\].*'$lbl'" "$TMP/out" \
    && fail "10i. BL-347: '$lbl' was reported — its glyphs are #333 on #eaeaea, the pale fill is on the <text> the browser never paints: $(cat "$TMP/out")"
done
# The MUTATION that keeps those two absences honest. Same figure, same rect,
# same classes; the only difference is that the tspan RE-DECLARES the pale fill,
# which the browser does paint. If the fix silences tspan labels — by skipping
# them, by marking them unreadable, or by dropping the pair — this goes quiet
# too and the block above would pass having proved nothing.
grep -q "FAIL \[svg-contrast\].*'tspan repeats the pale fill'.*against the rect it sits on" "$TMP/out" \
  || fail "10i. BL-347: the control label whose tspan re-declares #eee was NOT reported — the two absences above prove nothing: $(cat "$TMP/out")"
# And a <text> with no tspan still reads its own class rule.
grep -q "FAIL \[svg-contrast\].*'no tspan at all'.*against the rect it sits on" "$TMP/out" \
  || fail "10i. BL-347: the tspan-less label lost its own <text> fill: $(cat "$TMP/out")"
# The FLAT-KEY trap, from the other side. `#fig-i tspan.legend{fill:#fff}` is a
# rule the browser gives only to a tspan carrying that class; a fix that keys it
# on the bare element name hands it to EVERY tspan in the figure as the base
# fill, so this dark label — whose tspan declares nothing and simply inherits
# its <text> — comes out white on #eaeaea and is reported. The first cut of
# BL-347 did exactly that, matching `tspan.cls` and then discarding the class.
grep -q "\[svg-contrast\].*'plain tspan inherits its text'" "$TMP/out" \
  && fail "10i. BL-347: 'plain tspan inherits its text' was reported — a class-qualified tspan rule leaked onto a tspan that does not carry the class: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "10i. BL-347: the two control pairs did not fail the wrap: $(cat "$TMP/out")"
# All five labels are still MEASURED — a fix that resolved the tspan to
# something unreadable would clear the findings above and be
# indistinguishable from one that resolved it correctly.
grep -qE "FAIL \[svg-contrast\].*measured 5 text node\(s\).* 0 unmeasurable" "$TMP/out" \
  || fail "10i. BL-347: the five labels were not all measured as literal colours: $(cat "$TMP/out")"

# ---- 10j. BL-348: a fill rule is keyed on its WHOLE selector, and resolved by
# walking the node's ancestor chain. `svg_css_fills` used to keep only the leaf,
# so `#id .statediagram-note text{fill:#fff}` was stored under the bare key
# `text` and handed to every <text> in the figure, and a second rule with the
# same leaf silently replaced the first with no source-order or specificity
# model. That is wrong in BOTH directions, which is why it is worth fixing
# rather than tolerating: on the route bench page's `s4mermaid-fig-s4`, six
# rules end in `text`, only the last survived, and the checker reported 14
# labels while the browser census also reported 14 — a DIFFERENT 14.
mkpage "$TMP/warn-svg-chain.html" "<style>figure.cell.litebox .figbox { background: #F6F7F5 }</style>
<div class=\"page\"><main class=\"main\">
<figure class=\"cell litebox\"><div class=\"figbox\"><svg id=\"fig-j\" viewBox=\"0 0 400 500\" role=\"img\" aria-label=\"j\">
  <style>#fig-j text { font-size: 12px }
         #fig-j .box text { fill: #dddddd }
         #fig-j .tie text { fill: #111111 }
         #fig-j .tie text { fill: #dddddd }
         #fig-j .hdr text { fill: #111111 }</style>
  <g class=\"box\"><rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
    <text x=\"10\" y=\"45\">pale on pale reads its own subtree</text></g>
  <g class=\"hdr\"><rect x=\"0\" y=\"120\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
    <text x=\"10\" y=\"145\">dark heading stays legible</text></g>
  <g fill=\"#eeeeee\"><rect x=\"0\" y=\"220\" width=\"300\" height=\"40\" fill=\"#111111\"/>
    <text x=\"10\" y=\"245\">outside every scoped subtree</text></g>
  <g class=\"tie\"><rect x=\"0\" y=\"320\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
    <text x=\"10\" y=\"345\">the later rule of equal weight wins</text></g>
</svg></div></figure>
<figure class=\"cell litebox\"><div class=\"figbox\"><svg id=\"fig-k\" viewBox=\"0 0 400 200\" role=\"img\" aria-label=\"k\">
  <style>#fig-k text { font-size: 12px }
         #fig-k .pale { fill: #dddddd }
         #fig-k text { fill: #111111 }</style>
  <rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <text class=\"pale\" x=\"10\" y=\"45\">a class rule outweighs a later element rule</text>
  <rect x=\"0\" y=\"120\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <text x=\"10\" y=\"145\">and does not reach the label beside it</text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-chain.html")"
# DIRECTION 1 — the flat map INVENTS. `.box text`, `.tie text` and `.hdr text`
# all key on `text`; the last one wins and paints this label #111111, which on
# the #111111 rect under it reads 1.00:1. The browser matches none of the three
# — the label is in no such subtree — so it keeps the #eeeeee it inherits from
# its <g> and clears 16:1.
grep -q "\[svg-contrast\].*'outside every scoped subtree'" "$TMP/out" \
  && fail "10j. BL-348: 'outside every scoped subtree' was reported — a descendant rule was handed to a node outside its subtree: $(cat "$TMP/out")"
# DIRECTION 2 — the flat map SUPPRESSES, and this is the one that matters. The
# label's own rule is `#fig-j .box text{fill:#dddddd}`: #dddddd on #f0f0f0 is
# 1.13:1 and genuinely illegible. Under the flat map the later `.hdr text`
# overwrites the `text` key with #111111, so the checker measures 17:1 and says
# nothing. A checker that hides a real finding is worse than one that is noisy.
grep -q "FAIL \[svg-contrast\].*'pale on pale reads its own subtree'.*against the rect it sits on" "$TMP/out" \
  || fail "10j. BL-348: the pale label inside .box was NOT reported — a later rule with the same leaf overwrote its own: $(cat "$TMP/out")"
# SOURCE ORDER breaks a tie between two rules of equal weight: `.tie text` is
# declared #111111 and then #dddddd, and the browser paints the second.
grep -q "FAIL \[svg-contrast\].*'the later rule of equal weight wins'.*against the rect it sits on" "$TMP/out" \
  || fail "10j. BL-348: the .tie label did not take the LATER of two equal-weight rules: $(cat "$TMP/out")"
# The control that keeps direction 1's absence honest in the other axis: a label
# that IS inside `.hdr` still takes that rule, so the scoping did not simply
# stop applying descendant rules altogether.
grep -q "\[svg-contrast\].*'dark heading stays legible'" "$TMP/out" \
  && fail "10j. BL-348: the .hdr label was reported — its own descendant rule stopped resolving: $(cat "$TMP/out")"
# PINNED, and green before this change: specificity outranks source order, so a
# class rule beats an element rule declared after it…
grep -q "FAIL \[svg-contrast\].*'a class rule outweighs a later element rule'.*against the rect it sits on" "$TMP/out" \
  || fail "10j. BL-348: the .pale label lost its class rule to a later element rule: $(cat "$TMP/out")"
# …and does not reach the label beside it, which keeps the element rule.
grep -q "\[svg-contrast\].*'and does not reach the label beside it'" "$TMP/out" \
  && fail "10j. BL-348: the unclassed label took the .pale class rule: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "10j. BL-348: the three control pairs did not fail the wrap: $(cat "$TMP/out")"
# The MUTATION that keeps the three absences honest. Every label in both figures
# resolves to a literal colour: a fix that answered the two absences by dropping
# those labels, or by marking them unreadable, would clear them and be
# indistinguishable from one that resolved the chain correctly.
grep -qE "FAIL \[svg-contrast\].*measured 6 text node\(s\).* 0 unmeasurable" "$TMP/out" \
  || fail "10j. BL-348: the six labels were not all measured as literal colours: $(cat "$TMP/out")"


# ---- 10k. BL-357: a CSS comment before a rule must not swallow the rule.
# SVG_CSS_RULE hands group(1) everything between the previous `}` and this `{`,
# so a `/* ... */` sitting in front of a selector travels WITH it. `/*` fails
# SVG_COMPOUND, svg_parse_selector returns None, and the whole rule is
# discarded — the suppressing direction again: the label keeps whatever it
# inherits and a genuine contrast failure goes unreported. A comment is not a
# selector, and stripping it is not widening the parser.
# The page-level style block carries a leading comment too: svg_page_backgrounds
# reads SVG_CSS_RULE the same way, and losing this rule would silently move the
# ground every label below is judged against.
mkpage "$TMP/warn-svg-comment.html" "<style>/* the light figure ground */ figure.cell.litebox .figbox { background: #F6F7F5 }</style>
<div class=\"page\"><main class=\"main\">
<figure class=\"cell litebox\"><div class=\"figbox\"><svg id=\"fig-l\" viewBox=\"0 0 400 300\" role=\"img\" aria-label=\"l\">
  <style>#fig-l text { font-size: 12px }
         /* the note labels, kept pale on purpose */
         #fig-l .note text { fill: #dddddd }
         #fig-l .hdr text { fill: #111111 } /* trailing comment, same line */
         #fig-l .tail text { fill: #dddddd }</style>
  <g class=\"note\"><rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
    <text x=\"10\" y=\"45\">pale rule behind a comment</text></g>
  <g class=\"hdr\"><rect x=\"0\" y=\"120\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
    <text x=\"10\" y=\"145\">dark rule before a trailing comment</text></g>
  <g class=\"tail\"><rect x=\"0\" y=\"220\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
    <text x=\"10\" y=\"245\">pale rule after a trailing comment</text></g>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-comment.html")"
# THE DEFECT, direction 1: the rule sitting behind a leading comment is the
# label's own, #dddddd on #f0f0f0 is 1.13:1, and dropping the rule hides it.
grep -q "FAIL \[svg-contrast\].*'pale rule behind a comment'.*against the rect it sits on" "$TMP/out" \
  || fail "10k. BL-357: the label whose fill rule sits behind a leading CSS comment was NOT reported — the comment swallowed the rule: $(cat "$TMP/out")"
# Direction 2: a comment CLOSING on the previous line leaks into the NEXT
# selector the same way. `.tail text` follows `... } /* ... */` and is the rule
# most likely to be lost by a naive `^\s*/\*` strip.
grep -q "FAIL \[svg-contrast\].*'pale rule after a trailing comment'.*against the rect it sits on" "$TMP/out" \
  || fail "10k. BL-357: the label whose rule follows a trailing comment was NOT reported: $(cat "$TMP/out")"
# The control in the other axis: a rule that is FOLLOWED by a comment on its own
# line still applies, so the strip did not eat the rule it was meant to save.
grep -q "\[svg-contrast\].*'dark rule before a trailing comment'" "$TMP/out" \
  && fail "10k. BL-357: the dark heading was reported — stripping the comment lost its own rule: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "10k. BL-357: the two control pairs did not fail the wrap: $(cat "$TMP/out")"
# The MUTATION that keeps the absence honest: all three labels resolve to a
# literal colour. A fix that dropped them, or marked them unreadable, would
# clear the finding above and look identical from the outside.
grep -qE "FAIL \[svg-contrast\].*measured 3 text node\(s\).* 0 unmeasurable" "$TMP/out" \
  || fail "10k. BL-357: the three labels were not all measured as literal colours: $(cat "$TMP/out")"


# ---- 10l. BL-358: a selector compound naming the <svg> ROOT must match.
# svg_geometry is handed the svg BODY and started its ancestor chain empty, so
# the <svg> element itself was never in it. svg_parse_selector strips only a
# bare `#id` compound; a root compound spelled as a TAG (`svg text`) or as a
# CLASS (`.d2-77 .fill-N1` — the shape d2 and mermaid actually emit) survived
# parsing and was then matched against a chain that could not contain it, so
# the rule never applied. Suppressing direction again: the label keeps what it
# inherits and a real contrast failure goes unreported.
mkpage "$TMP/warn-svg-root.html" "<div class=\"page\"><main class=\"main\">
<figure class=\"cell\"><div class=\"figbox\"><svg id=\"fig-d\" class=\"d2-77\" viewBox=\"0 0 400 300\" role=\"img\" aria-label=\"d\">
  <style>#fig-d text { font-size: 12px }
         svg .viatag { fill: #dddddd }
         .d2-77 .fill-N1 { fill: #dddddd }
         #fig-d .ctrl { fill: #111111 }</style>
  <rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <text class=\"viatag\" x=\"10\" y=\"45\">root named as a tag</text>
  <rect x=\"0\" y=\"120\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <text class=\"fill-N1\" x=\"10\" y=\"145\">root named as a class</text>
  <rect x=\"0\" y=\"220\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <text class=\"ctrl\" x=\"10\" y=\"245\">no root compound at all</text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-root.html")"
# THE DEFECT, spelling 1: `svg .viatag`. #dddddd on #f0f0f0 is 1.13:1.
grep -q "FAIL \[svg-contrast\].*'root named as a tag'.*against the rect it sits on" "$TMP/out" \
  || fail "10l. BL-358: the label whose rule names the root as a TAG was NOT reported — the root is missing from the ancestor chain: $(cat "$TMP/out")"
# Spelling 2: the root as a CLASS, which is what d2 and mermaid emit.
grep -q "FAIL \[svg-contrast\].*'root named as a class'.*against the rect it sits on" "$TMP/out" \
  || fail "10l. BL-358: the label whose rule names the root as a CLASS was NOT reported: $(cat "$TMP/out")"
# The control in the other axis: a selector with no root compound still matches,
# so seeding the chain with the root did not shift what an ordinary rule hits.
grep -q "\[svg-contrast\].*'no root compound at all'" "$TMP/out" \
  && fail "10l. BL-358: the dark control label was reported — seeding the root broke ordinary matching: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "10l. BL-358: the two root-compound pairs did not fail the wrap: $(cat "$TMP/out")"
# The MUTATION that keeps the absence honest: all three labels resolve to a
# literal colour, so a fix that answered the finding by marking them unreadable
# fails here instead of passing.
grep -qE "FAIL \[svg-contrast\].*measured 3 text node\(s\).* 0 unmeasurable" "$TMP/out" \
  || fail "10l. BL-358: the three labels were not all measured as literal colours: $(cat "$TMP/out")"


# ---- 10m. BL-353: a nested <tspan> inherits from the RUN above it, not the <text>.
# svg_geometry pushes each open <tspan> with the fill DECLARED on it, and a run
# that declares nothing fell back to the enclosing <text>'s fill — skipping the
# nearest enclosing tspan that does declare one. So a label whose outer run is
# pale and whose inner run merely inherits it resolved to two different colours,
# collapsed to SVG_UNREADABLE, and went UNMEASURED: the browser paints both runs
# the same colour and the contrast failure was never reported. Conservative, so
# BL-347 shipped without it, but it still costs a real measurement.
mkpage "$TMP/warn-svg-tspan.html" "<div class=\"page\"><main class=\"main\">
<figure class=\"cell\"><div class=\"figbox\"><svg id=\"fig-t\" viewBox=\"0 0 400 300\" role=\"img\" aria-label=\"t\">
  <style>#fig-t text { font-size: 12px }
         #fig-t .actor { fill: #111111 }</style>
  <rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <text class=\"actor\" x=\"10\" y=\"45\"><tspan fill=\"#dddddd\">outer run<tspan> inner run</tspan></tspan></text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-tspan.html")"
# THE DEFECT: both runs are painted #dddddd on #f0f0f0 (1.13:1). The inner run
# inheriting #111111 from the <text> instead split the label in two.
grep -q "FAIL \[svg-contrast\].*'outer run inner run'.*against the rect it sits on" "$TMP/out" \
  || fail "10m. BL-353: the label whose inner <tspan> inherits from the outer run was NOT reported: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "10m. BL-353: the nested-tspan pair did not fail the wrap: $(cat "$TMP/out")"
# The MUTATION that makes the fix load-bearing rather than merely quiet: the
# label must be MEASURED, not silently dropped. Before the fix it was counted
# unmeasurable, which is the shape a lazy fix would restore.
grep -qE "FAIL \[svg-contrast\].*measured 1 text node\(s\).* 0 unmeasurable" "$TMP/out" \
  || fail "10m. BL-353: the nested label was not measured as ONE literal colour: $(cat "$TMP/out")"

# The control in the other axis: an inner run that declares its OWN fill keeps
# it, and two runs that genuinely disagree still collapse to unmeasurable —
# inheriting from the run above must not become "the outer run always wins".
mkpage "$TMP/warn-svg-tspan-own.html" "<div class=\"page\"><main class=\"main\">
<figure class=\"cell\"><div class=\"figbox\"><svg id=\"fig-t2\" viewBox=\"0 0 400 300\" role=\"img\" aria-label=\"t2\">
  <style>#fig-t2 text { font-size: 12px }</style>
  <rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <text x=\"10\" y=\"45\"><tspan fill=\"#dddddd\">pale run<tspan fill=\"#111111\"> dark run</tspan></tspan></text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-tspan-own.html")"
grep -qE "\[svg-contrast\].*measured 0 text node\(s\).* 1 unmeasurable" "$TMP/out" \
  || fail "10m. BL-353: two runs declaring different fills were not left unmeasurable — the inner run's own declaration was overridden by the one above it: $(cat "$TMP/out")"

# ---- 10n. BL-355: a mermaid figure's root `#id{fill:...}` is the only fill many
# of its labels ever get. Every mermaid <style> opens with one. The compound is
# nothing but an id, so svg_parse_selector dropped it entirely and the rule
# matched nothing; the labels that only inherit it were counted unmeasurable —
# 5 of them in one figure of the route bench, and the same shape in all four.
# Same family as BL-358 (the root missing from the chain) but the other half:
# there the compound could not match, here the rule never survived parsing, and
# what it paints is INHERITED down rather than matched on the label.
mkpage "$TMP/warn-svg-rootid.html" "<div class=\"page\"><main class=\"main\">
<figure class=\"cell\"><div class=\"figbox\"><svg id=\"fig-m\" viewBox=\"0 0 400 300\" role=\"img\" aria-label=\"m\">
  <style>#fig-m{font-family:sans-serif;fill:#dddddd;}
         #fig-m text { font-size: 12px }
         #fig-m .own { fill: #111111 }</style>
  <rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <g><text x=\"10\" y=\"45\">inherits the root rule</text></g>
  <rect x=\"0\" y=\"120\" width=\"300\" height=\"40\" fill=\"#f0f0f0\"/>
  <g><text class=\"own\" x=\"10\" y=\"145\">has its own rule</text></g>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-rootid.html")"
# THE DEFECT: #dddddd on #f0f0f0 is 1.13:1, and the label gets that colour from
# the root rule alone — through a <g> that declares nothing.
grep -q "FAIL \[svg-contrast\].*'inherits the root rule'.*against the rect it sits on" "$TMP/out" \
  || fail "10n. BL-355: the label inheriting the figure's root #id fill was NOT reported — the root-only compound never survived parsing: $(cat "$TMP/out")"
# The control in the other axis: a label with its OWN rule keeps it, so seeding
# the figure's inherited fill did not overwrite what the cascade already said.
grep -q "\[svg-contrast\].*'has its own rule'" "$TMP/out" \
  && fail "10n. BL-355: the label carrying its own fill rule was reported — the root seed overrode the cascade: $(cat "$TMP/out")"
[[ "$rc" == "1" ]] \
  || fail "10n. BL-355: the root-inherited pair did not fail the wrap: $(cat "$TMP/out")"
# The MUTATION that keeps the absence honest: BOTH labels resolve to a literal
# colour. Before the fix the first was unmeasurable, which is what a fix that
# merely silenced the pair would restore.
grep -qE "FAIL \[svg-contrast\].*measured 2 text node\(s\).* 0 unmeasurable" "$TMP/out" \
  || fail "10n. BL-355: the two labels were not both measured as literal colours: $(cat "$TMP/out")"

# ---- 10o. LOOP-006: an oklch() rect is a literal colour, and the label is judged
# against it. The parser read only hex, rgb() and a few names, so an oklch() box
# was skipped and white text drawn on a dark oklch() box was judged against the
# light page ground: a false FAIL on a pair the browser shows at ~9:1. The light
# box is the control in the other direction: parsing must measure, not excuse.
mkpage "$TMP/svg-oklch.html" "<div class=\"page\"><main class=\"main\">
<figure><svg id=\"fig-o\" viewBox=\"0 0 400 200\" role=\"img\" aria-label=\"o\">
  <style>#fig-o text { font-size: 12px }</style>
  <rect x=\"0\" y=\"20\" width=\"300\" height=\"40\" fill=\"oklch(0.35 0.08 160)\"/>
  <text x=\"10\" y=\"45\" fill=\"#FFFFFF\">white on a dark oklch box</text>
  <rect x=\"0\" y=\"120\" width=\"300\" height=\"40\" fill=\"oklch(93% 0.01 130deg)\"/>
  <text x=\"10\" y=\"145\" fill=\"#FFFFFF\">white on a light oklch box</text>
</svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/svg-oklch.html")"
grep -q "\[svg-contrast\].*'white on a dark oklch box'" "$TMP/out" \
  && fail "10o. white text on a dark oklch() rect was reported — the rect's colour was not read: $(cat "$TMP/out")"
grep -q "FAIL \[svg-contrast\].*'white on a light oklch box'.*against the rect it sits on" "$TMP/out" \
  || fail "10o. white text on a light oklch() rect was not reported against that rect: $(cat "$TMP/out")"
# ...and an oklch() BACKGROUND on the figure's wrapper is the box the label sits
# on, exactly as a hex one is (10f): dark slate on a light oklch wrapper passes.
mkpage "$TMP/svg-oklch-bg.html" "<style>figure.cell .okbox { background: oklch(0.97 0.01 130) }</style>
<div class=\"page\"><main class=\"main\">
<figure class=\"cell\"><div class=\"okbox\"><svg id=\"fig-ob\" viewBox=\"0 0 400 100\" role=\"img\" aria-label=\"ob\">
  <style>#fig-ob text { font-size: 12px }</style>
  <text x=\"10\" y=\"40\" fill=\"#1F2937\">dark slate on a light oklch wrapper</text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/svg-oklch-bg.html")"
grep -q "\[svg-contrast\].*'dark slate on a light oklch wrapper'" "$TMP/out" \
  && fail "10o. an oklch() wrapper background was not read, so the label was judged on the page ground: $(cat "$TMP/out")"
# ...and with a trailing `!important`, which the whole-value parse read as part
# of the colour, so the wrapper was skipped again (review, LOOP-006).
mkpage "$TMP/svg-oklch-imp.html" "<style>figure.cell .okbox { background: oklch(0.2 0.02 250) !important }</style>
<div class=\"page\"><main class=\"main\">
<figure class=\"cell\"><div class=\"okbox\"><svg id=\"fig-oi\" viewBox=\"0 0 400 100\" role=\"img\" aria-label=\"oi\">
  <style>#fig-oi text { font-size: 12px }</style>
  <text x=\"10\" y=\"40\" fill=\"#FFFFFF\">white on a dark oklch wrapper marked important</text>
</svg></div></figure>
</main></div>
$composer"
rc="$(run "$TMP/svg-oklch-imp.html")"
grep -q "\[svg-contrast\].*'white on a dark oklch wrapper marked important'" "$TMP/out" \
  && fail "10o. an oklch() !important wrapper background was not read, so the label was judged on the page ground: $(cat "$TMP/out")"
python3 - "$SKILL/scripts/dash" <<'PY' || fail "10o. oklch() does not convert to the sRGB the browser paints"
import sys; sys.path.insert(0, sys.argv[1]); import check_artifact as ca
# Reference values: what Chromium paints on a canvas for each (±1 per channel);
# the last is out of the sRGB gamut and Chromium clips it per channel.
for src, want in (("oklch(0.35 0.08 160)", (0, 71, 44)),
                  ("oklch(93% 0.01 130deg)", (230, 233, 226)),
                  ("oklch(0.5 0.4 264)", (21, 0, 255)),
                  ("oklch(1 0 0)", (255, 255, 255)), ("oklch(0 0 0)", (0, 0, 0)),
                  ("oklch(0.628 0.2577 29.23)", (255, 0, 0)),
                  ("oklch(62.8% 64.4% 29.23deg / 0.5)", (255, 0, 0))):
    got = ca.svg_literal_colour(src)
    assert got and all(abs(g - w) <= 1 for g, w in zip(got, want)), (src, got, want)
# Malformed numbers are not a colour: None (unmeasured), never an exception.
for src in ("oklch(0.5. 0.1 30)", "oklch(. 0.1 30)", "oklch(0.5 0.1 3.0.0)"):
    got = ca.svg_literal_colour(src)
    assert got is None, (src, got)
PY



# The first cut read every label without a font-size attribute as 16 px and
# reported collisions on 13 of 60 field pages; measured in Chrome, the pages
# set the size in a CSS class and the labels never touched. A class rule is
# the size; a label with no attribute and no rule is skipped, not guessed.
mkpage "$TMP/warn-svg-css.html" "<style>.lbl{font:400 10px system-ui} .mono{font-family:ui-monospace,monospace}</style>
<div class=\"page\"><main class=\"main\">
<figure><svg viewBox=\"0 0 960 200\" role=\"img\" aria-label=\"probe\">
  <text class=\"lbl\" x=\"100\" y=\"40\">ten pixel label</text>
  <text class=\"lbl\" x=\"185\" y=\"40\">its neighbour</text>
  <text x=\"100\" y=\"80\">unsized label one</text>
  <text x=\"150\" y=\"80\">unsized label two</text>
  <text class=\"lbl mono\" x=\"100\" y=\"120\">MONO_LABEL_WIDE</text>
  <text class=\"lbl\" x=\"185\" y=\"120\">after the mono</text>
</svg></figure>
</main></div>
$composer"
rc="$(run "$TMP/warn-svg-css.html")"
[[ "$rc" == "0" ]] || fail "10c. css fixture failed the contract: $(cat "$TMP/out")"
grep -q "WARN \[svg-text\].*'ten pixel label'" "$TMP/out" \
  && fail "10c. a 10 px class-sized label was measured at the 16 px default: $(cat "$TMP/out")"
grep -q "WARN \[svg-text\].*'unsized label" "$TMP/out" \
  && fail "10c. a label with no size anywhere was guessed instead of skipped: $(cat "$TMP/out")"
grep -q "WARN \[svg-text\].*'MONO_LABEL_WIDE'.*'after the mono'" "$TMP/out" \
  || fail "10c. a monospace label was measured proportionally and its collision missed: $(cat "$TMP/out")"

# ...and warnings stay out of --census, where nobody can clear them.
mkdir -p "$TMP/census/.context/reports"
cp "$TMP/warn-opts.html" "$TMP/census/.context/reports/w.html"
bash "$CHECK" --census "$TMP/census" > "$TMP/out" 2>&1
grep -q 'WARN' "$TMP/out" \
  && fail "10. --census printed a warning — noise on a page nobody is editing: $(cat "$TMP/out")"

# ---- 11. a [show-me] ask is answered with a visual, not prose (BL-475/BL-504) --
# The reader's marks live in browser storage and in the paste, never on disk, so
# the round's reply is saved verbatim beside the baseline and the check reads it —
# against `.answered.html` (save-reply.sh's fixed snapshot of what the reader saw),
# never against the moving `.aidex-artifact-prev/<page>.html` contract baseline,
# which is advanced on every passing wrap. Found on dashboard_template_ws's
# 2026-09-27 barrida page: items marked [show-me] came back as prose rewrites and
# the page passed because that moving baseline had already been overwritten by an
# earlier re-wrap inside the same round.
R="$TMP/rounds"; mkdir -p "$R/.aidex-artifact-prev"
showitem() {  # $1 = extra markup inside Q1
  mkpage "$2" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"The first claim\">
  <h3>Q1</h3><p>What happens today, explained again.</p>$1<p class=fieldlabel>Free text</p><textarea></textarea></section>
<section class=\"consult-item\" data-id=\"Q2\" data-free data-title=\"The second claim\">
  <h3>Q2</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
$gclose
$notesitem
$bars
$composer"
}
# The ANSWERED snapshot is the page the reader saw — the baseline plays no part
# in this check any more, so it is written here too but never read by it.
showitem '' "$R/.aidex-artifact-prev/page.html"
showitem '' "$R/.aidex-artifact-prev/page.answered.html"
cat > "$R/.aidex-artifact-prev/page.reply.md" <<'MD'
## G1 · The context
### Q1 · The first claim

- [show-me]

no entiendo qué cambia
### Q2 · The second claim

- Yes

it says [show-me] in prose, which is not an ask
MD

showitem '' "$R/page.html"
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] || fail "11a. a [show-me] item rewritten as prose passed: $(cat "$TMP/out")"
grep -q 'FAIL \[consult-marker-duties\].*Q1' "$TMP/out" || fail "11a. the failure does not name the item: $(cat "$TMP/out")"
grep -q 'FAIL \[consult-marker-duties\].*Q2' "$TMP/out" && fail "11a. [show-me] typed in the notes was read as an ask: $(cat "$TMP/out")"

showitem '<figure><svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg></figure>' "$R/page.html"
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] || fail "11b. a [show-me] item answered with a figure failed: $(cat "$TMP/out")"

# 11c. BL-504: the moving baseline is overwritten — as a real wrap would do —
# and the check still fails, because it is keyed to .answered.html, not to it.
showitem '' "$R/.aidex-artifact-prev/page.html"
showitem '' "$R/page.html"
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] || fail "11c. BL-504: a second wrap, after the moving baseline advanced, was no longer enforced: $(cat "$TMP/out")"
grep -q 'FAIL \[consult-marker-duties\].*Q1' "$TMP/out" || fail "11c. the failure does not name the item after the baseline moved: $(cat "$TMP/out")"

# 11d. with no reply/answered snapshot ever saved, the check cannot run at all —
# WARN, not a silent pass, and not a FAIL either (there is nothing to compare).
rm "$R/.aidex-artifact-prev/page.reply.md" "$R/.aidex-artifact-prev/page.answered.html"
showitem '' "$R/page.html"
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] || fail "11d. a page that was never answered failed the wrap: $(cat "$TMP/out")"
grep -q 'WARN \[consult-marker-duties\]' "$TMP/out" || fail "11d. a page with no saved reply said nothing: $(cat "$TMP/out")"

# 11e. BL-504 restores this row explicitly: a reply saved for round N, with
# no NEWER reply since, does not expire — there is no mtime test any more
# (the old check_show_me had one; check_marker_duties never reads a
# timestamp at all). An old `reply.md`/`answered.html`, however old on
# disk, is enforced exactly the same as a freshly-saved one, for as long as
# nothing newer replaces it. A hard "a new round needs its own saved reply"
# gate is a SEPARATE, harder property (BL-507, not implemented here — see
# 02-local-first-artifacts.md).
showitem '' "$R/.aidex-artifact-prev/page.html"
showitem '' "$R/.aidex-artifact-prev/page.answered.html"
cat > "$R/.aidex-artifact-prev/page.reply.md" <<'MD'
### Q1 · The first claim

- [show-me]

no entiendo qué cambia
MD
touch -t 202001010000 "$R/.aidex-artifact-prev/page.reply.md" \
                      "$R/.aidex-artifact-prev/page.answered.html"
showitem '' "$R/page.html"                    # still no figure on Q1
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] || fail "11e. a reply from 2020, with nothing newer, was NOT enforced: $(cat "$TMP/out")"
grep -q 'FAIL \[consult-marker-duties\].*Q1' "$TMP/out" \
  || fail "11e. the stale-but-only reply's failure does not name the item: $(cat "$TMP/out")"

# ---- 12. BL-701: free text at three levels, each with a visible label -------
# One compliant page, then one mutation per level. The block box and the labels
# are judged on the markup, so a commented-out box or a placeholder-only box
# must not satisfy them.
q1='<section class="consult-item" data-id="Q1" data-title="Pick one"><h3>Pick one</h3><div class="opts"><label><input type="radio" name="Q1" data-label="A"><span>A</span></label><label><input type="radio" name="Q1" data-label="B"><span>B</span></label></div><p class="fieldlabel">Notes on this one</p><textarea></textarea></section>'
q1nolabel="$(printf '%s' "$q1" | sed 's|<p class="fieldlabel">Notes on this one</p>||')"
bl701() {  # bl701 <name> <block box> <item html> <page notes html>; echoes the exit code
  mkpage "$TMP/$1.html" "$visual
$gopen
$3
$2
</section>
$4
$bars
$composer"
  run "$TMP/$1.html"
}
rc="$(bl701 t3-ok "$gnotes" "$q1" "$notesitem")"
[[ "$rc" == "0" ]] || fail "12. the three-level page failed: $(cat "$TMP/out")"
rc="$(bl701 t3-nogroup "" "$q1" "$notesitem")"
[[ "$rc" == "1" ]] && grep -q "block 'G1' has no notes box" "$TMP/out" \
  || fail "12. a block with no notes box of its own passed (rc=$rc): $(cat "$TMP/out")"
rc="$(bl701 t3-commented "<!-- $gnotes -->" "$q1" "$notesitem")"
[[ "$rc" == "1" ]] && grep -q "block 'G1' has no notes box" "$TMP/out" \
  || fail "12. a COMMENTED-OUT block notes box satisfied the check (rc=$rc): $(cat "$TMP/out")"
rc="$(bl701 t3-grouplabel '<div class="group-notes"><textarea placeholder="Notes on this block"></textarea></div>' "$q1" "$notesitem")"
[[ "$rc" == "1" ]] && grep -q "block 'G1': its notes box has no visible label" "$TMP/out" \
  || fail "12. a block notes box with only a placeholder passed (rc=$rc): $(cat "$TMP/out")"
rc="$(bl701 t3-itemlabel "$gnotes" "$q1nolabel" "$notesitem")"
[[ "$rc" == "1" ]] && grep -q "item 'Q1': its notes box has no visible label" "$TMP/out" \
  || fail "12. an item notes box with no visible label passed (rc=$rc): $(cat "$TMP/out")"
q1sel='<section class="consult-item" data-id="Q1" data-title="T"><h3>T</h3><p class="fieldlabel">The choice</p><select><option>A</option><option>B</option></select><textarea></textarea></section>'
rc="$(bl701 t3-labelbefore "$gnotes" "$q1sel" "$notesitem")"
[[ "$rc" == "1" ]] && grep -q "item 'Q1': its notes box has no visible label" "$TMP/out" \
  || fail "12. a label that names the select above, not the notes box, satisfied the item label rule (rc=$rc): $(cat "$TMP/out")"
# A gallery-shaped item: label, notes box, then the hidden kit-marks channel. The channel is not the notes box.
q1marks="${q1%</section>}<textarea class=\"kit-marks\" hidden></textarea></section>"
rc="$(bl701 t3-marks "$gnotes" "$q1marks" "$notesitem")"
[[ "$rc" == "0" ]] \
  || fail "12. an item with a label, its notes box and a hidden kit-marks textarea was rejected (rc=$rc): $(cat "$TMP/out")"
# A page that does not exist fails with the `missing` finding; --prev must not crash on opening it.
rc="$(run "$TMP/does-not-exist.html" --prev "$TMP/t3-ok.html")"
[[ "$rc" == "1" ]] && grep -q "FAIL \[missing\]" "$TMP/out" && ! grep -q "Traceback" "$TMP/out" \
  || fail "12. a missing page with --prev crashed or did not fail clearly (rc=$rc): $(cat "$TMP/out")"
rc="$(bl701 t3-pagelabel "$gnotes" "$q1" '<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><textarea placeholder="Notes for the whole page"></textarea></section>')"
[[ "$rc" == "1" ]] && grep -q "the general-notes item: its notes box has no visible label" "$TMP/out" \
  || fail "12. a page notes box with only a placeholder passed (rc=$rc): $(cat "$TMP/out")"

# BL-706: a visible label is not a name. The box passes the visible-label rule and
# still fails when nothing ties the label to the textarea (a screen reader would
# announce an unnamed text field). The fixtures below go through the raw writer, so
# the mutation strips the link the helper added.
rc="$(bl701 t3-unlinked-ok "$gnotes" "$q1" "$notesitem")"
[[ "$rc" == "0" ]] || fail "12b. the linked three-level page failed: $(cat "$TMP/out")"
grep -q 'aria-labelledby="fl-' "$TMP/t3-unlinked-ok.html" \
  || fail "12b. the fixture helper stopped linking labels, so the mutations below prove nothing"
sed -E 's/ aria-labelledby="[^"]*"//' "$TMP/t3-unlinked-ok.html" > "$TMP/t3-unlinked-all.html"
rc="$(run "$TMP/t3-unlinked-all.html")"
[[ "$rc" == "1" ]] && grep -q "item 'Q1': its notes box has a visible label but no accessible name" "$TMP/out" \
  && grep -q "block 'G1': its notes box has a visible label but no accessible name" "$TMP/out" \
  && grep -q "the general-notes item: its notes box has a visible label but no accessible name" "$TMP/out" \
  || fail "12b. a notes box whose label is not programmatically linked passed (rc=$rc): $(cat "$TMP/out")"
# An aria-labelledby that names an id nothing on the page carries is not a name either.
sed -E 's/aria-labelledby="fl-[0-9]+"/aria-labelledby="nowhere"/' "$TMP/t3-unlinked-ok.html" > "$TMP/t3-dangling.html"
rc="$(run "$TMP/t3-dangling.html")"
[[ "$rc" == "1" ]] && grep -q "no accessible name" "$TMP/out" \
  || fail "12b. an aria-labelledby pointing at nothing passed (rc=$rc): $(cat "$TMP/out")"
# aria-label names the box too.
sed -E 's/ aria-labelledby="[^"]*"/ aria-label="Notes"/' "$TMP/t3-unlinked-ok.html" > "$TMP/t3-arialabel.html"
rc="$(run "$TMP/t3-arialabel.html")"
[[ "$rc" == "0" ]] || fail "12b. aria-label on the notes box was rejected: $(cat "$TMP/out")"

# BL-706 (review round): a name must be the control's OWN label. Template item c3
# (label "The choice", select, label "Notes on this one", textarea) and c4 (label
# "The value", input, label, textarea). The fixtures carry their own ids, so the
# fixture linker leaves them as written.
c3ok='<section class="consult-item" data-id="Q1" data-title="Pick one"><h3>Pick one</h3><p class="fieldlabel" id="lc">The choice</p><select aria-labelledby="lc"><option value="">none</option><option>First</option></select><p class="fieldlabel" id="ln">Notes on this one</p><textarea aria-labelledby="ln"></textarea></section>'
rc="$(bl701 t3-c3-ok "$gnotes" "$c3ok" "$notesitem")"
[[ "$rc" == "0" ]] || fail "12c. the correctly named select+notes item failed: $(cat "$TMP/out")"
# (b) the notes box named by the label of the select above it
sed -E 's|<textarea aria-labelledby="ln">|<textarea aria-labelledby="lc">|' "$TMP/t3-c3-ok.html" > "$TMP/t3-c3-wrong.html"
rc="$(run "$TMP/t3-c3-wrong.html")"
[[ "$rc" == "1" ]] && grep -q "item 'Q1': its notes box has a visible label but no accessible name" "$TMP/out" \
  || fail "12c. a notes box named by the label of the control above it passed (rc=$rc): $(cat "$TMP/out")"
# (c) c4: the value input with no link, the notes box linked correctly
c4ok='<section class="consult-item" data-free data-id="Q1" data-title="A value"><h3>A value</h3><p class="fieldlabel" id="lv">The value</p><div class="row"><input type="text" aria-labelledby="lv"></div><p class="fieldlabel" id="ln">Notes on this one</p><textarea aria-labelledby="ln"></textarea></section>'
rc="$(bl701 t3-c4-ok "$gnotes" "$c4ok" "$notesitem")"
[[ "$rc" == "0" ]] || fail "12c. the correctly named value+notes item failed: $(cat "$TMP/out")"
sed -E 's|<input type="text" aria-labelledby="lv">|<input type="text">|' "$TMP/t3-c4-ok.html" > "$TMP/t3-c4-unnamed.html"
rc="$(run "$TMP/t3-c4-unnamed.html")"
[[ "$rc" == "1" ]] && grep -q "item 'Q1': its input labelled 'The value' has a visible label but no accessible name" "$TMP/out" \
  || fail "12c. a labelled value input with no accessible name passed (rc=$rc): $(cat "$TMP/out")"

# ---- 13. the masthead is the page's ONE opening -----------------------------
# A hand edit that deletes the masthead of a built page, or pastes a second one,
# used to pass every check. Two fail on any consult page; none fails only on a
# page the spec builder stamped (the block template and hand pages have none).
mh='<header class="masthead"><h1>Title</h1><p class="standfirst">Opening.</p></header>'
stamp='<meta name="spec-built" content="1">'
sed -E "s|<body>|<body>$mh|" "$TMP/t3-c4-ok.html" > "$TMP/mh-one.html"
rc="$(run "$TMP/mh-one.html")"
[[ "$rc" == "0" ]] || fail "13. a page with one masthead failed: $(cat "$TMP/out")"
sed -E "s|<body>|<body>$mh$mh|" "$TMP/t3-c4-ok.html" > "$TMP/mh-two.html"
rc="$(run "$TMP/mh-two.html")"
[[ "$rc" == "1" ]] && grep -q "FAIL \[consult-shape\].*second masthead" "$TMP/out" \
  || fail "13. a page with two mastheads passed (rc=$rc): $(cat "$TMP/out")"
sed -E "s|<head>|<head>$stamp|" "$TMP/t3-c4-ok.html" > "$TMP/mh-none-built.html"
rc="$(run "$TMP/mh-none-built.html")"
[[ "$rc" == "1" ]] && grep -q "FAIL \[consult-shape\].*no masthead" "$TMP/out" \
  || fail "13. a spec-built page with no masthead passed (rc=$rc): $(cat "$TMP/out")"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — the consultation contract counts items, accepts any reply surface, leaves a read alone, and warns without failing"
