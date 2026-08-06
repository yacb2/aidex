#!/usr/bin/env bash
# Publish-policy lockstep guard: the two aidex surfaces vs the Artifact tool's own default.
#
# Regression this locks (BL-081, 2026-07-24):
#   Three layers gave three readings of one action. `rules/artifacts-local-first.md` and
#   `skills/aidex-dash/SKILL.md` both say never publish unprompted; the harness-supplied
#   `Artifact` tool description says the opposite ("publishing proactively is fine for your
#   own work-product"). An agent that had just built a local report had to reconcile them
#   with nothing on the page saying which wins, so the conflict read as a contradiction
#   rather than as a deliberate override.
#
# Invariants:
#   (1) both aidex surfaces gate publishing on an explicit user ask — they never drift apart;
#   (2) the rule ACKNOWLEDGES the tool's opposite default and declares itself the winner.
#       Without (2) the agent is left arbitrating between two silent absolutes, which is the
#       exact failure this item was filed for. Restating the prohibition louder does not fix
#       it; naming the loser does.
#
# Run with: bash skills/aidex-conventions/scripts/test_publish_policy_lockstep.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
RULE="$ROOT/rules/artifacts-local-first.md"
DASH="$ROOT/skills/aidex-dash/SKILL.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

for f in "$RULE" "$DASH"; do
  [[ -f "$f" ]] || { echo "FAIL: expected surface not found at $f"; exit 1; }
done

# ---------- (1) both surfaces still gate on an explicit ask ----------
grep -qiE 'only.*when explicitly asked|explicitly asked to share' "$RULE" \
  || fail "(1) rules/artifacts-local-first.md no longer gates publishing on an explicit user ask"
grep -qiE 'NEVER call the .?Artifact.? tool unprompted' "$DASH" \
  || fail "(1) skills/aidex-dash/SKILL.md no longer forbids calling the Artifact tool unprompted"

# ---------- (2) the override is declared, not merely asserted ----------
# The rule must name the thing it overrides AND say it wins. Both halves are required:
# naming the conflict without resolving it leaves the agent arbitrating; declaring a winner
# without naming the loser leaves the agent unable to tell the clause applies.
# Flattened: the rule wraps mid-sentence, and a line-based grep reports a contradiction
# that is not there when a rewrap moves "tool's own default" onto the next line.
RULE_FLAT="$(tr '\n' ' ' < "$RULE" | tr -s ' ')"
grep -qiE 'overrides? the .?Artifact.? tool' <<<"$RULE_FLAT" \
  || fail "(2) rules/artifacts-local-first.md does not name the Artifact tool's own default as the thing it overrides — the three-layer conflict reads as a contradiction again (BL-081)"
grep -qiE 'this rule wins|rule wins' <<<"$RULE_FLAT" \
  || fail "(2) rules/artifacts-local-first.md names the conflict but never says which side wins"

if [[ "$failures" -eq 0 ]]; then
  echo "OK — publish policy in lockstep: both surfaces gate on an explicit ask, and the rule declares its override of the tool default"
  exit 0
fi
exit 1
