#!/usr/bin/env bash
# test-subagent-spend.sh — the invariants of the subagent spend table (BL-402),
# against the hand-written corpus fixture.
#
# WHY THIS SUITE EXISTS. The instrument answers one question — which subagent model
# and which agent type carries the spend — and every way of getting it wrong is
# silent: the table still prints, still totals, still looks plausible. The starting
# point for this walk (claude-session-handoff extract_usage.py) dropped every
# subagent turn through a global isSidechain filter and reported the remainder as
# the session's cost. The first green version of THIS script then dropped 8.4% of
# real spend to three further shapes, and credited part of it to the cheap model.
# So the cases below are all "the number is wrong but the output is well-formed",
# and each one is a number computed by hand in the fixture header, never by running
# the script.
#
# Scenarios:
#   (a) main-session row: exact tokens and USD, <synthetic> turn excluded
#   (b) the split message: one message.id over two lines is ONE turn, with the LAST
#       line's numbers
#   (c) sidechain turns are attributed, not dropped
#   (d) the inherited label appears on exactly the rows whose meta names no model
#   (e) an unpriced model shows USD n/a and still counts its tokens
#   (f) a nested subagents/workflows/wf_*/ transcript is walked
#   (g) the flat cache_creation_input_tokens fallback is read as 5m creation
#   (h) the TOTAL row equals the sum of the rows above it
#   (i) --transcripts-root is a real parameter and an empty corpus says so
#   (j) F1 — a non-`message` usage iteration is its own turn, on ITS OWN model,
#       for a subagent and for the main session
#   (k) F2 — the flat cache-creation field beats a stale `cache_creation` dict
#   (l) F3 — dedupe is per PROJECT: a resumed session's replay is not billed twice,
#       and a launch turn replayed into the child is credited to `main`
#   (m) F4/F5 — a meta that is not an object, and a truncated meta: agent type
#       `unknown`, NO inherited label, a warning on stderr, exit 0
#   (n) F6 — a row mixing priced and unpriced turns is marked, not silently partial
#   (o) Opus 5.5 is priced as itself, not by the longest-prefix fallback to Opus 5
#
# Run with: bash skills/audit/tests/test-subagent-spend.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RETRO="$TESTS_DIR/../scripts/usage-retro"
FIXTURE="$TESTS_DIR/fixtures/subagent-spend-corpus.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TX="$(bash "$FIXTURE")"
ERRLOG="$(mktemp)"
cleanup() { rm -rf "$TX" "$ERRLOG"; }
trap cleanup EXIT

OUT="$(python3 "$RETRO/subagent_spend.py" --transcripts-root "$TX" 2>"$ERRLOG")"
rc=$?
[[ $rc -eq 0 ]] || fail "(setup)(m) the script must exit 0 on the fixture corpus (rc=$rc):
$OUT
$(cat "$ERRLOG")"

# row <label-regex> -> the row's 7 fields, space-separated: turns input 5m 1h read out usd
row() {
  printf '%s\n' "$OUT" | python3 -c '
import re, sys
pat = re.compile(sys.argv[1])
for line in sys.stdin:
    line = line.rstrip("\n")
    parts = line.rsplit(None, 7)
    if len(parts) != 8:
        continue
    label = parts[0].strip()
    if pat.fullmatch(label):
        print(" ".join(parts[1:])); break
' "$1"
}

# ---------------------------------------------------------------------------
# (a) THE MAIN ROW, and the <synthetic> exclusion inside it. The fixture's main
#     session has five countable turns; the synthetic placeholder carries 999999 in
#     every class and a FULL usage block, which is what Claude Code writes, so a
#     reader that skips those by text rather than by model banks all of it — and the
#     row still prints. The unpriced turn (n) and the advisor turn (j) are here too.
#       msg_main_1  = (1000*5 + 2000*6.25 + 1000*10 + 10000*0.50 +  500*25) = 45000
#       msg_main_2  = (                               20000*0.50 + 1000*25) = 35000
#       msg_launch  = (   5*5 +                         100*0.50 +   50*25) =  1325
#       msg_main_adv= (   4*5 +                         200*0.50 +   20*25) =   620
#       -> 81945 / 1e6 = 0.081945, and the unpriced turn earns the `*`.
# ---------------------------------------------------------------------------
[[ "$(row 'main')" == "5 1010 2000 1000 30300 1571 0.081945*" ]] \
  || fail "(a)(n) main row wrong: '$(row 'main')' (expected '5 1010 2000 1000 30300 1571 0.081945*')"

printf '%s\n' "$OUT" | grep -q '999999' \
  && fail "(a) a <synthetic> turn's usage reached the table"

# ---------------------------------------------------------------------------
# (b) THE SPLIT MESSAGE. a1's first API message is written twice under one
#     message.id: the partial (output_tokens 1) then the settled one (400).
#     Censused over 300 real agent transcripts: 4,141 duplicate-id groups, the last
#     occurrence is the largest in every one. So the rule is dedupe-and-keep-last.
#     No dedupe  -> 3 turns, output 501. Keep-first -> output 101.
#       USD = (100*5 + 200*6.25 + 0*10 + 3000*0.50 + 500*25) / 1e6 = 0.015750
# ---------------------------------------------------------------------------
a1='claude-opus-5-20260301 / impl-opus'
[[ "$(row "$a1")" == "2 100 200 0 3000 500 0.015750" ]] \
  || fail "(b)(l) a1 row wrong: '$(row "$a1")' (expected '2 100 200 0 3000 500 0.015750')"

# ---------------------------------------------------------------------------
# (c) THE DEFECT THIS INSTRUMENT EXISTS NOT TO REPRODUCE. Every subagent line in
#     the fixture carries isSidechain: true. Under the filter that shipped in the
#     original extractor, all of these turns vanish and only `main` remains.
# ---------------------------------------------------------------------------
# Counted through the same parser the assertions use, not with grep: the header
# line reads "model / agent type" and `grep -c ' / '` would count it as one more row.
sub_rows="$(printf '%s\n' "$OUT" | python3 -c '
import sys
n = 0
for line in sys.stdin:
    parts = line.rstrip("\n").rsplit(None, 7)
    if len(parts) != 8 or " / " not in parts[0]:
        continue
    try:
        [int(x) for x in parts[1:7]]
    except ValueError:
        continue
    n += 1
print(n)')"
[[ "$sub_rows" -eq 10 ]] \
  || fail "(c) expected 10 subagent rows, got $sub_rows — sidechain turns are being dropped"

# ...and the bait must really be there, or (c) is vacuous.
grep -q '"isSidechain": true' "$TX"/*/s1/subagents/agent-a1.jsonl \
  || fail "(c) fixture drift: subagent turns must be marked isSidechain, or (c) proves nothing"

# ---------------------------------------------------------------------------
# (d) THE INHERITED LABEL, both directions. a2 (no `model` key) and a5 (no meta file
#     at all) are inherited; a4 names a model and is NOT — and a4 runs the SAME
#     model as a2 and a5. A reader that labels by model rather than by what the meta
#     asked for marks all three, and a reader that never labels marks none; both
#     pass a one-sided check.
#       a2 USD = (200*2 + 100*2.50 + 0*4 + 5000*0.20 + 300*10) / 1e6 = 0.004650
#       a4 USD = ( 50*2 +   0       + 0   + 1000*0.20 + 100*10) / 1e6 = 0.001300
#       a5 USD = ( 10*2 +   0       + 0   +  100*0.20 +  10*10) / 1e6 = 0.000140
# ---------------------------------------------------------------------------
a2='claude-sonnet-5-20260201 \(inherited\) / lookup-sonnet'
a4='claude-sonnet-5-20260201 / workflow-subagent'
a5='claude-sonnet-5-20260201 \(inherited\) / unknown'

[[ "$(row "$a2")" == "1 200 100 0 5000 300 0.004650" ]] \
  || fail "(d)(g) a2 (inherited) row wrong: '$(row "$a2")'"
[[ "$(row "$a4")" == "1 50 0 0 1000 100 0.001300" ]] \
  || fail "(d)(f) a4 (explicit model, nested) row wrong: '$(row "$a4")'"
[[ "$(row "$a5")" == "1 10 0 0 100 10 0.000140" ]] \
  || fail "(d) a5 (no meta -> unknown, inherited) row wrong: '$(row "$a5")'"

n_inherited="$(printf '%s\n' "$OUT" | grep -c '(inherited)')"
[[ "$n_inherited" -eq 2 ]] \
  || fail "(d)(m) expected exactly 2 inherited rows, got $n_inherited"

# ---------------------------------------------------------------------------
# (e) AN UNPRICED MODEL. The price table is a snapshot with a read date; a model
#     added after it must not be silently priced at zero, which would understate the
#     total while the row still looked complete. Tokens count, USD does not.
# ---------------------------------------------------------------------------
a3='claude-mystery-9-20260101 / probe'
[[ "$(row "$a3")" == "1 10 20 30 40 50 n/a" ]] \
  || fail "(e) unpriced row wrong: '$(row "$a3")' (expected '1 10 20 30 40 50 n/a')"

# ---------------------------------------------------------------------------
# (f) NESTED TRANSCRIPTS. 7,289 of the author's agent transcripts live at
#     subagents/workflows/wf_*/agent-*.jsonl, against 3,164 at subagents/*.jsonl.
#     A one-level glob — which is what the rest of this package uses — sees none of
#     them, and the table would omit two thirds of the corpus without saying so.
#     (d) asserts a4's numbers; this asserts the row exists at all, so a silent
#     rename of the label cannot turn (f) into a pass-by-absence.
# ---------------------------------------------------------------------------
printf '%s\n' "$OUT" | grep -q 'workflow-subagent' \
  || fail "(f) the nested subagents/workflows/ transcript was not walked"

# ---------------------------------------------------------------------------
# (j) F1 — THE ADVISOR ITERATION, THE BLOCKER. A settled message's top-level usage
#     is the sum of its `type: "message"` iterations ONLY. A `type: "advisor_message"`
#     iteration carries its own model and its own tokens, is billed separately, and
#     appears nowhere in that block. Corpus-wide: 20,736 of them.
#
#     Two directions, and both are needed. Losing them understates the total; folding
#     them into the parent's row PRICES OPUS WORK AT SONNET, which is the one number
#     this table exists to get right.
#       advisor USD = (1000*5 + 200*25) / 1e6 = 0.010000   <- opus rates
#       parent  USD = (   2*2 + 100*10) / 1e6 = 0.001004   <- sonnet rates, unchanged
# ---------------------------------------------------------------------------
a6adv='claude-opus-5-20260301 \(advisor\) / advisor-host'
a6par='claude-sonnet-5-20260201 / advisor-host'
[[ "$(row "$a6adv")" == "1 1000 0 0 0 200 0.010000" ]] \
  || fail "(j) the subagent advisor row is wrong or missing: '$(row "$a6adv")' (expected '1 1000 0 0 0 200 0.010000')"
[[ "$(row "$a6par")" == "1 2 0 0 0 100 0.001004" ]] \
  || fail "(j) the advisor's parent turn must keep ONLY its own top-level usage: '$(row "$a6par")'"

# The main session has advisors too, and `main` must stay ONE comparable line, so
# they get their own row rather than inflating it.
mainadv='main \(advisor\) claude-sonnet-5-20260201'
[[ "$(row "$mainadv")" == "1 500 0 0 0 30 0.001300" ]] \
  || fail "(j) the main-session advisor row is wrong or missing: '$(row "$mainadv")'"

# An advisor row names an explicit model, so it is never labelled inherited — guarded
# by (d)'s count of exactly 2, and named here so the reason is not lost.

# ---------------------------------------------------------------------------
# (k) F2 — THE STALE DICT. On a multi-iteration message the flat
#     `cache_creation_input_tokens` is the aggregate (8480) while
#     `cache_creation.ephemeral_5m_input_tokens` still holds iteration 0 alone
#     (6976). Preferring the dict — which every prior reader does, including the
#     delegation hook — loses 1504 tokens on this one turn and 14.5M corpus-wide.
#       USD = (34*2 + 8480*2.50 + 0*4 + 43490*0.20 + 2839*10) / 1e6 = 0.058356
#     Under the dict-first rule it reads 8480 -> 6976 and USD 0.054596.
# ---------------------------------------------------------------------------
a7='claude-sonnet-5-20260201 / stale-dict'
[[ "$(row "$a7")" == "1 34 8480 0 43490 2839 0.058356" ]] \
  || fail "(k) stale-dict row wrong: '$(row "$a7")' (expected '1 34 8480 0 43490 2839 0.058356')"

# ---------------------------------------------------------------------------
# (l) F3 — DEDUPE IS PER PROJECT. Two shapes, one rule.
#
#     The resume: Claude Code replays the parent session's records verbatim into the
#     new `<uuid>.jsonl` (571 of 571 real main-vs-main duplicate ids carry identical
#     tokens). Per-FILE dedupe bills `msg_main_1` twice — 1,499 ids corpus-wide.
#     Asserted by (a): main is 5 turns and 1010 input, not 6 and 2010.
#
#     The launch replay: the parent's `msg_launch` turn is copied into the CHILD's
#     transcript as launch context, with a stale output_tokens (7 against 50). 7 real
#     cases. It is credited to `main` — the parent produced it, and charging the
#     parent's thinking to the child corrupts exactly the comparison this table is
#     for. Asserted by (a) (main input includes the 5) and (b) (a1 is 2 turns, not 3).
#     Both directions below, so a walker that simply drops the id everywhere, or one
#     that lets the child win, is caught.
# ---------------------------------------------------------------------------
grep -q 'msg_launch' "$TX"/*/s1/subagents/agent-a1.jsonl \
  || fail "(l) fixture drift: a1 must replay the parent's launch turn, or (l) is vacuous"
grep -q 'msg_main_1' "$TX"/*/s1-resumed.jsonl \
  || fail "(l) fixture drift: the resumed session must replay msg_main_1, or (l) is vacuous"

# ---------------------------------------------------------------------------
# (m) F4/F5 — A BROKEN META IS NOT AN "INHERITED UNKNOWN". a8's meta is valid JSON
#     that is not an object (`.get` on a list raised AttributeError and took the
#     whole report down); a9's is truncated mid-write. Folding either into the
#     no-meta bucket is worse than the crash: the row then claims the model was
#     inherited — a fact about the launch — when the truth is that nobody could read
#     the file. So: `unknown` type, NO inherited label, one stderr line naming the
#     path, exit 0.
#       a8 USD = (7*2 + 70*0.20 + 7*10) / 1e6 = 0.000098   (sonnet)
#       a9 USD = (3*5 + 30*0.50 + 3*25) / 1e6 = 0.000105   (opus)
# ---------------------------------------------------------------------------
a8='claude-sonnet-5-20260201 / unknown'
a9='claude-opus-5-20260301 / unknown'
[[ "$(row "$a8")" == "1 7 0 0 70 7 0.000098" ]] \
  || fail "(m) the non-object meta row is wrong or still labelled inherited: '$(row "$a8")'"
[[ "$(row "$a9")" == "1 3 0 0 30 3 0.000105" ]] \
  || fail "(m) the truncated meta row is wrong or still labelled inherited: '$(row "$a9")'"

for bad in agent-a8 agent-a9; do
  grep -q "$bad.meta.json" "$ERRLOG" \
    || fail "(m) nothing on stderr named the unreadable meta $bad.meta.json: $(cat "$ERRLOG")"
done
# ...and a MISSING meta (a5) is a different case and must stay silent.
grep -q 'agent-a5.meta.json' "$ERRLOG" \
  && fail "(m) a missing meta is normal and must not warn: $(cat "$ERRLOG")"

# ---------------------------------------------------------------------------
# (n) F6 — A PARTIAL USD IS MARKED. `main` mixes a priced model with an unpriced one,
#     so its USD is a partial sum. Printed bare it is indistinguishable from a
#     complete one, and `main` is the line every subagent row is compared against.
#     `n/a` stays for a row with NO priced turn (e), and the footer explains both.
# ---------------------------------------------------------------------------
[[ "$(row 'main')" == *"*" ]] \
  || fail "(n) a row with an unpriced turn must be marked: '$(row 'main')'"
[[ "$(row "$a1")" != *"*" ]] \
  || fail "(n) a fully priced row must NOT be marked: '$(row "$a1")'"
printf '%s\n' "$OUT" | grep -q '2 turn(s)' \
  || fail "(n) the footer must count the unpriced turns (expected 2): $OUT"

# ---------------------------------------------------------------------------
# (h) THE TOTAL. Asserted twice on purpose: against the hand sum, and against the
#     rows the script itself printed. The first catches a wrong row, the second
#     catches a total computed from a different collection than the one displayed.
# ---------------------------------------------------------------------------
[[ "$(row 'TOTAL')" == "17 2926 10800 1030 83030 5710 0.174648*" ]] \
  || fail "(h) TOTAL row wrong: '$(row 'TOTAL')' (expected '17 2926 10800 1030 83030 5710 0.174648*')"

sum_check="$(printf '%s\n' "$OUT" | python3 -c '
import sys
cols, total = [0]*6, None
usd = 0.0
for line in sys.stdin:
    parts = line.rstrip("\n").rsplit(None, 7)
    if len(parts) != 8:
        continue
    label = parts[0].strip()
    try:
        nums = [int(x) for x in parts[1:7]]
    except ValueError:
        continue
    money = parts[7].rstrip("*")
    if label == "TOTAL":
        total = (nums, money); continue
    cols = [a + b for a, b in zip(cols, nums)]
    if money != "n/a":
        usd += float(money)
if total is None:
    print("NO-TOTAL-ROW")
elif total[0] != cols:
    print("TOKENS %s != %s" % (total[0], cols))
elif abs(float(total[1]) - usd) > 5e-7:
    print("USD %s != %.6f" % (total[1], usd))
else:
    print("OK")')"
[[ "$sum_check" == "OK" ]] \
  || fail "(h) the TOTAL row is not the sum of the printed rows: $sum_check"

# ---------------------------------------------------------------------------
# (i) --transcripts-root is a real parameter. If it were ignored, every assertion
#     above would be reading the author's real transcript tree and would still look
#     green — the failure mode test-mine-preferences.sh case (g) was written for.
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d)"
out_i="$(python3 "$RETRO/subagent_spend.py" --transcripts-root "$EMPTY" 2>&1)"; rc_i=$?
rm -rf "$EMPTY"
[[ $rc_i -ne 0 ]] || fail "(i) an empty corpus must not exit 0: $out_i"
printf '%s\n' "$out_i" | grep -qi 'no assistant turns' \
  || fail "(i) an empty corpus should say so, not print a table of zeroes: $out_i"

# ---------------------------------------------------------------------------
# (o) Opus 5.5 is priced as itself. With no `claude-opus-5-5` row, the longest-prefix
#     lookup fell back to `claude-opus-5` and billed Opus 5.5 at $5/$25/$0.50: every
#     Opus 5.5 row came out inflated (cache reads 2.5x) and still looked well-formed.
#     Prices: claude.dev "What a task costs on Opus 5.5" (2026-09-25).
# ---------------------------------------------------------------------------
for m in claude-opus-5-5 claude-opus-5-5-20260922; do
  got_o="$(cd "$RETRO" && python3 -c "import pricing; print(pricing.prices_for('$m'))")"
  [[ "$got_o" == "(4, 5, 8, 0.2, 20)" ]] \
    || fail "(o) $m must price as Opus 5.5 (4, 5, 8, 0.2, 20), got $got_o"
done
got_o5="$(cd "$RETRO" && python3 -c "import pricing; print(pricing.prices_for('claude-opus-5'))")"
[[ "$got_o5" == "(5, 6.25, 10, 0.5, 25)" ]] || fail "(o) claude-opus-5 must keep its own row, got $got_o5"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — subagent_spend: <synthetic> excluded, split message.id counted once from the last line, dedupe per PROJECT with the launch replay credited to main, non-message iterations priced on their own model, flat cache-creation beats a stale dict, sidechain turns attributed, inherited label only where the meta named no model, broken meta warns without inheriting, partial USD marked, TOTAL equals the printed rows"
