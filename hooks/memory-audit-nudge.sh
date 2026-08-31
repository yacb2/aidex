#!/bin/sh
# SessionStart hook — say once that this project's memory has drifted for a month.
#
# It reports; it does not audit. `/aidex memory` decides what to do about it.
#
# This runs on EVERY session start in EVERY project, so silence is the common case and
# the design is built around it: no stamp directory, no memory directory, no drift, or
# an already-nudged session all exit before doing any work. Both conditions are required
# before it speaks — a stale stamp over an unchanged directory is silent, and a changed
# directory under a fresh stamp is silent — because a nudge that fires on either alone
# becomes the thing people mute.
#
# Fields, from the probe record in ~/.claude/scripts/handoff-session-start.sh (verified
# live on 2.1.235, not taken from the docs):
#   systemMessage      shown to the user at session start — this is the one we want
#   additionalContext  goes to Claude's context and is invisible to the user
# SessionStart stdin carries session_id, cwd, hook_event_name and source.
#
# Fails open and silent on every path: no jq, no cwd, malformed stamp -> exit 0.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
[ -n "$CWD" ] || exit 0

# The slug is resolved FORWARD from cwd, never decoded backwards from a directory name.
# Decoding is lossy in three directions at once — `echo-lab-ws` may be `echo_lab_ws`,
# `--claude` is `/.claude`, and `bindery-press` really does keep its dash — and on
# 2026-08-31 guessing it wrong resolved a slug to an existing but WRONG directory, with
# every check then reporting against it. Going forward from a path we already have, and
# keeping only the candidate that exists on disk, has no such failure mode.
#
# cwd is not always the project root. In a split-repo `_ws` workspace people work in
# `frontend/` or `backend/`, and the exact-cwd slug for those does not exist — so the
# nudge was silent precisely where the work happens. It walks upward to find the project.
#
# The walk STOPS BEFORE $HOME, deliberately. `~/.claude/projects/-Users-<user>/memory` is
# a real memory directory (sessions started in the home directory), so an unbounded walk
# would make every session in any non-project directory — Downloads, a scratch dir —
# nudge about the user-level memory. An exact cwd of $HOME still matches, because the
# exact form is tried before the walk begins.
MEMDIR=""
DIR="$CWD"
FIRST=1
while [ -n "$DIR" ] && [ "$DIR" != "/" ]; do
  # $HOME is only ever matched as an EXACT cwd, never as an ancestor. Walking through it
  # would make every session in Downloads, or any scratch directory, nudge about the
  # user-level memory that lives under the home directory's own slug.
  if [ "$FIRST" -eq 0 ] && [ "$DIR" = "$HOME" ]; then
    break
  fi
  for CAND in "$(printf '%s' "$DIR" | tr '/' '-')" \
              "$(printf '%s' "$DIR" | tr '_' '-' | tr '/' '-')"; do
    if [ -d "$HOME/.claude/projects/$CAND/memory" ]; then
      MEMDIR="$HOME/.claude/projects/$CAND/memory"
      SLUG="$CAND"
      break 2
    fi
  done
  FIRST=0
  DIR=$(dirname "$DIR")
done
[ -n "$MEMDIR" ] || exit 0

# One notice per project per session. Without it the line repeats on every resume of a
# session that has already been told, which is how a useful signal becomes noise.
STATE_DIR="$HOME/.claude/tmp"
mkdir -p "$STATE_DIR" 2>/dev/null
find "$STATE_DIR" -maxdepth 1 -name 'mem-nudge-*' -mtime +7 -delete 2>/dev/null
STATE_FILE="$STATE_DIR/mem-nudge-${SESSION:-unknown}-$SLUG"
[ -f "$STATE_FILE" ] && exit 0

# The digest is count + newest mtime + total size. Never a content hash: this runs on
# every session start and must stay sub-millisecond. Size is in there because count and
# mtime alone miss an edit that replaces a file without changing either — and Phases 6-8
# of the cleanup rewrite memories in place, which is exactly that shape.
DIGEST=$(find "$MEMDIR" -maxdepth 1 -name '*.md' -type f -exec stat -f '%m %z' {} \; 2>/dev/null \
  | awk '{n++; s+=$2; if ($1>m) m=$1} END {printf "%d:%d:%d", n+0, m+0, s+0}')
case "$DIGEST" in ''|0:0:0) exit 0 ;; esac          # empty directory: nothing to nudge
COUNT=${DIGEST%%:*}

STAMP="$HOME/.claude/aidex/memory-audit-stamp/$SLUG.json"
NOW=$(date +%s)
if [ -f "$STAMP" ]; then
  STAMP_AT=$(jq -r '.at // empty' "$STAMP" 2>/dev/null)
  STAMP_DIGEST=$(jq -r '.digest // empty' "$STAMP" 2>/dev/null)
  # A stamp we cannot read is not a fresh stamp, but it is also not evidence of drift.
  # Staying silent is the safe reading: the audit itself will rewrite it.
  case "$STAMP_AT" in ''|*[!0-9]*) exit 0 ;; esac
  AGE_DAYS=$(( (NOW - STAMP_AT) / 86400 ))
  [ "$AGE_DAYS" -lt 30 ] && exit 0                  # fresh stamp: silent, changed or not
  [ "$DIGEST" = "$STAMP_DIGEST" ] && exit 0         # stale stamp, unchanged: silent
  WHEN="last audited ${AGE_DAYS}d ago"
else
  # An absent stamp over a non-empty directory counts as stale — it has never been
  # audited — but it still has to have changed to be worth a line, and with no stamp
  # there is nothing to compare against, so first sight is the drift.
  WHEN="never audited"
fi

printf '%s' "$DIGEST" > "$STATE_FILE" 2>/dev/null

jq -n --arg m "Memory: $COUNT file(s) in this project, $WHEN. Run /aidex memory to review them." \
  '{hookSpecificOutput: {hookEventName: "SessionStart", systemMessage: $m}}'
exit 0
