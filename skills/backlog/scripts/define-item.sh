#!/usr/bin/env bash
# define-item.sh — write optional front-matter fields into a backlog item: the triage
# VERDICT (estimate, surface, verify, touches, depends) and the tracker fields (raise,
# ticket, parent, branch, pr, review, checked) and the lifecycle fields a migration
# corrects (blocked_by, escalated_to).
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
#                   [--depends "<BL-NNN[, BL-NNN…]>"]
#                   [--raise to-raise|raised|none] [--ticket <KEY>] [--parent <KEY>]
#                   [--branch [<repo>:]<branch>]… [--pr <repo>#<n>@<state>]… [--review <repo>#<n>@<state>]…
#                   [--checked YYYY-MM-DD] [--blocked-by "<who/what>"] [--escalated-to "<ref>"]
#                   [--keep-title] [--no-index]
#
#   --touches   files or modules the item will change; comma-separated. Items sharing a
#               token cluster adjacently in the queue (sweep-kickoff.sh).
#   --depends   ids that must CLOSE before this item — `A→B` written on B as `depends: BL-A`.
#               `merge:BL-NNN` means "the same change seen twice": the pair closes in ONE
#               commit carrying both `Backlog:` trailers (a MERGE cluster).
#   --raise     an unconfirmed team finding: to-raise | raised; `none` deletes the line.
#   --ticket    `ticket: "issue/<KEY>"`, the key upper-cased; the title (and the item's own
#               `#` heading) gains the `<KEY> ` prefix, the file is never renamed. With a
#               `ticket_pattern` in the item's project backlog profile the key must match it
#               whole (case-insensitive), else any non-empty key without spaces or commas.
#   --parent    `parent: "issue/<KEY>"`, same key rules; the title is left alone.
#   --branch    repeatable; the values SET the list (`branch: "app:fix/x, api:fix/y"`). Use
#               `<repo>:` when the workspace holds several repos; a bare name stays valid.
#   --pr        repeatable; state draft|open|approved|merged|closed. The entry with the same
#               <repo>#<n> is replaced, a new one appended. Stamps `checked`.
#   --review    a teammate's PR to review, same shape, state requested|changes|approved.
#               Stamps `checked`.
#   --checked   the day a PR or review state was seen (YYYY-MM-DD, not in the future);
#               alone it rewrites `checked`, beside --pr/--review it replaces today's stamp.
#   --blocked-by  SETS the Blocked modifier on an active item (priority kept; defer-item.sh
#               --reason appends instead); "" clears it to `blocked_by: ""`.
#   --escalated-to  SETS the field on an active item without closing it (register-item.sh
#               --escalate-to accumulates); "" clears it. Shape is validate.py's to judge.
#   --ticket and --pr clear `raise` (the ticket or PR arrived), whatever --raise says.
#   --keep-title  with --ticket, leave the title and heading alone: register-item.sh
#               --review passes it, because a review title names the key in parentheses.
#
# Only the fields given are written; each is inserted if the item predates it. Every
# value is validated the way register-item.sh validates it, and `updated` is stamped.
# No profile gate: the tracker flags work in any project; nothing writes those fields
# unless they are given.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_backlog-lib.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

TARGET="" ESTIMATE="" SURFACE="" VERIFY="" TOUCHES="" DEPENDS="" NO_INDEX=0 KEEP_TITLE=0
SET_VERIFY=0 SET_TOUCHES=0 SET_DEPENDS=0
RAISE="" TICKET="" PARENT="" SET_TICKET=0 SET_PARENT=0 BRANCHES=() PRS=() REVIEWS=()
CHECKED_AT="" SET_CHECKED=0 BLOCKED="" SET_BLOCKED=0 ESCALATED="" SET_ESCALATED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --estimate) ESTIMATE="$2"; shift 2 ;;
    --surface)  SURFACE="$2"; shift 2 ;;
    --verify)   VERIFY="$2"; SET_VERIFY=1; shift 2 ;;
    --touches)  TOUCHES="$2"; SET_TOUCHES=1; shift 2 ;;
    --depends)  DEPENDS="$2"; SET_DEPENDS=1; shift 2 ;;
    --raise)    RAISE="$2"; shift 2 ;;
    --ticket)   TICKET="$2"; SET_TICKET=1; shift 2 ;;
    --parent)   PARENT="$2"; SET_PARENT=1; shift 2 ;;
    --branch)   BRANCHES+=("$2"); shift 2 ;;
    --pr)       PRS+=("$2"); shift 2 ;;
    --review)   REVIEWS+=("$2"); shift 2 ;;
    --checked)  CHECKED_AT="$2"; SET_CHECKED=1; shift 2 ;;
    --blocked-by)   BLOCKED="$2"; SET_BLOCKED=1; shift 2 ;;
    --escalated-to) ESCALATED="$2"; SET_ESCALATED=1; shift 2 ;;
    --keep-title) KEEP_TITLE=1; shift ;;
    --no-index) NO_INDEX=1; shift ;;
    -h|--help)  usage_from_header "$0"; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          TARGET="$1"; shift ;;
  esac
done
[[ -n "$TARGET" ]] || die "target required: <BL-id | slug | filename | path>"
[[ -n "$ESTIMATE$SURFACE$RAISE" || $SET_VERIFY -eq 1 || $SET_TOUCHES -eq 1 || $SET_DEPENDS -eq 1 \
   || $SET_TICKET -eq 1 || $SET_PARENT -eq 1 || ${#BRANCHES[@]} -gt 0 || ${#PRS[@]} -gt 0 || ${#REVIEWS[@]} -gt 0 \
   || $SET_CHECKED -eq 1 || $SET_BLOCKED -eq 1 || $SET_ESCALATED -eq 1 ]] \
  || die "nothing to write — give at least one field flag"

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

# --- tracker fields: every value is validated before the item is touched ---------------
[[ -z "$RAISE" ]] || case "$RAISE" in to-raise|raised|none) ;; *) die "invalid --raise: $RAISE (to-raise|raised|none)" ;; esac
# The key pattern is the item's project's (the item may live in another repo than the cwd):
# <ctx>/backlog/[_deferred|_archive/]<file> -> <ctx>.
PATTERN="" _abs="$(cd "$(dirname "$FILE")" && pwd -P)/$(basename "$FILE")"
_prof="$(resolve_profile "${_abs%/backlog/*}" backlog)" && PATTERN="$(profile_field "$_prof" ticket_pattern)"
# a whitespace-only pattern is no pattern; surrounding blanks are not part of one
PATTERN="${PATTERN#"${PATTERN%%[![:space:]]*}"}"; PATTERN="${PATTERN%"${PATTERN##*[![:space:]]}"}"
# norm_key <flag> <value>: the key upper-cased, an `issue/` prefix dropped; dies when refused.
norm_key() {
  local key="${2#[Ii][Ss][Ss][Uu][Ee]/}" rc=0
  [[ -n "$key" && ! "$key" =~ [[:space:],\"\\] ]] || die "invalid $1 '$2' (one non-empty key, no spaces or commas)"
  key="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  if [[ -n "$PATTERN" ]]; then
    grep -Eqi -- "^(${PATTERN})\$" <<<"$key" || rc=$?
    [[ $rc -le 1 ]] || die "invalid ticket_pattern in $_prof: $PATTERN"
    [[ $rc -eq 0 ]] || die "$1 '$2' does not match ticket_pattern $PATTERN ($_prof)"
  fi
  printf '%s' "$key"
}
if [[ $SET_TICKET -eq 1 ]]; then TICKET="$(norm_key --ticket "$TICKET")" || exit 2; fi
if [[ $SET_PARENT -eq 1 ]]; then PARENT="$(norm_key --parent "$PARENT")" || exit 2; fi

# fm_raw <key>: the item's front-matter value; a double-quoted scalar is unquoted and
# unescaped (yaml_escape's `\"` and `\\`, read back in one left-to-right pass).
fm_raw() { awk -v k="$1" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && index($0, k":")==1 {
  v=substr($0, length(k)+2); sub(/^[[:space:]]+/,"",v); sub(/[[:space:]]+$/,"",v)
  if (v ~ /^".*"$/) { v=substr(v, 2, length(v)-2); o=""
    for (i=1; i<=length(v); i++) { ch=substr(v,i,1); if (ch=="\\") { i++; ch=substr(v,i,1) } o=o ch }
    v=o }
  print v; exit}' "$FILE"; }

# merge_prs <field> <ladder> <entry>…: the field's comma list with each entry replacing the
# one with the same pr/<repo>#<n>, else appended; order kept.
# Index loops, not "${list[@]}": an empty array under `set -u` is unbound in bash 3.2.
merge_prs() {
  local field="$1" ladder="$2" e id i n=0 list=() out=""; shift 2
  [[ -z "$(fm_raw "$field")" ]] || { IFS=',' read -ra list <<<"$(fm_raw "$field")"; n=${#list[@]}; }
  for e in "$@"; do
    e="${e#pr/}"
    [[ "$e" =~ ^([A-Za-z0-9._-]+)#([0-9]+)@([a-z]+)$ && " $ladder " == *" ${BASH_REMATCH[3]} "* ]] \
      || die "invalid --$field '$e' (<repo>#<n>@<state>, state one of: $ladder)"
    e="pr/$e" id="${e%@*}" i=0
    while [[ $i -lt $n && "${list[i]// /}" != "$id"@* && "${list[i]// /}" != "$id" ]]; do i=$((i+1)); done
    list[i]="$e"; [[ $i -lt $n ]] || n=$((n+1))
  done
  for ((i=0; i<n; i++)); do e="${list[i]// /}"; [[ -z "$e" ]] || out="${out:+$out, }$e"; done
  printf '%s' "$out"
}
SET_PR=0 SET_REVIEW=0 PR_LIST="" REVIEW_LIST="" BRANCH_LIST="" CHECKED=""
if [[ ${#PRS[@]} -gt 0 ]]; then PR_LIST="$(merge_prs pr "draft open approved merged closed" "${PRS[@]}")" || exit 2; SET_PR=1; fi
if [[ ${#REVIEWS[@]} -gt 0 ]]; then REVIEW_LIST="$(merge_prs review "requested changes approved" "${REVIEWS[@]}")" || exit 2; SET_REVIEW=1; fi
[[ $SET_PR -eq 0 && $SET_REVIEW -eq 0 ]] || CHECKED="$(date +%Y-%m-%d)"
if [[ $SET_CHECKED -eq 1 ]]; then
  python3 -c '
import datetime, re, sys
v = sys.argv[1]
sys.exit(0 if re.fullmatch(r"\d{4}-\d{2}-\d{2}", v) and datetime.date.fromisoformat(v) <= datetime.date.today() else 1)' "$CHECKED_AT" 2>/dev/null \
    || die "invalid --checked '$CHECKED_AT' (YYYY-MM-DD, not in the future)"
  CHECKED="$CHECKED_AT"
fi
for _b in ${BRANCHES[@]+"${BRANCHES[@]}"}; do
  [[ "$_b" =~ ^([A-Za-z0-9._-]+:)?[^[:space:],:\"\\]+$ ]] || die "invalid --branch '$_b' ([<repo>:]<branch>, no spaces or commas)"
  BRANCH_LIST="${BRANCH_LIST:+$BRANCH_LIST, }$_b"
done
SET_BRANCH=0; [[ ${#BRANCHES[@]} -eq 0 ]] || SET_BRANCH=1

# A ticket or a PR clears raise: it arrived, so the finding is no longer unconfirmed —
# this wins over a --raise given in the same call. `--raise none` deletes the line too.
DEL_RAISE=0
[[ "$RAISE" != "none" && $SET_TICKET -eq 0 && $SET_PR -eq 0 ]] || { DEL_RAISE=1; RAISE=""; }

# --ticket prefixes the title with the key (once: a title already starting with it is
# kept, and a re-ticket replaces the old key's prefix). The first `#` heading follows only
# when it IS the item's title line.
SET_TITLE=0 OLD_TITLE="" NEW_TITLE=""
if [[ $SET_TICKET -eq 1 && $KEEP_TITLE -eq 0 ]]; then
  OLD_TITLE="$(fm_raw title)"
  _old_key="$(fm_raw ticket)"; _old_key="${_old_key#issue/}"
  # starts_with_key <title> <key>: the title begins with the key, then a non-alphanumeric or the end.
  starts_with_key() { local u k; u="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"; k="$2"
    [[ -n "$k" && "${u:0:${#k}}" == "$k" && ! "${u:${#k}:1}" =~ [A-Za-z0-9] ]]; }
  if starts_with_key "$OLD_TITLE" "$TICKET"; then
    NEW_TITLE="$OLD_TITLE"
  elif starts_with_key "$OLD_TITLE" "$_old_key"; then
    NEW_TITLE="$TICKET${OLD_TITLE:${#_old_key}}"
  else
    NEW_TITLE="$TICKET${OLD_TITLE:+ $OLD_TITLE}"
  fi
  [[ "$NEW_TITLE" == "$OLD_TITLE" ]] || SET_TITLE=1
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
DI_TIT="$(yaml_escape "$NEW_TITLE")" DI_OLDT="$OLD_TITLE" DI_NEWT="$NEW_TITLE" \
DI_TIC="$(yaml_escape "$TICKET")" DI_PAR="$(yaml_escape "$PARENT")" DI_BRA="$(yaml_escape "$BRANCH_LIST")" \
DI_PR="$PR_LIST" DI_REV="$REVIEW_LIST" DI_BLK="$(yaml_escape "$BLOCKED")" DI_ESC="$(yaml_escape "$ESCALATED")" \
awk -v today="$TODAY" \
    -v est="$ESTIMATE" -v sur="$SURFACE" \
    -v setver="$SET_VERIFY" -v settou="$SET_TOUCHES" -v setdep="$SET_DEPENDS" \
    -v rai="$RAISE" -v delrai="$DEL_RAISE" -v settit="$SET_TITLE" -v settic="$SET_TICKET" \
    -v setpar="$SET_PARENT" -v setbra="$SET_BRANCH" -v setpr="$SET_PR" -v setrev="$SET_REVIEW" \
    -v chk="$CHECKED" -v setblk="$SET_BLOCKED" -v setesc="$SET_ESCALATED" '
  BEGIN { d=0; s_est=0; s_sur=0; s_ver=0; s_tou=0; s_dep=0
          s_rai=0; s_tic=0; s_par=0; s_bra=0; s_pr=0; s_rev=0; s_chk=0; s_blk=0; s_esc=0; head=0
          ver=ENVIRON["DI_VER"]; tou=ENVIRON["DI_TOU"]; dep=ENVIRON["DI_DEP"]
          tit=ENVIRON["DI_TIT"]; oldt=ENVIRON["DI_OLDT"]; newt=ENVIRON["DI_NEWT"]
          tic=ENVIRON["DI_TIC"]; par=ENVIRON["DI_PAR"]; bra=ENVIRON["DI_BRA"]
          prl=ENVIRON["DI_PR"]; rev=ENVIRON["DI_REV"]; blk=ENVIRON["DI_BLK"]; esc=ENVIRON["DI_ESC"] }
  /^---[[:space:]]*$/ && d<2 {
    d++
    if (d==2) {
      if (est!="" && !s_est) print "estimate: " est
      if (sur!="" && !s_sur) print "surface: " sur
      if (setver && !s_ver) print "verify: \"" ver "\""
      if (settou && !s_tou) print "touches: \"" tou "\""
      if (setdep && !s_dep) print "depends: \"" dep "\""
      if (rai!="" && !s_rai) print "raise: " rai
      if (settic && !s_tic) print "ticket: \"issue/" tic "\""
      if (setpar && !s_par) print "parent: \"issue/" par "\""
      if (setbra && !s_bra) print "branch: \"" bra "\""
      if (setpr && !s_pr) print "pr: \"" prl "\""
      if (setrev && !s_rev) print "review: \"" rev "\""
      if (chk!="" && !s_chk) print "checked: " chk
      if (setblk && !s_blk) print "blocked_by: \"" blk "\""
      if (setesc && !s_esc) print "escalated_to: \"" esc "\""
    }
    print; next
  }
  d==1 && est!="" && /^estimate:/ { print "estimate: " est; s_est=1; next }
  d==1 && sur!="" && /^surface:/  { print "surface: " sur;  s_sur=1; next }
  d==1 && setver && /^verify:/    { print "verify: \"" ver "\""; s_ver=1; next }
  d==1 && settou && /^touches:/   { print "touches: \"" tou "\""; s_tou=1; next }
  d==1 && setdep && /^depends:/   { print "depends: \"" dep "\""; s_dep=1; next }
  d==1 && delrai && /^raise:/     { next }
  d==1 && rai!="" && /^raise:/    { print "raise: " rai; s_rai=1; next }
  d==1 && settit && /^title:/     { print "title: \"" tit "\""; next }
  d==1 && settic && /^ticket:/    { print "ticket: \"issue/" tic "\""; s_tic=1; next }
  d==1 && setpar && /^parent:/    { print "parent: \"issue/" par "\""; s_par=1; next }
  d==1 && setbra && /^branch:/    { print "branch: \"" bra "\""; s_bra=1; next }
  d==1 && setpr && /^pr:/         { print "pr: \"" prl "\""; s_pr=1; next }
  d==1 && setrev && /^review:/    { print "review: \"" rev "\""; s_rev=1; next }
  d==1 && chk!="" && /^checked:/  { print "checked: " chk; s_chk=1; next }
  d==1 && setblk && /^blocked_by:/ { print "blocked_by: \"" blk "\""; s_blk=1; next }
  d==1 && setesc && /^escalated_to:/ { print "escalated_to: \"" esc "\""; s_esc=1; next }
  d==1 && /^updated:/             { print "updated: " today; next }
  d==2 && !head && /^# / { head=1; if (settit && substr($0, 3)==oldt) { print "# " newt; next } }
  { print }
' "$FILE" > "$TMPF" && [[ -s "$TMPF" ]] && mv -f "$TMPF" "$FILE" || { rm -f "$TMPF"; die "could not rewrite $FILE"; }

ok "Triaged $(read_id "$FILE"): ${ESTIMATE:+estimate=$ESTIMATE }${SURFACE:+surface=$SURFACE }$([[ $SET_VERIFY -eq 1 ]] && printf 'verify ')$([[ $SET_TOUCHES -eq 1 ]] && printf 'touches ')$([[ $SET_DEPENDS -eq 1 ]] && printf 'depends')$([[ -n "$RAISE" ]] && printf ' raise=%s' "$RAISE")$([[ $DEL_RAISE -eq 1 ]] && printf ' raise-cleared')$([[ $SET_TICKET -eq 1 ]] && printf ' ticket=%s' "$TICKET")$([[ $SET_PARENT -eq 1 ]] && printf ' parent=%s' "$PARENT")$([[ $SET_BRANCH -eq 1 ]] && printf ' branch')$([[ $SET_PR -eq 1 ]] && printf ' pr')$([[ $SET_REVIEW -eq 1 ]] && printf ' review')$([[ $SET_CHECKED -eq 1 ]] && printf ' checked=%s' "$CHECKED")$([[ $SET_BLOCKED -eq 1 ]] && { [[ -n "$BLOCKED" ]] && printf ' blocked_by' || printf ' blocked_by-cleared'; })$([[ $SET_ESCALATED -eq 1 ]] && { [[ -n "$ESCALATED" ]] && printf ' escalated_to' || printf ' escalated_to-cleared'; })"
[[ $NO_INDEX -eq 1 ]] || bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null 2>&1 || true
printf '%s\n' "$FILE"
