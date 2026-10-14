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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

# ---- audit-specific helpers only below this line ----

# require_sibling_script <var> <skill> <script> <project-root>: set <var> to the path of
# another skill's executable script, or die. The plugin ships every skill under one
# skills/ folder, so the sibling is normally "$SKILL_DIR/../<skill>/scripts/<script>";
# "<project-root>/skills/..." covers an audit copied out of the plugin into a project
# that carries its own skills/ folder. Runs in the caller's shell (printf -v, no
# command substitution) so the die exits the calling script.
require_sibling_script() {
  local __var="$1" __skill="$2" __script="$3" __root="$4" __c
  for __c in "$SKILL_DIR/../$__skill/scripts/$__script" "$__root/skills/$__skill/scripts/$__script"; do
    if [[ -f "$__c" && -x "$__c" ]]; then printf -v "$__var" '%s' "$__c"; return 0; fi
  done
  die "$__skill script not found: the aidex plugin install looks incomplete; reinstall it with 'claude plugin install aidex@aidex' or run /reload-plugins."
}

# Known audit types — canon SHORT names (decision/2026-07-02-audit-rebuild-canon-decisions)
AUDIT_TYPES=(ux ai-opportunities security perf a11y hitl retest test-coverage docs-coverage rule-ablation custom)

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
    test-coverage|coverage)        printf '%s\n' "test-coverage"; return 0 ;;
    docs-coverage|docs|documentation) printf '%s\n' "docs-coverage"; return 0 ;;
    rule-ablation|rules|always-on) printf '%s\n' "rule-ablation"; return 0 ;;
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
    test-coverage)    printf 'Test Coverage' ;;
    docs-coverage)    printf 'Docs Coverage' ;;
    rule-ablation)    printf 'Rule Ablation' ;;
    *)                printf '%s' "$1" ;;
  esac
}

# Locate which inventory holds a finding id under the CANON layout: searches each
# audits/<methodology>/00-inventory.md (skipping the folders validate-audit.sh
# skips: _archive, methodology, _deferred), then the legacy root boards. The two
# root boards count as ONE board: an id on both resolves to 00-inventory.md
# (validate-audit's preference), an id only in INVENTORY.md (half-migrated) still
# resolves there. Prints the inventory path (methodology derivable from its
# parent), or returns 1.
# Ids are methodology-scoped (02-id-conventions.md), so the default F-NNN collides
# across methodologies: a bare id held by more than one inventory is refused
# (stderr names each, return 2) instead of picking the first in glob order. A
# qualified id <methodology>/<id> searches only that methodology's inventory; its
# methodology part is a folder name, so empty, ".", ".." or a second "/" is
# refused (return 2), as is an empty id part.
# Usage: find_inventory_for_id <audits_dir> <finding_id|methodology/finding_id>
find_inventory_for_id() {
  local audits_dir="$1" finding_id="$2" inv m root_hit=0 candidates=() hits=()
  if [[ "$finding_id" == */* ]]; then
    m="${finding_id%%/*}"; finding_id="${finding_id#*/}"
    if [[ -z "$m" || "$m" == . || "$m" == .. || "$finding_id" == */* || -z "$finding_id" ]]; then
      err "error: '$2' is not <methodology>/<id>: the methodology must be a folder name under audits/"
      return 2
    fi
    candidates=("$audits_dir/$m/00-inventory.md")
  else
    for inv in "$audits_dir"/*/00-inventory.md; do
      case "$(basename "$(dirname "$inv")")" in _archive|methodology|_deferred) continue ;; esac
      candidates+=("$inv")
    done
    candidates+=("$audits_dir/00-inventory.md" "$audits_dir/INVENTORY.md")
  fi
  for inv in "${candidates[@]}"; do
    [[ -f "$inv" ]] || continue
    # INVENTORY.md is the same root board as 00-inventory.md: one hit, not two.
    [[ "$inv" == "$audits_dir/INVENTORY.md" && $root_hit -eq 1 ]] && continue
    if grep -qE "^\|[[:space:]]*$(ere_escape "$finding_id")[[:space:]]*\|" "$inv"; then
      hits+=("$inv")
      [[ "$inv" == "$audits_dir/00-inventory.md" ]] && root_hit=1
    fi
  done
  case ${#hits[@]} in
    0) return 1 ;;
    1) printf '%s\n' "${hits[0]}" ;;
    *) err "error: finding $finding_id is in more than one inventory; qualify it as <methodology>/$finding_id:"
       printf '  %s\n' "${hits[@]}" >&2
       return 2 ;;
  esac
}

# Escape a literal string for use inside a grep -E pattern.
ere_escape() { printf '%s' "$1" | sed 's/[][\\.*^$/+?(){}|]/\\&/g'; }

# Whole-token match of a finding id in a file, never a substring: F-1 must not
# match F-10 or F-1.2 (a trailing sentence period still counts as F-1).
# Usage: cites_id <file> <finding_id>
cites_id() {
  grep -qE "(^|[^A-Za-z0-9_-])$(ere_escape "$2")(\$|[^A-Za-z0-9_.-]|\.([^A-Za-z0-9_-]|\$))" "$1"
}

# Find which audit run folder recorded a finding. Prints the run folder basename;
# falls back to the most recent run folder, or "unknown-run".
# Usage: find_audit_run <audits_dir> <finding_id>
find_audit_run() {
  local audits_dir="$1" finding_id="$2" audit_run="" f
  if compgen -G "$audits_dir/[0-9]*-*/findings.md" > /dev/null; then
    while IFS= read -r f; do
      if cites_id "$f" "$finding_id"; then
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

# awk function: restore the US placeholders back to the markdown escape \|. Built
# by concatenation, never a gsub replacement: backslashes in a gsub replacement
# are read differently by BSD awk and gawk.
AWK_UNESC='function unesc(s,   out, i) {
  out = ""
  while ((i = index(s, "\037")) > 0) { out = out substr(s, 1, i - 1) "\\|"; s = substr(s, i + 1) }
  return out s
}
'

# Extract "<summary>\t<severity>" for a finding row from the inventory.
# Prints empty if not found. Skips HTML comment blocks so template example rows
# never pollute the match. Summary is cell 5, status cell 6, severity cell 7.
# Usage: extract_finding_row <inventory> <finding_id>
extract_finding_row() {
  local inventory="$1" finding_id="$2"
  awk -v id="$finding_id" "$AWK_UNESC"'
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
      # Parse as pipe-delimited row. A literal pipe inside a cell is escaped as
      # \| (validate-audit.sh convention): swap it for US before splitting and
      # restore it in the summary, or every later column shifts right by one.
      if (line !~ /^\|/) next
      gsub(/\\[|]/, "\037", line)
      n = split(line, cells, "|")
      if (n < 11) next
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[2])
      if (cells[2] == id) {
        cells[5] = unesc(cells[5])
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

# The lock file that serialises writes to <inventory> (prints its path). Two escalations
# on one inventory (separate sessions, or a backlog and a loop escalation) each
# read-modify-write the whole file: they take a kernel lock (lock_take) kept outside
# .context, keyed by the inventory's real path. The `.flock` name never meets the `.lock`
# DIRECTORY the old mkdir lock may have left. The lock sits in a per-user 0700
# directory, never the shared temp namespace (/tmp on Linux), where another user could
# plant a symlink at the lock's guessable name: such a directory returns 2. A caller that
# files something before marking the row asks this first, so a refusal leaves nothing.
# Usage: inventory_lock_path <inventory>
inventory_lock_path() {
  local inventory="$1" lock_dir="${TMPDIR:-/tmp}/aidex.locks.$EUID"
  mkdir -m 700 "$lock_dir" 2>/dev/null || :   # an existing path (or symlink) stays as it is
  [[ -d "$lock_dir" && ! -L "$lock_dir" && -O "$lock_dir" ]] \
    || { err "error: the lock directory $lock_dir is a symlink, not a directory or not yours; nothing written"; return 2; }
  printf '%s/aidex-inv.%s.flock\n' "$lock_dir" "$(printf '%s' "$(CDPATH= cd "$(dirname "$inventory")" && pwd -P)/$(basename "$inventory")" | path_digest | cut -c1-16)"
}

# Would mark_row_escalated rewrite the finding's row? Runs the same awk program with its
# output discarded: 0 yes; 4 no, the row it selects is already done (done, legacy
# escalated or closed: audit-conventions.md §Status map); 5 no, the row is dropped (a
# won't-fix verdict, never overwritten with done); 3 no, no row it could rewrite
# (a comment on the row, a status outside the known lowercase words, fewer than 9
# columns). Escalation asks it before filing anything.
# Usage: finding_row_markable <inventory> <finding_id>
finding_row_markable() {
  awk -v id="$2" -v link=x -v today=x "$AWK_MARK" "$1" > /dev/null
}

# Rewrite a finding's inventory row in place on escalation, per the CANON model
# (base vocab + ISO dates + <type>/<filename> markers): status -> done, Last
# Updated -> today (ISO), today appended to Audit Runs (deduped), "Escalated To"
# cell set to <ref> — a canon MARKER like backlog/<filename> or loop/<filename>,
# never a markdown link. Skips HTML comment blocks so template EXAMPLE rows are
# never rewritten. Writes nothing and returns 4 when the row is already done, 5 when it is
# dropped, 3 when no row was rewritten.
# Usage: mark_row_escalated <inventory> <finding_id> <ref>
mark_row_escalated() {
  local inventory="$1" finding_id="$2" link="$3" tmp="" lock rc=0
  lock="$(inventory_lock_path "$inventory")" || return 2
  # A subshell: the lock goes as it ends.
  (
  lock_take "$lock" 10 || { err "error: could not lock $inventory; nothing written"; exit 2; }
  # The temp file sits beside the inventory (atomic rename) and takes its mode
  # (cp -p): mktemp's 0600 must not replace the board's mode.
  if tmp="$(mktemp "$inventory.XXXXXX")" && cp -p "$inventory" "$tmp" && awk -v id="$finding_id" -v link="$link" -v today="$(today_iso)" "$AWK_MARK" "$inventory" > "$tmp" && mv "$tmp" "$inventory"; then
    :
  else
    rc=$?; rm -f "$tmp"
    [[ $rc -ne 3 ]] || err "error: no finding row $finding_id in $inventory could be marked escalated; nothing written"
    [[ $rc -ne 4 ]] || err "error: finding $finding_id in $inventory is already done (escalated); nothing written"
    [[ $rc -ne 5 ]] || err "error: finding $finding_id in $inventory was dropped (won't fix); reopen its row (status open) first if you want to escalate it; nothing written"
    exit $rc
  fi
  ) || rc=$?
  return $rc
}

# awk program for mark_row_escalated and finding_row_markable (-v id, link, today).
# Exit: 4 the selected row is done, 5 it is dropped, 3 no row to rewrite; the first two write nothing.
AWK_MARK="$AWK_UNESC"'
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

      # Parse as pipe-delimited, with each escaped \| held as US so a cell that
      # quotes a pipe stays one cell; restored on reassembly.
      if ($0 !~ /^\|/) { print $0; next }
      row = $0; gsub(/\\[|]/, "\037", row)
      n = split(row, cells, "|")
      # 9 columns -> n == 11 with the empty edges; the pre-2026-08-06 11-column
      # schema -> n == 13. Both are written; the offsets below shift by two.
      if (n < 11) { print $0; next }
      wide = (n >= 13)

      t = cells[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      if (t != id) { print $0; next }

      # Verify this is a real finding row (status column has a known marker,
      # base vocab or legacy read-tolerated)
      s = cells[6]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (s !~ /^(open|doing|done|dropped|triaged|escalated|in-progress|closed)$/) {
        print $0; next
      }
      if (s ~ /^(done|escalated|closed)$/) { closed = 1; print $0; next }
      if (s == "dropped") { dropped = 1; print $0; next }

      # Update fields (canon: done + escalated_to modifier, never a status word)
      c_runs = wide ? 10 : 8
      c_esc  = wide ? 11 : 9
      cells[6] = " done "
      # Last Updated only exists on the wide schema; on a 9-column board there is
      # nothing to stamp, and writing cell 9 there would overwrite Escalated To.
      if (wide) cells[9] = " " today " "
      runs = cells[c_runs]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", runs)
      if (index(runs, today) == 0) {
        if (runs == "" || runs == "—") runs = today
        else runs = runs ", " today
      }
      cells[c_runs] = " " runs " "
      cells[c_esc]  = " " link " "

      # Reassemble
      out = cells[1]
      for (i = 2; i <= n; i++) out = out "|" cells[i]
      print unesc(out)
      hit = 1
    }
    END { if (closed) exit 4; if (dropped) exit 5; if (!hit) exit 3 }
'
