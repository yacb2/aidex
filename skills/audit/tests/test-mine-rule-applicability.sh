#!/usr/bin/env bash
# test-mine-rule-applicability.sh — LOOP-013 audit-c10: the autonomy signature must fire
# on a plugin-era session, whose Skill call is named `aidex:plan-exec`, not bare `plan-exec`.
#
# Layer: script over a synthetic HOME (the miner reads ~/.claude/projects and
# ~/.claude/rules); the failure is a silent 0.0% rate, observable only by running it.
# Run with: bash skills/audit/tests/test-mine-rule-applicability.sh
set -uo pipefail
MINER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/mine-rule-applicability.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
P="$W/.claude/projects/-Users-u-Documents-projects-app"
mkdir -p "$P" "$W/.claude/rules"
printf 'one two three\n' > "$W/.claude/rules/autonomy.md"
python3 - "$P" <<'PY'
import json, sys
d = sys.argv[1]
def sess(name, skill):
    ev = [{"type": "user", "message": {"role": "user", "content": "please run the plan"}},
          {"type": "assistant", "message": {"content": [
              {"type": "tool_use", "name": "Skill", "input": {"skill": skill}}]}}]
    open(f"{d}/{name}.jsonl", "w").write("\n".join(json.dumps(e) for e in ev) + "\n")
sess("a", "aidex:plan-exec")   # plugin-era name
sess("b", "plan-exec")         # bare name
sess("c", "other:audit")       # another plugin's skill of the same bare name: not ours
PY
out="$(HOME="$W" python3 "$MINER" 2>&1)"
line="$(grep -E '^autonomy ' <<<"$out")"
# 3 sessions: a and b fire the signature, c does not -> 2 events
if grep -qE ' +2 +[0-9]+' <<<"$line" && grep -q '66.7%' <<<"$line"; then
  echo "OK — autonomy fires for aidex:<skill> and bare names, not for another plugin's"
else
  echo "FAIL: expected autonomy rate 66.7% / 2 events, got: ${line:-<none>}"; echo "$out"; exit 1
fi
