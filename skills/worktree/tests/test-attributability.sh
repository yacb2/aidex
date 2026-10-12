#!/usr/bin/env bash
# test-attributability.sh — `new` must not report an unreclaimable stack as fine.
#
# BL-195. `worktree.sh new` ends with a block whose own comment says "every
# resource we just made must be attributable, or the teardown we ship cannot
# reclaim it. Assert it now, while the author is watching." The code under that
# comment only counted and called `info`, so a `new` that started a stack and
# left NOTHING carrying the compose project label printed
# `attributable resources for <proj>: 0` and exited 0 — the exact state the
# block names, reported as ordinary output.
#
# Zero is not a legitimate outcome here. `--no-infra` exits earlier (worktree.sh
# ~887) and a failed `docker compose up -d` rolls back, so reaching this line
# means a stack came up. Zero attributable resources therefore means the project
# label did not take, and `down` has nothing to reclaim by.
#
# Docker is stubbed throughout; nothing here needs a daemon.
#
# Run with: bash skills/worktree/tests/test-attributability.sh

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

# --- fixture: a workspace whose stack starts but carries no project label ----
mk_project() {
  local root="$1"
  mkdir -p "$root/.context/worktrees" "$root/backend"
  cat > "$root/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_PORT_VARS="DB_PORT=6400"
ENV
  printf 'services:\n  backend:\n    image: nginx\n' > "$root/docker-compose.yml"
  ( cd "$root/backend" && /usr/bin/git init -q . \
      && /usr/bin/git config user.email t@e.com && /usr/bin/git config user.name t \
      && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
}

# The stub: every docker call succeeds, and every ENUMERATION returns nothing.
# That is a stack that came up under a project name nothing is labelled with.
STUB_EMPTY='#!/bin/sh
case "$1" in
  info)    exit 0 ;;
  compose) exit 0 ;;
  ps|volume|network|images) exit 0 ;;   # no output: nothing is attributable
esac
exit 0'

mk_project "$TMP/p1"
mk_docker "$STUB_EMPTY"
out="$( cd "$TMP/p1" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new orphan --branch wt/orphan 2>&1 )"; rc=$?

# 1. it must still print the handle: the worktree exists and is usable, and a
#    user who is not shown its directory cannot tear it down at all.
grep -q 'worktree ready' <<<"$out" \
  || fail "1: the handle must still be printed before the failure is reported, got (rc=$rc): $out"

# 2. it must SAY what is wrong, naming the label the teardown searches by.
grep -qi 'no Docker resource carries the project label' <<<"$out" \
  || fail "2: zero attributable resources was not reported as a failure, got (rc=$rc): $out"

# 3. exit 3, not 0 and not 2 — created and running, but the config does not
#    describe it. Exit 2 would tell a caller to retry `new`, which then dies on
#    "destination already exists" and strands the stack.
[[ "$rc" -eq 3 ]] \
  || fail "3: expected exit 3 (created but undescribed), got $rc"

# --- the converse: a labelled stack must stay silent and exit 0 -------------
mk_project "$TMP/p2"
mk_docker '#!/bin/sh
case "$1" in
  info)    exit 0 ;;
  compose) exit 0 ;;
  ps)      echo "p2-wt-good-backend" ;;
  volume)  echo "p2-wt-good_dbdata" ;;
  network) echo "p2-wt-good_default" ;;
  images)  exit 0 ;;
esac
exit 0'
out2="$( cd "$TMP/p2" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new good --branch wt/good 2>&1 )"; rc2=$?
grep -qi 'no Docker resource carries the project label' <<<"$out2" \
  && fail "4: a properly labelled stack was reported as unattributable, got: $out2"
# The exit code too, not only the message: asserting the absence of a string
# leaves parity_rc free to become 3 for an unrelated reason and still pass.
[[ "$rc2" -eq 0 ]] \
  || fail "5: a properly labelled stack must exit 0, got $rc2: $out2"

# --- worktree-c04: a sibling slug's resources are not this stack's ----------
# The volume/network half of the count matched `grep -F $CPROJ`, a substring, so
# for slug `foo` the resources of a live sibling `foo-bar` (p3-wt-foo-bar_*)
# made an unlabelled stack read as attributable and the error never fired.
mk_project "$TMP/p3"
mk_docker '#!/bin/sh
case "$1" in
  volume)  echo "p3-wt-foo-bar_pgdata" ;;
  network) echo "p3-wt-foo-bar_default" ;;
esac
exit 0'
out3="$( cd "$TMP/p3" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new foo --branch wt/foo 2>&1 )"; rc3=$?
grep -qi 'no Docker resource carries the project label' <<<"$out3" \
  || fail "6: a sibling slug's volume and network were counted as this stack's, got (rc=$rc3): $out3"

# The other side of that boundary: this stack's own `<project>_<name>` volume
# and network must still count, with no container to carry the count instead
# (p2 lists one, so a boundary that admits only the bare project name passed it).
mk_project "$TMP/p4"
mk_docker '#!/bin/sh
case "$1" in
  volume)  echo "p4-wt-foo_pgdata" ;;
  network) echo "p4-wt-foo_default" ;;
esac
exit 0'
out4="$( cd "$TMP/p4" && PATH="$BIN:$PATH" bash "$S/worktree.sh" new foo --branch wt/foo 2>&1 )"; rc4=$?
grep -qi 'no Docker resource carries the project label' <<<"$out4" \
  && fail "7: this stack's own <project>_<name> volume and network were not counted, got (rc=$rc4): $out4"
[[ "$rc4" -eq 0 ]] || fail "8: a stack attributable by its volume and network alone must exit 0, got $rc4: $out4"

if [[ "$failures" -eq 0 ]]; then
  echo "PASS: test-attributability.sh"
  exit 0
fi
printf '%d failure(s)\n' "$failures"
exit 1
