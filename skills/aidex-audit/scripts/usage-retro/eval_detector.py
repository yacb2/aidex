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

POP = {"hit": 31, "warm": 1570, "cold": 3059}
SEED = 20260817


def half_of(sid):
    """'a' or 'b', fixed by the id so the split never drifts between runs."""
    return "a" if int(sid[1:]) % 2 == 1 else "b"


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
    for st in ("hit", "warm", "cold"):
        d = strata.get(st, {"n": 0, "pos": 0, "det": 0, "det_pos": 0})
        N = POP[st] * scale
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
        for st in ("hit", "warm", "cold"):
            d = strata.get(st, {"n": 0})
            if not d["n"]:
                continue
            N = POP[st] * scale
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
