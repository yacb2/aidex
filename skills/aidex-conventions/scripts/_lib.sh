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
  # Resolve $HOME the same way `start` is resolved, or the boundary silently does
  # not exist: the walk compares `pwd -P` output against `$HOME` verbatim, so a
  # home directory reached through a symlink never matched and the walk continued
  # past it into a stray `~/.context/` — the failure this boundary was added for.
  # macOS /var -> /private/var makes that the default shape for any temp dir, and
  # a home on a symlinked volume has it too.
  stop="${HOME:-}"
  [[ -n "$stop" && -d "$stop" ]] && stop="$(cd "$stop" 2>/dev/null && pwd -P)"

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
  # Eight aidex-worktree scripts source this file, and they are most often
  # invoked from inside a worktree, so this is the common case, not an edge one.
  #
  # BOTH paths are asked for in absolute form. `--git-common-dir` answers
  # relatively from the repo root (".git") while `--git-dir` answers absolutely,
  # so the plain forms differ in an ordinary checkout too — the test would have
  # been true everywhere, and `dirname` of a relative ".git" would then have
  # walked from the wrong place. Asked absolutely, they differ only inside a
  # linked worktree, which is what this block is for.
  #
  # Out of reach by construction, and fine: a non-git multi-repo root (git fails,
  # so the hop is skipped) and a project that tracks `.context/` (pass 1 already
  # answered). Resolution failure is not an error — fall through to the marker
  # pass exactly as before.
  local common gitdir mainroot
  if common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
     && gitdir="$(git rev-parse --absolute-git-dir 2>/dev/null)" \
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

# --- rendered companions (BL-234) ---------------------------------------------
#
# A rendered `.html` companion has no front-matter, so it names the artifact it
# belongs to in the page: `<meta name="artifact-anchor" content="plan/…">`. That
# meta is the ONLY join between the two, and the auto-generated indexes were blind
# to it — a companion could be orphaned, duplicated or left pointing at a moved
# anchor and every index still rendered as if nothing were wrong (2026-08-25).
#
# Emit "<anchor><TAB><path>" for every page declaring a NON-EMPTY anchor, path
# relative to `.context/`. One pass over the tree on purpose: a generator captures
# this once and filters it per entry, rather than re-scanning for each row.
# `validate.py` owns the integrity half (empty / malformed / unresolvable anchors);
# this function only reports what pages claim.
scan_artifact_anchors() {
  python3 - "$1" <<'PY'
import re, sys
from pathlib import Path

ctx = Path(sys.argv[1])
if not ctx.is_dir():
    sys.exit(0)
# Same two regexes as validate.py's read_artifact_anchor, deliberately: the
# checker and the indexers must agree on what a page declares, or a companion
# passes validation and still fails to appear under its entry.
META = re.compile(r"""<meta\s[^>]*\bname\s*=\s*["']artifact-anchor["'][^>]*>""", re.I)
CONTENT = re.compile(r"""\bcontent\s*=\s*["']([^"']*)["']""", re.I)
for p in sorted(ctx.rglob("*.html")):
    # wrap_report.py's superseded snapshots are tooling state, not companions —
    # listing them would show every entry its own history.
    if ".aidex-artifact-prev" in p.parts:
        continue
    try:
        m = META.search(p.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        continue
    if not m:
        continue
    c = CONTENT.search(m.group(0))
    anchor = (c.group(1).strip() if c else "")
    if anchor:
        print(f"{anchor}\t{p.relative_to(ctx)}")
PY
}

# Filter a scan_artifact_anchors stream down to one artifact's companions, newest
# path last. Usage: companions_of "<stream>" "<type>/<name>"
#
# Both sides are normalised by dropping a trailing `.md`: the cross-ref canon
# accepts the bare slug and the explicit filename as the same target (§3), so a
# page anchored `plan/x.md` must join an entry keyed `plan/x`.
companions_of() {
  printf '%s\n' "$1" | awk -F'\t' -v want="$2" '
    function norm(s) { sub(/\.md$/, "", s); return s }
    NF >= 2 && norm($1) == norm(want) { print $2 }'
}
