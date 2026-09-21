#!/bin/sh
# PreToolUse hook — refuse a new DATED file at a project's `.context/references/` root.
#
# references/ is evergreen by name (reference-conventions.md). A dated
# write-up dropped there is research's spike shape in the wrong folder, and nothing caught
# it: the ISO name passed validate.py, and no skill runs when a session writes a finding
# by hand — 17 of them landed in one workspace in six days (2026-09-16..21). The deny
# reason carries the routing of 00-global.md §8.1, so the block teaches the right home.
#
# Write only: an Edit never creates a file, and a legacy flat file must stay editable
# until it is moved. Deterministic path match, no judgement, and any error exits 0 with
# no output — there is no input on which it can prevent work by failing.
#
# SUNSET — review 2026-12-21. A block is JUSTIFIED if the content ended up in another
# folder. If sessions answer the deny by inventing a topic folder per finding
# (references/<topic>/ with one dated module), the gate moved the mess instead of
# routing it: demote it to the validator rule alone.

# -c, not a pipe or heredoc to `python3 -`: those consume the stdin the hook must read.
PYSRC=$(cat <<'PY'
import json, re, sys
try:
    ev = json.load(sys.stdin)
    path = (ev.get("tool_input") or {}).get("file_path") or ""
    if ev.get("tool_name") == "Write" and \
            re.search(r"/\.context/references/\d{4}-?\d{2}-?\d{2}-[^/]+$", path):
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason":
                "references/ is evergreen and takes no dated file (00-global.md section 8.1). "
                "Findings, gotchas or leftovers of a run, an incident analysis, a readout "
                "or census: .context/research/YYYY-MM-DD-<slug>.md (/aidex:research). "
                "A log of a running experiment: next to it in experiments/. "
                "Settled how-it-works content: a module in references/<topic>/ "
                "(/aidex:reference). Something to do later: /aidex:backlog."}}))
except Exception:
    pass
PY
)
python3 -c "$PYSRC" 2>/dev/null
exit 0
