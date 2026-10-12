#!/usr/bin/env bash
# test-define-defer-writes.sh — what define-item.sh and defer-item.sh write into an item.
#
# Owner of the write contract of the two front-matter mutators (module review 2026-10-12,
# backlog-c01 c02 c09 c10 c13 c22 c44 c52): a value lands as a valid double-quoted YAML
# scalar that reads back to the literal input, --depends stores what it validated, every
# refusal comes before any write, an ambiguous slug is refused, --help states what
# reactivate does, and a rewrite neither truncates the item nor changes its mode.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog"; cd "$TMP/p"
B="$TMP/p/.context/backlog"
reg() { bash "$SCRIPTS/register-item.sh" --origin manual --no-index "$@" 2>/dev/null; }
DEF="$SCRIPTS/define-item.sh" DFR="$SCRIPTS/defer-item.sh"
# The raw scalar text after `key: `, and its value read the way a YAML parser reads a
# double-quoted scalar (JSON's string escapes are a subset of YAML's); BAD when invalid.
raw() { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && index($0, k": ")==1 {print substr($0, length(k)+3); exit}' "$1"; }
val() { python3 -c 'import json,sys
try: print(json.loads(sys.argv[1]), end="")
except Exception: print("BAD", end="")' "$(raw "$1" "$2")"; }
mode() { ls -l "$1" | cut -c1-10; }

echo "define-item.sh / defer-item.sh writes:"
A="$(reg --title "alpha item")"; Bf="$(reg --title "bravo item")"   # BL-001, BL-002

# backlog-c01: quotes and backslashes reach the YAML scalar escaped, not raw.
V='run "make test" ok'; T='C:\new, a\b.py, x\ny'
bash "$DEF" BL-001 --verify "$V" --touches "$T" --no-index >/dev/null 2>&1
[[ "$(val "$A" verify)" == "$V" && "$(val "$A" touches)" == "$T" ]] \
  && ok "c01: --verify/--touches read back to the literal input" \
  || bad "c01: verify=$(raw "$A" verify) touches=$(raw "$A" touches)"

# backlog-c09: the stored depends is what was validated, so the merge twin resolves.
bash "$DEF" BL-001 --depends 'merge: BL-002' --no-index >/dev/null 2>&1
DEP="$(val "$A" depends)"
J="$(printf '{"eligible":[{"id":"BL-001","file":"%s","priority":"P2","estimate":"S","title":"a"},{"id":"BL-002","file":"%s","priority":"P2","estimate":"S","title":"b"}],"review":[],"needs_decision":[]}' "$(basename "$A")" "$(basename "$Bf")")"
MERGED="$(python3 "$SCRIPTS/sweep-order.py" "$B" <<<"$J" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["queue"])==1 and d["queue"][0]["merge"] and not d["needs_decision"])')"
[[ "$DEP" == "merge:BL-002" && "$MERGED" == "True" ]] \
  && ok "c09: 'merge: BL-002' is stored as merge:BL-002 and sweep-order pairs the twins" \
  || bad "c09: depends='$DEP' merged=$MERGED"

# backlog-c10: an unpadded id can never exist (ids are minted BL-%03d), so it is refused.
bash "$DEF" BL-002 --depends 'BL-5' --no-index >/dev/null 2>"$TMP/e10"; RC=$?
[[ $RC -eq 2 ]] && grep -q "invalid --depends entry 'BL-5'" "$TMP/e10" && [[ -z "$(raw "$Bf" depends)" ]] \
  && ok "c10: --depends BL-5 is refused, nothing written" \
  || bad "c10: rc=$RC depends=$(raw "$Bf" depends) err=$(cat "$TMP/e10")"

# backlog-c52: a rewrite keeps the item's mode and leaves no temp file behind ...
chmod 640 "$Bf"; bash "$DEF" BL-002 --estimate S --no-index >/dev/null 2>&1
[[ "$(mode "$Bf")" == "-rw-r-----" && -z "$(find "$B" -maxdepth 1 -type f ! -name '*.md')" ]] \
  && ok "c52: define-item keeps the item's mode, no temp left" || bad "c52: mode=$(mode "$Bf") stray=$(find "$B" -maxdepth 1 -type f ! -name '*.md')"
# ... and concurrent writers never truncate the item (lost updates need a lock: not claimed).
C="$(reg --title "charlie item")"; TRUNC=0
for _ in 1 2 3 4 5; do
  for s in internal behaviour ui ops internal behaviour ui ops internal behaviour ui ops; do
    bash "$DEF" "$C" --surface "$s" --no-index >/dev/null 2>&1 &
  done; wait
  grep -q '^id: BL-003$' "$C" || TRUNC=$((TRUNC+1))
done
[[ $TRUNC -eq 0 ]] && ok "c52: 12 concurrent define-item writers never truncate the item" || bad "c52: item truncated in $TRUNC of 5 trials"

# backlog-c02: --reason lands escaped; appending keeps an already-escaped blocked_by intact.
D="$(reg --title "delta item" --blocked-by 'has "q"')"; DID="$(awk '$1=="id:"{print $2; exit}' "$D")"
R='waiting on "vendor" C:\new'
chmod 640 "$D"
OUT="$(bash "$DFR" defer "$DID" --reason "$R" --no-index 2>/dev/null)"
[[ "$(val "$OUT" blocked_by)" == "has \"q\"; $R" ]] \
  && ok "c02: --reason reads back literally, appended to the existing blocker" \
  || bad "c02: blocked_by=$(raw "$OUT" blocked_by)"
[[ "$(mode "$OUT")" == "-rw-r-----" ]] && ok "c52: defer keeps the item's mode" || bad "c52: defer mode=$(mode "$OUT")"

# backlog-c44: reactivate clears blocked_by, and --help says so.
bash "$DFR" reactivate "$DID" --no-index >/dev/null 2>&1
H="$(bash "$DFR" --help)"
[[ -z "$(val "$D" blocked_by)" && "$H" == *"clears blocked_by"* && "$H" != *"left as-is"* ]] \
  && ok "c44: reactivate clears blocked_by and --help states it" || bad "c44: blocked_by=$(raw "$D" blocked_by) help=$(grep reactivate: <<<"$H")"

# backlog-c13: a destination collision is refused before the item is touched.
E="$(reg --title "echo item")"; EID="$(awk '$1=="id:"{print $2; exit}' "$E")"
sed -i.bak 's/^status: open$/status: doing/' "$E" && rm -f "$E.bak"
mkdir -p "$B/_deferred"; cp "$E" "$B/_deferred/"; SUM="$(cksum <"$E")"
bash "$DFR" defer "$EID" --reason "x" --no-index >/dev/null 2>"$TMP/e13"; RC=$?
[[ $RC -eq 2 && "$(cksum <"$E")" == "$SUM" ]] && grep -q "_deferred collision" "$TMP/e13" \
  && ok "c13: defer refuses a _deferred collision without rewriting the item" || bad "c13: defer rc=$RC, item changed: $(grep -E '^(status|blocked_by):' "$E")"
rm -f "$E"; cp "$B/_deferred/$(basename "$E")" "$E"
sed -i.bak 's/^blocked_by: .*/blocked_by: "vendor"/' "$B/_deferred/$(basename "$E")" && rm -f "$B/_deferred/$(basename "$E").bak"
SUM="$(cksum <"$B/_deferred/$(basename "$E")")"
bash "$DFR" reactivate "$EID" --no-index >/dev/null 2>"$TMP/e13r"; RC=$?
[[ $RC -eq 2 && "$(cksum <"$B/_deferred/$(basename "$E")")" == "$SUM" ]] && grep -q "active collision" "$TMP/e13r" \
  && ok "c13: reactivate refuses an active collision without rewriting the item" || bad "c13: reactivate rc=$RC, deferred item changed"
rm -f "$B/_deferred/$(basename "$E")"

# backlog-c22: a slug matching two items is refused naming both; a unique match still works.
L1="$(reg --title "login form validation")"; L2="$(reg --title "login rate limit")"
bash "$DFR" defer login --reason "x" --no-index >/dev/null 2>"$TMP/e22"; RC=$?
[[ $RC -eq 2 && -f "$L1" && -f "$L2" ]] && grep -q "$(basename "$L1")" "$TMP/e22" && grep -q "$(basename "$L2")" "$TMP/e22" \
  && ok "c22: an ambiguous slug is refused naming both items, nothing moved" || bad "c22: rc=$RC err=$(cat "$TMP/e22")"
bash "$DFR" defer rate-limit --reason "x" --no-index >/dev/null 2>&1 && [[ -f "$B/_deferred/$(basename "$L2")" ]] \
  && ok "c22: a slug matching one item still resolves" || bad "c22: unique slug did not resolve"
# The end-of-name step is anchored on the slug's hyphen: `login` is one item next to
# `relogin`, and `it` (a substring of many names) never lands on `...-limit.md` alone.
L3="$(reg --title "login")"; L4="$(reg --title "relogin")"
bash "$DFR" defer login --reason "x" --no-index >/dev/null 2>"$TMP/e22b"; RC=$?
[[ $RC -eq 0 && -f "$B/_deferred/$(basename "$L3")" && -f "$L4" ]] \
  && ok "c22: slug 'login' resolves to the -login item, not -relogin" || bad "c22: rc=$RC err=$(cat "$TMP/e22b")"
L5="$(reg --title "login rate limit")"
bash "$DFR" defer it --reason "x" --no-index >/dev/null 2>"$TMP/e22c"; RC=$?
[[ $RC -eq 2 && -f "$L5" && -f "$A" ]] && grep -q "$(basename "$L5")" "$TMP/e22c" && grep -q "$(basename "$A")" "$TMP/e22c" \
  && ok "c22: 'it' is a substring of several names: refused naming them, nothing moved" || bad "c22: rc=$RC err=$(cat "$TMP/e22c")"

# backlog-c02 (append): an already-corrupted quoted blocked_by is repaired, not carried raw.
F="$(reg --title "foxtrot item")"; FID="$(awk '$1=="id:"{print $2; exit}' "$F")"
sed -i.bak 's/^blocked_by: .*/blocked_by: "waiting on "vendor" C:"/' "$F" && rm -f "$F.bak"
OUT="$(bash "$DFR" defer "$FID" --reason "next" --no-index 2>/dev/null)"
[[ "$(val "$OUT" blocked_by)" == 'waiting on "vendor" C:; next' ]] \
  && ok "c02: appending to a raw-quoted blocked_by yields a valid scalar" || bad "c02: blocked_by=$(raw "$OUT" blocked_by)"

# backlog-c52: a failed copy leaves no hidden temp next to the item.
G="$(reg --title "golf item")"; chmod 000 "$G"
bash "$DEF" "$G" --estimate S --no-index >/dev/null 2>&1; RC=$?; chmod 644 "$G"
[[ $RC -ne 0 && -z "$(find "$B" -maxdepth 1 -type f ! -name '*.md')" ]] \
  && ok "c52: a failed rewrite removes its temp file" || bad "c52: rc=$RC stray=$(find "$B" -maxdepth 1 -type f ! -name '*.md')"

echo "passed=$PASS failed=$FAIL"; [[ $FAIL -eq 0 ]]
