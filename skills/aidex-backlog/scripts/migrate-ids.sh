#!/usr/bin/env bash
# migrate-ids.sh — backfill stable short ids (BL-NNN) into backlog items that
# predate the id scheme (D-09). Idempotent: items that already carry an `id:`
# are skipped. Scans active + _archive so ids are unique and never reused.
#
# Usage:
#   migrate-ids.sh [--apply]    # default: dry-run (prints what would change)
#
# Assigns ids in filename (chronological) order across active then _archive,
# continuing from the current max id so a re-run after new items is stable.

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
[[ -d "$BACKLOG_DIR" ]] || { echo "no backlog dir at $BACKLOG_DIR" >&2; exit 0; }

# current max id across active + archive
max=0
read_id_num() {
  awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {v=$2; gsub(/[^0-9]/,"",v); print v; exit}' "$1"
}
shopt -s nullglob
for f in "$BACKLOG_DIR"/*.md "$BACKLOG_DIR"/_archive/*.md; do
  [[ -f "$f" ]] || continue
  n="$(read_id_num "$f")"
  [[ -n "$n" ]] && (( 10#$n > max )) && max=$((10#$n))
done

changed=0
# Process active first, then archive; sorted within each for stable assignment.
for f in $(printf '%s\n' "$BACKLOG_DIR"/*.md | sort) $(printf '%s\n' "$BACKLOG_DIR"/_archive/*.md | sort); do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  [[ "$base" == "00-index.md" ]] && continue
  [[ -n "$(read_id_num "$f")" ]] && continue   # already has id
  # only touch files that have a title line in front-matter
  grep -qE '^title:' "$f" || continue
  max=$((max+1))
  newid="$(printf 'BL-%03d' "$max")"
  if [[ $APPLY -eq 1 ]]; then
    # insert `id:` immediately after the first `title:` line
    awk -v id="$newid" '
      !done && /^title:/ { print; print "id: " id; done=1; next }
      { print }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "assigned $newid -> $base"
  else
    echo "[dry-run] would assign $newid -> $base"
  fi
  changed=$((changed+1))
done
shopt -u nullglob

if [[ $changed -eq 0 ]]; then
  echo "all backlog items already have ids — nothing to do"
elif [[ $APPLY -eq 0 ]]; then
  echo "($changed item(s) would change — re-run with --apply to write)"
else
  echo "done: $changed item(s) updated"
fi
