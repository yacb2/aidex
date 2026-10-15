#!/usr/bin/env bash
# test-define-check.sh — the definition contract is checked, not described.
#
# define-check.py says which open items are below the contract and what a script can
# already deduce; sweep-eligible.py keeps every underdefined, parked or cross-repo item
# out of the queue (owner's call 2026-08-27, Q8). Also pins the front-matter regression
# that produced the first false report: `\s*` after the colon ate the newline of an
# EMPTY field (`origin_ref: `) and swallowed the next line, so `priority` read as absent.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog" "$TMP/p/src/gap" "$TMP/other_ws"; : > "$TMP/p/src/gap/lane.py"; cd "$TMP/p"
reg() { bash "$SCRIPTS/register-item.sh" --origin manual --no-index "$@" 2>/dev/null; }
idof() { awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$1"; }
accept() { python3 - "$1" <<'PY'
import sys,re;p=sys.argv[1];t=open(p).read()
t=re.sub(r'(## Acceptance\n)', r'\1\n- the lane renders\n', t, count=1);open(p,'w').write(t)
PY
}
context() { python3 - "$1" <<'PY'
import sys,re;p=sys.argv[1];t=open(p).read()
t=re.sub(r'(## Context\n)', r'\1\nWhy this matters, in prose.\n', t, count=1);open(p,'w').write(t)
PY
}

echo "define-check.py:"
A="$(reg --title "bare")"; AID="$(idof "$A")"
OUT="$(python3 "$SCRIPTS/define-check.py" 2>&1)"; RC=$?
[[ $RC -eq 1 ]] && grep -q "missing: verify, touches, Context, Acceptance" <<<"$OUT" && ok "a freshly registered item is underdefined: verify, touches, Context, Acceptance (exit 1)" || bad "bare: rc=$RC $OUT"
grep -q "0/1 defined" <<<"$OUT" && ok "summary line counts it" || bad "summary: $OUT"

# the regression: an empty field followed by priority
B="$(reg --title "empty ref" --priority P1)"; BID="$(idof "$B")"
python3 - "$B" <<'PY'
import sys,re;p=sys.argv[1];t=open(p).read();t=re.sub(r'^origin_ref:.*$','origin_ref: ',t,count=1,flags=re.M);open(p,'w').write(t)
PY
grep -q '^origin_ref: $' "$B" && grep -q '^priority: P1$' "$B" || bad "fixture: origin_ref not empty / priority missing"
OUT="$(python3 "$SCRIPTS/define-check.py" "$BID" 2>&1)"
grep -q "missing:.*priority" <<<"$OUT" && bad "REGRESSION: empty origin_ref swallowed the priority line" || ok "an empty field does not swallow the next line (priority still read)"
OUT="$(python3 "$SCRIPTS/sweep-eligible.py" 2>&1)"
grep -q "underdefined:.*priority" <<<"$OUT" && bad "REGRESSION in sweep-eligible: priority read as absent" || ok "sweep-eligible reads priority past the empty field too"

# fully defined: every contract field + body sections
C="$(reg --title "defined" --surface internal --verify "tests/test_gap.py")"; CID="$(idof "$C")"
accept "$C"; context "$C"
bash "$SCRIPTS/define-item.sh" "$CID" --touches "src/gap" --no-index >/dev/null 2>&1 || bad "define-item failed"
OUT="$(python3 "$SCRIPTS/define-check.py" "$CID" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && grep -q "^ok " <<<"$OUT" && ok "surface+verify+touches+Context+Acceptance: defined (exit 0)" || bad "defined: rc=$RC $OUT"
OUT="$(python3 "$SCRIPTS/sweep-eligible.py" 2>&1)"
grep -A1 "^ELIGIBLE (1)" <<<"$OUT" | grep >/dev/null "$CID" && ok "the defined item is the only eligible one" || bad "eligible: $OUT"
grep -q "underdefined: verify, touches" <<<"$OUT" && ok "sweep-eligible names what the underdefined item lacks" || bad "reason: $OUT"

# deductions: a backticked path that exists -> touches candidate; a sibling project -> cross-repo
D="$(reg --title "cites paths" --surface ops --verify "census output")"; DID="$(idof "$D")"
accept "$D"; context "$D"
printf '\nSee `src/gap/lane.py` and `other_ws/backend/app.py`; relates to %s.\n' "$CID" >> "$D"
OUT="$(python3 "$SCRIPTS/define-check.py" --json "$DID" 2>&1)"
python3 - "$OUT" "$CID" <<'PY' && ok "deduces touches candidate, cross-repo path and cited id" || bad "deduction: $OUT"
import json,sys;j=json.loads(sys.argv[1]);it=j['items'][0]
assert it['touches_candidates']==['src/gap/lane.py'],it
assert it['cross_repo']==['other_ws/backend/app.py'],it
assert it['cites']==[sys.argv[2]],it
PY
bash "$SCRIPTS/define-item.sh" "$DID" --touches "other_ws/backend" --no-index >/dev/null 2>&1
OUT="$(python3 "$SCRIPTS/sweep-eligible.py" 2>&1)"
grep -q "cross-repo: other_ws" <<<"$OUT" && ok "an item whose touches live in a sibling project is NEEDS-DECISION: cross-repo" || bad "cross-repo: $OUT"

# BL-645: a not-yet-existing file under a directory INSIDE the project is in-tree, even when
# a sibling project of the same name exists (aidex_ws/aidex vs ~/projects/aidex)
mkdir -p "$TMP/p/lib" "$TMP/lib"
bash "$SCRIPTS/define-item.sh" "$DID" --touches "lib/tests/test-new.sh" --no-index >/dev/null 2>&1
OUT="$(python3 "$SCRIPTS/define-check.py" --json "$DID" 2>&1)"
python3 -c "import json,sys;it=json.loads(sys.argv[1])['items'][0];assert not any(x.startswith('lib/') for x in it['cross_repo']),it" "$OUT" \
  && ok "a new file under an in-project dir is not cross-repo when a same-named sibling exists" || bad "in-tree new file read as cross-repo: $OUT"

# clusters: two items sharing a touches token
bash "$SCRIPTS/define-item.sh" "$DID" --touches "src/gap" --no-index >/dev/null 2>&1
OUT="$(python3 "$SCRIPTS/define-check.py" 2>&1)"
grep -q "src/gap: $CID, $DID" <<<"$OUT" && ok "items sharing a touches token are listed as a cluster" || bad "cluster: $OUT"
grep -q "cites: $DID -> $CID" <<<"$OUT" && ok "citations between open items are listed" || bad "cites cluster: $OUT"

# parked item is out of the queue
python3 - "$C" <<'PY'
import sys;p=sys.argv[1];t=open(p).read();t=t.replace('status: open','status: doing\nawaiting: owner',1);open(p,'w').write(t)
PY
OUT="$(python3 "$SCRIPTS/sweep-eligible.py" 2>&1)"
grep -q "awaiting owner" <<<"$OUT" && ! grep -A1 "^ELIGIBLE" <<<"$OUT" | grep >/dev/null "$CID" && ok "an item awaiting the owner is NEEDS-DECISION, never eligible" || bad "awaiting: $OUT"

# triage.sh carries the check
OUT="$(bash "$SCRIPTS/triage.sh" 2>&1)"
grep -q "definition — open items below the definition contract" <<<"$OUT" && ok "triage.sh reports the definition check" || bad "triage: $OUT"

# BL-251: the hint for body sections must not name define-item.sh (it writes front-matter only)
OUT="$(python3 "$SCRIPTS/define-check.py" 2>&1)"
grep -q "Context/Acceptance: edit the body" <<<"$OUT" && ! grep -q "write the missing fields with define-item.sh" <<<"$OUT" \
  && ok "the underdefined hint sends Context/Acceptance to the body, front-matter to define-item.sh" || bad "hint: $(tail -1 <<<"$OUT")"

# BL-252: a backticked _tmp/ path is scratch, never a touches candidate
mkdir -p _tmp && : > _tmp/probe.log
T="$(reg --title "cites a scratch log")"; TID="$(idof "$T")"; context "$T"; accept "$T"
printf '\nSee `_tmp/probe.log` and `src/gap/lane.py`.\n' >> "$T"
OUT="$(python3 "$SCRIPTS/define-check.py" 2>&1)"
LINE="$(grep -A3 "^!! $TID " <<<"$OUT" | grep 'touches?' || true)"
[[ "$LINE" == *"src/gap/lane.py"* && "$LINE" != *"_tmp/"* ]] && ok "touches? proposes src/gap/lane.py and never _tmp/probe.log" || bad "touches?: $LINE"

# BL-255: a REVIEW signal names the sentence that fired it
S="$(reg --title "acceptance says decision" --verify "a test")"; SID="$(idof "$S")"; context "$S"
python3 - "$S" <<'PY2'
import sys,re;p=sys.argv[1];t=open(p).read()
t=re.sub(r'(## Acceptance\n)', r'\1\n- A decision is recorded on whether AD rewriting runs at 0.2.\n', t, count=1);open(p,'w').write(t)
PY2
bash "$SCRIPTS/define-item.sh" "$S" --touches "src/gap/lane.py" --no-index >/dev/null 2>&1
J="$(python3 "$SCRIPTS/sweep-eligible.py" --json 2>/dev/null)"
python3 - "$J" "$SID" <<'PY2'
import json,sys; r=json.loads(sys.argv[1]); it=[i for i in r['review'] if i['id']==sys.argv[2]]
assert it, 'not in REVIEW'; assert 'A decision is recorded on whether' in it[0]['reason'], it[0]['reason']
PY2
[[ $? -eq 0 ]] && ok "REVIEW reason quotes the sentence, so the reader judges instead of guessing" || bad "signal excerpt: $J"

OUT="$(python3 "$SCRIPTS/sweep-eligible.py" 2>/dev/null)"
grep -q "«A decision is recorded on whether AD rewriting runs at 0.2.»" <<<"$OUT" && ok "the REVIEW table prints the whole quoted sentence on its own line" || bad "table quote: $(grep -A1 "$SID" <<<"$OUT")"

# backlog-s34: the item readers agree on a single-quoted value (YAML allows it; quick-wins and
# detect-resolved already read it). sweep-eligible and sweep-order each carried a copy of the
# define-check reader that stripped double quotes only, so `estimate: 'S'` ranked after XL and
# `surface: 'ui'` fell to internal.
Q="$(reg --title "single quoted" --estimate S --surface internal --verify "tests/test_gap.py")"; QID="$(idof "$Q")"
accept "$Q"; context "$Q"; bash "$SCRIPTS/define-item.sh" "$Q" --touches "src/gap/lane.py" --no-index >/dev/null 2>&1
sed -i.bak -e "s/^estimate: .*/estimate: 'S'/" -e "s/^surface: .*/surface: 'ui'/" "$Q" && rm -f "$Q.bak"
J="$(python3 "$SCRIPTS/sweep-eligible.py" --json 2>/dev/null)"
python3 - "$J" "$QID" <<'PY2'
import json,sys; r=json.loads(sys.argv[1]); it=[i for i in r['eligible'] if i['id']==sys.argv[2]]
assert it, "not eligible"; assert it[0]['estimate'] == 'S', it[0]['estimate']
PY2
[[ $? -eq 0 ]] && ok "sweep-eligible reads estimate: 'S' as S" || bad "single-quoted estimate: $(python3 -c 'import json,sys; print([i["estimate"] for i in json.loads(sys.argv[1])["eligible"]])' "$J")"
SURF="$(python3 "$SCRIPTS/sweep-order.py" "$TMP/p/.context/backlog" --format json <<<"$J" | python3 -c 'import json,sys; print([i["surface"] for c in json.load(sys.stdin)["queue"] for i in c["items"] if i["id"]==sys.argv[1]][0])' "$QID")"
[[ "$SURF" == "ui" ]] && ok "sweep-order reads surface: 'ui' as ui" || bad "single-quoted surface read as '$SURF'"

# backlog-s34: the estimate scale is restated in code; every restatement matches the reference
# table (references/01-backlog-conventions.md, `estimate` row), so one edit cannot miss a site.
REF="$SCRIPTS/../references/01-backlog-conventions.md"
SCALE="$(grep -m1 '^| `estimate` |' "$REF" | python3 -c 'import re,sys; print(" ".join(re.findall(r"`([A-Z]+)`", sys.stdin.read().split("|")[2])))')"
# Python-side sites are read as values (importlib), so a reshaped declaration still gets checked;
# the two shell sites are checked by behaviour: every reference value is accepted, XXL refused (rc 2).
SITES="$(python3 - "$SCRIPTS" <<'PY2'
import importlib, sys
s = sys.argv[1]; sys.path.insert(0, s)
rank = importlib.import_module('define-check').ESTIMATE_RANK
print('define-check', ' '.join(sorted(rank, key=rank.get)))
print('quick-wins.py', ' '.join(importlib.import_module('quick-wins').ESTIMATES))
print('estimate-calibration.py', ' '.join(importlib.import_module('estimate-calibration').BUCKETS))
PY2
)"; SRC=$?
[[ $SRC -eq 0 ]] || bad "estimate-scale site extraction crashed rc=$SRC"
[[ "$(cut -d' ' -f1 <<<"$SITES" | sort | tr '\n' ' ')" == "define-check estimate-calibration.py quick-wins.py " ]] || bad "estimate-scale python sites read: $SITES"
[[ "$SCALE" == "XS S M L XL" ]] || bad "estimate scale not read from the reference: '$SCALE'"
while read -r site scale; do
  [[ "$scale" == "$SCALE" ]] && ok "estimate scale in $site matches the reference" || bad "estimate scale in $site is '$scale', reference says '$SCALE'"
done <<<"$SITES"
for v in $SCALE; do
  bash "$SCRIPTS/define-item.sh" "$Q" --estimate "$v" --no-index >/dev/null 2>&1 && reg --title "scale $v" --estimate "$v" >/dev/null \
    && ok "define-item.sh and register-item.sh accept estimate $v" || bad "estimate $v refused by define-item.sh or register-item.sh"
done
bash "$SCRIPTS/define-item.sh" "$Q" --estimate XXL --no-index >/dev/null 2>&1; RCD=$?
reg --title "scale XXL" --estimate XXL >/dev/null; RCR=$?
[[ $RCD -eq 2 && $RCR -eq 2 ]] && ok "estimate XXL is refused with rc 2 by define-item.sh and register-item.sh" || bad "estimate XXL: define-item rc=$RCD register-item rc=$RCR (want 2 and 2)"

# a linked git worktree is a sibling of its project: the main worktree's queue is the one checked
WTBASE="$(mktemp -d "${TMPDIR:-/tmp}/w19.XXXXXX")"; mkdir -p "$WTBASE/main/.context/backlog"
mkdir -p "$WTBASE/.context"   # a stray .context/ (no backlog/) above the worktree, like ~/.context: HOME is the stop
cp "$A" "$WTBASE/main/.context/backlog/"
git -C "$WTBASE/main" init -q && git -C "$WTBASE/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$WTBASE/main" worktree add -q "$WTBASE/linked" -b wtbranch
OUTW="$(cd "$WTBASE/linked" && HOME="$WTBASE" python3 "$SCRIPTS/define-check.py" 2>&1)"
grep -q "0/1 defined" <<<"$OUTW" && ok "run from a linked worktree it checks the main worktree's queue" || bad "worktree: $OUTW"
rm -rf "$WTBASE"

echo; [[ $FAIL -eq 0 ]] && echo "OK — define-check: $PASS cells" || { echo "$FAIL failure(s)"; exit 1; }
