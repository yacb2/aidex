#!/usr/bin/env python3
"""
mine_preferences.py — which instructions about the FORM of the deliverable does
the user keep having to repeat?

WHY THIS MINER EXISTS (BL-164)
The usage-retro taxonomy is defect-shaped. All six tags — TRIGGER-MISS,
WRONG-SKILL, OUTPUT-CORRECTION, EVOLVE, WORKFLOW-GAP, FRICTION — describe
something that went wrong, and `prefilter.py` admits a record only via one of
three gates: a friction word, an improve word after a skill fired, or a skill
intent with no skill fired.

A standing preference passes none of them. "Escríbeme los artifacts en español",
"hazme un mockup de cada alternativa", "deja un espacio por cada cosa para poder
darte opinión" are polite, unambiguous, and were OBEYED. There is no complaint to
match on and no trigger to miss. The instrument was looking for a user who
complains; this user does not complain, he repeats.

Measured over 5,401 human prompts / 90 days against 13 hand-confirmed cases:
8/13 were invisible to the topical lexicon, 1/13 was misattributed to `backlog`
because the word appeared, and 4/13 registered only as `lang:spanish` — a label
that scored 23 in the run-5 repetition table and was never graduated to a
finding. So even the one preference label that existed produced no output.

WHAT THIS MINER IS AND IS NOT
It is a RANKER. It surfaces candidates for a human or an analyst agent to judge,
exactly like `prefilter.py`. It is NOT a classifier and its output must never be
reported as a count of findings. Hand-read precision on the 90-day corpus was
13/24 = 54%. That is adequate for ranking and useless as a statistic — the run
that reports "N standing preferences" without a hand-read sample behind it is
repeating INSTR-01, where 70% of a headline metric turned out to be machine text.

THE DETECTOR IS A CONJUNCTION, NOT A KEYWORD LIST
A keyword list cannot work here, and the failure is not subtle. In echo-lab (a
dubbing/localization product) "traducción" and "visual" are domain nouns; in
ns-backoffice "tabla" and "marcar" are domain verbs. A first pass built on
keywords returned 152 hits of which the overwhelming majority were people
discussing the application. The signal is three things at once:

    DIRECTIVE      an imperative or volitive aimed at the assistant
      +   within PROXIMITY characters of
    SHAPE-OBJECT   a noun naming the FORM of the output (casilla, mockup,
                   campo de notas, idioma)
      +   within DELIVERABLE_PROXIMITY characters of
    DELIVERABLE    the artifact being produced (artifact, informe, plan, mockup)

The third clause is what separates "ponme el floating panel EN EL MOCKUP" from
"las TABLAS siguen con bordes cuadrados". Adding it moved hand-read precision
from 42% to 54% and cost 3 of 16 true positives. That trade is recorded here so
nobody re-derives it: dropping the DELIVERABLE clause raises recall and drowns
the result in domain chatter.

ROOTS ARE PARAMETERS
`~/.claude/projects` is where Claude Code puts transcripts for everyone, so
defaulting the transcripts root is sound (this is the same reasoning mine_items.py
applies, and unlike that miner this one never reads a workspace tree, so there is
no projects root to require). It stays a flag so the tests can run against a
fixture corpus instead of the author's home directory.
"""
import os, re, sys, glob, json, random, argparse
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prompt_kinds

TX_ROOT = os.environ.get("CLAUDE_PROJECTS_ROOT") or os.path.expanduser("~/.claude/projects")

# ---------------------------------------------------------------------------
# The window (BL-164 / decision D5)
# ---------------------------------------------------------------------------
HEAD_DEFAULT = 400
TAIL_DEFAULT = 400


def head_tail(text, head=HEAD_DEFAULT, tail=TAIL_DEFAULT, marker=" […] "):
    """Keep the opening AND the closing of a prompt, drop the middle.

    `prefilter.py` passed the analyst `prompt[:600]`, which is the worst possible
    cut for this signal: a standing preference is appended AFTER the substantive
    request ("...y ponme un campo de notas"), so a head-only window removes
    precisely the clause that identifies it. Ablation on the same corpus with the
    same detector, changing only the cut:

        full text            39 detections
        2000 (extract.py)    37
        600  (analyst)       26      <- a third of the signal, all of it tail

    Head+tail recovers the tail at a fraction of the cost of raising the cap:
    800 characters against the 2000+ a flat raise would need to reach the same
    prompts. Returns the text unchanged when it already fits.
    """
    if head < 0 or tail < 0:
        raise ValueError("head and tail must be non-negative")
    if len(text) <= head + tail:
        return text
    return text[:head] + marker + (text[-tail:] if tail else "")


# ---------------------------------------------------------------------------
# The three clauses
# ---------------------------------------------------------------------------

# 1. The assistant is being told to do something. Spanish imperatives and
#    volitives ("quiero que", "necesito que") plus the English equivalents,
#    because this user's prompts code-switch mid-sentence.
DIRECTIVE = re.compile(
    r"\b("
    r"ponme|pon|ponlo|p[oó]ngame|"
    r"dame|d[aá]melo|d[ée]jame|deja|"
    r"hazme|haz|h[aá]game|"
    r"gen[ée]rame|generame|genera|"
    r"a[ñn]ade|a[ñn][aá]dele|agrega|agr[ée]game|incluye|incorpora|"
    r"mu[eé]strame|muestrame|ens[eé][ñn]ame|pres[eé]ntame|presentame|"
    r"usa|utiliza|"
    r"quiero que|necesito que|prefiero que|me gustar[ií]a que|"
    r"recuerda|no olvides|siempre que|cada vez que|"
    r"ordena|ap[óo]yate|prepara|prep[aá]rame|preparame|"
    r"no utilices|no me muestres|deben quedarse|deben ir|deben estar|"
    r"give me|show me|add|include|use|i want you to|i need you to|make sure"
    r")\b", re.I)

# 2. ...about the FORM of the output. Each label is a distinct ask, because
#    "give me checkboxes" and "write it in Spanish" want different fixes.
SHAPE = {
    "fmt:markable": re.compile(
        r"\b(casillas?|checkbox(es)?|check-?box(es)?|checklist|"
        r"marcar|marcable|casilla de verificaci[óo]n|tick)\b|\[\s?\]", re.I),
    "fmt:notes-field": re.compile(
        r"\b(campo de (notas?|comentarios?)|"
        r"espacio (para|por) (cada |mis )?(cosa|notas?|comentarios?|opini)|"
        r"notas? (abiertas?|libres?|finales?|generales?)|"
        r"para (que pueda |poder )?(comentar|opinar|anotar)|"
        r"free-?text|notes? field)\b", re.I),
    "fmt:options": re.compile(
        r"\b(bajo cada (opci[óo]n|decisi[óo]n|punto)|"
        r"(las )?opciones (marcables|a elegir|para elegir)|"
        r"opci[óo]n\s*[A-D]\b|dame opciones|"
        r"(opci[óo]n|posibilidad) de (seleccionar|responder|elegir)|"
        r"decisiones (pendientes|por (tomar|decidir)|tomadas)|"
        r"lo que queda por (decidir|tomar))\b", re.I),
    "fmt:running-summary": re.compile(
        r"\b(resum(e|iendo|en) (las )?decisiones|ve(te)? (cerrando|resumiendo)|"
        r"deja (solo|s[óo]lo|[uú]nicamente) las que|arrastra (las )?decisiones|"
        r"decisiones ya tomadas|running summary)\b", re.I),
    "viz:mockup": re.compile(
        r"\b(mock-?ups?|wireframes?|maquetas?|"
        r"diagramas?|diagram|esquema visual|"
        r"gr[áa]fic[oa]s?|charts?|ascii[- ]art|bocetos?|visuales?)\b", re.I),
    "viz:comprehension": re.compile(
        r"\b(para (que )?(lo )?(entienda|comprenda|se entienda|quede claro)|"
        r"(m[áa]s )?f[áa]cil de entender|esclarecer|"
        r"visualmente|de (forma|manera) visual|ayudas? visuales?|"
        r"para (mejor|mayor) comprensi[óo]n|m[áa]s comprensible|"
        r"m[áa]s visual|entender(lo)? mejor)\b", re.I),
    "lang:artifact": re.compile(
        r"\b(en espa[ñn]ol|en castellano|en ingl[ée]s|in spanish|in english|"
        r"el idioma del? (documento|artefacto|informe|reporte)|"
        r"(documentos?|artefactos?|informes?|reportes?|artifacts?) en espa[ñn]ol|"
        r"en spa\b|idioma (espa[ñn]ol|ingl[ée]s))\b", re.I),
    # Derived from the half-A false negatives of the 2026-08-17 recall study:
    # the reader keeps asking for something he can paste into Outlook, and for
    # less text. Neither had a word in the lexicon, so neither was ever counted.
    "fmt:copyable": re.compile(
        r"\b(no utilices tablas?|sin tablas?|se rompen al (copiar|pegar)|"
        r"copiarlo?s? y pegar|copiar y pegar|para (poder )?copiar(lo)? y pegar|"
        r"formato correcto|sigu(es|as|iendo) la estructura)\b", re.I),
    "fmt:length": re.compile(
        r"\b(un mill[óo]n de caracteres|sin exagerar en texto|"
        r"de manera resumida|no tan (enorme|largo)|m[áa]s corto)\b", re.I),
}

# 3. ...of a DELIVERABLE. Without this clause the detector reads every UI
#    discussion in a frontend project as a formatting preference.
DELIVERABLE = re.compile(
    r"\b(artifacts?|artefactos?|informes?|reportes?|documentos?|"
    r"mock-?ups?|maquetas?|res[uú]menes|resumen|an[áa]lisis|"
    r"backlogs?|planes?|plan|adr|decisiones|"
    r"correos?|e-?mails?|docs?|comunicaci[oó]n|"
    r"me lo (presentes?|muestres?|escribas?)|pres[eé]ntame|presentame|"
    r"me (escribas|generes|presentes|muestres))\b", re.I)

PROXIMITY = 120             # DIRECTIVE  <-> SHAPE
DELIVERABLE_PROXIMITY = 260  # SHAPE      <-> DELIVERABLE


def detect(text, proximity=PROXIMITY, deliverable_proximity=DELIVERABLE_PROXIMITY):
    """Labels whose shape-object satisfies the full three-part conjunction.

    Order matters for cost, not for correctness: both position lists are built
    once and reused across the seven shape patterns.
    """
    if not text:
        return []
    directives = [m.start() for m in DIRECTIVE.finditer(text)]
    if not directives:
        return []
    deliverables = [m.start() for m in DELIVERABLE.finditer(text)]
    if not deliverables:
        return []
    out = []
    for label, rx in SHAPE.items():
        for m in rx.finditer(text):
            at = m.start()
            if any(abs(at - d) <= proximity for d in directives) and \
               any(abs(at - v) <= deliverable_proximity for v in deliverables):
                out.append(label)
                break
    return out


# ---------------------------------------------------------------------------
# Corpus
# ---------------------------------------------------------------------------

def iter_human_prompts(root, since=""):
    """Every prompt a human actually typed, newest-agnostic, with its project.

    Provenance is `prompt_kinds.classify_session`, not `classify`, because the
    handoff wrapper's `continue` positional is only distinguishable with
    whole-session context. That is INSTR-01: 70% of the run-3 "autonomy nudge"
    metric was this one machine string.
    """
    for path in sorted(glob.glob(os.path.join(root, "*", "*.jsonl"))):
        project = os.path.basename(os.path.dirname(path))
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            objs = []
            for line in fh:
                if '"user"' not in line:
                    continue
                try:
                    objs.append(json.loads(line))
                except ValueError:
                    continue
        if not objs:
            continue
        for idx, kind, text in prompt_kinds.classify_session(objs):
            if kind not in prompt_kinds.HUMAN_KINDS or not text:
                continue
            ts = objs[idx].get("timestamp", "")
            if since and ts[:10] < since:
                continue
            yield {"ts": ts, "project": project, "prompt": text}


def short(project):
    """`-Users-me-Documents-projects-foo-ws` -> `foo-ws`, for readable output."""
    return re.sub(r"^-.*-projects-", "", project) or project


def main():
    ap = argparse.ArgumentParser(
        description="Rank prompts that carry a standing preference about the "
                    "FORM of the deliverable. A ranker, not a classifier.")
    ap.add_argument("--transcripts-root", default="",
                    help=f"Claude Code transcript root (default: {TX_ROOT})")
    ap.add_argument("--since", default="",
                    help="ISO date (YYYY-MM-DD); omit for the whole corpus")
    ap.add_argument("--window", choices=("full", "head-tail"), default="full",
                    help="full: read the whole prompt (default, for a miner run). "
                         "head-tail: apply the analyst window, to measure what a "
                         "shard-reading analyst would actually see")
    ap.add_argument("--head", type=int, default=HEAD_DEFAULT)
    ap.add_argument("--tail", type=int, default=TAIL_DEFAULT)
    ap.add_argument("--out", default="", help="write detections to this JSONL path")
    ap.add_argument("--sample", type=int, default=0,
                    help="print N random detections for hand-reading (the only "
                         "way this miner's output becomes evidence)")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    root = os.path.abspath(os.path.expanduser(args.transcripts_root)) \
        if args.transcripts_root else TX_ROOT

    total = 0
    found = []
    for rec in iter_human_prompts(root, args.since):
        total += 1
        text = rec["prompt"] if args.window == "full" \
            else head_tail(rec["prompt"], args.head, args.tail)
        labels = detect(text)
        if labels:
            rec = dict(rec)
            rec["labels"] = labels
            rec["chars"] = len(rec["prompt"])
            found.append(rec)

    if not total:
        sys.exit(f"ERROR: no human prompts under {root}. Wrong --transcripts-root?")

    pct = len(found) / total
    print(f"corpus            : {total:,} human prompts"
          f"{' since ' + args.since if args.since else ''}")
    print(f"window            : {args.window}"
          f"{f' ({args.head}+{args.tail})' if args.window == 'head-tail' else ''}")
    print(f"DETECTED          : {len(found):,} ({pct:.2%})")
    print()
    print(f"  {'label':22} {'hits':>5}  projects")
    print(f"  {'-'*22} {'-'*5}  {'-'*8}")
    for label, n in Counter(l for r in found for l in r["labels"]).most_common():
        projects = {short(r["project"]) for r in found if label in r["labels"]}
        print(f"  {label:22} {n:>5}  {len(projects)}")
    print()
    for project, n in Counter(short(r["project"]) for r in found).most_common(12):
        print(f"  {n:>5}  {project}")

    print("\nThis is a RANKING, not a count of findings. Hand-read a sample with")
    print("--sample before any of it is written down as a number (54% precision")
    print("on the 2026-08-17 calibration; every claim needs its own sample).")

    if args.out:
        with open(args.out, "w") as fh:
            for rec in found:
                fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(f"\nwrote {args.out}")

    if args.sample and found:
        random.seed(args.seed)
        sample = random.sample(found, min(args.sample, len(found)))
        sample.sort(key=lambda r: r["ts"])
        print(f"\n{'='*76}\nHAND-CHECK SAMPLE — {len(sample)} of {len(found)}\n{'='*76}")
        for i, rec in enumerate(sample, 1):
            body = " ".join(rec["prompt"].split())[:400]
            print(f"\n[{i:>2}] {rec['ts'][:16]}  {short(rec['project'])}  {rec['labels']}")
            print(f"     {body}")


if __name__ == "__main__":
    main()
