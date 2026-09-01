#!/usr/bin/env bash
# test-root-participant.sh — a project whose ROOT repo owns .context/ must get a
# worktree that owns its own .context/ too (BL-259).
#
# WT_PARTICIPANTS entries are all sub-directories of the project root, so the root
# repo itself could never participate. In echo_lab (root ops repo + backend +
# frontend) the root owns `.context/`, so a worktree got NO `.context/` of its own:
# `find_project_root` walked up past $DEST into the main checkout, and every backlog,
# work-list and proof write from inside the worktree landed in `main`. The sweep of
# 2026-08-28 had to copy `.context/` by hand before teardown.
#
# The fix is a root token (`.`) in WT_PARTICIPANTS: $DEST is itself a checkout of the
# root repo, the other participants nest inside it, WT_LINKS skips what that checkout
# already carries, and `down` removes it like any other.
#
# COVERAGE, STATED PLAINLY: this is behavioural end to end — a real root+nested git
# worktree through `new --no-infra`, a real write into the worktree's own .context/,
# and a real `down`. No daemon is involved.
#
# Run with: bash skills/aidex-worktree/tests/test-root-participant.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
LIB="$DIR/../../aidex-conventions/scripts/_lib.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf '  ok: %s\n' "$*"; }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/slots"; mkdir -p "$TMPDIR"

git_q() { /usr/bin/git "$@" >/dev/null 2>&1; }

# A workspace whose ROOT is a git repo tracking .context/, with one nested participant.
p="$TMP/proj"
mkdir -p "$p/.context/worktrees" "$p/backend"
printf 'WT_PARTICIPANTS=". backend"\n' > "$p/.context/worktrees/config.env"
printf 'root marker\n' > "$p/README.md"
( cd "$p" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
  && git_q add -A && git_q commit -qm init )
( cd "$p/backend" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
  && echo hi > f.txt && git_q add -A && git_q commit -qm init )

out="$( cd "$p" && bash "$WT" new rp --branch wt/rp --no-infra 2>&1 )"; rc=$?
D="$p/../proj-wt-rp"

[[ $rc -eq 0 ]] && ok "new with a root participant exits 0" \
  || fail "new rc=$rc: $out"

[[ -e "$D/.git" ]] && ok "\$DEST is itself a checkout, not a bare directory" \
  || fail "\$DEST has no .git — the root repo did not participate"

[[ -d "$D/.context" ]] && ok "the worktree carries its own .context/" \
  || fail "no .context/ in the worktree — writes will land in the main checkout"

[[ -d "$D/backend" ]] && ok "the nested participant is checked out inside \$DEST" \
  || fail "participant backend missing from $D"

# The bullet that matters: a script run from inside the worktree must resolve HERE.
if [[ -d "$D" ]]; then
  got="$( cd "$D" && bash -c "source '$LIB'; find_project_root" 2>/dev/null )"
  [[ "$got" == "$(cd "$D" && pwd -P)" ]] && ok "find_project_root resolves to \$DEST, not the main tree" \
    || fail "find_project_root returned '$got', wanted '$(cd "$D" 2>/dev/null && pwd -P)'"

  # And a real artifact write must land in the worktree's own backlog.
  mkdir -p "$D/.context/backlog"
  ( cd "$D" && printf 'x\n' > .context/backlog/probe.md )
  [[ -f "$D/.context/backlog/probe.md" && ! -f "$p/.context/backlog/probe.md" ]] \
    && ok "a write from the worktree stays in the worktree" \
    || fail "the write reached the main checkout"
fi

out="$( cd "$p" && bash "$WT" down rp --force 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] && ok "down exits 0" || fail "down rc=$rc: $out"
[[ ! -d "$D" ]] && ok "down removed the root checkout" || fail "$D survived down"
ls "$TMPDIR"/*/slot-* >/dev/null 2>&1 && fail "a slot claim outlived the teardown" \
  || ok "the slot claim was released"

# --- case 2: the root token must not depend on where it sits in the list -------
# `.` first happens to work because $DEST is still empty when `git worktree add
# $DEST/.` runs. List it last and the participants have already populated $DEST, so
# git refuses with "already exists" and the whole creation rolls back. Order in a
# config string is not a contract anybody knows they are relying on.
p2="$TMP/proj2"
mkdir -p "$p2/.context/worktrees" "$p2/backend"
printf 'WT_PARTICIPANTS="backend ."\n' > "$p2/.context/worktrees/config.env"
printf 'root marker\n' > "$p2/README.md"
( cd "$p2" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
  && git_q add -A && git_q commit -qm init )
( cd "$p2/backend" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
  && echo hi > f.txt && git_q add -A && git_q commit -qm init )
out2="$( cd "$p2" && bash "$WT" new rp2 --branch wt/rp2 --no-infra 2>&1 )"
D2="$p2/../proj2-wt-rp2"
[[ -e "$D2/.git" && -d "$D2/backend" ]] \
  && ok "the root token works listed LAST, not only first" \
  || fail "root token last: no root checkout at \$DEST — $(printf '%s' "$out2" | tail -2 | tr '\n' ' ')"
( cd "$p2" && bash "$WT" down rp2 --force ) >/dev/null 2>&1

# --- case 3: a link must not be written over a file the checkout already carries -
# WT_LINKS exists for UNVERSIONED wrapper files. With a root participant the
# checkout brings the tracked ones itself, so `ln -s` hits an existing path and
# creation dies. Skipping it with a notice is the acceptance; linking over it would
# dirty the checkout and make `git worktree remove` refuse later.
p3="$TMP/proj3"
mkdir -p "$p3/.context/worktrees" "$p3/backend"
printf 'WT_PARTICIPANTS=". backend"\nWT_LINKS="docker-compose.yml"\n' > "$p3/.context/worktrees/config.env"
printf 'services: {}\n' > "$p3/docker-compose.yml"
printf 'root marker\n' > "$p3/README.md"
( cd "$p3" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
  && git_q add -A && git_q commit -qm init )
( cd "$p3/backend" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
  && echo hi > f.txt && git_q add -A && git_q commit -qm init )
out3="$( cd "$p3" && bash "$WT" new lk --branch wt/lk --no-infra 2>&1 )"
D3="$p3/../proj3-wt-lk"
[[ -e "$D3/.git" ]] \
  && ok "a WT_LINKS entry the checkout carries does not kill creation" \
  || fail "link collision killed creation: $(printf '%s' "$out3" | tail -2 | tr '\n' ' ')"
if [[ -e "$D3/.git" ]]; then
  [[ ! -L "$D3/docker-compose.yml" ]] \
    && ok "the tracked file was skipped, not linked over" \
    || fail "docker-compose.yml was replaced by a symlink into the main tree"
  [[ -z "$(/usr/bin/git -C "$D3" status --porcelain 2>/dev/null)" ]] \
    && ok "the root checkout is clean, so git worktree remove will not refuse" \
    || fail "the checkout is dirty: $(/usr/bin/git -C "$D3" status --porcelain | head -2 | tr '\n' ' ')"
  printf '%s' "$out3" | grep -qi "skip" \
    && ok "the skip is announced, not silent" \
    || fail "nothing in the output tells the reader the link was skipped"
  # The consequence that makes the dirt matter: IS_DIRTY reads $DEST, so bookkeeping
  # left untracked would make a plain `down` refuse forever, naming aidex's own files
  # as the user's uncommitted work. Tear this one down WITHOUT --force.
  outd="$( cd "$p3" && bash "$WT" down lk 2>&1 )"
  [[ ! -d "$D3" ]] && ok "a plain down (no --force) tears down a root checkout" \
    || fail "down refused without --force: $(printf '%s' "$outd" | tail -2 | tr '\n' ' ')"
fi
( cd "$p3" && bash "$WT" down lk --force ) >/dev/null 2>&1

if [[ $failures -eq 0 ]]; then echo "OK — root participant"; else echo "$failures failure(s)"; exit 1; fi
