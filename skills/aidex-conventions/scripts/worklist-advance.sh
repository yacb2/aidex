#!/usr/bin/env bash
# worklist-advance.sh — mark the current head item done, print the next.
#
# This is what execution calls between items instead of asking "what next?".
#
# Usage:
#   worklist-advance.sh <slug-or-path>                 # complete head, print next
#   worklist-advance.sh <slug-or-path> --append "<kind:label>"   # add class-(b) emergent
#   worklist-advance.sh <slug-or-path> --peek          # print next without completing
#   worklist-advance.sh <slug-or-path> --commit <sha>  # resolving commit(s) for the head
#                                                      # item being closed (repeatable)
#   worklist-advance.sh <slug-or-path> --sweep         # sweep mode (or `mode: sweep` in
#                                                      # the worklist's front-matter)
#
# Prints the next unchecked queue item, or "DONE" when the queue is drained.
#
# Sweep mode drives the item lifecycle instead of running beside it: a plain advance
# first CLOSES the head via `close-item.sh --sweep <BL-id>` when its ref is `backlog`
# (inheriting the proof refusal — the queue cannot advance past an unproven item; the
# box stays unticked and this exits with close-item's code), then ticks the box, then
# STARTS the next backlog item via `start-item.sh`. The plain form is unchanged: a
# worklist ordering plans and audits has no item lifecycle to drive, and `--append`
# stays purely additive in both modes.
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
[[ -n "$arg" ]] || { echo "usage: worklist-advance.sh <slug-or-path> [--append <kind:label>] [--peek]" >&2; exit 2; }

append="" peek=0 sweep=0; commits=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --append) append="$2"; shift 2;;
    --commit) commits+=(--commit "$2"); shift 2;;
    --peek)   peek=1; shift;;
    --sweep)  sweep=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

# `|| true`: ls exits 2 on no match, which pipefail+errexit would turn into a
# silent exit 1 before the not-found diagnostic below ever runs.
if [[ -f "$arg" ]]; then file="$arg"; else file="$(ls "$WL_DIR/"*"$arg"*.md 2>/dev/null | head -1 || true)"; fi
[[ -n "${file:-}" && -f "$file" ]] || { echo "worklist not found: $arg" >&2; exit 2; }
today="$(date +%F)"
# quotes allowed: validate-worklist.py strips them, so `mode: "sweep"` validates and
# must mean sweep here too, or the queue silently advances past unproven work
grep -qE '^mode:[[:space:]]*["'"'"']?sweep["'"'"']?[[:space:]]*$' "$file" && sweep=1

BACKLOG_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-backlog/scripts" && pwd -P)"
ref_kind() { sed -nE 's/.*<!-- ref: ([a-z]+) -->.*/\1/p' <<<"$1"; }
bl_id()    { grep -oE '\bBL-[0-9]+\b' <<<"$1" | head -1 || true; }
item_where() {  # item_where <BL-id> -> active | archived | deferred | (empty)
  local d f
  for d in "" "_archive/" "_deferred/"; do
    for f in "$ROOT/.context/backlog/$d"*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$f")" == "$1" ]] || continue
      case "$d" in "") echo active;; _archive/) echo archived;; _deferred/) echo deferred;; esac; return 0
    done
  done
  return 0   # no match is an answer (empty), never a failed assignment under set -e
}

# append a class-(b) emergent item (no prompt, no re-ask). Appending is purely
# additive — it does NOT complete the current head (distinct semantics).
#
# In SWEEP mode a `backlog:` append joins the NUMBERED queue as its last item (marked
# `emergent`): the numbered queue is the only thing the walk reads, so an emergent item
# left in the unordered section would be recorded and never worked (found by review
# 2026-08-27). The report counts the `emergent` markers against queue-size-at-kickoff.
if [[ -n "$append" ]]; then
  kind="${append%%:*}"; label="${append#*:}"
  if [[ "$sweep" -eq 1 && "$kind" == "backlog" ]]; then
    last="$(grep -nE '^[0-9]+\. \[[ x]\] ' "$file" | tail -1 || true)"
    line_no="${last%%:*}"; num="${last#*:}"; n=$(( ${num%%.*} + 1 ))
    # insert after the last numbered line so the queue stays contiguous
    awk -v at="$line_no" -v row="$n. [ ] $label   <!-- ref: backlog --> <!-- emergent -->" 'NR==at{print; print row; next} {print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    printf -- '- [ ] %s   <!-- ref: %s -->\n' "$label" "$kind" >> "$file"
  fi
  sed -i.bak -E "s/^updated: .*/updated: $today/" "$file" && rm -f "$file.bak"
fi

# complete the first unchecked numbered queue item — only on a plain advance
# (not on --peek, not on --append). `|| true`: grep exits 1 when none remain.
if [[ "$peek" -eq 0 && -z "$append" ]]; then
  head_line="$(grep -nE '^[0-9]+\. \[ \] ' "$file" | head -1 | cut -d: -f1 || true)"
  if [[ -n "$head_line" ]]; then
    head_text="$(sed -n "${head_line}p" "$file")"
    # Sweep: the head is closed BEFORE its box is ticked, so a refusal (no proof) leaves
    # the queue exactly where it was. A backlog ref with no BL-id in its label is a
    # queue-authoring error, not something to tick past silently.
    if [[ "$sweep" -eq 1 && "$(ref_kind "$head_text")" == "backlog" ]]; then
      id="$(bl_id "$head_text")"
      [[ -n "$id" ]] || { echo "sweep: head item carries ref: backlog but no BL-NNN id: $head_text" >&2; exit 2; }
      # Where is the item? Closed out of band → tick past, saying so. Deferred → tick
      # past with a warning (it is blocked, not unproven). Absent → a queue-authoring
      # error. Only an ACTIVE item goes through the proof refusal — otherwise every
      # later advance repeated "not closed" with the wrong diagnosis and no way out.
      where="$(item_where "$id")"
      case "$where" in
        active)
          # `rc=$?` on its own line after the call — never inside `if !`, where $? is
          # the negated test's 0 and the refusal would exit 0 (caught by the wiring test).
          # `--commit` is forwarded: without it every sweep-closed item carried
          # `commits: ""` and the report had nothing to count (BL-576/637, 2026-08-28)
          rc=0; bash "$BACKLOG_SCRIPTS/close-item.sh" "$id" --sweep ${commits[@]+"${commits[@]}"} >/dev/null || rc=$?
          if [[ $rc -ne 0 ]]; then
            echo "sweep: $id was not closed — the queue does not advance past an unproven item" >&2
            exit "$rc"
          fi ;;
        archived) echo "sweep: $id is already closed (out of band) — ticking past it" >&2 ;;
        deferred) echo "sweep: warning — $id is deferred (blocked), not closed; ticking past it" >&2 ;;
        *) echo "sweep: $id is not in backlog/, _archive/ or _deferred/ — fix the queue line" >&2; exit 2 ;;
      esac
    fi
    sed -i.bak "${head_line}s/\[ \]/[x]/" "$file" && rm -f "$file.bak"
    sed -i.bak -E "s/^updated: .*/updated: $today/" "$file" && rm -f "$file.bak"
  fi
fi

# print the next still-unchecked numbered queue item, or DONE
next="$(grep -E '^[0-9]+\. \[ \] ' "$file" | head -1 || true)"
if [[ -n "$next" ]]; then
  # Sweep: opening the next item is the transition to `doing` and, for type: bug, the
  # RED->GREEN route — worklist-advance used to only NAME the next item, and items were
  # worked with `status: open` and closed out of band.
  if [[ "$sweep" -eq 1 && "$peek" -eq 0 && -z "$append" && "$(ref_kind "$next")" == "backlog" ]]; then
    id="$(bl_id "$next")"
    if [[ -n "$id" ]]; then
      rc=0; bash "$BACKLOG_SCRIPTS/start-item.sh" "$id" >/dev/null || rc=$?
      # a start that failed is not a started item: say so and stop, rather than let
      # the run believe the item is `doing` (found by review 2026-08-27)
      [[ $rc -eq 0 ]] || { echo "sweep: could not start $id (exit $rc) — the head was closed and ticked; fix the queue line and re-run --peek" >&2; exit 2; }
    fi
  fi
  echo "$next"
else echo "DONE"; fi
