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

echo
echo "artifact contract: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
