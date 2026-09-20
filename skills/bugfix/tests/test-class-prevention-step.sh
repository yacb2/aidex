#!/usr/bin/env bash
# test-class-prevention-step.sh — the bugfix step that asks what prevents the CLASS (BL-436).
#
# The regression test guarantees the instance; nothing else in the skill asks about the
# kind. The step is a question, never a hook — durability-stop-hook (4 blocks, 0
# justified) is the precedent against enforcing a judgement call — so what is guarded
# here is only that the question exists, sits where a reader meets it (after the commit,
# before guided human verification) and keeps "nothing, one-off" as a writable answer.
# Drop that last cell and the step silently becomes a gate: the only way to satisfy it
# would be to invent a rule for every one-off bug.
#
# Run with: bash skills/bugfix/tests/test-class-prevention-step.sh

set -uo pipefail

SKILL="${SKILL_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/SKILL.md}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

[ -f "$SKILL" ] || { printf 'FAIL: missing file: %s\n' "$SKILL" >&2; exit 1; }

FLAT="$(tr '\n' ' ' < "$SKILL" | tr -s ' ')"

# ---------- the step exists ----------
case "$FLAT" in
  *"prevents the class"*) ;;
  *) err "SKILL.md does not ask what prevents the CLASS of bug — the regression test only covers the instance" ;;
esac

# ---------- it sits between the commit step and guided human verification ----------
line_of() { grep -n -m1 -F "$1" "$SKILL" | cut -d: -f1; }
commit_line=$(line_of "Commit test + fix together")
class_line=$(grep -n -m1 -iE '^[0-9]+\. .*prevents the class' "$SKILL" | cut -d: -f1)
human_line=$(line_of "Guided human verification")

if [ -z "$commit_line" ] || [ -z "$class_line" ] || [ -z "$human_line" ]; then
  err "step list is not in the expected shape (commit=${commit_line:-none} class=${class_line:-none} human=${human_line:-none})"
else
  [ "$commit_line" -lt "$class_line" ] || err "the class-prevention step is not after the commit step"
  [ "$class_line" -lt "$human_line" ] || err "the class-prevention step is not before guided human verification"
fi

# ---------- "nothing, one-off" is an accepted, written answer ----------
case "$FLAT" in
  *"one-off"*) ;;
  *) err "the step does not accept 'nothing, this was a one-off' — without it the question reads as a demand for a rule per bug" ;;
esac
case "$FLAT" in
  *"one-off"*"valid answer"*|*"valid answer"*"one-off"*) ;;
  *) err "the one-off answer is not stated to be valid" ;;
esac
case "$FLAT" in
  *"commit body"*) ;;
  *) err "the step names no place to write the answer down — an unrecorded answer is the same as no answer" ;;
esac

# ---------- it is a question, not a gate ----------
case "$FLAT" in
  *"never blocks the commit"*|*"not a gate"*) ;;
  *) err "the step does not say it never blocks the commit — a question that reads as a gate becomes one" ;;
esac

[ "$fail" -eq 0 ] && echo "OK — bugfix asks what prevents the class, after the commit, with the one-off answer recorded"
exit "$fail"
