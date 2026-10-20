#!/usr/bin/env bash
# test-orphan-sweep.sh — isolated tests for orphan-sweep.sh. Stubs `docker` via
# a PATH shim (mirrors the AIDEX_JUDGE_CMD/claude-shim injection pattern in
# docs/retired/hooks/test-durability-hook.sh) so no real Docker daemon is required.
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
  ps) # project, working_dir (the dead one's is gone), mounts
    printf '%s\t%s\t\n' "myproj-wt-alive" "" "myproj-wt-dead" /nonexistent/myproj-wt-dead
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
if printf '%s' "$out" | grep >/dev/null 'docker compose -p myproj-wt-dead down --rmi local --remove-orphans'; then
  pass "exact worktree_down command printed for orphan"
else
  fail "worktree_down command missing/wrong: $out"
fi
# No container of myproj-wt-orphanvol proves its worktree gone: listed, never `volume rm` (BL-857).
if printf '%s' "$out" | grep >/dev/null 'NOT JUDGED volume: myproj-wt-orphanvol_pgdata'; then
  pass "container-less volume reported, not judged"
else
  fail "container-less volume not reported as NOT JUDGED: $out"
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
NROOT="$TMP/My.App"; mkdir -p "$NROOT/.context" "$TMP/My.App-wt-cn"
git init -q "$NROOT"
git -C "$NROOT" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$TMP/nbin"
cat > "$TMP/nbin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1" in
  info) exit 0 ;;
  ps) printf '%s\t%s\t\n' "myapp-wt-cn" "" "myapp-wt-dead" /nonexistent/myapp-wt-dead ;;
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

echo "== no destructive line for a live, unjudgeable or volume-sharing project (BL-857) =="
# Layer: script-level, docker shim that answers per --format (no daemon). The name rule
# alone handed `down -v` to a live worktree at a custom location; a pinned volume
# (ph_postgres_data) shared with the main stack got `down -v` too.
mkdir -p "$TMP/elsewhere/myproj-wt-custom" "$TMP/vbin"
cat > "$TMP/vbin/docker" <<SHIM
#!/usr/bin/env bash
T=\$'\t'
case "\$*" in
  info) ;;
  "ps -a --no-trunc"*working_dir*Mounts*State*) cat <<EOF   # without --no-trunc docker cuts volume names
myproj-wt-custom\${T}$TMP/elsewhere/myproj-wt-custom\${T}myproj-wt-custom_db
myproj-wt-nolabel\${T}\${T}myproj-wt-nolabel_db
myproj-wt-shared\${T}$TMP/gone/myproj-wt-shared\${T}ph_postgres_data
myproj-wt-shared\${T}$TMP/gone/myproj-wt-shared\${T}ph_postgres_data
myproj\${T}$TMP/myproj\${T}ph_postgres_data,/host/src
myproj\${T}$TMP/myproj\${T}ph_postgres_data
myproj-wt-gone2\${T}$TMP/gone/myproj-wt-gone2\${T}/host/src,myproj-wt-gone2_db
otherproj\${T}$TMP/other\${T}myproj-wt-gone3_db
myproj-wt-moved\${T}$TMP/gone/m\${T}myproj-wt-moved_db\${T}running
\${T}\${T}myproj-wt-gone4_db
EOF
  ;;
  "ps -a"*) printf '%s\n' myproj-wt-custom myproj-wt-nolabel myproj-wt-shared myproj myproj-wt-gone2 otherproj "" ;;
  "volume ls"*) printf '%s\n' myproj-wt-custom_db myproj-wt-nolabel_db ph_postgres_data myproj-wt-gone2_db myproj-wt-gone3_db myproj-wt-gone4_db myproj-wt-moved_db ;;
esac
exit 0
SHIM
chmod +x "$TMP/vbin/docker"
out="$( cd "$ROOT" && PATH="$TMP/vbin:$PATH" bash "$SCRIPT" 2>&1 )"
has()  { if grep -Fq -- "$2" <<< "$out"; then pass "$1"; else fail "$1: missing '$2' in: $out"; fi; }
hasnt(){ if grep -Fq -- "$2" <<< "$out"; then fail "$1: unexpected '$2' in: $out"; else pass "$1"; fi; }
has   "custom location: listed live by its working_dir" "LIVE (working_dir exists): $TMP/elsewhere/myproj-wt-custom"
hasnt "custom location: no compose command" "compose -p myproj-wt-custom"
hasnt "custom location: its volume is not removable" "volume rm myproj-wt-custom_db"
has   "no working_dir label: not judged" "NOT JUDGED compose project: myproj-wt-nolabel"
hasnt "no working_dir label: no compose command" "compose -p myproj-wt-nolabel"
hasnt "no working_dir label: its volume is not removable" "volume rm myproj-wt-nolabel_db"
has   "no working_dir label: its volume is still listed, not judged" "NOT JUDGED volume: myproj-wt-nolabel_db"
has   "shared pinned volume: down without -v" "  docker compose -p myproj-wt-shared down --rmi local --remove-orphans"
hasnt "shared pinned volume: no down -v" "compose -p myproj-wt-shared down -v"
[[ "$(grep -Fxc -- "  # no -v: shared volume ph_postgres_data is mounted by: myproj" <<< "$out")" -eq 1 ]] \
  && pass "shared pinned volume: named once, with its other project once" \
  || fail "shared pinned volume: want exactly one line naming myproj once: $out"
has   "an orphan proven gone gets down without -v" "  docker compose -p myproj-wt-gone2 down --rmi local --remove-orphans"
hasnt "a bind path is not a volume: no note names it" "/host/src"
has   "a gone project's own volume: listed with no command" "ORPHAN volume: myproj-wt-gone2_db  (verify by hand; no command printed: a moved worktree with a stopped stack looks identical, see worktree-conventions.md)"
hasnt "default mode never prints volume rm (a moved, stopped worktree looks gone)" "volume rm"
[[ "$(grep -Fxc -- "  # judged gone: $TMP/gone/myproj-wt-shared does not exist" <<< "$out")" -eq 1 ]] \
  && pass "the ORPHAN block shows its proof, once per working_dir" \
  || fail "want exactly one 'judged gone: $TMP/gone/myproj-wt-shared' line: $out"
hasnt "a volume mounted by another project's container: no volume rm" "volume rm myproj-wt-gone3_db"
has   "a volume mounted by another project's container: the mounter is named" "myproj-wt-gone3_db is mounted by: otherproj"
hasnt "a volume mounted by a container outside compose: no volume rm" "volume rm myproj-wt-gone4_db"
has   "moved worktree, container running: listed live" "LIVE (container running)"
hasnt "moved worktree, container running: no compose command" "compose -p myproj-wt-moved"
hasnt "moved worktree, container running: its volume is not removable" "volume rm myproj-wt-moved_db"
# nolabel, shared and gone2, and the nolabel and gone2/3/4 volumes; never the LIVE project or its volume.
has   "a not-judged project counts as a finding, a live one does not" "7 orphan(s) found"

echo "== no removal line without a container proving the worktree gone (BL-857 round 2) =="
# Layer: script-level, docker shim switched by MODE (no daemon). A volume whose project has
# no container (stack downed, or the listing failed) has no working_dir to judge, so it gets
# no `volume rm`; it is NOT JUDGED whether or not $TMP/elsewhere/myproj-wt-custom exists (that
# directory is NOT a liveness proof here). An orphan mounting a volume not named <project>_*
# (name:-pinned or external, e.g. ph_postgres_data) gets `down` without -v: a git worktree
# declares the main stack's pinned volume too, and nothing else may mount it right now.
HEX=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
mkdir -p "$TMP/rbin"
cat > "$TMP/rbin/docker" <<SHIM
#!/usr/bin/env bash
T=\$'\t'
case "\$MODE \$*" in
  *" info") ;;
  "nocontainers ps -a"*) ;;
  "psfail"*" ps -a"*) exit 1 ;;
  "partial ps -a"*) printf '%s\n' "myproj-wt-dead\${T}$TMP/gone/d\${T}myproj-wt-dead_db\${T}exited"; exit 1 ;;
  "partial volume ls"*) echo myproj-wt-dead_db ;;
  "partial images --format"*) echo myproj-wt-dead-web ;;
  "partial images -f dangling=true -q") echo d1 ;;
  "partial images -f dangling=true -f"*) echo d1 ;;
  "partial inspect"*) echo myproj-wt-dead ;;
  "partial network ls"*) echo myproj-wt-dead_default ;;
  "partial network inspect"*) echo 0 ;;
  "pinned ps -a"*) printf '%s\n' "myproj-wt-dead\${T}$TMP/gone/x\${T}ph_postgres_data" ;;
  "names ps -a"*) cat <<EOF
myproj-wt-anon\${T}$TMP/gone/a\${T}$HEX,myproj-wt-anon_db
myproj-wt-short\${T}$TMP/gone/s\${T}${HEX:1}
myproj-wt-upper\${T}$TMP/gone/u\${T}$(tr a-f A-F <<< "$HEX")
myproj-wt-dead\${T}$TMP/gone/d\${T}myproj-wt-dead-x_db
myproj-wt-long\${T}$TMP/gone/l\${T}${HEX}0
myproj-wt-pre\${T}$TMP/gone/p\${T}g$HEX
EOF
  ;;
  "states ps -a"*State*) cat <<EOF
myproj-wt-paused\${T}$TMP/gone/p\${T}\${T}paused
myproj-wt-restarting\${T}$TMP/gone/r\${T}\${T}restarting
myproj-wt-mixed\${T}$TMP/gone/m\${T}\${T}exited
myproj-wt-mixed\${T}$TMP/gone/m\${T}\${T}running
myproj-wt-exited\${T}$TMP/gone/e\${T}\${T}exited
myproj-wt-dead\${T}$TMP/gone/d\${T}\${T}dead
myproj-wt-created\${T}$TMP/gone/c\${T}\${T}created
myproj-wt-wrongcase\${T}$TMP/gone/w\${T}\${T}Running
myproj-wt-removing\${T}$TMP/gone/x\${T}\${T}removing
EOF
  ;;
  "bare ps -a"*) cat <<EOF
myproj-wt-bare\${T}$TMP/gone/b\${T}
myproj-wt-baz\${T}$TMP/gone/z\${T}myproj-wt-baz_cache
EOF
  ;;
  "bare volume ls"*) echo myproj-wt-baz_cache ;;
  "pinned volume ls"*) echo ph_postgres_data ;;
  "nocontainers volume ls"*|"psfail volume ls"*) echo myproj-wt-custom_db ;;
esac
exit 0
SHIM
chmod +x "$TMP/rbin/docker"
rsweep() { out="$( cd "$ROOT" && PATH="$TMP/rbin:$PATH" MODE="$1" bash "$SCRIPT" "${@:2}" 2>&1 )"; code=$?; }
# A stray environment variable of the same name must not count as proof.
gone_projects=myproj-wt-custom rsweep nocontainers
hasnt "no container: the volume gets no volume rm" "volume rm myproj-wt-custom_db"
has   "no container: the volume is listed NOT JUDGED" "NOT JUDGED volume: myproj-wt-custom_db"
has   "no container: a NOT JUDGED volume is a finding" "1 orphan(s) found"
has   "no container: the pointer to verify by hand" "#   git worktree list; docker volume inspect myproj-wt-custom_db"
rsweep psfail --check
hasnt "container listing failed: no volume rm" "volume rm"
has   "container listing failed: the sweep is reported incomplete" "sweep incomplete (degraded)"
rsweep psfailempty --check
hasnt "container listing failed, nothing listed: not a clean bill" "No orphaned"
[[ $code -eq 1 ]] && pass "container listing failed, nothing listed: --check exits 1" || fail "container listing failed, nothing listed: --check exit $code"
rsweep pinned
has   "pinned volume, nobody else mounts it: down without -v" "  docker compose -p myproj-wt-dead down --rmi local --remove-orphans"
hasnt "pinned volume, nobody else mounts it: no down -v" "compose -p myproj-wt-dead down -v"
has   "pinned volume, nobody else mounts it: the volume is named" "  # no -v: ph_postgres_data is not named myproj-wt-dead_*"
rsweep names
has   "an anonymous (64-hex) volume: down without -v" "  docker compose -p myproj-wt-anon down --rmi local --remove-orphans"
hasnt "an anonymous (64-hex) volume gets no note" "# no -v: $HEX is not"
has   "63 hex chars is a name, not an anonymous id" "# no -v: ${HEX:1} is not named myproj-wt-short_*"
has   "upper-case hex is a name, not an anonymous id" "# no -v: $(tr a-f A-F <<< "$HEX") is not named myproj-wt-upper_*"
has   "64 hex chars plus a trailing one is a name" "# no -v: ${HEX}0 is not named myproj-wt-long_*"
has   "64 hex chars after a leading letter is a name" "# no -v: g$HEX is not named myproj-wt-pre_*"
has   "a prefix sibling's volume (dead-x_db) is not dead's own" "# no -v: myproj-wt-dead-x_db is not named myproj-wt-dead_*"
echo "== default mode never prints down -v; a running container proves the project live (BL-857 round 3) =="
# Layer: script-level, same MODE shim. A bare `-p <proj> down -v` run from the workspace
# root loads its compose.yaml and removes a name:-pinned volume nobody mounts at that
# moment, so default mode never offers -v. Nor does it print `volume rm`: a worktree moved
# with a plain mv whose stack is stopped looks exactly like a removed one.
unjudged_projects=myproj-wt-baz rsweep bare    # a stray environment variable is no verdict
hasnt "no mounts: no down -v" "compose -p myproj-wt-bare down -v"
has   "no mounts: down without -v" "  docker compose -p myproj-wt-bare down --rmi local --remove-orphans"
hasnt "no mounts: no empty volume note" "# no -v:  "
hasnt "own volume only: no down -v" "compose -p myproj-wt-baz down -v"
has   "own volume only: down without -v" "  docker compose -p myproj-wt-baz down --rmi local --remove-orphans"
has   "own volume only: listed with no command" "ORPHAN volume: myproj-wt-baz_cache  (verify by hand; no command printed: a moved worktree with a stopped stack looks identical, see worktree-conventions.md)"
hasnt "own volume only: no volume rm" "volume rm"
rsweep states
for p in paused restarting mixed; do
  hasnt "state $p: no compose command" "compose -p myproj-wt-$p "
done
[[ "$(grep -Fxc "  LIVE (container running)" <<< "$out")" -eq 3 ]] \
  && pass "running, restarting and paused (any one container) read live" \
  || fail "want 3 LIVE (container running) lines: $out"
# Docker emits lowercase states only: a wrong-case one (Running) is malformed and is not
# read live; removing is a container on its way out. Both refused, like exited/dead/created.
for p in exited dead created wrongcase removing; do
  has "state $p: not live, gets down" "  docker compose -p myproj-wt-$p down --rmi local --remove-orphans"
done
has   "an ORPHAN block shows its proof" "  # judged gone: $TMP/gone/e does not exist"
rsweep states --slug mixed
has   "--slug: a running container is still residue" "  docker compose -p myproj-wt-mixed down --rmi local --remove-orphans"
hasnt "--slug: no down -v either" "down -v"
[[ $code -eq 1 ]] && pass "--slug: running residue exits 1" || fail "--slug: running residue exit $code"
rsweep bare --slug baz
has   "--slug: a volume keeps its removal line" "  docker volume rm myproj-wt-baz_cache   # confirm"

echo "== a container listing that failed partway: no removal line at all (BL-857 round 4) =="
# Layer: script-level, same MODE shim: `ps -a` prints one row, then exits 1. A running
# container missing from the partial listing would read gone, so nothing gets a command.
for args in "" "--slug dead"; do
  rsweep partial $args
  has   "partial listing ${args:-default}: the listing is kept" "compose project: myproj-wt-dead"
  has   "partial listing ${args:-default}: reported incomplete" "sweep incomplete (degraded): the container listing failed"
  hasnt "partial listing ${args:-default}: no compose command" "docker compose -p"
  hasnt "partial listing ${args:-default}: no rmi for a tagged image" "docker rmi myproj-wt-dead-web"
  hasnt "partial listing ${args:-default}: no rmi for a dangling layer" "docker rmi d1"
  hasnt "partial listing ${args:-default}: no network rm" "docker network rm"
  hasnt "partial listing ${args:-default}: no volume rm" "docker volume rm"
done

echo "== every printed rmi / network rm carries a one-line reason =="
# Layer: script-level, docker shim (no daemon). A suggestion with no stated basis asks the
# reader to trust the sweep; the comment line above the command says what it rests on.
mkdir -p "$TMP/wbin"
cat > "$TMP/wbin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
  "images -f dangling=true -q") echo d1 ;;
  "inspect -f"*d1) echo myproj-wt-gonea ;;
  "images -f dangling=true -f label="*) echo d1 ;;
  "image inspect"*) echo myproj-wt-gonec ;;
  "network ls"*) echo myproj-wt-goneb_default ;;
  "network inspect"*) echo 0 ;;
  images*) echo myproj-wt-gonec-web ;;
esac
exit 0
SHIM
chmod +x "$TMP/wbin/docker"
out="$( cd "$ROOT" && PATH="$TMP/wbin:$PATH" bash "$SCRIPT" 2>&1 )"
# grep -F splits a multi-line pattern into alternatives, so the line above the command is read.
above() { grep -Fx -B1 -- "$2" <<< "$out" | head -1 | grep -Fxq -- "$3" && pass "$1" || fail "$1: line above '$2' is not '$3' in: $out"; }
above "reason: tagged image" "  docker rmi myproj-wt-gonec-web" "  # no live worktree or running container for myproj-wt-gonec; the image rebuilds from its compose file"
above "reason: dangling layer" "  docker rmi d1" "  # no live worktree or running container for myproj-wt-gonea; the image rebuilds from its compose file"
above "reason: network" "  docker network rm myproj-wt-goneb_default" "  # no live worktree or running container for myproj-wt-goneb; the network has no endpoints"
hasnt "reason: still no volume rm" "volume rm"
hasnt "reason: still no down -v" "down -v"
# Under --slug the sweep cannot claim the containers are gone, so it names the scope instead.
out="$( cd "$ROOT" && PATH="$TMP/wbin:$PATH" bash "$SCRIPT" --slug gonec 2>&1 )"
above "reason under --slug: names the scope, not an empty project" "  docker rmi myproj-wt-gonec-web" "  # belongs to myproj-wt-gonec (--slug); the image rebuilds from its compose file"
hasnt "reason under --slug: no claim that containers are gone" "no live worktree or running container"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
