#!/usr/bin/env python3
"""
mine_repetition.py — which instructions does the user have to keep repeating?

A re-dictated instruction is the cheapest signal a suite can give: whatever the
user types every week is something the suite should already be doing. This miner
reads dataset.jsonl (produced by extract.py) and clusters near-duplicate prompts
so re-dictation shows up as a count instead of as a feeling.

Two passes:
  1. LEXICAL — normalize + shingle each prompt, union-find on Jaccard >= --sim.
     Catches literal re-typing ("no te detengas", "ejecuta el plan completo").
  2. TOPICAL — a curated intent lexicon (autonomy, e2e, worktree, commit style,
     language, verification, ...). Catches the same instruction reworded, which
     the lexical pass cannot see.

Both are reported per-week so a trend is visible: an instruction that stops being
re-typed after a fix is remediated; one that keeps coming back is not.

Usage:  mine_repetition.py [--sim 0.5] [--min 3] [--dataset PATH]
"""
import json, os, re, sys, argparse, datetime
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
try:
    import facets
except ImportError as exc:
    sys.exit(f"ERROR: cannot import the facet loader from the sibling usage-retro "
             f"scripts ({exc}).\nRefusing to run: the topical pass would silently "
             f"lose every facet-owned intent (BL-164 pattern).")

STOP = set("""
the a an de la el los las y o u en con por para que se lo un una del al es son
no si me te le nos su sus mi tu mas más pero como cuando donde muy ya sin sobre
to of and for in on it is be do can we you i this that with have has not
""".split())

# intent lexicon: label -> regex. Deliberately narrow; a broad pattern would
# make every prompt match everything and the counts would mean nothing.
# The facet files (references/facets/*.md) own every label a facet claims;
# RESIDUAL keeps only the labels no facet has claimed yet, and the lockstep test
# (tests/test-facet-lexicon-lockstep.sh) fails on a label present in both.
RESIDUAL = [
    ("autonomy:dont-stop", r"no te deteng|sin deteners|hasta (que )?termin|no pares|"
                           r"continu[ae] hasta|don'?t stop|keep going"),
    ("autonomy:full-run",  r"ejecuta (todo )?el plan completo|todas las fases|"
                           r"fase por fase|de principio a fin|end to end"),
    ("autonomy:decide",    r"toma (todas )?las decisiones|t[uú] decides|como (t[uú] )?considere|"
                           r"tienes libertad|a tu criterio"),
    ("method:workflow",    r"\bworkflow\b|ultracode|fan.?out|multi.?agent|subagentes?|"
                           r"agentes en paralelo"),
    ("method:adversarial", r"adversarial|adversario|refuta|contraargument|red.?team"),
    ("method:judge",       r"\bjudge\b|\barbiter\b|[áa]rbitro|panel de jueces"),
    ("method:max-effort",  r"m[áa]ximo esfuerzo|max effort|ultrathink|piensa (m[áa]s|profundo)"),
    ("verify:evidence",    r"mu[eé]strame (la )?(salida|output|evidencia)|demu[eé]stra|"
                           r"con evidencia|proof|verifica (que|antes)|no me digas que funciona"),
    ("e2e:isolated",       r"e2e|test-e2e|playwright|entorno aislado|base de datos de test"),
    ("worktree",           r"worktree|árbol de trabajo|arbol de trabajo"),
    ("git:commit",         r"haz commit|hacer commit|commitea|commit y push|\bpush\b"),
    ("backlog",            r"backlog|BL-\d|reg[íi]stralo|regist[rr]a (esto|eso)|para despu[ée]s"),
    ("plan:context",       r"\.context|plan formal|documenta (esto|el plan)|seg[uú]n (el )?est[áa]ndar"),
    ("lang:spanish",       r"en espa[ñn]ol|castellano|no en ingl[ée]s"),
    ("style:no-emoji",     r"emoji|sin iconos"),
    ("db:protect",         r"no borres|no elimines|no resetees|no toques la base"),
    ("context:handoff",    r"handoff|nueva sesi[óo]n|sesi[óo]n limpia|compact"),
    ("frustration",        r"otra vez|de nuevo|ya te (lo )?dije|te lo he dicho|"
                           r"sigues? (sin|haciendo)|por qu[ée] no (lo )?hiciste|no hiciste"),
]
INTENTS = [(k, re.compile(v, re.I)) for k, v in list(facets.lexicon().items()) + RESIDUAL]


HUMAN_KINDS = ("real", "slash")


def human_records(path):
    """Rows a human actually typed, with the exclusion reported, never silent.

    `kind` is written by extract.py; rows from datasets predating it default to
    "real" so an old file still loads rather than analysing to zero.
    """
    rows = [json.loads(l) for l in open(path) if l.strip()]
    human = [r for r in rows if r.get("kind", "real") in HUMAN_KINDS]
    if len(human) != len(rows):
        print(f"[machine-authored records excluded: {len(rows) - len(human)} "
              f"of {len(rows)}]")
    return human


def norm_tokens(s):
    s = s.lower()
    s = re.sub(r"```.*?```", " ", s, flags=re.S)     # code blocks are not instructions
    s = re.sub(r"https?://\S+", " ", s)
    s = re.sub(r"[^a-záéíóúñü0-9 ]+", " ", s)
    return [t for t in s.split() if t not in STOP and len(t) > 2]


def shingles(toks, n=3):
    if len(toks) < n:
        return set([" ".join(toks)]) if toks else set()
    return {" ".join(toks[i:i + n]) for i in range(len(toks) - n + 1)}


def week_of(ts):
    d = datetime.datetime.fromisoformat(ts)
    return (d - datetime.timedelta(days=d.weekday())).strftime("%Y-%m-%d")


def main():
    ap = argparse.ArgumentParser()
    # Required, not defaulted. The default was `HERE/dataset.jsonl`, which was
    # correct only while this file lived inside an audit run folder. From the
    # tracked scripts dir that path never exists, and a default nobody can
    # satisfy is worse than an explicit argument.
    ap.add_argument("--dataset", required=True)
    ap.add_argument("--sim", type=float, default=0.5)
    ap.add_argument("--min", type=int, default=3)
    ap.add_argument("--maxlen", type=int, default=600,
                    help="ignore prompts longer than this (pasted reports, not instructions)")
    args = ap.parse_args()

    recs = human_records(args.dataset)
    print(f"dataset: {len(recs)} prompts")

    # ---------- pass 2 first (cheap, and it frames the lexical output) ----------
    intent_hits = defaultdict(list)
    for r in recs:
        p = r["prompt"]
        for label, rx in INTENTS:
            if rx.search(p):
                intent_hits[label].append(r)

    print("\n=== TOPICAL: re-dictated intents (whole window) ===")
    weeks = sorted({week_of(r["ts"]) for r in recs})
    hdr = "  ".join(w[5:] for w in weeks)
    print(f"{'intent':26s} {'total':>5s}  {'projects':>8s}   {hdr}")
    for label, _ in INTENTS:
        hits = intent_hits.get(label, [])
        if not hits:
            continue
        per_week = Counter(week_of(r["ts"]) for r in hits)
        cells = "  ".join(f"{per_week.get(w, 0):5d}" for w in weeks)
        nproj = len({r["project"] for r in hits})
        print(f"{label:26s} {len(hits):5d}  {nproj:8d}   {cells}")

    # ---------- pass 1: lexical near-duplicate clustering ----------
    cand = [r for r in recs if len(r["prompt"]) <= args.maxlen]
    sh = [shingles(norm_tokens(r["prompt"])) for r in cand]

    parent = list(range(len(cand)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i, j):
        a, b = find(i), find(j)
        if a != b:
            parent[b] = a

    # invert index on shingles to avoid the O(n^2) all-pairs comparison
    idx = defaultdict(list)
    for i, s in enumerate(sh):
        for g in s:
            idx[g].append(i)
    for g, members in idx.items():
        if len(members) > 200:      # a shingle in 200+ prompts is boilerplate
            continue
        for a in range(len(members)):
            for b in range(a + 1, len(members)):
                i, j = members[a], members[b]
                if find(i) == find(j):
                    continue
                si, sj = sh[i], sh[j]
                if not si or not sj:
                    continue
                inter = len(si & sj)
                jac = inter / len(si | sj)
                if jac >= args.sim:
                    union(i, j)

    clusters = defaultdict(list)
    for i in range(len(cand)):
        clusters[find(i)].append(i)

    big = sorted((c for c in clusters.values() if len(c) >= args.min),
                 key=len, reverse=True)
    print(f"\n=== LEXICAL: near-duplicate prompt clusters (>= {args.min}, jaccard >= {args.sim}) ===")
    for c in big[:30]:
        projs = Counter(cand[i]["project"] for i in c)
        first = min(cand[i]["ts"] for i in c)[:10]
        last = max(cand[i]["ts"] for i in c)[:10]
        rep = min((cand[i]["prompt"] for i in c), key=len)
        print(f"\n  [{len(c)}x] {first}..{last}  {dict(projs.most_common(4))}")
        print(f"     {rep[:200].replace(chr(10), ' / ')}")


if __name__ == "__main__":
    main()
