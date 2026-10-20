#!/usr/bin/env bash
# orphan-sweep.sh — report-only sweep for orphaned `-wt-` Docker resources
# (compose projects, volumes, images, dangling build layers, networks) left
# behind by a skipped worktree teardown. Cross-checks discovered Docker
# resources against the worktree directories that are actually still on disk
# (siblings named `<project>-wt-<slug>`),
# and prints the exact reclaim command for each orphan. Outside --slug a compose
# project gets a command only when none of its containers' working_dir labels names an
# existing directory, none is running, restarting or paused (LIVE) and none is missing
# its label (NOT JUDGED), and that command is `down` without -v (--slug too); a volume
# shared with another project or not named <project>_* is named on a `# no -v:` line.
# Outside --slug no volume ever gets `volume rm`: a worktree moved with a plain mv whose
# stack is stopped reads exactly like a removed one, so a gone project's volume is listed
# for a check by hand (BL-857). A container listing that failed, even partway, prints no
# removal command at all. Never deletes anything
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
#   orphan-sweep.sh --all [--write-summary]
#                              # machine-wide listing judged by compose labels and
#                              # the filesystem, not by this workspace's prefix; see
#                              # orphan-sweep-all.sh. Always exit 0.
#
# Degrades gracefully when docker is not on PATH or the daemon is
# unreachable: prints a note and exits 0 (a --check gate cannot fail on an
# environment that has no Docker to begin with). A daemon that answers but
# times out on any call leaves that part unjudged, and so does everything after
# it (the first deadline hit trips a breaker: no further docker call is made):
# the sweep is reported incomplete, and --check / --slug exit 1 (never a clean bill).

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/wt-common.sh"

# --all (first argument only): the machine-wide, label-judged listing lives in its
# own script so nothing it decides can reach --slug / --check (BL-810, BL-811).
[[ "${1:-}" == --all ]] && exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/orphan-sweep-all.sh" "${@:2}"

CHECK=false
SLUG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --slug)  SLUG="${2:?--slug needs a value}"; shift 2 ;;
    -h|--help) wt_usage "${BASH_SOURCE[0]}"; exit 0 ;;
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
  dk_rc=$r
  printf -v "$v" '%s' "$o"
}

# --- inventory, fetched once up front: owner_slug needs every slug known to
#     exist before it can resolve a bare "-" suffix to the right one. ---
# One line per container: project, working_dir, mounts (--no-trunc: full volume names), state.
L='com.docker.compose.project' TAB=$'\t'
dk containers ps -a --no-trunc --format "{{.Label \"$L\"}}$TAB{{.Label \"$L.working_dir\"}}$TAB{{.Mounts}}$TAB{{.State}}"
# A failed listing reads as "no containers": every liveness and mount proof below is
# unknown. A plain failure does not trip the breaker; the sweep is still incomplete.
failed=0
[[ $dk_rc -ne 0 ]] && failed=1
compose_projects="$(cut -f1 <<< "$containers" | sort -u)"
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

# mounters VOL EXCEPT — the project of every container that mounts VOL, other than
# EXCEPT, space-separated; "(no compose project)" for a container outside compose.
mounters() {
  awk -F'\t' -v v="$1" -v x="$2" '$1 != x {
    n = split($3, m, ","); for (i = 1; i <= n; i++) if (m[i] == v) print ($1 == "" ? "(no compose project)" : $1) }' \
    <<< "$containers" | sort -u | paste -sd ' ' -
}

# say_cmd CMD... — print a removal command, unless the container listing failed: a
# running container missing from a partial listing reads as gone, so nothing is judged.
# basis PROJECT WHAT — the one-line reason above a rmi / network rm line. Outside --slug
# the project reached here because no live worktree or running container claims it;
# under --slug containers may still exist, so the line names the scope instead.
basis() {
  if [[ -n "$SLUG" ]]; then say_cmd "# belongs to $1 (--slug); $2"
  else say_cmd "# no live worktree or running container for $1; $2"; fi
}
say_cmd() { if [[ $failed -eq 0 ]]; then echo "  $*"; fi; }    # never false: _lib.sh sets -e

# --- compose projects ---
# Outside --slug a missing $WS_PARENT/$WS_NAME-wt-<slug> directory is not proof of an
# orphan (BL-857): a worktree at a custom location reads the same. Docker's own
# working_dir label decides first, as in orphan-sweep-all.sh; a project proven LIVE or
# left NOT JUDGED joins known_projects, so none of its resources gets a removal line.
gone_projects=() unjudged_projects=()
while IFS= read -r proj; do
  [[ -z "$proj" ]] && continue
  in_scope "$proj" || continue
  is_known "$proj" && continue
  if [[ -z "$SLUG" ]]; then
    live="" unread=0
    while IFS= read -r w; do
      if [[ -z "$w" ]]; then unread=1; elif [[ -e "$w" ]]; then live="$w"; fi
    done < <(awk -F'\t' -v p="$proj" '$1 == p { print $2 }' <<< "$containers")
    if [[ -n "$live" ]]; then
      echo "compose project: $proj"
      echo "  LIVE (working_dir exists): $live"
      known_projects+=("$proj"); continue
    fi
    # A worktree moved with a plain mv keeps its old working_dir label; a running
    # container still proves it live.
    if awk -F'\t' -v p="$proj" '$1 == p && $4 ~ /running|restarting|paused/ { f = 1 } END { exit !f }' <<< "$containers"; then
      echo "compose project: $proj"
      echo "  LIVE (container running)"
      known_projects+=("$proj"); continue
    fi
    if [[ $unread -eq 1 ]]; then
      echo "NOT JUDGED compose project: $proj"
      echo "  # a container carries no working_dir label; verify by hand before removing anything:"
      echo "  #   docker ps -a --filter label=$L=$proj"
      known_projects+=("$proj"); unjudged_projects+=("$proj")
      orphans_found=$((orphans_found + 1)); continue
    fi
    gone_projects+=("$proj")    # every working_dir is gone: the only proof a volume rm needs
    # Never `down -v` here: run from the workspace root, `-p <proj> down -v` loads its
    # compose file and removes every non-external volume it declares, the main stack's
    # name:-pinned one included, whenever nothing mounts it. Each <proj>_* volume gets its
    # own gated line below; a shared or differently named one is named here.
    echo "$LABEL compose project: $proj"
    awk -F'\t' -v p="$proj" '$1 == p { print "  # judged gone: " $2 " does not exist" }' <<< "$containers" | sort -u
    say_cmd docker compose -p "$proj" down --rmi local --remove-orphans
    while IFS= read -r v; do
      [[ -z "$v" || "$v" == /* || "$v" =~ ^[0-9a-f]{64}$ ]] && continue    # a bind path; an anonymous volume
      m="$(mounters "$v" "$proj")"
      if [[ -n "$m" ]]; then echo "  # no -v: shared volume $v is mounted by: $m"
      elif [[ "$v" != "${proj}_"* ]]; then echo "  # no -v: $v is not named ${proj}_* (name:-pinned or external)"
      fi
    done < <(awk -F'\t' -v p="$proj" '$1 == p { print $3 }' <<< "$containers" | tr ',' '\n' | sort -u)
    orphans_found=$((orphans_found + 1)); continue
  fi
  echo "$LABEL compose project: $proj"
  say_cmd docker compose -p "$proj" down --rmi local --remove-orphans
  orphans_found=$((orphans_found + 1))
done <<< "$compose_projects"

# --- volumes ---
while IFS= read -r vol; do
  [[ -z "$vol" ]] && continue
  in_scope "$vol" || continue
  owner="$PREFIX$(owner_slug "$vol")"
  if [[ " ${unjudged_projects[*]:-} " == *" $owner "* ]]; then    # empty under --slug
    echo "NOT JUDGED volume: $vol"
    echo "  # $owner is NOT JUDGED above; verify by hand before removing anything:"
    echo "  #   git worktree list; docker volume inspect $vol"
    orphans_found=$((orphans_found + 1)); continue
  fi
  if ! is_known "$vol"; then
    m="$(mounters "$vol" "$owner")"
    # Outside --slug a volume rm needs its project proven gone above (BL-857): with no
    # container (stack downed, listing failed) a live worktree anywhere reads the same.
    if [[ -z "$SLUG" && -z "$m" && " ${gone_projects[*]:-} " != *" $owner "* ]]; then
      echo "NOT JUDGED volume: $vol"
      echo "  # no container of $owner shows its working_dir gone; verify by hand before removing anything:"
      echo "  #   git worktree list; docker volume inspect $vol"
      orphans_found=$((orphans_found + 1)); continue
    fi
    if [[ -n "$m" ]]; then
      echo "$LABEL volume: $vol"
      echo "  # not removable: $vol is mounted by: $m"
    elif [[ -z "$SLUG" ]]; then
      echo "$LABEL volume: $vol  (verify by hand; no command printed: a moved worktree with a stopped stack looks identical, see worktree-conventions.md)"
    else
      echo "$LABEL volume: $vol"
      say_cmd "docker volume rm $vol   # confirm before removing — see safety doctrine in worktree-conventions.md"
    fi
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
    basis "$PREFIX$(owner_slug "$img" "$lbl")" "the image rebuilds from its compose file"
    say_cmd docker rmi "$img"
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
  basis "$proj" "the image rebuilds from its compose file"
  say_cmd docker rmi "$ids"
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
    basis "$PREFIX$(owner_slug "$net")" "the network has no endpoints"
    say_cmd docker network rm "$net"
  else
    echo "  # still has attached containers — tear their stack down first, do not force-remove"
  fi
  orphans_found=$((orphans_found + 1))
done <<< "$networks"

echo
[[ "$degraded" -gt 0 ]] && warn "sweep incomplete (degraded): $((degraded - skipped)) docker call(s) timed out; $skipped skipped after the breaker tripped; not judged."
[[ "$failed" -gt 0 ]] && warn "sweep incomplete (degraded): the container listing failed; liveness and mounts not judged."
if [[ "$orphans_found" -gt 0 ]]; then
  if [[ -n "$SLUG" ]]; then
    warn "$orphans_found resource group(s) attributable to $SCOPE."
  else
    warn "$orphans_found orphan(s) found."
  fi
elif [[ $((degraded + failed)) -eq 0 ]]; then
  if [[ -n "$SLUG" ]]; then
    ok "no Docker resources attributable to $SCOPE."
  else
    ok "No orphaned ${SCOPE}* Docker resources found."
  fi
fi

# An unjudged image is not a clean bill: --slug exit 0 releases a teardown.
if { $CHECK || [[ -n "$SLUG" ]]; } && [[ $((orphans_found + degraded + failed)) -gt 0 ]]; then
  exit 1
fi
exit 0
