#!/usr/bin/env bash
# test-artifact-contract.sh — unit tests for wrap-report.sh + check-artifact.sh,
# the deterministic half of rules/artifacts-local-first.md.
#
# No API cost and no `claude -p`: the expensive behavioral eval
# (tests/eval-local-first-behavior.sh) calls the same checker, so the assertion
# logic is proven here and merely reused there.
#
# Run with: bash skills/aidex-dash/tests/test-artifact-contract.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
WRAP="$SCRIPTS/wrap-report.sh"
CHECK="$SCRIPTS/check-artifact.sh"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

BODY='<style>:root{--ink:#111}
@media (prefers-color-scheme: dark){:root{--ink:#eee}}</style>
<div class="page"><main class="main"><h1>Informe</h1><p>Acentuaci&oacute;n y datos.</p></main></div>'

echo "== wrap-report.sh =="

printf '%s\n' "$BODY" | bash "$WRAP" --title "Report title" --lang es --favicon "*" > "$TMP/wrapped.html"
grep -qi '^<!doctype html>' "$TMP/wrapped.html" && ok "emits a doctype" || bad "no doctype emitted"
grep -q '<html lang="es">' "$TMP/wrapped.html" && ok "carries the requested lang" || bad "lang not applied"
grep -q '<meta charset="utf-8">' "$TMP/wrapped.html" && ok "emits charset" || bad "no charset"
grep -q 'name="viewport"' "$TMP/wrapped.html" && ok "emits viewport" || bad "no viewport"
grep -q '<title>Report title</title>' "$TMP/wrapped.html" && ok "emits the title" || bad "title missing"
grep -q 'rel="icon"' "$TMP/wrapped.html" && ok "favicon inlined as a data URI" || bad "favicon not inlined"
grep -q 'box-sizing' "$TMP/wrapped.html" && ok "minimal reset present" || bad "reset missing"

# The author's own <style> must land in <head>, AFTER the reset, so its rules win.
python3 - "$TMP/wrapped.html" <<'PY' && ok "author style lifted into head, after the reset" || bad "author style not ordered after the reset in head"
import sys, re
t = open(sys.argv[1], encoding="utf-8").read()
head = t[t.index("<head>"):t.index("</head>")]
sys.exit(0 if "--ink" in head and head.index("box-sizing") < head.index("--ink") else 1)
PY

# The envelope must not be applied twice.
if printf '%s\n' "$BODY" | bash "$WRAP" --title "x" | bash "$WRAP" --title "x" >/dev/null 2>&1; then
  bad "wrapping an already-wrapped document was accepted"
else
  ok "refuses to wrap a document that already has a doctype"
fi

echo "== check-artifact.sh =="

bash "$CHECK" "$TMP/wrapped.html" >/dev/null 2>&1 \
  && ok "wrapped output passes the contract" || bad "wrapped output failed its own contract"

# Each defect is caught, one fixture per rule.
mk() { printf '%s' "$2" > "$TMP/$1"; }
mk fragment.html "<title>t</title><style>@media (prefers-color-scheme: dark){}</style><h1>x</h1>"
mk nocharset.html "<!doctype html><title>t</title><style>@media (prefers-color-scheme: dark){}</style><meta name=\"viewport\" content=\"width=device-width\">"
mk nothemes.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><h1>x</h1>"
mk extcss.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><link rel=\"stylesheet\" href=\"https://cdn.example/x.css\"><style>@media (prefers-color-scheme: dark){}</style>"
mk extjs.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><script src=\"https://cdn.example/x.js\"></script><style>@media (prefers-color-scheme: dark){}</style>"
mk extimg.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><img src=\"https://example.com/x.png\">"
# The font src is on its own line: the block is flattened before matching, so a
# realistically-formatted @font-face must still be caught.
mk extfont.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>
@font-face{
  font-family: Inter;
  src: url(https://fonts.gstatic.com/s/inter/v1/x.woff2) format('woff2');
}
@media (prefers-color-scheme: dark){}</style>"

# `notitle.html` is here because no fixture omitted <title> — every page above
# carries `<title>t</title>` and every wrapper-produced page gets one from
# --title, so the `title` check had no discriminating input at all. Deleting it
# from the checker left the suite fully green, verified by mutation.
mk notitle.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><style>@media (prefers-color-scheme: dark){}</style><h1>x</h1>"

# `fragment` is paired with `viewport` as well as `doctype`: it is the only page
# without a viewport meta, and the loop only ever asserted `[doctype]` on it, so
# `[viewport]` was asserted nowhere in the file.
for case in "fragment doctype" "fragment viewport" "notitle title" \
            "nocharset charset" "nothemes themes" \
            "extcss self" "extjs self" "extimg self" "extfont self"; do
  set -- $case
  out="$(bash "$CHECK" "$TMP/$1.html" 2>&1)"
  if [[ "$out" == *"[$2]"* ]]; then ok "catches $2 ($1.html)"; else bad "did not catch $2 in $1.html: $out"; fi
done

# An inlined font is the compliant form — the remote-font check must not flag it.
mk datafont.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>
@font-face{font-family:Inter;src:url(data:font/woff2;base64,AAAA) format('woff2');}
@media (prefers-color-scheme: dark){}</style>"
bash "$CHECK" "$TMP/datafont.html" >/dev/null 2>&1 \
  && ok "a data: URI @font-face passes" || bad "inlined font wrongly flagged as remote"

# Sibling assets are a violation even when the HTML itself is clean.
mkdir -p "$TMP/sib"
cp "$TMP/wrapped.html" "$TMP/sib/page.html"
printf 'body{}\n' > "$TMP/sib/styles.css"
# Capture first: with pipefail, piping the checker's exit 1 into grep masks the match.
sib_out="$(bash "$CHECK" "$TMP/sib/page.html" 2>&1)"
[[ "$sib_out" == *"[siblings]"* ]] \
  && ok "catches a sibling .css next to a clean file" || bad "sibling asset not caught: $sib_out"

# A missing file is a failure, never a silent pass.
bash "$CHECK" "$TMP/does-not-exist.html" >/dev/null 2>&1 \
  && bad "a missing file exited 0" || ok "a missing file fails"

# --- BL-126: the verify is coupled to the wrap, so it cannot be skipped ---
# Two headless probes of the local-first procedure landed five steps 2 of 2 and the
# contract check 1 of 2. The fix is structural, not a louder instruction: --out writes the
# file AND checks it. These assert the coupling, which is stronger evidence than a probe
# showing the check fired once — a probe samples behaviour, this makes skipping impossible.
WRAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/wrap-report.sh"

GOOD='<style>body{color:#111}@media (prefers-color-scheme: dark){body{color:#eee}}</style><div class="page"><main class="main"><h1>ok</h1></main></div>'
printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" --out "$TMP/coupled-ok.html" >/dev/null 2>&1 \
  && ok "--out writes and passes a conforming page" || bad "--out rejected a conforming page"
[[ -f "$TMP/coupled-ok.html" ]] && ok "--out actually wrote the file" || bad "--out wrote nothing"

# A page that violates the contract must come back as a non-zero exit, not be
# written and reported as success.
#
# The fixture used to be a page with no dark-mode rule. artifact-kit injects
# tokens.css into every wrap, so [themes] is now unreachable THROUGH THE WRAPPER
# — which is the kit doing its job, not a hole: the check still fires on a
# hand-written file, asserted further down. The coupling is exercised here
# through §8 instead, which the wrapper cannot answer on the author behalf.
out="$(printf '<div class="page"><main class="main"><h1>answer me</h1>\n<textarea></textarea></main></div>\n' | bash "$WRAP" --title "T" --out "$TMP/coupled-bad.html" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && ok "--out exits non-zero when the wrapped file fails the contract" \
                || bad "--out returned 0 for a file that violates the contract"
[[ "$out" == *"[consult]"* ]] && ok "--out surfaces which check failed" \
                             || bad "--out hid the failing check: $out"
# The file is still written, so the author can fix it in place rather than re-derive it.
[[ -f "$TMP/coupled-bad.html" ]] && ok "the failing file is kept for fixing" \
                                 || bad "--out deleted the failing file"

# stdout mode cannot check (a pipe has no path), so the omission must be audible.
err="$(printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" 2>&1 >/dev/null)"
[[ "$err" == *"NOT verified"* ]] && ok "stdout mode says the contract went unverified" \
                                 || bad "stdout mode skipped the check silently: $err"

# The documented anchorless fallback writes to `.context/reports/`, which does not
# exist until the first report — so the procedure's own happy path ended in a
# traceback. One missing level is created; two means a wrong cwd, and a wrong cwd
# must be an error rather than a file written somewhere nobody will look.
mkdir -p "$TMP/anchor/.context"
printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" --out "$TMP/anchor/.context/reports/r.html" >/dev/null 2>&1 \
  && ok "one missing directory level is created (the documented fallback)" \
  || bad "the anchorless fallback path still fails to write"
[[ -f "$TMP/anchor/.context/reports/r.html" ]] && ok "the fallback file landed" \
                                               || bad "the fallback file was not written"

# --out takes a relative path in the documented flow, so a run standing in the
# wrong project writes a valid report into a neighbour and exits 0. The absolute
# path is what makes the landing visible.
#
# The --out here MUST be relative. This assertion used to pass `$TMP/...`, which
# `mktemp -d` already made absolute, so `os.path.abspath()` was the identity
# function on it and the check could not tell resolution from echoing the argument
# back — verified by mutation: replacing the abspath call with `print(args.outfile)`
# left all four dash suites byte-identical.
REL="$TMP/relproj"; mkdir -p "$REL/.context/reports"
out="$(cd "$REL" && printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" \
        --out ".context/reports/r2.html" 2>/dev/null)"
# Pick the path LINE out of stdout rather than testing the whole capture: python
# buffers its own stdout while the checker subprocess writes straight through, so
# `artifact contract OK` lands first. An unresolved path is not on any line here,
# which is exactly what makes this discriminating.
landed="$(grep -m1 '^/' <<<"$out")"
[[ -n "$landed" ]] \
  && ok "a relative --out is reported as an absolute path" \
  || bad "the landing path was echoed back unresolved: $out"
[[ "$landed" == *"relproj/.context/reports/r2.html" ]] \
  && ok "the reported path names the project it landed in" \
  || bad "the write did not say which project it landed in: $out"

err="$(printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" \
        --out "$TMP/anchor/nope/also-nope/r.html" 2>&1 >/dev/null)"; rc=$?
[[ $rc -ne 0 ]] && ok "two missing levels exit non-zero instead of guessing" \
                || bad "a wrong cwd was silently created and written into"
[[ "$err" == *"cwd="* ]] && ok "the wrong-cwd error names the cwd" \
                         || bad "the error did not report the cwd: $err"
[[ ! -d "$TMP/anchor/nope" ]] && ok "no directory tree was invented" \
                             || bad "a directory tree was created for a wrong cwd"

# --- BL-168: the § 8 consultation contract is checked, not merely written ------
# §8 shipped with a template and three requirements and was violated three ways by
# its own author on first contact. These assert the checks that make each one fail
# loudly. The fixture below is the real violating page reduced to its shape: reply
# boxes, no stable ids, nothing copied from the template.
echo "== consultation contract (§8) =="

TPL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/templates" && pwd -P)/consultation-block.html.template"

# The compliant form is the shipped template itself. If this ever fails, the checks
# demand something the suite does not ship — the worst kind of gate.
python3 - "$TPL" > "$TMP/consult-body.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
# The template ships BLOCKS to paste into skeleton.html, so the fixture supplies
# the layout container the skeleton would have. Without it the page is judged
# full-bleed (BL-177) and "the template fails nothing else" stops being about
# the template.
print('<div class="page"><main class="main">')
print(re.sub(r"\A\s*<!--.*?-->\s*", "", t, flags=re.S))
print('</main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>')
PY
# The shipped template must satisfy every check EXCEPT the one that is, by
# definition, an author's decision about a specific subject.
#
# It used to satisfy that one too, with `content="none: replace this with the
# reason, or with svg/mermaid/img"` — a "reason" that is the instruction to write a
# reason. references/02 §8 tells authors to copy this template rather than
# re-derive it, so every derived consultation shipped the visual gate already
# satisfied by a page with no visual and no reason: exactly the state §8 says must
# fail ("the reason is one grep away from review, which silence never is" — and the
# grep returned the placeholder).
#
# So the assertion is split rather than dropped. The original rationale still
# stands and is worth restating: if the template failed a check for any OTHER
# reason, the checks would demand something the suite does not ship, which is the
# worst kind of gate. What the template must NOT do is pre-answer the question.
tpl_out="$(bash "$WRAP" --title "C" --out "$TMP/consult-tpl.html" < "$TMP/consult-body.html" 2>&1)"
[[ "$tpl_out" == *"consult-visual"* ]] \
  && ok "the shipped template does not pre-satisfy the visual declaration" \
  || bad "the template ships the visual gate already answered: $tpl_out"
[[ "$(grep -c 'FAIL \[' <<<"$tpl_out")" -eq 1 ]] \
  && ok "and it fails NOTHING else — the checks demand only what the suite ships" \
  || bad "the template fails a check other than the visual declaration: $tpl_out"

# Replacing the placeholder is what makes it pass, so the template is one edit
# from compliant rather than broken.
python3 - "$TMP/consult-body.html" "$TMP/consult-body-decided.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
new, n = re.subn(r'content="none:[^"]*"',
                 'content="none: a wording decision, nothing to draw"', t)
assert n == 1, f"expected one consult-visual placeholder, found {n}"
open(sys.argv[2], "w").write(new)
PY
# The title of item c2 in the SHIPPED template, read from it rather than spelled
# here. Three fixtures below regenerate that item with a different claim, and
# they were all keyed to the literal "Second claim"; when the template's second
# item was retitled every one of them silently no-opped and stopped testing
# anything, while still reporting ok.
C2_TITLE="$(python3 - "$TMP/consult-body-decided.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<[^>]*\bdata-id\s*=\s*"c2"[^>]*\bdata-title\s*=\s*"([^"]*)"', t)
assert m, 'fixture drift: item c2 has no data-title in the shipped template'
print(m.group(1))
PY
)"
[[ -n "$C2_TITLE" ]] || { echo "FAIL: could not read item c2's title from the template"; exit 1; }

bash "$WRAP" --title "C" --out "$TMP/consult-ok.html" < "$TMP/consult-body-decided.html" >/dev/null 2>&1 \
  && ok "the template passes as soon as the author states the reason" \
  || bad "a template with its visual declaration answered still fails"

# The real BL-168 violation: hand-rolled reply boxes, no ids, no composer.
mk handrolled.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>
<h3>D4 · Visuales</h3><textarea></textarea>
<h3>D5 · Idioma</h3><textarea></textarea>
<button onclick=\"copiar()\">Copiar</button>"
out="$(bash "$CHECK" "$TMP/handrolled.html" 2>&1)"
[[ "$out" == *"[consult]"* ]] && ok "a hand-rolled consultation page is caught" \
                              || bad "hand-rolled consultation page passed: $out"
[[ "$out" == *"data-id"* ]] && ok "the failure names the missing stable ids" \
                            || bad "the consult failure did not mention data-id"
[[ "$out" == *"consultation-block.html.template"* ]] \
  && ok "the failure points at the template to copy" \
  || bad "the consult failure does not name the template"

# A report meant to be READ has no reply boxes, so none of this may fire on it.
bash "$CHECK" "$TMP/wrapped.html" >/dev/null 2>&1 \
  && ok "a plain report is not judged as a consultation" \
  || bad "the consultation checks fired on a page with no textarea"

# Each remaining requirement, one fixture per rule, built by breaking the good page.
sed 's/data-id="c2"/data-id="c1"/' "$TMP/consult-ok.html" > "$TMP/consult-dupe.html"
sed 's/id="consult-copy"/id="other"/' "$TMP/consult-ok.html" > "$TMP/consult-nobtn.html"
sed 's/:root\[data-theme="dark"\] \.consult-bar/:root[data-theme="dark"] .nothing/' \
  "$TMP/consult-ok.html" > "$TMP/consult-nodark.html"
sed 's/id="consult-status"/id="other-status"/' "$TMP/consult-ok.html" > "$TMP/consult-nostatus.html"
# data-title needs its OWN fixture. `handrolled.html` trips data-title,
# consult-status and the blank count all at once, and the assertions on it only
# look for `[consult]`, `data-id` and the template name — so a page with named
# reply boxes but no data-title had nothing discriminating it. Removing the
# attribute from the good page is what isolates the rule.
# Structural, not keyed to the template's wording: the previous form was
# `sed 's/ data-title="Second claim"//'`, and when the template's second item was
# retitled the sed quietly no-opped and the fixture stopped testing anything.
# `drop` removes item c2's data-title; `retitle` replaces it. Both assert the
# mutation landed, which the previous form could not: it was
# `sed 's/ data-title="Second claim"//'`, and when the template's second item was
# retitled the sed quietly no-opped and the fixture stopped testing anything.
mutate_c2() {  # <in> <out> <drop|retitle>
  python3 - "$1" "$2" "$3" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'<[^>]*\bdata-id\s*=\s*"c2"[^>]*>', text)
assert m, 'fixture drift: no item with data-id="c2" in the wrapped template'
attr = re.compile(r'\s*data-title\s*=\s*"[^"]*"')
tag = attr.sub("" if sys.argv[3] == "drop" else ' data-title="A different claim"',
               m.group(0), count=1)
assert tag != m.group(0), "fixture drift: the mutation changed nothing"
open(sys.argv[2], "w").write(text[:m.start()] + tag + text[m.end():])
PY
}
mutate_c2 "$TMP/consult-ok.html" "$TMP/consult-notitle.html" drop
for case in "consult-dupe duplicate" "consult-nobtn consult-copy" \
            "consult-nostatus consult-status" "consult-notitle data-title" \
            "consult-nodark data-theme"; do
  set -- $case
  out="$(bash "$CHECK" "$TMP/$1.html" 2>&1)"
  if [[ "$out" == *"[consult]"* && "$out" == *"$2"* ]]; then ok "catches $2 ($1.html)"
  else bad "did not catch $2 in $1.html: $out"; fi
done

# A consultation carries a visual by default, or says why not (BL-171 / USAGE-19).
# The check is on the DECLARATION because no checker can judge whether a subject
# has a shape — and an unenforceable sentence is what § 8 was written after.
# The composer is a real one, minimal but genuine: the blank-count requirement
# reads <script> content with comments stripped, so a fixture that "reported"
# blanks by carrying the word in its HTML text was relying on the very tautology
# this suite now rejects. It has to count them.
mk noviz.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}
:root[data-theme=\"dark\"] .consult-bar{background:#101619}</style>
<section class=\"consult-item\" data-id=\"c1\" data-title=\"T\"><textarea></textarea></section>
<section class=\"consult-item consult-notes\" data-id=\"notes\" data-title=\"General notes\"><textarea></textarea></section>
<button id=\"consult-copy\"></button><span id=\"consult-status\"></span>
<script>
document.getElementById('consult-copy').addEventListener('click', function () {
  var blank = [];
  document.querySelectorAll('.consult-item').forEach(function (el) {
    if (!el.querySelector('textarea').value.trim()) blank.push(el.dataset.id);
  });
  document.getElementById('consult-status').textContent = blank.length + ' still blank';
});
</script>"
out="$(bash "$CHECK" "$TMP/noviz.html" 2>&1)"
[[ "$out" == *"consult-visual"* ]] && ok "a consultation with neither a visual nor a reason is caught" \
                                  || bad "the missing-visual declaration was not caught: $out"

# Either half satisfies it: a real drawing, or an explicit reason there is none.
python3 - "$TMP/noviz.html" "$TMP/withviz.html" <<'PY'
import sys
t = open(sys.argv[1]).read().replace("<title>t</title>",
    '<title>t</title><svg width="10" height="10"></svg>')
open(sys.argv[2], "w").write(t)
PY
bash "$CHECK" "$TMP/withviz.html" >/dev/null 2>&1 \
  && ok "an inline SVG satisfies the visual default" || bad "a page WITH a drawing still failed"

python3 - "$TMP/noviz.html" "$TMP/declared.html" <<'PY'
import sys
t = open(sys.argv[1]).read().replace("<title>t</title>",
    '<title>t</title><meta name="consult-visual" content="none: a naming decision, nothing to draw">')
open(sys.argv[2], "w").write(t)
PY
bash "$CHECK" "$TMP/declared.html" >/dev/null 2>&1 \
  && ok "a declared reason for having no visual passes" || bad "an explicit none: reason was rejected"

# An empty declaration is silence wearing a meta tag.
python3 - "$TMP/noviz.html" "$TMP/emptydecl.html" <<'PY'
import sys
t = open(sys.argv[1]).read().replace("<title>t</title>",
    '<title>t</title><meta name="consult-visual" content="none:">')
open(sys.argv[2], "w").write(t)
PY
out="$(bash "$CHECK" "$TMP/emptydecl.html" 2>&1)"
[[ "$out" == *"consult-visual"* ]] && ok "an empty none: declaration does not satisfy it" \
                                   || bad "a reasonless declaration passed"

# And it must stay silent on an ordinary report: a page with no reply boxes is
# not a consultation, and most reports have no diagram by design.
bash "$CHECK" "$TMP/wrapped.html" >/dev/null 2>&1 \
  && ok "the visual default does not fire on a plain report" \
  || bad "the visual check leaked onto a non-consultation page"

# --- A read page with interactive CONTROLS can declare itself one -------------
# The consultation gate is deliberately broad, and that produced a false
# positive with no exit: a dashboard whose one <select> filters rows
# client-side collected the whole §8 battery (5 violations, probed on a real
# wrap) and could not comply without dropping the filter or dressing as a
# consultation with items nobody is meant to answer. The escape is a
# declaration with a reason — the same shape consult-visual already has, one
# grep away from review, which silence never is. And it is BOUNDED: it can
# only exempt closed controls (select, radio, checkbox, short text). Free-text
# surfaces are what a consultation IS — BL-168's page was hand-rolled
# textareas — and real consultation structure can never be declared away.
echo "== declared filter controls =="

FILTER_BODY="<h1>Rows</h1><label>Filter <select id=\"row-filter\"><option>all</option><option>open</option></select></label>"
mk filter.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>
$FILTER_BODY"
out="$(bash "$CHECK" "$TMP/filter.html" 2>&1)"
[[ "$out" == *"[consult]"* ]] \
  && ok "an undeclared filter select is still judged a consultation (the BL-168 arm stands)" \
  || bad "a bare select stopped triggering the gate — BL-168 pages with selects would pass: $out"
[[ "$out" == *"consult-surfaces"* ]] \
  && ok "…and the failure names the declaration that would exempt it" \
  || bad "the reader is offered no way out of the false positive: $out"

mk filter-declared.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><meta name=\"consult-surfaces\" content=\"none: the select filters rows client-side, there is nothing to answer\"><style>@media (prefers-color-scheme: dark){}</style>
$FILTER_BODY"
bash "$CHECK" "$TMP/filter-declared.html" >/dev/null 2>&1 \
  && ok "a declared filter select passes as a read" \
  || bad "the declaration did not exempt a read page's filter control: $(bash "$CHECK" "$TMP/filter-declared.html" 2>&1)"

# The bound, three ways. (1) free text can never be declared away.
mk ta-declared.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><meta name=\"consult-surfaces\" content=\"none: just a comment box\"><style>@media (prefers-color-scheme: dark){}</style>
<h1>Answer me</h1><textarea></textarea>"
out="$(bash "$CHECK" "$TMP/ta-declared.html" 2>&1)"
[[ "$out" == *"[consult]"* ]] \
  && ok "a textarea cannot be declared away — free text is what a consultation is" \
  || bad "the declaration laundered a hand-rolled reply box (BL-168 reopened): $out"

# (2) consultation STRUCTURE can never be declared away.
mk item-declared.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><meta name=\"consult-surfaces\" content=\"none: these are filters\"><style>@media (prefers-color-scheme: dark){}
:root[data-theme=\"dark\"] .consult-bar{background:#101619}</style>
<section class=\"consult-item\" data-id=\"c1\" data-title=\"T\"><div class=\"opts\"><label><input type=\"radio\" name=\"c1\" data-label=\"A\"><span>A</span></label></div></section>"
out="$(bash "$CHECK" "$TMP/item-declared.html" 2>&1)"
[[ "$out" == *"[consult]"* && "$out" == *"notes box"* ]] \
  && ok "a page with real consult items keeps the whole battery despite the declaration" \
  || bad "the declaration silenced §8 on a page with consultation structure: $out"

# (3) a placeholder reason is silence wearing a meta tag — same rule as
# consult-visual, or the template-shaped bypass returns through the new door.
mk filter-placeholder.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><meta name=\"consult-surfaces\" content=\"none: replace this with the reason\"><style>@media (prefers-color-scheme: dark){}</style>
$FILTER_BODY"
out="$(bash "$CHECK" "$TMP/filter-placeholder.html" 2>&1)"
[[ "$out" == *"[consult]"* ]] \
  && ok "a placeholder reason does not exempt anything" \
  || bad "the instruction to write a reason passed as a reason, again: $out"

# Requirement 1 across regenerations — the rule that was unenforceable, so it broke.
cp "$TMP/consult-ok.html" "$TMP/regen-same.html"
bash "$CHECK" "$TMP/regen-same.html" --prev "$TMP/consult-ok.html" >/dev/null 2>&1 \
  && ok "an unchanged regeneration passes --prev" || bad "--prev flagged an identical page"

mutate_c2 "$TMP/consult-ok.html" "$TMP/regen-shift.html" retitle
out="$(bash "$CHECK" "$TMP/regen-shift.html" --prev "$TMP/consult-ok.html" 2>&1)"
[[ "$out" == *"[consult-ids]"* ]] && ok "a shifted id is caught across regenerations" \
                                  || bad "an id now naming a different claim passed: $out"
[[ "$out" == *"c2"* ]] && ok "the shift report names the offending id" \
                       || bad "the consult-ids failure did not name the id: $out"

# A retyped title is not a moved claim: normalisation must keep this green, or the
# check gets disabled the first time someone fixes a typo.
sed 's/data-title="Second claim"/data-title="Second   Claim"/' \
  "$TMP/consult-ok.html" > "$TMP/regen-retitle.html"
bash "$CHECK" "$TMP/regen-retitle.html" --prev "$TMP/consult-ok.html" >/dev/null 2>&1 \
  && ok "case and whitespace changes in a title are not a shift" \
  || bad "a retyped title was reported as a moved claim"

# Documented non-failure: ids are never renumbered, but they may be closed out.
python3 - "$TMP/consult-ok.html" "$TMP/regen-dropped.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r'<section class="consult-item" data-id="c2".*?</section>', "", t, flags=re.S)
open(sys.argv[2], "w").write(t)
PY
bash "$CHECK" "$TMP/regen-dropped.html" --prev "$TMP/consult-ok.html" >/dev/null 2>&1 \
  && ok "a removed item is not a renumbering" || bad "--prev failed on a legitimately closed item"

bash "$CHECK" "$TMP/consult-ok.html" "$TMP/regen-same.html" --prev "$TMP/consult-ok.html" >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "--prev with several files is a usage error, not a guess" \
               || bad "--prev accepted an ambiguous comparison"

# --- BL-168: --out couples the regeneration checks to the write ---------------
# The prior version exists only until the write, so the snapshot has to happen there.
PROJ="$TMP/proj"; mkdir -p "$PROJ/.context/reports"
bash "$WRAP" --title "C" --out "$PROJ/.context/reports/c.html" < "$TMP/consult-body-decided.html" >/dev/null 2>&1
err="$(sed "s/data-title=\"$C2_TITLE\"/data-title=\"A different claim\"/" "$TMP/consult-body-decided.html" \
       | bash "$WRAP" --title "C" --out "$PROJ/.context/reports/c.html" 2>&1 >/dev/null)"; rc=$?
[[ $rc -ne 0 ]] && ok "regenerating with a shifted id fails the write" \
                || bad "--out accepted a regeneration that renumbered a claim"
[[ "$err" == *"typed"* ]] && ok "overwriting a consultation page warns about typed answers" \
                          || bad "no warning that a regeneration discards answers: $err"

# --- The blank-count requirement must measure the COMPOSER --------------------
# It was `grep -qi 'blank'` over the whole file, which measures nothing about the
# thing it names. Two failures, and the false NEGATIVE is the load-bearing one:
# the check was a tautology on the suite's own documented happy path, because the
# only surviving match on a page with the accounting torn out is a CSS comment
# inside the style block that references/02 §8 tells authors to copy verbatim.
echo "== blank count is about the composer =="

# fn.html — the shipped page with its blank accounting removed entirely, and
# NOTHING else touched. The CSS comment, both textarea placeholders ("leave blank
# to skip it") and the JS comment that says the blank count is reported before the
# paste are all left in place, because they are what the old check was matching.
python3 - "$TMP/consult-ok.html" "$TMP/consult-noblank.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()

# The kit composer, replaced by one that composes a reply and reports a count but
# does no blank accounting at all. Surgical substitutions into the shipped
# composer is what this used to do, and every edit to the composer broke the
# fixture instead of the check; swapping the whole script is stable and tests the
# same thing, because what the check must read is the code that ships.
MUTANT = """
(function () {
  var items = [].slice.call(document.querySelectorAll('.consult-item'));
  var status = [].slice.call(document.querySelectorAll('.consult-status'));
  // The blank count is reported before the paste, so a half-answered page is
  // visible while it can still be finished. This sentence is the CONTROL: it
  // names the blank count, and the code below accounts for nothing, so a check
  // that reads comments passes a page that does not do the work.
  function collect() {
    var answered = [];
    items.forEach(function (el) {
      var t = (el.querySelector('textarea') || {}).value || '';
      if (t.trim()) answered.push('### ' + el.dataset.id + '\\n\\n' + t.trim());
    });
    return { markdown: answered.join('\\n\\n'), answered: answered.length };
  }
  document.querySelectorAll('#consult-copy, #consult-copy-end').forEach(function (b) {
    b.addEventListener('click', function () {
      var r = collect();
      status.forEach(function (s) { s.textContent = r.answered + ' item(s) copied'; });
    });
  });
})();
"""

t, n = re.subn(r"<script\b[^>]*>.*?</script>", "<script>" + MUTANT + "</script>",
               t, count=1, flags=re.S | re.I)
assert n == 1, "fixture drift: no <script> to replace in the wrapped page"
js = "\n".join(m.group(1) for m in
                re.finditer(r"<script\b[^>]*>(.*?)</script>", t, re.I | re.S))
code = re.sub(r"(?m)//.*$", " ", re.sub(r"/\*.*?\*/", " ", js, flags=re.S))
assert "blank" not in code.lower(), "mutation left the accounting in the CODE"
# Controls: the word survives in a JS comment AND in the kit's own CSS comment,
# so a check that does not strip comments is satisfied by a page that counts
# nothing. That false negative is the whole reason the check reads the composer.
assert "blank" in js.lower(), "control: the JS comment must survive"
assert "blank" in re.sub(r"<script\b[^>]*>.*?</script>", " ", t, flags=re.S | re.I).lower(), \
    "control: the word must still appear outside the script"
open(sys.argv[2], "w").write(t)
PY
out="$(bash "$CHECK" "$TMP/consult-noblank.html" 2>&1)"
[[ "$out" == *"[consult]"* && "$out" == *"blank"* ]] \
  && ok "a composer with the blank accounting torn out is caught" \
  || bad "the blank-count check passed a page that does not count blanks: $out"

# The discriminator that keeps the above from being a new tautology in a smaller
# box: the surviving JS comment SAYS "blank count", inside the script. Scoping to
# script content is not enough on its own — comments have to go too, or the check
# has only moved the tautology.
python3 - "$TMP/consult-noblank.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
js = "\n".join(m.group(1) for m in
               re.finditer(r"<script\b[^>]*>(.*?)</script>", t, re.I | re.S))
assert "blank" in js.lower(), "fixture drift: the JS comment no longer mentions blank"
print("ok: the mutant still says 'blank' inside its script, so comments must be stripped")
PY

# The false positive, which is the reason the language field and §8 were unusable
# together: a correct Spanish consultation reports "sin responder" in its status
# text. House rules keep identifiers in English, so the composer still computes
# `blank` — the check must read the code, not the copy.
python3 - "$TMP/consult-ok.html" "$TMP/consult-es.html" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
t = t.replace("' still blank: '", "' sin responder: '")
t = t.replace("' · none left blank'", "' · ninguno sin responder'")
t = t.replace("leave blank to skip it", "dejalo vacio para omitirlo")
t = t.replace("' item(s) copied'", "' elemento(s) copiado(s)'")
open(sys.argv[2], "w").write(t)
PY
bash "$CHECK" "$TMP/consult-es.html" >/dev/null 2>&1 \
  && ok "a Spanish consultation whose composer still counts blanks passes" \
  || bad "a correct non-English consultation was rejected for not saying 'blank'"

# --- The self and consult gates must survive real formatting ------------------
# Both of these are the same shape: a grep that describes the page it expects
# rather than the pages that exist. A tag split across lines, or a reply box that
# is not a literal <textarea>, walked straight through.
echo "== self and consult gates =="

# (1) grep is line-based and `[^>]+` cannot cross a newline, so a remote
#     stylesheet or script wrapped by any HTML formatter passed the self
#     contract. The author knew tags span lines — the @font-face check flattens
#     first — but that fix reached one of the five self checks.
#
#     `tr '\n' ' '`, not `tr -d`: deleting the newline joins `<script` to `src=`
#     and the pattern stops matching for a second reason.
mk extjs-wrapped.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>
<script
  src=\"https://cdn.example.com/tracker.js\"></script>"
mk extcss-wrapped.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>
<link
  rel=\"stylesheet\"
  href=\"https://cdn.example.com/theme.css\">"
for case in "extjs-wrapped script" "extcss-wrapped stylesheet"; do
  set -- $case
  out="$(bash "$CHECK" "$TMP/$1.html" 2>&1)"
  [[ "$out" == *"[self]"* ]] \
    && ok "a line-wrapped remote $2 is still caught ($1.html)" \
    || bad "a line-wrapped remote $2 passed the self contract: $out"
done

# (2) The consultation gate keyed on the literal string `<textarea`, so a page
#     whose reply boxes are contenteditable divs — or are created at runtime —
#     skipped ALL of §8: no stable ids, no data-title, no duplicate check, no
#     composer, no status line, no visual declaration. A hand-rolled page is
#     exactly the one free to use a different element, and hand-rolled pages are
#     what the gate was widened for in the first place (BL-168).
mk consult-ce.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>
<h1>Please answer each claim below</h1>
<div contenteditable=\"true\" class=\"reply\"></div>
<div contenteditable=\"true\" class=\"reply\"></div>"
out="$(bash "$CHECK" "$TMP/consult-ce.html" 2>&1)"
[[ "$out" == *"[consult]"* ]] \
  && ok "contenteditable reply boxes are judged as a consultation" \
  || bad "a contenteditable consultation skipped every SS8 requirement: $out"

mk consult-runtime.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>
<section class=\"consult-item\"></section>
<script>document.querySelectorAll('.consult-item').forEach(function(s){s.appendChild(document.createElement('textarea'));});</script>"
out="$(bash "$CHECK" "$TMP/consult-runtime.html" 2>&1)"
[[ "$out" == *"[consult]"* ]] \
  && ok "reply boxes created at runtime are judged as a consultation" \
  || bad "a script-built consultation skipped every SS8 requirement: $out"

# The control that keeps (2) honest: widening the gate must not start judging an
# ordinary report. A page that merely NAMES textareas in its prose is a read.
mk mentions-textarea.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>
<h1>Report</h1><p>The consultation gate used to key on the textarea element.</p>"
bash "$CHECK" "$TMP/mentions-textarea.html" >/dev/null 2>&1 \
  && ok "prose naming a textarea is not a consultation" \
  || bad "the widened gate fired on an ordinary report"

# --- The --prev diff must FAIL CLOSED, and must survive real HTML -------------
# Every assertion in this block is about the same thing: `moved="$(python3 …)"`
# captured stdout and never the exit status, under `set -uo pipefail` with no
# `-e`. So any way of making the diff not run collapsed to "no ids moved", the
# script printed `artifact contract OK` and exited 0 — BL-126's "a check that is
# skipped is indistinguishable from a check that passed", reproduced inside the
# checker written to close it.
#
# Each fixture below carries a GENUINE shift (c2 names a different claim), so a
# passing run is always a false negative and never an empty comparison.
echo "== --prev fails closed =="

# (1) The interpreter cannot read --prev. `[[ ! -f ]]` tests existence and
#     regular-file-ness, never readability, so a mode-000 file passed the guard
#     and blew up in open().
cp "$TMP/consult-ok.html" "$TMP/prev-noperm.html"
chmod 000 "$TMP/prev-noperm.html"
out="$(bash "$CHECK" "$TMP/regen-shift.html" --prev "$TMP/prev-noperm.html" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && ok "an unreadable --prev fails instead of reading as no-change" \
                || bad "an unreadable --prev exited 0: $out"
[[ "$out" == *"[consult-ids]"* ]] && ok "the unreadable --prev is reported as a consult-ids failure" \
                                  || bad "the skipped diff was not reported: $out"
chmod 644 "$TMP/prev-noperm.html"

# (2) An empty data-id. The group-selection ternary tested truthiness where only
#     `is not None` is correct, so `data-id=""` took the wrong alternation branch
#     and `norm(None)` raised TypeError — killing the diff for the WHOLE page,
#     from either side. It passes every per-file check too (n_id == n_area, and a
#     single `data-id=""` is not a duplicate), so nothing else catches it.
python3 - "$TMP/regen-shift.html" "$TMP/shift-emptyid.html" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
extra = '<section class="consult-item" data-id="" data-title="Empty id claim"><textarea></textarea></section>'
open(sys.argv[2], "w").write(t.replace("</body>", extra + "</body>"))
PY
out="$(bash "$CHECK" "$TMP/shift-emptyid.html" --prev "$TMP/consult-ok.html" 2>&1)"
[[ "$out" == *"[consult-ids]"* && "$out" == *"c2"* ]] \
  && ok "an empty data-id does not disable the diff for the rest of the page" \
  || bad "one blank id silenced every real shift on the page: $out"

# (3) Single-quoted attributes. The PAIR regex hard-required double quotes, so a
#     page that picks its own quote style dropped out of the id map entirely —
#     and lines 88-90 of the checker say the check exists FOR hand-rolled pages,
#     which are exactly the pages that pick their own quote style.
squote() {  # squote <in> <out>
  python3 - "$1" "$2" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
t = re.sub(r'data-(id|title)="([^"]*)"', r"data-\1='\2'", t)
open(sys.argv[2], "w").write(t)
PY
}
squote "$TMP/consult-ok.html" "$TMP/sq-old.html"
squote "$TMP/regen-shift.html" "$TMP/sq-new.html"
out="$(bash "$CHECK" "$TMP/sq-new.html" --prev "$TMP/sq-old.html" 2>&1)"
[[ "$out" == *"[consult-ids]"* && "$out" == *"c2"* ]] \
  && ok "single-quoted data-id/data-title are compared, not skipped" \
  || bad "a single-quoted page silently passed the id-stability check: $out"

# (4) The realistic half of (3), with no author perversity required: a title that
#     QUOTES something forces single quotes on that one attribute, on an
#     otherwise fully double-quoted template-derived page. That item dropped out
#     of the map and any shift on it went unreported.
python3 - "$TMP/consult-ok.html" "$TMP/mix-old.html" "$TMP/mix-new.html" "$C2_TITLE" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
target = f'data-title="{sys.argv[4]}"'
assert target in t, "fixture drift: item c2's title is not in the wrapped page"
old = t.replace(target, """data-title='The "fix" that broke deploys'""")
new = t.replace(target, """data-title='A different claim about "auth"'""")
open(sys.argv[2], "w").write(old)
open(sys.argv[3], "w").write(new)
PY
out="$(bash "$CHECK" "$TMP/mix-new.html" --prev "$TMP/mix-old.html" 2>&1)"
[[ "$out" == *"[consult-ids]"* && "$out" == *"c2"* ]] \
  && ok "a title containing a double quote does not drop its item from the map" \
  || bad "a mixed-quote page laundered a total claim replacement: $out"

# (5) Duplicate-id detection had the same double-quote requirement, one file at a
#     time and with no --prev involved.
python3 - "$TMP/sq-old.html" "$TMP/sq-dupe.html" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w").write(t.replace("data-id='c2'", "data-id='c1'"))
PY
out="$(bash "$CHECK" "$TMP/sq-dupe.html" 2>&1)"
[[ "$out" == *"duplicate"* ]] \
  && ok "duplicate single-quoted ids are caught" \
  || bad "two claims answering to one single-quoted id passed: $out"

# --- A failed contract must not become the next run's baseline ----------------
# The gate inverted after any failure. The violating document is written to disk
# (deliberately — the author fixes it in place rather than re-deriving it, asserted
# above), the temp snapshot is deleted, and nothing else remembers the last good
# version. So the violating file became the --prev baseline, which makes the check
# single-shot and self-erasing in the two worst directions:
#   run 3a  the author does exactly what the error message says, restores the
#           correct title, and the FIX is reported as the violation
#   run 3b  the author re-runs the SAME violating content and it PASSES
# The existing coverage stops at run 2, so neither ever appeared.
echo "== the baseline is the last PASSING version =="

INV="$TMP/inv"; mkdir -p "$INV/.context/reports"
PAGE="$INV/.context/reports/c.html"
shifted() {  # shifted <title> — regenerate c2 with the given claim
  sed "s/data-title=\"$C2_TITLE\"/data-title=\"$1\"/" "$TMP/consult-body-decided.html" \
    | bash "$WRAP" --title "C" --out "$PAGE" 2>&1 >/dev/null
}

bash "$WRAP" --title "C" --out "$PAGE" < "$TMP/consult-body-decided.html" >/dev/null 2>&1
rc1=$?
[[ $rc1 -eq 0 ]] && ok "run 1: the original consultation passes" \
                 || bad "run 1 did not pass, so nothing below measures the baseline"

out2="$(shifted "A different claim")"; rc2=$?
[[ $rc2 -ne 0 ]] && ok "run 2: a claim moved behind a kept id fails" \
                 || bad "run 2: the id shift was not caught: $out2"
grep -q 'data-title="A different claim"' "$PAGE" \
  && ok "run 2: the violating file is still on disk to be fixed in place" \
  || bad "run 2: the failing write was rolled back (that behaviour is asserted above)"

# 3a — the author does what the message told them to do.
out3a="$(shifted "$C2_TITLE")"; rc3a=$?
[[ $rc3a -eq 0 ]] && ok "run 3a: restoring the correct claim PASSES" \
                  || bad "run 3a: the fix was reported as the violation: $out3a"

# 3b — and the violation must not be launderable by repetition. Re-run 2 first so
# the failing state is current again, then repeat it.
shifted "A different claim" >/dev/null
out3b="$(shifted "A different claim")"; rc3b=$?
[[ $rc3b -ne 0 ]] && ok "run 3b: repeating the same violation still fails" \
                  || bad "run 3b: the violation was laundered by repeating it: $out3b"

# --- BL-168: the style profile is a FIELD the wrapper reads (D2) --------------
echo "== style profile =="
LANGP="$TMP/langproj"; mkdir -p "$LANGP/.context/reports"
GOODB='<style>body{color:#111}@media (prefers-color-scheme: dark){body{color:#eee}}</style><div class="page"><main class="main"><h1>x</h1></main></div>'

# The one-time offer: it fires when the project has no profile, and records itself
# so it cannot become the 14-offers-across-7-projects nag the usage-retro measured.
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --out "$LANGP/.context/reports/a.html" 2>&1 >/dev/null)"
[[ "$err" == *"artifact-style.md"* ]] && ok "a first artifact offers the style profile" \
                                      || bad "the one-time style-profile offer never fired: $err"
[[ -f "$LANGP/.context/.aidex-artifact-style-offered" ]] \
  && ok "the offer records itself" || bad "the offer left no record, so it will repeat"
[[ ! -f "$LANGP/.context/artifact-style.md" ]] \
  && ok "the profile itself is never auto-created (e87bbd3)" \
  || bad "the offer created the profile unasked"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --out "$LANGP/.context/reports/b.html" 2>&1 >/dev/null)"
[[ "$err" != *"artifact-style.md"* ]] && ok "the offer does not repeat on the next artifact" \
                                      || bad "the offer nagged a second time: $err"

grep -q 'language:' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/templates" && pwd -P)/artifact-style.md.template" \
  && ok "the style template carries a parseable language: field" \
  || bad "artifact-style.md.template has no language: field"

grep -o '<html lang="[a-z]*"' "$LANGP/.context/reports/a.html" | grep -q 'lang="en"' \
  && ok "no profile falls back to en (D-04)" || bad "wrong default language"

printf '## Language\n\n- language: es\n' > "$LANGP/.context/artifact-style.md"
printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --out "$LANGP/.context/reports/c.html" >/dev/null 2>&1
grep -q '<html lang="es"' "$LANGP/.context/reports/c.html" \
  && ok "the profile's language: is applied without --lang" \
  || bad "the language: field is not load-bearing"

printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --lang fr --out "$LANGP/.context/reports/d.html" >/dev/null 2>&1
grep -q '<html lang="fr"' "$LANGP/.context/reports/d.html" \
  && ok "an explicit --lang wins over the profile" || bad "--lang was overridden by the profile"

# The upward walk stops at $HOME, like _lib.sh's find_project_root. Without the
# boundary a stray ~/.context/ captures every uninitialised project (field-observed
# 2026-07-25): the artifact would take a neighbour's language and drop this
# project's one-time offer marker in the home directory.
FAKEHOME="$TMP/home"; mkdir -p "$FAKEHOME/.context" "$FAKEHOME/proj"
printf '## Language\n\n- language: de\n' > "$FAKEHOME/.context/artifact-style.md"
printf '%s\n' "$GOODB" | HOME="$FAKEHOME" bash "$WRAP" --title "T" \
  --out "$FAKEHOME/proj/r.html" >/dev/null 2>&1
grep -q '<html lang="en"' "$FAKEHOME/proj/r.html" \
  && ok "the profile walk stops at \$HOME" \
  || bad "a stray ~/.context/ captured an uninitialised project's language"
[[ ! -f "$FAKEHOME/.context/.aidex-artifact-style-offered" ]] \
  && ok "no offer marker is dropped in \$HOME" || bad "the offer marker landed in \$HOME"

# An unreadable profile must not take the artifact down with it. `isfile` only
# stats — it does not imply readability — and the read was a bare open(), so a
# mode-000 artifact-style.md aborted the whole wrap with a PermissionError
# traceback and NO file was written. The profile is an optimisation, not a
# contract: an unreadable one degrades to the D-04 default and says so.
NOREAD="$TMP/noread"; mkdir -p "$NOREAD/.context/reports"
printf '## Language\n\n- language: es\n' > "$NOREAD/.context/artifact-style.md"
chmod 000 "$NOREAD/.context/artifact-style.md"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" \
        --out "$NOREAD/.context/reports/a.html" 2>&1 >/dev/null)"; rc=$?
chmod 644 "$NOREAD/.context/artifact-style.md"
[[ "$err" != *"Traceback"* ]] && ok "an unreadable style profile does not raise" \
                             || bad "the wrap died on an unreadable profile: $err"
[[ -f "$NOREAD/.context/reports/a.html" ]] \
  && ok "the artifact is still written when the profile cannot be read" \
  || bad "an unreadable profile prevented the artifact from being written"
grep -q '<html lang="en"' "$NOREAD/.context/reports/a.html" 2>/dev/null \
  && ok "an unreadable profile falls back to en (D-04)" \
  || bad "the fallback language was not applied"
# Require the NOTE, not just the filename: a traceback also contains the path, so
# a substring check on `artifact-style.md` passes on the unfixed code.
[[ "$err" == *"NOTE:"*"artifact-style.md"* ]] \
  && ok "and the unreadable profile is reported as a NOTE, not silently ignored" \
  || bad "the profile read failed without a readable warning: $err"

# --- The project root is resolved by the SHARED resolver ----------------------
# find_context_dir was a private Python reimplementation of _lib.sh's
# find_project_root, missing the linked-worktree hop — so route B (this script)
# and route A (render.sh, which sources _lib.sh) resolved DIFFERENT roots for the
# same project. render.sh:15-19 records that its own copy was deleted for exactly
# these fixes, and the no-private-copies guard could not see this one because it
# greps for a bash function definition.
#
# A linked worktree is a SIBLING of the project, never a descendant, so an upward
# walk cannot reach the main tree's `.context/` — which is gitignored and
# therefore absent from the worktree.
echo "== the project root comes from _lib.sh =="

if command -v git >/dev/null 2>&1; then
  WT="$TMP/wtproj"
  mkdir -p "$WT/main"
  ( cd "$WT/main" && git init -q . && git config user.email t@t && git config user.name t \
    && printf '.context/\n' > .gitignore && git add -A && git commit -qm init ) >/dev/null 2>&1
  mkdir -p "$WT/main/.context/reports"
  printf '## Language\n\n- language: es\n' > "$WT/main/.context/artifact-style.md"
  ( cd "$WT/main" && git worktree add -q "$WT/main-wt-feature" -b feature ) >/dev/null 2>&1

  # Control first: from the main tree the profile is found, so a failure below is
  # about the worktree hop and not about the profile being unreadable.
  ( cd "$WT/main" && printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" \
      --out ".context/reports/main.html" ) >/dev/null 2>&1
  grep -q '<html lang="es"' "$WT/main/.context/reports/main.html" 2>/dev/null \
    && ok "control: from the main tree the profile is applied" \
    || bad "control failed: the profile was not read from the main tree"

  mkdir -p "$WT/main-wt-feature/out"
  ( cd "$WT/main-wt-feature" && printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" \
      --out "out/wt.html" ) >/dev/null 2>&1
  grep -q '<html lang="es"' "$WT/main-wt-feature/out/wt.html" 2>/dev/null \
    && ok "from a linked worktree the main tree's profile is still applied" \
    || bad "a worktree run ignored the project's artifact language (no --git-common-dir hop)"
else
  ok "SKIP: git is unavailable, so the worktree hop cannot be exercised"
fi

echo "== the kit layout container (BL-177) =="
# The kit puts the whole width and column system on two classes — `.page` caps
# the measure and lays the grid, `.main` is the column — and wrap-report.sh
# injects the STYLES, never the structure. A page written as a bare <h1> plus
# sections therefore gets every token and no layout: it renders full-bleed at the
# browser's default width, and at 64rem+ the type reads enormous. That page
# passed every check the contract had.
KITCSS="$(cat "$SCRIPTS/../assets/artifact-kit/tokens.css" "$SCRIPTS/../assets/artifact-kit/components.css")"

mkkit() {  # $1 = filename, $2 = body markup
  { printf '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
    printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>Fixture</title>\n<meta name="artifact-kit" content="1">\n'
    printf '<style>\n%s\n</style>\n</head>\n<body>\n%s\n</body>\n</html>\n' "$KITCSS" "$2"
  } > "$TMP/$1"
}

# The fixture carries the WHOLE kit stylesheet, which spells `.page` and `.main`
# as selectors. The check must read the MARKUP: an unanchored grep is answered by
# the injected CSS on exactly the page that has none of the structure.
mkkit nowrap.html '<h1>Full bleed</h1><section id="s1"><h2>A section</h2><p>Prose.</p></section>'
out="$(bash "$CHECK" "$TMP/nowrap.html" 2>&1)"
[[ "$out" == *"layout"* || "$out" == *"skeleton.html"* ]] \
  && ok "a kit page whose content is not inside .page/.main is caught" \
  || bad "the wrapper-less page passed: $out"
[[ "$out" == *"skeleton.html"* ]] \
  && ok "the failure names skeleton.html as the fix" \
  || bad "the failure does not say where the structure comes from: $out"

mkkit wrapped-ok.html '<div class="page"><main class="main"><h1>Contained</h1><section id="s1"><h2>A section</h2><p>Prose.</p></section></main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>'
bash "$CHECK" "$TMP/wrapped-ok.html" >/dev/null 2>&1 \
  && ok "control: the same page inside the container passes" \
  || bad "a correctly wrapped page was rejected: $(bash "$CHECK" "$TMP/wrapped-ok.html" 2>&1)"

# `.main` alone is not the layout: without `.page` there is no cap and no grid.
mkkit halfwrap.html '<main class="main"><h1>Half</h1><section id="s1"><h2>A section</h2><p>Prose.</p></section></main>'
bash "$CHECK" "$TMP/halfwrap.html" >/dev/null 2>&1 \
  && bad "a page with .main but no .page passed — the cap and the grid both live on .page" \
  || ok "a page with .main but no .page is caught"

# A page that does NOT carry the kit is out of scope: it has no .page rule to be
# inside of, and judging it would fail every pre-kit artifact on disk.
printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n<meta name="viewport" content="width=device-width">\n<title>t</title>\n<style>@media (prefers-color-scheme: dark){body{background:#111}}</style>\n</head>\n<body><h1>Pre-kit</h1></body></html>\n' > "$TMP/prekit.html"
bash "$CHECK" "$TMP/prekit.html" >/dev/null 2>&1 \
  && ok "a page without the kit stamp is not judged on the kit's layout" \
  || bad "a pre-kit page was failed for a container it never had"

# A wide table is the second way the same mechanism breaks: the kit ships `.tw`
# (overflow-x:auto) and nothing makes the page use it. Measured on a real page —
# a 12-column table in the 728px column renders 1055px wide, its right edge at
# x=1299 while the rail starts at x=1028, so it PAINTS OVER the rail. There is no
# page-level scrollbar to give it away, and no CSS net is possible: max-width
# cannot shrink a table below its min-content width, and display:block collapses
# a narrow table's cells.
mkkit bare-table.html '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>s</h2><table><tr><td>a</td><td>b</td></tr></table></section></main></div>'
out="$(bash "$CHECK" "$TMP/bare-table.html" 2>&1)"
[[ "$out" == *"tw"* ]] \
  && ok "a table outside any scroll container is caught" \
  || bad "a bare table passed, so it is free to paint over the rail: $out"

mkkit tw-table.html '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>s</h2><div class="tw"><table><tr><td>a</td><td>b</td></tr></table></div></section></main></div>'
bash "$CHECK" "$TMP/tw-table.html" >/dev/null 2>&1 \
  && ok "control: the same table inside .tw passes" \
  || bad "a table inside the kit wrapper was rejected: $(bash "$CHECK" "$TMP/tw-table.html" 2>&1)"

# The page's OWN scroll wrapper counts. The class set is read from the CSS the
# document carries, not from a whitelist — a page that wraps its tables in
# `.scroll` is honouring the rule, and a checker that only knows `.tw` would fail
# it for a defect it does not have. One artifact on disk does exactly this.
mkkit own-scroll.html '<style>.roll{overflow-x:auto}</style><div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>s</h2><div class="roll"><table><tr><td>a</td></tr></table></div></section></main></div>'
bash "$CHECK" "$TMP/own-scroll.html" >/dev/null 2>&1 \
  && ok "a page's own overflow wrapper counts, without a whitelist" \
  || bad "a table in the page's own scroll wrapper was rejected: $(bash "$CHECK" "$TMP/own-scroll.html" 2>&1)"

# A commented-out table is not markup. skeleton.html is a file of examples in
# comments, so this is the false positive that would have fired on the very page
# authors copy from.
mkkit commented-table.html '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>s</h2><!-- <table><tr><td>example</td></tr></table> --><p>Prose.</p></section></main></div>'
bash "$CHECK" "$TMP/commented-table.html" >/dev/null 2>&1 \
  && ok "a table inside an HTML comment is not counted" \
  || bad "a commented-out table was reported as unwrapped: $(bash "$CHECK" "$TMP/commented-table.html" 2>&1)"

# Route A boards are full of tables and are not kit pages: the same stamp gate as
# the layout check keeps them out of it.
printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n<meta name="viewport" content="width=device-width">\n<title>t</title>\n<style>@media (prefers-color-scheme: dark){body{background:#111}}</style>\n</head>\n<body><table><tr><td>a</td></tr></table></body></html>\n' > "$TMP/board.html"
bash "$CHECK" "$TMP/board.html" >/dev/null 2>&1 \
  && ok "a page without the kit stamp is not judged on the kit's table wrapper" \
  || bad "a non-kit page was failed for the kit's table wrapper"

echo
echo "artifact contract: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
