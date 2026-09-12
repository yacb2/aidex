#!/usr/bin/env bash
# test_eval_grade_artifact.sh — the grader must DISCRIMINATE, not merely pass.
#
# A grader only ever demonstrated passing is not demonstrated at all: every case
# below pairs a pass with the failure it is supposed to catch. Cleans up its
# fixture.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
GRADE="$DIR/eval-grade-artifact.sh"
TMP="$(mktemp -d -t eval-grade-test)"
trap 'rm -rf "$TMP"' EXIT
fail=0
assert() { if eval "$2"; then echo "  [PASS] $1"; else echo "  [FAIL] $1"; fail=1; fi; }

# rc <expected> <args...> — run the grader, compare exit code.
rc() {
  local want="$1"; shift
  local got=0
  bash "$GRADE" "$@" >/dev/null 2>&1 || got=$?
  [ "$got" -eq "$want" ]
}

echo "test_eval_grade_artifact.sh"

# --- a model-named artifact, reached through a glob -------------------------
mkdir -p "$TMP/communications/meetings/2026-08-06-acme-kickoff"
printf 'title: "Kickoff"\ndirection: meetings\n' \
  > "$TMP/communications/meetings/2026-08-06-acme-kickoff/body.md"

G='communications/meetings/*/body.md'

assert "correct artifact passes (slug never named in the config)" \
  "rc 0 --root '$TMP' --glob '$G' --pattern 'direction: meetings'"

# The discrimination half: same artifact, wrong content.
assert "mis-classified artifact FAILS, exit 1" \
  "rc 1 --root '$TMP' --glob '$G' --pattern 'direction: received'"

# --- an absent artifact must not read as a pass ----------------------------
assert "no match is exit 2, never a silent pass" \
  "rc 2 --root '$TMP' --glob 'communications/sent/*/body.md' --pattern 'anything'"

# --- ambiguity is reported, not guessed ------------------------------------
mkdir -p "$TMP/communications/meetings/2026-08-06-other-call"
printf 'direction: meetings\n' \
  > "$TMP/communications/meetings/2026-08-06-other-call/body.md"

assert "two matches without --newest is exit 2 (ambiguous, not graded)" \
  "rc 2 --root '$TMP' --glob '$G' --pattern 'direction: meetings'"

# --newest resolves it, and still discriminates.
touch "$TMP/communications/meetings/2026-08-06-other-call/body.md"
printf 'direction: received\n' \
  > "$TMP/communications/meetings/2026-08-06-other-call/body.md"
touch "$TMP/communications/meetings/2026-08-06-other-call/body.md"

assert "--newest grades the latest file, and fails on its wrong content" \
  "rc 1 --root '$TMP' --glob '$G' --pattern 'direction: meetings' --newest"
assert "--newest passes when the latest file is correct" \
  "rc 0 --root '$TMP' --glob '$G' --pattern 'direction: received' --newest"

# --- usage errors are their own exit code, never confused with a verdict ----
assert "missing --pattern is exit 3" \
  "rc 3 --root '$TMP' --glob '$G'"
assert "non-directory --root is exit 3" \
  "rc 3 --root '$TMP/nope' --glob '$G' --pattern 'x'"
assert "unknown flag is exit 3" \
  "rc 3 --root '$TMP' --glob '$G' --pattern 'x' --bogus"

echo
[ "$fail" -eq 0 ] && echo "test_eval_grade_artifact.sh: all assertions passed"
exit "$fail"
