#!/usr/bin/env python3
"""Tests for hooks/artifact-open-once.sh.

The hook exists because gate 2 of skills/artifact/references/02-local-first-artifacts.md ("open the file
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
import time
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


def event(name, home, tr, session="w1", **extra):
    """Feed the hook a real PostToolUse / Stop event; return (rc, stdout)."""
    payload = {"hook_event_name": name, "session_id": session,
               "transcript_path": tr, "cwd": home}
    payload.update(extra)
    env = dict(os.environ, HOME=home)
    p = subprocess.run(["sh", HOOK], input=json.dumps(payload),
                       capture_output=True, text=True, env=env)
    return p.returncode, p.stdout


def decision(out):
    try:
        return json.loads(out).get("decision", "")
    except ValueError:
        return ""


def wrap_post(home, tr, page, **extra):
    cmd = "bash skills/artifact/scripts/wrap-report.sh --title T --in b.html --out %s" % page
    return event("PostToolUse", home, tr, tool_name="Bash",
                 tool_input={"command": cmd}, **extra)


def wrap_cells():
    """BL-678: a page wrapped in a turn must be opened in that turn; Stop blocks once.

    Pages live under the repo, not a temp dir: the hook exempts temp dirs, and HOME
    here is one.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    with tempfile.TemporaryDirectory() as home, \
            tempfile.TemporaryDirectory(dir=here) as pages:
        page = os.path.join(pages, "wrapped.html")
        open(page, "w").write("<p>x</p>")
        tr = os.path.join(home, "t.jsonl")
        transcript(tr, 1)

        rc, out = event("Stop", home, tr)
        check("Stop with no wrap passes", (rc, out.strip()), (0, ""))

        wrap_post(home, tr, page)
        rc, out = event("Stop", home, tr)
        check("wrap never opened: Stop blocks", (rc, decision(out)), (0, "block"))
        check("the block names the page and the open command",
              page in out and "open " in json.loads(out or "{}").get("reason", ""), True)
        rc, out = event("Stop", home, tr)
        check("second Stop in the same turn passes (blocks once)", (rc, out.strip()), (0, ""))

        transcript(tr, 2)
        wrap_post(home, tr, page)
        rc, out = event("Stop", home, tr, stop_hook_active=True)
        check("stop_hook_active passes even with a pending wrap", (rc, out.strip()), (0, ""))
        rc, out = event("Stop", home, tr)
        check("...and the next plain Stop still blocks", decision(out), "block")

        transcript(tr, 3)
        wrap_post(home, tr, page)
        rc, d, _ = run("open %s" % page, home, session="w1", transcript_path=tr)
        check("the open itself is allowed", (rc, d), (0, ""))
        rc, out = event("Stop", home, tr)
        check("wrap then open: no block", (rc, out.strip()), (0, ""))

        transcript(tr, 4)
        wrap_post(home, tr, page)
        transcript(tr, 5)
        rc, out = event("Stop", home, tr)
        check("a wrap from an earlier turn does not block", (rc, out.strip()), (0, ""))

        def exempt_cell(label, sess, do_exempt):
            """Exempt wrap passes Stop, AND a normal wrap in the same session blocks:
            the control proves recording works, so the pass is not vacuous."""
            transcript(tr, 20)
            do_exempt(sess)
            rc, out = event("Stop", home, tr, session=sess)
            check(label, (rc, out.strip()), (0, ""))
            wrap_post(home, tr, page, session=sess)
            rc, out = event("Stop", home, tr, session=sess)
            check(label + " (control wrap blocks)", decision(out), "block")

        exempt_cell("a subagent wrap is exempt", "x1",
                    lambda se: wrap_post(home, tr, page, session=se, agent_id="sub1"))
        tmpage = os.path.join(tempfile.gettempdir(), "aidex-wrapcell-%d.html" % os.getpid())
        open(tmpage, "w").write("<p>x</p>")
        try:
            exempt_cell("a wrap under a temp dir is exempt", "x2",
                        lambda se: wrap_post(home, tr, tmpage, session=se))
        finally:
            os.unlink(tmpage)
        transcript(tr, 21)
        rc, out = event("Stop", home, tr, session="x3", agent_id="sub1")
        check("a subagent Stop is exempt", (rc, out.strip()), (0, ""))

        # wrap and open in ONE command, new page: PreToolUse sees no file yet.
        newpage = os.path.join(pages, "new.html")
        both = "bash wrap-report.sh --title T --in b.html --out %s && open %s" % (newpage, newpage)
        transcript(tr, 22)
        rc, d, _ = run(both, home, session="c1", transcript_path=tr)
        check("compound wrap+open of a new page passes Pre", (rc, d), (0, ""))
        open(newpage, "w").write("<p>x</p>")
        event("PostToolUse", home, tr, session="c1", tool_name="Bash",
              tool_input={"command": both})
        rc, out = event("Stop", home, tr, session="c1")
        check("compound wrap+open of a new page: Stop does not block", (rc, out.strip()), (0, ""))
        os.unlink(newpage)

        # Relative --out: hook process runs in `home`, the event cwd is the pages dir.
        def spawn(payload, proc_cwd):
            payload = dict(payload, session_id="r1", transcript_path=tr, cwd=pages)
            p = subprocess.run(["sh", HOOK], input=json.dumps(payload), capture_output=True,
                               text=True, env=dict(os.environ, HOME=home), cwd=proc_cwd)
            return p.returncode, p.stdout

        def relcase(open_arg, session_tr):
            transcript(tr, session_tr)
            cmd = "bash wrap-report.sh --title T --in b.html --out a.html && open %s" % open_arg
            ev = {"tool_name": "Bash", "tool_input": {"command": cmd}}
            spawn(dict(ev, hook_event_name="PreToolUse"), home)
            open(os.path.join(pages, "a.html"), "w").write("<p>x</p>")
            spawn(dict(ev, hook_event_name="PostToolUse"), home)
            rc, out = spawn({"hook_event_name": "Stop"}, home)
            os.unlink(os.path.join(pages, "a.html"))
            return rc, out.strip()

        check("relative --out and open a.html: no block", relcase("a.html", 30), (0, ""))
        rc, out = relcase("sub/a.html", 31)
        check("control: opening a different relative path still blocks", decision(out), "block")

        # A cwd the hook cannot enter must not crash it.
        locked = os.path.join(home, "locked")
        os.mkdir(locked)
        os.chmod(locked, 0)
        try:
            p = subprocess.run(["sh", HOOK], capture_output=True, text=True,
                               input=json.dumps({"hook_event_name": "Stop", "cwd": locked,
                                                 "session_id": "r2", "transcript_path": tr}),
                               env=dict(os.environ, HOME=home))
            check("an unreadable cwd fails open, no traceback",
                  (p.returncode, p.stdout.strip(), "Traceback" in p.stderr), (0, "", False))
        finally:
            os.chmod(locked, 0o700)

        # stdin that is valid JSON but not an event object fails open.
        for raw in ("null", "[]", '"x"', "1"):
            env = dict(os.environ, HOME=home)
            p = subprocess.run(["sh", HOOK], input=raw, capture_output=True,
                               text=True, env=env)
            check("stdin %s fails open" % raw, (p.returncode, p.stdout.strip()), (0, ""))

        transcript(tr, 8)
        cmd = "wrap-report.sh --building --title T --in b.html --out %s" % page
        event("PostToolUse", home, tr, tool_name="Bash", tool_input={"command": cmd})
        rc, out = event("Stop", home, tr)
        check("a --building wrap is not recorded", (rc, out.strip()), (0, ""))

        rc, out = event("Stop", home, "/nonexistent/t.jsonl")
        check("Stop with no transcript fails open", (rc, out.strip()), (0, ""))
        env = dict(os.environ, HOME=home)
        p = subprocess.run(["sh", HOOK], input="{not json", capture_output=True,
                           text=True, env=env)
        check("malformed event fails open", (p.returncode, p.stdout.strip()), (0, ""))


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

        # --- the build lock: a page an agent is still writing (2026-09-20) ---
        # The incident: an agent wrapped its final --out path mid-run, the main
        # session's file watcher fired, the gate passed on that intermediate
        # state and the page was opened 1 min 41 s before the hand-back. The
        # lock is per PAGE, so no unrelated pending agent is ever blocked.
        building = os.path.join(home, "building.html")
        open(building, "w").write("<p>half</p>")
        lockdir = os.path.join(home, ".aidex-artifact-prev")
        os.makedirs(lockdir, exist_ok=True)
        lock = os.path.join(lockdir, "building.html.building")

        transcript(tr, 5)
        open(lock, "w").write("")
        rc, d, out = run("open %s" % building, home, transcript_path=tr)
        check("a page with a fresh lock is refused", (rc, d), (0, "deny"))
        check("the refusal says an agent is still building it",
              "still building" in out, True)
        check("the refusal names the hand-back as the only end",
              "hand-back" in out, True)

        # A different page is not touched by this page's lock.
        rc, d, _ = run("open %s" % other, home, transcript_path=tr)
        check("another page is not blocked by this lock", (rc, d), (0, ""))

        # The refusal must not spend the per-turn budget: nothing was opened, so
        # the open that follows the agent's hand-back is the FIRST one.
        os.unlink(lock)
        rc, d, _ = run("open %s" % building, home, transcript_path=tr)
        check("once the lock is gone the open goes through", (rc, d), (0, ""))

        # A lock older than 20 minutes is an agent that died or forgot its last
        # step. Ignoring it is the right direction for a friction guard — but
        # silently ignoring it would hide the reason the page may be half-written.
        transcript(tr, 6)
        open(lock, "w").write("")
        os.utime(lock, (0, time.time() - 21 * 60))
        rc, d, out = run("open %s" % building, home, transcript_path=tr)
        check("a stale lock is ignored", (rc, d), (0, ""))
        check("and says so", "stale" in out, True)
        os.unlink(lock)

        # A stale lock must not cost the hook its other rule. The stale notice and
        # the per-turn verdict are ONE hook answer: two JSON objects on stdout are
        # not parseable as one, and the deny in the second is lost.
        open(lock, "w").write("")
        os.utime(lock, (0, time.time() - 21 * 60))
        transcript(tr, 7)
        rc, d, out = run("open %s" % building, home, transcript_path=tr)
        check("stale + first open in the turn: allowed", (rc, d), (0, ""))
        rc, d, out = run("open %s" % building, home, transcript_path=tr)
        check("stale + second open in the turn: still denied", (rc, d), (0, "deny"))
        try:
            json.loads(out)
            one_object = True
        except ValueError:
            one_object = False
        check("the hook answers with exactly one JSON object", one_object, True)
        check("and the stale notice rides on it", "stale" in out, True)
        os.unlink(lock)

        # A lock dated in the FUTURE (a clock skew, a copied tree, a touch -t) gave
        # a negative age, which is younger than fresh — it would have held the page
        # forever and announced "-60 minute(s)". Unusable as a lock, so: stale.
        transcript(tr, 8)
        open(lock, "w").write("")
        os.utime(lock, (0, time.time() + 3600))
        rc, d, out = run("open %s" % building, home, transcript_path=tr)
        check("a lock dated in the future is stale, not a block", (rc, d), (0, ""))
        check("and no negative age is printed", "-" not in out.split("minutes")[0][-8:],
              True)
        check("and the notice says it is dated in the future (BL-563)",
              "in the future" in out and "0 minutes ago" not in out, True)
        os.unlink(lock)

        # --- the spellings of a path that `open` accepts and the hook must too ---
        # Both were invisible to the isfile() test, so a locked page opened as a
        # file:// URL or with a #fragment went through, and neither spelling ever
        # spent the per-turn budget.
        transcript(tr, 9)
        open(lock, "w").write("")
        rc, d, _ = run("open 'file://%s'" % building, home, transcript_path=tr)
        check("a file:// URL of a locked page is refused", (rc, d), (0, "deny"))
        rc, d, _ = run("open %s#section" % building, home, transcript_path=tr)
        check("a #fragment of a locked page is refused", (rc, d), (0, "deny"))
        os.unlink(lock)

        transcript(tr, 10)
        rc, d, _ = run("open 'file://%s'" % art, home, transcript_path=tr)
        check("file:// URL: first open allowed", (rc, d), (0, ""))
        rc, d, _ = run("open %s" % art, home, transcript_path=tr)
        check("...and it spent the page budget, so the plain repeat is denied",
              d, "deny")
        transcript(tr, 11)
        rc, d, _ = run("open %s#top" % other, home, transcript_path=tr)
        check("#fragment: first open allowed", (rc, d), (0, ""))
        rc, d, _ = run("open %s" % other, home, transcript_path=tr)
        check("...and the repeat without the fragment is the same page", d, "deny")

        # A file whose NAME contains a #: the fragment strip must not invent a path.
        transcript(tr, 12)
        hashy = os.path.join(home, "a#b.html")
        open(hashy, "w").write("<p>x</p>")
        rc, d, _ = run("open '%s'" % hashy, home, transcript_path=tr)
        check("a # in the filename: first open allowed", (rc, d), (0, ""))
        rc, d, _ = run("open '%s'" % hashy, home, transcript_path=tr)
        check("a # in the filename is tracked as that file", d, "deny")

        # A percent sign in the NAME. `file://` decoding used to replace the literal
        # spelling instead of being tried beside it, so `a%20b.html` — a real file
        # with that exact name — resolved to `a b.html`, which does not exist: the
        # page had no budget and no lock lookup at all under that spelling.
        transcript(tr, 13)
        pct = os.path.join(home, "a%20b.html")
        open(pct, "w").write("<p>x</p>")
        rc, d, _ = run("open '%s'" % pct, home, transcript_path=tr)
        check("a %-escaped name: the plain open is allowed", (rc, d), (0, ""))
        rc, d, _ = run("open 'file://%s'" % pct, home, transcript_path=tr)
        check("...and its file:// spelling is the same page", d, "deny")

        transcript(tr, 14)
        pct_lock = os.path.join(lockdir, "a%20b.html.building")
        open(pct_lock, "w").write("")
        rc, d, out = run("open 'file://%s'" % pct, home, transcript_path=tr)
        check("a %-escaped name behind a lock is refused", (rc, d), (0, "deny"))
        check("and refused as a build, not as a repeat", "still building" in out, True)
        os.unlink(pct_lock)

        # The two bands of a mtime in the future. A second or two of clock skew
        # between a container and the host is ordinary, and calling it stale would
        # disarm the guard on exactly the machines that produce it; only a lock
        # dated further ahead than the whole window is unusable.
        transcript(tr, 15)
        open(lock, "w").write("")
        os.utime(lock, (0, time.time() + 30))
        rc, d, _ = run("open %s" % building, home, transcript_path=tr)
        check("a lock 30 s in the future is still a live build", (rc, d), (0, "deny"))
        os.utime(lock, (0, time.time() + 21 * 60))
        rc, d, out = run("open %s" % building, home, transcript_path=tr)
        check("a lock further ahead than the window is stale", (rc, d), (0, ""))
        check("and the stale notice carries no negative age", "-1 minutes" in out, False)
        os.unlink(lock)

    wrap_cells()

    print("%s — artifact open-once: %d passed, %d failed"
          % ("FAIL" if FAIL else "OK", PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
