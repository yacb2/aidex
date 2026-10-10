#!/bin/sh
# PreToolUse hook — refuse an Edit/Write/MultiEdit of a spec-built HTML page.
#
# spec_build.py writes `<!-- GENERATED from <spec> by /aidex:artifact spec_build.py
# — DO NOT EDIT: edit the spec and rebuild -->` on line 1. A hand edit of that page is
# lost at the next rebuild, and sessions did it anyway (LOOP-012 F10, scn-edit-spec-page).
# The marker is only a request; this gate makes it a refusal and names the spec to edit.
#
# Existing .html files only, line 1 only. A new file, a board's different header
# (`GENERATED <timestamp> by ...`), another extension, or any error exits 0 with no
# output. A marker whose spec is gone passes too: the rebuild the refusal points to is
# impossible, and a dead-end deny pushes the session to a Bash rewrite. Edit/Write only: sed or python through Bash is not covered (owner's scope).
#
# SUNSET — review 2026-12-21. A deny is JUSTIFIED if the session then edits the spec and
# rebuilds. It is NOT if the session switches to a Bash rewrite (sed/python) of the page:
# then the gate only moved the hand edit out of its sight; rethink it.

# -c, not a pipe or heredoc to `python3 -`: those consume the stdin the hook must read.
PYSRC=$(cat <<'PY'
import html, json, os, re, sys
try:
    ev = json.load(sys.stdin)
    path = (ev.get("tool_input") or {}).get("file_path") or ""
    if path.endswith(".html") and os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            first = f.readline()
        m = re.match(r"<!-- GENERATED from (.+?) by /aidex:artifact spec_build\.py", first)
        if m:
            base = os.path.dirname(os.path.abspath(path))
            if os.path.basename(base) == ".aidex-artifact-prev":  # the rebuild's baseline copy
                base = os.path.dirname(base)
            spec = os.path.normpath(os.path.join(base, html.unescape(m.group(1))))
        if m and os.path.isfile(spec):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason":
                    f"{path} is built from a spec (line 1: GENERATED, DO NOT EDIT); a hand "
                    f"edit is lost at the next rebuild. Edit the spec instead: {spec} "
                    "and rebuild with skills/artifact/scripts/spec_build.py (see "
                    "/aidex:artifact)."}}))
except Exception:
    pass
PY
)
python3 -c "$PYSRC" 2>/dev/null
exit 0
