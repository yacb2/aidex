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

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — host-port check: pinned + inline literals found, sourced-.env and comments exempt, fixed shape clean"
