#!/usr/bin/env python3
"""Tests for hooks/artifact-open-once.sh.

The hook exists because gate 2 of rules/artifacts-local-first.md ("open the file
ONCE, when it is final") was prose nothing observed, and the observed behaviour was
five to seven tabs of the same page.

The BLOCK cell is the easy half. The ALLOW cells are the ones this file exists for:
this repo closed BL-291 and BL-292 on the same day, both "a check with green cells
that had never seen the input it exists for". A test that only asserts the refusal
would ship a hook that also refuses the consultation loop, where the page is
legitimately re-wrapped and re-opened every time the reader answers.

Run: python3 hooks/test-artifact-open-once.py
"""

import json
import os
import subprocess
import sys
import tempfile

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "artifact-open-once.sh")

PASS = 0
FAIL = 0


def transcript(path, user_turns):
    """Write a transcript with `user_turns` real user messages plus noise.

    The noise matters: tool results are also `type: user`, and counting them would
    make every tool call look like a new user turn, which switches the hook off.
    """
    with open(path, "w") as fh:
        for i in range(user_turns):
            fh.write(json.dumps({
                "type": "user",
                "message": {"role": "user", "content": "user message %d" % i},
            }) + "\n")
            fh.write(json.dumps({
                "type": "assistant",
                "message": {"role": "assistant", "content": [
                    {"type": "tool_use", "name": "Bash"}]},
            }) + "\n")
            fh.write(json.dumps({
                "type": "user",
                "message": {"role": "user", "content": [
                    {"type": "tool_result", "content": "out"}]},
            }) + "\n")


def run(command, home, session="s1", transcript_path=None, tool="Bash"):
    payload = {
        "tool_name": tool,
        "tool_input": {"command": command},
        "session_id": session,
    }
    if transcript_path is not None:
        payload["transcript_path"] = transcript_path
    env = dict(os.environ, HOME=home)
    p = subprocess.run(["sh", HOOK], input=json.dumps(payload),
                       capture_output=True, text=True, env=env)
    decision = ""
    if p.stdout.strip():
        try:
            decision = json.loads(p.stdout).get(
                "hookSpecificOutput", {}).get("permissionDecision", "")
        except ValueError:
            decision = "UNPARSEABLE:" + p.stdout.strip()[:80]
    return p.returncode, decision, p.stdout


def check(label, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
    else:
        FAIL += 1
        print("  FAIL %s: got %r, want %r" % (label, got, want))


def main():
    if not os.path.exists(HOOK):
        print("no hook at %s" % HOOK)
        return 1

    with tempfile.TemporaryDirectory() as home:
        art = os.path.join(home, "report.html")
        other = os.path.join(home, "second.html")
        for f in (art, other):
            open(f, "w").write("<p>x</p>")
        tr = os.path.join(home, "t.jsonl")
        transcript(tr, 1)

        # --- the pathology: open, edit, open again inside one user turn ---
        rc, d, _ = run("open %s" % art, home, transcript_path=tr)
        check("first open allowed", (rc, d), (0, ""))
        rc, d, _ = run("open %s" % art, home, transcript_path=tr)
        check("second open in same turn denied", (rc, d), (0, "deny"))
        rc, d, out = run("open %s" % art, home, transcript_path=tr)
        check("still denied on the third", d, "deny")
        check("the refusal names the file", art in out, True)

        # --- the consultation loop: the reader answered, so re-opening is right ---
        transcript(tr, 2)
        rc, d, _ = run("open %s" % art, home, transcript_path=tr)
        check("re-open after a user turn allowed", (rc, d), (0, ""))
        rc, d, _ = run("open %s" % art, home, transcript_path=tr)
        check("but only once per turn", d, "deny")

        # --- things the hook must not touch ---
        rc, d, _ = run("open %s" % other, home, transcript_path=tr)
        check("a different file is its own budget", (rc, d), (0, ""))
        rc, d, _ = run("ls %s" % art, home, transcript_path=tr)
        check("a non-open command is untouched", (rc, d), (0, ""))
        rc, d, _ = run("ls %s" % art, home, transcript_path=tr)
        check("and stays untouched when repeated", (rc, d), (0, ""))
        rc, d, _ = run("open https://example.com", home, transcript_path=tr)
        check("a URL is not a file", (rc, d), (0, ""))
        rc, d, _ = run("open https://example.com", home, transcript_path=tr)
        check("a URL is still not a file the second time", (rc, d), (0, ""))
        rc, d, _ = run("open %s/gone.html" % home, home, transcript_path=tr)
        check("a path that does not exist is not tracked", (rc, d), (0, ""))

        # --- a second session has its own state ---
        rc, d, _ = run("open %s" % art, home, session="s2", transcript_path=tr)
        check("another session starts clean", (rc, d), (0, ""))

        # --- open inside a compound command is still an open ---
        transcript(tr, 3)
        rc, d, _ = run("bash check.sh && open %s" % other, home, transcript_path=tr)
        check("compound: first is allowed", (rc, d), (0, ""))
        rc, d, _ = run("bash check.sh && open %s" % other, home, transcript_path=tr)
        check("compound: the repeat is denied", d, "deny")

        # --- `open -a App file` keeps the file as the target ---
        transcript(tr, 4)
        rc, d, _ = run("open -a Safari %s" % art, home, transcript_path=tr)
        check("open -a: first allowed", (rc, d), (0, ""))
        rc, d, _ = run("open %s" % art, home, transcript_path=tr)
        check("open -a: the plain repeat is denied", d, "deny")

        # --- fails open on anything it cannot read ---
        rc, d, _ = run("open %s" % art, home, transcript_path=None)
        check("no transcript: fails open", (rc, d), (0, ""))
        rc, d, _ = run("open %s" % art, home,
                       transcript_path=os.path.join(home, "missing.jsonl"))
        check("missing transcript: fails open", (rc, d), (0, ""))
        p = subprocess.run(["sh", HOOK], input="not json",
                           capture_output=True, text=True,
                           env=dict(os.environ, HOME=home))
        check("malformed input: fails open", (p.returncode, p.stdout.strip()), (0, ""))
        rc, d, _ = run("open %s" % art, home, transcript_path=tr, tool="Read")
        check("a non-Bash tool is not ours", (rc, d), (0, ""))

    print("%s — artifact open-once: %d passed, %d failed"
          % ("FAIL" if FAIL else "OK", PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
