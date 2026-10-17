#!/usr/bin/env bash
# test-port-held.sh — "held" means LISTENING, in the slot allocator and in the listing alike.
#
# `worktree.sh list` reports a port as held only when something LISTENs on it. The
# allocator in `new` probed `lsof -ti :PORT` with no state filter, so a port that
# only had an outgoing or established socket on it (a client whose local port
# happens to be a slot's port) made `new` skip that slot, and `list` could not
# explain why (worktree-s28, owner decision Q9, 2026-10-15). A listener must still
# be skipped: only the non-listening socket stops counting.
#
# Layer: the script itself in a temp project; the defect is in which lsof query the
# allocator runs, so only a real socket on a real port can show it. Docker is a stub.
#
# Run with: bash skills/worktree/tests/test-port-held.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

command -v lsof >/dev/null 2>&1 || { echo "SKIP — lsof not available"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP — python3 not available"; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/w19.XXXXXX")"; TMP="$(cd "$TMP" && pwd -P)"
PIDS=""
cleanup() { [[ -n "$PIDS" ]] && kill $PIDS 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

# A free port to play slot 1's DB_PORT: base = PORT - stride, so slot 1 lands on PORT.
PORT="$(python3 -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
STRIDE=100
PROJ="$TMP/heldproj"
mkdir -p "$PROJ/.context/worktrees" "$PROJ/backend"
cat > "$PROJ/.context/worktrees/config.env" <<ENV
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_PORT_VARS="DB_PORT=$((PORT - STRIDE))"
WT_PORT_STRIDE=$STRIDE
WT_MAX_SLOTS=3
ENV
SLOTS="$TMP/slots"; SD="$SLOTS/aidex-wt-slots-heldproj"; mkdir -p "$SD"
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nexit 0\n' > "$BIN/docker"; chmod +x "$BIN/docker"
# `backend` is not a git repo: `new` fails in worktree-multi AFTER its slot is reserved
# and reported ("slot N -> ..."), which is all this test reads.
run_new() { out="$( cd "$PROJ" && TMPDIR="$SLOTS" PATH="$BIN:$PATH" bash "$WT" new "$1" --branch "wt/$1" --base main 2>&1 )"; }

# A background python holding a socket on PORT. $1 = listen | outgoing. Prints nothing;
# waits (bounded) until lsof sees PORT, then sets HOLDER.
hold_port() {
  python3 -c '
import socket, sys, time
mode, port = sys.argv[1], int(sys.argv[2])
if mode == "listen":
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port)); s.listen(1)
else:
    srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1)
    s = socket.socket(); s.bind(("127.0.0.1", port)); s.connect(srv.getsockname())
time.sleep(60)
' "$1" "$PORT" & HOLDER=$!
  PIDS="$PIDS $HOLDER"
  local _
  for _ in $(seq 1 50); do lsof -nP -ti :"$PORT" >/dev/null 2>&1 && return 0; sleep 0.1; done
  fail "fixture: nothing came to hold port $PORT ($1)"
}
release_port() { kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; rm -f "$SD"/slot-*; }

# --- 1. an outgoing socket on the slot's port does not make the slot busy -------
hold_port outgoing
lsof -nP -ti :"$PORT" -sTCP:LISTEN >/dev/null 2>&1 \
  && fail "fixture: the outgoing holder must not be listening on $PORT"
run_new outgoing
grep -q "slot 1 -> DB_PORT=$PORT" <<<"$out" \
  || fail "outgoing: a non-listening socket on the slot's port must not skip slot 1, got: $out"
release_port

# --- 2. a listener on the slot's port still skips that slot ---------------------
hold_port listen
run_new listener
grep -q "slot 2 -> DB_PORT=$((PORT + STRIDE))" <<<"$out" \
  || fail "listener: a listening port must still skip slot 1 and land on slot 2, got: $out"
release_port

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — slot allocator: only a LISTENing socket makes a port held, as in the listing"
