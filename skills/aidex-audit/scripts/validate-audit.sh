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
#
# Waivers: accepted findings recorded in <context>/.aidex-waivers are suppressed
# from counts and the exit code but always reported under a `waived: N` summary —
# same file, line format and anchor semantics as validate.py (00-global.md §10.1).
# Every finding therefore carries a rule id and a project-root-relative path, which
# is what a waiver line keys on.

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

CONTEXT_DIR="$(dirname "$AUDITS_DIR")"
PROJECT_ROOT="$(dirname "$CONTEXT_DIR")"

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
# Restore the `\|` escapes that validate_inventory() swaps out before splitting a
# row on the raw pipe. Reports quote cell contents verbatim, so this runs on
# every cell that is read, not only on the one that carried the escape.
unescape_pipes() { printf '%s' "${1//$'\x1f'/\\|}"; }

# A finding is <rule> US <path> US <message>. US (0x1f) and not "|", because
# messages legitimately contain pipes — the legacy-schema warning prints a whole
# markdown table row.
US=$'\037'

# Project-root-relative, exactly the shape validate.py prints and a waiver keys on
# (e.g. .context/audits/ux/00-inventory.md).
# Directory globs leave a trailing slash, so "$entry/$board" arrives as
# ".../ux//00-changelog.md" — squeeze it, or the waiver path never matches.
# tr, not ${p//\/\//\/}: bash 3.2 takes a quoted replacement literally and a
# bare one leaves a stray backslash, both of which silently break the match.
relpath() {
  local p
  p="$(printf '%s' "${1%/}" | tr -s '/')"
  printf '%s' "${p#"$PROJECT_ROOT"/}"
}

# add_violation <rule> <path> <message>   (path is absolute; relativized here)
add_violation() { VIOLATIONS+=("$1$US$(relpath "$2")$US$3"); }
add_warning()   { WARNINGS+=("$1$US$(relpath "$2")$US$3"); }

field()   { printf '%s' "${1%%$US*}"; }                       # rule
f_path()  { local r="${1#*$US}"; printf '%s' "${r%%$US*}"; }  # path
f_msg()   { printf '%s' "${1##*$US}"; }                       # message

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
  local legacy_here=0 parsed_here=0 pipe_rows=0 oversize_notes=0 unparsed_ids=""
  local line row pipe_count c_id c_type c_module c_summary c_status c_severity c_first c_last c_runs c_escalated rest notes nb
  local id status escalated mapped

  # Soft budget: board file > 30 KB (warn only, never a violation).
  local board_bytes
  board_bytes="$(wc -c < "$inv" | tr -d ' ')"
  if [[ "$board_bytes" -gt 30720 ]]; then
    add_warning audit-board-oversize "$inv" "$scope inventory board is $((board_bytes / 1024)) KB (> 30 KB) — archive resolved rows or move narrative to run findings.md/proofs to keep the board at open-set size"
  fi

  while IFS= read -r line; do
    [[ "$line" =~ ^\|[[:space:]]*ID[[:space:]]*\| ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*-+ ]] && continue
    [[ "$line" =~ ^\|[[:space:]]*— ]] && continue
    # Markdown escapes a literal pipe inside a cell as `\|`, and a Summary that
    # quotes one is ordinary (an alternation in a grep pattern, a shell pipeline).
    # Splitting on the raw character shifted every column right by one, so
    # looks_like_status read the wrong field and the row was skipped in silence —
    # after which the run's own findings.md reference to that id was reported as
    # an orphan. Swap the escapes out before counting and splitting, then restore
    # them per cell (US, \x1f, cannot occur in a markdown table row).
    row="${line//\\|/$'\x1f'}"
    pipe_count="$(printf '%s' "$row" | tr -cd '|' | wc -c | tr -d ' ')"
    [[ "$pipe_count" -ge 5 ]] || continue
    # Two widths are canonical-enough to parse. 9 columns is current; 11 is the
    # pre-2026-08-06 schema that also carried First Seen / Last Updated, dropped
    # because nothing read them (BL-057). Legacy boards are TOLERATED, not
    # migrated: a project's board is its own, and a validator that only parsed
    # the new width would report every unmigrated project as unparseable.
    # 9 cols -> 10 pipes, 11 cols -> 12 pipes.
    if [[ "$pipe_count" -ge 12 ]]; then
      IFS='|' read -r _ c_id c_type c_module c_summary c_status c_severity _c_first _c_last c_runs c_escalated rest <<< "$row"
    else
      IFS='|' read -r _ c_id c_type c_module c_summary c_status c_severity c_runs c_escalated rest <<< "$row"
    fi
    id="$(trim "$(unescape_pipes "${c_id:-}")")"
    status="$(trim "$(unescape_pipes "${c_status:-}")")"
    escalated="$(trim "$(unescape_pipes "${c_escalated:-}")")"
    notes="$(trim "$(unescape_pipes "${rest%%|*}")")"
    [[ -z "$id" || "$id" == "—" ]] && continue
    [[ "$id" =~ [A-Za-z] ]] || continue
    if [[ "$id" =~ ^[A-Z]+[-A-Z0-9]*-[0-9]+$ ]]; then
      pipe_rows=$((pipe_rows+1))
      # An id-shaped row that does not parse is the case that used to vanish. It
      # is still not parsed — the row is malformed markdown and guessing which
      # cell moved would be worse — but it is now NAMED, so the board's own
      # orphan check cannot accuse a reference to a row it dropped.
      if ! looks_like_status "$status"; then
        unparsed_ids="$unparsed_ids $id"
      fi
    fi
    looks_like_status "$status" || continue
    # A canonical row has every column present: 9 cols = 10 pipes, 11 cols = 12.
    [[ "$pipe_count" -ge 10 ]] || continue

    if id_seen "$id"; then
      add_violation audit-duplicate-id "$inv" "duplicate ID in $scope inventory: $id"
    fi
    inventory_ids="$inventory_ids"$'\n'"$id"
    findings_in_inventory=$((findings_in_inventory+1))
    parsed_here=$((parsed_here+1))

    # Soft budget: Notes cell > 300 B (warn only) — canon keeps Notes a one-line
    # state note; narrative belongs in the run findings.md/proofs.
    nb="$(printf '%s' "$notes" | wc -c | tr -d ' ')"
    [[ "$nb" -gt 300 ]] && oversize_notes=$((oversize_notes+1))

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
          add_violation audit-lifecycle-done-unevidenced "$inv" "finding $id ($scope) is done but has neither an Escalated To marker nor verifying evidence in Notes"
        fi ;;
      doing)
        if [[ $has_esc -eq 0 ]]; then
          add_violation audit-lifecycle-doing-unlinked "$inv" "finding $id ($scope) is doing but has no Escalated To reference"
        fi ;;
      dropped)
        if [[ $has_notes -eq 0 ]]; then
          add_violation audit-lifecycle-dropped-unreasoned "$inv" "finding $id ($scope) is dropped with no reason in Notes"
        fi ;;
    esac
  done < <(strip_html_comments "$inv")

  if [[ $legacy_here -gt 0 ]]; then
    add_warning audit-legacy-status "$inv" "$scope inventory carries $legacy_here legacy status value(s) (triaged/escalated/in-progress/closed) — counted under the mapped base status; run /aidex-audit migrate to convert"
  fi
  if [[ $oversize_notes -gt 0 ]]; then
    add_warning audit-notes-oversize "$inv" "$scope inventory has $oversize_notes Notes cell(s) over 300 B — move the resolution narrative to the run findings.md or .context/proofs/ (canon: Notes is a one-line state note)"
  fi
  if [[ -n "$unparsed_ids" ]]; then
    add_warning audit-inventory-row-unparseable "$inv" "$scope inventory has row(s) whose columns do not line up and were not read:${unparsed_ids} — a literal pipe inside a cell must be escaped as \\| , otherwise it shifts every column right and the row is dropped (and its id then reads as an orphan reference)"
  fi
  if [[ $pipe_rows -gt 0 && $parsed_here -eq 0 ]]; then
    add_warning audit-legacy-schema "$inv" "$scope inventory uses a legacy schema ($pipe_rows pipe-rows, 0 parse as canonical). Expected: | ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes | (the 11-column form with First Seen / Last Updated is also accepted). Run /aidex-audit migrate."
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
      add_warning audit-legacy-run-name "$dir" "$scope run '$base' uses legacy YYYYMMDD naming — run /aidex-audit migrate"
    fi
    [[ -f "$dir/index.md" ]]    || add_violation audit-run-missing-index "$dir/index.md" "missing index.md in $scope/$base"
    [[ -f "$dir/findings.md" ]] || add_violation audit-run-missing-findings "$dir/findings.md" "missing findings.md in $scope/$base"
  done
}

# ---------- Discover units ----------

# Legacy root boards → validate as a pseudo-methodology, warn to migrate.
ROOT_INV=""
if [[ -f "$AUDITS_DIR/00-inventory.md" ]]; then ROOT_INV="$AUDITS_DIR/00-inventory.md"
elif [[ -f "$AUDITS_DIR/INVENTORY.md" ]]; then ROOT_INV="$AUDITS_DIR/INVENTORY.md"; fi
if [[ -f "$AUDITS_DIR/00-inventory.md" && -f "$AUDITS_DIR/INVENTORY.md" ]]; then
  add_warning audit-duplicate-root-inventory "$AUDITS_DIR/INVENTORY.md" "both 00-inventory.md and INVENTORY.md exist at the audits root; preferring 00-inventory.md — remove the legacy file after confirming content is migrated"
fi
if [[ -n "$ROOT_INV" ]]; then
  add_warning audit-legacy-root-boards "$ROOT_INV" "boards at the audits/ ROOT are the pre-D-02 legacy layout — run /aidex-audit migrate to group by methodology"
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
      [[ -f "$entry/index.md" ]] || add_violation audit-run-missing-index "$entry/index.md" "missing index.md in legacy run $name"
    else
      standalone_runs=$((standalone_runs+1))
      [[ "$name" =~ ^[0-9]{8}- ]] && add_warning audit-standalone-legacy-name "$entry" "standalone run '$name' uses legacy YYYYMMDD naming — rename to YYYY-MM-DD-<slug>"
      # A standalone run needs a main md file carrying front-matter.
      main=""
      for cand in "$entry/index.md" "$entry/00-report.md"; do
        [[ -f "$cand" ]] && { main="$cand"; break; }
      done
      [[ -z "$main" ]] && main="$(ls "$entry"/*.md 2>/dev/null | head -1 || true)"
      if [[ -z "$main" ]]; then
        add_violation audit-standalone-no-main "$entry" "standalone run $name has no main .md file (expected index.md or 00-report.md)"
      elif ! head -1 "$main" | grep -q '^---'; then
        add_warning audit-standalone-no-frontmatter "$main" "standalone run $name: $(basename "$main") lacks front-matter (title/status/created/updated)"
      fi
    fi
    continue
  fi
  # Anything else MAY be a methodology folder. Not every folder is one:
  # `test-coverage/` is a data directory this same script special-cases below
  # (module-map.json, coverage-matrix.md, defect-prone.jsonl), and its path is
  # hard-coded in coverage/defect_prone.py, references 06 and 07, and
  # test-defect-prone.sh — so demanding three methodology boards there produced
  # three violations with no correct way to close them. Require the boards only
  # where the folder BEHAVES like a methodology: it holds at least one dated run
  # folder, or at least one board already. A folder with neither is data.
  behaves_like_methodology=0
  for board in 00-inventory.md 00-methodology.md 00-changelog.md; do
    [[ -f "$entry/$board" ]] && { behaves_like_methodology=1; break; }
  done
  if [[ "$behaves_like_methodology" -eq 0 ]]; then
    if find "${entry%/}" -mindepth 1 -maxdepth 1 -type d \
         \( -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*' -o -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*' \) \
         2>/dev/null | grep -q .; then
      behaves_like_methodology=1
    fi
  fi
  [[ "$behaves_like_methodology" -eq 0 ]] && continue

  methodologies=$((methodologies+1))
  for board in 00-inventory.md 00-methodology.md 00-changelog.md; do
    [[ -f "$entry/$board" ]] || add_violation audit-methodology-missing-board "$entry/$board" "methodology '$name' missing $board"
  done
  [[ -f "$entry/00-inventory.md" ]] && validate_inventory "$entry/00-inventory.md" "$name"
  validate_methodology_runs "${entry%/}" "$name"

  # Orphan references: IDs in this methodology's run findings must exist somewhere.
  while IFS= read -r findings_file; do
    while IFS= read -r mentioned_id; do
      [[ -z "$mentioned_id" ]] && continue
      if ! id_seen "$mentioned_id"; then
        rel="${findings_file#"$AUDITS_DIR"/}"
        add_violation audit-orphan-finding-ref "$findings_file" "$rel references $mentioned_id which is not in any inventory"
      fi
    # `BL-<n>` (backlog), `D-<n>` (ADR) and `CWE-<n>` (the weakness catalogue) are ids of
    # SIBLING VOCABULARIES. A findings narrative cites them constantly ("unmeasured
    # (BL-166)", "stays English (D-04)", "maps to CWE-1236"), and none can ever appear in
    # an audit inventory — so reporting them is noise with no correct fix, and the
    # pressure it creates is to waive the rule, silencing the real orphans.
    #
    # The segment group is `*`, not `?`. With `?` the pattern took at most one segment
    # before the number, so a three-segment id never matched from its own start: grep
    # re-anchored after the first dash and reported `FE-CATALOG-01` for
    # `SEC-FE-CATALOG-01` — an id in no inventory because it does not exist. One real
    # security run produced ~39 such violations, all frontend, all false.
    done < <(strip_html_comments "$findings_file" | grep -oE '\b[A-Z]+(-[A-Z0-9]+)*-[0-9]+\b' 2>/dev/null \
             | grep -vE '^(BL|D|CWE)-[0-9]+$' | sort -u)
  done < <(find "${entry%/}" -type f -name findings.md -path '*/[0-9]*-*/findings.md' 2>/dev/null)
done

# ---------- Backlog back-references ----------
BACKLOG_DIR="$(dirname "$AUDITS_DIR")/backlog"
if [[ -d "$BACKLOG_DIR" ]]; then
  while IFS= read -r bl_entry; do
    origin_ref_line="$(grep -E '^origin_ref:[[:space:]]*"?audit/' "$bl_entry" 2>/dev/null | head -1 || true)"
    [[ -z "$origin_ref_line" ]] && continue
    ref="$(printf '%s' "$origin_ref_line" | sed -E 's/^origin_ref:[[:space:]]*"?//; s/"?[[:space:]]*$//')"
    # D-10 archives a finished run into _archive/, which adds a segment and would
    # push a standalone run into the 4-segment (methodology) branch — reading
    # `_archive` as a methodology name and orphaning every reference. Archiving is
    # what D-10 mandates, so drop the marker and count the shape the run had before
    # it moved. Same defect f405d8d fixed in validate.py.
    ref="${ref/#audit\/_archive\//audit/}"
    # audit/<methodology>/<run>/<id> = 4 segments -> checkable.
    # audit/<run>/<id> (standalone, 3 segments) -> no inventory to check; skip.
    # audit/<id> (2, legacy) -> check against aggregate ids.
    seg_count="$(printf '%s' "$ref" | awk -F'/' '{print NF}')"
    ref_id="${ref##*/}"
    ref_id="$(trim "$ref_id")"
    if [[ "$seg_count" -ge 4 || "$seg_count" -eq 2 ]]; then
      if ! id_seen "$ref_id"; then
        rel="${bl_entry#"$(dirname "$AUDITS_DIR")"/}"
        add_violation audit-backlog-orphan-ref "$bl_entry" "backlog entry $rel cites audit finding $ref_id which is not in any inventory"
      fi
    fi
  done < <(find "$BACKLOG_DIR" -maxdepth 2 -type f -name '*.md')
fi

# ---------- test-coverage additive checks (warnings only, first release) ----------
# Scoped to projects that have a test-coverage methodology folder. Two checks:
#   1. module-map.json parses (delegate to the coverage lib's `load` CLI).
#   2. coverage-matrix.md, if present, carries the GENERATED header — a hand-created
#      matrix without it is flagged (the never-hand-edit rule, enforced).
COV_DIR="$AUDITS_DIR/test-coverage"
if [[ -d "$COV_DIR" ]]; then
  COV_LIB="$SKILL_DIR/scripts/coverage/_coverage_lib.py"
  WS_ROOT="$(dirname "$(dirname "$AUDITS_DIR")")"
  if [[ -f "$COV_DIR/module-map.json" && -f "$COV_LIB" ]]; then
    if ! python3 "$COV_LIB" load "$WS_ROOT" >/dev/null 2>&1; then
      add_warning audit-coverage-map-unparseable "$COV_DIR/module-map.json" "test-coverage/module-map.json does not parse via the coverage lib — run: python3 <skill>/scripts/coverage/_coverage_lib.py load <workspace-root>"
    fi
  fi
  if [[ -f "$COV_DIR/coverage-matrix.md" ]] && ! grep -q 'GENERATED' "$COV_DIR/coverage-matrix.md"; then
    add_warning audit-coverage-matrix-ungenerated "$COV_DIR/coverage-matrix.md" "test-coverage/coverage-matrix.md lacks the GENERATED header — it looks hand-created; regenerate via /aidex-audit coverage-matrix (never hand-edit generated artifacts)"
  fi
fi

# ---------- Roll-up index freshness (non-fatal warning) ----------
REINDEX_AUDITS="$SKILL_DIR/scripts/reindex-audits.sh"
if [[ -x "$REINDEX_AUDITS" ]]; then
  drift_msg="$(NO_COLOR=1 bash "$REINDEX_AUDITS" --check 2>&1)" || \
    add_warning audit-index-stale "$AUDITS_DIR/00-index.md" "${drift_msg:-00-index.md stale — run /aidex-audit reindex}"
fi

# ---------- Waivers ----------
# Same store, line format and anchor semantics as validate.py (00-global.md §10.1):
#   <rule> | <path> | <anchor> | <reason> [| <date>]
# A waiver keys on (rule, path) and suppresses matching findings only while its
# anchor still matches, so any edit to the anchored file resurfaces the finding.
WAIVERS_FILE="$CONTEXT_DIR/.aidex-waivers"
waiver_parse_errors=0
matched_waivers=""   # newline-separated "<rule>US<path>"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}

# No anchor ("-" or empty) always matches. An anchored waiver matches only while
# the file's sha256 still starts with the recorded prefix (missing file: no match).
anchor_matches() {
  local anchor="$1" path="$2" hex target
  [[ -z "$anchor" || "$anchor" == "-" ]] && return 0
  [[ "$anchor" =~ ^sha256:([0-9a-f]{8,64})$ ]] || return 1
  hex="${BASH_REMATCH[1]}"
  target="$PROJECT_ROOT/$path"
  [[ -f "$target" ]] || return 1
  [[ "$(sha256_of "$target")" == "$hex"* ]]
}

if [[ -f "$WAIVERS_FILE" ]]; then
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="$(trim "$raw")"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    # Bad lines are counted, never silently swallowed.
    if [[ "$(printf '%s' "$line" | tr -cd '|' | wc -c | tr -d ' ')" -lt 3 ]]; then
      waiver_parse_errors=$((waiver_parse_errors+1)); continue
    fi
    IFS='|' read -r w_rule w_path w_anchor _w_rest <<< "$line"
    w_rule="$(trim "$w_rule")"; w_path="$(trim "$w_path")"; w_anchor="$(trim "$w_anchor")"
    if [[ -z "$w_rule" || -z "$w_path" ]]; then
      waiver_parse_errors=$((waiver_parse_errors+1)); continue
    fi
    anchor_matches "$w_anchor" "$w_path" && matched_waivers="$matched_waivers"$'\n'"$w_rule$US$w_path"
  done < "$WAIVERS_FILE"
fi

is_waived() {
  [[ -n "$matched_waivers" ]] || return 1
  printf '%s\n' "$matched_waivers" | grep -qxF "$1$US$2"
}

# Partition. Waived findings leave the counts and the exit code but are always
# reported — never silently dropped.
ACTIVE_V=(); ACTIVE_W=(); WAIVED=()
for f in ${VIOLATIONS[@]+"${VIOLATIONS[@]}"}; do
  if is_waived "$(field "$f")" "$(f_path "$f")"; then WAIVED+=("$f"); else ACTIVE_V+=("$f"); fi
done
for f in ${WARNINGS[@]+"${WARNINGS[@]}"}; do
  if is_waived "$(field "$f")" "$(f_path "$f")"; then WAIVED+=("$f"); else ACTIVE_W+=("$f"); fi
done
VIOLATIONS=(${ACTIVE_V[@]+"${ACTIVE_V[@]}"})
WARNINGS=(${ACTIVE_W[@]+"${ACTIVE_W[@]}"})

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
  printf '  "waived": %d,\n' "${#WAIVED[@]}"
  printf '  "waiver_parse_errors": %d,\n' "$waiver_parse_errors"
  printf '  "violations": ['
  for i in ${VIOLATIONS[@]+"${!VIOLATIONS[@]}"}; do
    [[ $i -gt 0 ]] && printf ','
    v="$(f_msg "${VIOLATIONS[$i]}")"; v="${v//\\/\\\\}"; v="${v//\"/\\\"}"
    printf '\n    {"rule": "%s", "path": "%s", "message": "%s"}' \
      "$(field "${VIOLATIONS[$i]}")" "$(f_path "${VIOLATIONS[$i]}")" "$v"
  done
  printf '\n  ],\n'
  printf '  "warnings": ['
  for i in ${WARNINGS[@]+"${!WARNINGS[@]}"}; do
    [[ $i -gt 0 ]] && printf ','
    w="$(f_msg "${WARNINGS[$i]}")"; w="${w//\\/\\\\}"; w="${w//\"/\\\"}"
    printf '\n    {"rule": "%s", "path": "%s", "message": "%s"}' \
      "$(field "${WARNINGS[$i]}")" "$(f_path "${WARNINGS[$i]}")" "$w"
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
      for v in "${VIOLATIONS[@]}"; do
        printf '  %s[x]%s %s %s(%s)%s\n' "$C_RED" "$C_RESET" "$(f_msg "$v")" "$C_DIM" "$(field "$v")" "$C_RESET"
      done
    fi
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
      warn "Warnings (${#WARNINGS[@]}):"
      for w in "${WARNINGS[@]}"; do
        printf '  %s[!]%s %s %s(%s)%s\n' "$C_YELLOW" "$C_RESET" "$(f_msg "$w")" "$C_DIM" "$(field "$w")" "$C_RESET"
      done
    fi
  fi
  if [[ ${#WAIVED[@]} -gt 0 ]]; then
    printf '\n%swaived: %d%s (accepted in .context/%s)\n' \
      "$C_DIM" "${#WAIVED[@]}" "$C_RESET" ".aidex-waivers"
    for f in "${WAIVED[@]}"; do
      printf '  %s[~] %s — %s%s\n' "$C_DIM" "$(field "$f")" "$(f_path "$f")" "$C_RESET"
    done
  fi
  if [[ $waiver_parse_errors -gt 0 ]]; then
    printf '\n%swaiver file: %d unparseable line(s) ignored%s\n' "$C_DIM" "$waiver_parse_errors" "$C_RESET"
  fi
fi

[[ ${#VIOLATIONS[@]} -eq 0 ]] || exit 1
exit 0
