#!/usr/bin/env bash
# validate-audit.sh — check coherence of .context/audits/ against the CANON model
# (D-02 per-methodology layout + standalone one-shot runs + base status vocabulary;
# rebuild 2026-07-02, decision/2026-07-02-audit-rebuild-canon-decisions).
#
# Usage: validate-audit.sh [--json] [path]
# Exit codes: 0 OK · 1 violations found · 2 usage error
#
# Model:
#   audits/<methodology>/          three boards + YYYY-MM-DD-<slug>/ runs
#   audits/YYYY-MM-DD-<slug>/      standalone one-shot run (no boards; main md
#                                  file with front-matter). Never a violation.
#   Legacy (root boards, YYYYMMDD names, legacy status vocab) -> WARNINGS with a
#   pointer to /aidex-audit migrate; reads never crash.

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
AUDITS_DIR="${AUDITS_DIR%/}"

# If user passed a run/methodology sub-folder, resolve up to the audits root.
while [[ "$(basename "$(dirname "$AUDITS_DIR")")" == "audits" ]]; do
  AUDITS_DIR="$(dirname "$AUDITS_DIR")"
done

VIOLATIONS=()
WARNINGS=()
runs=0
standalone_runs=0
methodologies=0
findings_in_inventory=0
f_open=0; f_doing=0; f_done=0; f_dropped=0; f_legacy=0
inventory_ids=""   # newline-separated "<id>" across all methodologies

# Whitespace trim without xargs (xargs dies on unbalanced quotes in cell text —
# same field bug class as the backlog --list apostrophe crash).
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

add_violation() { VIOLATIONS+=("$1"); }
add_warning()   { WARNINGS+=("$1"); }

id_seen() {
  local needle="$1"
  [[ -n "$inventory_ids" ]] && printf '%s\n' "$inventory_ids" | grep -qxF "$needle"
}

# Strip HTML comment blocks from a file (multi-line safe).
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
          if (end == 0) { line = before; in_comment = 1; break }
          line = before substr(after, end + 3)
        }
      }
      print line
    }
  ' "$1"
}

# Base canon vocabulary; legacy words map (audit-conventions.md §Status map).
base_status() {
  case "$1" in
    open) printf 'open' ;;
    doing) printf 'doing' ;;
    done) printf 'done' ;;
    dropped) printf 'dropped' ;;
    triaged) printf 'open' ;;        # legacy
    escalated|closed) printf 'done' ;;  # legacy
    in-progress) printf 'doing' ;;   # legacy
    *) printf '' ;;
  esac
}
is_legacy_status() {
  case "$1" in triaged|escalated|in-progress|closed) return 0 ;; *) return 1 ;; esac
}
looks_like_status() {
  [[ -n "$(base_status "$1")" ]]
}

# Parse one inventory file; appends findings/violations/warnings. $1=path $2=scope label.
validate_inventory() {
  local inv="$1" scope="$2"
  local legacy_here=0 parsed_here=0 pipe_rows=0
  local line pipe_count c_id c_type c_module c_summary c_status c_severity c_first c_last c_runs c_escalated rest notes
  local id status escalated mapped
  while IFS= read -r line; do
    [[ "$line" =~ ^\|[[:space:]]*ID[[:space:]]*\| ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*-+ ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*— ]] && continue
    pipe_count="$(printf '%s' "$line" | tr -cd '|' | wc -c | tr -d ' ')"
    [[ "$pipe_count" -ge 5 ]] || continue
    IFS='|' read -r _ c_id c_type c_module c_summary c_status c_severity c_first c_last c_runs c_escalated rest <<< "$line"
    id="$(trim "${c_id:-}")"
    status="$(trim "${c_status:-}")"
    escalated="$(trim "${c_escalated:-}")"
    notes="$(trim "${rest%%|*}")"
    [[ -z "$id" || "$id" == "—" ]] && continue
    [[ "$id" =~ [A-Za-z] ]] || continue
    [[ "$id" =~ ^[A-Z]+[-A-Z0-9]*-[0-9]+$ ]] && pipe_rows=$((pipe_rows+1))
    looks_like_status "$status" || continue
    [[ "$pipe_count" -ge 10 ]] || continue

    if id_seen "$id"; then
      add_violation "duplicate ID in $scope inventory: $id"
    fi
    inventory_ids="$inventory_ids"$'\n'"$id"
    findings_in_inventory=$((findings_in_inventory+1))
    parsed_here=$((parsed_here+1))

    if is_legacy_status "$status"; then
      legacy_here=$((legacy_here+1))
      f_legacy=$((f_legacy+1))
    fi
    mapped="$(base_status "$status")"
    case "$mapped" in
      open)    f_open=$((f_open+1)) ;;
      doing)   f_doing=$((f_doing+1)) ;;
      done)    f_done=$((f_done+1)) ;;
      dropped) f_dropped=$((f_dropped+1)) ;;
    esac

    # Lifecycle enforcement (canon 03-lifecycle):
    #   done  -> Escalated To marker OR verifying evidence in Notes
    #   doing -> Escalated To (the plan doing the work)
    #   dropped -> reason in Notes
    local has_esc=1 has_notes=1
    [[ -z "$escalated" || "$escalated" == "—" ]] && has_esc=0
    [[ -z "$notes" || "$notes" == "—" ]] && has_notes=0
    case "$mapped" in
      done)
        if [[ $has_esc -eq 0 && $has_notes -eq 0 ]]; then
          add_violation "finding $id ($scope) is done but has neither an Escalated To marker nor verifying evidence in Notes"
        fi ;;
      doing)
        if [[ $has_esc -eq 0 ]]; then
          add_violation "finding $id ($scope) is doing but has no Escalated To reference"
        fi ;;
      dropped)
        if [[ $has_notes -eq 0 ]]; then
          add_violation "finding $id ($scope) is dropped with no reason in Notes"
        fi ;;
    esac
  done < <(strip_html_comments "$inv")

  if [[ $legacy_here -gt 0 ]]; then
    add_warning "$scope inventory carries $legacy_here legacy status value(s) (triaged/escalated/in-progress/closed) — counted under the mapped base status; run /aidex-audit migrate to convert"
  fi
  if [[ $pipe_rows -gt 0 && $parsed_here -eq 0 ]]; then
    add_warning "$scope inventory uses a legacy schema ($pipe_rows pipe-rows, 0 parse as canonical). Expected: | ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |. Run /aidex-audit migrate."
  fi
}

# Validate the run folders inside one methodology dir. $1=dir $2=scope.
validate_methodology_runs() {
  local mdir="$1" scope="$2" dir base
  for dir in "$mdir"/[0-9]*-*/; do
    [[ -d "$dir" ]] || continue
    base="$(basename "$dir")"
    runs=$((runs+1))
    if [[ "$base" =~ ^[0-9]{8}- ]]; then
      add_warning "$scope run '$base' uses legacy YYYYMMDD naming — run /aidex-audit migrate"
    fi
    [[ -f "$dir/index.md" ]]    || add_violation "missing index.md in $scope/$base"
    [[ -f "$dir/findings.md" ]] || add_violation "missing findings.md in $scope/$base"
  done
}

# ---------- Discover units ----------

# Legacy root boards → validate as a pseudo-methodology, warn to migrate.
ROOT_INV=""
if [[ -f "$AUDITS_DIR/00-inventory.md" ]]; then ROOT_INV="$AUDITS_DIR/00-inventory.md"
elif [[ -f "$AUDITS_DIR/INVENTORY.md" ]]; then ROOT_INV="$AUDITS_DIR/INVENTORY.md"; fi
if [[ -f "$AUDITS_DIR/00-inventory.md" && -f "$AUDITS_DIR/INVENTORY.md" ]]; then
  add_warning "both 00-inventory.md and INVENTORY.md exist at the audits root; preferring 00-inventory.md — remove the legacy file after confirming content is migrated"
fi
if [[ -n "$ROOT_INV" ]]; then
  add_warning "boards at the audits/ ROOT are the pre-D-02 legacy layout — run /aidex-audit migrate to group by methodology"
  validate_inventory "$ROOT_INV" "(root-legacy)"
fi

for entry in "$AUDITS_DIR"/*/; do
  [[ -d "$entry" ]] || continue
  name="$(basename "$entry")"
  case "$name" in
    _archive|methodology|_deferred|.*) continue ;;
  esac
  if [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- || "$name" =~ ^[0-9]{8}- ]]; then
    # Dated folder at the root: legacy-layout run (if root boards exist) or standalone one-shot.
    if [[ -n "$ROOT_INV" ]]; then
      runs=$((runs+1))
      [[ -f "$entry/index.md" ]] || add_violation "missing index.md in legacy run $name"
    else
      standalone_runs=$((standalone_runs+1))
      [[ "$name" =~ ^[0-9]{8}- ]] && add_warning "standalone run '$name' uses legacy YYYYMMDD naming — rename to YYYY-MM-DD-<slug>"
      # A standalone run needs a main md file carrying front-matter.
      main=""
      for cand in "$entry/index.md" "$entry/00-report.md"; do
        [[ -f "$cand" ]] && { main="$cand"; break; }
      done
      [[ -z "$main" ]] && main="$(ls "$entry"/*.md 2>/dev/null | head -1 || true)"
      if [[ -z "$main" ]]; then
        add_violation "standalone run $name has no main .md file (expected index.md or 00-report.md)"
      elif ! head -1 "$main" | grep -q '^---'; then
        add_warning "standalone run $name: $(basename "$main") lacks front-matter (title/status/created/updated)"
      fi
    fi
    continue
  fi
  # Anything else is a methodology folder: boards inside + dated runs.
  methodologies=$((methodologies+1))
  for board in 00-inventory.md 00-methodology.md 00-changelog.md; do
    [[ -f "$entry/$board" ]] || add_violation "methodology '$name' missing $board"
  done
  [[ -f "$entry/00-inventory.md" ]] && validate_inventory "$entry/00-inventory.md" "$name"
  validate_methodology_runs "${entry%/}" "$name"

  # Orphan references: IDs in this methodology's run findings must exist somewhere.
  while IFS= read -r findings_file; do
    while IFS= read -r mentioned_id; do
      [[ -z "$mentioned_id" ]] && continue
      if ! id_seen "$mentioned_id"; then
        rel="${findings_file#"$AUDITS_DIR"/}"
        add_violation "$rel references $mentioned_id which is not in any inventory"
      fi
    done < <(strip_html_comments "$findings_file" | grep -oE '\b[A-Z]+(-[A-Z0-9]+)?-[0-9]+\b' 2>/dev/null | sort -u)
  done < <(find "${entry%/}" -type f -name findings.md -path '*/[0-9]*-*/findings.md' 2>/dev/null)
done

# ---------- Backlog back-references ----------
BACKLOG_DIR="$(dirname "$AUDITS_DIR")/backlog"
if [[ -d "$BACKLOG_DIR" ]]; then
  while IFS= read -r bl_entry; do
    origin_ref_line="$(grep -E '^origin_ref:[[:space:]]*"?audit/' "$bl_entry" 2>/dev/null | head -1 || true)"
    [[ -z "$origin_ref_line" ]] && continue
    ref="$(printf '%s' "$origin_ref_line" | sed -E 's/^origin_ref:[[:space:]]*"?//; s/"?[[:space:]]*$//')"
    # audit/<methodology>/<run>/<id> = 4 segments -> checkable.
    # audit/<run>/<id> (standalone, 3 segments) -> no inventory to check; skip.
    # audit/<id> (2, legacy) -> check against aggregate ids.
    seg_count="$(printf '%s' "$ref" | awk -F'/' '{print NF}')"
    ref_id="${ref##*/}"
    ref_id="$(trim "$ref_id")"
    if [[ "$seg_count" -ge 4 || "$seg_count" -eq 2 ]]; then
      if ! id_seen "$ref_id"; then
        rel="${bl_entry#"$(dirname "$AUDITS_DIR")"/}"
        add_violation "backlog entry $rel cites audit finding $ref_id which is not in any inventory"
      fi
    fi
  done < <(find "$BACKLOG_DIR" -maxdepth 2 -type f -name '*.md')
fi

# ---------- Roll-up index freshness (non-fatal warning) ----------
REINDEX_AUDITS="$SKILL_DIR/scripts/reindex-audits.sh"
if [[ -x "$REINDEX_AUDITS" ]]; then
  drift_msg="$(NO_COLOR=1 bash "$REINDEX_AUDITS" --check 2>&1)" || \
    add_warning "${drift_msg:-00-index.md stale — run /aidex-audit reindex}"
fi

# ---------- Report ----------
if [[ $JSON_OUT -eq 1 ]]; then
  printf '{\n'
  printf '  "audits_dir": "%s",\n' "$AUDITS_DIR"
  printf '  "methodologies": %d,\n' "$methodologies"
  printf '  "runs": %d,\n' "$runs"
  printf '  "standalone_runs": %d,\n' "$standalone_runs"
  printf '  "findings_in_inventory": %d,\n' "$findings_in_inventory"
  printf '  "stats": {"open":%d,"doing":%d,"done":%d,"dropped":%d,"legacy_status_values":%d},\n' \
    "$f_open" "$f_doing" "$f_done" "$f_dropped" "$f_legacy"
  printf '  "violations": ['
  for i in "${!VIOLATIONS[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    v="${VIOLATIONS[$i]//\\/\\\\}"; v="${v//\"/\\\"}"
    printf '\n    "%s"' "$v"
  done
  printf '\n  ],\n'
  printf '  "warnings": ['
  for i in "${!WARNINGS[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    w="${WARNINGS[$i]//\\/\\\\}"; w="${w//\"/\\\"}"
    printf '\n    "%s"' "$w"
  done
  printf '\n  ]\n'
  printf '}\n'
else
  printf '\n%sAudit validation — %s%s\n' "$C_BOLD" "$AUDITS_DIR" "$C_RESET"
  printf '%s  methodologies: %d · runs: %d (+%d standalone) · findings: %d (open:%d doing:%d done:%d dropped:%d · legacy values:%d)%s\n\n' \
    "$C_DIM" "$methodologies" "$runs" "$standalone_runs" "$findings_in_inventory" \
    "$f_open" "$f_doing" "$f_done" "$f_dropped" "$f_legacy" "$C_RESET"
  if [[ ${#VIOLATIONS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    ok "OK — no violations"
  else
    if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
      err "Violations (${#VIOLATIONS[@]}):"
      for v in "${VIOLATIONS[@]}"; do printf '  %s[x]%s %s\n' "$C_RED" "$C_RESET" "$v"; done
    fi
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
      warn "Warnings (${#WARNINGS[@]}):"
      for w in "${WARNINGS[@]}"; do printf '  %s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$w"; done
    fi
  fi
fi

[[ ${#VIOLATIONS[@]} -eq 0 ]] || exit 1
exit 0
