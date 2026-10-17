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
# The Spanish spec carries a Spanish body: since 25fb616a the builder refuses a
# masthead language over a body written in the other one.
ES="$TMP/reports/es.spec.md"
cat > "$ES" <<'SPEC'
::: masthead {lang="es" visual="none: consultation"}
# Ruta del spec
:::

::: group {#G1 title="Uno"}
::: item {#Q1 title="Elegir"}
Ana abre el proyecto y no ve el botón de borrar.

- Permitirlo {recommended}
- Dejarlo como está
:::
:::

::: notes {title="Algo más"}
:::
SPEC
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
REPLY_B=$'## G1 \xc2\xb7 One\n\nthis whole block is fine\n\n### Q1 \xc2\xb7 Pick\n\n- Keep it\n\nnot sure yet\n\n## G2 \xc2\xb7 Two\n\n- [show-me]\n\n### Q2 \xc2\xb7 Pick again\n\n- Skip it\n'
out="$(printf '%s' "$REPLY_B" | bash "$SAVE" "$SPB" - 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" != *Q1* ]] \
  && ok "(f) a block note with a marker-shaped line is not charged to the item before it" \
  || fail "(f) save-reply charged the G2 note's [show-me] to Q1 (rc=$rc): $out"
# the reader picked Q2 and asked nothing back: a round that opens must decide it.
# Q1 (option + note) stays open so G2's [show-me] could still be wrongly charged to it.
sed -i.bak 's/{#Q2 title="Pick again"}/{#Q2 title="Pick again" decided="Skip it"}/' "$SP2"
python3 "$BUILD" "$SP2" -o "$SPB" --new-round >/dev/null 2>&1 && [[ "$(round_of "$SPB")" == "2" ]] \
  && ok "(f) the round after a reply with block notes opens" \
  || fail "(f) the round after a reply with block notes did not open (got '$(round_of "$SPB")')"

# (g) A page that was plain before: the guard counts the surface-less baseline's
# wrap count as an open reader round. The first wrap that gives it a consult
# surface is reader round 1 (next_round resets), so --new-round must pass there
# exactly as it does on a brand-new page (c), not refuse "round N already open".
GP="$TMP/reports/g.html"
for _ in 1 2; do
  bash "$WRAP" --title Read --lang en --in "$TMP/read.html" --out "$GP" >/dev/null 2>&1 \
    || fail "(g) a plain wrap failed"
done
out="$(bash "$WRAP" --title Consultation --lang en --in "$KIT/skeleton.html" --out "$GP" --new-round 2>&1)"; rc=$?
[[ $rc -eq 0 && "$(round_of "$GP")" == "1" ]] \
  && ok "(g) the first consult wrap over a plain page takes --new-round and is round 1" \
  || fail "(g) --new-round on the first consult wrap over a plain page exited $rc (round '$(round_of "$GP")'): $out"

# (h) BL-824: a round the SESSION opens without a reply. `consult-round` (and the rail's
# "ronda N") only advanced on a saved reply, while the masthead eyebrow the session types
# said "ronda N+1": the two disagreed on every such round. `--new-round --no-reply` opens
# the round with a separate marker (never the answered snapshot: spec_verbs would expire
# proposals the reader never saw), and check-artifact FAILS an eyebrow round that differs
# from the page's consult-round.
NR="$TMP/reports/nr.spec.md"
cat > "$NR" <<'SPEC'
::: masthead {lang="es" eyebrow="Consulta · ronda 1" visual="none: consultation"}
# Ronda sin respuesta
:::

::: group {#G1 title="Uno"}
::: item {#Q1 title="Elegir"}
Ana abre el proyecto y no ve el botón de borrar.

- Permitirlo {recommended}
- Dejarlo como está
:::
:::

::: notes {title="Algo más"}
:::
SPEC
NRG="$TMP/reports/nr.html"
NRA="$TMP/reports/.aidex-artifact-prev/nr.answered.html"
nrbuild() { python3 "$BUILD" "$NR" -o "$NRG" "$@" 2>&1; }
brow() { sed -i.bak -E "s/eyebrow=\"[^\"]*\"/eyebrow=\"$1\"/" "$NR"; }
nrbuild >/dev/null || fail "(h) the first no-reply spec build failed"
# (d) the gap itself: eyebrow says ronda 2 over consult-round 1 -> FAIL, page untouched
brow "Consulta · ronda 2"
before="$(cat "$NRG")"
out="$(nrbuild)"; rc=$?
[[ $rc -ne 0 && "$out" == *consult-round-eyebrow* && "$out" == *--no-reply* && "$(cat "$NRG")" == "$before" ]] \
  && ok "(h) an eyebrow naming ronda 2 over consult-round 1 FAILS, naming --no-reply" \
  || fail "(h) eyebrow ronda 2 over consult-round 1 exited $rc / message wrong: $out"
# (b) --no-reply alone is a usage error, on both entry points
out="$(nrbuild --no-reply)"; rc=$?
[[ $rc -ne 0 && "$out" == *"--no-reply needs --new-round"* && "$(cat "$NRG")" == "$before" ]] \
  && ok "(h) spec_build --no-reply without --new-round is refused" \
  || fail "(h) spec_build --no-reply alone exited $rc: $out"
out="$(bwrap --no-reply)"; rc=$?
[[ $rc -ne 0 && "$out" == *"--no-reply needs --new-round"* ]] \
  && ok "(h) wrap-report --no-reply without --new-round is refused" \
  || fail "(h) wrap-report --no-reply alone exited $rc: $out"
# the refusal of --new-round over an unanswered round names the third path
out="$(nrbuild --new-round)"; rc=$?
[[ $rc -ne 0 && "$out" == *--no-reply* ]] \
  && ok "(h) --new-round over an unanswered round names --no-reply" \
  || fail "(h) the --new-round refusal does not name --no-reply: $out"
# (a) the session opens round 2 with no reply: meta and rail both say 2
out="$(nrbuild --new-round --no-reply)"; rc=$?
[[ $rc -eq 0 && "$(round_of "$NRG")" == "2" && "$(shown_of "$NRG")" == "2" ]] \
  && ok "(h) --new-round --no-reply on unanswered round 1 opens round 2 (meta and rail)" \
  || fail "(h) --new-round --no-reply exited $rc: meta '$(round_of "$NRG")', rail '$(shown_of "$NRG")': $out"
# (c) and it wrote no answered snapshot
[[ ! -e "$NRA" ]] && ok "(h) --no-reply created no answered snapshot" \
  || fail "(h) --no-reply created $NRA"
nrbuild >/dev/null; nrbuild >/dev/null
[[ "$(round_of "$NRG")" == "2" ]] && ok "(h) plain re-wraps of the no-reply round stay round 2" \
  || fail "(h) a plain re-wrap after --no-reply moved the round to '$(round_of "$NRG")'"
# (b) --no-reply over a round that HAS a saved reply is refused; (c) the snapshot is untouched
printf 'Q1: bien\n' | bash "$SAVE" "$NRG" - >/dev/null 2>&1
snap="$(cat "$NRA" 2>/dev/null)"
brow "Consulta · ronda 3"
out="$(nrbuild --new-round --no-reply)"; rc=$?
[[ $rc -ne 0 && "$out" == *--no-reply* && "$out" == *"saved reply"* && "$(round_of "$NRG")" == "2" ]] \
  && ok "(h) --no-reply over a round with a saved reply is refused" \
  || fail "(h) --no-reply over a saved reply exited $rc (round '$(round_of "$NRG")'): $out"
[[ -n "$snap" && "$(cat "$NRA")" == "$snap" ]] && ok "(h) the refused --no-reply left the answered snapshot as it was" \
  || fail "(h) the answered snapshot changed or is missing"
nrbuild --new-round >/dev/null && [[ "$(round_of "$NRG")" == "3" ]] \
  && ok "(h) save-reply then --new-round after a no-reply round opens round 3" \
  || fail "(h) --new-round over the saved reply did not open round 3 (got '$(round_of "$NRG")')"
# (e) a --new-round --no-reply wrap that FAILS the contract leaves no trace: the marker is
# unchanged and a plain wrap stays at round 3; the fixed wrap repeats the flags: one advance
NRM="$TMP/reports/.aidex-artifact-prev/nr.closed-round"
mark="$(cat "$NRM" 2>/dev/null)"
brow "Consulta · ronda 9"
out="$(nrbuild --new-round --no-reply)"; rc=$?
[[ $rc -ne 0 && "$(round_of "$NRG")" == "3" && "$(cat "$NRM" 2>/dev/null)" == "$mark" ]] \
  && ok "(h) a failed --no-reply wrap left the closed-round marker as it was" \
  || fail "(e) the bad-eyebrow --no-reply wrap rc=$rc, round '$(round_of "$NRG")', marker '$(cat "$NRM" 2>/dev/null)' (was '$mark')"
brow "Consulta · ronda 3"
nrbuild >/dev/null && [[ "$(round_of "$NRG")" == "3" ]] \
  && ok "(h) the plain wrap after a failed --no-reply stays round 3" \
  || fail "(h) the plain wrap after a failed --no-reply landed round '$(round_of "$NRG")'"
brow "Consulta · ronda 4"
nrbuild --new-round --no-reply >/dev/null && [[ "$(round_of "$NRG")" == "4" && "$(shown_of "$NRG")" == "4" ]] \
  && ok "(h) a failed --no-reply wrap then the fixed one advance the round once (3 -> 4)" \
  || fail "(h) failed-then-fixed --no-reply wraps landed round '$(round_of "$NRG")', rail '$(shown_of "$NRG")'"
# (d) passes: an eyebrow with no round, and English "round 3" over consult-round 3
brow "Consulta · cifras declaradas"
nrbuild >/dev/null && ok "(h) an eyebrow naming no round passes" \
  || fail "(h) an eyebrow with no round failed the build"
sed -i.bak 's/^::: masthead {lang="en" visual/::: masthead {lang="en" eyebrow="Consultation · round 3" visual/' "$SP"
SPA="$TMP/reports/.aidex-artifact-prev/s.answered.html"
snap="$(cat "$SPA")"
out="$(python3 "$BUILD" "$SP" -o "$SPG" --new-round --no-reply 2>&1)"; rc=$?
[[ -n "$snap" && "$(cat "$SPA")" == "$snap" ]] && ok "(h) a passing --no-reply over an older snapshot left it byte-identical" \
  || fail "(h) the passing --no-reply changed or lost $SPA"
[[ $rc -eq 0 && "$(round_of "$SPG")" == "3" ]] \
  && ok "(h) English 'Consultation · round 3' over consult-round 3 passes (snapshot 1, no-reply 2)" \
  || fail "(h) the English round-3 page exited $rc (round '$(round_of "$SPG")'): $out"

# (i) BL-824 edges of --no-reply, one page per case. Each page starts as a round-1
# Spanish consultation built once (newpage), then runs one sequence.
VERBS="$SKILL/scripts/spec_verbs.py"
newpage() {   # newpage <name> <eyebrow>
  IS="$TMP/reports/$1.spec.md"; IG="$TMP/reports/$1.html"
  IP="$TMP/reports/.aidex-artifact-prev"; IM="$IP/$1.closed-round"; IB="$IP/$1.html"
  sed "s/eyebrow=\"Consulta · ronda 1\"/eyebrow=\"$2\"/" "$NR" > "$IS"
  python3 "$BUILD" "$IS" -o "$IG" >/dev/null 2>&1 || fail "(i) $1: the first build failed"
}
ibuild() { python3 "$BUILD" "$IS" -o "$IG" "$@" 2>&1; }
ibrow() { sed -i.bak -E "s/eyebrow=\"[^\"]*\"/eyebrow=\"$1\"/" "$IS"; }
eyebrow_line() { printf '%s\n' "$1" | grep 'consult-round-eyebrow'; }
sed -i.bak -E 's/eyebrow="[^"]*"/eyebrow="Consulta · ronda 1"/' "$NR"

# A mistaken --new-round --no-reply over eyebrow "ronda 1" (a re-wrap was meant) fails,
# leaves no marker, and says to drop the flags; the plain re-wrap then passes at round 1.
newpage mistaken "Consulta · ronda 1"
out="$(ibuild --new-round --no-reply)"; rc=$?; line="$(eyebrow_line "$out")"
[[ $rc -ne 0 && ! -e "$IM" && "$(round_of "$IG")" == "1" ]] \
  && ok "(i) mistaken --no-reply: the failed wrap leaves no .closed-round" \
  || fail "(i) mistaken --no-reply: rc=$rc, marker '$(cat "$IM" 2>/dev/null)', round '$(round_of "$IG")'"
[[ "$line" == *drop* && "$line" != *"correct the eyebrow"* ]] \
  && ok "(i) mistaken --no-reply: the message says to drop the flags" \
  || fail "(i) mistaken --no-reply: message wrong: $line"
out="$(ibuild)"; rc=$?
[[ $rc -eq 0 && "$(round_of "$IG")" == "1" ]] \
  && ok "(i) mistaken --no-reply: the plain wrap after it stays round 1" \
  || fail "(i) mistaken --no-reply: the plain wrap rc=$rc, round '$(round_of "$IG")': $out"

# An eyebrow BELOW the meta on a plain wrap (the meta came from a reply): the message
# offers only the eyebrow fix, because --no-reply can only raise the meta.
newpage below "Consulta · cifras"
printf 'Q1: bien\n' | bash "$SAVE" "$IG" - >/dev/null 2>&1
ibuild --new-round >/dev/null || fail "(i) below: --new-round over the reply failed"
ibrow "Consulta · ronda 1"
out="$(ibuild)"; rc=$?; line="$(eyebrow_line "$out")"
[[ $rc -ne 0 && "$line" == *"correct the eyebrow"* && "$line" != *--no-reply* ]] \
  && ok "(i) eyebrow below the meta: the message offers only the eyebrow fix" \
  || fail "(i) eyebrow below the meta: rc=$rc, message wrong: $line"

# Re-running --new-round --no-reply inside the round it just opened FAILS the eyebrow
# rule, says to drop the flags (correcting the eyebrow would skip a round), leaves the
# marker unchanged, and the next plain wrap passes at page 2, baseline 2.
newpage repeat "Consulta · ronda 1"
ibrow "Consulta · ronda 2"
ibuild --new-round --no-reply >/dev/null || fail "(i) repeat: --new-round --no-reply failed"
mark="$(cat "$IM" 2>/dev/null)"
out="$(ibuild --new-round --no-reply)"; rc=$?; line="$(eyebrow_line "$out")"
[[ $rc -ne 0 && -n "$line" && "$(cat "$IM" 2>/dev/null)" == "$mark" && -n "$mark" ]] \
  && ok "(i) repeat: a repeated --no-reply FAILS the eyebrow rule and leaves the marker ($mark)" \
  || fail "(i) repeat: rc=$rc, marker '$(cat "$IM" 2>/dev/null)' (was '$mark'): $out"
[[ "$line" == *drop* && "$line" != *"correct the eyebrow"* ]] \
  && ok "(i) repeat: the message says to drop the flags, not to correct the eyebrow" \
  || fail "(i) repeat: message wrong: $line"
out="$(ibuild)"; rc=$?
[[ $rc -eq 0 && "$(round_of "$IG")" == "2" && "$(round_of "$IB")" == "2" ]] \
  && ok "(i) repeat: the plain wrap after it passes at page 2, baseline 2" \
  || fail "(i) repeat: plain rc=$rc, page '$(round_of "$IG")', baseline '$(round_of "$IB")': $out"

# A marker from an EARLIER no-reply round exempts nothing later: round 1 closed with no
# reply, the reader then picked only an option for Q1 on round 2, and opening round 3
# with Q1 still open FAILS consult-round-pick.
newpage pickgate "Consulta · ronda 1"
ibrow "Consulta · ronda 2"
ibuild --new-round --no-reply >/dev/null || fail "(i) pickgate: --new-round --no-reply failed"
printf '### Q1 · Elegir\n- Permitirlo\n' | bash "$SAVE" "$IG" - >/dev/null 2>&1
ibrow "Consulta · ronda 3"
out="$(ibuild --new-round)"; rc=$?
[[ $rc -ne 0 && "$out" == *consult-round-pick* ]] \
  && ok "(i) pickgate: an older marker does not exempt round 2's bare pick" \
  || fail "(i) pickgate: --new-round leaving Q1 open exited $rc: $(printf '%s' "$out" | grep -E 'FAIL' | cut -c1-200)"

# The marker cannot be written (a directory sits at its path): the wrap does not land,
# so the baseline is not left at round 2 with no marker, and the failure is named. With
# the path cleared, the same command lands round 2 with its marker.
newpage markerdir "Consulta · ronda 1"
mkdir -p "$IM"
ibrow "Consulta · ronda 2"
out="$(ibuild --new-round --no-reply)"; rc=$?
[[ $rc -ne 0 && "$(round_of "$IB")" == "1" && "$(round_of "$IG")" == "1" && "$out" == *closed-round* ]] \
  && ok "(i) markerdir: an unwritable marker aborts the landing (page and baseline stay 1)" \
  || fail "(i) markerdir: rc=$rc, page '$(round_of "$IG")', baseline '$(round_of "$IB")': $(printf '%s' "$out" | grep -E 'ERROR|NOTE: could not' | cut -c1-200)"
rmdir "$IM"
ibuild --new-round --no-reply >/dev/null && [[ "$(round_of "$IG")" == "2" && "$(cat "$IM" 2>/dev/null)" == "1" ]] \
  && ok "(i) markerdir: with the path cleared the same command lands round 2 and its marker" \
  || fail "(i) markerdir: recovery landed page '$(round_of "$IG")', marker '$(cat "$IM" 2>/dev/null)'"

# The verb route over a saved reply: decide is the first rebuild of round 2 and the
# spec says ronda 2. Its trial build (an empty temp dir, always round 1) must not judge it.
newpage verbreply "Consulta · ronda 1"
printf '### Q1 · Elegir\n- Permitirlo\n' | bash "$SAVE" "$IG" - >/dev/null 2>&1
ibrow "Consulta · ronda 2"
out="$(python3 "$VERBS" decide "$IS" --id Q1 --verdict "Permitirlo" 2>&1)"; rc=$?
[[ $rc -eq 0 && "$(grep -c 'decided=' "$IS")" -ge 1 && "$(round_of "$IG")" == "2" ]] \
  && ok "(i) verb route: decide over a saved reply on an eyebrow 'ronda 2' page passes" \
  || fail "(i) verb route: decide rc=$rc, round '$(round_of "$IG")': $(printf '%s' "$out" | grep -E 'FAIL|spec-verbs' | cut -c1-200)"
# The same after a --no-reply round. No reply ever answered Q1, so the decide is still
# refused (BL-569, as on an unanswered round 1), but never by the eyebrow rule.
newpage verbnoreply "Consulta · ronda 1"
ibrow "Consulta · ronda 2"
ibuild --new-round --no-reply >/dev/null || fail "(i) verb route: --new-round --no-reply failed"
out="$(python3 "$VERBS" decide "$IS" --id Q1 --verdict "Permitirlo" 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" != *consult-round-eyebrow* ]] \
  && ok "(i) verb route: decide on a --no-reply round is not refused by the eyebrow rule" \
  || fail "(i) verb route: decide rc=$rc: $(printf '%s' "$out" | grep -E 'FAIL|spec-verbs' | cut -c1-200)"
# Backed by an answer: the reader answered Q1 in round 1 with a note (it stays open),
# round 2 opened over that reply, the session closed round 2 with no reply, and decides
# Q1 on round 3 from the round-1 answer.
newpage verbanswered "Consulta · ronda 1"
printf 'Q1: Permitirlo, pero lo quiero pensar\n' | bash "$SAVE" "$IG" - >/dev/null 2>&1
ibrow "Consulta · ronda 2"
ibuild --new-round >/dev/null || fail "(i) verb route: --new-round over the reply failed"
ibrow "Consulta · ronda 3"
ibuild --new-round --no-reply >/dev/null || fail "(i) verb route: round-3 --new-round --no-reply failed"
out="$(python3 "$VERBS" decide "$IS" --id Q1 --verdict "Permitirlo" 2>&1)"; rc=$?
[[ $rc -eq 0 && "$(grep -c 'decided=' "$IS")" -ge 1 && "$(round_of "$IG")" == "3" ]] \
  && ok "(i) verb route: decide on a --no-reply round 3 with eyebrow 'ronda 3' passes" \
  || fail "(i) verb route: round-3 decide rc=$rc, round '$(round_of "$IG")': $(printf '%s' "$out" | grep -E 'FAIL|spec-verbs' | cut -c1-200)"

[[ $failures -eq 0 ]] && echo "PASS: consult reader round" || { echo "FAILED: $failures"; exit 1; }
