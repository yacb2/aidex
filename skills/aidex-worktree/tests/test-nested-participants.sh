#!/usr/bin/env bash
# test-nested-participants.sh — one root cause, three symptoms: a participant is
# recorded by BASENAME where its PATH is what the code then needs.
#
# WT_PARTICIPANTS may name a nested repo ("apps/backend"), and the worktree
# checkout for it lands at $DEST/backend. Three places conflated the two:
#
#   - the gitignore gate on a rendered env file probed $ROOT/<first-component>,
#     so for a nested participant the gate was silently SKIPPED -- and its whole
#     purpose is to stop a worktree that can be created and never torn down.
#   - the double-writer guard compared the exact relative path against
#     WT_LINKS/WT_COPIES, so a render into a LINKED DIRECTORY (WT_LINKS=".docker",
#     render ".docker/env.local") wrote through the symlink into the MAIN tree.
#   - `down --delete-branch` queued the basename and then looked the repo up at
#     $ROOT/<basename>, so a nested participant never matched and the branch was
#     silently never deleted.
#
# All three are latent in the field today -- every project uses flat participants
# and none sets WT_ENV_RENDER -- which is exactly why they needed a test rather
# than a field report.
#
# COVERAGE, STATED PLAINLY: case 3 is behavioural -- it creates and tears down a
# real nested git worktree through `new --no-infra` / `down`, no daemon involved.
# Cases 1 and 2 are STRUCTURAL: `render_env_files` runs only after `docker
# compose up`, and `--no-infra` returns before it, so those two guards cannot be
# driven end-to-end here. Asserting their shape is what is honestly available;
# saying so is the difference between a limit and a false claim of coverage.
#
# Run with: bash skills/aidex-worktree/tests/test-nested-participants.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/slots"; mkdir -p "$TMPDIR"

# mk_project <name> <config-body> — a workspace whose only participant is nested.
mk_project() {
  local d="$TMP/$1"; shift
  mkdir -p "$d/.context/worktrees/env-templates" "$d/apps/backend"
  printf '%s\n' "$1" > "$d/.context/worktrees/config.env"
  ( cd "$d/apps/backend" \
    && /usr/bin/git init -q . \
    && /usr/bin/git config user.email t@example.com && /usr/bin/git config user.name t \
    && echo hi > f.txt && /usr/bin/git add -A && /usr/bin/git commit -qm init ) >/dev/null 2>&1
  printf '%s' "$d"
}

# --- 1 and 2 are STRUCTURAL, and that is stated rather than hidden ----------
# `render_env_files` runs only on the full create/up path, after `docker compose
# up`; `--no-infra` returns before it. So the two render guards cannot be driven
# end-to-end without a daemon, and asserting their SHAPE is what is honestly
# available here. Both are named at the site, not counted.
WT_SRC="$WT"

# 1. the gitignore gate must resolve the participant PATH, not the basename.
grep -q 'PARTICIPANT_PATH()' "$WT_SRC" \
  || fail "gitignore gate: PARTICIPANT_PATH helper is missing"
awk '/^render_env_files\(\)/,/^}/' "$WT_SRC" | grep -q 'PARTICIPANT_PATH "$part"' \
  || fail "gitignore gate: the probe must resolve \$part through PARTICIPANT_PATH"
awk '/^render_env_files\(\)/,/^}/' "$WT_SRC" | grep -q 'ROOT/\$part/\.git' \
  && fail "gitignore gate: still probing \$ROOT/\$part/.git, which no nested participant matches"

# 2. the double-writer guard must test every directory ABOVE the render path.
awk '/^render_env_files\(\)/,/^}/' "$WT_SRC" | grep -q 'renders inside' \
  || fail "double-writer guard: a render inside a LINKED directory must be refused"

# --- 3. --delete-branch must find a nested participant's repo --------------
p="$(mk_project delbranch 'WT_PARTICIPANTS="apps/backend"
WT_LINKS=""
WT_PORT_VARS="DB_PORT=6400"')"
( cd "$p" && bash "$WT" new db --branch wt/db --no-infra ) >/dev/null 2>&1
out="$( cd "$p" && bash "$WT" down db --force --delete-branch 2>&1 )"
grep -q 'is not in' <<<"$out" \
  && fail "delete-branch: a nested participant was reported as not in the workspace: $out"
if /usr/bin/git -C "$p/apps/backend" show-ref --verify --quiet refs/heads/wt/db; then
  fail "delete-branch: the branch wt/db survived — it was silently never deleted"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — nested participants: branch deletion resolves the path (behavioural); both render guards in shape (structural)"
