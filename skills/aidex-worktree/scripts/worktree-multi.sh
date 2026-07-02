#!/usr/bin/env bash
# worktree-multi.sh — Tier-1 worktree creation/removal for MULTI-REPO (split-git)
# workspaces: one git worktree per touched participant + symlinks for the
# unversioned root wrapper files (compose file, dev scripts) that a code-only
# worktree of a single participant would otherwise lack.
#
# Stack-agnostic by construction: participants and wrapper files come from the
# ARGUMENTS (i.e. from the project's own .context/worktrees/00-index.md Procedure
# section) — nothing project-specific is hardcoded here. Single-repo projects
# don't need this script (native EnterWorktree / git worktree add covers them).
#
# Usage:
#   worktree-multi.sh create --slug <slug> --branch <branch> \
#       --repo <path> [--repo <path> ...] [--link <file> ...] [--dest <dir>]
#   worktree-multi.sh remove --slug <slug> [--dest <dir>]
#
#   create: for each --repo (relative to the workspace root = cwd), adds a git
#           worktree at <dest>/<repo-basename> on <branch> (creates the branch if
#           it does not exist). Each --link <file> becomes a symlink
#           <dest>/<file> -> <root>/<file>. Refuses an existing <dest>.
#   remove: for each worktree inside <dest>, runs `git worktree remove` (which
#           REFUSES dirty trees — commit or stash first; this script never
#           discards work), then removes the wrapper symlinks and <dest> itself.
#
#   --dest default: ../<root-basename>-wt-<slug> (a sibling of the workspace root).

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

usage() {
  sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

cmd="${1:-}"; shift || true
[[ "$cmd" == "create" || "$cmd" == "remove" ]] || usage

SLUG="" BRANCH="" DEST=""
REPOS=()
LINKS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)   SLUG="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --repo)   REPOS+=("$2"); shift 2 ;;
    --link)   LINKS+=("$2"); shift 2 ;;
    --dest)   DEST="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$SLUG" ]] || die "--slug is required"
is_valid_slug "$SLUG" || die "invalid slug: $SLUG (kebab-case, [a-z0-9-])"

ROOT="$(pwd -P)"
[[ -n "$DEST" ]] || DEST="$ROOT/../$(basename "$ROOT")-wt-$SLUG"

if [[ "$cmd" == "create" ]]; then
  [[ -n "$BRANCH" ]] || die "create requires --branch"
  [[ "${#REPOS[@]}" -gt 0 ]] || die "create requires at least one --repo"
  [[ -e "$DEST" ]] && die "destination already exists: $DEST (remove it first, or pick another --slug)"

  # Validate every participant BEFORE mutating anything.
  for r in "${REPOS[@]}"; do
    [[ -d "$ROOT/$r" ]] || die "participant not found: $r (relative to $ROOT)"
    git -C "$ROOT/$r" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $r"
  done
  for l in "${LINKS[@]:-}"; do
    [[ -z "$l" ]] && continue
    [[ -e "$ROOT/$l" ]] || die "wrapper file to link not found: $l (relative to $ROOT)"
  done

  mkdir -p "$DEST"
  for r in "${REPOS[@]}"; do
    name="$(basename "$r")"
    if git -C "$ROOT/$r" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git -C "$ROOT/$r" worktree add "$DEST/$name" "$BRANCH" >/dev/null
    else
      git -C "$ROOT/$r" worktree add -b "$BRANCH" "$DEST/$name" >/dev/null
    fi
    ok "worktree: $name -> $DEST/$name (branch $BRANCH)"
  done
  for l in "${LINKS[@]:-}"; do
    [[ -z "$l" ]] && continue
    ln -s "$ROOT/$l" "$DEST/$(basename "$l")"
    ok "link: $(basename "$l") -> $ROOT/$l"
  done
  printf '%s\n' "$DEST"
  exit 0
fi

# --- remove ---
[[ -d "$DEST" ]] || die "destination not found: $DEST"

removed=0
for sub in "$DEST"/*/; do
  [[ -d "$sub" ]] || continue
  sub="${sub%/}"
  # A linked worktree has a .git FILE pointing back to the main repo.
  [[ -f "$sub/.git" ]] || continue
  common="$(git -C "$sub" rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$common" ]] || { warn "skipping $sub — cannot resolve its main repo"; continue; }
  main_tree="$(dirname "$common")"
  # git refuses to remove a dirty worktree — that protection is the point.
  git -C "$main_tree" worktree remove "$sub"
  ok "removed worktree: $sub"
  removed=$((removed + 1))
done
[[ "$removed" -gt 0 ]] || warn "no worktrees found inside $DEST"

# Wrapper symlinks (top-level only), then the dir itself if empty.
find "$DEST" -maxdepth 1 -type l -exec rm -f {} +
rmdir "$DEST" 2>/dev/null || warn "$DEST not empty after removal — inspect it manually (never force-deleted)"
exit 0
