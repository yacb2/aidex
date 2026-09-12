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
    printf '%s\n' "$body"
    printf '</main></div>\n<script>var blank = 0;</script>\n</body>\n</html>\n'
  } > "$out"
}

visual='<meta name="consult-visual" content="none: fixtures have no shape to draw">'
header='<header><p class="eyebrow">FIXTURE</p><h1>Claim</h1><p class="standfirst">The thesis.</p></header>'
ledger='<section id="sec-ledger"><div class="sec-head"><h2>Settled</h2></div><div class="ledger"><div><span class="k">d1</span><span class="v"><b>Done.</b> x</span></div></div></section>'
notes='<section class="consult-item consult-notes" data-id="notes" data-title="General notes"><h3>General notes</h3><textarea></textarea></section>'
bars='<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div>'
ref='<section id="sec-ref"><div class="sec-head"><h2>Where the figures come from</h2></div><p>Measured.</p></section>'
item() {  # item <id> <title>
  printf '<section class="consult-item" data-id="%s" data-title="%s"><h3>%s</h3><textarea></textarea></section>' "$1" "$2" "$2"
}
group() {  # group <id> <title> <items-html>
  printf '<section class="consult-group" id="%s" data-id="%s" data-title="%s"><div class="sec-head"><p class="eyebrow">Block %s</p><h2>%s</h2></div><p>The context this block shares.</p>%s</section>' "$1" "$1" "$2" "$1" "$2" "$3"
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

# --- a read page (no items) is untouched by the shape rules -------------------
mkpage "$TMP/read.html" "$header<section id=\"a\"><h2>One</h2><p>x</p></section><section id=\"b\"><h2>Two</h2><p>y</p></section>"
rc="$(run "$TMP/read.html")"
[[ "$rc" == 0 ]] || fail "a read page has no shape rules: $(cat "$TMP/out")"

# --- a group id kept across rounds names the same context ---------------------
mkpage "$TMP/v1.html" "$good"
mkpage "$TMP/v2.html" "$visual$header$ledger$(group G1 'A different context' "$(item Q1 'First')$(item Q2 'Second')")$(group G2 'Context two' "$(item Q3 'Third')")$notes$bars$ref"
rc="$(run "$TMP/v2.html" --prev "$TMP/v1.html")"; expect_fail "group id reused for a different context" "G1"

# --- the group is not counted as an item ---------------------------------------
# It carries data-id/data-title for --prev; it has no reply surface of its own
# and must not be reported as an item the reader cannot answer.
grep -q "G1.*no reply surface\|G1.*no notes" "$TMP/out" && fail "a group was judged as an item"
rc="$(run "$TMP/good.html")"
grep -q "G1\|G2" "$TMP/out" && fail "a group was reported on a passing page: $(cat "$TMP/out")"

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "ok: consultation shape (8 cases)"
