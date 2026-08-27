#!/usr/bin/env bash
# test_worklist_lifecycle.sh — new → advance ×N → append → close, asserting state
# and that the file validates throughout. Cleans up its fixture.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fail=0
assert() { if eval "$2"; then echo "  [PASS] $1"; else echo "  [FAIL] $1"; fail=1; fi; }

slug="lifecycle-test-$$"
file="$(bash "$DIR/worklist-new.sh" --title "Lifecycle test $$" --slug "$slug" \
  --ref "backlog:BL-1 — do a" --ref "plan:p-2 — do b" --ref "inline:do c" --publish ask)"
cleanup() { rm -f "$file" "$ROOT/.context/worklists/_archive/$(basename "$file")"; }
trap cleanup EXIT

assert "new: file created"              "[[ -f '$file' ]]"
assert "new: validates clean"           "python3 '$DIR/validate-worklist.py' '$file' >/dev/null"
assert "new: 3 queue items, all open"   "[[ \$(grep -cE '^[0-9]+\. \[ \] ' '$file') -eq 3 ]]"

n1="$(bash "$DIR/worklist-advance.sh" "$file")"
assert "advance#1: head 1 now done"     "[[ \$(grep -cE '^1\. \[x\] ' '$file') -eq 1 ]]"
assert "advance#1: next is item 2"      "[[ '$n1' == 2.* ]]"

n2="$(bash "$DIR/worklist-advance.sh" "$file")"
assert "advance#2: next is item 3"      "[[ '$n2' == 3.* ]]"

bash "$DIR/worklist-advance.sh" "$file" --append "inline:emergent d" >/dev/null
assert "append: emergent in deferred"   "grep -q 'emergent d' '$file'"
assert "append: still validates"        "python3 '$DIR/validate-worklist.py' '$file' >/dev/null"

n3="$(bash "$DIR/worklist-advance.sh" "$file")"
assert "advance#3: queue DONE"          "[[ '$n3' == 'DONE' ]]"

out="$(bash "$DIR/worklist-close.sh" "$file" 2>/dev/null)"
assert "close: prints CLOSED"           "[[ '$out' == CLOSED* ]]"
archived="${out#CLOSED }"
assert "close: archived to _archive/"   "[[ '$archived' == */worklists/_archive/* && -f '$archived' && ! -f '$file' ]]"
assert "close: status done"             "grep -q '^status: done' '$archived'"
assert "close: validates clean"         "python3 '$DIR/validate-worklist.py' '$archived' >/dev/null"

echo "== regressions (suite analysis 2026-07-02) =="
# close must survive a queue with only inline refs: the grep|wc ref-count pipeline
# failed under set -euo pipefail (grep exit 1 on no match) AFTER mutating status,
# so callers saw exit 1 on a half-completed close.
slug2="lifecycle-inline-$$"
file2="$(bash "$DIR/worklist-new.sh" --title "Inline only $$" --slug "$slug2" \
  --ref "inline:only inline work" --publish ask)"
rc=0; out2="$(bash "$DIR/worklist-close.sh" "$file2" 2>/dev/null)" || rc=$?
assert "close: inline-only queue exits 0"   "[[ $rc -eq 0 ]]"
assert "close: inline-only prints CLOSED"   "[[ '$out2' == CLOSED* ]]"
rm -f "$file2" "${out2#CLOSED }"

# an unmatched slug must reach the intended diagnostic (exit 2 + message) instead
# of dying silently with exit 1 at the ls|head lookup under pipefail.
rc=0; err="$(bash "$DIR/worklist-advance.sh" "no-such-slug-$$" 2>&1 >/dev/null)" || rc=$?
assert "advance: bad slug exits 2"          "[[ $rc -eq 2 ]]"
assert "advance: bad slug prints not-found" "[[ '$err' == *'worklist not found'* ]]"
rc=0; err="$(bash "$DIR/worklist-close.sh" "no-such-slug-$$" 2>&1 >/dev/null)" || rc=$?
assert "close: bad slug exits 2"            "[[ $rc -eq 2 ]]"

if [[ "$fail" -eq 0 ]]; then echo "all worklist lifecycle assertions passed"; else echo "lifecycle FAILED"; exit 1; fi
