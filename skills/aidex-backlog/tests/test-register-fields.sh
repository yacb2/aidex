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

OPS="$(bash "$REG" --origin manual --title "ops surface" --surface ops 2>/dev/null)"
[[ "$(fm "$OPS" surface)" == "ops" ]] && ok "ops is a valid surface (no test surface: config, infra, canon, other-repo state)" || bad "ops: '$(fm "$OPS" surface)'"
if bash "$REG" --origin manual --title "bogus" --surface backend >/dev/null 2>"$TMP/err"; then bad "invalid surface accepted"
else [[ $? -eq 2 ]] && grep -q "invalid surface" "$TMP/err" && ok "invalid surface exits 2 and says so" || bad "invalid surface: wrong exit/message"; fi
# a refused registration must not have spent an id
[[ "$(ls .context/backlog/*-bl-*.md | wc -l | tr -d ' ')" == "4" ]] && ok "the refusal wrote no entry" || bad "refusal wrote an entry"

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

# The four-value type vocabulary is refused at the WRITER, not only judged by
# validate.py. BL-354: one archived item carried `type: feature`, which is not in the
# vocabulary, so validate.py exited 1 on every run of a clean tree and masked any real
# finding a later run would want to see. The writer already refuses it — this pins that,
# because the guard was untested and its absence is what made the stale value plausible.
# An EMPTY --type is not in this list on purpose: `${TYPE:-task}` defaults it, which is
# the documented default and not the defect BL-354 is about.
for bad_type in feature chore; do
  out="$(bash "$REG" --origin manual --title "bad type" --type "$bad_type" 2>&1)" \
    && bad "register-item accepted --type '$bad_type'" \
    || case "$out" in
         *"invalid type"*|*"must be bug, improvement, task, or idea"*)
           ok "--type '$bad_type' refused by the writer" ;;
         *) bad "--type '$bad_type' failed for the wrong reason: $out" ;;
       esac
done
for good_type in bug improvement task idea; do
  G="$(bash "$REG" --origin manual --title "good type" --type "$good_type" 2>/dev/null | head -1)"
  [[ "$(fm "$G" type)" == "$good_type" ]] && ok "--type '$good_type' round-trips" \
    || bad "--type '$good_type' did not survive: $(fm "$G" type)"
done

# BL-360: a source escalated to N repos keeps N pointers. stamp_escalated_to() rewrote
# the line, so ten --escalate-to runs against one --source-id left it pointing only at
# the tenth — nine forward links silently lost when BL-319 was fanned to the fleet. The
# reverse links survived (each counterpart carries origin: aidex/BL-NNN), so nothing was
# orphaned; the source just could not show its own fan-out, and the ten ids had to be
# written into the body by hand.
mkdir -p "$TMP/fan/.context/backlog" "$TMP/r1" "$TMP/r2" "$TMP/r3"
SRC="$(bash "$REG" --origin manual --title "fan me out" 2>/dev/null | head -1)"
SRCID="$(fm "$SRC" id)"
for r in r1 r2 r3; do
  mkdir -p "$TMP/$r/.context/backlog"
  bash "$REG" --origin manual --title "fan me out" --escalate-to "$TMP/$r" --source-id "$SRCID" >/dev/null 2>&1
done
ESC="$(fm "$SRC" escalated_to)"
n_ptr="$(printf '%s' "$ESC" | tr ',' '\n' | grep -c 'BL-')"
[[ "$n_ptr" -eq 3 ]] && ok "three --escalate-to runs leave three pointers ($ESC)" \
  || bad "escalated_to kept $n_ptr of 3 pointers: '$ESC'"
# Escalating to a repo already in the list is not a duplicate: it mints a NEW
# counterpart there, so the source gains a fourth genuine pointer. Asserted so the
# accumulation is not mistaken for de-duplication, which this flow cannot need.
bash "$REG" --origin manual --title "fan me out" --escalate-to "$TMP/r1" --source-id "$SRCID" >/dev/null 2>&1
n2="$(fm "$SRC" escalated_to | tr ',' '\n' | grep -c 'BL-')"
[[ "$n2" -eq 4 ]] && ok "a second counterpart in an already-listed repo is a fourth pointer, not a duplicate" \
  || bad "a repeat escalation left $n2 pointers: '$(fm "$SRC" escalated_to)'"
# Every element is a well-formed <repo>/BL-NNN, so validate.py can judge them one by one.
printf '%s' "$(fm "$SRC" escalated_to)" | tr ',' '\n' | sed 's/^ *//' \
  | grep -qvE '^[A-Za-z0-9_.-]+/BL-[0-9]+$' \
  && bad "a fan-out element is not a <repo>/BL-NNN ref: '$(fm "$SRC" escalated_to)'" \
  || ok "every fan-out element keeps the cross-repo ref format"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — register fields: $PASS cells round-trip"; exit 0; }; echo "$FAIL failure(s)"; exit 1
