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
# Run with: bash skills/aidex-conventions/scripts/test-resolve-review-scope.sh

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

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
