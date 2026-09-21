#!/usr/bin/env python3
"""
prefilter.py (v2) — rank dataset.jsonl records into friction / trigger-miss / evolve candidates.

Heuristics RANK candidates for analyst reading; they do NOT classify. The analyst layer
reads prompt + prior_assistant and judges, discarding heuristic false positives.

Usage: prefilter.py --in DATASET.jsonl --out CANDIDATES.jsonl
"""
import json, re, os, sys, argparse
from collections import Counter, defaultdict, deque

# The standing-preference detector and the analyst window are both owned by the
# shipped, tested miner. Importing rather than copying is deliberate: this repo
# already carries four forks of extract.py, and registry-lag drift between them
# is its documented systemic failure mode.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from mine_preferences import detect as detect_preferences, head_tail
    import facets
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

# The facet files (references/facets/*.md) own every lexicon entry a facet claims;
# RESIDUAL keeps only the skills no facet has claimed yet. The lockstep test
# (tests/test-facet-lexicon-lockstep.sh) fails on any key present in both.
RESIDUAL = {
    "decision": [r"\bdecidim", r"\bdecisi[oó]n\b", r"\badr\b", r"\boptamos por\b", r"\bnos quedamos con\b"],
    "request":  [r"\bel cliente (pidi|quier)", r"\bstakeholder\b", r"\brequerimiento\b", r"\bnos pidieron\b"],
    "research": [r"\binvestiga", r"\bspike\b", r"\bexplora c[oó]mo\b", r"\bcómo funciona\b"],
    "reference":[r"\bdocumenta c[oó]mo\b", r"\brunbook\b", r"\bdocumenta la arquitectura\b"],
    "bugfix":   [r"\bbug\b", r"\bse rompe\b", r"\bno funciona\b", r"\bregresi[oó]n\b", r"\barreglar? el\b"],
    "loop":     [r"\bloop\b", r"\bbucle\b", r"\bhasta que pasen?\b", r"\bitera hasta\b"],
    "comm":     [r"\blog(uea)? (el|este) (email|correo|whatsapp)\b", r"\bredacta un (correo|email)\b", r"\bla reuni[oó]n con\b"],
    "audit":    [r"\bauditor[ií]a\b", r"\bhacer un audit\b", r"\bux audit\b"],
}
INTENT = facets.skill_lexicon() | RESIDUAL
INTENT_RE = {k: re.compile("|".join(v), re.I) for k, v in INTENT.items()}
FACETS = facets.compiled()

def lexicon_keys(fired):
    """The INTENT keys named by a list of Skill invocation names.

    The two namespaces are not the same string: INTENT is keyed by lexicon key
    (`backlog`, `plan`, `research`), while `skills_fired`/`prior_skills` carry
    the literal Skill argument. Censused over the four shipped datasets under
    .context/audits/usage-retro (91 distinct names), those come in three
    shapes: bare (`artifact-design`, `session-handoff`, `audit`), `aidex-`
    prefixed (`aidex-backlog`, `aidex-plan-exec`, `aidex-research`) and
    `<plugin>:<skill>` (`code-review:code-review`, `version:release`,
    `dt:dt-usage`, and `aidex:plan` for an aidex skill reached through the
    plugin). So: drop the plugin prefix, then the `aidex-` one, and keep what
    INTENT actually knows. A name that maps to no key (`git-commit`,
    `backlog-register`) yields nothing rather than a guess.
    """
    keys = set()
    for name in fired:
        short = name.rsplit(":", 1)[-1]
        for cand in (short, short[len("aidex-"):] if short.startswith("aidex-") else short):
            if cand in INTENT: keys.add(cand)
    return keys

def delegate_keys(agents):
    """Lexicon keys whose own regex matches a launched agent's name: `artifact-sonnet`
    is the artifact skills running, `task-general` is nobody's delegate (BL-438)."""
    return {sk for sk, rx in INTENT_RE.items() if any(rx.search(a) for a in agents)}

# How far back a fire of the same skill still counts as "already running" (BL-388).
# A trigger-miss means the skill did not run; a follow-up on the page it is
# already producing is not one. Measured on the 2026-09-11 artifacts dataset
# (3,928 records): 113 of the 199 miss?:artifact-design tags had the skill
# firing earlier in the same session, and the analysts discarded every one by
# hand. By distance in turns: 32 at 1, 29 at 2, 12 at 3, then a flat tail
# (15, 4, 21 beyond). The density collapses after 2, so 3 keeps one turn of
# slack and leaves the long tail — where a re-trigger is plausibly a real miss —
# taggable.
#
# The census counted EVERY record of the session as a turn, slash commands
# included, and the window below consumes them the same way — so a fire
# followed by three /slash turns has already fallen out of it. Measuring and
# enforcing on the same notion of "turn" is the point; whether a slash turn
# should count at all is a separate question, unmeasured here.
MISS_LOOKBACK_TURNS = 3

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
    ap.add_argument("--facet", default=None,
                    help="keep only rows tagged facet:NAME (the facet run's view)")
    args = ap.parse_args()
    if args.facet and args.facet not in {f[0] for f in FACETS}:
        sys.exit(f"ERROR: no facet named {args.facet!r} under {facets.facets_dir()}")
    recs = [json.loads(l) for l in open(args.inp) if l.strip()]
    cands = []
    # Per session, the skills fired by the last MISS_LOOKBACK_TURNS records.
    # Keyed by session so an interleaved second session never suppresses the
    # first turn of its neighbour; records arrive in ts order per session.
    recent = defaultdict(lambda: deque(maxlen=MISS_LOOKBACK_TURNS))
    for r in recs:
        p = r["prompt"]; signals = []
        if FRICTION_RE.search(p): signals.append("friction")
        prior_sk = r.get("prior_skills") or []
        if IMPROVE_RE.search(p):
            if prior_sk:
                for sk in set(prior_sk): signals.append(f"evolve?:{sk}")
            else: signals.append("improve?")
        # Both sides are lexicon keys, never invocation names (see lexicon_keys).
        window = recent[r["session"]]
        running = lexicon_keys(prior_sk).union(*window) if window else lexicon_keys(prior_sk)
        delegated = delegate_keys(r.get("agents_fired") or [])
        running |= delegated
        recent[r["session"]].append(lexicon_keys(r["skills_fired"] or []) | delegated)
        if not r["skills_fired"] and not r["is_slash"]:
            for sk, rx in INTENT_RE.items():
                # Named, never silently dropped: `Plan` or `research-sonnet` doing the
                # job in place of the skill may still be what the analyst is looking for.
                if sk in delegated and rx.search(p): signals.append(f"delegated:{sk}")
                if sk in running: continue
                if rx.search(p): signals.append(f"miss?:{sk}")
        # The fourth gate (BL-164). The three above are all defect-shaped: they
        # need a complaint, a correction, or a missed trigger. A standing
        # preference has none of those — it is a polite instruction that was
        # OBEYED — so it passed through this filter invisibly for every run to
        # date. Admission here is repetition, not dissatisfaction.
        for label in detect_preferences(p):
            signals.append(f"pref:{label}")
        # The fifth gate: facet membership. The four above are all signal-shaped,
        # so a facet that is working well never reaches a shard through them —
        # the same blindness that hid STANDING-PREFERENCE for three runs. A row
        # that belongs to a facet is admitted on membership alone.
        hit = facets.facets_for(r, FACETS)
        for name in hit:
            signals.append(f"facet:{name}")
        if args.facet and args.facet not in hit:
            continue
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
    for name, *_ in FACETS:
        tag = f"facet:{name}"
        adm = sum(tag in r["signals"] for r in cands)
        fonly = sum(tag in r["signals"] and all(s.startswith("facet:") for s in r["signals"])
                    for r in cands)
        print(f"facet {name}: {adm} admitted ({fonly} facet-only, reachable by NO other gate)")
    if args.facet:
        print(f"view: --facet {args.facet}")
    print(f"wrote {args.out}")

if __name__ == "__main__":
    main()
