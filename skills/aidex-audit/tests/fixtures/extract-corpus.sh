#!/usr/bin/env bash
# extract-corpus.sh — a disposable transcript corpus for extract.py, the front of
# the usage-retro pipeline.
#
# Hand-written, like usage-retro-corpus.sh: every session below exists to
# discriminate ONE provenance rule, and each rule is one that already shipped
# broken. The corpus is transcripts only — extract.py reads no projects tree.
#
# The CALLER owns cleanup. Echoes "<transcripts-root>".
#
# What it encodes:
#
#   s1  a typed prompt, then an EXPANDED SLASH-COMMAND BODY, then an INJECTED
#       harness body. Only the typed prompt may reach the dataset. The two
#       machine records sit BETWEEN the typed prompt and a later skill fire, so
#       a look-ahead that walks past them credits their skill fires to the human
#       prompt — the exact defect BL-165 names.
#   s2  a handoff-seeded session whose first human-looking record is the
#       wrapper's "continue" positional (a KICKOFF, machine), followed by a real
#       prompt. The kickoff must not appear; the real prompt must.
#   s3  a session with only machine records, so the excluded COUNT has to be
#       non-zero and reported — a silently smaller denominator is the original bug.
#   s4/s5  one session resumed into a second transcript file, replaying its
#       earlier prompt. One thing said once must be one record, and the new
#       prompt in the second file must survive the dedup.
#   s6  two DIFFERENT prompts at the SAME timestamp, so a dedup keyed on the
#       timestamp alone is caught eating a real record.
#   s10/s11  a SHORT prompt (below NEAR_DUP_MINLEN) replayed at the SAME
#       timestamp. The only pair that isolates the exact-key dedup branch: s4/s5
#       clear the near-dup length floor, so the near branch collapses them even
#       with the exact branch disabled.

set -euo pipefail

TX="$(mktemp -d)"
D="$TX/-Users-yoelacevedo-Documents-projects-demo-ws"
mkdir -p "$D"

# Records carry `origin.kind` where a real Claude Code transcript would. The
# fixture must not lean on the content fallback alone: the structural signal is
# the primary mechanism and the fallback is only a safety net for old data.
py_typed() {  # text [ts]
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":sys.argv[2],
    "origin":{"kind":"human"},"message":{"content":sys.argv[1]}}))' "$1" "${2:-2026-01-01T10:00:00Z}"
}
py_plain() {  # text [ts] — no provenance fields, as pre-`origin` transcripts have
  python3 -c 'import json,sys; print(json.dumps({"type":"user","timestamp":sys.argv[2],
    "message":{"content":sys.argv[1]}}))' "$1" "${2:-2026-01-01T10:00:00Z}"
}
py_assistant_text() {  # text
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","timestamp":"2026-01-01T10:00:00Z",
    "message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$1"
}
py_skill() {  # skill name
  python3 -c 'import json,sys; print(json.dumps({"type":"assistant","timestamp":"2026-01-01T10:00:00Z",
    "message":{"content":[{"type":"tool_use","name":"Skill","id":"t","input":{"skill":sys.argv[1]}}]}}))' "$1"
}

# --- s1: typed prompt, then two machine bodies, each followed by a skill fire ---
# ORDER IS THE POINT. If the look-ahead treats a machine body as "not a prompt"
# it keeps walking, and aidex-comm + session-handoff land on the typed prompt.
{
  py_typed "add a notes field to the report and keep it in every version" "2026-01-01T10:00:00Z"
  py_skill "aidex-plan"
  py_plain "# /handoff
Close the current session and open a new one, seeding handoff context." "2026-01-01T10:05:00Z"
  py_skill "session-handoff"
  py_plain "Review this change for security vulnerabilities. Report only high-confidence findings." "2026-01-01T10:10:00Z"
  py_skill "aidex-comm"
  py_assistant_text "Done."
} > "$D/s1.jsonl"

# --- s2: handoff-seeded; the wrapper's kickoff is machine, the next prompt is not ---
{
  python3 -c 'import json; print(json.dumps({"type":"user","isMeta":True,
    "timestamp":"2026-01-02T09:00:00Z","message":{"content":
    "=== HANDOFF FROM PREVIOUS SESSION ===\nresume the plan"}}))'
  py_typed "continue" "2026-01-02T09:00:01Z"
  py_assistant_text "Resuming."
  py_typed "no, primero mide el recall antes de seguir" "2026-01-02T09:30:00Z"
} > "$D/s2.jsonl"

# --- s3: nothing but machine records, so the exclusion count cannot be zero ---
{
  py_plain "Approach this as the design lead and produce the page." "2026-01-03T08:00:00Z"
  py_assistant_text "ok"
  py_plain "You are the durability-arbiter. Return CONTINUE, ASK or STOP." "2026-01-03T08:05:00Z"
} > "$D/s3.jsonl"

# --- s4/s5: the SAME session resumed into a second file --------------------
# Claude Code opens a new .jsonl for a resumed or forked session and replays the
# earlier records into it. A file-walking extractor emits the replayed prompt
# once per file, so one thing the user said becomes two data points (BL-170).
# The second file also carries a NEW prompt, which must survive.
{
  py_typed "usa siempre mockups cuando presentes alternativas" "2026-01-04T07:00:00Z"
  py_assistant_text "ok"
} > "$D/s4.jsonl"
{
  py_typed "usa siempre mockups cuando presentes alternativas" "2026-01-04T07:00:00Z"
  py_assistant_text "ok"
  py_typed "y ahora sigue con la fase dos" "2026-01-04T07:30:00Z"
} > "$D/s5.jsonl"

# --- s7/s8: the same fork, but the replay gets a FRESH timestamp ------------
# The observed pair was 4.19s apart across two session files, so an exact-ts key
# does not see it. What separates it from a real repetition is length: nobody
# retypes 125 characters byte-identically in four seconds, while "continue" is
# retyped constantly. Both axes are asserted, because either one alone is wrong.
LONG="presentame esto en un artefacto en espanol, usa graficos o mockups para apoyarte al presentar, y dame la opcion de dejar notas"
{
  py_typed "$LONG" "2026-01-06T07:00:00Z"
  py_assistant_text "ok"
} > "$D/s7.jsonl"
{
  py_typed "$LONG" "2026-01-06T07:00:05Z"
  py_assistant_text "ok"
  py_typed "continue" "2026-01-06T07:00:30Z"
  py_assistant_text "ok"
  py_typed "continue" "2026-01-06T07:00:35Z"
} > "$D/s8.jsonl"

# --- s9: the same long prompt, genuinely asked again much later -------------
# A window with no upper bound would collapse a preference the user had to
# repeat — which is the very signal STANDING-PREFERENCE exists to count.
{
  py_typed "$LONG" "2026-01-07T09:00:00Z"
  py_assistant_text "ok"
} > "$D/s9.jsonl"

# --- s10/s11: a SHORT prompt replayed at the SAME timestamp -----------------
# This is the only pair that isolates the exact-timestamp dedup branch. s4/s5
# replay a 49-character prompt, which is >= NEAR_DUP_MINLEN (40) and 0s apart, so
# the near-dup predicate catches it on both axes — disabling the exact branch
# entirely (`if key in seen:` -> `if False:`) left the record count unchanged and
# the suite fully green. Below the length floor the near-dup branch cannot fire, so
# only the exact key can collapse this, and the mutation becomes visible.
#
# It is also the realistic case the corpus comment calls out: a short prompt
# written twice at one timestamp into a resumed session file.
{
  py_typed "sigue con eso" "2026-01-08T08:00:00Z"
} > "$D/s10.jsonl"
{
  py_typed "sigue con eso" "2026-01-08T08:00:00Z"
} > "$D/s11.jsonl"

# --- s6: two DIFFERENT prompts sharing one timestamp -----------------------
# Dedup keyed on the timestamp alone would silently eat one of these. The key
# has to include the text, or the fix trades a 0.4% inflation for a real loss.
{
  py_typed "primera pregunta distinta" "2026-01-05T07:00:00Z"
  py_assistant_text "ok"
  py_typed "segunda pregunta distinta" "2026-01-05T07:00:00Z"
} > "$D/s6.jsonl"

printf '%s\n' "$TX"
