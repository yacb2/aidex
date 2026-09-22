#!/usr/bin/env bash
# The REPLY PARSER (scripts/gallery-reply.sh): a pasted consultation reply
# becomes JSON — gallery rows with verdict, notes and region marks, and every
# other item untouched under `other` (plan 2026-09-22-artifact-gallery-review-
# unit, Phase 4, Task 4.2).
#
# The fixture is the composer's REAL paste, captured from a headless run and
# copied byte for byte (no trailing newline). A hand-typed fixture tests the
# parser against what its author believes the composer writes, which is the
# one thing this test exists to not trust.
#
# Every refusal is a RED control built by mutating ONE line of that fixture, and
# asserts exit 2, the line number in the message, and nothing on stdout: a
# parser that printed half a document before refusing would hand the session
# a reply with a row silently missing.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARSE="$SKILL/scripts/gallery-reply.sh"
FIX="$SKILL/tests/fixtures/gallery-reply-paste.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf '  ok: %s\n' "$*"; }

# mutate <line number> <replacement> <out>: the fixture with one line replaced.
mutate() {
  python3 - "$FIX" "$1" "$2" "$3" <<'PY'
import sys
src, n, new, out = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
lines = open(src, encoding="utf-8").read().split("\n")
lines[n - 1] = new
open(out, "w", encoding="utf-8").write("\n".join(lines))
PY
}

# row <body, printf-escaped> <out>: one gallery row with that body.
row() {
  printf '### audit-with-data · audit · with-data\n\n'"$1" > "$2"
}

# parsed <body> <python expression over `r`, the row> <label>
parsed() {
  row "$1" "$TMP/p.txt"
  bash "$PARSE" "$TMP/p.txt" > "$TMP/p.json" 2> "$TMP/p.err" \
    || { fail "$3: refused (exit $?): $(cat "$TMP/p.err")"; return; }
  expect_json "$TMP/p.json" "len(d['rows']) == 1 and (lambda r: $2)(d['rows'][0])" "$3"
}

# expect_json <json file> <python expression over `d`> <label>
# The expression is always a literal written in this file, never input.
expect_json() {
  if python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$3"; else fail "$3: $(cat "$1")"; fi
}

# refuse <input file> <line> <stderr fragment> <label>
refuse() {
  bash "$PARSE" "$1" > "$TMP/r.out" 2> "$TMP/r.err"
  local rc=$?
  if [[ "$rc" == 2 && ! -s "$TMP/r.out" ]] \
     && grep -q "line $2:" "$TMP/r.err" && grep -q -- "$3" "$TMP/r.err"; then
    ok "RED: $4 (exit 2, line $2)"
  else
    fail "$4: expected exit 2, 'line $2:' and '$3' on stderr, empty stdout; got exit $rc, stderr: $(cat "$TMP/r.err"), stdout: $(head -c 200 "$TMP/r.out")"
  fi
}

echo "== the real paste =="

[[ -s "$FIX" && "$(tail -c 1 "$FIX" | od -An -c | tr -d ' ')" != '\n' ]] \
  && ok "the fixture is the captured paste (no trailing newline)" \
  || fail "the fixture is missing or has been retyped with a trailing newline"

bash "$PARSE" "$FIX" > "$TMP/real.json" 2> "$TMP/real.err"
rc=$?
[[ "$rc" == 0 ]] && ok "the real paste parses" \
  || fail "the real paste was refused (exit $rc): $(cat "$TMP/real.err")"

expect_json "$TMP/real.json" 'd == {"rows": [{"id": "audit-with-data", "gallery": "audit", "cell": "with-data", "verdict": "Needs changes", "notes": "la fila se ve bien", "asks": [], "provisional": False, "marks": [{"tile": "light-desktop", "x": 12.5, "y": 34.0, "w": 40.0, "h": 10.5, "note": "the breadcrumb wraps under the title"}, {"tile": "light-desktop", "x": 0.0, "y": 0.0, "w": 25.0, "h": 25.0, "note": "the logo is cut"}]}], "other": []}' \
  "the real paste is exactly one row with its verdict, notes and two marks"

bash "$PARSE" < "$FIX" > "$TMP/stdin.json" 2>/dev/null
cmp -s "$TMP/real.json" "$TMP/stdin.json" \
  && ok "stdin gives the same JSON as a file argument" \
  || fail "stdin and file input differ: $(diff "$TMP/real.json" "$TMP/stdin.json" | head -5)"

echo "== what is and is not a row =="

# The row is recognised by its heading, never by its marks: an approved row is
# the common case and it carries none.
{ cat "$FIX"; printf '\n\n### audit-empty · audit · empty\n\n- Approved'; } > "$TMP/approved.txt"
bash "$PARSE" "$TMP/approved.txt" > "$TMP/approved.json" 2>/dev/null
expect_json "$TMP/approved.json" 'len(d["rows"]) == 2 and d["rows"][1] == {"id": "audit-empty", "gallery": "audit", "cell": "empty", "verdict": "Approved", "notes": "", "asks": [], "provisional": False, "marks": []}' \
  "an approved row with no marks is still a row"

# A consultation item, the general-notes item, and a decoy whose title has the
# `a · b` shape but whose id is not `a-b`: all three land in `other`, untouched.
{ cat "$FIX"; printf '\n\n## G1 · Decisions\n\n### Q1 · Which one?\n\n- Option A\n\nbecause [mark this] is not a mark here\n\n### X9 · audit · with-data\n\n- Approved\n\n### notes · Notas generales\n\ntodo bien'; } > "$TMP/other.txt"
bash "$PARSE" "$TMP/other.txt" > "$TMP/other.json" 2> "$TMP/other.err"
expect_json "$TMP/other.json" 'len(d["rows"]) == 1 and d["other"] == [{"id": "Q1", "title": "Which one?", "body": "- Option A\n\nbecause [mark this] is not a mark here"}, {"id": "X9", "title": "audit · with-data", "body": "- Approved"}, {"id": "notes", "title": "Notas generales", "body": "todo bien"}]' \
  "non-gallery items land in other with id, title and raw body"

echo "== the answer block =="

# F1: a first paragraph of `- ` lines is the answer block only when every line
# is a known label. Dictated bullets are notes, not a verdict.
parsed '- the breadcrumb wraps\n- logo cut' \
  'r["verdict"] == "" and r["notes"] == "- the breadcrumb wraps\n- logo cut" and r["asks"] == [] and r["provisional"] is False' \
  "bullets that are not labels are notes, verdict empty"

parsed '- Needs changes [provisional]\n- [question]\n\nwhy?' \
  'r["verdict"] == "Needs changes" and r["asks"] == ["[question]"] and r["provisional"] is True and r["notes"] == "why?"' \
  "a provisional verdict with an ask splits into verdict, asks, provisional"

parsed '- Necesita cambios [provisional]\n- [explain-why]\n- [show-me]\n\n¿por qué?' \
  'r["verdict"] == "Necesita cambios" and r["asks"] == ["[explain-why]", "[show-me]"] and r["provisional"] is True and r["notes"] == "¿por qué?"' \
  "the Spanish verdict parses the same way, asks in paste order"

parsed '- No puedo juzgarla así' \
  'r["verdict"] == "No puedo juzgarla así" and r["notes"] == "" and r["provisional"] is False' \
  "a Spanish verdict with an accent is a verdict"

parsed '- Otra — lo explico en las notas\n\nla sombra' \
  'r["verdict"] == "Otra — lo explico en las notas" and r["notes"] == "la sombra"' \
  "the Spanish Other label is a verdict"

parsed '- Other — see my notes [provisional]\n- [reframe]' \
  'r["verdict"] == "Other — see my notes" and r["asks"] == ["[reframe]"] and r["provisional"] is True' \
  "the English Other label is a verdict"

parsed '- [not-now]' \
  'r["verdict"] == "" and r["asks"] == ["[not-now]"] and r["notes"] == ""' \
  "[not-now] is a marker, not a verdict"

parsed '- Approved\n- the logo is cut' \
  'r["verdict"] == "" and r["notes"] == "- Approved\n- the logo is cut"' \
  "one unknown line makes the whole paragraph notes"

# F3: only `[mark ` with the space is a mark candidate.
parsed '- Approved\n\n[markdown] rendering looks off\nsecond' \
  'r["verdict"] == "Approved" and r["notes"] == "[markdown] rendering looks off\nsecond" and r["marks"] == []' \
  "a note starting [markdown] is a note, not a malformed mark"

echo "== the mark line =="

mutate 10 '[mark light-desktop 0.0,0.0 25.0x25.0]' "$TMP/nonote.txt"
bash "$PARSE" "$TMP/nonote.txt" > "$TMP/nonote.json" 2>/dev/null
expect_json "$TMP/nonote.json" 'd["rows"][0]["marks"][1] == {"tile": "light-desktop", "x": 0.0, "y": 0.0, "w": 25.0, "h": 25.0, "note": ""}' \
  "a mark with nothing after ] parses to note \"\""

# The edge is inclusive: a mark the composer drew flush against the right and
# bottom edges (x+w == 100, y+h == 100) is a mark, not a refusal. A `>=` in the
# edge check is the defect this pins.
mutate 9 '[mark dark-mobile 33.3,0.0 66.7x100.0] flush' "$TMP/edge.txt"
bash "$PARSE" "$TMP/edge.txt" > "$TMP/edge.json" 2> "$TMP/edge.err"
expect_json "$TMP/edge.json" 'd["rows"][0]["marks"][0] == {"tile": "dark-mobile", "x": 33.3, "y": 0.0, "w": 66.7, "h": 100.0, "note": "flush"}' \
  "a mark flush against the right and bottom edges is accepted"

echo "== refusals: RED controls, one mutated line each =="

mutate 9 '[mark light-tablet 12.5,34.0 40.0x10.5] x' "$TMP/bad-tile.txt"
refuse "$TMP/bad-tile.txt" 9 "light-tablet" "a tile outside the four"

mutate 10 '[mark light-desktop 0.0,101.0 25.0x25.0] x' "$TMP/bad-range.txt"
refuse "$TMP/bad-range.txt" 10 "0-100" "a number above 100"

mutate 9 '[mark light-desktop 70.0,34.0 40.0x10.5] x' "$TMP/bad-xw.txt"
refuse "$TMP/bad-xw.txt" 9 "x+w" "x+w past the right edge"

mutate 9 '[mark light-desktop 12.5,90.0 40.0x10.5] x' "$TMP/bad-yh.txt"
refuse "$TMP/bad-yh.txt" 9 "y+h" "y+h past the bottom edge"

mutate 10 '[mark light-desktop 0,0 25x25] no decimals' "$TMP/bad-shape.txt"
refuse "$TMP/bad-shape.txt" 10 "does not match" "a [mark line off the contract (no decimal)"

mutate 10 '[mark light-desktop 0.0,0.0 25.0x25.0 the logo is cut' "$TMP/bad-bracket.txt"
refuse "$TMP/bad-bracket.txt" 10 "does not match" "a [mark line off the contract (no closing bracket)"

# Dictated speech after the paste cannot be told apart from notes, so text
# after a marked row's marks stays a refusal, and the message says what to feed.
{ cat "$FIX"; printf '\nstray text after the marks'; } > "$TMP/bad-after.txt"
refuse "$TMP/bad-after.txt" 11 "after the marks" "text after a row's marks"
refuse "$TMP/bad-after.txt" 11 "feed only the block the page's copy button produced" "the trailing-text refusal names what to feed"

# The composer's radios are single-choice; two answer-side labels in one block
# is not a paste it produced.
row '- Approved\n- Needs changes' "$TMP/two.txt"
refuse "$TMP/two.txt" 4 "more than one answer" "two answer-side labels in one row"

echo "== input =="

bash "$PARSE" --help > "$TMP/help.out" 2>&1
grep -q "exactly the block" "$TMP/help.out" \
  && ok "--help says the input is exactly the copied block" \
  || fail "--help does not say the input is exactly the copied block: $(cat "$TMP/help.out")"

# A BOM (Windows clipboards, some editors) right before the first `###` must
# not hide the row: read as plain utf-8, `\ufeff### ...` is not a heading.
{ printf '\xef\xbb\xbf'; tail -n +3 "$FIX"; } > "$TMP/bom.txt"
bash "$PARSE" "$TMP/bom.txt" > "$TMP/bom.json" 2> "$TMP/bom.err"
expect_json "$TMP/bom.json" 'len(d["rows"]) == 1 and d["rows"][0]["id"] == "audit-with-data"' \
  "a BOM before the first ### still yields the row (file)"
bash "$PARSE" < "$TMP/bom.txt" > "$TMP/bom-stdin.json" 2> "$TMP/bom.err"
expect_json "$TMP/bom-stdin.json" 'len(d["rows"]) == 1 and d["rows"][0]["id"] == "audit-with-data"' \
  "a BOM before the first ### still yields the row (stdin)"

echo
if [[ "$failures" == 0 ]]; then
  echo "test-gallery-reply: all passed"
  exit 0
fi
echo "test-gallery-reply: $failures failure(s)"
exit 1
