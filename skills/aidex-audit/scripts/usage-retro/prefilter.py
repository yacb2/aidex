#!/usr/bin/env python3
"""
prefilter.py (v2) — rank dataset.jsonl records into friction / trigger-miss / evolve candidates.

Heuristics RANK candidates for analyst reading; they do NOT classify. The analyst layer
reads prompt + prior_assistant and judges, discarding heuristic false positives.

Usage: prefilter.py --in DATASET.jsonl --out CANDIDATES.jsonl
"""
import json, re, os, sys, argparse
from collections import Counter

# The standing-preference detector and the analyst window are both owned by the
# shipped, tested miner. Importing rather than copying is deliberate: this repo
# already carries four forks of extract.py, and registry-lag drift between them
# is its documented systemic failure mode.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from mine_preferences import detect as detect_preferences, head_tail
except ImportError as exc:
    sys.exit(f"ERROR: cannot import the preference detector from the sibling "
             f"usage-retro scripts ({exc}).\nRefusing to run: a pass without it "
             f"silently drops the whole STANDING-PREFERENCE\nclass and reports "
             f"the remainder as if it were the full picture (BL-164).")

# What the analyst actually reads. Was `prompt[:600]` — head-only, which is the
# worst possible cut for this signal. Same budget, both ends.
ANALYST_HEAD, ANALYST_TAIL = 400, 400

FRICTION = [
    r"\bno,? ", r"\beso no\b", r"\bas[ií] no\b", r"\bno es( lo)?\b", r"\bno era\b",
    r"\bte equivoc", r"\best[aá] mal\b", r"\bincorrect", r"\bequivocad",
    r"\bno quiero\b", r"\bno me gusta\b", r"\bno hagas\b", r"\bno deber",
    r"\ben realidad\b", r"\bm[aá]s bien\b", r"\bmejor\b", r"\bdeshaz\b", r"\brevert",
    r"\bvuelve a\b", r"\botra vez\b", r"\bde nuevo\b", r"\brehac", r"\bvolv[ae]mos\b",
    r"\bpor qu[eé]\b", r"\bwhy did you\b", r"\bthat'?s not\b", r"\bnot what\b",
    r"\bwrong\b", r"\bundo\b", r"\bredo\b", r"\bdetente\b", r"\bdetén", r"\bespera\b",
    r"\bno corresponde\b", r"\bno aplica\b", r"\bdije que\b", r"\bya te dije\b",
    r"\bse supone\b", r"\bfall[oó]\b", r"\bsigue fallando\b", r"\bsigue sin\b",
]
FRICTION_RE = re.compile("|".join(FRICTION), re.I)

INTENT = {
    "aidex-plan":     [r"\bplan(ea|ifica)?\b", r"\bvamos a planear\b", r"\bmulti-?fase\b"],
    "aidex-decision": [r"\bdecidim", r"\bdecisi[oó]n\b", r"\badr\b", r"\boptamos por\b", r"\bnos quedamos con\b"],
    "aidex-request":  [r"\bel cliente (pidi|quier)", r"\bstakeholder\b", r"\brequerimiento\b", r"\bnos pidieron\b"],
    "aidex-research": [r"\binvestiga", r"\bspike\b", r"\bexplora c[oó]mo\b", r"\bcómo funciona\b"],
    "aidex-reference":[r"\bdocumenta c[oó]mo\b", r"\brunbook\b", r"\bdocumenta la arquitectura\b"],
    "aidex-bugfix":   [r"\bbug\b", r"\bse rompe\b", r"\bno funciona\b", r"\bregresi[oó]n\b", r"\barreglar? el\b"],
    "aidex-loop":     [r"\bloop\b", r"\bbucle\b", r"\bhasta que pasen?\b", r"\bitera hasta\b"],
    "aidex-comm":     [r"\blog(uea)? (el|este) (email|correo|whatsapp)\b", r"\bredacta un (correo|email)\b", r"\bla reuni[oó]n con\b"],
    "aidex-audit":    [r"\bauditor[ií]a\b", r"\bhacer un audit\b", r"\bux audit\b"],
    "aidex-backlog":  [r"\bbacklog\b", r"\bpara m[aá]s adelante\b", r"\banota para luego\b"],
}
INTENT_RE = {k: re.compile("|".join(v), re.I) for k, v in INTENT.items()}

IMPROVE = [
    r"\bse pod[ií]a mejorar\b", r"\bse puede mejorar\b", r"\bmejorem", r"\bmejorar(lo|la|emos)?\b",
    r"\bpodr[ií]amos\b", r"\bqu[eé] tal si\b", r"\by si en (vez|lugar)\b", r"\ben (vez|lugar) de\b",
    r"\bdeber[ií]a(mos)?\b", r"\bagrega(r|le)?\b", r"\ba[ñn]ad(e|ir|amos)\b", r"\bfaltar[ií]a\b",
    r"\bme gustar[ií]a que\b", r"\bsería bueno que\b", r"\bse me ocurri[oó]\b", r"\bidea\b",
    r"\bcambia(r|le|mos)?\b", r"\bajusta(r|le|mos)?\b", r"\bafina(r|mos)?\b",
    r"\bextend(er|amos)\b", r"\bevolucion", r"\bquiero que (tambi[eé]n|adem[aá]s)\b",
]
IMPROVE_RE = re.compile("|".join(IMPROVE), re.I)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    recs = [json.loads(l) for l in open(args.inp) if l.strip()]
    cands = []
    for r in recs:
        p = r["prompt"]; signals = []
        if FRICTION_RE.search(p): signals.append("friction")
        prior_sk = r.get("prior_skills") or []
        if IMPROVE_RE.search(p):
            if prior_sk:
                for sk in set(prior_sk): signals.append(f"evolve?:{sk}")
            else: signals.append("improve?")
        if not r["skills_fired"] and not r["is_slash"]:
            for sk, rx in INTENT_RE.items():
                if rx.search(p): signals.append(f"miss?:{sk}")
        # The fourth gate (BL-164). The three above are all defect-shaped: they
        # need a complaint, a correction, or a missed trigger. A standing
        # preference has none of those — it is a polite instruction that was
        # OBEYED — so it passed through this filter invisibly for every run to
        # date. Admission here is repetition, not dissatisfaction.
        for label in detect_preferences(p):
            signals.append(f"pref:{label}")
        if signals:
            r2 = dict(r); r2["signals"] = signals
            r2["prompt"] = head_tail(p, ANALYST_HEAD, ANALYST_TAIL)
            r2.pop("prior_assistant", None)
            r2["prior_assistant"] = (r.get("prior_assistant") or "")[-500:]
            cands.append(r2)
    cands.sort(key=lambda r: (r["bucket"], r["ts"]))
    with open(args.out, "w") as fh:
        for r in cands: fh.write(json.dumps(r, ensure_ascii=False) + "\n")
    bc = Counter(r["bucket"] for r in cands)
    fr = sum("friction" in r["signals"] for r in cands)
    ms = sum(any(s.startswith("miss?") for s in r["signals"]) for r in cands)
    ev = sum(any(s.startswith("evolve?") for s in r["signals"]) for r in cands)
    pf = sum(any(s.startswith("pref:") for s in r["signals"]) for r in cands)
    only = sum(all(s.startswith("pref:") for s in r["signals"]) for r in cands)
    print(f"candidates: {len(cands)} / {len(recs)} records | by bucket: {dict(bc)}")
    print(f"friction: {fr} | trigger-miss: {ms} | evolve-after-fire: {ev}")
    print(f"standing-preference: {pf} ({only} of them reachable by NO other gate)")
    if pf:
        pl = Counter(s for r in cands for s in r["signals"] if s.startswith("pref:"))
        print("  " + " | ".join(f"{k.split(':',1)[1]}={v}" for k, v in pl.most_common()))
    print(f"wrote {args.out}")

if __name__ == "__main__":
    main()
