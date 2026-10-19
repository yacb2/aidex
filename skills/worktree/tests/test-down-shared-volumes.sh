#!/usr/bin/env bash
# test-down-shared-volumes.sh — BL-862: a worktree teardown must never delete a
# volume another project owns or mounts.
#
# `docker compose down -v` removes every NON-external volume the compose file
# declares, by its resolved name, whoever created it (docker/compose
# pkg/compose/down.go ensureVolumesDown -> removeVolume, Force: true). The engine
# refuses only while a container still references the volume (moby
# daemon/volume/service/store.go Remove: hasRef), and that reference is released
# when the container is REMOVED, not stopped (daemon/delete.go -> mounts.go
# removeMountPoints). So a `name:`-pinned volume of the main stack, after a plain
# `compose down` of the main tree, was deleted by `worktree.sh down` and by the
# rollback of a failed `new`: the main database, gone.
#
# Layer: script integration with a docker stub. The observable is the argument
# list `compose down` receives and the line that names a kept volume; neither is
# visible below the script.
#
# Run with: bash skills/worktree/tests/test-down-shared-volumes.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bl862.XXXXXX")" || { echo 'FAIL: mktemp'; exit 1; }
TMP="$(cd "$TMP" && pwd -P)" || exit 1
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/bin" "$TMP/slots" "$TMP/p/.context/worktrees" "$TMP/p/backend"

# The stub reads one scenario directory ($SCN): config.json is what
# `compose config --format json` prints (absent = the call fails), `volumes` what
# `volume ls -q` lists, label-<vol> the volume's compose project label, ps-<vol>
# the containers `ps -a --filter volume=<vol>` finds ("<name> <project label>"),
# and up-fails makes `compose up` fail so `new` rolls back; ls-fails, ps-fails and
# config-hangs make that one call fail or hang. `config` prints config.json with
# @S@ replaced by $WT_SUFFIX; rendered as the MAIN project (`-p p`) it also scopes
# every `p-wt-<slug>_` prefix to `p_`, the way compose names an unpinned volume,
# so a literal `name:` stays the same in both renders (config-main-fails makes
# only that render fail). Every `compose down` is logged with its arguments, and the
# directory of every `config` and `down` is logged: the judgement must read the
# same compose file the teardown then runs from.
cat > "$TMP/bin/docker" <<'STUB'
#!/bin/sh
case " $* " in
  *" --services "*) echo db; exit 0 ;;
  *" config --format json "*) echo "$PWD" >> "$SCN/config.pwd"
    [ -f "$SCN/config-hangs" ] && exec /bin/sleep 20
    [ -f "$SCN/config.json" ] || exit 1
    case " $* " in *" -p p "*) [ -f "$SCN/config-main-fails" ] && exit 1
      sed -e 's/p-wt-[^_"]*_/p_/g' -e "s/@S@/$WT_SUFFIX/g" "$SCN/config.json"; exit 0 ;; esac
    sed "s/@S@/$WT_SUFFIX/g" "$SCN/config.json"; exit 0 ;;
  *" volume ls "*) [ -f "$SCN/ls-fails" ] && exit 1; cat "$SCN/volumes" 2>/dev/null; exit 0 ;;
  *" volume inspect "*) for a; do v="$a"; done; cat "$SCN/label-$v"; exit $? ;;
  *" --filter volume="*) [ -f "$SCN/ps-fails" ] && exit 1; for a; do case "$a" in volume=*) v="${a#volume=}" ;; esac; done
    cat "$SCN/ps-$v" 2>/dev/null; exit 0 ;;
  *" ps -a "*) echo "$COMPOSE_PROJECT_NAME-db-1"; exit 0 ;;
  *" up -d "*) [ -f "$SCN/up-fails" ] && exit 1; exit 0 ;;
  *" compose "*" down "*) echo "down $*" >> "$SCN/down.log"; echo "$PWD" >> "$SCN/down.pwd"; exit 0 ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/docker"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sleep"; chmod +x "$TMP/bin/sleep"

cat > "$TMP/p/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_SERVICES="db"
WT_PORT_VARS="DB_PORT=6400"
ENV
printf 'services:\n  db:\n    image: postgres\n' > "$TMP/p/docker-compose.yml"
( cd "$TMP/p/backend" && /usr/bin/git init -q -b main . && /usr/bin/git config user.email t@e.com \
  && /usr/bin/git config user.name t && echo x > f && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1

run() {  # run <scenario dir> <worktree.sh args...>
  local scn="$1"; shift
  ( cd "$TMP/p" && SCN="$scn" TMPDIR="$TMP/slots" PATH="$TMP/bin:$PATH" bash "$WT" "$@" 2>&1 )
}
# scenario <slug>: a fresh scenario dir for worktree p-wt-<slug>, printed.
scenario() { mkdir -p "$TMP/scn/$1"; printf '%s' "$TMP/scn/$1"; }
vol() {  # vol <scn> <name> <label> [ps line]: an existing volume, its label, who mounts it
  printf '%s\n' "$2" >> "$1/volumes"; printf '%s\n' "$3" > "$1/label-$2"
  [[ -z "${4:-}" ]] || printf '%s\n' "$4" >> "$1/ps-$2"
}
used_v() { grep -q -- ' down -v ' "$1/down.log" 2>/dev/null; }
same_dir() {  # same_dir <scn> <dir> <label>: config and down both ran in <dir>, last time
  [[ "$(tail -1 "$1/config.pwd" 2>/dev/null)" == "$2" && "$(tail -1 "$1/down.pwd" 2>/dev/null)" == "$2" ]] \
    || fail "$3: compose config and compose down must both run in $2; config ran in '$(tail -1 "$1/config.pwd" 2>/dev/null)', down in '$(tail -1 "$1/down.pwd" 2>/dev/null)'"
}

# check_down <slug> <want: v|keep> <expected output fragment or ""> <why> [flag]
# Creates worktree <slug> with the scenario already in place, arms [flag] (a
# failure that must not hit `new`), tears it down, and asserts whether
# `compose down` ran with -v and what it said.
check_down() {
  local slug="$1" want="$2" frag="$3" why="$4" scn="$TMP/scn/$1" out
  out="$(run "$scn" new "$slug" --branch "wt/$slug")" || { fail "$slug fixture: new failed: $out"; return; }
  [[ -z "${5:-}" ]] || : > "$scn/$5"
  : > "$scn/down.log"
  out="$(run "$scn" down "$slug" --force)"
  [[ -s "$scn/down.log" ]] || { fail "$slug: compose down never ran: $out"; return; }
  if [[ "$want" == v ]]; then
    used_v "$scn" || fail "$slug ($why): compose down must keep -v; docker saw: $(cat "$scn/down.log"); output: $out"
  else
    used_v "$scn" && fail "$slug ($why): compose down ran with -v; docker saw: $(cat "$scn/down.log"); output: $out"
  fi
  [[ -z "$frag" ]] || grep -qF -- "$frag" <<<"$out" || fail "$slug ($why): output must say '$frag'; got: $out"
  same_dir "$scn" "$TMP/p-wt-$slug" "$slug ($why)"
}

# --- down: the table --------------------------------------------------------
# r1, the reported loss: the main stack's name:-pinned volume, its containers
# already removed, so nothing but the label says whose it is.
s="$(scenario r1)"; printf '{"volumes":{"pg":{"name":"p_pgdata"}}}' > "$s/config.json"
vol "$s" p_pgdata p
check_down r1 keep "keeping volume p_pgdata: created by project 'p'" "main's pinned volume, no container left"

# r2: the worktree's own volume, mounted by a STOPPED container of the main project.
s="$(scenario r2)"; printf '{"volumes":{"pg":{"name":"p-wt-r2_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r2_pg p-wt-r2 "p-db-1 p"
check_down r2 keep "keeping volume p-wt-r2_pg: mounted by" "own volume mounted by another project's container"

# r3, the passing boundary: own label, mounted only by its own container.
s="$(scenario r3)"; printf '{"volumes":{"pg":{"name":"p-wt-r3_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r3_pg p-wt-r3 "p-wt-r3-db-1 p-wt-r3"
check_down r3 v "" "own volume, own container only"

# r4: external is never compose's to remove, whoever made it -- it never blocks -v.
s="$(scenario r4)"; printf '{"volumes":{"ext":{"name":"p_ext","external":true},"pg":{"name":"p-wt-r4_pg"}}}' > "$s/config.json"
vol "$s" p_ext p "p-db-1 p"; vol "$s" p-wt-r4_pg p-wt-r4
check_down r4 v "" "external volume ignored"

# r5: a declared volume that does not exist has nothing to lose.
s="$(scenario r5)"; printf '{"volumes":{"pg":{"name":"p-wt-r5_pg"}}}' > "$s/config.json"
check_down r5 v "" "declared volume absent"

# r6: no volumes section at all.
s="$(scenario r6)"; printf '{"services":{"db":{}}}' > "$s/config.json"
check_down r6 v "" "no volumes declared"

# r7: compose config fails -- nothing can be judged, so nothing is removed.
s="$(scenario r7)"
check_down r7 keep "could not judge" "compose config failed"

# r8: malformed config output -- same.
s="$(scenario r8)"; printf '{"volumes":' > "$s/config.json"
check_down r8 keep "could not judge" "malformed compose config"

# r9: empty label -- a `docker volume create` volume no compose project owns.
s="$(scenario r9)"; printf '{"volumes":{"pg":{"name":"shared_pg"}}}' > "$s/config.json"
vol "$s" shared_pg ""
check_down r9 keep "keeping volume shared_pg: created by no compose project" "unlabelled volume"

# r10: a label next to the boundary -- a prefix of another slug's project is not this one.
s="$(scenario r10)"; printf '{"volumes":{"pg":{"name":"p-wt-r10_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r10_pg p-wt-r10x
check_down r10 keep "keeping volume p-wt-r10_pg: created by project 'p-wt-r10x'" "label is a near-miss of the project"

# r11: wrong case -- compose project names are lower-case; an exact compare only.
s="$(scenario r11)"; printf '{"volumes":{"pg":{"name":"p-wt-r11_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r11_pg P-WT-R11
check_down r11 keep "keeping volume p-wt-r11_pg" "label differs only in case"

# r12: own volume, mounted by a plain `docker run` container (no compose label).
s="$(scenario r12)"; printf '{"volumes":{"pg":{"name":"p-wt-r12_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r12_pg p-wt-r12 "adhoc "
check_down r12 keep "keeping volume p-wt-r12_pg: mounted by" "mounted by a container with no compose project"

# r20: the reverse of r1 -- the worktree came up first and created the main's
# pinned volume, so the label names the worktree; the main tree then mounted it
# (compose only warns) and was brought down. A `name:` that resolves the same
# under the main project is the main's volume whoever created it.
s="$(scenario r20)"; printf '{"volumes":{"pg":{"name":"p_pgdata"}}}' > "$s/config.json"
vol "$s" p_pgdata p-wt-r20
check_down r20 keep "keeping volume p_pgdata: same name under the main project 'p'" "pinned name the worktree created"

# r22, the passing boundary: a pinned name that varies with the suffix differs
# between the renders, so an own volume of that kind still goes with -v.
s="$(scenario r22)"; printf '{"volumes":{"pg":{"name":"p_pgdata@S@"}}}' > "$s/config.json"
vol "$s" p_pgdata-r22 p-wt-r22; vol "$s" p_pgdata p
check_down r22 v "" "suffixed pinned name differs from the main's"

# r23: the main render failing leaves nothing judged.
s="$(scenario r23)"; printf '{"volumes":{"pg":{"name":"p-wt-r23_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r23_pg p-wt-r23
check_down r23 keep "could not judge" "main project render failed" config-main-fails

# r16-r18: any docker call of the judgement failing keeps every volume.
s="$(scenario r16)"; printf '{"volumes":{"pg":{"name":"p-wt-r16_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r16_pg p-wt-r16
check_down r16 keep "could not judge" "volume ls failed" ls-fails
s="$(scenario r17)"; printf '{"volumes":{"pg":{"name":"p-wt-r17_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r17_pg p-wt-r17; rm -f "$s/label-p-wt-r17_pg"   # listed, but inspect fails
check_down r17 keep "could not judge" "volume inspect failed"
s="$(scenario r18)"; printf '{"volumes":{"pg":{"name":"p-wt-r18_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r18_pg p-wt-r18
check_down r18 keep "could not judge" "ps -a failed" ps-fails

# r19: a wedged daemon answering the judgement never holds the teardown past
# AIDEX_DOCKER_TIMEOUT (the stub hangs 20 s on `config`).
s="$(scenario r19)"; printf '{"volumes":{"pg":{"name":"p-wt-r19_pg"}}}' > "$s/config.json"
out="$(run "$s" new r19 --branch wt/r19)" || fail "r19 fixture: new failed: $out"
: > "$s/config-hangs"; : > "$s/down.log"
t0=$SECONDS
out="$( cd "$TMP/p" && SCN="$s" AIDEX_DOCKER_TIMEOUT=1 TMPDIR="$TMP/slots" PATH="$TMP/bin:$PATH" bash "$WT" down r19 --force 2>&1 )"
(( SECONDS - t0 < 15 )) || fail "r19: a hung compose config held down for $((SECONDS - t0)) s past AIDEX_DOCKER_TIMEOUT=1"
used_v "$s" && fail "r19: a hung judgement must keep every volume; docker saw: $(cat "$s/down.log")"
grep -qF "could not judge" <<<"$out" || fail "r19: output must say 'could not judge'; got: $out"

# r13: the failed-teardown recovery path -- $DEST already gone, compose runs from
# the MAIN tree's file, the one that declares the pinned volume.
s="$(scenario r13)"; printf '{"volumes":{"pg":{"name":"p_pgdata"}}}' > "$s/config.json"
vol "$s" p_pgdata p
out="$(run "$s" new r13 --branch wt/r13)" || fail "r13 fixture: new failed: $out"
/usr/bin/git -C "$TMP/p/backend" worktree remove --force "$TMP/p-wt-r13/backend" >/dev/null 2>&1
rm -rf "$TMP/p-wt-r13"
: > "$s/down.log"
out="$(run "$s" down r13 --force)"
[[ -s "$s/down.log" ]] || fail "r13 fixture: compose down never ran on the recovery path: $out"
used_v "$s" && fail "r13 (recovery path, \$DEST gone): compose down ran with -v; docker saw: $(cat "$s/down.log")"
grep -qF "keeping volume p_pgdata" <<<"$out" || fail "r13: output must name the kept volume; got: $out"
same_dir "$s" "$TMP/p" "r13 (recovery path)"

# --- rollback of a failed `new` ---------------------------------------------
# r14: the same pinned main volume, torn down by rollback instead of `down`.
s="$(scenario r14)"; printf '{"volumes":{"pg":{"name":"p_pgdata"}}}' > "$s/config.json"
vol "$s" p_pgdata p; : > "$s/up-fails"; : > "$s/down.log"
out="$(run "$s" new r14 --branch wt/r14)"
grep -q 'rolling back' <<<"$out" || fail "r14 fixture: a failing compose up did not roll back: $out"
[[ -s "$s/down.log" ]] || fail "r14 fixture: rollback never ran compose down: $out"
used_v "$s" && fail "r14 (rollback): compose down ran with -v over main's pinned volume; docker saw: $(cat "$s/down.log")"
grep -qF "keeping volume p_pgdata: created by project 'p'" <<<"$out" \
  || fail "r14 (rollback): output must name the kept volume; got: $out"
same_dir "$s" "$TMP/p-wt-r14" "r14 (rollback)"

# r15: rollback still reclaims a stack that is wholly its own.
s="$(scenario r15)"; printf '{"volumes":{"pg":{"name":"p-wt-r15_pg"}}}' > "$s/config.json"
vol "$s" p-wt-r15_pg p-wt-r15; : > "$s/up-fails"; : > "$s/down.log"
out="$(run "$s" new r15 --branch wt/r15)"
grep -q 'rolling back' <<<"$out" || fail "r15 fixture: a failing compose up did not roll back: $out"
used_v "$s" || fail "r15 (rollback, own volume): compose down must keep -v; docker saw: $(cat "$s/down.log"); output: $out"

# r21: r20 on the rollback path -- the pinned name labelled as the worktree's own.
s="$(scenario r21)"; printf '{"volumes":{"pg":{"name":"p_pgdata"}}}' > "$s/config.json"
vol "$s" p_pgdata p-wt-r21; : > "$s/up-fails"; : > "$s/down.log"
out="$(run "$s" new r21 --branch wt/r21)"
grep -q 'rolling back' <<<"$out" || fail "r21 fixture: a failing compose up did not roll back: $out"
[[ -s "$s/down.log" ]] || fail "r21 fixture: rollback never ran compose down: $out"
used_v "$s" && fail "r21 (rollback, pinned name the worktree created): compose down ran with -v; docker saw: $(cat "$s/down.log")"
grep -qF "keeping volume p_pgdata: same name under the main project 'p'" <<<"$out" \
  || fail "r21 (rollback): output must name the kept volume; got: $out"
same_dir "$s" "$TMP/p-wt-r21" "r21 (rollback)"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — teardown keeps shared volumes: down and rollback drop -v (and say why) when a declared volume was created by, is mounted by, or keeps its name under another project, or when nothing can be judged; an own, external, absent or undeclared volume keeps -v"
