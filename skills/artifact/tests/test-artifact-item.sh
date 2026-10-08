#!/usr/bin/env bash
# test-artifact-item.sh — `artifact-item.sh` addresses ONE unit of a page's body
# sidecar: list the outline, get one unit, put one unit back.
#
# The whole point is what it must NOT do. `put` rewrites the unit and nothing else,
# byte for byte, so every edit here also asserts that the rest of the sidecar is
# unchanged. The parser is html.parser with offsets, not a regex, because the real
# pages nest an item inside a group and a greedy `<section ...>.*</section>` takes
# the block for the item — and because markup shown inside a `<pre>`, an id in an
# inline `<svg>` and CRLF line endings all appear on pages already on disk.
#
# Two kinds of fixture, on purpose. The consultation probe is wrapped for real, so
# the sidecar under test is the one the wrap writes and the edited result is proved
# to wrap again. The adversarial shapes (a duplicated id, markup shown inside a
# `<pre>`, CRLF) get a hand-written sidecar: check-artifact.sh FAILS a page that
# carries them, so a wrap could not have produced one, and this tool still has to
# survive them.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ITEM="$SKILL/scripts/artifact-item.sh"
WRAP="$SKILL/scripts/wrap-report.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

# Everything outside the edited unit is untouched: the two files differ by exactly
# the old unit and the new one, each appearing once.
assert_only_unit_changed() { # before after old-unit new-unit label
  python3 - "$@" <<'PY'
import sys
before, after, old_f, new_f, label = sys.argv[1:6]
r = lambda p: open(p, "rb").read().decode("utf-8")
b, a, old, new = r(before), r(after), r(old_f).rstrip("\r\n"), r(new_f).rstrip("\r\n")
problems = []
if b.count(old) != 1:
    problems.append("the old unit appears %d times in the original" % b.count(old))
if a.count(new) != 1:
    problems.append("the new unit appears %d times in the result" % a.count(new))
if not problems and b.replace(old, "\0", 1) != a.replace(new, "\0", 1):
    problems.append("bytes outside the unit changed")
print(("FAIL: %s — %s" % (label, "; ".join(problems))) if problems
      else "ok   — %s" % label)
sys.exit(1 if problems else 0)
PY
  [[ $? -eq 0 ]] || failures=$((failures + 1))
}

mkdir -p "$TMP/reports"
PREV="$TMP/reports/.aidex-artifact-prev"

# ---------------------------------------------------------------------------
# 1. The real page: a consultation that passes the contract, so its sidecar is
#    the one `wrap-report.sh --out` wrote. A group with two items inside it is
#    the nesting every consultation has.
cat > "$TMP/body.html" <<'HTML'
<meta name="consult-visual" content="none: a fixture has no shape to draw">
<div class="page"><main class="main">
<header><h1>Probe</h1><p class="standfirst">One page, several units.</p></header>
<section class="consult-group" id="G1" data-id="G1" data-title="The block">
  <div class="sec-head"><h2>The block</h2></div>
  <p>Shared context for both decisions.</p>
  <section class="consult-item" data-id="c1" data-free data-title="First claim">
    <h3>The first question</h3>
    <p class="fieldlabel">Notes on this one</p>
    <textarea placeholder="Notes"></textarea>
  </section>
  <section class="consult-item" data-id="c2" data-free data-title="Segunda afirmación">
    <h3>¿La segunda pregunta, con acentos?</h3>
    <p>Aquí hay una decisión más: ¿qué pasa con la configuración?</p>
    <p class="fieldlabel">Notes on this one</p>
    <textarea placeholder="Notas"></textarea>
  </section>
  <div class="group-notes"><p class="fieldlabel">Notes on this block</p><textarea></textarea></div>
</section>
<section class="consult-item consult-notes" data-id="notes" data-title="General notes">
  <h3>General notes</h3>
  <p class="fieldlabel">Notes for the whole page</p>
  <textarea></textarea>
</section>
<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>
<aside class="rail"><div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside>
<section id="sec-ref"><div class="sec-head"><h2>Where the figures come from</h2></div><p>Measured.</p></section>
</main><aside class="rail"><p class="railhead">Contents</p>
<nav class="raillist" id="raillist"></nav></aside></div>
HTML

bash "$WRAP" --title "Probe page" --lang en --in "$TMP/body.html" --out "$TMP/reports/page.html" \
  >/dev/null 2>"$TMP/wrap.err" || fail "the probe page does not pass the contract: $(tail -3 "$TMP/wrap.err")"
[[ -f "$PREV/page.html.body" ]] || fail "no sidecar to address — the rest of this file is vacuous"

bash "$ITEM" list "$TMP/reports/page.html" > "$TMP/list.txt" 2>&1 || fail "list exits non-zero"
grep -q "page.html.body" "$TMP/list.txt" || fail "list does not name the sidecar it read"
grep -qx "G1 · group · [0-9]* B · The block" "$TMP/list.txt" \
  || fail "G1 is not listed as a group: $(grep G1 "$TMP/list.txt")"
grep -qx "  c1 · item · [0-9]* B · First claim" "$TMP/list.txt" \
  || fail "c1 is not listed as an item nested under G1: $(grep c1 "$TMP/list.txt")"
grep -qx "  c2 · item · [0-9]* B · Segunda afirmación" "$TMP/list.txt" \
  || fail "c2 is not nested, or its non-ASCII title is mangled: $(grep c2 "$TMP/list.txt")"
grep -qx "notes · item · [0-9]* B · General notes" "$TMP/list.txt" \
  || fail "the general-notes item is not at the top level: $(grep notes "$TMP/list.txt")"
grep -qx "sec-ref · section · [0-9]* B · Where the figures come from" "$TMP/list.txt" \
  || fail "a plain <section id> is not listed as a section with its heading: $(grep sec-ref "$TMP/list.txt")"
[[ $(grep -c . "$TMP/list.txt") == 6 ]] \
  && ok "list prints one header line and the five units, items indented under their group" \
  || fail "expected a header and 5 units, got $(grep -c . "$TMP/list.txt") lines: $(cat "$TMP/list.txt")"

# get — exactly that unit, and the group is a strict superset of the item in it.
bash "$ITEM" get "$TMP/reports/page.html" c1 > "$TMP/c1.html" 2>&1 || fail "get c1 exits non-zero"
head -1 "$TMP/c1.html" | grep >/dev/null '^<section class="consult-item" data-id="c1"' \
  || fail "get c1 does not start at the item's own tag: $(head -1 "$TMP/c1.html")"
tail -1 "$TMP/c1.html" | grep >/dev/null -x '  </section>' || fail "get c1 does not end at the item's close tag"
if grep -q 'data-id="c2"' "$TMP/c1.html"; then fail "get c1 ran past the item into its sibling"
else ok "get c1 returns the item and stops at its close tag"; fi
bash "$ITEM" get "$TMP/reports/page.html" G1 > "$TMP/G1.html" 2>&1
if grep -q 'data-id="c1"' "$TMP/G1.html" && grep -q 'data-id="c2"' "$TMP/G1.html"; then
  ok "get G1 returns the whole block, both items inside it"
else fail "get G1 lost an item"; fi
[[ $(wc -c < "$TMP/G1.html") -gt $(wc -c < "$TMP/c1.html") ]] \
  && ok "the nested item is a strict slice of its group" || fail "the group is not larger than its item"
bash "$ITEM" get "$TMP/reports/page.html" c2 | grep >/dev/null "configuración" \
  && ok "get returns non-ASCII text intact" || fail "non-ASCII text did not survive get"

# put — the unit is replaced and nothing else moves.
cp "$PREV/page.html.body" "$TMP/before.body"
# The replacement is written the way `get` returned it: the unit's span starts at
# its own `<`, so the first line carries no indentation and the closing tag keeps
# the one it had.
cat > "$TMP/c1-new.html" <<'HTML'
<section class="consult-item" data-id="c1" data-free data-title="First claim">
    <h3>The first question, asked better</h3>
    <p>Qué existe hoy: dos archivos, uno de ellos vacío.</p>
    <p class="fieldlabel">Notes on this one</p>
    <textarea placeholder="Notes"></textarea>
  </section>
HTML
bash "$ITEM" put "$TMP/reports/page.html" c1 "$TMP/c1-new.html" > "$TMP/put.out" 2>&1 \
  || fail "put c1 exits non-zero: $(cat "$TMP/put.out")"
assert_only_unit_changed "$TMP/before.body" "$PREV/page.html.staged.body" "$TMP/c1.html" "$TMP/c1-new.html" \
  "put replaces the item and leaves every other byte alone"
grep -q "^next: .*wrap-report.sh --title 'Probe page' --lang en --in .*page.html.staged.body --out .*reports/page.html$" "$TMP/put.out" \
  && ok "put prints the wrap command to run next, with the page's own title and lang" \
  || fail "put's next-step line is wrong: $(grep next "$TMP/put.out")"
grep -q "c1 · [0-9]* B -> [0-9]* B" "$TMP/put.out" \
  || fail "put does not report what it wrote: $(head -1 "$TMP/put.out")"
bash "$ITEM" get "$TMP/reports/page.html" c1 | grep >/dev/null "asked better" \
  && ok "the outline still addresses the rewritten unit, still nested" || fail "the rewritten unit is not addressable"

# ...and the round closes: the edited sidecar is still a wrappable page.
bash "$WRAP" --title "Probe page" --lang en --in "$PREV/page.html.staged.body" --out "$TMP/reports/page.html" \
  >/dev/null 2>"$TMP/wrap2.err" \
  && ok "the edited sidecar wraps and passes the contract" \
  || fail "the edited sidecar no longer wraps: $(tail -3 "$TMP/wrap2.err")"

# ---------------------------------------------------------------------------
# 1b. A round ADDS a question to a block and DROPS one from it. That is an
#     ordinary revision, not a violation: the outer unit keeps its id, so what
#     changed is what is inside it. The first version refused it as "the unit's
#     identity changed (G1 -> G1)" — a message that named neither the cause nor
#     anything the writer could act on.
bash "$ITEM" get "$TMP/reports/page.html" G1 > "$TMP/G1-before.html" 2>&1
insert_item() { # insert_item <src> <dst> <id> <title>
  python3 - "$@" <<'PY'
import sys
src, dst, iid, title = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
item = ('  <section class="consult-item" data-id="%s" data-free data-title="%s">\n'
        '    <h3>A question added this round</h3>\n'
        '    <p class="fieldlabel">Notes on this one</p>\n'
        '    <textarea></textarea>\n'
        '  </section>\n') % (iid, title)
i = t.rstrip().rfind("</section>")
open(dst, "w", encoding="utf-8").write(t[:i] + item + t[i:])
PY
}
cp "$PREV/page.html.body" "$TMP/before-add.body"
insert_item "$TMP/G1-before.html" "$TMP/G1-add.html" c3 "Third claim"
if bash "$ITEM" put "$TMP/reports/page.html" G1 "$TMP/G1-add.html" >"$TMP/add.out" 2>&1; then
  ok "a block that gains an item is accepted"
else fail "put refuses a block that gained an item: $(cat "$TMP/add.out")"; fi
grep -q "nested: +c3" "$TMP/add.out" && ok "put names the nested id it added" \
  || fail "put does not say which nested id appeared: $(cat "$TMP/add.out")"
assert_only_unit_changed "$TMP/before-add.body" "$PREV/page.html.staged.body" \
  "$TMP/G1-before.html" "$TMP/G1-add.html" "the block grew by one item and nothing outside it moved"
bash "$ITEM" list "$TMP/reports/page.html" | grep >/dev/null -x "  c3 · item · [0-9]* B · Third claim" \
  && ok "the item added inside the block is addressable on its own" \
  || fail "the added item is not in the outline"
bash "$WRAP" --title "Probe page" --lang en --in "$PREV/page.html.staged.body" --out "$TMP/reports/page.html" \
  >/dev/null 2>"$TMP/wrap3.err" && ok "the grown block still wraps and passes the contract" \
  || fail "the grown block no longer wraps: $(tail -3 "$TMP/wrap3.err")"

cp "$PREV/page.html.body" "$TMP/before-rm.body"
if bash "$ITEM" put "$TMP/reports/page.html" G1 "$TMP/G1-before.html" >"$TMP/rm.out" 2>&1; then
  ok "a block that loses an item is accepted"
else fail "put refuses a block that lost an item: $(cat "$TMP/rm.out")"; fi
grep -q "nested: -c3" "$TMP/rm.out" && ok "put names the nested id it removed" \
  || fail "put does not say which nested id went away: $(cat "$TMP/rm.out")"
assert_only_unit_changed "$TMP/before-rm.body" "$PREV/page.html.staged.body" \
  "$TMP/G1-add.html" "$TMP/G1-before.html" "the block shrank by one item and nothing outside it moved"

# ...but an id the sidecar already uses elsewhere is still refused, and the
# message names the collision rather than the count.
cp "$PREV/page.html.staged.body" "$TMP/guard-collide.body"
insert_item "$TMP/G1-before.html" "$TMP/G1-collide.html" notes "Stolen id"
if bash "$ITEM" put "$TMP/reports/page.html" G1 "$TMP/G1-collide.html" >"$TMP/collide.out" 2>&1; then
  fail "put accepts a nested id that already exists elsewhere in the sidecar"
elif grep -q "notes" "$TMP/collide.out" && grep -qi "already" "$TMP/collide.out"; then
  ok "a nested id colliding with one elsewhere is refused, and the id is named"
else fail "the collision refusal does not name the id: $(cat "$TMP/collide.out")"; fi
cmp -s "$TMP/guard-collide.body" "$PREV/page.html.staged.body" || fail "the refused collision put wrote to the sidecar"

# ---------------------------------------------------------------------------
# 2. Refusals. Each one is a silent wrong edit if it is not refused.
if bash "$ITEM" get "$TMP/reports/page.html" c9 >"$TMP/e.txt" 2>&1; then
  fail "get of an unknown id succeeds"
elif grep -q "no unit 'c9'" "$TMP/e.txt" && grep -q "c1" "$TMP/e.txt"; then
  ok "an unknown id is refused and the known ids are named"
else fail "the unknown-id message does not list what is there: $(cat "$TMP/e.txt")"; fi

cp "$PREV/page.html.staged.body" "$TMP/guard.body"
printf '<section class="consult-item" data-id="c7"><h3>Renumbered</h3></section>\n' > "$TMP/c1-wrongid.html"
if bash "$ITEM" put "$TMP/reports/page.html" c1 "$TMP/c1-wrongid.html" >"$TMP/e1.txt" 2>&1; then
  fail "put accepts a replacement carrying a different id"
elif grep -q "carries 'c7', not 'c1'" "$TMP/e1.txt"; then
  ok "a replacement that renumbers the id is refused"
else fail "the wrong-id refusal is unclear: $(cat "$TMP/e1.txt")"; fi

cat > "$TMP/two.html" <<'HTML'
<section class="consult-item" data-id="c1"><h3>One</h3></section>
<section class="consult-item" data-id="c8"><h3>Two</h3></section>
HTML
if bash "$ITEM" put "$TMP/reports/page.html" c1 "$TMP/two.html" >"$TMP/e2.txt" 2>&1; then
  fail "put accepts two elements as the replacement of one unit"
elif grep -q "exactly one addressable element" "$TMP/e2.txt"; then
  ok "a replacement holding two units is refused"
else fail "the two-unit refusal is unclear: $(cat "$TMP/e2.txt")"; fi

printf '<p>Loose prose.</p>\n<section class="consult-item" data-id="c1"><h3>One</h3></section>\n' > "$TMP/loose.html"
if bash "$ITEM" put "$TMP/reports/page.html" c1 "$TMP/loose.html" >"$TMP/e3.txt" 2>&1; then
  fail "put accepts content sitting outside the replacement element"
elif grep -q "content outside its outer element" "$TMP/e3.txt"; then
  ok "prose outside the replacement element is refused"
else fail "the stray-content refusal is unclear: $(cat "$TMP/e3.txt")"; fi

# A page built from `<stem>.spec.md` is an output of that spec. A put plus a
# passing re-wrap advances the baseline, so spec_build's hand-edit guard cannot
# see the change and the next build silently reverts it.
bash "$ITEM" get "$TMP/reports/page.html" c1 | sed 's/The first question/The first question, edited/' > "$TMP/c1-same.html"
printf '# spec\n' > "$TMP/reports/page.spec.md"
if bash "$ITEM" put "$TMP/reports/page.html" c1 "$TMP/c1-same.html" >"$TMP/e5.txt" 2>&1; then
  fail "put edits the sidecar of a page that is built from page.spec.md"
elif grep -q "page.spec.md" "$TMP/e5.txt"; then
  ok "a put on a spec-built page is refused and the spec is named"
else fail "the spec-built refusal does not name the spec: $(cat "$TMP/e5.txt")"; fi
rm -f "$TMP/reports/page.spec.md"

cmp -s "$TMP/guard.body" "$PREV/page.html.staged.body" && ok "every refused put wrote nothing" \
  || fail "a refused put modified the sidecar"

# No sidecar at all — the one case a reviser meets on a page that predates it. The page
# EXISTS: exit 1 with the full guidance (a state to repair, not a wrong argument).
printf '<p>old</p>\n' > "$TMP/reports/nosidecar.html"
bash "$ITEM" list "$TMP/reports/nosidecar.html" >"$TMP/e4.txt" 2>&1; rc=$?
if [[ $rc -ne 1 ]]; then
  fail "list of an existing page with no sidecar exits $rc, expected 1"
elif grep -q "no body sidecar" "$TMP/e4.txt" && grep -q "wrap-report.sh --in" "$TMP/e4.txt" \
     && grep -q "02-local-first-artifacts.md" "$TMP/e4.txt"; then
  ok "a page with no sidecar: exit 1, names the fallback and the canon"
else fail "the missing-sidecar message does not point anywhere: $(cat "$TMP/e4.txt")"; fi
# A page path that names nothing is a wrong argument: exit 2, one usage line.
bash "$ITEM" list "$TMP/reports/nosuch.html" >"$TMP/e5.txt" 2>&1; rc=$?
[[ $rc -eq 2 && $(grep -c . "$TMP/e5.txt") -eq 1 ]] && grep -q "^usage: .*no such page" "$TMP/e5.txt" \
  && ok "a page that does not exist: exit 2, one usage line" \
  || fail "missing page: exit $rc, output: $(cat "$TMP/e5.txt")"

# Pipes are valid inputs (--in /dev/stdin, <(...)): a regular-file test refuses them.
cat "$TMP/body.html" | bash "$WRAP" --title Probe --lang en --in /dev/stdin --out "$TMP/reports/pipe.html" >/dev/null 2>"$TMP/pipe.err"
[[ $? -eq 0 ]] && ok "wrap-report --in /dev/stdin is accepted" || fail "wrap-report --in /dev/stdin: $(head -c 300 "$TMP/pipe.err")"
printf '# Informe\n\n## Uno\n\nViejo.\n' > "$TMP/pipe.md"
bash "$WRAP" --title Pipe --lang es --in "$TMP/pipe.md" --out "$TMP/reports/pipemd.html" >/dev/null 2>&1
printf '## Uno\n\nNuevo.\n' | bash "$ITEM" put "$TMP/reports/pipemd.html" sec-uno /dev/stdin >/dev/null 2>"$TMP/pipe2.err"
rc=$?
[[ $rc -eq 0 ]] && grep -q "Nuevo." "$PREV/pipemd.html.staged.body.md" \
  && ok "artifact-item put <file> accepts /dev/stdin" \
  || fail "put from /dev/stdin: rc=$rc $(head -c 300 "$TMP/pipe2.err")"

# ---------------------------------------------------------------------------
# 3. The shapes a wrap cannot produce, addressed straight on a hand-written
#    sidecar: markup shown inside a <pre>, an id repeated inside an inline <svg>,
#    a title that has to come from the heading, and a genuinely duplicated id.
mkdir -p "$TMP/hand/.aidex-artifact-prev"
cat > "$TMP/hand/.aidex-artifact-prev/h.html.body" <<'HTML'
<div class="page"><main class="main">
<section class="consult-group" id="G1" data-id="G1">
  <h2>El bloque</h2>
  <section class="consult-item" data-id="c1">
    <h3>¿La primera pregunta?</h3>
    <svg viewBox="0 0 10 10"><g id="c1" data-id="c1"><rect width="4" height="4"/></g></svg>
    <pre>&lt;section data-id="ghost1"&gt;escaped markup&lt;/section&gt;</pre>
    <pre><section data-id="ghost2">literal markup inside pre</section></pre>
  </section>
</section>
<!-- <section data-id="ghost3">a commented-out item</section> -->
</main></div>
HTML
bash "$ITEM" list "$TMP/hand/h.html" > "$TMP/hlist.txt" 2>&1 || fail "list on the hand-written sidecar exits non-zero"
if grep -q "ghost" "$TMP/hlist.txt"; then fail "a data-id inside <pre> or a comment is addressable: $(grep ghost "$TMP/hlist.txt")"
else ok "ids inside <pre> and inside comments are not units"; fi
[[ $(grep -c "^  c1 · " "$TMP/hlist.txt") == 1 ]] \
  && ok "an id repeated inside an inline <svg> does not duplicate the item" \
  || fail "the <svg> id collides with the item that contains it: $(cat "$TMP/hlist.txt")"
grep -qx "  c1 · item · [0-9]* B · ¿La primera pregunta?" "$TMP/hlist.txt" \
  && ok "an item with no data-title takes its heading text, accents and all" \
  || fail "the heading fallback title is wrong: $(grep c1 "$TMP/hlist.txt")"
grep -qx "G1 · group · [0-9]* B · El bloque" "$TMP/hlist.txt" \
  || fail "the group's heading fallback is wrong: $(grep G1 "$TMP/hlist.txt")"
bash "$ITEM" get "$TMP/hand/h.html" c1 | grep >/dev/null "ghost2" \
  && ok "the <pre> the item contains still comes back inside it" \
  || fail "get c1 dropped the <pre> inside the item"

# A unit whose attributes carry a literal ">" — a before/after title is the way it
# shows up. The span has to come from the parser: scanning for the first ">" ends
# the tag inside the attribute value and returns half a unit.
mkdir -p "$TMP/gt/.aidex-artifact-prev"
cat > "$TMP/gt/.aidex-artifact-prev/g.html.body" <<'HTML'
<div class="page"><main class="main">
<img data-id="fig1" data-title="antes>después" src="data:image/gif;base64,R0lGOD" alt="El diagrama">
<section class="consult-item" data-id="c1" data-title="a>b"><h3>Con signo</h3></section>
</main></div>
HTML
bash "$ITEM" list "$TMP/gt/g.html" > "$TMP/gtlist.txt" 2>&1 || fail "list over a '>' in an attribute exits non-zero"
grep -qx 'fig1 · item · [0-9]* B · antes>después' "$TMP/gtlist.txt" \
  && ok "a void element carrying data-id is a unit, title and all" \
  || fail "the void unit is missing or mis-titled: $(cat "$TMP/gtlist.txt")"
bash "$ITEM" get "$TMP/gt/g.html" fig1 > "$TMP/gt-fig1.txt" 2>&1
grep -q 'alt="El diagrama">$' "$TMP/gt-fig1.txt" \
  && ok "the unit's span ends at the real end of the tag, not at the '>' inside an attribute" \
  || fail "get truncated the tag at the '>' in its attribute: $(cat "$TMP/gt-fig1.txt")"
bash "$ITEM" get "$TMP/gt/g.html" c1 | grep >/dev/null '</section>$' \
  || fail "a container unit with '>' in an attribute is truncated: $(bash "$ITEM" get "$TMP/gt/g.html" c1)"
cp "$TMP/gt/.aidex-artifact-prev/g.html.body" "$TMP/gt-before.body"
printf '<img data-id="fig1" data-title="antes>después" src="data:image/gif;base64,R0lGOD" alt="El diagrama, v2">' > "$TMP/gt-new.txt"
bash "$ITEM" put "$TMP/gt/g.html" fig1 "$TMP/gt-new.txt" >/dev/null 2>&1 \
  || fail "put on a void unit fails"
assert_only_unit_changed "$TMP/gt-before.body" "$TMP/gt/.aidex-artifact-prev/g.html.staged.body" \
  "$TMP/gt-fig1.txt" "$TMP/gt-new.txt" "put on a void unit replaces the whole tag and nothing else"

# A replacement whose markup does not CLOSE the way it looks. Both shapes below
# were written, accepted and left a sidecar whose next wrap passed the contract,
# because the parser and the browser disagreed about where the unit ends.
mkdir -p "$TMP/sc/.aidex-artifact-prev"
cat > "$TMP/sc/.aidex-artifact-prev/s.html.body" <<'HTML'
<div class="page"><main class="main">
<div class="consult-item" data-id="q3"><h3>Tres</h3></div>
<div class="consult-item" data-id="q9"><h3>Nueve</h3></div>
</main></div>
HTML
cp "$TMP/sc/.aidex-artifact-prev/s.html.body" "$TMP/sc-before.body"
bash "$ITEM" list "$TMP/sc/s.html" > "$TMP/sclist.txt" 2>&1
grep -qx "q3 · item · [0-9]* B · Tres" "$TMP/sclist.txt" && grep -qx "q9 · item · [0-9]* B · Nueve" "$TMP/sclist.txt" \
  && ok "two sibling items are both at the top level of the outline" \
  || fail "the sibling fixture is not what the test assumes: $(cat "$TMP/sclist.txt")"

# B-1: a self-closing NON-void tag. HTML ignores the slash on a <div>, so q9 stops
# being a sibling and becomes content of q3 — in the browser, in the composer, and
# in the next round's outline. The contract check never sees it.
printf '<div class="consult-item" data-id="q3"/>\n' > "$TMP/sc-selfclose.html"
if bash "$ITEM" put "$TMP/sc/s.html" q3 "$TMP/sc-selfclose.html" >"$TMP/e8.txt" 2>&1; then
  fail "put accepts a unit declared with a self-closing <div/>"
elif grep -q "q3" "$TMP/e8.txt" && grep -qi "self-clos" "$TMP/e8.txt"; then
  ok "a self-closing non-void element is refused, and the id is named"
else fail "the self-closing refusal is unclear: $(cat "$TMP/e8.txt")"; fi
cmp -s "$TMP/sc-before.body" "$TMP/sc/.aidex-artifact-prev/s.html.body" \
  && ok "the refused self-closing put left the sidecar byte for byte" \
  || fail "the refused self-closing put wrote to the sidecar"

# B-2: an unclosed nested element. The close tag belongs to the OUTER element, so
# the inner unit is never closed — and its id, which already exists elsewhere in
# the sidecar, was invisible to the collision check.
printf '<div class="consult-item" data-id="q3"><span data-id="q9">x</div>\n' > "$TMP/sc-unclosed.html"
if bash "$ITEM" put "$TMP/sc/s.html" q3 "$TMP/sc-unclosed.html" >"$TMP/e9.txt" 2>&1; then
  fail "put accepts a replacement with an unclosed nested unit"
elif grep -q "q9" "$TMP/e9.txt" && grep -qi "unclosed\|never closed" "$TMP/e9.txt"; then
  ok "an unclosed nested element is refused, and the id it hides is named"
else fail "the unclosed-element refusal is unclear: $(cat "$TMP/e9.txt")"; fi
cmp -s "$TMP/sc-before.body" "$TMP/sc/.aidex-artifact-prev/s.html.body" \
  && ok "the refused unclosed put left the sidecar byte for byte" \
  || fail "the refused unclosed put wrote to the sidecar"
bash "$ITEM" list "$TMP/sc/s.html" > "$TMP/sclist2.txt" 2>&1
cmp -s "$TMP/sclist.txt" "$TMP/sclist2.txt" \
  && ok "after both refusals q3 and q9 are still siblings" \
  || fail "the outline changed under a refused put: $(cat "$TMP/sclist2.txt")"

# The same slash on a VOID element is ordinary HTML and stays accepted.
printf '<img data-id="q3" data-title="Tres" alt="x"/>\n' > "$TMP/sc-void.html"
bash "$ITEM" put "$TMP/sc/s.html" q3 "$TMP/sc-void.html" >/dev/null 2>&1 \
  && ok "a self-closing VOID element is still a legitimate unit" \
  || fail "put refuses <img ... /> , which is ordinary HTML"

mkdir -p "$TMP/dup/.aidex-artifact-prev"
cat > "$TMP/dup/.aidex-artifact-prev/d.html.body" <<'HTML'
<div class="page"><main class="main">
<section class="consult-item" data-id="c1"><h3>First</h3></section>
<section class="consult-item" data-id="c1"><h3>Second</h3></section>
</main></div>
HTML
if bash "$ITEM" get "$TMP/dup/d.html" c1 >"$TMP/e5.txt" 2>&1; then
  fail "get of a duplicated id picks one silently"
elif grep -q "appears 2 times" "$TMP/e5.txt"; then ok "a duplicated id is refused, not guessed"
else fail "the duplicate refusal is unclear: $(cat "$TMP/e5.txt")"; fi

# CRLF: a body that arrived with Windows line endings comes back with them.
mkdir -p "$TMP/crlf/.aidex-artifact-prev"
printf '<div class="page"><main class="main">\r\n<section class="consult-item" data-id="c1"><h3>Uno</h3></section>\r\n<section id="sec-b"><h2>Dos</h2></section>\r\n</main></div>\r\n' \
  > "$TMP/crlf/.aidex-artifact-prev/w.html.body"
cp "$TMP/crlf/.aidex-artifact-prev/w.html.body" "$TMP/crlf-before.body"
bash "$ITEM" get "$TMP/crlf/w.html" c1 > "$TMP/crlf-c1.html" 2>&1
printf '<section class="consult-item" data-id="c1"><h3>Uno, otra vez</h3></section>' > "$TMP/crlf-new.html"
bash "$ITEM" put "$TMP/crlf/w.html" c1 "$TMP/crlf-new.html" >/dev/null 2>&1 || fail "put on a CRLF sidecar fails"
assert_only_unit_changed "$TMP/crlf-before.body" "$TMP/crlf/.aidex-artifact-prev/w.html.staged.body" \
  "$TMP/crlf-c1.html" "$TMP/crlf-new.html" "a CRLF sidecar keeps its line endings outside the unit"
[[ $(grep -c $'\r' "$TMP/crlf/.aidex-artifact-prev/w.html.body") == 4 ]] \
  && ok "all four CR bytes survive the edit" \
  || fail "CR bytes were lost: $(grep -c $'\r' "$TMP/crlf/.aidex-artifact-prev/w.html.body") left"

# ---------------------------------------------------------------------------
# 4. The markdown sidecar: the `## ` sections, addressed by the slug md_body
#    gives them in the RENDERED page — including the -2 suffix on a repeated
#    heading and the fence rule that keeps a heading inside a code block out.
cat > "$TMP/report.md" <<'MD'
# Informe de prueba

Una línea de resumen.

## Qué encontramos

Un párrafo con acentuación: la configuración está vacía.

```bash
grep '## Notes' file.md
```

## Notes

Primera.

## Notes

Segunda.
MD
bash "$WRAP" --title "Informe" --lang es --in "$TMP/report.md" --out "$TMP/reports/md.html" \
  >/dev/null 2>"$TMP/wrapmd.err" || fail "the markdown probe does not pass the contract: $(tail -3 "$TMP/wrapmd.err")"
bash "$ITEM" list "$TMP/reports/md.html" > "$TMP/mdlist.txt" 2>&1 || fail "list on a markdown sidecar exits non-zero"
grep -qx "sec-qu-encontramos · section · [0-9]* B · Qué encontramos" "$TMP/mdlist.txt" \
  || fail "the first md section is not listed by its rendered slug: $(cat "$TMP/mdlist.txt")"
grep -qx "sec-notes · section · [0-9]* B · Notes" "$TMP/mdlist.txt" || fail "sec-notes is missing"
grep -qx "sec-notes-2 · section · [0-9]* B · Notes" "$TMP/mdlist.txt" \
  || fail "the repeated heading does not take md_body's -2 suffix: $(cat "$TMP/mdlist.txt")"
[[ $(grep -c . "$TMP/mdlist.txt") == 4 ]] \
  && ok "a heading inside a fence is not a unit (3 sections, not 4)" \
  || fail "the fenced heading opened a section: $(cat "$TMP/mdlist.txt")"
grep -q 'id="sec-notes-2"' "$TMP/reports/md.html" \
  && ok "the md ids are the ids the rendered page really carries" \
  || fail "the md outline invents ids the page does not have"

bash "$ITEM" get "$TMP/reports/md.html" sec-qu-encontramos > "$TMP/md-sec.txt" 2>&1
head -1 "$TMP/md-sec.txt" | grep >/dev/null -x "## Qué encontramos" || fail "md get does not start at the heading"
grep -q "grep '## Notes'" "$TMP/md-sec.txt" && ok "md get keeps the fenced block that belongs to the section" \
  || fail "md get truncated the section at the fenced heading"
if grep -q "^## Notes$" "$TMP/md-sec.txt"; then fail "md get ran into the next section"
else ok "md get stops at the next heading"; fi

cp "$PREV/md.html.body.md" "$TMP/md-before.md"
printf '## Qué encontramos\n\nReescrito: la configuración tiene dos claves.\n' > "$TMP/md-new.md"
bash "$ITEM" put "$TMP/reports/md.html" sec-qu-encontramos "$TMP/md-new.md" >"$TMP/mdput.out" 2>&1 \
  || fail "put on a markdown sidecar fails: $(cat "$TMP/mdput.out")"
python3 - "$TMP/md-before.md" "$PREV/md.html.staged.body.md" <<'PY'
import sys
b, a = (open(p, encoding="utf-8").read() for p in sys.argv[1:3])
head = "# Informe de prueba\n\nUna línea de resumen.\n\n"
tail = "\n## Notes\n\nPrimera.\n\n## Notes\n\nSegunda.\n"
bad = []
if not a.startswith(head): bad.append("the header above the first section changed")
if not a.endswith(tail): bad.append("the sections after the edited one changed")
if "Reescrito" not in a: bad.append("the new content is not there")
if "Un párrafo" in a: bad.append("the old content is still there")
print("FAIL: md put rewrote more than its section — " + "; ".join(bad) if bad
      else "ok   — md put replaces one section and leaves the rest byte for byte")
sys.exit(1 if bad else 0)
PY
[[ $? -eq 0 ]] || failures=$((failures + 1))

# A renamed heading changes the slug, so the id the reviser addressed would stop
# existing: refused. This is the markdown half of "ids are never renumbered".
cp "$PREV/md.html.staged.body.md" "$TMP/md-guard.md"
printf '## Otro título\n\nTexto.\n' > "$TMP/md-renamed.md"
if bash "$ITEM" put "$TMP/reports/md.html" sec-notes "$TMP/md-renamed.md" >"$TMP/e6.txt" 2>&1; then
  fail "put accepts a markdown section whose heading renames its id"
elif grep -q "changes the unit's identity" "$TMP/e6.txt"; then ok "a renamed md heading is refused"
else fail "the md rename refusal is unclear: $(cat "$TMP/e6.txt")"; fi
# A markdown section that gains a `## ` of its own is the one case the html side
# allows and this one cannot: the new heading is a SIBLING section, and every slug
# after it shifts. The refusal has to say that, not "the identity changed".
printf '## Notes\n\nPrimera.\n\n## Añadida\n\nNueva.\n' > "$TMP/md-split.md"
if bash "$ITEM" put "$TMP/reports/md.html" sec-notes "$TMP/md-split.md" >"$TMP/e7.txt" 2>&1; then
  fail "put accepts a markdown replacement that adds a second section"
elif grep -q "number of \`## \` sections (3 -> 4)" "$TMP/e7.txt" && grep -q "renamed" "$TMP/e7.txt"; then
  ok "adding a section inside a markdown put is refused, and the message says why"
else fail "the md section-count refusal is unclear: $(cat "$TMP/e7.txt")"; fi

cmp -s "$TMP/md-guard.md" "$PREV/md.html.staged.body.md" && ok "the refused md put wrote nothing" \
  || fail "a refused md put modified the sidecar"

bash "$WRAP" --title "Informe" --lang es --in "$PREV/md.html.staged.body.md" --out "$TMP/reports/md.html" \
  >/dev/null 2>"$TMP/wrapmd2.err" \
  && ok "the edited markdown sidecar wraps and passes the contract" \
  || fail "the edited markdown sidecar no longer wraps: $(tail -3 "$TMP/wrapmd2.err")"

# ---------------------------------------------------------------------------
# BL-731 (owner: staging). `put` writes the edit to a staging file beside the
# sidecar and the sidecar changes only when a wrap PASSES. Before this, put
# rewrote the sidecar itself, so a failing wrap restored the page but left the
# sidecar holding the failing content, and the wrap's "left exactly as they
# were" was false. The rule for several puts before one wrap: each put applies
# on top of the staged content, and a passing wrap retires the staging file.
bash "$WRAP" --title "Staged" --lang en --in "$TMP/body.html" --out "$TMP/reports/st.html" \
  >/dev/null 2>"$TMP/st0.err" || fail "the staging probe does not wrap: $(tail -3 "$TMP/st0.err")"
cp "$PREV/st.html.body" "$TMP/st-passing.body"
cat > "$TMP/st-bad.html" <<'HTML'
<section class="consult-item" data-id="c1" data-free data-title="First claim">
    <h3>zzzbroken: no notes box any more</h3>
  </section>
HTML
bash "$ITEM" put "$TMP/reports/st.html" c1 "$TMP/st-bad.html" > "$TMP/st-put1.out" 2>&1 \
  || fail "BL-731: put of the failing c1 exits non-zero: $(cat "$TMP/st-put1.out")"
cmp -s "$TMP/st-passing.body" "$PREV/st.html.body" \
  && ok "BL-731: put leaves the sidecar alone until a wrap passes" \
  || fail "BL-731: put rewrote the sidecar before any wrap"
next1="$(sed -n 's/^next: //p' "$TMP/st-put1.out")"
eval "$next1" >/dev/null 2>"$TMP/st-wrap1.err" && fail "BL-731: the probe edit was meant to FAIL the contract and passed"
cmp -s "$TMP/st-passing.body" "$PREV/st.html.body" \
  && ok "BL-731: after a failing wrap the sidecar is still the last passing content" \
  || fail "BL-731: a failing wrap left the failing content in the sidecar: $(grep -c zzzbroken "$PREV/st.html.body") zzzbroken line(s)"
cat > "$TMP/st-c2.html" <<'HTML'
<section class="consult-item" data-id="c2" data-free data-title="Segunda afirmación">
    <h3>zzzsecond edit, staged on top</h3>
    <p class="fieldlabel">Notes on this one</p>
    <textarea></textarea>
  </section>
HTML
bash "$ITEM" put "$TMP/reports/st.html" c2 "$TMP/st-c2.html" > "$TMP/st-put2.out" 2>&1 \
  || fail "BL-731: the second put exits non-zero: $(cat "$TMP/st-put2.out")"
bash "$ITEM" get "$TMP/reports/st.html" c1 | grep >/dev/null zzzbroken \
  && ok "BL-731: a second put applies on top of the staged edit (get reads the staged content)" \
  || fail "BL-731: the second put dropped the first staged edit"
bash "$ITEM" put "$TMP/reports/st.html" c1 "$TMP/c1-new.html" > "$TMP/st-put3.out" 2>&1 \
  || fail "BL-731: the fixing put exits non-zero: $(cat "$TMP/st-put3.out")"
next3="$(sed -n 's/^next: //p' "$TMP/st-put3.out")"
if eval "$next3" >/dev/null 2>"$TMP/st-wrap3.err"; then
  grep -q "asked better" "$PREV/st.html.body" && grep -q "zzzsecond" "$PREV/st.html.body" \
    && ok "BL-731: a passing wrap lands both staged edits in the sidecar" \
    || fail "BL-731: the passing wrap did not land the staged edits in the sidecar"
  ls "$PREV" | grep >/dev/null '^st\.html\.staged' \
    && fail "BL-731: the staging file outlived the passing wrap: $(ls "$PREV" | grep staged)" \
    || ok "BL-731: a passing wrap retires the staging file"
else fail "BL-731: the fixed staged content does not wrap: $(tail -3 "$TMP/st-wrap3.err")"; fi

[[ $failures -eq 0 ]] && echo "PASS: artifact item" || { echo "FAILED: $failures"; exit 1; }
