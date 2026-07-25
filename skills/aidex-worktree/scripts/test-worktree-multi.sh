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

# =====================================================================
# Teardown coupling on remove.
#
# Regression (field-observed 2026-07-25): `remove` deleted the directory and
# only *printed* the teardown as a next step. Skipping it stranded the Docker
# stack, and with <dest> gone nothing could attribute those resources to a
# worktree again — an orphaned network survived that way for two days while
# untagged 3GB build layers piled up behind it.
#
# Docker is stubbed via PATH; the stub reports the worktree's stack as present
# until the recorded teardown runs and drops the marker file.
# =====================================================================

mkdir -p "$TMP/bin" "$WS/_scripts" "$WS/.context/worktrees"
cat > "$TMP/bin/docker" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "info") exit 0 ;;
  *"ps -a"*) [[ -e "$TMP/torn" ]] || echo ws-wt-feat-t ;;
  *"network inspect"*) echo 0 ;;
  *) : ;;
esac
FAKE
chmod +x "$TMP/bin/docker"
export PATH="$TMP/bin:$PATH"

cat > "$WS/_scripts/down.sh" <<DOWN
#!/usr/bin/env bash
echo "torn:\$1" >> "$TMP/teardown.log"
touch "$TMP/torn"
DOWN
chmod +x "$WS/_scripts/down.sh"

mk_doc() {  # mk_doc <worktree_down-value>
  cat > "$WS/.context/worktrees/00-index.md" <<DOC
---
title: "t"
worktree_up: ""
worktree_down: "$1"
---
## Procedure
## Usage log
DOC
}

DEST_T="$TMP/ws-wt-feat-t"

# --- refuses when resources exist but no teardown is recorded ---
mk_doc ""
bash "$SCRIPT" create --slug feat-t --branch feat/t --repo backend --dest "$DEST_T" >/dev/null 2>&1
if bash "$SCRIPT" remove --slug feat-t --dest "$DEST_T" >/dev/null 2>&1; then
  fail "remove: must refuse when Docker resources exist and no worktree_down is recorded"
fi
[[ -d "$DEST_T" ]] || fail "remove: a refused teardown must NOT have removed the directory"

# --- runs the recorded teardown, substituting <slug>, before removing ---
mk_doc "_scripts/down.sh <slug>"
bash "$SCRIPT" remove --slug feat-t --dest "$DEST_T" >/dev/null 2>&1 || fail "remove: exited non-zero with a valid teardown"
[[ -f "$TMP/teardown.log" ]] || fail "remove: recorded teardown was never executed"
grep -q '^torn:feat-t$' "$TMP/teardown.log" 2>/dev/null || fail "remove: teardown ran without the <slug> substituted (got: $(cat "$TMP/teardown.log" 2>/dev/null))"
[[ ! -e "$DEST_T" ]] || fail "remove: dest still exists after a successful teardown"

# --- --skip-teardown removes the dir without touching Docker ---
rm -f "$TMP/torn" "$TMP/teardown.log"
DEST_S="$TMP/ws-wt-feat-s"
bash "$SCRIPT" create --slug feat-s --branch feat/s --repo backend --dest "$DEST_S" >/dev/null 2>&1
bash "$SCRIPT" remove --slug feat-s --dest "$DEST_S" --skip-teardown >/dev/null 2>&1 || fail "remove --skip-teardown: exited non-zero"
[[ ! -e "$DEST_S" ]] || fail "remove --skip-teardown: dest still exists"
[[ ! -f "$TMP/teardown.log" ]] || fail "remove --skip-teardown: must not run the teardown"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — multi-repo worktree create/refuse/validate/remove lifecycle + teardown coupling"
