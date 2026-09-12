#!/usr/bin/env bash
# test-style-profile.sh — cells for the communications house-style profile (BL-216).
#
# The acceptance's hard requirement is that ABSENCE of a profile resolves to the
# documented default and never to an error — a scaffolder that fails on a workspace
# with no profile is worse than one that ignores style entirely.

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/new-communication.sh"
AXES=(voice sign_off tone address date_format)
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
  grep -q 'first-person singular' "$BODY" \
    || fail "cell 1: the documented voice default did not reach the body"
  grep -q '{{STYLE}}' "$BODY" && fail "cell 1: the placeholder was left unsubstituted"
else
  fail "cell 1: no body.md was produced"
fi
pass "no profile resolves to the five documented defaults, not an error"
rm -rf "$ROOT"

# --- Cell 2: a full profile overrides every axis ------------------------------------
ROOT="$(mk_project)"
mkdir -p "$ROOT/.context"
cat > "$ROOT/.context/communication-style.md" <<'EOF'
# Style

Prose the parser must ignore, including a decoy line: voice: NOT-THIS-ONE

## Profile

```
voice: PRIMERA-PERSONA
sign_off: FIRMA-FIJA
tone: TONO-X
address: TRATAMIENTO-X
date_format: FECHA-X
```

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
grep -q 'NOT-THIS-ONE' "$BODY" \
  && fail "cell 2: a 'voice:' line OUTSIDE the ## Profile fence was parsed as config"
grep -q 'first-person singular — never' "$BODY" \
  && fail "cell 2: a default leaked through even though the profile set that axis"
pass "a full profile overrides all five axes, and only the fenced ## Profile block is read"
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
grep -q 'ignorado' "$BODY" && fail "cell 3: a key outside the five axes was rendered"
pass "an axis the profile omits falls back on its own; unknown keys are ignored"
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
printf '\nOK — communications style profile: 4 cells passed\n'
