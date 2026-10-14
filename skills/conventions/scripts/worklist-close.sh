#!/usr/bin/env bash
# worklist-close.sh — close a run-queue (status done|dropped), stamp updated.
#
# Usage:
#   worklist-close.sh <slug-or-path> [--status done|dropped] [--force]
#
# For a SWEEP work-list (`mode: sweep`) refuses — exit 2, nothing mutated — while either
# holds (sweep plan, Q14/Q16); a plain work-list closes as before:
#   · a queued backlog item (active or archived) carries a `## Verification` row of
#     kind `owner` whose proof cell is empty or a placeholder (placeholder-proofs.txt):
#     the owner has not answered, and a run
#     that closes over it silently converts "outstanding" into "done";
#   · `## Deferred / emergent` holds an unchecked line that names no BL-NNN and no
#     `CLOSE:` — a deferral that would vanish with the run (close-plan.sh's guard, on
#     the sweep's side; "a deferral must outlive the run that made it").
# `--force` closes anyway and PRINTS what it overrode: "the checklist was handed over
# and never answered" is a legitimate end state, but it is recorded, never silent.
#
# On close the file moves to worklists/_archive/ (D-10) — `worklist/<file>` references
# keep resolving through the two-folder lookup. Prints "CLOSED <archived path>".
set -euo pipefail

# Shared resolver (find_project_root in _lib.sh) — never a private one or git rev-parse; see its header.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"
ROOT="$(find_project_root)"
WL_DIR="$ROOT/.context/worklists"

arg="${1:-}"; shift || true
[[ -n "$arg" ]] || { echo "usage: worklist-close.sh <slug-or-path> [--status done|dropped]" >&2; exit 2; }

status="done" force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) status="$2"; shift 2;;
    --force)  force=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ "$status" == "done" || "$status" == "dropped" ]] || { echo "--status must be done|dropped" >&2; exit 2; }

# resolve_worklist (in _lib.sh) skips -report companions and exits 2 on an ambiguous slug.
file="$(resolve_worklist "$WL_DIR" "$arg")"
[[ -n "${file:-}" && -f "$file" ]] || { echo "worklist not found: $arg" >&2; exit 2; }
# worklist-advance.sh's lock, held to exit: the --force line, the stamp (set_front_matter's
# fixed `$file.tmp`) and the move must not interleave with an append's read-modify-write.
# AIDEX_WL_LOCK_WAIT: seconds, as in worklist-advance.sh.
lock="$(wl_lock_file "$file")" || exit 2
lock_take "$lock" "${AIDEX_WL_LOCK_WAIT:-30}" || { echo "error: could not lock $file; nothing written" >&2; exit 2; }
# another close that held the lock while this one waited has moved the list away
[[ -f "$file" ]] || { echo "worklist was closed/archived while waiting: $file; nothing written" >&2; exit 2; }
today="$(date +%F)"
# archived-ness from the resolved directory (wl_is_archived, _lib.sh)
wl_is_archived "$file" "$WL_DIR" && { echo "worklist already archived: $file" >&2; exit 2; }
# no front matter: refused here, before the --force line or the stamp below writes anything
has_front_matter "$file" || { echo "no front matter in $file" >&2; exit 2; }
# archive collision: refused here too, or the --force line and the stamp were already written
dest="$WL_DIR/_archive/$(basename "$file")"
[[ -e "$dest" ]] && { echo "archive collision: $dest already exists" >&2; exit 2; }

# --- the two refusals, BEFORE any mutation — SWEEP work-lists only ---
# A plain work-list (audit kickoff, a chain of plans) keeps its old close: its emergent
# section is a class-(b) record, not a queue the run owes, and audit calls this
# script that way today. The sweep is where an unanswered owner row or an unreconciled
# deferral means work silently lost, so that is where the refusal lives.
sweep=0; wl_is_sweep "$file" && sweep=1
BACKLOG="$ROOT/.context/backlog"
item_file() { bl_item_file "$BACKLOG" "$1"; }  # <BL-id> -> path in backlog/, _deferred/ or _archive/ (or empty)
owner_open=""
unreconciled=""
# the scans below feed only the sweep refusal; a plain work-list never reads them
if [[ $sweep -eq 1 ]]; then
  while IFS= read -r line; do
    id="$(grep -oE '\bBL-[0-9]+\b' <<<"$line" | sed -n 1p || true)"; [[ -n "$id" ]] || continue
    f="$(item_file "$id")"; [[ -n "$f" ]] || continue
    # unanswered = empty OR a placeholder ("awaiting owner"), the definition close-item.sh
    # parks on (proof_is_placeholder, _lib.sh); an empty-only test let a parked item's run end
    while IFS=$'\037' read -r what proof; do
      if [[ -z "$proof" ]] || proof_is_placeholder "$proof"; then owner_open="$owner_open
      - $id: $what"; fi
    done < <(awk 'BEGIN{s=0} /^## /{s=($0 ~ /^## Verification[[:space:]]*$/)} s && /^\|/ {
        l=$0; sub(/^\|/,"",l); sub(/\|[[:space:]]*$/,"",l); n=split(l,c,"|")
        for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/,"",c[i])}
        if (c[1]=="owner") printf "%s\037%s\n", c[2], c[3] }' "$f")
  done < <(wl_queue_grep "$file" "$WL_QUEUE_ITEM.*<!-- ref: backlog -->")
  # `[[ -n ]]`-free: an empty section is fine; an unchecked deferral with no BL-NNN / CLOSE: is not
  unreconciled="$(awk '/^## Deferred/{s=1; next} /^## /{s=0} s && /^- \[ \]/' "$file" | grep -v -E 'BL-[0-9]+|CLOSE:' || true)"
fi
if [[ $sweep -eq 1 && ( -n "$owner_open" || -n "$unreconciled" ) ]]; then
  if [[ $force -eq 0 ]]; then
    echo "close refused for $(basename "$file"):" >&2
    [[ -z "$owner_open" ]] || { echo "  owner rows still unanswered (the owner has not looked; closing would convert outstanding into done):$owner_open" >&2; }
    [[ -z "$unreconciled" ]] || { echo "  unreconciled deferrals (name a BL-NNN on the line, or write CLOSE: <reason>):" >&2; printf '%s\n' "$unreconciled" | sed 's/^/    /' >&2; }
    echo "  --force closes anyway and records what it overrode" >&2
    exit 2
  fi
  echo "FORCED close of $(basename "$file") — overriding:" >&2
  [[ -z "$owner_open" ]] || echo "  unanswered owner rows:$owner_open" >&2
  [[ -z "$unreconciled" ]] || { echo "  unreconciled deferrals:" >&2; printf '%s\n' "$unreconciled" | sed 's/^/    /' >&2; }
  { printf -- '\n- Closed %s (%s) with --force, overriding:' "$today" "$status"
    [[ -z "$owner_open" ]] || printf ' unanswered owner rows —%s' "$(printf '%s' "$owner_open" | tr '\n' ' ' | tr -s ' ')"
    [[ -z "$unreconciled" ]] || printf ' unreconciled deferrals — %s' "$(printf '%s' "$unreconciled" | tr '\n' ' ' | tr -s ' ')"
    printf '\n'; } >> "$file"
fi

# front matter only: a whole-file sed also rewrote `status:`/`updated:` lines in the body
set_front_matter "$file" "status=$status" "updated=$today" || { echo "no front matter in $file" >&2; exit 2; }

# surface any still-open upstream refs for manual closure propagation.
# `|| true`: grep exits 1 when a queue has only inline refs — without it,
# pipefail+errexit killed the script here, AFTER the status mutation above.
open_refs="$( (grep -oE '<!-- ref: (backlog|plan|audit) -->' "$file" || true) | wc -l | tr -d ' ')"
[[ "$open_refs" -gt 0 ]] && echo "note: $open_refs tracked upstream ref(s) — run backlog/scripts/reconcile.sh for closure propagation" >&2

# archive on close (D-10): the `worklist/<file>` cross-ref keeps resolving via _archive/
mkdir -p "$WL_DIR/_archive"
mv "$file" "$dest"
echo "CLOSED $dest"
