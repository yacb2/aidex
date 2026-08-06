#!/usr/bin/env bash
# SKILL.md size-budget guard — both axes, numbers read from the canon.
#
# Regression this locks (BL-078, 2026-07-24):
#   skill-conventions.md § Size Constraints sets the SKILL.md body budget on TWO axes —
#   a soft line/token budget and a hard one. Nothing executable measured
#   either, and the skills-auditor measured lines only. aidex-plan-exec/SKILL.md sat at 413
#   lines and ~7.4k tokens: under the 500-line ceiling, so a line-only check passed it,
#   while it was ~48% over the token ceiling. The token axis was unenforceable by
#   construction — that is what this file changes.
#
# Enforcement model, stated so nobody reads more into a pass than it means:
#   - over MAXIMUM on either axis  -> FAIL. That is the ceiling, and it is enforced.
#   - over IDEAL on either axis    -> reported, not failed. Several skills sit between the
#     two today; failing them here would either block the repo or invite the numbers to be
#     quietly raised to match reality, which is the ratchet-destroying move this suite has
#     been bitten by before. They are printed every run so the debt stays visible.
#
# The four numbers are parsed from skill-conventions.md, not restated. Edit the canon and
# this test follows; there is no second copy to drift.
#
# Token estimate is bytes/4 — the same crude-but-stable rule the skills-auditor is told to
# use, so the two agree by construction rather than by coincidence.
#
# Run with: bash skills/aidex-conventions/scripts/test_skill_budget.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_DIR="$SCRIPT_DIR/../.."
CANON="$SCRIPT_DIR/../references/skill-conventions.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$CANON" ]] || { echo "FAIL: canon not found at $CANON"; exit 1; }

# ---------- read the budget from the canon ----------
row_lines="$(grep -E '^\| SKILL\.md body *\|.*lines' "$CANON" | head -1)"
row_tokens="$(grep -E '^\| SKILL\.md body *\|.*tokens' "$CANON" | head -1)"
[[ -n "$row_lines" && -n "$row_tokens" ]] \
  || { echo "FAIL: could not find both SKILL.md body rows in $CANON § Size Constraints"; exit 1; }

num() { grep -oE '[0-9]+(\.[0-9]+)?k?' <<<"$1" | sed 's/k/000/' | head -1; }
IDEAL_LINES="$(num "$(cut -d'|' -f3 <<<"$row_lines")")"
MAX_LINES="$(num "$(cut -d'|' -f4 <<<"$row_lines")")"
IDEAL_TOKENS="$(num "$(cut -d'|' -f3 <<<"$row_tokens")")"
MAX_TOKENS="$(num "$(cut -d'|' -f4 <<<"$row_tokens")")"
for v in "$IDEAL_LINES" "$MAX_LINES" "$IDEAL_TOKENS" "$MAX_TOKENS"; do
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "FAIL: could not parse the budget numbers from the canon"; exit 1; }
done

# A canon whose ideal exceeds its maximum would make every check vacuous.
(( IDEAL_LINES < MAX_LINES && IDEAL_TOKENS < MAX_TOKENS )) \
  || fail "the canon's ideal exceeds its maximum — the budget cannot be enforced as written"

printf 'budget from canon: lines %s ideal / %s max · tokens %s ideal / %s max\n\n' \
  "$IDEAL_LINES" "$MAX_LINES" "$IDEAL_TOKENS" "$MAX_TOKENS"

# ---------- measure every shipped skill ----------
over_ideal=0
checked=0
for skill in "$SKILLS_DIR"/*/SKILL.md; do
  [[ -f "$skill" ]] || continue
  name="$(basename "$(dirname "$skill")")"
  body="$(awk 'NR>1 && /^---$/{f=1;next} f' "$skill")"
  lines="$(grep -c '' <<<"$body")"
  tokens=$(( $(printf '%s' "$body" | wc -c) / 4 ))
  checked=$((checked + 1))

  status="ok"
  if (( lines > MAX_LINES )); then
    fail "$name: body is $lines lines, over the $MAX_LINES-line maximum — split to references/"
    status="OVER MAX"
  fi
  if (( tokens > MAX_TOKENS )); then
    fail "$name: body is ~$tokens tokens, over the $MAX_TOKENS-token maximum — split to references/ (a line count alone would not have caught this)"
    status="OVER MAX"
  fi
  if [[ "$status" == "ok" ]] && (( lines > IDEAL_LINES || tokens > IDEAL_TOKENS )); then
    status="over ideal"
    over_ideal=$((over_ideal + 1))
  fi
  [[ "$status" == "ok" ]] || printf '  %-22s %4s lines  ~%5s tokens  [%s]\n' "$name" "$lines" "$tokens" "$status"
done

(( checked > 0 )) || { echo "FAIL: no SKILL.md files found under $SKILLS_DIR"; exit 1; }

echo
if [[ "$failures" -eq 0 ]]; then
  echo "OK — $checked skills within the maximum on both axes ($over_ideal over the ideal, listed above and not failed)"
  exit 0
fi
exit 1
