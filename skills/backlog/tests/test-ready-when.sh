#!/usr/bin/env bash
# test-ready-when.sh — the `ready_when` front-matter field (owner decision 2026-10-18).
#
# Layer: script integration in an isolated temp project. defer-item.sh writes and clears the
# field, sweep-eligible.py judges it (date/cmd, READY / WAITING / ASK OWNER), an active item
# with an unmet one never reaches ELIGIBLE, and the index's Deferred row shows it.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; export HOME="$TMP/home"; ALLOWFILE="$HOME/.claude/aidex/ready-when-allow.txt"; mkdir -p "$HOME"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog" "$TMP/p/src/gap"; : > "$TMP/p/src/gap/lane.py"; cd "$TMP/p"
B="$TMP/p/.context/backlog"
reg() { bash "$SCRIPTS/register-item.sh" --origin manual --no-index "$@" 2>/dev/null; }
DFR="$SCRIPTS/defer-item.sh"
# a fully defined item: eligible unless something parks it
mk() {
  local f; f="$(reg --title "$1" --surface internal --verify "a test" --estimate S)"
  python3 - "$f" <<'PY'
import sys,re;p=sys.argv[1];t=open(p).read()
t=re.sub(r'(## Acceptance\n)', r'\1\n- the lane renders\n', t, count=1)
t=re.sub(r'(## Context\n)', r'\1\nWhy this matters, in prose.\n', t, count=1);open(p,'w').write(t)
PY
  bash "$SCRIPTS/define-item.sh" "$f" --touches "src/gap" --no-index >/dev/null 2>&1
  printf '%s' "$f"
}
# the owner's approval, seeded straight into the temp project's allowlist (approve-ready-when.sh needs a TTY)
seed() { local root="${SEED_ROOT:-$TMP/p}"; python3 -c 'import importlib,os,sys
sys.path.insert(0, sys.argv[1]); se = importlib.import_module("sweep-eligible")
os.makedirs(os.path.dirname(sys.argv[2]), exist_ok=True)
open(sys.argv[2], "a").write(se.cmd_hash(sys.argv[3], sys.argv[4][4:].strip()) + "\n")' "$SCRIPTS" "$HOME/.claude/aidex/ready-when-allow.txt" "$root" "$1"; }
defer_cmd() { bash "$DFR" defer "$1" --reason "${3:-r}" --ready-when "$2" --no-index >/dev/null 2>&1; seed "$2"; }
raw() { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && index($0, k": ")==1 {print substr($0, length(k)+3); exit}' "$1"; }
verdict() { python3 "$SCRIPTS/sweep-eligible.py" --json | python3 -c 'import json,sys
d=json.load(sys.stdin); print({i["id"]:i["verdict"] for i in d["deferred"]}[sys.argv[1]], end="")' "$1"; }
sect() { python3 "$SCRIPTS/sweep-eligible.py" --json | python3 -c 'import json,sys
d=json.load(sys.stdin); print(",".join(i["id"] for i in d[sys.argv[1]]), end="")' "$1"; }

echo "ready_when:"
PAST="date:2020-01-01" FUT="date:2999-01-01"
A="$(mk "past date")"; Bf="$(mk "future date")"; C="$(mk "cmd true")"; D="$(mk "cmd false")"; E="$(mk "no condition")"
bash "$DFR" defer BL-001 --reason "r1" --ready-when "$PAST" --no-index >/dev/null 2>&1
bash "$DFR" defer BL-002 --reason "r2" --ready-when "$FUT" --no-index >/dev/null 2>&1
bash "$DFR" defer BL-003 --reason "r3" --ready-when "cmd:test -f src/gap/lane.py" --no-index >/dev/null 2>&1
[[ ! -e "$ALLOWFILE" ]] && ok "defer --ready-when cmd: never writes the allowlist (an agent cannot approve)" || bad "defer wrote the allowlist"
seed "cmd:test -f src/gap/lane.py"
defer_cmd BL-004 "cmd:test -f nope.txt" r4
bash "$DFR" defer BL-005 --reason "owner answer" --no-index >/dev/null 2>&1
DEFD="$B/_deferred"
[[ "$(raw "$DEFD"/*bl-001*.md ready_when)" == "\"$PAST\"" ]] && ok "defer --ready-when writes the field" || bad "write: $(raw "$DEFD"/*bl-001*.md ready_when)"
[[ -z "$(raw "$DEFD"/*bl-005*.md ready_when)" ]] && ok "defer without --ready-when writes none" || bad "bl-005 has ready_when"
X="$(mk "format target")"   # BL-006, active: the refusal must come from the format check
for bad_v in "tomorrow" "date:2026-02-30" "cmd:" "cmd: " $'cmd:echo\ta' $'cmd:echo\ra' $'cmd:echo\na'; do
  bash "$DFR" defer BL-006 --reason x --ready-when "$bad_v" --no-index >/dev/null 2>"$TMP/e"; RC=$?
  [[ $RC -ne 0 ]] && grep -q -- "--ready-when must be" "$TMP/e" && [[ -f "$X" ]] \
    && ok "ready_when '$bad_v' is refused by the format check, item stays in the root" || bad "refuse '$bad_v': rc=$RC err=$(cat "$TMP/e")"
done

[[ "$(verdict BL-001)" == READY ]]  && ok "date in the past: READY" || bad "past: $(verdict BL-001)"
[[ "$(verdict BL-002)" == WAITING ]] && ok "date in the future: WAITING" || bad "future: $(verdict BL-002)"
[[ "$(verdict BL-003)" == READY ]]  && ok "cmd exit 0: READY" || bad "cmd0: $(verdict BL-003)"
[[ "$(verdict BL-004)" == WAITING ]] && ok "cmd exit 1: WAITING" || bad "cmd1: $(verdict BL-004)"
[[ "$(verdict BL-005)" == "ASK OWNER" ]] && ok "no ready_when: ASK OWNER" || bad "ask: $(verdict BL-005)"
OUT="$(python3 "$SCRIPTS/sweep-eligible.py")"
grep -q "^DEFERRED — condition check (5)" <<<"$OUT" && grep -q "BL-002 .*WAITING" <<<"$OUT" && grep -q "$FUT" <<<"$OUT" \
  && grep -q "blocked_by owner answer" <<<"$OUT" && ok "text output has the section, the waiting value and the blocker" || bad "text: $OUT"

# the index row shows it
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1
grep -q "ready_when: \"$FUT\"" "$B/00-index.md" && ok "index Deferred row shows ready_when" || bad "index: $(grep -n Deferred -A6 "$B/00-index.md")"

# an active item with an unmet ready_when is not eligible; a met one is
F="$(mk "active waiting")"; G="$(mk "active ready")"
python3 - "$F" "$FUT" "$G" "$PAST" <<'PY'
import sys
for p,v in ((sys.argv[1],sys.argv[2]),(sys.argv[3],sys.argv[4])):
    t=open(p).read().replace('\ntouches:', '\nready_when: "%s"\ntouches:' % v, 1); open(p,'w').write(t)
PY
[[ ",$(sect eligible)," == *",BL-007,"* ]] && bad "unmet ready_when still ELIGIBLE" || ok "active item with unmet ready_when is not ELIGIBLE"
[[ ",$(sect review)," == *",BL-007,"* && ",$(sect eligible)," == *",BL-008,"* ]] && ok "unmet goes to REVIEW, met stays ELIGIBLE" || bad "review=$(sect review) eligible=$(sect eligible)"
python3 "$SCRIPTS/sweep-eligible.py" | grep >/dev/null "waiting: $FUT" && ok "REVIEW reason reads 'waiting: <value>'" || bad "reason text"

# reactivate clears it
bash "$DFR" reactivate BL-002 --no-index >/dev/null 2>&1
R2="$(ls "$B"/*bl-002*.md 2>/dev/null)"
[[ -n "$R2" ]] && ! grep -q '^ready_when:' "$R2" && grep -q '^blocked_by: ""' "$R2" \
  && ok "reactivate removes ready_when" || bad "reactivate: ${R2:-not moved} $(grep -n ready_when "$R2")"

# --- review round: recognise-or-park, quoting, timeouts, kickoff -------------------------
sect_has() { [[ ",$(sect "$1")," == *",$2,"* ]]; }
H1="$(mk "bad form active")"; H2="$(mk "quoted cmd")"   # BL-009, BL-010 (the format target X is BL-006)
python3 - "$H1" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read().replace('\ntouches:', '\nready_when: "Date:2999-01-01"\ntouches:', 1); open(p,'w').write(t)
PY
sect_has eligible BL-009 && bad "unrecognised ready_when 'Date:2999-01-01' reached ELIGIBLE" || { sect_has review BL-009 && ok "unrecognised ready_when parks the item in REVIEW" || bad "BL-009 nowhere"; }

echo ok > flag.txt
defer_cmd BL-010 'cmd:grep -q "ok" flag.txt'
[[ "$(verdict BL-010)" == READY ]] && ok "cmd with double quotes survives yaml escaping: READY" || bad "quoted cmd: $(verdict BL-010) raw=$(raw "$DEFD"/*bl-010*.md ready_when)"
J2="$(mk "bracket cmd")"
defer_cmd BL-011 'cmd:[ "$(cat flag.txt)" = ok ]'
[[ "$(verdict BL-011)" == READY ]] && ok "cmd with an inner quoted substitution compared to an unquoted word: READY" || bad "bracket cmd: $(verdict BL-011)"
J3="$(mk "trailing quote cmd")"
defer_cmd BL-012 'cmd:test "$(cat flag.txt)" = ok && echo "done"'
[[ "$(verdict BL-012)" == READY ]] && ok "cmd ending in an escaped quote: READY" || bad "trailing quote cmd: $(verdict BL-012)"

K="$(mk "today")"; bash "$DFR" defer BL-013 --reason r --ready-when "date:$(date +%Y-%m-%d)" --no-index >/dev/null 2>&1
[[ "$(verdict BL-013)" == READY ]] && ok "date:<today> is READY (on-the-day boundary)" || bad "today: $(verdict BL-013)"

# cmd runs from the project root even when the sweep starts in a subdirectory
mkdir -p sub/deep; OUTSUB="$(cd sub/deep && python3 "$SCRIPTS/sweep-eligible.py" --json | python3 -c 'import json,sys
print({i["id"]:i["verdict"] for i in json.load(sys.stdin)["deferred"]}["BL-010"], end="")')"
[[ "$OUTSUB" == READY ]] && ok "cmd: runs from the project root when invoked from a subdirectory" || bad "subdir: $OUTSUB"

# a timed-out cmd leaves no child behind
L="$(mk "slow cmd")"; MARK="$TMP/slow-$$"
defer_cmd BL-014 "cmd:sleep 31$$ & wait"
python3 "$SCRIPTS/sweep-eligible.py" --json >/dev/null 2>&1
if pgrep -f "sleep 31$$" >/dev/null; then pkill -f "sleep 31$$"; bad "timed-out cmd left its child running"; else ok "timed-out cmd leaves no child process"; fi
[[ "$(verdict BL-014)" == WAITING ]] && ok "a timed-out cmd is WAITING, not an error" || bad "timeout verdict: $(verdict BL-014)"
rm -f "$DEFD"/*bl-014*.md   # every later sweep run would pay the 10 s timeout again

# the full waiting value is printed, not the 34-char column
LONG="date:2999-01-01-and-then-a-very-long-tail-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
python3 - "$H1" "$LONG" <<'PY'
import sys,re
p,v=sys.argv[1:3]; t=re.sub(r'^ready_when:.*$', 'ready_when: "%s"' % v, open(p).read(), count=1, flags=re.M); open(p,'w').write(t)
PY
python3 "$SCRIPTS/sweep-eligible.py" | grep >/dev/null -F "waiting: $LONG" && ok "REVIEW prints the whole waiting value" || bad "long waiting value clipped"
KO="$(bash "$SCRIPTS/sweep-kickoff.sh" --dry-run 2>&1)"; echo "$KO" > "$TMP/ko"; grep -qF "waiting: $LONG" "$TMP/ko" && ok "kickoff REVIEW prints the whole waiting value" || bad "kickoff clips waiting value"

# the kickoff the owner sees carries the deferred section
KOUT="$(bash "$SCRIPTS/sweep-kickoff.sh" --dry-run 2>&1)"
grep -q "^DEFERRED — condition check" <<<"$KOUT" && grep -q "BL-001 .*READY" <<<"$KOUT" && grep -q "BL-005 .*ASK OWNER" <<<"$KOUT" \
  && ok "kickoff --dry-run prints READY and ASK OWNER deferred rows" || bad "kickoff deferred: $KOUT"
bash "$SCRIPTS/sweep-kickoff.sh" --json 2>/dev/null | python3 -c 'import json,sys; assert json.load(sys.stdin)["deferred"]' \
  && ok "kickoff --json carries the deferred key" || bad "kickoff --json lacks deferred"

# --- round 2 ----------------------------------------------------------------------------

# deferring without --ready-when keeps a ready_when the item already carried
M="$(mk "keeps ready_when")"   # BL-015
python3 - "$M" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read().replace('\ntouches:', '\nready_when: "date:2999-01-01"\ntouches:', 1); open(p,'w').write(t)
PY
bash "$DFR" defer BL-015 --reason x --no-index >/dev/null 2>&1
[[ "$(raw "$DEFD"/*bl-015*.md ready_when)" == '"date:2999-01-01"' ]] && ok "defer without --ready-when keeps the existing ready_when" || bad "kept: $(grep -n ready_when "$DEFD"/*bl-015*.md)"

# a malformed ready_when in _deferred/ gets its own verdict and its value is shown
N="$(mk "malformed deferred")"   # BL-016
bash "$DFR" defer BL-016 --reason x --no-index >/dev/null 2>&1
python3 - "$DEFD"/*bl-016*.md <<'PY'
import sys
p=sys.argv[1]; t=open(p).read().replace('\ntouches:', '\nready_when: "Date:2020-01-01"\ntouches:', 1); open(p,'w').write(t)
PY
[[ "$(verdict BL-016)" == "BAD FORM" ]] && ok "malformed deferred ready_when: BAD FORM" || bad "bad form verdict: $(verdict BL-016)"
python3 "$SCRIPTS/sweep-eligible.py" | grep >/dev/null -F "Date:2020-01-01" && ok "sweep-eligible prints the malformed value" || bad "malformed value hidden"
bash "$SCRIPTS/sweep-kickoff.sh" --dry-run > "$TMP/ko2" 2>&1
grep -q "BL-016 .*BAD FORM" "$TMP/ko2" && ok "kickoff deferred section shows BAD FORM rows" || bad "kickoff lacks BAD FORM"

# kickoff REVIEW overflows only the waiting value, not every long reason
O="$(mk "outside repo")"   # BL-017
printf '\nbackport the fix to the boilerplate workspace and then verify it twice over.\n' >> "$O"
grep -qF "outside this repo" "$TMP/ko2" || true
bash "$SCRIPTS/sweep-kickoff.sh" --dry-run > "$TMP/ko3" 2>&1
grep -q "BL-017 .*outside this repo" "$TMP/ko3" && ! grep -qF "twice over" "$TMP/ko3" \
  && ok "a long non-waiting REVIEW reason prints no overflow line" || bad "overflow for non-waiting reason: $(grep -n 'BL-017' -A2 "$TMP/ko3")"

# --- cmd: approval (security): a cmd: runs only when the local allowlist holds its hash ---
ALLOW="$ALLOWFILE"; MK="$TMP/marker"
P="$(mk "hand written cmd")"   # BL-018: a pulled-in item nobody approved
bash "$DFR" defer BL-018 --reason r --no-index >/dev/null 2>&1
python3 - "$DEFD"/*bl-018*.md "$MK" <<'PY'
import sys
p,mk=sys.argv[1:3]; t=open(p).read().replace('\ntouches:', '\nready_when: "cmd:touch %s"\ntouches:' % mk, 1); open(p,'w').write(t)
PY
[[ "$(verdict BL-018)" == "NEEDS APPROVAL" ]] && ok "hand-written cmd: is NEEDS APPROVAL" || bad "unapproved cmd verdict: $(verdict BL-018)"
[[ ! -e "$MK" ]] && ok "the unapproved command was not run" || bad "unapproved command RAN (marker exists)"
python3 "$SCRIPTS/sweep-eligible.py" | grep >/dev/null -F "cmd:touch $MK" && ok "the command text is shown for review" || bad "command text not shown"

Q="$(mk "approved via defer")"   # BL-019
defer_cmd BL-019 "cmd:touch $MK"
[[ "$(verdict BL-019)" == READY && -e "$MK" ]] && ok "a cmd: whose hash the owner approved runs and is READY" || bad "approved cmd: $(verdict BL-019) marker=$([[ -e $MK ]] && echo yes || echo no)"
rm -f "$MK"

# the same text approved for ANOTHER project root is not approved here
R="$(mk "other root")"   # BL-020
bash "$DFR" defer BL-020 --reason r --no-index >/dev/null 2>&1
python3 - "$DEFD"/*bl-020*.md "$MK" <<'PY'
import sys
p,mk=sys.argv[1:3]; t=open(p).read().replace('\ntouches:', '\nready_when: "cmd:touch %s.other"\ntouches:' % mk, 1); open(p,'w').write(t)
PY
mkdir -p "$TMP/q/.context/backlog"
SEED_ROOT="$TMP/q" seed "cmd:touch $MK.other"    # the very same text, approved in project q
V="$(verdict BL-020)"
[[ "$V" == "NEEDS APPROVAL" && ! -e "$MK.other" ]] && ok "the same command approved in project q does not approve it in project p" || bad "other-root approval: $V marker=$([[ -e $MK.other ]] && echo ran)"

# an active item carrying an unapproved cmd: is REVIEW with the command, never ELIGIBLE, never run
T="$(mk "active hand written cmd")"   # BL-021
python3 - "$T" "$MK" <<'PY'
import sys
p,mk=sys.argv[1:3]; t=open(p).read().replace('\ntouches:', '\nready_when: "cmd:touch %s.active"\ntouches:' % mk, 1); open(p,'w').write(t)
PY
sect_has eligible BL-021 && bad "unapproved active cmd: reached ELIGIBLE" || ok "unapproved active cmd: is not ELIGIBLE"
python3 "$SCRIPTS/sweep-eligible.py" | grep >/dev/null -F "waiting: needs approval: touch $MK.active" && [[ ! -e "$MK.active" ]] \
  && ok "active item: REVIEW 'waiting: needs approval: <cmd>', not run" || bad "active approval reason / ran"
bash "$SCRIPTS/sweep-kickoff.sh" --dry-run > "$TMP/ko4" 2>&1
grep -q "BL-020 .*NEEDS APPROVAL" "$TMP/ko4" && grep -qF "cmd:touch $MK.other" "$TMP/ko4" \
  && ok "kickoff deferred section shows NEEDS APPROVAL with the command" || bad "kickoff NEEDS APPROVAL"

# the owner line: a NEEDS APPROVAL row says how, and that it is owner only
APPR="$SCRIPTS/approve-ready-when.sh"
python3 "$SCRIPTS/sweep-eligible.py" > "$TMP/se" 2>&1
grep -qF "! bash $APPR BL-020" "$TMP/se" && grep -qF "owner only: agents must not run this" "$TMP/se" && ! grep -q "defer --ready-when" "$TMP/se" \
  && ok "sweep-eligible NEEDS APPROVAL row names approve-ready-when.sh, owner only" || bad "sweep-eligible owner line: $(grep -n 'BL-020' -A2 "$TMP/se")"
grep -qF "! bash $APPR BL-020" "$TMP/ko4" && grep -qF "owner only: agents must not run this" "$TMP/ko4" \
  && ok "kickoff NEEDS APPROVAL row names approve-ready-when.sh, owner only" || bad "kickoff owner line"

# approve-ready-when.sh refuses without a terminal and writes nothing
BEFORE="$(cksum < "$ALLOW")"
bash "$APPR" BL-020 </dev/null >"$TMP/ap.out" 2>"$TMP/ap.err"; RC=$?
[[ $RC -eq 2 && "$(cksum < "$ALLOW")" == "$BEFORE" ]] && ok "approve-ready-when.sh refuses (exit 2) without a TTY, allowlist untouched" || bad "approve no-tty: rc=$RC err=$(cat "$TMP/ap.err")"

# with a pty (script(1)): n writes nothing, y appends once, a second y adds no duplicate
if command -v script >/dev/null 2>&1; then
  pty() { ( perl -e 'select(undef,undef,undef,1.0)'; printf '%s\n' "$1"; perl -e 'select(undef,undef,undef,1.0)' ) | script -q /dev/null bash "$APPR" BL-020 >"$TMP/ap.pty" 2>&1; }
  pty n
  [[ "$(cksum < "$ALLOW")" == "$BEFORE" && "$(verdict BL-020)" == "NEEDS APPROVAL" ]] && ok "answering n approves nothing" || bad "n wrote: $(cat "$TMP/ap.pty")"
  pty y; pty y
  grep -qF "touch $MK.other" "$TMP/ap.pty" && grep -qF "Approve this command for this project? [y/N]" "$TMP/ap.pty" \
    && ok "approve prints the exact command and the question" || bad "approve prompt: $(cat "$TMP/ap.pty")"
  [[ "$(verdict BL-020)" == READY && -e "$MK.other" ]] && ok "after y the command is approved: runs and is READY" || bad "after y: $(verdict BL-020)"
  [[ "$(sort "$ALLOW" | uniq -d | wc -l | tr -d ' ')" == 0 ]] && ok "approving twice adds no duplicate line" || bad "duplicate allowlist lines"
else
  echo "  SKIP: script(1) not available, the TTY approval path is untested"
fi

# --- hardening: allowlist location, control characters ---
idof() { basename "$1" | sed -E 's/^[0-9-]+(bl-[0-9]+)-.*/\1/' | tr a-z A-Z; }
# an allowlist inside the project (HOME pointed there by a repo) is never trusted
U="$(mk "repo allowlist")"; UID_="$(idof "$U")"
bash "$DFR" defer "$UID_" --reason r --ready-when "cmd:touch $MK.repo" --no-index >/dev/null 2>&1
HOME="$TMP/p/hm" seed "cmd:touch $MK.repo"
V2="$(HOME="$TMP/p/hm" verdict "$UID_")"
[[ "$V2" == "NEEDS APPROVAL" && ! -e "$MK.repo" ]] && ok "an allowlist under the project root is not trusted" || bad "repo allowlist honoured: $V2"

# control characters in a cmd: are shown escaped, never raw, and never hide the command
W="$(mk "escape sequence")"; WID="$(idof "$W")"
bash "$DFR" defer "$WID" --reason r --no-index >/dev/null 2>&1
python3 - "$(ls "$DEFD"/*"$(echo "$WID" | tr A-Z a-z)"-*.md)" <<'PY'
import sys, json
p=sys.argv[1]; v=json.dumps("cmd:echo hi\x1b[2K\rtrue\tx")
t=open(p).read().replace('\ntouches:', '\nready_when: %s\ntouches:' % v, 1); open(p,'w').write(t)
PY
python3 "$SCRIPTS/sweep-eligible.py" > "$TMP/se2" 2>&1; bash "$SCRIPTS/sweep-kickoff.sh" --dry-run > "$TMP/ko5" 2>&1
if LC_ALL=C grep -q $'[\x01-\x09\x0b-\x1f]' "$TMP/se2" "$TMP/ko5"; then bad "raw control bytes in the NEEDS APPROVAL output"; else ok "no control byte reaches sweep-eligible or kickoff output"; fi
grep -qF 'echo hi\x1b[2K\rtrue\tx' "$TMP/se2" && ok "the control characters are shown escaped" || bad "escaped form missing: $(grep -n "$WID" -A2 "$TMP/se2")"
if command -v script >/dev/null 2>&1; then
  B2="$(cksum < "$ALLOW")"
  ( perl -e 'select(undef,undef,undef,1.0)'; printf 'y\n'; perl -e 'select(undef,undef,undef,1.0)' ) | NO_COLOR=1 script -q /dev/null bash "$APPR" "$WID" >"$TMP/ap2" 2>&1; RC=$?
  [[ "$(cksum < "$ALLOW")" == "$B2" ]] && ! LC_ALL=C grep -q $'\x1b' "$TMP/ap2" && ok "approve refuses a cmd with control characters and never prints them raw" || bad "approve control chars: rc=$RC"
fi

# a hostile id never reaches the printed shell line (the id comes from front matter)
cat > "$TMP/p/.context/backlog/_deferred/2026-10-18-bl-hostile.md" <<'HX'
---
title: "hostile id"
id: "BL-77;touch /tmp/aidex-hostile-id"
status: open
priority: P3
blocked_by: "r"
ready_when: "cmd:true"
---
HX
python3 "$SCRIPTS/sweep-eligible.py" > "$TMP/hx" 2>&1
grep -q "BL-77" "$TMP/hx" && ! grep -q '! bash .*BL-77' "$TMP/hx" && ok "a non-BL-NNN id gets no runnable approve line" || bad "hostile id reached the approve line: $(grep BL-77 "$TMP/hx")"
rm -f "$TMP/p/.context/backlog/_deferred/2026-10-18-bl-hostile.md"

echo "passed=$PASS failed=$FAIL"; [[ $FAIL -eq 0 ]]
