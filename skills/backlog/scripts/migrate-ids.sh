#!/usr/bin/env bash
# migrate-ids.sh — backfill stable short ids (BL-NNN) into backlog items that
# predate the id scheme (D-09). Idempotent: items that already carry an `id:`
# are skipped. Scans active + _archive + _deferred (and the _claims ledger) so ids are
# unique and never reused.
#
# Usage:
#   migrate-ids.sh [--apply]    # default: dry-run (prints what would change)
#
# Assigns ids in filename (chronological) order across active then _archive,
# continuing from the current max id (which also reads _deferred and _claims) so a re-run after new items is stable.

set -euo pipefail

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
[[ -d "$BACKLOG_DIR" ]] || { echo "no backlog dir at $BACKLOG_DIR" >&2; exit 0; }

# current max id across active + archive + deferred + claims. Only ids in register-item.sh's
# 3-5 digit window count: a legacy BL-20260610 would otherwise inflate the sequence, and a
# deferred item or a claim marker holds an id that must not be minted again.
max=0
read_id_num() {
  awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {v=$2; gsub(/[^0-9]/,"",v); print v; exit}' "$1"
}
shopt -s nullglob
for f in "$BACKLOG_DIR"/*.md "$BACKLOG_DIR"/_archive/*.md "$BACKLOG_DIR"/_deferred/*.md; do
  [[ -f "$f" ]] || continue
  n="$(read_id_num "$f")"
  [[ -n "$n" && ${#n} -ge 3 && ${#n} -le 5 ]] && (( 10#$n > max )) && max=$((10#$n))
done
# Same ledger location as register-item.sh backlog_claims_dir (BL-239): from a linked
# worktree the claims live in the MAIN tree's .context/backlog/_claims. Copied, not sourced:
# register-item.sh runs its body when sourced.
CLAIMS_DIR="$BACKLOG_DIR/_claims"
if common="$(git -C "$BACKLOG_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
   && gitdir="$(git -C "$BACKLOG_DIR" rev-parse --absolute-git-dir 2>/dev/null)" \
   && [[ -n "$common" && "$common" != "$gitdir" ]] \
   && main="$(cd "$(dirname "$common")" 2>/dev/null && pwd -P)" \
   && [[ -n "$main" && -d "$main/.context" ]]; then
  CLAIMS_DIR="$main/.context/backlog/_claims"
fi
for f in "$CLAIMS_DIR"/BL-*; do
  n="$(basename "$f")"
  [[ "$n" =~ ^BL-([0-9]{3,5})$ ]] && (( 10#${BASH_REMATCH[1]} > max )) && max=$((10#${BASH_REMATCH[1]}))
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
