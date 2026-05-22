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
if [[ -f "$AUDITS_DIR/00-inventory.md" ]]; then
  INVENTORY="$AUDITS_DIR/00-inventory.md"
elif [[ -f "$AUDITS_DIR/INVENTORY.md" ]]; then
  INVENTORY="$AUDITS_DIR/INVENTORY.md"
else
  die "inventory not found: expected $AUDITS_DIR/00-inventory.md (or legacy INVENTORY.md)"
fi
BACKLOG_DIR="$ROOT/.context/backlog"

# Verify finding exists
if ! grep -qE "^\|[[:space:]]*${FINDING_ID}[[:space:]]*\|" "$INVENTORY"; then
  die "finding $FINDING_ID not found in $(basename "$INVENTORY")"
fi

# Find which audit run(s) recorded this finding (for Origen path)
AUDIT_RUN=""
if compgen -G "$AUDITS_DIR/[0-9]*-*/findings.md" > /dev/null; then
  while IFS= read -r f; do
    if grep -q "$FINDING_ID" "$f"; then
      AUDIT_RUN="$(basename "$(dirname "$f")")"
      break
    fi
  done < <(find "$AUDITS_DIR" -type f -name findings.md -path '*/[0-9]*-*/findings.md' | sort)
fi
# Fallback: if no run references it, pick the most recent audit folder
if [[ -z "$AUDIT_RUN" ]]; then
  AUDIT_RUN="$(ls -1d "$AUDITS_DIR"/[0-9]*-*/ 2>/dev/null | sort | tail -1 | xargs -I{} basename {})"
fi
[[ -z "$AUDIT_RUN" ]] && AUDIT_RUN="unknown-run"

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
# Skip HTML comment blocks so example rows in the template don't pollute the match.
ROW_DATA="$(awk -v id="$FINDING_ID" '
  BEGIN { in_comment = 0 }
  {
    line = $0
    # Handle HTML comments (single-line and multi-line)
    while (1) {
      if (in_comment) {
        end = index(line, "-->")
        if (end == 0) { line = ""; break }
        line = substr(line, end + 3)
        in_comment = 0
      } else {
        start = index(line, "<!--")
        if (start == 0) break
        before = substr(line, 1, start - 1)
        after = substr(line, start + 4)
        end = index(after, "-->")
        if (end == 0) { line = before; in_comment = 1; break }
        line = before substr(after, end + 3)
      }
    }
    # Parse as pipe-delimited row
    if (line !~ /^\|/) next
    n = split(line, cells, "|")
    if (n < 11) next
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[2])
    if (cells[2] == id) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[5])
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[6])
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[7])
      # Must also have a real-looking status to avoid matching reference tables
      if (cells[6] ~ /open|triaged|escalated|in-progress|closed|dropped/) {
        print cells[5] "\t" cells[7]
        exit
      }
    }
  }
' "$INVENTORY")"

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

# Compute relative path from INVENTORY to the backlog file
REL_BACKLOG="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], start=os.path.dirname(sys.argv[2])))" "$BACKLOG_FILE" "$INVENTORY" 2>/dev/null || echo "$BACKLOG_FILE")"

# Update INVENTORY row: set Status to "escalated", set Escalated To column.
# Skip HTML comment blocks so the template's EXAMPLE rows are never rewritten.
TMP="$(mktemp)"
awk -v id="$FINDING_ID" -v link="[$REL_BACKLOG]($REL_BACKLOG)" -v today="$(today)" '
  BEGIN { in_comment = 0 }
  {
    # Track whether the CURRENT line is inside a multi-line HTML comment.
    # We need to detect comment state BEFORE parsing the row, and pass the line through unchanged.
    line = $0
    skip_parse = in_comment
    # Handle comment delimiters on this line to update in_comment for next line
    tmp = line
    while (1) {
      if (in_comment) {
        end = index(tmp, "-->")
        if (end == 0) { tmp = ""; break }
        tmp = substr(tmp, end + 3)
        in_comment = 0
      } else {
        start = index(tmp, "<!--")
        if (start == 0) break
        after = substr(tmp, start + 4)
        end = index(after, "-->")
        if (end == 0) { in_comment = 1; break }
        tmp = substr(after, end + 3)
      }
    }

    # If the line started inside a comment or contained comment markers, pass through unchanged.
    if (skip_parse || index($0, "<!--") > 0 || index($0, "-->") > 0) {
      print $0
      next
    }

    # Parse as pipe-delimited
    if ($0 !~ /^\|/) { print $0; next }
    n = split($0, cells, "|")
    if (n < 11) { print $0; next }

    t = cells[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    if (t != id) { print $0; next }

    # Verify this is a real finding row (status column has a known marker)
    s = cells[6]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    if (s !~ /open|triaged|escalated|in-progress|closed|dropped/) {
      print $0; next
    }

    # Update fields
    cells[6]  = " escalated "
    cells[9]  = " " today " "
    runs = cells[10]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", runs)
    if (index(runs, today) == 0) {
      if (runs == "" || runs == "—") runs = today
      else runs = runs ", " today
    }
    cells[10] = " " runs " "
    cells[11] = " " link " "

    # Reassemble
    out = cells[1]
    for (i = 2; i <= n; i++) out = out "|" cells[i]
    print out
  }
' "$INVENTORY" > "$TMP"
mv "$TMP" "$INVENTORY"

ok "$FINDING_ID escalated"
printf '  backlog entry: %s\n' "$BACKLOG_FILE" >&2
printf '  INVENTORY row: status -> escalated, Escalated To -> %s\n' "$REL_BACKLOG" >&2
printf '\nNext: /aidex-audit validate\n' >&2
