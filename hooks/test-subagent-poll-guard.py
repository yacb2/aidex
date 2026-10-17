#!/usr/bin/env python3
"""Tests for subagent-poll-guard.py. Run: python3 hooks/test-subagent-poll-guard.py"""
import importlib.util, os, sys, time

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "subagent-poll-guard.py")
spec = importlib.util.spec_from_file_location("subagent_poll_guard", HOOK)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
decide = mod.decide

SUB = {"agent_id": "a1", "agent_type": "impl-opus"}


def sub(command, **extra):
    return {**SUB, "tool_input": {"command": command, **extra}}


cases = [
    ("until loop in a subagent is denied", sub("until [ -f out.txt ]; do sleep 5; done"), True),
    ("until grep poll is denied", sub('until grep -q "^rc=" log; do sleep 15; done; tail log'), True),
    ("while-sleep poll is denied", sub("while pgrep -f run-all.sh >/dev/null; do sleep 10; done"), True),
    ("until without sleep is allowed", sub("until make; do make clean; done"), False),
    ("plain test run is allowed", sub("bash tests/run-all.sh"), False),
    ("word until inside a string is allowed", sub("grep -n 'until' file.md; sleep 1"), False),
    ("main session is never touched", {"tool_input": {"command": "until [ -f x ]; do sleep 5; done"}}, False),
    ("backgrounded non-loop command is allowed", sub("npm run dev", run_in_background=True), False),
    ("backgrounded poll is still denied", sub("until [ -s f ]; do sleep 5; done", run_in_background=True), True),
    ("for-sleep poll is denied", sub("for i in 1 2 3; do test -s out && break; sleep 5; done"), True),
    ("statement before sleep in the body is denied", sub("until [ -s f ]; do :; sleep 5; done"), True),
    ("loop quoted inside bash -c is denied", sub("bash -c 'until [ -s f ]; do sleep 5; done'"), True),
    ("multi-line until loop is denied", sub("until [ -s f ]\ndo\n  sleep 5\ndone"), True),
    ("for loop without sleep is allowed", sub("for f in a b; do echo $f; done"), False),
    ("plain sleep with no loop is allowed", sub("sleep 5"), False),
    ("word sleep outside a loop is allowed", sub("grep -n sleep hooks/*.py"), False),
    ("sleep as an argument inside a loop is allowed", sub('for f in hooks/*.py; do grep -c sleep "$f"; done'), False),
    ("sleep after the loop ends is allowed", sub("for f in a b; do echo $f; done; sleep 1"), False),
    # The word `done` as an argument or inside a word does not close the body.
    ("done sentinel path is denied", sub("while true; do test -f out/done && break || sleep 5; done"), True),
    ("done sentinel suffix is denied", sub("while true; do [ -f build.done ] && break || sleep 5; done"), True),
    ("done in a quoted grep pattern is denied", sub("until [ -s f ]; do tail -1 log | grep -q 'All done' && break; sleep 10; done"), True),
    ("done inside a regex is denied", sub("for i in $(seq 30); do grep -q '^done$' st && break; sleep 10; done"), True),
    ("done as a variable is denied", sub('while [ "$done" != 1 ]; do check && done=1; sleep 5; done'), True),
    ("done as a compared value is denied", sub('while true; do status=$(cat s); [ "$status" = done ] && break; sleep 5; done'), True),
    ("done as an echo argument is denied", sub("until [ -s f ]; do echo done; sleep 5; done"), True),
    ("done as an argument before a redirect is denied", sub("until [ -s f ]; do echo done > log; sleep 5; done"), True),
    # Wrappers and paths keep sleep in command position.
    ("sleep behind timeout is denied", sub("until [ -s f ]; do timeout 5 sleep 1; done"), True),
    ("sleep by absolute path is denied", sub("until [ -s f ]; do /bin/sleep 1; done"), True),
    ("arithmetic for loop is denied", sub("for ((i=0; i<30; i++)); do curl -sf localhost:8000 && break; sleep 2; done"), True),
    ("sleep as the while condition is denied", sub("while sleep 5; do pgrep -f run-all.sh || break; done"), True),
    ("bash -c behind a wrapper is denied", sub("timeout 900 bash -c 'until [ -s f ]; do sleep 5; done'"), True),
    ("wrapper option value is not the command", sub("until [ -s f ]; do timeout -s KILL 5 sleep 1; done"), True),
    # A backslash-newline is a blank, not part of a word.
    ("sleep after a line continuation is denied", sub("until curl -sf x; do \\\n  sleep 2; \\\ndone"), True),
    ("sleep after or-continuation is denied", sub("while true; do test -f x && break || \\\n  sleep 5; done"), True),
    ("line-continued loop then sleep after done is allowed", sub("for f in a b; do \\\n  echo $f; \\\ndone\nsleep 2"), False),
    # `}` and `fi` keep command position, so a `done` right after them closes the loop.
    ("done after a brace group closes the loop", sub("for f in a; do { echo $f; } done; sleep 5"), False),
    ("done after fi closes the loop", sub("until x; do if y; then :; fi done; sleep 5"), False),
    # Loop words or sleep inside arguments, comments and other names are not commands.
    ("poll shape in a grep pattern is allowed", sub("for f in t/*.jsonl; do grep -c '; sleep' \"$f\"; done"), False),
    ("poll alternation in a grep pattern is allowed", sub("for f in t/*.jsonl; do grep -cE 'do sleep|; sleep' \"$f\"; done"), False),
    ("and-sleep in a double-quoted pattern is allowed", sub('for f in t/*.jsonl; do cat "$f" | grep -c "&& sleep"; done'), False),
    ("sleep in a comment is allowed", sub("for f in a b; do echo $f; # then sleep\ndone"), False),
    ("sleep.sh is not sleep", sub("for f in a b; do x=1; sleep.sh; done"), False),
    ("loop words in a commit message are allowed", sub('git commit -m "feat(hooks): poll guard denies `for ...; do ...; sleep` loops"'), False),
    ("loop words in a single-quoted message are allowed", sub("git commit -m 'while waiting; do sleep work'"), False),
    ("hash inside a word is not a comment", sub("for x in a b; do echo ${#x}; done; sleep 5"), False),
    ("quoted until then sleep is allowed", sub("grep -c 'until' log; sleep 5"), False),
]

R = mod.REASON
rows = [(n, lambda d=d, w=w: ((decide(d) is not None) == w, f"want deny={w}")) for n, d, w in cases]
rows += [
    ("REASON holds 'Never poll'", lambda: ("Never poll" in R, "missing")),
    ("REASON holds 'running in the background'", lambda: ("running in the background" in R, "missing")),
    ("REASON does not say 'end your turn'", lambda: ("end your turn" not in R, "present: kills a foreground run")),
    ("REASON does not say 'a timeout that covers it'", lambda: ("a timeout that covers it" not in R, "present")),
]


def timed(command):
    start = time.perf_counter()
    decide(sub(command))
    took = time.perf_counter() - start
    return took < 1.0, f"{took:.3f} s"


rows += [
    ("long prose with many 'for' runs under 1 s", lambda: timed('curl -d "' + " wait for the result of the run, and then go on with it" * 4000 + '"')),
    ("8000 unclosed for headers run under 1 s", lambda: timed(" for x" * 8000)),
    ("prose x8000 under 1 s", lambda: timed('curl -d "' + " wait for the result of the run, and then go on with it" * 8000 + '"')),
]

fails = 0
for name, check in rows:
    ok, detail = check()
    if "under 1 s" in name:
        print(f"time {name}: {detail}")
    if not ok:
        fails += 1
        print(f"FAIL {name}: {detail}")
print(f"{len(rows) - fails}/{len(rows)} passed")
sys.exit(1 if fails else 0)
