#!/usr/bin/env bash
# The two tests that launch headless Chrome leave no Chrome behind (BL-495).
#
# Both start Chrome under perl's setpgrp, so Chrome leads its own process group
# and is NOT killed with the test. A test stopped mid-dump (Ctrl-C, a runner's
# timeout, SIGKILL) left a Chrome re-parented to launchd for days: one was found
# alive after 1d22h, 141 MB, with the dead run's /tmp dir still on disk.
#
# Layer: the scripts' process boundary, the lowest one that can see an orphan.
# A fake Chrome stands in for the real one through the existing $AIDEX_CHROME
# seam: it never writes </html>, so the test is always mid-dump when stopped,
# and no browser opens. Two cells per test:
#   - TERM while its Chrome runs  -> that Chrome is gone after the test exits
#   - an orphan from a SIGKILLed earlier run (ppid 1) -> swept at the next start
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TMP="$(mktemp -d /tmp/chrome-cleanup-XXXXXX)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

FAKE="$TMP/fake-chrome"
printf '#!/bin/bash\nsleep 120 &\nwait\n' > "$FAKE"
chmod +x "$FAKE"
trap 'pkill -9 -f "$FAKE" 2>/dev/null; rm -rf "$TMP"' EXIT

wait_for() {  # <seconds> <command...>: poll until the command succeeds
  local i n=$(( $1 * 4 )); shift
  for ((i = 0; i < n; i++)); do "$@" && return 0; sleep 0.25; done
  return 1
}
alive() { pgrep -f -- "$FAKE .*--user-data-dir=$1" > /dev/null; }
gone() { ! alive "$1"; }

for pair in test-composer-functional.sh:composer-fn test-figures-script.sh:figscript; do
  t="${pair%%:*}"; prefix="/tmp/${pair##*:}-"

  # Cell 1: TERM while the test's Chrome is running.
  AIDEX_CHROME="$FAKE" bash "$HERE/$t" > /dev/null 2>&1 &
  tpid=$!
  if wait_for 30 alive "$prefix"; then
    kill -TERM "$tpid"
    wait "$tpid" 2>/dev/null
    wait_for 3 gone "$prefix" || fail "$t: its Chrome outlived the test after TERM"
  else
    kill -9 "$tpid" 2>/dev/null
    fail "$t: never launched the fake Chrome (setup)"
  fi
  pkill -9 -f "$FAKE" 2>/dev/null

  # Cell 2: an orphan left by a SIGKILLed run is swept when the test next starts.
  orphan="$(mktemp -d "${prefix}XXXXXX")"
  ( "$FAKE" --headless=new --user-data-dir="$orphan/profile" > /dev/null 2>&1 & )
  wait_for 3 alive "$orphan/" || fail "$t: could not plant the orphan (setup)"
  AIDEX_CHROME="$FAKE" bash "$HERE/$t" > /dev/null 2>&1 &
  tpid=$!
  wait_for 10 gone "$orphan/" \
    || fail "$t: an orphaned Chrome from an earlier run was not swept at start"
  [[ -d "$orphan" ]] && fail "$t: the orphan's /tmp dir was left on disk"
  kill -TERM "$tpid" 2>/dev/null; wait "$tpid" 2>/dev/null
  pkill -9 -f "$FAKE" 2>/dev/null
  rm -rf "$orphan"
done

[[ "$failures" -eq 0 ]] || { echo "$failures failure(s)"; exit 1; }
echo "OK — both Chrome tests clean up their Chrome on TERM and sweep orphans of killed runs"
