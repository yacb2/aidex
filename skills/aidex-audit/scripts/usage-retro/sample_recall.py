#!/usr/bin/env python3
"""sample_recall.py — draw a stratified sample for measuring a detector's RECALL.

Precision you can measure by reading what the detector flagged. Recall you cannot:
a false negative is by definition something nobody looked at. So the sample has to
be drawn from the records the detector did NOT flag, and it has to be drawn in a
way that finds the rare positives without pretending the rate is higher than it is.

THE DESIGN
----------
Three strata over one dataset, each sampled at a known rate, so an estimate can be
projected back to the population (Horvitz-Thompson):

  hit    every record the detector flagged. Sampled at 100%: there are few, and
         they are the numerator's evidence.
  warm   not flagged, but carrying at least one of the detector's three clauses
         on its own (a directive, a shape word, or a deliverable noun). This is
         where a near-miss lives — the conjunction failed by one term.
  cold   not flagged and carrying none of them. Positives here would mean the
         detector's whole vocabulary is wrong, not just its conjunction, so this
         stratum exists to bound that rather than to find much.

A uniform random sample instead of this would spend ~99.5% of the labelling budget
on cold records and return an estimate with no usable precision.

BLINDNESS
---------
`--out` writes ONE shuffled file with opaque ids and nothing else: no stratum, no
labels, no signals. `--key` writes the mapping separately. Label the first file,
then join. Reading the stratum while labelling is how a recall study measures the
labeller's memory instead of the detector.

Usage:
  sample_recall.py --dataset D.jsonl --candidates C.jsonl \\
                   --out sample.jsonl --key key.jsonl [--warm 200] [--cold 120]
"""
import argparse
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mine_preferences as MP  # noqa: E402

# The sample must be reproducible: a recall figure nobody can redraw is an anecdote.
SEED = 20260817


def clause_hits(text):
    """Which of the detector's three clauses fire on their own."""
    return (bool(MP.DIRECTIVE.search(text)),
            any(rx.search(text) for rx in MP.SHAPE.values()),
            bool(MP.DELIVERABLE.search(text)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True, help="extract.py output (the population)")
    ap.add_argument("--candidates", required=True, help="prefilter.py output (carries pref: signals)")
    ap.add_argument("--out", required=True, help="shuffled, opaque, unlabelled — what you read")
    ap.add_argument("--key", required=True, help="id -> stratum + provenance — what you join afterwards")
    ap.add_argument("--warm", type=int, default=200)
    ap.add_argument("--cold", type=int, default=120)
    args = ap.parse_args()

    flagged = set()
    for line in open(args.candidates, encoding="utf-8"):
        if not line.strip():
            continue
        r = json.loads(line)
        if any(s.startswith("pref:") for s in r.get("signals", [])):
            flagged.add((r["ts"], r["project"]))

    hit, warm, cold = [], [], []
    for line in open(args.dataset, encoding="utf-8"):
        if not line.strip():
            continue
        r = json.loads(line)
        if (r["ts"], r["project"]) in flagged:
            hit.append(r)
        elif any(clause_hits(r["prompt"])):
            warm.append(r)
        else:
            cold.append(r)

    rng = random.Random(SEED)
    picked = [("hit", r, 1.0) for r in hit]
    for name, pool, n in (("warm", warm, args.warm), ("cold", cold, args.cold)):
        take = min(n, len(pool))
        rate = take / len(pool) if pool else 0.0
        picked += [(name, r, rate) for r in rng.sample(pool, take)]

    rng.shuffle(picked)
    with open(args.out, "w", encoding="utf-8") as fh_out, \
         open(args.key, "w", encoding="utf-8") as fh_key:
        for i, (stratum, r, rate) in enumerate(picked, 1):
            sid = f"S{i:04d}"
            # Deliberately minimal: an id and the text. Anything else here is a
            # cue about which stratum the record came from.
            fh_out.write(json.dumps({"id": sid, "prompt": r["prompt"]},
                                    ensure_ascii=False) + "\n")
            fh_key.write(json.dumps({"id": sid, "stratum": stratum, "rate": rate,
                                     "ts": r["ts"], "project": r["project"]},
                                    ensure_ascii=False) + "\n")

    sys.stderr.write(
        f"population: hit={len(hit)} warm={len(warm)} cold={len(cold)}\n"
        f"sampled:    hit={len(hit)} (100%) "
        f"warm={min(args.warm, len(warm))} ({min(args.warm, len(warm))/max(len(warm),1)*100:.1f}%) "
        f"cold={min(args.cold, len(cold))} ({min(args.cold, len(cold))/max(len(cold),1)*100:.1f}%)\n"
        f"wrote {args.out} ({len(picked)} rows) + {args.key}\n")


if __name__ == "__main__":
    main()
