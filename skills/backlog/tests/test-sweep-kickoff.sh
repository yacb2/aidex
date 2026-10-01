#!/usr/bin/env bash
# test-sweep-kickoff.sh — the kickoff partitions, cluster-orders, writes ONE sweep
# work-list, and keeps NEEDS-DECISION out of it; triage verdicts land in the items;
# `--origin sweep` is accepted everywhere the enum is declared.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
CONV="$(cd "$SCRIPTS/../../conventions/scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
fm()  { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog"; cd "$TMP/p"
# The definition contract (2026-08-27) keeps an underdefined item out of every queue, so the
# fixture registers each item with the contract met (verify, Context prose, a touches token)
# and the cells below take fields away deliberately.
reg() { local f; f="$(bash "$SCRIPTS/register-item.sh" --origin manual --no-index --verify "a targeted test" "$@" 2>/dev/null)"
  python3 - "$f" <<'PY'
import sys,re;p=sys.argv[1];t=open(p).read()
t=re.sub(r'(## Context\n)', r'\1\nWhy this matters, in prose.\n', t, count=1);open(p,'w').write(t)
PY
  bash "$SCRIPTS/define-item.sh" "$f" --touches "apps/misc.py" --no-index >/dev/null 2>&1; printf '%s\n' "$f"; }
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
bash "$SCRIPTS/define-item.sh" "$AID" --touches "apps/gap/lane.py" --surface ui --verify "screenshot" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$CID" --touches "apps/gap/lane.py, frontend/Lane.vue" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$BID" --touches "apps/export/csv.py" --depends "$DID" --estimate S --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$DID" --touches "apps/export/models.py" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$EID" --depends "merge:$BID" --no-index >/dev/null 2>&1
for kv in "touches:apps/gap/lane.py" "surface:ui" "verify:screenshot"; do
  [[ "$(fm "$A" "${kv%%:*}")" == "${kv#*:}" ]] && ok "triage wrote ${kv%%:*} into the item" || bad "triage ${kv%%:*}: '$(fm "$A" "${kv%%:*}")'"
done
[[ "$(fm "$B" estimate)" == "S" && "$(fm "$B" depends)" == "$DID" ]] && ok "triage corrected estimate and wrote depends" || bad "B: $(fm "$B" estimate) / $(fm "$B" depends)"
[[ "$(fm "$B" updated)" == "$(date +%F)" ]] && ok "triage stamps updated" || bad "updated not stamped"
bash "$SCRIPTS/define-item.sh" "$AID" --estimate XXL --no-index >/dev/null 2>&1 && bad "bad estimate accepted" || ok "triage refuses an invalid estimate"
bash "$SCRIPTS/define-item.sh" "$AID" --depends "nope" --no-index >/dev/null 2>&1 && bad "bad depends accepted" || ok "triage refuses a malformed depends"

# --dry-run: the queue, nothing written
OUT="$(bash "$SCRIPTS/sweep-kickoff.sh" --dry-run 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && ok "dry-run exits 0" || bad "dry-run rc=$RC: $OUT"
[[ ! -d .context/worklists ]] && ok "dry-run writes no work-list" || bad "dry-run wrote a work-list"
[[ "$OUT" == *"NEEDS-DECISION (2)"* && "$OUT" == *"$NID"* && "$OUT" == *"$KID"* ]] && ok "no-Acceptance and blocked items are NEEDS-DECISION" || bad "needs-decision: $OUT"
[[ "$OUT" == *"REVIEW (1)"* && "$OUT" == *"$RID"* ]] && ok "the prod-signal item is REVIEW, not queued" || bad "review tier: $OUT"
[[ "$OUT" != *"$MID"* ]] && ok "an M item is outside --size XS,S" || bad "M item present"

# --slug is OPTIONAL, and omitting it is the path a real caller takes. Every other write
# here passes --slug, so bash 3.2's empty-array-under-`set -u` expansion in the
# `"${SLUG_ARGS[@]}"` call went unseen: the queue printed, then the run died before the
# work-list existed. Assert the DEFAULT path writes a file (BL-291).
NOSLUG_ERR="$TMP/noslug.err"
NOSLUG="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Kickoff with no slug" 2>"$NOSLUG_ERR" | tail -1)"
[[ -f "$NOSLUG" ]] && ok "a kickoff without --slug writes its work-list" \
  || bad "no-slug kickoff wrote nothing: $(cat "$NOSLUG_ERR")"
grep -q "unbound variable" "$NOSLUG_ERR" && bad "no-slug kickoff hit an unbound variable: $(cat "$NOSLUG_ERR")" \
  || ok "a kickoff without --slug raises no unbound-variable error"
rm -f "$NOSLUG"

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
grep -E "^[0-9]+\. \[ \] .*\b$EID\b" "$WL" | grep >/dev/null "MERGE" && ok "MERGE marked on the pair" || bad "no MERGE marker: $(grep "$EID" "$WL")"
grep -q "$NID\|$KID\|$RID\|$MID" <<<"$Q" && bad "a non-eligible item was queued" || ok "REVIEW / NEEDS-DECISION / oversize items are not in the queue"

# --include queues a REVIEW item the kickoff has read; --exclude pulls an eligible one
J="$(bash "$SCRIPTS/sweep-kickoff.sh" --json --include "$RID" --exclude "$AID" 2>/dev/null)"
python3 -c '
import json,sys; d=json.loads(sys.argv[1]); ids=[i["id"] for c in d["queue"] for i in c["items"]]
assert sys.argv[2] in ids and sys.argv[3] not in ids and not d["review"], ids' "$J" "$RID" "$AID" \
  && ok "--include / --exclude move items across the boundary" || bad "--include/--exclude: $J"

# the small-sweep-3 work-list is still `doing` and now holds every item (BL-250); close it
sed -i.bak 's/^status: doing/status: done/' .context/worklists/*small-sweep-3*.md && rm -f .context/worklists/*.bak

# BL-482: --exclude is "a decision the regex could not see", so the pulled item belongs
# under Needs decision — it was dropped, and the report said "none recorded at kickoff"
# for a sweep that had pulled eight. The optional `:reason` suffix is carried as written.
WLX="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Exclude run" --slug exclude-run --exclude "$AID" --exclude "$CID:waits on the lane redesign" 2>/dev/null | tail -1)"
NDX="$(awk '/^## Needs decision \(kickoff\)/{f=1;next} /^## /{f=0} f' "$WLX" 2>/dev/null)"
grep -q "^- $AID — alpha gap lane   <!-- reason: pulled at kickoff (--exclude) -->$" <<<"$NDX" \
  && ok "an --exclude item is recorded under Needs decision, marked pulled at kickoff" || bad "--exclude not under Needs decision: [$NDX]"
grep -q "^- $CID — charlie gap lane hover   <!-- reason: pulled at kickoff (--exclude): waits on the lane redesign -->$" <<<"$NDX" \
  && ok "--exclude BL-NNN:<reason> carries the reason into Needs decision" || bad "--exclude reason: [$NDX]"
grep -qE "^[0-9]+\. \[ \] .*\b($AID|$CID)\b" "$WLX" && bad "an --exclude item was still queued" || ok "--exclude BL-NNN:<reason> still pulls the item from the queue"
sed -i.bak 's/^status: doing/status: done/' "$WLX" && rm -f "$WLX.bak"
# a comma list is several ids, each with its own reason; a repeat is one line; a reason
# cannot close the HTML comment it is written into
WLY="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Exclude list" --slug exclude-list --exclude "$AID,$CID:held --> until Friday, maybe later" --exclude "$AID" 2>/dev/null | tail -1)"
NDY="$(awk '/^## Needs decision \(kickoff\)/{f=1;next} /^## /{f=0} f' "$WLY" 2>/dev/null)"
[[ "$(grep -c "^- $AID — alpha gap lane   <!-- reason: pulled at kickoff (--exclude) -->$" <<<"$NDY")" -eq 1 ]] \
  && ok "--exclude A,B: the first id gets its own titled line, once despite the repeat" || bad "comma/repeat: [$NDY]"
grep -q "^- $CID — charlie gap lane hover   <!-- reason: pulled at kickoff (--exclude): held --&gt; until Friday, maybe later -->$" <<<"$NDY" \
  && ok "--exclude A,B:reason: the second id carries its reason, commas kept and --> escaped" || bad "comma reason/escape: [$NDY]"
grep -qE "^[0-9]+\. \[ \] .*\b($AID|$CID)\b" "$WLY" && bad "a comma-listed --exclude item was still queued" || ok "every id of a comma list is pulled from the queue"
sed -i.bak 's/^status: doing/status: done/' "$WLY" && rm -f "$WLY.bak"
# BL-490 (b): a trailing comma and a space before the colon are typing slips, not unknown ids
WLZ="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Exclude slips" --slug exclude-slips --exclude "$AID,$CID : waits on design," 2>"$TMP/slip.err" | tail -1)"; RC=${PIPESTATUS[0]}
NDZ="$(sed -n '/^## Needs decision/,/^## Deferred/p' "$WLZ" 2>/dev/null)"
grep -q "^- $AID — alpha gap lane   <!-- reason: pulled at kickoff (--exclude) -->$" <<<"$NDZ" \
  && grep -q "^- $CID — charlie gap lane hover   <!-- reason: pulled at kickoff (--exclude): waits on design -->$" <<<"$NDZ" \
  && ok "--exclude tolerates a trailing comma and a space before the colon" || bad "exclude slips: rc=$RC $(cat "$TMP/slip.err") [$NDZ]"
sed -i.bak 's/^status: doing/status: done/' "$WLZ" 2>/dev/null && rm -f "$WLZ.bak"
# an id in no partition list is a typo: refuse, never write an untitled line
bash "$SCRIPTS/sweep-kickoff.sh" --title "Exclude typo" --slug exclude-typo --exclude "BL-99999" >/dev/null 2>"$TMP/typo.err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "BL-99999" "$TMP/typo.err" && ! ls .context/worklists/*exclude-typo* >/dev/null 2>&1 \
  && ok "--exclude of an unknown id exits 2 naming it, and writes no work-list" || bad "unknown --exclude: rc=$RC $(cat "$TMP/typo.err")"
# a depends cycle cannot be ordered: exit 2, no work-list
bash "$SCRIPTS/define-item.sh" "$DID" --depends "$BID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-kickoff.sh" --title "cycle" --slug cycle >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 && ! -e .context/worklists/*cycle* ]] && grep -q "cycle" "$TMP/err" && ok "a depends cycle exits 2 and writes nothing" || bad "cycle: rc=$RC $(cat "$TMP/err")"

# --origin sweep (Task 4.4)
S="$(bash "$SCRIPTS/register-item.sh" --origin sweep --title "found mid-sweep" --worklist "$WL" --no-index 2>/dev/null)"
[[ -f "$S" && "$(fm "$S" origin)" == "sweep" && "$(fm "$S" origin_ref)" == "worklist/$(basename "$WL")" ]] && ok "--origin sweep --worklist writes origin_ref worklist/<file>" || bad "origin sweep: $(fm "$S" origin) $(fm "$S" origin_ref)"
# BL-479: the registration must also land in the run's queue as an emergent item — the
# report reads only the queue, so an item that is merely registered is invisible to it
SID="$(idof "$S")"
grep -qE "^[0-9]+\. \[ \] $SID .*<!-- ref: backlog --> <!-- emergent -->" "$WL" \
  && [[ "$(grep -cE "^[0-9]+\. \[ \] $SID " "$WL")" -eq 1 ]] \
  && ok "--origin sweep --worklist appends the item to the queue as emergent, exactly once" \
  || bad "$SID not appended to the queue: $(grep -nE '^[0-9]+\. ' "$WL" | tail -2)"
S2="$(bash "$SCRIPTS/register-item.sh" --origin sweep --title "no worklist yet" --no-index 2>/dev/null)"
[[ -f "$S2" && "$(fm "$S2" origin_ref)" == "" ]] && ok "--origin sweep without --worklist is accepted (empty ref)" || bad "origin sweep bare"
bash "$SCRIPTS/register-item.sh" --origin bogus --title x --no-index >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "--origin bogus exits 2" || bad "bogus origin accepted"
# the two reference tables declare the enum too
CONVREF="$SCRIPTS/../references/01-backlog-conventions.md"; GLOBAL="$CONV/../references/00-global.md"
grep -q '`sweep`' "$CONVREF" && grep -qE '^\| `origin` .*`sweep`' "$GLOBAL" && ok "sweep is in both reference enums" || bad "reference enums lack sweep"

# BL-250: an item already queued in another `doing` work-list is not eligible again —
# two sweeps admitting the same item produced two fixes for it (2026-08-28)
Q="$(reg --title "queued elsewhere" --estimate XS)"; QID="$(idof "$Q")"; accept "$Q"
mkdir -p .context/worklists
printf -- '---\ntitle: "Other sweep"\nstatus: doing\ncreated: 2026-08-28\nupdated: 2026-08-28\nmode: sweep\n---\n\n## Queue (in execution order)\n1. [ ] %s — queued elsewhere   <!-- ref: backlog -->\n' "$QID" > .context/worklists/2026-08-28-other-sweep.md
J="$(python3 "$SCRIPTS/sweep-eligible.py" --json 2>/dev/null)"
python3 - "$J" "$QID" <<'PY2'
import json,sys; r=json.loads(sys.argv[1]); q=sys.argv[2]
assert not [i for i in r['eligible'] if i['id']==q], 'still eligible'
nd=[i for i in r['needs_decision'] if i['id']==q]; assert nd and nd[0]['reason']=='queued in worklist/2026-08-28-other-sweep.md', nd
PY2
[[ $? -eq 0 ]] && ok "an item queued in another doing work-list is NEEDS-DECISION: queued in worklist/<file>" || bad "queued elsewhere: $J"
# 2026-09-30: a sweep left `doing` turned its unticked items into NEEDS-DECISION rows with
# nothing saying the fix was to resume or close that work-list; the kickoff names it first
OUT="$(bash "$SCRIPTS/sweep-kickoff.sh" --dry-run 2>&1)"
grep -qE '^OPEN WORK-LISTS \(1\)' <<<"$OUT" && grep -qE '^  worklist/2026-08-28-other-sweep\.md +1 unticked' <<<"$OUT" \
  && ok "the kickoff names each open work-list and its unticked count before the queue" || bad "open work-lists header: $OUT"
sed -i.bak 's/^status: doing/status: done/' .context/worklists/2026-08-28-other-sweep.md && rm -f .context/worklists/2026-08-28-other-sweep.md.bak
J="$(python3 "$SCRIPTS/sweep-eligible.py" --json 2>/dev/null)"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert [i for i in r["eligible"] if i["id"]==sys.argv[2]]' "$J" "$QID" \
  && ok "a done work-list releases it" || bad "done worklist still holds it"

# BL-258: a project that tracks .context/ gives each worktree its own worklists; a `doing`
# queue in the MAIN tree must still exclude the item from a sweep run in a linked worktree
# (small-sweep-3 vs main, 2026-08-28), and the other way round
if command -v git >/dev/null; then
  git init -q . 2>/dev/null; git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -q -m base 2>/dev/null
  W="$(reg --title "wanted by both trees" --estimate XS)"; WID="$(idof "$W")"; accept "$W"
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -q -m item 2>/dev/null
  printf -- '---\ntitle: "Main sweep"\nstatus: doing\ncreated: 2026-08-28\nupdated: 2026-08-28\nmode: sweep\n---\n\n## Queue (in execution order)\n1. [ ] %s — wanted by both trees   <!-- ref: backlog -->\n' "$WID" > .context/worklists/2026-08-28-main-sweep.md
  if git worktree add -q "$TMP/p-wt" -b wt-sweep >/dev/null 2>&1; then
    J="$(cd "$TMP/p-wt" && python3 "$SCRIPTS/sweep-eligible.py" --json 2>/dev/null)"
    python3 - "$J" "$WID" <<'PY2'
import json,sys; r=json.loads(sys.argv[1]); q=sys.argv[2]
assert not [i for i in r['eligible'] if i['id']==q], 'eligible in the worktree'
nd=[i for i in r['needs_decision'] if i['id']==q]; assert nd and nd[0]['reason']=='queued in p:worklist/2026-08-28-main-sweep.md', nd
PY2
    OUTW="$(cd "$TMP/p-wt" && python3 "$SCRIPTS/sweep-eligible.py" 2>/dev/null)"
    grep -qE "^ +queued in p:worklist/2026-08-28-main-sweep.md$" <<<"$OUTW" && ok "a clipped NEEDS-DECISION reason is printed whole on the next line (BL-260)" || bad "clipped reason: $(grep -A1 "$WID" <<<"$OUTW")"
    [[ $? -eq 0 ]] && ok "a doing queue in the MAIN tree excludes the item from a sweep in a linked worktree" || bad "worktree blind to main: $J"
    sed -i.bak 's/^status: doing/status: done/' .context/worklists/2026-08-28-main-sweep.md && rm -f .context/worklists/*.bak
    mkdir -p "$TMP/p-wt/.context/worklists"
    printf -- '---\ntitle: "Worktree sweep"\nstatus: doing\ncreated: 2026-08-28\nupdated: 2026-08-28\nmode: sweep\n---\n\n## Queue (in execution order)\n1. [ ] %s — wanted by both trees   <!-- ref: backlog -->\n' "$WID" > "$TMP/p-wt/.context/worklists/2026-08-28-wt-sweep.md"
    J="$(python3 "$SCRIPTS/sweep-eligible.py" --json 2>/dev/null)"
    python3 -c 'import json,sys; r=json.loads(sys.argv[1]); nd=[i for i in r["needs_decision"] if i["id"]==sys.argv[2]]; assert nd and nd[0]["reason"]=="queued in p-wt:worklist/2026-08-28-wt-sweep.md", nd' "$J" "$WID" \
      && ok "a doing queue in a linked WORKTREE excludes the item from a sweep in main" || bad "main blind to worktree: $J"
  else echo "  skip: git worktree add unavailable"; fi
fi

# BL-605: depends only ordered the queue, so an item whose dependency was still open and
# outside the queue was presented as workable (walkcut BL-032 -> BL-027, 2026-10-01).
# A dependency that is closed, or queued in the same run, does not block; one that is open
# and not queued does, and so does a dependency on an item that this rule just blocked.
mkdir -p "$TMP/dep/.context/backlog"; cd "$TMP/dep"
O="$(reg --title "open medium dep" --estimate M)"; OID="$(idof "$O")"; accept "$O"
Z="$(reg --title "archived dep" --estimate XS)"; ZID="$(idof "$Z")"; accept "$Z"
mkdir -p .context/backlog/_archive && sed 's/^status: open/status: done/' "$Z" > ".context/backlog/_archive/$(basename "$Z")" && rm "$Z"
V="$(reg --title "victor queued dep" --estimate XS)"; VID="$(idof "$V")"; accept "$V"
X="$(reg --title "xray waits on open" --estimate S)"; XID="$(idof "$X")"; accept "$X"
Y="$(reg --title "yankee after archived" --estimate S)"; YID="$(idof "$Y")"; accept "$Y"
W="$(reg --title "whiskey after victor" --estimate S)"; WID="$(idof "$W")"; accept "$W"
T="$(reg --title "tango after xray" --estimate S)"; TID="$(idof "$T")"; accept "$T"
bash "$SCRIPTS/define-item.sh" "$XID" --depends "$OID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$YID" --depends "$ZID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$WID" --depends "$VID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$TID" --depends "$XID" --no-index >/dev/null 2>&1
# a MERGE twin is one change: when one side cannot run, neither is queued alone (either side
# may hold the `merge:` edge); a dependency parked in _deferred/ is still open; an id found
# in no backlog directory is a typo, not a closed item
MA="$(reg --title "mike merges xray" --estimate S)"; MAID="$(idof "$MA")"; accept "$MA"
Q="$(reg --title "quebec twin of papa" --estimate S)"; QID="$(idof "$Q")"; accept "$Q"
P="$(reg --title "papa holds the merge" --estimate S)"; PID="$(idof "$P")"; accept "$P"
D="$(reg --title "deferred dep" --estimate XS)"; DID="$(idof "$D")"; accept "$D"
bash "$SCRIPTS/defer-item.sh" defer "$DID" --reason "vendor" --no-index >/dev/null 2>&1
DD="$(reg --title "dd waits on deferred" --estimate S)"; DDID="$(idof "$DD")"; accept "$DD"
U="$(reg --title "uniform typo dep" --estimate S)"; UID_="$(idof "$U")"; accept "$U"
bash "$SCRIPTS/define-item.sh" "$MAID" --depends "merge:$XID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$PID" --depends "merge:$QID, $OID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$DDID" --depends "$DID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$UID_" --depends "BL-9999" --no-index >/dev/null 2>&1
OUT="$(bash "$SCRIPTS/sweep-kickoff.sh" --dry-run 2>&1)"
QS="$(sed -n '/^QUEUE/,/^$/p' <<<"$OUT")"; NDS="$(sed -n '/^NEEDS-DECISION/,/^$/p' <<<"$OUT")"
qpos() { grep -nE "^ +[0-9]+\. $1 " <<<"$QS" | cut -d: -f1; }   # the item column, not a depends: tail
[[ -n "$(qpos "$XID")" ]] && bad "an item depending on an open non-queued item was queued: $QS" \
  || ok "an item whose dependency is open and not queued stays out of QUEUE"
grep -qE "^  $XID .*depends on open $OID" <<<"$NDS" && ok "it is listed under NEEDS-DECISION naming the open dependency" || bad "blocked reason: $NDS"
[[ -n "$(qpos "$TID")" ]] && bad "an item depending on a blocked item was queued: $QS" || ok "an item depending on a blocked item is blocked too"
grep -qE "^  $TID .*depends on open $XID" <<<"$NDS" && ok "the transitive block names the blocked dependency" || bad "transitive reason: $NDS"
[[ -n "$(qpos "$MAID")" ]] && bad "a merge twin of a blocked item was queued alone: $QS" || ok "a merge twin of a blocked item stays out of QUEUE"
grep -qE "^  $MAID .*merge partner $XID not queued" <<<"$NDS" && ok "it is listed naming the merge partner" || bad "merge holder reason: $NDS"
grep -qE "^  $QID .*merge partner $PID not queued" <<<"$NDS" && [[ -z "$(qpos "$QID")" ]] \
  && ok "the twin named by a blocked merge holder is blocked too" || bad "merge target: $OUT"
grep -qE "^  $DDID .*depends on open $DID" <<<"$NDS" && [[ -z "$(qpos "$DDID")" ]] \
  && ok "a dependency parked in _deferred/ blocks (still open)" || bad "deferred dep: $OUT"
grep -qE "^  $UID_ .*depends on unknown BL-9999" <<<"$NDS" && [[ -z "$(qpos "$UID_")" ]] \
  && ok "a dependency found in no backlog directory blocks as unknown" || bad "unknown dep: $OUT"
[[ -n "$(qpos "$YID")" ]] && ok "a dependency closed in _archive/ does not block" || bad "archived dep blocked: $OUT"
[[ -n "$(qpos "$WID")" && "$(qpos "$VID")" -lt "$(qpos "$WID")" ]] 2>/dev/null \
  && ok "a dependency queued in the same run does not block (and runs first)" || bad "queued dep: $QS"
WLD="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Depends run" --slug depends-run 2>/dev/null | tail -1)"
grep -q "^- $XID — xray waits on open   <!-- reason: depends on open $OID -->$" "$WLD" 2>/dev/null \
  && ok "the written work-list records the blocked item under Needs decision" || bad "work-list needs block: $(sed -n '/^## Needs decision/,/^## Deferred/p' "$WLD" 2>/dev/null)"
sed -i.bak 's/^status: doing/status: done/' "$WLD" 2>/dev/null && rm -f "$WLD.bak"
# every eligible item blocked: the empty-queue message must not claim nothing was eligible
bash "$SCRIPTS/sweep-kickoff.sh" --dry-run --exclude "$VID,$YID" >/dev/null 2>"$TMP/allblocked.err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "nothing queueable at --size XS,S — [0-9]* eligible, all blocked by open or unknown depends" "$TMP/allblocked.err" \
  && ok "an all-blocked queue exits 2 saying the eligible items are blocked" || bad "all blocked: rc=$RC $(head -2 "$TMP/allblocked.err")"
# a depends cycle still exits 2 when an open dependency would otherwise block its members
CA="$(reg --title "cycle a" --estimate S)"; CAID="$(idof "$CA")"; accept "$CA"
CB="$(reg --title "cycle b" --estimate S)"; CBID="$(idof "$CB")"; accept "$CB"
bash "$SCRIPTS/define-item.sh" "$CAID" --depends "$CBID, $OID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/define-item.sh" "$CBID" --depends "$CAID" --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-kickoff.sh" --dry-run >/dev/null 2>"$TMP/cyc.err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "cycle among" "$TMP/cyc.err" && ok "a depends cycle is reported before open depends block its members" || bad "hidden cycle: rc=$RC $(cat "$TMP/cyc.err")"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — sweep kickoff: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
