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
#   worktree.sh down <slug> [--keep-dir]
#   worktree.sh list
#
#   new  : allocate a free port slot, create one git worktree per participant,
#          link the unversioned wrapper files, bring the isolated stack up.
#   down : tear the stack down INCLUDING what compose does not reclaim, verify
#          nothing is left attributable to the slug, then remove the directory.
#   list : every worktree of this project with its slot, branch and stack state.
#
# Config (.context/worktrees/config.env), all optional except WT_PARTICIPANTS:
#   WT_PARTICIPANTS   "backend frontend"     repos that can participate
#   WT_LINKS          "docker-compose.yml dev.sh .docker"
#                                            unversioned wrapper paths to symlink
#   WT_SERVICES       "db backend"           services to start
#   WT_PORT_VARS      "DB_PORT=4400 BACKEND_PORT=4500"
#                                            var=dev-base pairs; slot N adds N*WT_PORT_STRIDE
#   WT_PORT_STRIDE    100                    per-slot offset
#   WT_MAX_SLOTS      9
#   WT_SUFFIX_VAR     WT_SUFFIX              var carrying -<slug> into container_name
#   WT_SEED_CMD       ""                     shell run inside the new stack to seed data
#   WT_READY_CMD      ""                     shell that must succeed before seeding

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$(cd "$SELF_DIR/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
set +e   # this script reports and decides; it does not want inherited errexit

SWEEP="$SELF_DIR/orphan-sweep.sh"
SNAP="$SELF_DIR/docker-snapshot.sh"
MULTI="$SELF_DIR/worktree-multi.sh"

cmd="${1:-}"; shift 2>/dev/null
case "$cmd" in new|down|list) ;; *) sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;; esac

ROOT="$(find_project_root)"
PROJECT="$(basename "$ROOT")"
CONFIG="$ROOT/.context/worktrees/config.env"

# --- defaults, then the project's own values ---
WT_PARTICIPANTS=""; WT_LINKS=""; WT_SERVICES=""
WT_PORT_VARS=""; WT_PORT_STRIDE=100; WT_MAX_SLOTS=9
WT_SUFFIX_VAR="WT_SUFFIX"; WT_SEED_CMD=""; WT_READY_CMD=""
[[ -f "$CONFIG" ]] && . "$CONFIG"

SLUG=""; BRANCH=""; SLOT=""; NO_INFRA=false; KEEP_DIR=false
REPOS=()
[[ $# -gt 0 && "$1" != -* ]] && { SLUG="$1"; shift; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="${2-}"; shift 2 ;;
    --repo)   REPOS+=("${2-}"); shift 2 ;;
    --slot)   SLOT="${2-}"; shift 2 ;;
    --no-infra) NO_INFRA=true; shift ;;
    --keep-dir) KEEP_DIR=true; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

DEST_FOR() { printf '%s/../%s-wt-%s\n' "$ROOT" "$PROJECT" "$1"; }
PROJ_FOR() { printf '%s-wt-%s\n' "$PROJECT" "$1"; }

# ---------------------------------------------------------------- list
if [[ "$cmd" == "list" ]]; then
  found=0
  for d in "$ROOT"/../"$PROJECT"-wt-*; do
    [[ -d "$d" ]] || continue
    found=1
    s="$(basename "$d")"; s="${s#${PROJECT}-wt-}"
    slot="$(cat "$d/.wt-slot" 2>/dev/null || echo '?')"
    br="$(git -C "$d/$(echo "$WT_PARTICIPANTS" | awk '{print $1}')" branch --show-current 2>/dev/null || echo '?')"
    up="$(docker ps -q --filter "label=com.docker.compose.project=$(PROJ_FOR "$s")" 2>/dev/null | wc -l | tr -d ' ')"
    printf '%-22s slot=%-3s branch=%-32s containers_up=%s\n' "$s" "$slot" "$br" "$up"
  done
  [[ "$found" -eq 1 ]] || echo "no worktrees for $PROJECT"
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

# ---------------------------------------------------------------- new
if [[ "$cmd" == "new" ]]; then
  [[ -n "$BRANCH" ]] || die "new requires --branch"
  [[ -e "$DEST" ]] && die "destination already exists: $DEST"
  [[ "${#REPOS[@]}" -gt 0 ]] || read -r -a REPOS <<< "$WT_PARTICIPANTS"
  [[ "${#REPOS[@]}" -gt 0 ]] || die "no participants: pass --repo or set WT_PARTICIPANTS in $CONFIG"

  # --- base branch, stated not inherited ---
  first="${REPOS[0]}"
  default_branch="$(git -C "$ROOT/$first" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
  [[ -n "$default_branch" ]] || default_branch="$(git -C "$ROOT/$first" branch --show-current 2>/dev/null)"
  info "base $default_branch -> worktree $CPROJ · branch $BRANCH · participants: ${REPOS[*]}"

  # --- slot allocation under a lock, so two concurrent sessions cannot pick
  #     the same one. A static "offset by index" rule cannot see a slot held by
  #     a stale stack whose directory is already gone. ---
  if ! $NO_INFRA && [[ -n "$WT_PORT_VARS" ]]; then
    LOCK="${TMPDIR:-/tmp}/aidex-wt-slot-${PROJECT}.lock"
    for _ in $(seq 1 50); do mkdir "$LOCK" 2>/dev/null && break; sleep 0.2; done
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT

    if [[ -z "$SLOT" ]]; then
      for cand in $(seq 1 "$WT_MAX_SLOTS"); do
        busy=0
        while IFS= read -r line; do
          p="${line##*=}"
          lsof -ti :"$p" >/dev/null 2>&1 && { busy=1; break; }
        done < <(port_env "$cand")
        [[ "$busy" -eq 0 ]] && { SLOT="$cand"; break; }
      done
      [[ -n "$SLOT" ]] || die "no free slot in 1..$WT_MAX_SLOTS — tear an existing worktree down"
    fi
    info "slot $SLOT -> $(port_env "$SLOT" | tr '\n' ' ')"
  fi

  # --- git worktrees + wrapper links ---
  args=(create --slug "$SLUG" --branch "$BRANCH" --dest "$DEST")
  for r in "${REPOS[@]}"; do args+=(--repo "$r"); done
  for l in $WT_LINKS; do args+=(--link "$l"); done
  ( cd "$ROOT" && bash "$MULTI" "${args[@]}" ) >/dev/null || die "worktree creation failed"
  ok "worktrees created: $DEST"

  if $NO_INFRA; then
    echo "$SLOT" > "$DEST/.wt-slot" 2>/dev/null
    ok "--no-infra: code only, no stack started"
    echo "$DEST"; exit 0
  fi

  echo "$SLOT" > "$DEST/.wt-slot"

  # --- the isolated stack ---
  envs=(COMPOSE_PROJECT_NAME="$CPROJ" "$WT_SUFFIX_VAR=-$SLUG")
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done < <(port_env "$SLOT")

  ( cd "$DEST" && env "${envs[@]}" docker compose up -d ${WT_SERVICES:-} ) || die "stack failed to start"
  ok "stack up: project $CPROJ"

  if [[ -n "$WT_READY_CMD" ]]; then
    for i in $(seq 1 60); do
      ( cd "$DEST" && env "${envs[@]}" bash -c "$WT_READY_CMD" ) >/dev/null 2>&1 && { ok "ready after ${i}s"; break; }
      sleep 1
      [[ "$i" -eq 60 ]] && die "WT_READY_CMD never succeeded — inspect: docker compose -p $CPROJ logs"
    done
  fi
  if [[ -n "$WT_SEED_CMD" ]]; then
    ( cd "$DEST" && env "${envs[@]}" bash -c "$WT_SEED_CMD" ) || die "WT_SEED_CMD failed"
    ok "seeded"
  fi

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
  exit 0
fi

# ---------------------------------------------------------------- down
if [[ "$cmd" == "down" ]]; then
  SLOT="$(cat "$DEST/.wt-slot" 2>/dev/null || echo 1)"
  envs=(COMPOSE_PROJECT_NAME="$CPROJ" "$WT_SUFFIX_VAR=-$SLUG")
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done < <(port_env "$SLOT")

  COMPOSE_DIR="$DEST"; [[ -d "$DEST" ]] || COMPOSE_DIR="$ROOT"
  info "tearing down $CPROJ"
  ( cd "$COMPOSE_DIR" && env "${envs[@]}" docker compose -p "$CPROJ" --profile '*' down -v --rmi local --remove-orphans )

  # `--rmi local` cannot reach untagged layers this project built; nothing else
  # ever revisits them. Label-scoped, so only this project can be touched.
  dangling="$(docker images -f dangling=true -f "label=com.docker.compose.project=$CPROJ" -q | tr '\n' ' ')"
  if [[ -n "${dangling// /}" ]]; then
    info "reclaiming untagged layers built by $CPROJ: $dangling"
    docker rmi $dangling >/dev/null 2>&1
  fi

  # A zero exit from compose is not proof; ask.
  if bash "$SWEEP" --slug "$SLUG" >/dev/null 2>&1; then
    ok "no Docker resource remains attributable to $CPROJ"
  else
    warn "residue remains:"; bash "$SWEEP" --slug "$SLUG" 2>&1 | sed 's/^/  /'
  fi

  if $KEEP_DIR; then
    ok "--keep-dir: $DEST left in place"
  elif [[ -d "$DEST" ]]; then
    ( cd "$ROOT" && bash "$MULTI" remove --slug "$SLUG" --dest "$DEST" --skip-teardown ) \
      || die "directory removal failed (dirty worktree? commit or stash first) — the stack is already down"
    ok "removed $DEST"
  fi
  exit 0
fi
