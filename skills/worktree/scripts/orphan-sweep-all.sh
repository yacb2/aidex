#!/usr/bin/env bash
# orphan-sweep-all.sh — machine-wide, report-only listing of compose projects whose
# working directory no longer exists (BL-810, BL-811). Reached as
# `orphan-sweep.sh --all`; never from --slug, --check or the default mode, which stay
# workspace-scoped because worktree-multi.sh evals `worktree_down` on their exit code.
#
# Usage:
#   orphan-sweep.sh --all                    # print the listing, always exit 0
#   orphan-sweep.sh --all --write-summary    # also write the summary the session-start
#                                            # hook reads (~/.claude/tmp/docker-orphans/summary)
#
# The only rule, Docker's own labels plus the filesystem, no name parsing:
#   CANDIDATE ORPHAN  the project has containers, every one of them carries a
#                     com.docker.compose.project.working_dir label, and none of those
#                     directories exists (each is under $HOME/, and its parent lists
#                     without it).
# Everything else is not judged and not mentioned: a project with no container, a
# container without the label, any working_dir present, or one outside $HOME/ (an
# unmounted disk, a devcontainer path) where absence cannot be proven.
#
# Known limit: a live worktree moved with a plain `mv` keeps the old working_dir on its
# containers until its stack is recreated, so it reads as a candidate. That is why the
# listing is a lead, not a verdict.
#
# It never stops, removes or prunes anything and never prints a command that would:
# every docker call is a read (info, ps, volume ls), and volumes are only ever listed as
# attached to their project.

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

WRITE_SUMMARY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --write-summary) WRITE_SUMMARY=true; shift ;;
    -h|--help) usage_from_header "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

SUMMARY_DIR="$HOME/.claude/tmp/docker-orphans"
SUMMARY="$SUMMARY_DIR/summary"
TAB=$'\t'

# write_summary COUNT NAMES — atomic; only a complete scan writes, so a docker-down or
# failed scan leaves the last good summary in place.
write_summary() {
  $WRITE_SUMMARY || return 0
  mkdir -p "$SUMMARY_DIR" || return 0
  {
    echo "scanned_at=$(date +%s)"
    echo "status=ok"
    echo "candidates=$1"
    echo "candidate_projects=$2"
  } > "$SUMMARY.tmp.$$" && mv "$SUMMARY.tmp.$$" "$SUMMARY"
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found on PATH — skipping the machine-wide orphan listing."
  exit 0
fi
dt="${AIDEX_DOCKER_TIMEOUT:-30}" drc=0
with_timeout "$dt" docker info >/dev/null 2>&1 || drc=$?
if [[ $drc -ne 0 ]]; then
  [[ $drc -eq 142 ]] && echo "docker did not answer within ${dt} s."
  echo "docker daemon unreachable — skipping the machine-wide orphan listing."
  exit 0
fi

L='com.docker.compose.project'
containers="$(with_timeout "$dt" docker ps -a --no-trunc --format "{{.Label \"$L\"}}$TAB{{.Label \"$L.working_dir\"}}$TAB{{.State}}" 2>/dev/null)" \
  && volumes="$(with_timeout "$dt" docker volume ls --format "{{.Name}}$TAB{{.Label \"$L\"}}" 2>/dev/null)" \
  || { echo "a docker read failed: inventory incomplete, nothing judged."; exit 0; }

# gone DIR — positive proof that DIR does not exist: under $HOME/, not there, and its
# parent lists without it. Anything that cannot be listed is not proof.
gone() {
  local listing
  [[ "$1" == "$HOME"/?* && ! -e "$1" ]] || return 1
  listing="$(ls -A "$(dirname "$1")" 2>/dev/null)" || return 1
  ! grep -Fxq -- "$(basename "$1")" <<< "$listing"
}

count=0 names=""
echo "Compose projects whose working directory no longer exists (report-only)..."
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  pc="$(awk -F'\t' -v p="$p" '$1 == p' <<< "$containers")"
  wds="$(cut -f2 <<< "$pc" | sort -u)"
  ok=1                                        # an empty (missing) label fails `gone`
  while IFS= read -r w; do gone "$w" || { ok=0; break; }; done <<< "$wds"
  [[ $ok -eq 1 ]] || continue
  echo
  echo "CANDIDATE ORPHAN $p"
  while IFS= read -r w; do echo "  working_dir $w (does not exist)"; done <<< "$wds"
  echo "  $(wc -l <<< "$pc" | tr -d ' ') container(s): $(cut -f3 <<< "$pc" | sort | uniq -c | awk '{printf "%s%s %s", NR > 1 ? ", " : "", $1, $2}')"
  while IFS= read -r v; do
    [[ -n "$v" ]] && echo "  volume $v attached to $p"
  done < <(awk -F'\t' -v p="$p" '$2 == p { print $1 }' <<< "$volumes")
  echo "  verify by hand before removing anything"
  count=$((count + 1)); names="$names $p"
done < <(cut -f1 <<< "$containers" | sort -u)

echo
if [[ $count -gt 0 ]]; then
  warn "$count candidate(s). Nothing was deleted."
else
  echo "No candidate."
fi
write_summary "$count" "${names# }"
exit 0
