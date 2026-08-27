#!/usr/bin/env bash
# test-sweep-kickoff.sh — the kickoff partitions, cluster-orders, writes ONE sweep
# work-list, and keeps NEEDS-DECISION out of it; triage verdicts land in the items;
# `--origin sweep` is accepted everywhere the enum is declared.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
CONV="$(cd "$SCRIPTS/../../aidex-conventions/scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
fm()  { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog"; cd "$TMP/p"
reg() { bash "$SCRIPTS/register-item.sh" --origin manual --no-index "$@" 2>/dev/null; }
idof() { awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$1"; }
accept() { sed -i.bak 's/^- <!-- concrete, verifiable criterion -->$/- the thing is done and a test says so/' "$1" && rm -f "$1.bak"; }

echo "sweep kickoff:"
# fixture: two clusters, one depends edge that reverses file order, one MERGE pair,
# one no-Acceptance (NEEDS-DECISION), one REVIEW signal, one blocked, one M-sized
A="$(reg --title "alpha gap lane" --estimate S)";   AID="$(idof "$A")"; accept "$A"
B="$(reg --title "bravo export csv" --estimate XS)"; BID="$(idof "$B")"; accept "$B"
C="$(reg --title "charlie gap lane hover" --estimate S)"; CID="$(idof "$C")"; accept "$C"
D="$(reg --title "delta before bravo" --estimate S)"; DID="$(idof "$D")"; accept "$D"
E="$(reg --title "echo same as bravo" --estimate XS)"; EID="$(idof "$E")"; accept "$E"
N="$(reg --title "no acceptance yet" --estimate XS)"; NID="$(idof "$N")"
R="$(reg --title "runs against prod" --estimate XS)"; RID="$(idof "$R")"; accept "$R"; printf '\nBackfill against echo_prod first.\n' >> "$R"
K="$(reg --title "blocked one" --estimate XS --blocked-by "vendor")"; KID="$(idof "$K")"; accept "$K"
M="$(reg --title "medium sized" --estimate M)"; MID="$(idof "$M")"; accept "$M"

# triage verdicts written INTO the items (Task 4.2)
bash "$SCRIPTS/sweep-triage.sh" "$AID" --touches "apps/gap/lane.py" --surface ui --verify "screenshot" --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-triage.sh" "$CID" --touches "apps/gap/lane.py, frontend/Lane.vue" --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-triage.sh" "$BID" --touches "apps/export/csv.py" --depends "$DID" --estimate S --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-triage.sh" "$DID" --touches "apps/export/models.py" --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-triage.sh" "$EID" --depends "merge:$BID" --no-index >/dev/null 2>&1
for kv in "touches:apps/gap/lane.py" "surface:ui" "verify:screenshot"; do
  [[ "$(fm "$A" "${kv%%:*}")" == "${kv#*:}" ]] && ok "triage wrote ${kv%%:*} into the item" || bad "triage ${kv%%:*}: '$(fm "$A" "${kv%%:*}")'"
done
[[ "$(fm "$B" estimate)" == "S" && "$(fm "$B" depends)" == "$DID" ]] && ok "triage corrected estimate and wrote depends" || bad "B: $(fm "$B" estimate) / $(fm "$B" depends)"
[[ "$(fm "$B" updated)" == "$(date +%F)" ]] && ok "triage stamps updated" || bad "updated not stamped"
bash "$SCRIPTS/sweep-triage.sh" "$AID" --estimate XXL --no-index >/dev/null 2>&1 && bad "bad estimate accepted" || ok "triage refuses an invalid estimate"
bash "$SCRIPTS/sweep-triage.sh" "$AID" --depends "nope" --no-index >/dev/null 2>&1 && bad "bad depends accepted" || ok "triage refuses a malformed depends"

# --dry-run: the queue, nothing written
OUT="$(bash "$SCRIPTS/sweep-kickoff.sh" --dry-run 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && ok "dry-run exits 0" || bad "dry-run rc=$RC: $OUT"
[[ ! -d .context/worklists ]] && ok "dry-run writes no work-list" || bad "dry-run wrote a work-list"
[[ "$OUT" == *"NEEDS-DECISION (2)"* && "$OUT" == *"$NID"* && "$OUT" == *"$KID"* ]] && ok "no-Acceptance and blocked items are NEEDS-DECISION" || bad "needs-decision: $OUT"
[[ "$OUT" == *"REVIEW (1)"* && "$OUT" == *"$RID"* ]] && ok "the prod-signal item is REVIEW, not queued" || bad "review tier: $OUT"
[[ "$OUT" != *"$MID"* ]] && ok "an M item is outside --size XS,S" || bad "M item present"

# the real thing
WL="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Small sweep 3" --slug small-sweep-3 2>/dev/null | tail -1)"
[[ -f "$WL" ]] && ok "work-list written: $(basename "$WL")" || bad "no work-list: $WL"
grep -q '^mode: sweep$' "$WL" && grep -q '^  publish: never$' "$WL" && ok "mode: sweep, publish: never" || bad "front-matter: $(head -12 "$WL")"
grep -q "^queue-size-at-kickoff: 5$" "$WL" && ok "original queue size recorded (growth baseline)" || bad "queue-size line: $(grep queue-size "$WL")"
awk '/^## Needs decision \(kickoff\)/{n=NR} /^## Deferred/{d=NR} END{exit !(n && d && n<d)}' "$WL" && ok "Needs-decision section sits before Deferred / emergent (which stays last)" || bad "section order in worklist"
python3 "$CONV/validate-worklist.py" "$WL" >/dev/null && ok "sweep work-list validates" || bad "validate: $(python3 "$CONV/validate-worklist.py" "$WL")"
Q="$(grep -E '^[0-9]+\. \[ \] ' "$WL")"
[[ "$(grep -c . <<<"$Q")" == "5" ]] && ok "five eligible items queued" || bad "queue: $Q"
pos() { grep -nE "^[0-9]+\. \[ \] .*\b$1\b" "$WL" | cut -d: -f1; }
# cluster adjacency: A and C share apps/gap/lane.py → adjacent
[[ $(( $(pos "$AID") - $(pos "$CID") )) -eq 1 || $(( $(pos "$CID") - $(pos "$AID") )) -eq 1 ]] && ok "items sharing touches are adjacent (gap cluster)" || bad "gap cluster split: $(pos "$AID") vs $(pos "$CID")"
# depends: D before B even though B's file sorts first and B is XS
[[ $(pos "$DID") -lt $(pos "$BID") ]] && ok "depends edge orders D before B (across file order)" || bad "depends violated: D=$(pos "$DID") B=$(pos "$BID")"
# merge pair: E adjacent to B and labelled MERGE
[[ $(( $(pos "$EID") - $(pos "$BID") )) -eq 1 || $(( $(pos "$BID") - $(pos "$EID") )) -eq 1 ]] && ok "merge pair adjacent" || bad "merge pair split"
grep -E "^[0-9]+\. \[ \] .*\b$EID\b" "$WL" | grep -q "MERGE" && ok "MERGE marked on the pair" || bad "no MERGE marker: $(grep "$EID" "$WL")"
grep -q "$NID\|$KID\|$RID\|$MID" <<<"$Q" && bad "a non-eligible item was queued" || ok "REVIEW / NEEDS-DECISION / oversize items are not in the queue"

# --include queues a REVIEW item the kickoff has read; --exclude pulls an eligible one
J="$(bash "$SCRIPTS/sweep-kickoff.sh" --json --include "$RID" --exclude "$AID" 2>/dev/null)"
python3 -c '
import json,sys; d=json.loads(sys.argv[1]); ids=[i["id"] for c in d["queue"] for i in c["items"]]
assert sys.argv[2] in ids and sys.argv[3] not in ids and not d["review"], ids' "$J" "$RID" "$AID" \
  && ok "--include / --exclude move items across the boundary" || bad "--include/--exclude: $J"

# a depends cycle cannot be ordered: exit 2, no work-list
bash "$SCRIPTS/sweep-triage.sh" "$DID" --depends "$BID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-kickoff.sh" --title "cycle" --slug cycle >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 && ! -e .context/worklists/*cycle* ]] && grep -q "cycle" "$TMP/err" && ok "a depends cycle exits 2 and writes nothing" || bad "cycle: rc=$RC $(cat "$TMP/err")"

# --origin sweep (Task 4.4)
S="$(bash "$SCRIPTS/register-item.sh" --origin sweep --title "found mid-sweep" --worklist "$WL" --no-index 2>/dev/null)"
[[ -f "$S" && "$(fm "$S" origin)" == "sweep" && "$(fm "$S" origin_ref)" == "worklist/$(basename "$WL")" ]] && ok "--origin sweep --worklist writes origin_ref worklist/<file>" || bad "origin sweep: $(fm "$S" origin) $(fm "$S" origin_ref)"
S2="$(bash "$SCRIPTS/register-item.sh" --origin sweep --title "no worklist yet" --no-index 2>/dev/null)"
[[ -f "$S2" && "$(fm "$S2" origin_ref)" == "" ]] && ok "--origin sweep without --worklist is accepted (empty ref)" || bad "origin sweep bare"
bash "$SCRIPTS/register-item.sh" --origin bogus --title x --no-index >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "--origin bogus exits 2" || bad "bogus origin accepted"
# the two reference tables declare the enum too
CONVREF="$SCRIPTS/../references/01-backlog-conventions.md"; GLOBAL="$CONV/../references/00-global.md"
grep -q '`sweep`' "$CONVREF" && grep -qE '^\| `origin` .*`sweep`' "$GLOBAL" && ok "sweep is in both reference enums" || bad "reference enums lack sweep"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — sweep kickoff: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
