#!/usr/bin/env bash
# test-references-pinned.sh — content moved out of SKILL.md keeps an owner and a pointer.
#
# A split that loses its pointer, or a pointer in the "See ..." shape, is read 0% of the
# time (BL-125); a reference that loses a phase drifts silently. Each cell pins one side.
set -u

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SKILL="$SKILL_DIR/SKILL.md"
REF="$SKILL_DIR/references/03-skeleton-first.md"
HARNESS="$SKILL_DIR/references/01-harness-contract.md"
FAILURES=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# 1. SKILL.md points at the skeleton reference as an imperative Read with the full path.
grep -A1 'Read$' "$SKILL" | grep -qF '`${CLAUDE_PLUGIN_ROOT}/skills/ui-contract/references/03-skeleton-first.md`' \
  || fail "SKILL.md lacks the imperative Read pointer to references/03-skeleton-first.md"

# 2. The reference owns all five phases, in order.
prev=0
for phase in "1. **Skeleton of the real page**" "2. **Review of the skeleton**" \
             "3. **Shared primitives**" "4. **Gallery and gate**" "5. **Wire**"; do
  n="$(grep -nF "$phase" "$REF" | head -1 | cut -d: -f1)"
  if [ -z "$n" ]; then fail "03-skeleton-first.md lacks phase: $phase"; continue; fi
  [ "$n" -gt "$prev" ] || fail "phase out of order: $phase"
  prev="$n"
done

# 3. The rules that moved with the phases are still stated; the round shape stays inline
#    because it is sketch-trial text.
grep -qF 'Geometry assertions go in before the first owner round' "$REF" || fail "geometry-assertion rule lost"
# The documented pending-owner line, filled in, is read by the gate that owns the grammar.
LINE="$(python3 -c "
import re, sys
t = ' '.join(open(sys.argv[1], encoding='utf-8').read().split())
m = re.search(r'\`(ui-surface: [^\`]*pending-owner[^\`]*)\`', t)
print(m.group(1).replace('<N>', '3').replace('<its page>', 'consult.html').replace('...', 'empty') if m else '')
" "$REF")"
PLAN="$(mktemp)"; printf '## UI contract\n\n## Execution log\n\n- %s\n' "$LINE" > "$PLAN"
bash "$SKILL_DIR/../plan-exec/scripts/check-ui-evidence.sh" --pending "$PLAN" 2>&1 | grep -qxF 'pending-owner: phase 3 · consult.html · cells: empty' \
  || fail "the pending-owner line documented in 03-skeleton-first.md is not read by check-ui-evidence.sh --pending: '$LINE'"
rm -f "$PLAN"
grep -qF 'a budget of 2 rounds' "$SKILL" || fail "skeleton round budget left SKILL.md"

# 4. The light/dark-only rule moved to the harness contract; SKILL.md points there.
grep -qF 'Light and dark are the only two modes this contract renders' "$HARNESS" || fail "light/dark rule missing from harness contract"
grep -qF 'harness contract § 3' "$SKILL" || fail "SKILL.md lost its pointer to harness contract § 3"

if [ "$FAILURES" -eq 0 ]; then echo "PASS: ui-contract references pinned"; exit 0; fi
echo "FAIL: $FAILURES cell(s)"; exit 1
