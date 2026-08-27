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
#   define-item.sh <BL-id | path> [--estimate XS|S|M|L|XL] [--surface internal|behaviour|ui|ops]
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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
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
[[ -n "$TARGET" ]] || die "target required: <BL-id | path>"
[[ -n "$ESTIMATE$SURFACE" || $SET_VERIFY -eq 1 || $SET_TOUCHES -eq 1 || $SET_DEPENDS -eq 1 ]] || die "nothing to write — give at least one verdict flag"

[[ -z "$ESTIMATE" ]] || case "$ESTIMATE" in XS|S|M|L|XL) ;; *) die "invalid estimate: $ESTIMATE" ;; esac
[[ "$SURFACE" == "behavior" ]] && SURFACE="behaviour"
[[ -z "$SURFACE" ]] || case "$SURFACE" in internal|behaviour|ui|ops) ;; *) die "invalid surface: $SURFACE (internal|behaviour|ui|ops)" ;; esac
if [[ $SET_DEPENDS -eq 1 && -n "$DEPENDS" ]]; then
  IFS=',' read -ra _deps <<<"$DEPENDS"
  for d in "${_deps[@]}"; do
    d="${d// /}"
    [[ "$d" =~ ^(merge:)?BL-[0-9]+$ ]] || die "invalid --depends entry '$d' (BL-NNN or merge:BL-NNN, comma-separated)"
  done
fi

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
read_id() { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$1"; }
FILE=""
if [[ "$TARGET" =~ ^[Bb][Ll]-[0-9]+$ ]]; then
  T="$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
  for f in "$BACKLOG_DIR"/*.md; do [[ -f "$f" && "$(read_id "$f")" == "$T" ]] && { FILE="$f"; break; }; done
  [[ -n "$FILE" ]] || die "no active backlog item with id $T"
elif [[ -f "$TARGET" ]]; then FILE="$TARGET"
elif [[ -f "$BACKLOG_DIR/$TARGET" ]]; then FILE="$BACKLOG_DIR/$TARGET"
else die "cannot resolve target: $TARGET"; fi

esc() { printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
TODAY="$(date +%Y-%m-%d)"
# One awk pass: rewrite a key where present, insert the absent ones before the closing
# `---` (the insert-if-missing idiom close-item.sh and stamp_escalated_to already use —
# a rewrite-only branch is a silent no-op on an item that predates the field).
awk -v today="$TODAY" \
    -v est="$ESTIMATE" -v sur="$SURFACE" \
    -v ver="$(esc "$VERIFY")" -v setver="$SET_VERIFY" \
    -v tou="$(esc "$TOUCHES")" -v settou="$SET_TOUCHES" \
    -v dep="$(esc "$DEPENDS")" -v setdep="$SET_DEPENDS" '
  BEGIN { d=0; s_est=0; s_sur=0; s_ver=0; s_tou=0; s_dep=0 }
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
' "$FILE" > "$FILE.tmp" && [[ -s "$FILE.tmp" ]] && mv "$FILE.tmp" "$FILE" || die "could not rewrite $FILE"

ok "Triaged $(read_id "$FILE"): ${ESTIMATE:+estimate=$ESTIMATE }${SURFACE:+surface=$SURFACE }$([[ $SET_VERIFY -eq 1 ]] && printf 'verify ')$([[ $SET_TOUCHES -eq 1 ]] && printf 'touches ')$([[ $SET_DEPENDS -eq 1 ]] && printf 'depends')"
[[ $NO_INDEX -eq 1 ]] || bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null 2>&1 || true
printf '%s\n' "$FILE"
