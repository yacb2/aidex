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

# usage_from_header <script> [start-line=2] — print <script>'s leading comment block
# (its usage) with the "# " prefix stripped, whatever its length. \{0,1\} is portable
# BRE: the GNU-only \? leaves the prefix on macOS /usr/bin/sed. The caller passes its
# own "$0" / "${BASH_SOURCE[0]}": inside this file that name is ours.
usage_from_header() { sed -n "${2:-2},\${/^#/!q;p;}" "$1" | sed 's/^# \{0,1\}//'; }

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
# Never `git rev-parse --show-toplevel` instead. That answers the wrong root twice over:
# inside a linked worktree it is the worktree (which vanishes on teardown), and in a
# multi-repo workspace it is the sub-repo, not the workspace `.context/`. A private
# resolver in a script that chains with others would update the queue in one tree while
# the item closes in another. Pinned by test-find-project-root.sh (no private copies).
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

today_iso() { date +%Y-%m-%d; }

# Render a template: substitute {{KEY}} placeholders with provided values.
# Usage: render_template <template-path> <output-path> KEY1=val1 KEY2=val2 ...
render_template() {
  local template="$1"; shift
  local out="$1"; shift
  [[ -f "$template" ]] || die "template not found: $template"
  [[ -e "$out" ]] && die "refusing to overwrite existing file: $out"

  # The trailing `x` keeps `$(...)` from eating the template's final newline(s); it
  # survives the sed loop below (no `}}` follows it) and is dropped on write.
  local content
  content="$(cat "$template"; printf x)"

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

  printf '%s' "${content%x}" > "$out"
}

# A work-list queue item, as ERE: validate-worklist.py's QUEUE_ITEM
# (`^\s*(\d+)\.\s+\[[ x]\]\s+.+`) spelled for grep -E, and its unchecked subset. One
# definition for every bash reader, or the advancer printed DONE over items the validator
# passed (conventions-scripts-c16). test_worklist_lifecycle.sh holds both to the validator
# per queue form: WL_QUEUE_OPEN through --peek and the tick, WL_QUEUE_ITEM through a sweep
# append's insertion point; test-worklist-close-refusal.sh holds close's owner-row read.
WL_QUEUE_ITEM='^[[:space:]]*[0-9]+\.[[:space:]]+\[[ x]\][[:space:]]+.'
WL_QUEUE_OPEN='^[[:space:]]*[0-9]+\.[[:space:]]+\[ \][[:space:]]+.'

# wl_queue_grep <file> <ERE> — `NR:line` for each line of the work-list's `## Queue`
# section matching ERE (anchored at the line start). The section is the validator's split:
# from the first line holding `## Queue`, after the front matter, up to the next `## `
# heading. The regex alone matched numbered lines anywhere, so a nested `1. [ ]` under
# `## Deferred / emergent` was taken for the head, ticked, or appended after.
wl_queue_grep() {
  awk 'NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
       fm { if (/^---[[:space:]]*$/) fm = 0; next }
       !seen && index($0, "## Queue") { seen = 1; s = 1; next }
       s && /^## / { exit }
       s { print NR ":" $0 }' "$1" | grep -E "^[0-9]+:${2#^}" || true
}

# has_front_matter <file> — 0 when line 1 is `---` and a closing `---` follows; the
# definition set_front_matter scopes to. Callers that write before stamping check first.
has_front_matter() {
  awk 'NR == 1 && !/^---[[:space:]]*$/ { exit } NR > 1 && /^---[[:space:]]*$/ { f = 1; exit } END { exit !f }' "$1"
}

# set_front_matter <file> KEY=VALUE ... — set each KEY inside the YAML front matter only
# (line 1 `---` to the next `---`), the value written literally; a KEY the front matter
# lacks is inserted before its closing delimiter. A file with no front matter returns 1
# and is left untouched. Values travel through ENVIRON: `awk -v` and sed would both
# reinterpret `\`, `&` or `|` in them.
set_front_matter() {
  local file="$1"; shift
  local kv i=0 envs=()
  for kv in "$@"; do
    envs+=("FM_K$i=${kv%%=*}" "FM_V$i=${kv#*=}"); i=$((i + 1))
  done
  env "${envs[@]}" FM_N="$i" awk '
    BEGIN { n = ENVIRON["FM_N"]; for (i = 0; i < n; i++) { k[i] = ENVIRON["FM_K" i]; v[i] = ENVIRON["FM_V" i] } }
    NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit 3; fm = 1; print; next }
    fm && /^---[[:space:]]*$/ {
      for (i = 0; i < n; i++) if (!seen[i]) print k[i] ": " v[i]
      fm = 0; closed = 1; print; next
    }
    fm {
      for (i = 0; i < n; i++) {
        l = length(k[i]) + 1
        if (substr($0, 1, l) == k[i] ":" && (length($0) == l || substr($0, l + 1, 1) ~ /[[:space:]]/)) {
          print k[i] ": " v[i]; seen[i] = 1; next
        }
      }
    }
    { print }
    END { if (!closed) exit 3 }
  ' "$file" > "$file.tmp" || { rm -f "$file.tmp"; return 1; }
  # copied back, not moved: the file keeps its own mode (a tmp gets the umask's)
  cat "$file.tmp" > "$file" && rm -f "$file.tmp"
}

# kebab-case validator
is_valid_slug() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}

# The directory name as a Compose project-name prefix: Compose accepts only
# lowercase alphanumerics, hyphens and underscores, starting with an alphanumeric
# (it rejects `MyApp-wt-x`). Every script that names or looks for a worktree's
# compose project must come through here, or it scans a name nothing carries.
compose_project_name() {
  local p; p="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_-')"
  printf '%s' "${p#"${p%%[!_-]*}"}"
}

# with_timeout <seconds> <cmd...>: run cmd as a child (in its own process group);
# at the deadline TERM the group, then KILL it after a 2 s grace, and exit 142
# (what an alarm-killed process returns). `alarm; exec cmd` only sent SIGALRM to
# cmd, and the docker CLI (a Go binary) ignores SIGALRM: a wedged daemon kept
# `docker` running long past its deadline. TERM alone is not enough either: the
# compose plugin ignores it, and it is a child of the CLI, hence the group. The
# KILL goes out even when the direct child died of the TERM: a TERM-ignoring
# grandchild would otherwise keep a `$( )` pipe open. INT/TERM/HUP/QUIT sent to the
# wrapper are forwarded as the SAME signal to the group (no TERM is sent for an
# INT), then a 2 s grace (armed by the first signal only), then KILL; the signal is
# then re-raised on the wrapper with
# its default disposition, as coreutils `timeout` does: Ctrl-C ends the calling
# script (130) instead of being swallowed as "the command failed", and an outer
# TERM does not leave a `compose down -v` running detached.
with_timeout() {
  perl -e '$t=shift; $p=fork; if(!$p){ setpgrp(0,0); exec @ARGV or exit 127 }
    setpgrp($p,$p);
    for $s (qw(INT TERM HUP QUIT)){ $SIG{$s}=sub{ alarm 2 unless $got; $got=$_[0]; kill $got,-$p } }
    $SIG{ALRM}=sub{ die "timeout\n" };
    sub reap { $r=-1; until($r==$p || $@){ $r=eval{ waitpid $p,0 }; last if $r<0 && !$!{EINTR} } }
    alarm $t; reap(); alarm 0;
    if($@ && !$got){ kill "TERM",-$p; alarm 2; $@=""; reap(); alarm 0; $to=1 }
    if($@ || $got || $to){ kill "KILL",-$p; waitpid $p,0 }
    if($got){ $SIG{$got}="DEFAULT"; kill $got,$$; exit 1 }
    exit 142 if $to;
    exit($?&127 ? 128+($?&127) : $?>>8)' "$@"
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

# resolve_worklist [--with-archive] [--keep-reports] <dir> <slug-or-path> — print the one work-list a slug names.
# Skips -report(.spec).md companions (they sort before `<wl>.md`) unless --keep-reports:
# requests/ and decisions/ have no sweep reports, and there a slug may end in -report; an exact stem
# (`<slug>.md` or `YYYY-MM-DD-<slug>.md`) wins over longer names that merely contain the
# slug; otherwise a slug matching several work-lists is refused (exit 2) instead of
# taking the first (BL-539). --with-archive also searches <dir>/_archive/. Prints
# nothing when nothing matches; the caller owns the not-found message.
resolve_worklist() {
  local arch=0 keep=0 dir arg m n f b exact=() re
  [[ "${1:-}" == "--with-archive" ]] && { arch=1; shift; }
  [[ "${1:-}" == "--keep-reports" ]] && { keep=1; shift; }
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
    m="$(ls "$dir/"*"$arg"*.md "$dir/_archive/"*"$arg"*.md 2>/dev/null || true)"
  else
    m="$(ls "$dir/"*"$arg"*.md 2>/dev/null || true)"
  fi
  [[ $keep -eq 1 ]] || m="$(grep -Ev -- '-report(\.spec)?\.md$' <<<"$m" || true)"
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

# wl_is_archived <file> <wl-dir> — 0 when <file> sits in <wl-dir>/_archive. Archived-ness from
# the RESOLVED directory, never the spelling: `cd _archive && ./x.md` or a symlinked dir
# reaches an archived list with no literal `_archive/` in it (BL-591).
wl_is_archived() {
  [[ "$(CDPATH= cd -P "$(dirname "$1")" >/dev/null 2>&1 && pwd -P)" == "$(CDPATH= cd -P "$2/_archive" >/dev/null 2>&1 && pwd -P)" ]]
}

# wl_is_sweep <file> — 0 when the work-list front matter says `mode: sweep`. Quotes allowed:
# validate-worklist.py strips them, so `mode: "sweep"` validates and must mean sweep here
# too, or the queue silently advances past unproven work.
wl_is_sweep() { grep -qE '^mode:[[:space:]]*["'"'"']?sweep["'"'"']?[[:space:]]*$' "$1"; }

# bl_item_file <backlog-dir> <BL-id> — path of the item carrying that id, or empty (rc 0).
# Order: active, _deferred, _archive — the order of backlog/scripts/register-item.sh
# backlog_files: a deferred item is live where an archived copy is closed, so a duplicated id
# must resolve to the live one.
bl_item_file() {
  local f
  for f in "$1"/*.md "$1"/_deferred/*.md "$1"/_archive/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$f")" == "$2" ]] && { printf '%s' "$f"; return 0; }
  done
  # explicit: a no-match ends on a false `[[ ]] &&`, and under `set -e` a caller's
  # `f="$(bl_item_file …)"` would die on the first id it cannot find
  return 0
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

# resolve_profile <context-dir> <name> — path of a per-project profile, or empty + return 1.
# New path .context/profiles/<name>.md first, the legacy root file second (canon:
# 00-global.md "Profiles"). Names: artifact communication testing deploy ui-contract.
# Python twin: profiles.py. Writers never use the legacy path: profile_write_path.
profile_write_path() { printf '%s/profiles/%s.md\n' "$1" "$2"; }
resolve_profile() {
  local ctx="$1" name="$2" legacy new
  case "$name" in
    artifact)      legacy="artifact-style.md" ;;
    communication) legacy="communication-style.md" ;;
    testing)       legacy="testing-profile.md" ;;
    deploy)        legacy="deploy-profile.md" ;;
    ui-contract)   legacy="ui-contract.md" ;;
    *) return 1 ;;
  esac
  new="$(profile_write_path "$ctx" "$name")"
  if [[ -f "$new" ]]; then printf '%s\n' "$new"; return 0; fi
  if [[ -f "$ctx/$legacy" ]]; then printf '%s\n' "$ctx/$legacy"; return 0; fi
  return 1
}

# Digest of stdin (first field) for lock and log file names: shasum, else
# sha256sum, else cksum — shasum is missing on some Linux images.
path_digest() { { shasum 2>/dev/null || sha256sum 2>/dev/null || cksum; } | cut -d' ' -f1; }

# lock_take <lockfile> <wait-seconds> [fd] / lock_drop [fd] — an exclusive kernel lock
# (perl flock) on <lockfile>, held through a shell fd (3-9, default 9) until lock_drop
# closes it or the shell exits. The mkdir locks it replaces took over a lock by its age
# and lost data both ways: two waiters each removed a lock the other had just taken, and
# a future mtime deleted a live one. A kernel lock has no stale state, so there is no
# takeover: a killed holder's lock goes with its process, a live holder keeps it however
# long it runs. Nothing is ever removed: deleting a flock file reopens an inode race, so
# the file stays (local filesystem only; flock is unreliable on NFS).
# Returns 0 held; 75 when <wait-seconds> pass with the lock still taken; 2 on a bad wait
# or fd, no perl, a lock path that is a symlink, an unopenable file, or an fd this shell
# already locks with; each failure prints one line naming <lockfile>.
# Children inherit the fd: one still running (a hung `docker ps`, a background job) keeps
# the lock after the shell drops it or dies; start such a child with `9>&-`. Nested locks
# need distinct fds. fds above 9 are refused: bash 3.2 does not replace an open fd above 9
# on `exec N>>`, so a second lock there silently re-locked the first file.
# Re-entrant per lock path: once held, AIDEX_LOCK_<digest>=<fd> is exported. A take of a
# lock whose marker is set returns 0 at once, instead of waiting on itself, only when that
# fd in this process still refers to the lock file (a child started with `9>&-` keeps the
# marker without the lock, so it takes the lock for real). The same shell taking the same
# lock on the same fd again goes one level deeper and its lock_drop only comes back up; on
# another fd it is refused (rc 2). A child's re-entrant take has no lock_drop (a no-op).
#
# One shape, a section: take, write, drop. Every exit path must drop, or put the section
# in a subshell, which drops as it ends:
#     lock_take "$file.flock" 30 || exit $?; ...read, modify, write...; lock_drop
#     ( lock_take "$lock" 10 || exit $?; cp -p "$f" "$tmp" && awk ... > "$tmp" && mv "$tmp" "$f" ) || rc=$?
# A whole script is the same call with no lock_drop: the lock lasts until it exits.
# The per-shell record _AIDEX_LOCK_FD<fd> is "<subshell level> <marker> <depth>": a
# subshell may reuse its parent's fd (its copy is its own), the same shell may not (that
# would silently drop the lock the fd holds).
lock_take() {
  local lock="$1" wait="$2" fd="${3:-9}" mark rec held lvl m n rc=0
  [[ "$wait" =~ ^[1-9][0-9]*$ ]] || { err "error: the wait for $lock must be whole seconds, got '$wait'"; return 2; }
  [[ "$fd" =~ ^[3-9]$ ]] || { err "error: the fd for $lock must be 3-9, got '$fd'"; return 2; }
  command -v perl >/dev/null 2>&1 || { err "error: perl is required to lock $lock; nothing written"; return 2; }
  mark="AIDEX_LOCK_$(printf '%s' "$(cd "$(dirname "$lock")" 2>/dev/null && pwd -P)/$(basename "$lock")" | path_digest | cut -c1-16)"
  rec="_AIDEX_LOCK_FD$fd"
  held="${!mark:-}"
  if [[ "$held" =~ ^[3-9]$ ]] && perl -e 'my @f = stat(shift); open(my $h, ">&=", shift) or exit 1;
       my @d = stat($h); exit(@f && @d && $f[0] == $d[0] && $f[1] == $d[1] ? 0 : 1)' "$lock" "$held" 2>/dev/null; then
    if [[ "$held" == "$fd" && "${!rec:-}" == "$BASH_SUBSHELL $mark "* ]]; then
      read -r lvl m n <<<"${!rec}"; eval "$rec=\"\$lvl \$m \$((n + 1))\""
    else
      # this shell holds it on another fd: a take here would leave nothing for its
      # lock_drop to undo but that fd's own lock (a child's take is fine: not ours to drop)
      m="_AIDEX_LOCK_FD$held"
      [[ "${!m:-}" != "$BASH_SUBSHELL $mark "* ]] \
        || { err "error: $lock is held by this shell on fd $held; take it on fd $held, not fd $fd"; return 2; }
    fi
    return 0
  fi
  [[ "${!rec:-}" != "$BASH_SUBSHELL "* ]] || { err "error: fd $fd already holds a lock in this shell; take $lock on another fd"; return 2; }
  # a symlink is refused, not followed (a shared temp dir lets another user plant one);
  # bash has no O_NOFOLLOW, so callers also keep their locks in a private directory
  [[ ! -L "$lock" ]] || { err "error: the lock file $lock is a symlink; refusing to follow it, nothing written"; return 2; }
  eval "exec $fd>>\"\$lock\"" 2>/dev/null || { err "error: cannot open the lock file $lock; nothing written"; return 2; }
  perl -MFcntl=:flock -e 'open(my $h, ">&=", shift) or exit 2; $SIG{ALRM} = sub { exit 75 };
    alarm shift; exit(flock($h, LOCK_EX) ? 0 : 2)' "$fd" "$wait" || rc=$?
  case $rc in
    0)  export "$mark=$fd"; eval "$rec=\"\$BASH_SUBSHELL \$mark 1\"" ;;
    75) err "error: $lock is held by another run (waited $wait s); nothing written" ;;
    *)  err "error: could not lock $lock; nothing written"; rc=2 ;;
  esac
  [[ $rc -eq 0 ]] || eval "exec $fd>&-"
  return $rc
}
lock_drop() {
  local fd="${1:-9}" rec lvl m n
  rec="_AIDEX_LOCK_FD$fd"
  [[ "${!rec:-}" == "$BASH_SUBSHELL "* ]] || return 0
  read -r lvl m n <<<"${!rec}"
  if (( n > 1 )); then eval "$rec=\"\$lvl \$m \$((n - 1))\""; return 0; fi
  unset "$m" "$rec"
  eval "exec $fd>&-"
}

# wl_lock_file <work-list> — the lock_take path every writer of one work-list shares
# (worklist-advance.sh, worklist-close.sh). Keyed by the list's REAL path, so a slug, a
# `./x.md` and a symlinked `.context` reach one lock. Kept in a per-user 0700 directory, not
# beside the list: a flock file is never removed and would pile up in worklists/. The same
# directory as mark_row_escalated's inventory lock (audit/_lib.sh). Prints the path, or
# returns 2 with one line when the directory is a symlink or not this user's.
# Limit: the directory follows $TMPDIR, so two processes with different TMPDIR values (or
# different users) get different lock files and do NOT exclude each other.
wl_lock_file() {
  local dir="${TMPDIR:-/tmp}/aidex.locks.$EUID"
  mkdir -m 700 "$dir" 2>/dev/null || :   # an existing path (or symlink) stays as it is
  [[ -d "$dir" && ! -L "$dir" && -O "$dir" ]] \
    || { err "error: the lock directory $dir is a symlink, not a directory or not yours; nothing written"; return 2; }
  # CDPATH= : an exported CDPATH sent a relative `.context/...` to another project's twin
  printf '%s/aidex-wl.%s.flock\n' "$dir" "$(printf '%s' "$(CDPATH= cd -P "$(dirname "$1")" && pwd -P)/$(basename "$1")" | path_digest | cut -c1-16)"
}
