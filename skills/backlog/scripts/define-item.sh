#!/usr/bin/env bash
# define-item.sh — write a triage VERDICT into a backlog item's front-matter.
#
# Kickoff triage confirms or corrects what registration only hypothesised, and the
# verdict lives in the ITEM — the work-list is gitignored and per-run, so a verdict
# that lives only in the queue dies with the queue. Measured: on 2026-08-26 M/L items
# were "promoted to a later wave" without anyone touching `estimate`, so the next run
# re-read the same wrong size.
#
# `triage.sh` (the health report) stays READ-ONLY by contract; this is the writer.
#
# Usage:
#   define-item.sh <BL-id | slug | filename | path> [--estimate XS|S|M|L|XL] [--surface internal|behaviour|ui|ops]
#                   [--verify "<how it will be proven>"] [--touches "<path, path, …>"]
#                   [--depends "<BL-NNN[, BL-NNN…]>"] [--no-index]
#
#   --touches   files or modules the item will change; comma-separated. Items sharing a
#               token cluster adjacently in the queue (sweep-kickoff.sh).
#   --depends   ids that must CLOSE before this item — `A→B` written on B as `depends: BL-A`.
#               `merge:BL-NNN` means "the same change seen twice": the pair closes in ONE
#               commit carrying both `Backlog:` trailers (a MERGE cluster).
#
# Only the fields given are written; each is inserted if the item predates it. Every
# value is validated the way register-item.sh validates it, and `updated` is stamped.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_backlog-lib.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

TARGET="" ESTIMATE="" SURFACE="" VERIFY="" TOUCHES="" DEPENDS="" NO_INDEX=0
SET_VERIFY=0 SET_TOUCHES=0 SET_DEPENDS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --estimate) ESTIMATE="$2"; shift 2 ;;
    --surface)  SURFACE="$2"; shift 2 ;;
    --verify)   VERIFY="$2"; SET_VERIFY=1; shift 2 ;;
    --touches)  TOUCHES="$2"; SET_TOUCHES=1; shift 2 ;;
    --depends)  DEPENDS="$2"; SET_DEPENDS=1; shift 2 ;;
    --no-index) NO_INDEX=1; shift ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          TARGET="$1"; shift ;;
  esac
done
[[ -n "$TARGET" ]] || die "target required: <BL-id | slug | filename | path>"
[[ -n "$ESTIMATE$SURFACE" || $SET_VERIFY -eq 1 || $SET_TOUCHES -eq 1 || $SET_DEPENDS -eq 1 ]] || die "nothing to write — give at least one verdict flag"

[[ -z "$ESTIMATE" ]] || case "$ESTIMATE" in XS|S|M|L|XL) ;; *) die "invalid estimate: $ESTIMATE" ;; esac
[[ "$SURFACE" == "behavior" ]] && SURFACE="behaviour"
[[ -z "$SURFACE" ]] || case "$SURFACE" in internal|behaviour|ui|ops) ;; *) die "invalid surface: $SURFACE (internal|behaviour|ui|ops)" ;; esac
# Store what was validated: 'merge: BL-002' kept its space and sweep-order never matched
# the twin. Ids are minted `BL-%03d` (register-item.sh accepts 3-5 digits), so `BL-5` can
# never name an item and is refused, not padded.
if [[ $SET_DEPENDS -eq 1 && -n "$DEPENDS" ]]; then
  IFS=',' read -ra _deps <<<"$DEPENDS"
  _norm=""
  for d in "${_deps[@]}"; do
    d="${d// /}"
    [[ "$d" =~ ^(merge:)?BL-[0-9]{3,5}$ ]] || die "invalid --depends entry '$d' (BL-NNN or merge:BL-NNN, comma-separated)"
    _norm="${_norm:+$_norm, }$d"
  done
  DEPENDS="$_norm"
fi

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
FILE="$(resolve_backlog_target "$BACKLOG_DIR" "$TARGET")"
if [[ -z "$FILE" ]]; then
  [[ "$TARGET" =~ ^[Bb][Ll]-[0-9]+$ ]] && die "no active backlog item with id $(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
  die "cannot resolve target: $TARGET"
fi

TODAY="$(date +%Y-%m-%d)"
# One awk pass: rewrite a key where present, insert the absent ones before the closing
# `---` (the insert-if-missing idiom close-item.sh and stamp_escalated_to already use —
# a rewrite-only branch is a silent no-op on an item that predates the field).
# Escaped values go through ENVIRON, never `-v`: awk -v re-reads backslash escapes and
# undid yaml_escape(), so `"` and `\` landed raw in the double-quoted scalar.
# A private temp next to the item, carrying its mode (cp -p), renamed over it: a shared
# `$FILE.tmp` let one writer truncate the file another was about to move into place.
TMPF="$(mktemp "$(dirname "$FILE")/.$(basename "$FILE").XXXXXX")" && cp -p "$FILE" "$TMPF" || { rm -f "$TMPF"; die "could not rewrite $FILE"; }
DI_VER="$(yaml_escape "$VERIFY")" DI_TOU="$(yaml_escape "$TOUCHES")" DI_DEP="$(yaml_escape "$DEPENDS")" \
awk -v today="$TODAY" \
    -v est="$ESTIMATE" -v sur="$SURFACE" \
    -v setver="$SET_VERIFY" -v settou="$SET_TOUCHES" -v setdep="$SET_DEPENDS" '
  BEGIN { d=0; s_est=0; s_sur=0; s_ver=0; s_tou=0; s_dep=0
          ver=ENVIRON["DI_VER"]; tou=ENVIRON["DI_TOU"]; dep=ENVIRON["DI_DEP"] }
  /^---[[:space:]]*$/ {
    d++
    if (d==2) {
      if (est!="" && !s_est) print "estimate: " est
      if (sur!="" && !s_sur) print "surface: " sur
      if (setver && !s_ver) print "verify: \"" ver "\""
      if (settou && !s_tou) print "touches: \"" tou "\""
      if (setdep && !s_dep) print "depends: \"" dep "\""
    }
    print; next
  }
  d==1 && est!="" && /^estimate:/ { print "estimate: " est; s_est=1; next }
  d==1 && sur!="" && /^surface:/  { print "surface: " sur;  s_sur=1; next }
  d==1 && setver && /^verify:/    { print "verify: \"" ver "\""; s_ver=1; next }
  d==1 && settou && /^touches:/   { print "touches: \"" tou "\""; s_tou=1; next }
  d==1 && setdep && /^depends:/   { print "depends: \"" dep "\""; s_dep=1; next }
  d==1 && /^updated:/             { print "updated: " today; next }
  { print }
' "$FILE" > "$TMPF" && [[ -s "$TMPF" ]] && mv -f "$TMPF" "$FILE" || { rm -f "$TMPF"; die "could not rewrite $FILE"; }

ok "Triaged $(read_id "$FILE"): ${ESTIMATE:+estimate=$ESTIMATE }${SURFACE:+surface=$SURFACE }$([[ $SET_VERIFY -eq 1 ]] && printf 'verify ')$([[ $SET_TOUCHES -eq 1 ]] && printf 'touches ')$([[ $SET_DEPENDS -eq 1 ]] && printf 'depends')"
[[ $NO_INDEX -eq 1 ]] || bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null 2>&1 || true
printf '%s\n' "$FILE"
