#!/usr/bin/env bash
# Facet-lexicon lockstep guard for aidex-audit's usage-retro (plan usage-retro-facets,
# phase 3).
#
# The intent lexicon used to live in TWO places that drifted: prefilter.INTENT
# (keyed by skill, drives `miss?:<skill>`) and mine_repetition.INTENTS (keyed by
# topic label). A facet file (references/facets/<name>.md) is now the single
# owner of every entry it claims; each script keeps only a RESIDUAL for entries
# no facet claims. This guard pins that split:
#
#   1. facet lexicon labels ∩ mine_repetition.RESIDUAL labels = ∅
#   2. facet skills        ∩ prefilter.RESIDUAL skills        = ∅
#   3. every `skills:` entry of every facet has a regex behind it
#   4. references/facets/00-index.md lists every facet file
#   5. the loader REFUSES a facet file missing a required key (never defaults)
#   6. the fifth admission gate: a prompt with no defect signal that matches a
#      facet is admitted, tagged, and counted as facet-only; --facet filters
#
# Every set is DERIVED from its file; nothing here hard-codes a label, a skill
# or a facet name (aidex-workflow/tests/test-shape-enum-lockstep.sh's rule).
# 1-4 run against the SHIPPED facet dir; then 1-6 run again against a temporary
# facet dir the test builds, so the checks are exercised even while the shipped
# dir carries no facet yet (the four facet files land in phase 5).
#
# Run with: bash skills/aidex-audit/tests/test-facet-lexicon-lockstep.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$TESTS_DIR/.." && pwd -P)"
RETRO="$SKILL/scripts/usage-retro"
SHIPPED="$SKILL/references/facets"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[ -f "$RETRO/facets.py" ] || { echo "FAIL: missing $RETRO/facets.py"; exit 1; }
[ -f "$SHIPPED/00-index.md" ] || { echo "FAIL: missing $SHIPPED/00-index.md"; exit 1; }

# ---- derived sets ---------------------------------------------------------
py() { PYTHONPATH="$RETRO" python3 -c "$@"; }

facet_labels() { AIDEX_FACETS_DIR="$1" py 'import facets; print("\n".join(sorted(facets.lexicon())))'; }
facet_skills() { AIDEX_FACETS_DIR="$1" py 'import facets; print("\n".join(sorted({s for f in facets.load_all() for s in f["skills"]})))'; }
facet_names()  { AIDEX_FACETS_DIR="$1" py 'import facets; print("\n".join(f["name"] for f in facets.load_all()))'; }
rep_residual() { AIDEX_FACETS_DIR="$1" py 'import mine_repetition as m; print("\n".join(sorted(k for k,_ in m.RESIDUAL)))'; }
pre_residual() { AIDEX_FACETS_DIR="$1" py 'import prefilter as p; print("\n".join(sorted(p.RESIDUAL)))'; }
indexed()      { grep -o '`[a-z][a-z0-9-]*\.md`' "$1/00-index.md" | tr -d '`' | sed 's/\.md$//' | sort -u; }

check_dir() {   # $1 = facet dir, $2 = tag for messages
  local dir="$1" tag="$2"
  local labels skills names rr pr idx
  labels="$(facet_labels "$dir")" || fail "($tag) loader failed on $dir"
  skills="$(facet_skills "$dir")"
  names="$(facet_names "$dir")"
  rr="$(rep_residual "$dir")";  [ -n "$rr" ] || fail "($tag) mine_repetition.RESIDUAL derived empty"
  pr="$(pre_residual "$dir")";  [ -n "$pr" ] || fail "($tag) prefilter.RESIDUAL derived empty"

  # 1. labels disjoint
  dup="$(comm -12 <(echo "$labels" | grep -v '^$') <(echo "$rr"))"
  [ -z "$dup" ] || fail "($tag) label(s) owned by both a facet and mine_repetition.RESIDUAL: $dup"
  # 2. skills disjoint
  dup="$(comm -12 <(echo "$skills" | grep -v '^$') <(echo "$pr"))"
  [ -z "$dup" ] || fail "($tag) skill(s) owned by both a facet and prefilter.RESIDUAL: $dup"
  # 3. every facet skill has a regex behind it (skill_lexicon carries it)
  for sk in $skills; do
    AIDEX_FACETS_DIR="$dir" py "import facets; import sys; sys.exit(0 if facets.skill_lexicon().get('$sk') else 1)" \
      || fail "($tag) facet skill $sk has no lexicon regex"
  done
  # 4. the index lists every facet file
  idx="$(indexed "$dir")"
  for n in $names; do
    echo "$idx" | grep -qx "$n" || fail "($tag) $dir/00-index.md does not list $n.md"
  done
}

# ---- A. the shipped facet dir ---------------------------------------------
check_dir "$SHIPPED" shipped

# ---- B. a temporary facet dir with two facets ------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
FD="$TMP/facets"; mkdir -p "$FD"
cat > "$FD/alpha.md" <<'EOF'
---
title: "alpha"
label: { en: "Alpha", es: "Alfa" }
lexicon:
  alpha:page: "\\bzorbal\\b|\\bp[aá]gina zorbal\\b"
skills: [zorbal-design, zorbal-dash]
slash: ["/zorbal-dash"]
scripts: [wrap-zorbal.sh]
paths: ["\\.context/zorbal/"]
primary_source: pages
reader: read_zorbal.py
sub_objectives: [wrap, consult]
---
Lens for alpha.
EOF
cat > "$FD/beta.md" <<'EOF'
---
title: "beta"
label: { en: "Beta", es: "Beta" }
lexicon:
  beta:queue: "\\bquxlist\\b"
skills: [quxlist-skill]
slash: []
scripts: []
paths: []
primary_source: transcript
---
Lens for beta.
EOF
cat > "$FD/00-index.md" <<'EOF'
# temp facets
| Facet | Primary source |
|---|---|
| `alpha.md` | pages |
| `beta.md` | transcript |
EOF
check_dir "$FD" temp

# the temp facets really loaded (the derived sets are non-empty, so 1-4 saw input)
n="$(facet_names "$FD" | grep -c .)"
[ "$n" -eq 2 ] || fail "(temp) expected 2 facets loaded, got $n"
facet_labels "$FD" | grep -q 'alpha:page' || fail "(temp) lexicon() lacks alpha:page"
AIDEX_FACETS_DIR="$FD" py 'import facets; s=facets.load("alpha"); assert s["label"]["es"]=="Alfa", s["label"]; assert s["reader"]=="read_zorbal.py"; assert s["sub_objectives"]==["wrap","consult"]; assert s["lens"].startswith("Lens for alpha"); b=facets.load("beta"); assert b["reader"] is None and b["sub_objectives"]==[]' \
  || fail "(temp) parsed shapes differ from the contract"

# 4b. an unlisted facet file is caught by the index check
cp "$FD/beta.md" "$FD/gamma.md"; sed -i '' 's/^title: "beta"/title: "gamma"/; s/beta:queue/gamma:queue/' "$FD/gamma.md"
out="$(indexed "$FD")"; echo "$out" | grep -qx gamma && fail "(temp) index check cannot see an unlisted file"
rm "$FD/gamma.md"

# 5. refusal on a missing required key — one temp copy per key, loader must exit non-zero
for key in title label lexicon skills slash scripts paths primary_source; do
  R="$TMP/refuse-$key"; mkdir -p "$R"; cp "$FD/00-index.md" "$R/"
  if [ "$key" = lexicon ]; then
    awk '/^lexicon:/{skip=1; next} skip && /^  /{next} {skip=0; print}' "$FD/alpha.md" > "$R/alpha.md"
  else
    grep -v "^$key:" "$FD/alpha.md" > "$R/alpha.md"
  fi
  out="$(AIDEX_FACETS_DIR="$R" py 'import facets; facets.load("alpha")' 2>&1)"; rc=$?
  [ $rc -ne 0 ] || fail "(refuse) loader accepted alpha.md without \`$key\`"
  echo "$out" | grep -q "$key" || fail "(refuse) the error for a missing \`$key\` does not name it: $out"
done
# a label owned by two facets is refused too
D="$TMP/dup"; mkdir -p "$D"; cp "$FD/"*.md "$D/"; sed -i '' 's/beta:queue/alpha:page/' "$D/beta.md"
AIDEX_FACETS_DIR="$D" py 'import facets; facets.lexicon()' >/dev/null 2>&1 && fail "(refuse) two facets owning one label was accepted"

# 6. the fifth admission gate on a tiny dataset
DS="$TMP/dataset.jsonl"
python3 - "$DS" <<'EOF'
import json, sys
rows = [
 # matches alpha's lexicon with no skill fired -> admitted, plus miss?: for its skills (not facet-only)
 dict(session="s1", project="p", bucket="b", ts="2026-09-01T10:00:00+00:00", is_slash=False, kind="real",
      prompt="revisa la zorbal de ayer", prior_assistant="", prior_skills=[], skills_fired=[]),
 # a facet skill fired, prompt says nothing -> admitted by skills_fired
 dict(session="s1", project="p", bucket="b", ts="2026-09-01T10:01:00+00:00", is_slash=False, kind="real",
      prompt="sigue con lo tuyo", prior_assistant="", prior_skills=[], skills_fired=["zorbal-dash"]),
 # the facet slash command
 dict(session="s1", project="p", bucket="b", ts="2026-09-01T10:02:00+00:00", is_slash=True, kind="slash",
      prompt="/zorbal-dash", prior_assistant="", prior_skills=[], skills_fired=[]),
 # beta's lexicon plus friction -> admitted, but NOT facet-only
 dict(session="s1", project="p", bucket="b", ts="2026-09-01T10:03:00+00:00", is_slash=False, kind="real",
      prompt="no, la quxlist está mal", prior_assistant="", prior_skills=[], skills_fired=[]),
 # nothing at all -> not a candidate
 dict(session="s1", project="p", bucket="b", ts="2026-09-01T10:04:00+00:00", is_slash=False, kind="real",
      prompt="gracias, sigue", prior_assistant="", prior_skills=[], skills_fired=[]),
]
with open(sys.argv[1], "w") as fh:
    for r in rows: fh.write(json.dumps(r, ensure_ascii=False) + "\n")
EOF
out="$(AIDEX_FACETS_DIR="$FD" python3 "$RETRO/prefilter.py" --in "$DS" --out "$TMP/cands.jsonl" 2>&1)" \
  || fail "(gate) prefilter failed: $out"
echo "$out" | grep -q 'facet alpha: 3 admitted (2 facet-only' || fail "(gate) alpha summary wrong: $out"
echo "$out" | grep -q 'facet beta: 1 admitted (0 facet-only'  || fail "(gate) beta summary wrong: $out"
n="$(grep -c . "$TMP/cands.jsonl")"; [ "$n" -eq 4 ] || fail "(gate) expected 4 candidates, got $n"
grep -q '"facet:alpha"' "$TMP/cands.jsonl" || fail "(gate) no facet:alpha tag in candidates"
grep '"/zorbal-dash"' "$TMP/cands.jsonl" | grep -q 'facet:alpha' || fail "(gate) slash command not admitted"
# the lexicon match also yields miss?:<skill> for the facet's skills (prefilter's INTENT view)
grep 'zorbal de ayer' "$TMP/cands.jsonl" | grep -q 'miss?:zorbal-design' || fail "(gate) facet skills do not get miss?: entries"
# --facet keeps only that facet's rows; an unknown facet is refused
out="$(AIDEX_FACETS_DIR="$FD" python3 "$RETRO/prefilter.py" --in "$DS" --out "$TMP/beta.jsonl" --facet beta 2>&1)"
n="$(grep -c . "$TMP/beta.jsonl")"; [ "$n" -eq 1 ] || fail "(gate) --facet beta expected 1 row, got $n"
echo "$out" | grep -q 'view: --facet beta' || fail "(gate) --facet view line missing"
AIDEX_FACETS_DIR="$FD" python3 "$RETRO/prefilter.py" --in "$DS" --out "$TMP/x.jsonl" --facet nosuch >/dev/null 2>&1 \
  && fail "(gate) --facet nosuch was accepted"
# mine_repetition's topical pass sees the facet label
out="$(AIDEX_FACETS_DIR="$FD" python3 "$RETRO/mine_repetition.py" --dataset "$DS" --min 1 2>&1)"
echo "$out" | grep -q 'alpha:page' || fail "(repetition) facet label absent from the topical pass: $out"

if [ "$failures" -eq 0 ]; then
  echo "PASS: facet lexicon lockstep (shipped dir: $(facet_names "$SHIPPED" | grep -c .) facets; temp dir: 2 facets; 8 required-key refusals; gate on 5 rows)"
else
  echo "FAIL: $failures failure(s)"; exit 1
fi
