#!/usr/bin/env bash
# orphan-sweep.sh — report-only sweep for orphaned `-wt-` Docker resources
# (compose projects, volumes, images) left behind by a skipped worktree
# teardown. Cross-checks discovered Docker resources against the worktree
# directories that are actually still on disk (siblings named
# `<project>-wt-<slug>` and `_worktrees/<slug-or-project>`), and prints the
# exact `worktree_down` command to reclaim each orphan. Never deletes
# anything itself — see the safety doctrine in
# aidex-conventions/references/worktree-conventions.md ("dangling is not
# disposable").
#
# Usage:
#   orphan-sweep.sh            # report orphans (if any), always exit 0
#   orphan-sweep.sh --check    # same report, exit 1 if any orphan found (for gates)
#
# Degrades gracefully when docker is not on PATH or the daemon is
# unreachable: prints a note and exits 0 (a --check gate cannot fail on an
# environment that has no Docker to begin with).

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

# --- resolve the workspace root + name (drives the naming contract) ---
if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
  WS_ROOT="$(git rev-parse --show-toplevel)"
else
  WS_ROOT="$(find_project_root)"
fi
WS_NAME="$(basename "$WS_ROOT")"
WS_PARENT="$(dirname "$WS_ROOT")"

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

# is_known IDENT — true if IDENT is (or clearly derives from, e.g. a compose
# volume/image whose name is the project name plus a separator suffix) a
# known live project.
is_known() {
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

echo "Scanning for orphaned -wt- Docker resources..."

# --- compose projects ---
compose_projects="$(docker ps -a --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | sort -u | grep -- '-wt-' || true)"
while IFS= read -r proj; do
  [[ -z "$proj" ]] && continue
  if ! is_known "$proj"; then
    echo "ORPHAN compose project: $proj"
    echo "  docker compose -p $proj down -v --rmi local --remove-orphans"
    orphans_found=$((orphans_found + 1))
  fi
done <<< "$compose_projects"

# --- volumes ---
volumes="$(docker volume ls --filter name=-wt- --format '{{.Name}}' 2>/dev/null | sort -u || true)"
while IFS= read -r vol; do
  [[ -z "$vol" ]] && continue
  if ! is_known "$vol"; then
    echo "ORPHAN volume: $vol"
    echo "  docker volume rm $vol   # confirm before removing — see safety doctrine in worktree-conventions.md"
    orphans_found=$((orphans_found + 1))
  fi
done <<< "$volumes"

# --- images ---
images="$(docker images '*-wt-*' --format '{{.Repository}}' 2>/dev/null | sort -u || true)"
while IFS= read -r img; do
  [[ -z "$img" ]] && continue
  if ! is_known "$img"; then
    echo "ORPHAN image: $img"
    echo "  docker rmi $img"
    orphans_found=$((orphans_found + 1))
  fi
done <<< "$images"

echo
if [[ "$orphans_found" -eq 0 ]]; then
  ok "No orphaned -wt- Docker resources found."
else
  warn "$orphans_found orphan(s) found."
fi

if $CHECK && [[ "$orphans_found" -gt 0 ]]; then
  exit 1
fi
exit 0
