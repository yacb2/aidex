#!/usr/bin/env bash
# test_worklist_lifecycle.sh — new → advance ×N → append → close, asserting state
# and that the file validates throughout. Cleans up its fixture.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
# Run inside a throwaway project, never the live one. The scripts write wherever
# find_project_root() points for the cwd, and that answer is not stable across a
# run: two suites at once (a linked worktree and the main tree) flip it for each
# other, so the fixture was archived into one project while cleanup deleted from
# another — leaking lifecycle-test files into aidex_ws/.context (BL-418) and, on
# 2026-09-29, a `.context/` into the public repo. A sandbox with its own
# `.context/` is what find_project_root() answers first, whoever runs next door.
ROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT
mkdir "$ROOT/.context"
cd "$ROOT"
fail=0
assert() { if eval "$2"; then echo "  [PASS] $1"; else echo "  [FAIL] $1"; fail=1; fi; }

slug="lifecycle-test-$$"
file="$(bash "$DIR/worklist-new.sh" --title "Lifecycle test $$" --slug "$slug" \
  --ref "backlog:BL-1 — do a" --ref "plan:p-2 — do b" --ref "inline:do c" --publish ask)"

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

# BL-370: a --slug that already carries a date (the shape every other .context/
# filename has) was prefixed a second time: 2026-09-08-2026-09-08-<slug>.
slug3="2031-01-01-dated-$$"
file3="$(bash "$DIR/worklist-new.sh" --title "Dated slug $$" --slug "$slug3" \
  --ref "inline:x" --publish ask)"
assert "new: a dated --slug is not date-prefixed twice" "[[ '$(basename "$file3")' == '$slug3.md' ]]"
rm -f "$file3"
slug4="undated-$$"
file4="$(bash "$DIR/worklist-new.sh" --title "Undated slug $$" --slug "$slug4" \
  --ref "inline:x" --publish ask)"
assert "new: an undated --slug still gets today's date" "[[ '$(basename "$file4")' == '$(date +%F)-$slug4.md' ]]"
rm -f "$file4"

# BL-539: a slug resolves to the work-list, never a -report companion (which sorts first:
# "-" < "."), and two work-lists matching one slug are refused (exit 2), not head -1'd.
slug5="companion-$$"
file5="$(bash "$DIR/worklist-new.sh" --title "Companion $$" --slug "$slug5" --ref "inline:x" --publish ask)"
comp5="${file5%.md}-report.md"; printf 'report\n' > "$comp5"
rc=0; out5="$(bash "$DIR/worklist-advance.sh" "$slug5" 2>/dev/null)" || rc=$?
assert "advance: slug with a -report companion advances the work-list" \
  "[[ $rc -eq 0 && \$(grep -cE '^1\. \[x\] ' '$file5') -eq 1 && \$(cat '$comp5') == report ]]"
rc=0; out5="$(bash "$DIR/worklist-close.sh" "$slug5" 2>/dev/null)" || rc=$?
assert "close: slug with a -report companion closes the work-list" \
  "[[ $rc -eq 0 && '$out5' == CLOSED*/_archive/$(basename "$file5") && -f '$comp5' ]]"
rm -f "$comp5" "${out5#CLOSED }"
slug6="ambig-$$"
f6a="$(bash "$DIR/worklist-new.sh" --title "Ambig one $$" --slug "$slug6-one" --ref "inline:x" --publish ask)"
f6b="$(bash "$DIR/worklist-new.sh" --title "Ambig two $$" --slug "$slug6-two" --ref "inline:x" --publish ask)"
before6="$(cat "$f6a" "$f6b")"
rc=0; err="$(bash "$DIR/worklist-advance.sh" "$slug6" 2>&1 >/dev/null)" || rc=$?
assert "advance: a slug matching two work-lists is refused (exit 2)" "[[ $rc -eq 2 && \"\$err\" == *ambiguous* ]]"
rc=0; err="$(bash "$DIR/worklist-close.sh" "$slug6" 2>&1 >/dev/null)" || rc=$?
assert "close: a slug matching two work-lists is refused (exit 2)" "[[ $rc -eq 2 && \"\$err\" == *ambiguous* ]]"
after6="$(cat "$f6a" "$f6b")"
assert "ambiguous slug mutates neither work-list" "[[ \"\$before6\" == \"\$after6\" ]]"
rm -f "$f6a" "$f6b"

# exact stem wins: `<d>-x.md` and `<d>-x-2.md` both contain the slug `<d>-x`; the exact one is meant
slug7="exact-$$"
f7a="$(bash "$DIR/worklist-new.sh" --title "Exact $$" --slug "$slug7" --ref "inline:x" --publish ask)"
f7b="$(bash "$DIR/worklist-new.sh" --title "Exact two $$" --slug "$slug7-2" --ref "inline:x" --publish ask)"
before7b="$(cat "$f7b")"
rc=0; bash "$DIR/worklist-advance.sh" "$(basename "$f7a" .md)" >/dev/null 2>&1 || rc=$?
assert "advance: an exact stem wins over a longer name containing it" \
  "[[ $rc -eq 0 && \$(grep -cE '^1\. \[x\] ' '$f7a') -eq 1 && \"\$(cat '$f7b')\" == \"\$before7b\" ]]"
rm -f "$f7a" "$f7b"

if [[ "$fail" -eq 0 ]]; then echo "all worklist lifecycle assertions passed"; else echo "lifecycle FAILED"; exit 1; fi
