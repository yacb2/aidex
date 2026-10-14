#!/usr/bin/env bash
# wt-config.sh — sourced, never run. Reads ONE declarative field of a project's
# .context/worktrees/config.env without sourcing it (the file is not vetted by the
# checkers that read it). Shared by check-worktree-ports.sh, check-worktree-runner.sh
# and check-worktree-isolation.sh so the three cannot read a field differently.
# worktree.sh keeps its own WT_PROFILE peek: it must accept only a profile NAME.

# wt_cfg_field <config.env> <VAR> — the value of the first `VAR=...` line, up to the
# first quote; a single optional opening quote is dropped. Empty when absent.
wt_cfg_field() {
  sed -n "s/^[[:space:]]*$2=[\"']\{0,1\}\([^\"']*\).*/\1/p" "$1" | sed -n 1p
}
