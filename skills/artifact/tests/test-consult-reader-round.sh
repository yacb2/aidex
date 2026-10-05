#!/usr/bin/env bash
# test-consult-reader-round.sh — BL-507: `consult-round` is the READER's round.
#
# It used to count passing wraps (the moving baseline), so an owner-questions page
# read 'ronda 16' after 4 reader rounds and a hard "no new round without the saved
# reply" rule could not be written. It now advances only when save-reply.sh has
# snapshotted the page the reader answered (`.answered.html`, which carries the
# round it answered) at or past the baseline's round.
# Layer: shell integration on the real wrapper (the decision is a file-system
# state machine across wrap-report.sh and save-reply.sh; no unit boundary owns it).
set -uo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
WRAP="$SKILL/scripts/wrap-report.sh"
SAVE="$SKILL/scripts/save-reply.sh"
KIT="$SKILL/assets/artifact-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
ok()   { printf 'ok   — %s\n' "$*"; }

mkdir -p "$TMP/reports"
PG="$TMP/reports/c.html"
round_of() { sed -nE 's/.*<meta name="consult-round" content="([0-9]+)">.*/\1/p' "$1" | sed -n 1p; }
wrap() { bash "$WRAP" --title "Consultation" --lang en --in "$KIT/skeleton.html" --out "$PG" "$@" 2>&1; }
reply() { printf 'Q1: fine as is\n' | bash "$SAVE" "$PG" - >/dev/null 2>&1; }

# (c) first round
wrap >/dev/null || fail "(c) the first wrap failed"
[[ "$(round_of "$PG")" == "1" ]] && ok "(c) a first page is round 1" \
  || fail "(c) a first page is not round 1 (got '$(round_of "$PG")')"

# (a) three wraps between two save-reply calls keep one round number
wrap >/dev/null; wrap >/dev/null
[[ "$(round_of "$PG")" == "1" ]] && ok "(a) re-wraps before any reply stay round 1" \
  || fail "(a) two re-wraps of round 1 read round '$(round_of "$PG")'"
reply
wrap >/dev/null
[[ "$(round_of "$PG")" == "2" ]] || fail "(a) the wrap after a saved reply is not round 2 (got '$(round_of "$PG")')"
wrap >/dev/null; wrap >/dev/null
[[ "$(round_of "$PG")" == "2" ]] && ok "(a) three wraps between two replies read one round" \
  || fail "(a) re-wraps of round 2 advanced it to '$(round_of "$PG")'"
reply
wrap >/dev/null
[[ "$(round_of "$PG")" == "3" ]] && ok "(a) the second saved reply opens round 3" \
  || fail "(a) after the second reply the round is '$(round_of "$PG")', expected 3"

# (b) --new-round means "this wrap must advance the reader round": on a consult page
# past round 1 it is refused unless the current round has a saved reply.
# Fresh page: wrap, then --new-round with no reply is refused, page untouched.
BP="$TMP/reports/b.html"
bwrap() { bash "$WRAP" --title "Consultation" --lang en --in "$KIT/skeleton.html" --out "$BP" "$@" 2>&1; }
bwrap >/dev/null || fail "(b) the first wrap of the fresh page failed"
before="$(cat "$BP")"
out="$(bwrap --new-round)"; rc=$?
if [[ $rc -ne 0 && "$out" == *save-reply.sh* && "$out" == *--new-round* && "$out" == *"round 1 "* ]]; then
  ok "(b) wrap then --new-round with no reply is refused, naming save-reply.sh, --new-round and round 1"
else fail "(b) --new-round over an unanswered round exited $rc / message wrong: $out"; fi
[[ "$(round_of "$BP")" == "1" && "$(cat "$BP")" == "$before" ]] \
  && ok "(b) the refused wrap left the page byte-identical at round 1" \
  || fail "(b) the refused wrap changed the page or round (got '$(round_of "$BP")')"
# reply, --new-round opens round 2, a repeat --new-round inside it is refused, a plain wrap passes
printf 'Q1: ok\n' | bash "$SAVE" "$BP" - >/dev/null 2>&1
bwrap --new-round >/dev/null && [[ "$(round_of "$BP")" == "2" ]] \
  && ok "(b) reply then --new-round opens round 2" \
  || fail "(b) --new-round over a saved reply did not open round 2 (got '$(round_of "$BP")')"
before="$(cat "$BP")"
out="$(bwrap --new-round)"; rc=$?
if [[ $rc -ne 0 && "$out" == *save-reply.sh* && "$out" == *"round 2 "* && "$(cat "$BP")" == "$before" ]]; then
  ok "(b) a repeat --new-round inside the round it opened is refused"
else fail "(b) a repeat --new-round exited $rc / page changed / message wrong: $out"; fi
bwrap >/dev/null && [[ "$(round_of "$BP")" == "2" ]] \
  && ok "(b) a plain wrap after the refusal passes and stays round 2" \
  || fail "(b) the plain wrap after a refused --new-round failed or moved the round (got '$(round_of "$BP")')"

# Same on the long-running page (round 3 here): reply -> round 4, repeat refused.
reply
wrap --new-round >/dev/null && [[ "$(round_of "$PG")" == "4" ]] \
  && ok "(b) --new-round over a saved reply opens round 4" \
  || fail "(b) --new-round after a saved reply did not open round 4 (got '$(round_of "$PG")')"
out="$(wrap --new-round)"; rc=$?
[[ $rc -ne 0 && "$(round_of "$PG")" == "4" ]] \
  && ok "(b) a second --new-round in the same round is refused and stays round 4" \
  || fail "(b) a second --new-round in round 4 exited $rc (round '$(round_of "$PG")')"
# Legacy page (from before save-reply existed: no answered snapshot at all): refused too.
rm -f "$TMP/reports/.aidex-artifact-prev/c.answered.html"
before="$(cat "$PG")"
out="$(wrap --new-round)"; rc=$?
if [[ $rc -ne 0 && "$out" == *save-reply.sh* ]]; then ok "(b) legacy page with no answered snapshot: --new-round fails, naming save-reply.sh"
else fail "(b) legacy --new-round exited $rc / did not name save-reply.sh: $out"; fi
[[ "$(cat "$PG")" == "$before" ]] || fail "(b) the refused wrap changed the page on disk"

# (c) first round with the flag, and a page with no consult surface, are unaffected
NP="$TMP/reports/n.html"
printf '<div class="page"><main class="main"><h1>Read</h1></main></div>\n' > "$TMP/read.html"
bash "$WRAP" --title Read --lang en --in "$TMP/read.html" --out "$NP" >/dev/null 2>&1 \
  && bash "$WRAP" --title Read --lang en --in "$TMP/read.html" --out "$NP" >/dev/null 2>&1 \
  && [[ "$(round_of "$NP")" == "2" ]] \
  && ok "(c) a page with no consult surface keeps counting wraps and needs no reply" \
  || fail "(c) a no-surface page re-wrap failed or changed round (got '$(round_of "$NP")')"
FP="$TMP/reports/f.html"
bash "$WRAP" --title Consultation --lang en --in "$KIT/skeleton.html" --out "$FP" --new-round >/dev/null 2>&1 \
  && [[ "$(round_of "$FP")" == "1" ]] \
  && ok "(c) the first round needs no reply, even declared" \
  || fail "(c) a first wrap with --new-round was refused or is not round 1"

# (d) The spec route: pages are built with spec_build.py, which runs the wrap
# itself, so --new-round must reach the wrap through it (echo_lab replay,
# 2026-09-29: spec_build.py refused the flag as an unknown argument).
BUILD="$SKILL/scripts/spec_build.py"
SP="$TMP/reports/s.spec.md"
cat > "$SP" <<'SPEC'
::: masthead {lang="en" visual="none: consultation"}
# Spec route
:::

::: group {#G1 title="One"}
::: item {#Q1 title="Pick"}
Ana opens the project and sees no Delete button.

- Allow it {recommended}
- Keep it
:::
:::

::: notes {title="Anything else"}
:::
SPEC
SPG="$TMP/reports/s.html"
python3 "$BUILD" "$SP" -o "$SPG" >/dev/null 2>&1 || fail "(d) the first spec build failed"
out="$(python3 "$BUILD" "$SP" -o "$SPG" --new-round 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *save-reply.sh* ]] \
  && ok "(d) spec_build --new-round with no saved reply is refused, naming save-reply.sh" \
  || fail "(d) spec_build --new-round with no saved reply exited $rc: $out"
printf 'Q1: fine as is\n' | bash "$SAVE" "$SPG" - >/dev/null 2>&1
python3 "$BUILD" "$SP" -o "$SPG" --new-round >/dev/null 2>&1 && [[ "$(round_of "$SPG")" == "2" ]] \
  && ok "(d) spec_build --new-round over a saved reply opens round 2" \
  || fail "(d) spec_build --new-round over a saved reply did not open round 2 (got '$(round_of "$SPG")')"

# (e) BL-534 GUARD (never went red: the filer could not reproduce it and neither
# could we on the real cola-barrido spec, whose meta and rail line both read 2).
# The rail's "ronda N"/"round N" line and the consult-round meta are two
# renderings of one fact; pin that they agree at every round of the page above
# (round 4, a replied round, and the spec route in Spanish).
shown_of() { sed -nE 's/.*class="railbuilt"[^>]*>[^<]*(round|ronda) ([0-9]+).*/\2/p' "$1" | sed -n 1p; }
for pg in "$PG" "$BP" "$SPG"; do
  [[ -n "$(shown_of "$pg")" && "$(shown_of "$pg")" == "$(round_of "$pg")" ]] \
    && ok "(e) $(basename "$pg"): the rail round ($(shown_of "$pg")) equals consult-round" \
    || fail "(e) $(basename "$pg"): rail round '$(shown_of "$pg")' != consult-round '$(round_of "$pg")'"
done
ES="$TMP/reports/es.spec.md"; sed 's/lang="en"/lang="es"/' "$SP" > "$ES"
ESG="$TMP/reports/es.html"
python3 "$BUILD" "$ES" -o "$ESG" >/dev/null 2>&1; printf 'Q1: bien\n' | bash "$SAVE" "$ESG" - >/dev/null 2>&1
python3 "$BUILD" "$ES" -o "$ESG" --new-round >/dev/null 2>&1
[[ "$(round_of "$ESG")" == "2" && "$(shown_of "$ESG")" == "2" ]] \
  && ok "(e) a Spanish spec page reads ronda 2 in the rail and in consult-round" \
  || fail "(e) es page: meta '$(round_of "$ESG")', rail '$(shown_of "$ESG")'"

# (f) BL-701: a BLOCK note sits under its `## ` heading in the reply and must survive the round:
# it is not an item answer (no `### `), and a marker-shaped line typed in it belongs to the block,
# never to the last item of the block before it. G2's note carries `- [show-me]`, a duty only an
# ITEM can own: save-reply must not charge it to Q1, and the next round must still open.
SP2="$TMP/reports/blk.spec.md"
cat > "$SP2" <<'SPEC'
::: masthead {lang="en" visual="none: consultation"}
# Block notes
:::

::: group {#G1 title="One"}
::: item {#Q1 title="Pick"}
Ana opens the project and sees no Delete button.

- Allow it {recommended}
- Keep it
:::
:::

::: group {#G2 title="Two"}
::: item {#Q2 title="Pick again"}
Ana opens the list and sees no filter.

- Add it {recommended}
- Skip it
:::
:::

::: notes {title="Anything else"}
:::
SPEC
SPB="$TMP/reports/blk.html"
python3 "$BUILD" "$SP2" -o "$SPB" >/dev/null 2>&1 || fail "(f) the block-notes spec build failed"
REPLY_B=$'## G1 \xc2\xb7 One\n\nthis whole block is fine\n\n### Q1 \xc2\xb7 Pick\n\n- Keep it\n\n## G2 \xc2\xb7 Two\n\n- [show-me]\n\n### Q2 \xc2\xb7 Pick again\n\n- Skip it\n'
out="$(printf '%s' "$REPLY_B" | bash "$SAVE" "$SPB" - 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" != *Q1* ]] \
  && ok "(f) a block note with a marker-shaped line is not charged to the item before it" \
  || fail "(f) save-reply charged the G2 note's [show-me] to Q1 (rc=$rc): $out"
python3 "$BUILD" "$SP2" -o "$SPB" --new-round >/dev/null 2>&1 && [[ "$(round_of "$SPB")" == "2" ]] \
  && ok "(f) the round after a reply with block notes opens" \
  || fail "(f) the round after a reply with block notes did not open (got '$(round_of "$SPB")')"

[[ $failures -eq 0 ]] && echo "PASS: consult reader round" || { echo "FAILED: $failures"; exit 1; }
