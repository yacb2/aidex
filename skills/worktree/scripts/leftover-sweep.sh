#!/usr/bin/env bash
# leftover-sweep.sh — clean up what a worktree removal leaves on disk, scoped to the
# wrappers `<workspace>-wt-*` next to the workspace root:
#   - drops worktree records git marks `prunable` whose path is under such a wrapper
#     (just those records, never a repo-wide prune); other prunable records are only listed
#   - removes wrappers holding no non-directory entry at any depth (.DS_Store is noise)
#     and no registered worktree: rmdir only, deepest first, never rm -rf
#   - reports (never removes) wrappers with content that no repo registers
# Repos: the workspace root when it is a git repo, plus each immediate child that is.
# The workspace root is the `<base>` next to the `<base>-wt-<slug>` the caller stands in,
# else find_project_root. No `.context/worktrees/config.env` there: nothing is touched.
# Usage: leftover-sweep.sh [--root <workspace-dir>]
# Always exits 0 unless the arguments are wrong.

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

# wrapper_base_root — when cwd is inside <parent>/<base>-wt-<slug>/..., print <parent>/<base>
wrapper_base_root() {
  local dir name base
  dir="$(pwd -P)"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    name="$(basename "$dir")"
    case "$name" in
      *-wt-*)
        base="${name%%-wt-*}"
        if [ -n "$base" ] && [ -d "$(dirname "$dir")/$base" ]; then
          printf '%s\n' "$(dirname "$dir")/$base"; return 0
        fi ;;
    esac
    dir="$(dirname "$dir")"
  done
  return 1
}

WS_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) WS_ROOT="${2:?--root needs a value}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$WS_ROOT" ] || WS_ROOT="$(wrapper_base_root || find_project_root)"
WS_ROOT="$(cd "$WS_ROOT" && pwd -P)"
WS_NAME="$(basename "$WS_ROOT")"
WS_PARENT="$(dirname "$WS_ROOT")"
WRAP="$WS_PARENT/$WS_NAME-wt-"

if [ ! -f "$WS_ROOT/.context/worktrees/config.env" ]; then
  echo "no worktree config at $WS_ROOT; leftover sweep skipped"
  exit 0
fi

found=0
repos=()
candidates=()
[ -e "$WS_ROOT/.git" ] && candidates+=("$WS_ROOT")
for d in "$WS_ROOT"/*/; do
  [ -e "${d}.git" ] && candidates+=("${d%/}")
done
for r in ${candidates[@]+"${candidates[@]}"}; do
  if git -C "$r" rev-parse --git-dir >/dev/null 2>&1; then
    repos+=("$r")
  else
    found=1
    echo "broken git repo (skipped): $r"
  fi
done

# abs_path PATH BASE — PATH made absolute against BASE, "." and ".." collapsed textually
# (the target may be gone); a gitdir is relative under worktree.useRelativePaths
abs_path() {
  local p="$1" out="" seg
  case "$p" in /*) ;; *) p="$2/$p" ;; esac
  local IFS=/
  for seg in $p; do
    case "$seg" in
      ""|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
  done
  printf '%s\n' "$out"
}

# 1. drop prunable records under the wrappers; list the others
for r in ${repos[@]+"${repos[@]}"}; do
  listing="$(git -C "$r" worktree list --porcelain 2>/dev/null || true)"
  [[ "$listing" == *$'\nprunable'* ]] || continue
  common="$(cd "$r" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  cur=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) cur="${line#worktree }" ;;
      prunable*)
        found=1
        matched=0
        case "$cur" in
          "$WRAP"*)
            for a in "$common"/worktrees/*/; do
              [ -f "${a}gitdir" ] && [ ! -e "${a}locked" ] || continue
              if [ "$(abs_path "$(cat "${a}gitdir")" "${a%/}")" = "$cur/.git" ]; then
                rm -rf "${a%/}"
                echo "pruned dead worktree record: $cur (repo $r)"
                matched=1
                break
              fi
            done
            [ "$matched" -eq 1 ] || echo "prunable record not matched (left alone): $cur" ;;
          *) echo "prunable record outside the workspace wrappers (left alone): $cur" ;;
        esac ;;
    esac
  done <<EOF2
$listing
EOF2
done

# 2. registered worktree paths (after pruning), one per line
registered=""
for r in ${repos[@]+"${repos[@]}"}; do
  registered="$registered$(git -C "$r" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' || true)
"
done

# is_registered DIR — DIR is, or contains, a registered worktree
is_registered() {
  local p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in "$1"|"$1"/*) return 0 ;; esac
  done <<EOF2
$registered
EOF2
  return 1
}

# 3. wrappers
for c in "$WRAP"*; do
  [ -d "$c" ] && [ ! -L "$c" ] || continue
  c="$(cd "$c" && pwd -P)"
  is_registered "$c" && continue
  if [ -z "$(find "$c" ! -type d ! -name .DS_Store -print -quit)" ]; then
    find "$c" -type f -name .DS_Store -exec rm -f {} \;
    find "$c" -depth -type d -exec rmdir {} \; 2>/dev/null || true
    if [ ! -e "$c" ]; then
      found=1
      echo "removed empty leftover: $c"
      continue
    fi
  fi
  found=1
  echo "LEFTOVER (not empty, ask the owner): $c ($(du -sh "$c" | cut -f1))"
  echo "  entries: $(ls -A "$c" | tr '\n' ' ')"
done

[ "$found" -eq 1 ] || echo "no worktree leftovers"
exit 0
