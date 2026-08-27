#!/usr/bin/env bash
# worklist-close.sh — close a run-queue (status done|dropped), stamp updated.
#
# Usage:
#   worklist-close.sh <slug-or-path> [--status done|dropped] [--force]
#
# For a SWEEP work-list (`mode: sweep`) refuses — exit 2, nothing mutated — while either
# holds (sweep plan, Q14/Q16); a plain work-list closes as before:
#   · a queued backlog item (active or archived) carries a `## Verification` row of
#     kind `owner` whose proof cell is empty: the owner has not answered, and a run
#     that closes over it silently converts "outstanding" into "done";
#   · `## Deferred / emergent` holds an unchecked line that names no BL-NNN and no
#     `CLOSE:` — a deferral that would vanish with the run (close-plan.sh's guard, on
#     the sweep's side; "a deferral must outlive the run that made it").
# `--force` closes anyway and PRINTS what it overrode: "the checklist was handed over
# and never answered" is a legitimate end state, but it is recorded, never silent.
#
# On close the file moves to worklists/_archive/ (D-10) — `worklist/<file>` references
# keep resolving through the two-folder lookup. Prints "CLOSED <archived path>".
set -euo pipefail

# Shared resolver — never `git rev-parse --show-toplevel`. That answered the wrong root
# twice over: inside a linked worktree it is the worktree (which vanishes on teardown),
# and in a multi-repo workspace it is the sub-repo, not the workspace `.context/`. Every
# backlog script the sweep chains this with resolves through _lib.sh, so a private
# resolver here would update the queue in one tree while the item closes in another.
# Pinned by test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"
ROOT="$(find_project_root)"
WL_DIR="$ROOT/.context/worklists"

arg="${1:-}"; shift || true
[[ -n "$arg" ]] || { echo "usage: worklist-close.sh <slug-or-path> [--status done|dropped]" >&2; exit 2; }

status="done" force=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) status="$2"; shift 2;;
    --force)  force=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ "$status" == "done" || "$status" == "dropped" ]] || { echo "--status must be done|dropped" >&2; exit 2; }

# `|| true`: ls exits 2 on no match, which pipefail+errexit would turn into a
# silent exit 1 before the not-found diagnostic below ever runs.
if [[ -f "$arg" ]]; then file="$arg"; else file="$(ls "$WL_DIR/"*"$arg"*.md 2>/dev/null | head -1 || true)"; fi
[[ -n "${file:-}" && -f "$file" ]] || { echo "worklist not found: $arg" >&2; exit 2; }
today="$(date +%F)"
case "$file" in */_archive/*) echo "worklist already archived: $file" >&2; exit 2;; esac

# --- the two refusals, BEFORE any mutation — SWEEP work-lists only ---
# A plain work-list (audit kickoff, a chain of plans) keeps its old close: its emergent
# section is a class-(b) record, not a queue the run owes, and aidex-audit calls this
# script that way today. The sweep is where an unanswered owner row or an unreconciled
# deferral means work silently lost, so that is where the refusal lives.
sweep=0; grep -qE '^mode:[[:space:]]*["'"'"']?sweep["'"'"']?[[:space:]]*$' "$file" && sweep=1
BACKLOG="$ROOT/.context/backlog"
item_file() {  # item_file <BL-id> -> path in backlog/ or backlog/_archive/ (or empty)
  local f
  for f in "$BACKLOG"/*.md "$BACKLOG"/_archive/*.md "$BACKLOG"/_deferred/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$f")" == "$1" ]] && { printf '%s' "$f"; return 0; }
  done
  # explicit: a no-match ends on a false `[[ ]] &&`, and under `set -e` the caller's
  # `f="$(item_file …)"` would kill the script on the first id it cannot find
  return 0
}
owner_open=""
while IFS= read -r line; do
  id="$(grep -oE '\bBL-[0-9]+\b' <<<"$line" | head -1 || true)"; [[ -n "$id" ]] || continue
  f="$(item_file "$id")"; [[ -n "$f" ]] || continue
  rows="$(awk 'BEGIN{s=0} /^## /{s=($0 ~ /^## Verification[[:space:]]*$/)} s && /^\|/ {
      l=$0; sub(/^\|/,"",l); sub(/\|[[:space:]]*$/,"",l); n=split(l,c,"|")
      for(i=1;i<=n;i++){gsub(/^[[:space:]]+|[[:space:]]+$/,"",c[i])}
      if (c[1]=="owner" && c[3]=="") print "    - " id_ ": " c[2] }' id_="$id" "$f")"
  [[ -z "$rows" ]] || owner_open="$owner_open
$rows"
done < <(grep -E '^[0-9]+\. \[[ x]\] .*<!-- ref: backlog -->' "$file" || true)
# `[[ -n ]]`-free: an empty section is fine; an unchecked deferral with no BL-NNN / CLOSE: is not
unreconciled="$(awk '/^## Deferred/{s=1; next} /^## /{s=0} s && /^- \[ \]/' "$file" | grep -v -E 'BL-[0-9]+|CLOSE:' || true)"
if [[ $sweep -eq 1 && ( -n "$owner_open" || -n "$unreconciled" ) ]]; then
  if [[ $force -eq 0 ]]; then
    echo "close refused for $(basename "$file"):" >&2
    [[ -z "$owner_open" ]] || { echo "  owner rows still unanswered (the owner has not looked; closing would convert outstanding into done):$owner_open" >&2; }
    [[ -z "$unreconciled" ]] || { echo "  unreconciled deferrals (name a BL-NNN on the line, or write CLOSE: <reason>):" >&2; printf '%s\n' "$unreconciled" | sed 's/^/    /' >&2; }
    echo "  --force closes anyway and records what it overrode" >&2
    exit 2
  fi
  echo "FORCED close of $(basename "$file") — overriding:" >&2
  [[ -z "$owner_open" ]] || echo "  unanswered owner rows:$owner_open" >&2
  [[ -z "$unreconciled" ]] || { echo "  unreconciled deferrals:" >&2; printf '%s\n' "$unreconciled" | sed 's/^/    /' >&2; }
  { printf -- '\n- Closed %s (%s) with --force, overriding:' "$today" "$status"
    [[ -z "$owner_open" ]] || printf ' unanswered owner rows —%s' "$(printf '%s' "$owner_open" | tr '\n' ' ' | tr -s ' ')"
    [[ -z "$unreconciled" ]] || printf ' unreconciled deferrals — %s' "$(printf '%s' "$unreconciled" | tr '\n' ' ' | tr -s ' ')"
    printf '\n'; } >> "$file"
fi

sed -i.bak -E "s/^status: .*/status: $status/" "$file" && rm -f "$file.bak"
sed -i.bak -E "s/^updated: .*/updated: $today/" "$file" && rm -f "$file.bak"

# surface any still-open upstream refs for manual closure propagation.
# `|| true`: grep exits 1 when a queue has only inline refs — without it,
# pipefail+errexit killed the script here, AFTER the status mutation above.
open_refs="$( (grep -oE '<!-- ref: (backlog|plan|audit) -->' "$file" || true) | wc -l | tr -d ' ')"
[[ "$open_refs" -gt 0 ]] && echo "note: $open_refs tracked upstream ref(s) — run reconcile.sh for closure propagation" >&2

# archive on close (D-10): the `worklist/<file>` cross-ref keeps resolving via _archive/
mkdir -p "$WL_DIR/_archive"
dest="$WL_DIR/_archive/$(basename "$file")"
[[ -e "$dest" ]] && { echo "archive collision: $dest already exists" >&2; exit 2; }
mv "$file" "$dest"
echo "CLOSED $dest"
