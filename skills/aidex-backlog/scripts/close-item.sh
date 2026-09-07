#!/usr/bin/env bash
# close-item.sh — atomically close a backlog item (D-10): set status, record
# resolving commit(s), stamp `updated`, move to _archive/, rebuild the index.
# Never edit `status` by hand — this is the one supported close path.
#
# Usage:
#   close-item.sh <BL-id | filename | path> [options]
#
# Options:
#   --status <done|dropped>     default: done
#   --commit <sha>              resolving commit (repeatable). Use when the item
#                               was fixed directly, with no plan (D-09 provenance).
#   --superseded-by <type/ref>  mark superseded (status stays; index shows "superseded →")
#   --escalated-to <type/ref>   mark handed off (e.g. plan/<slug>)
#   --reason "<text>"           appended under ## Notes
#   --no-index                  skip index regeneration
#   --sweep                     sweep mode: closing `done` REQUIRES a ## Verification
#                               section whose non-owner rows all carry a proof and
#                               whose rows meet the item's `surface` minimum; otherwise
#                               exit 2, nothing mutated, nothing archived. Outside sweep
#                               mode the type: bug warning below is all there is.
#
# Resolves <BL-id> against active backlog items' front-matter `id:` field.

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_RESET=$'\033[0m'
else C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''; fi
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()  { printf '%serror: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 2; }

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

TARGET="" STATUS="done" SUPERSEDED="" ESCALATED="" REASON="" NO_INDEX=0 SWEEP=0
COMMITS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)        STATUS="$2"; shift 2 ;;
    --commit)        COMMITS+=("$2"); shift 2 ;;
    --superseded-by) SUPERSEDED="$2"; shift 2 ;;
    --escalated-to)  ESCALATED="$2"; shift 2 ;;
    --reason)        REASON="$2"; shift 2 ;;
    --no-index)      NO_INDEX=1; shift ;;
    --sweep)         SWEEP=1; shift ;;
    -h|--help)       sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)              die "unknown option: $1" ;;
    *)               TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || die "target required: <BL-id | filename | path>"
case "$STATUS" in done|dropped) ;; *) die "invalid --status: $STATUS (done|dropped)";; esac

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- resolve target to an active backlog file ---
read_id() { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$1"; }
FILE=""
if [[ "$TARGET" =~ ^[Bb][Ll]-[0-9]+$ ]]; then
  TARGET_UC="$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
  for f in "$BACKLOG_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(read_id "$f")" == "$TARGET_UC" ]] && { FILE="$f"; break; }
  done
  [[ -n "$FILE" ]] || die "no active backlog item with id $TARGET_UC (already closed?)"
elif [[ -f "$TARGET" ]]; then
  FILE="$TARGET"
elif [[ -f "$BACKLOG_DIR/$TARGET" ]]; then
  FILE="$BACKLOG_DIR/$TARGET"
else
  die "cannot resolve target: $TARGET"
fi

[[ "$(dirname "$FILE")" == "$BACKLOG_DIR" ]] || die "target is not an active backlog item: $FILE"

TODAY="$(date +%Y-%m-%d)"
COMMITS_STR="${COMMITS[*]:-}"

# --- every cited commit must be ON A TREE THIS RUN IS ACTUALLY IN ---
# 2026-08-28: BL-635/636 cited a worktree branch's commits for hours while main carried
# different fixes for the same items. A hash that resolves but is not an ancestor of any
# HEAD here is a citation of work that is not here. Multi-repo workspaces (backend/.git,
# frontend/.git beside the root) are searched one level down; the first repo that has
# the commit on its current branch wins.
#
# BL-333: the caller's OWN tree is searched first, and it is usually not $ROOT. A sweep
# is mandated to run in a linked worktree (sweep-execution-policy.md stage 2) whose
# branch stays unmerged until close-out, while find_project_root deliberately hops OUT of
# that worktree so the queue and the item live in the main tree. Both hops are right;
# together they refused every hash a sweep produced, for a whole run, item 1 to item 10.
#
# The discriminant is "the tree this run is EXECUTING in", never "reachable from some
# ref": a branch in a worktree the caller is not in stays refused, which is BL-635/636
# unweakened, and so does a hash on no branch at all.
caller_tree() {  # prints the caller's worktree root when it is another checkout of $ROOT's repo
  local top common root_common
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "$top" && "$top" != "$ROOT" ]] || return 1
  # The same REPOSITORY, not merely some git checkout: run from an unrelated repo that
  # happens to contain the object, this would otherwise wave the hash through. The common
  # dir is what a linked worktree shares with its main tree, so it is the identity.
  common="$(cd "$top" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd -P)" || return 1
  root_common="$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd -P)" || return 1
  [[ "$common" == "$root_common" ]] || return 1
  printf '%s' "$top"
}
CALLER_TREE="$(caller_tree || true)"

commit_on_trunk() {  # commit_on_trunk <sha> → prints the tree that carries it; exit 1 if none, 3 if no repo at all
  local sha="$1" repo any=0
  for repo in ${CALLER_TREE:+"$CALLER_TREE"} "$ROOT" "$ROOT"/*/; do
    [[ -d "$repo/.git" || -f "$repo/.git" ]] || continue
    any=1
    if git -C "$repo" cat-file -e "$sha^{commit}" 2>/dev/null \
       && git -C "$repo" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
      printf '%s' "$(basename "${repo%/}")"; return 0
    fi
  done
  [[ $any -eq 1 ]] && return 1 || return 3
}
# Named in the refusal, because "not here" is unactionable without "here is where I
# looked" — the two cases a caller has to tell apart are a hash from the wrong tree and
# a hash that exists nowhere.
SEARCHED="$(basename "$ROOT") (and any sub-repo)"
[[ -n "$CALLER_TREE" ]] && SEARCHED="the worktree $(basename "$CALLER_TREE"), then $SEARCHED"
for sha in "${COMMITS[@]:-}"; do
  [[ -n "$sha" ]] || continue
  rc=0; commit_on_trunk "$sha" >/dev/null || rc=$?
  case $rc in
    0) ;;
    3) warn "--commit $sha not verified: no git repository under $ROOT" ;;
    *) die "--commit $sha is not on the current branch of $SEARCHED — cite a commit that is here. Running from inside the worktree that carries it is what makes a sweep's own hash citable." ;;
  esac
done

# --- sweep mode: proof is a precondition, not a warning (Q15/Q16) ---
# The warning further down is what we had, and it is the 2.2% number: measured adoption
# of a mandate that is merely written down. In a sweep the item cannot become `done`
# without a ## Verification row per criterion, each with a proof — and this check runs
# BEFORE the first mutation, so a refusal leaves the file exactly as it was.
#
# Rows: `| kind | what | proof |`, kind in test|e2e|smoke|owner. An OWNER row with an
# empty proof does not REFUSE here, but it does not let the item become `done` either:
# the item is PARKED — `awaiting: owner` written into its front-matter, status left as
# it was, nothing archived, exit 0 — so the run moves on and the item sits under
# `## Awaiting owner` in the index until the owner answers (fill the proof cell, close
# again). Owner's call 2026-08-27: an item that still needs a judgement must never read
# as closed, or it gets archived by mistake. worklist-close.sh refuses to end the run
# while any queued item is parked; the report aggregates every parked row.
# Every other empty proof cell refuses.
read_fm() { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":"{
  sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }
verification_rows() {  # -> "kind<TAB>what<TAB>proof" per data row
  awk 'BEGIN{insec=0}
    /^## /{insec=($0 ~ /^## Verification[[:space:]]*$/)}
    insec && /^\|/ {
      line=$0; sub(/^\|/,"",line); sub(/\|[[:space:]]*$/,"",line)
      n=split(line, c, "|")
      for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/,"",c[i])}
      if (c[1]=="kind" || c[1] ~ /^-+$/) next
      # \x1f, not a tab: tab is IFS whitespace, so an empty `what` cell collapsed and
      # the proof landed in the what slot — a proven row refused with a misleading message.
      printf "%s\037%s\037%s\n", c[1], c[2], c[3]
    }' "$1"
}
if [[ $SWEEP -eq 1 && "$STATUS" == "done" ]]; then
  SURFACE="$(read_fm "$FILE" surface)"; SURFACE="${SURFACE:-internal}"
  ROWS="$(verification_rows "$FILE")"
  [[ -n "$ROWS" ]] || die "sweep close refused: $(basename "$FILE") has no ## Verification rows — one row per criterion (kind | what | proof), then close again"
  has_test=0 has_e2e=0 has_smoke=0 has_owner_proof=0 owner_open=0 missing=""
  while IFS=$'\037' read -r kind what proof; do
    [[ -n "$kind" ]] || continue
    case "$kind" in
      test|e2e|smoke|owner) ;;
      *) die "sweep close refused: ## Verification row has kind '$kind' (test|e2e|smoke|owner)" ;;
    esac
    if [[ -z "$proof" && "$kind" != "owner" ]]; then missing="$missing
    - $kind: $what"; continue; fi
    if [[ -z "$proof" ]]; then owner_open=$((owner_open+1)); continue; fi
    case "$kind" in test) has_test=1;; e2e) has_e2e=1;; smoke) has_smoke=1;; owner) has_owner_proof=1;; esac
  done <<<"$ROWS"
  [[ -z "$missing" ]] || die "sweep close refused: ## Verification rows with an empty proof cell:$missing"
  case "$SURFACE" in
    internal)  [[ $has_test -eq 1 ]] || die "sweep close refused: surface internal needs a proven \`test\` row" ;;
    behaviour) [[ $has_test -eq 1 && ( $has_e2e -eq 1 || $has_smoke -eq 1 ) ]] \
                 || die "sweep close refused: surface behaviour needs a proven \`test\` row AND an \`e2e\` or \`smoke\` row" ;;
    ui)        [[ $has_smoke -eq 1 ]] || die "sweep close refused: surface ui needs a proven \`smoke\` row (a screenshot is the proof)" ;;
    ops)       [[ $has_smoke -eq 1 || $has_test -eq 1 || $has_owner_proof -eq 1 ]] \
                 || die "sweep close refused: surface ops needs one proven row (a \`smoke\` with the command output, a \`test\`, or an answered \`owner\`)" ;;
    *)         die "sweep close refused: unknown surface '$SURFACE' (internal|behaviour|ui|ops)" ;;
  esac
  if [[ $owner_open -gt 0 ]]; then
    # Park, do not close: everything mechanical is proven, a judgement is still owed.
    # The resolving commits are kept too: a parked item is proven work whose sha was
    # otherwise lost until the owner closed it by hand (BL-499, 2026-08-28).
    awk -v today="$TODAY" -v commits="$COMMITS_STR" 'BEGIN{d=0;seen=0;seen_c=0}
      /^---[[:space:]]*$/ { d++
        if (d==2 && !seen) print "awaiting: owner"
        if (d==2 && commits!="" && !seen_c) print "commits: \"" commits "\""
        print; next }
      d==1 && /^awaiting:/ { print "awaiting: owner"; seen=1; next }
      d==1 && commits!="" && /^commits:/ { val=$0; sub(/^commits:[[:space:]]*/,"",val); gsub(/"/,"",val)
        if (val=="" || val=="[]") print "commits: \"" commits "\""; else print "commits: \"" val " " commits "\""
        seen_c=1; next }
      d==1 && /^updated:/ { print "updated: " today; next }
      { print }' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    [[ $NO_INDEX -eq 1 ]] || bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null 2>&1 || true
    printf 'parked: %s awaits the owner (%d owner row(s) unanswered) — not closed, not archived; fill the proof cell(s) and close again\n' "$(basename "$FILE")" "$owner_open"
    exit 0
  fi
fi

# --- mutate front-matter (status, updated, optional superseded_by/escalated_to/commits) ---
awk -v status="$STATUS" -v today="$TODAY" -v sup="$SUPERSEDED" -v esc="$ESCALATED" -v commits="$COMMITS_STR" '
  BEGIN { d=0; infm=0; seen_sup=0; seen_esc=0; seen_commits=0 }
  /^---[[:space:]]*$/ {
    d++
    if (d==1) { infm=1; print; next }
    if (d==2) {
      if (sup!="" && !seen_sup) print "superseded_by: " sup
      if (esc!="" && !seen_esc) print "escalated_to: " esc
      if (commits!="" && !seen_commits) print "commits: \"" commits "\""
      infm=0; print; next
    }
  }
  infm==1 {
    if ($0 ~ /^awaiting:/) next
    if ($0 ~ /^status:/)  { print "status: " status; next }
    if ($0 ~ /^updated:/) { print "updated: " today; next }
    if (sup!="" && $0 ~ /^superseded_by:/) { print "superseded_by: " sup; seen_sup=1; next }
    if (esc!="" && $0 ~ /^escalated_to:/)  { print "escalated_to: " esc; seen_esc=1; next }
    if (commits!="" && $0 ~ /^commits:/) {
      val=$0; sub(/^commits:[[:space:]]*/,"",val); gsub(/"/,"",val)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
      if (val=="" || val=="[]") print "commits: \"" commits "\""
      else                      print "commits: \"" val " " commits "\""
      seen_commits=1; next
    }
    print; next
  }
  { print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

# --- optional closing note ---
if [[ -n "$REASON" ]]; then
  printf -- '\n- Closed %s (%s): %s\n' "$TODAY" "$STATUS" "$REASON" >> "$FILE"
fi

# --- bug items close with proof of RED->GREEN, or say so (BL-134) ---
# The enforcement half of the start-item.sh route: a `type: bug` item that
# closes as done with no RED/GREEN evidence is the 2.2%-adoption failure showing
# up at the other end. Warn, never block — the visual/CSS exception is real, and
# items predating this carry no proof by construction.
if [[ "$STATUS" == "done" ]]; then
  ITEM_TYPE="$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="type:"{print $2; exit}' "$FILE")"
  if [[ "$ITEM_TYPE" == "bug" ]]; then
    # Both YAML shapes: `proof_links: [a, b]` on one line, and the block list
    # the conventions document (`proof_links:` then indented `- ` entries).
    # Reading only the same-line value made a correctly-proven item warn.
    PROOF="$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit}
      c==1 && $1=="proof_links:"{inline=$0; sub(/^[^:]*:[[:space:]]*/,"",inline); inlist=1; next}
      c==1 && inlist{
        if ($0 ~ /^[[:space:]]+-[[:space:]]*[^[:space:]]/) {found=1; exit}
        else if ($0 ~ /^[^[:space:]]/) {inlist=0}}
      END{print (found ? "LIST" : inline)}' "$FILE")"
    HAS_PROOF=1
    [[ -z "$PROOF" || "$PROOF" == "[]" || "$PROOF" == '""' ]] && HAS_PROOF=0
    # HTML comments are stripped first: a template comment must never read as proof.
    # python, not sed: BSD sed reads `:a; s/…` as one label name, emits the input
    # unchanged and exits 0 — a silent no-op (found by review 2026-08-27).
    BODY_NO_COMMENTS="$(python3 -c 'import re,sys; print(re.sub(r"<!--.*?-->", "", open(sys.argv[1]).read(), flags=re.S))' "$FILE")"
    if [[ $HAS_PROOF -eq 0 ]] && ! { grep -qE '\bRED\b' <<<"$BODY_NO_COMMENTS" && grep -qE '\bGREEN\b' <<<"$BODY_NO_COMMENTS"; }; then
      warn "bug item closing with no RED->GREEN proof (no proof_links, no RED/GREEN line in the body)"
      warn "  the regression test is what proves this bug fixed — see aidex-bugfix, and the"
      warn "  bug-fix policy in CLAUDE.md. Purely visual/CSS bugs are the documented exception."
    fi
  fi
fi

# --- move to _archive/ ---
mkdir -p "$BACKLOG_DIR/_archive"
DEST="$BACKLOG_DIR/_archive/$(basename "$FILE")"
[[ -e "$DEST" ]] && die "archive collision: $DEST already exists"
mv "$FILE" "$DEST"
ok "Closed $(basename "$FILE") → $STATUS · archived"
# A backlog item's companion is always a sibling, never inside it, so `mv` alone
# leaves every one of them behind.
archive_companions "$ROOT/.context" "backlog/$(basename "$FILE")" "$BACKLOG_DIR/_archive"
[[ -n "$COMMITS_STR" ]] && ok "  commits: $COMMITS_STR"

# --- rebuild index ---
if [[ $NO_INDEX -eq 0 ]]; then
  bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null
  ok "  index rebuilt"
fi

printf '%s\n' "$DEST"
