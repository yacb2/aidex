#!/usr/bin/env bash
# test-mine-preferences.sh — the invariants of the standing-preference miner
# (BL-164), against the hand-written corpus fixture.
#
# WHY THIS SUITE EXISTS. The miner's whole value is that it does NOT fire on
# domain chatter. A detector for "mockup / casilla / en espanol" is trivial to
# write and useless: in a dubbing product "traduccion" is a domain noun, in an
# ERP "tabla" and "marcar" are domain verbs, and the keyword version of this
# returned 152 hits that were overwhelmingly people discussing their own app.
# What makes it work is a three-part conjunction, and each clause is load-bearing
# in a way that only shows up as a FALSE POSITIVE — so the negative cases below
# are the real test. Delete them and the suite passes against a detector that
# fires on everything.
#
# Scenarios:
#   (a) the full conjunction fires
#   (b) domain chatter with a shape word but NO deliverable does not fire
#       -> the DELIVERABLE clause is load-bearing
#   (c) shape + deliverable with NO directive does not fire
#       -> the DIRECTIVE clause is load-bearing
#   (d) head_tail() is a pure function with the documented boundary
#   (e) a preference in the TAIL survives head+tail and dies under head-only
#       -> decision D5, the reason prefilter.py's 600-char cut was wrong
#   (f) a machine-authored body carrying a perfect preference does not fire
#       -> the provenance gate (INSTR-01)
#   (g) --transcripts-root is a real parameter, not decoration
#   (h) the miner refuses to report a corpus it could not read
#   (i) the output labels the ASK, not just "a preference"
#
# Run with: bash skills/aidex-audit/tests/test-mine-preferences.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RETRO="$TESTS_DIR/../scripts/usage-retro"
FIXTURE="$TESTS_DIR/fixtures/preferences-corpus.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TX="$(bash "$FIXTURE")"
OUT="$(mktemp -d)"
cleanup() { rm -rf "$TX" "$OUT"; }
trap cleanup EXIT

run() {  # run [extra args...] -> stdout+stderr of a full-text miner pass
  python3 "$RETRO/mine_preferences.py" --transcripts-root "$TX" "$@" 2>&1
}

report="$(run --out "$OUT/full.jsonl")"

# The fixture has 5 human prompts: s1-s4 one each, s5 injected (0), and s6 one
# real prompt plus a kickoff and a handoff envelope that must NOT count. s7 is
# handoff-seeded with the marker in the shape real transcripts use (a
# `type: "attachment"` record) and contributes NO human prompt: its only
# prompt-shaped record is the wrapper's `continue`.
#
# That last one is load-bearing rather than decorative. This total is the
# denominator of the printed DETECTED percentage, so a reader that drops the
# attachment record loses the seeding evidence, re-admits `continue` as typed,
# and reports 6 — a confident wrong number, and the INSTR-01 inflation
# prompt_kinds.py exists to prevent. If this drifts, every assertion below is
# measuring a corpus nobody described.
echo "$report" | grep -qE 'corpus +: 5 human prompts' \
  || fail "(setup) expected 5 human prompts (both kickoffs + envelope excluded): $report"

labels_for() {  # labels_for <session-substring-of-prompt>
  python3 -c '
import json, sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if sys.argv[2] in r["prompt"]:
        print(",".join(sorted(r["labels"]))); break
' "$OUT/full.jsonl" "$1"
}

# ---------------------------------------------------------------------------
# (a) the full conjunction fires, and is labelled for the ask it actually makes.
# ---------------------------------------------------------------------------
[[ "$(labels_for 'escribas los artifacts')" == "lang:artifact" ]] \
  || fail "(a) the full conjunction should fire as lang:artifact, got '$(labels_for 'escribas los artifacts')'"

# ---------------------------------------------------------------------------
# (b) THE DELIVERABLE CLAUSE. s2 carries a directive ("usa") and two shape words
#     ("tablas", "graficos") — everything except a deliverable noun. This is the
#     exact false-positive class that dominated the keyword version. If it
#     fires, the clause has been removed or weakened.
# ---------------------------------------------------------------------------
[[ -z "$(labels_for 'tablas dentro de tarjetas')" ]] \
  || fail "(b) domain UI chatter must not fire: got '$(labels_for 'tablas dentro de tarjetas')'"

# ...and the fixture must really contain the bait, or (b) proves nothing.
grep -q 'graficos' "$TX"/*/s2.jsonl \
  || fail "(b) fixture drift: s2 must carry a shape word, or (b) is vacuous"

# ---------------------------------------------------------------------------
# (c) THE DIRECTIVE CLAUSE. s3 has a shape word ("opcion B") and a deliverable
#     ("informe") but instructs nothing — the user is choosing, not asking.
# ---------------------------------------------------------------------------
[[ -z "$(labels_for 'vamos con la opcion B')" ]] \
  || fail "(c) a user ANSWERING must not read as a format instruction: '$(labels_for 'vamos con la opcion B')'"

# ---------------------------------------------------------------------------
# (d) head_tail() is a predicate with a stated boundary, not prose. Pinned
#     because the whole of decision D5 rests on it keeping the END of a prompt.
# ---------------------------------------------------------------------------
out_d="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from mine_preferences import head_tail
bad = []
# shorter than head+tail: returned unchanged, no marker
if head_tail("abc", 10, 10) != "abc": bad.append("short-unchanged")
# exactly at the boundary: still unchanged
if head_tail("a"*20, 10, 10) != "a"*20: bad.append("boundary-unchanged")
# one over: cut, and BOTH ends survive
got = head_tail("S" + "m"*30 + "E", 5, 5)
if not got.startswith("Smmmm") or not got.endswith("mmmmE"): bad.append("ends-lost")
if "[...]" not in got.replace("…", "..."): bad.append("no-marker")
# tail=0 degrades to head-only rather than crashing
if head_tail("a"*100, 10, 0)[:10] != "a"*10: bad.append("tail-zero")
# negative input is a programming error, not a silent 0
try:
    head_tail("x", -1, 5); bad.append("negative-accepted")
except ValueError: pass
print("BAD" if bad else "OK", bad)
' "$RETRO")"
[[ "$out_d" == OK* ]] || fail "(d) head_tail boundary wrong: $out_d"

# ---------------------------------------------------------------------------
# (e) DECISION D5, end to end. s4 puts its preference in the last 60 characters
#     of a ~950-char prompt. Under the window prefilter.py used to pass the
#     analyst (head-only 600) it is invisible; under head+tail it is recovered.
#     Both directions are asserted: a head+tail that "finds everything" because
#     the window is not being applied at all would pass a one-sided check.
# ---------------------------------------------------------------------------
[[ "$(labels_for 'flujo completo de creacion')" == "viz:mockup" ]] \
  || fail "(e) full text must see a tail preference: '$(labels_for 'flujo completo de creacion')'"

head_only="$(run --window head-tail --head 600 --tail 0)"
echo "$head_only" | grep -qE 'DETECTED +: 2 ' \
  || fail "(e) head-only 600 should LOSE the tail case (expected 2): $head_only"

head_tail_run="$(run --window head-tail --head 400 --tail 400)"
echo "$head_tail_run" | grep -qE 'DETECTED +: 3 ' \
  || fail "(e) head+tail should RECOVER the tail case (expected 3): $head_tail_run"

# ---------------------------------------------------------------------------
# (f) THE PROVENANCE GATE. s5 is a machine-authored body that says, verbatim,
#     the thing this miner looks for. Attributing it would report the harness's
#     own prose as the user's standing instruction — which is precisely how the
#     run-3 autonomy metric came out 70% artifact.
# ---------------------------------------------------------------------------
[[ -z "$(labels_for 'Approach this as the design lead')" ]] \
  || fail "(f) a machine-authored body must not attribute: '$(labels_for 'Approach this as the design lead')'"

# The bait has to be genuinely detectable as text, or (f) is vacuous: run the
# detector directly on the injected body and require that it WOULD have fired.
out_f="$(python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from mine_preferences import detect
t = "Genera el artifact en espanol y ponme casillas bajo cada opcion con un campo de notas."
print("WOULD-FIRE" if detect(t) else "INERT")
' "$RETRO")"
[[ "$out_f" == "WOULD-FIRE" ]] \
  || fail "(f) fixture drift: the injected body is inert, so the gate proves nothing"

# ---------------------------------------------------------------------------
# (g) --transcripts-root is a real parameter. If it were ignored, every
#     assertion above would be reading the author's real transcript tree and
#     would still look green.
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d)"
out_g="$(python3 "$RETRO/mine_preferences.py" --transcripts-root "$EMPTY" 2>&1)"; rc_g=$?
rm -rf "$EMPTY"
[[ $rc_g -ne 0 ]] || fail "(g)(h) an unreadable corpus must not exit 0: $out_g"
echo "$out_g" | grep -q 'no human prompts' \
  || fail "(h) an empty corpus should say so, not report 0 findings: $out_g"

# ---------------------------------------------------------------------------
# (i) the labels distinguish the ASK. "give me checkboxes" and "write it in
#     Spanish" need different fixes, so one merged "preference" label would be
#     useless downstream.
# ---------------------------------------------------------------------------
[[ "$(labels_for 'ponme casillas bajo cada opcion para poder marcarlas')" == *"fmt:markable"* ]] \
  || fail "(i) a checkbox request should label fmt:markable: '$(labels_for 'ponme casillas bajo cada opcion para poder marcarlas')'"

n_labels="$(python3 -c '
import json, sys
labs = set()
for line in open(sys.argv[1]):
    labs.update(json.loads(line)["labels"])
print(len(labs))' "$OUT/full.jsonl")"
[[ "$n_labels" -ge 3 ]] \
  || fail "(i) expected >=3 distinct labels across the fixture, got $n_labels"

# Case (j) asks about the LEXICON, so it calls the detector on a literal string
# rather than fishing a fixture session out of the pipeline output. Both matter:
# the fixture cases above prove the pipeline carries labels end to end, this one
# proves a specific phrasing is recognised at all.
detect_direct() {  # detect_direct <text>
  python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
import mine_preferences as MP
print(",".join(sorted(MP.detect(sys.argv[2]))))' "$RETRO" "$1"
}

# ---------------------------------------------------------------------------
# (j) THE VOCABULARY THE 2026-08-17 RECALL STUDY PAID FOR. Measured recall was
#     13.8%, and 13 of the 17 false negatives carried no SHAPE match at all: the
#     lexicon was the binding constraint, not the conjunction. These four
#     phrasings are the ones the study proved were being lost, and each is
#     pinned so a future tightening cannot silently drop them again.
#
#     `spa` matters more than it looks: it is this user's own abbreviation for
#     Spanish, it appears in the corpus, and nothing matched it.
# ---------------------------------------------------------------------------
[[ "$(detect_direct 'presentame el plan en un artefacto en spa con visuales')" == *"lang:artifact"* ]] \
  || fail "(j) 'en spa' must label lang:artifact: '$(detect_direct 'presentame el plan en un artefacto en spa con visuales')'"
[[ "$(detect_direct 'presentame el plan en un artefacto en spa con visuales')" == *"viz:mockup"* ]] \
  || fail "(j) a bare 'visuales' must label viz:mockup"
[[ "$(detect_direct 'prepara el correo, no utilices tablas porque se rompen al copiar y pegar')" == *"fmt:copyable"* ]] \
  || fail "(j) a paste-into-Outlook request must label fmt:copyable: '$(detect_direct 'prepara el correo, no utilices tablas porque se rompen al copiar y pegar')'"
[[ "$(detect_direct 'presentame el informe y no me muestres un millon de caracteres de texto')" == *"fmt:length"* ]] \
  || fail "(j) a length preference must label fmt:length: '$(detect_direct 'presentame el informe y no me muestres un millon de caracteres de texto')'"

# And the widening must not have dissolved the DELIVERABLE clause: a UI
# discussion carrying BOTH a directive and the new shape words is still not a
# preference about a deliverable. The directive is deliberate — without one the
# case passes for the wrong reason and guards nothing, which is what a first
# draft of this line did.
[[ -z "$(detect_direct 'haz que el boton de la pista sea mas visual y permita copiar y pegar el segmento')" ]] \
  || fail "(j) product-UI talk must stay unlabelled: '$(detect_direct 'haz que el boton de la pista sea mas visual y permita copiar y pegar el segmento')'"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — mine_preferences: conjunction fires, DELIVERABLE and DIRECTIVE clauses each pinned by a false positive, head_tail boundary, D5 tail recovery both directions, provenance gate non-vacuous, root honoured, labels distinguish the ask"
