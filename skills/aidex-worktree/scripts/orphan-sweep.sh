#!/usr/bin/env bash
# orphan-sweep.sh — report-only sweep for orphaned `-wt-` Docker resources
# (compose projects, volumes, images, dangling build layers, networks) left
# behind by a skipped worktree teardown. Cross-checks discovered Docker
# resources against the worktree directories that are actually still on disk
# (siblings named `<project>-wt-<slug>` and `_worktrees/<slug-or-project>`),
# and prints the exact reclaim command for each orphan. Never deletes anything
# itself — see the safety doctrine in
# aidex-conventions/references/worktree-conventions.md ("dangling is not
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
# environment that has no Docker to begin with).

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

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
  SCOPE="${WS_NAME}-wt-${SLUG}"
  # Under --slug the finding is "attributable to this worktree", not "orphaned":
  # the resources of a LIVE worktree are exactly what the pre-flight must list.
  LABEL="RESOURCE"
else
  SCOPE="${WS_NAME}-wt-"
  LABEL="ORPHAN"
fi

# in_scope IDENT — true if IDENT is the scoped project name or clearly derives
# from it (a compose volume/image/network is the project name plus a separator
# suffix). Anchored at the start: never a substring match.
in_scope() {
  local ident="$1"
  if [[ -n "$SLUG" ]]; then
    case "$ident" in "$SCOPE"|"$SCOPE"_*|"$SCOPE"-*|"$SCOPE":*) return 0 ;; esac
    return 1
  fi
  [[ "$ident" == "$SCOPE"* ]]
}

# --- build the set of KNOWN live compose-project names, i.e. worktrees that
#     still have a directory on disk. Contract: COMPOSE_PROJECT_NAME =
#     <project>-wt-<slug>, where <project> is the main repo's basename. ---
known_projects=()

while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  known_projects+=("$(basename "$d")")
done < <(find "$WS_PARENT" -maxdepth 1 -type d -name "${WS_NAME}-wt-*" 2>/dev/null)

if [[ -d "$WS_ROOT/_worktrees" ]]; then
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    name="$(basename "$d")"
    if [[ "$name" == *-wt-* ]]; then
      known_projects+=("$name")
    else
      known_projects+=("${WS_NAME}-wt-${name}")
    fi
  done < <(find "$WS_ROOT/_worktrees" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

# is_known IDENT — true if IDENT is (or clearly derives from) a known live
# worktree. Under --slug the question is not liveness but attribution, so
# nothing counts as known: the caller wants the full inventory for that slug.
is_known() {
  [[ -n "$SLUG" ]] && return 1
  local ident="$1" p
  for p in "${known_projects[@]:-}"; do
    [[ -z "$p" ]] && continue
    case "$ident" in
      "$p"|"$p"_*|"$p"-*|"$p":*) return 0 ;;
    esac
  done
  return 1
}

# --- docker availability (degrade gracefully) ---
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH — skipping Docker orphan sweep (degraded)."
  exit 0
fi
if ! docker info >/dev/null 2>&1; then
  echo "docker daemon unreachable — skipping Docker orphan sweep (degraded)."
  exit 0
fi

orphans_found=0

if [[ -n "$SLUG" ]]; then
  echo "Attribution pre-flight for $SCOPE (every resource carrying this project name)..."
else
  echo "Scanning for orphaned ${SCOPE}* Docker resources..."
fi

# --- compose projects ---
compose_projects="$(docker ps -a --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | sort -u || true)"
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
volumes="$(docker volume ls --format '{{.Name}}' 2>/dev/null | sort -u || true)"
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
images="$(docker images --format '{{.Repository}}' 2>/dev/null | sort -u || true)"
while IFS= read -r img; do
  [[ -z "$img" ]] && continue
  in_scope "$img" || continue
  if ! is_known "$img"; then
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
dangling_projects="$(
  docker images -f dangling=true -q 2>/dev/null | while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id" 2>/dev/null
  done | sort -u | grep -v '^$' || true
)"
while IFS= read -r proj; do
  [[ -z "$proj" ]] && continue
  in_scope "$proj" || continue
  is_known "$proj" && continue
  ids="$(docker images -f dangling=true -f "label=com.docker.compose.project=$proj" -q 2>/dev/null | tr '\n' ' ')"
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
networks="$(docker network ls --format '{{.Name}}' 2>/dev/null | sort -u || true)"
while IFS= read -r net; do
  [[ -z "$net" ]] && continue
  in_scope "$net" || continue
  is_known "$net" && continue
  attached="$(docker network inspect "$net" -f '{{len .Containers}}' 2>/dev/null || echo 0)"
  echo "$LABEL network: $net ($attached container(s) attached)"
  if [[ "$attached" == "0" ]]; then
    echo "  docker network rm $net"
  else
    echo "  # still has attached containers — tear their stack down first, do not force-remove"
  fi
  orphans_found=$((orphans_found + 1))
done <<< "$networks"

echo
if [[ "$orphans_found" -eq 0 ]]; then
  if [[ -n "$SLUG" ]]; then
    ok "no Docker resources attributable to $SCOPE."
  else
    ok "No orphaned ${SCOPE}* Docker resources found."
  fi
else
  if [[ -n "$SLUG" ]]; then
    warn "$orphans_found resource group(s) attributable to $SCOPE."
  else
    warn "$orphans_found orphan(s) found."
  fi
fi

if { $CHECK || [[ -n "$SLUG" ]]; } && [[ "$orphans_found" -gt 0 ]]; then
  exit 1
fi
exit 0
