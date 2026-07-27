#!/usr/bin/env bash
# allowed-tools lockstep guard for aidex-dash.
#
# Regression this locks (BL-080, 2026-07-24):
#   SKILL.md declared `allowed-tools: Bash Read Glob Grep` — no Write, no Skill — while the
#   ad-hoc branch added in 61df678 instructs the agent to load the `artifact-design` skill
#   and write the sibling HTML. Board renders survived because render.sh writes via Bash,
#   which hid the gap: the only path that needed the undeclared capabilities was the one
#   nobody exercised in the test suite.
#
# Invariant: every capability the BODY mandates must appear in the declared allowed-tools.
# The check is body-driven, not a frozen expected list — a future branch that adds an Edit
# or a WebFetch instruction fails here rather than at the user's first permission denial.
#
# Run with: bash skills/aidex-dash/tests/test-allowed-tools-lockstep.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$SCRIPT_DIR/../SKILL.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$SKILL" ]] || { echo "FAIL: SKILL.md not found at $SKILL"; exit 1; }

DECLARED="$(grep -m1 '^allowed-tools:' "$SKILL" | sed 's/^allowed-tools: *//')"
[[ -n "$DECLARED" ]] || { echo "FAIL: SKILL.md declares no allowed-tools line"; exit 1; }

# Body = everything after the front-matter, so the declaration cannot satisfy itself.
BODY="$(awk 'NR>1 && /^---$/{f=1;next} f' "$SKILL")"
[[ -n "$BODY" ]] || { echo "FAIL: could not split SKILL.md body from its front-matter"; exit 1; }

# Flattened to one line: markdown wraps mid-sentence, and a line-based grep silently misses
# any instruction that straddles a newline — which is exactly how the Skill mandate hid.
BODY="$(tr '\n' ' ' <<<"$BODY" | tr -s ' ')"

declares() { grep -qwF "$1" <<<"$DECLARED"; }

# phrase-in-body -> capability the agent cannot perform without
check() {  # <regex> <tool> <why>
  grep -qiE "$1" <<<"$BODY" || return 0
  declares "$2" || fail "the body instructs $3, which needs '$2', but allowed-tools declares only: $DECLARED"
}

check 'load the .?artifact-design.? skill|invoke the .?[a-z-]+.? skill'  Skill 'invoking another skill'
check 'write the sibling HTML|write the .?\.html|hand-generate'          Write 'writing an HTML file directly'
check 'render\.sh|shell out|run the'                                     Bash  'running a script'

# ---------- the declared set must not drift into the opposite failure ----------
# Over-declaring is its own defect: allowed-tools is the skill's stated blast radius, and a
# tool nobody's instruction needs widens it for free.
for t in $DECLARED; do
  case "$t" in
    Bash|Read|Glob|Grep) continue ;;   # baseline read/render surface
    Skill) grep -qiE 'skill' <<<"$BODY" || fail "allowed-tools declares 'Skill' but the body never instructs invoking one" ;;
    Write) grep -qiE 'write|generate|hand-roll' <<<"$BODY" || fail "allowed-tools declares 'Write' but the body never instructs writing a file" ;;
    *) fail "allowed-tools declares '$t', which no instruction in the body accounts for — narrow it or justify it in the body" ;;
  esac
done

if [[ "$failures" -eq 0 ]]; then
  echo "OK — aidex-dash allowed-tools in lockstep with its body: $DECLARED"
  exit 0
fi
exit 1
