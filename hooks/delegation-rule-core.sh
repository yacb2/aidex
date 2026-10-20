#!/bin/sh
# SessionStart hook — print the delegation rule core (BL-784), only when the plugin option
# `delegation_rule_core` is switched on. Default OFF: with the option unset or false the
# hook prints nothing and exits 0.
#
# Claude Code exports a plugin's userConfig values to its hooks as
# CLAUDE_PLUGIN_OPTION_<KEY> (key upper-cased). Only the exact value "true" turns it on.
# Text lives in hooks/assets/delegation-rule-core.md (no personal paths, dates or ledgers).
#
# SessionStart stdout is added to the session context. Fails open and silent.

cat >/dev/null
[ "${CLAUDE_PLUGIN_OPTION_DELEGATION_RULE_CORE:-}" = "true" ] || exit 0
CORE="$(cd "$(dirname "$0")" && pwd -P)/assets/delegation-rule-core.md"
[ -f "$CORE" ] || exit 0
cat "$CORE"
