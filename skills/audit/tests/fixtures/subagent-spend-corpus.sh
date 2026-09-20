#!/usr/bin/env bash
# subagent-spend-corpus.sh — a disposable, hand-written transcript corpus for
# subagent_spend.py (BL-402).
#
# Hand-written for the same reason preferences-corpus.sh is: the real corpus is
# hundreds of MB, so a captured fixture would make these invariants untestable in
# practice. The CALLER owns cleanup. Echoes "<transcripts-root>".
#
# Every number below is small and round so the expected totals can be computed by
# hand in the test, which is the point: a fixture whose totals are only reproducible
# by running the script under test proves nothing. The one exception is a7, which
# copies a REAL record's numbers verbatim (see below).
#
# One project, two main transcripts, nine subagents. Each exists to discriminate ONE
# rule:
#
#   s1.jsonl            main session. Carries a <synthetic> turn that must NOT count;
#                       the `msg_launch` turn that a1 replays; an UNPRICED turn, so
#                       `main` mixes priced and unpriced models; and `msg_main_adv`,
#                       whose settled usage hides an advisor iteration on a DIFFERENT
#                       model
#   s1-resumed.jsonl    a resumed session replaying s1's `msg_main_1` verbatim. Dedupe
#                       is per PROJECT, not per file, or this turn is billed twice
#   a1  impl-opus       meta names a model -> NO "(inherited)" label. Its first API
#                       message is written over TWO lines under one message.id (the
#                       partial, output_tokens=1, then the final) -> counted ONCE with
#                       the LAST line's numbers. Its FIRST line is the main session's
#                       `msg_launch` turn replayed as launch context, with a stale
#                       output_tokens -> credited to `main`, never to a1
#   a2  lookup-sonnet   meta has no `model` key -> "(inherited)"; its usage carries
#                       only the flat `cache_creation_input_tokens`, no dict
#   a3  probe           an unpriced model -> USD "n/a", tokens still counted
#   a4  workflow-...    lives in a NESTED subagents/workflows/wf_*/ directory, and its
#                       meta names a model. Same model as a2, different agent type and
#                       a different label: a reader that groups by model alone, or
#                       that labels the whole model "(inherited)", collapses these two
#   a5  (no meta file)  -> agent type "unknown", and inherited by the same rule
#   a6  advisor-host    a settled message whose `usage.iterations` holds a
#                       `type: "advisor_message"` on ANOTHER model, billed separately
#                       and absent from the top-level block
#   a7  stale-dict      the real record's shape: flat cache_creation_input_tokens is
#                       the aggregate over iterations while `cache_creation` still
#                       holds iteration 0 only
#   a8  (meta is `[]`)  valid JSON, not an object -> agent type "unknown", NO
#                       inherited label, a warning on stderr, exit 0
#   a9  (truncated meta) invalid JSON -> the same treatment as a8
#
# Every subagent line carries "isSidechain": true. That is load-bearing: the defect
# this instrument exists to not reproduce (claude-session-handoff BL-035) is a global
# isSidechain filter that drops every one of these turns.

set -euo pipefail

TX="$(mktemp -d)"
P="$TX/-Users-user-Documents-projects-demo-ws"
SUB="$P/s1/subagents"
WF="$SUB/workflows/wf_deadbeef01"
mkdir -p "$SUB" "$WF"

OPUS="claude-opus-5-20260301"
SONNET="claude-sonnet-5-20260201"
UNPRICED="claude-mystery-9-20260101"

# turn <model> <sidechain:true|false> <msg-id> <input> <5m> <1h> <read> <output>
turn() {
  python3 -c '
import json, sys
m, side, mid, i, c5, c1, cr, o = sys.argv[1:9]
print(json.dumps({
    "type": "assistant", "isSidechain": side == "true",
    "timestamp": "2026-09-01T10:00:00.000Z",
    "message": {"id": mid, "role": "assistant", "model": m,
                "content": [{"type": "text", "text": "..."}],
                "usage": {"input_tokens": int(i),
                          "cache_creation": {"ephemeral_5m_input_tokens": int(c5),
                                             "ephemeral_1h_input_tokens": int(c1)},
                          "cache_creation_input_tokens": int(c5) + int(c1),
                          "cache_read_input_tokens": int(cr),
                          "output_tokens": int(o)}}}))' "$@"
}

# turn_flat — the older usage shape: no `cache_creation` dict, only the flat
# `cache_creation_input_tokens`, which the token rule must read as 5m creation.
# turn_flat <model> <msg-id> <input> <create> <read> <output>
turn_flat() {
  python3 -c '
import json, sys
m, mid, i, cc, cr, o = sys.argv[1:7]
print(json.dumps({
    "type": "assistant", "isSidechain": True,
    "timestamp": "2026-09-01T10:00:00.000Z",
    "message": {"id": mid, "role": "assistant", "model": m,
                "content": [{"type": "text", "text": "..."}],
                "usage": {"input_tokens": int(i),
                          "cache_creation_input_tokens": int(cc),
                          "cache_read_input_tokens": int(cr),
                          "output_tokens": int(o)}}}))' "$@"
}

# turn_advisor — a SETTLED message carrying an advisor iteration. Copied from the
# real shape (aidex--tmp-e1-wt-D1-1/2be6c672-.../subagents/agent-a7b84bdf94e3a0c87
# .jsonl, msg_011Cf1M4DFVUd5zfJQucdSCo): the top-level block is the sum of the
# `type: "message"` iterations ONLY, and the advisor iteration — its own model, its
# own tokens, billed separately — appears nowhere in it.
# turn_advisor <model> <sidechain> <msg-id> <in> <read> <out> <advisor-model> <adv-in> <adv-out>
turn_advisor() {
  python3 -c '
import json, sys
m, side, mid, i, cr, o, am, ai, ao = sys.argv[1:10]
it = lambda t, mdl, i, o, cr: {"input_tokens": int(i), "output_tokens": int(o),
                               "cache_read_input_tokens": int(cr),
                               "cache_creation_input_tokens": 0,
                               "cache_creation": {"ephemeral_5m_input_tokens": 0,
                                                  "ephemeral_1h_input_tokens": 0},
                               "type": t, "model": mdl}
print(json.dumps({
    "type": "assistant", "isSidechain": side == "true",
    "timestamp": "2026-09-01T10:00:00.000Z",
    "message": {"id": mid, "role": "assistant", "model": m,
                "content": [{"type": "text", "text": "..."}],
                "usage": {"input_tokens": int(i),
                          "cache_creation": {"ephemeral_5m_input_tokens": 0,
                                             "ephemeral_1h_input_tokens": 0},
                          "cache_creation_input_tokens": 0,
                          "cache_read_input_tokens": int(cr),
                          "output_tokens": int(o),
                          "iterations": [it("message", None, i, o, cr),
                                         it("advisor_message", am, ai, ao, 0)]}}}))' "$@"
}

meta() {  # meta <path> <agentType> [model]
  python3 -c '
import json, sys
d = {"agentType": sys.argv[2], "toolUseId": "toolu_01", "spawnDepth": 1,
     "description": "fixture agent"}
if len(sys.argv) > 3 and sys.argv[3]:
    d["model"] = sys.argv[3]
open(sys.argv[1], "w").write(json.dumps(d))' "$@"
}

# --- main session. `msg_main_1` and `msg_main_2` are the plain turns; the rest each
#     carry one trap. The <synthetic> placeholder is written with a FULL usage block,
#     which is what Claude Code does, so a reader that skips those by text rather
#     than by model banks all of it. ---
{
  turn "$OPUS" false msg_main_1 1000 2000 1000 10000 500
  python3 -c '
import json
print(json.dumps({"type": "assistant", "timestamp": "2026-09-01T10:00:01.000Z",
                  "message": {"id": "msg_main_synth", "role": "assistant",
                              "model": "<synthetic>",
                              "content": [{"type": "text", "text": "No response requested."}],
                              "usage": {"input_tokens": 999999,
                                        "cache_creation": {"ephemeral_5m_input_tokens": 999999,
                                                           "ephemeral_1h_input_tokens": 999999},
                                        "cache_read_input_tokens": 999999,
                                        "output_tokens": 999999}}}))'
  turn "$OPUS" false msg_main_2 0 0 0 20000 1000
  # the turn that launched a1; a1's transcript replays it (see below)
  turn "$OPUS" false msg_launch 5 0 0 100 50
  # an unpriced model INSIDE the main session, so `main` mixes priced and unpriced
  turn "$UNPRICED" false msg_main_unpriced 1 0 0 0 1
  # a main-session advisor iteration, on a cheaper model than the session's own
  turn_advisor "$OPUS" false msg_main_adv 4 200 20 "$SONNET" 500 30
} > "$P/s1.jsonl"

# --- the RESUME. Claude Code replays the parent's records into the new session file,
#     verbatim (censused: 571 of 571 main-vs-main duplicate ids carry identical
#     tokens). Deduping per file bills `msg_main_1` twice. Sorts BEFORE s1.jsonl, so
#     the assertion does not depend on which of the two the walker reaches first. ---
turn "$OPUS" false msg_main_1 1000 2000 1000 10000 500 > "$P/s1-resumed.jsonl"

# --- a1: THE SPLIT MESSAGE, and the LAUNCH REPLAY.
#     Line 0 is the main session's own `msg_launch` turn, replayed into the child as
#     launch context with a stale output_tokens (7 against the real 50) — the real
#     shape, censused at 7 cases. It is the parent's turn, produced by the parent, so
#     it belongs to `main`; crediting a1 charges the parent's thinking to the child,
#     which is the comparison this whole table exists to make.
#     Lines 1-2 are one message over two lines: the partial (output_tokens 1) then
#     the settled one. Dropping the dedupe double-counts; keeping the FIRST reports 1. ---
{
  turn "$OPUS" true msg_launch 5 0 0 100 7
  turn "$OPUS" true msg_a1_1 100 200 0 1000 1
  turn "$OPUS" true msg_a1_1 100 200 0 1000 400
  turn "$OPUS" true msg_a1_2 0 0 0 2000 100
} > "$SUB/agent-a1.jsonl"
meta "$SUB/agent-a1.meta.json" impl-opus opus

# --- a2: no `model` key in the meta -> the row is labelled inherited. ---
turn_flat "$SONNET" msg_a2_1 200 100 5000 300 > "$SUB/agent-a2.jsonl"
meta "$SUB/agent-a2.meta.json" lookup-sonnet

# --- a3: a model no price table knows. Its tokens still count; only its USD is n/a. ---
turn "$UNPRICED" true msg_a3_1 10 20 30 40 50 > "$SUB/agent-a3.jsonl"
meta "$SUB/agent-a3.meta.json" probe mystery

# --- a4: NESTED under subagents/workflows/wf_*/. 7,289 of the author's agent
#     transcripts live at this depth; a one-level glob sees none of them. ---
turn "$SONNET" true msg_a4_1 50 0 0 1000 100 > "$WF/agent-a4.jsonl"
meta "$WF/agent-a4.meta.json" workflow-subagent sonnet
# journal.jsonl sits beside the agents in the real tree and is not a transcript.
printf '%s\n' '{"type":"started","key":"v2:abc","agentId":"a4"}' > "$WF/journal.jsonl"

# --- a5: no meta file at all -> agent type "unknown", inherited by the same rule. ---
turn "$SONNET" true msg_a5_1 10 0 0 100 10 > "$SUB/agent-a5.jsonl"

# --- a6: THE ADVISOR ITERATION. A sonnet subagent whose settled message hides 1000
#     input and 200 output on OPUS. Corpus-wide that is 20,736 advisor iterations, and
#     leaving them in the top-level block's shadow both LOSES the spend and, worse,
#     would credit it to the cheap model if anyone summed the iterations naively. ---
turn_advisor "$SONNET" true msg_a6_1 2 0 100 "$OPUS" 1000 200 > "$SUB/agent-a6.jsonl"
meta "$SUB/agent-a6.meta.json" advisor-host sonnet

# --- a7: THE STALE DICT, with the real record's numbers. Top-level flat is 8480 (the
#     aggregate over both `message` iterations) while `cache_creation.ephemeral_5m`
#     still holds 6976, iteration 0's value alone. Preferring the dict loses 1504. ---
python3 -c '
import json
print(json.dumps({
    "type": "assistant", "isSidechain": True,
    "timestamp": "2026-09-01T10:00:00.000Z",
    "message": {"id": "msg_a7_1", "role": "assistant",
                "model": "claude-sonnet-5-20260201",
                "content": [{"type": "text", "text": "..."}],
                "usage": {"input_tokens": 34,
                          "cache_creation_input_tokens": 8480,
                          "cache_read_input_tokens": 43490,
                          "cache_creation": {"ephemeral_1h_input_tokens": 0,
                                             "ephemeral_5m_input_tokens": 6976},
                          "output_tokens": 2839}}}))' > "$SUB/agent-a7.jsonl"
meta "$SUB/agent-a7.meta.json" stale-dict sonnet

# --- a8: a meta that is valid JSON but NOT an object. `.get` on a list raises, and
#     one bad file took the whole report down with an AttributeError. ---
turn "$SONNET" true msg_a8_1 7 0 0 70 7 > "$SUB/agent-a8.jsonl"
printf '%s' '[]' > "$SUB/agent-a8.meta.json"

# --- a9: a TRUNCATED meta — a write interrupted mid-flush. Folding it into the same
#     bucket as "no meta at all" is worse than crashing: the agent type is lost AND
#     the row claims the model was inherited, with nothing on stderr to say so. ---
turn "$OPUS" true msg_a9_1 3 0 0 30 3 > "$SUB/agent-a9.jsonl"
printf '%s' '{"agentType": "impl-' > "$SUB/agent-a9.meta.json"

printf '%s\n' "$TX"
