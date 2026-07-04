#!/usr/bin/env bash
# Shared helpers for audit scripts.
# Source: . "$(dirname "$0")/_lib.sh"

set -euo pipefail

# Resolve the skill directory even when invoked via symlink.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPLATES_DIR="$SKILL_DIR/assets/templates"

# Generic helpers (colors, log-family, find_project_root, today/today_iso,
# render_template, is_valid_slug, slugify, relpath_from) come from the SHARED
# library — single-sourced so the copies cannot diverge (the 2026-07-02 suite
# analysis found ~80 duplicated lines and a diverged find_project_root fork).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

# ---- audit-specific helpers only below this line ----

# Known audit types — canon SHORT names (decision/2026-07-02-audit-rebuild-canon-decisions)
AUDIT_TYPES=(ux ai-opportunities security perf a11y hitl retest custom)

# Normalize input (incl. legacy -audit-suffixed and ia- aliases) to the canon
# short name. Returns non-zero if the type is unknown.
normalize_type() {
  local t="$1"
  case "$t" in
    ux|ux-audit)                   printf '%s\n' "ux"; return 0 ;;
    ia|ai|ia-opportunities|ai-opportunities) printf '%s\n' "ai-opportunities"; return 0 ;;
    retest|re-test)                printf '%s\n' "retest"; return 0 ;;
    sec|security|security-audit)   printf '%s\n' "security"; return 0 ;;
    perf|performance|perf-audit)   printf '%s\n' "perf"; return 0 ;;
    a11y|accessibility|a11y-audit) printf '%s\n' "a11y"; return 0 ;;
    hitl|hitl-guided-manual|guided-manual) printf '%s\n' "hitl"; return 0 ;;
    custom)                        printf '%s\n' "custom"; return 0 ;;
    *) return 1 ;;
  esac
}

# Human-readable methodology name for templates.
methodology_name() {
  case "$1" in
    ux)               printf 'UX' ;;
    ai-opportunities) printf 'AI Opportunities' ;;
    security)         printf 'Security' ;;
    perf)             printf 'Performance' ;;
    a11y)             printf 'Accessibility' ;;
    hitl)             printf 'HITL Guided Manual' ;;
    retest)           printf 'Re-test' ;;
    *)                printf '%s' "$1" ;;
  esac
}

is_known_type() {
  normalize_type "$1" > /dev/null 2>&1
}

# Resolve the inventory file: canonical 00-inventory.md, else legacy INVENTORY.md.
# Prints the path, or dies if neither exists.
# Usage: resolve_inventory <audits_dir>
resolve_inventory() {
  local audits_dir="$1"
  if [[ -f "$audits_dir/00-inventory.md" ]]; then
    printf '%s\n' "$audits_dir/00-inventory.md"
  elif [[ -f "$audits_dir/INVENTORY.md" ]]; then
    printf '%s\n' "$audits_dir/INVENTORY.md"
  else
    die "inventory not found: expected $audits_dir/00-inventory.md (or legacy INVENTORY.md)"
  fi
}

# Locate which inventory holds a finding id under the CANON layout: searches each
# audits/<methodology>/00-inventory.md, then the legacy root boards. Prints the
# inventory path (methodology derivable from its parent), or returns 1.
# Usage: find_inventory_for_id <audits_dir> <finding_id>
find_inventory_for_id() {
  local audits_dir="$1" finding_id="$2" inv
  for inv in "$audits_dir"/*/00-inventory.md "$audits_dir/00-inventory.md" "$audits_dir/INVENTORY.md"; do
    [[ -f "$inv" ]] || continue
    if grep -qE "^\|[[:space:]]*${finding_id}[[:space:]]*\|" "$inv"; then
      printf '%s\n' "$inv"
      return 0
    fi
  done
  return 1
}

# Find which audit run folder recorded a finding. Prints the run folder basename;
# falls back to the most recent run folder, or "unknown-run".
# Usage: find_audit_run <audits_dir> <finding_id>
find_audit_run() {
  local audits_dir="$1" finding_id="$2" audit_run="" f
  if compgen -G "$audits_dir/[0-9]*-*/findings.md" > /dev/null; then
    while IFS= read -r f; do
      if grep -q "$finding_id" "$f"; then
        audit_run="$(basename "$(dirname "$f")")"
        break
      fi
    done < <(find "$audits_dir" -type f -name findings.md -path '*/[0-9]*-*/findings.md' | sort)
  fi
  if [[ -z "$audit_run" ]]; then
    audit_run="$(ls -1d "$audits_dir"/[0-9]*-*/ 2>/dev/null | sort | tail -1 | xargs -I{} basename {})"
  fi
  [[ -z "$audit_run" ]] && audit_run="unknown-run"
  printf '%s\n' "$audit_run"
}

# Extract "<summary>\t<severity>" for a finding row from the inventory.
# Prints empty if not found. Skips HTML comment blocks so template example rows
# never pollute the match. Summary is cell 5, status cell 6, severity cell 7.
# Usage: extract_finding_row <inventory> <finding_id>
extract_finding_row() {
  local inventory="$1" finding_id="$2"
  awk -v id="$finding_id" '
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
        # (base vocab open/doing/done/dropped + legacy words, read-tolerated)
        if (cells[6] ~ /open|doing|done|dropped|triaged|escalated|in-progress|closed/) {
          print cells[5] "\t" cells[7]
          exit
        }
      }
    }
  ' "$inventory"
}

# Rewrite a finding's inventory row in place on escalation, per the CANON model
# (base vocab + ISO dates + <type>/<filename> markers): status -> done, Last
# Updated -> today (ISO), today appended to Audit Runs (deduped), "Escalated To"
# cell set to <ref> — a canon MARKER like backlog/<filename> or loop/<filename>,
# never a markdown link. Skips HTML comment blocks so template EXAMPLE rows are
# never rewritten.
# Usage: mark_row_escalated <inventory> <finding_id> <ref>
mark_row_escalated() {
  local inventory="$1" finding_id="$2" link="$3" tmp
  tmp="$(mktemp)"
  awk -v id="$finding_id" -v link="$link" -v today="$(today_iso)" '
    BEGIN { in_comment = 0 }
    {
      # Track whether the CURRENT line is inside a multi-line HTML comment.
      line = $0
      skip_parse = in_comment
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

      # Verify this is a real finding row (status column has a known marker,
      # base vocab or legacy read-tolerated)
      s = cells[6]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (s !~ /open|doing|done|dropped|triaged|escalated|in-progress|closed/) {
        print $0; next
      }

      # Update fields (canon: done + escalated_to modifier, never a status word)
      cells[6]  = " done "
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
  ' "$inventory" > "$tmp"
  mv "$tmp" "$inventory"
}

# Compute the relative path from a base file's directory to a target file.
