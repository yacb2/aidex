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
#   WT_POST_CMD       ""                     shell run after seeding (E2E template, fixtures)

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
WT_SUFFIX_VAR="WT_SUFFIX"; WT_SEED_CMD=""; WT_READY_CMD=""; WT_POST_CMD=""
# `set -a` so everything the project defines here is EXPORTED. WT_READY_CMD and
# WT_SEED_CMD run in a subshell, so a plain shell variable would be empty there
# — a profile that referenced its own $WT_DB_USER probed as an empty role, never
# became ready, and rolled back after 60s. Exporting makes a project's own
# config values usable by its own commands, which is the least surprising rule.
set -a
[[ -f "$CONFIG" ]] && . "$CONFIG"
set +a

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
      [[ -d "$DEST" ]] && ( cd "$ROOT" && bash "$MULTI" remove --slug "$SLUG" --dest "$DEST" --skip-teardown ) >/dev/null 2>&1
    fi
    err "$1"
    exit 1
  }

  # --- git worktrees + wrapper links ---
  args=(create --slug "$SLUG" --branch "$BRANCH" --dest "$DEST")
  for r in "${REPOS[@]}"; do args+=(--repo "$r"); done
  for l in $WT_LINKS; do args+=(--link "$l"); done
  ( cd "$ROOT" && bash "$MULTI" "${args[@]}" ) >/dev/null || rollback "worktree creation failed"
  CREATED_DIR=true
  ok "worktrees created: $DEST"

  if $NO_INFRA; then
    echo "${SLOT:-}" > "$DEST/.wt-slot" 2>/dev/null
    ok "--no-infra: code only, no stack started"
    echo "$DEST"; exit 0
  fi

  echo "$SLOT" > "$DEST/.wt-slot"

  # --- the isolated stack ---
  envs=(COMPOSE_PROJECT_NAME="$CPROJ" "$WT_SUFFIX_VAR=-$SLUG")
  while IFS= read -r line; do [[ -n "$line" ]] && envs+=("$line"); done < <(port_env "$SLOT")

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

  # Release the slot reservation. A claim nobody releases is a slot lost for the
  # rest of the machine's uptime; `new` reaps stale ones, but only a teardown
  # knows the slot is free *now*.
  SLOTDIR="${TMPDIR:-/tmp}/aidex-wt-slots-${PROJECT}"
  for claim in "$SLOTDIR"/slot-*; do
    [[ -e "$claim" ]] || continue
    [[ "$(awk '{print $2}' "$claim" 2>/dev/null)" == "$SLUG" ]] && { rm -f "$claim"; info "released slot $(basename "$claim" | sed 's/slot-//')"; }
  done

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
