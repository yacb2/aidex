#!/usr/bin/env python3
"""PreToolUse/Bash: refuse sleep-polling loops inside subagents.

A delegate that runs `until ...; do sleep N; done` (or the `while` form) sits on the Bash
timeout and reads as a hung run; most mid-run stalls of delegates come from the delegate
blocked on its own Bash call. The guard denies such a command when the call comes from a
subagent (the payload carries `agent_id`). The main session is never touched.
"""
import json, re, sys

POLL = re.compile(r"(^|[;&|(\s])(until|while)\s[^;]*;\s*do\b[^;]*\bsleep\b", re.S)

REASON = (
    "Sleep-polling loops are refused in subagents: they sit on the Bash timeout and read "
    "as a hung delegate. Run the command in the foreground with a timeout that covers it, "
    "and run only the tests the brief names or the ones your change affects."
)


def decide(data):
    if not data.get("agent_id"):
        return None
    if POLL.search(data.get("tool_input", {}).get("command", "")):
        return REASON
    return None


if __name__ == "__main__":
    reason = decide(json.load(sys.stdin))
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}))
