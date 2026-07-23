#!/usr/bin/env bash
# test-autonomy-protocol.sh — asserts the "Default autonomy" kickoff block
# lands identically (single-sourced pointer, not forked content) in the three
# executing skills, plus plan-exec's workspace-root durability marker,
# completion notification, and structural review gate.
#
# Regression: retro run 4 observed ~17 "no te detengas" prompts per window
# because the executing skills waited for the user to grant autonomy instead
# of applying it by default (.context/audits/2026-06-21-usage-retro/, Run 4).
# Fixture-free grep assertions — the deliverable is doc text, not behavior a
# fixture can exercise.
#
# Run with: bash tests/test-autonomy-protocol.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PLAN_EXEC="$REPO_ROOT/skills/aidex-plan-exec/SKILL.md"
LOOP="$REPO_ROOT/skills/aidex-loop/SKILL.md"
AUDIT="$REPO_ROOT/skills/aidex-audit/SKILL.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

for f in "$PLAN_EXEC" "$LOOP" "$AUDIT"; do
  [[ -f "$f" ]] || { fail "missing file: $f"; continue; }
done

# ---------- (a) each executor carries the "Default autonomy" heading ----------
for f in "$PLAN_EXEC" "$LOOP" "$AUDIT"; do
  grep -q '^## Default autonomy' "$f" || fail "(a) $f: missing '## Default autonomy' heading"
done

# ---------- (b) each block single-sources the autonomy canon (cites, doesn't fork) ----------
for f in "$PLAN_EXEC" "$LOOP" "$AUDIT"; do
  grep -q 'aidex-conventions/references/autonomy-conventions.md' "$f" \
    || fail "(b) $f: does not point to autonomy-conventions.md"
done

# ---------- (c) each block states autonomy applies automatically, not on request ----------
for f in "$PLAN_EXEC" "$LOOP" "$AUDIT"; do
  grep -q 'do not wait for the user to grant it' "$f" \
    || fail "(c) $f: Default autonomy block does not state auto-apply"
done

# ---------- (d) each block stays <=6 lines ----------
for f in "$PLAN_EXEC" "$LOOP" "$AUDIT"; do
  block="$(awk '/^## Default autonomy/{flag=1; next} /^---$/{if(flag) exit} /^## /{if(flag) exit} flag' "$f")"
  nonblank_lines="$(printf '%s\n' "$block" | grep -c '[^[:space:]]')"
  [[ "$nonblank_lines" -le 6 ]] || fail "(d) $f: Default autonomy block is $nonblank_lines lines, expected <=6"
done

# ---------- (e) plan-exec's durability marker runs from the workspace root ----------
grep -q 'workspace root' "$PLAN_EXEC" || fail "(e) plan-exec: no workspace-root instruction found"
grep -q 'durability-run.sh" start plan-exec' "$PLAN_EXEC" \
  || fail "(e) plan-exec: durability-run.sh start plan-exec invocation missing"

# ---------- (f) plan-exec fires the completion notifier, guarded on existence+executable ----------
grep -q 'notify.sh' "$PLAN_EXEC" || fail "(f) plan-exec: no notify.sh reference"
grep -q 'exists and is executable' "$PLAN_EXEC" \
  || fail "(f) plan-exec: notify.sh call is not guarded on existence+executability"

# ---------- (g) plan-exec's between-phase checkpoint writes review evidence before commit ----------
grep -q 'review: <verdict>' "$PLAN_EXEC" \
  || fail "(g) plan-exec: no 'review: <verdict> · <n> findings' Execution-log pattern"
grep -q 'before' "$PLAN_EXEC" && grep -B2 'review: <verdict>' "$PLAN_EXEC" | grep -qi 'commit' \
  || fail "(g) plan-exec: review evidence not tied to landing before the commit step"

# ---------- (h) plan-exec's Orient step checks the prior phase's review entry ----------
grep -q "prior phase's review evidence" "$PLAN_EXEC" \
  || fail "(h) plan-exec: Orient step does not check the prior phase's review evidence"
grep -q 'missing' "$PLAN_EXEC" \
  || fail "(h) plan-exec: no handling for a missing review entry"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — Default autonomy block is single-sourced across plan-exec/loop/audit; plan-exec carries the workspace-root marker, completion notify, and review gate"
