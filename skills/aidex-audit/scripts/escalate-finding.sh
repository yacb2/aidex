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
# Canonical inventory filename per D-02 is 00-inventory.md; legacy INVENTORY.md still accepted.
INVENTORY="$(resolve_inventory "$AUDITS_DIR")"

# Verify finding exists
if ! grep -qE "^\|[[:space:]]*${FINDING_ID}[[:space:]]*\|" "$INVENTORY"; then
  die "finding $FINDING_ID not found in $(basename "$INVENTORY")"
fi

# Find which audit run(s) recorded this finding (for Origen path)
AUDIT_RUN="$(find_audit_run "$AUDITS_DIR" "$FINDING_ID")"

# Delegate to aidex-backlog. Resolve its script path.
REGISTER=""
for candidate in \
  "$SKILL_DIR/../aidex-backlog/scripts/register-item.sh" \
  "$ROOT/skills/aidex-backlog/scripts/register-item.sh" \
  "$HOME/.aidex/skills/aidex-backlog/scripts/register-item.sh" \
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
  warn "could not extract Summary for $FINDING_ID from INVENTORY — falling back to ID-based slug. Check the row's status column matches one of: open, triaged, escalated, in-progress, closed, dropped."
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
BACKLOG_FILE="$("$REGISTER" --origin audit --finding "$FINDING_ID" --audit-run "$AUDIT_RUN" --title "$SUMMARY" "${PRIORITY_ARG[@]}")"

if [[ -z "$BACKLOG_FILE" || ! -f "$BACKLOG_FILE" ]]; then
  die "aidex-backlog did not return a valid entry path"
fi

# Compute relative path from INVENTORY to the backlog file, then mark the row.
REL_BACKLOG="$(relpath_from "$BACKLOG_FILE" "$INVENTORY")"
mark_row_escalated "$INVENTORY" "$FINDING_ID" "[$REL_BACKLOG]($REL_BACKLOG)"

ok "$FINDING_ID escalated"
printf '  backlog entry: %s\n' "$BACKLOG_FILE" >&2
printf '  INVENTORY row: status -> escalated, Escalated To -> %s\n' "$REL_BACKLOG" >&2
printf '\nNext: /aidex-audit validate\n' >&2
