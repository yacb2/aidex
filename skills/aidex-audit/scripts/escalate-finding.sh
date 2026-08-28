#!/usr/bin/env bash
# escalate-finding.sh — move an audit finding to the backlog.
# Usage: escalate-finding.sh <finding-id>

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

if [[ "${1:-}" == "escalate" ]]; then shift; fi

if [[ $# -lt 1 ]]; then
  cat <<EOF >&2
Usage: /aidex-audit escalate <finding-id>

Example:
  /aidex-audit escalate BUG-01-3
EOF
  exit 2
fi

FINDING_ID="$1"
ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"
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

# Delegate to aidex-backlog. Resolve its script path.
REGISTER=""
for candidate in \
  "$SKILL_DIR/../aidex-backlog/scripts/register-item.sh" \
  "$ROOT/skills/aidex-backlog/scripts/register-item.sh" \
  "$HOME/.claude/skills/aidex-backlog/scripts/register-item.sh" \
  "$HOME/.claude/skills/aidex-backlog/scripts/register-item.sh"
do
  if [[ -f "$candidate" && -x "$candidate" ]]; then
    REGISTER="$candidate"
    break
  fi
done

if [[ -z "$REGISTER" ]]; then
  die "aidex-backlog script not found. Run './install.sh --update' to install it."
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

info "Creating backlog entry for $FINDING_ID via aidex-backlog"
BACKLOG_FILE="$("$REGISTER" --origin audit --finding "$FINDING_ID" --audit-run "$RUN_REF" --title "$SUMMARY" "${PRIORITY_ARG[@]}")"

if [[ -z "$BACKLOG_FILE" || ! -f "$BACKLOG_FILE" ]]; then
  die "aidex-backlog did not return a valid entry path"
fi

# Canon cross-ref MARKER (D-03: <type>/<filename>, never a markdown relative link).
MARKER="backlog/$(basename "$BACKLOG_FILE" .md)"
mark_row_escalated "$INVENTORY" "$FINDING_ID" "$MARKER"

ok "$FINDING_ID escalated"
printf '  backlog entry: %s\n' "$BACKLOG_FILE" >&2
printf '  inventory row: status -> done, Escalated To -> %s\n' "$MARKER" >&2
printf '\nNext: /aidex-audit validate\n' >&2
