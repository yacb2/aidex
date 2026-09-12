#!/usr/bin/env bash
# resolve-review-scope.sh — resolve a review scope name to a concrete git base ref.
#
# Why this exists: the installed review instruments hard-code their own scope and
# cannot be repointed. `/security-review` interpolates `git diff origin/HEAD...`
# at invocation time; on a repo whose work lands directly on the default branch
# and is then pushed, that resolves to ZERO files while the working tree is dirty
# — a review that reports "no findings" without having read anything. Measured in
# the aidex repo on 2026-07-27: `git diff --name-only origin/HEAD...` returned 0
# paths with 1 dirty path in `git status --short`.
#
# This resolver is the single place that answers "what am I reviewing?", and it
# NEVER returns a silently-empty anchor: every resolution reports the anchor it
# actually used, and a genuinely empty scope exits 3 instead of printing nothing.
# The caller must be able to tell "nothing changed" apart from "wrong base ref".
#
# Usage:
#   resolve-review-scope.sh <scope> [target]        # print key=value resolution
#   resolve-review-scope.sh --files <scope> [target] # print the resolved file list
#
# Scopes (the closed enum — see references/review-scope-conventions.md):
#   working-diff         uncommitted tracked changes vs HEAD
#   branch-vs-main       this branch's cumulative work vs the default branch
#   worktree-cumulative  a linked worktree's cumulative work vs its fork point
#   module-path <path>   changes under <path>, over the widest non-empty base
#
# A base ref is a PARAMETER, not an enum member: `--base <ref>` overrides the
# resolved base for any scope, so callers that want "the diff of this phase" or
# "since the last commit" express it as a preset over this resolver rather than
# as a new scope that every consumer would have to learn.
#
# Output (stdout, one key=value per line):
#   scope=<name>
#   base=<rev>        git rev-spec to diff against; `-` means "working tree vs HEAD"
#   anchor=<how>      merge-base | default-branch | head | last-commit | explicit
#   pathspec=<path>   empty unless the scope narrows to a path
#
# Exit codes: 0 resolved · 2 usage error · 3 scope resolved but empty

set -uo pipefail

SCOPES="working-diff branch-vs-main worktree-cumulative module-path"

die() { printf 'resolve-review-scope: %s\n' "$*" >&2; exit 2; }

files_mode=0
base_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --files) files_mode=1; shift ;;
    --base)  [ $# -ge 2 ] || die "--base needs a ref"; base_override="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*) die "unknown option: $1" ;;
    *) break ;;
  esac
done

[ $# -ge 1 ] || die "usage: resolve-review-scope.sh [--files] [--base <ref>] <scope> [target]"
scope="$1"; shift
target="${1:-}"

case " $SCOPES " in
  *" $scope "*) ;;
  *) die "unknown scope: $scope (expected one of: $SCOPES)" ;;
esac

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"

# --- helpers ---------------------------------------------------------------

# Files changed for a base. `-` means working tree vs HEAD.
changed_files() { # base [pathspec]
  local base="$1" ps="${2:-}"
  if [ "$base" = "-" ]; then
    if [ -n "$ps" ]; then git diff --name-only HEAD -- "$ps" 2>/dev/null
    else git diff --name-only HEAD 2>/dev/null; fi
  else
    if [ -n "$ps" ]; then git diff --name-only "$base" -- "$ps" 2>/dev/null
    else git diff --name-only "$base" 2>/dev/null; fi
  fi
}

nonempty() { [ -n "$(changed_files "$1" "${2:-}")" ]; }

# The repo's default branch, without assuming a remote exists.
default_branch() {
  local d
  d=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) && {
    printf '%s\n' "${d#origin/}"; return 0; }
  for c in main master; do
    git show-ref --verify --quiet "refs/heads/$c" && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# Cumulative base for a branch: the merge-base with the default branch.
# Falls through when HEAD *is* the default branch (merge-base == HEAD, so the
# diff would be empty) — that degenerate case is the whole reason this exists.
resolve_cumulative() { # -> sets base/anchor
  local db mb
  if db=$(default_branch); then
    if mb=$(git merge-base HEAD "$db" 2>/dev/null) && [ -n "$mb" ]; then
      if [ "$mb" != "$(git rev-parse HEAD)" ] && nonempty "$mb" "$pathspec"; then
        base="$mb"; anchor="merge-base"; return 0
      fi
    fi
  fi
  # On the default branch (or no divergence): the real work is uncommitted, or
  # else it is the last commit. Never report the empty merge-base as the answer.
  if nonempty "-" "$pathspec"; then
    base="-"; anchor="head"; return 0
  fi
  if git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1 && nonempty "HEAD~1" "$pathspec"; then
    base="HEAD~1"; anchor="last-commit"; return 0
  fi
  base="-"; anchor="head"; return 1
}

# --- resolution ------------------------------------------------------------

base=""; anchor=""; pathspec=""; empty=0

case "$scope" in
  working-diff)
    base="-"; anchor="head"
    ;;
  branch-vs-main)
    resolve_cumulative || empty=1
    ;;
  worktree-cumulative)
    # A linked worktree forks from wherever it was created; that is the same
    # merge-base question, so it shares the resolver rather than duplicating it.
    resolve_cumulative || empty=1
    ;;
  module-path)
    [ -n "$target" ] || die "module-path needs a <path> argument"
    [ -e "$target" ] || die "module-path target does not exist: $target"
    pathspec="$target"
    resolve_cumulative || empty=1
    ;;
esac

if [ -n "$base_override" ]; then
  git rev-parse --verify --quiet "$base_override" >/dev/null 2>&1 \
    || die "--base ref does not resolve: $base_override"
  base="$base_override"; anchor="explicit"
  nonempty "$base" "$pathspec" && empty=0 || empty=1
fi

[ "$empty" -eq 1 ] || nonempty "$base" "$pathspec" || empty=1

if [ "$files_mode" -eq 1 ]; then
  changed_files "$base" "$pathspec"
else
  printf 'scope=%s\nbase=%s\nanchor=%s\npathspec=%s\n' \
    "$scope" "$base" "$anchor" "$pathspec"
fi

[ "$empty" -eq 1 ] && exit 3
exit 0
