#!/usr/bin/env python3
"""eval_detector.py — score mine_preferences against a labelled stratified sample.

Reports recall and precision, projected to the population with the sampling rates
in the key (Horvitz-Thompson), and splits the sample into two halves so a lexicon
derived from one half can be scored on the other.

WHY THE SPLIT IS THE WHOLE POINT
--------------------------------
The false negatives that motivate a lexicon change cannot also be the evidence
that the change worked: add the exact words you just read, re-measure on the same
records, and recall rises by construction. That is not a measurement, it is a
restatement. `--derive-half a` marks half the sample as the only half you are
allowed to read while editing the detector; `--report-half b` is the number that
means something.

The halves are fixed by the id's parity, so they do not move between runs.

Usage:
  eval_detector.py --sample S.jsonl --key K.jsonl --labels L.jsonl [--half a|b|all]
                   [--list-fn]
"""
import argparse
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mine_preferences as MP  # noqa: E402

SEED = 20260817
STRATA = ("hit", "warm", "cold")


def half_of(sid):
    """'a' or 'b', fixed by the id so the split never drifts between runs."""
    return "a" if int(sid[1:]) % 2 == 1 else "b"


def populations(key):
    """Stratum populations, recovered from the key's own sampling rates.

    `sample_recall.py` computes `rate = take / len(pool)` and writes it on every
    key record, so `N = n / rate` is EXACT — the population is already in the file
    this script opens.

    This used to be the module constant `POP = {"hit": 31, "warm": 1570,
    "cold": 3059}`, transcribed from the 2026-08-17 run while `rate` was loaded
    into memory and never read. The estimator's inputs were parameters and its
    weights were a literal, so any other corpus was projected onto a stale
    population: recall and precision came out wrong by the ratio of the two
    warm:cold splits, with nothing in the output indicating a mismatch and the N
    column presenting the stale numbers as authoritative.

    A key that cannot support the projection is refused. Substituting anything is
    what produced the defect in the first place, and a confident wrong recall
    figure is the one output this pipeline cannot afford.
    """
    counts, rates = {}, {}
    for sid, rec in key.items():
        st = rec.get("stratum")
        if st is None:
            raise SystemExit(f"ERROR: key record {sid} has no `stratum` — cannot "
                             f"project without knowing which stratum it came from")
        counts[st] = counts.get(st, 0) + 1
        rate = rec.get("rate")
        if rate is None:
            raise SystemExit(
                f"ERROR: key record {sid} (stratum {st}) has no `rate`, so the "
                f"population cannot be recovered and the Horvitz-Thompson weights "
                f"are unknowable. Redraw the sample with sample_recall.py, which "
                f"writes `rate` on every record.")
        if not rate > 0:
            raise SystemExit(
                f"ERROR: key record {sid} (stratum {st}) has rate={rate}; a "
                f"population of n/rate is undefined. Redraw the sample.")
        prev = rates.setdefault(st, rate)
        if abs(prev - rate) > 1e-12:
            raise SystemExit(
                f"ERROR: stratum {st} carries two different sampling rates "
                f"({prev} and {rate}) — the key mixes two draws, so no single "
                f"weight is correct for it.")
    return {st: counts[st] / rates[st] for st in counts}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--labels", required=True)
    ap.add_argument("--half", default="all", choices=("a", "b", "all"))
    ap.add_argument("--list-fn", action="store_true", help="print the false negatives")
    args = ap.parse_args()

    text = {json.loads(l)["id"]: json.loads(l)["prompt"] for l in open(args.sample, encoding="utf-8")}
    key = {json.loads(l)["id"]: json.loads(l) for l in open(args.key, encoding="utf-8")}
    lab = {json.loads(l)["id"]: json.loads(l) for l in open(args.labels, encoding="utf-8")}
    # Recovered from the whole key, then scaled below: a half represents half the
    # population, and re-deriving it from the filtered subset would apply the
    # sampling rate twice.
    pop = populations(key)

    ids = [s for s in text if args.half == "all" or half_of(s) == args.half]
    # The population a half represents is half the population, since the split is
    # on an id assigned at random-shuffle time.
    scale = 1.0 if args.half == "all" else 0.5

    strata = {}
    fired_pos = []
    for sid in ids:
        st = key[sid]["stratum"]
        d = strata.setdefault(st, {"n": 0, "pos": 0, "det_pos": 0, "det": 0})
        d["n"] += 1
        positive = lab[sid]["label"] == 1
        detected = bool(MP.detect(text[sid]))
        d["pos"] += positive
        d["det"] += detected
        d["det_pos"] += (positive and detected)
        if positive and not detected:
            fired_pos.append(sid)

    est_pos = est_det = est_det_pos = 0.0
    print(f"{'stratum':6} {'n':>5} {'pos':>5} {'det':>5} {'det&pos':>8} {'N':>8}")
    for st in STRATA:
        d = strata.get(st, {"n": 0, "pos": 0, "det": 0, "det_pos": 0})
        N = pop.get(st, 0.0) * scale
        if d["n"]:
            est_pos += d["pos"] / d["n"] * N
            est_det += d["det"] / d["n"] * N
            est_det_pos += d["det_pos"] / d["n"] * N
        print(f"{st:6} {d['n']:>5} {d['pos']:>5} {d['det']:>5} {d['det_pos']:>8} {N:>8.0f}")

    recall = est_det_pos / est_pos * 100 if est_pos else 0
    precision = est_det_pos / est_det * 100 if est_det else 0
    print(f"\nhalf={args.half}  projected positives={est_pos:.0f}  projected detections={est_det:.0f}")
    print(f"RECALL    {recall:5.1f}%")
    print(f"PRECISION {precision:5.1f}%")

    # Bootstrap only the sampled strata; the hit stratum is a census, not a sample.
    rng = random.Random(SEED)
    draws = []
    for _ in range(2000):
        tp = fp_pos = 0.0
        for st in STRATA:
            d = strata.get(st, {"n": 0})
            if not d["n"]:
                continue
            N = pop.get(st, 0.0) * scale
            if st == "hit":
                tp += d["det_pos"] / d["n"] * N
                fp_pos += d["pos"] / d["n"] * N
                continue
            idx = [rng.randrange(d["n"]) for _ in range(d["n"])]
            pos_list = [1] * d["pos"] + [0] * (d["n"] - d["pos"])
            dp_list = [1] * d["det_pos"] + [0] * (d["n"] - d["det_pos"])
            fp_pos += sum(pos_list[i] for i in idx) / d["n"] * N
            tp += sum(dp_list[i] for i in idx) / d["n"] * N
        draws.append(tp / fp_pos * 100 if fp_pos else 0)
    draws.sort()
    print(f"recall 90% CI  {draws[100]:.1f}% – {draws[1900]:.1f}%")

    if args.list_fn:
        print(f"\nfalse negatives ({len(fired_pos)}):")
        for sid in sorted(fired_pos):
            print(f"  {sid} [{key[sid]['stratum']}] {lab[sid]['why'][:70]}")


if __name__ == "__main__":
    main()
