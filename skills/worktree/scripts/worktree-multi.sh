#!/usr/bin/env bash
# worktree-multi.sh — INTERNAL to worktree.sh. Do not call this directly.
#
# It performs the git half of a worktree: one git worktree per participant plus
# symlinks for the unversioned root wrapper files (compose file, dev scripts)
# that a code-only checkout of a single participant would lack. That is ALL it
# does — no port slot, no isolated stack, no generated .env, no readiness, no
# seeding, no rollback, no teardown verification.
#
# It survives as a separate script because worktree.sh calls it, and because the
# "Tier 1" of the retired tier taxonomy was exactly this and nothing more.
# Several projects' older .context/worktrees/00-index.md still invoke it by
# name. Following those docs produces a checkout that LOOKS like a worktree,
# shares dev's database and ports, and reports no error — which is worse than a
# broken command. Hence the direct-invocation warning below; the docs are the
# thing to fix (check-overview.sh does NOT flag them: it passes any Procedure
# line naming this script, because the script exists).
#
# The one path is: worktree.sh new|up|down|list.
#
# Stack-agnostic by construction: participants and wrapper files come from the
# ARGUMENTS (i.e. from the project's own .context/worktrees/00-index.md Procedure
# section) — nothing project-specific is hardcoded here. Single-repo projects
# don't need this script (native EnterWorktree / git worktree add covers them).
#
# Usage:
#   worktree-multi.sh create --slug <slug> --branch <branch> [--base <commit-ish>] \
#       --repo <path> [--repo <path> ...] [--link <file> ...] [--copy <file> ...] [--dest <dir>]
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

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/wt-env-marker.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/wt-frontmatter.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/wt-common.sh"

usage() {
  wt_usage "${BASH_SOURCE[0]}"
  exit 2
}

cmd="${1:-}"; shift || true
case "$cmd" in -h|--help) wt_usage "${BASH_SOURCE[0]}"; exit 0 ;; esac
[[ "$cmd" == "create" || "$cmd" == "remove" ]] || usage

# Warn, don't refuse: worktree.sh sets AIDEX_WT_INTERNAL, and a hard failure
# would break any caller mid-teardown — including a recovery from a half-removed
# worktree, which is the worst possible moment to add a new way to fail.
if [[ -z "${AIDEX_WT_INTERNAL:-}" ]]; then
  warn "worktree-multi.sh was invoked directly. It creates a CODE-ONLY checkout:"
  warn "  no port slot, no isolated stack, no generated .env, no teardown verification."
  warn "  A worktree made this way silently shares dev's database and ports."
  # worktree.sh has no create/remove: their counterparts are new/down.
  warn "  Use instead:  worktree.sh $([[ "$cmd" == create ]] && echo new || echo down) ..."
  warn "  If a project doc told you to run this, that doc predates the current"
  warn "  mechanism — update it to call worktree.sh new|up|down|list."
fi

SLUG="" BRANCH="" BASE="" DEST=""
SKIP_TEARDOWN=false
FORCE_RM=false
REPOS=()
LINKS=()
COPIES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)   SLUG="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --base)   BASE="$2"; shift 2 ;;
    --repo)   REPOS+=("$2"); shift 2 ;;
    --link)   LINKS+=("$2"); shift 2 ;;
    --copy)   COPIES+=("$2"); shift 2 ;;
    --dest)   DEST="$2"; shift 2 ;;
    --skip-teardown) SKIP_TEARDOWN=true; shift ;;
    --force) FORCE_RM=true; shift ;;
    -h|--help) wt_usage "${BASH_SOURCE[0]}"; exit 0 ;;
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
    if [[ -n "$BASE" ]]; then
      git -C "$ROOT/$r" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || die "base not found in $r: $BASE"
      ! git -C "$ROOT/$r" show-ref --verify --quiet "refs/heads/$BRANCH" \
        || die "--base given but branch $BRANCH already exists in $r (it would be used at its own tip, ignoring the base)"
    elif ! git -C "$ROOT/$r" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      # Nothing names a default, and the ambient checkout is no base: forking from
      # it welds $BRANCH to whatever is checked out, and a wrong base is expensive
      # to undo (owner, 2026-10-12). Refused before anything is created.
      wt_default_start "$ROOT" "$r" >/dev/null \
        || die "$r: no default branch found (no origin/HEAD, main or master) to fork $BRANCH from — pass --base <commit-ish>, or create $BRANCH in $r first (git -C $r branch $BRANCH <commit>); nothing created"
    fi
  done
  # A root participant gets per-worktree excludes (extensions.worktreeConfig, below).
  # Under that extension a core.worktree in the shared config applies to EVERY worktree
  # (a new checkout resolves its toplevel to the main tree), so git wants it moved to
  # the main tree's config.worktree first; refuse rather than move the user's setting.
  # That holds when the extension is already on, too.
  for r in "${REPOS[@]}"; do
    [[ "$r" == "." || "$r" == "./" ]] || continue
    [[ -z "$(git -C "$ROOT" config --local --get core.worktree 2>/dev/null)" ]] \
      || die "the root repo sets core.worktree in .git/config; per-worktree excludes need extensions.worktreeConfig, which requires moving it to config.worktree first — nothing created"
  done
  for l in "${LINKS[@]:-}"; do
    [[ -z "$l" ]] && continue
    [[ -e "$ROOT/$l" ]] || die "wrapper file to link not found: $l (relative to $ROOT)"
  done

  # The ROOT repo may itself be a participant, spelled `.` (BL-259): a project whose
  # root owns `.context/` needs $DEST to BE a checkout of it, so the worktree has its
  # own .context/ and find_project_root stops there instead of walking back into the
  # main tree. The other participants then nest inside that checkout.
  #
  # It must be created FIRST, whatever order the config lists it in. `git worktree add`
  # refuses a non-empty destination, so with `WT_PARTICIPANTS="backend ."` the
  # participants had already populated $DEST and creation died on
  # `fatal: '<dest>/.' already exists` — a config-order dependency nobody knew they had.
  ROOT_FIRST=(); REST=()
  for r in "${REPOS[@]}"; do
    if [[ "$r" == "." || "$r" == "./" ]]; then ROOT_FIRST=("$r"); else REST+=("$r"); fi
  done
  ORDERED=(${ROOT_FIRST[@]+"${ROOT_FIRST[@]}"} ${REST[@]+"${REST[@]}"})

  # Only make the directory when no root checkout will make it: `git worktree add`
  # wants to create $DEST itself.
  [[ "${#ROOT_FIRST[@]}" -gt 0 ]] || mkdir -p "$DEST"
  for r in "${ORDERED[@]}"; do
    name="$(basename "$r")"
    # basename "." is "." and "$DEST/." is "$DEST", which is exactly where the root
    # checkout belongs — but say so, because relying on it silently is how the
    # order-dependence above stayed invisible.
    if git -C "$ROOT/$r" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git -C "$ROOT/$r" worktree add "$DEST/$name" "$BRANCH" >/dev/null
    else
      # Fork from --base, else the repo's default branch: never the ambient HEAD,
      # which welds the new branch to whatever feature branch happens to be checked out.
      # A missing default was refused above, so start is never empty here.
      start="$BASE"
      [[ -n "$start" ]] || start="$(wt_default_start "$ROOT" "$r")"
      git -C "$ROOT/$r" worktree add --no-track -b "$BRANCH" "$DEST/$name" "$start" >/dev/null
    fi
    if [[ "$name" == "." ]]; then
      # worktree.sh writes its own bookkeeping (.wt-slot, .wt-branch, a generated
      # .env) into $DEST. In a plain directory that is invisible; in a root CHECKOUT
      # they are untracked files, so the checkout is dirty from the moment it is
      # created — and `IS_DIRTY` reads $DEST, so a plain `down` would refuse forever,
      # naming aidex's own bookkeeping as the user's uncommitted work (BL-259).
      # The other participants are checked out INSIDE this one, so the root repo
      # sees each as an untracked directory too: aidex's layout, not the user's work.
      #
      # The excludes are scoped to THIS checkout (BL-771). info/exclude is a
      # common-dir path, shared by every worktree: lines written there also hid the
      # main tree's own .env, .wt-* and /<participant>/ from its git status, and
      # nothing removed them. A per-worktree core.excludesFile (extensions.worktreeConfig)
      # pointing into the checkout's private gitdir goes away with the checkout.
      # That value REPLACES the user's global excludes file in this checkout, so the
      # global file's lines are copied above aidex's.
      # `/.env`, anchored: worktree.sh generates only the checkout's top-level .env.
      # A bare `.env` also hid the user's own <dir>/.env (BL-770).
      _lines=('# aidex worktree bookkeeping (worktree.sh)' '.wt-slot' '.wt-branch' '/.env')
      _parts=()
      for _p in ${REST[@]+"${REST[@]}"}; do _parts+=("/$(basename "$_p")/"); done
      _gx="$(git -C "$ROOT" config --type=path --get core.excludesFile 2>/dev/null || true)"
      [[ -n "$_gx" ]] || _gx="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"
      scope_excludes() {  # <checkout> [/<participant>/ ...] -> its own excludes file, set as its per-worktree value
        local wt="$1" wx; wx="$(git -C "$1" rev-parse --absolute-git-dir)/aidex-exclude"
        shift
        : > "$wx"
        if [[ -f "$_gx" && -r "$_gx" ]]; then
          cat "$_gx" >> "$wx"
          # A file not ending in a newline would glue aidex's header onto its last line.
          if [[ -s "$_gx" && -n "$(tail -c1 "$_gx")" ]]; then printf '\n' >> "$wx"; fi
        fi
        printf '%s\n' "${_lines[@]}" "$@" >> "$wx"
        git -C "$wt" config --worktree core.excludesFile "$wx"
      }
      # Only when off: every write takes .git/config.lock, and a concurrent `git config`
      # in the main tree (or another create) would then fail one of the two.
      [[ "$(git -C "$ROOT" config --bool --get extensions.worktreeConfig 2>/dev/null)" == true ]] \
        || git -C "$ROOT" config extensions.worktreeConfig true
      scope_excludes "$DEST" ${_parts[@]+"${_parts[@]}"}
      # Older versions wrote that block to the shared info/exclude, one per create
      # before 33ac4406. Strip ONLY inside those blocks (BL-770's block rule): after the
      # header, a body line is one of `.wt-slot`, `.wt-branch`, `.env`/`/.env` (only
      # the first per block) or `/<name>/`; anything else (a comment, a user rule, a
      # second `.env`) ends the block and is kept in place. A blank line closing a
      # block goes with it.
      # Known limits: a user `/<name>/` rule right after a block is stripped with it;
      # the rewrite replaces a symlinked exclude file with a regular file, mode 644.
      _ex="$(git -C "$ROOT" rev-parse --git-path info/exclude 2>/dev/null || true)"
      [[ "$_ex" == /* ]] || _ex="$ROOT/$_ex"
      if [[ -s "$_ex" ]] && grep -qxF -- "${_lines[0]}" "$_ex"; then
        _mig="$(mktemp "$(dirname "$_ex")/exclude.XXXXXX")"
        _gone="$(mktemp "$(dirname "$_ex")/exclude.XXXXXX")"
        # Kept lines go to $_mig; every stripped `/<name>/` goes to $_gone.
        if awk -v hdr="${_lines[0]}" -v gone="$_gone" '
          function member(x) {
            return x == ".wt-slot" || x == ".wt-branch" || x == ".env" || x == "/.env" || x ~ /^\/[^\/]+\/$/
          }
          {
            if (inb) {
              isenv = ($0 == ".env" || $0 == "/.env")
              if (member($0) && !(isenv && envseen)) {
                if (isenv) envseen = 1
                else if ($0 ~ /^\/[^\/]+\/$/) print > gone
                next
              }
              inb = 0
              if ($0 == "") next
            }
            if ($0 == hdr) { inb = 1; envseen = 0; next }
            print
          }' "$_ex" > "$_mig"; then
          # Root checkouts made before this fix had only the shared block; stripping it
          # would surface their bookkeeping and make their `down` refuse (BL-259). Give
          # each one (it holds .wt-slot and has no per-worktree value yet) its own first,
          # with every `/<name>/` the stripped blocks held: those are the participants it
          # was hidden from, whatever THIS create lists. The first entry is the main tree.
          _old_parts=()
          while IFS= read -r _p; do _old_parts+=("$_p"); done < <(sort -u "$_gone")
          while IFS= read -r _wt; do
            [[ -e "$_wt/.wt-slot" ]] || continue
            [[ -z "$(git -C "$_wt" config --worktree --get core.excludesFile 2>/dev/null)" ]] || continue
            scope_excludes "$_wt" ${_old_parts[@]+"${_old_parts[@]}"}
          done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p' | tail -n +2)
          { chmod 644 "$_mig" && mv "$_mig" "$_ex"; } || true
        fi
        rm -f "$_mig" "$_gone"
      fi
      ok "worktree: (root) -> $DEST (branch $BRANCH)"
    else
      ok "worktree: $name -> $DEST/$name (branch $BRANCH)"
    fi
  done
  for l in "${LINKS[@]:-}"; do
    [[ -z "$l" ]] && continue
    # Mirror the RELATIVE path, not just the basename. `--link backend/.env`
    # used to land as <dest>/.env, so compose looked for <dest>/backend/.env,
    # found nothing, and the stack refused to start with an error that named
    # the file but not the reason.
    # With a root participant the checkout brings its own tracked files, so a
    # WT_LINKS entry naming one of them hits an existing path: `ln -s` fails and the
    # whole creation rolls back. WT_LINKS is for UNVERSIONED wrapper files, so the
    # tracked one is not a conflict to resolve — it is already correct. Skip it, and
    # SAY so: linking over it would dirty the checkout and make `git worktree remove`
    # refuse at teardown (BL-259).
    if [[ -e "$DEST/$l" || -L "$DEST/$l" ]]; then
      ok "link: $l skipped — the root checkout already carries it"
      continue
    fi
    mkdir -p "$(dirname "$DEST/$l")"
    ln -s "$ROOT/$l" "$DEST/$l"
    ok "link: $l -> $ROOT/$l"
  done
  # COPIES exist because a Docker build context cannot follow a symlink that
  # escapes it. `backend/poetry.lock` is gitignored in this family, so a fresh
  # worktree checkout lacks the file the Dockerfile does
  # `COPY pyproject.toml poetry.lock ./` with; symlinking it resolves fine on the
  # filesystem and STILL fails the build with `"/poetry.lock": not found`,
  # because BuildKit refuses to leave the context. Copy those; symlink the rest,
  # so an edit to the compose file still reaches every worktree.
  for c in "${COPIES[@]:-}"; do
    [[ -z "$c" ]] && continue
    [[ -e "$ROOT/$c" ]] || die "--copy $c: no such file in $ROOT"
    if [[ -e "$DEST/$c" || -L "$DEST/$c" ]]; then
      ok "copy: $c skipped — the root checkout already carries it"
      continue
    fi
    mkdir -p "$(dirname "$DEST/$c")"
    cp -R "$ROOT/$c" "$DEST/$c"
    ok "copy: $c"
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
  warn "--skip-teardown: leaving Docker resources for $(compose_project_name "$(basename "$ROOT")")-wt-$SLUG untouched"
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
      # The leading front-matter block only (wt_fm_block): this value is EVAL'd as the
      # teardown recipe, and a `worktree_down:` below the front matter must not be it.
      WT_DOWN="$(wt_fm_unquote "$(wt_fm_block "$DOC" | sed -n 's/^worktree_down: *//p' | sed -n 1p)")"
    fi

    if [[ -z "$WT_DOWN" ]]; then
      err "Docker resources exist, or could not be judged (see 'not judged' above), for $(compose_project_name "$(basename "$ROOT")")-wt-$SLUG but the project records no 'worktree_down'."
      err "Refusing to invent a teardown. Either:"
      err "  - record worktree_down in $DOC (see /aidex:worktree bootstrap, Axis 4), or"
      err "  - reclaim the resources with the commands listed above, then re-run with --skip-teardown"
      err "    (nothing listed but 'not judged': re-run once docker answers, not --skip-teardown)"
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

# Refuse BEFORE the first removal. git refuses a dirty worktree one at a time, so a
# dirty second participant left the first already removed: a half worktree that
# `up` never rebuilds. The root checkout counts too, minus the untracked files the
# sweep below deletes anyway -- keep this list in step with it: wrapper links, the
# markers, the generated .env and the --copy files.
# True when $DEST/.env is the slot env file worktree.sh generated: line 1 contains
# WT_ENV_MARKER_TEXT as a fixed substring (wt-env-marker.sh, shared with the writer).
is_generated_env() { head -1 "$DEST/.env" 2>/dev/null | grep >/dev/null -F -- "$WT_ENV_MARKER_TEXT"; }
swept() {  # <path relative to $DEST> -> 0 when the sweep below would delete it
  local c
  # A participant checkout the root repo does not ignore shows as `?? <name>/`. It
  # is a participant, not the user's work; its own dirt was checked just above.
  [[ -f "$DEST/${1%/}/.git" ]] && return 0
  [[ -L "$DEST/$1" || "$1" == .wt-slot || "$1" == .wt-branch ]] && return 0
  [[ "$1" == .env ]] && is_generated_env && return 0
  for c in "${COPIES[@]:-}"; do
    [[ -n "$c" && ( "$1" == "$c" || "$1" == "$c/"* ) ]] && return 0
  done
  return 1
}
if ! $FORCE_RM; then
  dirty=()
  for sub in "$DEST"/*/; do
    sub="${sub%/}"
    [[ -f "$sub/.git" && -n "$(git -C "$sub" status --porcelain 2>/dev/null)" ]] && dirty+=("$sub")
  done
  if [[ -f "$DEST/.git" ]]; then
    while IFS= read -r line; do
      [[ "$line" == "?? "* ]] && swept "${line:3}" && continue
      dirty+=("$DEST"); break
    done < <(git -C "$DEST" status --porcelain -uall 2>/dev/null)
  fi
  if [[ "${#dirty[@]}" -gt 0 ]]; then
    err "uncommitted work in: ${dirty[*]}"
    die "nothing was removed — commit or stash it, then re-run (--force discards it)"
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
# When $DEST is itself a root checkout (below), a symlink it TRACKS is the repo's, not
# a wrapper: deleting it made the checkout dirty and its removal refused.
tracked_links=""
[[ -f "$DEST/.git" ]] && tracked_links="$(git -C "$DEST" ls-files -s -z | tr "\0" "\n" | awk -F'\t' '$1 ~ /^120000 / {print $2}')"
while IFS= read -r l; do
  grep -qxF -- "${l#"$DEST"/}" <<<"$tracked_links" || rm -f "$l"
done < <(find "$DEST" -type l 2>/dev/null)
# .wt-slot: the slot number. .wt-branch: the branch `new` created, which
# `down --delete-branch` needs and cannot re-derive (git answers with whatever
# is checked out at teardown, not with what the worktree was made for).
rm -f "$DEST/.wt-slot" "$DEST/.wt-branch"
# The slot env file worktree.sh writes, and ONLY that one: it is matched by the
# marker its generator puts on line 1, never by name. A project's own .env that
# somehow landed here is the user's file and is left in place: in a plain directory
# it blocks removal (the check below). In a root checkout it does NOT: `create`
# excludes /.env, so the dirty check never sees it and `git worktree remove` deletes
# it as an ignored file. Known limit of a `--no-infra` worktree (BL-770, owner Q48).
if [[ -f "$DEST/.env" ]] && is_generated_env; then
  rm -f "$DEST/.env"
fi
# Files materialized by --copy are this tool's too. They are named on the
# command line, so removal is explicit rather than a recursive guess. Except one
# the root checkout TRACKS: `create` skipped it, so it is the repo's file, and
# deleting it threw away any edit to it and made `git worktree remove` refuse.
# -r: create copies with cp -R, so an entry may be a directory.
for c in "${COPIES[@]:-}"; do
  [[ -n "$c" ]] || continue
  [[ -f "$DEST/.git" ]] && git -C "$DEST" ls-files --error-unmatch -- "$c" >/dev/null 2>&1 && continue
  rm -rf "$DEST/$c"
done
find "$DEST" -type d -empty -delete 2>/dev/null

# $DEST may itself be a linked worktree, not just a directory holding them: a
# project whose ROOT repo owns .context/ gets a root checkout at $DEST so the
# worktree has one (BL-259's shape; the 2026-08-28 manual workaround did it by
# hand). It is not in WT_PARTICIPANTS, so the loop above never saw it, and
# `down` left a live worktree behind with its slot still claimed — freeing it
# took a manual `git worktree remove`.
#
# It goes LAST on purpose. The marker and symlink sweep above is what makes the
# checkout clean, and `git worktree remove` refuses a worktree with untracked
# files — so removing $DEST first would refuse on this tool's own leftovers.
if [[ -f "$DEST/.git" ]]; then
  common="$(git -C "$DEST" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -z "$common" ]]; then
    warn "skipping $DEST — it looks like a worktree but its main repo cannot be resolved"
  else
    main_tree="$(dirname "$common")"
    if $FORCE_RM; then
      warn "--force: discarding any uncommitted work in $DEST"
      git -C "$main_tree" worktree remove --force "$DEST"
    else
      git -C "$main_tree" worktree remove "$DEST"
    fi
    ok "removed root checkout: $DEST"
  fi
fi

if [[ -d "$DEST" ]]; then
  err "$DEST still exists after removal — it holds files this tool did not create:"
  find "$DEST" -mindepth 1 -maxdepth 2 | sed 's|^|    |' >&2
  err "inspect and remove it yourself (never force-deleted)"
  exit 1
fi
ok "removed $DEST"
exit 0
