#!/usr/bin/env bash
# test-pattern-catalog-levels.sh — BL-697/BL-698: level 2 is split into 2a (catalog pattern)
# and 2b (reference screen), the Dashboard state row exists, and ui_patterns_ref is read by
# ui-contract and gallery-builder and documented beside gallery_gate_cmd.
# Layer: text contract (the flow is prose).
set -u
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="$SKILL_DIR/../.."
SKILL="$SKILL_DIR/SKILL.md"
FAILURES=0
fail() { echo "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

grep -qF '| 2a — ' "$SKILL" || fail "level table lacks a 2a row"
grep -qF '| 2b — ' "$SKILL" || fail "level table lacks a 2b row"
grep -qE '^\| 2 — ' "$SKILL" && fail "level table still has an unsplit level 2 row"
grep -qF '| 3 — New visual direction (only this)' "$SKILL" || fail "level 3 is not limited to a new visual direction"
row="$(grep -F '| Dashboard |' "$SKILL")"
for st in 'with data' 'loading' 'empty' 'one widget failed' 'no permission'; do
  echo "$row" | grep -qF "$st" || fail "Dashboard state row lacks: $st"
done
grep -qF 'ui_patterns_ref' "$SKILL" || fail "ui-contract SKILL.md does not read ui_patterns_ref"
grep -qF 'ui_patterns_ref' "$ROOT/agents/gallery-builder.md" || fail "gallery-builder does not read ui_patterns_ref"
tpl="$ROOT/skills/coverage/assets/templates/testing.md.template"
g="$(grep -n '^gallery_gate_cmd:' "$tpl" | cut -d: -f1)"
u="$(grep -n '^ui_patterns_ref:' "$tpl" | cut -d: -f1)"
{ [ -n "$g" ] && [ -n "$u" ] && [ "$((u - g))" -le 2 ] && [ "$u" -gt "$g" ]; } || fail "template lacks ui_patterns_ref beside gallery_gate_cmd"

if [ "$FAILURES" -eq 0 ]; then echo "PASS: pattern-catalog levels and ui_patterns_ref"; exit 0; fi
echo "FAIL: $FAILURES cell(s)"; exit 1
