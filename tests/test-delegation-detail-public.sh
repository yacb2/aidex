#!/usr/bin/env bash
# test-delegation-detail-public.sh — skills/delegation-detail/ ships in the public plugin,
# so it must carry no private workspace content and must name routed agents with the
# `aidex:` prefix (a bare name does not resolve once the agents live in the plugin).
# Regression: the raw copy of the owner's personal skill carried BL- ids, owner paths,
# aidex_ws paths and bare agent names.
# Usage: bash tests/test-delegation-detail-public.sh [dir]   (dir defaults to the skill)

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIR="${1:-$ROOT/skills/delegation-detail}"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[ -f "$DIR/SKILL.md" ] || { echo "FAIL: $DIR/SKILL.md missing"; exit 1; }

for pat in 'BL-[0-9]' '/Users/' 'aidex_ws' '~/\.claude'; do
  if hits="$(grep -rnE -- "$pat" "$DIR")"; then fail "private pattern '$pat':
$hits"; fi
done

agents="artifact-sonnet backlog-filer bugfix-opus figure-sonnet gate-runner impl-sonnet lookup-sonnet research-sonnet review-diff-opus smoke-sonnet synthesis-sonnet task-general verify-browser-opus verify-browser-sonnet"
for a in $agents; do
  # a match not directly preceded by "aidex:" is a bare name
  if hits="$(grep -rnE -- "(^|[^:a-z-])$a([^a-z-]|$)" "$DIR")"; then fail "bare agent name '$a':
$hits"; fi
done

if [ "$failures" -gt 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — delegation-detail carries no private content and only aidex:-prefixed agent names"
