#!/usr/bin/env bash
# test-init.sh — smoke tests for skills/aidex/scripts/init-context.sh.
#
# Covers:
#   1. Fresh dir -> full .context/ skeleton created.
#   2. Re-run -> everything reported "exists"; a pre-written canary file in
#      backlog/ is left untouched.
#   3. Partial pre-existing .context/ (only plans/) -> fills the gaps only.
#   4. Suite not installed (AIDEX_DIR pointed at an empty temp dir) -> still
#      scaffolds the directories, notes the skipped seeding, exits 0.
#   5. The suggested CLAUDE.md block is printed to stdout but no CLAUDE.md
#      file is ever created.
#
# Run with: bash skills/aidex/tests/test-init.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INIT="$SCRIPT_DIR/../scripts/init-context.sh"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

# --- Scenario 1: fresh dir -> full skeleton created ---

d1="$(mktemp -d)"
out1="$(bash "$INIT" "$d1")"

for sub in backlog plans decisions research references requests \
           backlog/_archive plans/_archive requests/_archive; do
  if [[ -d "$d1/.context/$sub" ]]; then
    pass "scenario1: .context/$sub created"
  else
    fail "scenario1: .context/$sub missing"
  fi
done

created_count="$(printf '%s\n' "$out1" | grep -c '^created: \.context/')"
[[ "$created_count" -ge 9 ]] || fail "scenario1: expected >=9 created: lines, got $created_count"

# --- Scenario 2: re-run -> all exists, canary untouched ---

canary="$d1/.context/backlog/canary.md"
printf 'do not touch\n' > "$canary"

out2="$(bash "$INIT" "$d1")"
exists_count="$(printf '%s\n' "$out2" | grep -c '^exists: \.context/')"
[[ "$exists_count" -ge 9 ]] || fail "scenario2: expected >=9 exists: lines on re-run, got $exists_count"

if printf '%s\n' "$out2" | grep -q '^created: \.context/backlog$'; then
  fail "scenario2: backlog/ reported created on re-run"
else
  pass "scenario2: backlog/ reported exists on re-run"
fi

if [[ "$(cat "$canary")" == "do not touch" ]]; then
  pass "scenario2: canary file untouched"
else
  fail "scenario2: canary file was modified"
fi

rm -rf "$d1"

# --- Scenario 3: partial pre-existing .context/ (only plans/) -> fills gaps only ---

d3="$(mktemp -d)"
mkdir -p "$d3/.context/plans"
printf 'pre-existing\n' > "$d3/.context/plans/canary.md"

out3="$(bash "$INIT" "$d3")"

if printf '%s\n' "$out3" | grep -q '^exists: \.context/plans$'; then
  pass "scenario3: pre-existing plans/ reported exists"
else
  fail "scenario3: pre-existing plans/ not reported exists"
fi

for sub in backlog decisions research references requests \
           backlog/_archive plans/_archive requests/_archive; do
  if [[ -d "$d3/.context/$sub" ]]; then
    pass "scenario3: gap $sub filled"
  else
    fail "scenario3: gap $sub not filled"
  fi
done

if [[ "$(cat "$d3/.context/plans/canary.md")" == "pre-existing" ]]; then
  pass "scenario3: plans/ pre-existing content untouched"
else
  fail "scenario3: plans/ pre-existing content was modified"
fi

rm -rf "$d3"

# --- Scenario 4: suite not installed (AIDEX_DIR -> empty temp dir) ---

d4="$(mktemp -d)"
empty_aidex="$(mktemp -d)"

out4="$(AIDEX_DIR="$empty_aidex" bash "$INIT" "$d4")"
rc4=$?

[[ $rc4 -eq 0 ]] || fail "scenario4: exit code expected 0, got $rc4"

for sub in backlog plans decisions research references requests \
           backlog/_archive plans/_archive requests/_archive; do
  [[ -d "$d4/.context/$sub" ]] || fail "scenario4: .context/$sub not scaffolded without suite"
done

if printf '%s\n' "$out4" | grep -qi 'not installed'; then
  pass "scenario4: notes the skipped seeding"
else
  fail "scenario4: no note about skipped seeding"
fi

rm -rf "$d4" "$empty_aidex"

# --- Scenario 5: CLAUDE.md block printed, no file created ---

d5="$(mktemp -d)"
out5="$(bash "$INIT" "$d5")"

if printf '%s\n' "$out5" | grep -qi 'Suggested CLAUDE.md addition'; then
  pass "scenario5: CLAUDE.md suggestion block printed"
else
  fail "scenario5: CLAUDE.md suggestion block missing from output"
fi

if [[ -f "$d5/CLAUDE.md" ]]; then
  fail "scenario5: CLAUDE.md file was created"
else
  pass "scenario5: no CLAUDE.md file created"
fi

rm -rf "$d5"

# --- Scenario 6: _tmp/ scratch bucket seeded, README never overwritten (BL-028) ---

d6="$(mktemp -d)"
bash "$INIT" "$d6" >/dev/null

if [[ -f "$d6/_tmp/README.md" ]]; then
  pass "scenario6: _tmp/README.md seeded"
else
  fail "scenario6: _tmp/README.md not created"
fi

if grep -q 'deleted at any time without asking' "$d6/_tmp/README.md"; then
  pass "scenario6: README carries the disposable contract"
else
  fail "scenario6: README missing the disposable contract"
fi

printf 'project-specific contract\n' > "$d6/_tmp/README.md"
out6="$(bash "$INIT" "$d6")"

if [[ "$(cat "$d6/_tmp/README.md")" == "project-specific contract" ]]; then
  pass "scenario6: existing _tmp/README.md left untouched"
else
  fail "scenario6: existing _tmp/README.md was overwritten"
fi

if printf '%s\n' "$out6" | grep -q '^exists: _tmp/README.md$'; then
  pass "scenario6: re-run reports the README as existing"
else
  fail "scenario6: re-run did not report _tmp/README.md as existing"
fi

rm -rf "$d6"

# --- Summary ---

if [[ $failures -eq 0 ]]; then
  printf 'All init-context.sh tests passed.\n'
  exit 0
else
  printf '%d test(s) failed.\n' "$failures"
  exit 1
fi
