#!/usr/bin/env bash
# test-pack-path.sh — the pack and profile-init paths the shipped skills hand a reader resolve.
#
# 1. Stack packs (testing-django, testing-vue, ...) are user skills installed under
#    ~/.claude/skills/<pack>/; none ships in this plugin. The plugin path sweep
#    (75f77955) rewrote every site to ${CLAUDE_PLUGIN_ROOT}/skills/<pack>/, so a profile
#    naming testing-django read as "pack not installed" and its test shapes were lost
#    (LOOP-013 coverage-c14). Scans every shipped skill: testing/SKILL.md, preloaded
#    into the bugfix and impl agents, carried the same rewrite.
# 2. Every `python3 ... profile-init.py` command names the plugin path: the
#    cwd-relative `python3 scripts/profile-init.py` fails from a project root, which is
#    where the phase-close tripwire is run (LOOP-013 coverage-c16).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS="$(cd "$HERE/../.." && pwd -P)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
rc=0

hits="$(grep -rnIE '\$\{CLAUDE_PLUGIN_ROOT\}/skills/(<pack>|testing-)' "$SKILLS" | grep -v "^$SELF:")"
if [ -n "$hits" ]; then
  printf 'FAIL: a shipped skill points stack packs into the plugin, where none ships (use ~/.claude/skills/<pack>/):\n%s\n' "$hits"
  rc=1
fi

hits="$(grep -rnIE 'python3 +[^ ]*profile-init\.py' "$SKILLS" --include='*.md' \
  | grep -v 'python3 \${CLAUDE_PLUGIN_ROOT}/skills/coverage/scripts/profile-init\.py')"
if [ -n "$hits" ]; then
  printf 'FAIL: a profile-init.py command is cwd-relative (name ${CLAUDE_PLUGIN_ROOT}/skills/coverage/scripts/profile-init.py):\n%s\n' "$hits"
  rc=1
fi

[ "$rc" -eq 0 ] && echo "ok: stack packs resolve under ~/.claude/skills, every profile-init.py command names the plugin path"
exit "$rc"
