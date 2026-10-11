#!/usr/bin/env python3
"""Tests for subagent-poll-guard.py decide(). Run: python3 hooks/test-subagent-poll-guard.py"""
import importlib.util, os, sys

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "subagent-poll-guard.py")
spec = importlib.util.spec_from_file_location("subagent_poll_guard", HOOK)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
decide = mod.decide

SUB = {"agent_id": "a1", "agent_type": "impl-opus"}
cases = [
    ("until loop in a subagent is denied", {**SUB, "tool_input": {"command": "until [ -f out.txt ]; do sleep 5; done"}}, True),
    ("until grep poll is denied", {**SUB, "tool_input": {"command": 'until grep -q "^rc=" log; do sleep 15; done; tail log'}}, True),
    ("while-sleep poll is denied", {**SUB, "tool_input": {"command": "while pgrep -f run-all.sh >/dev/null; do sleep 10; done"}}, True),
    ("until without sleep is allowed", {**SUB, "tool_input": {"command": "until make; do make clean; done"}}, False),
    ("plain test run is allowed", {**SUB, "tool_input": {"command": "bash tests/run-all.sh"}}, False),
    ("word until inside a string is allowed", {**SUB, "tool_input": {"command": "grep -n 'until' file.md; sleep 1"}}, False),
    ("main session is never touched", {"tool_input": {"command": "until [ -f x ]; do sleep 5; done"}}, False),
    ("backgrounded command in a subagent is allowed", {**SUB, "tool_input": {"command": "npm run dev", "run_in_background": True}}, False),
]
fails = 0
for name, data, want in cases:
    got = decide(data) is not None
    if got != want:
        fails += 1
        print(f"FAIL {name}: want deny={want}, got deny={got}")
print(f"{len(cases) - fails}/{len(cases)} passed")
sys.exit(1 if fails else 0)
