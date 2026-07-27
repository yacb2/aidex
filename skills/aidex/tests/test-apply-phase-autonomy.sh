#!/usr/bin/env bash
# Autonomy-protocol guard for /aidex's apply phase.
#
# Regression this locks (BL-077, 2026-07-24):
#   `skills/aidex/SKILL.md` ended its synthesis with a front-loaded menu
#   ([A] apply all critical / [B] apply all / [C] pick individually / [D] report only) and
#   then, having been authorized, asked `apply? [y/n/skip]` again for every single change.
#   `rules/autonomy.md` classifies small reversible additive patches as class 4 —
#   proceed and document — and names per-item menus at execution time as *the* leak
#   surface. Two aidex-owned surfaces prescribed opposite behavior for the same moment,
#   and a second section of the same file listed "trim duplicated content" as destructive
#   while the apply phase treated the same edit as routine.
#
# Invariants:
#   (1) the apply phase does not re-gate what the menu already authorized;
#   (2) every patch kind it can perform is classified against autonomy's classes, so
#       "which class is this?" is answered in the file rather than left to the agent;
#   (3) the genuinely non-reversible kinds stay gated — this fix must not read as
#       "autonomy means stop asking about everything";
#   (4) the two sections of SKILL.md that talk about destructive actions agree.
#
# Run with: bash skills/aidex/tests/test-apply-phase-autonomy.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$SCRIPT_DIR/../SKILL.md"
RULE="$SCRIPT_DIR/../../../rules/autonomy.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

for f in "$SKILL" "$RULE"; do
  [[ -f "$f" ]] || { echo "FAIL: expected file not found at $f"; exit 1; }
done

# The apply phase only. Flattened: markdown wraps mid-sentence and a line-based grep
# silently misses instructions that straddle a newline.
APPLY="$(awk '/^### Apply phase/{f=1;next} /^---$/{f=0} f' "$SKILL" | tr '\n' ' ' | tr -s ' ')"
[[ -n "$APPLY" ]] || { echo "FAIL: could not extract the Apply phase section from SKILL.md"; exit 1; }

# ---------- (1) the front-loaded gate is not re-asked ----------
if grep -qiE 'Always confirm per item\. No batch apply without prompts' <<<"$APPLY"; then
  fail "(1) the apply phase still mandates a per-item prompt for every change, which is the execution-time leak rules/autonomy.md names"
fi
grep -qiE 'front-loaded gate' <<<"$APPLY" \
  || fail "(1) the apply phase never states that the [A]/[B]/[C]/[D] menu is the gate — without that, 'ask once' has no anchor and drifts back to per-item"

# ---------- (2) every patch kind is classified ----------
# Derived from the patch table itself: each row must name a class. A row with no class is
# the ambiguity this item was filed for.
APPLY_RAW="$(awk '/^### Apply phase/{f=1;next} /^---$/{f=0} f' "$SKILL")"
rows="$(grep -E '^\s*\|' <<<"$APPLY_RAW" | grep -vE '^\s*\|[ -]*\|[ -]*\|' | grep -viE '\| *Patch *\|')"
[[ -n "$rows" ]] || fail "(2) no apply-phase patch table found — the classification is not expressed anywhere checkable"
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  grep -qE '\| *[14] +—' <<<"$row" \
    || fail "(2) an apply-phase patch row names no autonomy class: ${row:0:80}"
done <<<"$rows"

# ---------- (3) the non-reversible kinds stay gated ----------
for needle in 'Plugin uninstall' 'deletes'; do
  row="$(grep -iE "$needle" <<<"$rows" | head -1)"
  if [[ -z "$row" ]]; then
    fail "(3) no apply-phase row mentions '$needle' any more — the non-reversible kinds must stay listed"
  elif ! grep -qiE '\| *1 +—' <<<"$row" || ! grep -qiE '[Ss]till gated' <<<"$row"; then
    fail "(3) '$needle' is no longer class 1 + still gated per item — this fix must narrow the prompting, not remove it"
  fi
done

# ---------- (3b) the safety precondition survives ----------
grep -qiE 'backup .*(is what makes|failed or was skipped)' <<<"$APPLY" \
  || fail "(3b) nothing ties unprompted class-4 application to the backup having succeeded — without the backup, none of it is reversible"

# ---------- (4) the two destructive-action sections agree ----------
DEST="$(awk '/^\*\*Destructive actions/{f=1} f && /^After execution/{f=0} f' "$SKILL" | tr '\n' ' ')"
[[ -n "$DEST" ]] || fail "(4) could not find the 'Destructive actions' list"
if grep -qiE '^- Trim duplicated content' <<<"$(awk '/^\*\*Destructive actions/{f=1} f && /^After execution/{f=0} f' "$SKILL")"; then
  fail "(4) 'Trim duplicated content' is listed as destructive while the apply phase treats the same edit as class 4 — the two sections disagree again"
fi

# ---------- (5) the classes cited actually exist in the rule ----------
for c in 1 4; do
  grep -qE "^${c}\. \*\*" "$RULE" \
    || fail "(5) SKILL.md classifies patches as class $c, but rules/autonomy.md defines no such numbered class"
done

if [[ "$failures" -eq 0 ]]; then
  echo "OK — apply phase in lockstep with rules/autonomy.md: menu is the gate, every patch classified, class-1 kinds still gated"
  exit 0
fi
exit 1
