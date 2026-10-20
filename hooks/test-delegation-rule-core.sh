#!/usr/bin/env bash
# test-delegation-rule-core.sh — BL-784. Layer: shell hook, run as the harness runs it
# (no unit seam exists; the contract is stdout + the option gate + the shipped text).
# Catches: the core printing while the option is off or unset; the core not printing when
# on; a private path, date or ledger line leaking into the public core text; the option or
# the hook wiring being dropped from plugin.json / hooks.json.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOOK="$ROOT/hooks/delegation-rule-core.sh"
CORE="$ROOT/hooks/assets/delegation-rule-core.md"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

run() { # run <value|UNSET>
  if [ "$1" = UNSET ]; then env -u CLAUDE_PLUGIN_OPTION_DELEGATION_RULE_CORE sh "$HOOK" </dev/null
  else CLAUDE_PLUGIN_OPTION_DELEGATION_RULE_CORE="$1" sh "$HOOK" </dev/null; fi
}

# Gate: only the exact value "true" prints; everything else is silent.
for v in UNSET false "" 0 1 TRUE yes "true "; do
  out="$(run "$v")"; rc=$?
  { [ "$rc" -eq 0 ] && [ -z "$out" ]; } || fail "value '$v' must print nothing and exit 0 (rc=$rc, ${#out} bytes)"
done
out="$(run true)"
[ "$out" = "$(cat "$CORE")" ] || fail "value 'true' must print the core file verbatim"
printf '%s' "$out" | grep -q 'Files to read first' || fail "core lacks the 'Files to read first' brief section"
printf '%s' "$out" | grep -q 'what you deliberately left alone' || fail "core lacks the 'what you deliberately left alone' brief section"

# Core text carries nothing private to one machine or one trial.
for pat in '/Users/' '~/\.claude' '~/Documents' 'aidex_ws' '[Oo]wner' 'readout' 'TRIAL' 'review-yield' 'BL-[0-9]' '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 'ADR'; do
  if hits="$(grep -nE -- "$pat" "$CORE")"; then fail "private pattern '$pat' in core:
$hits"; fi
done

# Wiring: option declared as boolean default false; hook on SessionStart.
python3 -I - "$ROOT" <<'PY' || fail "plugin.json / hooks.json wiring"
import json, sys
r = sys.argv[1]
o = json.load(open(r + "/.claude-plugin/plugin.json"))["userConfig"]["delegation_rule_core"]
assert o["type"] == "boolean" and o["default"] is False, o
h = json.load(open(r + "/hooks/hooks.json"))["hooks"]["SessionStart"]
cmds = [x["command"] for g in h for x in g["hooks"]]
assert any("delegation-rule-core.sh" in c for c in cmds), cmds
PY

if [ "$failures" -gt 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — delegation rule core: silent unless option is 'true', public text, wired"
