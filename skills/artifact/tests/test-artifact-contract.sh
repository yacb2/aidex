#!/usr/bin/env bash
# test-artifact-contract.sh — unit tests for wrap-report.sh + check-artifact.sh,
# the deterministic half of the local-first artifact contract
# (skills/artifact/references/02-local-first-artifacts.md).
#
# No API cost and no `claude -p`: the expensive behavioral eval
# (tests/eval-local-first-behavior.sh) calls the same checker, so the assertion
# logic is proven here and merely reused there.
#
# Run with: bash skills/artifact/tests/test-artifact-contract.sh

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
@media (prefers-color-scheme: dark){:root{--ink:#eee}</style>
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
# A <video> counts as the page's visual like an <img> (03-spec-grammar.md § The
# `video` block), so a remote one breaks the file the same way, by its own src
# or by a <source> child.
mk extvideo.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><video src=\"https://cdn.example.com/r1.mp4\"></video>"
mk extsource.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><video controls><source src=\"https://cdn.example.com/r1.mp4\" type=\"video/mp4\"></video>"
# srcset and poster are remote loads too; a data-src is a script's business,
# not the browser's, and loads nothing by itself.
mk extsrcset.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><picture><source srcset=\"https://x/a.png\"><img src=\"a.png\" alt=\"a\"></picture>"
mk extposter.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><video poster=\"https://x/p.jpg\" src=\"../media/a.mp4\"></video>"
# BL-553: every srcset candidate loads, not only the first; <audio> is a media
# element like <video>; an <img> with a remote srcset alone is caught too.
mk extsrcset2.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><img src=\"a.png\" srcset=\"a.png 1x, https://x/b.png 2x\" alt=\"a\">"
mk extaudio.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><audio controls src=\"https://cdn.example.com/a.mp3\"></audio>"
mk extimgsrcset.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><img src=\"a.png\" srcset=\"https://x/b.png 2x\" alt=\"a\">"
# An apostrophe inside a double-quoted srcset is part of the value, not its end.
mk extsrcsetapos.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><img src=\"a.png\" srcset=\"it's.png 1x, https://x/b.png 2x\" alt=\"a\">"
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
            "extcss self" "extjs self" "extimg self" "extfont self" \
            "extvideo self" "extsource self" "extsrcset self" "extposter self" \
            "extsrcset2 self" "extaudio self" "extimgsrcset self" "extsrcsetapos self"; do
  set -- $case
  out="$(bash "$CHECK" "$TMP/$1.html" 2>&1)"
  if [[ "$out" == *"[$2]"* ]]; then ok "catches $2 ($1.html)"; else bad "did not catch $2 in $1.html: $out"; fi
done

mk datasrc.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><video controls><source data-src=\"https://x/a.mp4\" type=\"video/mp4\"></video>"
out="$(bash "$CHECK" "$TMP/datasrc.html" 2>&1)"
[[ "$out" != *"[self]"* ]] \
  && ok "a data-src loads nothing and passes self" || bad "a data-src was judged a remote load: $out"

# A multi-candidate srcset of local files is not a remote load (BL-553).
mk localsrcset.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><img src=\"a.png\" srcset=\"a.png 1x, shots/https-b.png 2x\" alt=\"a\">"
out="$(bash "$CHECK" "$TMP/localsrcset.html" 2>&1)"
[[ "$out" != *"[self]"* ]] \
  && ok "a local multi-candidate srcset passes self" || bad "a local srcset was judged a remote load: $out"

# BL-564: remote loads via track, iframe, embed, object, protocol-relative and CSS url().
mk exttrack.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><video><track src=\"https://x/a.vtt\"></video>"
mk extiframe.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><iframe src=\"https://x/p\"></iframe>"
mk extembed.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><embed src=\"https://x/a.swf\">"
mk extobject.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><object data=\"https://x/a.pdf\"></object>"
mk extproto.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><img src=\"//x/a.png\" alt=\"a\">"
mk extprotoaudio.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><audio src=\"//x/a.mp3\"></audio>"
mk extprotosrcset.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><img srcset=\"a.png 1x, //x/b.png 2x\" alt=\"a\">"
mk extstyleurl.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><div style=\"background:url(https://x/a.png)\">x</div>"
mk extcssurl.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>.a{background:url(//x/a.png)}@media (prefers-color-scheme: dark){}</style>"
for case in "exttrack self" "extiframe self" "extembed self" "extobject self" "extproto self" "extprotoaudio self" "extprotosrcset self" "extstyleurl self" "extcssurl self"; do
  set -- $case
  out="$(bash "$CHECK" "$TMP/$1.html" 2>&1)"
  if [[ "$out" == *"[$2]"* ]]; then ok "catches $2 ($1.html)"; else bad "did not catch $2 in $1.html: $out"; fi
done
mk localforms.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>.a{background:url(data:image/png;base64,AAAA)}.b{background:url(a.png)}@media (prefers-color-scheme: dark){}</style><video><track src=\"a.vtt\"></video><iframe src=\"p.html\"></iframe><embed src=\"a.swf\"><object data=\"a.pdf\"></object><img src=\"data:image/png;base64,AAAA\" alt=\"a\"><div style=\"background:url(a.png)\">x</div><svg><rect fill=\"url(#g)\"/></svg>"
out="$(bash "$CHECK" "$TMP/localforms.html" 2>&1)"
[[ "$out" != *"[self]"* ]] \
  && ok "local, relative and data: URLs in the same forms pass self" || bad "a local URL was judged a remote load: $out"

# BL-564 review notes: whitespace in the quote, unquoted/single-quoted style, @import string, // on every tag.
mk extiframews.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><iframe src=\" https://x/p\"></iframe>"
mk extcsswsurl.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>.a{background:url(\" //x/a.png\")}@media (prefers-color-scheme: dark){}</style>"
mk extstyleunq.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><div style=background:url(//x/a.png)>x</div>"
mk extstylesq.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><div style='background:url(//x/a.png)'>x</div>"
mk extimportstr.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@import \"//x/a.css\";@media (prefers-color-scheme: dark){}</style>"
mk extprotoiframe.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><iframe src=\"//x/p\"></iframe>"
mk extprototrack.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><video><track src=\"//x/a.vtt\"></video>"
mk extprotoembed.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><embed src=\"//x/a.swf\">"
mk extprotoobject.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@media (prefers-color-scheme: dark){}</style><object data=\"//x/a.pdf\"></object>"
mk extimporturl.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>@import url(https://x/a.css);@media (prefers-color-scheme: dark){}</style>"
for case in "extiframews self" "extcsswsurl self" "extstyleunq self" "extstylesq self" "extimportstr self" "extprotoiframe self" "extprototrack self" "extprotoembed self" "extprotoobject self" "extimporturl self"; do
  set -- $case
  out="$(bash "$CHECK" "$TMP/$1.html" 2>&1)"
  if [[ "$out" == *"[$2]"* ]]; then ok "catches $2 ($1.html)"; else bad "did not catch $2 in $1.html: $out"; fi
done
# One defect, one finding: @font-face and @import url() are not also reported as CSS url().
for f in extfont extimporturl; do
  n="$(bash "$CHECK" "$TMP/$f.html" 2>&1 | grep -c '\[self\]')"
  [[ "$n" == 1 ]] && ok "$f yields exactly one [self] finding" || bad "$f yields $n [self] findings"
done
# BL-647: the remaining remote-load forms, and comments that load nothing.
HEAD5='<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>t</title><style>@media (prefers-color-scheme: dark){}</style>'
mk extbase.html "$HEAD5<base href=\"https://x/\"><img src=\"a.png\" alt=\"a\">"
mk extsvgimage.html "$HEAD5<svg><image href=\"https://x/a.png\"/></svg>"
mk extsvgxlink.html "$HEAD5<svg><image xlink:href=\"//x/a.png\"/></svg>"
mk extsvgfill.html "$HEAD5<svg><rect fill=\"url(https://x/g.svg#g)\"/></svg>"
mk extsvgfilter.html "$HEAD5<svg><rect filter=\"url(//x/f.svg#f)\"/></svg>"
mk extsvgmask.html "$HEAD5<svg><rect mask='url(\"https://x/m.svg#m\")'/></svg>"
mk exticon.html "$HEAD5<link rel=\"icon\" href=\"https://x/f.ico\">"
mk exticonunq.html "$HEAD5<link rel=icon href=https://x/f.ico>"
mk extbackslash.html "$HEAD5<img src=\"\\\\x/a.png\" alt=\"a\">"
for f in extbase extsvgimage extsvgxlink extsvgfill extsvgfilter extsvgmask exticon exticonunq extbackslash; do
  out="$(bash "$CHECK" "$TMP/$f.html" 2>&1)"
  if [[ "$out" == *"[self]"* ]]; then ok "catches self ($f.html)"; else bad "did not catch self in $f.html: $out"; fi
done
mk commentedremote.html "$HEAD5<!-- <iframe src=\"https://x\"></iframe> <link rel=\"stylesheet\" href=\"https://x/a.css\"> --><p>x</p>"
out="$(bash "$CHECK" "$TMP/commentedremote.html" 2>&1)"
[[ "$out" != *"[self]"* ]] && ok "a remote URL in an HTML comment passes self" || bad "an HTML comment was judged a remote load: $out"
mk csscomment.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>/* a{background:url(https://x/a.png)} */
@media (prefers-color-scheme: dark){}</style>"
out="$(bash "$CHECK" "$TMP/csscomment.html" 2>&1)"
[[ "$out" != *"[self]"* ]] && ok "a remote url() in a CSS comment passes self" || bad "a CSS comment was judged a remote load: $out"
mk localnew.html "$HEAD5<base href=\"sub/\"><link rel=\"icon\" href=\"f.ico\"><link rel=\"canonical\" href=\"https://x/p\"><svg><image href=\"a.png\"/><rect fill=\"url(#g)\" xmlns=\"http://www.w3.org/2000/svg\"/></svg>"
out="$(bash "$CHECK" "$TMP/localnew.html" 2>&1)"
[[ "$out" != *"[self]"* ]] && ok "local base, icon, image and url(#id) pass self" || bad "a local form was judged remote: $out"

# BL-647 review: a "<!--" in a script string, a textarea or an attribute is not a comment.
mk hidescript.html "$HEAD5<script>var s=\"<!--\";</script><img src=\"https://x/a.png\" alt=\"a\"><!-- c -->"
mk hidetextarea.html "$HEAD5<textarea><!-- </textarea><iframe src=\"https://x\"></iframe><!-- c -->"
mk hideattr.html "$HEAD5<img alt=\"<!--\" src=\"https://x/a.png\"><!-- c -->"
# Security review: the HTML parser ends a comment at "<!-->", "<!--->" and "--!>";
# a regex that waits for the next "-->" hides the live load in between.
mk hideempty.html "$HEAD5<!--><img src=\"https://x/a.png\" alt=\"a\"><p>e</p><!-- c -->"
mk hidedash.html "$HEAD5<!---><img src=\"https://x/a.png\" alt=\"a\"><p>e</p><!-- c -->"
mk hidebang.html "$HEAD5<!-- a --!><img src=\"https://x/a.png\" alt=\"a\"><p>e</p><!-- c -->"
for e in xmp noembed noframes noscript iframe; do
  mk "hide$e.html" "$HEAD5<$e><!--</$e><img src=\"https://x/a.png\" alt=\"a\"><p>e</p><!-- c -->"
done
mk iconlabel.html "$HEAD5<link rel=preload href=https://x/icon.png>"
for f in hidescript hidetextarea hideattr hideempty hidedash hidebang hidexmp hidenoembed hidenoframes hidenoscript hideiframe; do
  out="$(bash "$CHECK" "$TMP/$f.html" 2>&1)"
  if [[ "$out" == *"[self]"* ]]; then ok "catches self ($f.html)"; else bad "a comment opener hid a remote load in $f.html: $out"; fi
done
out="$(bash "$CHECK" "$TMP/iconlabel.html" 2>&1)"
[[ "$out" != *"rel=icon"* ]] && ok "a preload href naming icon is not labelled rel=icon" || bad "preload mislabelled as icon: $out"
# Quoted prose and non-loading attributes that merely spell url(https://...) are not loads.
mk prose1.html "$HEAD5<pre><code>&lt;rect fill=\"url(https://x/g.svg#g)\"/&gt;</code></pre>"
mk prose2.html "$HEAD5<p>set a=url(https://example.com) in config</p>"
mk prose3.html "$HEAD5<div data-bg=\"url(https://x/a.png)\">x</div>"
mk prose4.html "$HEAD5<span title=\"url(https://x)\">x</span>"
for f in prose1 prose2 prose3 prose4; do
  out="$(bash "$CHECK" "$TMP/$f.html" 2>&1)"
  [[ "$out" != *"[self]"* ]] && ok "$f.html passes self" || bad "$f.html was judged a remote load: $out"
done

# An svg data: URI naming an http namespace is inlined, not a remote load.
mk datasvg.html "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>t</title><style>.a{background:url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3C/svg%3E\")}@media (prefers-color-scheme: dark){}</style>"
out="$(bash "$CHECK" "$TMP/datasvg.html" 2>&1)"
[[ "$out" != *"[self]"* ]] && ok "a data:image/svg+xml url() passes self" || bad "a data: svg url() was judged remote: $out"

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

GOOD='<style>body{color:#111}@media (prefers-color-scheme: dark){body{color:#eee}</style><div class="page"><main class="main"><h1>ok</h1></main></div>'
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
# CHANGED 2026-09-20. This used to assert "the failing file is kept for fixing":
# `--out` left the violating document at the very path the reader has open, and a
# page that fails its contract must never be what sits there. The author's work is
# carried by the body sidecar now (test-body-sidecar.sh), so nothing is lost by
# taking the failing render out of the reader's path. This wrap was the FIRST at
# that path, so there is nothing to restore: the page must not exist at all.
[[ ! -e "$TMP/coupled-bad.html" ]] \
  && ok "a failing FIRST wrap leaves no page at --out" \
  || bad "--out left a contract-failing page at the reader's path"
[[ -f "$TMP/.aidex-artifact-prev/coupled-bad.html.failed" ]] \
  && ok "the failing render is kept for the author at .aidex-artifact-prev/<page>.failed" \
  || bad "the failing render was lost entirely"
[[ "$out" == *"coupled-bad.html.failed"* && "$out" == *"coupled-bad.html.failed.body"* ]] \
  && ok "the error names the failed render and the attempt's own source to fix" \
  || bad "the error message points the author nowhere: $out"

# ...and a later PASSING wrap of the same page clears it, or the directory keeps a
# render nobody will ever look at again.
printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" --out "$TMP/coupled-bad.html" >/dev/null 2>&1 \
  && ok "the same path wraps clean afterwards" || bad "the clean re-wrap failed"
[[ ! -e "$TMP/.aidex-artifact-prev/coupled-bad.html.failed" ]] \
  && ok "a passing wrap removes the kept failing render" \
  || bad "the .failed render outlived the fix"

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
# the template. The template's own rail goes after </main>, where it says it lives.
t = re.sub(r"\A\s*<!--.*?-->\s*", "", t, flags=re.S)
blocks, rail = t.split('<aside class="rail">', 1)
print('<div class="page"><main class="main">')
print(blocks)
print('</main><aside class="rail">' + rail + '</div>')
PY
# The shipped template must satisfy every check EXCEPT the one that is, by
# definition, an author's decision about a specific subject.
#
# It used to satisfy that one too, with `content="none: replace this with the
# reason, or with svg/img"` — a "reason" that is the instruction to write a
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

# BL-328: `class="mermaid"` counted as a visual and NOTHING renders it. A local
# artifact is a file:// document with no external host allowed, and the kit ships
# no renderer — verified by grep over artifact-kit/ and wrap_report.py — so the
# block IS its own source. The page passed the check and showed the reader a wall
# of `graph TD`: a gate that passes input it should reject. A fleet census on
# 2026-09-07 over every .context/**/*.html found zero pages declaring it, so
# removing the value costs nothing and makes Mermaid's retirement real in code.
# The output is NOT named after the diagram language: the assertion below greps
# the message for it, and a filename would answer the grep.
printf '<div class="page"><main class="main"><h1>x</h1>
<pre class="mermaid">graph TD; A--&gt;B;</pre>
<section class="consult-group" id="G1" data-id="G1" data-title="The context"><div class="sec-head"><h2>The context</h2></div><p>What the decisions share.</p>
<section class="consult-item" data-id="m1" data-title="One"><h3>One</h3>
<div class="opts one"><label><input type="radio" name="m1" data-label="A"><span>A</span></label></div>
<p class="fieldlabel">Notes on this one</p><textarea></textarea></section>
</section>
<section class="consult-item consult-notes" data-id="notes" data-title="Notes"><h3>Notes</h3><textarea></textarea></section>
<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div>
</main></div>\n' > "$TMP/mm-body.html"
mm_out="$(bash "$WRAP" --title "M" --out "$TMP/mm.html" < "$TMP/mm-body.html" 2>&1)"
[[ "$mm_out" == *"consult-visual"* ]] \
  && ok "BL-328: a page whose only visual is class=\"mermaid\" fails the visual check" \
  || bad "BL-328: mermaid still counts as a visual, and nothing renders it: $mm_out"
# The message must stop advertising it, or the author is sent to the same dead end.
[[ "$mm_out" == *"mermaid"* ]] \
  && bad "BL-328: the failure message still offers mermaid as a value: $mm_out" \
  || ok "the visual-declaration message names only the values that render"
grep -q 'svg` / `img`' "$TPL" \
  && ! grep -q 'svg` / `mermaid` / `img`' "$TPL" \
  && ok "the template offers svg / img and no longer mermaid" \
  || bad "BL-328: the template still tells the author to write mermaid"
grep -q 'svg/mermaid/img' "$TPL" \
  && bad "BL-328: the template's own placeholder still advertises mermaid" \
  || ok "the placeholder the author copies names only the values that render"

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
<main><section class=\"consult-group\" id=\"G1\" data-id=\"G1\" data-title=\"Ctx\"><h2>Ctx</h2><section class=\"consult-item\" data-id=\"c1\" data-title=\"T\" data-free><textarea></textarea></section></section>
<section class=\"consult-item consult-notes\" data-id=\"notes\" data-title=\"General notes\"><textarea></textarea></section>
<button id=\"consult-copy-end\"></button></main>
<aside class=\"rail\"><div class=\"consult-bar\"><button id=\"consult-copy\"></button><span id=\"consult-status\"></span></div></aside>
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

# BL-611: a declared retitle (`consult-retitled` meta) lets ONE named id change
# its title, as a NOTE with both titles; an id not named still fails.
C2_NORM="$(python3 -c 'import sys; print(" ".join(sys.argv[1].lower().split()))' "$C2_TITLE")"
sed 's#<title>#<meta name="consult-retitled" content="c2"><title>#' \
  "$TMP/regen-shift.html" > "$TMP/regen-retitled.html"
grep -q 'name="consult-retitled" content="c2"' "$TMP/regen-retitled.html" \
  || bad "BL-611: fixture drift: the sed did not insert the consult-retitled meta"
out="$(bash "$CHECK" "$TMP/regen-retitled.html" --prev "$TMP/consult-ok.html" 2>&1)"
[[ "$out" != *"FAIL [consult-ids]"* && "$out" == *"NOTE [consult-ids]"* && "$out" == *"c2"* \
   && "$out" == *"$C2_NORM"* && "$out" == *"a different claim"* ]] \
  && ok "BL-611: a retitle declared by consult-retitled is a NOTE with the old and new title" \
  || bad "BL-611: a declared retitle did not pass with a NOTE naming both titles: $out"
sed 's#<title>#<meta name="consult-retitled" content="c1"><title>#' \
  "$TMP/regen-shift.html" > "$TMP/regen-retitled-other.html"
grep -q 'name="consult-retitled" content="c1"' "$TMP/regen-retitled-other.html" \
  || bad "BL-611: fixture drift: the sed did not insert the consult-retitled meta (c1)"
out="$(bash "$CHECK" "$TMP/regen-retitled-other.html" --prev "$TMP/consult-ok.html" 2>&1)"
[[ "$out" == *"id reused for a different claim"* && "$out" == *"c2"* ]] \
  && ok "BL-611: declaring a DIFFERENT id does not excuse the retitle" \
  || bad "BL-611: an undeclared retitle passed because another id was declared: $out"

# BL-396: an id that DISAPPEARS is a failure too — a claim is closed by marking its
# item decided, never by removing it. Two decided items vanished from a live
# consultation under a string-slice rewrite and this check stayed green for two rounds.
python3 - "$TMP/consult-ok.html" "$TMP/regen-dropped.html" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
t2 = re.sub(r'<section class="consult-item" data-id="c2".*?</section>', "", t, flags=re.S)
assert t2 != t, 'fixture drift: no c2 section to drop'
open(sys.argv[2], "w").write(t2)
PY
out="$(bash "$CHECK" "$TMP/regen-dropped.html" --prev "$TMP/consult-ok.html" 2>&1)"
[[ "$out" == *"[consult-ids]"* && "$out" == *"dropped"* && "$out" == *"c2"* ]] \
  && ok "a dropped id fails --prev and is named" \
  || bad "an id removed between rounds passed --prev (BL-396): $out"

# The one exit: a page declaring consult-surfaces: none is a closed page, not a round.
sed 's#<title>#<meta name="consult-surfaces" content="none: closed page, the record stays"><title>#' \
  "$TMP/regen-dropped.html" > "$TMP/regen-dropped-closed.html"
out="$(bash "$CHECK" "$TMP/regen-dropped-closed.html" --prev "$TMP/consult-ok.html" 2>&1)"
[[ "$out" != *"dropped between rounds"* ]] \
  && ok "a closed page (consult-surfaces: none) may drop ids" \
  || bad "the closed-page exit did not clear the dropped-id failure: $out"

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

# (4b) BL-324: both readers compare RAW SOURCE, so an entity-encoded accent is
#      content they count as prose. Measured on the Spanish translation of
#      home-concepts-report.html: re-wrapping the identical page with literal
#      accents against an entity-encoded baseline reported 7 ids as "reused for
#      a different claim" — same language, same words, same claim.
python3 - "$TMP/consult-ok.html" "$TMP/ent-old.html" "$TMP/ent-new.html" "$C2_TITLE" <<'ENT'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
target = f'data-title="{sys.argv[4]}"'
assert target in t, "fixture drift: item c2's title is not in the wrapped page"
open(sys.argv[2], "w").write(t.replace(target, 'data-title="para qui&eacute;n es el sitio"'))
open(sys.argv[3], "w").write(t.replace(target, 'data-title="para quién es el sitio"'))
ENT
out="$(bash "$CHECK" "$TMP/ent-new.html" --prev "$TMP/ent-old.html" 2>&1)"
[[ "$out" == *"[consult-ids]"* ]] \
  && bad "BL-324: the same title, entity-encoded in one version and literal in the next, read as a changed claim: $out" \
  || ok "an entity-encoded accent is decoded before the id diff compares titles"
# The complement, or the fix is just "stop comparing": a genuinely different
# claim written with accents must still fail.
python3 - "$TMP/consult-ok.html" "$TMP/ent-diff.html" "$C2_TITLE" <<'ENT'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
open(sys.argv[2], "w").write(t.replace(f'data-title="{sys.argv[3]}"',
                                       'data-title="otra afirmaci&oacute;n distinta"'))
ENT
out="$(bash "$CHECK" "$TMP/ent-diff.html" --prev "$TMP/ent-old.html" 2>&1)"
[[ "$out" == *"[consult-ids]"* && "$out" == *"c2"* ]] \
  && ok "a genuinely different accented claim still fails the id diff" \
  || bad "BL-324: decoding entities laundered a real claim change: $out"

# (4c) BL-323: a TRANSLATION changes every data-title by definition, so
#      check_prev failed on all 12 ids of a real page at once. The remedy the
#      message proposes — "append a new id instead" — is wrong here: the claim
#      behind c7 is unchanged, and BRIEF.md plus the page's own ledger anchor on
#      those ids by name. Waivers could not help either: split_waived() runs
#      only in the census, never on the authoring-time check wrap_report.py
#      invokes, so the FAIL was unwaivable at the moment it fired. Unblocking it
#      took moving .aidex-artifact-prev/ out of the tree by hand and resetting
#      the consult-round meta twice.
# Wrapped from two real bodies rather than string-substituted out of the English
# fixture: the `lang` check reads the body's own prose, so a page that merely
# relabels <html lang> is a different defect and would mask this one.
TR_ITEM='<section class="consult-item" data-id="c2" data-title="%s"><h3>%s</h3>
<div class="opts one"><label><input type="radio" name="c2" data-label="A"><span>A</span></label><label><input type="radio" name="c2" data-label="B"><span>B</span></label></div>
<p class="fieldlabel">Notes on this one</p><textarea></textarea></section>'
tr_page() {  # tr_page <lang> <title> <prose> <out>
  printf '<meta name="consult-visual" content="none: %s">\n<div class="page"><main class="main">
<section id="s"><div class="sec-head"><h2>%s</h2></div><p>%s</p>
<section class="consult-group" id="G1" data-id="G1" data-title="%s"><div class="sec-head"><h2>%s</h2></div><p>%s</p>
'"$TR_ITEM"'</section>
<section class="consult-item consult-notes" data-id="notes" data-title="%s"><h3>%s</h3><textarea></textarea></section>
<div class="endbar"><button type="button" id="consult-copy-end">Copy</button><span class="consult-status" id="consult-status-end"></span></div>
</section></main><aside class="rail"><nav class="raillist" id="raillist"></nav>
<div class="consult-bar"><button type="button" id="consult-copy">Copy</button><span class="consult-status" id="consult-status"></span></div></aside></div>\n' "$3" "$2" "$3" "$2" "$2" "$3" "$4" "$4" "$5" "$5" \
    | bash "$WRAP" --title "$2" --lang "$1" --out "$6" >/dev/null 2>&1
}
EN_PROSE='This is the question we are asking about the site and about the people who will use it; there is nothing else in it.'
ES_PROSE='Esta es la pregunta que estamos haciendo sobre el sitio y sobre las personas que lo van a usar; no hay nada más en ella.'
tr_page en "The context" "$EN_PROSE" "who the site is for" "General notes" "$TMP/tr-en.html"
tr_page es "El contexto" "$ES_PROSE" "para quién es el sitio" "Notas generales" "$TMP/tr-es.html"
out="$(bash "$CHECK" "$TMP/tr-es.html" --prev "$TMP/tr-en.html" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] \
  && ok "BL-323: a translation of the same page passes instead of failing every kept id" \
  || bad "BL-323: translating a page still fails consult-ids (rc=$rc): $out"
# Silence would be the wrong fix: the reader still has to see that the titles
# moved, and on which ids.
[[ "$out" == *"NOTE [consult-ids]"* && "$out" == *"c2"* ]] \
  && ok "the moved titles are still reported, as a note naming the ids" \
  || bad "BL-323: the translation passed silently — nothing said the titles moved: $out"
# And within ONE language it is still a failure: the lang pair is the whole
# discriminant, so a same-language shift must not ride out on it.
out="$(bash "$CHECK" "$TMP/mix-new.html" --prev "$TMP/mix-old.html" 2>&1)"
[[ "$out" == *"FAIL [consult-ids]"* ]] \
  && ok "a shift between two pages of the SAME language is still a failure" \
  || bad "BL-323: the note downgraded a same-language claim shift: $out"

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

# Snapshot what run 1 actually left at $PAGE. Comparing against the stored
# baseline instead would only coincide here (run 1 passed, so the two are equal);
# the claim under test is that the PAGE is unchanged, which has to be measured
# against the page.
cp "$PAGE" "$TMP/inv-run1.html"
out2="$(shifted "A different claim")"; rc2=$?
[[ $rc2 -ne 0 ]] && ok "run 2: a claim moved behind a kept id fails" \
                 || bad "run 2: the id shift was not caught: $out2"
# CHANGED 2026-09-20. This used to assert that the violating file was still on disk
# at $PAGE ("fixed in place"). The failing render moved out of the reader's path: on
# a fail $PAGE goes back byte-for-byte to what run 1 wrote, and the violating render
# is kept at .aidex-artifact-prev/<page>.failed for the author, whose real working
# copy is the body sidecar. What the block below measures is unchanged — the baseline
# is still the last PASSING version, so 3a and 3b must still come out as they do.
cmp -s "$PAGE" "$TMP/inv-run1.html" \
  && ok "run 2: the page is restored to the last version that passed" \
  || bad "run 2: the failing render was left at the reader's path"
grep -q 'data-title="A different claim"' \
     "$INV/.context/reports/.aidex-artifact-prev/c.html.failed" \
  && ok "run 2: the violating render is kept for the author at <page>.failed" \
  || bad "run 2: the violating render was not kept anywhere"

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
GOODB='<style>body{color:#111}@media (prefers-color-scheme: dark){body{color:#eee}</style><div class="page"><main class="main"><h1>x</h1></main></div>'

# The one-time offer: it fires when the project has no profile, and records itself
# so it cannot become the 14-offers-across-7-projects nag the usage-retro measured.
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --out "$LANGP/.context/reports/a.html" 2>&1 >/dev/null)"
[[ "$err" == *"profiles/artifact.md"* ]] && ok "a first artifact offers the style profile" \
                                      || bad "the one-time style-profile offer never fired: $err"
[[ -f "$LANGP/.context/.aidex-artifact-style-offered" ]] \
  && ok "the offer records itself" || bad "the offer left no record, so it will repeat"
[[ ! -f "$LANGP/.context/profiles/artifact.md" ]] \
  && ok "the profile itself is never auto-created (e87bbd3)" \
  || bad "the offer created the profile unasked"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --out "$LANGP/.context/reports/b.html" 2>&1 >/dev/null)"
# The offer is identified by ITS OWN words, not by the filename. Every note about
# the profile names that file, so a bare `profiles/artifact.md` substring cannot tell
# the one-time offer apart from the language NOTE asserted below — it only ever
# discriminated because nothing else spoke here. BL-322 makes something else speak.
[[ "$err" != *"Offer the profile to the reader ONCE"* ]] \
  && ok "the offer does not repeat on the next artifact" \
  || bad "the offer nagged a second time: $err"

# --- BL-322: marker present + no profile + no --lang is not silent ------------
# Two functions handed this case to each other and neither spoke:
# style_profile_offer() returns None because the marker exists, and
# _warn_prose_only_language() returned early because there is no profile. So from
# the second artifact onward a project with no declared language got lang="en"
# with nothing on stderr, and check-artifact's lang gate agreed with itself
# because an English body under lang="en" is self-consistent. Absence was
# invisible at every layer. This is the state of `b.html` above.
[[ -n "$err" ]] \
  && ok "the second artifact of a project with no profile still speaks" \
  || bad "BL-322: marker present, no profile, no --lang — stderr was completely silent"
[[ "$err" == *"NOTE:"* && "$err" == *'lang="en"'* ]] \
  && ok "and it states the language it fell back to, as a fact" \
  || bad "BL-322: nothing named lang=\"en\" as the language actually used: $err"
# A fact, not a re-offer: BL-168 removed the nag and it must not return by this door.
[[ "$err" != *"Offer the profile"* ]] \
  && ok "and it is a statement, not the offer coming back" \
  || bad "BL-322: the language note re-opened the offer BL-168 closed: $err"

# --lang silences it: the language IS declared, just not through a profile.
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --lang es \
        --out "$LANGP/.context/reports/c.html" 2>&1 >/dev/null)"
[[ "$err" != *'lang="en"'* ]] \
  && ok "an explicit --lang silences the undeclared-language note" \
  || bad "BL-322: the note fired even though --lang was given: $err"

# --- BL-371: an explicit --lang that CONTRADICTS a declared profile is not silent --
# The note above covers "both absent". The symmetric blind spot: a profile that
# declares `language: es` and a call that passes `--lang en` emitted lang="en" with
# nothing on stderr, and check-artifact's lang gate agreed with itself because an
# English body under lang="en" is self-consistent. That is how a kickoff
# consultation arrived in English in a project that asked for Spanish.
CONTRAP="$TMP/contraproj"; mkdir -p "$CONTRAP/.context/reports"
mkdir -p "$CONTRAP/.context/profiles"; printf -- '- language: es\n' > "$CONTRAP/.context/profiles/artifact.md"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --lang en \
        --out "$CONTRAP/.context/reports/a.html" 2>&1 >/dev/null)"
[[ "$err" == *"NOTE:"* && "$err" == *"language: es"* && "$err" == *"--lang en"* ]] \
  && ok "BL-371: --lang en against a profile declaring es prints a NOTE naming both" \
  || bad "BL-371: --lang contradicting the profile was accepted in silence: $err"
[[ ! -f "$CONTRAP/.context/reports/a.html" ]] \
  && ok "and the page is refused, not written (LOOP-006: every page follows the profile)" \
  || bad "a page wrapped --lang en against a language: es profile was written"
# The negative: agreeing with the profile must stay silent, or the note is noise on
# every correct call.
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --lang es \
        --out "$CONTRAP/.context/reports/b.html" 2>&1 >/dev/null)"
[[ "$err" != *"NOTE:"* ]] \
  && ok "BL-371: --lang agreeing with the profile stays silent" \
  || bad "BL-371: the note fired on an agreeing --lang: $err"

# A close-out report under worklists/_archive/ follows the profile too (BL-382,
# BL-482): only human-verification.* takes --lang en (test-contract-defects.sh).
mkdir -p "$CONTRAP/.context/worklists/_archive"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --lang en \
        --out "$CONTRAP/.context/worklists/_archive/x-report.html" 2>&1 >/dev/null)"
[[ "$err" == *"contradicts"* && ! -f "$CONTRAP/.context/worklists/_archive/x-report.html" ]] \
  && ok "a close-out record under worklists/_archive/ with --lang en is noted and refused" \
  || bad "a close-out record kept --lang en against the profile: $err"

grep -q 'language:' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../assets/templates" && pwd -P)/artifact.md.template" \
  && ok "the style template carries a parseable language: field" \
  || bad "artifact.md.template has no language: field"

grep -o '<html lang="[a-z]*"' "$LANGP/.context/reports/a.html" | grep >/dev/null 'lang="en"' \
  && ok "no profile falls back to en (D-04)" || bad "wrong default language"

mkdir -p "$LANGP/.context/profiles"; printf '## Language\n\n- language: es\n' > "$LANGP/.context/profiles/artifact.md"
printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --out "$LANGP/.context/reports/c.html" >/dev/null 2>&1
grep -q '<html lang="es"' "$LANGP/.context/reports/c.html" \
  && ok "the profile's language: is applied without --lang" \
  || bad "the language: field is not load-bearing"

# The profile's `## Language` section is its last one: an earlier line shaped like
# the field (a worked example in another section) is not the declaration (LOOP-006).
printf '## Layout\n\n- language: en (the code blocks)\n\n## Language\n\n- language: es\n' \
  > "$LANGP/.context/profiles/artifact.md"
printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --out "$LANGP/.context/reports/c2.html" >/dev/null 2>&1
grep -q '<html lang="es"' "$LANGP/.context/reports/c2.html" \
  && ok "the language: field inside ## Language wins over an earlier field-shaped line" \
  || bad "an earlier language: line won over the ## Language section: $(grep -o '<html lang="[a-z]*"' "$LANGP/.context/reports/c2.html")"
# …and the railhead the wrap injects is in that language (ui-string-language).
grep -q '<p class="railhead">Contenido</p>' "$LANGP/.context/reports/c2.html" \
  && ok "the injected rail is headed in the page's language" \
  || bad "the injected rail is not headed Contenido on an es page: $(grep -o '<p class="railhead">[^<]*' "$LANGP/.context/reports/c2.html")"
mkdir -p "$LANGP/.context/profiles"; printf '## Language\n\n- language: es\n' > "$LANGP/.context/profiles/artifact.md"

printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" --lang fr --out "$LANGP/.context/reports/d.html" >/dev/null 2>&1
[[ ! -f "$LANGP/.context/reports/d.html" ]] \
  && ok "an explicit --lang against the profile is refused, not silently applied" \
  || bad "--lang fr against a language: es profile was written as $(grep -o '<html lang="[a-z]*"' "$LANGP/.context/reports/d.html")"

# A profile that names its language in PROSE and declares no `language:` field is
# the one case the BL-279 page check cannot see: the wrapper falls to "en", the
# author writes English to match, and page and <html lang> agree — a consistently
# wrong artifact that every check passes. Field-observed 2026-09-07: work_hours_ws
# carried "Default for this project's artifacts: **Spanish** (neutral LATAM)" as
# prose and had been shipping English artifacts silently. The wrap still resolves
# to "en" — that is the honest answer to an undeclared field — but it must SAY so.
printf '## Language\n\n- Default for this project: **Spanish** (neutral LATAM).\n' \
  > "$LANGP/.context/profiles/artifact.md"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" \
        --out "$LANGP/.context/reports/e.html" 2>&1 >/dev/null)"
[[ "$err" == *"declares no \`language:\` field"* ]] \
  && ok "a prose-only language is reported, not silently defaulted" \
  || bad "prose-only language defaulted to en with no warning: $err"
grep -q '<html lang="en"' "$LANGP/.context/reports/e.html" \
  && ok "a prose-only language still resolves to en (the field is the contract)" \
  || bad "prose was parsed as a language field"

# and the complement, so the warning cannot become a nag: a profile that simply
# has nothing to say about language is not a misconfiguration.
mkdir -p "$LANGP/.context/profiles"; printf '## Palette\n\n- accent: teal\n' > "$LANGP/.context/profiles/artifact.md"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" \
        --out "$LANGP/.context/reports/f.html" 2>&1 >/dev/null)"
[[ "$err" != *"declares no \`language:\` field"* ]] \
  && ok "a profile silent on language is not warned about" \
  || bad "the prose-language warning fires on a profile that never mentions one: $err"

# The upward walk stops at $HOME, like _lib.sh's find_project_root. Without the
# boundary a stray ~/.context/ captures every uninitialised project (field-observed
# 2026-07-25): the artifact would take a neighbour's language and drop this
# project's one-time offer marker in the home directory.
FAKEHOME="$TMP/home"; mkdir -p "$FAKEHOME/.context" "$FAKEHOME/proj"
mkdir -p "$FAKEHOME/.context/profiles"; printf '## Language\n\n- language: de\n' > "$FAKEHOME/.context/profiles/artifact.md"
printf '%s\n' "$GOODB" | HOME="$FAKEHOME" bash "$WRAP" --title "T" \
  --out "$FAKEHOME/proj/r.html" >/dev/null 2>&1
grep -q '<html lang="en"' "$FAKEHOME/proj/r.html" \
  && ok "the profile walk stops at \$HOME" \
  || bad "a stray ~/.context/ captured an uninitialised project's language"
[[ ! -f "$FAKEHOME/.context/.aidex-artifact-style-offered" ]] \
  && ok "no offer marker is dropped in \$HOME" || bad "the offer marker landed in \$HOME"

# An unreadable profile must not take the artifact down with it. `isfile` only
# stats — it does not imply readability — and the read was a bare open(), so a
# mode-000 profiles/artifact.md aborted the whole wrap with a PermissionError
# traceback and NO file was written. The profile is an optimisation, not a
# contract: an unreadable one degrades to the D-04 default and says so.
NOREAD="$TMP/noread"; mkdir -p "$NOREAD/.context/reports"
mkdir -p "$NOREAD/.context/profiles"; printf '## Language\n\n- language: es\n' > "$NOREAD/.context/profiles/artifact.md"
chmod 000 "$NOREAD/.context/profiles/artifact.md"
err="$(printf '%s\n' "$GOODB" | bash "$WRAP" --title "T" \
        --out "$NOREAD/.context/reports/a.html" 2>&1 >/dev/null)"; rc=$?
chmod 644 "$NOREAD/.context/profiles/artifact.md"
[[ "$err" != *"Traceback"* ]] && ok "an unreadable style profile does not raise" \
                             || bad "the wrap died on an unreadable profile: $err"
[[ -f "$NOREAD/.context/reports/a.html" ]] \
  && ok "the artifact is still written when the profile cannot be read" \
  || bad "an unreadable profile prevented the artifact from being written"
grep -q '<html lang="en"' "$NOREAD/.context/reports/a.html" 2>/dev/null \
  && ok "an unreadable profile falls back to en (D-04)" \
  || bad "the fallback language was not applied"
# Require the NOTE, not just the filename: a traceback also contains the path, so
# a substring check on `profiles/artifact.md` passes on the unfixed code.
[[ "$err" == *"NOTE:"*"profiles/artifact.md"* ]] \
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
  mkdir -p "$WT/main/.context/profiles"; printf '## Language\n\n- language: es\n' > "$WT/main/.context/profiles/artifact.md"
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
printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n<meta name="viewport" content="width=device-width">\n<title>t</title>\n<style>@media (prefers-color-scheme: dark){body{background:#111}</style>\n</head>\n<body><h1>Pre-kit</h1></body></html>\n' > "$TMP/prekit.html"
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

mkkit tw-table.html '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>s</h2><div class="tw"><table><tr><td>a</td><td>b</td></tr></table></div></section></main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>'
bash "$CHECK" "$TMP/tw-table.html" >/dev/null 2>&1 \
  && ok "control: the same table inside .tw passes" \
  || bad "a table inside the kit wrapper was rejected: $(bash "$CHECK" "$TMP/tw-table.html" 2>&1)"

# The page's OWN scroll wrapper counts. The class set is read from the CSS the
# document carries, not from a whitelist — a page that wraps its tables in
# `.scroll` is honouring the rule, and a checker that only knows `.tw` would fail
# it for a defect it does not have. One artifact on disk does exactly this.
mkkit own-scroll.html '<style>.roll{overflow-x:auto}</style><div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>s</h2><div class="roll"><table><tr><td>a</td></tr></table></div></section></main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>'
bash "$CHECK" "$TMP/own-scroll.html" >/dev/null 2>&1 \
  && ok "a page's own overflow wrapper counts, without a whitelist" \
  || bad "a table in the page's own scroll wrapper was rejected: $(bash "$CHECK" "$TMP/own-scroll.html" 2>&1)"

# A commented-out table is not markup. skeleton.html is a file of examples in
# comments, so this is the false positive that would have fired on the very page
# authors copy from.
mkkit commented-table.html '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>s</h2><!-- <table><tr><td>example</td></tr></table> --><p>Prose.</p></section></main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>'
bash "$CHECK" "$TMP/commented-table.html" >/dev/null 2>&1 \
  && ok "a table inside an HTML comment is not counted" \
  || bad "a commented-out table was reported as unwrapped: $(bash "$CHECK" "$TMP/commented-table.html" 2>&1)"

# --- The rail is built at runtime from `.main > section[id]` into #raillist ----
# (composer.js), so a page can pass every static check and open with NO index:
# either the author wrote .page/.main and left the <aside class="rail"> out, or
# only some of the h2s sit in an id'd top-level section and the rail lists those.
# Both shipped on 2026-09-13 (D4, spike 2026-09-13-supervised-cheap-subagents).
echo "== the navigation rail (D4) =="
mkkit norail.html '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>One</h2><p>Prose.</p></section><section id="s2"><h2>Two</h2><p>Prose.</p></section></main></div>'
out="$(bash "$CHECK" "$TMP/norail.html" 2>&1)"
[[ "$out" == *"rail"* ]] \
  && ok "a kit page with .page/.main but no #raillist is caught" \
  || bad "a page with no rail container passed, so it opens with no index: $out"

mkkit partrail.html '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>One</h2><p>Prose.</p></section><h2>Two</h2><p>Loose.</p><div><h2>Three</h2></div></main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>'
out="$(bash "$CHECK" "$TMP/partrail.html" 2>&1)"
[[ "$out" == *"rail"* ]] \
  && ok "an h2 outside any id'd top-level section is caught (the rail would list 1 of 3)" \
  || bad "a page whose rail can only index 1 of its 3 headings passed: $out"

bash "$CHECK" "$TMP/wrapped-ok.html" >/dev/null 2>&1 \
  && ok "control: one section per h2 plus #raillist passes" \
  || bad "the well-formed rail page was rejected: $(bash "$CHECK" "$TMP/wrapped-ok.html" 2>&1)"

# A tag left open swallows what follows: haiku's T2 page (A1, 2026-09-14) never
# closed its <figure>, so in the DOM every section was a child of the figure,
# `.main > section[id]` matched nothing and the rail listed one entry — while a
# depth counter over <section> tags alone saw nothing wrong. The check must see
# nesting the way the browser does: sections must be DIRECT children of .main.
mkkit swallowed.html '<div class="page"><main class="main"><h1>t</h1><figure><svg viewBox="0 0 10 10"></svg><section id="s1"><h2>One</h2><p>Prose.</p></section><section id="s2"><h2>Two</h2><p>Prose.</p></section></main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>'
out="$(bash "$CHECK" "$TMP/swallowed.html" 2>&1)"
[[ "$out" == *"rail"* ]] \
  && ok "sections swallowed by an unclosed <figure> are caught (the rail would index none)" \
  || bad "an unclosed figure hid every section from the rail and the check passed: $out"

mkkit nested.html '<div class="page"><main class="main"><h1>t</h1><div class="wrap"><section id="s1"><h2>One</h2><p>Prose.</p></section></div></main><aside class="rail"><nav class="raillist" id="raillist"></nav></aside></div>'
out="$(bash "$CHECK" "$TMP/nested.html" 2>&1)"
[[ "$out" == *"rail"* ]] \
  && ok "a section wrapped in a div under .main is caught (not a direct child)" \
  || bad "a section that is not a direct child of .main passed: $out"

# The wrapper closes the gap for the .html body path the way md_body already
# does for markdown: a body with .main and no #raillist gets the skeleton's aside.
printf '%s\n' '<div class="page"><main class="main"><h1>t</h1><section id="s1"><h2>One</h2><p>Prose.</p></section></main></div>' > "$TMP/norail-body.html"
bash "$WRAP" --title "t" --lang en --in "$TMP/norail-body.html" --out "$TMP/norail-wrapped.html" >/dev/null 2>&1
grep -q 'id="raillist"' "$TMP/norail-wrapped.html" \
  && ok "wrap injects the rail aside into an .html body that has none" \
  || bad "the wrapped page still has no #raillist"
bash "$CHECK" "$TMP/norail-wrapped.html" >/dev/null 2>&1 \
  && ok "and the wrapped page passes the rail check" \
  || bad "the wrapped page fails: $(bash "$CHECK" "$TMP/norail-wrapped.html" 2>&1)"

# Route A boards are full of tables and are not kit pages: the same stamp gate as
# the layout check keeps them out of it.
printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n<meta name="viewport" content="width=device-width">\n<title>t</title>\n<style>@media (prefers-color-scheme: dark){body{background:#111}</style>\n</head>\n<body><table><tr><td>a</td></tr></table></body></html>\n' > "$TMP/board.html"
bash "$CHECK" "$TMP/board.html" >/dev/null 2>&1 \
  && ok "a page without the kit stamp is not judged on the kit's table wrapper" \
  || bad "a non-kit page was failed for the kit's table wrapper"

# --- The census: the contract, re-judged after the fact -----------------------
# The contract was evaluated exactly once, at the wrap, and never again. Two
# observed holes: a page that passed at 10:31 and failed by 20:15 the same day
# (the .tw and notes-box rules landed that evening), and a page that never went
# through the wrapper at all (BL-168). An absence claim needs a census; waivers
# make it livable, because retroactive drift is EXPECTED and a sweep whose
# failures cannot be settled becomes noise nobody reads.
echo "== census =="

CEN="$TMP/census-proj"
mkdir -p "$CEN/.context/reports/.aidex-artifact-prev" \
         "$CEN/.context/backlog/_archive/.aidex-artifact-prev"
# A passing page, a kit page that drifted out of contract (layout only), an
# archived page (closed work is not re-judged), and a baseline copy (superseded
# versions are not re-judged either — they were judged at their canonical path).
bash "$WRAP" --title "G" --out "$CEN/.context/reports/good.html" >/dev/null 2>&1 <<<"$GOOD"
mk_census_bad() {
  printf '<!doctype html>\n<meta charset="utf-8">\n<meta name="viewport" content="width=device-width">\n<title>t</title>\n<meta name="artifact-kit" content="1">\n<style>@media (prefers-color-scheme: dark){}</style>\n<h1>Full bleed</h1>\n' > "$1"
}
mk_census_bad "$CEN/.context/reports/bad.html"
printf '<h1>fragment</h1>\n' > "$CEN/.context/backlog/_archive/old.html"
printf '<h1>fragment</h1>\n' > "$CEN/.context/reports/.aidex-artifact-prev/ghost.html"
printf '<h1>fragment</h1>\n' > "$CEN/.context/backlog/_archive/.aidex-artifact-prev/dead.html"

out="$(bash "$CHECK" --census "$CEN" 2>&1)"; rc=$?
[[ $rc -eq 1 ]] && ok "census: a drifted artifact fails the sweep" \
                || bad "census exited $rc on a tree with a known-failing page: $out"
[[ "$out" == *"bad.html"* && "$out" == *"[layout]"* ]] \
  && ok "census: the drifted page is named with its failing check" \
  || bad "census did not name the drifted page: $out"
# Judged means a FAIL line — the hygiene NOTEs below legitimately name these
# files, so the assertion reads FAIL lines only, never the whole capture.
grep -E '^  FAIL' <<<"$out" | grep >/dev/null 'old.html' \
  && bad "census re-judged a page under _archive/: $out" \
  || ok "census: archived pages are closed work, not re-judged"
grep -E '^  FAIL' <<<"$out" | grep >/dev/null -E 'ghost.html|dead.html' \
  && bad "census judged a .aidex-artifact-prev copy: $out" \
  || ok "census: baseline copies are superseded versions, not re-judged"
[[ "$out" == *"good.html"* ]] \
  && bad "census flagged the passing page: $out" \
  || ok "census: the passing page is not flagged"

# Baseline hygiene: report-only, with the exact rm to run — never deletes.
[[ "$out" == *"orphaned baseline"* && "$out" == *"ghost.html"* ]] \
  && ok "census: an orphaned baseline is reported with its rm" \
  || bad "the orphaned baseline went unreported: $out"
grep -q "orphaned baseline.*_archive/.aidex-artifact-prev/dead.html'" <<<"$out" \
  && ok "census: a baseline under _archive/ whose page is gone is reported as orphaned" \
  || bad "the archived baseline went unreported: $out"
[[ -f "$CEN/.context/reports/.aidex-artifact-prev/ghost.html" \
   && -f "$CEN/.context/backlog/_archive/.aidex-artifact-prev/dead.html" ]] \
  && ok "census: hygiene reports, it does not delete" \
  || bad "the census DELETED baseline files instead of reporting them"

# A waiver settles accepted drift — same store, same format as validate.py,
# rule spelled artifact-<check>.
printf 'artifact-layout | .context/reports/bad.html | - | accepted full-bleed, pre-.page page\n' \
  > "$CEN/.context/.aidex-waivers"
out="$(bash "$CHECK" --census "$CEN" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "census: waived drift settles the sweep" \
                || bad "a waived finding still failed the census: $out"
[[ "$out" == *"waived: 2"* ]] \
  && ok "census: waived findings are reported, never silently dropped" \
  || bad "the waived count is missing or wrong: $out"

# An anchored waiver resurfaces when the file changes (here: a wrong anchor).
printf 'artifact-layout | .context/reports/bad.html | sha256:0000000000 | stale anchor\n' \
  > "$CEN/.context/.aidex-waivers"
bash "$CHECK" --census "$CEN" >/dev/null 2>&1 \
  && bad "a stale-anchored waiver kept suppressing the finding" \
  || ok "census: a stale anchor resurfaces the finding"
rm "$CEN/.context/.aidex-waivers"

# --- The wrap re-judges its own directory --------------------------------------
# NOTE-only: the file just written passed, and a neighbour's drift must not
# block it — but it must be AUDIBLE where new work happens, or drift stays
# invisible until someone remembers to run a census by hand.
err="$(bash "$WRAP" --title "G" --out "$CEN/.context/reports/good.html" 2>&1 >/dev/null <<<"$GOOD")"; rc=$?
[[ $rc -eq 0 ]] && ok "sweep: a passing wrap is not blocked by a drifted neighbour" \
                || bad "a neighbour's drift failed this wrap (exit $rc): $err"
[[ "$err" == *"neighbouring artifact"* && "$err" == *"bad.html"* ]] \
  && ok "sweep: the drifted neighbour is named at wrap time" \
  || bad "the wrap stayed silent about a drifted neighbour: $err"
printf 'artifact-layout | .context/reports/bad.html | - | accepted full-bleed\n' \
  > "$CEN/.context/.aidex-waivers"
err="$(bash "$WRAP" --title "G" --out "$CEN/.context/reports/good.html" 2>&1 >/dev/null <<<"$GOOD")"
[[ "$err" != *"neighbouring artifact"* ]] \
  && ok "sweep: waived drift stays quiet, so the note cannot become a nag" \
  || bad "the wrap nagged about drift that is already waived: $err"

echo "== double wrap: one kit envelope per document (BL-414) =="
# The field shape: a revising caller took the WRAPPED page from disk as its body,
# stripped only the <!doctype> (which is the one thing the wrapper refuses), and
# piped it back through --out. The kit went in twice, both composers appended to
# the same #raillist, and the contract said OK. The fixture is built by running the
# REAL wrapper twice — a hand-written page could not prove the wrapper produces it.
DW="$TMP/dw"; mkdir -p "$DW"
printf '%s\n' "$GOOD" | bash "$WRAP" --title "T" --out "$DW/once.html" >/dev/null 2>&1
sed '/<!doctype/Id' "$DW/once.html" > "$DW/body2.html"
dw_out="$(bash "$WRAP" --title "T" --in "$DW/body2.html" --out "$DW/twice.html" 2>&1)"; dw_rc=$?
# The render is rolled back on a failing --out, so judge the kept attempt.
DW_PAGE="$DW/twice.html"
[[ -f "$DW/.aidex-artifact-prev/twice.html.failed" ]] && DW_PAGE="$DW/.aidex-artifact-prev/twice.html.failed"
[[ $(grep -c 'name="artifact-kit"' "$DW_PAGE") -eq 2 ]] \
  && ok "the fixture really is doubly wrapped (two kit stamps)" \
  || bad "the fixture is not a double wrap, so the rule below proves nothing"
chk_out="$(bash "$CHECK" "$DW_PAGE" 2>&1)"
[[ "$chk_out" == *"FAIL [double-wrap]"* ]] \
  && ok "the checker FAILS a doubly-wrapped page" \
  || bad "the checker accepted a doubly-wrapped page: $chk_out"
[[ "$chk_out" == *"body"* ]] \
  && ok "the message points at extracting the body" \
  || bad "the message does not say what to do: $chk_out"
[[ $dw_rc -ne 0 ]] \
  && ok "--out exits non-zero on a doubly-wrapped output" \
  || bad "--out wrote a doubly-wrapped page and reported success: $dw_out"
[[ ! -e "$DW/twice.html" ]] \
  && ok "the doubly-wrapped page is not left at the reader's path" \
  || bad "--out left a doubly-wrapped page on disk"
# A single wrap of the same content must stay clean: the rule keys on the kit
# stamp and the composer, never on how many <style> or <meta> blocks a page has.
bash "$CHECK" "$DW/once.html" >/dev/null 2>&1 \
  && ok "a singly-wrapped page still passes" || bad "the double-wrap rule fires on a normal page"

echo "== lang: the body's language must match <html lang> (BL-279) =="
# The 2026-08-31 memory-audit page: English prose under a Spanish profile. The
# wrapper set lang=es and the composer spoke Spanish over an English body.
EN_BODY='<div class="page"><main class="main"><h1>Nine memories</h1><p>The checker sees size and the defect is content: most of the files duplicate a document that already exists or describe work that has closed, and the rest belong in a backlog item or a reference. The instrument with the right rubric has not run since May, and nothing at all looks at a memory when it is saved, which is the whole problem.</p></main></div>'
ES_BODY='<div class="page"><main class="main"><h1>Nueve memorias</h1><p>El verificador mide el tamaño y el defecto es el contenido: la mayoría de los archivos duplica un documento que ya existe o describe trabajo que ya cerró, y el resto pertenece a un ítem del backlog o a una referencia. El instrumento con la rúbrica correcta no corre desde mayo, y nada mira una memoria cuando se guarda, que es todo el problema.</p></main></div>'
printf '%s\n' "$EN_BODY" | bash "$WRAP" --title "t" --lang es > "$TMP/en-under-es.html" 2>/dev/null
out="$(bash "$CHECK" "$TMP/en-under-es.html" 2>&1)"
grep -q "FAIL \[lang\]" <<<"$out" && ok "English body under lang=es fails [lang]" || bad "English body under lang=es was accepted: $out"
printf '%s\n' "$ES_BODY" | bash "$WRAP" --title "t" --lang es > "$TMP/es-under-es.html" 2>/dev/null
bash "$CHECK" "$TMP/es-under-es.html" >/dev/null 2>&1 && ok "Spanish body under lang=es passes" || bad "Spanish body under lang=es was rejected"
printf '%s\n' "$ES_BODY" | bash "$WRAP" --title "t" --lang en > "$TMP/es-under-en.html" 2>/dev/null
grep -q "FAIL \[lang\]" <<<"$(bash "$CHECK" "$TMP/es-under-en.html" 2>&1)" && ok "Spanish body under lang=en fails [lang]" || bad "Spanish body under lang=en was accepted"
# A short page has no dominant language to judge: never fail on thin evidence.
printf '%s\n' '<div class="page"><main class="main"><h1>x</h1><p>ok</p></main></div>' | bash "$WRAP" --title "t" --lang es > "$TMP/thin.html" 2>/dev/null
bash "$CHECK" "$TMP/thin.html" >/dev/null 2>&1 && ok "a page too short to judge is not flagged" || bad "thin page flagged for language"

# BL-657: a bare .svg figure file (root element <svg>, no <html>) has no lang to carry.
# Under a language: es profile it failed [lang] (no lang read as "en" against a Spanish
# body) and [lang-follows-profile] (lang="" against es). Shape of the reported figure,
# with its client data replaced.
SVGP="$TMP/svgproj"; mkdir -p "$SVGP/.context/research/figs"; git -C "$SVGP" init -q . 2>/dev/null
mkdir -p "$SVGP/.context/profiles"; printf -- '- language: es\n' > "$SVGP/.context/profiles/artifact.md"
cat > "$SVGP/.context/research/figs/fig-transfer.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" id="fig-transfer" viewBox="0 0 880 420" role="img" aria-label="Barras apiladas de los GB descargados por mes, por la red de entrega y directo desde el almacén, con el costo de la descarga directa de cada mes.">
  <style>
    #fig-transfer { font-family: system-ui, sans-serif; color: var(--ink); }
    #fig-transfer text { fill: currentColor; font-size: 13px; }
  </style>
  <rect x="80" y="60" width="90" height="200" style="fill: var(--s1)"/>
  <text x="80" y="40">Por la red de entrega</text>
  <text x="200" y="40">Directo desde el almacén</text>
  <text x="80" y="300">Jun 2026</text>
  <text x="80" y="330">28 ago: tras la mudanza, las descargas salen directo del almacén</text>
  <text x="80" y="350">22 sep: corregido por el equipo, con aviso automático</text>
  <text x="80" y="370">el plan de la red empezó a fines de junio</text>
  <text x="80" y="390">Fuente: el panel de costos de la cuenta, con los datos del mes.</text>
</svg>
SVG
out="$(bash "$CHECK" "$SVGP/.context/research/figs/fig-transfer.svg" 2>&1)"
grep -q 'FAIL \[doctype\]' <<<"$out" && ! grep -q 'FAIL \[lang' <<<"$out" \
  && ok "BL-657: a bare .svg figure under a language: es profile fails no language check" \
  || bad "BL-657: a bare svg failed a language check: $(grep 'FAIL \[lang' <<<"$out")"

echo
echo "artifact contract: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
