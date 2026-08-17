#!/usr/bin/env bash
# test-find-project-root.sh — regression test for _lib.sh's find_project_root.
#
# The bug (field-observed 2026-07-25, found by the worktree sandbox on its very
# first command): the upward walk had no boundary, so a stray `~/.context/`
# captured every project that had not been initialised yet. A fresh project
# resolved its root to $HOME, which made `orphan-sweep` scan for
# `<username>-wt-*` and report a clean workspace it was never looking at, and
# would have written that project's worktree overview into `~/.context/`.
# 33 scripts across every skill call this function.
#
# $HOME is overridden per-case so the boundary is exercised without touching
# the real home directory.
#
# Run with: bash skills/aidex-conventions/scripts/test-find-project-root.sh

set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
# macOS mktemp returns /var/... which is a symlink to /private/var; the function
# reports the resolved path, so resolve the expectations the same way.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# run <cwd> <home> -> prints the resolved root
run() { ( cd "$1" && HOME="$2" bash -c ". '$LIB'; find_project_root" ); }

FAKEHOME="$TMP/home"
mkdir -p "$FAKEHOME/.context/references"          # the stray ancestor .context
mkdir -p "$FAKEHOME/projects"

# --- case 1: THE BUG — a project with no .context under a home that has one ---
P1="$FAKEHOME/projects/fresh"
mkdir -p "$P1/backend"; : > "$P1/CLAUDE.md"
got="$(run "$P1" "$FAKEHOME")"
[[ "$got" == "$P1" ]] || fail "fresh project resolved to '$got', expected '$P1' — an ancestor .context must never capture an uninitialised project"
[[ "$got" == "$FAKEHOME" ]] && fail "resolved to \$HOME: artifacts would be written to the home directory"

# --- case 1b: the boundary must hold for an UNRESOLVED $HOME ---
# Every case here resolves TMP with `pwd -P` first (see above), which quietly made
# the boundary untestable: the walk compares `pwd -P` output against `$HOME`
# verbatim, so a $HOME reached through a symlink never matched and the walk
# continued straight past it into the stray `.context/`. On macOS that is the
# default shape of any temp dir (/var -> /private/var), and it is also what a home
# directory on a symlinked volume looks like. Pass the logical path on purpose.
RAWTMP="$(dirname "$TMP")/$(basename "$TMP")"
if [[ -L /var && "$TMP" == /private/var/* ]]; then
  RAWTMP="${TMP#/private}"
fi
if [[ "$RAWTMP" != "$TMP" && -d "$RAWTMP/home" ]]; then
  got="$(run "$P1" "$RAWTMP/home")"
  [[ "$got" == "$P1" ]] \
    || fail "with a symlinked \$HOME the boundary was skipped: resolved to '$got', expected '$P1'"
else
  printf 'note: no symlinked path available for the unresolved-$HOME case\n'
fi

# --- case 2: an initialised project still resolves exactly as before ---
P2="$FAKEHOME/projects/inited"
mkdir -p "$P2/.context" "$P2/sub/deeper"
got="$(run "$P2/sub/deeper" "$FAKEHOME")"
[[ "$got" == "$P2" ]] || fail "initialised project resolved to '$got', expected '$P2'"

# --- case 3: the nearest .context wins over an outer one ---
P3="$FAKEHOME/projects/inited/nested"
mkdir -p "$P3/.context"
got="$(run "$P3" "$FAKEHOME")"
[[ "$got" == "$P3" ]] || fail "nested .context should win, got '$got'"

# --- case 4: no .context anywhere, marker is a git repo ---
P4="$FAKEHOME/projects/repoonly"
mkdir -p "$P4/.git" "$P4/src"
got="$(run "$P4/src" "$FAKEHOME")"
[[ "$got" == "$P4" ]] || fail "repo root should be the fallback marker, got '$got'"

# --- case 5: no .context and no marker at all -> cwd, never an ancestor ---
P5="$FAKEHOME/projects/bare"
mkdir -p "$P5"
got="$(run "$P5" "$FAKEHOME")"
[[ "$got" == "$P5" ]] || fail "markerless dir should fall back to cwd, got '$got'"

# --- case 6: .context BELOW the project but above cwd still resolves upward ---
# (guards against the boundary being applied too aggressively)
P6="$FAKEHOME/projects/inited/sub"
got="$(run "$P6" "$FAKEHOME")"
[[ "$got" == "$P2" ]] || fail "an existing .context above cwd must still be found, got '$got'"

# --- case 7: HOME unset is DEGRADED, not broken ---
# With no $HOME there is no boundary to apply, so an ancestor .context wins
# again — the pre-fix behaviour. What must still hold is that the function
# terminates and returns an absolute path rather than crashing or emitting "/".
got="$( cd "$P1" && env -u HOME bash -c ". '$LIB'; find_project_root" )"
[[ -n "$got" && "$got" == /* && "$got" != "/" ]] \
  || fail "with HOME unset, expected a sane absolute path, got '$got'"

# --- case 8: from inside a LINKED WORKTREE, the main tree owns the artifacts ---
# A worktree is created as a sibling of the project, not under it, so the upward
# walk never reaches the main tree's .context/. Pass 2 then matched the worktree's
# own `.git` — a FILE, which `-e` accepts — and returned the worktree as the
# project root. Everything downstream wrote there: worktree.sh reads
# "$ROOT/.context/worktrees/config.env", which does not exist at that root, and
# nine aidex-worktree scripts source this same _lib.sh.
if command -v git >/dev/null 2>&1; then
  WMAIN="$FAKEHOME/projects/wtmain"
  mkdir -p "$WMAIN/.context"
  ( cd "$WMAIN" && git init -q . && : > f.txt && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
  ( cd "$WMAIN" && git worktree add -q "$FAKEHOME/projects/wtmain-wt-feat" -b feat ) >/dev/null 2>&1
  WT="$FAKEHOME/projects/wtmain-wt-feat"
  if [[ -d "$WT" ]]; then
    got="$(run "$WT" "$FAKEHOME")"
    [[ "$got" == "$WMAIN" ]] || fail "from inside a linked worktree, expected the main tree '$WMAIN', got '$got' — artifacts would be written into the worktree and vanish with it"

    # And a subdirectory of the worktree resolves the same way.
    mkdir -p "$WT/src"
    got="$(run "$WT/src" "$FAKEHOME")"
    [[ "$got" == "$WMAIN" ]] || fail "from a subdir of a linked worktree, expected '$WMAIN', got '$got'"

    # The main tree itself is unaffected — pass 1 still answers it directly, and
    # the worktree pass must not redirect a normal checkout anywhere.
    got="$(run "$WMAIN" "$FAKEHOME")"
    [[ "$got" == "$WMAIN" ]] || fail "the main tree must resolve to itself, got '$got'"
  else
    echo "skip: git worktree add unavailable — case 8 not exercised"
  fi
else
  echo "skip: git not on PATH — case 8 not exercised"
fi

# --- case 9: there is exactly ONE definition of this function in the suite ------
# Nineteen scripts carried a private copy. All of them were three fixes behind:
# no $HOME boundary (2026-07-25), no project-marker fallback, no linked-worktree
# hop. That was survivable while every copy was equally wrong; it stopped being
# survivable the moment the shared one was fixed, because then two artifacts
# written in the same session could land in different trees.
#
# So the invariant is not "the copies are in sync" — it is that there are none.
SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if [[ -d "$SKILLS_DIR" ]]; then
  extra=""
  while IFS= read -r hit; do
    [[ "$hit" == */aidex-conventions/scripts/_lib.sh ]] && continue
    extra="$extra $hit"
  done < <(grep -rl 'find_project_root()[[:space:]]*{' "$SKILLS_DIR" 2>/dev/null || true)
  [[ -z "${extra// /}" ]] \
    || fail "find_project_root is defined outside _lib.sh:${extra} — source the shared library instead; a private copy silently drifts behind every fix"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — find_project_root: stops at \$HOME, nearest .context wins, marker fallback, cwd last resort"
