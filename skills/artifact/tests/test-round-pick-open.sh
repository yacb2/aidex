#!/usr/bin/env bash
# test-round-pick-open.sh — round-open-pick-not-decided (LOOP-008, 225f968e):
# check-artifact FAILS a round-N+1 page that leaves OPEN an item the saved
# round-N reply only PICKED (an option, nothing asked back).
#
# Layer: integration over the real spec_build.py / save-reply.sh / check-artifact.sh
# (the pieces share the files beside the page, so mocking any would test the mock).
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

# Q1 verdict in $1 (empty = open). Q2 stays open.
spec() {
  cat > "$SPEC" <<SP
::: masthead {visual="none: two short questions, nothing to draw" title="Dos preguntas"}
Una decision y una pregunta.
:::

::: group {#G1 title="Lo que falta cerrar"}
::: item {#Q1 title="¿Cerramos el item ahora?"${1:+ decided="$1"}}
¿Cerramos el item ahora o lo dejamos para otra ronda?

- Sí: cerrarlo ahora {recommended}
- No: dejarlo para otra ronda
:::

::: item {#Q2 title="¿Aplazamos el segundo item?"}
¿Aplazamos el segundo item a la próxima ronda?

- Sí: aplazarlo {recommended}
- No: intentarlo ahora
:::
:::

::: notes {title="Notas generales"}
:::
SP
}
build() { python3 "$BUILD" "$SPEC" -o "$PAGE" "$@" > "$TMP/build.out" 2>&1; }

# A fresh page, round 1 built, the reader's reply $1 saved. Leaves the spec open.
round1() {
  PAGE="$D/$2.html"; SPEC="$D/$2.spec.md"
  spec ""; build || fail "$2: round 1 build: $(cat "$TMP/build.out")"
  printf '%b' "$1" | bash "$SAVE_REPLY" "$PAGE" >/dev/null || fail "$2: save-reply.sh failed"
}
PICK='### Q1 · ¿Cerramos el item ahora?\n\n- Sí: cerrarlo ahora (recommended)\n'

# e. round 1 page: nothing to compare against
PAGE="$D/first.html"; SPEC="$D/first.spec.md"
spec ""; build && bash "$CHECK" "$PAGE" >"$TMP/o" 2>&1 \
  && ok "e. a round 1 page is not subject to the check" || fail "e. $(cat "$TMP/build.out" "$TMP/o")"

# a. picked, round 2 leaves Q1 open: FAIL naming Q1 and the option
round1 "$PICK" picked
build --new-round; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-round-pick.*Q1.*Sí: cerrarlo ahora' "$TMP/build.out" \
  && ! grep -q 'consult-round-pick.*Q2' "$TMP/build.out" \
  && ok "a. a pick left open on round 2 FAILS, naming Q1 and the picked option" \
  || fail "a. rc=$rc out=$(cat "$TMP/build.out")"

# b. the same pick decided: passes
round1 "$PICK" decided
spec "Sí"; build --new-round && bash "$CHECK" "$PAGE" >/dev/null 2>&1 \
  && ok "b. the same item decided passes" || fail "b. $(cat "$TMP/build.out")"

# c. Other answer left open: passes
round1 '### Q1 · ¿Cerramos?\n\n- Other — see my notes\n\nnecesito pensarlo\n' other
build --new-round && ok "c. an Other answer left open passes" || fail "c. $(cat "$TMP/build.out")"

# d. option + note left open: passes
round1 '### Q1 · ¿Cerramos?\n\n- Sí: cerrarlo ahora (recommended)\n\nsolo si es seguro\n' note
build --new-round && ok "d. an option+note answer left open passes" || fail "d. $(cat "$TMP/build.out")"

# g. a bare Otra label (no note line) is an Other answer, not a pick
round1 '### Q1 · ¿Cerramos?\n\n- Otra — lo explico en las notas\n' otra
build --new-round && ok "g. a bare Otra label left open passes" || fail "g. $(cat "$TMP/build.out")"

# h. an ask marker beside the pick makes it provisional, not a pick
round1 '### Q1 · ¿Cerramos?\n\n- Sí: cerrarlo ahora (recommended) [provisional]\n- [show-me]\n' prov
build --new-round; rc=$?
! grep -q 'consult-round-pick' "$TMP/build.out" \
  && ok "h. a provisional pick with an ask marker left open raises no pick finding" \
  || fail "h. rc=$rc $(cat "$TMP/build.out")"

# i. two picks, the opening build decides only Q1: FAIL naming Q2, not Q1
round1 "$PICK"'\n### Q2 · ¿Aplazamos?\n\n- Sí: aplazarlo (recommended)\n' partial
spec "Sí"; build --new-round; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-round-pick.*Q2' "$TMP/build.out" \
  && ! grep -q 'consult-round-pick.*Q1' "$TMP/build.out" \
  && ok "i. the build opening a round with one of two picks decided FAILS, naming Q2" \
  || fail "i. rc=$rc out=$(cat "$TMP/build.out")"

# j. the same spec rebuilt without --new-round (what a decide verb does) passes and opens round 2
build && grep -q 'consult-round" content="2"' "$PAGE" \
  && ok "j. a decide-verb style rebuild (no --new-round) that decided one of two picks is a round in progress" \
  || fail "j. $(cat "$TMP/build.out")"

# f. round 2 page with no saved reply: says so instead of passing
PAGE="$D/noreply.html"; SPEC="$D/noreply.spec.md"
spec ""; build; sed -i.bak 's/name="consult-round" content="1"/name="consult-round" content="2"/' "$PAGE"
bash "$CHECK" "$PAGE" >"$TMP/o" 2>&1; rc=$?
[[ "$rc" != "0" ]] && grep -q 'consult-round-pick.*round 2.*missing' "$TMP/o" \
  && ok "f. a round 2 page with no saved reply FAILS rather than passing unchecked" \
  || fail "f. rc=$rc out=$(cat "$TMP/o")"

[[ "$failures" == "0" ]] && { echo "all passed"; exit 0; }
echo "$failures failure(s)"; exit 1
