#!/usr/bin/env bash
# usage-retro-corpus.sh — a disposable, hand-written corpus for the usage-retro
# miners: a projects tree with tracked items and a transcript tree with sessions.
#
# Hand-written on purpose. Real transcripts are hundreds of MB and a full miner run
# takes ~4 minutes, so a captured corpus would make the invariants untestable in
# practice — which is how they went unguarded in the first place.
#
# Follows the temp-handling style of coverage-workspace.sh: the CALLER owns cleanup.
# Echoes "<projects-root> <transcripts-root>".
#
# What it encodes (each line exists to discriminate one rule):
#
#   BL-901 / 2026-01-01-alpha  session s1  a real user prompt names it, 1 edit
#                                          -> attributed, and WORKING (prompt rule)
#   BL-902 / 2026-01-02-beta   session s2  named ONLY inside a tool_result payload
#                                          -> attributed to nothing (provenance gate)
#   BL-903 / 2026-01-03-gamma  session s3  no user prompt, 2 edits -> NOT working
#   BL-904 / 2026-01-04-delta  session s4  no user prompt, 3 edits -> WORKING (edit rule)

set -euo pipefail

PROJ="$(mktemp -d)"
TX="$(mktemp -d)"
P="$PROJ/demo_ws"
mkdir -p "$P/.context/backlog"

item() {  # item <id> <slug> <title>
  cat > "$P/.context/backlog/$2.md" <<EOF
---
title: "$3"
id: $1
status: open
created: 2026-01-01
updated: 2026-01-01
type: task
---

# $3
EOF
}

item BL-901 2026-01-01-alpha "Alpha"
item BL-902 2026-01-02-beta  "Beta"
item BL-903 2026-01-03-gamma "Gamma"
item BL-904 2026-01-04-delta "Delta"

# Transcript dir name follows the encoding tx_dirs_for() decodes.
D="$TX/-Users-yoelacevedo-Documents-projects-demo-ws"
mkdir -p "$D"

py_user_prompt() {  # text
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":sys.argv[1]}}))' "$1"
}
# Two tool_result shapes, both real. A census of the 15 largest transcripts
# (40,844 lines, 8,039 tool_result blocks) found inner content as a bare `str`
# 5,849 times and as a `[{"type":"text"}]` list 1,000 times. A fixture carrying
# only one of them leaves the other shape's leak path untested.
py_tool_result() {  # text -> inner content as a bare string
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_result","content":sys.argv[1]}]}}))' "$1"
}
py_tool_result_blocks() {  # text -> inner content as a list of text blocks
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":sys.argv[1]}]}]}}))' "$1"
}
py_assistant_text() {  # text
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$1"
}
py_edit() {  # file_path
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Edit","id":"t","input":{"file_path":sys.argv[1],"old_string":"a","new_string":"b"}}]}}))' "$1"
}

# --- s1: a real user prompt names BL-901 twice, then one edit ---
{
  py_user_prompt "let's work on BL-901 now"
  py_assistant_text "Starting BL-901."
  py_edit "$P/src/alpha.py"
} > "$D/s1.jsonl"

# --- s2: BL-902 appears ONLY inside a tool_result, exactly as reading the backlog
#     index would produce. Nothing here may attribute. ---
{
  py_user_prompt "show me the backlog"
  py_tool_result "BL-902 2026-01-02-beta Beta | BL-902 open | 2026-01-02-beta"
  py_tool_result_blocks "2026-01-02-beta BL-902 2026-01-02-beta BL-902"
  py_edit "$P/src/unrelated.py"
} > "$D/s2.jsonl"

# --- s3: no user prompt names it; assistant text does, plus 2 edits -> not working ---
{
  py_user_prompt "continue"
  py_assistant_text "Working on BL-903 / 2026-01-03-gamma."
  py_edit "$P/src/gamma_a.py"
  py_edit "$P/src/gamma_b.py"
} > "$D/s3.jsonl"

# --- s4: same shape as s3 but 3 edits -> working by the edit rule ---
{
  py_user_prompt "continue"
  py_assistant_text "Working on BL-904 / 2026-01-04-delta."
  py_edit "$P/src/delta_a.py"
  py_edit "$P/src/delta_b.py"
  py_edit "$P/src/delta_c.py"
} > "$D/s4.jsonl"

printf '%s %s\n' "$PROJ" "$TX"
