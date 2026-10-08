#!/usr/bin/env bash
# test-consultation-round-guards.sh — BL-504: every ask marker owes a CHECKED
# duty, not only `[show-me]`, and the check must not be defeated by the moving
# contract baseline.
#
# Root defect (research/2026-09-29-consult-answerability, the BL-503 page):
# `.aidex-artifact-prev/<page>.html` is advanced on every PASSING wrap (by
# design, for id stability), and the old `check_show_me` judged a `[show-me]`
# ask against a reply-vs-baseline mtime — so the first re-wrap inside a round
# could already have moved the baseline the check believed it was comparing
# against, and a missing reply.md only WARNed. A round shipped 7 [show-me]
# items and 0 figures.
#
# The fix: `save-reply.sh` snapshots the page as the reader answered it to a
# FIXED file (`.answered.html`) nothing else ever touches, and every marker
# check (`check_marker_duties` in dash/check_artifact.py) reads THAT — never
# the baseline, never an mtime, so it is enforced on every wrap of the page
# until a newer reply replaces it. (The second guard, refusing a new round with no
# saved reply, landed with BL-507: `consult-round` is now the reader's round, see
# test-consult-reader-round.sh.)
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
SAVE_REPLY="$SKILL/scripts/save-reply.sh"
WRAP="$SKILL/scripts/wrap-report.sh"
KIT="$SKILL/assets/artifact-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

mkpage() {
  local out="$1" body="$2" round="${3:-}"
  local meta=""
  [[ -n "$round" ]] && meta="<meta name=\"consult-round\" content=\"$round\">"
  {
    printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>Fixture</title>\n%s\n<style>\n' "$meta"
    printf '@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --paper:#111; } }\n'
    printf ':root[data-theme="dark"] .consult-bar { background: #111; }\n'
    printf '</style>\n</head>\n<body>\n'
    printf '%s\n' "$body" | python3 "$(dirname "${BASH_SOURCE[0]}")/link_labels.py"
    printf '</body>\n</html>\n'
  } > "$out"
}

visual='<meta name="consult-visual" content="none: the subject is a single number, so there is no shape to draw">'
notesitem='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><p class="fieldlabel">Notes for the whole page</p><textarea></textarea></section>'
gopen='<section class="consult-group" id="G1" data-id="G1" data-title="The context"><div class="sec-head"><h2>The context</h2></div><p>What the decisions below share.</p>'
gclose='<div class="group-notes"><p class="fieldlabel">Notes on this block</p><textarea></textarea></div></section>'
bars='<main><div class="endbar"><button type="button" id="consult-copy-end">Copy</button></div></main><aside class="rail"><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside>'
kit="$(printf '<style>\n'; cat "$KIT/tokens.css"; printf '</style>\n<style>\n'; \
       cat "$KIT/components.css"; printf '</style>\n')"
composer="$kit$(printf '<script>\n'; cat "$KIT/composer.js"; printf '</script>\n')"

run() { bash "$CHECK" "$@" > "$TMP/out" 2>&1; echo $?; }

# One item, Q1, whose body is a paragraph plus $2 (extra markup), a heading
# whose TEXT is $3 (so the "reframe" cases can vary the question), and no
# figure unless $2 supplies one.
page() {  # $1=out $2=extra-markup-in-Q1 $3=heading-text $4=round
  local heading="${3:-The question, asked as a question}"
  mkpage "$1" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"The first claim\">
  <h3>$heading</h3>
  <p>What is at stake, and what each answer costs, in one short paragraph.</p>
  $2
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer" "${4:-}"
}

decided_page() {  # $1=out — Q1 is data-decided, still marked show-me in the reply
  mkpage "$1" "$visual
<div id=\"sec-ledger\"></div>
$gopen
<section class=\"consult-item\" data-decided=\"First option\" data-id=\"Q1\" data-free data-title=\"The first claim\">
  <h3>The question, asked as a question</h3>
  <p>What is at stake, and what each answer costs, in one short paragraph.</p>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
}

R="$TMP/rounds"; mkdir -p "$R/.aidex-artifact-prev"
# Writes the reply, the answered snapshot, AND the contract baseline (so
# consult-ids has an id-stable --prev to compare against; these tests are not
# about that rule, and an unrelated FAIL there would mask the one under test).
save_reply() {
  printf '%s' "$2" > "$R/.aidex-artifact-prev/page.reply.md"
  page "$R/.aidex-artifact-prev/page.answered.html" "$1"
  page "$R/.aidex-artifact-prev/page.html" "$1"
}

# ============================================================================
# Part A — one duty per marker, checked against the ANSWERED snapshot
# ============================================================================

# ---- A1. [more-examples]: no more visuals/tables/examples than last round ---
save_reply '' '### Q1 · Q1

- [more-examples]

no veo suficientes ejemplos'
page "$R/page.html" ''
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*more-examples' "$TMP/out" \
  && ok "A1a. [more-examples] with no more examples FAILS" \
  || fail "A1a: rc=$rc $(cat "$TMP/out")"

page "$R/page.html" '<table><tr><td>one</td></tr></table>'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A1b. [more-examples] answered with an added table PASSES" \
  || fail "A1b: rc=$rc $(cat "$TMP/out")"

# ---- A2. [explain-simpler]: fewer words than last round ---------------------
save_reply '' '### Q1 · Q1

- [explain-simpler]

demasiado largo, no lo entiendo'
page "$R/page.html" '<p>An even longer paragraph added instead of a shorter one, which is the opposite of what was asked for here.</p>'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*explain-simpler' "$TMP/out" \
  && ok "A2a. [explain-simpler] answered with MORE words FAILS" \
  || fail "A2a: rc=$rc $(cat "$TMP/out")"

mkpage "$R/page.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q1\" data-free data-title=\"The first claim\">
  <h3>Q1</h3>
  <p>Shorter.</p>
  <p class=fieldlabel>Free text</p><textarea></textarea>
</section>
$gclose
$notesitem
$bars
$composer"
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A2b. [explain-simpler] answered with FEWER words PASSES" \
  || fail "A2b: rc=$rc $(cat "$TMP/out")"

# ---- A3. [reframe]: a DIFFERENT question, not the same one re-explained -----
save_reply '' '### Q1 · Q1

- [reframe]

esto no es lo que me tienen que preguntar'
page "$R/page.html" '' 'The question, asked as a question'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*reframe' "$TMP/out" \
  && ok "A3a. [reframe] with the SAME question FAILS" \
  || fail "A3a: rc=$rc $(cat "$TMP/out")"

page "$R/page.html" '' 'A completely different question, re-scoped'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A3b. [reframe] with a different question PASSES" \
  || fail "A3b: rc=$rc $(cat "$TMP/out")"

# ---- A4. explain-state/options/why/question: body must not be identical -----
for marker in explain-state explain-options explain-why question; do
  save_reply '' "### Q1 · Q1

- [$marker]

no entiendo"
  page "$R/page.html" '' 'The question, asked as a question'
  rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
  [[ "$rc" == "1" ]] && grep -q "consult-marker-duties.*Q1.*\[$marker\]" "$TMP/out" \
    && ok "A4. [$marker] with the identical item FAILS" \
    || fail "A4 [$marker]: rc=$rc $(cat "$TMP/out")"

  page "$R/page.html" '' 'The question, rewritten with the missing piece'
  rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
  [[ "$rc" == "0" ]] && ok "A4. [$marker] with a changed item PASSES" \
    || fail "A4 [$marker] pass: rc=$rc $(cat "$TMP/out")"
done

# ---- A4b. BL-609: a gallery row's note <ul>, and nothing else new, answers [explain-why]
save_reply '' "### Q1 · Q1

- [explain-why]

no entiendo"
page "$R/page.html" '<ul class="gal-note"><li>If it is removed, the empty state loses its only guide.</li></ul>'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A4b. [explain-why] answered only by a gal-note list PASSES" \
  || fail "A4b: rc=$rc $(cat "$TMP/out")"

# ---- A5. [page-defect] and [not-now]: no per-item check at all --------------
save_reply '' '### Q1 · Q1

- [page-defect]

hay un problema de encoding en el titulo'
page "$R/page.html" ''   # byte-identical to the answered snapshot
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A5a. [page-defect] carries no re-ask duty" \
  || fail "A5a: rc=$rc $(cat "$TMP/out")"

save_reply '' '### Q1 · Q1

- [not-now]'
page "$R/page.html" ''
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A5b. [not-now] carries no re-ask duty" \
  || fail "A5b: rc=$rc $(cat "$TMP/out")"

# ---- A6. 3+ stacked asks: rewrite-from-situation, not marker-by-marker ------
save_reply '' '### Q1 · Q1

- [explain-state]
- [explain-simpler]
- [show-me]

no entiendo nada de esto'
page "$R/page.html" '' 'The question, asked as a question'   # unchanged, no figure
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -qi 'stacked' "$TMP/out" \
  && ok "A6a. an item with 3+ stacked asks, unrewritten, FAILS the stacked duty" \
  || fail "A6a: rc=$rc $(cat "$TMP/out")"
# A rewrite that changes the text but adds no figure still fails — the stacked
# duty is show-me PLUS body-changed, not either alone.
page "$R/page.html" '' 'A different question entirely, reframed from the situation'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*show-me' "$TMP/out" \
  && ok "A6b. 3+ stacked asks rewritten as text but with no figure still FAILS show-me" \
  || fail "A6b: rc=$rc $(cat "$TMP/out")"
page "$R/page.html" '<figure><svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg></figure>' \
  'A different question entirely, reframed from the situation'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A6c. 3+ stacked asks, reframed AND figured, PASSES" \
  || fail "A6c: rc=$rc $(cat "$TMP/out")"

# ---- A6d. a [show-me] answered by a figure the reader cannot see FAILS -------
# A visual tag inside a comment or a script string is not a figure on the page
# (the same stripping _example_count does for [more-examples]).
save_reply '' '### Q1 · Q1

- [show-me]'
for hidden in '<!-- <svg viewBox="0 0 10 10"></svg> -->' \
              '<script>var s = "<img src=x>";</script>'; do
  page "$R/page.html" "<p>A changed answer.</p>$hidden"
  rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
  [[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*show-me' "$TMP/out" \
    && ok "A6d. [show-me] with only a hidden visual ($hidden) FAILS" \
    || fail "A6d: hidden=$hidden rc=$rc $(cat "$TMP/out")"
done

# ---- A7. an item decided in the new round is exempt --------------------------
save_reply '' '### Q1 · Q1

- [show-me]

no entiendo

Q1: Sí, cerrarlo'   # BL-569: a decided item needs a deciding answer in the reply too
decided_page "$R/page.html"        # Q1 now carries data-decided, no figure
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A7. an item decided this round is exempt from its own marked duty" \
  || fail "A7: rc=$rc $(cat "$TMP/out")"

# A7b. ...but a decided copy of Q1 left in a COMMENT decides nothing: the live
# Q1 still owes its figure.
save_reply '' '### Q1 · Q1

- [show-me]'
decided_page "$TMP/decided-q1.html"
page "$R/page.html" '<p>A changed answer.</p>'
python3 - "$TMP/decided-q1.html" "$R/page.html" <<'PY'
import sys
d, p = open(sys.argv[1]).read(), open(sys.argv[2]).read()
a = d.index('<section class="consult-item" data-decided')
old = d[a:d.index("</section>", a) + len("</section>")]
b = p.index('<section class="consult-item" data-id="Q1"')
open(sys.argv[2], "w").write(p[:b] + "<!-- " + old + " -->\n" + p[b:])
PY
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*show-me' "$TMP/out" \
  && ok "A7b. a commented-out decided copy of Q1 does not exempt the live Q1" \
# ---- A7c. BL-711: a proposal the reader ASKED about is not exempt ------------
# A proposal carries the ask chips now, so a reply can mark it [show-me]. The new page still
# carries decided (the proposal is not settled), but the duty is owed: judged against the
# answered snapshot, where the item was a proposal.
save_reply '' '### Q1 · Q1

- [show-me]'
{ printf '%s' "$(cat "$R/.aidex-artifact-prev/page.answered.html")" | sed 's|<section class="consult-item" data-id="Q1"|<section class="consult-item" data-decided data-proposal data-id="Q1"|'; } > "$TMP/ans.html"
cp "$TMP/ans.html" "$R/.aidex-artifact-prev/page.answered.html"
decided_page "$R/page.html"        # still decided on the new page, no figure
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*show-me' "$TMP/out" \
  && ok "A7c. a proposal marked [show-me] and answered with no figure FAILS (not exempt as decided)" \
  || fail "A7c: rc=$rc $(cat "$TMP/out")"

# ============================================================================
# Part C — save-reply.sh: writes both files verbatim and prints the DUTIES
# ============================================================================
PAGEC="$TMP/pagec/page.html"
mkdir -p "$TMP/pagec"
page "$PAGEC" '' 'The question, asked as a question'
REPLY_TXT='### Q1 · Q1

- [show-me]
- Yes

no entiendo'
printf '%s' "$REPLY_TXT" > "$TMP/reply.md"
out="$(bash "$SAVE_REPLY" "$PAGEC" "$TMP/reply.md")"
rc=$?
[[ $rc -eq 0 ]] && ok "C1. save-reply.sh exits 0" || fail "C1: rc=$rc $out"
cmp -s "$TMP/reply.md" "$TMP/pagec/.aidex-artifact-prev/page.reply.md" \
  && ok "C2. the reply is saved verbatim" \
  || fail "C2. the saved reply differs from the paste"
cmp -s "$PAGEC" "$TMP/pagec/.aidex-artifact-prev/page.answered.html" \
  && ok "C3. the answered snapshot is the page as it stood, verbatim" \
  || fail "C3. the answered snapshot differs from the page that was answered"
echo "$out" | grep >/dev/null 'Q1 \[show-me\]' \
  && ok "C4. save-reply.sh prints the show-me duty for Q1" \
  || fail "C4: $out"

# C5. reading from stdin (the "-" / omitted form) works the same way.
PAGEC2="$TMP/pagec2/page.html"
mkdir -p "$TMP/pagec2"
page "$PAGEC2" '' 'Another question'
out2="$(printf '%s' "$REPLY_TXT" | bash "$SAVE_REPLY" "$PAGEC2")"
rc=$?
[[ $rc -eq 0 ]] && cmp -s "$PAGEC2" "$TMP/pagec2/.aidex-artifact-prev/page.answered.html" \
  && ok "C5. save-reply.sh reads the paste from stdin when no file is given" \
  || fail "C5: rc=$rc $out2"

# C6. 3+ stacked asks collapse to ONE duty line, not one per marker.
STACKED='### Q1 · Q1

- [explain-state]
- [explain-simpler]
- [show-me]

no entiendo nada'
out3="$(printf '%s' "$STACKED" | bash "$SAVE_REPLY" "$PAGEC2")"
n="$(printf '%s\n' "$out3" | grep -c '^Q1 \[')"
[[ "$n" == "1" ]] && printf '%s\n' "$out3" | grep >/dev/null 'marker by marker' \
  && ok "C6. 3+ stacked asks print ONE duty line, not one per marker" \
  || fail "C6: got $n duty line(s): $out3"

# C7. a paste that is only a UTF-8 BOM (Windows clipboards) is an empty reply:
#     refused, and the reply already saved is left byte-for-byte as it was.
printf '\xef\xbb\xbf \n' > "$TMP/bom-only.md"
cp "$TMP/pagec2/.aidex-artifact-prev/page.reply.md" "$TMP/reply-before-bom.md"
for form in file stdin; do
  if [[ $form == file ]]; then
    err="$(bash "$SAVE_REPLY" "$PAGEC2" "$TMP/bom-only.md" 2>&1 >/dev/null)"; rc=$?
  else
    err="$(bash "$SAVE_REPLY" "$PAGEC2" < "$TMP/bom-only.md" 2>&1 >/dev/null)"; rc=$?
  fi
  [[ $rc -eq 2 && "$err" == *"empty"* ]] \
    && cmp -s "$TMP/reply-before-bom.md" "$TMP/pagec2/.aidex-artifact-prev/page.reply.md" \
    && ok "C7. a BOM-only reply ($form) is refused as empty and the saved reply is kept" \
    || fail "C7 ($form): rc=$rc $err"
done

# C7b. a leading BOM on a real reply is dropped: the saved reply starts at `Q1:`.
printf '\xef\xbb\xbfQ1: ok\n' > "$TMP/bom-led.md"
for form in file stdin; do
  d="$TMP/bomled-$form"; mkdir -p "$d"; page "$d/page.html" '' 'A BOM-led question'
  if [[ $form == file ]]; then
    bash "$SAVE_REPLY" "$d/page.html" "$TMP/bom-led.md" >/dev/null 2>&1; rc=$?
  else
    bash "$SAVE_REPLY" "$d/page.html" < "$TMP/bom-led.md" >/dev/null 2>&1; rc=$?
  fi
  head3="$(head -c 3 "$d/.aidex-artifact-prev/page.reply.md" 2>/dev/null)"
  [[ $rc -eq 0 && "$head3" == "Q1:" ]] \
    && ok "C7b. a BOM-led reply ($form) is saved without the BOM" \
    || fail "C7b ($form): rc=$rc first bytes: $(head -c 3 "$d/.aidex-artifact-prev/page.reply.md" 2>/dev/null | od -An -c)"
done

# ============================================================================
# Part D — review finding 1 (BLOCKING): a second save-reply must not wipe an
# outstanding duty. Reproduces: save a paste marking Q1 [show-me] (no figure),
# wrap a draft, save a chat follow-up with NO marks — a page whose Q1 still has
# no figure must not silently start passing.
# ============================================================================
PAGED="$TMP/paged/page.html"
mkdir -p "$TMP/paged"
page "$PAGED" '' 'The question, asked as a question'      # v1: Q1, no figure
cp "$PAGED" "$TMP/paged/orig.html"                         # what save-reply #1 snapshots
FIRST_REPLY='### Q1 · Q1

- [show-me]

no entiendo, dame un dibujo'
printf '%s' "$FIRST_REPLY" | bash "$SAVE_REPLY" "$PAGED" >/dev/null

# "wrap a draft" — content changes elsewhere, Q1 still carries no figure.
page "$PAGED" '<p>A small unrelated addition from the draft.</p>' 'The question, asked as a question'

FOLLOWUP='### Q1 · Q1

gracias, ahora se entiende mejor'
out_followup="$(printf '%s' "$FOLLOWUP" | bash "$SAVE_REPLY" "$PAGED")"

cp "$PAGED" "$TMP/paged/.aidex-artifact-prev/page.html"    # simulate the passing baseline
rc="$(run "$PAGED" --prev "$TMP/paged/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1' "$TMP/out" \
  && ok "D1. an unmet [show-me] duty from an earlier reply is NOT cleared by a no-marks follow-up" \
  || fail "D1: rc=$rc $(cat "$TMP/out")"

grep -q '<!-- reply saved' "$TMP/paged/.aidex-artifact-prev/page.reply.md" \
  && ok "D2a. the follow-up is APPENDED under a timestamped separator, not a replacement" \
  || fail "D2a: $(cat "$TMP/paged/.aidex-artifact-prev/page.reply.md")"
grep -q 'dame un dibujo' "$TMP/paged/.aidex-artifact-prev/page.reply.md" \
  && grep -q 'ahora se entiende mejor' "$TMP/paged/.aidex-artifact-prev/page.reply.md" \
  && ok "D2b. reply.md keeps BOTH the original text and the follow-up" \
  || fail "D2b: $(cat "$TMP/paged/.aidex-artifact-prev/page.reply.md")"
cmp -s "$TMP/paged/orig.html" "$TMP/paged/.aidex-artifact-prev/page.answered.html" \
  && ok "D2c. answered.html is KEPT at the original snapshot, not re-captured from the unmet draft" \
  || fail "D2c: answered.html was overwritten while the duty was still unmet"
echo "$out_followup" | grep >/dev/null 'Q1 \[show-me\]' \
  && ok "D2d. save-reply.sh still prints the outstanding show-me duty on the follow-up" \
  || fail "D2d: $out_followup"

# D3. once the duty IS met, the NEXT save-reply replaces reply.md (no separator)
# and re-snapshots answered.html to the delivered page — the ledger closes.
page "$PAGED" '<figure><svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg></figure>' \
  'The question, asked as a question'
DELIVERED='### Q1 · Q1

- Yes

gracias, se ve el dibujo'
printf '%s' "$DELIVERED" | bash "$SAVE_REPLY" "$PAGED" >/dev/null
grep -q '<!-- reply saved' "$TMP/paged/.aidex-artifact-prev/page.reply.md" \
  && fail "D3a. once duties are met the reply is still appended instead of replaced" \
  || ok "D3a. once every outstanding duty is met, reply.md is REPLACED (no separator)"
cmp -s "$PAGED" "$TMP/paged/.aidex-artifact-prev/page.answered.html" \
  && ok "D3b. once every outstanding duty is met, answered.html is re-snapshotted to the delivered page" \
  || fail "D3b: answered.html was not re-synced after delivery"

# D4. BL-654: a gallery duty (BL-632: a "Necesita cambios" row) holds the same
# append guard. The page is rebuilt elsewhere with the row byte-identical; a
# follow-up save must append, keep the snapshot and still print the row.
PAGEG="$TMP/pageg/page.html"
mkdir -p "$TMP/pageg"
gpage() {  # $1=extra markup outside the row  $2=the row's capture file
  mkpage "$PAGEG" "$1
<section class=\"consult-item consult-gallery\" data-id=\"x-full-light-desktop\" data-title=\"x · full · light-desktop\">
  <h3>x full</h3><figure class=\"gal-tile\"><img src=\"$2\"></figure><p class=fieldlabel>Free text</p><textarea></textarea>
</section>"
}
gpage '<p>v1</p>' 'x-full-v1.png'
cp "$PAGEG" "$TMP/pageg/orig.html"
printf '%s' '### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

el boton se sale del borde' | bash "$SAVE_REPLY" "$PAGEG" >/dev/null
gpage '<p>v2, rebuilt elsewhere</p>' 'x-full-v1.png'
out_g="$(printf '%s' '### notes · General notes

gracias' | bash "$SAVE_REPLY" "$PAGEG")"
grep -q '<!-- reply saved .* duty -->' "$TMP/pageg/.aidex-artifact-prev/page.reply.md" \
  && cmp -s "$TMP/pageg/orig.html" "$TMP/pageg/.aidex-artifact-prev/page.answered.html" \
  && echo "$out_g" | grep >/dev/null '^x-full-light-desktop \[needs-changes\]' \
  && ok "D4. an unaddressed gallery duty holds the append guard like a marker duty" \
  || fail "D4: $out_g // $(cat "$TMP/pageg/.aidex-artifact-prev/page.reply.md")"

# D5. the row rebuilt (a new capture): the next save REPLACES and re-snapshots.
gpage '<p>v3</p>' 'x-full-v2.png'
printf '%s' '### x-full-light-desktop · x · full · light-desktop

- Aprobada' | bash "$SAVE_REPLY" "$PAGEG" >/dev/null
! grep -q '<!-- reply saved' "$TMP/pageg/.aidex-artifact-prev/page.reply.md" \
  && cmp -s "$PAGEG" "$TMP/pageg/.aidex-artifact-prev/page.answered.html" \
  && ok "D5. once the gallery row is rebuilt, reply.md is REPLACED and re-snapshotted" \
  || fail "D5: $(cat "$TMP/pageg/.aidex-artifact-prev/page.reply.md")"

# D6. BL-654 review: the gated flow, three rounds through spec_build. A round 2
# that leaves the owed gallery row untouched is REFUSED by the wrap gate (as a
# marker duty is), so answered.html never freezes behind a shipped round and
# --new-round keeps working: the row rebuilt wraps, and round 3 builds.
FL="$TMP/flow"; mkdir -p "$FL/shots" "$FL/actual" "$FL/pages"
(cd "$FL" && git init -q .)
python3 "$SKILL/tests/png_fixture.py" "$FL/shots/a.png" 16 9 96   # a before that differs from the after (the builder refuses identical pairs)
python3 "$SKILL/tests/png_fixture.py" "$FL/actual/a.png" 16 9
cat > "$FL/pages/rows.json" <<'J'
{"gallery": "audit", "variants": ["light-desktop"], "rows": [
 {"cell": "with-data", "variant": "light-desktop", "kind": "review", "look": "The header", "before": "shots/a.png", "after": "actual/a.png"}]}
J
printf '::: masthead {eyebrow="Rev" byline="aidex"}\n# Galeria prueba\n\nRevisa las capturas.\n:::\n\n::: gallery {#E title="Galeria audit" rows="rows.json"}\n:::\n\n::: notes {title="Notas generales"}\n:::\n' > "$FL/pages/p.spec.md"
build() { (cd "$FL" && python3 "$SKILL/scripts/spec_build.py" pages/p.spec.md -o pages/p.html "$@") > "$TMP/fl.out" 2>&1; }
build; rc1=$?
printf '%s' '### audit-with-data-light-desktop · audit · with-data · light-desktop

- Necesita cambios

el header se corta' | bash "$SAVE_REPLY" "$FL/pages/p.html" >/dev/null
build --new-round; rc=$?
[[ "$rc1" == 0 && "$rc" != 0 ]] && grep -q 'consult-marker-duties.*audit-with-data-light-desktop' "$TMP/fl.out" \
  && ok "D6a. round 2 with the owed gallery row untouched is REFUSED, the row named" \
  || fail "D6a: rc1=$rc1 rc=$rc $(cat "$TMP/fl.out")"
python3 "$SKILL/tests/png_fixture.py" "$FL/actual/a.png" 16 10       # the capture rebuilt
build --new-round; rc=$?
printf '%s' '### audit-with-data-light-desktop · audit · with-data · light-desktop

- Aprobada' | bash "$SAVE_REPLY" "$FL/pages/p.html" >/dev/null
build --new-round; rc3=$?
[[ "$rc" == 0 && "$rc3" == 0 ]] && grep -q 'ronda 3' "$FL/pages/p.html" \
  && ok "D6b. the row rebuilt wraps, and the next --new-round builds round 3" \
  || fail "D6b: rc=$rc rc3=$rc3 $(cat "$TMP/fl.out")"

# D6c. BL-690: a row that owes ANY duty from the last saved reply cannot wait on an
# open item (the reader asked about THIS row, so it is not only the pending option):
# the wrap FAILS naming the row and the item, never a silent skip and never a deferral.
# A row with no duty may wait (control). Three rounds of one flow per case.
wflow() {  # wflow <name> <reply> <rows.py mutation of d for round 2>; leaves rc in $wrc, output in $TMP/wt-<name>.out
  local n="$1" W="$TMP/wait-$1"
  mkdir -p "$W/shots" "$W/actual" "$W/pages"
  (cd "$W" && git init -q .)
  python3 "$SKILL/tests/png_fixture.py" "$W/shots/a.png" 16 9 96   # a before that differs from the after (the builder refuses identical pairs)
  python3 "$SKILL/tests/png_fixture.py" "$W/actual/a.png" 16 9
  cat > "$W/pages/rows.json" <<'J'
{"gallery": "audit", "variants": ["light-desktop"], "rows": [
 {"cell": "with-data", "variant": "light-desktop", "kind": "review", "look": "The header", "before": "shots/a.png", "after": "actual/a.png"},
 {"cell": "loaded", "variant": "light-desktop", "kind": "unrequested", "look": "The rows", "before": "shots/a.png", "after": "actual/a.png"}]}
J
  printf '::: masthead {eyebrow="Rev" byline="aidex" visual="none: a layout probe"}\n# Galeria prueba\n\nRevisa las capturas.\n:::\n\n::: group {#G1 title="Decision" eyebrow="Q"}\n::: item {#Q14 title="Forma de Inicio"}\n?\n\n- B\n- C {recommended}\n:::\n:::\n\n::: gallery {#E title="Galeria audit" rows="rows.json"}\n:::\n\n::: notes {title="Notas generales"}\n:::\n' > "$W/pages/p.spec.md"
  (cd "$W" && python3 "$SKILL/scripts/spec_build.py" pages/p.spec.md -o pages/p.html) > "$TMP/wt-$n.out" 2>&1 || { wrc=99; return; }
  printf '%s' "$2" | bash "$SAVE_REPLY" "$W/pages/p.html" >/dev/null
  python3 - "$W/pages/rows.json" "$3" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for i in sys.argv[2].split(","):
    d["rows"][int(i)]["depends_on"] = "Q14"
json.dump(d, open(sys.argv[1], "w"))
PY
  (cd "$W" && python3 "$SKILL/scripts/spec_build.py" pages/p.spec.md -o pages/p.html --new-round) > "$TMP/wt-$n.out" 2>&1; wrc=$?
}
UNREQ='### audit-loaded-light-desktop-unrequested · audit · loaded · light-desktop'
REVIEW='### audit-with-data-light-desktop · audit · with-data · light-desktop'
wflow a "$UNREQ

- Necesita cambios

no lo pedi" 1
[[ "$wrc" != 0 && "$wrc" != 99 ]] && grep -q 'consult-marker-duties.*audit-loaded-light-desktop-unrequested.*Q14' "$TMP/wt-a.out" \
  && ok "D6c-a. a gallery verdict duty on a row that now waits on Q14 FAILS the wrap, naming the row and Q14 (BL-690)" \
  || fail "D6c-a: rc=$wrc $(grep -i 'fail\|error' "$TMP/wt-a.out" | cut -c1-300)"
wflow b "$REVIEW

- [explain-why]

por que

$UNREQ

- [show-me]

mostrar" 0,1
[[ "$wrc" != 0 && "$wrc" != 99 ]] \
  && grep -q 'consult-marker-duties.*audit-with-data-light-desktop.*explain-why.*Q14' "$TMP/wt-b.out" \
  && grep -q 'consult-marker-duties.*audit-loaded-light-desktop-unrequested.*show-me.*Q14' "$TMP/wt-b.out" \
  && ! grep -q 'no figure, image or diagram' "$TMP/wt-b.out" \
  && ok "D6c-b. marker-chip duties (explain-why on a review row, show-me on an unrequested row) on rows that now wait FAIL naming row and Q14, not the no-figure message (BL-690)" \
  || fail "D6c-b: rc=$wrc $(grep -i 'fail\|error' "$TMP/wt-b.out" | cut -c1-400)"
wflow c "$UNREQ

- Aprobada" 1
[[ "$wrc" == 0 ]] \
  && ok "D6c-c. control: depends_on on a row whose reply owes nothing builds (BL-690)" \
  || fail "D6c-c: rc=$wrc $(grep -i 'fail\|error' "$TMP/wt-c.out" | cut -c1-300)"
wflow d "$UNREQ

- [not-now]" 1
[[ "$wrc" == 0 ]] && grep -q 'data-waits-on="Q14"' "$TMP/wait-d/pages/p.html" \
  && ok "D6c-d. [not-now] defers the row, so it may wait on Q14: no FAIL, the row waits (BL-690 review round 4)" \
  || fail "D6c-d: rc=$wrc $(grep -i 'fail\|error' "$TMP/wt-d.out" | cut -c1-300)"

# D7. the stale-snapshot shape outside the gate: a round-2 page saved with the
# gallery row untouched appends (answered.html frozen at round 1, the BL-504
# D2c policy), so a round 3 that still leaves the row untouched must FAIL the
# row — never go green with the duty unmet.
ST="$TMP/stale"; mkdir -p "$ST"
spage() {  # $1=Q1 claim  $2=trailing markup
  mkpage "$ST/page.html" "<section class=\"consult-item\" data-id=\"Q1\" data-title=\"Q1\"><h3>Q1</h3><p>$1</p><p class=fieldlabel>Free text</p><textarea></textarea></section>
<section class=\"consult-item consult-gallery\" data-id=\"x-full-light-desktop\" data-title=\"x · full · light-desktop\"><h3>x full</h3><figure class=\"gal-tile\"><img src=\"v1.png\"></figure><p class=fieldlabel>Free text</p><textarea></textarea></section>
$2"
}
spage 'Round one claim about the cache.' ''
printf '%s' '### Q1 · Q1

- Yes

### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

el boton se sale' | bash "$SAVE_REPLY" "$ST/page.html" >/dev/null
spage 'Round two claim, rewritten by the author.' ''
printf '%s' '### Q1 · Q1

- [explain-why]

por que?' | bash "$SAVE_REPLY" "$ST/page.html" >/dev/null
spage 'Round two claim, rewritten by the author.' '<p>round 3</p>'
duty_fails() {
  python3 - "$SKILL/scripts/dash" "$1" <<'P'
import sys; sys.path.insert(0, sys.argv[1])
import check_artifact as ca
for _, _, msg in ca.check_marker_duties(sys.argv[2])[0]: print(msg)
P
}
st_out="$(duty_fails "$ST/page.html")"
echo "$st_out" | grep >/dev/null 'gallery row x-full-light-desktop' \
  && ok "D7. round 3 with the owed gallery row still untouched FAILS the row" \
  || fail "D7: $st_out"

# D8. a row DECIDED in the rebuilt round left the question set: no FAIL, and
# the next save replaces reply.md and re-snapshots.
DC="$TMP/decided"; mkdir -p "$DC"
dpage() {  # $1=attributes on the row
  mkpage "$DC/page.html" "<p>$2</p><section class=\"consult-item consult-gallery\" $1 data-id=\"x-full-light-desktop\" data-title=\"x · full · light-desktop\"><h3>x full</h3><figure class=\"gal-tile\"><img src=\"v1.png\"></figure><p class=fieldlabel>Free text</p><textarea></textarea></section>"
}
dpage '' 'v1'
printf '%s' '### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

el boton se sale' | bash "$SAVE_REPLY" "$DC/page.html" >/dev/null
dpage 'data-decided="Aprobada"' 'v2'
dc_out="$(duty_fails "$DC/page.html")"
printf '%s' '### notes · General notes

gracias' | bash "$SAVE_REPLY" "$DC/page.html" >/dev/null
[[ -z "$dc_out" ]] && ! grep -q '<!-- reply saved' "$DC/.aidex-artifact-prev/page.reply.md" \
  && cmp -s "$DC/page.html" "$DC/.aidex-artifact-prev/page.answered.html" \
  && ok "D8. a decided gallery row owes nothing: no FAIL, reply replaced, page re-snapshotted" \
  || fail "D8: fails=[$dc_out] $(cat "$DC/.aidex-artifact-prev/page.reply.md")"

# D9-D11 share one shape: a page in $1 dir, the reply saved, the page rebuilt.
duty_warns() {
  python3 - "$SKILL/scripts/dash" "$1" <<'P'
import sys; sys.path.insert(0, sys.argv[1])
import check_artifact as ca
for _, _, msg in ca.check_marker_duties(sys.argv[2])[1]: print(msg)
P
}
row_html='<section class="consult-item consult-gallery" data-id="x-full-light-desktop" data-title="x · full · light-desktop"><h3>x full</h3><figure class="gal-tile"><img src="v1.png"></figure><p class=fieldlabel>Free text</p><textarea></textarea></section>'
q_html='<section class="consult-item" data-id="Q1" data-title="Q1"><h3>Q1</h3><p>claim</p><p class=fieldlabel>Free text</p><textarea></textarea></section>'

# D9. an ORDINARY item whose heading has the old light/dark row shape
# (`cache-ttl · cache · ttl`) is not a gallery row: no "could not be read"
# WARN at the gate, and save-reply prints no [unreadable] duty for it.
P9="$TMP/d9"; mkdir -p "$P9"
mkpage "$P9/page.html" '<section class="consult-item" data-id="cache-ttl" data-title="cache · ttl"><h3>TTL</h3><p>claim</p><p class=fieldlabel>Free text</p><textarea></textarea></section>'
out9="$(printf '%s' '### cache-ttl · cache · ttl

- [explain-why]

por que' | bash "$SAVE_REPLY" "$P9/page.html")"
w9="$(duty_warns "$P9/page.html")"
[[ -z "$w9" ]] && [[ "$out9" != *"[unreadable]"* ]] && [[ "$out9" == *"cache-ttl [explain-why]"* ]] \
  && ok "D9. an ordinary item shaped like an old matrix row is not read as a gallery row" \
  || fail "D9: warns=[$w9] save=[$out9]"

# D10. the owed row is gone from the rebuilt page: one WARN, no FAIL.
P10="$TMP/d10"; mkdir -p "$P10"
mkpage "$P10/page.html" "$q_html
$row_html"
printf '%s' '### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

el boton se sale' | bash "$SAVE_REPLY" "$P10/page.html" >/dev/null
mkpage "$P10/page.html" "$q_html"
w10="$(duty_warns "$P10/page.html")"; f10="$(duty_fails "$P10/page.html")"
[[ "$(printf '%s\n' "$w10" | grep -c .)" == 1 && "$w10" == *"not in the new page"* && -z "$f10" ]] \
  && ok "D10. an owed gallery row missing from the rebuilt page WARNs once, no FAIL" \
  || fail "D10: warns=[$w10] fails=[$f10]"

# D11. a gallery paste gallery_reply refuses: one "could not be read" WARN.
P11="$TMP/d11"; mkdir -p "$P11"
mkpage "$P11/page.html" "$q_html
$row_html"
printf '%s' '### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

[mark after 1.7,0.2 33.0x5.6] nota
dictated sentence after the marks' | bash "$SAVE_REPLY" "$P11/page.html" >/dev/null
w11="$(duty_warns "$P11/page.html")"; f11="$(duty_fails "$P11/page.html")"
[[ "$(printf '%s\n' "$w11" | grep -c .)" == 1 && "$w11" == *"could not be read"* && -z "$f11" ]] \
  && ok "D11. an unreadable gallery paste WARNs once at the gate, no FAIL" \
  || fail "D11: warns=[$w11] fails=[$f11]"

# ============================================================================
# Part E — finding 2: [page-defect] and [not-now] do not count toward the 3+
# stack, and a [page-defect] duty always reaches the printed duties.
# ============================================================================
save_reply '' '### Q1 · Q1

- [show-me]
- [page-defect]
- [not-now]

no entiendo, y además hay un error de encoding en el titulo'
page "$R/page.html" ''   # no figure, unchanged text — one REAL ask (show-me)
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*show-me' "$TMP/out" \
  && ! grep -qi 'stacked' "$TMP/out" \
  && ok "E1. show-me + page-defect + not-now (one real ask) is not a 3+ stack" \
  || fail "E1: rc=$rc $(cat "$TMP/out")"

PAGEE="$TMP/pagee/page.html"
mkdir -p "$TMP/pagee"
page "$PAGEE" '' 'The question, asked as a question'
out_e="$(printf '%s' '### Q1 · Q1

- [show-me]
- [page-defect]
- [not-now]

no entiendo, y además hay un error de encoding en el titulo' | bash "$SAVE_REPLY" "$PAGEE")"
echo "$out_e" | grep >/dev/null 'Q1 \[page-defect\]' \
  && ok "E2. [page-defect] prints its own duty line even beside other asks, not stacked" \
  || fail "E2: $out_e"

# 3+ REAL asks (excluding page-defect/not-now) still stack to one combined
# line, and [page-defect] still prints its own line alongside it. A FRESH
# page/path: PAGEE already carries an outstanding duty from E2 above, and
# accumulating onto it is Part D's behaviour, not what this case is isolating.
PAGEE3="$TMP/pagee3/page.html"
mkdir -p "$TMP/pagee3"
page "$PAGEE3" '' 'The question, asked as a question'
STACK3='### Q1 · Q1

- [explain-state]
- [explain-simpler]
- [show-me]
- [page-defect]

no entiendo nada, y el titulo tiene un error de encoding'
out_e3="$(printf '%s' "$STACK3" | bash "$SAVE_REPLY" "$PAGEE3")"
n="$(printf '%s\n' "$out_e3" | grep -c '^Q1 \[')"
[[ "$n" == "2" ]] && printf '%s\n' "$out_e3" | grep >/dev/null 'marker by marker' \
  && printf '%s\n' "$out_e3" | grep >/dev/null '\[page-defect\]' \
  && ok "E3. 3+ real asks stack to one line; [page-defect] still prints separately" \
  || fail "E3: got $n line(s): $out_e3"

# ============================================================================
# Part DEF — the composer's page-defect SUB-BLOCK (LOOP-008 Q10): a
# `#### Fallo de la página` heading at the end of the item's block. It is read
# as the page-defect marker was, its text is quoted in the printed duty, and
# its text is never read as markers of its own.
# ============================================================================
PAGEG="$TMP/pageg/page.html"
mkdir -p "$TMP/pageg"
page "$PAGEG" '' 'The question, asked as a question'
out_g="$(printf '%s' '### Q1 · Q1

- Option A

#### Page problem

el titulo tiene un error de encoding' | bash "$SAVE_REPLY" "$PAGEG")"
printf '%s\n' "$out_g" | grep >/dev/null '^Q1 \[page-defect\].*"el titulo tiene un error de encoding"' \
  && ok "DEF1. a page-defect sub-block prints the page-defect duty with the reported text quoted" \
  || fail "DEF1: $out_g"

save_reply '' '### Q1 · Q1

#### Fallo de la página

- [show-me]
nada se ve'
page "$R/page.html" ''
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "DEF2. a line inside the page-defect text is not read as a marker (no show-me duty)" \
  || fail "DEF2: rc=$rc $(cat "$TMP/out")"

# G3. the report is what follows the LAST heading: a note that holds the literal
# heading line is note text, not a report (the composer always emits it last).
PAGEG3="$TMP/pageg3/page.html"
mkdir -p "$TMP/pageg3"
page "$PAGEG3" '' 'The question, asked as a question'
out_g3="$(printf '%s' '### Q1 · Q1

- Option A

mi nota cita esto:

#### Page problem

texto de la nota que no es un reporte

#### Page problem

el reporte real' | bash "$SAVE_REPLY" "$PAGEG3")"
printf '%s\n' "$out_g3" | grep >/dev/null '"el reporte real"' \
  && ! printf '%s\n' "$out_g3" | grep >/dev/null 'no es un reporte' \
  && ok "DEF3. a heading line inside a note is not the report: the LAST heading starts it" \
  || fail "DEF3: $out_g3"

# DEF4. two saves: Q1's report in save 1 must not swallow save 2 (an appended
# paste under the `<!-- reply saved ... -->` separator, here a chat-form Q2 line).
PAGEG4="$TMP/pageg4/page.html"
mkdir -p "$TMP/pageg4"
page "$PAGEG4" '' 'The question, asked as a question'
printf '%s' '### Q1 · Q1

#### Page problem

el titulo sale roto' | bash "$SAVE_REPLY" "$PAGEG4" >/dev/null
out_g4="$(printf '%s' 'Q2: si, la B
- [show-me]' | bash "$SAVE_REPLY" "$PAGEG4")"
printf '%s\n' "$out_g4" | grep >/dev/null '^Q1 \[page-defect\].*"el titulo sale roto"$' \
  && ! printf '%s\n' "$out_g4" | grep >/dev/null 'si, la B' \
  && ! printf '%s\n' "$out_g4" | grep >/dev/null '^Q1 \[show-me\]' \
  && ok "DEF4. a report does not swallow the next appended save: its quote is its own text" \
  || fail "DEF4: $out_g4"

# ============================================================================
# Part F — finding 3: [more-examples] strips comments/script/style, and a
# <figure> wrapping its own visual counts ONCE, not twice.
# ============================================================================
save_reply '<img src="a.png">' '### Q1 · Q1

- [more-examples]

no veo más ejemplos'
page "$R/page.html" '<figure><img src="a.png"></figure>'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*more-examples' "$TMP/out" \
  && ok "F1. the same image re-wrapped in <figure> is still ONE example — [more-examples] FAILs" \
  || fail "F1: rc=$rc $(cat "$TMP/out")"

save_reply '' '### Q1 · Q1

- [more-examples]

no veo más ejemplos'
page "$R/page.html" '<!-- <table><tr><td>commented out</td></tr></table> -->'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*more-examples' "$TMP/out" \
  && ok "F2. a commented-out table does not count toward [more-examples]" \
  || fail "F2: rc=$rc $(cat "$TMP/out")"

page "$R/page.html" '<table><tr><td>a real one</td></tr></table>'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "F3. a real added table PASSES [more-examples]" \
  || fail "F3: rc=$rc $(cat "$TMP/out")"

# ============================================================================
# Part G — finding 4: [reframe] must be stricter than the explain-* markers —
# a punctuation-only edit is still the SAME question.
# ============================================================================
save_reply '' '### Q1 · Q1

- [reframe]

esto no es lo que me tienen que preguntar'
page "$R/page.html" '' 'The question, asked as a question,'   # trailing comma added only
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "1" ]] && grep -q 'consult-marker-duties.*Q1.*reframe' "$TMP/out" \
  && ok "G1. [reframe] FAILs on a punctuation-only edit (still the same question)" \
  || fail "G1: rc=$rc $(cat "$TMP/out")"

save_reply '' '### Q1 · Q1

- [explain-state]

no entiendo'
page "$R/page.html" '' 'The question, asked as a question,'   # same punctuation-only edit
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "G2. [explain-state] PASSes on the same punctuation-only edit (any body change counts)" \
  || fail "DEF2: rc=$rc $(cat "$TMP/out")"

save_reply '' '### Q1 · Q1

- [reframe]

esto no es lo que me tienen que preguntar'
page "$R/page.html" '' 'A genuinely different question about something else entirely'
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "G3. [reframe] PASSes on a genuinely different question" \
  || fail "G3: rc=$rc $(cat "$TMP/out")"

# ============================================================================
# Part H — finding 5: WARN when a reply id is absent from the answered
# snapshot or from the new page (the reply was saved against the wrong page).
# ============================================================================
printf '### Q1 · Q1\n\n- [show-me]\n\nno entiendo\n' > "$R/.aidex-artifact-prev/page.reply.md"
mkpage "$R/.aidex-artifact-prev/page.answered.html" "$visual
$gopen
<section class=\"consult-item\" data-id=\"Q9\" data-free data-title=\"A different item\"><h3>Q9</h3><p class=fieldlabel>Free text</p><textarea></textarea></section>
$gclose
$notesitem
$bars
$composer"
page "$R/.aidex-artifact-prev/page.html" ''
page "$R/page.html" ''
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
grep -qi 'WARN \[consult-marker-duties\].*Q1' "$TMP/out" \
  && ok "H1. a reply id absent from the answered snapshot WARNs (reply saved against the wrong page)" \
  || fail "H1: $(cat "$TMP/out")"

printf '### Q9 · Q9\n\n- [show-me]\n\nno entiendo\n' > "$R/.aidex-artifact-prev/page.reply.md"
page "$R/.aidex-artifact-prev/page.answered.html" ''
page "$R/.aidex-artifact-prev/page.html" ''
page "$R/page.html" ''
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
grep -qi 'WARN \[consult-marker-duties\].*Q9' "$TMP/out" \
  && ok "H2. a reply id absent from the new page WARNs too" \
  || fail "H2: $(cat "$TMP/out")"

# ============================================================================
# Part I — finding 6: one true end-to-end test through wrap-report.sh itself
# (not just check-artifact.sh on hand-built fixtures).
# ============================================================================
PROJI="$TMP/proji"; mkdir -p "$PROJI/.context/reports"
PAGEI="$PROJI/.context/reports/consult.html"
cp "$KIT/skeleton.html" "$TMP/bodyi.html"
bash "$WRAP" --title "Consultation" --lang en --in "$TMP/bodyi.html" --out "$PAGEI" \
  >/dev/null 2>"$TMP/erri1" \
  || fail "I1. the first real wrap of the skeleton failed: $(cat "$TMP/erri1")"
REPLYI='### Q1 · Short name for this question

- [show-me]

no entiendo, dame un dibujo'
printf '%s' "$REPLYI" | bash "$SAVE_REPLY" "$PAGEI" >/dev/null \
  || fail "I2. save-reply.sh failed on the real wrapped page"
# A second real wrap of the SAME (unchanged, figure-less) content through the
# real wrap-report.sh pipeline must FAIL and roll the page back.
bash "$WRAP" --title "Consultation" --lang en --in "$TMP/bodyi.html" --out "$PAGEI" \
  >"$TMP/outi3" 2>"$TMP/erri3"
rc=$?
[[ "$rc" != "0" ]] && grep -qi 'consult-marker-duties' "$TMP/outi3" \
  && ok "I3. a real second wrap through wrap-report.sh FAILS the outstanding [show-me] duty" \
  || fail "I3: rc=$rc out=$(cat "$TMP/outi3") err=$(cat "$TMP/erri3")"
grep -q 'left exactly as they were' "$TMP/erri3" \
  && ok "I4. the failing wrap rolled the page back rather than landing an unanswered round" \
  || fail "I4: $(cat "$TMP/erri3")"

if [[ "$failures" -eq 0 ]]; then
  echo "test-consultation-round-guards.sh: all checks passed"
else
  echo "$failures failure(s)"; exit 1
fi
