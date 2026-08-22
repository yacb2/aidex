#!/usr/bin/env bash
# test-check-worktree-isolation.sh — the umbrella's own honesty.
#
# The umbrella adds no checking logic, so it has no findings of its own to test.
# What it CAN get wrong is its verdict line, and both ways it can are here.
#
# Lives in tests/, not scripts/: run-all.sh treats every
# skills/aidex-worktree/scripts/test-*.sh as Docker-dependent. Every fixture
# below is deliberately compose-less, so nothing here needs a daemon and the
# umbrella's own sequencing runs in the DEFAULT suite.
#
# Run with: bash skills/aidex-worktree/tests/test-check-worktree-isolation.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK="$DIR/../scripts/check-worktree-isolation.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. a project with no worktree config is not "every surface holds" ------
# Each sub-check returns 0 when it has nothing to examine, so the umbrella
# aggregated three vacuous zeros into a full green verdict for a project that
# has no worktree setup at all. The census path already refused this; the
# single-project path did not.
p="$TMP/bare"; mkdir -p "$p/.git"
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "bare: a project with no worktree config must NOT report every surface holding, got: $out"
grep -qi 'nothing was checked' <<<"$out" || fail "bare: must say it examined nothing, got: $out"

# --- 2. do not claim compose was verified when it never ran -----------------
# The compose check is gated on the literal filename `docker-compose.yml`, but
# the success line named compose unconditionally. A project using `compose.yaml`
# — or none at all — was told its compose addressing holds when that surface was
# never looked at.
p="$TMP/nocompose"; mkdir -p "$p/.context/worktrees" "$p/backend"
cat > "$p/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS="dev.sh"
WT_PORT_VARS="BACKEND_PORT=8401"
ENV
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
BACKEND_PORT=${BACKEND_PORT:-8400}
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "nocompose: the other surfaces are clean, so this must pass, got: $out"
grep -qi 'compose' <<<"$out" && ! grep -qi 'no compose file' <<<"$out" \
  && fail "nocompose: must not claim compose holds when no compose file was found, got: $out"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — umbrella: a project with nothing to examine is refused, and compose is only claimed when it ran"
