#!/usr/bin/env bash
# test-close-item-bl926.sh — BL-926: reproduced close-item.sh defects, one block each, plus
# the start-item / defer-item sibling rows that carried the same defect shape. Layer: script,
# temp fixtures only; each cell runs the real script. Owned elsewhere: the park field writes
# (test-verification-gate.sh), sweep-report.py's reader (test-sweep-report.sh), migrate-ids
# (test-migrate-ids.sh).
#   1 a relative or symlinked path to an active item is that item (header: "<... | path>")
#   2 --commit HEAD (any ref name) records the commit it names in the CALLER's repo
#   3 an escaped \| inside a Verification cell is cell text, not a separator
#   4 a colon-aligned separator row (:---, ---:, :---:) is not a data row
#   5 a row with an empty kind but a criterion is refused, not skipped
#   7 a failed front-matter rewrite never reports success: exit non-zero, item untouched
#   8 the warn-only RED/GREEN reader of a type: bug item cannot abort a close half-way,
#     whether it fails on a non-UTF-8 byte or python3 itself fails
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
G() { git -c user.email=t@t -c user.name=t "$@"; }
TODAY="$(date +%Y-%m-%d)"

W="$TMP/ws"; B="$W/.context/backlog"; A="$B/_archive"
mkdir -p "$B"; G -C "$W" init -q -b main; echo a > "$W/a"; G -C "$W" add a; G -C "$W" commit -qm base
item() { # item <id> <type> <verification rows> [extra front-matter line] -> prints the path
  local f="$B/bl-$1-x.md"
  printf -- '---\ntitle: "x"\nid: BL-%s\nstatus: open\ncreated: 2026-10-02\nupdated: 2026-10-02\npriority: P3\ntype: %s\nsurface: internal\ncommits: ""\n%s---\n\n# x\n\n## Verification\n| kind | what | proof |\n|---|---|---|\n%s\n\n## Notes\n' \
    "$1" "$2" "${4:+$4
}" "$3" > "$f"
  printf '%s\n' "$f"
}
close() { (cd "$W" && NO_COLOR=1 bash "$SCRIPTS/close-item.sh" "$@" --no-index); }
fm() { awk -v k="$2" '/^---/{c++; if(c==2)exit} c==1 && $1==k":"{sub(/^[^:]*:[[:space:]]*/,""); print}' "$1"; }
PROVEN='| test | it works | 3 passed |' n2=0 n3=0

echo "1 path forms:"
F="$(item 101 improvement "$PROVEN")"
close .context/backlog/bl-101-x.md >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 0 && -f "$A/bl-101-x.md" && ! -e "$F" ]] && ok "relative path closes and archives" || bad "relative path: rc=$RC $(cat "$TMP/err")"
F="$(item 102 improvement "$PROVEN")"; ln -s "$B" "$W/blink"
close blink/bl-102-x.md >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 0 && -f "$A/bl-102-x.md" && ! -e "$F" ]] && ok "path through a symlinked directory closes into the real _archive/" || bad "symlinked path: rc=$RC $(cat "$TMP/err")"
mkdir -p "$W/elsewhere"; F="$(item 103 improvement "$PROVEN")"; mv "$F" "$W/elsewhere/"
close elsewhere/bl-103-x.md >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 && -f "$W/elsewhere/bl-103-x.md" && ! -e "$A/bl-103-x.md" ]] && ok "control: a same-named file outside backlog/ is still refused" || bad "outside file: rc=$RC"
close .context/backlog/_archive/bl-101-x.md >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 && -f "$A/bl-101-x.md" ]] && ok "control: a path into _archive/ is still refused" || bad "archive path: rc=$RC"
# siblings: start-item and defer-item carried the same textual directory comparison
F="$(item 104 improvement "$PROVEN")"
(cd "$W" && bash "$SCRIPTS/start-item.sh" .context/backlog/bl-104-x.md --no-index >/dev/null 2>"$TMP/err"); RC=$?
[[ $RC -eq 0 && "$(fm "$F" status)" == doing ]] && ok "start-item: relative path starts the item" || bad "start-item relative: rc=$RC $(cat "$TMP/err")"
(cd "$W" && bash "$SCRIPTS/defer-item.sh" defer .context/backlog/bl-104-x.md --reason "waits" --no-index >/dev/null 2>"$TMP/err"); RC=$?
[[ $RC -eq 0 && -f "$B/_deferred/bl-104-x.md" ]] && ok "defer-item defer: relative path defers the item" || bad "defer relative: rc=$RC $(cat "$TMP/err")"
(cd "$W" && bash "$SCRIPTS/defer-item.sh" reactivate .context/backlog/_deferred/bl-104-x.md --no-index >/dev/null 2>"$TMP/err"); RC=$?
[[ $RC -eq 0 && -f "$F" && ! -e "$B/_deferred/bl-104-x.md" ]] && ok "defer-item reactivate: relative path reactivates the item" || bad "reactivate relative: rc=$RC $(cat "$TMP/err")"

echo "2 --commit records a commit, not a ref name:"
SHORT="$(G -C "$W" rev-parse --short HEAD)"; FULL="$(G -C "$W" rev-parse HEAD)"
for c in "HEAD:$SHORT" "main:$SHORT" "$FULL:$FULL" "${FULL:0:7}:${FULL:0:7}"; do
  ref="${c%%:*}" want="${c#*:}"; n2=$((n2+1)); F="$(item 2$n2 improvement "$PROVEN")"
  close "BL-2$n2" --commit "$ref" >/dev/null 2>"$TMP/err"; RC=$?
  got="$(fm "$A/$(basename "$F")" commits 2>/dev/null)"
  [[ $RC -eq 0 && "$got" == "\"$want\"" ]] && ok "--commit $ref stored as $want" || bad "--commit $ref: rc=$RC commits=$got $(cat "$TMP/err")"
done
# split workspace whose root is itself a repo: a ref names a commit of the repo the caller
# is IN, never the first searched repo that happens to have a ref of that name
SW="$TMP/split"; mkdir -p "$SW/code" "$SW/.context/backlog"; G -C "$SW" init -q -b main; G -C "$SW" commit -q --allow-empty -m ws
G -C "$SW/code" init -q -b main; G -C "$SW/code" commit -q --allow-empty -m code; G -C "$SW/code" tag v1
swclose() { # swclose <id> <cwd> <ref>: an item in the split workspace, closed from <cwd>
  cp "$(item "$1" improvement "$PROVEN")" "$SW/.context/backlog/"; rm -f "$B/bl-$1-x.md"
  (cd "$2" && NO_COLOR=1 bash "$SCRIPTS/close-item.sh" "BL-$1" --commit "$3" --no-index >/dev/null 2>"$TMP/err")
}
CODE_HEAD="$(G -C "$SW/code" rev-parse --short HEAD)"; WS_HEAD="$(G -C "$SW" rev-parse --short HEAD)"
swclose 297 "$SW/code" HEAD; RC=$?; got="$(fm "$SW/.context/backlog/_archive/bl-297-x.md" commits 2>/dev/null)"
[[ $RC -eq 0 && "$got" == "\"$CODE_HEAD\"" ]] && ok "split: --commit HEAD from code/ stores code's HEAD $CODE_HEAD" || bad "split HEAD from code/: rc=$RC commits=$got (code $CODE_HEAD, workspace $WS_HEAD) $(cat "$TMP/err")"
swclose 298 "$SW/code" v1; RC=$?; got="$(fm "$SW/.context/backlog/_archive/bl-298-x.md" commits 2>/dev/null)"
[[ $RC -eq 0 && "$got" == "\"$CODE_HEAD\"" ]] && ok "split: --commit v1 from code/ stores the sub-repo's $CODE_HEAD" || bad "split v1 from code/: rc=$RC commits=$got $(cat "$TMP/err")"
swclose 299 "$SW" v1; RC=$?
[[ $RC -eq 2 && -f "$SW/.context/backlog/bl-299-x.md" ]] && grep -q 'ref name' "$TMP/err" && ok "split: --commit v1 from the root (no such ref there) is refused, item untouched" || bad "split v1 from root: rc=$RC $(cat "$TMP/err")"

sweep() { # sweep <label> <expect: closes|refused> <rows> [message fragment]
  local f id rc; n3=$((n3+1)); f="$(item 3$n3 improvement "$3")"; id="BL-3$n3"
  close "$id" --sweep >/dev/null 2>"$TMP/err"; rc=$?
  if [[ "$2" == closes ]]; then
    [[ $rc -eq 0 && -f "$A/$(basename "$f")" ]] && ok "$1: closes" || bad "$1: expected to close, rc=$rc $(cat "$TMP/err")"
  else
    [[ $rc -eq 2 && -f "$f" ]] && grep -qF -- "$4" "$TMP/err" && ok "$1: refused ($4)" || bad "$1: expected refusal '$4', rc=$rc $(cat "$TMP/err")"
  fi
}
echo "3 escaped pipe:"
sweep "escaped pipe in what, empty proof" refused '| test | output of grep foo \| wc -l | |' "empty proof cell"
sweep "the refusal names the cell with its literal pipe" refused '| test | output of grep foo \| wc -l | |' "- test: output of grep foo | wc -l"
sweep "escaped pipe in what, real proof" closes '| test | output of grep foo \| wc -l | 3 passed |'
sweep "escaped pipe in the proof" closes '| test | it works | grep -c x \| 3 |'
echo "4 alignment separators:"
sweep "a :---|:---:|---: separator row" closes "|:---|:---:|---:|
$PROVEN"
sweep "kind ':' is no separator" refused "| : | x | 1 passed |
$PROVEN" "kind ':'"
sweep "kind '-:-' is no separator" refused "| -:- | x | 1 passed |
$PROVEN" "kind '-:-'"
echo "5 empty kind:"
sweep "empty kind with a criterion" refused "| | login works | not run |
$PROVEN" "kind ''"

honest() { # honest <label> <rc> <file> <content before> <stdout> <success word>
  if [[ $2 -eq 0 ]]; then bad "$1: reported success (exit 0, '$(head -1 <<<"$5")') on a failed rewrite"
  else
    [[ "$(cat "$3")" == "$4" && ! -e "$3.tmp" && "$5" != *"$6"* ]] && ok "$1: exit $2, item byte-identical, no .tmp, no '$6'" || bad "$1: rc=$2 but item mutated, .tmp left or '$6' printed"
  fi
}
echo "7 a failed front-matter rewrite is not a close:"
F="$(item 701 improvement "$PROVEN")"; printf 'caf\351\n' >> "$F"; BEFORE="$(cat "$F")"
OUT="$(cd "$W" && LC_ALL=en_US.UTF-8 NO_COLOR=1 bash "$SCRIPTS/close-item.sh" BL-701 --no-index --reason r 2>&1)"; RC=$?
if [[ $RC -eq 0 && -f "$A/bl-701-x.md" && "$(fm "$A/bl-701-x.md" status)" == done ]]; then ok "non-UTF-8 byte: this awk copes, the close is real"
else honest "non-UTF-8 byte in the body" "$RC" "$F" "$BEFORE" "$OUT" "Closed"; fi
# siblings, same `awk > tmp && mv` shape: an unwritable backlog dir makes the redirect fail
F="$(item 702 improvement "$PROVEN
| owner | wording | |")"; BEFORE="$(cat "$F")"; chmod a-w "$B"
OUT="$(close BL-702 --sweep 2>/dev/null)"; RC=$?; chmod u+w "$B"
honest "park in an unwritable dir" "$RC" "$F" "$BEFORE" "$OUT" "parked:"
F="$(item 703 improvement "$PROVEN")"; BEFORE="$(cat "$F")"; chmod a-w "$B"
OUT="$(cd "$W" && NO_COLOR=1 bash "$SCRIPTS/start-item.sh" BL-703 --no-index 2>&1)"; RC=$?; chmod u+w "$B"
honest "start-item in an unwritable dir" "$RC" "$F" "$BEFORE" "$OUT" "Started"
F="$(item 705 improvement "$PROVEN")"; printf 'caf\351\n' >> "$F"; BEFORE="$(cat "$F")"
OUT="$(cd "$W" && LC_ALL=en_US.UTF-8 NO_COLOR=1 bash "$SCRIPTS/start-item.sh" BL-705 --no-index 2>&1)"; RC=$?
if [[ $RC -eq 0 && "$(fm "$F" status)" == doing ]]; then ok "start-item, non-UTF-8 byte: this awk copes, the start is real"
else honest "start-item, non-UTF-8 byte in the body" "$RC" "$F" "$BEFORE" "$OUT" "Started"; fi
# the main close rewrite on any awk: unwritable dir (the redirect fails)...
F="$(item 706 improvement "$PROVEN")"; BEFORE="$(cat "$F")"; mkdir -p "$A"; chmod a-w "$B"
OUT="$(close BL-706 --reason r 2>&1)"; RC=$?; chmod u+w "$B"
honest "main close in an unwritable dir" "$RC" "$F" "$BEFORE" "$OUT" "Closed"
# ...and an awk that fails AFTER the tmp exists (a shim: partial output into a regular-file
# stdout, then exit 2), so the cleanup of a partial .tmp is what is asserted
SHIM="$TMP/shim"; mkdir -p "$SHIM"; REAL_AWK="$(command -v awk)"
printf '#!/bin/sh\nif [ -f /dev/stdout ]; then echo partial; exit 2; fi\nexec %s "$@"\n' "$REAL_AWK" > "$SHIM/awk"; chmod +x "$SHIM/awk"
F="$(item 707 improvement "$PROVEN")"; BEFORE="$(cat "$F")"
OUT="$(PATH="$SHIM:$PATH" close BL-707 --reason r 2>&1)"; RC=$?
honest "main close, awk fails mid-write" "$RC" "$F" "$BEFORE" "$OUT" "Closed"
F="$(item 708 improvement "$PROVEN
| owner | wording | |")"; BEFORE="$(cat "$F")"
OUT="$(PATH="$SHIM:$PATH" close BL-708 --sweep --reason r 2>&1)"; RC=$?
honest "park, awk fails mid-write" "$RC" "$F" "$BEFORE" "$OUT" "parked:"
F="$(item 709 improvement "$PROVEN")"; BEFORE="$(cat "$F")"
OUT="$(cd "$W" && PATH="$SHIM:$PATH" NO_COLOR=1 bash "$SCRIPTS/start-item.sh" BL-709 --no-index 2>&1)"; RC=$?
honest "start-item, awk fails mid-write" "$RC" "$F" "$BEFORE" "$OUT" "Started"

echo "8 the bug-proof reader cannot half-close:"
F="$(item 801 bug "$PROVEN")"; printf '<!-- RED then GREEN -->\ncaf\351\n' >> "$F"
ERR="$(cd "$W" && LC_ALL=C NO_COLOR=1 bash "$SCRIPTS/close-item.sh" BL-801 --no-index 2>&1 >/dev/null)"; RC=$?
[[ $RC -eq 0 && -f "$A/bl-801-x.md" && ! -e "$F" && ! -e "$F.tmp" ]] && ok "type: bug item with a non-UTF-8 byte closes and archives" || bad "bug item: rc=$RC active=$([[ -e "$F" ]] && fm "$F" status) $ERR"
[[ "$ERR" == *"no RED->GREEN proof"* ]] && ok "...and RED/GREEN inside its HTML comment still does not count as proof" || bad "warning missing: $ERR"
F="$(item 802 bug "$PROVEN")"; printf 'RED: failed, then GREEN: passed\ncaf\351\n' >> "$F"
ERR="$(cd "$W" && LC_ALL=C NO_COLOR=1 bash "$SCRIPTS/close-item.sh" BL-802 --no-index 2>&1 >/dev/null)"; RC=$?
[[ $RC -eq 0 && -f "$A/bl-802-x.md" && "$ERR" != *"no RED->GREEN proof"* ]] && ok "...and its RED/GREEN body line is still read as proof (no false warning)" || bad "bug item with proof: rc=$RC $ERR"
# python3 itself failing (missing, broken) is a warn-only step failing: the close goes on.
# The exit code is not asserted: the companion move AFTER the archive (scan_artifact_anchors,
# _lib.sh) needs python3 too and still fails the run once the item is archived.
PYSHIM="$TMP/pyshim"; mkdir -p "$PYSHIM"; printf '#!/bin/sh\nexit 127\n' > "$PYSHIM/python3"; chmod +x "$PYSHIM/python3"
F="$(item 803 bug "$PROVEN")"
ERR="$(cd "$W" && PATH="$PYSHIM:$PATH" NO_COLOR=1 bash "$SCRIPTS/close-item.sh" BL-803 --no-index 2>&1 >/dev/null)"; RC=$?
[[ -f "$A/bl-803-x.md" && "$(fm "$A/bl-803-x.md" status)" == done && ! -e "$F" && "$ERR" == *"no RED->GREEN proof"* ]] && ok "python3 failing: the bug item is not half-closed (archived as done) and warns" || bad "python3 failing: rc=$RC active=$([[ -e "$F" ]] && fm "$F" status) $ERR"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — close-item BL-926: $PASS cells"; exit 0; }; echo "$PASS ok, $FAIL failed"; exit 1
