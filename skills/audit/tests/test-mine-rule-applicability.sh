#!/usr/bin/env bash
# test-mine-rule-applicability.sh — a live rule's signature fires on the sessions that hit it
# and only on those (artifacts-local-first: the Artifact tool or an .html write). The six
# signatures of retired rule files were deleted (Q8, audit-s09); this fixture used the autonomy rule.
#
# Layer: script over a synthetic HOME (the miner reads ~/.claude/projects and
# ~/.claude/rules); the failure is a silent 0.0% rate, observable only by running it.
# Run with: bash skills/audit/tests/test-mine-rule-applicability.sh
set -uo pipefail
MINER="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/mine-rule-applicability.py"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
P="$W/.claude/projects/-Users-u-Documents-projects-app"
mkdir -p "$P" "$W/.claude/rules"
printf 'one two three\n' > "$W/.claude/rules/artifacts-local-first.md"
printf 'one two three\n' > "$W/.claude/rules/autonomy.md"   # a retired rule file: no signature, never measured
python3 - "$P" <<'PY'
import json, sys
d = sys.argv[1]
def sess(name, tool, inp):
    ev = [{"type": "user", "message": {"role": "user", "content": "please make the page"}},
          {"type": "assistant", "message": {"content": [
              {"type": "tool_use", "name": tool, "input": inp}]}}]
    open(f"{d}/{name}.jsonl", "w").write("\n".join(json.dumps(e) for e in ev) + "\n")
sess("a", "Write", {"file_path": "/tmp/p/report.html"})   # .html write
sess("b", "Artifact", {})                                  # Artifact tool
sess("c", "Write", {"file_path": "/tmp/p/notes.txt"})      # neither: not this rule
sess("d", "Skill", {"skill": "aidex:plan-exec"})           # what the deleted autonomy signature counted
PY
out="$(HOME="$W" python3 "$MINER" 2>&1)"
line="$(grep -E '^artifacts-local-first ' <<<"$out")"
# 4 sessions: a and b fire the signature, c does not -> 2 events
auto="$(grep -E '^autonomy ' <<<"$out")"
if grep -qE ' +2 +[0-9]+' <<<"$line" && grep -q '50.0%' <<<"$line" && grep -q 'not measurable' <<<"$auto"; then
  echo "OK — artifacts-local-first fires for an .html write and the Artifact tool, not for a .txt write; the retired autonomy rule is not measured"
else
  echo "FAIL: expected artifacts-local-first rate 50.0% / 2 events and autonomy not measurable, got: ${line:-<none>} / ${auto:-<none>}"; echo "$out"; exit 1
fi
