#!/usr/bin/env python3
"""mine_phrases.py — find recurring phrasings with NO lexicon supplied.

The retro's other instruments all start from a category someone named, so they
can only confirm. This one starts from nothing: it counts n-grams and ranks them
by DISPERSION — how many distinct sessions and projects a phrase appears in —
rather than by raw frequency.

Why dispersion and not frequency. A phrase repeated forty times inside one
session is that session's subject; the same phrase appearing once in forty
sessions is a habit. Only the second kind is a candidate for a default, and raw
counts cannot tell them apart — a long argument about invoices will out-rank
every recurring instruction in the corpus.

The output is a ranked list to READ, not a classification. It has no notion of
what a finding is, which is exactly what makes it able to surface one nobody
named.

Usage:
  mine_phrases.py --dataset D.jsonl [--min-n 2] [--max-n 6] [--top 60]
                  [--min-sessions 4]
"""
import argparse
import json
import re
import sys
import unicodedata
from collections import defaultdict

# Function-word-only n-grams are noise: they recur everywhere and mean nothing.
# A candidate must carry at least one token outside this set.
STOP = set("""
a al algo ahora asi aqui ante antes aunque cada como con contra cual cuando de del desde
donde dos e el ella ellas ello ellos en entre era eran es esa ese eso esta estan este esto
estos ha hace hacer hasta hay la las le les lo los mas me mi mis mucho muy ni no nos o para
pero poco por porque pues que se ser si sin sobre solo son su sus tan te ti todo todos tu
tus un una uno unos y ya yo the a an and or of to in is it for on with this that be are
you i we our your not have has do does can will would should if then than at from by as
""".split())


def norm(text):
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.findall(r"[a-z0-9']+", text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--min-n", type=int, default=2)
    ap.add_argument("--max-n", type=int, default=6)
    ap.add_argument("--top", type=int, default=60)
    ap.add_argument("--min-sessions", type=int, default=4)
    args = ap.parse_args()

    sessions = defaultdict(set)
    projects = defaultdict(set)
    counts = defaultdict(int)

    for line in open(args.dataset, encoding="utf-8"):
        if not line.strip():
            continue
        r = json.loads(line)
        toks = norm(r["prompt"])
        seen_here = set()
        for n in range(args.min_n, args.max_n + 1):
            for i in range(len(toks) - n + 1):
                g = tuple(toks[i:i + n])
                if all(t in STOP for t in g):
                    continue
                key = " ".join(g)
                counts[key] += 1
                seen_here.add(key)
        for key in seen_here:
            sessions[key].add(r["session"])
            projects[key].add(r["project"])

    rows = [(len(sessions[k]), len(projects[k]), counts[k], k)
            for k in counts if len(sessions[k]) >= args.min_sessions]

    # A longer phrase that appears in the same sessions as its own prefix says
    # nothing new, so keep the longest form of each nested family.
    rows.sort(key=lambda r: (-len(r[3].split()), -r[0]))
    kept, covered = [], []
    for s, p, c, k in rows:
        if any(k in longer and sessions[k] == sessions[longer] for longer in covered):
            continue
        covered.append(k)
        kept.append((s, p, c, k))

    kept.sort(key=lambda r: (-r[0], -r[1]))
    print(f"{'sess':>5} {'proj':>5} {'hits':>6}  phrase")
    for s, p, c, k in kept[:args.top]:
        print(f"{s:>5} {p:>5} {c:>6}  {k}")
    print(f"\n{len(kept)} phrases in >= {args.min_sessions} sessions "
          f"(of {len(counts)} distinct n-grams)", file=sys.stderr)


if __name__ == "__main__":
    main()
