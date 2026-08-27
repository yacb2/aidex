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
    printf '%s\n' "$body"
    printf '</body>\n</html>\n'
  } > "$out"
}

# The page-level general-notes item. Every consultation fixture that is not
# testing its absence carries it, the way the template ships it.
notesitem='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><textarea></textarea></section>'
gopen='<section class="consult-group" id="G1" data-id="G1" data-title="The context"><div class="sec-head"><h2>The context</h2></div><p>What the decisions below share.</p>'
gclose='</section>'
bars='<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div>'
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
  <textarea placeholder=\"Anything the options do not cover\"></textarea>
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
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Pick one\">
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
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"The first claim\">
  <h3>Q1</h3><textarea></textarea></section>
$gclose
$notesitem
$bars
$composer"
mkpage "$TMP/now.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"A completely different claim\">
  <h3>Q1</h3><textarea></textarea></section>
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
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Pick one\">
  <h3>Pick one</h3><textarea></textarea>
</section>
$gclose
$bars
$composer"
rc="$(run "$TMP/no-general.html")"
[[ "$rc" == "1" ]] || fail "9. a consultation with no general-notes item passed (or the check was satisfied by components.css)"
grep -qi 'consult-notes' "$TMP/out" || fail "9. the failure does not name the missing general-notes item"

# ---- 7. the template ships the full component set ------------------------
# ---- 8. BL-198: an id in the ledger AND still in the question set fails ----
# The contract's "decided items leave the interface". The ledger is the only
# declaration of decidedness a page carries, so the intersection is what a
# checker can reach.
ledger_ok='<div class="ledger"><div><span class="k">c1</span><span class="v"><b>Done.</b> Settled last round.</span></div></div>'
ledger_bad='<div class="ledger"><div><span class="k">c1 &middot; BL-265</span><span class="v"><b>Done.</b> Settled last round.</span></div></div>'
item() { printf '<section class="consult-item" data-id="%s" data-title="A question"><h3>A question</h3><textarea></textarea></section>' "$1"; }

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
mkpage "$TMP/ledger-numbered.html" "$visual
<div class=\"ledger\"><div><span class=\"k\">1</span><span class=\"v\">A numbered row.</span></div></div>
<div class=\"ledger\"><article><p>A grid row with no key at all.</p></article></div>
$gopen
$(item c1)
$notesitem
$bars
$gclose
$composer"
rc="$(run "$TMP/ledger-numbered.html")"
[[ "$rc" == "0" ]] || fail "8. a numbered or keyless ledger was read as item ids: $(cat "$TMP/out")"


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
  </div>
  <textarea></textarea>
</section>
<section class=\"consult-item\" data-id=\"Q2\" data-title=\"Hand-rolled wrapper\">
  <h3>Hand-rolled wrapper</h3>
  <div class=\"consult-options\">
    <label><input type=\"radio\" name=\"Q2\" data-label=\"B (recomendada)\"><span>B</span></label>
  </div>
  <textarea></textarea>
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

# The declared affordance is the thing the warning points AT, so it must be
# silent: a page that complied and still got warned teaches authors to ignore it.
mkpage "$TMP/warn-clean.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Declared properly\">
  <h3>Declared properly</h3>
  <div class=\"opts one\">
    <label><input type=\"radio\" name=\"Q1\" data-label=\"A\" data-recommended><span>A</span></label>
    <label><input type=\"radio\" name=\"Q1\" data-label=\"B\" data-recommended=\"no\"><span>B</span></label>
  </div>
  <textarea></textarea>
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

# ...and warnings stay out of --census, where nobody can clear them.
mkdir -p "$TMP/census/.context/reports"
cp "$TMP/warn-opts.html" "$TMP/census/.context/reports/w.html"
bash "$CHECK" --census "$TMP/census" > "$TMP/out" 2>&1
grep -q 'WARN' "$TMP/out" \
  && fail "10. --census printed a warning — noise on a page nobody is editing: $(cat "$TMP/out")"

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — the consultation contract counts items, accepts any reply surface, leaves a read alone, and warns without failing"
