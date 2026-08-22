#!/usr/bin/env bash
# test-teardown-and-scope.sh — five defects that all end the same way: a
# teardown or a scope check reporting success over something it never did.
#
#   #5  a blank .wt-slot read as slot 0, so `down` exported the MAIN tree's dev
#       ports into WT_PRE_DOWN_CMD -- `new --no-infra` writes exactly that file.
#   #6  orphan-sweep took its `<project>-wt-` namespace from `git rev-parse` of
#       the CALLER's cwd, so in a split-git workspace (participants are separate
#       repos, the workspace root is not one) it scanned a namespace that can
#       never match and reported a false all-clear.
#   #14 check-compose-isolation's `die "docker compose config failed"` is
#       unreachable: _lib.sh turns errexit ON and the script never turns it off,
#       so the failing render assignment kills the script first -- exit 1, no
#       message, no cause.
#   #16 with the daemon unreachable, orphan-sweep exits 0 by design and `down`
#       printed that as positive proof the teardown was clean.
#   #19 the `worktree_down` recipe -- which is EVAL'd -- was extracted with a sed
#       range that re-opens on every later `---`, so it was never bounded to the
#       document's front matter.
#
# Docker is stubbed throughout; nothing here needs a daemon and nothing here
# touches a real project.
#
# Run with: bash skills/aidex-worktree/tests/test-teardown-and-scope.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
S="$DIR/../scripts"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/slots"; mkdir -p "$TMPDIR"

BIN="$TMP/bin"; mkdir -p "$BIN"
mk_docker() { printf '%s\n' "$1" > "$BIN/docker"; chmod +x "$BIN/docker"; }

# --- #5. a blank .wt-slot is "no slot", never slot 0 ------------------------
# `cat` on an empty file SUCCEEDS, so the `||` fallbacks never fire and the slot
# is the empty string, which bash arithmetic reads as 0 -- the main tree.
mkdir -p "$TMP/p5/.context/worktrees" "$TMP/p5/backend"
cat > "$TMP/p5/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_PORT_VARS="DB_PORT=6400"
WT_PRE_DOWN_CMD='echo PRE_DB=$DB_PORT'
ENV
( cd "$TMP/p5/backend" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
  && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
( cd "$TMP/p5" && bash "$S/worktree.sh" new blank --branch wt/blank --no-infra ) >/dev/null 2>&1
: > "$TMP/p5-wt-blank/.wt-slot"          # exactly what --no-infra leaves
mk_docker '#!/bin/sh
exit 0'
out="$( cd "$TMP/p5" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down blank --force 2>&1 )"
grep -q 'PRE_DB=6400' <<<"$out" \
  && fail "#5: a blank .wt-slot handed the MAIN tree's dev port 6400 to the teardown hook"
grep -qi 'no slot' <<<"$out" \
  || fail "#5: a blank .wt-slot must be reported as no slot recorded, got: $out"

# --- #6. the sweep's namespace comes from the WORKSPACE, not the caller -----
# Split-git: the workspace root has no .git; each participant is its own repo.
mkdir -p "$TMP/wsproj/.context/worktrees" "$TMP/wsproj/backend"
printf 'WT_PARTICIPANTS="backend"\nWT_LINKS=""\n' > "$TMP/wsproj/.context/worktrees/config.env"
( cd "$TMP/wsproj/backend" && /usr/bin/git init -q . ) >/dev/null 2>&1
mk_docker '#!/bin/sh
case "$1" in info) exit 0 ;; esac
case "$1" in
  ps) echo "wsproj-wt-feat-backend" ;;
  volume) echo "wsproj-wt-feat_dbdata" ;;
  images) [ "${2:-}" = "-f" ] && exit 0; echo "wsproj-wt-feat-backend" ;;
  network) echo "wsproj-wt-feat_default" ;;
esac
exit 0'
out="$( cd "$TMP/wsproj/backend" && PATH="$BIN:$PATH" bash "$S/orphan-sweep.sh" --slug feat 2>&1 )"
grep -q 'wsproj-wt-feat' <<<"$out" \
  || fail "#6: called from a participant repo, the sweep must scope to the WORKSPACE, got: $out"

# --- #14. the compose-config failure must say so ---------------------------
mkdir -p "$TMP/p14"
printf 'services:\n  web:\n    image: nginx\n' > "$TMP/p14/docker-compose.yml"
mk_docker '#!/bin/sh
case "$1" in info) exit 0 ;; esac
echo "compose config error: required variable DB_PASSWORD is missing" >&2
exit 1'
out="$( cd "$TMP/p14" && PATH="$BIN:$PATH" bash "$S/check-compose-isolation.sh" 2>&1 )"; rc=$?
grep -qi 'docker compose config failed' <<<"$out" \
  || fail "#14: a failing render must reach its own die message, got (rc=$rc): $out"

# --- #16. daemon down is not proof of a clean teardown ---------------------
mk_docker '#!/bin/sh
exit 1'
out="$( cd "$TMP/p5" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down blank --force 2>&1 )"
grep -q 'no Docker resource remains attributable' <<<"$out" \
  && fail "#16: with the daemon unreachable, a clean teardown was claimed anyway"

# --- #19. the eval'd recipe must come from the FRONT MATTER only -----------
mkdir -p "$TMP/p19/.context/worktrees"
cat > "$TMP/p19/.context/worktrees/00-index.md" <<'MD'
---
title: "Worktree procedure"
status: doing
---

# Procedure

Historic note, quoted from an old revision:

---

worktree_down: rm -rf / --no-preserve-root

---
MD
got="$( sed -n '/^---$/,/^---$/p' "$TMP/p19/.context/worktrees/00-index.md" \
        | sed -n 's/^worktree_down: *//p' | head -1 )"
[[ -n "$got" ]] || fail "#19: the fixture no longer reproduces the unbounded range"
grep -q "awk 'NR==1" "$S/worktree-multi.sh" \
  || fail "#19: worktree-multi.sh must bound the front matter to the leading block"

# --- #15. the attributable count must not carry a dead fallback ------------
# `grep -c` prints 0 on empty input already, so `|| echo 0` can only ever append
# a SECOND line, making the count malformed rather than defaulting it.
grep -q 'grep -cv "\^\$" 2>/dev/null || echo 0' "$S/worktree.sh" \
  && fail "#15: the dead '|| echo 0' fallback is still there; it makes the count two lines"

# --- the create/rollback path and WT_COPIES ---------------------------------
# These two were the review's unverified pair (their verifiers died on a
# connection error); adjudicated against the code and pinned here.

# A. WT_COPIES=".env" is refused at CONFIG time, not after the tree exists.
# The collision guard looked only at WT_LINKS. A project that COPIES .env -- a
# legitimate need, since a Docker build context cannot follow a symlink out of
# itself, which is why WT_COPIES exists -- passed the guard, had the main tree's
# .env copied in by `create`, and then hit write_wt_env's `die` AFTER
# CREATED_DIR=true: a hard exit that bypasses rollback and strands a registered
# worktree holding its slot.
mkdir -p "$TMP/pcopy/.context/worktrees" "$TMP/pcopy/backend"
cat > "$TMP/pcopy/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_COPIES=".env"
ENV
# Driven through `new`, which is the path that would create the tree: the guard
# has to fire BEFORE anything exists, and asserting the directory's absence is
# what makes that a real claim rather than a message check.
out="$( cd "$TMP/pcopy" && bash "$S/worktree.sh" new x --branch wt/x --no-infra 2>&1 )"; rc=$?
grep -qi 'WT_COPIES contains .env' <<<"$out" \
  || fail "copies-env: a .env in WT_COPIES must be refused before creation, got: $out"
[[ ! -d "$TMP/pcopy-wt-x" ]] || fail "copies-env: the worktree was created before the refusal"

# B. rollback must remove the same things `down` does.
# Structural, and precise: the two call sites are compared to each other rather
# than a shape being asserted twice. rollback passed no --copy arguments, so a
# root-level WT_COPIES entry survived, $DEST stayed non-empty, and the removal
# failed behind `>/dev/null 2>&1` -- invisible, and the retry that rollback's own
# "creation is all-or-nothing" contract invites then died on "destination
# already exists".
awk '/rbargs=\(remove --slug/,/MULTI" "\$\{rbargs\[@\]\}"/' "$S/worktree.sh" \
  | grep -q 'for c in $WT_COPIES; do rbargs+=(--copy "$c"); done' \
  || fail "rollback: its remove call must carry the same --copy args as down's"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — teardown and scope: blank slot refused, sweep scoped to the workspace, compose failure reported, daemon-down not a clean teardown, recipe bounded to front matter"
