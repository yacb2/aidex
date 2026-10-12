#!/usr/bin/env bash
# test-register-define.sh — a registration can leave an item DEFINED (BL-273).
#
# register-item.sh could write five of the six contract fields and no body, and said
# nothing at the end, so BL-271/BL-272 — registered with everything the registrar knew —
# still read "underdefined: touches" at the next kickoff. Now --touches/--depends go
# through define-item.sh (its validation, not a copy), --context/--acceptance fill the
# body, and every registration ends with define-check.py's verdict on stderr with the
# exact command that completes it. Nothing became mandatory: a bare stub still registers.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REG="$SCRIPTS/register-item.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
fm()  { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog"; cd "$TMP/p"

echo "register-item.sh leaves an item defined (BL-273):"
F="$(bash "$REG" --origin manual --title "six fields" --type improvement --priority P2 --estimate S \
      --surface ops --verify "the verdict prints" --touches "scripts/a.sh, scripts/b.sh" \
      --depends "BL-001, merge:BL-002" --context "Why this matters, in prose long enough to count." \
      --acceptance "first criterion" --acceptance "second criterion" 2>"$TMP/err")"
[[ -f "$F" ]] && ok "registered; stdout is still the path" || bad "no file: $F"
[[ "$(fm "$F" touches)" == "scripts/a.sh, scripts/b.sh" ]] && ok "--touches written via define-item.sh" || bad "touches: '$(fm "$F" touches)'"
[[ "$(fm "$F" depends)" == "BL-001, merge:BL-002" ]] && ok "--depends written via define-item.sh" || bad "depends: '$(fm "$F" depends)'"
[[ "$(fm "$F" verify)" == "the verdict prints" && "$(fm "$F" estimate)" == "S" ]] && ok "verify/estimate survive the positional hand-off" || bad "verify/estimate lost"
grep -q '^Why this matters' "$F" && ok "--context replaces the template prompt" || bad "context not written"
grep -q '^- first criterion$' "$F" && grep -q '^- second criterion$' "$F" && ok "--acceptance is repeatable, one bullet each" || bad "acceptance bullets missing"
grep -q 'concrete, verifiable criterion' "$F" && bad "the empty template bullet survived next to real criteria" || ok "the template's empty bullet is gone"
python3 "$SCRIPTS/define-check.py" BL-001 >/dev/null 2>&1 && ok "define-check exit 0: DEFINED in one step" || bad "define-check still reports underdefined"
grep -q 'definition: BL-001 is defined' "$TMP/err" && ok "verdict printed at the end of registration (stderr)" || bad "no verdict line: $(cat "$TMP/err")"

S="$(bash "$REG" --origin manual --title "bare stub" 2>"$TMP/err2")"
[[ -f "$S" ]] && ok "a bare stub still registers (commit-hook / sweep paths keep working)" || bad "bare stub refused"
grep -q 'definition: BL-002 is UNDERDEFINED — missing: verify, touches, Context, Acceptance' "$TMP/err2" \
  && ok "verdict names every missing field" || bad "verdict: $(cat "$TMP/err2")"
grep -q 'define-item.sh BL-002 --verify "<verify>" --touches "<touches>"' "$TMP/err2" \
  && ok "verdict carries the exact define-item.sh command" || bad "no command line: $(cat "$TMP/err2")"
grep -q 'edit ## Context and ## Acceptance in ' "$TMP/err2" && ok "body gaps point at the file" || bad "body hint missing"

if bash "$REG" --origin manual --title "bad depends" --depends "nope" >/dev/null 2>"$TMP/err3"; then bad "a malformed --depends was accepted"
else
  [[ $? -eq 2 ]] && grep -q "invalid --depends entry 'nope'" "$TMP/err3" && ok "malformed --depends is define-item.sh's error, exit 2" || bad "wrong exit/message: $(cat "$TMP/err3")"
  ls .context/backlog/*bad-depends* >/dev/null 2>&1 && bad "the rejected entry survived on disk" || ok "the rejected entry is rolled back"
fi

D="$(bash "$REG" --origin manual --title "done on arrival" --status done 2>"$TMP/err4")"; RC=$?
grep -q 'definition:' "$TMP/err4" && bad "a done item got a verdict (define-check only scans open/doing)" || ok "no verdict for a done/dropped registration"
# backlog-c25: a closed-on-arrival item lands in _archive/ (D-10), where the index's
# Closed section lists it; in the active root the index skipped it entirely.
for st in done dropped; do
  [[ $st == dropped ]] && { D="$(bash "$REG" --origin manual --title "dropped on arrival" --status dropped 2>/dev/null)"; RC=$?; }
  DID="$(fm "$D" id)"
  [[ $RC -eq 0 && "$D" == "$(pwd -P)/.context/backlog/_archive/"*"-$(printf '%s' "$DID" | tr 'A-Z' 'a-z')-$st-on-arrival.md" && -f "$D" ]] \
    && grep -qF -- "- **$DID** · [$st on arrival](_archive/$(basename "$D")) — $st" .context/backlog/00-index.md \
    && ok "--status $st registers into _archive/ and the index lists it under Closed" \
    || bad "--status $st: rc=$RC path=$D index: $(grep -n "on arrival" .context/backlog/00-index.md)"
  # The --escalate-to source stub carries the same status, so it is archived the same way.
  mkdir -p "$TMP/tgt-$st/.context/backlog"
  OUT="$(bash "$REG" --origin manual --title "routed $st" --status "$st" --escalate-to "$TMP/tgt-$st" 2>/dev/null)"; RC=$?
  E="$(printf '%s\n' "$OUT" | sed -n 1p)"; EID="$(fm "$E" id)"
  [[ $RC -eq 0 && "$E" == "$(pwd -P)/.context/backlog/_archive/"*"-$(printf '%s' "$EID" | tr 'A-Z' 'a-z')-routed-$st.md" && -f "$E" ]] \
    && grep -qF -- "- **$EID** · [routed $st](_archive/$(basename "$E")) — $st → tgt-$st/BL-001" .context/backlog/00-index.md \
    && ok "--escalate-to --status $st puts the source stub in _archive/, listed under Closed with its link" \
    || bad "--escalate-to --status $st: rc=$RC source=$E index: $(grep -n "routed" .context/backlog/00-index.md)"
  # --touches/--depends hand the new path to define-item.sh: an _archive/ path is written too.
  T="$(bash "$REG" --origin manual --title "closed with fields $st" --status "$st" --touches "scripts/a.sh" --depends "BL-001" 2>/dev/null)"; RC=$?
  [[ $RC -eq 0 && "$T" == "$(pwd -P)/.context/backlog/_archive/"* && "$(fm "$T" touches)" == "scripts/a.sh" && "$(fm "$T" depends)" == "BL-001" ]] \
    && ok "--status $st with --touches/--depends writes both fields on the _archive/ item" \
    || bad "--status $st with --touches/--depends: rc=$RC path=$T touches='$(fm "$T" touches 2>&1)' depends='$(fm "$T" depends 2>&1)'"
done

echo "passed=$PASS failed=$FAIL"; [[ $FAIL -eq 0 ]]
