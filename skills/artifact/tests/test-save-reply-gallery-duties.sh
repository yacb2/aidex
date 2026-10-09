#!/usr/bin/env bash
# BL-632: save-reply.sh must list gallery rows that carry a "Necesita cambios" /
# "Needs changes" verdict or region marks (even on an approved row) as DUTIES,
# and never print "nothing owed" when such rows exist. An approved row with no
# mark is not a duty. Layer: script boundary (stdout of save-reply.sh), the
# only place the owner-visible line is decided.
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAVE_REPLY="$SKILL/scripts/save-reply.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf '  ok: %s\n' "$*"; }

# save <dir> <reply text>: a fresh page, the reply piped on stdin; stdout in $out.
save() {
  mkdir -p "$1"
  printf '<!doctype html><html><body><p>gallery page</p></body></html>\n' > "$1/page.html"
  out="$(printf '%s' "$2" | bash "$SAVE_REPLY" "$1/page.html" - 2>&1)"
}

ES='## E · La matriz

### x-empty-light-desktop · x · empty · light-desktop

- Aprobada

[mark after 1.7,0.2 33.0x5.6] nota

### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

nota larga

### x-ok-light-desktop · x · ok · light-desktop

- Aprobada
'
save "$TMP/es" "$ES"
[[ "$out" != *"nothing owed"* ]] && ok "es: no 'nothing owed' line" || fail "es: printed 'nothing owed': $out"
[[ "$out" == *"DUTIES the next round owes:"* ]] && ok "es: DUTIES header" || fail "es: no DUTIES header: $out"
[[ "$out" == *"x-empty-light-desktop ["*"region"* ]] && ok "es: marked approved row listed" || fail "es: marked row missing: $out"
[[ "$out" == *"x-full-light-desktop ["*"needs"* ]] && ok "es: needs-changes row listed" || fail "es: needs-changes row missing: $out"
[[ "$out" != *"x-ok-light-desktop"* ]] && ok "es: approved row without marks not listed" || fail "es: approved unmarked row listed: $out"

EN='### y-a-light-desktop · y · a · light-desktop

- Needs changes

say which

### y-b-light-desktop · y · b · light-desktop

- Approved
'
save "$TMP/en" "$EN"
[[ "$out" != *"nothing owed"* && "$out" == *"y-a-light-desktop ["* && "$out" != *"y-b-light-desktop"* ]] \
  && ok "en: Needs changes listed, Approved not" || fail "en: $out"

# A second paste from the same page is appended behind a separator line; the
# gallery parser must not choke on it or lose the first paste's rows.
out="$(printf '%s' "$ES" | bash "$SAVE_REPLY" "$TMP/es/page.html" - 2>&1)"
[[ "$out" == *"APPENDED"* && "$out" == *"x-full-light-desktop ["* && "$out" != *"nothing owed"* ]] \
  && ok "appended save still lists the rows" || fail "appended: $out"

# Control: a reply with nothing owed still says so.
save "$TMP/none" '### z-a-light-desktop · z · a · light-desktop

- Aprobada
'
[[ "$out" == *"nothing owed"* ]] && ok "approved-only reply: nothing owed" || fail "none: $out"

# --- review round 2 (coordinator) -------------------------------------------
# 1. one refused / alternatives row must not drop the other rows' duties.
ALT="$ES
### x-alt-light-desktop-alternatives · x · alt · light-desktop

- Opción B
"
save "$TMP/alt" "$ALT"
[[ "$out" != *"nothing owed"* && "$out" == *"x-full-light-desktop ["* && "$out" != *"unreadable"* ]] \
  && ok "alternatives row (no --rows) parses; other rows still listed" || fail "alt: $out"

# D-c01: with no --rows the labels are unknown, so a first paragraph of two
# bullets on an unpicked alternatives row is notes; it must not crash the save
# (a TypeError escaped gallery_duties_for) or read as unreadable.
ALT2="$ES
### x-alt-light-desktop-alternatives · x · alt · light-desktop

- point one
- point two
"
save "$TMP/alt2" "$ALT2"
[[ "$out" != *"Traceback"* && "$out" != *"[unreadable]"* && "$out" == *"x-full-light-desktop ["* ]] \
  && ok "two note bullets on an unpicked alternatives row (no --rows): no crash, other rows still listed" \
  || fail "alt2: $out"

# U3-1: with no --rows an alternatives row whose first bullet is the kit's
# "Other" label and whose second is the reader's reason keeps its other-verdict
# duty (the reason bullet stays in the notes); it must not demote to plain notes.
for lbl in "Other — see my notes" "Otra — lo explico en las notas"; do
  save "$TMP/alt3-${lbl%% *}" "### x-alt-light-desktop-alternatives · x · alt · light-desktop

- $lbl
- the reason I could not pick
"
  [[ "$out" != *"nothing owed"* && "$out" == *"x-alt-light-desktop-alternatives ["*"other"* ]] \
    && ok "alternatives row '$lbl' + reason bullet (no --rows) keeps the other-verdict duty" \
    || fail "alt3 ($lbl): $out"
done

# N1: the same demotion hit a REVIEW row: an owing first bullet followed by the
# reader's reason bullet must stay the verdict (lenient parse, no --rows).
for lbl in "Needs changes" "Other — see my notes" "Necesita cambios" "Cannot judge"; do
  save "$TMP/n1-${lbl%% *}-${lbl##* }" "### y-a-light-desktop · y · a · light-desktop

- $lbl
- say which
"
  case "$lbl" in "Needs changes"|"Necesita cambios") tag="y-a-light-desktop [needs-changes";; *) tag="y-a-light-desktop [other-verdict";; esac
  [[ "$out" != *"nothing owed"* && "$out" == *"$tag"* ]] \
    && ok "review row '$lbl' + reason bullet keeps its duty (${tag#* })" || fail "n1 ($lbl): $out"
done

# N2: rejecting every alternative owes a rewrite, with or without a reason bullet.
i=0
for body in "- None of them" "- None of them
- what is missing" "- Ninguna"; do
  i=$((i + 1)); save "$TMP/n2-$i" "### x-alt-light-desktop-alternatives · x · alt · light-desktop

$body
"
  [[ "$out" != *"nothing owed"* && "$out" == *"x-alt-light-desktop-alternatives [other-verdict"* \
     && "$out" == *"rejected every alternative"* ]] \
    && ok "alternatives row '${body%%$'\n'*}' owes, in its own wording" || fail "n2 ($body): $out"
done

BAD='### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

nota

### x-empty-light-desktop · x · empty · light-desktop

- Aprobada

[mark after 1.7,0.2 33.0x5.6] nota
dictated sentence after the marks'
save "$TMP/bad" "$BAD"
[[ "$out" != *"nothing owed"* && "$out" == *"[unreadable]"* && "$out" == *"by hand"* ]] \
  && ok "a refused paste prints an unreadable duty, never nothing owed" || fail "bad: $out"

# 2. any answered verdict other than Approved is a duty.
save "$TMP/otra" '### w-a-light-desktop · w · a · light-desktop

- Otra — lo explico en las notas

creo que ya teniamos un filtro
'
[[ "$out" != *"nothing owed"* && "$out" == *"w-a-light-desktop ["* ]] \
  && ok "Otra verdict is a duty" || fail "otra: $out"
save "$TMP/cj" '### w-b-light-desktop · w · b · light-desktop

- Cannot judge
'
[[ "$out" == *"w-b-light-desktop ["* ]] && ok "Cannot judge verdict is a duty" || fail "cj: $out"

# the real echo_lab reply (s1-review): 1 approved+mark, 2 Otra, 3 approved
REAL='## G1 · Estados

### users-list-with-data-light-desktop · users-list · with-data · light-desktop

- Aprobada

cambios menores

[mark after 65.2,27.1 7.9x4.0] otro color

### users-list-filters-access-open-light-desktop · users-list · filters-access-open · light-desktop

- Otra — lo explico en las notas

un filtro custom?

### users-list-filters-status-open-light-desktop · users-list · filters-status-open · light-desktop

- Otra — lo explico en las notas

un filtro custom?

### users-list-actions-menu-active-light-desktop · users-list · actions-menu-active · light-desktop

- Aprobada
'
save "$TMP/real" "$REAL"
n=$(printf '%s\n' "$out" | grep -c '^users-list-')
[[ "$n" == 3 && "$out" != *"nothing owed"* && "$out" != *"actions-menu-active"* ]] \
  && ok "real s1-review shape: three rows listed" || fail "real($n): $out"

# 3. appended pastes: each id once, latest paste wins for a row.
out="$(printf '%s' "$ES" | bash "$SAVE_REPLY" "$TMP/es/page.html" - 2>&1)"
[[ "$(printf '%s\n' "$out" | grep -c '^x-full-light-desktop \[')" == 1 ]] \
  && ok "appended: each id listed once" || fail "dedupe: $out"
LATER='### x-full-light-desktop · x · full · light-desktop

- Aprobada
'
out="$(printf '%s' "$LATER" | bash "$SAVE_REPLY" "$TMP/es/page.html" - 2>&1)"
[[ "$out" != *"x-full-light-desktop ["* && "$out" == *"x-empty-light-desktop ["* ]] \
  && ok "latest paste wins: row turned Aprobada leaves the duties" || fail "latest: $out"

# 4. mixed paste: an ordinary [show-me] item plus a gallery row.
save "$TMP/mixed" '### Q1 · Q1

- [show-me]
- Yes

no entiendo

### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

nota
'
[[ "$out" == *"Q1 [show-me]"* && "$out" == *"x-full-light-desktop ["* ]] \
  && ok "mixed paste: show-me and gallery duties both print" || fail "mixed: $out"

# BL-719 D-c05: a '## ' line inside an ORDINARY item's notes is a note, so it
# neither ends that item's block nor loses the gallery row's duties.
if python3 - "$SKILL/scripts/dash" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import save_reply
text = """### x-full-light-desktop · x · full · light-desktop

- Necesita cambios

nota

[mark after 1.0,1.0 5.0x5.0] aqui

### q1 · Pregunta

- Si

## titulo en nota
mas
"""
d = save_reply.gallery_duties_for(text, ordinary={"q1"})
assert d and all("unreadable" not in str(x) for x in d), d
assert {x[1] for x in d} == {"needs-changes", "region-marks"}, d
PY
then ok "a '## ' note line in an ordinary item keeps the gallery row's duties"
else fail "an ordinary item's '## ' note line lost or broke the gallery duties"; fi

# BL-718 left-alone: the ordinary-item duty readers end a block on the shared
# heading rule (reply_defect.is_block_head), like the gallery readers: a '## '
# line with no ' ·' separator is the reader's note, so a mark under it is
# still the item's, while a real '## G2 · ...' heading ends the block.
if PYTHONPATH="$SKILL/scripts/dash" python3 - <<'PY'
import check_artifact as ca
note = "### q1 \u00b7 Pregunta\n\n- Si\n\n## titulo en nota\n\n- [show-me]\n"
assert ca.marker_duties_of(note) == [("q1", ["show-me"])], ca.marker_duties_of(note)
head = "### q1 \u00b7 Pregunta\n\n- Si\n\n## G2 \u00b7 Otro\n\n- [show-me]\n"
assert ca.marker_duties_of(head) == [], ca.marker_duties_of(head)
assert ca.defect_reports_of("### q1 \u00b7 P\n\n## nota\n\n#### Page problem\n\nroto\n") == {"q1": "roto"}
# the composer's empty-title head (`### q2 ·`, trailing space trimmed) opens its own block
empty = "### q1 \u00b7 Uno\n\n- Si\n\n### q2 \u00b7\n\n- [show-me]\n"
assert ca.marker_duties_of(empty) == [("q2", ["show-me"])], ca.marker_duties_of(empty)
# a reader's own `### two words · x` line is no item head and no block end: a mark under
# it stays the enclosing item's (an extra duty is safer than a dropped one)
own = "### q1 \u00b7 Uno\n\n### Tema largo \u00b7 detalle\n\n- [show-me]\n"
assert ca.marker_duties_of(own) == [("q1", ["show-me"])], ca.marker_duties_of(own)
# reply_blocks (the answer reader) agrees: the mark under a plain '## ' line is q1's,
# so q1 is provisional, not answered
plain = "### q1 \u00b7 Uno\n\n- Si\n\n## mi nota\n\n- [show-me]\n"
assert ca._reply_has_answer(plain, "q1") is False
real = "### q1 \u00b7 Uno\n\n- Si\n\n## G2 \u00b7 Otro\n\n- [show-me]\n"
assert ca._reply_has_answer(real, "q1") is True
# a hashed chat-form head (`## Q2:` / `### Q2:`) still ends the previous item's block
ids = ("Q1", "Q2")
for h in ("##", "###"):
    blank = "### Q1:\n\n%s Q2:\n- A\n" % h
    assert ca._reply_has_answer(blank, "Q1", ids) is False, h
    assert ca._reply_has_answer("### Q1:\n- A\n\n%s Q2:\n- [show-me]\n" % h, "Q1", ids) is True, h
# the answer reader keeps the text under a reader's own `### two words · x` line in q1
assert ca._reply_has_answer("### q1 \u00b7 Uno\n\n### Tema largo \u00b7 detalle\n\n- [show-me]\n", "q1") is False
assert ca._reply_has_answer("### q1 \u00b7 Uno\n\n### Tema largo \u00b7 detalle\n\n- Si\n", "q1") is True
PY
then ok "an ordinary item's block ends at a '## ... · ' heading, not at a plain '## ' note line"
else fail "the ordinary-item duty readers still end a block at every '## ' line"; fi

echo
[[ $failures -eq 0 ]] && { echo "test-save-reply-gallery-duties: PASS"; exit 0; }
echo "test-save-reply-gallery-duties: $failures FAIL"; exit 1
