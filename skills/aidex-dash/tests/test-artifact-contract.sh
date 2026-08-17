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
<h1>Informe</h1><p>Acentuaci&oacute;n y datos.</p>'

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

for case in "fragment doctype" "nocharset charset" "nothemes themes" "extcss self" "extjs self" "extimg self" "extfont self"; do
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

GOOD='<style>body{color:#111}@media (prefers-color-scheme: dark){body{color:#eee}}</style><h1>ok</h1>'
printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" --out "$TMP/coupled-ok.html" >/dev/null 2>&1 \
  && ok "--out writes and passes a conforming page" || bad "--out rejected a conforming page"
[[ -f "$TMP/coupled-ok.html" ]] && ok "--out actually wrote the file" || bad "--out wrote nothing"

# A page with no dark-mode rule violates the contract. --out must surface that as a
# non-zero exit, not write it and return success.
out="$(printf '<h1>no theme</h1>\n' | bash "$WRAP" --title "T" --out "$TMP/coupled-bad.html" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && ok "--out exits non-zero when the wrapped file fails the contract" \
                || bad "--out returned 0 for a file that violates the contract"
[[ "$out" == *"[themes]"* ]] && ok "--out surfaces which check failed" \
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
out="$(printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" --out "$TMP/anchor/.context/reports/r2.html" 2>/dev/null)"
[[ "$out" == *"$TMP/anchor/.context/reports/r2.html"* ]] \
  && ok "the absolute landing path is reported" \
  || bad "the write did not say where it landed: $out"

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
print(re.sub(r"\A\s*<!--.*?-->\s*", "", t, flags=re.S))
PY
bash "$WRAP" --title "C" --out "$TMP/consult-ok.html" < "$TMP/consult-body.html" >/dev/null 2>&1 \
  && ok "the shipped consultation template passes its own checks" \
  || bad "the consultation template fails the checks written for it"

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
for case in "consult-dupe duplicate" "consult-nobtn consult-copy" "consult-nodark data-theme"; do
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

# Requirement 1 across regenerations — the rule that was unenforceable, so it broke.
cp "$TMP/consult-ok.html" "$TMP/regen-same.html"
bash "$CHECK" "$TMP/regen-same.html" --prev "$TMP/consult-ok.html" >/dev/null 2>&1 \
  && ok "an unchanged regeneration passes --prev" || bad "--prev flagged an identical page"

sed 's/data-title="Second claim"/data-title="A different claim"/' \
  "$TMP/consult-ok.html" > "$TMP/regen-shift.html"
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
bash "$WRAP" --title "C" --out "$PROJ/.context/reports/c.html" < "$TMP/consult-body.html" >/dev/null 2>&1
err="$(sed 's/data-title="Second claim"/data-title="A different claim"/' "$TMP/consult-body.html" \
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
import sys
t = open(sys.argv[1], encoding="utf-8").read()
subs = [
    ("var answered = [], blank = [];", "var answered = [];"),
    ("else blank.push(id);", "else { /* skipped */ }"),
    ("return { markdown: answered.join('\\n\\n'), answered: answered.length, blank: blank };",
     "return { markdown: answered.join('\\n\\n'), answered: answered.length };"),
]
for old, new in subs:
    assert old in t, f"template drift: {old[:40]!r} not found"
    t = t.replace(old, new, 1)
# The status line, reduced to a count with no blank accounting.
i = t.index("var msg = r.answered")
j = t.index(";", t.index("r.blank.join(', ')"))
t = t[:i] + "var msg = r.answered + ' item(s) copied'" + t[j:]
assert "r.blank" not in t and "blank.push" not in t, "mutation left the accounting in"
assert "still blank" not in t, "mutation left the status text in"
assert "leave blank to skip it" in t, "control: the placeholders must survive"
assert "blank-count status landed at 1.31:1" in t, "control: the CSS comment must survive"
assert "The blank count is reported BEFORE the paste" in t, "control: the JS comment must survive"
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
python3 - "$TMP/consult-ok.html" "$TMP/mix-old.html" "$TMP/mix-new.html" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
old = t.replace('data-title="Second claim"',
                """data-title='The "fix" that broke deploys'""")
new = t.replace('data-title="Second claim"',
                """data-title='A different claim about "auth"'""")
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
  sed "s/data-title=\"Second claim\"/data-title=\"$1\"/" "$TMP/consult-body.html" \
    | bash "$WRAP" --title "C" --out "$PAGE" 2>&1 >/dev/null
}

bash "$WRAP" --title "C" --out "$PAGE" < "$TMP/consult-body.html" >/dev/null 2>&1
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
out3a="$(shifted "Second claim")"; rc3a=$?
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
GOODB='<style>body{color:#111}@media (prefers-color-scheme: dark){body{color:#eee}}</style><h1>x</h1>'

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

echo
echo "artifact contract: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
