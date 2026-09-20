#!/usr/bin/env bash
# test-style-profile.sh — cells for the communications house-style profile (BL-216, BL-415).
#
# The acceptance's hard requirement is that ABSENCE of a profile resolves to the
# documented default and never to an error — a scaffolder that fails on a workspace
# with no profile is worse than one that ignores style entirely.
#
# paste_font (BL-415) is the axis whose VALUE carries double quotes and commas, so every
# assertion on it is byte-exact (grep -F on the whole string): the font stack crosses a
# shell default, a `key: value` parser and an awk injection, and a layer that ate one of
# those quotes would still render a plausible-looking line.

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/new-communication.sh"
AXES=(voice sign_off tone address date_format paste_font)

# The shipped defaults, in AXES order. Pinned here so a silent edit to one of them in
# new-communication.sh has to be made in two places on purpose.
DEFAULTS=(
  "first-person singular — never the editorial 'we' for work one person did"
  "none — the message ends with its last paragraph, no signature block"
  "cordial-professional — one line of courtesy opening and closing, plain vocabulary"
  "mirror the interlocutor's own register"
  "spelled out in the body's own language (front-matter stays ISO per D-01)"
  'font-family: Aptos,"Aptos Display",Calibri,Carlito,"Segoe UI",Arial,sans-serif at 12 pt — state it on any body.html (a browser preview falls back to Calibri; that is expected)'
)

# An override that is itself quote- and comma-bearing, and not a value the parser's
# surrounding-quote stripping would touch (it neither starts nor ends with a quote).
OVERRIDE_PASTE_FONT='font-family: FUENTE-X,"Fuente Ancha",Georgia,"Times New Roman",serif at 11 pt'

FAILURES=0

fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

mk_project() {
  local root; root="$(mktemp -d)"
  mkdir -p "$root/.git"
  printf '%s' "$root"
}

# Scaffold a sent draft and echo the body path.
scaffold() {
  local root="$1" slug="$2"
  (cd "$root" && NO_COLOR=1 bash "$SCRIPT" sent "$slug" 2>/dev/null) || return 1
}

# --- Cell 1: no profile -> shipped defaults, exit 0 ---------------------------------
ROOT="$(mk_project)"
BODY="$(scaffold "$ROOT" no-profile)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 1: scaffolding without a profile must exit 0, got $RC"
if [[ -f "$BODY" ]]; then
  grep -q 'HOUSE STYLE (defaults' "$BODY" || fail "cell 1: the defaults header is missing"
  for axis in "${AXES[@]}"; do
    grep -q -- "- $axis:" "$BODY" || fail "cell 1: axis '$axis' absent from the rendered block"
  done
  for i in "${!AXES[@]}"; do
    grep -qF -- "${DEFAULTS[$i]}" "$BODY" \
      || fail "cell 1: the documented default for '${AXES[$i]}' did not reach the body byte-exact"
  done
  grep -q '{{STYLE}}' "$BODY" && fail "cell 1: the placeholder was left unsubstituted"
else
  fail "cell 1: no body.md was produced"
fi
pass "no profile resolves to the six documented defaults byte-exact, not an error"
rm -rf "$ROOT"

# --- Cell 2: a full profile overrides every axis ------------------------------------
ROOT="$(mk_project)"
mkdir -p "$ROOT/.context"
cat > "$ROOT/.context/communication-style.md" <<EOF
# Style

Prose the parser must ignore, including a decoy line: voice: NOT-THIS-ONE

## Profile

\`\`\`
voice: PRIMERA-PERSONA
sign_off: FIRMA-FIJA
tone: TONO-X
address: TRATAMIENTO-X
date_format: FECHA-X
paste_font: $OVERRIDE_PASTE_FONT
\`\`\`

## Notes

voice: ALSO-NOT-THIS-ONE
EOF
BODY="$(scaffold "$ROOT" full-profile)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 2: expected exit 0, got $RC"
grep -q 'HOUSE STYLE (from .context/communication-style.md' "$BODY" \
  || fail "cell 2: the block does not say where the values came from"
for v in PRIMERA-PERSONA FIRMA-FIJA TONO-X TRATAMIENTO-X FECHA-X; do
  grep -q "$v" "$BODY" || fail "cell 2: profile value '$v' did not reach the body"
done
grep -qF -- "$OVERRIDE_PASTE_FONT" "$BODY" \
  || fail "cell 2: the quote- and comma-bearing paste_font override did not survive byte-exact"
grep -qF -- "${DEFAULTS[5]}" "$BODY" \
  && fail "cell 2: the shipped font stack leaked through even though the profile set paste_font"
grep -q 'NOT-THIS-ONE' "$BODY" \
  && fail "cell 2: a 'voice:' line OUTSIDE the ## Profile fence was parsed as config"
grep -q 'first-person singular — never' "$BODY" \
  && fail "cell 2: a default leaked through even though the profile set that axis"
pass "a full profile overrides all six axes, and only the fenced ## Profile block is read"
rm -rf "$ROOT"

# --- Cell 3: a partial profile falls back per axis, not wholesale -------------------
ROOT="$(mk_project)"
mkdir -p "$ROOT/.context"
cat > "$ROOT/.context/communication-style.md" <<'EOF'
## Profile

```
tone: SOLO-TONO
unknown_key: ignorado
```
EOF
BODY="$(scaffold "$ROOT" partial-profile)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 3: expected exit 0, got $RC"
grep -q 'SOLO-TONO' "$BODY" || fail "cell 3: the one declared axis was not applied"
grep -q 'first-person singular' "$BODY" \
  || fail "cell 3: an undeclared axis did not fall back to its default"
grep -qF -- "${DEFAULTS[5]}" "$BODY" \
  || fail "cell 3: paste_font did not fall back to the shipped stack byte-exact"
grep -q 'ignorado' "$BODY" && fail "cell 3: a key outside the six axes was rendered"
pass "an axis the profile omits falls back on its own; unknown keys are ignored"
rm -rf "$ROOT"

# --- Cell 3b: declaring only paste_font leaves the other five axes at their defaults ---
ROOT="$(mk_project)"
mkdir -p "$ROOT/.context"
printf '## Profile\n\n```\npaste_font: %s\n```\n' "$OVERRIDE_PASTE_FONT" \
  > "$ROOT/.context/communication-style.md"
BODY="$(scaffold "$ROOT" font-only-profile)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 3b: expected exit 0, got $RC"
grep -qF -- "$OVERRIDE_PASTE_FONT" "$BODY" || fail "cell 3b: the paste_font override was not applied"
for i in 0 1 2 3 4; do
  grep -qF -- "${DEFAULTS[$i]}" "$BODY" \
    || fail "cell 3b: adding paste_font disturbed the default for '${AXES[$i]}'"
done
pass "a paste_font-only profile changes that axis and nothing else"
rm -rf "$ROOT"

# --- Cell 4: a profile with no ## Profile section is documentation, not an error ----
ROOT="$(mk_project)"
mkdir -p "$ROOT/.context"
printf '# Style notes\n\nWe write plainly.\n' > "$ROOT/.context/communication-style.md"
BODY="$(scaffold "$ROOT" prose-only)"; RC=$?
[[ $RC -eq 0 ]] || fail "cell 4: a profile with no parsable section must still exit 0, got $RC"
grep -q 'first-person singular' "$BODY" \
  || fail "cell 4: expected the defaults when nothing parsable is present"
pass "a profile carrying no ## Profile fence degrades to the defaults"
rm -rf "$ROOT"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d cell(s) failed\n' "$FAILURES"
  exit 1
fi
printf '\nOK — communications style profile: 5 cells passed\n'
