#!/usr/bin/env bash
# A wrap that REPHRASES a question says so, naming the items (USAGE-21).
#
# Since kit v6 the composer fingerprints each item's question body and
# `restore()` skips an answer whose fingerprint no longer matches: the reader
# opens the new round and that box reads blank. The page's banner tells the
# READER how many were dropped; nothing told the WRITER which questions he had
# just rephrased, so a round could silently cost an answer that was typed and
# never sent. The wrap now names them.
#
# What is pinned here:
#   1. a question edited between two renders is named, and only it;
#   2. two of them are one NOTE line naming both, in page order;
#   3. an untouched re-wrap, a moved item, an added id, a removed id and a
#      first wrap say nothing — "changed" is the composer's meaning, not
#      "the render is different";
#   4. what the composer strips before hashing is stripped here too: a stored
#      render carrying the kit's injected controls is not a changed question;
#   5. it is a NOTE — the exit code and the contract verdict are untouched.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$SKILL/assets/artifact-kit"
DASH="$SKILL/scripts/dash"
WRAP="$SKILL/scripts/wrap-report.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

NOTE_RE='NOTE: the question of'

# `changed_questions(prev, new)` on two fragments, as a comma-joined list. The
# id-level cells are read here rather than through a page because two of them —
# an id that disappears, a render carrying the kit's runtime controls — cannot
# be spelled as a wrap that passes the contract.
changed() {
  python3 - "$DASH" "$1" "$2" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import wrap_report
print(",".join(wrap_report.changed_questions(sys.argv[2], sys.argv[3])))
PY
}

item() {   # id, question text
  printf '<section class="consult-item" data-id="%s" data-title="T%s">' "$1" "$1"
  printf '<h3><span class="consult-id">%s</span>%s</h3>' "$1" "$2"
  printf '<p class="fieldlabel">Notes on this one</p><textarea></textarea></section>'
}

A="$(item Q1 'The first question')$(item Q2 'The second question')"

# ---------- unit cells -------------------------------------------------------
got="$(changed "$A" "$A")"
[[ -z "$got" ]] || fail "an identical render reports changed questions: '$got'"

got="$(changed "$A" "$(item Q1 'The first question')$(item Q2 'The second question, rephrased')")"
[[ "$got" == "Q2" ]] || fail "a rephrased Q2 reports '$got', expected 'Q2'"

got="$(changed "$A" "$(item Q2 'The second question')$(item Q1 'The first question')")"
[[ -z "$got" ]] || fail "a MOVED item reports '$got' — same id, same question, new position"

got="$(changed "$A" "$A$(item Q3 'A question that is new')")"
[[ -z "$got" ]] || fail "an ADDED id reports '$got' — it has no previous question to differ from"

got="$(changed "$A" "$(item Q1 'The first question')")"
[[ -z "$got" ]] || fail "a REMOVED id reports '$got' — it is not on the new render at all"

# `textContent` concatenates: a tag boundary is not a space. Both directions.
got="$(changed "$(item Q1 'Does the budget matter?')" "$(item Q1 'Does the budget <em>matter</em>?')")"
[[ -z "$got" ]] || fail "emphasis added to an unchanged question reports '$got'"
got="$(changed "$(item Q1 '<code>--out</code>PATH is required')" "$(item Q1 '--out PATH is required')")"
[[ "$got" == "Q1" ]] || fail "a boundary the composer hashes differently reports '$got', expected 'Q1'"

# The class and the attribute are matched whole, not as a hyphenated prefix or a value.
note='<section class="consult-item-note" data-id="Q9"><p>%s</p></section>'
got="$(changed "$A$(printf "$note" 'a side note')" "$A$(printf "$note" 'a side note, edited')")"
[[ -z "$got" ]] || fail "a .consult-item-note is judged as an item: '$got'"
got="$(changed "$(item Q1 '<span data-hint="contenteditable">The real question</span>')" \
               "$(item Q1 '<span data-hint="contenteditable">Another question</span>')")"
[[ "$got" == "Q1" ]] || fail "an attribute VALUE naming contenteditable dropped the question: '$got'"

got="$(changed "$A" "$(item Q1 'The first question, rephrased')$(item Q2 'Also rephrased')")"
[[ "$got" == "Q1,Q2" ]] || fail "two rephrased questions report '$got', expected 'Q1,Q2'"

got="$(changed "" "$A")"
[[ -z "$got" ]] || fail "a first render reports '$got' — there is no previous question"

# The composer strips its own injected controls before hashing, or every answer
# stored before a kit release would read as "the question changed". A render
# saved out of a browser carries them; the same item without them is the same
# question.
WITH_CHROME='<section class="consult-item" data-id="Q1" data-title="TQ1">'\
'<h3><span class="consult-id">Q1</span>The first question<span class="kit-tag">recommended</span></h3>'\
'<div class="kit-ask"><span class="kit-ask-lead">Ask for</span><label><input type="checkbox" data-label="[explain-why]"> why</label></div>'\
'<p class="kit-provisional">Provisional: an ask is ticked beside it.</p>'\
'<p class="fieldlabel">Notes on this one</p><textarea></textarea>'\
'<button class="consult-clear">Clear</button></section>'
got="$(changed "$WITH_CHROME" "$(item Q1 'The first question')")"
[[ -z "$got" ]] || fail "the kit's injected controls count as the question: '$got'"

# A reader's own typing inside a [contenteditable] is not the question either —
# `setFreeValue` writes it with `.textContent`, so hashing it would drop the
# answer on a plain reload.
TYPED='<section class="consult-item" data-id="Q1" data-title="TQ1">'\
'<h3><span class="consult-id">Q1</span>The first question</h3>'\
'<div contenteditable="true">what the reader typed</div></section>'
BLANK='<section class="consult-item" data-id="Q1" data-title="TQ1">'\
'<h3><span class="consult-id">Q1</span>The first question</h3>'\
'<div contenteditable="true"></div></section>'
got="$(changed "$TYPED" "$BLANK")"
[[ -z "$got" ]] || fail "text typed into a contenteditable counts as the question: '$got'"

# ---------- through the wrap, on a real page ---------------------------------
PROJ="$TMP/proj"; mkdir -p "$PROJ/.context/reports"
PAGE="$PROJ/.context/reports/consult.html"
BODY="$TMP/body.html"
cp "$KIT/skeleton.html" "$BODY"

err="$TMP/err1"
bash "$WRAP" --title "Consultation" --lang en --in "$BODY" --out "$PAGE" >/dev/null 2>"$err" \
  || fail "the first wrap of the skeleton failed: $(cat "$err")"
grep -q "$NOTE_RE" "$err" && fail "the FIRST wrap at a path names changed questions: $(cat "$err")"

err="$TMP/err2"
bash "$WRAP" --title "Consultation" --lang en --in "$BODY" --out "$PAGE" >/dev/null 2>"$err"
rc=$?
[[ "$rc" == 0 ]] || fail "an untouched re-wrap exits $rc: $(cat "$err")"
grep -q "$NOTE_RE" "$err" && fail "an untouched re-wrap names changed questions: $(cat "$err")"

# Q1's evidence paragraph, rewritten. The id and the data-title are untouched —
# the claim is the same, which is exactly why the id cannot be the discriminant.
python3 - "$BODY" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
old = "What is at stake for this one, and what each answer costs."
assert old in t, "the skeleton no longer carries the sentence this test edits"
open(p, "w", encoding="utf-8").write(t.replace(old, "Rewritten so the reader can follow it."))
PY
err="$TMP/err3"
bash "$WRAP" --title "Consultation" --lang en --in "$BODY" --out "$PAGE" >/dev/null 2>"$err"
rc=$?
[[ "$rc" == 0 ]] || fail "a wrap with a rephrased question exits $rc: $(cat "$err")"
line="$(grep "$NOTE_RE" "$err")"
[[ -n "$line" ]] || fail "a rephrased Q1 is not reported: $(cat "$err")"
[[ "$line" == *"Q1"* ]] || fail "the note does not name Q1: '$line'"
[[ "$line" == *"Q2"* ]] && fail "the note names Q2, whose question nobody touched: '$line'"
[[ "$line" == *"not restore"* ]] \
  || fail "the note does not say what the reader loses: '$line'"
[[ "$(grep -c "$NOTE_RE" "$err")" == 1 ]] \
  || fail "one rephrased question produced $(grep -c "$NOTE_RE" "$err") notes"

# Two of them, one line, in page order.
python3 - "$BODY" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace("Rewritten so the reader can follow it.", "Rewritten once more.")
old = "The second question this context raises"
assert old in t, "the skeleton no longer carries Q2's heading"
open(p, "w", encoding="utf-8").write(t.replace(old, "The second question, asked better"))
PY
err="$TMP/err4"
bash "$WRAP" --title "Consultation" --lang en --in "$BODY" --out "$PAGE" >/dev/null 2>"$err"
rc=$?
[[ "$rc" == 0 ]] || fail "a wrap with two rephrased questions exits $rc: $(cat "$err")"
[[ "$(grep -c "$NOTE_RE" "$err")" == 1 ]] \
  || fail "two rephrased questions produced $(grep -c "$NOTE_RE" "$err") NOTE lines, expected 1"
line="$(grep "$NOTE_RE" "$err")"
[[ "$line" == *"Q1, Q2"* ]] || fail "the note does not name both ids in page order: '$line'"

# A moved item is not a changed one, through the wrap too: Q2 before Q1.
python3 - "$BODY" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
items = re.findall(r'  <section class="consult-item" data-id="Q\d".*?</section>\n', t, re.S)
assert len(items) == 2, "the skeleton's two block items are no longer matchable"
t = t.replace(items[0] + "\n" + items[1], items[1] + "\n" + items[0])
open(p, "w", encoding="utf-8").write(t)
PY
err="$TMP/err5"
bash "$WRAP" --title "Consultation" --lang en --in "$BODY" --out "$PAGE" >/dev/null 2>"$err"
rc=$?
[[ "$rc" == 0 ]] || fail "a wrap that only reorders two items exits $rc: $(cat "$err")"
grep -q "$NOTE_RE" "$err" && fail "reordering two items reports a changed question: $(cat "$err")"

# A page with no questions at all has nothing to say, on any round.
RPAGE="$PROJ/.context/reports/report.html"
printf '<div class="page"><main class="main"><section id="s1"><h2>Body</h2><p>A read.</p></section></main></div>\n' \
  > "$TMP/report-body.html"
bash "$WRAP" --title "Report" --lang en --in "$TMP/report-body.html" --out "$RPAGE" >/dev/null 2>&1
err="$TMP/err6"
bash "$WRAP" --title "Report" --lang en --in "$TMP/report-body.html" --out "$RPAGE" >/dev/null 2>"$err"
rc=$?
[[ "$rc" == 0 ]] || fail "re-wrapping a plain report exits $rc: $(cat "$err")"
grep -q "$NOTE_RE" "$err" && fail "a report with no consult items reports changed questions: $(cat "$err")"

if [[ "$failures" -eq 0 ]]; then
  echo "test-question-changed-note.sh: all checks passed"
else
  echo "$failures failure(s)"; exit 1
fi
