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
# Run with: bash skills/worktree/tests/test-teardown-and-scope.sh

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
# BL-796: a --no-infra tree holds no claim, so `down` has no slot dir to check and
# must not create one (its guard is "only when one exists").
[[ -e "$TMPDIR/aidex-wt-slots-p5" || -L "$TMPDIR/aidex-wt-slots-p5" ]] \
  && fail "BL-796: down of a --no-infra tree created the slot directory"

# --- #5 / BL-776. down reads a slot from the file, else the claim, else none --
# `down` checked only "is a number", so 0 -- the MAIN tree -- passed and the hook
# got dev's own port. Each source is checked on its own: a 0 file falls through to
# a real claim, a 0 claim is no slot. No range check: a slot above a LOWERED
# WT_MAX_SLOTS is still that worktree's, and its teardown must release it.
# Row: name | .wt-slot | claim slot ("" = none) | WT_MAX_SLOTS ("" = default) |
#      hook output | expect "released slot N" (yes/no).
down_case() {
  local name="$1" file="$2" claim="$3" max="$4" want="$5" rel="$6" P="$TMP/p5$1" sd
  mkdir -p "$P/.context/worktrees" "$P/backend"
  { printf '%s\n' 'WT_PARTICIPANTS="backend"' 'WT_LINKS=""' 'WT_PORT_VARS="WEB_PORT=8000"' \
      "WT_PRE_DOWN_CMD='echo PRE_WEB=\${WEB_PORT:-none}'"
    [[ -n "$max" ]] && printf 'WT_MAX_SLOTS=%s\n' "$max"; } > "$P/.context/worktrees/config.env"
  ( cd "$P/backend" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
    && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
  ( cd "$P" && bash "$S/worktree.sh" new z --branch wt/z --no-infra ) >/dev/null 2>&1
  printf '%s\n' "$file" > "$P-wt-z/.wt-slot"
  if [[ -n "$claim" ]]; then
    sd="$TMPDIR/aidex-wt-slots-p5$name"; mkdir -p "$sd"; chmod 700 "$sd"
    printf '99999 z 0\n' > "$sd/slot-$claim"
  fi
  out="$( cd "$P" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down z --force 2>&1 )"
  grep -qx "$want" <<<"$out" \
    || fail "BL-776 down ($name): .wt-slot '$file', claim '${claim:--}' must give the hook $want, got: $out"
  if [[ "$rel" == yes ]]; then
    grep -q "released slot $claim" <<<"$out" || fail "BL-776 down ($name): slot $claim must be released, got: $out"
  fi
}
down_case zero  0 ''  '' PRE_WEB=none no    # no claim: no slot, never the main tree
down_case zfile 0 3   '' PRE_WEB=8300 yes   # a 0 file falls through to the claim
down_case zclm  '' 0  '' PRE_WEB=none no    # a 0 claim is no slot either
down_case lower 7 7   4  PRE_WEB=8700 yes   # above a lowered WT_MAX_SLOTS: still released

# --- BL-193. --delete-branch cannot name the branch -> it must REFUSE --------
#
# `down --delete-branch` reads the branch from `<worktree>/.wt-branch`. When that
# file is missing or empty it cannot identify the branch, skips the deletion and
# reports SUCCESS -- leaving a branch nobody will remember to remove. Both states
# occur: a worktree created before the `.wt-branch` file existed (2026-08-15)
# has NO `.wt-branch`, which is the case the item mis-recorded as empty.
#
# What is NOT done here, deliberately: falling back to `git worktree list
# --porcelain`. Measured 2026-08-22 -- after a checkout switches branches that
# command reports the NEW branch, so it is the current branch under another name
# and using it is exactly the wrong-target deletion worktree.sh:1173 forbids.
# The refusal names the current checkout as information and refuses to act on it.
mk_branch_fixture() {  # mk_branch_fixture <dir> <slug>
  mkdir -p "$1/.context/worktrees" "$1/backend"
  printf 'WT_PARTICIPANTS="backend"\nWT_LINKS=""\nWT_PORT_VARS="DB_PORT=6400"\n' \
    > "$1/.context/worktrees/config.env"
  ( cd "$1/backend" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
    && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A \
    && /usr/bin/git commit -qm i ) >/dev/null 2>&1
  ( cd "$1" && bash "$S/worktree.sh" new "$2" --branch "wt/$2" --no-infra ) >/dev/null 2>&1
}
mk_docker '#!/bin/sh
exit 0'

# (a) CONTROL FIRST. With .wt-branch intact the deletion happens and exits 0 --
#     without this, every assertion below is satisfied by a command that refuses
#     unconditionally.
mk_branch_fixture "$TMP/pb-ok" keep
out="$( cd "$TMP/pb-ok" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down keep --force --delete-branch 2>&1 )"; rc=$?
[[ "$rc" -eq 0 ]] || fail "BL-193 control: an intact .wt-branch must still exit 0, got $rc: $out"
/usr/bin/git -C "$TMP/pb-ok/backend" rev-parse --verify -q wt/keep >/dev/null \
  && fail "BL-193 control: the branch was not deleted although .wt-branch named it: $out"

# (b) EMPTY .wt-branch — mutated at the call site, which is the state the item names.
mk_branch_fixture "$TMP/pb-empty" mt
: > "$TMP/pb-empty-wt-mt/.wt-branch"
out="$( cd "$TMP/pb-empty" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down mt --force --delete-branch 2>&1 )"; rc=$?
# The exit code is the whole point: this item is about a command that reports
# success while doing nothing, so grepping the message alone would reproduce the
# defect class inside the test.
[[ "$rc" -ne 0 ]] \
  || fail "BL-193: an empty .wt-branch skipped the deletion and reported SUCCESS (rc=0): $out"
grep -qi 'empty' <<<"$out" \
  || fail "BL-193: the refusal does not say the recorded branch is empty: $out"
/usr/bin/git -C "$TMP/pb-empty/backend" rev-parse --verify -q wt/mt >/dev/null \
  || fail "BL-193: refusing must not delete anything — wt/mt is gone: $out"

# (c) MISSING .wt-branch — the live case, and it must NOT be described as empty.
mk_branch_fixture "$TMP/pb-gone" old
rm -f "$TMP/pb-gone-wt-old/.wt-branch"
out="$( cd "$TMP/pb-gone" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down old --force --delete-branch 2>&1 )"; rc=$?
[[ "$rc" -ne 0 ]] \
  || fail "BL-193: a missing .wt-branch skipped the deletion and reported SUCCESS (rc=0): $out"
grep -qi 'no .wt-branch' <<<"$out" \
  || fail "BL-193: the refusal does not distinguish a MISSING file from an empty one: $out"

# (d) The teardown itself still succeeded — the refusal is about the branch only,
#     and must not read as a failed teardown.
[[ -d "$TMP/pb-gone-wt-old" ]] \
  && fail "BL-193: the worktree directory survived — the refusal aborted the teardown"

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

# --- #16b. a daemon that never answers is unreachable too, after a deadline --
# A wedged Docker Desktop accepts the socket and never replies: an unbounded
# `docker info` hung `down` and orphan-sweep forever. Deadline 2 s here
# (AIDEX_DOCKER_TIMEOUT, default 30); each run is polled, never waited on unbounded.
mk_docker '#!/bin/sh
[ "$1" = info ] && exec sleep 300
exit 0'
( cd "$TMP/p5" && bash "$S/worktree.sh" new hang --branch wt/hang --no-infra ) >/dev/null 2>&1 \
  || fail "#16b: fixture: worktree new failed"
bounded() {  # bounded <label> <command...>: 20 s to finish; prints its output
  local label="$1" i; shift
  ( cd "$TMP/p5" && PATH="$BIN:$PATH" AIDEX_DOCKER_TIMEOUT=2 "$@" ) > "$TMP/bounded.out" 2>&1 & local pid=$!
  for ((i = 0; i < 80; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid"; pkill -f "$BIN/docker" 2>/dev/null
    fail "$label: still hung on docker info after 20 s (deadline 2 s)"; return 99
  fi
  wait "$pid"
}
# Keyed on "did not hang" (99), not on exit 0: down exits non-zero over an
# unreachable daemon (worktree-c02), and an `&&` on its exit code would skip the
# warning check without saying so.
bounded "#16b down" bash "$S/worktree.sh" down hang --force
[[ $? -ne 99 ]] && ! grep -q 'did not answer' "$TMP/bounded.out" \
  && fail "#16b down: no 'did not answer' warning: $(cat "$TMP/bounded.out")"
bounded "#16b orphan-sweep" bash "$S/orphan-sweep.sh" --slug hang \
  && ! grep -q 'did not answer' "$TMP/bounded.out" \
  && fail "#16b orphan-sweep: no 'did not answer' line: $(cat "$TMP/bounded.out")"

# --- #16c. the deadline stops a docker that ignores SIGALRM ----------------
# The real docker CLI (a Go binary) ignores SIGALRM, so `alarm; exec docker`
# signalled a process that kept running: down still hung past its deadline. The
# stub here ignores ALRM the same way; down must give up within the deadline.
mk_docker '#!/bin/sh
[ "$1" = info ] && { trap "" ALRM; exec sleep 300; }
exit 0'
( cd "$TMP/p5" && bash "$S/worktree.sh" new hang2 --branch wt/hang2 --no-infra ) >/dev/null 2>&1 \
  || fail "#16c: fixture: worktree new failed"
bounded "#16c down" bash "$S/worktree.sh" down hang2 --force
[[ $? -ne 99 ]] && ! grep -q 'did not answer within 2 s' "$TMP/bounded.out" \
  && fail "#16c down: no 'did not answer within 2 s' warning: $(cat "$TMP/bounded.out")"

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
        | sed -n 's/^worktree_down: *//p' | sed -n 1p )"
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
  | grep >/dev/null 'for c in $WT_COPIES; do rbargs+=(--copy "$c"); done' \
  || fail "rollback: its remove call must carry the same --copy args as down's"

# C. rollback removes what THIS run made, even when that reads as dirty.
# `new` refuses an existing $DEST, so everything in it is this run's. Without
# --force, remove's up-front dirt check refused on this run's own untracked copy
# inside a participant -- silently, behind rollback's >/dev/null -- and the retry
# then died on "destination already exists". Behavioural: `compose up` fails.
mkdir -p "$TMP/prb/.context/worktrees" "$TMP/prb/backend"
cat > "$TMP/prb/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_COPIES="backend/extra.txt"
WT_PORT_VARS="DB_PORT=6400"
ENV
printf 'services:\n  backend:\n    image: nginx\n' > "$TMP/prb/docker-compose.yml"
( cd "$TMP/prb/backend" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
  && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
echo extra > "$TMP/prb/backend/extra.txt"   # untracked in backend, so the copy is too
mk_docker '#!/bin/sh
case " $* " in *" up "*) exit 1 ;; esac
exit 0'
out="$( cd "$TMP/prb" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new rb --branch wt/rb 2>&1 )"; rc=$?
[[ $rc -ne 0 ]] || fail "rollback fixture: new must fail when compose up fails, got exit 0"
[[ ! -e "$TMP/prb-wt-rb" ]] \
  || fail "rollback: a failed new must leave no \$DEST behind (this run's own copy made it read dirty): $out"

# D. worktree-c12: a slot env file that cannot be written rolls back too.
# A root participant whose checkout TRACKS .env brings it into $DEST without the
# marker, and write_wt_env refused with `die` AFTER CREATED_DIR=true: exit 2,
# no rollback, a registered worktree holding slot 1, and a retry that died on
# "destination already exists".
mkdir -p "$TMP/penv/.context/worktrees"
cat > "$TMP/penv/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="."
WT_LINKS=""
WT_PORT_VARS="DB_PORT=6400"
ENV
printf 'services:\n  app:\n    image: nginx\n' > "$TMP/penv/docker-compose.yml"
printf 'FOO=bar\n' > "$TMP/penv/.env"
( cd "$TMP/penv" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
  && /usr/bin/git config user.name t && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
mk_docker '#!/bin/sh
exit 0'
out="$( cd "$TMP/penv" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new e1 --branch wt/e1 2>&1 )"; rc=$?
[[ $rc -ne 0 ]] || fail "c12 fixture: new must fail when the tracked .env blocks the slot env file: $out"
/usr/bin/git -C "$TMP/penv" worktree list | grep >/dev/null "penv-wt-e1" \
  && fail "c12: the refused slot env file left a registered worktree behind: $out"
[[ -e "$TMPDIR/aidex-wt-slots-penv/slot-1" ]] \
  && fail "c12: the refused slot env file left slot 1 claimed: $out"
out="$( cd "$TMP/penv" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new e1 --branch wt/e1b 2>&1 )"
grep -q 'destination already exists' <<<"$out" \
  && fail "c12: the retry of new died on the first run's leftovers: $out"

# E. worktree-c38: rollback frees the ports before it frees the slot. The stub
# records the claim directory at the moment compose down runs; an empty record
# means a concurrent `new` could already have been handed slot 1.
mkdir -p "$TMP/porder/.context/worktrees" "$TMP/porder/backend"
printf 'WT_PARTICIPANTS="backend"\nWT_LINKS=""\nWT_PORT_VARS="DB_PORT=6400"\n' \
  > "$TMP/porder/.context/worktrees/config.env"
printf 'services:\n  backend:\n    image: nginx\n' > "$TMP/porder/docker-compose.yml"
( cd "$TMP/porder/backend" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
  && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
mk_docker "#!/bin/sh
case \" \$* \" in
  *' up '*) exit 1 ;;
  *' compose '*' down '*) ls '$TMPDIR/aidex-wt-slots-porder' > '$TMP/order.log' 2>&1 ;;
esac
exit 0"
out="$( cd "$TMP/porder" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new o1 --branch wt/o1 2>&1 )"
grep -q 'rolling back' <<<"$out" || fail "c38 fixture: compose up failure did not roll back: $out"
grep -q 'slot-1' "$TMP/order.log" 2>/dev/null \
  || fail "c38: rollback released slot 1 before compose down freed its ports (claims during down: $(cat "$TMP/order.log" 2>/dev/null))"
[[ -e "$TMPDIR/aidex-wt-slots-porder/slot-1" ]] && fail "c38: rollback must still release slot 1 in the end"

# --- BL-267. `down` removes a $DEST that is itself a root-repo checkout ------
# The 2026-08-28 workaround: a project whose root owns .context/, so the
# worktree's $DEST was made a checkout of the root repo by hand. `down` builds
# its removal list from WT_PARTICIPANTS ($DEST/<basename> per entry) and $DEST
# itself is not in it, so the participants went and $DEST stayed a live
# worktree — directory there, slot still claimed, only a manual
# `git worktree remove` freeing it.
#
# The end state is reconstructed rather than driven through `new`, which
# refuses a $DEST that already exists: `new` builds the markers and the claim,
# then $DEST is re-created as a root checkout with git's own bookkeeping and
# the contents move back into it.
mk_rootco() {  # mk_rootco <project-dir> [noignore] -> builds the worktree, $DEST is a root checkout
  local P="$1" D="$1-wt-rootco"
  mkdir -p "$P/.context/worktrees" "$P/backend"
  cat > "$P/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
ENV
  # backend/ is ignored by the root repo: it is a repo of its own, and an
  # untracked directory would make every root checkout read as dirty.
  [[ "${2:-}" == noignore ]] || printf 'backend/\n' > "$P/.gitignore"
  ( cd "$P" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
    && /usr/bin/git config user.name t && /usr/bin/git add -A && /usr/bin/git commit -qm i )
  ( cd "$P/backend" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
    && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i )
  ( cd "$P" && bash "$S/worktree.sh" new rootco --branch wt/rootco --no-infra )
  mv "$D" "$D.stage"
  /usr/bin/git -C "$P" worktree add -q -b wt/root-rootco "$D"
  mv "$D.stage/backend" "$D/backend"
  mv "$D.stage/.wt-branch" "$D/.wt-branch" 2>/dev/null || true
  rm -rf "$D.stage"
  # `new --no-infra` leaves .wt-slot BLANK, so a fixture that just moves it has
  # no claim to release and the "slot is free again" assertion below can never
  # fail. A real slot and its claim file are written here instead — the claim
  # format is `<pid> <slug>`, which is what release_claim matches on.
  printf '3\n' > "$D/.wt-slot"
  mkdir -p "$TMPDIR/aidex-wt-slots-$(basename "$P")"
  printf '%s %s\n' "$$" rootco > "$TMPDIR/aidex-wt-slots-$(basename "$P")/slot-3"
}

mk_docker '#!/bin/sh
exit 0'
P267="$TMP/p267"; D267="$TMP/p267-wt-rootco"
mk_rootco "$P267" >/dev/null 2>&1
/usr/bin/git -C "$P267" worktree list | grep >/dev/null "$D267" \
  || fail "BL-267 setup: \$DEST was not made a checkout of the root repo"
out="$( cd "$P267" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down rootco 2>&1 )"
[[ ! -d "$D267" ]] \
  || fail "BL-267: down left \$DEST behind — it is a root-repo checkout and not a participant: $out"
/usr/bin/git -C "$P267" worktree list | grep >/dev/null "$D267" \
  && fail "BL-267: the root repo still lists \$DEST as a live worktree after down"
[[ -e "$TMPDIR/aidex-wt-slots-p267/slot-3" ]] \
  && fail "BL-267: the slot claim was not released, so slot 3 stays taken: $out"

# A root repo that does NOT ignore the participant sees `?? backend/`. That is the
# participant itself, not the user's work: the old order removed it first and the
# root was then clean, so the up-front dirt check must not refuse on it.
P269="$TMP/p269"; D269="$TMP/p269-wt-rootco"
mk_rootco "$P269" noignore >/dev/null 2>&1
out="$( cd "$P269" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down rootco 2>&1 )"; rc=$?
[[ $rc -eq 0 && ! -d "$D269" ]] \
  || fail "root checkout with an unignored participant: down must exit 0 and remove \$DEST (rc=$rc): $out"

# The uncommitted-work refusal covers the root checkout too: without --force,
# `down` must refuse and print the ROOT's own status, not only the
# participants'. Before this, the root checkout was invisible to IS_DIRTY, so
# the refusal message said nothing about the work it was protecting.
P268="$TMP/p268"; D268="$TMP/p268-wt-rootco"
mk_rootco "$P268" >/dev/null 2>&1
echo 'work in progress' > "$D268/root-wip.txt"
/usr/bin/git -C "$D268" add root-wip.txt
out="$( cd "$P268" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down rootco 2>&1 )"; rc=$?
[[ $rc -ne 0 ]] \
  || fail "BL-267: down over a DIRTY root checkout must refuse without --force, got exit 0: $out"
[[ -d "$D268" ]] \
  || fail "BL-267: down discarded a dirty root checkout without --force"
# Anchored on the LABEL, not just the filename: `down` already exits non-zero
# over a $DEST it cannot remove, and git's own refusal happens to echo the
# path — so a bare 'root-wip.txt' match passed before IS_DIRTY could see the
# root checkout at all, which is a cell proving nothing.
grep -q '(root checkout) .*root-wip.txt' <<<"$out" \
  || fail "BL-267: the refusal must name the root checkout's uncommitted work as such, got: $out"

# --- worktree-c02. an unverified teardown keeps its slot and does not exit 0 --
# `down` released the claim and exited 0 when compose down failed, when the
# sweep found residue, and when the daemon could not be asked at all: a driving
# agent read success, and the leftovers were tracked by no claim. The directory
# still goes (what is withheld is the CLAIM), so `list` shows MISSING-DIR and a
# second `down` runs the reclaim again against the project root.
mk_claimed() {  # mk_claimed <project-dir> <slug>: a worktree holding slot 3
  mk_branch_fixture "$1" "$2"
  printf '3\n' > "$1-wt-$2/.wt-slot"
  mkdir -p "$TMPDIR/aidex-wt-slots-$(basename "$1")"
  printf '%s %s\n' "$$" "$2" > "$TMPDIR/aidex-wt-slots-$(basename "$1")/slot-3"
}
# With no claim held (a --no-infra tree, or a slug whose claim is already gone)
# there is nothing to withhold: an unverifiable teardown keeps the warning and
# exits 0 (noinfra: daemon down). claimnodocker: docker not on PATH at all while
# a claim IS held -- compose down exits 127, and that is unverified, not clean.
# A PATH with every directory that holds a `docker` dropped, the stub's included.
NODOCKER_PATH="$(printf '%s\n' "$PATH" | tr ':' '\n' \
  | while IFS= read -r d; do [[ -n "$d" && ! -x "$d/docker" ]] && printf '%s:' "$d"; done)"
NODOCKER_PATH="${NODOCKER_PATH%:}"   # a trailing ':' would put the cwd on PATH
for cell in daemon composefail residue keepdir clean noinfra claimnodocker; do
  P="$TMP/pc02$cell"; C="$TMPDIR/aidex-wt-slots-pc02$cell/slot-3"
  case "$cell" in
    noinfra) mk_branch_fixture "$P" td >/dev/null 2>&1 ;;
    *)                mk_claimed "$P" td >/dev/null 2>&1 ;;
  esac
  case "$cell" in
    # Only `docker info` fails: compose down succeeds, so the daemon check is
    # the one thing that can withhold the claim here.
    daemon)      mk_docker '#!/bin/sh
case "$1" in info) exit 1 ;; esac
exit 0' ;;
    composefail) mk_docker '#!/bin/sh
case " $* " in *" compose "*" down "*) exit 1 ;; esac
exit 0' ;;
    residue|keepdir) mk_docker "#!/bin/sh
case \"\$1\" in volume) echo 'pc02$cell-wt-td_pgdata' ;; esac
exit 0" ;;
    clean)       mk_docker '#!/bin/sh
exit 0' ;;
    noinfra)     mk_docker '#!/bin/sh
exit 1' ;;
  esac
  flags=(--force); [[ "$cell" == keepdir ]] && flags+=(--keep-dir)
  if [[ "$cell" == claimnodocker ]]; then
    out="$( cd "$P" && PATH="$NODOCKER_PATH" "$BASH" "$S/worktree.sh" down td "${flags[@]}" 2>&1 )"; rc=$?
  else
    out="$( cd "$P" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down td "${flags[@]}" 2>&1 )"; rc=$?
  fi
  case "$cell" in
    keepdir)
      # --keep-dir holds the slot anyway; what it must not do is exit 0 over residue.
      [[ $rc -eq 1 && -d "$P-wt-td" && -e "$C" ]] \
        || fail "c02 keepdir: --keep-dir over residue must keep dir and slot and exit 1 (rc=$rc): $out" ;;
    clean)
      [[ $rc -eq 0 && ! -e "$C" && ! -d "$P-wt-td" ]] \
        || fail "c02 control: a verified teardown must exit 0, remove the dir and release slot 3 (rc=$rc): $out" ;;
    noinfra)
      [[ $rc -eq 0 && ! -d "$P-wt-td" ]] \
        || fail "c02 $cell: with no claim to withhold, an unverifiable teardown must remove the dir and exit 0 (rc=$rc): $out"
      grep -q 'stays claimed' <<<"$out" && fail "c02 $cell: no claim exists, yet down says one stays claimed: $out" ;;
    *)
      [[ $rc -eq 1 ]] || fail "c02 $cell: an unverified teardown must exit 1 (rc=$rc): $out"
      [[ -e "$C" ]] || fail "c02 $cell: the slot claim was released over an unverified teardown: $out"
      [[ ! -d "$P-wt-td" ]] || fail "c02 $cell: the directory must still be removed (only the claim is withheld): $out"
      grep -q 'stays claimed' <<<"$out" || fail "c02 $cell: down must say the slot stays claimed and why: $out" ;;
  esac
done

# --- worktree-c36. down releases only the claim it resolved -------------------
# release_claim ran without the slot lock and removed EVERY claim naming the
# slug. A `new` of the same slug that starts once $DEST is gone reaps down's
# claim and reserves the slot afresh; down's release then deleted that live
# reservation, and the slot was handed out twice. The concurrent `new` is played
# by an `lsof` stub: the first call after the directory is removed (the second
# holders pass, just before the release) rewrites slot 3 the way `new` would.
P="$TMP/pc36"; C="$TMPDIR/aidex-wt-slots-pc36/slot-3"
mk_claimed "$P" td >/dev/null 2>&1
mk_docker '#!/bin/sh
exit 0'
LBIN="$TMP/lsofbin"; mkdir -p "$LBIN"
printf '#!/bin/sh\n[ -d %q ] || { [ -e %q.done ] || { rm -f %q; printf "424242 td\\n" > %q; : > %q.done; }; }\nexit 0\n' \
  "$P-wt-td" "$C" "$C" "$C" "$C" > "$LBIN/lsof"; chmod +x "$LBIN/lsof"
out="$( cd "$P" && PATH="$LBIN:$BIN:$PATH" bash "$S/worktree.sh" down td --force 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] || fail "c36: a verified teardown must exit 0 (rc=$rc): $out"
[[ "$(cat "$C" 2>/dev/null)" == "424242 td" ]] \
  || fail "c36: down deleted the fresh reservation a concurrent new made on slot 3: $out"
grep -q 'released slot 3' <<<"$out" && fail "c36: down reports releasing a claim that was not its own: $out"

# --- worktree-c36. the release waits for the slot lock `new` allocates under --
# The compare-and-delete is only atomic if `new` cannot run its reaper and
# reserve between the compare and the rm. With a live run holding the slot lock,
# down must not release around it: it waits, then exits 2 with slot 3 kept.
LIB="$DIR/../../conventions/scripts/_lib.sh"
P="$TMP/pc36lock"; C="$TMPDIR/aidex-wt-slots-pc36lock/slot-3"
mk_claimed "$P" td >/dev/null 2>&1
mk_docker '#!/bin/sh
exit 0'
mkfifo "$TMP/held36"
( trap - EXIT; exec bash -c '. "$1"; lock_take "$2" 5 || exit 1; echo held > "$3"; exec sleep 60' _ "$LIB" "${C%/*}/.flock" "$TMP/held36" ) &
H36=$!
read -t 10 -r _ <> "$TMP/held36" || fail "c36 lock fixture: the holder never took the slot lock"
out="$( cd "$P" && PATH="$BIN:$PATH" AIDEX_WT_LOCK_WAIT=1 bash "$S/worktree.sh" down td --force 2>&1 )"; rc=$?
kill "$H36" 2>/dev/null; wait "$H36" 2>/dev/null
[[ $rc -eq 2 ]] || fail "c36 lock: down must exit 2 when the slot lock stays held, got $rc: $out"
[[ "$(cat "$C" 2>/dev/null)" == "$$ td" ]] || fail "c36 lock: down released slot 3 without the slot lock: $out"
grep -q "error: ${C%/*}/.flock is held by another run" <<<"$out" || fail "c36 lock: the refusal must name the held lock: $out"

# --- r2 F6. down's release refuses a symlinked slot directory ----------------
# `new` and `up` refuse one (ensure_slotdir); the release in `down` took the lock
# through the bare path, followed the link and created `.flock` in its target.
# Refused before anything is torn down: the worktree directory stays (r3).
P="$TMP/pslink"; SLD="$TMPDIR/aidex-wt-slots-pslink"; TGT="$TMP/slink-target"
mk_branch_fixture "$P" td >/dev/null 2>&1
printf '3\n' > "$P-wt-td/.wt-slot"
mkdir -p "$TGT"; printf '%s td\n' "$$" > "$TGT/slot-3"; ln -s "$TGT" "$SLD"
mk_docker '#!/bin/sh
exit 0'
out="$( cd "$P" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down td --force 2>&1 )"; rc=$?
[[ $rc -eq 2 ]] || fail "F6: down must refuse a symlinked slot directory, exit 2, got $rc: $out"
grep -q "error: refusing slot directory $SLD: it is a symlink" <<<"$out" || fail "F6: the refusal must name the symlinked slot directory: $out"
[[ ! -e "$TGT/.flock" ]] || fail "F6: down followed the symlink and created $TGT/.flock"
[[ -e "$TGT/slot-3" ]] || fail "F6: down released a claim through a symlinked slot directory"
[[ -d "$P-wt-td" ]] || fail "F6: down removed $P-wt-td before refusing the slot directory"

# --- r2 F7. a claim on a slot down did not resolve is reported, not released --
# .wt-slot says 3, the slug's claim is on slot 5. down releases only the slot it
# resolved (c36), and slot 5 then stayed claimed with nothing said. It is still
# not released (it may be a concurrent run's), but down names it and the way out.
P="$TMP/pother"; SO="$TMPDIR/aidex-wt-slots-pother"
mk_branch_fixture "$P" td >/dev/null 2>&1
printf '3\n' > "$P-wt-td/.wt-slot"
( trap - EXIT; exit 0 ) & deadp=$!; wait "$deadp" 2>/dev/null
mkdir -p "$SO"; printf '%s td\n' "$deadp" > "$SO/slot-5"
mk_docker '#!/bin/sh
exit 0'
out="$( cd "$P" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down td --force 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] || fail "F7: down must still exit 0, got $rc: $out"
[[ -e "$SO/slot-5" ]] || fail "F7: down released a claim on a slot it did not resolve: $out"
grep -q "'td' also holds slot 5" <<<"$out" || fail "F7: down must name the other slot the slug holds: $out"
grep -q "rm $SO/slot-5" <<<"$out" || fail "F7: down must say how to free slot 5: $out"

# --- worktree-c36 (control) and wta-r2 A. a sibling slug's claim is not ours --
# The slug boundary: .wt-slot names slot 3, but slot 3 is claimed by `td-2`.
# `down td` over an unreachable daemon must neither withhold nor release it.
P="$TMP/pc36sib"; C="$TMPDIR/aidex-wt-slots-pc36sib/slot-3"
mk_branch_fixture "$P" td >/dev/null 2>&1
printf '3\n' > "$P-wt-td/.wt-slot"
mkdir -p "$(dirname "$C")"; printf '%s td-2\n' "$$" > "$C"
mk_docker '#!/bin/sh
case "$1" in info) exit 1 ;; esac
exit 0'
out="$( cd "$P" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down td --force 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] || fail "wta-r2 A: down td withheld td-2's claim as its own (rc=$rc): $out"
[[ "$(cat "$C" 2>/dev/null)" == "$$ td-2" ]] || fail "wta-r2 A: down td touched td-2's claim on slot 3: $out"
grep -q 'stays claimed' <<<"$out" && fail "wta-r2 A: down td says a slot stays claimed, but td holds none: $out"

# --- wta-r2 D. --keep-dir with no claim does not say a slot is still claimed ---
P="$TMP/pkeepnc"
mk_branch_fixture "$P" td >/dev/null 2>&1
mk_docker '#!/bin/sh
exit 0'
out="$( cd "$P" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down td --force --keep-dir 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] || fail "keep-dir no claim: must exit 0 (rc=$rc): $out"
grep -q "keep-dir: $P-wt-td left in place (no slot claimed; resume with: worktree.sh up td)" <<<"$out" \
  || fail "keep-dir no claim: must say no slot is claimed: $out"
grep -q 'still claimed' <<<"$out" && fail "keep-dir no claim: claims a slot is still claimed with none held: $out"

# --- BL-795. a foreign file at the slot path must not block a claim-less down ---
# The refusal is for a symlinked or foreign slot DIRECTORY that `down` would read a
# claim from or delete one in. A --no-infra tree records no slot and holds no claim,
# so there is nothing to read or delete, and refusing named a claim that is not there.
mk_docker '#!/bin/sh
exit 0'
mk_branch_fixture "$TMP/p795" fs >/dev/null 2>&1
: > "$TMP/p795-wt-fs/.wt-slot"
printf 'not a directory\n' > "$TMPDIR/aidex-wt-slots-p795"
out="$( cd "$TMP/p795" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down fs --force 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] || fail "BL-795: a foreign file at the slot path blocked a down that holds no claim (rc=$rc): $out"
[[ ! -d "$TMP/p795-wt-fs" ]] || fail "BL-795: the claim-less worktree was not torn down: $out"
rm -f "$TMPDIR/aidex-wt-slots-p795"

# --- BL-793. a docker that ignores TERM must not hang `down` ------------------
# with_timeout only sent TERM, and the compose plugin ignores it, so a wedged
# daemon hung the unbounded `compose down` and `docker images` for good. The stub
# ignores TERM and ALRM (an ignored disposition survives `exec`); down must give
# up within the deadlines (AIDEX_DOWN_TIMEOUT 2 s, AIDEX_DOCKER_TIMEOUT 2 s, plus
# the KILL grace) -- bounded() allows 20 s. Only the two calls `down` makes itself
# hang: the label-less `docker images` belongs to orphan-sweep.
mk_docker '#!/bin/sh
case "$1 $*" in
  "compose "*|"images "*label=*) trap "" TERM ALRM; exec sleep 300 ;;
esac
exit 0'
( cd "$TMP/p5" && bash "$S/worktree.sh" new wedge --branch wt/wedge --no-infra ) >/dev/null 2>&1 \
  || fail "BL-793: fixture: worktree new failed"
bounded "BL-793 down" env AIDEX_DOWN_TIMEOUT=2 bash "$S/worktree.sh" down wedge --force

# --- BL-793 follow-ups: with_timeout itself ----------------------------------
eval "$(sed -n '/^with_timeout()/,/^}/p' "$S/../../conventions/scripts/_lib.sh")"
# (a) the KILL reaches the whole group: a TERM-ignoring grandchild that holds the
#     pipe of a $( ) otherwise keeps the substitution waiting for its full life.
t0=$SECONDS
x="$(with_timeout 1 sh -c '(trap "" TERM; exec sleep 8) & wait')"
[[ $((SECONDS - t0)) -le 4 ]] \
  || fail "with_timeout: a TERM-ignoring grandchild held the pipe for $((SECONDS - t0)) s (deadline 1 s + 2 s grace)"
# (b) a TERM sent to with_timeout itself (Ctrl-C, an outer timeout) reaches the
#     child instead of leaving it running detached.
( with_timeout 30 sh -c 'echo $$ > "$1"; exec sleep 31' sh "$TMP/fwd.pid"; true ) 2>/dev/null & wpid=$!
for ((i = 0; i < 40; i++)); do [[ -s "$TMP/fwd.pid" ]] && break; sleep 0.1; done
cpid="$(cat "$TMP/fwd.pid" 2>/dev/null)"
if [[ -n "$cpid" ]]; then
  kill -TERM "$(ps -o ppid= -p "$cpid" | tr -d ' ')" 2>/dev/null
  for ((i = 0; i < 30; i++)); do kill -0 "$cpid" 2>/dev/null || break; sleep 0.1; done
  kill -0 "$cpid" 2>/dev/null && { fail "with_timeout: a TERM to the wrapper left its child running"; kill -9 "$cpid"; }
else
  fail "with_timeout: fixture: the child never started"
fi
{ wait "$wpid"; } 2>/dev/null

# (b2) a signal reaching with_timeout is forwarded as the SAME signal to the child's
#      group (no TERM is sent for an INT), the child gets 2 s, then the group is
#      KILLed, and the signal is re-raised on the wrapper: the CALLING script dies of
#      it (INT -> 130) instead of going on as if the command had merely failed.
#      Rows: INT to the group (Ctrl-C) with a plain child and with a child that
#      ignores TERM and INT (must be KILLed within the grace, whole group gone);
#      TERM to the wrapper PID alone (forwarding is the only way the child learns).
cat > "$TMP/ctrlc.sh" <<EOS
$(sed -n '/^with_timeout()/,/^}/p' "$S/../../conventions/scripts/_lib.sh")
set +e
with_timeout 20 sh -c "\$1" sh "\$2"
echo CONTINUED
EOS
for row in 'INT group exec sleep 30' 'INT group trap "" TERM INT; sleep 30' "TERM wrapper trap 'touch $TMP/kid.term; exit 0' TERM; sleep 30 & wait"; do
  sig="${row%% *}"; rest="${row#* }"; who="${rest%% *}"; kid="${rest#* }"
  kid="echo \$\$ > \"$TMP/kid.pid\"; $kid"
  rm -f "$TMP/kid.pid" "$TMP/kid.term"; : > "$TMP/ctrlc.out"
  perl -e '$SIG{INT}="DEFAULT"; setpgrp(0,0); exec @ARGV' bash "$TMP/ctrlc.sh" "$kid" x > "$TMP/ctrlc.out" 2>&1 &
  wpid=$!
  for ((i = 0; i < 50; i++)); do [[ -s "$TMP/kid.pid" ]] && break; sleep 0.1; done
  kpid="$(cat "$TMP/kid.pid" 2>/dev/null)"
  [[ -n "$kpid" ]] || { fail "with_timeout ($sig): fixture: the child never started"; kill -9 -- "-$wpid" 2>/dev/null; continue; }
  if [[ $who == group ]]; then target="-$wpid"; else target="$(ps -o ppid= -p "$kpid" | tr -d ' ')"; fi
  t0=$SECONDS
  kill -"$sig" -- "$target" 2>/dev/null
  for ((i = 0; i < 80; i++)); do kill -0 "$wpid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$wpid" 2>/dev/null; then
    fail "with_timeout ($sig, '$rest'): the script was still running 8 s after the signal"; kill -9 -- "-$wpid" 2>/dev/null
  fi
  { wait "$wpid"; } 2>/dev/null; rc=$?
  [[ $((SECONDS - t0)) -le 4 ]] || fail "with_timeout ($sig, '$rest'): took $((SECONDS - t0)) s to end (grace is 2 s)"
  kill -0 -- "-$kpid" 2>/dev/null && { fail "with_timeout ($sig, '$rest'): the child's group outlived the wrapper"; kill -9 -- "-$kpid" 2>/dev/null; }
  # bash itself only abandons a script over SIGINT; after a TERM it carries on (rc 143).
  # The child's own TERM trap proves the TERM was FORWARDED (a KILL after the grace
  # would also end it, but leaves no marker).
  if [[ $sig == TERM ]]; then
    [[ -e "$TMP/kid.term" ]] || fail "with_timeout (TERM): the child never received the forwarded TERM"
    continue
  fi
  grep -q CONTINUED "$TMP/ctrlc.out" && fail "with_timeout ($sig, '$rest'): the script continued after the signal"
  [[ $rc -eq 130 ]] || fail "with_timeout ($sig, '$rest'): the script must end with 130, got $rc"
done

# (c) the timeout is VISIBLE on a claimed tree: exit 142 reported, the slot kept.
#     (--no-infra clears the 142 because it holds no claim.)
mk_docker '#!/bin/sh
case "$1" in compose) trap "" TERM ALRM; exec sleep 300 ;; esac
exit 0'
( cd "$TMP/p5" && bash "$S/worktree.sh" new claimed --branch wt/claimed --no-infra ) >/dev/null 2>&1 \
  || fail "BL-793 claimed: fixture: worktree new failed"
echo 3 > "$TMP/p5-wt-claimed/.wt-slot"
mkdir -p "$TMPDIR/aidex-wt-slots-p5"
echo "1 claimed Mon" > "$TMPDIR/aidex-wt-slots-p5/slot-3"
bounded "BL-793 claimed down" env AIDEX_DOWN_TIMEOUT=2 bash "$S/worktree.sh" down claimed --force; rc=$?
[[ $rc -ne 0 && $rc -ne 99 ]] || fail "BL-793 claimed: a timed-out compose down must exit non-zero, got rc=$rc"
grep -q 'compose down failed (exit 142)' "$TMP/bounded.out" \
  || fail "BL-793 claimed: the timeout is not reported as exit 142: $(cat "$TMP/bounded.out")"
[[ -e "$TMPDIR/aidex-wt-slots-p5/slot-3" ]] || fail "BL-793 claimed: the slot claim was released over an unverified teardown"

# --- the timeout knobs are validated (0 would mean no deadline) ---------------
mk_docker '#!/bin/sh
exit 0'
for kv in AIDEX_DOWN_TIMEOUT=0 AIDEX_DOCKER_TIMEOUT=abc AIDEX_DOWN_TIMEOUT=99999999999999999999; do
  out="$( cd "$TMP/p5" && env "$kv" PATH="$BIN:$PATH" bash "$S/worktree.sh" down claimed --force 2>&1 )"; rc=$?
  [[ $rc -eq 2 ]] || fail "$kv must be refused with exit 2, got $rc: $out"
  grep -q "${kv%%=*}" <<<"$out" || fail "$kv: the refusal does not name the variable: $out"
done

# --- worktree-c06. the compose project name is Compose-normalised ------------
# Compose rejects `MyApp-wt-x` ("must consist only of lowercase alphanumeric
# characters, hyphens, and underscores"), so a directory with an uppercase letter
# or a dot could never get a worktree. DEST keeps the raw directory name; only the
# project name is normalised.
mk_docker '#!/bin/sh
echo "ARGS $*" >> "$DOCKER_LOG"
case "$*" in "ps -a --format"*) echo myapp-wt-cn ;; esac
exit 0'
P="$TMP/My.App"
mk_branch_fixture "$P" cn >/dev/null 2>&1
export DOCKER_LOG="$TMP/docker06.log"; : > "$DOCKER_LOG"
out="$( cd "$P" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down cn --force 2>&1 )"
# The verifier must look under the same normalised name: a live myapp-wt-cn stack
# was reported as "no Docker resource remains" when the sweep scanned `My.App-wt-`.
grep -q 'no Docker resource remains' <<<"$out" \
  && fail "c06: down declared a clean teardown over a live myapp-wt-cn stack: $out"
grep -q 'residue remains' <<<"$out" \
  || fail "c06: down did not report the myapp-wt-cn residue: $out"
grep -q 'compose -p myapp-wt-cn ' "$DOCKER_LOG" \
  || fail "c06: down must name the compose project myapp-wt-cn, got: $(grep compose "$DOCKER_LOG" | sed -n 1p)"
grep -q 'My\.App-wt\|MyApp-wt' "$DOCKER_LOG" \
  && fail "c06: a raw, un-normalised project name reached docker: $(grep 'My' "$DOCKER_LOG" | sed -n 1p)"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — teardown and scope: blank slot refused, sweep scoped to the workspace, compose failure reported, daemon-down not a clean teardown, recipe bounded to front matter, a root-repo \$DEST removed and its slot released, rollback covers the slot env file and frees ports before the slot, an unverified teardown keeps its slot"
