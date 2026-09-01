#!/bin/sh
# PreToolUse (Bash) hook — a file gets opened once per user turn, not once per fix.
#
# THE BEHAVIOUR IT EXISTS FOR. Gate 2 of rules/artifacts-local-first.md already says
# "open the file ONCE, when it is final — verify with the checker and DevTools first,
# `open` last". Nothing observed it, and the field behaviour was the opposite: the page
# was opened, then checked, then edited, then opened again, five to seven times for one
# artifact. The reader ends up with a stack of tabs of the same page and reads a stale
# one, because a new tab is what says "this is the version to read". Reported by the
# owner on 2026-09-01 as BL-294.
#
# WHY THE KEY IS "PER USER TURN" AND NOT "PER SESSION". A session-scoped block would be
# simpler and would be wrong: gate 6 of the same rule makes a consultation page
# *contractually* re-wrapped and re-opened every time the reader answers something, over
# and over inside one session. Blocking that loop would train the override into a habit,
# which is the rubber-stamp failure rules/autonomy.md describes and the reason three of
# this repo's four hooks are unwired. So the discriminator is arithmetic, not judgement:
# has the user said anything since the last time this exact path was opened? If yes the
# re-open is the reader's, and it goes through. If no it is the same turn opening the
# same file twice, which is the reported defect.
#
# That is deliberately the same line context-depth-nudge.sh's header draws about why it
# survived and the durability judge did not: counting is a thing that cannot misfire.
#
# WHAT IT DOES NOT DO. It does not judge whether the page is finished, it does not read
# the file, and it never blocks anything but a repeat `open` of a path that already
# exists on disk. A different file, a URL, a non-`open` command and a path that is not
# there yet all pass untouched.
#
# NO OVERRIDE FLAG, on purpose. The escape hatch is the user speaking, which is exactly
# when a re-open is legitimate; a flag would be reachable in the turn where it is not.
#
# KNOWN IMPRECISION, stated rather than hidden: an inbound cross-session message lands in
# the transcript as a user entry, so it also releases the budget. It is rare, and erring
# toward allowing an open is the right direction for a friction guard.
#
# State: ~/.claude/aidex/open-once/<session>.tsv, one "<turn>\t<path>" line per open.
# Fails open on every path: no python3, no transcript, malformed JSON -> silent exit 0.

command -v python3 >/dev/null 2>&1 || exit 0

exec python3 -c '
import json, os, shlex, sys

def out(payload):
    print(json.dumps(payload))

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

try:
    if data.get("tool_name") != "Bash":
        sys.exit(0)

    command = (data.get("tool_input") or {}).get("command") or ""
    if "open" not in command:
        sys.exit(0)

    # Every place a new command can start. `open` anywhere else is an argument.
    seps = ["\n", ";", "&&", "||", "|", "&"]
    segments = [command]
    for sep in seps:
        nxt = []
        for seg in segments:
            nxt.extend(seg.split(sep))
        segments = nxt

    targets = []
    for seg in segments:
        try:
            tokens = shlex.split(seg)
        except ValueError:
            continue
        if not tokens:
            continue
        head = tokens[0]
        if head != "open" and not head.endswith("/open"):
            continue
        args = tokens[1:]
        i = 0
        while i < len(args):
            a = args[i]
            # -a/-b take a value that is an application, not the file we track.
            if a in ("-a", "-b", "--args"):
                i += 2
                continue
            if a.startswith("-"):
                i += 1
                continue
            p = os.path.abspath(os.path.expanduser(a))
            if os.path.isfile(p) and p not in targets:
                targets.append(p)
            i += 1

    if not targets:
        sys.exit(0)

    transcript = data.get("transcript_path") or ""
    if not transcript or not os.path.isfile(transcript):
        sys.exit(0)

    # A user turn is a `type: user` entry that is not a tool result and not meta.
    # Counting tool results here would make every tool call look like a new turn,
    # which switches the whole hook off silently.
    turn = 0
    with open(transcript) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get("type") != "user" or entry.get("isMeta"):
                continue
            content = (entry.get("message") or {}).get("content")
            if isinstance(content, str):
                turn += 1
            elif isinstance(content, list) and not any(
                    isinstance(c, dict) and c.get("type") == "tool_result"
                    for c in content):
                turn += 1

    session = str(data.get("session_id") or data.get("sessionId") or "unknown")
    session = "".join(c for c in session if c.isalnum() or c in "-_") or "unknown"
    state_dir = os.path.join(os.path.expanduser("~"), ".claude", "aidex", "open-once")
    state = os.path.join(state_dir, session + ".tsv")

    seen = set()
    if os.path.isfile(state):
        with open(state) as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t", 1)
                if len(parts) == 2 and parts[0] == str(turn):
                    seen.add(parts[1])

    repeats = [p for p in targets if p in seen]
    if repeats:
        lines = ["This file was already opened since the last thing the user said:", ""]
        lines += ["  " + p for p in repeats]
        lines += ["",
                  "rules/artifacts-local-first.md, gate 2: open the page ONCE, when it "
                  "is final. Finish verifying it — check-artifact.sh, DevTools, whatever "
                  "is left — and let the open you already did stand. A second tab of the "
                  "same page is how the reader ends up reading a stale one.",
                  "",
                  "If the page changed in a way the reader has to see, say so in your "
                  "reply and let them ask; their next message clears this."]
        out({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "\n".join(lines)}})
        sys.exit(0)

    os.makedirs(state_dir, exist_ok=True)
    with open(state, "a") as fh:
        for p in targets:
            fh.write("%d\t%s\n" % (turn, p))
except Exception:
    pass
sys.exit(0)
'
