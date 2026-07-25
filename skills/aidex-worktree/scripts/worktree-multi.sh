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
#   worktree-multi.sh remove --slug <slug> [--dest <dir>] [--skip-teardown]
#
#   create: for each --repo (relative to the workspace root = cwd), adds a git
#           worktree at <dest>/<repo-basename> on <branch> (creates the branch if
#           it does not exist). Each --link <file> becomes a symlink
#           <dest>/<file> -> <root>/<file>. Refuses an existing <dest>.
#   remove: tears the worktree's Docker stack down FIRST (see below), then for
#           each worktree inside <dest> runs `git worktree remove` (which
#           REFUSES dirty trees — commit or stash first; this script never
#           discards work), then removes the wrapper symlinks and <dest> itself.
#
#   --dest default: ../<root-basename>-wt-<slug> (a sibling of the workspace root).
#   --skip-teardown: remove the directory without touching Docker. Only correct
#           when the stack is already down; otherwise it strands the stack, and
#           once <dest> is gone nothing can attribute those resources to a
#           worktree again — that is exactly how orphaned networks and tens of
#           GB of untagged images accumulate.
#
# TEARDOWN COUPLING (remove)
#   Removing the directory and tearing down the stack were once two independent
#   steps, the second merely *printed* as a suggestion. Skipping it left Docker
#   resources with no directory left to attribute them to. `remove` now:
#     1. runs the attribution pre-flight (orphan-sweep.sh --slug <slug>) to
#        enumerate every resource carrying THIS worktree's project name;
#     2. if none exist, proceeds straight to the git removal;
#     3. otherwise resolves `worktree_down` from the project's
#        .context/worktrees/00-index.md front-matter, substitutes <slug>, prints
#        the exact command, and runs it;
#     4. re-runs the pre-flight and reports whatever survived (residue is
#        reported, never force-removed — "dangling is not disposable").
#   Nothing outside the `<project>-wt-<slug>` namespace is ever considered: the
#   pre-flight matches resource names anchored at that prefix, so a teardown can
#   only ever reach the worktree it was invoked for.
#   No `worktree_down` recorded (Tier 1, or Tier 2 not yet available) and
#   resources exist anyway → refuse rather than invent a teardown.

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

usage() {
  # Print the whole leading comment block, whatever its length — a hardcoded
  # line range silently truncates the moment the header grows.
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

cmd="${1:-}"; shift || true
[[ "$cmd" == "create" || "$cmd" == "remove" ]] || usage

SLUG="" BRANCH="" DEST=""
SKIP_TEARDOWN=false
FORCE_RM=false
REPOS=()
LINKS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)   SLUG="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --repo)   REPOS+=("$2"); shift 2 ;;
    --link)   LINKS+=("$2"); shift 2 ;;
    --dest)   DEST="$2"; shift 2 ;;
    --skip-teardown) SKIP_TEARDOWN=true; shift ;;
    --force) FORCE_RM=true; shift ;;
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
    # Mirror the RELATIVE path, not just the basename. `--link backend/.env`
    # used to land as <dest>/.env, so compose looked for <dest>/backend/.env,
    # found nothing, and the stack refused to start with an error that named
    # the file but not the reason.
    mkdir -p "$(dirname "$DEST/$l")"
    ln -s "$ROOT/$l" "$DEST/$l"
    ok "link: $l -> $ROOT/$l"
  done
  printf '%s\n' "$DEST"
  exit 0
fi

# --- remove ---
[[ -d "$DEST" ]] || die "destination not found: $DEST"

# --- teardown the Docker stack BEFORE the directory disappears ---
#
# Order is load-bearing. Once <dest> is gone the worktree is unattributable:
# orphan-sweep can still see the resources but can no longer tell a live
# worktree from a dead one, so they sit forever. Tear down first, remove second.
SWEEP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/orphan-sweep.sh"

if $SKIP_TEARDOWN; then
  warn "--skip-teardown: leaving Docker resources for $(basename "$ROOT")-wt-$SLUG untouched"
else
  # Pre-flight: what, exactly, belongs to THIS worktree? Exit 1 means "resources
  # exist" — the enumeration itself is the guard the user reads before anything
  # is removed. Everything listed is name-anchored at <project>-wt-<slug>, so
  # nothing unrelated can appear in it.
  # `&&/||` keeps errexit from aborting on the intentional non-zero exit that
  # means "resources exist" — a bare assignment would kill the script here.
  preflight="$(bash "$SWEEP" --slug "$SLUG" 2>&1)" && had_resources=0 || had_resources=$?

  if [[ "$had_resources" -eq 0 ]]; then
    info "no Docker resources attributable to this worktree — nothing to tear down"
  else
    printf '%s\n' "$preflight"

    # The teardown recipe is the project's own, read from its recorded
    # front-matter. Never improvise one: a hand-rolled `compose down` here would
    # not know the project's volume names, port slots or seeding.
    DOC="$ROOT/.context/worktrees/00-index.md"
    WT_DOWN=""
    if [[ -f "$DOC" ]]; then
      WT_DOWN="$(sed -n '/^---$/,/^---$/p' "$DOC" | sed -n 's/^worktree_down: *//p' | head -1)"
      WT_DOWN="${WT_DOWN%\"}"; WT_DOWN="${WT_DOWN#\"}"
    fi

    if [[ -z "$WT_DOWN" ]]; then
      err "Docker resources exist for $(basename "$ROOT")-wt-$SLUG but the project records no 'worktree_down'."
      err "Refusing to invent a teardown. Either:"
      err "  - record worktree_down in $DOC (see /aidex-worktree bootstrap, Axis 4), or"
      err "  - reclaim the resources with the commands listed above, then re-run with --skip-teardown"
      exit 1
    fi

    # `<slug>` is the documented placeholder in the recorded command.
    TEARDOWN="${WT_DOWN//<slug>/$SLUG}"
    info "[teardown] $TEARDOWN"
    ( cd "$ROOT" && eval "$TEARDOWN" ) || die "teardown failed — the worktree directory was NOT removed; fix the stack and re-run"

    # Residue check. `compose down --rmi local` cannot reclaim untagged build
    # layers, and leaves a network behind if another stack was attached to it,
    # so a clean-exiting teardown is not proof of a clean namespace.
    if residue="$(bash "$SWEEP" --slug "$SLUG" 2>&1)"; then
      ok "teardown complete — no residue for this worktree"
    else
      warn "teardown left residue attributable to this worktree:"
      printf '%s\n' "$residue"
      warn "reclaim it with the commands above (report-only: nothing was force-removed)"
    fi
  fi
fi

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
  # --force overrides it and DISCARDS the work; it exists only so a caller can
  # offer that choice explicitly, never as a fallback when removal fails.
  if $FORCE_RM; then
    warn "--force: discarding any uncommitted work in $sub"
    git -C "$main_tree" worktree remove --force "$sub"
  else
    git -C "$main_tree" worktree remove "$sub"
  fi
  ok "removed worktree: $sub"
  removed=$((removed + 1))
done
[[ "$removed" -gt 0 ]] || warn "no worktrees found inside $DEST"

# Wrapper symlinks (at any depth — --link mirrors relative paths) and the
# markers this tooling wrote itself. Anything else is the user's, and a
# non-empty directory is reported as a FAILURE rather than shrugged off: the
# previous version warned and still exited 0, so a caller printed "removed"
# over a directory that was still there.
find "$DEST" -type l -delete 2>/dev/null
rm -f "$DEST/.wt-slot"
find "$DEST" -type d -empty -delete 2>/dev/null
if [[ -d "$DEST" ]]; then
  err "$DEST still exists after removal — it holds files this tool did not create:"
  find "$DEST" -mindepth 1 -maxdepth 2 | sed 's|^|    |' >&2
  err "inspect and remove it yourself (never force-deleted)"
  exit 1
fi
ok "removed $DEST"
exit 0
