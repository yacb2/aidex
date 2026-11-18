#!/usr/bin/env bash
# test-introducing-commit.sh — introducing-commit.sh names the commit a fix most likely repairs.
#
# Contract: skills/bugfix/scripts/introducing-commit.sh [--repo DIR] [FIX]; stdout is
# "<short sha> TAB <date> TAB <blamed lines> TAB <subject>", most recent committer date first;
# exit 0 candidates, 3 none, 2 usage/unknown/rootless FIX.
# Layer: real git in throwaway repos with pinned commit dates; nothing is stubbed.
# Add-only fixes (a missing guard) are the common case and have no removed line to blame, so
# they get their own fixtures; so does every filter that keeps a wrong commit out of the answer.
#
# Run with: bash skills/bugfix/tests/test-introducing-commit.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SCRIPT="${SCRIPT_OVERRIDE:-$ROOT/skills/bugfix/scripts/introducing-commit.sh}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/introducing-commit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }
TAB="$(printf '\t')"

n=0
newrepo() { n=$((n + 1)); R="$TMP/r$n"; mkdir -p "$R"; cd "$R" || exit 1; git -C "$R" init -q; git -C "$R" config user.email t@example.com; git -C "$R" config user.name t; }
# commit <date> <subject>: stage everything, commit with a pinned author/committer date; sets SHA
commit() {
  git -C "$R" add -A
  GIT_AUTHOR_DATE="$1 12:00:00 +0000" GIT_COMMITTER_DATE="$1 12:00:00 +0000" git -C "$R" commit -q -m "$2" || err "commit failed: $2"
  SHA="$(git -C "$R" rev-parse --short HEAD)"
}
# run [args]: sets OUT, ERR, RC
run() { OUT="$(bash "$SCRIPT" --repo "$R" "$@" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"; }
expect() { # <label> <rc> [expected stdout]
  [ "$RC" -eq "$2" ] || err "$1: exit $RC, wanted $2 (stderr: $ERR; stdout: $OUT)"
  if [ $# -ge 3 ] && [ "$OUT" != "$3" ]; then err "$1: stdout was
$OUT
wanted
$3"; fi
}
fixhead() { git -C "$R" rev-parse HEAD; }

# (a) modify-line fix names the commit that wrote the line, not a later one elsewhere in the file
newrepo; printf 'one\ntwo\nthree\n' > f.txt; commit 2024-01-01 "write top"; A="$SHA"
printf 'four\nfive\n' >> f.txt; commit 2024-03-01 "append bottom"
sed 's/two/TWO/' f.txt > f.new && mv f.new f.txt; commit 2024-04-01 "fix two"
run "$(fixhead)"; expect "(a) modify-line" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write top"

# (b) add-only fix names the enclosing context; a later unrelated commit elsewhere is not picked
newrepo; printf 'top\nguard-above\nguard-below\n' > f.txt; commit 2024-01-01 "write context"; A="$SHA"
printf 'far-away\n' >> f.txt; commit 2024-03-01 "unrelated tail"
printf 'top\nguard-above\nNEW GUARD\nguard-below\nfar-away\n' > f.txt; commit 2024-04-01 "add guard"
run "$(fixhead)"; expect "(b) add-only" 0 "$A${TAB}2024-01-01${TAB}2${TAB}write context"

# (b2) the context is the nearest NON-BLANK line each side: a blank line is never the answer
newrepo; printf 'head\n' > f.txt; commit 2024-01-01 "write head"; A="$SHA"
printf '\n' >> f.txt; commit 2024-02-01 "blank spacer"
printf 'tail\n' >> f.txt; commit 2024-03-01 "write tail"; C="$SHA"
printf 'head\n\nNEW\ntail\n' > f.txt; commit 2024-04-01 "insert after blank"
run "$(fixhead)"
expect "(b2) blank skipped" 0 "$C${TAB}2024-03-01${TAB}1${TAB}write tail
$A${TAB}2024-01-01${TAB}1${TAB}write head"

# (b3) insertion at end of file and at start of file: context is clipped to the file
newrepo; printf 'only\n' > f.txt; commit 2024-01-01 "write only"; A="$SHA"
printf 'only\nappended\n' > f.txt; commit 2024-02-01 "append at end"
run "$(fixhead)"; expect "(b3) end of file" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write only"
printf 'prepended\nonly\nappended\n' > f.txt; commit 2024-03-01 "prepend at start"
run "$(fixhead)"; expect "(b3) start of file" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write only"

# (c) test paths are excluded, lookalikes are not
check_path() { # <path> <expected rc>
  newrepo; mkdir -p "$R/$(dirname "$1")"; printf 'x\ny\n' > "$R/$1"; commit 2024-01-01 "write"
  printf 'x\nY\n' > "$R/$1"; commit 2024-02-01 "fix"
  run "$(fixhead)"; expect "(c) path $1" "$2"
}
for p in tests/a.sh src/test/a.sh pkg/__tests__/a.js spec/a.rb web/e2e/a.ts test_a.py a_test.go a.test.js a.spec.ts test-a.sh a-test.sh app/tests.py AppTests/FooTests.swift Tests/A.cs Core/FooTest.cs; do check_path "$p" 3; done
for p in src/attest.sh contest/a.sh src/mytest.sh src/testing/a.sh a.tests.js src/latest.sh src/my-contest.sh src/Contest.java; do check_path "$p" 0; done

# (c2) a hyphenated test file edited with the fix is skipped; its unrelated newer commit is not the pick
newrepo; mkdir scripts; printf 'bug\n' > scripts/foo.sh; printf 'check a\n' > scripts/test-foo.sh; commit 2024-01-01 "write bug"; A="$SHA"
printf 'check a\ncheck b\n' > scripts/test-foo.sh; commit 2024-05-01 "unrelated check"
printf 'fixed\n' > scripts/foo.sh; printf 'check a\ncheck b\ncheck c\n' > scripts/test-foo.sh; commit 2024-06-01 "fix with test"
run "$(fixhead)"; expect "(c2) test-foo.sh skipped" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write bug"

# (b4) blank lines inside a removed/modified hunk are not blamed either (a later spacer commit never wins)
newrepo; printf 'a()\nstray()\nb()\n' > f.txt; commit 2024-01-01 "write stray"; A="$SHA"
printf 'a()\nstray()\n\nb()\n' > f.txt; commit 2024-05-01 "unrelated spacing"
printf 'a()\nb()\n' > f.txt; commit 2024-06-01 "remove stray and spacer"
run "$(fixhead)"; expect "(b4) removed blank skipped" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write stray"
newrepo; printf 'a\nbuggy\n' > f.txt; commit 2024-01-01 "A writes buggy"; A="$SHA"
printf 'a\n\nbuggy\n' > f.txt; commit 2024-03-01 "B adds blank spacer"
printf 'a\nfixed\n' > f.txt; commit 2024-04-01 "fix"
run "$(fixhead)"; expect "(b4) blank replaced with fix" 0 "$A${TAB}2024-01-01${TAB}1${TAB}A writes buggy"
# only blank lines replaced by code: that is add-only, the context lines are blamed
newrepo; printf 'top\n\nbot\n' > f.txt; commit 2024-01-01 "write frame"; A="$SHA"
printf 'top\nGUARD\nbot\n' > f.txt; commit 2024-02-01 "fill blank"
run "$(fixhead)"; expect "(b4) blank replaced by code" 0 "$A${TAB}2024-01-01${TAB}2${TAB}write frame"

# (r) renames: the fix's own diff is rename-aware, hunks are blamed under the old path
newrepo; printf 'buggy\nmid\nold3\n' > f.txt; commit 2024-01-01 "A writes file"; A="$SHA"
printf 'buggy\nmid\nnew3\n' > f.txt; commit 2024-03-01 "B edits line 3"
git mv f.txt g.txt; printf 'fixed\nmid\nnew3\n' > g.txt; commit 2024-04-01 "rename and fix"
RENFIX="$SHA"
run "$(fixhead)"; expect "(r) rename + fix" 0 "$A${TAB}2024-01-01${TAB}1${TAB}A writes file"
git mv g.txt h.txt; run; expect "(r) staged rename uncommitted" 3 ""
printf 'fixed2\nmid\nnew3\n' > h.txt; run; expect "(r) staged rename + edit uncommitted" 0 "$RENFIX${TAB}2024-04-01${TAB}1${TAB}rename and fix"
git reset -q --hard
newrepo; printf 'x\ny\nz\n' > f.txt; commit 2024-01-01 "write"; printf 'x\ny\nz\nw\n' > f.txt; commit 2024-02-01 "later edit"
git mv f.txt g.txt; commit 2024-03-01 "pure rename"
run "$(fixhead)"; expect "(r) pure rename" 3 ""
# a deleted file is a meta-change: only the other file's fix is blamed
newrepo; printf 'dead\n' > dead.txt; printf 'bug\n' > live.txt; commit 2024-01-01 "write both"; A="$SHA"
printf 'dead2\n' > dead.txt; commit 2024-05-01 "touch dead file"
git rm -q dead.txt; printf 'ok\n' > live.txt; commit 2024-06-01 "drop dead, fix live"
run "$(fixhead)"; expect "(r) deleted file" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write both"

# (d) a fix that only creates a new file has nothing to blame
newrepo; printf 'x\n' > f.txt; commit 2024-01-01 "write"
printf 'new\n' > g.txt; commit 2024-02-01 "new file only"
run "$(fixhead)"; expect "(d) new file" 3 ""

# (e) uncommitted mode (staged + unstaged, untracked ignored) picks what committed mode picks
newrepo; printf 'one\ntwo\n' > f.txt; printf 'p\nq\n' > g.txt; commit 2024-01-01 "write both"; A="$SHA"
printf 'x\n' > g.txt.untracked
sed 's/one/ONE/' f.txt > f.new && mv f.new f.txt; git -C "$R" add f.txt
sed 's/q/Q/' g.txt > g.new && mv g.new g.txt
run; expect "(e) uncommitted" 0 "$A${TAB}2024-01-01${TAB}2${TAB}write both"; U="$OUT"
rm "$R/g.txt.untracked"; commit 2024-02-01 "fix both"
run "$(fixhead)"; expect "(e) committed" 0 "$U"
run; expect "(e) clean tree" 3 ""

# (f) two candidates, most recent first even when the older one blames more lines
newrepo; printf 'old1\nold2\n' > f.txt; commit 2024-01-01 "older, two lines"; A="$SHA"
printf 'new1\n' >> f.txt; commit 2024-06-01 "newer, one line"; B="$SHA"
printf 'OLD1\nOLD2\nNEW1\n' > f.txt; commit 2024-07-01 "fix"
run "$(fixhead)"
expect "(f) date order" 0 "$B${TAB}2024-06-01${TAB}1${TAB}newer, one line
$A${TAB}2024-01-01${TAB}2${TAB}older, two lines"
# same committer time: more blamed lines first (five commits, so sha order cannot pass by luck)
newrepo; : > f.txt; exp=
for k in 1 2 3 4 5; do
  i=0; while [ "$i" -lt "$k" ]; do printf 'c%s_%s\n' "$k" "$i" >> f.txt; i=$((i + 1)); done
  commit 2024-01-01 "commit $k"
  line="$SHA${TAB}2024-01-01${TAB}$k${TAB}commit $k"
  if [ -z "$exp" ]; then exp="$line"; else exp="$line
$exp"; fi
done
sed 's/^c/C/' f.txt > f.new && mv f.new f.txt; commit 2024-02-01 "fix all"
run "$(fixhead)"; expect "(f) tie by count" 0 "$exp"

# (g) a whitespace-only reformat is not blamed (-w); a whitespace-only fix has no hunk
newrepo; printf 'if a:\n  go()\n  stop()\n' > f.txt; commit 2024-01-01 "write logic"; A="$SHA"
printf 'if a:\n    go()\n    stop()\n' > f.txt; commit 2024-02-01 "reindent"
printf 'if a:\n    go()\n    halt()\n' > f.txt; commit 2024-03-01 "fix stop"
run "$(fixhead)"; expect "(g) -w" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write logic"
printf 'if a:\n        go()\n        halt()\n' > f.txt; commit 2024-04-01 "reindent only"
run "$(fixhead)"; expect "(g) whitespace-only fix" 3 ""
printf 'if a:\n        go()\n\n        halt()\n' > f.txt; commit 2024-05-01 "blank line only"
run "$(fixhead)"; expect "(g) blank-line-only fix" 3 ""

# (g2) moved lines are followed to their author: within a file (-M) and across files (-C)
# git copy detection scores alphanumerics: -C needs 40 in the blamed range, so the lines are long
L1="alpha_alpha_alpha_alpha_alpha_alpha_alpha_alpha"; L2="bravo_bravo_bravo_bravo_bravo_bravo_bravo_bravo"; L3="charlie_charlie_charlie_charlie_charlie_charlie"; L4="delta_delta_delta_delta_delta_delta_delta_delta"
newrepo; printf '%s\n%s\n%s\n%s\n' "$L1" "$L2" "$L3" "$L4" > f.txt; commit 2024-01-01 "write blocks"; A="$SHA"
printf '%s\n%s\n%s\n%s\n' "$L3" "$L4" "$L1" "$L2" > f.txt; commit 2024-02-01 "reorder"
printf '%s\n%s\n%s\n%s\n' "$L3" "$L4" "${L1}_fixed" "$L2" > f.txt; commit 2024-03-01 "fix"
run "$(fixhead)"; expect "(g2) -M within file" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write blocks"
newrepo; printf '%s\n%s\n%s\n' "$L1" "$L2" "$L3" > a.txt; printf 'keep\n' > b.txt; commit 2024-01-01 "write in a"; A="$SHA"
printf '%s\n' "$L3" > a.txt; printf 'keep\n%s\n%s\n' "$L1" "$L2" > b.txt; commit 2024-02-01 "move to b"
printf 'keep\n%s\n%s\n' "${L1}_fixed" "$L2" > b.txt; commit 2024-03-01 "fix"
run "$(fixhead)"; expect "(g2) -C across files" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write in a"

# (h) a path with a space
newrepo; mkdir "$R/my dir"; printf 'one\ntwo\n' > "$R/my dir/my file.txt"; commit 2024-01-01 "write spaced"; A="$SHA"
printf 'one\nTWO\n' > "$R/my dir/my file.txt"; commit 2024-02-01 "fix spaced"
run "$(fixhead)"; expect "(h) space path" 0 "$A${TAB}2024-01-01${TAB}1${TAB}write spaced"

# (k) a user's diff.interHunkContext must not merge two hunks: the lines between them are not the fix's
newrepo; git -C "$R" config diff.interHunkContext 5
printf 'a1\nmid1\nmid2\nz1\n' > f.txt; commit 2024-01-01 "A writes a1,z1"; A="$SHA"
printf 'a1\nMID1\nMID2\nz1\n' > f.txt; commit 2024-02-01 "unrelated rewrites mid"
printf 'A1\nMID1\nMID2\nZ1\n' > f.txt; commit 2024-03-01 "fix ends"
run "$(fixhead)"; expect "(k) interHunkContext" 0 "$A${TAB}2024-01-01${TAB}2${TAB}A writes a1,z1"

# (j) a shallow clone's boundary commit is a graft, not an author: it is never named
newrepo; printf 'one\ntwo\n' > f.txt; commit 2024-01-01 "real author"
printf 'one\ntwo\nthree\n' > f.txt; commit 2024-02-01 "second"
sed 's/two/TWO/' f.txt > f.new && mv f.new f.txt; commit 2024-03-01 "fix"
SRC="$R"; R="$TMP/shallow"; git clone -q --depth 2 --no-local "file://$SRC" "$R"
run "$(fixhead)"; expect "(j) shallow boundary" 3 ""

# (i) usage errors: root commit as FIX, unknown FIX, not a repo, bad option, two FIXes
newrepo; printf 'x\n' > f.txt; commit 2024-01-01 "root"; ROOTC="$SHA"
run "$ROOTC"; expect "(i) root commit" 2; case "$ERR" in *"no parent"*) ;; *) err "(i) root commit: reason not on stderr: $ERR" ;; esac
run deadbeefdeadbeef; expect "(i) unknown FIX" 2
run --bogus; expect "(i) bad option" 2
run "$ROOTC" "$ROOTC"; expect "(i) two FIXes" 2
mkdir "$TMP/plain"; OUT="$(bash "$SCRIPT" --repo "$TMP/plain" 2>/dev/null)"; RC=$?; ERR=; expect "(i) not a repo" 2

if [ "$fail" -eq 0 ]; then echo "OK: introducing-commit.sh contract"; else exit 1; fi
