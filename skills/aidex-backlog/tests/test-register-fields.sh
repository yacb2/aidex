#!/usr/bin/env bash
# test-register-fields.sh — `surface:` and `verify:` round-trip through register-item.sh.
#
# `emit_backlog_entry` is positional, and the comment above it records a prior incident
# where --estimate/--status/--blocked-by passed their validation gates and were dropped
# in exactly this hand-off. Two more positional arguments is how it happens again, so
# this is a ROUND-TRIP: register with both fields at non-default values, read them back
# off disk, and assert estimate and blocked_by still survive alongside them.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REG="$SCRIPTS/register-item.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
fm()  { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog"; cd "$TMP/p"

echo "register-item.sh surface/verify:"
F="$(bash "$REG" --origin manual --title "gap lane renders" --surface behaviour \
      --verify "vitest on useGapLane plus the /editor E2E spec" --estimate S --blocked-by "seed video 4" 2>/dev/null)"
[[ -f "$F" ]] && ok "registered" || bad "no file: $F"
[[ "$(fm "$F" surface)" == "behaviour" ]] && ok "surface round-trips (behaviour)" || bad "surface: '$(fm "$F" surface)'"
[[ "$(fm "$F" verify)" == "vitest on useGapLane plus the /editor E2E spec" ]] && ok "verify round-trips" || bad "verify: '$(fm "$F" verify)'"
[[ "$(fm "$F" estimate)" == "S" ]] && ok "estimate still survives the positional hand-off" || bad "estimate: '$(fm "$F" estimate)'"
[[ "$(fm "$F" blocked_by)" == "seed video 4" ]] && ok "blocked_by still survives" || bad "blocked_by: '$(fm "$F" blocked_by)'"
grep -q '^## Verification' "$F" && grep -q '^| kind | what | proof |' "$F" && ok "body carries the ## Verification table skeleton" || bad "no Verification skeleton"
# the skeleton must sit between Acceptance and Notes, where sweep-eligible.py's section reader expects sections
awk '/^## Acceptance/{a=NR} /^## Verification/{v=NR} /^## Notes/{n=NR} END{exit !(a<v && v<n)}' "$F" && ok "section order Acceptance < Verification < Notes" || bad "section order"

D="$(bash "$REG" --origin manual --title "defaults" 2>/dev/null)"
[[ "$(fm "$D" surface)" == "internal" ]] && ok "surface defaults to internal" || bad "default surface: '$(fm "$D" surface)'"
[[ "$(fm "$D" verify)" == "" ]] && ok "verify defaults empty" || bad "default verify: '$(fm "$D" verify)'"
B="$(bash "$REG" --origin manual --title "us spelling" --surface behavior 2>/dev/null)"
[[ "$(fm "$B" surface)" == "behaviour" ]] && ok "behavior is normalised to behaviour" || bad "behavior: '$(fm "$B" surface)'"

if bash "$REG" --origin manual --title "bogus" --surface backend >/dev/null 2>"$TMP/err"; then bad "invalid surface accepted"
else [[ $? -eq 2 ]] && grep -q "invalid surface" "$TMP/err" && ok "invalid surface exits 2 and says so" || bad "invalid surface: wrong exit/message"; fi
# a refused registration must not have spent an id
[[ "$(ls .context/backlog/*-bl-*.md | wc -l | tr -d ' ')" == "3" ]] && ok "the refusal wrote no entry" || bad "refusal wrote an entry"

# the --escalate-to source stub goes through emit_backlog_stub — a second positional hand-off
mkdir -p "$TMP/q/.context/backlog"
S="$(bash "$REG" --origin manual --title "cross repo" --surface ui --verify "screenshot of /settings" --estimate XS \
      --escalate-to "$TMP/q" 2>/dev/null | head -1)"
[[ -f "$S" ]] && ok "escalate-to source stub written" || bad "no source stub: $S"
[[ "$(fm "$S" surface)" == "ui" && "$(fm "$S" verify)" == "screenshot of /settings" && "$(fm "$S" estimate)" == "XS" ]] \
  && ok "source stub keeps surface/verify/estimate through emit_backlog_stub" || bad "stub fields: $(fm "$S" surface) / $(fm "$S" verify) / $(fm "$S" estimate)"
T="$(ls "$TMP/q/.context/backlog/"*-bl-*.md | head -1)"
[[ "$(fm "$T" surface)" == "ui" && "$(fm "$T" verify)" == "screenshot of /settings" ]] \
  && ok "the cross-repo TARGET stub carries surface/verify too (the work happens there)" || bad "target stub: $(fm "$T" surface) / $(fm "$T" verify)"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — register fields: $PASS cells round-trip"; exit 0; }; echo "$FAIL failure(s)"; exit 1
