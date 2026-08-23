#!/usr/bin/env bash
# test-check-worktree-ports.sh — the host-port check, against fixtures that
# encode its refutation.
#
# The rule this exercises was WRONG in its first form. "A linked script must not
# name a port literal" fires on 5 of 5 field projects and is wrong on 5 of them:
# every `test-e2e.sh` pins `DB_PORT=<dev>` at the top and sources the worktree
# `.env` sixty lines below, so the slot's value wins by design.
#
# So the exempting fixture (case 2) is not a nicety — it is the case that
# decides whether this check can ship at all. A version of these tests without
# it would pass while the check blocked every project in the field.
#
# Lives in tests/, not scripts/, ON PURPOSE. run-all.sh treats every
# `skills/aidex-worktree/scripts/test-*.sh` as Docker-dependent and skips it
# unless RUN_DOCKER_TESTS=1. This check is pure static analysis — it must run
# in the DEFAULT suite, and `skills/*/tests/test-*.sh` is already a discovery
# root. Putting it beside its script would have shipped it permanently skipped.
#
# Run with: bash skills/aidex-worktree/tests/test-check-worktree-ports.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK="$DIR/../scripts/check-worktree-ports.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# A project fixture: config.env naming the slot vars, plus whatever scripts the
# case needs. WT_LINKS is what makes a script reachable from a worktree, and
# therefore what makes it in scope.
mk_project() {  # mk_project <name> <links>
  local d="$TMP/$1"
  mkdir -p "$d/.context/worktrees"
  cat > "$d/.context/worktrees/config.env" <<ENV
WT_PARTICIPANTS="backend frontend"
WT_LINKS="$2"
WT_PORT_VARS="DB_PORT=6400 BACKEND_PORT=6401 FRONTEND_PORT=6404"
WT_PORT_STRIDE=10
ENV
  echo "$d"
}

# --- 1. a pinned assignment that nothing can override -> FINDING -------------
p="$(mk_project pinned dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_PORT=8700
FRONTEND_PORT=3700
free_port $FRONTEND_PORT
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "pinned: a literal assignment with no environment path must be a finding"
grep -q 'FRONTEND_PORT=3700' <<<"$out" || fail "pinned: must name the variable and the literal, got: $out"
grep -q 'pinned-assignment' <<<"$out" || fail "pinned: must classify the shape, got: $out"

# --- 2. THE REFUTATION: pinned, but the worktree .env is sourced -> CLEAN ----
# This is every project's test-e2e.sh. The assignment is identical to case 1;
# the sourcing line below it is the entire difference, and it is deliberate.
p="$(mk_project exempt test-e2e.sh)"
cat > "$p/test-e2e.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PORT=5700
BACKEND_PORT=8700
# In a worktree, the slot's ports live in a .env worktree.sh writes next to us.
if [ -f "$PROJECT_ROOT/.env" ]; then
    . "$PROJECT_ROOT/.env"
fi
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "exempt: a script that sources the worktree .env must be CLEAN, got: $out"

# --- 3. an inline literal at the call site -> FINDING ------------------------
# Strictly worse than case 1: there is no variable at all, so no environment can
# reach it. The first draft of this check missed this shape entirely and
# reported two field projects clean — one of them on its start path.
p="$(mk_project inline dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
ensure_frontend_port_free() {
    local vite_pid=$(lsof -ti :3911 2>/dev/null)
    kill -9 $(lsof -ti :3911) 2>/dev/null || true
}
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "inline: a bare literal in an lsof call site must be a finding"
grep -q 'inline-literal' <<<"$out" || fail "inline: must classify the shape, got: $out"
grep -q '3911' <<<"$out" || fail "inline: must name the port, got: $out"

# --- 4. a port literal in a COMMENT is not a call site -> CLEAN --------------
# work_hours/dev.sh:255 documents Metro's port in prose. It was this check's one
# false positive before comment lines were excluded.
p="$(mk_project comment dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
start_mobile() {
    # `expo start --port 3424` in package.json). A stale Metro from a previous run
    npx expo start --port "$MOBILE_PORT"
}
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "comment: a port literal in a comment must be CLEAN, got: $out"

# --- 5. the fixed shape -> CLEAN --------------------------------------------
# What Task 2.2 writes. Pins nothing the environment cannot beat, and the
# launcher carries the port explicitly so vite cannot fall back to its config.
p="$(mk_project fixed dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$PROJECT_ROOT/.env" ] && . "$PROJECT_ROOT/.env"
BACKEND_PORT=${BACKEND_PORT:-8700}
FRONTEND_PORT=${FRONTEND_PORT:-3700}
free_port $FRONTEND_PORT
pnpm dev --port "$FRONTEND_PORT" &
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "fixed: the shape Task 2.2 writes must be CLEAN, got: $out"

# --- 6. a script NOT in WT_LINKS is out of scope -> CLEAN -------------------
# Scope is what a worktree can reach. An unlinked script is dev-only, and
# flagging it would make the check unactionable noise.
p="$(mk_project unlinked docker-compose.yml)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
FRONTEND_PORT=3700
SH
: > "$p/docker-compose.yml"
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "unlinked: a script outside WT_LINKS is out of scope, got: $out"

# --- 7. a project's OWN kill helper, called with a literal -> FINDING --------
# `free_port 3424` in work_hours/dev.sh:279,306. The check's first two patterns
# (`lsof -ti :N`, `--port N`) matched neither, so it reported clean on a call
# site that does the same kill -9. Matching only the shapes one script happens
# to use is how a checker misses the defect it was written for.
p="$(mk_project helper dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
start_mobile() {
    free_port 3424
}
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "helper: a kill helper called with a literal must be a finding"
grep -q '3424' <<<"$out" || fail "helper: must name the port, got: $out"

# --- 8. THE EXEMPTION IS SCOPED TO ASSIGNMENTS -> still a FINDING ------------
# Sourcing the worktree .env sets VARIABLES. It cannot reach a literal that no
# variable stands in front of. When the exemption covered the whole file,
# work_hours/dev.sh went clean the moment Task 2.2 added its `.env` line, while
# `free_port 3424` sat two hundred lines below, unchanged and still lethal.
p="$(mk_project scoped dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$PROJECT_ROOT/.env" ] && . "$PROJECT_ROOT/.env"
FRONTEND_PORT=${FRONTEND_PORT:-3423}
free_port $FRONTEND_PORT
free_port 3424
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "scoped: sourcing .env must NOT exempt an inline literal"
grep -q '3424' <<<"$out" || fail "scoped: must name the un-overridable literal, got: $out"
# Exactly one finding: the literal on line 6. `free_port $FRONTEND_PORT` on
# line 5 is parameterized and must stay clean. Assert on the COUNT and the
# line, not on the text -- the remediation hint names FRONTEND_PORT too, so a
# grep for it matches the advice rather than a finding.
[[ "$(grep -c 'inline-literal' <<<"$out")" == "1" ]] \
  || fail "scoped: expected exactly 1 finding (the literal), got: $out"
grep -q 'dev.sh:6' <<<"$out" || fail "scoped: the finding must be line 6, got: $out"

# --- 9. the GUARDED ONE-LINER sourcing form is also an exemption -------------
# Code review, 2026-08-21: `sources_slot_env` was anchored to the start of a line
# and to three specific variable names, so
# `[ -f "$PROJECT_ROOT/.env" ] && . "$PROJECT_ROOT/.env"` -- the common shape --
# was NOT matched, and a script using it got two pinned-assignment findings even
# though the slot's values win. A false positive in a BLOCKING check.
#
# Fixture 5 already used this one-liner but was clean for an unrelated reason
# (it also used ${VAR:-...}), so it could not catch this. Here the assignments
# are BARE, so the exemption is the only thing that can make it clean.
p="$(mk_project oneliner test-e2e.sh)"
cat > "$p/test-e2e.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PORT=5700
BACKEND_PORT=8700
[ -f "$PROJECT_ROOT/.env" ] && . "$PROJECT_ROOT/.env"
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "oneliner: the guarded one-liner sourcing form must exempt, got: $out"

# ...including a root variable this check does not know by name.
p="$(mk_project othervar test-e2e.sh)"
cat > "$p/test-e2e.sh" <<'SH'
#!/usr/bin/env bash
DB_PORT=5700
BACKEND_PORT=8700
. "$(dirname "$0")/.env"
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "othervar: sourcing via \$(dirname \$0) must exempt, got: $out"

# --- 10. a census that examined NOTHING is not a pass -----------------------
# The glob was hardcoded to ~/Documents/projects, so on any other layout the loop
# body never ran, rc stayed 0, and the gate printed green having checked nothing.
out="$(AIDEX_PROJECTS_DIR=/tmp/aidex-no-such-dir bash "$CHECK" --census 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "census: examining 0 projects must NOT report clean, got: $out"
grep -qi '0 projects' <<<"$out" || fail "census: must say it examined nothing, got: $out"

# --- 11. a SINGLE project with nothing to examine is not a pass -------------
# The census learned this (case 10) and the single-project path did not:
# `scan_project` returns 0 both when every linked script is clean and when there
# was no config.env, or no WT_LINKS, to look at. The caller printed the same
# "host ports OK" either way, which is a positive isolation guarantee derived
# from having examined nothing.
p="$TMP/noconfig"; mkdir -p "$p"
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "noconfig: a project with no worktree config must NOT report clean, got: $out"
grep -qi 'nothing was checked' <<<"$out" || fail "noconfig: must say it examined nothing, got: $out"

p="$TMP/nolinks"; mkdir -p "$p/.context/worktrees"
printf 'WT_PARTICIPANTS="backend"\nWT_LINKS=""\n' > "$p/.context/worktrees/config.env"
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "nolinks: an empty WT_LINKS must NOT report clean, got: $out"
grep -qi 'nothing was checked' <<<"$out" || fail "nolinks: must say it examined nothing, got: $out"

# --- 12. BL-192: a port VARIABLE the slot never supplies -> FINDING ----------
# The gap this closes, and it is the checker's own success turned against it.
# Case 5 catches `free_port 3424` as an inline-literal. The field fix for that
# was to parameterize it -- `free_port "$FRONTEND_MOBILE_PORT"` with
# `FRONTEND_MOBILE_PORT=${FRONTEND_MOBILE_PORT:-3424}` above. That silences BOTH
# existing shapes: shape 1 skips the var because it is not in WT_PORT_VARS, and
# shape 2 needs a bare literal and now sees a variable. The kill still lands on
# the main tree's Metro, and the checker reports clean. Measured on
# work_hours_ws and room_booking_ws 2026-08-23: both clean, both defective.
p="$(mk_project unsupplied dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$PROJECT_ROOT/.env" ]; then . "$PROJECT_ROOT/.env"; fi
FRONTEND_PORT=${FRONTEND_PORT:-3700}
FRONTEND_MOBILE_PORT=${FRONTEND_MOBILE_PORT:-3701}
free_port "$FRONTEND_PORT"
free_port "$FRONTEND_MOBILE_PORT"
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "unsupplied: a port var absent from WT_PORT_VARS, defaulted to the main tree's literal and swept, must be a finding -- got: $out"
grep -q 'FRONTEND_MOBILE_PORT' <<<"$out" || fail "unsupplied: must name the variable, got: $out"
grep -q '3701' <<<"$out" || fail "unsupplied: must name the literal it resolves to, got: $out"
grep -q 'unsupplied-var' <<<"$out" || fail "unsupplied: must classify the shape, got: $out"
# FRONTEND_PORT is in WT_PORT_VARS and is swept the same way -- it must NOT be
# reported. Without this the rule would fire on every correctly-isolated port.
grep -q 'FRONTEND_PORT=' <<<"$out" && fail "unsupplied: reported a var the slot DOES supply, got: $out"

# --- 13. the same file, with provenance captured -> CLEAN -------------------
# The exempting case, and the one that decides whether the rule can ship. After
# `VAR=${VAR:-literal}` runs, the variable is set either way and nothing can
# tell a slot-supplied value from the default. Capturing `${VAR:+1}` ABOVE that
# line is what makes a guard possible, and it keeps working unchanged the day
# the var is added to the slot allocator.
p="$(mk_project guarded dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$PROJECT_ROOT/.env" ]; then . "$PROJECT_ROOT/.env"; fi
FRONTEND_PORT=${FRONTEND_PORT:-3700}
FRONTEND_MOBILE_PORT_FROM_SLOT=${FRONTEND_MOBILE_PORT:+1}
FRONTEND_MOBILE_PORT=${FRONTEND_MOBILE_PORT:-3701}
own_mobile_port() {
    [ ! -f "$PROJECT_ROOT/.env" ] || [ -n "${FRONTEND_MOBILE_PORT_FROM_SLOT:-}" ]
}
free_port "$FRONTEND_PORT"
if own_mobile_port; then free_port "$FRONTEND_MOBILE_PORT"; fi
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "guarded: a script that captures provenance before defaulting must be clean, got: $out"


# --- 13b. provenance captured BELOW the default -> still a FINDING -----------
# The exemption's own comment says the capture is only meaningful ABOVE
# `VAR=${VAR:-lit}`: after that line the variable is set either way and
# `${VAR:+1}` is always-true — a guard built on it never skips the sweep. The
# first implementation was a whole-file grep with no position check, so the
# broken ordering (one wrong fix away from case 13) went clean. Weekend review
# 2026-08-23, finding 3.
p="$(mk_project misordered dev.sh)"
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$PROJECT_ROOT/.env" ]; then . "$PROJECT_ROOT/.env"; fi
FRONTEND_PORT=${FRONTEND_PORT:-3700}
FRONTEND_MOBILE_PORT=${FRONTEND_MOBILE_PORT:-3701}
FRONTEND_MOBILE_PORT_FROM_SLOT=${FRONTEND_MOBILE_PORT:+1}
free_port "$FRONTEND_PORT"
if [ -n "$FRONTEND_MOBILE_PORT_FROM_SLOT" ]; then free_port "$FRONTEND_MOBILE_PORT"; fi
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "misordered: a provenance capture BELOW the default is always-true and must NOT exempt -- got: $out"
grep -q 'FRONTEND_MOBILE_PORT' <<<"$out" || fail "misordered: must name the variable, got: $out"
grep -q 'unsupplied-var' <<<"$out" || fail "misordered: must classify the shape, got: $out"

# --- 14. the guard idiom must be `set -e` safe (BL-192) ---------------------
# Both field dev.sh files run under `set -e`, and the obvious spelling of the
# guard is NOT safe there. `own_mobile_port && free_port ...` as a FUNCTION's
# last statement makes the function return 1; the bare call in stop_all then
# trips set -e and the shutdown aborts half-done. Measured, not reasoned: the
# AND-form never printed "ALL-STOPPED" and exited 1. An `if` condition is exempt
# from set -e, which is why the fixture above and both projects use it.
#
# This RUNS the idiom rather than grepping for it: a static check would have
# been satisfied by the broken spelling.
: > "$TMP/.env"    # a worktree: the guard is FALSE, so the sweep must be skipped
and_form="$(bash -c 'set -e
R="$1"; FROM_SLOT=
own_mobile_port() { [ ! -f "$R/.env" ] || [ -n "$FROM_SLOT" ]; }
free_port() { echo SWEPT; }
kill_mobile() { own_mobile_port && free_port 3901; }
stop_all() { kill_mobile; echo ALL-STOPPED; }
stop_all' _ "$TMP" 2>&1)"
[[ "$and_form" != *ALL-STOPPED* ]] || fail "set-e: the AND-form no longer aborts shutdown — this test's premise is stale, re-derive before trusting the if-form fixture"

if_form="$(bash -c 'set -e
R="$1"; FROM_SLOT=
own_mobile_port() { [ ! -f "$R/.env" ] || [ -n "$FROM_SLOT" ]; }
free_port() { echo SWEPT; }
kill_mobile() { if own_mobile_port; then free_port 3901; fi; }
stop_all() { kill_mobile; echo ALL-STOPPED; }
stop_all' _ "$TMP" 2>&1)"
[[ "$if_form" == *ALL-STOPPED* ]] || fail "set-e: the if-form must let shutdown finish, got: $if_form"
[[ "$if_form" != *SWEPT* ]] || fail "set-e: a worktree must not sweep the main tree's port, got: $if_form"
rm -f "$TMP/.env"


if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — host-port check: pinned + inline literals found, sourced-.env and comments exempt, fixed shape clean"
