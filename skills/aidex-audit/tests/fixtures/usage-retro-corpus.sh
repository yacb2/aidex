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
#   BL-904 / 2026-01-04-delta  session s5  no user prompt, 2 edits -> NOT working, on a
#                                          CLOSED item, so downstream consumers that
#                                          ignore `working` are observably wrong
#   2026-01-07-eta.html        session s7  a PAGE (kind: page), wrapped by a Bash
#                                          wrap-report.sh --out and named by the user
#   2026-01-04-delta.html                  a page sharing delta's slug -> attached as
#                                          `pages` on the item, never a second key

set -euo pipefail

PROJ="$(mktemp -d)"
TX="$(mktemp -d)"
P="$PROJ/demo_ws"
mkdir -p "$P/.context/backlog"

# `status` and `estimate` exist for the calibration read (BL-131); mine_items
# filters on neither, so the miner scenarios above are unaffected by them.
item() {  # item <id> <slug> <title> <status> <estimate>
  cat > "$P/.context/backlog/$2.md" <<EOF
---
title: "$3"
id: $1
status: $4
created: 2026-01-01
updated: 2026-01-01
type: task
estimate: $5
---

# $3
EOF
}

item BL-901 2026-01-01-alpha "Alpha" done S   # scored
item BL-902 2026-01-02-beta  "Beta"  done S   # excluded: no measurable work
item BL-903 2026-01-03-gamma "Gamma" open M   # excluded: not closed
item BL-904 2026-01-04-delta "Delta" done L   # scored

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
# Bash tool events. The result is paired by tool_use_id, exactly as the real
# corpus does it; there is no exit-code field — a failing command's result is a
# STRING starting "Exit code N\n" with is_error true (verified on real transcripts
# 2026-09-11), and a passing one is the plain output with no flag.
py_bash() {  # id command
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","id":sys.argv[1],"input":{"command":sys.argv[2]}}]}}))' "$1" "$2"
}
py_bash_ok() {  # id output
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_result","tool_use_id":sys.argv[1],"content":sys.argv[2]}]}}))' "$1" "$2"
}
py_bash_fail() {  # id exit-code output
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"content":[{"type":"tool_result","tool_use_id":sys.argv[1],"content":"Exit code "+sys.argv[2]+"\n"+sys.argv[3],"is_error":True}]}}))' "$1" "$2" "$3"
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

# --- s5: delta again, but assistant-text mention + only 2 edits -> a NON-working
#     span on a CLOSED item. Without this the strict-span rule is unobservable
#     downstream: gamma is the only other non-working span and it is excluded by
#     status anyway, so a consumer that ignored `working` would still look right.
{
  py_user_prompt "continue"
  py_assistant_text "Back on BL-904 / 2026-01-04-delta."
  py_edit "$P/src/delta_a.py"
  py_edit "$P/src/delta_d.py"
} > "$D/s5.jsonl"

# --- s6: TOOL EVENTS, no tracked item named (attribution stays empty). A sweep
#     close refused with exit 2, the same command retried, a `cat` of a script path
#     (a read, not a run), and a subagent transcript that runs validate.py. ---
{
  py_user_prompt "sweep the backlog"
  py_bash b1 "bash skills/aidex-backlog/scripts/close-item.sh --sweep BL-777"
  py_bash_fail b1 2 "refused: item is not closable under --sweep"
  py_bash b2 "bash skills/aidex-backlog/scripts/close-item.sh --sweep BL-777"
  py_bash_fail b2 2 "refused: item is not closable under --sweep"
  py_bash b3 "cat skills/aidex-backlog/scripts/close-item.sh"
  py_bash_ok b3 "#!/usr/bin/env bash"
} > "$D/s6.jsonl"
mkdir -p "$D/s6/subagents"
{
  py_user_prompt "validate the tree"
  py_bash b4 "python3 skills/aidex-conventions/scripts/validate.py --type plans"
  py_bash_ok b4 "OK"
} > "$D/s6/subagents/agent-x.jsonl"

# --- pages: a dated page in reports/, one in an _archive/, a rendered board and a
#     wrap's prior copy (both skipped), and a page whose slug is BL-904's ---
mkdir -p "$P/.context/reports/_archive" "$P/.context/reports/.aidex-artifact-prev"
page() {  # path title
  printf '<title>%s</title>\n<main class="main"><section data-id="q1" data-decided>x</section></main>\n' "$2" > "$1"
}
page "$P/.context/reports/2026-01-07-eta.html" "Eta"
page "$P/.context/reports/_archive/2026-01-08-theta.html" "Theta"
page "$P/.context/reports/00-index.html" "Board"
page "$P/.context/reports/.aidex-artifact-prev/2026-01-07-eta.html" "Eta prev"
page "$P/.context/reports/2026-01-04-delta.html" "Delta page"

# --- s7: the user names the eta page and the session wraps it ---
{
  py_user_prompt "wrap the 2026-01-07-eta consultation"
  py_bash b5 "bash ~/.claude/skills/aidex-dash/scripts/wrap-report.sh --in _tmp/eta.md --out .context/reports/2026-01-07-eta.html"
  py_bash_ok b5 "wrote .context/reports/2026-01-07-eta.html"
} > "$D/s7.jsonl"

printf '%s %s\n' "$PROJ" "$TX"
