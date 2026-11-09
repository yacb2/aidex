#!/usr/bin/env python3
"""Tests for decision-capture-nudge.py. Run: python3 hooks/test-decision-capture-nudge.py

Layer: hook boundary. Each row runs the script as Claude Code does (JSON on stdin, state in a
temp CLAUDE_CONFIG_DIR) and reads stdout and the exit code.
"""
import json, os, subprocess, sys, tempfile, time

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "decision-capture-nudge.py")
BL = "/p/.context/backlog/BL-1-x.md"
DEC = "/p/.context/decisions/2026-11-09-x.md"


def payload(path=BL, text="owner decided to ship", tool="Write", sid="s1", agent=None):
    if tool == "Write":
        ti = {"file_path": path, "content": text}
    elif tool == "Edit":
        ti = {"file_path": path, "old_string": "a", "new_string": text}
    else:
        ti = {"file_path": path, "edits": [{"old_string": "a", "new_string": "nothing"},
                                           {"old_string": "b", "new_string": text}]}
    d = {"session_id": sid, "cwd": "/p", "tool_name": tool, "tool_input": ti, "tool_response": {}}
    if agent is not None:
        d["agent_id"] = agent
    return d


def run(cfg, data, raw=None):
    stdin = raw if raw is not None else json.dumps(data)
    p = subprocess.run([sys.executable, HOOK], input=stdin, capture_output=True, text=True,
                       env={**os.environ, "CLAUDE_CONFIG_DIR": cfg}, timeout=20)
    return p.returncode, p.stdout


def speaks(cfg, data, raw=None):
    rc, out = run(cfg, data, raw)
    return rc == 0 and out.strip() != ""


def fresh(*steps):
    """Run payloads in order in one config dir; return the last (rc, stdout)."""
    with tempfile.TemporaryDirectory() as cfg:
        res = None
        for s in steps:
            res = run(cfg, s)
        return res


def quiet(data=None, raw=None):
    with tempfile.TemporaryDirectory() as cfg:
        return run(cfg, data, raw) == (0, "")


def one(data=None, raw=None):
    with tempfile.TemporaryDirectory() as cfg:
        return speaks(cfg, data, raw)


rows = []  # (name, bool)


def row(name, ok):
    rows.append((name, ok))


# Path predicate.
row("backlog path speaks", one(payload(BL)))
row("plans path speaks", one(payload("/p/.context/plans/2026-11-09-x.md")))
row("src path is silent", quiet(payload("/p/src/a.md")))
row("backlog word without .context is silent", quiet(payload("/p/backlog/BL-1.md")))
row("_archive under backlog is silent", quiet(payload("/p/.context/backlog/_archive/BL-1.md")))
row("00-index.md is silent", quiet(payload("/p/.context/backlog/00-index.md")))
row("00-index.md under plans is silent", quiet(payload("/p/.context/plans/00-index.md")))
row("a file merely ending in 00-index.md is not excluded", one(payload("/p/.context/backlog/x-00-index.md")))
row("backslash path speaks", one(payload("C:\\p\\.context\\backlog\\BL-1.md")))
row("dot-dot path to src is silent", quiet(payload("/p/.context/backlog/../../src/a.md")))
row("plans _archive is silent", quiet(payload("/p/.context/plans/_archive/x.md")))
row("project under /x/_archive/ still speaks", one(payload("/x/_archive/proj/.context/backlog/BL-1.md")))
row("relative .context path speaks", one(payload(".context/backlog/BL-1.md")))
row("decisions path alone is silent", quiet(payload(DEC)))

# Pattern predicate.
for w in ["decided", "Decision: x", "owner decision", "agreed", "settled on", "chose",
          "decidió", "decidio", "decidimos", "acordamos"]:
    row(f"pattern '{w}' speaks", one(payload(text=f"we {w} it")))
row("DECIDED uppercase speaks", one(payload(text="DECIDED")))
row("Decidió capitalised speaks", one(payload(text="El dueño Decidió")))
row("undecided is silent", quiet(payload(text="still undecided")))
row("decisions alone is silent", quiet(payload(text="see the decisions list")))
row("disagreed is silent", quiet(payload(text="they disagreed")))
row("chosen is silent", quiet(payload(text="the chosen one")))
row("decision: glued to a word before it is silent", quiet(payload(text="predecision: x")))
row("bold **Decision**: speaks", one(payload(text="**Decision**: use X")))
row("heading Decision: speaks", one(payload(text="## Decision: use X")))
row("**Decision:** speaks", one(payload(text="**Decision:** use X")))
row("Decisión: speaks", one(payload(text="Decisión: usar X")))
row("settled  on with two spaces speaks", one(payload(text="we settled  on X")))
row("settled\\non across a newline speaks", one(payload(text="we settled\non X")))
row("decision without colon is silent", quiet(payload(text="a decision about it")))
row("empty text is silent", quiet(payload(text="")))
row("decided at end of text speaks", one(payload(text="x\ndecided")))

# No ADR-citation exemption: the session flag is the signal.
row("citing an ADR plus a new decided line speaks",
    one(payload(text="ADR decisions/2026-11-01-x.md\nDecided: also Y")))
row("skills/decision/SKILL.md is not a citation", one(payload(text="decided; see skills/decision/SKILL.md")))
row("indecision/ is not a citation", one(payload(text="decided; indecision/notes")))

# Session state.
dec_then_bl = fresh(payload(DEC, text="# ADR"), payload(BL))
row("earlier decisions write suppresses", dec_then_bl[0] == 0 and dec_then_bl[1].strip() == "")
row("decisions-old write does not suppress",
    fresh(payload("/p/.context/decisions-old/x.md", text="# ADR"), payload(BL))[1].strip() != "")
row("decisions write in another session does not suppress",
    fresh(payload(DEC, sid="other"), payload(BL))[1].strip() != "")
with tempfile.TemporaryDirectory() as cfg:
    first = speaks(cfg, payload())
    second = run(cfg, payload())
    third = speaks(cfg, payload(sid="s2"))
    row("first hit speaks", first)
    row("second hit in the same session is silent", second == (0, ""))
    row("spoke state file exists", os.path.exists(os.path.join(cfg, "tmp", "decision-capture-s1-spoke")))
    row("another session speaks", third)
with tempfile.TemporaryDirectory() as cfg:
    run(cfg, payload(text="nothing here"))
    row("a silent write does not use up the one message", speaks(cfg, payload()))
with tempfile.TemporaryDirectory() as cfg:
    old = os.path.join(cfg, "tmp", "decision-capture-old")
    os.makedirs(os.path.dirname(old))
    open(old, "w").close()
    t = time.time() - 8 * 86400
    os.utime(old, (t, t))
    run(cfg, payload())
    row("state older than 7 days is removed", not os.path.exists(old))

# Subagents.
row("subagent hit is silent", quiet(payload(agent="a1")))
sub_then_main = fresh(payload(agent="a1"), payload())
row("subagent hit does not use up the message", sub_then_main[1].strip() != "")
row("subagent decisions write suppresses the main session",
    fresh(payload(DEC, text="# ADR", agent="a1"), payload()) == (0, ""))
row("empty agent_id counts as the main session", one(payload(agent="")))

# Cleanup.
with tempfile.TemporaryDirectory() as cfg:
    d = os.path.join(cfg, "tmp", "decision-capture-stale")
    os.makedirs(d)
    os.symlink("/nonexistent/x", os.path.join(cfg, "tmp", "decision-capture-broken"))
    t = time.time() - 8 * 86400
    os.utime(d, (t, t))
    files = [os.path.join(cfg, "tmp", f"decision-capture-z{i}") for i in range(5)]
    for i in range(5):
        os.makedirs(os.path.join(cfg, "tmp", f"decision-capture-d{i}"))
        os.utime(os.path.join(cfg, "tmp", f"decision-capture-d{i}"), (t, t))
    for f in files:
        open(f, "w").close()
        os.utime(f, (t, t))
    row("stale directory and broken symlink in tmp do not block speaking", speaks(cfg, payload()))
    row("a stale directory does not stop cleanup of the stale files after it",
        not any(os.path.exists(f) for f in files))
with tempfile.TemporaryDirectory() as cfg:
    run(cfg, payload(DEC, text="# ADR", sid="A"))
    run(cfg, payload(sid="B"))
    row("young state survives cleanup", run(cfg, payload(sid="A")) == (0, ""))

# Tool shapes.
row("Edit payload speaks", one(payload(tool="Edit")))
row("MultiEdit payload speaks from a later edit", one(payload(tool="MultiEdit")))
row("MultiEdit without a hit is silent", quiet(payload(tool="MultiEdit", text="plain")))

# Malformed input.
with tempfile.TemporaryDirectory() as cfg:
    rc, out = run(cfg, None, raw="{not json")
    row("malformed JSON exits 0 silent", rc == 0 and out == "")
    rc, out = run(cfg, None, raw="")
    row("empty stdin exits 0 silent", rc == 0 and out == "")
    rc, out = run(cfg, None, raw="[1]")
    row("non-object JSON exits 0 silent", rc == 0 and out == "")
    d = payload(); del d["session_id"]
    rc, out = run(cfg, d)
    row("missing session_id exits 0 silent", rc == 0 and out == "")
    d = payload(); d["session_id"] = ""
    rc, out = run(cfg, d)
    row("empty session_id exits 0 silent", rc == 0 and out == "")
    d = payload(); del d["tool_input"]["file_path"]
    rc, out = run(cfg, d)
    row("missing file_path exits 0 silent", rc == 0 and out == "")
    d = payload(); d["tool_input"]["content"] = 5
    rc, out = run(cfg, d)
    row("non-string content exits 0 silent", rc == 0 and out == "")
    d = payload(tool="MultiEdit"); d["tool_input"]["edits"] = "x"
    rc, out = run(cfg, d)
    row("malformed edits exits 0 silent", rc == 0 and out == "")
    d = payload(); d["tool_input"] = []
    rc, out = run(cfg, d)
    row("non-object tool_input exits 0 silent", rc == 0 and out == "")

# Output shape.
rc, out = fresh(payload(text="owner decision: use X"))
try:
    o = json.loads(out)
    h = o["hookSpecificOutput"]
    msg = h["additionalContext"]
    row("output JSON shape", rc == 0 and list(o) == ["hookSpecificOutput"]
        and h["hookEventName"] == "PostToolUse" and set(h) == {"hookEventName", "additionalContext"})
    row("message names the matched phrase", "owner decision" in msg)
    row("message points to /aidex:decision", "/aidex:decision" in msg)
    row("message gives the order and both skip conditions",
        "before you reply" in msg.lower() and "does not record a choice" in msg and "already held by an ADR" in msg)
except Exception as e:
    row(f"output JSON shape ({e!r})", False)
    row("message names the matched phrase", False)
    row("message points to /aidex:decision", False)
    row("message says to skip a restated choice", False)

fails = [n for n, ok in rows if not ok]
for n in fails:
    print(f"FAIL {n}")
print(f"{len(rows) - len(fails)}/{len(rows)} passed")
sys.exit(1 if fails else 0)
