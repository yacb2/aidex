#!/usr/bin/env bash
# worktree.sh — create and destroy fully isolated worktrees, one path only.
#
# WHY THIS EXISTS. The skill used to *describe* a recipe and leave each project
# to hand-write its own worktree-up.sh. Every project then implemented it
# differently and wrong: images pinned to the main project, container names that
# could not be namespaced, ports that could not move, teardowns that skipped the
# resources no `compose down` reclaims. Measured across a real workspace, all 15
# projects with a compose file shipped a stack that could not run a second copy
# of itself. A recipe that every reader implements differently is not a recipe.
#
# So the mechanism lives HERE, and a project supplies only parameters
# (.context/worktrees/config.env). There is no tier interview and no tier
# decision: a worktree is born with its full isolated stack, always. `--no-infra`
# is the explicit opt-out for the rare code-only case.
#
# Usage:
#   worktree.sh new  <slug> --branch <branch> [--repo R]... [--no-infra] [--slot N]
#   worktree.sh up   <slug>
#   worktree.sh down <slug> [--keep-dir] [--force] [--reap] [--delete-branch]
#   worktree.sh list [--porcelain]
#
#   new  : allocate a free port slot, create one git worktree per participant,
#          link the unversioned wrapper files, bring the isolated stack up.
#   up   : bring an EXISTING worktree's stack back on its recorded slot. Without
#          it, a worktree whose stack is down has no way back and the directory
#          is stranded — the state a failed `down` leaves behind.
#   down : tear the stack down INCLUDING what compose does not reclaim, verify
#          nothing is left attributable to the slug, then remove the directory.
#          --force discards uncommitted work (git refuses otherwise). NEVER pass
#          it without the user asking: it destroys work no one can recover.
#          Host processes still holding the directory are REPORTED, never killed;
#          --reap opts into killing them, always by PID and only the ones just
#          reported. There is deliberately no way to kill by name: `pkill vite`
#          takes the main tree's dev server and every sibling project's with it.
#          --delete-branch also deletes the worktree's branch in each participant
#          repo, with `git branch -d` — which refuses an unmerged branch, so it is
#          its own merged-ness gate and no separate check is invented. Only the
#          branch `new` created is ever a candidate: it is recorded in .wt-branch
#          at creation, and a checkout that has since moved on is skipped with a
#          warning rather than having its current branch deleted. Default off:
#          the branch is the only trace a torn-down worktree leaves, and deleting
#          it by default would destroy unmerged work. This deliberately does NOT
#          merge anything — an unrequested merge consumes the review window the
#          worktree existed to create.
#   list : every worktree with slot, branch, stack state, and whether it holds
#          uncommitted work. --porcelain emits one tab-separated record per
#          worktree for a supervising agent to parse.
#
# SUPERVISION. These worktrees are created and destroyed by an agent, not by a
# person reading errors at a prompt. So every state must be both recoverable and
# legible: `list --porcelain` reports what is actually true, `up` recovers a
# stack that went down, and a claim is released only when the worktree is really
# gone — never leaving a slot free while its directory still exists.
#
# Config (.context/worktrees/config.env), all optional except WT_PARTICIPANTS:
#   WT_PARTICIPANTS   "backend frontend"     repos that can participate
#   WT_LINKS          "docker-compose.yml dev.sh .docker"
#                                            unversioned wrapper paths to symlink
#   WT_COPIES         "backend/poetry.lock"  same, but COPIED — for files a Docker
#                                            build context reads (it cannot follow a
#                                            symlink that escapes the context)
#   WT_SERVICES       "db backend"           services to start (must cover every
#                                            profile-less compose service)
#   WT_SERVICES_BY_HOOK "backend-test # <what starts it>"
#                                            profile-gated services that legitimately
#                                            run here; allowlist for the running check
#   WT_SERVICES_EXCLUDE "heavy-svc # <reason>"
#                                            profile-less services deliberately NOT
#                                            started; the reason is required
#   WT_ENV_RENDER     "frontend/.env.local"  host env files rendered per slot from
#                                            .context/worktrees/env-templates/<path>.tmpl
#   WT_PORT_VARS      "DB_PORT=4400 BACKEND_PORT=4500"
#                                            var=dev-base pairs; slot N adds N*WT_PORT_STRIDE
#   WT_PORT_STRIDE    100                    per-slot offset
#   WT_MAX_SLOTS      9
#   WT_SUFFIX_VAR     WT_SUFFIX              var carrying -<slug> into container_name
#   WT_SEED_CMD       ""                     shell run inside the new stack to seed data
#   WT_READY_CMD      ""                     shell that must succeed before seeding
#   WT_POST_CMD       ""                     shell run after seeding (E2E template, fixtures)
#   WT_PRE_DOWN_CMD   ""                     shell run in the worktree BEFORE the Docker
#                                            teardown; its failure is reported, not fatal

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$(cd "$SELF_DIR/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
set +e   # this script reports and decides; it does not want inherited errexit

SWEEP="$SELF_DIR/orphan-sweep.sh"
SNAP="$SELF_DIR/docker-snapshot.sh"
MULTI="$SELF_DIR/worktree-multi.sh"

cmd="${1:-}"; shift 2>/dev/null
case "$cmd" in new|up|down|list) ;; *) sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;; esac

ROOT="$(find_project_root)"
PROJECT="$(basename "$ROOT")"
CONFIG="$ROOT/.context/worktrees/config.env"

# --- defaults, then the project's own values ---
WT_PARTICIPANTS=""; WT_LINKS=""; WT_COPIES=""; WT_SERVICES=""
WT_SERVICES_BY_HOOK=""; WT_SERVICES_EXCLUDE=""; WT_ENV_RENDER=""
WT_PORT_VARS=""; WT_PORT_STRIDE=100; WT_MAX_SLOTS=9
WT_SUFFIX_VAR="WT_SUFFIX"; WT_SEED_CMD=""; WT_READY_CMD=""; WT_POST_CMD=""; WT_PRE_DOWN_CMD=""
# `set -a` so everything the project defines here is EXPORTED. WT_READY_CMD and
# WT_SEED_CMD run in a subshell, so a plain shell variable would be empty there
# — a profile that referenced its own $WT_DB_USER probed as an empty role, never
# became ready, and rolled back after 60s. Exporting makes a project's own
# config values usable by its own commands, which is the least surprising rule.
set -a
# A project may declare WT_PROFILE="<name>" to LOAD a family profile from this
# skill rather than copy it. Loaded first so the project's own config.env wins
# on every line — the override path is "state the value plus the reason".
#
# Copying was the old shape and it did not work: this script read only
# config.env, so a fix to the profile reached zero existing projects and each
# project quietly held its own drifted copy of "the family default" — the same
# failure the shipped mechanism was built to end, one level up.
#
# grep, not source, for the peek: config.env has not been vetted yet at this
# point, and reading one declarative line is all that is needed to find the
# profile.
if [[ -f "$CONFIG" ]]; then
  _prof="$(sed -n 's/^[[:space:]]*WT_PROFILE=["'"'"']\{0,1\}\([A-Za-z0-9._-]*\).*/\1/p' "$CONFIG" | head -1)"
  if [[ -n "$_prof" ]]; then
    _profile_file="$SELF_DIR/../assets/profiles/$_prof.defaults.env"
    if [[ -f "$_profile_file" ]]; then
      . "$_profile_file"
    else
      set +a
      die "config.env declares WT_PROFILE=\"$_prof\" but no such profile ships with this skill (looked for $_profile_file)"
    fi
  fi
  . "$CONFIG"
fi
set +a

# A profile is a template with holes in it. Filling none of them and running
# anyway is the failure mode a copied profile invites: the readiness probe then
# authenticates as a role literally named CHANGEME_user, times out after 60s and
# rolls the whole create back, reporting nothing about why.
_unfilled=""
for _v in WT_PARTICIPANTS WT_DB_USER WT_DB_NAME WT_LINKS WT_PORT_VARS WT_SERVICES; do
  case "${!_v:-}" in *CHANGEME*) _unfilled="$_unfilled $_v" ;; esac
done
if [[ -n "$_unfilled" ]]; then
  err "config.env still carries profile placeholders:$_unfilled"
  err "Fill them from the project's compose file (DB identity), a live port probe"
  err "(port band) and a deliberate decision (participants, services). Config: $CONFIG"
  exit 2
fi

SLUG=""; BRANCH=""; SLOT=""; NO_INFRA=false; KEEP_DIR=false; FORCE=false; PORCELAIN=false; REAP=false; DELETE_BRANCH=false
REPOS=()
[[ $# -gt 0 && "$1" != -* ]] && { SLUG="$1"; shift; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2-}"; shift 2 ;;
    --repo)   REPOS+=("${2-}"); shift 2 ;;
    --slot)   SLOT="${2-}"; shift 2 ;;
    --no-infra) NO_INFRA=true; shift ;;
    --keep-dir) KEEP_DIR=true; shift ;;
    --force) FORCE=true; shift ;;
    --reap) REAP=true; shift ;;
    --delete-branch) DELETE_BRANCH=true; shift ;;
    --porcelain) PORCELAIN=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

DEST_FOR() { printf '%s/../%s-wt-%s\n' "$ROOT" "$PROJECT" "$1"; }
PROJ_FOR() { printf '%s-wt-%s\n' "$PROJECT" "$1"; }

# ---------------------------------------------------------------- list
#
# Reports what is TRUE, not what was intended: a directory can exist with its
# stack down (a failed teardown leaves exactly that), and a worktree can hold
# uncommitted work that blocks its own removal. A supervising agent needs both
# facts before it decides anything, so both are columns.
SLOTDIR_FOR() { printf '%s/aidex-wt-slots-%s\n' "${TMPDIR:-/tmp}" "$PROJECT"; }
CLAIMED_SLOT() {  # slug -> slot number held in the claim files, or ""
  local sl f
  for f in "$(SLOTDIR_FOR)"/slot-*; do
    [[ -e "$f" ]] || continue
    [[ "$(awk '{print $2}' "$f" 2>/dev/null)" == "$1" ]] && { sl="$(basename "$f")"; printf '%s' "${sl#slot-}"; return 0; }
  done
  return 1
}
IS_DIRTY() {  # dest -> 0 when any participant has uncommitted or untracked work
  local d="$1" p
  for p in $WT_PARTICIPANTS; do
    [[ -d "$d/$(basename "$p")" ]] || continue
    [[ -n "$(git -C "$d/$(basename "$p")" status --porcelain 2>/dev/null)" ]] && return 0
  done
  return 1
}

if [[ "$cmd" == "list" ]]; then
  found=0
  hdr() { $PORCELAIN && return 0; [[ "$found" -eq 0 ]] && printf '%-20s %-5s %-28s %-9s %-7s %s\n' SLUG SLOT BRANCH STACK DIRTY DIR; }
  for d in "$ROOT"/../"$PROJECT"-wt-*; do
    [[ -d "$d" ]] || continue
    hdr; found=1
    sg="$(basename "$d")"; sg="${sg#${PROJECT}-wt-}"

    # A directory is not a worktree. A dev server that outlived the teardown
    # rewrote frontend/.vite/deps/ and so recreated the tree it had been started
    # in; `list` then showed a row for something git has never heard of, and an
    # agent reading that row would try to `up` a worktree that does not exist.
    #
    # BOTH signals must be absent, and that is the whole difficulty: either one
    # alone marks ordinary states as stray. `--keep-dir` deliberately leaves the
    # directory with its claim, and a failed removal leaves exactly the same
    # shape — the claim is held precisely so the state stays resumable. Absent
    # registration alone would condemn both.
    #
    # $d comes from a glob rooted at "$ROOT/.." so it is not canonical; git
    # prints resolved paths, and comparing the two forms directly matches
    # nothing.
    #
    # The SOURCE repo is at "$ROOT/<participant>" with the participant's full
    # relative path — that is where worktree-multi.sh runs `worktree add`, and a
    # nested participant like `apps/backend` does not live at "$ROOT/backend".
    # Its worktree copy, though, is at "$DEST/<basename>", which is why the grep
    # anchors on the directory and not on a full path.
    dr="$( cd "$d" && pwd -P )"
    registered=false
    for pp in $WT_PARTICIPANTS; do
      git -C "$ROOT/$pp" worktree list --porcelain 2>/dev/null \
        | grep -q "^worktree $dr/" && { registered=true; break; }
    done
    if ! $registered && ! CLAIMED_SLOT "$sg" >/dev/null; then
      if $PORCELAIN; then printf '%s\t-\t-\t-\tno\tSTRAY-DIR:%s\n' "$sg" "$d"
      else warn "'$sg' is a directory with no git worktree and no slot claim — something recreated it after the teardown; it is not a worktree: $d"; fi
      continue
    fi

    slot="$(cat "$d/.wt-slot" 2>/dev/null || CLAIMED_SLOT "$sg" || echo '-')"
    br="$(git -C "$d/$(echo "$WT_PARTICIPANTS" | awk '{print $1}')" branch --show-current 2>/dev/null || echo '-')"
    n_up="$(docker ps -q --filter "label=com.docker.compose.project=$(PROJ_FOR "$sg")" 2>/dev/null | wc -l | tr -d ' ')"
    stack="down"; [[ "${n_up:-0}" -gt 0 ]] && stack="up:$n_up"
    dirty=no; IS_DIRTY "$d" && dirty=YES
    if $PORCELAIN; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sg" "$slot" "$br" "$stack" "$dirty" "$d"
    else
      printf '%-20s %-5s %-28s %-9s %-7s %s\n' "$sg" "$slot" "$br" "$stack" "$dirty" "$d"
    fi
  done
  # A claim with no directory is a leak the agent must see, not a silent oddity.
  for f in "$(SLOTDIR_FOR)"/slot-*; do
    [[ -e "$f" ]] || continue
    cs="$(awk '{print $2}' "$f" 2>/dev/null)"
    [[ -d "$(DEST_FOR "$cs")" ]] && continue
    found=1
    if $PORCELAIN; then printf '%s\t%s\t-\t-\tno\tMISSING-DIR\n' "$cs" "$(basename "$f" | sed 's/slot-//')"
    else warn "claim for '$cs' (slot $(basename "$f" | sed 's/slot-//')) has no directory — run: worktree.sh down $cs"; fi
  done
  [[ "$found" -eq 1 ]] || { $PORCELAIN || echo "no worktrees for $PROJECT"; }
  exit 0
fi

[[ -n "$SLUG" ]] || die "a <slug> is required"
is_valid_slug "$SLUG" || die "invalid slug: $SLUG (kebab-case, [a-z0-9-])"
case "$SLUG" in "$PROJECT"|dev|prod|main) die "refusing dev/prod-like slug: $SLUG" ;; esac

DEST="$(cd "$(dirname "$(DEST_FOR "$SLUG")")" && pwd -P)/$(basename "$(DEST_FOR "$SLUG")")"
CPROJ="$(PROJ_FOR "$SLUG")"

# port_env SLOT -> prints "VAR=value" per line for that slot
port_env() {
  local slot="$1" pair var base
  for pair in $WT_PORT_VARS; do
    var="${pair%%=*}"; base="${pair##*=}"
    printf '%s=%s\n' "$var" "$(( base + slot * WT_PORT_STRIDE ))"
  done
}

# The offset scheme is only sound when one slot's whole port block clears the
# next one's. With bases spanning 4400..4610 and a stride of 100, slot 1's
# DB_PORT lands on 4500 — dev's BACKEND_PORT. The probe caught it and skipped to
# slot 2, so it merely looked like "slot 1 was busy": a structural
# misconfiguration wearing the costume of a transient collision. Assert the
# invariant instead of letting the allocator paper over it.
assert_port_scheme() {
  [[ -n "$WT_PORT_VARS" ]] || return 0
  local pair base min="" max=""
  for pair in $WT_PORT_VARS; do
    base="${pair##*=}"
    [[ -z "$min" || "$base" -lt "$min" ]] && min="$base"
    [[ -z "$max" || "$base" -gt "$max" ]] && max="$base"
  done
  local span=$(( max - min ))
  if [[ "$WT_PORT_STRIDE" -le "$span" ]]; then
    err "WT_PORT_STRIDE=$WT_PORT_STRIDE does not clear the port bases (span $min..$max = $span)."
    err "Slot N would reuse a port from slot N-1's block. Set WT_PORT_STRIDE > $span,"
    err "or move the bases into a window narrower than the stride. Config: $CONFIG"
    exit 2
  fi
}
assert_port_scheme

# --- services parity: the three-class partition -------------------------------
#
# `WT_SERVICES` was a static "db backend", with the profile's instruction to
# override it per project left in prose. Two of the three field projects with an
# always-on worker never did, and the symptom was silent: a worktree whose queue
# never drained, for five hours, with every port check passing. A comment can
# assert anything about the compose file; nothing compared the two.
#
# Every compose service lands in exactly one class:
#   start-at-create  no `profiles:` key       -> MUST be in WT_SERVICES (or EXCLUDE)
#   start-by-hook    profile-gated, but a project workflow legitimately starts it
#                    here                     -> declared in WT_SERVICES_BY_HOOK
#   on-demand        profile-gated, nobody starts it -> in neither
#
# The derivation needs NO parser and no second source of truth: `docker compose
# config --services` WITHOUT a --profile flag returns exactly the profile-less
# set — compose's own definition of what a bare `up -d` starts. Verified
# 2026-08-21 against an independent YAML parse of all five field projects: same
# set, five for five. It is a client-side parse, so it works with Docker closed;
# do not gate it behind a daemon check.
#
# Both declaration lists are "<names...> # <reason>": names before the '#', one
# reason covering them. The reason is what keeps an escape from becoming the
# default, so a list without one is itself a refusal.
decl_names() { printf '%s\n' "${1%%#*}" | tr -s ' \t' '\n' | sed '/^$/d' | tr '\n' ' '; }

assert_services_declared() {
  local dir="$1" svc at_create declared missing="" list
  # The reason gate is checked FIRST, and unconditionally: it reads only the
  # config, so an unreadable compose file must not disable it. Ordering these the
  # other way round silently restored the free escape hatch on exactly the
  # projects whose compose the derivation could not read.
  for list in WT_SERVICES_EXCLUDE WT_SERVICES_BY_HOOK; do
    [[ -z "${!list}" ]] && continue
    case "${!list}" in
      *"#"*) [[ -n "$(printf '%s' "${!list#*#}" | tr -d ' \t')" ]] && continue ;;
    esac
    err "$list carries no '# reason': ${!list}"
    err "Write it as: $list=\"<service> # <why>\". Config: $CONFIG"
    return 1
  done

  at_create="$( cd "$dir" && docker compose config --services 2>/dev/null )"
  # Fails OPEN, deliberately and narrowly: an unreadable compose file is the
  # `docker compose up` below failing anyway, with a better message than this
  # check could produce. It must never be the reason a reason-less escape passes,
  # which is why the loop above already ran.
  [[ -n "$at_create" ]] || return 0

  declared=" $(decl_names "$WT_SERVICES")$(decl_names "$WT_SERVICES_EXCLUDE")"
  for svc in $at_create; do
    case "$declared" in *" $svc "*) ;; *) missing="$missing $svc" ;; esac
  done
  [[ -z "$missing" ]] && return 0

  err "services parity: dev starts$missing here, and this worktree would not."
  err "They carry no 'profiles:' key, so a bare 'docker compose up -d' starts"
  err "them; WT_SERVICES does not list them. The result is a worktree that looks"
  err "healthy and diverges silently — no port check can see it."
  err ""
  err "Start them too:"
  err "  WT_SERVICES=\"$(decl_names "$WT_SERVICES" | sed 's/ $//')$missing\""
  err "or, if one is deliberately not wanted here, say why:"
  for svc in $missing; do
    err "  WT_SERVICES_EXCLUDE=\"$svc # <reason it is not needed in a worktree>\""
  done
  err ""
  err "Config: $CONFIG"
  return 1
}

# The running check compares the config against REALITY, which is the half that
# catches the compose file changing under a config that did not.
#
# Two directions, and they are different assertions:
#   running MUST cover WT_SERVICES ................ a declared service that never
#     came up is the original symptom itself (a crash loop looks like this)
#   running MUST NOT exceed WT_SERVICES u BY_HOOK . something profile-gated is up
#     that nobody declared — e.g. echo_lab's `worker`, whose `ai` profile makes
#     paid API calls
#
# BY_HOOK is an ALLOWLIST, never a requirement. The plan that specified it
# assumed `WT_POST_CMD` starts `backend-test`; it does not — the profile's
# `./test-e2e.sh --setup-template` uses `docker compose run --rm backend`
# throwaways, and `backend-test` is started later by the full E2E run (by
# test-e2e.sh in echo_lab/work_hours, by Playwright's globalSetup in the other
# three). Requiring BY_HOOK members to be running would fail every fresh create.
# Field-checked 2026-08-21 on both live echo_lab worktrees: `ps --services`
# lists `backend-test` with no --profile flag, so the allowlist has real work.
assert_services_running() {
  local dir="$1" svc running allowed down="" extra=""
  running="$( cd "$dir" && env "${envs[@]}" docker compose ps --services 2>/dev/null | tr '\n' ' ' )"
  # An EMPTY set is not "nothing to check" -- it is every declared service being
  # down at once, which is the loudest form of the very defect this function is
  # for (a stack that crash-looped out, or a daemon that went away). Returning 0
  # here made the check blind precisely where it mattered most, and `up` has no
  # readiness failure path, so it would have printed "stack up" and exited 0.
  if [[ -z "$running" ]]; then
    [[ -z "$(decl_names "$WT_SERVICES")" ]] && return 0
    err "services parity: NOTHING is running in $dir, but WT_SERVICES declares $(decl_names "$WT_SERVICES")."
    err "The stack is down or every container exited. Read 'docker compose logs' there."
    return 1
  fi

  for svc in $(decl_names "$WT_SERVICES"); do
    case " $running " in *" $svc "*) ;; *) down="$down $svc" ;; esac
  done
  # EXCLUDE members belong here too: they are profile-LESS, so `depends_on`
  # can pull one in implicitly even though nobody named it on the command
  # line. Without them the check would report an excluded service as
  # "profile-gated, declared nowhere" and print the wrong line to add.
  allowed=" $(decl_names "$WT_SERVICES")$(decl_names "$WT_SERVICES_BY_HOOK")$(decl_names "$WT_SERVICES_EXCLUDE")"
  for svc in $running; do
    case "$allowed" in *" $svc "*) ;; *) extra="$extra $svc" ;; esac
  done

  if [[ -n "$down" ]]; then
    err "services parity: WT_SERVICES declares$down, but they are not running."
    err "Running: $running"
    err "Read 'docker compose logs' in $dir — a crash loop looks exactly like this."
    # `return 1`, not `exit 2`. This is a predicate with two callers: `up` writes
    # `|| exit 2` and still exits 2, so nothing changes there; `new` writes
    # `|| parity_rc=3` precisely so the failure is reported AFTER the worktree
    # handle is printed. Exiting here bypassed that and stranded a created
    # worktree with its slot still claimed -- the failure the comment at the
    # `new` call site claims to have fixed.
    return 1
  fi
  [[ -z "$extra" ]] && return 0

  err "services parity: profile-gated service(s)$extra are running here but are"
  err "declared nowhere. Running what dev does not is as much a divergence as"
  err "missing what dev does, and an undeclared profile can carry live credentials."
  err ""
  err "If a project workflow legitimately starts it here, name what starts it:"
  for svc in $extra; do
    err "  WT_SERVICES_BY_HOOK=\"$svc # started by <command>\""
  done
  err "Otherwise stop it:  docker compose --profile '*' stop$extra"
  err ""
  err "Config: $CONFIG"
  return 1
}

# --- the slot's environment, as a file the worktree carries -------------------
#
# Everything this script runs, it runs through `env "${envs[@]}"`. Anything run
# LATER — by a person, by an agent, by a gate in a plan — does not inherit that,
# and a bare `docker compose` in the worktree then resolves the project from the
# directory name (correct) but every container_name and port from the compose
# defaults (DEV's). Field-observed twice: a `docker compose up -d db` inside a
# worktree recreated the db container on dev's port, and a project's own
# `test-e2e.sh` invoked there drove dev's database while believing it was
# isolated. `new` succeeding proves nothing about this — it never takes the path.
#
# Compose auto-loads `.env` from the project directory, which IS the worktree
# root, so one file fixes every later compose call. Project scripts source the
# same file, for the same reason.
WT_ENV_MARKER='# generated by aidex worktree.sh — regenerated on `up`, do not edit'
#
# A project that links its own root .env into the worktree would have it
# clobbered. Refuse at config-load time, before anything is created, rather than
# win silently: the mechanism cannot know which of the two the project meant.
case " $WT_LINKS " in
  *" .env "*) err "WT_LINKS contains .env, which collides with the slot env file worktree.sh writes into the worktree root."
              err "Remove it from WT_LINKS, or have the project read those values from a differently-named file. Config: $CONFIG"
              exit 2 ;;
esac
write_wt_env() {
  local dest="$1" slot="$2" f="$1/.env"
  if [[ -e "$f" || -L "$f" ]] && ! head -1 "$f" 2>/dev/null | grep -qF -- "$WT_ENV_MARKER"; then
    die "$f exists and was not written by worktree.sh — refusing to overwrite it"
  fi
  { echo "$WT_ENV_MARKER"
    echo "COMPOSE_PROJECT_NAME=$CPROJ"
    echo "$WT_SUFFIX_VAR=-$SLUG"
    port_env "$slot"
  } > "$f"
}

# --- slot-dependent host env files: rendered, never linked or copied ----------
#
# `write_wt_env` above generates the worktree root `.env` -- everything Compose
# needs, and nothing else. The HOST half of the stack reads its own env file
# (`frontend/.env.local`), and no mechanism produced it. Neither list can supply
# one: WT_LINKS gives a symlink to the main tree's file and WT_COPIES a copy of
# it, and both carry the MAIN TREE's ports. The values are slot-dependent, which
# is exactly why they ended up hand-written.
#
# The cost of hand-writing, field-observed 2026-08-21: the two live echo_lab
# worktrees held two DIFFERENT files. One documented that VITE_API_URL must be
# absolute and name this slot's backend port -- a relative URL makes the Vite dev
# server answer `/auth/login/` with index.html, so login silently never happens
# -- and that Vite does not load .env.local into process.env. The other carried
# the same values with none of the warnings. A future worktree inherits whichever
# its author happens to copy.
#
# So: one template per destination, rendered with the slot environment. The
# knowledge lives in the template, where every worktree gets it.
#
# Templates use `${VAR}` and ONLY `${VAR}`. The bare `$VAR` form is deliberately
# unsupported: it cannot be substituted safely without word-boundary handling,
# and `$FRONTEND_PORT` is a prefix of nothing today but would be tomorrow.

# The COMPLETE set of variables a template may reference. Declared explicitly
# rather than inherited from the ambient environment on purpose: a template that
# silently picked up a variable from the invoking shell would render differently
# for two people on the same slot, which is the class of bug this replaces.
slot_env_pairs() {  # slot_env_pairs <slot> -> VAR=VALUE per line
  port_env "$1"
  printf 'COMPOSE_PROJECT_NAME=%s\n' "$CPROJ"
  printf '%s=-%s\n' "$WT_SUFFIX_VAR" "$SLUG"
  printf 'WT_SLUG=%s\n' "$SLUG"
  printf 'WT_SLOT=%s\n' "$1"
}

render_env_files() {  # render_env_files <worktree-dir> <slot>
  [[ -n "${WT_ENV_RENDER:-}" ]] || return 0
  local dir="$1" slot="$2" rel tmpl dest part inner pairs names refs missing v val script

  pairs="$(slot_env_pairs "$slot")"
  names=" $(printf '%s\n' "$pairs" | cut -d= -f1 | tr '\n' ' ')"

  for rel in $WT_ENV_RENDER; do
    tmpl="$ROOT/.context/worktrees/env-templates/$rel.tmpl"
    dest="$dir/$rel"

    [[ -f "$tmpl" ]] || { err "WT_ENV_RENDER lists '$rel' but its template is missing: $tmpl"; return 1; }

    # A destination that is ALSO linked or copied gets two writers, and the last
    # one wins silently. Refuse rather than pick one.
    case " $WT_LINKS $WT_COPIES " in
      *" $rel "*) err "WT_ENV_RENDER and WT_LINKS/WT_COPIES both claim '$rel' -- remove it from one. Config: $CONFIG"; return 1 ;;
    esac

    # A rendered file MUST be gitignored. `git worktree remove` refuses a tree
    # holding untracked non-ignored files, so rendering into a tracked path
    # builds a worktree that can be created and then never torn down -- a failure
    # that surfaces at teardown, long after its cause.
    part="${rel%%/*}"; inner="${rel#*/}"
    if [[ "$part" != "$rel" && -e "$ROOT/$part/.git" ]]; then
      if ! git -C "$ROOT/$part" check-ignore -q "$inner" 2>/dev/null; then
        err "WT_ENV_RENDER destination '$rel' is NOT gitignored in the '$part' repo."
        err "git worktree remove refuses a tree with untracked non-ignored files, so"
        err "this worktree could be created and then never torn down. Add it to"
        err "$part/.gitignore, or render somewhere already ignored. Config: $CONFIG"
        return 1
      fi
    fi

    # Every ${VAR} the template names must exist in the slot environment. A hole
    # rendered as an empty string is worse than a failed create: the file looks
    # right and the app fails somewhere else entirely.
    refs="$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$tmpl" 2>/dev/null | tr -d '${}' | sort -u)"
    missing=""
    for v in $refs; do
      case "$names" in *" $v "*) ;; *) missing="$missing $v" ;; esac
    done
    if [[ -n "$missing" ]]; then
      err "template $rel.tmpl references variable(s)$missing that the slot environment does not define."
      err "Available: $(printf '%s' "$names" | sed 's/^ //;s/ $//')"
      err "An undefined variable renders as an empty string and fails somewhere else."
      return 1
    fi

    mkdir -p "$(dirname "$dest")"
    if [[ -e "$dest" || -L "$dest" ]] && ! head -1 "$dest" 2>/dev/null | grep -qF -- "$WT_ENV_MARKER"; then
      { err "$dest exists and was not written by worktree.sh -- refusing to overwrite it"; return 1; }
    fi

    script=""
    while IFS='=' read -r v val; do
      [[ -z "$v" ]] && continue
      script="${script}s|\\\${${v}}|${val}|g;"
    done <<< "$pairs"

    { echo "$WT_ENV_MARKER"; sed "$script" "$tmpl"; } > "$dest"
    ok "rendered $rel (slot $slot)"
  done
}

# ---------------------------------------------------------------- up
#
# A worktree whose stack is down used to have no way back: `new` refuses an
# existing destination, so the directory was stranded. That is precisely the
# state a failed teardown leaves (git refuses to remove a dirty worktree AFTER
# the stack is already down), and it is the state an agent most needs to be able
# to resolve without discarding anything.
if [[ "$cmd" == "up" ]]; then
  [[ -d "$DEST" ]] || die "no worktree directory at $DEST — use: worktree.sh new $SLUG --branch <b>"
  # Before the slot claim: a refusal must leave no state behind. The compose
  # file lives in the worktree (linked), so the derivation reads the same one
  # the `up` below will.
  assert_services_declared "$DEST" || exit 2
  SLOT="${SLOT:-$(cat "$DEST/.wt-slot" 2>/dev/null || CLAIMED_SLOT "$SLUG" || echo '')}"
  [[ -n "$SLOT" ]] || die "no slot recorded for $SLUG (missing .wt-slot and no claim) — pass --slot N"

  # Re-assert the claim: the slot is ours again while the stack is up.
  SLOTDIR="$(SLOTDIR_FOR)"; mkdir -p "$SLOTDIR"
  other="$(awk '{print $2}' "$SLOTDIR/slot-$SLOT" 2>/dev/null)"
  [[ -n "$other" && "$other" != "$SLUG" ]] && die "slot $SLOT is held by '$other' — free it first"
  printf '%s %s\n' "$$" "$SLUG" > "$SLOTDIR/slot-$SLOT"
  echo "$SLOT" > "$DEST/.wt-slot"
  write_wt_env "$DEST" "$SLOT"
  render_env_files "$DEST" "$SLOT" || exit 2

  envs=(COMPOSE_PROJECT_NAME="$CPROJ" "$WT_SUFFIX_VAR=-$SLUG")
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done < <(port_env "$SLOT")
  ( cd "$DEST" && env "${envs[@]}" docker compose up -d ${WT_SERVICES:-} ) || die "stack failed to start"
  if [[ -n "$WT_READY_CMD" ]]; then
    for i in $(seq 1 60); do
      ( cd "$DEST" && env "${envs[@]}" bash -c "$WT_READY_CMD" ) >/dev/null 2>&1 && { ok "ready after ${i}s"; break; }
      sleep 1
    done
  fi
  assert_services_running "$DEST" || exit 2
  ok "stack up: $CPROJ (slot $SLOT)"
  port_env "$SLOT" | sed 's/^/  port     /'
  exit 0
fi

# ---------------------------------------------------------------- new
if [[ "$cmd" == "new" ]]; then
  [[ -n "$BRANCH" ]] || die "new requires --branch"
  [[ -e "$DEST" ]] && die "destination already exists: $DEST"
  # Before the worktree exists, so the derivation reads the MAIN tree's compose
  # file — the same one WT_LINKS is about to link in. A refusal here creates
  # nothing, which is why it comes before the branch resolution below.
  # Fast-fail courtesy check against the MAIN tree, so the common case refuses
  # before anything is created. It is not authoritative: the worktree checks out
  # $BRANCH, whose docker-compose.yml may declare a different service set. The
  # authoritative check runs against $DEST after checkout, below.
  # Skipped under --no-infra, which starts no stack at all -- refusing there
  # complains about services it would never have started.
  $NO_INFRA || assert_services_declared "$ROOT" || exit 2
  [[ "${#REPOS[@]}" -gt 0 ]] || read -r -a REPOS <<< "$WT_PARTICIPANTS"
  [[ "${#REPOS[@]}" -gt 0 ]] || die "no participants: pass --repo or set WT_PARTICIPANTS in $CONFIG"

  # --- base branch, stated not inherited ---
  first="${REPOS[0]}"
  default_branch="$(git -C "$ROOT/$first" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  [[ -n "$default_branch" ]] || default_branch="$(git -C "$ROOT/$first" branch --show-current 2>/dev/null)"
  info "base $default_branch -> worktree $CPROJ · branch $BRANCH · participants: ${REPOS[*]}"

  # --- slot RESERVATION -----------------------------------------------------
  #
  # A port probe alone cannot allocate. Five concurrent creations all probed,
  # all saw the same free ports, and four picked slot 2 — three of them died on
  # `Bind for 0.0.0.0:4420 failed: port is already allocated`. The previous lock
  # made it worse in two ways: it was held for the WHOLE run (~25s), so
  # contenders exhausted their 10s wait, and it then let them continue WITHOUT
  # the lock instead of failing. A silent degradation under exactly the load it
  # existed for.
  #
  # So: hold the lock only around the reservation, and reserve by writing a
  # claim file — the claim is what makes the choice visible to the next process
  # before this one has bound anything.
  if ! $NO_INFRA && [[ -n "$WT_PORT_VARS" ]]; then
    SLOTDIR="${TMPDIR:-/tmp}/aidex-wt-slots-${PROJECT}"
    LOCK="$SLOTDIR/.lock"
    mkdir -p "$SLOTDIR"

    locked=false
    for _ in $(seq 1 300); do mkdir "$LOCK" 2>/dev/null && { locked=true; break; }; sleep 0.1; done
    $locked || die "could not acquire the slot lock at $LOCK after 30s — remove it if no worktree creation is running"

    # Reap claims whose owner is gone. A claim carries the PID of the process
    # that made it, and that is load-bearing: an in-flight creation has claimed
    # its slot but has NOT yet created its directory or containers, so a reaper
    # that only checks those two reads a live reservation as dead garbage. That
    # is exactly what happened — two of five concurrent runs were handed slot 2,
    # because the second reaped the first's seconds-old claim. A live PID means
    # hands off; a dead one with nothing on disk means genuinely abandoned.
    for claim in "$SLOTDIR"/slot-*; do
      [[ -e "$claim" ]] || continue
      read -r cpid cs < "$claim" 2>/dev/null
      [[ -z "${cs:-}" ]] && { rm -f "$claim"; continue; }
      kill -0 "${cpid:-0}" 2>/dev/null && continue          # owner still running
      if [[ ! -d "$(DEST_FOR "$cs")" ]] \
         && [[ -z "$(docker ps -aq --filter "label=com.docker.compose.project=$(PROJ_FOR "$cs")" 2>/dev/null)" ]]; then
        rm -f "$claim"
      fi
    done

    if [[ -n "$SLOT" ]]; then
      [[ -e "$SLOTDIR/slot-$SLOT" ]] && { rmdir "$LOCK"; die "slot $SLOT is claimed by '$(awk '{print $2}' "$SLOTDIR/slot-$SLOT")'"; }
    else
      for cand in $(seq 1 "$WT_MAX_SLOTS"); do
        [[ -e "$SLOTDIR/slot-$cand" ]] && continue
        busy=0
        while IFS= read -r line; do
          p="${line##*=}"
          lsof -nP -ti :"$p" >/dev/null 2>&1 && { busy=1; break; }
        done < <(port_env "$cand")
        [[ "$busy" -eq 0 ]] && { SLOT="$cand"; break; }
      done
      [[ -n "$SLOT" ]] || { rmdir "$LOCK"; die "no free slot in 1..$WT_MAX_SLOTS — tear an existing worktree down"; }
    fi

    printf '%s %s\n' "$$" "$SLUG" > "$SLOTDIR/slot-$SLOT"
    rmdir "$LOCK"
    CLAIM="$SLOTDIR/slot-$SLOT"
    info "slot $SLOT -> $(port_env "$SLOT" | tr '\n' ' ')"
  fi

  # --- rollback: creation is all-or-nothing -----------------------------------
  #
  # A failed `new` used to leave its image, network, volume and half-started
  # containers behind. They were attributable, so a later sweep could find them,
  # but "recoverable mess" is not the same as "no mess": the next run inherits a
  # half-built stack and the failure compounds.
  CREATED_DIR=false
  rollback() {
    warn "rolling back $CPROJ"
    if [[ -n "${CLAIM:-}" ]]; then rm -f "$CLAIM"; fi
    if $CREATED_DIR || [[ -d "$DEST" ]]; then
      ( cd "${DEST:-$ROOT}" 2>/dev/null || cd "$ROOT"
        env COMPOSE_PROJECT_NAME="$CPROJ" "$WT_SUFFIX_VAR=-$SLUG" \
          docker compose -p "$CPROJ" --profile '*' down -v --rmi local --remove-orphans ) >/dev/null 2>&1
      local dang
      dang="$(docker images -f dangling=true -f "label=com.docker.compose.project=$CPROJ" -q | tr '\n' ' ')"
      [[ -n "${dang// /}" ]] && docker rmi $dang >/dev/null 2>&1
      [[ -d "$DEST" ]] && ( cd "$ROOT" && AIDEX_WT_INTERNAL=1 bash "$MULTI" remove --slug "$SLUG" --dest "$DEST" --skip-teardown ) >/dev/null 2>&1
    fi
    err "$1"
    exit 1
  }

  # --- git worktrees + wrapper links ---
  args=(create --slug "$SLUG" --branch "$BRANCH" --dest "$DEST")
  for r in "${REPOS[@]}"; do args+=(--repo "$r"); done
  for l in $WT_LINKS; do args+=(--link "$l"); done
  for c in $WT_COPIES; do args+=(--copy "$c"); done
  ( cd "$ROOT" && AIDEX_WT_INTERNAL=1 bash "$MULTI" "${args[@]}" ) >/dev/null || rollback "worktree creation failed"
  CREATED_DIR=true
  ok "worktrees created: $DEST"

  # Record the branch this worktree was CREATED with. `down --delete-branch`
  # cannot ask git for it later: `branch --show-current` answers with whatever is
  # checked out at teardown, and a worktree switched to another branch would hand
  # the deletion an unrelated ref from the main repo. Nothing else stores it --
  # the slot claim holds only "<pid> <slug>" and .wt-slot only the number.
  #
  # Written HERE, before the --no-infra split below, because this is the one
  # unconditional point after creation succeeds. (.wt-slot is written twice, once
  # per branch of that split; do not copy that shape.)
  printf '%s\n' "$BRANCH" > "$DEST/.wt-branch" 2>/dev/null || true

  if $NO_INFRA; then
    echo "${SLOT:-}" > "$DEST/.wt-slot" 2>/dev/null
    ok "--no-infra: code only, no stack started"
    echo "$DEST"; exit 0
  fi

  echo "$SLOT" > "$DEST/.wt-slot"
  write_wt_env "$DEST" "$SLOT"
  render_env_files "$DEST" "$SLOT" || rollback "WT_ENV_RENDER failed"

  # --- the isolated stack ---
  envs=(COMPOSE_PROJECT_NAME="$CPROJ" "$WT_SUFFIX_VAR=-$SLUG")
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done < <(port_env "$SLOT")

  # Authoritative parity check: this reads the BRANCH's compose file, which is
  # the one the `up` below actually uses. A branch that adds a profile-less
  # service passes the $ROOT check and would otherwise surface later as
  # "profile-gated, declared nowhere" -- the wrong class, with a
  # WT_SERVICES_BY_HOOK line that would permanently hide a real parity gap.
  assert_services_declared "$DEST" || rollback "services parity (branch compose)"

  ( cd "$DEST" && env "${envs[@]}" docker compose up -d ${WT_SERVICES:-} ) || rollback "stack failed to start"
  ok "stack up: project $CPROJ"

  if [[ -n "$WT_READY_CMD" ]]; then
    ready=false
    for i in $(seq 1 60); do
      ( cd "$DEST" && env "${envs[@]}" bash -c "$WT_READY_CMD" ) >/dev/null 2>&1 && { ready=true; ok "ready after ${i}s"; break; }
      sleep 1
    done
    $ready || rollback "WT_READY_CMD never succeeded in 60s"
  fi
  if [[ -n "$WT_SEED_CMD" ]]; then
    ( cd "$DEST" && env "${envs[@]}" bash -c "$WT_SEED_CMD" ) || rollback "WT_SEED_CMD failed"
    ok "seeded"
  fi

  # Anything the project needs on top of a migrated database — provisioning an
  # isolated E2E template, loading fixtures. It runs with the same environment
  # as the stack, so a project script that respects COMPOSE_PROJECT_NAME and its
  # port variables needs no per-worktree copy of itself. Generating such copies
  # by `sed` is what produced bare-slug compose projects that no sweep could
  # attribute to a worktree.
  if [[ -n "$WT_POST_CMD" ]]; then
    ( cd "$DEST" && env "${envs[@]}" bash -c "$WT_POST_CMD" ) || rollback "WT_POST_CMD failed"
    ok "post-create done"
  fi

  # Deliberately NOT a rollback: the stack is up and the worktree is usable —
  # what is wrong is the declaration, and discarding a freshly built tree to
  # punish a config line would cost more than the finding. Held until AFTER the
  # handle is printed, and reported with its own exit code — see below.
  parity_rc=0
  assert_services_running "$DEST" || parity_rc=3

  # --- every resource we just made must be attributable, or the teardown we
  #     ship cannot reclaim it. Assert it now, while the author is watching. ---
  unattributed="$(
    { docker ps -a  --filter "label=com.docker.compose.project=$CPROJ" --format '{{.Names}}'
      docker volume ls  --format '{{.Name}}'   | grep -F "$CPROJ" || true
      docker network ls --format '{{.Name}}'   | grep -F "$CPROJ" || true
    } | grep -cv "^$" 2>/dev/null || echo 0
  )"
  info "attributable resources for $CPROJ: $unattributed"

  cat <<EOF

worktree ready
  dir      $DEST
  project  $CPROJ   (slot $SLOT)
$(port_env "$SLOT" | sed 's/^/  port     /')
  teardown worktree.sh down $SLUG
EOF
  # Exit 3, NOT 2, and only after the handle above is printed. The worktree
  # EXISTS and its stack is up; what failed is the declaration. Exiting 2 here —
  # the code the "created nothing" refusals use — told a caller to retry `new`,
  # which then died on "destination already exists", stranding a running stack
  # and a claimed slot whose directory the caller had never been shown.
  #   2 = refused, nothing was created
  #   3 = created and running, but the config does not describe it
  exit $parity_rc
fi

# ---------------------------------------------------------------- down
if [[ "$cmd" == "down" ]]; then
  # Read the slot from the claim when the directory is already gone — assuming
  # slot 1 pointed the teardown at another worktree's ports.
  SLOT="$(cat "$DEST/.wt-slot" 2>/dev/null || CLAIMED_SLOT "$SLUG" || echo 1)"
  envs=(COMPOSE_PROJECT_NAME="$CPROJ" "$WT_SUFFIX_VAR=-$SLUG")
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done < <(port_env "$SLOT")

  COMPOSE_DIR="$DEST"; [[ -d "$DEST" ]] || COMPOSE_DIR="$ROOT"
  info "tearing down $CPROJ"

  # The project's own stop recipe, before Docker's. `down` reclaims only what
  # Docker owns, so in a hybrid stack the half that runs as a host process
  # survives a teardown that reports success. This is the hook that lets a
  # project say how to stop that half.
  #
  # Deliberately NOT like the three create-path hooks: they call `rollback` on
  # failure because a half-created worktree is worse than none. Here the Docker
  # teardown is the part that must happen, and a hook that fails must not take
  # it down with it — report and continue.
  #
  # Guarded on the directory: `down` runs against an already-removed worktree on
  # the failed-teardown recovery path, where the subshell `cd` cannot succeed.
  if [[ -n "$WT_PRE_DOWN_CMD" && -d "$DEST" ]]; then
    info "running WT_PRE_DOWN_CMD"
    ( cd "$DEST" && env "${envs[@]}" bash -c "$WT_PRE_DOWN_CMD" ) \
      || warn "WT_PRE_DOWN_CMD failed (exit $?) — continuing with the Docker teardown"
  fi

  ( cd "$COMPOSE_DIR" && env "${envs[@]}" docker compose -p "$CPROJ" --profile '*' down -v --rmi local --remove-orphans )

  # `--rmi local` cannot reach untagged layers this project built; nothing else
  # ever revisits them. Label-scoped, so only this project can be touched.
  dangling="$(docker images -f dangling=true -f "label=com.docker.compose.project=$CPROJ" -q | tr '\n' ' ')"
  if [[ -n "${dangling// /}" ]]; then
    info "reclaiming untagged layers built by $CPROJ: $dangling"
    docker rmi $dangling >/dev/null 2>&1
  fi

  release_claim() {
    local claim
    for claim in "$(SLOTDIR_FOR)"/slot-*; do
      [[ -e "$claim" ]] || continue
      [[ "$(awk '{print $2}' "$claim" 2>/dev/null)" == "$SLUG" ]] && { rm -f "$claim"; info "released slot $(basename "$claim" | sed 's/slot-//')"; }
    done
  }

  # A zero exit from compose is not proof; ask.
  if bash "$SWEEP" --slug "$SLUG" >/dev/null 2>&1; then
    ok "no Docker resource remains attributable to $CPROJ"
  else
    warn "residue remains:"; bash "$SWEEP" --slug "$SLUG" 2>&1 | sed 's/^/  /'
  fi

  # --- what Docker never owned ------------------------------------------------
  #
  # The sweep above answers "is any Docker resource left?" and that is the wrong
  # question for a hybrid stack. In this family half the stack runs as a host
  # process, so `down` could report a clean teardown while a vite kept holding
  # the slot's port and the worktree directory — and the next `new` collided on
  # a port whose owner nothing on screen named.
  #
  # ONE lsof pass, not one per candidate: ~980 processes in ~0.5s, measured.
  # `-a` is mandatory and load-bearing — lsof ORs its selection options, so
  # without it `-u UID -d cwd` returned 106,740 lines in 10.5s instead of 1,959
  # in 0.5s: wrong answers and a 20x slowdown, silently.
  #
  # Matched by PATH PREFIX, never by a `(deleted)` marker: Linux appends one to a
  # removed cwd, macOS does not (measured — it still reports the full path after
  # `rm -rf`), so a parser that requires the marker finds nothing here.
  # Matched against $DEST as assigned, which is already resolved through its
  # PARENT rather than through itself. That is load-bearing twice over: lsof
  # reports resolved paths (/tmp is a symlink to /private/tmp on macOS, so a raw
  # string compare matches nothing), and the directory may be gone — which is
  # precisely the case this scan exists for.
  #
  # `$$` and `$PPID` are excluded because they are not survivors of the teardown,
  # they are what ran it — `worktree.sh down` invoked from inside the worktree is
  # ordinary. It also keeps --reap from ever signalling the caller's own shell.
  #
  # The `cd /` is the other half of that, and it is not optional: run from inside
  # the worktree, this scan's OWN children — the substitution subshell, lsof,
  # awk, grep, `id` — all inherit that cwd and report themselves as survivors.
  # Verified in isolation: without it the scan named seven phantom PIDs beside
  # the one real holder. `holders` is only ever called as `$(holders)`, so the
  # cd applies to the whole pipeline and never touches the caller's own cwd.
  holders() {
    cd / 2>/dev/null || return 1
    lsof -a -u "$(id -u)" -d cwd -Fpn 2>/dev/null | awk -v dir="$DEST" '
      /^p/ { pid = substr($0, 2); next }
      /^n/ { path = substr($0, 2)
             if (path == dir || index(path, dir "/") == 1) print pid }
    ' | grep -vx -e "$$" -e "$PPID"
  }

  # Age and port are what make the report actionable: age separates "started
  # before this worktree existed" from "started by it", and the port is the
  # answer to why the next `new` will collide. The listener lookup is verified to
  # surface IPv6-only listeners (`TCP [::1]:5173 (LISTEN)`), which is the case
  # that has bitten this codebase before.
  describe_holders() {
    local p age port cmd
    for p in $1; do
      age="$(ps -o etime= -p "$p" 2>/dev/null | tr -d ' ')"
      port="$(lsof -nP -a -p "$p" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {n=split($9,a,":"); print a[n]; exit}')"
      cmd="$(ps -o comm= -p "$p" 2>/dev/null)"
      printf '  pid %s  age %s  port %s  %s\n' "$p" "${age:-?}" "${port:--}" "${cmd##*/}"
    done
  }

  survivors="$(holders)"
  if [[ -n "$survivors" ]]; then
    warn "the Docker teardown is complete, but these host processes still hold $DEST:"
    describe_holders "$survivors" >&2
    if $REAP; then
      # By PID, one signal each, and only PIDs this scan just reported. Never a
      # name or a pattern: `pkill vite` reaches the main tree and every sibling
      # project. No escalation to -9 either — a process that ignores TERM is
      # reported, because killing something harder than it asked for is how a
      # teardown starts destroying work.
      for p in $survivors; do
        kill "$p" 2>/dev/null && info "reaped pid $p" || warn "could not signal pid $p"
      done
      sleep 1
      still="$(holders)"
      if [[ -n "$still" ]]; then
        warn "still holding $DEST after --reap (not escalating to -9):"
        describe_holders "$still" >&2
      else
        ok "--reap: every reported process is gone"
      fi
    else
      warn "they keep the port and the directory; re-run with --reap to kill them by PID"
    fi
  fi

  # The claim is released only when the worktree is REALLY gone. Releasing it on
  # the way out left a directory with no stack and no slot — a limbo `up` could
  # not resume deterministically and `new` refused to recreate.
  if $KEEP_DIR; then
    ok "--keep-dir: $DEST left in place (slot $SLOT still claimed; resume with: worktree.sh up $SLUG)"
    exit 0
  fi

  # Read the branch names BEFORE the removal. `list` reads them out of the
  # worktree's own checkout, and after `git worktree remove` there is no checkout
  # to read — so a name captured afterwards is empty and the deletion silently
  # does nothing. Captured unconditionally: the cost is one git call per repo and
  # it keeps the ordering trap from reappearing if the flag is ever moved.
  declare -a WT_BRANCHES=()
  if [[ -d "$DEST" ]]; then
    want="$(cat "$DEST/.wt-branch" 2>/dev/null || true)"
    for pp in $WT_PARTICIPANTS; do
      b="$(basename "$pp")"
      [[ -d "$DEST/$b" ]] || continue
      brname="$(git -C "$DEST/$b" branch --show-current 2>/dev/null || true)"
      # Only the branch this worktree was CREATED with is ever a candidate. If
      # the checkout has moved on -- switched to another branch, or detached --
      # the current name belongs to something else and deleting it would remove
      # a ref nobody asked about while leaving the intended one behind.
      #
      # A missing .wt-branch SKIPS. It must never fall back to the current
      # branch: that fallback is precisely the wrong-target deletion, and a
      # worktree created before this file existed is exactly the case that would
      # take it.
      if [[ -z "$want" ]]; then
        $DELETE_BRANCH && warn "--delete-branch: no recorded branch for $b (pre-dates .wt-branch) — skipped"
      elif [[ "$want" != "$brname" ]]; then
        $DELETE_BRANCH && warn "--delete-branch: $b is on '${brname:-detached HEAD}', not the created '$want' — skipped"
      else
        WT_BRANCHES+=("$b|$want")
      fi
    done
  fi

  if [[ -d "$DEST" ]]; then
    rmargs=(remove --slug "$SLUG" --dest "$DEST" --skip-teardown)
    for c in $WT_COPIES; do rmargs+=(--copy "$c"); done
    $FORCE && rmargs+=(--force)
    if ! ( cd "$ROOT" && AIDEX_WT_INTERNAL=1 bash "$MULTI" "${rmargs[@]}" ); then
      err "the stack is down but $DEST could not be removed."
      if IS_DIRTY "$DEST"; then
        err "it holds uncommitted work:"
        for pp in $WT_PARTICIPANTS; do
          b="$(basename "$pp")"; [[ -d "$DEST/$b" ]] || continue
          git -C "$DEST/$b" status --porcelain 2>/dev/null | sed "s|^|    $b |" >&2
        done
        err "commit or stash it, then re-run — or pass --force to DISCARD it."
      fi
      err "slot $SLOT stays claimed so nothing else takes it; resume with: worktree.sh up $SLUG"
      exit 1
    fi
  fi
  # Second pass, now that the directory is gone. The first ran with the removal
  # still pending, so anything only this one sees is what the removal surfaced.
  # Only the difference is printed: repeating the first list in full would train
  # a reader to skip both.
  # `$(holders)` first, then sort — never `<(holders | sort -u)`. In a pipeline
  # inside a process substitution the `sort` is forked with the CALLER's cwd, so
  # it becomes a phantom survivor of exactly the kind the `cd /` above removes.
  late_now="$(holders)"
  late="$( comm -13 <(printf '%s\n' $survivors | sort -u) <(printf '%s\n' $late_now | sort -u) )"
  if [[ -n "${late// /}" ]]; then
    warn "these turned up only after $DEST was removed, and hold a path that no longer exists:"
    describe_holders "$late" >&2
  fi

  release_claim
  ok "removed $DEST"

  # The branch is the last thing a torn-down worktree leaves behind, and nothing
  # in the suite ever removed it — so every finished worktree left a branch in
  # each participant repo, indistinguishable from live work.
  #
  # `git branch -d` IS the gate: it refuses a branch not merged into its upstream
  # or HEAD. So there is no "recorded base" to invent and no state to keep, and a
  # refusal is reported rather than escalated. There is deliberately no --force
  # sibling: the whole point of refusing is that the work is not in the trunk yet.
  # The empty case is an ELSE, not a warning followed by the loop anyway. On
  # bash 3.2 (the macOS system shell) expanding an empty array under `set -u` is
  # fatal, so the loop aborted the script with a raw "unbound variable" and exit
  # 1 over a teardown that had already fully succeeded. Two reachable paths hit
  # it: the stranded-directory recovery `list` itself prescribes, and an ordinary
  # detached HEAD.
  if $DELETE_BRANCH; then
    if [[ ${#WT_BRANCHES[@]} -eq 0 ]]; then
      warn "--delete-branch: no branch was eligible for deletion; nothing deleted"
    else
    for entry in "${WT_BRANCHES[@]}"; do
      repo="${entry%%|*}"; br="${entry#*|}"
      [[ -d "$ROOT/$repo" ]] || { warn "--delete-branch: $repo is not in $ROOT — skipped"; continue; }
      if out="$(git -C "$ROOT/$repo" branch -d "$br" 2>&1)"; then
        ok "deleted branch $br in $repo"
      else
        warn "kept branch $br in $repo — $(printf '%s' "$out" | tr '\n' ' ' | head -c 160)"
      fi
    done
    fi
  fi
  exit 0
fi
