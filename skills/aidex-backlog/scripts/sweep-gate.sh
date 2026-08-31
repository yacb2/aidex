#!/usr/bin/env bash
# sweep-gate.sh — the end-of-sweep boundary gate, run from the project's testing
# profile instead of from a habit.
#
# NOT `sweep.sh`. That sibling is the D-10 archive sweep (batch-archive of done/dropped
# items) and has nothing to do with this file; a grep for `sweep` in this directory lands
# on it first.
#
# What it makes impossible (2026-08-26): a `pytest | tail` pipeline reported exit 0 over
# five real failures, and 55 of 66 E2E invocations in the measured sweep produced no
# verdict at all. Here each leg's exit code is PIPESTATUS[0] of the command itself, and a
# leg whose output carries no recognisable test count is `count=?` — which makes the
# verdict FAIL, never PASS. A runner that bails early having run nothing cannot go green.
#
# Usage:
#   sweep-gate.sh                       # every leg: backend, frontend, build, e2e
#   sweep-gate.sh --only <leg> [...]    # a subset (repeatable)
#   sweep-gate.sh --json                # the same rows as a JSON array (for sweep-report.sh)
#   sweep-gate.sh --only <leg> --from-log <file>          # any leg, not only e2e: a backend
#                                                 # rerun on a quiet host goes in the same way
#   sweep-gate.sh --only <leg> --from-log <file> --exit <rc>   # a log written by hand (a rerun
#                                                 # on a quiet host): the marker is missing,
#                                                 # the exit is yours, the count is the log's
#                                       # score a log a DETACHED run wrote (see below)
#
# Reads from .context/testing-profile.md: backend_suite_cmd, frontend_suite_cmd,
# build_cmd, e2e_suite_cmd, e2e_detached. A missing key for a leg that is about to run
# is exit 2, naming the key — a gate over an unbound leg is the one we already have.
# Optional per leg: `<leg>_pre_cmd`, run immediately before the leg and into the same
# log. A non-zero pre-command fails the leg and the leg does not run.
#
# Output — one machine-readable line per leg, then the verdict:
#   leg=backend exit=0 count=1284
#   leg=build exit=0 count=-            (build has no test count; exit code only)
#   leg=e2e exit=0 count=?              <- countless: verdict is FAIL
#   verdict=FAIL legs=4 failed=1
#
# Detached legs are the CALLER's job, not this script's: when `e2e_detached: true` the e2e
# leg is not run inline — the script prints the exact detached invocation and the log
# path, so the foreground ceiling cannot be hit from inside the gate. The invocation
# appends `sweep-gate-exit=<rc>` to the log; `--from-log` reads that marker back and
# scores the leg. Until it is scored the verdict is PENDING (exit 3), never PASS.
#
# Exit: 0 PASS · 1 FAIL · 2 usage / missing key · 3 PENDING (a detached leg not yet scored)

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

ALL_LEGS=(backend frontend build e2e)
ONLY=() JSON=0 FROM_LOG="" EXIT_RC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)     [[ $# -ge 2 ]] || die "--only needs a leg"; ONLY+=("$2"); shift 2 ;;
    --exit)     [[ $# -ge 2 ]] || die "--exit needs a code"; EXIT_RC="$2"; shift 2 ;;
    --json)     JSON=1; shift ;;
    --from-log) [[ $# -ge 2 ]] || die "--from-log needs a file"; FROM_LOG="$2"; shift 2 ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)          die "unknown option: $1" ;;
  esac
done
for l in "${ONLY[@]:-}"; do
  [[ -z "$l" ]] && continue
  case "$l" in backend|frontend|build|e2e) ;; *) die "unknown leg: $l (backend|frontend|build|e2e)" ;; esac
done
if [[ -n "$FROM_LOG" ]]; then
  [[ ${#ONLY[@]} -eq 1 ]] || die "--from-log scores exactly one leg: pass a single --only <leg>"
  [[ -f "$FROM_LOG" ]] || die "--from-log: no such file: $FROM_LOG"
  [[ -z "$EXIT_RC" || "$EXIT_RC" =~ ^[0-9]+$ ]] || die "--exit must be a number: $EXIT_RC"
else
  [[ -z "$EXIT_RC" ]] || die "--exit only accompanies --from-log"
fi
LEGS=("${ALL_LEGS[@]}"); [[ ${#ONLY[@]} -gt 0 ]] && LEGS=("${ONLY[@]}")

ROOT="$(find_project_root)"
PROFILE="$ROOT/.context/testing-profile.md"
[[ -f "$PROFILE" ]] || die "no testing profile at $PROFILE — the gate reads its commands from it (aidex-coverage/references/14-testing-profile.md)"

# Front-matter scalar. Quotes stripped, a trailing ` # comment` dropped (so a command
# may not itself contain ` #`); a block scalar (`key: |`) is not a command.
profile_key() {
  awk -v k="$1" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":"{
    sub(/^[^:]*:[[:space:]]*/,""); sub(/[[:space:]]+#.*$/,""); gsub(/^["\x27]|["\x27]$/,""); print; exit}' "$PROFILE"
}
key_for() { case "$1" in backend) echo backend_suite_cmd;; frontend) echo frontend_suite_cmd;; build) echo build_cmd;; e2e) echo e2e_suite_cmd;; esac; }

# Every leg is bound BEFORE any leg runs: a gate that ran two suites and then died on a
# missing key would leave the caller with half a verdict and a log to reinterpret.
# (bash 3.2 on macOS: no associative arrays, so CMD_<leg> variables + indirection.)
cmd_of() { local v="CMD_$1"; printf '%s' "${!v}"; }
for leg in "${LEGS[@]}"; do
  k="$(key_for "$leg")"
  v="$(profile_key "$k")"
  [[ -n "$v" ]] || die "testing-profile.md has no \`$k\` — the $leg leg is unbound (fill the key, or --only the legs that are bound)"
  printf -v "CMD_$leg" '%s' "$v"
done
# An OPTIONAL per-leg command run immediately before the leg, in the same working
# directory and into the same log (BL-265). It exists because the first backend run
# inside a fresh worktree came back `count=?`: stale __pycache__/.pytest_cache reached
# the checkout and xdist's workers disagreed on collection. The gate must not carry
# Python knowledge, so the project declares what to clear —
# `backend_pre_cmd: find . -name __pycache__ -prune -exec rm -rf {} +` — and the gate
# only runs it. Absent is the normal case and changes nothing.
E2E_DETACHED="$(profile_key e2e_detached)"
for leg in "${LEGS[@]}"; do
  printf -v "PRE_$leg" '%s' "$(profile_key "${leg}_pre_cmd")"
done
pre_of() { local v="PRE_$1"; printf '%s' "${!v}"; }

LOG_DIR="$ROOT/_tmp/sweep-gate"; mkdir -p "$LOG_DIR"
# The history is evidence and outlives the run; _tmp/ is deletable without asking.
HIST_DIR="$ROOT/.context/proofs/sweep-gate"; mkdir -p "$HIST_DIR"

# The count is what says the runner ran SOMETHING. Per-runner shapes, last match wins:
#   pytest     "1284 passed"            vitest  "Tests  133 passed"
#   playwright "12 passed (1.2m)"       build   none — the exit code is the whole verdict
count_in() {  # count_in <leg> <log>
  local leg="$1" log="$2" n
  [[ "$leg" == "build" ]] && { echo "-"; return; }
  n="$(grep -oE '(Tests[[:space:]]+)?[0-9]+ passed' "$log" 2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)"
  # "0 passed" with exit 0 is a runner that ran nothing and said so politely — the
  # same incident as printing nothing. Countless, never a count.
  if [[ -n "$n" && "$n" != "0" ]]; then echo "$n"; else echo "?"; fi
}

ROWS=() FAILED=0 PENDING=0
emit_row() { ROWS+=("leg=$1 exit=$2 count=$3 secs=$4"); [[ $JSON -eq 1 ]] || echo "leg=$1 exit=$2 count=$3 secs=$4"; }

for leg in "${LEGS[@]}"; do
  log="$LOG_DIR/$leg.log"
  if [[ -n "$FROM_LOG" ]]; then
    rc="$(grep -oE '^sweep-gate-exit=[0-9]+' "$FROM_LOG" | tail -1 | cut -d= -f2 || true)"
    # `--exit` is the marker for a log that was not written by the printed invocation —
    # a rerun on a quiet host after a load-poisoned leg (2026-08-28). The count still
    # comes from the log, so a leg that ran nothing cannot be scored green by hand.
    [[ -n "$EXIT_RC" ]] && rc="$EXIT_RC"
    [[ -n "$rc" ]] || die "$FROM_LOG carries no \`sweep-gate-exit=<rc>\` marker — the detached run has not finished, or was not launched with the printed invocation (a log written by hand is scored with --exit <rc>)"
    count="$(count_in "$leg" "$FROM_LOG")"; secs="-"
  elif [[ "$leg" == "e2e" && "$E2E_DETACHED" == "true" ]]; then
    # Printed, not run: `sweep-execution-policy.md` §3 made mechanical. The marker line
    # is what --from-log scores; without it a detached run has an exit code nobody kept.
    # the log is CLEARED here: otherwise --from-log on a run nobody launched would score
    # the previous cycle's marker and count, and the leg would go green having run
    # nothing this cycle (found by review 2026-08-27)
    : > "$log"
    printf 'detached: leg=e2e log=%s\n' "$log" >&2
    printf 'detached: run with run_in_background (never a foreground call, never a poll wrapper):\n' >&2
    # The pre-command is chained into the printed invocation rather than run here:
    # a detached leg runs elsewhere, and dropping it would leave the one leg that
    # runs in another process as the only one keeping the stale cache.
    if [[ -n "$(pre_of "$leg")" ]]; then
      printf '  cd %q && ((%s) && (%s)) > %q 2>&1; echo "sweep-gate-exit=$?" >> %q\n' \
        "$ROOT" "$(pre_of "$leg")" "$(cmd_of "$leg")" "$log" "$log" >&2
    else
      printf '  cd %q && (%s) > %q 2>&1; echo "sweep-gate-exit=$?" >> %q\n' "$ROOT" "$(cmd_of "$leg")" "$log" "$log" >&2
    fi
    printf 'detached: then score it: sweep-gate.sh --only e2e --from-log %q\n' "$log" >&2
    emit_row "$leg" pending - -; PENDING=$((PENDING+1)); continue
  else
    # The raw exit of the command itself: NO pipeline at all. The first draft used
    # `… | tee "$log" || true; rc=${PIPESTATUS[0]}` and the `|| true` reset PIPESTATUS —
    # the test's case 2 reported exit 0 over a failing leg, which is the 08-26 incident
    # re-implemented inside the gate meant to stop it. An `if` records the code and
    # keeps `set -e` out of it.
    t0="$(date +%s)"
    rc=0
    # The pre-command opens the log (`>`), the leg appends to it (`>>`): both are
    # evidence, and a pre-command that truncated the leg's own output would hide the
    # count the verdict is made of. A non-zero pre-command FAILS the leg and the leg
    # does not run — running the suite anyway against the state the pre-command
    # failed to clear is the flake this exists to remove, now with a green tick.
    if [[ -n "$(pre_of "$leg")" ]]; then
      printf '# pre_cmd: %s\n' "$(pre_of "$leg")" > "$log"
      # `if ! (...); then rc=$?` reads the NEGATION's status, which is always 0 — the
      # same shape the leg's own run has a comment about, re-made one block above it.
      if ( cd "$ROOT" && bash -c "$(pre_of "$leg")" ) >> "$log" 2>&1; then rc=0; else rc=$?; fi
      if [[ $rc -ne 0 ]]; then
        printf '# pre_cmd FAILED (exit %s) — the %s leg was not run\n' "$rc" "$leg" >> "$log"
      fi
    else
      : > "$log"
    fi
    if [[ $rc -eq 0 ]]; then
      if ( cd "$ROOT" && bash -c "$(cmd_of "$leg")" ) >> "$log" 2>&1; then rc=0; else rc=$?; fi
    fi
    secs=$(( $(date +%s) - t0 ))
    count="$(count_in "$leg" "$log")"
  fi
  emit_row "$leg" "$rc" "$count" "$secs"
  [[ "$rc" == "0" && "$count" != "?" ]] || FAILED=$((FAILED+1))
done

if   [[ $FAILED -gt 0 ]]; then VERDICT=FAIL; RC=1
elif [[ $PENDING -gt 0 ]]; then VERDICT=PENDING; RC=3
else VERDICT=PASS; RC=0; fi

# The JSON form is ALWAYS appended to gate-history.jsonl, one line per run: the report
# reads the rows verbatim and counts how many times the gate had to be re-run.
json_rows() {
  printf '['
  for i in "${!ROWS[@]}"; do
    r="${ROWS[$i]}"
    l="${r#leg=}"; l="${l%% *}"; e="${r#*exit=}"; e="${e%% *}"; c="${r#*count=}"; c="${c%% *}"; s="${r#*secs=}"
    [[ $i -gt 0 ]] && printf ','
    printf '{"leg":"%s","exit":"%s","count":"%s","secs":"%s"}' "$l" "$e" "$c" "$s"
  done
  printf ',{"verdict":"%s","legs":%d,"failed":%d,"pending":%d,"at":"%s"}]\n' "$VERDICT" "${#LEGS[@]}" "$FAILED" "$PENDING" "$(date +%Y-%m-%dT%H:%M:%S)"
}
json_rows >> "$HIST_DIR/gate-history.jsonl"
if [[ $JSON -eq 1 ]]; then
  json_rows
else
  if [[ $PENDING -gt 0 ]]; then echo "verdict=$VERDICT legs=${#LEGS[@]} failed=$FAILED pending=$PENDING"
  else echo "verdict=$VERDICT legs=${#LEGS[@]} failed=$FAILED"; fi
fi
exit $RC
