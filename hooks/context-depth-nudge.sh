#!/bin/sh
# UserPromptSubmit hook — surface context depth once per band. Never blocks.
#
# WHAT IT DOES NOT DO, deliberately: it does not decide whether to hand off, and
# it does not fire one. The retired durability Stop hook (2ca548a, 2026-08-03)
# ran a `claude -p` judge over exactly that class of call — "is this a legitimate
# place to stop?" — and measured 4 real blocks, 0 justified, 4 misfires, every one
# of them on a terminal the policy was supposed to allow. Counting tokens is
# arithmetic and cannot misfire; judging whether a thread is mid-hypothesis is the
# thing that did. So this hook counts, states the number, and stops there.
#
# UserPromptSubmit rather than Stop for two reasons: it fires at the boundary
# where a handoff is cheapest (a new instruction is starting, not a thread being
# cut), and it can inform without blocking — Stop can only act by blocking, which
# is the retired hook's failure mode.
#
# Bands and their justification: .context/research/2026-08-13-session-token-threshold-handoff.md
#   200k  warn    — 1.41x slower than the same session's own sub-100k baseline
#   250k  advise  — marginal knee under the constants that describe deep sessions
#   300k  urgent  — half of all input spend sits above here; slowdown has plateaued
#
# Fails open on every path: no jq, no transcript, malformed JSON -> silent exit 0.

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
[ -n "$TRANSCRIPT" ] || exit 0
[ -f "$TRANSCRIPT" ] || exit 0

# Depth = max over iterations, NOT the top-level usage sum.
#
# Top-level usage SUMS the iterations of a multi-iteration turn: one observed turn
# reported cache_read 1,170,043 against a 1M window because its three iterations
# (584k / 588k / 585k) were added together. That figure is what was billed; it is
# not what occupied the window. Using it here would fire the 300k band at ~100k of
# real depth on any turn that iterated three times.
#
# Bounded to the last 400 lines so the cost does not grow with transcript size —
# these files reach hundreds of MB, and this runs on every prompt.
DEPTH=$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -s -r '
  [ .[]
    | select(.type == "assistant")
    | .message.usage
    | select(. != null)
  ] | last
  | if . == null then 0
    elif ((.iterations // []) | length) > 0 then
      [ .iterations[]
        | (.cache_read_input_tokens // 0)
          + (.cache_creation_input_tokens // 0)
          + (.input_tokens // 0)
      ] | max
    else
      (.cache_read_input_tokens // 0)
        + (.cache_creation_input_tokens // 0)
        + (.input_tokens // 0)
    end
' 2>/dev/null)

case "$DEPTH" in ''|*[!0-9]*) exit 0 ;; esac

if   [ "$DEPTH" -ge 300000 ]; then BAND=3
elif [ "$DEPTH" -ge 250000 ]; then BAND=2
elif [ "$DEPTH" -ge 200000 ]; then BAND=1
else exit 0
fi

# One notice per band per session. Without this it speaks on every prompt for the
# rest of the session, which is how a useful signal becomes noise that gets muted.
STATE_DIR="$HOME/.claude/tmp"
mkdir -p "$STATE_DIR" 2>/dev/null
# One marker per session would otherwise accumulate forever. Only runs on the
# turns that actually cross a band, so at most three times per session.
find "$STATE_DIR" -maxdepth 1 -name 'ctx-band-*' -mtime +7 -delete 2>/dev/null
STATE_FILE="$STATE_DIR/ctx-band-${SESSION:-unknown}"
LAST=0
[ -f "$STATE_FILE" ] && LAST=$(cat "$STATE_FILE" 2>/dev/null)
case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
[ "$BAND" -le "$LAST" ] && exit 0
printf '%s' "$BAND" > "$STATE_FILE"

DEPTH_K=$((DEPTH / 1000))

case "$BAND" in
  1) MSG="Context depth is now ~${DEPTH_K}k tokens. Turns here run about 1.4x slower than this session did below 100k. Nothing to do yet — but if the current thread is close to a natural boundary, that is the cheap moment to hand off." ;;
  2) MSG="Context depth is now ~${DEPTH_K}k tokens — past the point where staying in-session stops paying for itself. Recommended: finish the current step, then hand off at the next boundary (end of a phase, after a commit). Mention this to the user once, in one line, and let them decide; do not hand off on your own." ;;
  3) MSG="Context depth is now ~${DEPTH_K}k tokens. Over half of all input spend sits above this line and the speed loss has plateaued, so continuing here buys nothing a fresh session would not give back. Tell the user plainly, in one line, that a handoff is due and offer to draft the brief. The decision is theirs — do not hand off on your own." ;;
esac

jq -n --arg m "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $m
  }
}'
exit 0
