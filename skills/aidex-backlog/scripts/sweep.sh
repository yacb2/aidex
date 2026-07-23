#!/usr/bin/env bash
# sweep.sh — batch-archive backlog items already marked done/dropped that still
# sit in the active folder, then rebuild the index once (D-10 retroactive cleanup).
# Idempotent: a second run is a no-op once the active folder is clean.
#
# Usage:
#   sweep.sh [--apply]    # default: dry-run (lists what would move)

set -euo pipefail

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -d "$BACKLOG_DIR" ]] || { echo "no backlog dir at $BACKLOG_DIR" >&2; exit 0; }

read_status() { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="status:"{print $2; exit}' "$1"; }
read_id()     { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$1"; }

moved=0
mkdir -p "$BACKLOG_DIR/_archive"
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
    continue
  fi
  if [[ $APPLY -eq 1 ]]; then
    mv "$f" "$dest"
    echo "archived ($st): $base"
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

if [[ $moved -eq 0 ]]; then
  echo "active backlog is clean — nothing to sweep"
elif [[ $APPLY -eq 0 ]]; then
  echo "($moved done/dropped item(s) still in the active folder — archive on close, D-10)"
  echo "  archive all at once: bash $SCRIPT_DIR/sweep.sh --apply"
else
  bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null
  echo "done: $moved item(s) archived; index rebuilt"
fi
