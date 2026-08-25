#!/usr/bin/env bash
# test-register-plan-origin.sh — BL-220: aidex-plan-exec defers emergent work mid-run,
# and the deferred item has to say which plan it came from. The acceptance is one
# property: registering with `--origin plan` produces an item whose `origin_ref`
# RESOLVES to that plan.
#
# "Resolves" is the whole point, so every cell checks the marker the way validate.py
# reads it (`<type>/<filename>`, D-03) — not merely that the field is non-empty. A
# stored filesystem path looks correct in the file and breaks the moment the item is
# read from anywhere but the directory it was registered from; that is the mutation
# these cells exist to catch.
#
# Isolated temp project. No network, no real .context/ touched.

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REG="${REG_OVERRIDE:-$SCRIPTS/register-item.sh}"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fresh() {                      # fresh <name> -> a clean project dir, echoed
  local d="$TMP/$1"
  rm -rf "$d"; mkdir -p "$d/.context/backlog" "$d/.context/plans/_archive"
  printf '%s' "$d"
}
fm() {                         # fm <file> <key> -> front-matter value
  awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$1"
}
# resolves <project> <ref> — the marker check validate.py performs: split on the first
# `/`, map the prefix to its folder, accept the bare slug, the .md filename, or a
# modular folder, in the active tree or in _archive.
resolves() {
  local root="$1" ref="$2" prefix rest base
  [[ "$ref" == */* ]] || return 1
  prefix="${ref%%/*}"; rest="${ref#*/}"
  [[ "$prefix" == "plan" ]] || return 1
  base="$root/.context/plans"
  for cand in "$rest" "$rest.md"; do
    [[ -e "$base/$cand" || -e "$base/_archive/$cand" ]] && return 0
  done
  return 1
}

echo "register-item.sh --origin plan cells:"

# ── P1 · a modular plan folder ───────────────────────────────────────────────
D="$(fresh p1)"; cd "$D"
mkdir -p .context/plans/2026-08-22-suite-speed-rollout
printf -- '---\ntitle: "p"\nstatus: doing\n---\n' > .context/plans/2026-08-22-suite-speed-rollout/00-index.md
A="$(bash "$REG" --origin plan --plan 2026-08-22-suite-speed-rollout \
      --title "Deferred from a modular plan" --priority P3 --type improvement 2>/dev/null)"
if [[ -f "$A" ]]; then
  R="$(fm "$A" origin_ref)"
  [[ "$(fm "$A" origin)" == "plan" ]] && ok "P1 origin is plan" || bad "P1 origin: $(fm "$A" origin)"
  resolves "$D" "$R" && ok "P1 origin_ref resolves to the modular plan ($R)" \
                     || bad "P1 origin_ref does not resolve: '$R'"
else
  bad "P1 no entry written"
fi

# ── P2 · a single-file plan, passed as a path ────────────────────────────────
# The convenience of passing a path must not leak a path INTO the front matter.
D="$(fresh p2)"; cd "$D"
printf -- '---\ntitle: "p"\nstatus: doing\n---\n' > .context/plans/2026-08-24-scoped-change.md
A="$(bash "$REG" --origin plan --plan .context/plans/2026-08-24-scoped-change.md \
      --title "Deferred from a single-file plan" 2>/dev/null)"
if [[ -f "$A" ]]; then
  R="$(fm "$A" origin_ref)"
  resolves "$D" "$R" && ok "P2 origin_ref resolves from a path argument ($R)" \
                     || bad "P2 origin_ref does not resolve: '$R'"
  [[ "$R" != *".context/"* ]] && ok "P2 marker carries no filesystem path" \
                             || bad "P2 marker stored a path: '$R'"
else
  bad "P2 no entry written"
fi

# ── P3 · an archived plan still resolves ─────────────────────────────────────
# Deferrals outlive the run that made them; the plan is archived on close (D-10)
# precisely so inbound refs keep resolving.
D="$(fresh p3)"; cd "$D"
printf -- '---\ntitle: "p"\nstatus: done\n---\n' > .context/plans/_archive/2026-07-01-old-plan.md
A="$(bash "$REG" --origin plan --plan 2026-07-01-old-plan --title "From an archived plan" 2>/dev/null)"
if [[ -f "$A" ]]; then
  R="$(fm "$A" origin_ref)"
  resolves "$D" "$R" && ok "P3 origin_ref resolves into _archive ($R)" \
                     || bad "P3 origin_ref does not resolve: '$R'"
else
  bad "P3 no entry written"
fi

# ── P4 · --plan is required, and a bad plan warns without silently dropping ──
D="$(fresh p4)"; cd "$D"
bash "$REG" --origin plan --title "No plan named" >/dev/null 2>&1
[[ $? -ne 0 ]] && ok "P4 --origin plan without --plan exits non-zero" \
               || bad "P4 --origin plan without --plan exited 0"

ERR="$TMP/p4.err"
A="$(bash "$REG" --origin plan --plan 2026-01-01-does-not-exist --title "Dangling" 2>"$ERR")"
if [[ -f "$A" ]]; then
  ok "P4 an unresolvable plan still registers the item (never lose the deferral)"
  grep -qi "resolves to no plan" "$ERR" && ok "P4 and warns about it" \
                                        || bad "P4 registered silently, no warning"
  [[ "$(fm "$A" origin_ref)" == "plan/2026-01-01-does-not-exist" ]] \
    && ok "P4 marker is still a marker" || bad "P4 marker: $(fm "$A" origin_ref)"
else
  bad "P4 an unresolvable plan lost the item"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
