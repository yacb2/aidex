#!/usr/bin/env bash
# test-consult-spec-trace.sh — BL-569: check-artifact fails (a) a built page that
# omits an item its `<stem>.spec.md` declares, and (b) a page that shows an item
# as Decided when the saved reply has no block for it.
#
# Layer: integration over the real spec_build.py / save-reply.sh / check-artifact.sh
# (the pieces share the files beside the page, so mocking any of them would
# test the mock). Owner decision C4 of the 2026-10-01 insights-suite critique:
# one rebuild listed 14 unanswered questions under "Decided"; another omitted a
# new question. The brief itself is never on disk — only the spec is checkable.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SKILL/scripts/check-artifact.sh"
BUILD="$SKILL/scripts/spec_build.py"
SAVE_REPLY="$SKILL/scripts/save-reply.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

D="$TMP/proj/.context/reports"; mkdir -p "$D"
PAGE="$D/consult.html"; SPEC="$D/consult.spec.md"

spec() {  # $1 = decided verdict for Q1, $2 = for Q2 (empty = open), $3 = extra item
  cat > "$SPEC" <<SP
::: masthead {visual="none: two short questions, nothing to draw" title="Dos preguntas"}
Una decision y una pregunta.
:::

::: group {#G1 title="Lo que falta cerrar"}
::: item {#${IDA:-Q1} title="¿Cerramos el item ahora?"${1:+ decided="$1"}}
¿Cerramos el item ahora o lo dejamos para otra ronda?

- Sí: cerrarlo ahora {recommended}
- No: dejarlo para otra ronda
:::

::: item {#${IDB:-Q2} title="¿Aplazamos el segundo item?"${2:+ decided="$2"}${4:+ dropped="$4"}}
¿Aplazamos el segundo item a la próxima ronda?

- Sí: aplazarlo {recommended}
- No — intentarlo ahora
:::
${3:-}:::

::: notes {title="Notas generales"}
:::
SP
}
build() { python3 "$BUILD" "$SPEC" -o "$PAGE" "$@" > "$TMP/build.out" 2>&1; }

# 1. a correct page passes
spec "" ""
build && bash "$CHECK" "$PAGE" >"$TMP/o" 2>&1 \
  && ok "1. a page built from its spec, nothing decided, passes" \
  || fail "1. $(cat "$TMP/build.out" "$TMP/o")"

# 2. (a) a spec item the built page omits. Own page: ids never leave a baseline.
PAGE="$D/other.html"; SPEC="$D/other.spec.md"
spec "" ""
build
spec "" "" '
::: item {#Q3 title="¿Un tercer item?"}
¿Hacemos un tercer item?

- Sí: hacerlo {recommended}
- No: omitirlo
:::
'
out="$(bash "$CHECK" "$PAGE" 2>&1)"; rc=$?
[[ "$rc" == "1" ]] && grep -q 'consult-spec-items.*Q3' <<<"$out" \
  && ok "2. (a) a spec item missing from the page FAILS, naming Q3" \
  || fail "2. rc=$rc out=$out"
PAGE="$D/consult.html"; SPEC="$D/consult.spec.md"

# 3. (b) Q2 shown Decided while the reply only answered Q1
spec "" ""
build
printf '### Q1 · ¿Cerramos el item ahora?\n\n- Sí: cerrarlo ahora\n' \
  | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "3. save-reply.sh failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ! grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "3. (b) Q2 Decided with no reply block FAILS the build, naming Q2 only" \
  || fail "3. rc=$rc out=$(cat "$TMP/build.out")"

# 4. the reply names Q2 too: the same rebuild passes
printf '### Q1 · ¿Cerramos el item ahora?\n\n- Sí: cerrarlo ahora\n\n### Q2 · ¿Aplazamos el segundo item?\n\n- No: intentarlo ahora\n' \
  | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "4. save-reply.sh failed"
build && ok "4. with a reply block for each decided item the build passes" \
  || fail "4. $(cat "$TMP/build.out")"

# 5. an item decided in the answered snapshot is exempt from the next reply
printf '### notes · Notas\n\nnada\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null
build && bash "$CHECK" "$PAGE" >/dev/null 2>&1 \
  && ok "5. items decided in an earlier round need no block in the latest reply" \
  || fail "5. $(cat "$TMP/build.out")"

# 6. no spec beside the page: nothing to compare. A NO-CRASH GUARD, not a
#    regression: the silence is also what the check does when absent.
rm -f "$SPEC"
out="$(bash "$CHECK" "$PAGE" 2>&1)"; rc=$?
[[ "$rc" == "0" ]] && ! grep -q 'consult-spec-items' <<<"$out" \
  && ok "6. (no-crash guard) no spec beside the page passes without a finding" \
  || fail "6. rc=$rc out=$out"

# Each of the rows below owns a fresh page: ids never leave a baseline.
newpage() { PAGE="$D/$1.html"; SPEC="$D/$1.spec.md"; }

# 7. a reply given in chat format (`Q1: ...`) counts as the reply to Q1
newpage chat
spec "" ""; build
printf 'Q1: Sí: cerrarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "7. save-reply.sh failed"
spec "Sí" ""
build && ok "7. a chat-format reply (Q1: ...) lets Q1 be decided" \
  || fail "7. $(cat "$TMP/build.out")"

# 8. a dropped item needs no reply block
newpage dropped
spec "" ""; build
printf 'Q1: Sí: cerrarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "8. save-reply.sh failed"
spec "Sí" "" "" "ya-no-aplica"
build && ok "8. Q1 answered, Q2 dropped= : no reply block needed for Q2" \
  || fail "8. $(cat "$TMP/build.out")"

# 9. no reply saved at all: the baseline shows Q2 was open, so deciding it FAILS
newpage noreply
spec "" ""; build
spec "" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ok "9. Q2 decided with no saved reply at all FAILS, naming Q2" \
  || fail "9. rc=$rc out=$(cat "$TMP/build.out")"

# 10. a block holding only a marker line does not decide the item
newpage marker
spec "" ""; build
printf '### Q1 · ¿Cerramos?\n\n- Sí: cerrarlo ahora\n\n### Q2 · x\n\n- [show-me]\n' \
  | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "10. save-reply.sh failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ! grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "10. a marker-only reply block does not decide Q2 (Q1 still passes)" \
  || fail "10. rc=$rc out=$(cat "$TMP/build.out")"

# 11. a [provisional] answer does not decide the item either
newpage prov
spec "" ""; build
printf 'Q1: Sí: cerrarlo ahora [provisional]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "11. save-reply.sh failed"
spec "Sí" ""
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "11. a [provisional] answer does not decide Q1" \
  || fail "11. rc=$rc out=$(cat "$TMP/build.out")"

# 12. the verb's BuildFailed message names the failing check (fix 6)
newpage verb
spec "" ""; build
out="$(python3 "$SKILL/scripts/spec_verbs.py" decide "$SPEC" --id Q2 --verdict No --out "$PAGE" 2>&1)"; rc=$?
[[ "$rc" != "0" ]] && grep -q 'exited 1.*failing check: FAIL \[consult-decided-trace\]' <<<"$out" \
  && ok "12. spec_verbs decide with no reply names consult-decided-trace in its error" \
  || fail "12. rc=$rc out=$out"

# 13. (a) item added AFTER the last reply, then decided: the answered snapshot
#     never had it, the baseline did and it was open -> needs its own reply.
newpage h1
spec "" ""; build
printf 'Q1: Sí: cerrarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "13. save-reply.sh failed"
Q3='
::: item {#Q3 title="¿Un tercer item?"}
¿Hacemos un tercer item?

- Sí: hacerlo {recommended}
- No: omitirlo
:::
'
spec "" "" "$Q3"; build || fail "13. adding Q3 failed: $(cat "$TMP/build.out")"
Q3D="${Q3/\{#Q3 title=\"¿Un tercer item?\"/{#Q3 title=\"¿Un tercer item?\" decided=\"Sí\"}"
spec "Sí" "" "$Q3D"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q3' "$TMP/build.out" \
  && ! grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "13. an item added after the last reply and then decided FAILS, naming Q3" \
  || fail "13. rc=$rc out=$(cat "$TMP/build.out")"

# 14. (b) a marker as the whole answer does not decide: `Q2: [show-me]`
newpage inlinemark
spec "" ""; build
printf 'Q1: Sí\nQ2: [show-me]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "14. save-reply.sh failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ! grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "14. an inline marker-only answer (Q2: [show-me]) does not decide Q2" \
  || fail "14. rc=$rc out=$(cat "$TMP/build.out")"

# 15. (c) an empty `Q1:` line is not answered by the NEXT line `Q2: Sí`
newpage emptyhead
spec "" ""; build
printf 'Q1:\nQ2: Sí\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "15. save-reply.sh failed"
spec "Sí" "Sí"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ! grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ok "15. an empty Q1: line does not borrow the Q2 answer; Q1 FAILS, Q2 passes" \
  || fail "15. rc=$rc out=$(cat "$TMP/build.out")"

# 16. (d) an ask marker beside prose: the item is provisional, prose decides nothing
newpage markprose
spec "" ""; build
printf '### Q1 · x\n\n- [question]\n\n¿Qué significa cerrar?\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "16. save-reply.sh failed"
spec "Sí" ""
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "16. an ask marker plus prose does not decide Q1" \
  || fail "16. rc=$rc out=$(cat "$TMP/build.out")"

# 17. [page-defect] is not an ask about the answer: it does not block an answer
newpage defect
spec "" ""; build
printf '### Q1 · x\n\n- Sí: cerrarlo ahora\n- [page-defect]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "17. save-reply.sh failed"
spec "Sí" ""
build && ok "17. an answer carrying only [page-defect] still decides Q1" \
  || fail "17. $(cat "$TMP/build.out")"

# 18. an inline [page-defect] token is no answer either (the strip, not the ask rule)
newpage inlinedefect
spec "" ""; build
printf 'Q1: Sí\nQ2: [page-defect]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "18. save-reply.sh failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ok "18. an inline [page-defect]-only answer does not decide Q2" \
  || fail "18. rc=$rc out=$(cat "$TMP/build.out")"

# 19. (e) ids that are not Letters+digits: `D4a:` empty must not borrow `D4b: Sí`
newpage idsuffix; IDA=D4a IDB=D4b
spec "" ""; build
printf 'D4a:\nD4b: Sí\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "19. save-reply.sh failed"
spec "Sí" "Sí"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*D4a' "$TMP/build.out" \
  && ! grep -q 'consult-decided-trace.*D4b' "$TMP/build.out" \
  && ok "19. D4a: (empty) then D4b: Sí FAILS D4a only" \
  || fail "19. rc=$rc out=$(cat "$TMP/build.out")"

# 20. (e) D4b's marker line must not leak into D4a's block
newpage idleak; IDA=D4a IDB=D4b
spec "" ""; build
printf 'D4a: Sí\nD4b: [show-me]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "20. save-reply.sh failed"
spec "Sí" ""
build && ok "20. D4a: Sí then D4b: [show-me] decides D4a (no marker leak)" \
  || fail "20. $(cat "$TMP/build.out")"
unset IDA IDB

# 21. an option-style line that is not an item id is content, not a boundary
newpage optline
spec "" ""; build
printf 'Q1:\nV2: la segunda\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "21. save-reply.sh failed"
spec "Sí" ""
build && ok "21. Q1: then V2: la segunda (V2 not an item) decides Q1" \
  || fail "21. $(cat "$TMP/build.out")"

# 22. (f) the latest block for an id governs: a later re-ask undoes an earlier answer
newpage latest
spec "" ""; build
printf '### Q1 · x\n\n- Sí: cerrarlo ahora\n\n### Q2 · y\n\n- [show-me]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "22. save 1 failed"
printf '### Q1 · x\n\n- Sí: cerrarlo ahora [provisional]\n- [question]\n\nespera, ¿qué implica cerrarlo?\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "22. save 2 failed"
spec "Sí" "" "" "later"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "22. an earlier answer followed by a later re-ask leaves Q1 undecided" \
  || fail "22. rc=$rc out=$(cat "$TMP/build.out")"

# 23. (g) a spec with items beside a page with zero consult items is not silent
newpage noitems
spec "" ""
printf '<!DOCTYPE html><html lang="es"><body><h1>Sin items</h1></body></html>\n' > "$PAGE"
bash "$CHECK" "$PAGE" >"$TMP/o" 2>&1; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-spec-items.*Q1' "$TMP/o" \
  && ok "23. a spec with items next to a page with no items FAILS consult-spec-items" \
  || fail "23. rc=$rc out=$(cat "$TMP/o")"

# 24. (h) a markdown link in the answer is content, not an ask marker
newpage mdlink
spec "" ""; build
printf 'Q1: Sí, ver [readme](https://x)\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "24. save-reply.sh failed"
spec "Sí" ""
build; rc=$?
[[ "$rc" == "0" ]] && ! grep -q 'consult-decided-trace' "$TMP/build.out" \
  && ok "24. Q1: Sí, ver [readme](url) decides Q1" \
  || fail "24. rc=$rc out=$(cat "$TMP/build.out")"

# 25. (h) a checked task-list line `- [x]` in the answer is content too
newpage tasklist
spec "" ""; build
printf 'Q1: Sí\n- [x] revisado\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "25. save-reply.sh failed"
spec "Sí" ""
build; rc=$?
[[ "$rc" == "0" ]] \
  && ok "25. Q1: Sí with a '- [x] revisado' line decides Q1" \
  || fail "25. rc=$rc out=$(cat "$TMP/build.out")"

# 26. (i) two saves in one round, no rebuild between: both answers survive
newpage twosaves
spec "" ""; build
printf 'Q1: Sí\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "26. save 1 failed"
printf 'Q2: No\n' | bash "$SAVE_REPLY" "$PAGE" >"$TMP/save2.out" || fail "26. save 2 failed"
# the same-round append owes nothing: its message must not claim a duty
grep -q 'duty is still outstanding' "$TMP/save2.out" \
  && fail "26. same-round append claims an outstanding duty: $(cat "$TMP/save2.out")"
spec "Sí" "No"
build; rc=$?
RP="$D/.aidex-artifact-prev/$(basename "$PAGE" .html).reply.md"
[[ "$rc" == "0" ]] && grep -q 'Q1: Sí' "$RP" && grep -q 'Q2: No' "$RP" \
  && ok "26. two saves with no rebuild between append; both items decide" \
  || fail "26. rc=$rc out=$(cat "$TMP/build.out") reply=$(cat "$RP")"

# 26b. BL-644 review: a CRLF page. answered.html is written from the decoded
# text (universal newlines), so a raw-byte fingerprint of the page never
# matches it: the second save from the SAME page replaced the first
newpage crlf
spec "" ""; build
python3 -c 'import sys; p=sys.argv[1]; b=open(p,"rb").read(); open(p,"wb").write(b.replace(b"\n", b"\r\n"))' "$PAGE"
printf '### Q1 · a\n\n- Sí: cerrarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "26b. save 1 failed"
printf '### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "26b. save 2 failed"
RP="$D/.aidex-artifact-prev/crlf.reply.md"
grep -q 'reply saved .* same-round -->' "$RP" && grep -q '^### Q1' "$RP" \
  && ok "26b. two saves from one CRLF page are same-round; the first paste survives" \
  || fail "26b. reply=$(cat "$RP")"

# 27. guard: save, REBUILD the page (a real change), save again -> overwritten
newpage resave
spec "" ""; build
printf 'Q1: Sí\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "27. save 1 failed"
spec "Sí" ""; build || fail "27. rebuild failed"
printf 'Q2: No\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "27. save 2 failed"
RP="$D/.aidex-artifact-prev/$(basename "$PAGE" .html).reply.md"
grep -q 'Q2: No' "$RP" && ! grep -q 'Q1: Sí' "$RP" \
  && ok "27. a save after a real rebuild replaces reply.md" \
  || fail "27. reply=$(cat "$RP")"

# 28. BL-598: a later full composer paste supersedes earlier saves: Q1 absent
# from the latest full paste is not answered by the first one
newpage fullsup
spec "" ""; build
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "28. save 1 failed"
printf '## G1 · x\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "28. save 2 failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q1' "$TMP/build.out"   && ! grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ok "28. a second full paste without Q1 leaves Q1 unanswered (FAIL names Q1 only)" \
  || fail "28. rc=$rc out=$(cat "$TMP/build.out")"

# 29. a chat save AFTER the latest full paste still counts
newpage chatafter
spec "" ""; build
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "29. save 1 failed"
printf 'Q2: No\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "29. save 2 failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" == "0" ]] \
  && ok "29. a chat line saved after a full paste still decides its item" \
  || fail "29. rc=$rc out=$(cat "$TMP/build.out")"

# 30. a chat save BEFORE a full paste that holds the id is not a regression
newpage chatbefore
spec "" ""; build
printf 'Q1: Sí\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "30. save 1 failed"
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "30. save 2 failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" == "0" ]] \
  && ok "30. a full paste after a chat save, holding both ids, decides both" \
  || fail "30. rc=$rc out=$(cat "$TMP/build.out")"

# 31. BL-598 review: with NO full paste, a free-text follow-up save must not
# merge into the previous save's block (the save separator ends a block)
newpage sepq
spec "" ""; build
printf 'Q2: [page-defect]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "31. save 1 failed"
printf 'Lo demás lo vemos luego\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "31. save 2 failed"
spec "" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ok "31. a free-text follow-up does not lend its prose to Q2's marker-only block" \
  || fail "31. rc=$rc out=$(cat "$TMP/build.out")"

# 32. ...and a follow-up save's marker text must not leak back into Q2's answer
newpage sepr
spec "" ""; build
printf 'Q2: No\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "32. save 1 failed"
printf 'Olvida el [show-me] que pedí antes\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "32. save 2 failed"
spec "" "No"
build; rc=$?
[[ "$rc" == "0" ]] \
  && ok "32. a later save's [show-me] text does not make Q2's earlier answer provisional" \
  || fail "32. rc=$rc out=$(cat "$TMP/build.out")"

# 33. a composer paste holding only the general notes is the reader's whole
# state too: it supersedes the earlier full paste
newpage notesonly
spec "" ""; build
NID=$(grep -o 'consult-notes" data-id="[^"]*"' "$PAGE" | sed -n 1p | sed 's/.*data-id="//; s/"$//')
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "33. save 1 failed"
printf '### %s · Notas generales\n\nMejor lo pienso otra vez\n' "${NID:-notes}" | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "33. save 2 failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ok "33. a notes-only composer paste supersedes the earlier answers (FAIL names Q1 and Q2)" \
  || fail "33. NID=$NID rc=$rc out=$(cat "$TMP/build.out")"

# 34. BL-598 review finding 1: a CHAT save is never in the composer, so a later
# full paste (which cannot hold Q1: it is blank there) does not supersede it
newpage chatkept
spec "" ""; build
printf 'Q1: Sí, ciérralo\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "34. save 1 failed"
printf '## G1 · x\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "34. save 2 failed"
spec "Sí" "No"
build; rc=$?
[[ "$rc" == "0" ]] && ! grep -q 'consult-decided-trace' "$TMP/build.out" \
  && ok "34. a chat answer saved before a full paste without that id still decides it" \
  || fail "34. rc=$rc out=$(cat "$TMP/build.out")"

# 35. BL-598 review finding 2: a paste appended because a duty is unmet comes
# from a NEW page (Q1 decided there, so the composer omits it): it must not
# supersede the previous round's paste. The gate rolls back a page with an
# unmet duty, so the round-2 page is built beside it and copied in (as
# test-consultation-round-guards.sh D1 writes its draft directly).
newpage dutyround
spec "" ""; build
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n\n### Q2 · b\n\n- [show-me]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "35. save 1 failed"
spec "Sí" ""
mkdir -p "$TMP/alt"; cp "$SPEC" "$TMP/alt/dutyround.spec.md"
python3 "$BUILD" "$TMP/alt/dutyround.spec.md" -o "$TMP/alt/dutyround.html" >"$TMP/alt.out" 2>&1 \
  || fail "35. round-2 page build failed: $(cat "$TMP/alt.out")"
cp "$TMP/alt/dutyround.html" "$PAGE"
cmp -s "$PAGE" "$D/.aidex-artifact-prev/dutyround.answered.html" \
  && fail "35. fixture: the round-2 page equals the answered snapshot"
grep -q 'data-id="Q1"[^>]*data-decided' "$PAGE" || fail "35. fixture: Q1 is not decided on the round-2 page"
printf '## G1 · x\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >"$TMP/save2.out" || fail "35. save 2 failed"
grep -q 'duty is still outstanding' "$TMP/save2.out" || fail "35. fixture: save 2 was not a duty append: $(cat "$TMP/save2.out")"
spec "Sí" "No"
build; rc=$?
[[ "$rc" == "0" ]] && ! grep -q 'consult-decided-trace' "$TMP/build.out" \
  && ok "35. a full paste appended in a later round (duty unmet) does not erase the earlier round's Q1" \
  || fail "35. rc=$rc out=$(cat "$TMP/build.out")"

# 36. a duty outstanding but the page NOT rebuilt: the second paste comes from
# the same page, so it is same-round and still supersedes (Q1 withdrawn)
newpage dutysame
spec "" ""; build
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n\n### Q2 · b\n\n- [show-me]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "36. save 1 failed"
printf '## G1 · x\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "36. save 2 failed"
# fixture guard (couples to the separator wording on purpose): save 2 is same-round
grep -q 'reply saved .* same-round -->' "$D/.aidex-artifact-prev/dutysame.reply.md" \
  || fail "36. fixture: save 2 was not labelled same-round: $(cat "$D/.aidex-artifact-prev/dutysame.reply.md")"
spec "Sí" "No"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q1' "$TMP/build.out" \
  && ok "36. same page with a duty outstanding: a later full paste without Q1 still supersedes" \
  || fail "36. rc=$rc out=$(cat "$TMP/build.out")"

# 37. a legacy separator with no mode (reply.md written before BL-598) is a
# round end: a later full paste does not supersede across it
newpage legacysep
spec "" ""; build
mkdir -p "$D/.aidex-artifact-prev"
cp "$PAGE" "$D/.aidex-artifact-prev/legacysep.answered.html"
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n\n<!-- reply saved 2026-09-30T10:00:00 -->\n\n## G1 · x\n\n### Q2 · b\n\n- No: intentarlo ahora' \
  > "$D/.aidex-artifact-prev/legacysep.reply.md"
spec "Sí" "No"
build; rc=$?
[[ "$rc" == "0" ]] && ! grep -q 'consult-decided-trace' "$TMP/build.out" \
  && ok "37. a mode-less legacy separator ends a round: Q1 from before it still counts" \
  || fail "37. rc=$rc out=$(cat "$TMP/build.out")"

# 38. BL-644: two duty-labelled saves from the SAME ungated page (answered.html
# is still round 1's) are one round: the later full paste withdrew Q3, so a
# page showing Q3 decided FAILS naming it. Repro steps from the item.
newpage dutytwice
Q3='
::: item {#Q3 title="¿Un tercer item?"}
¿Hacemos un tercer item?

- Sí: hacerlo {recommended}
- No: omitirlo
:::
'
spec "" "" "$Q3"; build || fail "38. round-1 build failed: $(cat "$TMP/build.out")"
printf '## G1 · x\n\n### Q1 · a\n\n- [show-me]\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "38. save 1 failed"
# round 2 built outside the gate, Q1 still without its figure (a reworded
# masthead is the only change, so the page differs from the snapshot)
mkdir -p "$TMP/alt38"; sed 's/Una decision y una pregunta./Tres preguntas, ronda dos./' "$SPEC" > "$TMP/alt38/dutytwice.spec.md"
python3 "$BUILD" "$TMP/alt38/dutytwice.spec.md" -o "$TMP/alt38/dutytwice.html" >"$TMP/alt38.out" 2>&1 \
  || fail "38. round-2 page build failed: $(cat "$TMP/alt38.out")"
cp "$TMP/alt38/dutytwice.html" "$PAGE"
cmp -s "$PAGE" "$D/.aidex-artifact-prev/dutytwice.answered.html" \
  && fail "38. fixture: the round-2 page equals the answered snapshot"
printf '## G1 · x\n\n### Q2 · b\n\n- No\n\n### Q3 · c\n\n- Sí\n' | bash "$SAVE_REPLY" "$PAGE" >"$TMP/save2.out" || fail "38. save 2 failed"
grep -q 'duty is still outstanding' "$TMP/save2.out" || fail "38. fixture: save 2 was not a duty append: $(cat "$TMP/save2.out")"
printf '## G1 · x\n\n### Q2 · b\n\n- No\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "38. save 3 failed"
Q3D="${Q3/\{#Q3 title=\"¿Un tercer item?\"/{#Q3 title=\"¿Un tercer item?\" decided=\"Sí\"}"
spec "" "No" "$Q3D"
build; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-decided-trace.*Q3' "$TMP/build.out" \
  && ! grep -q 'consult-decided-trace.*Q2' "$TMP/build.out" \
  && ok "38. two saves from one rebuilt page with a duty unmet: the later full paste withdraws Q3" \
  || fail "38. rc=$rc out=$(cat "$TMP/build.out") reply=$(cat "$D/.aidex-artifact-prev/dutytwice.reply.md")"

# 39. backward compatibility: a reply.md whose last separator predates the
# page fingerprint (BL-598 wording, `duty` and no `page:`) falls back to the
# answered snapshot: a save from a page equal to it is same-round, and the
# legacy separator still ends the round before it (Q1 still counts)
newpage legacyfp
spec "" ""; build
mkdir -p "$D/.aidex-artifact-prev"
cp "$PAGE" "$D/.aidex-artifact-prev/legacyfp.answered.html"
printf '## G1 · x\n\n### Q1 · a\n\n- Sí: cerrarlo ahora\n\n<!-- reply saved 2026-10-01T10:00:00 duty -->\n\n## G1 · x\n\n### Q2 · b\n\n- [show-me]\n' \
  > "$D/.aidex-artifact-prev/legacyfp.reply.md"
printf '## G1 · x\n\n### Q2 · b\n\n- No: intentarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "39. save failed"
grep -q 'reply saved .* page:[0-9a-f]* same-round -->' "$D/.aidex-artifact-prev/legacyfp.reply.md" \
  && ok "39a. after a fingerprint-less separator, a save from the answered page is same-round" \
  || fail "39a. $(cat "$D/.aidex-artifact-prev/legacyfp.reply.md")"
spec "Sí" "No"
build; rc=$?
[[ "$rc" == "0" ]] && ! grep -q 'consult-decided-trace' "$TMP/build.out" \
  && ok "39b. a legacy duty separator still ends a round: Q1 from before it counts" \
  || fail "39b. rc=$rc out=$(cat "$TMP/build.out")"

# 40. BL-692: a proposal (proposal=yes) is decided by the WRITER, so the reader's reply need not answer it.
newpage proposal
spec "" ""; build
printf '### Q1 · x\n\n- Sí: cerrarlo ahora\n' | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "40. save-reply.sh failed"
spec "Sí" "No"; sed -i.bak 's/decided=No/decided=No proposal=yes/' "$SPEC"
build; rc=$?
[[ "$rc" == "0" ]] && ! grep -q 'consult-decided-trace' "$TMP/build.out" \
  && ok "40. a proposal=yes item with no reply block does not trip consult-decided-trace" \
  || fail "40. rc=$rc out=$(cat "$TMP/build.out")"

# 41. BL-692: on a first-round page a decided item with no proposal=yes is probably a proposal the kit would fold away.
newpage warn1
spec "Sí" ""
build; rc=$?
out="$(bash "$CHECK" "$PAGE" 2>&1)"; crc=$?
[[ "$crc" == "0" ]] && grep -q 'WARN \[consult-round1-decided\].*proposal=yes' <<<"$out" \
  && ok "41. a round-1 page with a decided item and no proposal=yes WARNS (exit 0)" \
  || fail "41. rc=$crc out=$out"
newpage warn1b
spec "Sí" "No"; sed -i.bak -e 's/decided=No/decided=No proposal=yes/' -e 's/decided=Sí/decided=Sí proposal=yes/' "$SPEC"
build
out="$(bash "$CHECK" "$PAGE" 2>&1)"
grep -q 'consult-round1-decided' <<<"$out" \
  && fail "41b. a round-1 page whose decided items are proposals still WARNS: $out" \
  || ok "41b. proposal=yes on every decided item: no round-1 warning"

if [[ "$failures" -eq 0 ]]; then
  echo "test-consult-spec-trace.sh: all checks passed"
else
  echo "$failures failure(s)"; exit 1
fi
