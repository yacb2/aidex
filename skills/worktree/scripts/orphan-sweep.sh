#!/usr/bin/env bash
# orphan-sweep.sh — report-only sweep for orphaned `-wt-` Docker resources
# (compose projects, volumes, images, dangling build layers, networks) left
# behind by a skipped worktree teardown. Cross-checks discovered Docker
# resources against the worktree directories that are actually still on disk
# (siblings named `<project>-wt-<slug>` and `_worktrees/<slug-or-project>`),
# and prints the exact reclaim command for each orphan. Never deletes anything
# itself — see the safety doctrine in
# conventions/references/worktree-conventions.md ("dangling is not
# disposable").
#
# SCOPE: only resources belonging to THIS workspace (`<project>-wt-*`) are ever
# considered. A sibling project's worktrees are invisible here — their liveness
# is knowable only from their own workspace root, and judging them from the
# wrong cwd is how this script once printed `docker volume rm` for a worktree
# that was live with three running containers.
#
# Usage:
#   orphan-sweep.sh            # report orphans (if any), always exit 0
#   orphan-sweep.sh --check    # same report, exit 1 if any orphan found (for gates)
#   orphan-sweep.sh --slug S   # report every resource attributable to ONE slug,
#                              # orphan or not; exit 1 if any resource exists.
#                              # This is the attribution pre-flight a teardown
#                              # runs before removing anything.
#
# Degrades gracefully when docker is not on PATH or the daemon is
# unreachable: prints a note and exits 0 (a --check gate cannot fail on an
# environment that has no Docker to begin with). A daemon that answers but
# times out on any call leaves that part unjudged, and so does everything after
# it (the first deadline hit trips a breaker: no further docker call is made):
# the sweep is reported incomplete, and --check / --slug exit 1 (never a clean bill).

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

CHECK=false
SLUG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --slug)  SLUG="${2:?--slug needs a value}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# --- resolve the workspace root + name (drives the naming contract) ---
# find_project_root, never `git rev-parse`. The naming contract is
# "<workspace>-wt-<slug>", and `git rev-parse --show-toplevel` answers a
# different question: which repo is the CALLER standing in. In a split-git
# workspace -- participants are separate repos and the workspace root is not one
# -- calling the sweep from inside a participant made it scan "backend-wt-*",
# a namespace nothing can ever be in, and it reported a confident all-clear.
# find_project_root prefers the nearest .context/, so single-repo behaviour is
# unchanged and a split workspace resolves to the same root every caller uses.
WS_ROOT="$(find_project_root)"
WS_NAME="$(basename "$WS_ROOT")"
WS_PARENT="$(dirname "$WS_ROOT")"

# Every resource this script may speak about carries this prefix. Anything that
# does not is another workspace's business (or not a worktree at all).
if [[ -n "$SLUG" ]]; then
  is_valid_slug "$SLUG" || die "invalid slug: $SLUG (kebab-case, [a-z0-9-])"
  SCOPE="$(compose_project_name "$WS_NAME")-wt-${SLUG}"
  # Under --slug the finding is "attributable to this worktree", not "orphaned":
  # the resources of a LIVE worktree are exactly what the pre-flight must list.
  LABEL="RESOURCE"
else
  SCOPE="$(compose_project_name "$WS_NAME")-wt-"
  LABEL="ORPHAN"
fi

# Compose project names are normalised (compose_project_name); directories are not.
PREFIX="$(compose_project_name "$WS_NAME")-wt-"

# owner_slug IDENT — the slug IDENT belongs to, by the boundary the tool creates:
# project <ws>-wt-<slug>; volume/network <project>_<name>; compose v2 image
# <project>-<service>. A slug never contains "_" (or ":"), so the text before the
# first one is the slug exactly. A bare "-" suffix is ambiguous by name alone
# (ws-wt-foo-bar-backend: foo's "bar-backend" or foo-bar's "backend"?), so it
# goes to the LONGEST slug known to exist -- never a prefix sibling (worktree-c03).
# LABEL (optional): the resource's com.docker.compose.project label; when it
# carries this workspace's prefix it is the exact owner and the name is not read.
owner_slug() {
  local rest="${1#"$PREFIX"}" head best="" c
  if [[ "${2:-}" == "$PREFIX"?* ]]; then printf '%s\n' "${2#"$PREFIX"}"; return; fi
  head="${rest%%[_:]*}"
  if [[ "$head" != "$rest" ]]; then printf '%s\n' "$head"; return; fi
  for c in "${candidates[@]:-}"; do
    [[ -z "$c" || ${#c} -le ${#best} ]] && continue
    [[ "$rest" == "$c" || "$rest" == "$c"-* ]] && best="$c"
  done
  printf '%s\n' "${best:-$rest}"
}

# in_scope IDENT — true if IDENT carries this workspace's prefix and, under
# --slug, belongs to exactly that slug. Anchored at the start: never a substring.
in_scope() {
  [[ "$1" == "$PREFIX"* ]] || return 1
  [[ -z "$SLUG" ]] && return 0
  [[ "$(owner_slug "$1" "${2:-}")" == "$SLUG" ]]
}

# --- build the set of KNOWN live compose-project names, i.e. worktrees that
#     still have a directory on disk. Contract: COMPOSE_PROJECT_NAME =
#     <project>-wt-<slug>, where <project> is the main repo's basename. ---
known_projects=()

for d in "$WS_PARENT/$WS_NAME"-wt-*; do
  [[ -d "$d" ]] || continue
  d="$(basename "$d")"
  known_projects+=("${PREFIX}${d#"${WS_NAME}-wt-"}")
done

if [[ -d "$WS_ROOT/_worktrees" ]]; then
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    name="$(basename "$d")"
    if [[ "$name" == "${WS_NAME}-wt-"* ]]; then
      known_projects+=("${PREFIX}${name#"${WS_NAME}-wt-"}")
    elif [[ "$name" == *-wt-* ]]; then
      known_projects+=("$name")
    else
      known_projects+=("${PREFIX}${name}")
    fi
  done < <(find "$WS_ROOT/_worktrees" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

# is_known IDENT — true if IDENT belongs to a known live worktree. Under --slug
# the question is not liveness but attribution, so nothing counts as known: the
# caller wants the full inventory for that slug.
is_known() {
  [[ -n "$SLUG" ]] && return 1
  local owner p
  owner="$PREFIX$(owner_slug "$1" "${2:-}")"
  for p in "${known_projects[@]:-}"; do
    [[ "$owner" == "$p" ]] && return 0
  done
  return 1
}

# --- docker availability (degrade gracefully) ---
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH — skipping Docker orphan sweep (degraded)."
  exit 0
fi
# A wedged Docker Desktop accepts the socket and never answers; 30 s covers a cold start.
dt="${AIDEX_DOCKER_TIMEOUT:-30}" drc=0
with_timeout "$dt" docker info >/dev/null 2>&1 || drc=$?
if [[ $drc -ne 0 ]]; then
  [[ $drc -eq 142 ]] && echo "docker did not answer within ${dt} s."
  echo "docker daemon unreachable — skipping Docker orphan sweep (degraded)."
  exit 0
fi

# dk VAR docker-args... — run docker under the deadline and put its stdout in
# VAR. A deadline hit is reported and counted as degraded (VAR left empty): an
# empty inventory from a wedged daemon must never read as "No orphans".
# Circuit breaker: after the first deadline hit no further docker call is made
# (N images would otherwise cost N x dt); each skipped call counts as degraded.
degraded=0 skipped=0 tripped=0
dk() {
  local v="$1" o r=0; shift
  if [[ $tripped -eq 1 ]]; then
    skipped=$((skipped + 1)); degraded=$((degraded + 1)); printf -v "$v" '%s' ''; return
  fi
  o="$(with_timeout "$dt" docker "$@" 2>/dev/null)" || r=$?
  if [[ $r -eq 142 ]]; then
    echo "docker did not answer within ${dt} s running: docker $* (not judged)."
    degraded=$((degraded + 1)); o=""; tripped=1
  fi
  printf -v "$v" '%s' "$o"
}

# --- inventory, fetched once up front: owner_slug needs every slug known to
#     exist before it can resolve a bare "-" suffix to the right one. ---
dk compose_projects ps -a --format '{{.Label "com.docker.compose.project"}}'
compose_projects="$(sort -u <<< "$compose_projects")"
dk volumes volume ls --format '{{.Name}}'
volumes="$(sort -u <<< "$volumes")"
dk images images --format '{{.Repository}}'
images="$(sort -u <<< "$images")"
dk dangling_ids images -f dangling=true -q
dangling_projects=""
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  dk lbl inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id"
  dangling_projects+="$lbl"$'\n'
done <<< "$dangling_ids"
dangling_projects="$(sort -u <<< "$dangling_projects" | grep -v '^$' || true)"
dk networks network ls --format '{{.Name}}'
networks="$(sort -u <<< "$networks")"

# Candidate slugs: worktrees on disk, compose project labels (exact names),
# volume/network heads, and the slug asked about.
candidates=()
[[ -n "$SLUG" ]] && candidates+=("$SLUG")
while IFS= read -r ident; do
  [[ "$ident" == "$PREFIX"?* ]] || continue
  ident="${ident#"$PREFIX"}"
  candidates+=("${ident%%[_:]*}")
done < <(printf '%s\n' "${known_projects[@]:-}" "$compose_projects" "$dangling_projects" "$volumes" "$networks")

orphans_found=0

if [[ -n "$SLUG" ]]; then
  echo "Attribution pre-flight for $SCOPE (every resource carrying this project name)..."
else
  echo "Scanning for orphaned ${SCOPE}* Docker resources..."
fi

# --- compose projects ---
while IFS= read -r proj; do
  [[ -z "$proj" ]] && continue
  in_scope "$proj" || continue
  if ! is_known "$proj"; then
    echo "$LABEL compose project: $proj"
    echo "  docker compose -p $proj down -v --rmi local --remove-orphans"
    orphans_found=$((orphans_found + 1))
  fi
done <<< "$compose_projects"

# --- volumes ---
while IFS= read -r vol; do
  [[ -z "$vol" ]] && continue
  in_scope "$vol" || continue
  if ! is_known "$vol"; then
    echo "$LABEL volume: $vol"
    echo "  docker volume rm $vol   # confirm before removing — see safety doctrine in worktree-conventions.md"
    orphans_found=$((orphans_found + 1))
  fi
done <<< "$volumes"

# --- images (tagged) ---
# Owner by the compose-project label compose stamps on the image (BL-774); the
# name rule is only the fallback for an unlabelled image. A lookup that times
# out leaves the image unjudged and the sweep degraded, never clean.
while IFS= read -r img; do
  [[ -z "$img" ]] && continue
  [[ "$img" == "$PREFIX"* ]] || continue
  irc=0
  if [[ $tripped -eq 1 ]]; then skipped=$((skipped + 1)); degraded=$((degraded + 1)); continue; fi
  lbl="$(with_timeout "$dt" docker image inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$img" 2>/dev/null)" || irc=$?
  if [[ $irc -eq 142 ]]; then
    echo "docker did not answer within ${dt} s reading the label of image $img (not judged)."
    degraded=$((degraded + 1)); tripped=1
    continue
  fi
  in_scope "$img" "$lbl" || continue
  if ! is_known "$img" "$lbl"; then
    echo "$LABEL image: $img"
    echo "  docker rmi $img"
    orphans_found=$((orphans_found + 1))
  fi
done <<< "$images"

# --- dangling images (untagged build layers) ---
#
# `compose down --rmi local` only removes images the compose file currently
# references by their default tag. Every rebuild of a service orphans the
# PREVIOUS image as <none>, and no teardown verb reclaims those — which is how
# a workspace accumulates tens of GB of untagged 3GB layers after a handful of
# worktree E2E runs. They stay attributable: compose stamps
# com.docker.compose.project on the image itself, so each dangling layer can be
# traced back to the exact worktree that built it and reclaimed by ID.
while IFS= read -r proj; do
  [[ -z "$proj" ]] && continue
  in_scope "$proj" || continue
  is_known "$proj" && continue
  before=$degraded
  dk ids images -f dangling=true -f "label=com.docker.compose.project=$proj" -q
  if [[ $degraded -gt $before ]]; then
    echo "$LABEL dangling images: $proj (not judged)"
    orphans_found=$((orphans_found + 1))
    continue
  fi
  ids="$(tr '\n' ' ' <<< "$ids")"
  ids="${ids% }"
  [[ -z "$ids" ]] && continue
  n="$(wc -w <<< "$ids" | tr -d ' ')"
  echo "$LABEL dangling images: $proj ($n)"
  echo "  docker rmi $ids"
  orphans_found=$((orphans_found + 1))
done <<< "$dangling_projects"

# --- networks ---
#
# `compose down` removes the project network only when nothing else is still
# attached. A container from a second stack joined to it (an E2E runner, say)
# leaves the network behind, and once that container dies the network is a
# 0-container orphan no teardown will ever revisit.
while IFS= read -r net; do
  [[ -z "$net" ]] && continue
  in_scope "$net" || continue
  is_known "$net" && continue
  before=$degraded
  dk attached network inspect "$net" -f '{{len .Containers}}'
  if [[ $degraded -gt $before ]]; then
    echo "$LABEL network: $net (attached count not judged)"
    echo "  # attached containers unknown — do not force-remove"
    orphans_found=$((orphans_found + 1))
    continue
  fi
  echo "$LABEL network: $net ($attached container(s) attached)"
  if [[ "$attached" == "0" ]]; then
    echo "  docker network rm $net"
  else
    echo "  # still has attached containers — tear their stack down first, do not force-remove"
  fi
  orphans_found=$((orphans_found + 1))
done <<< "$networks"

echo
[[ "$degraded" -gt 0 ]] && warn "sweep incomplete (degraded): $((degraded - skipped)) docker call(s) timed out; $skipped skipped after the breaker tripped; not judged."
if [[ "$orphans_found" -gt 0 ]]; then
  if [[ -n "$SLUG" ]]; then
    warn "$orphans_found resource group(s) attributable to $SCOPE."
  else
    warn "$orphans_found orphan(s) found."
  fi
elif [[ "$degraded" -eq 0 ]]; then
  if [[ -n "$SLUG" ]]; then
    ok "no Docker resources attributable to $SCOPE."
  else
    ok "No orphaned ${SCOPE}* Docker resources found."
  fi
fi

# An unjudged image is not a clean bill: --slug exit 0 releases a teardown.
if { $CHECK || [[ -n "$SLUG" ]]; } && [[ $((orphans_found + degraded)) -gt 0 ]]; then
  exit 1
fi
exit 0
