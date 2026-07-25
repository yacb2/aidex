#!/usr/bin/env bash
# test-profile-load.sh — config resolution, without Docker.
#
# Covers the three ways a project's config.env can meet a family profile:
#   1. no WT_PROFILE at all       -> unchanged behavior (every existing project)
#   2. WT_PROFILE="<name>"        -> defaults load FIRST, project values win
#   3. WT_PROFILE="<unknown>"     -> refuse, rather than run with silent gaps
# plus the placeholder guard, which is what a copied-but-unfilled profile hits.
#
# `list` is the probe: it resolves the whole config and touches no Docker
# resource, so a config error surfaces without creating anything.
#
# Run with: bash skills/aidex-worktree/scripts/test-profile-load.sh

set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$SELF/worktree.sh"
PROFILES="$SELF/../assets/profiles"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

WS="$TMP/proj"
mkdir -p "$WS/.context/worktrees" "$WS/svc"
: > "$WS/CLAUDE.md"          # project-root marker (no root .git)
CFG="$WS/.context/worktrees/config.env"

run() { ( cd "$WS" && bash "$WT" "$@" 2>&1 ); }

# --- 1. no WT_PROFILE: a fully self-contained config still works -------------
# This is every project configured before the split. It must not regress.
cat > "$CFG" <<'ENV'
WT_PARTICIPANTS="svc"
WT_LINKS="docker-compose.yml"
WT_SERVICES="db backend"
WT_PORT_VARS="DB_PORT=47100"
WT_PORT_STRIDE=10
WT_MAX_SLOTS=9
ENV
out="$(run list)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "no-profile config: list exited $rc — $out"

# --- 2. WT_PROFILE loads the family defaults, and the project overrides them --
[[ -f "$PROFILES/django-vue-compose.defaults.env" ]] \
  || fail "the django-vue-compose defaults profile is missing — case 2 proves nothing"
cat > "$CFG" <<'ENV'
WT_PROFILE="django-vue-compose"
WT_PARTICIPANTS="svc"
WT_DB_USER="proj_user"
WT_DB_NAME="proj"
WT_LINKS="docker-compose.yml"
WT_PORT_VARS="DB_PORT=47100 BACKEND_PORT=47101"
ENV
out="$(run list)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "profile config: list exited $rc — $out"

# The profile must actually be REACHED. WT_PORT_STRIDE is set only there, and
# the stride assertion refuses a port span it cannot clear — so pick a span the
# two candidate values disagree about: 50. Profile stride 10 -> REFUSE; the
# script's own fallback of 100 -> accept. `up` is the probe rather than `list`,
# because `list` returns before the assertion runs.
sed -i.bak 's|^WT_PORT_VARS=.*|WT_PORT_VARS="DB_PORT=47100 BACKEND_PORT=47150"|' "$CFG" && rm -f "$CFG.bak"
out="$(run up ghost)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "profile not loaded: a 50-port span must be refused by the profile's stride of 10, but it was accepted"
grep -q 'WT_PORT_STRIDE=10' <<<"$out" \
  || fail "the refusal did not come from the profile's stride — got: $out"

# A project value must beat the profile's: same span, stride declared locally.
cat >> "$CFG" <<'ENV'
WT_PORT_STRIDE=100
ENV
out="$(run up ghost)"; rc=$?
grep -q 'WT_PORT_STRIDE' <<<"$out" \
  && fail "project override of a profile value did not win — still refused: $out"
grep -q 'no worktree directory' <<<"$out" \
  || fail "expected to get past the port assertion to the missing-directory error — got: $out"

# --- 3. an unknown profile is refused, not silently ignored -----------------
cat > "$CFG" <<'ENV'
WT_PROFILE="no-such-family"
WT_PARTICIPANTS="svc"
ENV
out="$(run list)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "unknown WT_PROFILE: must refuse, exited 0"
grep -q 'no such profile' <<<"$out" || fail "unknown WT_PROFILE: unhelpful message — $out"

# --- 4. unfilled placeholders are refused ------------------------------------
# The copied-but-unfilled profile. Without this guard the readiness probe
# authenticates as a role named CHANGEME_user, times out after 60s and rolls the
# create back, saying nothing about why.
cp "$PROFILES/django-vue-compose.project.env" "$CFG"
out="$(run list)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "unfilled profile: must refuse, exited 0"
grep -q 'placeholders' <<<"$out" || fail "unfilled profile: message does not name the problem — $out"
grep -q 'WT_DB_USER' <<<"$out" || fail "unfilled profile: message must name the offending vars — $out"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — config resolution: no-profile unchanged, profile loads under project overrides, unknown profile and unfilled placeholders refused"
