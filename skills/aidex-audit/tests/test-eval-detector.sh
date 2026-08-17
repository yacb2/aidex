#!/usr/bin/env bash
# test-eval-detector.sh — the Horvitz-Thompson weights must come from the key.
#
# WHY THIS EXISTS. eval_detector.py takes --sample / --key / --labels as CLI
# parameters, so it presents itself as reusable, and its docstring says it projects
# "with the sampling rates in the key". It did not: the stratum populations were a
# module constant frozen from one 2026-08-17 corpus, while the per-stratum `rate`
# that sample_recall.py writes into the key — from which N = n/rate is exactly
# recoverable — was loaded into memory and never read.
#
# Score a differently-sized corpus and every weight is wrong, nothing errors, and
# nothing warns: the printed N column shows the stale numbers as if authoritative.
# A confident wrong recall figure is the one output this pipeline cannot afford,
# which is why the weights are asserted here rather than trusted.
#
# Scenarios:
#   (a) N is recovered per stratum as n/rate, not from any constant
#   (b) the SAME sample with different rates yields different N — the discriminator
#       against a hardcoded population, which (a) alone cannot provide
#   (c) a half-sample halves the population, since the split is on a random id
#   (d) a key with a missing or zero rate is REFUSED, never silently weighted
#
# Run with: bash skills/aidex-audit/tests/test-eval-detector.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RETRO="$TESTS_DIR/../scripts/usage-retro"
EVAL="$RETRO/eval_detector.py"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# corpus <dir> <warm-rate> <cold-rate> — 2 hit (census), 4 warm, 4 cold.
# Ids are S0001.. so half_of() splits them odd/even; the texts are deliberately
# plain so the assertions below do not depend on the detector's lexicon.
corpus() {
  local d="$1" wr="$2" cr="$3"
  mkdir -p "$d"
  python3 - "$d" "$wr" "$cr" <<'PY'
import json, sys
d, wr, cr = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
strata = [("hit", 2, 1.0), ("warm", 4, wr), ("cold", 4, cr)]
sample, key, labels = [], [], []
i = 0
for st, n, rate in strata:
    for _ in range(n):
        i += 1
        sid = f"S{i:04d}"
        sample.append({"id": sid, "prompt": f"prompt number {i} about nothing in particular"})
        key.append({"id": sid, "stratum": st, "rate": rate,
                    "ts": "2026-08-01T00:00:00Z", "project": "p"})
        labels.append({"id": sid, "label": i % 2, "why": "fixture"})
for name, rows in (("sample", sample), ("key", key), ("labels", labels)):
    with open(f"{d}/{name}.jsonl", "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
}

run() {  # run <dir> [extra args...]
  python3 "$EVAL" --sample "$1/sample.jsonl" --key "$1/key.jsonl" \
                  --labels "$1/labels.jsonl" "${@:2}" 2>&1
}

# n_for <output> <stratum> -> the N column for that stratum
n_for() { awk -v s="$2" '$1==s {print $NF}' <<<"$1"; }

# ---------------------------------------------------------------------------
# (a) N = n / rate, per stratum. warm: 4 / 0.5 = 8. cold: 4 / 0.05 = 80.
#     hit is a census (rate 1.0), so N = n = 2.
# ---------------------------------------------------------------------------
corpus "$TMP/c1" 0.5 0.05
out1="$(run "$TMP/c1")"
[[ "$(n_for "$out1" hit)"  == "2"  ]] && ok "hit N is the census count (2)" \
  || bad "hit N wrong: $(n_for "$out1" hit) — output: $out1"
[[ "$(n_for "$out1" warm)" == "8"  ]] && ok "warm N is recovered as n/rate (4/0.5 = 8)" \
  || bad "warm N wrong: $(n_for "$out1" warm) — output: $out1"
[[ "$(n_for "$out1" cold)" == "80" ]] && ok "cold N is recovered as n/rate (4/0.05 = 80)" \
  || bad "cold N wrong: $(n_for "$out1" cold) — output: $out1"

# The frozen constants must not appear for a corpus that is not that corpus.
[[ "$out1" != *" 1570"* && "$out1" != *" 3059"* ]] \
  && ok "the 2026-08-17 populations are not projected onto another corpus" \
  || bad "a stale hardcoded population reached the output: $out1"

# ---------------------------------------------------------------------------
# (b) THE DISCRIMINATOR. Same sample, same labels, only the rates differ. A
#     hardcoded population is identical across these two runs by construction, so
#     this is the assertion a frozen constant cannot satisfy.
# ---------------------------------------------------------------------------
corpus "$TMP/c2" 0.25 0.01
out2="$(run "$TMP/c2")"
[[ "$(n_for "$out2" warm)" == "16"  ]] && ok "a different warm rate moves warm N (4/0.25 = 16)" \
  || bad "warm N did not follow the key's rate: $(n_for "$out2" warm)"
[[ "$(n_for "$out2" cold)" == "400" ]] && ok "a different cold rate moves cold N (4/0.01 = 400)" \
  || bad "cold N did not follow the key's rate: $(n_for "$out2" cold)"
[[ "$(n_for "$out1" cold)" != "$(n_for "$out2" cold)" ]] \
  && ok "two corpora with the same sample size get different weights" \
  || bad "the weights did not move between corpora — they are not read from the key"

# ---------------------------------------------------------------------------
# (c) A half represents half the population. The halves are fixed by id parity,
#     so this must scale the recovered N rather than re-deriving it from the
#     filtered subset (which would double-count the sampling rate).
# ---------------------------------------------------------------------------
out_h="$(run "$TMP/c1" --half a)"
[[ "$(n_for "$out_h" cold)" == "40" ]] && ok "--half a halves the recovered population (80 -> 40)" \
  || bad "the half-sample population is wrong: $(n_for "$out_h" cold) — output: $out_h"

# ---------------------------------------------------------------------------
# (d) A key that cannot support the projection must REFUSE. Silently substituting
#     anything here is how the defect this file is about got shipped: the estimator
#     printed a number to one decimal place with nothing indicating a mismatch.
# ---------------------------------------------------------------------------
corpus "$TMP/c3" 0.5 0.05
python3 - "$TMP/c3/key.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
for r in rows:
    if r["stratum"] == "cold":
        r.pop("rate")           # a key written by an older sample_recall
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    for r in rows:
        fh.write(json.dumps(r, ensure_ascii=False) + "\n")
PY
out3="$(run "$TMP/c3")"; rc3=$?
[[ $rc3 -ne 0 ]] && ok "a key with no rate is refused (exit $rc3)" \
  || bad "a key with no sampling rate was scored anyway: $out3"
[[ "$out3" == *"rate"* ]] && ok "the refusal names what is missing" \
  || bad "the refusal did not say why: $out3"

corpus "$TMP/c4" 0.5 0.0
out4="$(run "$TMP/c4")"; rc4=$?
[[ $rc4 -ne 0 ]] && ok "a zero sampling rate is refused rather than dividing by it" \
  || bad "a zero rate was projected: $out4"

echo
echo "eval detector: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
