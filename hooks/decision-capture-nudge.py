#!/usr/bin/env python3
"""PostToolUse/Write|Edit|MultiEdit: remind once per session to record an ADR (BL-906 option C).

Speaks when text written to a backlog item or a plan carries a decision phrase
and no `.context/decisions/` write happened this session. Fails open and silent on any
malformed input or missing session id. State: files under ${CLAUDE_CONFIG_DIR:-~/.claude}/tmp,
keyed by session id, removed after 7 days.
"""
import json, os, re, sys, time

PHRASE = re.compile(
    r"(?<!\w)(?:decided|owner\s+decision|agreed|settled\s+on|chose|decidió|decidio|decidimos|acordamos)(?!\w)"
    r"|(?<!\w)decisi[oó]n\**:", re.I)
TARGET = re.compile(r"/\.context/(?:backlog|plans)/(.*)", re.S)
MESSAGE = ("The backlog/plan text just written says \"{hit}\" and no .context/decisions/ ADR was written in "
           "this session. If that text records a choice (by the owner, a stakeholder or this session), record "
           "it with /aidex:decision before you reply (add it to the item's existing accepted ADR when one "
           "covers it) and cite the ADR from the item. Skip this when the word does not record a choice (code "
           "or data vocabulary such as \"decided rows\") or the choice is already held by an ADR.")


def config_dir():
    cfg = os.environ.get("CLAUDE_CONFIG_DIR", "").strip(" \t\n\r\v\f")
    if cfg == "~" or cfg.startswith("~/"):
        cfg = os.path.expanduser("~") + cfg[1:]
    return cfg if cfg.startswith("/") else os.path.expanduser("~/.claude")


def written_text(tool_input):
    """Text the call wrote, or None when the payload shape is not one we read."""
    if isinstance(tool_input.get("content"), str):
        return tool_input["content"]
    if isinstance(tool_input.get("new_string"), str):
        return tool_input["new_string"]
    edits = tool_input.get("edits")
    if isinstance(edits, list) and all(isinstance(e, dict) and isinstance(e.get("new_string"), str) for e in edits):
        return "\n".join(e["new_string"] for e in edits)
    return None


def main():
    try:
        data = json.load(sys.stdin)
        sid = data["session_id"]
        tool_input = data["tool_input"]
        path = tool_input["file_path"]
        text = written_text(tool_input)
        if not (isinstance(sid, str) and sid and isinstance(path, str) and isinstance(text, str)):
            return
    except Exception:
        return
    path = os.path.normpath("/" + path.replace("\\", "/").lstrip("/"))
    state = os.path.join(config_dir(), "tmp")
    key = re.sub(r"[^\w.-]", "_", sid)
    decided, spoke = (os.path.join(state, f"decision-capture-{key}-{k}") for k in ("decided", "spoke"))

    if "/.context/decisions/" in path:
        os.makedirs(state, exist_ok=True)
        open(decided, "w").close()  # a delegate's ADR covers the session too
        return
    if data.get("agent_id"):
        return  # a subagent never speaks and never uses up the one message
    target = TARGET.search(path)
    if not target or target.group(1).startswith("_archive/") or os.path.basename(path) == "00-index.md":
        return
    hit = PHRASE.search(text)
    if not hit or os.path.exists(decided):
        return
    os.makedirs(state, exist_ok=True)
    try:
        os.close(os.open(spoke, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
    except FileExistsError:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": MESSAGE.format(hit=hit.group(0))}}), flush=True)
    cleanup(state)


def cleanup(state):
    cutoff = time.time() - 7 * 86400
    try:
        names = os.listdir(state)
    except OSError:
        return
    for name in names:
        try:
            p = os.path.join(state, name)
            if name.startswith("decision-capture-") and os.lstat(p).st_mtime < cutoff:
                os.remove(p)
        except OSError:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
