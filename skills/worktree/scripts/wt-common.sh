#!/usr/bin/env bash
# wt-common.sh — sourced, never run. Two helpers shared across the scripts here.
# Callers keep their own `exit`.

# wt_usage <script> — used by worktree.sh, worktree-multi.sh, docker-snapshot.sh,
# orphan-sweep.sh, check-overview.sh and the four check-*.sh scripts (check-compose-isolation,
# check-worktree-isolation, check-worktree-ports, check-worktree-runner). Print <script>'s leading comment block (its usage), whatever
# its length: a hardcoded line range truncates the moment the header grows. The
# caller passes its own "${BASH_SOURCE[0]}": inside this file that name is ours.
wt_usage() { usage_from_header "$1"; }   # usage_from_header: conventions/scripts/_lib.sh, sourced first by every caller

# wt_default_start <root> <repo> — used by worktree.sh and worktree-multi.sh. The
# repo's default branch as a start point: origin/HEAD's name, else main, else master, LOCAL first (owner repos run ahead of
# origin, and an origin/* start point would also set upstream tracking). Prints
# nothing and fails when none exists. worktree.sh's `base ...` report and
# worktree-multi.sh's fork both use it, so the report names what multi forks from
# (worktree-c22). `|| true` on the origin/HEAD read: worktree-multi.sh runs under
# `set -e -o pipefail`, and a repo with no origin/HEAD is the normal case.
wt_default_start() {
  local _oh _c _cand
  _oh="$(git -C "$1/$2" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  for _c in $_oh main master; do
    for _cand in "$_c" "origin/$_c"; do
      git -C "$1/$2" rev-parse --verify --quiet "$_cand^{commit}" >/dev/null && { printf '%s' "$_cand"; return 0; }
    done
  done
  return 1
}
