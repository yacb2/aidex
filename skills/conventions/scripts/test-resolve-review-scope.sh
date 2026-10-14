#!/usr/bin/env bash
# Behavioural test for resolve-review-scope.sh.
#
# The defect under guard is NOT "the enum is missing a name" — it is a silent
# no-op: `/security-review` hard-codes `git diff origin/HEAD...`, and on a repo
# whose work lands on the default branch and is pushed, that resolves to zero
# files while the tree is dirty. The review then reports "no findings" without
# having read anything. Case 3 below reconstructs exactly that repo state and
# asserts the resolver does NOT return an empty set there.
#
# Every case builds a real repo in mktemp (absolute path) and asserts on the
# resolved FILE SET, not on the script's prose. A test that only checked the
# enum would pass against a resolver that returns nothing.
#
# Run with: bash skills/conventions/scripts/test-resolve-review-scope.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/resolve-review-scope.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: not executable: $SCRIPT" >&2; exit 1; }

pass=0; fail=0
ok()  { printf 'ok   — %s\n' "$*"; pass=$((pass+1)); }
err() { printf 'FAIL — %s\n' "$*" >&2; fail=$((fail+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Build a repo with an "origin" that already contains every commit, so
# origin/HEAD == HEAD — the pushed-main state.
make_repo() { # <name> -> echoes absolute path
  local name="$1" up="$TMPROOT/$1.upstream" wd="$TMPROOT/$1"
  git init -q --bare "$up"
  git init -q -b main "$wd"
  git -C "$wd" config user.email t@t.test
  git -C "$wd" config user.name Test
  printf 'one\n' > "$wd/a.txt"
  mkdir -p "$wd/mod"; printf 'm1\n' > "$wd/mod/m.txt"
  git -C "$wd" add -A >/dev/null
  git -C "$wd" commit -qm base
  git -C "$wd" remote add origin "$up"
  git -C "$wd" push -q -u origin main
  git -C "$wd" remote set-head origin main >/dev/null 2>&1
  printf '%s\n' "$wd"
}

files_for() { # <repo> <scope> [target] -> file list on stdout, exit code preserved
  local wd="$1"; shift
  ( cd "$wd" && "$SCRIPT" --files "$@" )
}
key_for() { # <repo> <key> <scope> [target]
  local wd="$1" key="$2"; shift 2
  ( cd "$wd" && "$SCRIPT" "$@" ) | sed -n "s/^$key=//p"
}

# --- case 0: the fixture really reproduces the broken anchor ----------------
# If this fails, every later assertion is meaningless — the repo state we claim
# to guard against would not exist.
R=$(make_repo pushed)
printf 'two\n' >> "$R/a.txt"
broken=$( cd "$R" && git diff --name-only origin/HEAD... 2>/dev/null | wc -l | tr -d ' ' )
dirty=$( cd "$R" && git status --short | wc -l | tr -d ' ' )
if [ "$broken" = "0" ] && [ "$dirty" != "0" ]; then
  ok "fixture reproduces the dead anchor (origin/HEAD... = 0 files, tree dirty = $dirty)"
else
  err "fixture does NOT reproduce the dead anchor (origin/HEAD...=$broken, dirty=$dirty) — later cases prove nothing"
fi

# --- case 1: working-diff sees uncommitted changes --------------------------
out=$(files_for "$R" working-diff)
if [ "$out" = "a.txt" ]; then ok "working-diff resolves to the dirty file"
else err "working-diff expected 'a.txt', got '$out'"; fi

# --- case 2: unknown scope is rejected, not silently defaulted --------------
if ( cd "$R" && "$SCRIPT" whole-repo >/dev/null 2>&1 ); then
  err "unknown scope 'whole-repo' was accepted"
else
  ok "unknown scope is rejected"
fi

# --- case 3: THE DEFECT — branch-vs-main on pushed main must not be empty ---
out=$(files_for "$R" branch-vs-main); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "a.txt" ]; then
  ok "branch-vs-main on pushed main resolves to the real change (not the empty origin/HEAD... set)"
else
  err "branch-vs-main on pushed main returned rc=$rc files='$out' — this is the silent no-op the resolver exists to prevent"
fi

anchor=$(key_for "$R" anchor branch-vs-main)
if [ "$anchor" = "head" ]; then
  ok "the fallback anchor is reported ('head'), so a degenerate base is visible to the caller"
else
  err "expected anchor=head on pushed main, got '$anchor'"
fi

# --- case 4: a real feature branch still uses the merge-base ----------------
R2=$(make_repo feature)
git -C "$R2" checkout -qb feat
printf 'feature\n' >> "$R2/a.txt"
git -C "$R2" commit -qam feat-work
out=$(files_for "$R2" branch-vs-main)
anchor=$(key_for "$R2" anchor branch-vs-main)
if [ "$out" = "a.txt" ] && [ "$anchor" = "merge-base" ]; then
  ok "branch-vs-main on a diverged branch uses the merge-base anchor"
else
  err "diverged branch expected files='a.txt' anchor='merge-base', got files='$out' anchor='$anchor'"
fi

# --- case 5: module-path narrows, and does not leak sibling changes ---------
R3=$(make_repo module)
printf 'edit\n' >> "$R3/a.txt"
printf 'm2\n' >> "$R3/mod/m.txt"
out=$(files_for "$R3" module-path mod)
if [ "$out" = "mod/m.txt" ]; then
  ok "module-path narrows to the module and excludes the sibling change"
else
  err "module-path expected 'mod/m.txt', got '$out'"
fi

# --- case 6: a genuinely clean tree exits 3, distinguishable from a bad base -
R4=$(make_repo clean)
out=$(files_for "$R4" branch-vs-main); rc=$?
if [ "$rc" -eq 3 ] && [ -z "$out" ]; then
  ok "a genuinely empty scope exits 3 (clean tree is reported, not disguised as a review)"
else
  err "clean repo expected rc=3 with no files, got rc=$rc files='$out'"
fi

# --- case 7: --base is a parameter, so presets need no new enum member ------
R5=$(make_repo baseparam)
printf 'c1\n' >> "$R5/a.txt"; git -C "$R5" commit -qam c1
printf 'c2\n' >> "$R5/mod/m.txt"; git -C "$R5" commit -qam c2
out=$( cd "$R5" && "$SCRIPT" --files --base HEAD~1 branch-vs-main )
anchor=$( cd "$R5" && "$SCRIPT" --base HEAD~1 branch-vs-main | sed -n 's/^anchor=//p' )
if [ "$out" = "mod/m.txt" ] && [ "$anchor" = "explicit" ]; then
  ok "--base overrides the resolved base ('since-last-commit' is a preset, not a 5th scope)"
else
  err "--base HEAD~1 expected files='mod/m.txt' anchor='explicit', got files='$out' anchor='$anchor'"
fi

# --- case 7b: --base names a ref that is also a tracked directory ------------
# `git diff --name-only main` is "ambiguous argument" when ./main exists; without a
# bare `--` the list came back empty (stderr hidden) and the scope exited 3.
R5b=$(make_repo refpath)
mkdir -p "$R5b/main"; printf 'x\n' > "$R5b/main/f.txt"; git -C "$R5b" add -A; git -C "$R5b" commit -qm dir
git -C "$R5b" push -q origin main
git -C "$R5b" checkout -qb feat
printf 'c1\n' >> "$R5b/a.txt"; git -C "$R5b" commit -qam c1
out=$( cd "$R5b" && "$SCRIPT" --files --base main working-diff ); rc=$?
if [ "$out" = "a.txt" ] && [ "$rc" -eq 0 ]; then
  ok "--base <ref> still resolves when a tracked directory has the ref's name"
else
  err "--base main with a main/ directory expected files='a.txt' rc=0, got files='$out' rc=$rc"
fi

# --- case 8: worktree-cumulative resolves inside a real linked worktree -----
# The enum documents this scope, so it needs a case in a genuine `git worktree`,
# not just a diverged branch that happens to share the code path.
R6=$(make_repo wt)
WT="$TMPROOT/wt.linked"
git -C "$R6" worktree add -q -b wt-branch "$WT" >/dev/null 2>&1
if [ -d "$WT" ]; then
  printf 'wt-change\n' >> "$WT/a.txt"
  git -C "$WT" commit -qam wt-work
  out=$( cd "$WT" && "$SCRIPT" --files worktree-cumulative )
  anchor=$( cd "$WT" && "$SCRIPT" worktree-cumulative | sed -n 's/^anchor=//p' )
  if [ "$out" = "a.txt" ] && [ "$anchor" = "merge-base" ]; then
    ok "worktree-cumulative resolves a linked worktree's work against its fork point"
  else
    err "linked worktree expected files='a.txt' anchor='merge-base', got files='$out' anchor='$anchor'"
  fi
  git -C "$R6" worktree remove --force "$WT" >/dev/null 2>&1
else
  err "could not create a linked worktree — worktree-cumulative is left unproven"
fi

# --- case 9 (c10): origin/HEAD names the default branch but no local branch of that
# name exists. The merge-base must use the remote ref, not silently fall back to
# the last commit (a 3-commit branch reviewed as its last commit only, rc=0).
R7=$(make_repo nolocal)
git -C "$R7" checkout -qb feat
for n in f1 f2 f3; do printf '%s\n' "$n" > "$R7/$n.txt"; git -C "$R7" add "$n.txt"; git -C "$R7" commit -qm "$n"; done
git -C "$R7" branch -D main >/dev/null 2>&1
out=$(files_for "$R7" branch-vs-main | sort | tr '\n' ' ')
anchor=$(key_for "$R7" anchor branch-vs-main)
if [ "$out" = "f1.txt f2.txt f3.txt " ] && [ "$anchor" = "merge-base" ]; then
  ok "no local default branch: merge-base falls back to origin/<default>, all 3 commits reviewed"
else
  err "no local main: expected f1 f2 f3 + merge-base, got files='$out' anchor='$anchor'"
fi

# --- case 10 (c11): untracked, non-ignored files belong to working-diff ONLY ----
R8=$(make_repo untracked)
printf 'n\n' > "$R8/new.py"
out=$(files_for "$R8" working-diff); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "new.py" ]; then ok "working-diff lists an untracked file (add-only change is not empty)"
else err "working-diff with only an untracked file: rc=$rc files='$out'"; fi
# ignored files stay out; a tracked edit and an untracked file both appear, root-relative
printf 'ignored.log\n' > "$R8/.gitignore"; printf 'x\n' > "$R8/ignored.log"
printf 'edit\n' >> "$R8/mod/m.txt"
out=$( cd "$R8/mod" && "$SCRIPT" --files working-diff | sort | tr '\n' ' ' )
if [ "$out" = ".gitignore mod/m.txt new.py " ]; then ok "tracked + untracked, root-relative from a subdirectory, ignored file excluded"
else err "mixed tracked/untracked from subdir: got '$out'"; fi
# names with glob characters and spaces are listed verbatim, a sibling-prefix dir is not special
mkdir -p "$R8/mod2" "$R8/mo[d]" "$R8/sp ace"
printf 'u\n' > "$R8/mod2/sib.txt"; printf 'u\n' > "$R8/mo[d]/g.txt"; printf 'u\n' > "$R8/sp ace/s.txt"
out=$(files_for "$R8" working-diff | grep -c -x -e 'mod2/sib.txt' -e 'mo\[d\]/g.txt' -e 'sp ace/s.txt')
if [ "$out" = "3" ]; then ok "working-diff lists untracked names with glob characters and spaces"
else err "untracked special names: matched $out of 3"; fi

# the other scopes stay as at HEAD: 194 untracked PNGs must not flip their anchor
R10=$(make_repo untrackedscopes)
git -C "$R10" checkout -qb feat
printf 'feature\n' >> "$R10/a.txt"; git -C "$R10" commit -qam feat-work
printf 'u\n' > "$R10/u.txt"
for sc in branch-vs-main; do
  out=$(files_for "$R10" $sc | tr '\n' ' '); anchor=$(key_for "$R10" anchor $sc)
  if [ "$out" = "a.txt " ] && [ "$anchor" = "merge-base" ]; then ok "$sc does not list the untracked file"
  else err "$sc with an untracked file: files='$out' anchor='$anchor'"; fi
done
R11=$(make_repo untrackedmain)
printf 'u\n' > "$R11/u.txt"
anchor=$(key_for "$R11" anchor branch-vs-main); out=$(files_for "$R11" branch-vs-main); rc=$?
if [ "$anchor" = "last-commit" ] || [ "$rc" -eq 3 ]; then ok "branch-vs-main on main with only an untracked file is not flipped to anchor=head ('$anchor', rc=$rc)"
else err "untracked-only on main: anchor='$anchor' rc=$rc files='$out'"; fi
out=$(files_for "$R10" module-path . | tr '\n' ' ')
if [ "$out" = "a.txt " ]; then ok "module-path does not list the untracked file"
else err "module-path with an untracked file: '$out'"; fi
git -C "$R10" worktree add -q -b wt2 "$TMPROOT/untrackedscopes.wt" >/dev/null 2>&1
printf 'wt\n' >> "$TMPROOT/untrackedscopes.wt/a.txt"; git -C "$TMPROOT/untrackedscopes.wt" commit -qam wtw
printf 'u\n' > "$TMPROOT/untrackedscopes.wt/wu.txt"
out=$( cd "$TMPROOT/untrackedscopes.wt" && "$SCRIPT" --files worktree-cumulative | sort | tr '\n' ' ' )
if [ "$out" = "a.txt " ]; then ok "worktree-cumulative does not list the untracked file"
else err "worktree-cumulative with an untracked file: '$out'"; fi

# --- case 10b (Q27b): --base brings the untracked files of the last, uncommitted unit
BASE_SHA=$(git -C "$R10" rev-parse main)
out=$(files_for "$R10" --base "$BASE_SHA" branch-vs-main | tr '\n' ' ')
if [ "$out" = "a.txt u.txt " ]; then ok "branch-vs-main with --base lists the untracked file"
else err "branch-vs-main --base with an untracked file: '$out'"; fi
printf 'ign\n' > "$R10/ignored.log"; printf 'ignored.log\n' >> "$R10/.git/info/exclude"
out=$(files_for "$R10" --base "$BASE_SHA" branch-vs-main | tr '\n' ' ')
if [ "$out" = "a.txt u.txt " ]; then ok "branch-vs-main with --base keeps an ignored untracked file out"
else err "branch-vs-main --base with an ignored file: '$out'"; fi
# module-path with --base: the pathspec narrows the untracked listing too (root u.txt stays out)
printf 'n\n' > "$R10/mod/nu.txt"
out=$(files_for "$R10" --base "$BASE_SHA" module-path mod | tr '\n' ' ')
if [ "$out" = "mod/nu.txt " ]; then ok "module-path --base lists only untracked files under the path"
else err "module-path mod --base: '$out'"; fi
# untracked-only repo: --base HEAD makes the scope non-empty (rc 0), not 3
R13=$(make_repo untrackedonlybase)
printf 'u\n' > "$R13/u.txt"
out=$(files_for "$R13" --base HEAD branch-vs-main | tr '\n' ' '); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "u.txt " ]; then ok "untracked-only repo with --base HEAD resolves rc 0 to that file"
else err "untracked-only --base HEAD: rc=$rc files='$out'"; fi
# --help prints the whole header (to Exit codes) and stops before code
help=$("$SCRIPT" --help)
case "$help" in
  *"Exit codes:"*) case "$help" in *"set -uo"*) err "--help leaks code: set -uo" ;; *) ok "--help ends at the header's end" ;; esac ;;
  *) err "--help is cut before 'Exit codes:'" ;;
esac

# --- case 11: no duplicate lines when a file is both in the diff and untracked ---
R12=$(make_repo dedupe)
git -C "$R12" rm -q --cached a.txt
dups=$(files_for "$R12" working-diff | sort | uniq -d)
if [ -z "$dups" ]; then ok "working-diff lists a de-indexed file once"
else err "duplicate lines in working-diff: '$dups'"; fi

# --- case 12 (c10): no origin/HEAD, no local main, origin/main present ---------
R13=$(make_repo noorigin_head)
git -C "$R13" checkout -qb feat
for n in f1 f2; do printf '%s\n' "$n" > "$R13/$n.txt"; git -C "$R13" add "$n.txt"; git -C "$R13" commit -qm "$n"; done
git -C "$R13" branch -D main >/dev/null 2>&1
git -C "$R13" remote set-head origin -d >/dev/null 2>&1
out=$(files_for "$R13" branch-vs-main | sort | tr '\n' ' '); anchor=$(key_for "$R13" anchor branch-vs-main)
if [ "$out" = "f1.txt f2.txt " ] && [ "$anchor" = "merge-base" ]; then
  ok "no origin/HEAD and no local main: origin/main is the default branch"
else
  err "no origin/HEAD, no local main: files='$out' anchor='$anchor'"
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
