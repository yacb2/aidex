#!/usr/bin/env bash
# validate-audit.sh — check coherence of .context/audits/
# Usage: validate-audit.sh [path]
#   [path]: optional audits directory (default: auto-detect from cwd)
# Exit codes: 0 OK · 1 violations found · 2 usage error

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

if [[ "${1:-}" == "validate" ]]; then shift; fi

JSON_OUT=0
if [[ "${1:-}" == "--json" ]]; then
  JSON_OUT=1
  shift
fi

if [[ -n "${1:-}" ]]; then
  AUDITS_DIR="$1"
else
  ROOT="$(find_project_root)"
  AUDITS_DIR="$ROOT/.context/audits"
fi

[[ -d "$AUDITS_DIR" ]] || die "no audits directory at $AUDITS_DIR"

VIOLATIONS=()
WARNINGS=()
runs=0
findings_in_inventory=0
findings_open=0
findings_closed=0
findings_dropped=0
findings_escalated=0
findings_in_progress=0
findings_triaged=0
total_pipe_rows=0
is_legacy=0

add_violation() { VIOLATIONS+=("$1"); }
add_warning()   { WARNINGS+=("$1"); }

# --- Check 1: canonical files exist ---
for f in INVENTORY.md METHODOLOGY.md CHANGELOG.md; do
  [[ -f "$AUDITS_DIR/$f" ]] || add_violation "missing canonical file: $f"
done

# --- Check 2: each run folder has index.md + findings.md ---
for dir in "$AUDITS_DIR"/[0-9]*-*/; do
  [[ -d "$dir" ]] || continue
  runs=$((runs+1))
  [[ -f "$dir/index.md" ]]    || add_violation "missing index.md in $(basename "$dir")"
  [[ -f "$dir/findings.md" ]] || add_violation "missing findings.md in $(basename "$dir")"
done

# --- Check 3: parse INVENTORY rows and verify fields ---
# Use newline-separated variables instead of associative arrays for Bash 3.2 compatibility.
inventory_ids=""   # newline-separated IDs seen so far

id_seen() {
  # Check if $1 is in the newline-separated $inventory_ids
  local needle="$1"
  [[ -n "$inventory_ids" ]] && printf '%s\n' "$inventory_ids" | grep -qxF "$needle"
}

# Strip HTML comment blocks from a file.
# Supports multi-line <!-- ... --> by joining lines and re-splitting.
strip_html_comments() {
  awk '
    BEGIN { in_comment = 0 }
    {
      line = $0
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
          after  = substr(line, start + 4)
          end = index(after, "-->")
          if (end == 0) {
            line = before
            in_comment = 1
            break
          } else {
            line = before substr(after, end + 3)
          }
        }
      }
      print line
    }
  ' "$1"
}

# A "real" status cell contains one of the known status words (lowercase text only).
is_real_status() {
  case "$1" in
    *open*|*triaged*|*escalated*|*in-progress*|*closed*|*dropped*) return 0 ;;
    *) return 1 ;;
  esac
}

# Detect a legacy INVENTORY schema: has pipe rows but none pass canonical validation.
# Called after full parsing.
has_legacy_inventory() {
  [[ "$total_pipe_rows" -gt 0 ]] && [[ "$findings_in_inventory" -eq 0 ]]
}

if [[ -f "$AUDITS_DIR/INVENTORY.md" ]]; then
  # Match rows that look like: | ID | Type | Module | Summary | Status | ...
  while IFS= read -r line; do
    # Skip header and separator lines
    [[ "$line" =~ ^\|[[:space:]]*ID[[:space:]]*\| ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*-+ ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*— ]] && continue  # placeholder row

    # Count pipes to decide if the row could be a data row
    pipe_count="$(printf '%s' "$line" | tr -cd '|' | wc -c | tr -d ' ')"

    # Look at column 2 (first data cell) — if it looks like an ID, this is
    # plausibly a finding row regardless of canonical vs legacy schema.
    # Used for legacy-schema detection below.
    first_data_cell="$(printf '%s' "$line" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"
    if [[ "$pipe_count" -ge 5 ]] && [[ "$first_data_cell" =~ ^[A-Z]+[-A-Z0-9]*-[0-9]+$ ]]; then
      total_pipe_rows=$((total_pipe_rows+1))
    fi

    # A canonical finding row must have at least 10 pipes (11 cells incl. empty edges)
    [[ "$pipe_count" -ge 10 ]] || continue

    # Split on |
    IFS='|' read -r _ c_id c_type c_module c_summary c_status c_severity c_first c_last c_runs c_escalated _rest <<< "$line"
    id="$(echo "$c_id" | xargs)"
    status="$(echo "${c_status:-}" | xargs)"
    escalated="$(echo "${c_escalated:-}" | xargs)"

    # Skip empty or dash-only IDs
    [[ -z "$id" || "$id" == "—" ]] && continue
    # Skip rows that don't look like IDs (must contain a letter)
    [[ "$id" =~ [A-Za-z] ]] || continue
    # Skip rows whose Status column doesn't look like a real status — avoids parsing
    # reference tables or explanatory tables as findings.
    is_real_status "$status" || continue

    if id_seen "$id"; then
      add_violation "duplicate ID in INVENTORY: $id"
    fi
    inventory_ids="$inventory_ids"$'\n'"$id"
    findings_in_inventory=$((findings_in_inventory+1))

    case "$status" in
      *open*)         findings_open=$((findings_open+1)) ;;
      *triaged*)      findings_triaged=$((findings_triaged+1)) ;;
      *escalated*)    findings_escalated=$((findings_escalated+1)) ;;
      *in-progress*)  findings_in_progress=$((findings_in_progress+1)) ;;
      *closed*)       findings_closed=$((findings_closed+1)) ;;
      *dropped*)      findings_dropped=$((findings_dropped+1)) ;;
    esac

    # States with forward-links must have a non-empty Escalated To
    case "$status" in
      *escalated*|*in-progress*|*closed*)
        if [[ -z "$escalated" || "$escalated" == "—" ]]; then
          add_violation "finding $id is $status but has no Escalated To reference"
        fi
        ;;
    esac
  done < <(strip_html_comments "$AUDITS_DIR/INVENTORY.md")

  # --- Legacy-schema detection: has pipe rows but none parsed as canonical findings ---
  if has_legacy_inventory; then
    is_legacy=1
    add_warning "INVENTORY.md uses a legacy schema ($total_pipe_rows pipe-rows detected, 0 parse as canonical). Expected columns: | ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To |. Migrate with /audit migrate or adapt manually."
  fi

  # --- Check 4: IDs mentioned in per-run findings.md exist in INVENTORY ---
  # Skipped entirely for legacy schemas — orphan-reference checking makes no sense
  # when the canonical INVENTORY can't be parsed.
  if [[ $is_legacy -eq 0 ]]; then
    while IFS= read -r findings_file; do
      # Extract IDs OUTSIDE HTML comments (strip them first).
      # Require a numeric suffix to avoid false positives on placeholders like
      # IA-EXISTE, BUG-NN, D1-D2, RE-ALL.
      while IFS= read -r mentioned_id; do
        [[ -z "$mentioned_id" ]] && continue
        if ! id_seen "$mentioned_id"; then
          rel="${findings_file#$AUDITS_DIR/}"
          add_violation "$rel references $mentioned_id which is not in INVENTORY"
        fi
      done < <(strip_html_comments "$findings_file" | grep -oE '\b[A-Z]+(-[A-Z0-9]+)?-[0-9]+\b' 2>/dev/null | sort -u)
    done < <(find "$AUDITS_DIR" -type f -name findings.md -path '*/[0-9]*-*/findings.md' 2>/dev/null)
  fi

  # --- Check 5: backlog entries citing audit origin must reference valid IDs ---
  # Skipped for legacy schemas.
  if [[ $is_legacy -eq 0 ]]; then
    BACKLOG_DIR="$(dirname "$AUDITS_DIR")/backlog"
    if [[ -d "$BACKLOG_DIR" ]]; then
      while IFS= read -r entry; do
        # Accept both `origin_ref: audit/` (YAML frontmatter) and legacy `Origen: audit/`
        origin_ref_line="$(grep -E '^origin_ref:[[:space:]]*audit/' "$entry" 2>/dev/null || true)"
        if [[ -z "$origin_ref_line" ]]; then
          origin_ref_line="$(grep -E '^Origen:[[:space:]]*audit/' "$entry" 2>/dev/null || true)"
        fi
        [[ -z "$origin_ref_line" ]] && continue
        # Extract the finding ID part (after last /)
        ref_id="${origin_ref_line##*/}"
        ref_id="$(echo "$ref_id" | xargs)"
        if ! id_seen "$ref_id"; then
          rel="${entry#$(dirname "$AUDITS_DIR")/}"
          add_violation "backlog entry $rel cites audit finding $ref_id which is not in INVENTORY"
        fi
      done < <(find "$BACKLOG_DIR" -maxdepth 2 -type f -name '*.md')
    fi
  fi
fi

# --- Report ---
if [[ $JSON_OUT -eq 1 ]]; then
  # Emit minimal JSON (no jq dependency for basic output)
  printf '{\n'
  printf '  "audits_dir": "%s",\n' "$AUDITS_DIR"
  printf '  "runs": %d,\n' "$runs"
  printf '  "findings_in_inventory": %d,\n' "$findings_in_inventory"
  printf '  "stats": {"open":%d,"triaged":%d,"escalated":%d,"in_progress":%d,"closed":%d,"dropped":%d},\n' \
    "$findings_open" "$findings_triaged" "$findings_escalated" "$findings_in_progress" "$findings_closed" "$findings_dropped"
  printf '  "violations": ['
  for i in "${!VIOLATIONS[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    # Escape quotes and backslashes
    v="${VIOLATIONS[$i]//\\/\\\\}"
    v="${v//\"/\\\"}"
    printf '\n    "%s"' "$v"
  done
  printf '\n  ],\n'
  printf '  "warnings": ['
  for i in "${!WARNINGS[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    w="${WARNINGS[$i]//\\/\\\\}"
    w="${w//\"/\\\"}"
    printf '\n    "%s"' "$w"
  done
  printf '\n  ]\n'
  printf '}\n'
else
  printf '\n%sAudit validation — %s%s\n' "$C_BOLD" "$AUDITS_DIR" "$C_RESET"
  printf '%s  runs: %d · findings: %d (open:%d triaged:%d escalated:%d in-progress:%d closed:%d dropped:%d)%s\n\n' \
    "$C_DIM" "$runs" "$findings_in_inventory" \
    "$findings_open" "$findings_triaged" "$findings_escalated" "$findings_in_progress" "$findings_closed" "$findings_dropped" \
    "$C_RESET"

  if [[ ${#VIOLATIONS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    ok "OK — no violations"
  else
    if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
      err "Violations (${#VIOLATIONS[@]}):"
      for v in "${VIOLATIONS[@]}"; do
        printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$v"
      done
    fi
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
      warn "Warnings (${#WARNINGS[@]}):"
      for w in "${WARNINGS[@]}"; do
        printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$w"
      done
    fi
  fi
fi

[[ ${#VIOLATIONS[@]} -eq 0 ]] || exit 1
exit 0
