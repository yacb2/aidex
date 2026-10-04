#!/usr/bin/env bash
# escalate-finding.sh — move an audit finding to the backlog.
# Usage: escalate-finding.sh <finding-id>... [--page <consultation-page>]
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

# Resolve every id and refuse already-done rows BEFORE escalating anything.
for id in "${IDS[@]}"; do
  inv="$(find_inventory_for_id "$AUDITS_DIR" "$id")" \
    || die "finding $id not found in any audits/<methodology>/00-inventory.md (or legacy root inventory)"
  st="$(awk -F'|' -v id="$id" '{ k=$2; gsub(/^[ \t]+|[ \t]+$/, "", k); if (k == id) { v=$6; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit } }' "$inv")"
  [[ "$st" != "done" ]] || die "finding $id is already done (escalated); nothing was escalated"
done

# Escalation log lives outside the committed tree, one file per project root.
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/aidex/escalation-log"
LOG="$LOG_DIR/$(printf '%s' "$ROOT" | shasum | cut -d' ' -f1)"
mkdir -p "$LOG_DIR"

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
page_cites() { # whole-token match, never a substring (F-1 must not match F-10 or F-1.2)
  local esc; esc="$(printf '%s' "$2" | sed 's/[][\\.*^$/+?(){}|]/\\&/g')"
  grep -qE "(^|[^A-Za-z0-9_-])${esc}(\$|[^A-Za-z0-9_.-]|\.([^A-Za-z0-9_-]|\$))" "$1"
}

# Check-and-reserve the 10-minute window atomically (mkdir lock), so two
# concurrent single escalations cannot both pass. The reservation is appended
# before escalating and removed again if the escalation then fails.
LOCK="$LOG.lock"
MYLINE=""; HELD=0
acquire() { # take the mkdir lock; a lock older than 60 s is stale and taken over
  local _ age
  for _ in $(seq 1 100); do
    if mkdir "$LOCK" 2>/dev/null; then HELD=1; return 0; fi
    sleep 0.1
  done
  age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || date +%s) ))
  if (( age > 60 )); then
    echo "escalate-finding.sh: taking over a stale escalation lock ($LOCK, ${age}s old)" >&2
    rmdir "$LOCK" 2>/dev/null || true
    if mkdir "$LOCK" 2>/dev/null; then HELD=1; return 0; fi
  fi
  return 1
}
unlock() {
  if [[ "$HELD" == 1 ]]; then
    if ! rmdir "$LOCK" 2>/dev/null; then
      echo "escalate-finding.sh: could not release the escalation lock $LOCK" >&2
    fi
    HELD=0
  fi
  return 0
}
release() { # drop an unused reservation (under the lock), then the lock
  if [[ -n "$MYLINE" && -f "$LOG" ]]; then
    [[ "$HELD" == 1 ]] || acquire || true
    local tmp="$LOG.tmp.$$"
    grep -vxF -- "$MYLINE" "$LOG" > "$tmp" || true
    mv "$tmp" "$LOG"
  fi
  unlock
}
trap 'release' EXIT
acquire || die "could not take the escalation lock $LOCK (held by another escalation); nothing was escalated"
NOW="$(date +%s)"
RECENT=0
[[ -f "$LOG" ]] && RECENT="$(awk -v n="$NOW" 'n - $1 < 600' "$LOG" | wc -l | tr -d ' ')"
if (( ${#IDS[@]} + RECENT > 1 )); then
  if [[ -z "$PAGE" ]] || ! page_is_consultation "$PAGE"; then
    die "escalating more than one finding in one batch (or within 10 min of the last escalation) needs a consultation page: pass --page <.html built by /aidex:artifact (kit stamp and a consult-group) or its .spec.md, citing the finding ids>. Build one with /aidex:artifact first (USAGE-30)."
  fi
  for id in "${IDS[@]}"; do
    page_cites "$PAGE_HTML" "$id" || die "page $PAGE does not cite finding $id"
  done
fi
if [[ ${#IDS[@]} -gt 1 ]]; then
  trap - EXIT; unlock
  for id in "${IDS[@]}"; do bash "$0" "$id" --page "$PAGE" || exit $?; done
  exit 0
fi
MYLINE="$NOW $$"
echo "$MYLINE" >> "$LOG"
unlock

FINDING_ID="${IDS[0]}"
# Canon layout: the finding lives in some audits/<methodology>/00-inventory.md
# (legacy root boards still accepted read-only).
INVENTORY="$(find_inventory_for_id "$AUDITS_DIR" "$FINDING_ID")" \
  || die "finding $FINDING_ID not found in any audits/<methodology>/00-inventory.md (or legacy root inventory)"

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
REGISTER=""
for candidate in \
  "$SKILL_DIR/../backlog/scripts/register-item.sh" \
  "$ROOT/skills/backlog/scripts/register-item.sh"
do
  if [[ -f "$candidate" && -x "$candidate" ]]; then
    REGISTER="$candidate"
    break
  fi
done

if [[ -z "$REGISTER" ]]; then
  die "backlog script not found. Run './install.sh --update' to install it."
fi

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
  P0|P1|P2|P3) PRIORITY_ARG=(--priority "$SEVERITY") ;;
  "")
    warn "no Severity found for $FINDING_ID — backlog entry will default to P2"
    PRIORITY_ARG=()
    ;;
  *)
    warn "unrecognized Severity '$SEVERITY' for $FINDING_ID — backlog entry will default to P2"
    PRIORITY_ARG=()
    ;;
esac

info "Creating backlog entry for $FINDING_ID via backlog"
BACKLOG_FILE="$("$REGISTER" --origin audit --finding "$FINDING_ID" --audit-run "$RUN_REF" --title "$SUMMARY" "${PRIORITY_ARG[@]}")"

if [[ -z "$BACKLOG_FILE" || ! -f "$BACKLOG_FILE" ]]; then
  die "backlog did not return a valid entry path"
fi

# Canon cross-ref MARKER (D-03: <type>/<filename>, never a markdown relative link).
MARKER="backlog/$(basename "$BACKLOG_FILE" .md)"
mark_row_escalated "$INVENTORY" "$FINDING_ID" "$MARKER"

MYLINE=""
ok "$FINDING_ID escalated"
printf '  backlog entry: %s\n' "$BACKLOG_FILE" >&2
printf '  inventory row: status -> done, Escalated To -> %s\n' "$MARKER" >&2
printf '\nNext: /aidex:audit validate\n' >&2
