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

# Shared resolver (find_project_root in _lib.sh) — never a private one or git rev-parse; see its header.
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

# resolve_worklist (in _lib.sh) skips -report companions and exits 2 on an ambiguous slug.
file="$(resolve_worklist "$WL_DIR" "$arg")"
[[ -n "${file:-}" && -f "$file" ]] || { echo "worklist not found: $arg" >&2; exit 2; }
# Every write below is a read-modify-write of the whole file, so two runs at once
# (register-item.sh --origin sweep appends one per registration) lost rows or emptied the
# list (c19). One kernel lock per work-list (lock_take, shared with worklist-close.sh)
# serialises them for the rest of this run, and every read of the list below runs under it:
# the front matter and `mode: sweep` read before it came from a list another writer was
# rewriting. It has no stale state: a killed run's lock goes with its process, so there is
# no age-based takeover (the mkdir lock it replaces let two waiters take one stale lock
# together and truncated the list). A sweep advance holds it through close-item +
# start-item (~2 s on a 790-item backlog); --peek reads only. AIDEX_WL_LOCK_WAIT: seconds.
if [[ -n "$append" || "$peek" -eq 0 ]]; then
  lock="$(wl_lock_file "$file")" || exit 2
  lock_take "$lock" "${AIDEX_WL_LOCK_WAIT:-30}" || { echo "error: could not lock $file; nothing written" >&2; exit 2; }
  # a close that held the lock while this run waited has moved the list away
  [[ -f "$file" ]] || { echo "worklist was closed/archived while waiting: $file; nothing written" >&2; exit 2; }
fi

# archived-ness from the resolved directory (wl_is_archived, _lib.sh)
wl_is_archived "$file" "$WL_DIR" && { echo "worklist already archived: $file" >&2; exit 2; }
# no front matter: refused here, before the append, the tick or the stamp below writes anything
has_front_matter "$file" || { echo "no front matter in $file" >&2; exit 2; }
today="$(date +%F)"
wl_is_sweep "$file" && sweep=1

BACKLOG_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../backlog/scripts" && pwd -P)"
ref_kind() { sed -nE 's/.*<!-- ref: ([a-z]+) -->.*/\1/p' <<<"$1"; }
bl_id()    { grep -oE '\bBL-[0-9]+\b' <<<"$1" | sed -n 1p || true; }
item_where() {  # item_where <BL-id> -> active | archived | deferred | (empty)
  local f; f="$(bl_item_file "$ROOT/.context/backlog" "$1")"
  [[ -n "$f" ]] || return 0   # no match is an answer (empty), never a failed assignment under set -e
  case "$(basename "$(dirname "$f")")" in _archive) echo archived;; _deferred) echo deferred;; *) echo active;; esac
}

# An emergent that is ALREADY deferred is appended already-deferred (BL-263). It is
# queued so it is not lost, but it is blocked — cross-repo, waiting on an owner — and
# nothing downstream should try to work it. Saying so here is what makes the queue line
# honest at the moment it is written, rather than at the advance that trips over it.
# Said only once the row is written: a refused append printed it and then "was NOT
# appended".
kind="${append%%:*}"; label="${append#*:}"; mark="" said=""
# a real CR/LF in the label split the queue row across lines: each run folds to one space (BL-805)
label="$(printf '%s' "$label" | tr -s '\r\n' '\n' | tr '\n' ' ')"
if [[ -n "$append" && "$sweep" -eq 1 && "$kind" == "backlog" ]]; then
  aid="$(bl_id "$label")"
  if [[ -n "$aid" && "$(item_where "$aid")" == "deferred" ]]; then
    mark=" <!-- deferred -->"
    said="sweep: $aid is deferred (blocked) — appended to the queue already deferred, it will be ticked past, not worked"
  fi
fi

# append a class-(b) emergent item (no prompt, no re-ask). Appending is purely
# additive — it does NOT complete the current head (distinct semantics).
#
# In SWEEP mode a `backlog:` append joins the NUMBERED queue as its last item (marked
# `emergent`): the numbered queue is the only thing the walk reads, so an emergent item
# left in the unordered section would be recorded and never worked (found by review
# 2026-08-27). The report counts the `emergent` markers against queue-size-at-kickoff.
if [[ -n "$append" ]]; then
  if [[ "$sweep" -eq 1 && "$kind" == "backlog" ]]; then
    last="$(wl_queue_grep "$file" "$WL_QUEUE_ITEM" | tail -1)"
    # no queue item to insert after: the row would be dropped and `updated` stamped over
    # the loss (c17), or — a numbered line elsewhere — land outside `## Queue` — refuse
    # before anything is written
    [[ -n "$last" ]] || { echo "sweep: no numbered queue item in $file to append after — '$label' was NOT appended" >&2; exit 2; }
    line_no="${last%%:*}"; num="${last#*:}"; n=$(( ${num%%.*} + 1 ))
    # insert after the last numbered line so the queue stays contiguous; a unique temp,
    # copied back so the work-list keeps its own mode (a temp gets the umask's). The row
    # travels through ENVIRON, as in set_front_matter: `awk -v` turns a literal `\n` in a
    # title into a newline and splits the queue line (BL-778)
    tmp="$(mktemp "$file.XXXXXX")"
    WL_ROW="$n. [ ] $label   <!-- ref: backlog --> <!-- emergent -->$mark" \
      awk -v at="$line_no" 'NR==at{print; print ENVIRON["WL_ROW"]; next} {print}' "$file" > "$tmp" \
      || { rm -f "$tmp"; echo "sweep: could not insert into $file — '$label' was NOT appended" >&2; exit 2; }
    cat "$tmp" > "$file"; rm -f "$tmp"
    [[ -z "$said" ]] || echo "$said" >&2
  else
    printf -- '- [ ] %s   <!-- ref: %s -->\n' "$label" "$kind" >> "$file"
  fi
  set_front_matter "$file" "updated=$today" || { echo "no front matter in $file" >&2; exit 2; }
fi

# complete the first unchecked numbered queue item — only on a plain advance
# (not on --peek, not on --append). Read from `## Queue` only (wl_queue_grep).
if [[ "$peek" -eq 0 && -z "$append" ]]; then
  head_line="$(wl_queue_grep "$file" "$WL_QUEUE_OPEN" | sed -n 1p | cut -d: -f1)"
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
          rc=0; close_out="$(bash "$BACKLOG_SCRIPTS/close-item.sh" "$id" --sweep ${commits[@]+"${commits[@]}"})" || rc=$?
          # 4 = archived and index written, but the id guard found a duplicate/nonconforming id
          if [[ $rc -eq 4 ]]; then
            echo "sweep: $id closed; index rebuilt, but reindex reported an id problem (exit 4)" >&2; rc=0
          fi
          if [[ $rc -ne 0 ]]; then
            echo "sweep: $id was not closed — the queue does not advance past an unproven item" >&2
            exit "$rc"
          fi
          # parked (owner row unanswered) is handled, not done: the tick alone read as
          # done in the list (2026-08-28) — the line says what actually happened
          if [[ "$close_out" == parked:* ]]; then
            sed -i.bak "${head_line}s/[[:space:]]*\$/   <!-- parked: awaiting owner -->/" "$file" && rm -f "$file.bak"
            echo "sweep: $id is parked (awaiting owner) — ticked as handled, not closed" >&2
          fi ;;
        archived) echo "sweep: $id is already closed (out of band) — ticking past it" >&2 ;;
        deferred) echo "sweep: warning — $id is deferred (blocked), not closed; ticking past it" >&2 ;;
        *) echo "sweep: $id is not in backlog/, _archive/ or _deferred/ — fix the queue line" >&2; exit 2 ;;
      esac
    fi
    sed -i.bak "${head_line}s/\[ \]/[x]/" "$file" && rm -f "$file.bak"
    set_front_matter "$file" "updated=$today" || { echo "no front matter in $file" >&2; exit 2; }
  fi
fi

# print the next still-unchecked numbered queue item, or DONE
next="$(wl_queue_grep "$file" "$WL_QUEUE_OPEN" | sed -n 1p)"; next="${next#*:}"
if [[ -n "$next" ]]; then
  # Sweep: opening the next item is the transition to `doing` and, for type: bug, the
  # RED->GREEN route — worklist-advance used to only NAME the next item, and items were
  # worked with `status: open` and closed out of band.
  if [[ "$sweep" -eq 1 && "$peek" -eq 0 && -z "$append" && "$(ref_kind "$next")" == "backlog" ]]; then
    id="$(bl_id "$next")"
    # A DEFERRED item is not started (BL-263). It used to be handed to start-item.sh
    # like any other, and the walk then died on `could not start` — the same blockage
    # under a message that reads like a broken queue line. The item is blocked; the
    # queue is not. The next advance ticks past it with the existing warning.
    if [[ -n "$id" && "$(item_where "$id")" == "deferred" ]]; then
      echo "sweep: $id is deferred (blocked) — not started; the next advance ticks past it" >&2
      id=""
    fi
    if [[ -n "$id" ]]; then
      rc=0; bash "$BACKLOG_SCRIPTS/start-item.sh" "$id" >/dev/null || rc=$?
      # a start that failed is not a started item: say so and stop, rather than let
      # the run believe the item is `doing` (found by review 2026-08-27)
      # The advice names start-item.sh: --peek never starts an item (c18).
      [[ $rc -eq 0 ]] || { echo "sweep: could not start $id (exit $rc) — the head was closed and ticked; fix the queue line, then start that item with backlog/scripts/start-item.sh <its BL-id>" >&2; exit 2; }
    fi
  fi
  echo "$next"
else echo "DONE"; fi
