#!/usr/bin/env bash
# wt-config.sh — sourced, never run. Reads ONE declarative field of a project's
# .context/worktrees/config.env without sourcing it (the file is not vetted by the
# checkers that read it). Shared by check-worktree-ports.sh, check-worktree-runner.sh
# and check-worktree-isolation.sh so the three cannot read a field, or pick the
# file, differently. wt_parent_* (WT_PARENT) also serve worktree.sh and the sweeps.
# worktree.sh keeps its own WT_PROFILE peek: it must accept only a profile NAME.

# wt_cfg_field <config.env> <VAR> — the value of the first `VAR=...` line, up to the
# first quote; a single optional opening quote is dropped. Empty when absent.
wt_cfg_field() {
  sed -n "s/^[[:space:]]*$2=[\"']\{0,1\}\([^\"']*\).*/\1/p" "$1" | sed -n 1p
}

# wt_cfg_path <root> — the config.env that governs <root>. Its own when present;
# otherwise, when <root> is a LINKED git worktree, the main worktree's (BL-814:
# in a split workspace `.context/` is tracked but config.env is not, so a
# worktree has the directory and lacks the file, and find_project_root stops at
# the worktree). Same linked-worktree test as find_project_root: the absolute
# common dir differs from the absolute git dir only there. When neither exists
# the root's own path is printed, so a "no worktree config at" error names it.
wt_cfg_path() {
  local own="$1/.context/worktrees/config.env" common gitdir main
  if [[ ! -f "$own" ]] \
     && common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
     && gitdir="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" \
     && [[ -n "$common" && "$common" != "$gitdir" ]]; then
    main="$(dirname "$common")/.context/worktrees/config.env"
    [[ -f "$main" ]] && { printf '%s\n' "$main"; return 0; }
  fi
  printf '%s\n' "$own"
}

# wt_parent_resolve <root> <value> — the directory <root>'s worktrees live in, from a
# WT_PARENT value: relative to <root>, or absolute; empty means beside <root>.
# Resolved with pwd -P when it exists; textual otherwise (`new` has not made it yet).
wt_parent_resolve() {
  local d
  case "$2" in "") d="$1/.." ;; /*) d="$2" ;; *) d="$1/$2" ;; esac
  if [[ -d "$d" ]]; then (cd "$d" && pwd -P); else printf '%s\n' "$d"; fi
}

# wt_parent_of <root> — wt_parent_resolve with WT_PARENT read from <root>'s config.env
# (wt_cfg_path), for the sweeps that read the file without sourcing it.
wt_parent_of() {
  local cfg p=""
  cfg="$(wt_cfg_path "$1")"
  [[ -f "$cfg" ]] && p="$(wt_cfg_field "$cfg" WT_PARENT)"
  wt_parent_resolve "$1" "$p"
}
