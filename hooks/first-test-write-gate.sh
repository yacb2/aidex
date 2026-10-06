#!/bin/sh
# PreToolUse hook (Write, Bash) — deny the first NEW test file once per (session, agent).
#
# The testing core (skills/testing/SKILL.md) was in context before the first test write
# in 0 of 110 sessions measured on 2026-09-25: nothing loads it at the moment a test is
# written. A probe of this exact shape (deny the first new test Write once, allow the
# retry) changed the first landed file 6 of 6 times for one extra Write call each
# (.context/experiments/2026-09-25-testing-delivery-probes/RESULTS.md, Table 2). The deny
# reaches the model as "PreToolUse:<Write|Bash> hook error: <reason>".
#
# The reason is a POINTER, never a copy of the core: skills/testing owns the questions and
# tests/test-single-source.sh fails if any shipped file restates them. It starts with the
# literal "aidex:testing" so a reader of a transcript recognizes the gate. census.py does
# NOT count the deny as core in context — only the Skill load or Read it leads to counts.
#
# Key: session_id plus agent_id, because a subagent starts from a fresh context. Main is
# the ABSENT field (the probe saw main send none); any present value, even "", is keyed
# as itself. No session_id: allow, write nothing. State:
# ~/.claude/aidex/first-test-write/<session>.tsv, one key per line; check and append
# happen under flock, so parallel Writes from one context get exactly one deny.
#
# Only a Write, or a Bash command, that creates a path that does not exist yet: an Edit,
# or a write over an existing test, is work on a test that already passed this gate or
# predates it. The 2026-09-25 eval wrote its first test through Bash (cat > ... <<EOF,
# python - <<EOF ... open(p,'w')) in 4 of 12 runs, so Bash is gated too; the paths a
# command writes come from census.py's bash_writes (unquoted redirection, tee, touch,
# python open/write_text; never cp/mv), resolved from the event's cwd across cd/pushd and
# $VARs set earlier in the command; a path it cannot resolve is never denied. The test
# patterns and the Bash
# detector are IMPORTED from skills/testing/scripts/census.py, so the hook gates exactly
# what the census counts. Any error, or a command it cannot parse, exits 0 with no output.

# -c, not a pipe or heredoc to `python3 -`: those consume the stdin the hook must read.
PYSRC=$(cat <<'PY'
import fcntl, json, os, sys
try:
    ev = json.load(sys.stdin)
    sys.dont_write_bytecode = True
    sys.path.insert(0, os.path.join(os.environ["HOOK_DIR"], "..", "skills", "testing", "scripts"))
    from census import bash_writes, is_test
    tool, inp = ev.get("tool_name"), ev.get("tool_input") or {}
    if tool == "Write":
        paths = [inp.get("file_path") or ""]
    elif tool == "Bash":
        # Resolved across cd/pushd from the event cwd; a path still holding a `$` is
        # unknown and never denied.
        paths = [p for p in bash_writes(inp.get("command") or "", ev.get("cwd") or os.getcwd())
                 if "$" not in p]
    else:
        sys.exit(0)
    if not any(is_test(p) and not os.path.exists(p) for p in paths):
        sys.exit(0)
    session = "".join(c for c in str(ev.get("session_id") or "") if c.isalnum() or c in "-_")
    if not session:
        sys.exit(0)
    # An agent whose definition preloads the testing skill (`skills: [aidex:testing]`)
    # already has the core in context: denying it costs a turn and teaches nothing.
    atype = str(ev.get("agent_type") or "")
    if atype:
        plugin, _, name = atype.rpartition(":")
        cands = [os.path.join(os.path.expanduser("~"), ".claude", "agents", name + ".md"),
                 os.path.join(ev.get("cwd") or os.getcwd(), ".claude", "agents", name + ".md")]
        if plugin == "aidex":
            cands = [os.path.join(os.environ["HOOK_DIR"], "..", "agents", name + ".md")]
        for c in cands:
            if os.path.isfile(c):
                head = open(c).read().split("\n---", 1)[0]
                if any(l.startswith("skills:") and "testing" in l for l in head.splitlines()):
                    sys.exit(0)
                break
    key = "main" if "agent_id" not in ev else "agent:" + str(ev["agent_id"])
    state_dir = os.path.join(os.path.expanduser("~"), ".claude", "aidex", "first-test-write")
    os.makedirs(state_dir, exist_ok=True)
    with open(os.path.join(state_dir, session + ".tsv"), "a+") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        fh.seek(0)
        if key in fh.read().splitlines():
            sys.exit(0)
        fh.write(key + "\n")
    skill = os.path.normpath(os.path.join(os.environ.get("HOOK_DIR", ""), "..", "skills", "testing", "SKILL.md"))
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason":
            "aidex:testing: this is the first new test file in this context, so the testing "
            "core has to be read before it lands.\n"
            "Load the aidex:testing skill (Skill tool) or Read " + skill + ".\n"
            "Answer its questions for this test, then write the file again; "
            "this gate fires once per session and agent."}}))
except Exception:
    pass
PY
)
HOOK_DIR=$(cd "$(dirname "$0")" && pwd -P) python3 -c "$PYSRC" 2>/dev/null
exit 0
