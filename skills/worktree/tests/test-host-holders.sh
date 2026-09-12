#!/usr/bin/env bash
# test-host-holders.sh — BL-376: what Docker never owned.
#
# In a hybrid stack the frontend runs as a host process, so a worktree acquires a
# Vite dev server `compose down` never sees: it keeps the port, holds the deleted
# directory open, and one rewrote frontend/.vite/deps/ after the tree was removed.
# Two assertions, both on a real process and no daemon (Docker is stubbed):
#   1. `down --reap` terminates a process whose cwd is the worktree, by PID.
#   2. `list` flags a slot nobody claims whose port is still held — the tree is
#      gone and the holder survived, which is the state that makes the next `new`
#      collide on a port nothing on screen names.
#
# Run with: bash skills/worktree/tests/test-host-holders.sh
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
S="$DIR/../scripts"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
export TMPDIR="$TMP/slots"; mkdir -p "$TMPDIR"
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nexit 0\n' > "$BIN/docker"; chmod +x "$BIN/docker"

# A free port for the fixture's slot 1 (base + 1 * stride).
BASE=$(( 20000 + (RANDOM % 20000) )); PORT=$(( BASE + 100 ))
mkdir -p "$TMP/p/.context/worktrees" "$TMP/p/backend"
cat > "$TMP/p/.context/worktrees/config.env" <<ENV
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_PORT_VARS="FRONTEND_PORT=$BASE"
ENV
( cd "$TMP/p/backend" && /usr/bin/git init -q . && /usr/bin/git config user.email t@e.com \
  && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
( cd "$TMP/p" && bash "$S/worktree.sh" new hold --branch wt/hold --no-infra ) >/dev/null 2>&1 \
  || fail "fixture: worktree new failed"
WT="$(cd "$TMP/p-wt-hold" && pwd -P)"

# --- 1. down --reap terminates the holder, by PID ----------------------------
( cd "$WT" && exec sleep 300 ) & SLEEPER=$!; PIDS+=("$SLEEPER")
sleep 0.3
out="$( cd "$TMP/p" && PATH="$BIN:$PATH" bash "$S/worktree.sh" down hold --force --reap 2>&1 )"
grep -q "pid $SLEEPER" <<<"$out" \
  || fail "#1: the sleeper holding the worktree was not enumerated: $out"
sleep 0.5
kill -0 "$SLEEPER" 2>/dev/null \
  && fail "#1: the sleeper survived down --reap: $out"

# --- 2. list flags an unclaimed slot whose port is still held -----------------
( cd "$TMP" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 ) >/dev/null 2>&1 & LISTENER=$!; PIDS+=("$LISTENER")
for _ in 1 2 3 4 5 6 7 8 9 10; do lsof -nP -ti :"$PORT" >/dev/null 2>&1 && break; sleep 0.2; done
out="$( cd "$TMP/p" && PATH="$BIN:$PATH" bash "$S/worktree.sh" list 2>&1 )"
grep -q "port $PORT" <<<"$out" && grep -q "slot 1" <<<"$out" \
  || fail "#2: list did not flag slot 1's port $PORT held with no worktree: $out"
out="$( cd "$TMP/p" && PATH="$BIN:$PATH" bash "$S/worktree.sh" list --porcelain 2>&1 )"
grep -q "PORT-HELD" <<<"$out" \
  || fail "#2: list --porcelain carries no PORT-HELD record: $out"

if [[ "$failures" -eq 0 ]]; then echo "OK — host holders: 2 cells"; else echo "host holders FAILED ($failures)"; exit 1; fi
