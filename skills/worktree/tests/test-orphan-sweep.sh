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

echo "== an image label lookup that times out is degraded, not clean (BL-774) =="
# The image's compose-project label decides its owner; a wedged `image inspect`
# leaves the image unjudged, and the sweep must not call that an all-clear.
mkdir -p "$TMP/ibin"
cat > "$TMP/ibin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "info ") exit 0 ;;
  "images --format") echo myproj-wt-alive ;;
  "image inspect") trap '' ALRM; exec sleep 6 ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/ibin/docker"
t0=$SECONDS
out="$( cd "$ROOT" && PATH="$TMP/ibin:$PATH" AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" 2>&1 )"; code=$?
el=$((SECONDS - t0))
[[ "$el" -le 4 ]] && pass "the label lookup returned at the deadline (${el} s)" \
  || fail "a wedged image inspect held the sweep for ${el} s (deadline 1 s): $out"
printf '%s' "$out" | grep >/dev/null 'No orphaned' \
  && fail "an image whose label lookup timed out was swept as clean: $out" \
  || pass "a timed-out label lookup is not an all-clear"
printf '%s' "$out" | grep >/dev/null 'did not answer within 1 s' \
  && pass "the label timeout is reported" \
  || fail "no 'did not answer' note for the image label lookup: $out"
[[ "$code" -eq 0 ]] && pass "a plain run with an unjudged image still exits 0" \
  || fail "a plain (report-only) run with an unjudged image exited $code"
# Under --slug an exit 0 means "nothing attributable" and lets a teardown go ahead.
out="$( cd "$ROOT" && PATH="$TMP/ibin:$PATH" AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" --slug alive 2>&1 )"; code=$?
[[ "$code" -eq 1 ]] && pass "--slug with an unjudged image exits 1" \
  || fail "--slug read an unjudged image as nothing attributable (exit $code): $out"
printf '%s' "$out" | grep >/dev/null 'RESOURCE image: myproj-wt-alive' \
  && fail "--slug attributed an unjudged image by its name: $out" \
  || pass "--slug does not attribute an unjudged image by name"

echo "== every other docker call is bounded and a timeout is degraded (Q28a) =="
# Inventory calls (ps, volume ls, images, dangling ids, dangling label, network
# ls) and the per-class follow-ups: a wedged one must leave the sweep reported
# incomplete, never an empty inventory read as "No orphaned". HANG is a glob over
# the stub's argument string (that call ignores ALRM and sleeps 6 s); ORPH names
# the one call that carries orphan evidence, every other call answers with the
# live worktree only -- so when HANG hides ORPH, a sweep that trusts the empty
# answer has nothing to report.
mkdir -p "$TMP/hbin"
cat > "$TMP/hbin/docker" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$CLOG"
[[ "$*" == $HANG ]] && { trap '' ALRM; exec sleep 6; }
who=alive; [[ "$*" == $ORPH ]] && who=gone
case "$*" in
  info) ;;
  ps*) echo myproj-wt-$who ;;
  "volume ls"*) echo myproj-wt-${who}_pgdata ;;
  "images --format"*) echo myproj-wt-$who ;;
  "images -f dangling=true -q") echo abc ;;
  "images -f dangling=true -f label="*) echo abc ;;
  "image inspect"*) ;;
  "inspect -f"*) echo myproj-wt-$who ;;
  "network ls"*) echo myproj-wt-${who}_default ;;
  "network inspect"*) echo 0 ;;
esac
exit 0
SHIM
chmod +x "$TMP/hbin/docker"
# "<hung call>|<call that carries the orphan evidence>"
for pair in "ps*|ps*" "volume ls*|volume ls*" "images --format*|images --format*" \
            "network ls*|network ls*" "images -f dangling=true -q|inspect -f*" \
            "inspect -f*|inspect -f*" "images -f dangling=true -f label=*|inspect -f*" \
            "network inspect*|network ls*"; do
  HANG="${pair%%|*}" ORPH="${pair#*|}"
  for mode in plain check slug; do
    args=(); [[ $mode == slug ]] && args=(--slug gone); [[ $mode == check ]] && args=(--check)
    t0=$SECONDS; CLOG="$TMP/hlog"; : > "$CLOG"
    out="$( cd "$ROOT" && PATH="$TMP/hbin:$PATH" CLOG="$CLOG" HANG="$HANG" ORPH="$ORPH" AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" ${args[@]+"${args[@]}"} 2>&1 )"; code=$?
    el=$((SECONDS - t0))
    [[ "$el" -le 5 ]] || fail "$HANG ($mode): a wedged call held the sweep for ${el} s (deadline 1 s)"
    printf '%s' "$out" | grep >/dev/null 'did not answer within 1 s' \
      && pass "$HANG ($mode): the timeout is reported" \
      || fail "$HANG ($mode): no 'did not answer' note: $out"
    printf '%s' "$out" | grep >/dev/null -e 'No orphaned' -e 'no Docker resources attributable' \
      && fail "$HANG ($mode): a timed-out call was read as an all-clear: $out" \
      || pass "$HANG ($mode): not an all-clear"
    printf '%s' "$out" | grep >/dev/null 'sweep incomplete (degraded)' \
      && pass "$HANG ($mode): reported incomplete" \
      || fail "$HANG ($mode): sweep not reported incomplete: $out"
    printf '%s' "$out" | grep >/dev/null -e 'docker network rm' -e 'docker rmi abc' \
      && fail "$HANG ($mode): a reclaim command was printed for a resource the timed-out call was meant to judge: $out"
    # Breaker (owner 2026-10-14): the hung call is the last one docker ever sees,
    # and the warning counts exactly one timeout.
    last="$(tail -1 "$CLOG")"
    [[ "$last" == $HANG ]] && pass "$HANG ($mode): no docker call after the deadline hit" \
      || fail "$HANG ($mode): docker was called after the deadline hit (last: $last)"
    printf '%s' "$out" | grep -E >/dev/null '1 docker call\(s\) timed out; [0-9]+ skipped after the breaker tripped' \
      && pass "$HANG ($mode): one timeout, the rest skipped" \
      || fail "$HANG ($mode): warning does not count one timeout and the skipped calls: $out"
    want=0; [[ $mode != plain ]] && want=1
    [[ "$code" -eq "$want" ]] && pass "$HANG ($mode): exit $want" \
      || fail "$HANG ($mode): expected exit $want, got $code"
  done
done
out="$( cd "$ROOT" && PATH="$TMP/hbin:$PATH" CLOG="$TMP/hlog" HANG="ps*" ORPH=none AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" 2>&1 )"
printf '%s' "$out" | grep >/dev/null '1 docker call(s) timed out; 4 skipped after the breaker tripped' \
  && pass "ps* hang: 4 inventory calls skipped" || fail "ps* hang: expected '4 skipped': $out"

echo "== a non-timeout failure of an inventory call does not trip the breaker =="
mkdir -p "$TMP/fbin"
cat > "$TMP/fbin/docker" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$CLOG"
case "$*" in ps*) exit 1 ;; esac
exit 0
SHIM
chmod +x "$TMP/fbin/docker"
CLOG="$TMP/flog"; : > "$CLOG"
out="$( cd "$ROOT" && PATH="$TMP/fbin:$PATH" CLOG="$CLOG" AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" 2>&1 )"
grep >/dev/null '^network ls' "$CLOG" && pass "ps exit 1: the sweep goes on to network ls" \
  || fail "ps exit 1: the sweep stopped after a non-timeout failure: $(cat "$CLOG")"
printf '%s' "$out" | grep >/dev/null 'skipped after the breaker' \
  && fail "ps exit 1: breaker reported on a non-timeout failure: $out" || pass "ps exit 1: no breaker report"

echo "== a dangling project whose lookup is skipped by the breaker stays listed, unjudged =="
mkdir -p "$TMP/dbin"
cat > "$TMP/dbin/docker" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$CLOG"
case "$*" in
  "images -f dangling=true -q") printf '%s\n' d1 d2 ;;
  "inspect -f"*d1) echo myproj-wt-gonea ;;
  "inspect -f"*d2) echo myproj-wt-goneb ;;
  "images -f dangling=true -f label="*)
    [[ "$MODE" == hang ]] && { trap '' ALRM; exec sleep 6; }
    [[ "$*" == *gonea* ]] && echo d1
    [[ "$*" == *goneb* ]] && echo d2 ;;
esac
exit 0
SHIM
chmod +x "$TMP/dbin/docker"
CLOG="$TMP/dlog"; : > "$CLOG"
out="$( cd "$ROOT" && PATH="$TMP/dbin:$PATH" CLOG="$CLOG" MODE=hang AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" 2>&1 )"
for p in gonea goneb; do
  printf '%s' "$out" | grep >/dev/null "dangling images: myproj-wt-$p (not judged)" \
    && pass "dangling $p: listed as not judged" || fail "dangling $p: vanished from the listing: $out"
done
n="$(grep -c '^images -f dangling=true -f label=' "$CLOG")"
[[ "$n" -eq 1 ]] && pass "dangling: the second lookup was skipped by the breaker" \
  || fail "dangling: $n label lookups reached docker (breaker should stop at 1)"
printf '%s' "$out" | grep >/dev/null '2 orphan(s) found' \
  && pass "dangling: both unjudged projects are counted" || fail "dangling: unjudged projects not counted: $out"
printf '%s' "$out" | grep >/dev/null 'docker rmi' && fail "dangling: a removal command was printed: $out" \
  || pass "dangling: no removal command"
: > "$CLOG"
out="$( cd "$ROOT" && PATH="$TMP/dbin:$PATH" CLOG="$CLOG" MODE=ok AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" 2>&1 )"
printf '%s' "$out" | grep >/dev/null 'dangling images: myproj-wt-gonea (1)' && printf '%s' "$out" | grep >/dev/null '  docker rmi d1' \
  && pass "dangling healthy: judged and reclaimable" || fail "dangling healthy: not judged on a healthy daemon: $out"
printf '%s' "$out" | grep >/dev/null 'not judged' && fail "dangling healthy: reported not judged: $out" \
  || pass "dangling healthy: nothing unjudged"

echo "== a network whose inspect timed out stays listed, never force-removable; an empty answer is not 0 =="
for case in hang empty; do
  if [[ $case == hang ]]; then H="network inspect*"; else H="none"; fi
  mkdir -p "$TMP/nbin2"
  cat > "$TMP/nbin2/docker" <<'SHIM'
#!/usr/bin/env bash
[[ "$*" == $HANG ]] && { trap '' ALRM; exec sleep 6; }
case "$*" in
  "network ls"*) echo myproj-wt-gone_default ;;
  "network inspect"*) exit 0 ;;
esac
exit 0
SHIM
  chmod +x "$TMP/nbin2/docker"
  out="$( cd "$ROOT" && PATH="$TMP/nbin2:$PATH" HANG="$H" AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" 2>&1 )"
  printf '%s' "$out" | grep >/dev/null 'ORPHAN network: myproj-wt-gone_default' \
    && pass "$case: the network is still listed" || fail "$case: the network vanished from the list: $out"
  printf '%s' "$out" | grep >/dev/null 'docker network rm' \
    && fail "$case: a force-remove command was printed without an attached count: $out" \
    || pass "$case: no 'docker network rm'"
  if [[ $case == hang ]]; then
    printf '%s' "$out" | grep >/dev/null '1 orphan(s) found' \
      && pass "hang: the unjudged orphan network is counted" || fail "hang: the listed orphan network was not counted: $out"
  fi
done

echo "== the first deadline hit trips a breaker: no further docker call (owner 2026-10-14) =="
# Layer: script-level, stubbed docker. Four orphan-named images and an `image inspect`
# that hangs: without the breaker each one waits the deadline (N x dt) and a later
# call may still judge/print; with it exactly one call waits and the rest stay unjudged.
mkdir -p "$TMP/cbin"
cat > "$TMP/cbin/docker" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$CLOG"
case "$1 ${2:-}" in
  "info ") exit 0 ;;
  "images --format") printf '%s\n' myproj-wt-g1 myproj-wt-g2 myproj-wt-g3 myproj-wt-g4 ;;
  "image inspect") [[ "$MODE" == hang ]] && { trap '' ALRM; exec sleep 6; }; exit 1 ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/cbin/docker"
for mode in hang fail; do
  CLOG="$TMP/clog-$mode"; : > "$CLOG"
  for flag in "" --check; do
    : > "$CLOG"
    out="$( cd "$ROOT" && PATH="$TMP/cbin:$PATH" CLOG="$CLOG" MODE=$mode AIDEX_DOCKER_TIMEOUT=1 bash "$SCRIPT" $flag 2>&1 )"; code=$?
    n="$(grep -c '^image inspect' "$CLOG")"
    if [[ $mode == hang ]]; then
      [[ "$n" -eq 1 ]] && pass "hang ${flag:-plain}: one image inspect waited the deadline" \
        || fail "hang ${flag:-plain}: $n image inspect calls reached docker (breaker should stop at 1): $out"
      printf '%s' "$out" | grep >/dev/null '1 docker call(s) timed out; 3 skipped after the breaker tripped' \
        && pass "hang ${flag:-plain}: warning counts the timeout and the skipped calls" \
        || fail "hang ${flag:-plain}: warning does not state timed-out and skipped counts: $out"
      printf '%s' "$out" | grep >/dev/null -e 'ORPHAN image' -e 'No orphaned' -e 'docker rmi' \
        && fail "hang ${flag:-plain}: a skipped image was judged (orphan or clean): $out" \
        || pass "hang ${flag:-plain}: skipped images are neither orphan nor clean"
      want=0; [[ -n $flag ]] && want=1
      [[ "$code" -eq "$want" ]] && pass "hang ${flag:-plain}: exit $want" || fail "hang ${flag:-plain}: expected exit $want, got $code"
    else
      [[ "$n" -eq 4 ]] && pass "fail ${flag:-plain}: a non-timeout failure does not trip the breaker (4 inspects)" \
        || fail "fail ${flag:-plain}: $n image inspect calls (a plain failure must not stop the sweep): $out"
      printf '%s' "$out" | grep >/dev/null 'skipped after the breaker' \
        && fail "fail ${flag:-plain}: breaker reported on a non-timeout failure: $out" || pass "fail ${flag:-plain}: no breaker report"
    fi
  done
done

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
