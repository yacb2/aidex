#!/usr/bin/env bash
# test-worktree-multi.sh — lifecycle test for worktree-multi.sh in a temp
# split-git workspace fixture (two repos + an unversioned wrapper file):
# create -> assert worktrees/branch/links -> remove -> assert clean + refusal
# behavior on dirty trees is git's own (not exercised destructively here).
#
# Run with: bash skills/aidex-worktree/scripts/test-worktree-multi.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/worktree-multi.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixture: split-git workspace — root has NO .git; two participant repos; wrapper file.
WS="$TMP/ws"
mkdir -p "$WS/backend" "$WS/frontend"
for r in backend frontend; do
  git -C "$WS/$r" init -q
  git -C "$WS/$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
done
echo "services: {}" > "$WS/docker-compose.yml"

cd "$WS"
DEST="$TMP/ws-wt-feat-x"

# --- create ---
out="$(bash "$SCRIPT" create --slug feat-x --branch feat/x \
  --repo backend --repo frontend --link docker-compose.yml --dest "$DEST" 2>/dev/null)"
[[ "$out" == "$DEST" ]] || fail "create: expected dest path on stdout, got: $out"
[[ -f "$DEST/backend/.git" && -f "$DEST/frontend/.git" ]] || fail "create: missing worktree .git markers"
b1="$(git -C "$DEST/backend" branch --show-current)"
b2="$(git -C "$DEST/frontend" branch --show-current)"
[[ "$b1" == "feat/x" && "$b2" == "feat/x" ]] || fail "create: expected branch feat/x in both, got $b1 / $b2"
[[ -L "$DEST/docker-compose.yml" ]] || fail "create: wrapper symlink missing"
n_wt="$(git -C "$WS/backend" worktree list | wc -l | tr -d ' ')"
[[ "$n_wt" == "2" ]] || fail "create: backend should have 2 worktrees (main + wt), got $n_wt"

# --- create refuses existing dest ---
if bash "$SCRIPT" create --slug feat-x --branch feat/x --repo backend --dest "$DEST" >/dev/null 2>&1; then
  fail "create: should refuse an existing destination"
fi

# --- create validates participants before mutating ---
if bash "$SCRIPT" create --slug feat-y --branch feat/y --repo nonexistent --dest "$TMP/ws-wt-feat-y" >/dev/null 2>&1; then
  fail "create: should refuse a nonexistent participant"
fi
[[ ! -e "$TMP/ws-wt-feat-y" ]] || fail "create: failed validation must not leave a dest behind"

# --- remove ---
bash "$SCRIPT" remove --slug feat-x --dest "$DEST" >/dev/null 2>&1 || fail "remove: exited non-zero"
[[ ! -e "$DEST" ]] || fail "remove: dest still exists"
n_wt="$(git -C "$WS/backend" worktree list | wc -l | tr -d ' ')"
[[ "$n_wt" == "1" ]] || fail "remove: backend should be back to 1 worktree, got $n_wt"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — multi-repo worktree create/refuse/validate/remove lifecycle"
