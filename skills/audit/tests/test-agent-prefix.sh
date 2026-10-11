#!/usr/bin/env bash
# test-agent-prefix.sh — a plugin-launched agent (`aidex:impl-sonnet`) and the same
# agent launched by its bare name (`impl-sonnet`) are ONE series in the usage-retro
# scripts that key on the agent type. Two series would split one agent's count and
# spend in half, and every table would still print.
#
# Cases per script (bare only, prefixed only, mixed): one key, the summed count.
#   extract.py        agents_in_assistant: the `subagent_type` of Agent/Task launches
#   subagent_spend.py agent_meta/walk: the `agentType` of a subagent transcript meta
#
# Run with: bash skills/audit/tests/test-agent-prefix.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RETRO="$HERE/../scripts/usage-retro"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# --- extract.py: count per agent type over launches in assistant records ---
count_launches() {  # count_launches <type>...  -> "name=count" lines
  python3 - "$RETRO" "$@" <<'PY'
import collections, importlib.util, sys
spec = importlib.util.spec_from_file_location("extract", sys.argv[1] + "/extract.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
c = collections.Counter()
for t in sys.argv[2:]:
    rec = {"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Agent", "input": {"subagent_type": t}}]}}
    c.update(m.agents_in_assistant(rec))
print(",".join(f"{k}={v}" for k, v in sorted(c.items())))
PY
}
[[ "$(count_launches impl-sonnet impl-sonnet)" == "impl-sonnet=2" ]] || fail "extract bare-only: $(count_launches impl-sonnet impl-sonnet)"
[[ "$(count_launches aidex:impl-sonnet aidex:impl-sonnet)" == "impl-sonnet=2" ]] || fail "extract prefixed-only: $(count_launches aidex:impl-sonnet aidex:impl-sonnet)"
[[ "$(count_launches impl-sonnet aidex:impl-sonnet aidex:impl-sonnet)" == "impl-sonnet=3" ]] || fail "extract mixed: $(count_launches impl-sonnet aidex:impl-sonnet aidex:impl-sonnet)"

# --- subagent_spend.py: rows per (model, agent type) over subagent metas ---
spend_rows() {  # spend_rows <agentType>...  -> the table rows naming an agent type
  local TX; TX="$(mktemp -d)"
  python3 - "$TX" "$@" <<'PY'
import json, os, sys
tx, types = sys.argv[1], sys.argv[2:]
sub = f"{tx}/-proj/s1/subagents"
os.makedirs(sub)
for i, t in enumerate(types):
    base = f"{sub}/agent-a{i}"
    open(base + ".meta.json", "w").write(json.dumps({"agentType": t, "model": "claude-sonnet-5-5"}))
    open(base + ".jsonl", "w").write(json.dumps({"isSidechain": True, "message": {
        "id": f"msg_{i}", "role": "assistant", "model": "claude-sonnet-5-5",
        "usage": {"input_tokens": 10, "output_tokens": 5}}}) + "\n")
PY
  python3 "$RETRO/subagent_spend.py" --transcripts-root "$TX" | grep -E '^claude-' | awk '{print $1, $2, $3, $4}'
  rm -rf "$TX"
}
want="claude-sonnet-5-5 / impl-sonnet"
check_spend() {  # check_spend <turns> <label> <types>...
  local turns="$1" label="$2"; shift 2
  local got; got="$(spend_rows "$@")"
  [[ "$got" == "$want $turns" ]] || fail "spend $label: got '$got', want '$want $turns'"
}
check_spend 2 bare-only impl-sonnet impl-sonnet
check_spend 2 prefixed-only aidex:impl-sonnet aidex:impl-sonnet
check_spend 3 mixed impl-sonnet aidex:impl-sonnet aidex:impl-sonnet

if [[ $failures -eq 0 ]]; then echo "PASS: test-agent-prefix"; else echo "$failures failure(s)"; exit 1; fi
