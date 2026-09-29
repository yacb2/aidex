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
# until a newer reply replaces it. (A second guard — refusing to BUILD a new
# round at all with no reply on disk for the one being left behind — was
# scoped out; see the BL-504 report for why: `consult-round` currently
# advances on every passing wrap regardless of whether the reader ever saw
# it, so "round" and "wrap count" are the same number today and a hard
# refusal on that discriminant would misfire on ordinary same-round
# iteration, exactly the workflow test-question-changed-note.sh exercises.)
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
    printf '%s\n' "$body"
    printf '</body>\n</html>\n'
  } > "$out"
}

visual='<meta name="consult-visual" content="none: the subject is a single number, so there is no shape to draw">'
notesitem='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><textarea></textarea></section>'
gopen='<section class="consult-group" id="G1" data-id="G1" data-title="The context"><div class="sec-head"><h2>The context</h2></div><p>What the decisions below share.</p>'
gclose='</section>'
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
  <textarea></textarea>
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
  <textarea></textarea>
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
  <textarea></textarea>
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

# ---- A7. an item decided in the new round is exempt --------------------------
save_reply '' '### Q1 · Q1

- [show-me]

no entiendo'
decided_page "$R/page.html"        # Q1 now carries data-decided, no figure
rc="$(run "$R/page.html" --prev "$R/.aidex-artifact-prev/page.html")"
[[ "$rc" == "0" ]] && ok "A7. an item decided this round is exempt from its own marked duty" \
  || fail "A7: rc=$rc $(cat "$TMP/out")"

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
echo "$out" | grep -q 'Q1 \[show-me\]' \
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
[[ "$n" == "1" ]] && printf '%s\n' "$out3" | grep -q 'marker by marker' \
  && ok "C6. 3+ stacked asks print ONE duty line, not one per marker" \
  || fail "C6: got $n duty line(s): $out3"

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
echo "$out_followup" | grep -q 'Q1 \[show-me\]' \
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
echo "$out_e" | grep -q 'Q1 \[page-defect\]' \
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
[[ "$n" == "2" ]] && printf '%s\n' "$out_e3" | grep -q 'marker by marker' \
  && printf '%s\n' "$out_e3" | grep -q '\[page-defect\]' \
  && ok "E3. 3+ real asks stack to one line; [page-defect] still prints separately" \
  || fail "E3: got $n line(s): $out_e3"

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
  || fail "G2: rc=$rc $(cat "$TMP/out")"

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
<section class=\"consult-item\" data-id=\"Q9\" data-free data-title=\"A different item\"><h3>Q9</h3><textarea></textarea></section>
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
