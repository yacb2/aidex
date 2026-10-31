#!/usr/bin/env bash
# SKILL.md size-budget guard — both axes, numbers read from the canon.
#
# Regression this locks (BL-078, 2026-07-24):
#   skill-conventions.md § Size Constraints sets the SKILL.md body budget on TWO axes —
#   a soft line/token budget and a hard one. Nothing executable measured
#   either, and the skills-auditor measured lines only. plan-exec/SKILL.md sat at 413
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
# Third axis, rendered size (superpowers-adoptions phase 01, measurement m18): after compaction
# Claude Code re-attaches a skill cut at 20,000 characters of the RENDERED text. Rendered =
# body without front matter, ${CLAUDE_PLUGIN_ROOT} and ${CLAUDE_SKILL_DIR} expanded to a
# realistic absolute install path, plus the "Base directory for this skill: <path>" header.
# Claude Code caps the re-attached text at 20,000 characters INCLUDING a ~100-character
# truncation marker, so about 19,900 characters of the skill are kept. RENDERED_MAX is that
# 19,900: the gate has no slack beyond it. Whether truncation starts at >19,900 or at >20,000
# is undetermined (m18 saw only cuts at exactly 20,000), so 19,900 is the conservative reading.
# Over RENDERED_MAX -> FAIL. A margin line "skill: rendered N, margin M" is printed for every
# skill. Counted in characters, not bytes, by python (locale-independent). Front matter is the
# first line "---" through the first closing "---" (CRLF fences count); a file without front
# matter counts whole; "---" lines inside the body count. The blank line after the closing
# fence is counted (safe direction: it can only over-count by one).
#
# Run with: bash skills/conventions/scripts/test_skill_budget.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS_DIR="$SCRIPT_DIR/../.."
ROOT="$(cd "$SKILLS_DIR/.." && pwd -P)"
CANON="$SCRIPT_DIR/../references/skill-conventions.md"

# The skill list comes from _owned-skills.sh: every <root>/skills/*/ that holds a SKILL.md
# (the plugin checkout is aidex-only, so nothing is filtered).
. "$SCRIPT_DIR/_owned-skills.sh"

# Realistic install path (marketplace cache shape); a checkout path is shorter, so this errs
# on the safe side. The skill dir is <root>/skills/<name>.
RENDER_PLUGIN_ROOT="/Users/example/.claude/plugins/cache/aidex/aidex/1.27.0"
RENDERED_MAX=19900

# skill_body <file> — the file without its front matter (see the header comment).
skill_body() {
  awk '{ l = $0; sub(/\r$/, "", l) }
       NR == 1 { if (l == "---") { fm = 1; next } fm = 0 }
       fm == 1 { if (l == "---") fm = 2; next }
       { print }' "$1"
}

# rendered_text <skill-dir> — what Claude Code attaches for the skill, on stdout.
rendered_text() {
  local dir="$1" name root="$RENDER_PLUGIN_ROOT" body
  name="$(basename "$dir")"
  body="$(skill_body "$dir/SKILL.md")"
  body="${body//'${CLAUDE_PLUGIN_ROOT}'/$root}"
  body="${body//'${CLAUDE_SKILL_DIR}'/$root/skills/$name}"
  printf 'Base directory for this skill: %s\n\n%s\n' "$root/skills/$name" "$body"
}

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$CANON" ]] || { echo "FAIL: canon not found at $CANON"; exit 1; }

# ---------- read the budget from the canon ----------
row_lines="$(grep -E '^\| SKILL\.md body *\|.*lines' "$CANON" | sed -n 1p)"
row_tokens="$(grep -E '^\| SKILL\.md body *\|.*tokens' "$CANON" | sed -n 1p)"
[[ -n "$row_lines" && -n "$row_tokens" ]] \
  || { echo "FAIL: could not find both SKILL.md body rows in $CANON § Size Constraints"; exit 1; }

num() { grep -oE '[0-9]+(\.[0-9]+)?k?' <<<"$1" | sed 's/k/000/' | sed -n 1p; }
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
while IFS= read -r skill_dir; do
  skill="$skill_dir/SKILL.md"
  [[ -f "$skill" ]] || continue
  name="$(basename "$skill_dir")"
  body="$(skill_body "$skill")"
  lines="$(grep -c '' <<<"$body")"
  tokens=$(( $(printf '%s' "$body" | wc -c) / 4 ))
  checked=$((checked + 1))

  rendered="$(rendered_text "$skill_dir" | python3 -I -c 'import sys; print(len(sys.stdin.buffer.read().decode("utf-8", "replace")))')"
  margin=$(( RENDERED_MAX - rendered ))
  printf '%s: rendered %s, margin %s\n' "$name" "$rendered" "$margin"

  status="ok"
  if (( margin < 0 )); then
    fail "$name: rendered $rendered characters, over the $RENDERED_MAX limit — Claude Code cuts the re-attached skill at 20,000 after compaction; move a conditional branch to references/ behind a numbered Read step"
    status="OVER MAX"
  fi
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
done < <(aidex_owned_skill_dirs "$ROOT")

(( checked > 0 )) || { echo "FAIL: no aidex-owned SKILL.md found under $SKILLS_DIR — broken checkout"; exit 1; }

echo
if [[ "$failures" -eq 0 ]]; then
  echo "OK — $checked skills within the maximum on both axes ($over_ideal over the ideal, listed above and not failed)"
  exit 0
fi
exit 1
