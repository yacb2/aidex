#!/usr/bin/env bash
# docker-snapshot.sh — prove a worktree left nothing behind, instead of asserting it.
#
# A teardown that "looks clean" is the whole problem: `compose down` exits 0
# while leaving untagged layers and a project network, and once the worktree
# directory is gone nothing can attribute them to anything. The only honest
# check is a GLOBAL before/after diff — global on purpose, because the leaks
# worth catching are exactly the ones no project-scoped filter can see.
#
# Usage:
#   docker-snapshot.sh take <file>              # capture full docker state
#   docker-snapshot.sh diff <before> [<after>]  # what appeared / disappeared
#                                               # (no <after> => take one now)
#
#   diff exits 1 when anything APPEARED since <before>. Disappearances are
#   reported but never fail the check — a teardown is supposed to remove things.
#
# Every appeared resource is annotated with the compose project that owns it,
# or ORPHAN when nothing claims it. An ORPHAN line is the failure mode this
# whole exercise exists to eliminate.

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

cmd="${1:-}"; shift || true
case "$cmd" in take|diff) ;; *) die "usage: docker-snapshot.sh {take <file>|diff <before> [after]}" ;; esac

docker_ok() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

# owner ID KIND — the compose project a resource belongs to, or "-".
owner() {
  local id="$1" kind="$2" lbl=""
  case "$kind" in
    image|container)
      lbl="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$id" 2>/dev/null)" ;;
    volume)
      lbl="$(docker volume inspect "$id" -f '{{index .Labels "com.docker.compose.project"}}' 2>/dev/null)" ;;
    network)
      lbl="$(docker network inspect "$id" -f '{{index .Labels "com.docker.compose.project"}}' 2>/dev/null)" ;;
  esac
  [[ -z "$lbl" || "$lbl" == "<no value>" ]] && lbl="-"
  printf '%s' "$lbl"
}

take() {
  local out="${1:?usage: take <file>}"
  docker_ok || { echo "# docker unavailable" > "$out"; warn "docker unavailable — empty snapshot"; return 0; }
  {
    # Stable, sorted, one resource per line: KIND<TAB>ID<TAB>NAME.
    # Images are keyed by ID, not tag: a retag must not read as a new image,
    # and an untagged layer must still be a line.
    docker images -a --format '{{.ID}}' | sort -u | while read -r i; do
      printf 'image\t%s\t%s\n' "$i" "$(docker inspect -f '{{if .RepoTags}}{{index .RepoTags 0}}{{else}}<none>{{end}}' "$i" 2>/dev/null)"
    done
    docker ps -a --format '{{.ID}}\t{{.Names}}' | while IFS=$'\t' read -r i n; do printf 'container\t%s\t%s\n' "$i" "$n"; done
    docker volume ls --format '{{.Name}}'  | while read -r v; do printf 'volume\t%s\t%s\n' "$v" "$v"; done
    docker network ls --format '{{.ID}}\t{{.Name}}' | while IFS=$'\t' read -r i n; do printf 'network\t%s\t%s\n' "$i" "$n"; done
  } | sort > "$out"
  ok "snapshot: $(grep -c . "$out" || true) resource(s) -> $out"
}

diff_snap() {
  local before="${1:?usage: diff <before> [after]}" after="${2:-}"
  [[ -f "$before" ]] || die "snapshot not found: $before"
  local tmp=""
  if [[ -z "$after" ]]; then
    tmp="$(mktemp)"; take "$tmp" >/dev/null 2>&1; after="$tmp"
  fi
  [[ -f "$after" ]] || die "snapshot not found: $after"

  local appeared gone
  appeared="$(comm -13 "$before" "$after")"
  gone="$(comm -23 "$before" "$after")"

  local n_gone; n_gone="$(grep -c . <<<"$gone" || true)"
  if [[ "$n_gone" -gt 0 ]]; then
    info "removed since baseline ($n_gone):"
    while IFS=$'\t' read -r kind id name; do
      [[ -z "$kind" ]] && continue
      printf '  - %-9s %s\n' "$kind" "$name" >&2
    done <<<"$gone"
  fi

  local n_new; n_new="$(grep -c . <<<"$appeared" || true)"
  if [[ "$n_new" -eq 0 ]]; then
    ok "ZERO RESIDUE — docker state is identical to the baseline"
    [[ -n "$tmp" ]] && rm -f "$tmp"
    return 0
  fi

  err "residue: $n_new resource(s) appeared since baseline"
  local orphans=0
  while IFS=$'\t' read -r kind id name; do
    [[ -z "$kind" ]] && continue
    local own; own="$(owner "$id" "$kind")"
    if [[ "$own" == "-" ]]; then
      printf '  + %-9s %-46s ORPHAN (no compose project claims it)\n' "$kind" "$name" >&2
      orphans=$((orphans + 1))
    else
      printf '  + %-9s %-46s owner=%s\n' "$kind" "$name" "$own" >&2
    fi
  done <<<"$appeared"
  [[ "$orphans" -gt 0 ]] && err "$orphans unattributable — nothing can ever decide to reclaim these"
  [[ -n "$tmp" ]] && rm -f "$tmp"
  return 1
}

case "$cmd" in
  take) take "$@" ;;
  diff) diff_snap "$@" ;;
esac
