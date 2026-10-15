#!/usr/bin/env bash
# test-detect-project-commands.sh — smoke tests for detect-project-commands.sh.
#
# Covers (found via field-testing against a real project, 2026-07-01):
#   - flat .claude/commands/*.md detection (review, commit)
#   - NAMESPACED .claude/commands/<subdir>/<name>.md detection (release), which
#     a maxdepth-1 search misses entirely — this is the regression this test locks in
#   - cache reuse across two runs
#
# Run with: bash skills/conventions/scripts/test-detect-project-commands.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DETECTOR="$SCRIPT_DIR/detect-project-commands.sh"
# A private copy: the detector writes its cache into the project, and a shared in-repo
# fixture made concurrent runs trample each other's cache (c42).
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp -R "$SCRIPT_DIR/fixtures/detect-commands" "$TMP/fixture"
FIXTURE="$TMP/fixture"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

rm -f "$FIXTURE/.claude/.aidex-detected-commands.json"

bash "$DETECTOR" --project "$FIXTURE" >/dev/null
out1="$(cat "$FIXTURE/.claude/.aidex-detected-commands.json")"

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

# Deterministic: edit a field in the cache; a second run must print the edited value (read from the
# cache, not re-scanned) and leave the file as edited.
CACHE="$FIXTURE/.claude/.aidex-detected-commands.json"
python3 - "$CACHE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["review_command"] = "/cache-marker"
json.dump(d, open(sys.argv[1], "w"))
PY
out2="$(bash "$DETECTOR" --project "$FIXTURE")"
grep -qF 'review_command: /cache-marker' <<<"$out2" || fail "cache reuse: a second run did not print the cached value: $out2"
grep -qF '/cache-marker' "$CACHE" || fail "cache reuse: the second run rewrote the cache"

# A nonexistent --project is refused; it used to leave ROOT empty and scan /.
if bash "$DETECTOR" --project "$TMP/does-not-exist" >/dev/null 2>"$TMP/err"; then
  fail "nonexistent --project exited 0"
fi
grep -q "project directory not found" "$TMP/err" || fail "nonexistent --project: the script gave no clear error (it kept going with an empty ROOT): $(cat "$TMP/err")"

# The worktree fallback promises an EXECUTABLE worktree-up*.sh: a plain file is no command.
P2="$TMP/noexec"; mkdir -p "$P2"
printf '#!/bin/sh\n' > "$P2/worktree-up.sh"; printf '#!/bin/sh\n' > "$P2/worktree-down.sh"; chmod +x "$P2/worktree-down.sh"
bash "$DETECTOR" --project "$P2" >/dev/null
out3="$(cat "$P2/.claude/.aidex-detected-commands.json")"
up="$(printf '%s' "$out3" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_up_command"))')"
down="$(printf '%s' "$out3" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("worktree_down_command"))')"
[[ "$up" == "None" ]] || fail "non-executable worktree-up.sh was detected as a command: $up"
[[ "$down" == "./worktree-down.sh" ]] || fail "executable worktree-down.sh not detected: $down"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — flat + namespaced command detection, cache reuse"
