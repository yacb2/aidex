#!/usr/bin/env bash
# Single home for the plan-phase `tier` -> model/effort mapping.
#
# The mapping was written out in full in three places (plan-conventions.md
# §Optional phase metadata, aidex-plan-exec's 01-unattended-batch-execution.md
# §Phase tier hint, and a third, effort-free table in 04-model-tiering.md), and
# the gate cell was hardcoded a further six times across the three workflow
# scripts. Nothing tied them together, so a re-sweep of effort levels -- which
# both current model guides say to run per model generation, because effort
# level names do not carry the same amount of thinking across models -- would
# have had to find five files by memory.
#
# Not to be confused with aidex-workflow's stage heuristic
# (`breadth/mechanical -> sonnet`, `adversarial verify -> opus/high`): that maps
# a workflow STAGE, not a plan PHASE. Different axis, deliberately not unified.
#
# Invariants:
#   1. The canon table declares all three tiers plus the gate cell, with a
#      model and an effort for each.
#   2. No other shipped file restates the mapping (all three tier names in one
#      file, outside the canon, is a second copy).
#   3. Every workflow script's gate/verifier and arbiter cell matches the
#      canon's gate row.
#   4. Both consumers point at the canon by name instead of restating it.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CANON="$REPO/skills/aidex-conventions/references/plan-conventions.md"
BATCH="$REPO/skills/aidex-plan-exec/references/01-unattended-batch-execution.md"
TIERING="$REPO/skills/aidex-plan-exec/references/04-model-tiering.md"
WORKFLOWS="$REPO/skills/aidex-plan-exec/assets/workflows"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# Installed, $REPO is ~/.claude, whose skills/ also holds the user's own skills.
# Judging those is BL-115: a FAIL on a clean tree for something this repo does
# not ship. install.sh's manifest is the ownership record; without it (the repo
# copy, where the tree is aidex-only by construction) scan everything.
aidex_owned_md() {
  local manifest="$REPO/aidex/manifest"
  [ -f "$manifest" ] || manifest="$REPO/.manifest"
  if [ -f "$manifest" ]; then
    while IFS= read -r entry; do
      case "$entry" in skills/*/) continue ;; skills/*) ;; *) continue ;; esac
      [ -d "$REPO/$entry" ] || continue
      find "$REPO/$entry" -name '*.md' -not -path '*/evals/*' -not -path '*/tests/*'
    done < "$manifest"
  else
    find "$REPO/skills" -name '*.md' -not -path '*/evals/*' -not -path '*/tests/*'
  fi
}

# ---- 1. the canon table is parseable and complete -------------------------
# Rows look like: | `mechanical` | `sonnet` | `low` | default |
# The table sits indented inside a bullet's continuation, so leading whitespace
# is part of the row. Anchoring on `^|` is what made every row invisible.
row() { grep -E "^[[:space:]]*\|[[:space:]]*\`$1\`[^|]*\|" "$CANON" | head -1; }
cell() { echo "$1" | awk -F'|' -v n="$2" '{gsub(/[ `*]/,"",$n); print $n}'; }

# bash 3.2 on macOS has no associative arrays; four tiers, four pairs of vars.
CANON_PAIRS=""
parsed=0
for tier in mechanical standard hard gate; do
  line="$(row "$tier" || true)"
  if [ -z "$line" ]; then
    err "canon has no mapping row for tier '$tier' ($CANON)"
    continue
  fi
  m="$(cell "$line" 3)"; e="$(cell "$line" 4)"
  if [ -z "$m" ] || [ -z "$e" ]; then
    err "canon row for '$tier' is missing a model or an effort: $line"
    continue
  fi
  case "$e" in low|medium|high|xhigh|max) ;; *) err "canon row '$tier' has effort '$e', not an effort level" ;; esac
  CANON_PAIRS="$CANON_PAIRS$tier=$m/$e "
  parsed=$((parsed + 1))
done
[ "$parsed" -eq 4 ] || err "expected 4 canon rows (3 tiers + gate), parsed $parsed"

canon_cell() { echo "$CANON_PAIRS" | tr ' ' '\n' | sed -n "s|^$1=||p"; }
GATE_CELL="$(canon_cell gate)"
GATE_MODEL="${GATE_CELL%%/*}"; GATE_EFFORT="${GATE_CELL##*/}"

# The table is only a default because the re-sweep note says so. A table that
# loses it reads as settled and stops being re-measured -- which is the whole
# reason the mapping was worth centralising.
grep -qiE "do not transfer across model generations" "$CANON" \
  || err "canon lost the note that the cells do not transfer across model generations"
grep -qiE "re-run an effort sweep" "$CANON" \
  || err "canon lost the instruction to re-run an effort sweep per model generation"
grep -qiE "override a phase's cell at Orient" "$CANON" \
  || err "canon lost the rule that a run may override a cell for cost/quota"

# ---- 2. no second copy of the mapping -------------------------------------
# A file naming all three tier names is claiming the mapping. The canon is the
# only file allowed to.
while IFS= read -r f; do
  [ "$f" = "$CANON" ] && continue
  if grep -q 'mechanical' "$f" && grep -q 'standard' "$f" && grep -q '\bhard\b' "$f"; then
    grep -qE 'mechanical[^|]*(->|→)[^|]*(sonnet|opus|haiku|fable)' "$f" \
      && err "second copy of the tier mapping in ${f#$REPO/} -- point at the canon instead"
  fi
done < <(aidex_owned_md)

# ---- 3. workflow scripts agree with the canon's gate cell -----------------
for wf in "$WORKFLOWS"/*.workflow.js; do
  [ -e "$wf" ] || continue
  while IFS= read -r line; do
    m="$(echo "$line" | sed -nE "s/.*model: '([a-z0-9.-]+)'.*/\1/p")"
    e="$(echo "$line" | sed -nE "s/.*effort: '([a-z]+)'.*/\1/p")"
    [ -z "$e" ] && continue
    if [ -n "$GATE_MODEL" ] && { [ "$m" != "$GATE_MODEL" ] || [ "$e" != "$GATE_EFFORT" ]; }; then
      err "${wf##*/}: gate cell is $m/$e, canon says $GATE_MODEL/$GATE_EFFORT"
    fi
  done < <(grep -nE "label: .(verify|arbiter)" "$wf" | grep "effort: '")
done

# ---- 4. both consumers defer to the canon ---------------------------------
for f in "$BATCH" "$TIERING"; do
  grep -q 'plan-conventions.md' "$f" \
    || err "${f#$REPO/} does not name plan-conventions.md as the mapping's home"
done

if [ "$fail" -eq 0 ]; then
  echo "OK — tier mapping: canon owns 3 tiers + gate cell ($CANON_PAIRS), no second copy, $(ls "$WORKFLOWS"/*.workflow.js 2>/dev/null | wc -l | tr -d ' ') workflow scripts in step, both consumers defer"
fi
exit "$fail"
