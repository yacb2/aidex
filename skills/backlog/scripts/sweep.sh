#!/usr/bin/env bash
# sweep.sh — batch-archive backlog items already marked done/dropped that still
# sit in the active folder, then rebuild the index once (D-10 retroactive cleanup).
# Idempotent: a second run is a no-op once the active folder is clean.
#
# Usage:
#   sweep.sh [--apply]    # default: dry-run (lists what would move)
#   sweep.sh --check      # dry-run that EXITS 1 when anything would move, for triage/CI.
#                         # The plain dry-run exits 0 whatever it finds, which is right for a
#                         # human reading it and useless to a caller gating on the result.

set -euo pipefail

APPLY=0 CHECK=0
case "${1:-}" in
  --apply) APPLY=1 ;;
  --check) CHECK=1 ;;
esac

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_backlog-lib.sh"

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -d "$BACKLOG_DIR" ]] || { echo "no backlog dir at $BACKLOG_DIR" >&2; exit 0; }

read_status() { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="status:"{gsub(/["\047]/,"",$2); print $2; exit}' "$1"; }

moved=0 collided=0
# Only when applying: a dry-run must not touch the tree, or a read-only caller
# (compliance-sweep.sh over the whole fleet) creates directories in every project
# it merely inspects.
[[ $APPLY -eq 1 ]] && mkdir -p "$BACKLOG_DIR/_archive"
shopt -s nullglob
for f in "$BACKLOG_DIR"/*.md; do
  base="$(basename "$f")"
  [[ "$base" == "00-index.md" ]] && continue
  st="$(read_status "$f")"
  case "$st" in
    done|dropped) ;;
    *) continue ;;
  esac
  dest="$BACKLOG_DIR/_archive/$base"
  if [[ -e "$dest" ]]; then
    echo "WARN archive collision, skipping: $base" >&2
    collided=$((collided+1))
    continue
  fi
  if [[ $APPLY -eq 1 ]]; then
    mv "$f" "$dest"
    echo "archived ($st): $base"
    # The bare `mv` above moves the .md and nothing else, so every rendered .html
    # companion stayed in the active folder while its item left — and validate.py
    # cannot see the orphan, because crossref_target_exists searches _archive/ too,
    # so the stranded page's anchor still resolves. The user was the detector,
    # counting leftover pages by hand on three separate days. close-item.sh:268
    # already did this correctly for the single-item path; the batch path did not,
    # even though its own dry-run branch below prints the close-item.sh command
    # that would have. Same helper, same argument shape.
    archive_companions "$ROOT/.context" "backlog/$base" "$BACKLOG_DIR/_archive"
  else
    # Surface the item AND a copy-pasteable, status-preserving archive command
    # (the "archive re-dictated 4x" friction: a done item lingers because the
    # reader isn't told how to close it). Resolve by id when present, else file.
    id="$(read_id "$f")"
    target="${id:-$base}"
    echo "[dry-run] would archive ($st): $base"
    echo "      archive: bash $SCRIPT_DIR/close-item.sh $target --status $st"
  fi
  moved=$((moved+1))
done
shopt -u nullglob

if [[ $moved -eq 0 && $collided -gt 0 ]]; then
  echo "$collided done/dropped item(s) cannot be archived: archive collision (same file already in _archive/)" >&2
  if [[ $CHECK -eq 1 ]]; then exit 1; fi
elif [[ $moved -eq 0 ]]; then
  echo "active backlog is clean — nothing to sweep"
elif [[ $APPLY -eq 0 ]]; then
  echo "($moved done/dropped item(s) still in the active folder — archive on close, D-10)"
  echo "  archive all at once: bash $SCRIPT_DIR/sweep.sh --apply"
  if [[ $collided -gt 0 ]]; then echo "  plus $collided archive collision(s), not archivable" >&2; fi
  if [[ $CHECK -eq 1 ]]; then exit 1; fi
else
  # --reindex exits 4 AFTER writing the index (id guard); any other non-zero exit is a stale index
  IDX_RC=0
  bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null || IDX_RC=$?
  if [[ $IDX_RC -eq 0 ]]; then
    echo "done: $moved item(s) archived; index rebuilt"
    if [[ $collided -gt 0 ]]; then echo "$collided archive collision(s) skipped" >&2; fi
  elif [[ $IDX_RC -eq 4 ]]; then
    echo "done: $moved item(s) archived; index rebuilt, but reindex reported an id problem (exit $IDX_RC)"
  else
    echo "done: $moved item(s) archived; index is stale (reindex exit $IDX_RC); rebuild it with: bash $SCRIPT_DIR/register-item.sh --reindex" >&2
    exit "$IDX_RC"
  fi
fi
