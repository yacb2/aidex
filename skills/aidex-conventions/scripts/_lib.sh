#!/usr/bin/env bash
# Shared generic helpers for aidex skill scripts.
# Source: . "$(dirname "$0")/../../aidex-conventions/scripts/_lib.sh"
#
# Note: does NOT compute SKILL_DIR/TEMPLATES_DIR — ${BASH_SOURCE[0]} inside a
# sourced file resolves to this file's own path, not the caller's. Each
# sourcing script must compute its own SKILL_DIR/TEMPLATES_DIR before/after
# sourcing this file.

set -euo pipefail

# Colors for humans (no-op if NO_COLOR set or not a TTY).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_BOLD='' C_RESET=''
fi

log()   { printf '%s\n' "$*" >&2; }
info()  { printf '%s%s%s\n' "$C_BLUE"   "$*" "$C_RESET" >&2; }
ok()    { printf '%s%s%s\n' "$C_GREEN"  "$*" "$C_RESET" >&2; }
warn()  { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
err()   { printf '%s%s%s\n' "$C_RED"    "$*" "$C_RESET" >&2; }
die()   { err "error: $*"; exit 2; }

# Project root — walk up until we find .context/ or hit /
# find_project_root — the directory aidex artifacts belong to.
#
# The upward walk STOPS AT $HOME, exclusive. Without that boundary a single
# stray `~/.context/` captures every project that has not been initialised yet
# — precisely the first-run case every creator script is for — and the walk
# silently resolves the project root to $HOME. Field-observed 2026-07-25: a
# fresh project made `orphan-sweep` scan for `yoelacevedo-wt-*` (reporting a
# clean workspace it was not looking at), made `detect-topology` report the home
# directory's contents, and would have written a project's worktree overview to
# `~/.context/worktrees/00-index.md`. 33 scripts across every skill call this.
#
# Two passes, both innermost-first: an existing `.context/` always wins, and
# only when there is none does a project marker (`.git`, `CLAUDE.md`) stand in —
# so an initialised project's resolution is exactly what it always was.
# NOTE: nearest-ancestor by design — an artifact belongs to the project whose
# .context/ contains it. hooks/durability-run.sh deliberately uses the OUTERMOST
# .context instead (one run marker per workspace, BL-075); do not "align" them.
find_project_root() {
  local start stop dir
  start="$(pwd -P)"
  stop="${HOME:-}"

  dir="$start"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    [[ -n "$stop" && "$dir" == "$stop" ]] && break
    if [[ -d "$dir/.context" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  # Still nothing — but a LINKED WORKTREE is a sibling of the project, never a
  # descendant, so the walk above could not have reached the main tree's
  # `.context/`. Hop to the main worktree and walk again from there.
  #
  # Without this the next pass matched the worktree's own `.git` — a FILE in a
  # linked worktree, which `-e` accepts — and returned the worktree as the
  # project root. Everything then wrote into a directory that disappears on
  # teardown, and `worktree.sh` in particular reads
  # "$ROOT/.context/worktrees/config.env", which does not exist at that root.
  # Nine aidex-worktree scripts source this file, and they are most often invoked
  # from inside a worktree, so this is the common case rather than an edge one.
  #
  # `--git-common-dir` differs from `--git-dir` only inside a linked worktree, so
  # a normal checkout takes no new behaviour from this block. Resolution failure
  # is not an error: fall through to the marker pass exactly as before.
  local common gitdir mainroot
  if common="$(git rev-parse --git-common-dir 2>/dev/null)" \
     && gitdir="$(git rev-parse --git-dir 2>/dev/null)" \
     && [[ -n "$common" && "$common" != "$gitdir" ]]; then
    mainroot="$(cd "$(dirname "$common")" 2>/dev/null && pwd -P)" || mainroot=""
    dir="$mainroot"
    while [[ -n "$dir" && "$dir" != "/" ]]; do
      [[ -n "$stop" && "$dir" == "$stop" ]] && break
      if [[ -d "$dir/.context" ]]; then
        printf '%s\n' "$dir"
        return 0
      fi
      dir="$(dirname "$dir")"
    done
  fi

  # No .context yet — fall back to the nearest thing that looks like a project
  # root, so a not-yet-initialised project still gets its own directory rather
  # than an ancestor's.
  dir="$start"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    [[ -n "$stop" && "$dir" == "$stop" ]] && break
    if [[ -e "$dir/.git" || -f "$dir/CLAUDE.md" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  # Fallback: current directory (will create .context if needed)
  printf '%s\n' "$start"
}

today() { date +%Y%m%d; }
today_iso() { date +%Y-%m-%d; }

# Render a template: substitute {{KEY}} placeholders with provided values.
# Usage: render_template <template-path> <output-path> KEY1=val1 KEY2=val2 ...
render_template() {
  local template="$1"; shift
  local out="$1"; shift
  [[ -f "$template" ]] || die "template not found: $template"
  [[ -e "$out" ]] && die "refusing to overwrite existing file: $out"

  local content
  content="$(cat "$template")"

  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    # Escape for sed: use | as delimiter; escape | & \ in val
    val="${val//\\/\\\\}"
    val="${val//|/\\|}"
    val="${val//&/\\&}"
    content="$(printf '%s' "$content" | sed "s|{{$key}}|$val|g")"
  done

  printf '%s' "$content" > "$out"
}

# kebab-case validator
is_valid_slug() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# Make a kebab-case slug from arbitrary text: lowercase, non-alnum -> hyphen,
# collapse repeats, trim leading/trailing hyphens. Empty input -> empty output.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Compute the relative path from a base file's directory to a target file.
# Usage: relpath_from <target> <base-file>
relpath_from() {
  python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], start=os.path.dirname(sys.argv[2])))" "$1" "$2" 2>/dev/null || printf '%s\n' "$1"
}
