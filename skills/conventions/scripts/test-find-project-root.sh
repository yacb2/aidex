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
# Run with: bash skills/conventions/scripts/test-find-project-root.sh

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

# The two Python ports must answer as find_project_root does from the same directory:
# backlog/_ids.find_root (define-check, sweep-eligible, renumber-ids, migrate-filenames)
# and validate.find_context_dir (validate, migrate-conventions --apply). BL-769 landed in
# the bash resolver only, so from a nested worktree both still wrote into, or judged, the
# workspace's live .context/ while the bash scripts of the same chain used the worktree.
IDS_DIR="$(cd "$(dirname "$LIB")/../../backlog/scripts" && pwd -P)"
VAL_DIR="$(dirname "$LIB")"
# parity <cwd> <home>: both ports against find_project_root's answer from <cwd>
parity() {
  local want got wantctx
  want="$(run "$1" "$2")"
  got="$(HOME="$2" python3 -I -c 'import sys, pathlib; sys.path.insert(0, sys.argv[1]); import _ids; print(_ids.find_root(pathlib.Path(sys.argv[2])))' "$IDS_DIR" "$1")"
  [[ "$got" == "$want" ]] || fail "_ids.find_root from '$1' answered '$got', find_project_root '$want'"
  wantctx="None"; [[ -d "$want/.context" ]] && wantctx="$want/.context"
  got="$(HOME="$2" python3 -I -c 'import sys, pathlib; sys.path.insert(0, sys.argv[1]); import validate; print(validate.find_context_dir(pathlib.Path(sys.argv[2])))' "$VAL_DIR" "$1")"
  [[ "$got" == "$wantctx" ]] || fail "validate.find_context_dir from '$1' answered '$got', expected '$wantctx' (find_project_root: '$want')"
}

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
# nine worktree scripts source this same _lib.sh.
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

# --- case 10: the hop STOPS at the main worktree's root (BL-418) ------------
# A repo nested inside a workspace that has its own .context/ — the shape of every
# split workspace since BL-412: the main tree deliberately carries NO .context/.
# The hop used to keep walking up from there, escape the repo, and land on the
# WORKSPACE's private .context/, so any script run inside a cell worktree wrote
# into the owner's live artifacts (observed: 34 lifecycle-test files in
# aidex_ws/.context/worklists/_archive/). The main tree is the project; the walk
# must stop there.
if command -v git >/dev/null 2>&1; then
  WS="$FAKEHOME/projects/ws"
  mkdir -p "$WS/.context"
  NESTED="$WS/proj"
  mkdir -p "$NESTED"
  ( cd "$NESTED" && git init -q . && : > f.txt && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
  # The worktree is created OUTSIDE the workspace, as the cells are: otherwise
  # pass 1 finds the workspace .context/ before the hop ever runs.
  NWT="$FAKEHOME/projects/proj-wt-feat"
  ( cd "$NESTED" && git worktree add -q "$NWT" -b feat ) >/dev/null 2>&1
  if [[ -d "$NWT" ]]; then
    got="$(run "$NWT" "$FAKEHOME")"
    [[ "$got" == "$NESTED" ]] || fail "from a worktree of a repo nested in a workspace, expected the main tree '$NESTED', got '$got' — a script would write into the parent workspace's private .context/"
    parity "$NWT" "$FAKEHOME"
  else
    echo "skip: git worktree add unavailable — case 10 not exercised"
  fi
else
  echo "skip: git not on PATH — case 10 not exercised"
fi

# --- case 11: a worktree created INSIDE the workspace resolves to itself (BL-769) ---
# Same split-workspace shape as case 10, but the worktree lives under the workspace
# (aidex_ws/_tmp/wt/<x>). Pass 1 found the WORKSPACE .context/ before the hop ran,
# so every script wrote into the owner's live artifacts. Owner decision 2026-10-18
# (q16): a nested worktree's root is the worktree itself. The workspace's own
# worktrees and a project's worktrees under its own tree keep resolving to the main
# tree (rows b and c), and a worktree outside stays on case 10's main tree.
if command -v git >/dev/null 2>&1 && [[ -d "$NESTED/.git" ]]; then
  IWT="$WS/_tmp/wt/inside"
  mkdir -p "$WS/_tmp/wt"
  ( cd "$NESTED" && git worktree add -q "$IWT" -b inside ) >/dev/null 2>&1
  if [[ -d "$IWT" ]]; then
    mkdir -p "$IWT/sub"
    for c in "$IWT" "$IWT/sub"; do
      got="$(run "$c" "$FAKEHOME")"
      [[ "$got" == "$IWT" ]] || fail "from '$c' (a worktree inside the workspace), expected the worktree root '$IWT', got '$got' — a script would write into the workspace's live .context/"
      parity "$c" "$FAKEHOME"
    done
    # (b) the nested repo's main checkout still resolves to the workspace.
    got="$(run "$NESTED" "$FAKEHOME")"
    [[ "$got" == "$WS" ]] || fail "the nested repo's main checkout must still resolve to the workspace '$WS', got '$got'"
    parity "$NESTED" "$FAKEHOME"
  else
    echo "skip: git worktree add unavailable — case 11 not exercised"
  fi
  # (c) a project whose main tree HAS .context/ keeps owning a worktree made under it.
  CWT="$WMAIN/_tmp/wt/under"
  mkdir -p "$WMAIN/_tmp/wt"
  ( cd "$WMAIN" && git worktree add -q "$CWT" -b under ) >/dev/null 2>&1
  if [[ -d "$CWT" ]]; then
    got="$(run "$CWT" "$FAKEHOME")"
    [[ "$got" == "$WMAIN" ]] || fail "a worktree under its own main tree must resolve to the main tree '$WMAIN', got '$got'"
    parity "$CWT" "$FAKEHOME"
  else
    echo "skip: git worktree add unavailable — case 11 row c not exercised"
  fi
  # (d) a worktree DEST container that carries .context/ on purpose (a WT_LINKS
  # symlink to the workspace's .context/, or a root-participant checkout's own) owns
  # the participant worktrees inside it: the participant's main tree lies OUTSIDE the
  # container, so this is not the nested-workspace shape and must not resolve to the
  # sub-repo checkout. Both variants: a real .context/ dir and a symlink.
  for variant in dir link; do
    C="$FAKEHOME/projects/ws-wt-$variant"
    mkdir -p "$C"
    if [[ "$variant" == dir ]]; then mkdir -p "$C/.context"; else ln -s "$WS/.context" "$C/.context"; fi
    ( cd "$NESTED" && git worktree add -q "$C/proj" -b "rowd-$variant" ) >/dev/null 2>&1
    if [[ -d "$C/proj" ]]; then
      got="$(run "$C/proj" "$FAKEHOME")"
      [[ "$got" == "$C" ]] || fail "from a participant worktree '$C/proj' inside a container whose .context/ is a $variant, expected the container '$C', got '$got'"
      parity "$C/proj" "$FAKEHOME"
    else
      echo "skip: git worktree add unavailable — case 11 row d ($variant) not exercised"
    fi
  done
  # (e) the .context/ found must hold the WORKTREE too, not only the main tree: a main
  # tree moved inside its own worktree, below a .context/ (W/a/.context, W/a/main),
  # keeps W/a as the root; it is not the nested shape, so W must not answer.
  E="$FAKEHOME/projects/rowe"
  mkdir -p "$E"
  ( git init -q "$E/main" && git -C "$E/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i \
      && git -C "$E/main" worktree add -q "$E/W" -b rowe && mkdir -p "$E/W/a/.context" \
      && mv "$E/main" "$E/W/a/main" && git -C "$E/W/a/main" worktree repair ) >/dev/null 2>&1
  if [[ -d "$E/W/a/main/.git" && -f "$E/W/.git" ]]; then
    got="$(run "$E/W/a" "$FAKEHOME")"
    [[ "$got" == "$E/W/a" ]] || fail "with the main tree inside its own worktree, expected the nearest .context/ '$E/W/a', got '$got'"
    parity "$E/W/a" "$FAKEHOME"
  else
    echo "skip: worktree repair unavailable — case 11 row e not exercised"
  fi
else
  echo "skip: git not on PATH — case 11 not exercised"
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
    [[ "$hit" == */conventions/scripts/_lib.sh ]] && continue
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
