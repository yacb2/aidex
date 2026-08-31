#!/usr/bin/env bash
# test-memory-surface.sh — the memory half of the aidex skill describes memory correctly.
#
# Four defects shipped together and all of them made the memory audit either never fire
# or fire on the wrong thing: SKILL.md put MEMORY.md under `.claude/` or the project root
# (it lives at ~/.claude/projects/<slug>/memory/MEMORY.md), and three thresholds were
# expressed in LINES when the budget the checker enforces is WORDS.
#
# This test asserts the ABSENCE of the defect, so it stays meaningful after the fix. It
# reads the numbers out of memory-sweep.py rather than restating them — a second copy of
# 800/1200 in a test is the lockstep drift the suite already gets bitten by.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SKILL="$REPO_ROOT/skills/aidex"
SWEEP="$SKILL/scripts/memory-sweep.py"
SURFACE=("$SKILL/SKILL.md" "$SKILL/references/03-memory-workflow.md" "$SKILL/agents/memory-auditor.md")

PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

echo "== the surface files exist =="
for f in "${SURFACE[@]}"; do
  check "$(basename "$(dirname "$f")")/$(basename "$f") is present" "[[ -f '$f' ]]"
done

echo "== no threshold in the memory surface is expressed in lines =="
# `N lines` is legitimate when it measures the PROSE LENGTH of one entry ("more than two
# lines of inline content"). It is the defect when it measures the index or a memory —
# those are word budgets. Allowlisted prose-length phrasings are stripped before the scan,
# so a new one has to be added here deliberately instead of sneaking past a loose regex.
LINE_HITS="$(
  for f in "${SURFACE[@]}"; do
    grep -nE '[0-9]+ *lines' "$f" 2>/dev/null | sed "s|^|$(basename "$f"):|"
  done | sed -E 's/>?2 lines of inline content//g; s/>3 lines//g; s/\(<3 lines\)//g; s/3 lines of substantive prose//g' \
       | grep -E '[0-9]+ *lines'
)"
check "no line-unit threshold survives (found: ${LINE_HITS:-none})" '[[ -z "$LINE_HITS" ]]'

echo "== MEMORY.md is never located under .claude/ or the project root =="
# The correct path CONTAINS `.claude/`, so proximity alone cannot be the test: assert the
# positive instead — any line that places MEMORY.md inside a `.claude` path must say
# `projects/`, which is the segment the wrong locations lack.
LOC_HITS="$(
  for f in "${SURFACE[@]}"; do
    # The front-matter `description:` is trigger prose, not a location claim: it names
    # MEMORY.md and .claude/skills in one sentence and always will.
    grep -n 'MEMORY\.md' "$f" | grep -v '^[0-9]*:description:' \
      | grep '\.claude/' | grep -v 'projects/' | sed "s|^|$(basename "$f"):|"
  done
)"
check "no MEMORY.md location omits projects/ (found: ${LOC_HITS:-none})" '[[ -z "$LOC_HITS" ]]'
check "SKILL.md states the real path at least once" \
  'grep -q "~/.claude/projects/<slug>/memory/MEMORY.md" "$SKILL/SKILL.md"'

echo "== the memory-auditor launch gate resolves a real path =="
GATE="$(grep -n 'memory-auditor' "$SKILL/SKILL.md" | grep '| sonnet |')"
check "the gate row exists" '[[ -n "$GATE" ]]'
check "it gates on the memory directory, not a line count" \
  '[[ "$GATE" == *"memory/"* && "$GATE" != *"lines"* ]]'

echo "== budgets stay in lockstep with memory-sweep.py =="
SCRIPT_MEM="$(sed -n 's/^MEMORY_WORD_BUDGET = \([0-9]*\)$/\1/p' "$SWEEP")"
SCRIPT_IDX="$(sed -n 's/^INDEX_WORD_BUDGET = \([0-9]*\)$/\1/p' "$SWEEP")"
check "memory-sweep.py still defines both budgets" '[[ -n "$SCRIPT_MEM" && -n "$SCRIPT_IDX" ]]'
WF="$SKILL/references/03-memory-workflow.md"
check "03-memory-workflow.md states the memory budget ($SCRIPT_MEM words)" \
  'grep -qE "$SCRIPT_MEM ?w(ords)?" "$WF"'
check "03-memory-workflow.md states the index budget ($SCRIPT_IDX words)" \
  'grep -qE "(1,200|$SCRIPT_IDX) ?w(ords)?" "$WF"'
check "and names the sweep so the reader can run it" 'grep -q "memory-sweep.py" "$WF"'

echo
echo "memory-surface: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
