#!/usr/bin/env bash
# escalate-finding.sh — move an audit finding to the backlog.
# Usage: escalate-finding.sh <finding-id>... [--page <consultation-page>]
# A finding id may be qualified as <methodology>/<id> (e.g. ux/F-1); a bare id
# held by more than one methodology's inventory is refused, naming each.
# A batch (several ids, or a second escalation within 10 min of the last one)
# is refused without --page: an existing .html/.md page citing every id (USAGE-30).

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

if [[ "${1:-}" == "escalate" ]]; then shift; fi

PAGE=""; IDS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --page)
      [[ $# -ge 2 && "$2" != --* ]] || { echo "escalate-finding.sh: --page needs a value (path to a consultation page)" >&2; exit 2; }
      PAGE="$2"; shift 2 ;;
    *) IDS+=("$1"); shift ;;
  esac
done

if [[ ${#IDS[@]} -lt 1 ]]; then
  cat <<EOF >&2
Usage: /aidex:audit escalate <finding-id>... [--page <consultation-page>]

Example:
  /aidex:audit escalate BUG-01-3
EOF
  exit 2
fi

# De-duplicate ids (order kept) so "F-1 F-1" is one finding, not a "batch".
UNIQ=(); seen=" "
for id in "${IDS[@]}"; do
  case "$seen" in *" $id "*) ;; *) UNIQ+=("$id"); seen="$seen$id " ;; esac
done
IDS=("${UNIQ[@]}")

ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"

# Escalation log lives outside the committed tree, one file per project root.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/aidex/escalation-log"
LOG="$LOG_DIR/$(printf '%s' "$ROOT" | path_digest)"
mkdir -p "$LOG_DIR"

# One kernel lock per project (lock_take, fd 8) is held until this script exits: the
# done checks, the 10-minute window, the filing and the mark all happen under it, so
# two concurrent escalations of one id cannot both file. A batch's per-id children
# inherit it (re-entrant take). `.flock`, never the `.lock` DIRECTORY the old mkdir lock
# may have left.
lock_take "$LOG.flock" 10 8 || die "could not take the escalation lock $LOG.flock (held by another escalation); nothing was escalated"

# Resolve every id and refuse what cannot be escalated BEFORE escalating anything: a
# row the vocabulary already counts as done (done; legacy escalated, closed:
# audit-conventions.md §Status map), a row the mark could not rewrite, a lock directory
# the mark would refuse (each would otherwise leave a filed item behind).
for id in "${IDS[@]}"; do
  inv="$(find_inventory_for_id "$AUDITS_DIR" "$id")" || { [[ $? -eq 2 ]] && exit 2
    die "finding $id not found in any audits/<methodology>/00-inventory.md (or legacy root inventory)"; }
  # The done check comes from the awk that selects the row for the mark, so both skip
  # the same comments and read the same cells.
  finding_row_markable "$inv" "${id#*/}" || case $? in
    4) die "finding $id is already done (escalated); nothing was escalated" ;;
    5) die "finding $id was dropped (won't fix); reopen its row (status open) first if you want to escalate it; nothing was escalated" ;;
    *) die "finding $id's row in $inv cannot be marked escalated (a comment on the row, a status outside open/doing/done/dropped and the legacy words, or fewer than 9 columns): fix the row first; nothing was escalated" ;;
  esac
  inventory_lock_path "$inv" > /dev/null || exit 2
done

# A consultation page: the artifact kit's stamp plus at least one consult-group,
# so a board render (inventory/backlog index) never qualifies. A .spec.md page
# is judged by its built .html sibling.
page_is_consultation() {
  local page="$1"
  case "$page" in
    *.html) html="$page" ;;
    *.spec.md) html="${page%.spec.md}.html" ;;
    *) return 1 ;;
  esac
  PAGE_HTML="$html"
  [[ -f "$page" && -f "$html" ]] \
    && grep -qE '<meta[^>]+name=["'"'"']?artifact-kit' "$html" \
    && grep -qE 'class=["'"'"'][^"'"'"']*consult-group' "$html"
}

# The 10-minute window: checked under the lock; an escalation is logged once it lands.
NOW="$(date +%s)"
RECENT=0
[[ -f "$LOG" ]] && RECENT="$(awk -v n="$NOW" 'n - $1 < 600' "$LOG" | wc -l | tr -d ' ')"
if (( ${#IDS[@]} + RECENT > 1 )); then
  if [[ -z "$PAGE" ]] || ! page_is_consultation "$PAGE"; then
    die "escalating more than one finding in one batch (or within 10 min of the last escalation) needs a consultation page: pass --page <.html built by /aidex:artifact (kit stamp and a consult-group) or its .spec.md, citing the finding ids>. Build one with /aidex:artifact first (USAGE-30)."
  fi
  for id in "${IDS[@]}"; do
    cites_id "$PAGE_HTML" "${id#*/}" || die "page $PAGE does not cite finding $id"
  done
fi
if [[ ${#IDS[@]} -gt 1 ]]; then
  DONE_IDS=""; LEFT=" ${IDS[*]} "
  for id in "${IDS[@]}"; do
    bash "$0" "$id" --page "$PAGE" || { rc=$?
      # rc 4: the child filed (or may have filed) a backlog item but did not mark the
      # row (its message says which), so the id is not "not escalated": a rerun of the
      # not-escalated ids must not file it twice
      FILED=""
      if [[ $rc -eq 4 ]]; then FILED=" filed, row not marked: $id;"; LEFT="${LEFT/ "$id" / }"; fi
      LEFT="${LEFT% }"
      err "error: the batch stopped at $id. already escalated:${DONE_IDS:- none};$FILED not escalated:${LEFT:- none}"
      exit $rc; }
    DONE_IDS="$DONE_IDS $id"; LEFT="${LEFT/ "$id" / }"
  done
  exit 0
fi

FINDING_ID="${IDS[0]}"
# Canon layout: the finding lives in some audits/<methodology>/00-inventory.md
# (legacy root boards still accepted read-only).
INVENTORY="$(find_inventory_for_id "$AUDITS_DIR" "$FINDING_ID")" || { [[ $? -eq 2 ]] && exit 2
  die "finding $FINDING_ID not found in any audits/<methodology>/00-inventory.md (or legacy root inventory)"; }
FINDING_ID="${FINDING_ID#*/}"  # the inventory is resolved; everything below takes the bare id

# Methodology = the inventory's parent folder; empty for legacy root boards.
METHODOLOGY=""
INV_PARENT="$(dirname "$INVENTORY")"
[[ "$INV_PARENT" != "$AUDITS_DIR" ]] && METHODOLOGY="$(basename "$INV_PARENT")"

# Find which audit run recorded this finding (searched within its methodology).
AUDIT_RUN="$(find_audit_run "$INV_PARENT" "$FINDING_ID")"

# origin_ref path segment: canon audit/<methodology>/<run>/<id>; legacy audit/<run>/<id>.
RUN_REF="$AUDIT_RUN"
[[ -n "$METHODOLOGY" ]] && RUN_REF="$METHODOLOGY/$AUDIT_RUN"

# Delegate to backlog. Resolve its script path.
require_sibling_script REGISTER backlog register-item.sh "$ROOT"

# Extract Summary (cell 5) and Severity (cell 7) for the finding row.
# Output: "<summary>\t<severity>" — tab-separated so summaries with spaces survive.
ROW_DATA="$(extract_finding_row "$INVENTORY" "$FINDING_ID")"

SUMMARY="${ROW_DATA%%$'\t'*}"
SEVERITY="${ROW_DATA##*$'\t'}"
[[ "$SEVERITY" == "$ROW_DATA" ]] && SEVERITY=""  # no tab → no severity extracted

if [[ -z "$SUMMARY" ]]; then
  warn "could not extract Summary for $FINDING_ID from INVENTORY — falling back to ID-based slug. Check the row's status column carries a base status (open, doing, done, dropped) or a legacy value."
  SUMMARY="Escalated from $FINDING_ID"
fi

# Map Severity → backlog priority. Default P2 when severity is missing or unrecognized.
case "$SEVERITY" in
  P0|P1|P2|P3) PRIORITY="$SEVERITY" ;;
  "")
    warn "no Severity found for $FINDING_ID — backlog entry will default to P2"
    PRIORITY=P2
    ;;
  *)
    warn "unrecognized Severity '$SEVERITY' for $FINDING_ID — backlog entry will default to P2"
    PRIORITY=P2
    ;;
esac

info "Creating backlog entry for $FINDING_ID via backlog"
# From here an item may be filed: it counts toward the window, and any failure exits 4
# (maybe filed, row not marked), never as "not escalated".
echo "$NOW $$" >> "$LOG"
BACKLOG_FILE="$("$REGISTER" --origin audit --finding "$FINDING_ID" --audit-run "$RUN_REF" --title "$SUMMARY" --priority "$PRIORITY")" \
  && [[ -n "$BACKLOG_FILE" && -f "$BACKLOG_FILE" ]] \
  || { err "error: registering the backlog item for $FINDING_ID failed or returned no entry path, after it started: an item may have been filed and the row in $INVENTORY was not marked; check the backlog before rerunning"; exit 4; }

# Canon cross-ref MARKER (D-03: <type>/<filename>, never a markdown relative link).
MARKER="backlog/$(basename "$BACKLOG_FILE" .md)"
# The row was checked markable above, under the lock; a mark that still fails exits 4
# (filed, not marked) naming the filed item, so a rerun is not a silent duplicate.
mark_row_escalated "$INVENTORY" "$FINDING_ID" "$MARKER" \
  || { err "error: $(sed -n 's/^id: *//p' "$BACKLOG_FILE") ($BACKLOG_FILE) was filed for $FINDING_ID, but its row in $INVENTORY was not marked: set it to done with Escalated To $MARKER by hand; do not rerun (it would file a duplicate)"; exit 4; }

ok "$FINDING_ID escalated"
printf '  backlog entry: %s\n' "$BACKLOG_FILE" >&2
printf '  inventory row: status -> done, Escalated To -> %s\n' "$MARKER" >&2
printf '\nNext: /aidex:audit validate\n' >&2
