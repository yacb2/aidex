#!/usr/bin/env bash
# test-email-draft.sh - email-draft.py output must survive Outlook (BL-669).
# Layer: script contract (one spec in, two files out); no browser decides these properties.
# Protects: inline-style-only HTML, no max width, tables kept as <table>, table rows kept in the .txt.
set -uo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/email-draft.py"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
cat > "$D/reply.md" <<'SPEC'
---
subject: "Re: Presupuesto"
to: ana@example.com
cc: luis@example.com
language: es
---

Hola Ana, esto es **importante** y esto *enfatizado*, mira [el enlace](https://example.com/x).

## Pasos

- primero
- segundo

| Concepto | Importe |
|---|---|
| Licencia | 100 |
| Soporte | 50 |

```
linea uno
linea dos
```
SPEC

python3 "$SCRIPT" "$D/reply.md" >/dev/null || { fail "converter exited non-zero"; exit 1; }
H="$D/reply.html"; T="$D/reply.txt"
[[ -f "$H" && -f "$T" ]] || { fail "html or txt missing"; exit 1; }

no() { grep -qiE "$2" "$H" && fail "$1: found /$2/ in html" || pass "$1"; }
no "no script tag" '<script'
no "no link tag" '<link'
no "no style tag" '<style'
no "no class attribute" 'class='
no "no max-width" 'max-width'

# every element that carries presentation has an inline style
bare="$(grep -oE '<(p|h[1-6]|ul|ol|li|table|th|td|pre|strong|em|a)[ >][^>]*>' "$H" | grep -v 'style=' || true)"
[[ -z "$bare" ]] && pass "every styled tag is inline" || fail "tags without inline style: $bare"

grep -q '<table style=' "$H" && grep -q '<td style=[^>]*>Licencia</td>' "$H" && pass "table is a <table>" || fail "table not rendered as <table>"
grep -q '<strong style=[^>]*>importante</strong>' "$H" && pass "bold" || fail "bold missing"
grep -q '<a href="https://example.com/x" style=' "$H" && pass "link" || fail "link missing"
grep -q '<li style=[^>]*>primero</li>' "$H" && pass "list" || fail "list missing"
grep -q '<pre style=' "$H" && grep -q 'linea dos' "$H" && pass "fenced block" || fail "pre missing"
grep -q 'id="subject">Re: Presupuesto<' "$H" && grep -q 'id="to">ana@example.com<' "$H" && pass "subject and recipients on top" || fail "header missing"

grep -qF 'Licencia | 100' "$T" && grep -qF 'Soporte | 50' "$T" && pass "txt carries table rows" || fail "txt lacks table rows"
grep -q '^Subject: Re: Presupuesto' "$T" && pass "txt subject" || fail "txt subject missing"

# ---- table of edge cases: each spec is converted under a 5 s alarm (a hang is a failure) ----
conv() { # conv <name> <subject-line> <body>; sets CH/CT/RC
  printf -- '---\nsubject: %s\nlanguage: es\n---\n%s\n' "$2" "$3" > "$D/$1.md"
  perl -e 'alarm 5; exec @ARGV' python3 "$SCRIPT" "$D/$1.md" >/dev/null 2>"$D/$1.err"; RC=$?
  CH="$D/$1.html"; CT="$D/$1.txt"
}
P='<p style="margin:0 0 12px 0;">'
expect() { # expect <name> <file> <fixed string>
  grep -qF -- "$3" "$2" 2>/dev/null && pass "$1" || fail "$1: missing [$3]"
}
for body in $'Ticket\n#123 is fixed' '#hashtag' '####### x' '#'; do
  conv hash 'S' "$body"; [[ $RC -eq 0 ]] && pass "hash-line terminates: $body" || fail "hash-line exit $RC (hang or crash): $body"
done
conv hashp 'S' $'Ticket\n#123 is fixed'
expect "hash line joins with br (B1+M4)" "$CH" "${P}Ticket<br>#123 is fixed</p>"
expect "single newline kept in txt (M4)" "$CT" $'Ticket\n#123 is fixed'
conv subj 'Re: "Proyecto X"' 'x'
expect "inner quotes kept in html subject (B2)" "$CH" 'id="subject">Re: &quot;Proyecto X&quot;<'
grep -qx 'Subject: Re: "Proyecto X"' "$CT" && pass "inner quotes kept in txt subject (B2)" || fail "txt subject quotes (B2)"
conv subjq '"Quoted"' 'x'
expect "one wrapping pair stripped (B2)" "$CH" 'id="subject">Quoted<'
conv tbl 'S' $'Here is the table:\n| A | B |\n|---|---|\n| 1 | 2 |'
expect "table after paragraph (M1) table" "$CH" '<table style='
expect "paragraph ends at the table (M1)" "$CH" "${P}Here is the table:</p>"
conv font 'S' 'x'
expect "copy script carries FONT (M2)" "$CH" "font-family:Aptos,\&#x27;Aptos Display\&#x27;,Calibri"
conv li 'S' $'- item that\n  wraps here\n- next'
expect "wrapped list item (M3)" "$CH" '>item that wraps here</li>'
[[ "$(grep -o '<li ' "$CH" | wc -l | tr -d ' ')" == 2 ]] && pass "two li (M3)" || fail "li count (M3)"
conv br 'S' $'Saludos,\nAna Perez'
expect "sign-off hard break html (M4)" "$CH" "${P}Saludos,<br>Ana Perez</p>"
expect "sign-off newline txt (M4)" "$CT" $'Saludos,\nAna Perez'
conv href 'S' '[x](https://e.com/a"onmouseover="y)'
grep -q 'href="[^"]*"[^>]*onmouseover' "$CH" && fail "href attribute injection (L1)" || pass "href escaped (L1)"
conv both 'S' '***both***'
expect "triple star nests (L3)" "$CH" '<strong style="font-weight:bold;"><em style="font-style:italic;">both</em></strong>'
python3 "$SCRIPT" "$D/hash.md" --out >/dev/null 2>"$D/out.err"; rc=$?
{ [[ $rc -ne 0 ]] && ! grep -q Traceback "$D/out.err"; } && pass "--out last arg: usage, no traceback (L10)" || fail "--out last arg (L10) rc=$rc"

[[ $FAILURES -eq 0 ]] && { echo "OK"; exit 0; }
echo "$FAILURES failure(s)"; exit 1
