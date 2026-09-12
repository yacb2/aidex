#!/usr/bin/env bash
# Asserts the repo is a valid Claude Code plugin layout.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

FAIL=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# a. .claude-plugin/plugin.json exists and "name": "aidex" is in it
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"
if [ -f "$PLUGIN_JSON" ] && grep -q '"name": "aidex"' "$PLUGIN_JSON"; then
  pass "a. .claude-plugin/plugin.json exists with name=aidex"
else
  fail "a. .claude-plugin/plugin.json exists with name=aidex"
fi

# b. hooks/hooks.json exists
HOOKS_JSON="$ROOT/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ]; then
  pass "b. hooks/hooks.json exists"
else
  fail "b. hooks/hooks.json exists"
fi

# c. claude plugin validate <root> exits 0
if command -v claude >/dev/null 2>&1; then
  if claude plugin validate "$ROOT" >/dev/null 2>&1; then
    pass "c. claude plugin validate exits 0"
  else
    fail "c. claude plugin validate exits 0"
  fi
else
  fail "c. claude plugin validate exits 0 (claude CLI not found)"
fi

# d. no ~/.claude/skills or $HOME/.claude/skills references remain
D_MATCHES=$(grep -rnE '~/\.claude/skills/|\$HOME/\.claude/skills' "$ROOT/skills" "$ROOT/hooks" 2>/dev/null)
D_COUNT=$(printf '%s' "$D_MATCHES" | grep -c . || true)
if [ -z "$D_MATCHES" ]; then
  pass "d. no hardcoded ~/.claude/skills references (saw 0)"
else
  fail "d. no hardcoded ~/.claude/skills references (saw $D_COUNT)"
fi

# e. at least 150 lines use ${CLAUDE_PLUGIN_ROOT}/skills/
E_MATCHES=$(grep -rnF '${CLAUDE_PLUGIN_ROOT}/skills/' "$ROOT/skills" 2>/dev/null)
E_COUNT=$(printf '%s' "$E_MATCHES" | grep -c . || true)
if [ -n "$E_MATCHES" ] && [ "$E_COUNT" -ge 150 ]; then
  pass "e. CLAUDE_PLUGIN_ROOT skills refs >= 150 (saw $E_COUNT)"
else
  fail "e. CLAUDE_PLUGIN_ROOT skills refs >= 150 (saw $E_COUNT)"
fi

# f. no invocation-shaped bare slash command remains
F_MATCHES=$(grep -rnE '(^|[^A-Za-z0-9_/.])/aidex-[a-z-]+([^A-Za-z0-9_/-]|$)' "$ROOT/skills" "$ROOT/docs" "$ROOT/README.md" 2>/dev/null)
F_COUNT=$(printf '%s' "$F_MATCHES" | grep -c . || true)
if [ -z "$F_MATCHES" ]; then
  pass "f. no bare /aidex-* slash command refs (saw 0)"
else
  fail "f. no bare /aidex-* slash command refs (saw $F_COUNT)"
fi

# g. no un-namespaced "Not for" clause
G_MATCHES=$(grep -rnoE '\(aidex-[a-z-]+\)' "$ROOT"/skills/*/SKILL.md 2>/dev/null)
G_COUNT=$(printf '%s' "$G_MATCHES" | grep -c . || true)
if [ -z "$G_MATCHES" ]; then
  pass "g. no un-namespaced (aidex-*) clauses (saw 0)"
else
  fail "g. no un-namespaced (aidex-*) clauses (saw $G_COUNT)"
fi

exit $FAIL
