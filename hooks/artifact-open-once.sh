#!/bin/sh
# PreToolUse (Bash) hook — a file gets opened once per user turn, not once per fix.
#
# THE BEHAVIOUR IT EXISTS FOR. Gate 2 of skills/artifact/references/02-local-first-artifacts.md already says
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
# which is the rubber-stamp failure skills/conventions/references/autonomy-conventions.md describes and the reason three of
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
#
# THE OTHER DIRECTION (BL-678, owner decision 2026-10-06). The same turn counter also
# enforces that a wrap ENDS in an open: pages written or updated and never opened were
# about 20 prompts of USAGE-31. Two more events reach this script, keyed on
# `hook_event_name` (an event without one is the PreToolUse of above):
#   PostToolUse (Bash) records the --out path of every successful, final
#     `wrap-report.sh` run in <session>.wraps.tsv, as "<turn>\t<path>". Not `--building`
#     (a delegated build is opened after its hand-back) and not `--done`.
#   Stop: a page wrapped in THIS turn with no open of it in this turn blocks the stop,
#     naming the path and the `open` command, ONCE per turn ("<turn>\tBLOCKED" in the
#     same file, plus stop_hook_active as a second guard). It never blocks twice.
# Exempt: any event carrying agent_id (only the main session opens pages) and a page
# under a temp dir (tests and evals wrap there). Fail open on any error.

command -v python3 >/dev/null 2>&1 || exit 0

exec python3 -c '
import json, os, shlex, sys, time
from urllib.parse import unquote

def out(payload):
    print(json.dumps(payload))


def candidates(arg):
    """The paths one `open` argument can mean, most literal first.

    `open` takes three spellings of the same page and only the bare one used to be
    seen: a `file://` URL and a `#fragment` both failed isfile(), so a locked page
    opened either way went through, and neither spelling ever spent the per-turn
    budget. The fragment is tried as a STRIPPED alternative rather than stripped
    outright, because a real filename may contain a `#` and the literal path is
    the one to prefer when it exists.
    """
    out_paths = []
    forms = [arg]
    if arg.startswith("file://"):
        rest = arg[len("file://"):]
        # file:///abs and file://localhost/abs are the two spellings in the wild.
        if rest.startswith("localhost/"):
            rest = rest[len("localhost"):]
        if rest.startswith("/"):
            # BOTH, literal first. Decoding INSTEAD of the literal loses a file
            # whose name really contains a percent escape (`a%20b.html` is a legal
            # name, and `open` on it works): it resolved to `a b.html`, which does
            # not exist, so that spelling had no lock lookup and no budget.
            forms = [rest, unquote(rest)]
    for f in list(forms):
        if "#" in f:
            forms.append(f.split("#", 1)[0])
    for f in forms:
        if not f:
            continue
        p = os.path.abspath(os.path.expanduser(f))
        if p not in out_paths:
            out_paths.append(p)
    return out_paths

def user_turn(transcript):
    """Count of real user messages: a `type: user` entry that is not a tool result
    and not meta. Counting tool results would make every tool call look like a new
    turn, which switches the whole hook off silently."""
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
    return turn


def state_files(data):
    session = str(data.get("session_id") or data.get("sessionId") or "unknown")
    session = "".join(c for c in session if c.isalnum() or c in "-_") or "unknown"
    state_dir = os.path.join(os.path.expanduser("~"), ".claude", "aidex", "open-once")
    return state_dir, os.path.join(state_dir, session + ".tsv"), \
        os.path.join(state_dir, session + ".wraps.tsv")


def in_temp_dir(path):
    import tempfile
    roots = ["/tmp", "/private/tmp", "/var/tmp", "/var/folders", "/private/var/folders",
             tempfile.gettempdir()]
    real = os.path.realpath(path)
    return any(real == os.path.realpath(r) or
               real.startswith(os.path.realpath(r) + os.sep) for r in roots)


def open_paths(command):
    """Every path an `open` segment of `command` names, in all its spellings."""
    segments = [command]
    for sep in ["\n", ";", "&&", "||", "|", "&"]:
        segments = [piece for seg in segments for piece in seg.split(sep)]
    found = []
    for seg in segments:
        try:
            tokens = shlex.split(seg)
        except ValueError:
            continue
        if not tokens or not (tokens[0] == "open" or tokens[0].endswith("/open")):
            continue
        args, i = tokens[1:], 0
        while i < len(args):
            if args[i] in ("-a", "-b", "--args"):
                i += 2
                continue
            if not args[i].startswith("-"):
                found.extend(candidates(args[i]))
            i += 1
    return found


def wrapped_outs(command, cwd):
    """The --out paths of the final `wrap-report.sh` invocations in `command`."""
    segments = [command]
    for sep in ["\n", ";", "&&", "||", "|", "&"]:
        segments = [piece for seg in segments for piece in seg.split(sep)]
    outs = []
    for seg in segments:
        try:
            tokens = shlex.split(seg)
        except ValueError:
            continue
        idx = [i for i, t in enumerate(tokens)
               if t == "wrap-report.sh" or t.endswith("/wrap-report.sh")]
        if not idx or "--building" in tokens or "--done" in tokens:
            continue
        args = tokens[idx[0] + 1:]
        out = None
        for i, a in enumerate(args):
            if a == "--out" and i + 1 < len(args):
                out = args[i + 1]
            elif a.startswith("--out="):
                out = a[len("--out="):]
        if out:
            outs.append(os.path.abspath(os.path.join(cwd, os.path.expanduser(out))))
    return outs


def wrap_events(data):
    """PostToolUse records a wrap; Stop blocks once when it was never opened.
    Returns after answering; every error propagates to the fail-open of the caller."""
    if data.get("agent_id"):
        return
    event = data.get("hook_event_name")
    state_dir, opens, wraps = state_files(data)
    if event == "Stop" and (data.get("stop_hook_active") or not os.path.isfile(wraps)):
        return
    command = (data.get("tool_input") or {}).get("command") or ""
    if event == "PostToolUse" and (data.get("tool_name") != "Bash"
                                   or "wrap-report.sh" not in command):
        return
    transcript = data.get("transcript_path") or ""
    if not transcript or not os.path.isfile(transcript):
        return
    turn = user_turn(transcript)
    if event == "PostToolUse":
        outs = [p for p in wrapped_outs(command, os.getcwd()) if not in_temp_dir(p)]
        if outs:
            os.makedirs(state_dir, exist_ok=True)
            # `wrap ... --out P && open P`: PreToolUse ran before P existed, so it
            # could not record that open. The same command opens it, so count it.
            opened = [p for p in open_paths(command) if p in outs]
            with open(wraps, "a") as fh:
                for p in outs:
                    fh.write("%d\t%s\n" % (turn, p))
            if opened:
                with open(opens, "a") as fh:
                    for p in dict.fromkeys(opened):
                        fh.write("%d\t%s\n" % (turn, p))
        return
    if event != "Stop":
        return

    def rows(path):
        found = []
        if os.path.isfile(path):
            with open(path) as fh:
                for line in fh:
                    parts = line.rstrip("\n").split("\t", 1)
                    if len(parts) == 2 and parts[0] == str(turn):
                        found.append(parts[1])
        return found

    if "BLOCKED" in rows(wraps):
        return
    opened = set(rows(opens))
    pending = [p for p in dict.fromkeys(rows(wraps))
               if p != "BLOCKED" and p not in opened and os.path.isfile(p)]
    if not pending:
        return
    with open(wraps, "a") as fh:
        fh.write("%d\tBLOCKED\n" % turn)
    lines = ["A page was wrapped in this turn and never opened:", ""]
    lines += ["  " + p for p in pending]
    lines += ["", "If it is ready, open it and say so in your reply:", ""]
    lines += ["  open " + shlex.quote(p) for p in pending]
    lines += ["", "If it is still being graded or revised, or should not be opened, "
                  "stop again and say so; this check blocks only once per turn."]
    out({"decision": "block", "reason": "\n".join(lines)})


try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)
try:
    if isinstance(data.get("cwd"), str) and os.path.isdir(data["cwd"]):
        os.chdir(data["cwd"])
except OSError:
    pass

if data.get("hook_event_name") in ("PostToolUse", "Stop"):
    try:
        wrap_events(data)
    except Exception:
        pass
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
            for p in candidates(a):
                if os.path.isfile(p) and p not in targets:
                    targets.append(p)
                    break
            i += 1

    if not targets:
        sys.exit(0)

    # THE BUILD LOCK, added 2026-09-20. A delegated artifact agent writes its final
    # `--out` path two or three times mid-run, so a file watcher — or a passing
    # contract check — says "done" while the agent is still working; the reported
    # incident opened the page 1 min 41 s before the hand-back, on an intermediate
    # wrap that had passed the gate. `wrap-report.sh --building` refreshes
    # <dir>/.aidex-artifact-prev/<page>.building on every wrap of that build and
    # `--done` removes it, so the state is per PAGE. That is the whole reason this
    # is not "refuse while any agent is pending": replayed over the sessions since
    # 2026-09-14, the transcript-scoped guard blocked 18 of 26 real opens, nearly
    # all of them pages no pending agent was touching.
    #
    # STALE MEANS ALLOW. A lock older than STALE_AFTER is an agent that died, was
    # cancelled, or forgot its last step; holding the page hostage on that would be
    # the misfire that unwired the other hooks in this repo. It is announced instead of
    # ignored silently, because "the page may be half-written" is exactly what the
    # reader needs to know when the guard steps aside.
    STALE_AFTER = 20 * 60
    locked, stale = [], []
    now = time.time()
    for p in targets:
        lock = os.path.join(os.path.dirname(p), ".aidex-artifact-prev",
                            os.path.basename(p) + ".building")
        try:
            age = now - os.path.getmtime(lock)
        except OSError:
            continue
        # A mtime in the FUTURE has two bands, and collapsing them either way is a
        # defect. A few seconds or minutes ahead is ordinary clock skew (a
        # container, a network share, a restored tree) over a lock an agent is
        # really holding — calling that stale would disarm the guard on exactly the
        # machines that produce it. Further ahead than the whole window is a date
        # nothing can age out of: it would hold the page forever and announce a
        # negative number of minutes, and a guard whose worst case is permanent is
        # the one shape this hook must never have. So: skew is fresh, absurd is
        # stale, and the age printed is never negative.
        absurd = age < -STALE_AFTER
        (stale if age > STALE_AFTER or absurd else locked).append(
            (p, lock, max(age, 0), absurd))

    # ONE hook answer, always. The stale notice used to be printed on its own and
    # then fall through to the per-turn rule, so a second open of a stale-locked
    # page in the same turn wrote two JSON objects on stdout — which parses as
    # neither, and the deny in the second one was lost. The notice is a rider on
    # whatever this invocation decides, never an answer of its own.
    stale_msg = None
    if stale:
        p, lock, age, future = stale[0]
        when = ("dated more than %d minutes in the future" % (STALE_AFTER // 60)
                if future else "last touched %d minutes ago" % int(age // 60))
        stale_msg = ("stale build lock ignored (%s, %s): the "
                     "agent that was building %s never ran `wrap-report.sh --done`, so "
                     "this page may be a half-finished state. Opening anyway."
                     % (lock, when, p))

    if locked:
        lines = ["An agent is still building this page:", ""]
        lines += ["  %s" % p for p, _, _, _ in locked]
        lines += ["",
                  "The build lock beside it (.aidex-artifact-prev/<page>.building) was "
                  "refreshed %d minute(s) ago by the last wrap of that agent. An artifact "
                  "agent writes its --out path several times mid-run, so neither the "
                  "file changing nor check-artifact.sh passing means it has finished: "
                  "an intermediate wrap passes the contract."
                  % int(min(a for _, _, a, _ in locked) // 60),
                  "",
                  "The only signal that the agent is done is its own hand-back. Wait "
                  "for it — do not watch the file, do not poll it — and open the page "
                  "after it arrives. The lock is ignored after 20 minutes, so a dead "
                  "agent cannot block the page for longer than that."]
        payload = {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "\n".join(lines)}}
        if stale_msg:
            payload["systemMessage"] = stale_msg
        out(payload)
        sys.exit(0)

    transcript = data.get("transcript_path") or ""
    if not transcript or not os.path.isfile(transcript):
        sys.exit(0)

    turn = user_turn(transcript)
    state_dir, state, _ = state_files(data)

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
                  "skills/artifact/references/02-local-first-artifacts.md, gate 2: open the page ONCE, when it "
                  "is final. Finish verifying it — check-artifact.sh, DevTools, whatever "
                  "is left — and let the open you already did stand. A second tab of the "
                  "same page is how the reader ends up reading a stale one.",
                  "",
                  "If the page changed in a way the reader has to see, say so in your "
                  "reply and let them ask; their next message clears this."]
        payload = {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "\n".join(lines)}}
        if stale_msg:
            payload["systemMessage"] = stale_msg
        out(payload)
        sys.exit(0)

    os.makedirs(state_dir, exist_ok=True)
    with open(state, "a") as fh:
        for p in targets:
            fh.write("%d\t%s\n" % (turn, p))
    if stale_msg:
        out({"systemMessage": stale_msg})
except Exception:
    pass
sys.exit(0)
'
