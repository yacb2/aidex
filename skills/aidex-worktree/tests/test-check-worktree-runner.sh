#!/usr/bin/env bash
# test-check-worktree-runner.sh — the directly-invokable-harness check.
#
# Lives in tests/, not beside its script: run-all.sh treats every
# skills/aidex-worktree/scripts/test-*.sh as Docker-dependent and skips it
# without RUN_DOCKER_TESTS=1. This check needs no daemon (compose `config` is a
# client-side parse, and the fixtures below have no compose file at all), so it
# must run in the DEFAULT suite.
#
# Two fixture shapes carry the whole design, because each caught a real false
# negative while the check was being written against the field:
#   - case 2: the HELPER form `port('E2E_BACKEND_PORT', 8710)`, whose default
#     never sits next to a `||`. A ||-only rule reported the very project the
#     defect was reported from as clean.
#   - case 4: a harness that merely MENTIONS .env in an error string. Treating
#     that as "loads the slot environment" exempted a project that loads nothing.
#
# Run with: bash skills/aidex-worktree/tests/test-check-worktree-runner.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK="$DIR/../scripts/check-worktree-runner.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# A project fixture. `dev.sh` is in WT_LINKS and carries the declared dev ports
# as ${VAR:-<literal>} — that is where the check learns which numbers mean DEV,
# which is what lets it flag a literal in any syntax without mistaking a timeout
# for a port.
mk_project() {  # mk_project <name>
  local d="$TMP/$1"
  mkdir -p "$d/.context/worktrees" "$d/frontend/tests/e2e-setup"
  cat > "$d/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="frontend"
WT_LINKS="dev.sh"
WT_PORT_VARS="DB_PORT=6400 BACKEND_PORT=6401 FRONTEND_PORT=6404"
ENV
  cat > "$d/dev.sh" <<'SH'
#!/usr/bin/env bash
DB_PORT=${DB_PORT:-5700}
BACKEND_PORT=${BACKEND_PORT:-8700}
E2E_BACKEND_PORT=${E2E_BACKEND_PORT:-8710}
SH
  echo "$d"
}

# --- 1. the `||` fallback form -> FINDING ------------------------------------
p="$(mk_project fallback)"
cat > "$p/frontend/tests/e2e-setup/test-config.ts" <<'TS'
export const CONFIG = {
  BACKEND_URL: process.env.E2E_BACKEND_URL || 'http://localhost:8710',
}
TS
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "fallback: a dev-port fallback in a harness config must be a finding"
grep -q '8710' <<<"$out" || fail "fallback: must name the port, got: $out"

# --- 2. THE HELPER FORM -> FINDING ------------------------------------------
# `port(name, fallback)` reads process.env[name] dynamically, so the variable
# name never appears next to its default and no `||` is involved. This is the
# shape that actually ships, and the shape a ||-only rule misses.
p="$(mk_project helper)"
cat > "$p/frontend/tests/e2e-setup/test-config.ts" <<'TS'
const port = (name: string, fallback: number): number => {
  const parsed = Number(process.env[name])
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback
}
const BACKEND_PORT = port('E2E_BACKEND_PORT', 8710)
TS
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "helper: port(name, fallback) with a dev literal must be a finding"
grep -q '8710' <<<"$out" || fail "helper: must name the port, got: $out"

# --- 3. a number that is NOT a declared dev port -> CLEAN --------------------
# Restricting to the project's own declared ports is what keeps a timeout from
# being reported as a port. Without it, `timeout: 30000` is a finding.
p="$(mk_project timeout)"
cat > "$p/frontend/tests/e2e-setup/test-config.ts" <<'TS'
export const CONFIG = {
  timeout: 30000,
  expect: { timeout: 5000 },
}
TS
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "timeout: a non-port number must not be a finding, got: $out"

# --- 4. MENTIONING .env is not LOADING it -> still a FINDING ----------------
# work_hours' global-setup names the file in an error message. The first draft
# of the exemption matched any occurrence of `.env` and let it through.
p="$(mk_project mentions)"
cat > "$p/frontend/tests/e2e-setup/test-config.ts" <<'TS'
export const CONFIG = {
  BACKEND_URL: process.env.E2E_BACKEND_URL || 'http://localhost:8710',
}
TS
cat > "$p/frontend/tests/e2e-setup/global-setup.ts" <<'TS'
export default async function () {
  if (!process.env.DB_NAME) {
    throw new Error('Missing DB_NAME. Check backend/.env and re-run.')
  }
}
TS
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "mentions: naming .env in a message must NOT exempt, got: $out"

# --- 5. actually LOADING the slot .env -> CLEAN -----------------------------
# The fixed shape: read <root>/.env into process.env before the fallbacks. The
# literals below are unchanged and still correct in the main tree — Layer 1 is
# what makes them unreachable from a worktree.
p="$(mk_project loads)"
cat > "$p/frontend/tests/e2e-setup/test-config.ts" <<'TS'
import { existsSync, readFileSync } from 'node:fs'
const root = process.env.WORKSPACE_ROOT ?? `${process.cwd()}/..`
if (existsSync(`${root}/.env`)) {
  for (const line of readFileSync(`${root}/.env`, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/)
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2]
  }
}
export const CONFIG = {
  BACKEND_URL: process.env.E2E_BACKEND_URL || 'http://localhost:8710',
}
TS
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "loads: a harness that loads the slot .env must be CLEAN, got: $out"

# --- 6. the load may live in a SIBLING module -> CLEAN ----------------------
# Real harnesses put the load in one shared file and the fallbacks in another,
# which is why the exemption is evaluated per directory rather than per file.
p="$(mk_project sibling)"
cp "$TMP/loads/frontend/tests/e2e-setup/test-config.ts" "$p/frontend/tests/e2e-setup/global-setup.ts"
cat > "$p/frontend/tests/e2e-setup/test-config.ts" <<'TS'
export const CONFIG = {
  BACKEND_URL: process.env.E2E_BACKEND_URL || 'http://localhost:8710',
}
TS
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "sibling: a load in a sibling module must exempt the directory, got: $out"

# --- 7. a census that examined NOTHING is not a pass ------------------------
out="$(AIDEX_PROJECTS_DIR=/tmp/aidex-no-such-dir bash "$CHECK" --census 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "census: examining 0 projects must NOT report clean, got: $out"
grep -qi '0 projects' <<<"$out" || fail "census: must say it examined nothing, got: $out"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — runner check: || and helper forms found, non-port numbers ignored, mention-vs-load distinguished, sibling load exempts"
