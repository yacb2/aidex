#!/usr/bin/env bash
# test-detect-project-commands.sh — smoke tests for detect-project-commands.sh.
#
# Covers (found via field-testing against a real project, 2026-07-01):
#   - flat .claude/commands/*.md detection (review, commit)
#   - NAMESPACED .claude/commands/<subdir>/<name>.md detection (release), which
#     a maxdepth-1 search misses entirely — this is the regression this test locks in
#   - cache reuse across two runs without --refresh
#
# Run with: bash skills/aidex-conventions/scripts/test-detect-project-commands.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DETECTOR="$SCRIPT_DIR/detect-project-commands.sh"
FIXTURE="$SCRIPT_DIR/fixtures/detect-commands"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Clear any leftover cache from a prior run so this test is deterministic.
rm -f "$FIXTURE/.claude/.aidex-detected-commands.json"

out1="$(bash "$DETECTOR" --project "$FIXTURE" --json --refresh)"

review="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("review_command"))')"
commit="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("commit_command"))')"
release="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("release_command"))')"

[[ "$review" == "/code-review" ]] || fail "review_command: expected /code-review, got $review"
[[ "$commit" == "/commit" ]] || fail "commit_command: expected /commit, got $commit"
[[ "$release" == "/version:release" ]] || fail "release_command (namespaced): expected /version:release, got $release — namespaced .claude/commands/<subdir>/<name>.md detection regressed"

wt_up="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_up_command"))')"
wt_down="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_down_command"))')"
[[ "$wt_up" == "./worktree-up.sh <slug>" ]] || fail "worktree_up_command: expected ./worktree-up.sh <slug> (from .context/worktrees front-matter), got $wt_up"
[[ "$wt_down" == "./worktree-down.sh <slug>" ]] || fail "worktree_down_command: expected ./worktree-down.sh <slug>, got $wt_down"

detected_at1="$(printf '%s' "$out1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["detected_at"])')"
out2="$(bash "$DETECTOR" --project "$FIXTURE" --json)"
detected_at2="$(printf '%s' "$out2" | python3 -c 'import json,sys; print(json.load(sys.stdin)["detected_at"])')"
[[ "$detected_at1" == "$detected_at2" ]] || fail "cache reuse: detected_at changed across a non-refresh run ($detected_at1 vs $detected_at2)"

# Clean up the cache file this test wrote — it's not part of the fixture's committed content.
rm -f "$FIXTURE/.claude/.aidex-detected-commands.json"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — flat + namespaced command detection, cache reuse"
