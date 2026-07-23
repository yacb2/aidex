#!/usr/bin/env bash
# test-orphan-sweep.sh — isolated tests for orphan-sweep.sh. Stubs `docker` via
# a PATH shim (mirrors the AIDEX_JUDGE_CMD/claude-shim injection pattern in
# hooks/test-durability-hook.sh) so no real Docker daemon is required.
#
# Cases: orphan detected when the worktree dir is missing; no false positive
# when the dir exists; --check exit codes; docker-absent degradation.
#
# Run with: bash skills/aidex-worktree/tests/test-orphan-sweep.sh

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
if printf '%s' "$out" | grep -q 'ORPHAN compose project: myproj-wt-dead'; then
  pass "orphaned compose project reported"
else
  fail "orphaned compose project not reported: $out"
fi
if printf '%s' "$out" | grep -q 'docker compose -p myproj-wt-dead down -v --rmi local --remove-orphans'; then
  pass "exact worktree_down command printed for orphan"
else
  fail "worktree_down command missing/wrong: $out"
fi
if printf '%s' "$out" | grep -q 'ORPHAN volume: myproj-wt-orphanvol_pgdata'; then
  pass "orphaned volume reported"
else
  fail "orphaned volume not reported: $out"
fi
if printf '%s' "$out" | grep -q 'ORPHAN image: myproj-wt-orphanimg'; then
  pass "orphaned image reported"
else
  fail "orphaned image not reported: $out"
fi

echo "== no false positive when the dir exists =="
if printf '%s' "$out" | grep -q 'ORPHAN compose project: myproj-wt-alive'; then
  fail "live compose project (dir exists) falsely flagged as orphan"
else
  pass "live compose project not flagged"
fi
if printf '%s' "$out" | grep -q 'ORPHAN volume: myproj-wt-alive_pgdata'; then
  fail "live volume falsely flagged as orphan"
else
  pass "live volume not flagged"
fi
if printf '%s' "$out" | grep -q 'ORPHAN image: myproj-wt-alive'; then
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
if printf '%s' "$out" | grep -qi 'docker not found'; then
  pass "docker-absent prints a degradation notice"
else
  fail "docker-absent notice missing: $out"
fi
if [[ "$code" -eq 0 ]]; then
  pass "docker-absent exits 0"
else
  fail "docker-absent should exit 0, got $code"
fi

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
