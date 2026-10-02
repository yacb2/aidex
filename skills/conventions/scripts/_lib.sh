#!/usr/bin/env bash
# Shared generic helpers for aidex skill scripts.
# Source: . "$(dirname "$0")/../../conventions/scripts/_lib.sh"
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
# fresh project made `orphan-sweep` scan for `user-wt-*` (reporting a
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
  # Eight worktree scripts source this file, and they are most often
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
    # The walk STOPS AT THE MAIN WORKTREE'S OWN ROOT — it does not continue up.
    # BL-418, field-observed 2026-09-17: a repo nested inside a workspace that
    # has its own `.context/` (every split workspace since BL-412) carries no
    # `.context/` at its root BY DESIGN, so an upward walk from there escaped
    # the repo and resolved to the WORKSPACE's private `.context/`. Every aidex
    # script run inside a cell worktree then wrote into the owner's live
    # artifacts — 34 lifecycle-test files reached
    # `aidex_ws/.context/worklists/_archive/` before anyone noticed.
    # The main worktree IS the project: with a `.context/` it answers as itself,
    # and without one it is still the right root to create it in.
    if [[ -n "$mainroot" && "$mainroot" != "$stop" ]]; then
      printf '%s\n' "$mainroot"
      return 0
    fi
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
ANCHOR_SHAPE = re.compile(
    r"^(audit|backlog|plan|request|decision|reference|research|communication|loop|worktree)/\S+$")
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
    # The anchor is arbitrary text read out of a page, and it is emitted as the FIRST
    # tab-separated field. A tab inside content="…" shifts the fields, so the consumer
    # reads the injected text as the companion's path — and `archive_companions` feeds
    # that path to `mv`. Verified 2026-08-25: content="plan/x<TAB>../outside.txt" made
    # companions_of return a path outside `.context/` entirely.
    #
    # Requiring the canonical `<type>/<filename>` shape closes it at the root rather
    # than stripping control characters one at a time: field 2 is then always a real
    # rglob path under ctx. Nothing legitimate is lost — an anchor that does not match
    # this could never join a local entry anyway, and validate.py still reports it as
    # `artifact-anchor-format-invalid`. The type enum is the one from 00-global §3.
    if not ANCHOR_SHAPE.match(anchor):
        continue
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

# Move an artifact's rendered companions into the archive beside it, and SAY SO —
# both when a page moves and when one is left behind (BL-234).
#
# Archive-on-close (D-10) exists so inbound `<type>/<filename>` references keep
# resolving. A companion joins its anchor through the page, not through the
# filesystem, so `mv` carries only the ones that happen to live INSIDE a moved
# folder. Everything else — a single-file plan's `-report.html` sibling, a backlog
# item's companion, a page that sat next to a modular plan rather than in it — is
# silently orphaned. That is what happened to `plan/2026-08-22-suite-speed-and-
# coverage-rollout` on 2026-08-25: two companions travelled with the folder, the
# third stayed in `plans/`, and nothing anywhere said a word.
#
# Call AFTER the artifact has moved: the scan reads current paths, so a page that
# already travelled is recognised by its destination and left alone.
#
# Usage: archive_companions <context-dir> <type>/<name> <dest-dir>
# Always returns 0 — a companion that cannot be moved is a thing to report, never
# a reason to fail a close that has already happened.
archive_companions() {
  local ctx="$1" ref="$2" dest="$3"
  local anchors comp src base
  anchors="$(scan_artifact_anchors "$ctx")"
  while IFS= read -r comp; do
    [[ -n "$comp" ]] || continue
    src="$ctx/$comp"
    [[ -f "$src" ]] || continue
    # Already in the destination: it travelled inside the folder that just moved.
    case "$src" in "$dest"/*) continue ;; esac
    base="$(basename "$src")"
    if [[ -e "$dest/$base" ]]; then
      warn "companion left behind (a file named $base is already in the archive): $comp"
      continue
    fi
    mkdir -p "$dest"
    if mv "$src" "$dest/$base"; then
      ok "archived companion $base"
    else
      warn "companion left behind (move failed): $comp"
    fi
  done < <(companions_of "$anchors" "$ref")
  return 0
}

# resolve_worklist [--with-archive] <dir> <slug-or-path> — print the one work-list a slug names.
# Skips -report(.spec).md companions (they sort before `<wl>.md`); an exact stem
# (`<slug>.md` or `YYYY-MM-DD-<slug>.md`) wins over longer names that merely contain the
# slug; otherwise a slug matching several work-lists is refused (exit 2) instead of
# taking the first (BL-539). --with-archive also searches <dir>/_archive/. Prints
# nothing when nothing matches; the caller owns the not-found message.
resolve_worklist() {
  local arch=0 dir arg m n f b exact=() re
  [[ "${1:-}" == "--with-archive" ]] && { arch=1; shift; }
  dir="$1"; arg="$2"
  # A path (it has a `/`) is taken as given only inside <dir> or <dir>/_archive/; any
  # other path is refused, or `./notes.md` was closed and archived as a work-list
  # (BL-561). A path into _archive/ is returned; a caller that must refuse an archived list
  # compares the resolved directory with `$WL_DIR/_archive` (BL-591), never the path text. A bare name is a file only when the
  # CWD is the work-list dir itself: `foo` beside the caller is not the work-list `foo`
  # names (BL-551, same class as BL-541). Both sides resolved (a worktree may link
  # .context), cd's CDPATH echo silenced, CDPATH emptied for the relative `dirname` (an
  # exported CDPATH sent `cd worklists` to another project's folder), and `cd -P` so
  # `ext/..` after a symlinked folder means what the kernel opens, not worklists/ itself.
  if [[ -f "$arg" ]]; then
    if [[ "$arg" == */* ]]; then
      local at; at="$(CDPATH= cd -P "$(dirname "$arg")" >/dev/null 2>&1 && pwd -P)"
      if [[ "$at" == "$(cd "$dir" >/dev/null 2>&1 && pwd -P)" \
         || "$at" == "$(cd "$dir/_archive" >/dev/null 2>&1 && pwd -P)" ]]; then
        printf '%s\n' "$arg"; return 0
      fi
      err "not under $dir: $arg"; exit 2
    fi
    local here; here="$(pwd -P)"
    if [[ "$here" == "$(cd "$dir" >/dev/null 2>&1 && pwd -P)" ]] \
       || [[ $arch -eq 1 && "$here" == "$(cd "$dir/_archive" >/dev/null 2>&1 && pwd -P)" ]]; then
      printf '%s\n' "$arg"; return 0
    fi
  fi
  # the full filename (what every listing prints) globbed as `*<name>.md*.md` and matched nothing
  [[ -n "${arg%.md}" ]] && arg="${arg%.md}"
  if [[ $arch -eq 1 ]]; then
    m="$(ls "$dir/"*"$arg"*.md "$dir/_archive/"*"$arg"*.md 2>/dev/null | grep -Ev -- '-report(\.spec)?\.md$' || true)"
  else
    m="$(ls "$dir/"*"$arg"*.md 2>/dev/null | grep -Ev -- '-report(\.spec)?\.md$' || true)"
  fi
  # A slug with `..` climbs out through the glob: `*` matches the `_archive` entry, so
  # `_archive/../../../../q/...` named another project's list. Every match must resolve,
  # like a path, into <dir> or <dir>/_archive (review of BL-600).
  local wd ad
  wd="$(CDPATH= cd -P "$dir" >/dev/null 2>&1 && pwd -P)" || true
  ad="$(CDPATH= cd -P "$dir/_archive" >/dev/null 2>&1 && pwd -P)" || true
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    b="$(CDPATH= cd -P "$(dirname "$f")" >/dev/null 2>&1 && pwd -P)"
    [[ "$b" == "$wd" || "$b" == "$ad" ]] || { err "not under $dir: $arg"; exit 2; }
  done <<<"$m"
  n="$(grep -c . <<<"$m" || true)"
  if [[ "$n" -gt 1 ]]; then
    re='^[0-9]{4}-[0-9]{2}-[0-9]{2}-'
    while IFS= read -r f; do
      b="$(basename "$f")"
      if [[ "$b" == "$arg.md" || ( "$b" =~ $re && "${b:11}" == "$arg.md" ) ]]; then exact+=("$f"); fi
    done <<<"$m"
    if [[ ${#exact[@]} -eq 1 ]]; then printf '%s\n' "${exact[0]}"; return 0; fi
    err "ambiguous slug '$arg' matches more than one ($n) file in $dir:"; printf '%s\n' "$m" >&2
    exit 2
  fi
  printf '%s\n' "$m"
}

# proof_is_placeholder <cell> — 0 when a `## Verification` proof cell says no proof exists
# (or, on an owner row, that the answer is still owed). The phrases live in
# placeholder-proofs.txt beside this file, the one list sweep-report.py reads too.
# BASH_SOURCE[0] inside a function is the file that defined it: this one.
_PH_LEAD="" _PH_UPPER="" _PH_TAIL=""
proof_is_placeholder() {
  if [[ -z "$_PH_LEAD" ]]; then
    local where phrase lead="" upper="" tail=""
    # tolerant like the python reader: a CRLF file and a last line with no newline
    while read -r where phrase || [[ -n "$where" ]]; do
      phrase="${phrase%$'\r'}"
      case "$where" in
        lead)       lead="$lead|$phrase" ;;
        lead-upper) upper="$upper|$phrase" ;;
        tail)       tail="$tail|$phrase" ;;
      esac
    done < "$(dirname "${BASH_SOURCE[0]}")/placeholder-proofs.txt"
    _PH_LEAD="^(${lead#|})([^[:alnum:]]|$)"
    _PH_UPPER="^(${upper#|})([^[:alnum:]]|$)"
    _PH_TAIL="(^|[[:space:],;(])(${tail#|})[^[:alnum:]]*$"
  fi
  [[ "$1" =~ $_PH_UPPER ]] && return 0
  local rc=1
  shopt -s nocasematch   # restored on every path: callers match `case` arms after this
  if [[ "$1" =~ $_PH_LEAD || "$1" =~ $_PH_TAIL ]]; then rc=0; fi
  shopt -u nocasematch
  return $rc
}
