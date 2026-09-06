#!/usr/bin/env bash
# test-prompt-kinds.sh — pins the predicate that sets the usage-retro denominator.
#
# WHY THIS SUITE EXISTS. Every usage-retro number is a rate over "user prompts".
# The predicate deciding what counts as one was rejecting only `<`-prefixed text,
# so 37.9% of the measured window was machine-authored text counted as typed
# input: SDK harnesses, expanded skill bodies, expanded slash-command bodies,
# compaction summaries, and the handoff wrapper's kickoff positional. That
# inflation reached three published runs before anyone noticed, so the classes
# below are pinned by fixture rather than by docstring.
#
# The load-bearing cases are the ones where a naive rule gets it BACKWARDS:
#   (f) a desktop-app prompt is promptSource="sdk" AND origin.kind="human" — a
#       source-first rule discards 64 real prompts in the validation window
#   (i) a typed "continue" in a session that was NOT handoff-seeded is human
#   (j) injected/kickoff are RETURNED, never dropped — hiding them rebuilds the
#       original bug somewhere new
#
# Run with: bash skills/aidex-audit/tests/test-prompt-kinds.sh

set -uo pipefail

RETRO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/usage-retro" && pwd -P)"
failures=0
cases=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
# Counted, never hardcoded: a printed total that does not come from the
# assertions is the same class of claim this whole suite exists to distrust.
assert_eq() {  # assert_eq <label> <want> <got>
  cases=$((cases + 1))
  [[ "$3" == "$2" ]] || fail "$1: want '$2', got '$3'"
}

run_case() {
  # run_case <label> <expected-kind> <record-json>
  local label="$1" want="$2" rec="$3" got
  got="$(RETRO="$RETRO" REC="$rec" python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["RETRO"])
import prompt_kinds as P
print(P.classify(json.loads(os.environ["REC"]))[0])
PY
)" || { cases=$((cases + 1)); fail "$label: classifier raised"; return; }
  assert_eq "$label" "$want" "$got"
}

human() { printf '{"type":"user","origin":{"kind":"human"},"promptSource":"typed","entrypoint":"cli","message":{"role":"user","content":%s}}' "$1"; }

# ---------------------------------------------------------------- human input
run_case "(a) typed prompt" real "$(human '"arregla el bug del reproductor"')"
run_case "(b) typed slash command" slash "$(human '"/compact"')"
run_case "(c) command-name envelope" slash \
  '{"type":"user","message":{"role":"user","content":"<command-name>aidex-backlog</command-name>"}}'

# The snapshot's own `claude -p "/context"` runs (BL-312): a 2-record transcript
# with no assistant turn. Counting it as a slash prompt would make every
# /aidex context run read as usage in the next retro.
run_case "(c2) snapshot command envelope is not a prompt" skip \
  '{"type":"user","message":{"role":"user","content":"<command-name>/context</command-name>\n            <command-message>context</command-message>\n            <command-args></command-args>"}}'
run_case "(c3) typed /skill-doctor is not a prompt either" skip "$(human '"/skill-doctor"')"

# A prompt with NO provenance fields at all (transcripts predating `origin`)
# must still count as human when nothing marks it otherwise — the fallback is
# a denylist, so the default has to be "human", not "machine".
run_case "(d) no provenance, ordinary text" real \
  '{"type":"user","entrypoint":"cli","message":{"role":"user","content":"como vamos con el plan?"}}'

# ------------------------------------------------------------ machine input
run_case "(e) sdk harness (security-review)" injected \
  '{"type":"user","promptSource":"sdk","entrypoint":"sdk-py","message":{"role":"user","content":"Review this change for security vulnerabilities.\n\nChanged files:\n - a.py"}}'

# THE INVERSION CASE: desktop app stamps promptSource=sdk on genuinely typed
# input. origin.kind must be checked first or these are thrown away.
run_case "(f) desktop app: sdk source BUT human origin" real \
  '{"type":"user","origin":{"kind":"human"},"promptSource":"sdk","entrypoint":"claude-desktop","message":{"role":"user","content":"hazme un resumen de lo que queda"}}'

# THE MIRROR OF (f): the same desktop prompt from a transcript written before
# `origin` existed. Only `entrypoint` may condemn it — a promptSource-only test
# discarded 39 of these, and one whole project read as having no human input.
run_case "(f2) desktop app: sdk source, NO origin (pre-origin transcript)" real \
  '{"type":"user","promptSource":"sdk","entrypoint":"claude-desktop","message":{"role":"user","content":"dime como puedo jugar en ventana"}}'

# And the record with an sdk source and no entrypoint at all stays machine.
run_case "(f3) sdk source, no entrypoint" injected \
  '{"type":"user","promptSource":"sdk","message":{"role":"user","content":"some harness prompt with no entrypoint field"}}'

run_case "(g) expanded skill body, no provenance" injected \
  '{"type":"user","entrypoint":"cli","message":{"role":"user","content":"Approach this as the design lead at a small studio known for their versatility"}}'

run_case "(h) expanded slash-command body" injected \
  '{"type":"user","entrypoint":"cli","message":{"role":"user","content":"# /handoff\n\nCierra esta sesion y abre una nueva"}}'

run_case "(h2) namespaced command body" injected \
  '{"type":"user","entrypoint":"cli","message":{"role":"user","content":"# version:release\n\nCreate a new release"}}'

run_case "(h3) durability-arbiter stop-hook payload" injected \
  '{"type":"user","entrypoint":"cli","message":{"role":"user","content":"You are the durability-arbiter, running as a Claude Code Stop hook"}}'

# ------------------------------------------------------------------- skipped
run_case "(k) image-paste placeholder is not a prompt" skip \
  '{"type":"user","isMeta":true,"message":{"role":"user","content":"[Image: original 1179x2556]"}}'
run_case "(l) tool_result is not a prompt" skip \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}'
run_case "(m) system-reminder envelope" skip \
  '{"type":"user","message":{"role":"user","content":"<system-reminder>be careful</system-reminder>"}}'
run_case "(n) subagent sidechain" skip \
  '{"type":"user","isSidechain":true,"origin":{"kind":"human"},"message":{"role":"user","content":"real looking text"}}'
run_case "(o) skill body injection envelope" skip \
  '{"type":"user","message":{"role":"user","content":"Base directory for this skill is /x"}}'

# ------------------------------------------------- session-level: the kickoff
session_kinds() {
  # session_kinds <seeded:0|1> <first-prompt-text> -> kinds, space separated
  RETRO="$RETRO" SEEDED="$1" TEXT="$2" python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["RETRO"])
import prompt_kinds as P
objs = []
if os.environ["SEEDED"] == "1":
    objs.append({"type": "attachment", "attachment": {
        "type": "hook_additional_context",
        "content": [P.HANDOFF_MARKER + "\n## Objetivo\nseguir el plan"]}})
objs.append({"type": "user", "origin": {"kind": "human"}, "entrypoint": "cli",
             "message": {"role": "user", "content": os.environ["TEXT"]}})
objs.append({"type": "user", "origin": {"kind": "human"}, "entrypoint": "cli",
             "message": {"role": "user", "content": "continue"}})
print(" ".join(k for _, k, _ in P.classify_session(objs)))
PY
}

got="$(session_kinds 1 continue)"
assert_eq "(i1) handoff-seeded 'continue' should be kickoff, and only the FIRST one" "kickoff real" "$got"

got="$(session_kinds 0 continue)"
assert_eq "(i2) 'continue' in a NON-seeded session is a human nudge" "real real" "$got"

got="$(session_kinds 1 'arranca por la fase 1')"
assert_eq "(i3) a seeded session opened with a real instruction has no kickoff" "real real" "$got"

# (j) the machine kinds must be REPORTED, not dropped — a miner that hides them
# reproduces the original defect. classify_session emits one row per user record.
got="$(RETRO="$RETRO" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["RETRO"])
import prompt_kinds as P
objs = [
    {"type": "user", "promptSource": "sdk", "entrypoint": "sdk-py",
     "message": {"role": "user", "content": "Review this change for security vulnerabilities."}},
    {"type": "user", "origin": {"kind": "human"}, "entrypoint": "cli",
     "message": {"role": "user", "content": "y ahora arregla el otro"}},
]
rows = P.classify_session(objs)
print(f"{len(rows)}:{','.join(k for _, k, _ in rows)}")
PY
)"
assert_eq "(j) injected must be returned alongside real, not filtered out" "2:injected,real" "$got"

# (p) the kind vocabularies stay in lockstep with the constants, so a future
# rename cannot leave a consumer testing against a string that no longer exists.
got="$(RETRO="$RETRO" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["RETRO"])
import prompt_kinds as P
ok = (set(P.HUMAN_KINDS) == {P.REAL, P.SLASH}
      and set(P.MACHINE_KINDS) == {P.INJECTED, P.KICKOFF}
      and P.SKIP not in P.HUMAN_KINDS + P.MACHINE_KINDS)
print("ok" if ok else "drift")
PY
)"
[[ "$got" == "ok" ]] || fail "(p) kind vocabulary drifted from the constants: $got"

# (q) is_real_user agrees with classify for the two human kinds, and cannot see
# the kickoff — callers asking "did a human speak in this SESSION" need
# classify_session, and the docstring says so.
got="$(RETRO="$RETRO" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["RETRO"])
import prompt_kinds as P
h = {"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": "hola"}}
m = {"type": "user", "promptSource": "sdk", "entrypoint": "sdk-py",
     "message": {"role": "user", "content": "Review this change for security vulnerabilities."}}
print(f"{P.is_real_user(h)}/{P.is_real_user(m)}")
PY
)"
[[ "$got" == "True/False" ]] || fail "(q) is_real_user disagrees with classify: $got"

if [[ $failures -eq 0 ]]; then
  printf 'PASS: prompt_kinds classifies all %d cases correctly\n' "$cases"
else
  printf '\n%d failure(s)\n' "$failures"
fi
exit $(( failures > 0 ))
