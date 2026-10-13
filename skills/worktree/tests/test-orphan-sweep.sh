#!/usr/bin/env bash
# test-orphan-sweep.sh — isolated tests for orphan-sweep.sh. Stubs `docker` via
# a PATH shim (mirrors the AIDEX_JUDGE_CMD/claude-shim injection pattern in
# hooks/test-durability-hook.sh) so no real Docker daemon is required.
#
# Cases: orphan detected when the worktree dir is missing; no false positive
# when the dir exists; --check exit codes; docker-absent degradation.
#
# Run with: bash skills/worktree/tests/test-orphan-sweep.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$HERE/../scripts/orphan-sweep.sh"

PASS=0; FAIL=0
pass() { echo "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- fixture workspace: a real git repo named "myproj" with one live
#     worktree sibling (myproj-wt-alive) already on disk. -----------------
ROOT="$TMP/myproj"
mkdir -p "$ROOT/.context"
git init -q "$ROOT"
git -C "$ROOT" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$TMP/myproj-wt-alive"

# --- docker stub: reports one live project/volume/image (matches the
#     on-disk sibling) and one orphaned project/volume/image each (no
#     matching worktree dir anywhere). -----------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  ps)
    printf '%s\n' "myproj-wt-alive" "myproj-wt-dead"
    ;;
  volume)
    printf '%s\n' "myproj-wt-alive_pgdata" "myproj-wt-orphanvol_pgdata"
    ;;
  images)
    printf '%s\n' "myproj-wt-alive" "myproj-wt-orphanimg"
    ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/bin/docker"

run_sweep() {
  ( cd "$ROOT" && PATH="$TMP/bin:$PATH" bash "$SCRIPT" "$@" )
}

echo "== orphan detected when worktree dir is missing =="
out="$(run_sweep)"; code=$?
if printf '%s' "$out" | grep >/dev/null 'ORPHAN compose project: myproj-wt-dead'; then
  pass "orphaned compose project reported"
else
  fail "orphaned compose project not reported: $out"
fi
if printf '%s' "$out" | grep >/dev/null 'docker compose -p myproj-wt-dead down -v --rmi local --remove-orphans'; then
  pass "exact worktree_down command printed for orphan"
else
  fail "worktree_down command missing/wrong: $out"
fi
if printf '%s' "$out" | grep >/dev/null 'ORPHAN volume: myproj-wt-orphanvol_pgdata'; then
  pass "orphaned volume reported"
else
  fail "orphaned volume not reported: $out"
fi
if printf '%s' "$out" | grep >/dev/null 'ORPHAN image: myproj-wt-orphanimg'; then
  pass "orphaned image reported"
else
  fail "orphaned image not reported: $out"
fi

echo "== no false positive when the dir exists =="
if printf '%s' "$out" | grep >/dev/null 'ORPHAN compose project: myproj-wt-alive'; then
  fail "live compose project (dir exists) falsely flagged as orphan"
else
  pass "live compose project not flagged"
fi
if printf '%s' "$out" | grep >/dev/null 'ORPHAN volume: myproj-wt-alive_pgdata'; then
  fail "live volume falsely flagged as orphan"
else
  pass "live volume not flagged"
fi
if printf '%s' "$out" | grep >/dev/null 'ORPHAN image: myproj-wt-alive'; then
  fail "live image falsely flagged as orphan"
else
  pass "live image not flagged"
fi

echo "== --check exit codes =="
run_sweep --check >/dev/null 2>&1
code=$?
if [[ "$code" -eq 1 ]]; then
  pass "--check exits 1 when orphans exist"
else
  fail "--check should exit 1 when orphans exist, got $code"
fi

run_sweep >/dev/null 2>&1
code=$?
if [[ "$code" -eq 0 ]]; then
  pass "no --check exits 0 even when orphans exist (report-only)"
else
  fail "no --check should exit 0 regardless of orphans, got $code"
fi

# --- second fixture: no orphans at all (docker only reports the live set) ---
mkdir -p "$TMP/bin-clean"
cat > "$TMP/bin-clean/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  ps) printf '%s\n' "myproj-wt-alive" ;;
  volume) printf '%s\n' "myproj-wt-alive_pgdata" ;;
  images) printf '%s\n' "myproj-wt-alive" ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/bin-clean/docker"
( cd "$ROOT" && PATH="$TMP/bin-clean:$PATH" bash "$SCRIPT" --check >/dev/null 2>&1 )
code=$?
if [[ "$code" -eq 0 ]]; then
  pass "--check exits 0 when no orphans exist"
else
  fail "--check should exit 0 with no orphans, got $code"
fi

echo "== docker-absent degradation =="
mkdir -p "$TMP/bin-empty"
out="$( ( cd "$ROOT" && PATH="$TMP/bin-empty:/usr/bin:/bin" bash "$SCRIPT" ) 2>&1 )"
code=$?
if printf '%s' "$out" | grep >/dev/null -i 'docker not found'; then
  pass "docker-absent prints a degradation notice"
else
  fail "docker-absent notice missing: $out"
fi
if [[ "$code" -eq 0 ]]; then
  pass "docker-absent exits 0"
else
  fail "docker-absent should exit 0, got $code"
fi

echo "== a normalised compose project name (worktree-c06) =="
# A workspace directory `My.App` gets compose projects `myapp-wt-<slug>`; the sweep
# used to look for `My.App-wt-` and saw nothing, so a live stack read as absent.
NROOT="$TMP/My.App"; mkdir -p "$NROOT/.context" "$TMP/My.App-wt-cn" "$NROOT/_worktrees/My.App-wt-cx"
git init -q "$NROOT"
git -C "$NROOT" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$TMP/nbin"
cat > "$TMP/nbin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  ps) printf '%s\n' "myapp-wt-cn" "myapp-wt-dead" "myapp-wt-cx" ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/nbin/docker"
out="$( cd "$NROOT" && PATH="$TMP/nbin:$PATH" bash "$SCRIPT" )"
printf '%s' "$out" | grep >/dev/null 'ORPHAN compose project: myapp-wt-dead' \
  && pass "an orphan under a normalised name is reported" \
  || fail "the normalised-name orphan was not seen: $out"
printf '%s' "$out" | grep >/dev/null 'ORPHAN compose project: myapp-wt-cn' \
  && fail "a live My.App-wt-cn worktree made its own myapp-wt-cn stack look orphaned: $out" \
  || pass "the live worktree's stack is not an orphan"
# A live `_worktrees/My.App-wt-cx` is the same stack under the normalised name.
printf '%s' "$out" | grep >/dev/null 'ORPHAN compose project: myapp-wt-cx' \
  && fail "a live _worktrees/My.App-wt-cx made its own myapp-wt-cx stack look orphaned: $out" \
  || pass "a live _worktrees/<ws>-wt-<slug> stack is not an orphan"
# A glob character in the workspace name is literal, not a pattern (p[1] vs p1).
GROOT="$TMP/p[1]"; mkdir -p "$GROOT/.context" "$TMP/p[1]-wt-cn"
git init -q "$GROOT"
git -C "$GROOT" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$TMP/gbin"
cat > "$TMP/gbin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  ps) printf '%s\n' "p1-wt-cn" ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/gbin/docker"
out="$( cd "$GROOT" && PATH="$TMP/gbin:$PATH" bash "$SCRIPT" )"
printf '%s' "$out" | grep >/dev/null 'ORPHAN compose project: p1-wt-cn' \
  && fail "p[1]: a live p[1]-wt-cn worktree made the p1-wt-cn stack look orphaned: $out" \
  || pass "a glob character in the workspace name is literal"
out="$( cd "$NROOT" && PATH="$TMP/nbin:$PATH" bash "$SCRIPT" --slug cn )"; code=$?
{ [[ "$code" -eq 1 ]] && printf '%s' "$out" | grep >/dev/null 'RESOURCE compose project: myapp-wt-cn'; } \
  && pass "--slug cn sees the myapp-wt-cn stack" \
  || fail "--slug cn missed the myapp-wt-cn stack (exit $code): $out"

echo "== a wedged daemon is cut at the deadline (BL-794) =="
# The docker CLI is a Go binary and ignores SIGALRM, so `alarm; exec docker info`
# never stopped it. The stub ignores ALRM and sleeps 6 s; with a 1 s deadline the
# sweep must be back well before that, saying the daemon did not answer.
mkdir -p "$TMP/wbin"
cat > "$TMP/wbin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  info) trap '' ALRM; exec sleep 6 ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/wbin/docker"
t0=$SECONDS
out="$( cd "$ROOT" && PATH="$TMP/wbin:$PATH" AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" 2>&1 )"; code=$?
el=$((SECONDS - t0))
[[ "$el" -le 4 ]] && pass "the sweep returned at the deadline (${el} s)" \
  || fail "a docker that ignores SIGALRM held the sweep for ${el} s (deadline 1 s): $out"
printf '%s' "$out" | grep >/dev/null 'did not answer within 1 s' \
  && pass "a deadline hit is reported as such" \
  || fail "no 'did not answer' note on a deadline hit: $out"
[[ "$code" -eq 0 ]] && pass "a degraded sweep exits 0" || fail "a degraded sweep should exit 0, got $code"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
