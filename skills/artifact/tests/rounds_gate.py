#!/usr/bin/env python3
"""The LOOP-008 round runner: seeded consultation-round sequences against the real tools.

    python3 rounds_gate.py [--seed S] [--count N] [--verbose]

prints exactly one stdout line `rounds: X/Y` (Y = N sequences, default 50, seeds S..S+N-1,
base seed on stderr) and exits 0 iff X == Y and Y >= 50. Borrowed from Hypothesis's
RuleBasedStateMachine: a seeded random sequence of operations, the model checked after every
step, a fixed seed that replays a failure (`--seed <failing seed> --count 1 --verbose`).

One sequence = what an agent following SKILL.md does with a consultation:
  build -> [ the reader answers a random subset (reply in the exact shape composer.js copies:
  `## G1 · title`, `### Q1 · title`, `- option`, notes, Other, [not-now], blanks omitted) ->
  save-reply.sh -> either the VERBS (decide, add-item, new-round: they rebuild) or a hand edit of
  the spec plus ONE `spec_build.py --new-round` ] x 2..4 rounds.
It PASSES when every step succeeds (a refused step also must write nothing), the model agrees with the page after each step (ids, order, decided set and verdicts,
proposals, consult-round, ledger rows, decided-round stamps), and every built page has zero
violations under `render-probe.sh --invariants` (probed in batches, one browser call each).
Every step the generator makes is legitimate, so ANY refusal (rc != 0) fails the sequence
(`step-refused`); a sequence also needs at least one successful save-reply (`no-save-reply`).

Model checks (named in --verbose): answered-id-lost, id-renumbered, id-lost, id-appeared,
id-reordered, never-answered-decided, decision-lost, proposal-state, round-number,
ledger-rows, ledger-row-changed, decided-round-stamp, rail-round, save-files, refusal-wrote, traceback, crash,
step-refused, no-save-reply, invariant:<ID>, probe-no-verdict.

Seams (the gate's own test drives them): AIDEX_RENDER_PROBE replaces render-probe.sh;
AIDEX_ROUNDS_SCRIPTS replaces the directory holding spec_build.py, spec_verbs.py, save-reply.sh.
Stdlib only.
"""
import argparse
import hashlib
import html
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

bash_ = "bash"
HERE = os.path.dirname(os.path.abspath(__file__))
REAL_SCRIPTS = os.path.join(os.path.dirname(HERE), "scripts")
SCRIPTS = os.environ.get("AIDEX_ROUNDS_SCRIPTS") or REAL_SCRIPTS
PROBE = os.environ.get("AIDEX_RENDER_PROBE") or os.path.join(REAL_SCRIPTS, "render-probe.sh")
BASE_SEED = 8008
MIN_SEQUENCES = 50
BATCH = 10
STEP_TIMEOUT = 300

# --- words -------------------------------------------------------------------
TEXT = {
    "en": {"nouns": ["the project", "the list", "the report", "the settings page", "the inbox"],
           "feats": ["Delete", "Rename", "Filter", "Export", "Archive", "Share", "Undo", "Pin"],
           "opts": ["Add it", "Skip it", "Defer it", "Rework it"],
           "lead": "Ana opens %s and sees no %s button.", "ask": "Should we add %s?",
           "notes": "Anything else", "group": "Block", "rec": " (recommended)",
           "other": "Other — see my notes"},
    "es": {"nouns": ["el proyecto", "la lista", "el informe", "los ajustes", "la bandeja"],
           "feats": ["Borrar", "Renombrar", "Filtrar", "Exportar", "Archivar", "Compartir", "Deshacer", "Fijar"],
           "opts": ["Añadirlo", "Omitirlo", "Aplazarlo", "Rehacerlo"],
           "lead": "Ana abre %s y no ve el botón %s.", "ask": "¿Añadimos %s?",
           "notes": "Algo más", "group": "Bloque", "rec": " (recomendada)",
           "other": "Otra — lo explico en las notas"},
}
NOTES = ["Needs more thought", "Only for admins", "two lines\nof note", "ñandú café — ok",
         "has `code` and **bold**", "Pick *with* care"]


class Item:
    def __init__(self, ident, title, group, opts, rec, decided=None, proposal=False):
        self.id, self.title, self.group, self.opts, self.rec = ident, title, group, opts, rec
        self.decided, self.proposal = decided, proposal       # verdict text | None ; bool
        self.expired = False        # a proposal that became a plain decision: verdict text unknown


# --- the page, as the model reads it ------------------------------------------
ITEM_RE = re.compile(r'^<section class="consult-item([^"]*)"([^>]*)>', re.M)
ATTR_RE = re.compile(r'([A-Za-z][\w-]*)(?:="([^"]*)")?')
META_RE = re.compile(r'<meta name="consult-round" content="(\d+)">')
SHOWN_RE = re.compile(r'class="railbuilt"[^>]*>[^<]*(?:round|ronda) (\d+)')
LEDGER_RE = re.compile(r'<div class="ledger">(.*?)\n</div>', re.S)
ROW_RE = re.compile(r'<span class="k">(.*?)</span><span class="v">(.*?)</span>', re.S)


def parse_page(text):
    """{'round': int|None, 'items': [(id, verdict|None, proposal, stamp|None)], 'ledger': {id: v}}"""
    m = META_RE.search(text)
    items = []
    for im in ITEM_RE.finditer(text):
        if "consult-notes" in im.group(1):
            continue
        a = {k: (html.unescape(v) if v is not None else "") for k, v in ATTR_RE.findall(im.group(2))}
        if "data-id" not in a:
            continue
        stamp = a.get("data-decided-round")
        items.append((a["data-id"], a.get("data-decided") if "data-decided" in a else None,
                      "data-proposal" in a, int(stamp) if stamp and stamp.isdigit() else None))
    ledger = {}
    lm = LEDGER_RE.search(text)
    if lm:
        for k, v in ROW_RE.findall(lm.group(1)):
            ledger[html.unescape(re.sub(r"<[^>]+>", "", k)).strip()] = html.unescape(re.sub(r"<[^>]+>", "", v)).strip()
    sh = SHOWN_RE.search(text)
    return {"round": int(m.group(1)) if m else None, "items": items, "ledger": ledger,
            "shown": int(sh.group(1)) if sh else None}


# --- the model checks (pure: no files, no tools) -------------------------------
def check_model(model, page, answered):
    """Compare the model with a parsed page. Returns [(check, expected, got)].

    model: dict(items=[Item], round=int, ledger_expect=None|set of ids, ledger_seen={id: v},
                stamps={id: round}, first_page=bool). answered: ids the reader answered so far."""
    out = []
    want = [i.id for i in model["items"]]
    got = [p[0] for p in page["items"]]
    missing, extra = [i for i in want if i not in got], [i for i in got if i not in want]
    lost_answered = [i for i in missing if i in answered]
    if lost_answered:
        out.append(("answered-id-lost", "answered ids %s still on the page" % lost_answered,
                    "page ids: %s" % got))
    rest = [i for i in missing if i not in answered]
    if rest and extra and len(rest) == len(extra) and not lost_answered:
        out.append(("id-renumbered", "ids %s" % want, "ids %s" % got))
    else:
        if rest or (missing and extra and lost_answered):
            out.append(("id-lost", "ids %s on the page" % missing, "page ids: %s" % got))
        if extra:
            out.append(("id-appeared", "no id beyond %s" % want, "extra %s" % extra))
    if not missing and not extra and want != got:
        out.append(("id-reordered", "order %s" % want, "order %s" % got))
    by_id = {p[0]: p for p in page["items"]}
    for it in model["items"]:
        p = by_id.get(it.id)
        if p is None:
            continue
        _, verdict, is_prop, stamp = p
        if it.decided is None and not it.proposal and verdict is not None:
            out.append(("never-answered-decided" if it.id not in answered else "decided-without-decide",
                        "#%s open (no verdict)" % it.id, "#%s data-decided=%r" % (it.id, verdict)))
        elif it.decided is not None and not it.proposal:
            if verdict is None or (not it.expired and verdict != it.decided):
                out.append(("decision-lost", "#%s decided %r" % (it.id, it.decided),
                            "#%s data-decided=%r" % (it.id, verdict)))
        if is_prop != it.proposal:
            out.append(("proposal-state", "#%s proposal=%s" % (it.id, it.proposal),
                        "#%s proposal=%s" % (it.id, is_prop)))
        if verdict is not None:
            seen = model["stamps"].get(it.id)
            want_stamp = model["round"] if seen is None else seen
            if stamp != want_stamp:
                out.append(("decided-round-stamp", "#%s decided in round %s" % (it.id, want_stamp),
                            "#%s data-decided-round=%s" % (it.id, stamp)))
    if page["round"] != model["round"]:
        out.append(("round-number", "consult-round %s" % model["round"], "consult-round %s" % page["round"]))
    if page.get("shown", page["round"]) != page["round"]:
        out.append(("rail-round", "rail reads round %s (the meta)" % page["round"], "rail reads round %s" % page["shown"]))
    led, exp = page["ledger"], model["ledger_expect"]
    if exp is not None and set(led) != set(exp):
        out.append(("ledger-rows", "ledger ids %s" % sorted(exp), "ledger ids %s" % sorted(led)))
    for k, v in model["ledger_seen"].items():
        if k in led and led[k] != v:
            out.append(("ledger-row-changed", "#%s row %r" % (k, v), "#%s row %r" % (k, led[k])))
        elif k not in led:
            out.append(("ledger-row-changed", "#%s row kept" % k, "#%s row gone" % k))
    return out


def classify_output(rc, out):
    """A legitimate step must succeed. Returns a check name or None.
    Every refusal is a failure (the generator only makes legitimate steps); a crash is named apart."""
    if "Traceback (most recent call last)" in out:
        return "traceback"
    if rc < 0 or "Fatal Python error" in out:
        return "crash"
    if rc != 0:
        return "step-refused"
    return None


# --- the spec ------------------------------------------------------------------
def item_block(it, lang):
    t = TEXT[lang]
    attrs = '#%s title="%s"' % (it.id, it.title)
    if it.proposal:
        attrs += " decided=yes proposal=yes"
    lines = ["::: item {%s}" % attrs, "%s %s" % (it.body, it.title), ""]
    lines += ["- %s%s" % (o, " {recommended}" if i == it.rec else "") for i, o in enumerate(it.opts)]
    return "\n".join(lines + [":::"])


def render_spec(lang, title, groups, items):
    t = TEXT[lang]
    out = ['::: masthead {lang="%s" visual="none: consultation"}' % lang, "# %s" % title, ":::", ""]
    for g in groups:
        out += ['::: group {#%s title="%s"}' % (g[0], g[1])]
        out += ["\n\n".join(item_block(i, lang) for i in items if i.group == g[0]), ":::", ""]
    out += ['::: notes {title="%s"}' % t["notes"], ":::", ""]
    return "\n".join(out)


def make_item(rng, lang, ident, n, group, proposal=False):
    t = TEXT[lang]
    k = rng.randint(2, 4)
    opts = rng.sample(t["opts"], k)
    feat = "%s %d" % (rng.choice(t["feats"]), n)
    # the title IS the question: the rail label (title) and the h3 (the question) are one string
    it = Item(ident, t["ask"] % feat, group, opts,
              rng.randrange(k) if (proposal or rng.random() < 0.6) else None, proposal=proposal)
    it.feat = feat
    it.body = t["lead"] % (rng.choice(t["nouns"]), feat)
    if proposal:
        it.decided = opts[it.rec]
    return it


def text_of_edit_set_decided(text, ident, verdict):
    return re.sub(r"^(::: item \{#%s\b[^}\n]*?)\}" % re.escape(ident),
                  lambda m: '%s decided="%s"}' % (m.group(1), verdict), text, count=1, flags=re.M)


def text_of_edit_drop_proposal(text, ident):
    return re.sub(r"^(::: item \{#%s\b[^}\n]*?) proposal=yes" % re.escape(ident), r"\1", text, count=1, flags=re.M)


def text_of_edit_add_item(text, group, block):
    lines = text.split("\n")
    start = next(i for i, ln in enumerate(lines) if re.match(r"::: group \{#%s\b" % re.escape(group), ln))
    depth = 0
    for i in range(start, len(lines)):
        if re.match(r":::+\s+[a-z]", lines[i]):
            depth += 1
        elif re.match(r":::+\s*$", lines[i]):
            depth -= 1
            if depth == 0:
                return "\n".join(lines[:i] + ["", block] + lines[i:])
    raise ValueError("unclosed group %s" % group)


# --- one sequence --------------------------------------------------------------
class Sequence:
    def __init__(self, seed, work, pages_dir):
        self.seed, self.rng = seed, random.Random(seed)
        self.dir, self.pages_dir = work, pages_dir
        self.spec, self.page = os.path.join(work, "r.spec.md"), os.path.join(work, "r.html")
        self.steps, self.failures, self.pages = [], [], []
        self.alive, self.answered, self.pending = True, set(), False
        self.round_ids, self.saves = set(), 0
        self.ledger_seen, self.stamps = {}, {}
        self.round, self.ledger_expect, self.hashes = 1, None, set()

    # tools
    def sh(self, argv, stdin=None):
        p = subprocess.run(argv, cwd=self.dir, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           encoding="utf-8", errors="replace", timeout=STEP_TIMEOUT)
        return p.returncode, p.stdout.replace(self.dir, "<dir>")

    def read(self, path):
        try:
            with open(path, "rb") as fh:
                return fh.read()
        except OSError:
            return None

    def passed(self):
        """No failure, and a depth floor: at least one save-reply succeeded."""
        return not self.failures and self.saves > 0

    def finish(self):
        if self.saves == 0 and not self.failures:
            self.steps = self.steps or ["(sequence)"]
            self.fail("no-save-reply", "at least one save-reply succeeds", "none did (steps: %s)" % self.steps)

    def fail(self, check, expected, got):
        self.failures.append({"seed": self.seed, "step": len(self.steps), "name": self.steps[-1],
                              "check": check, "expected": expected, "got": got})

    # one step: run, classify, check the model
    def step(self, name, argv, stdin=None, writes="page", model_after=None, expect_refusal=False):
        """writes: 'page' (a rebuild: the model is checked on success), 'none' (save-reply:
        spec and page must stay byte-identical). model_after() updates the model on success."""
        self.steps.append(name)
        before = (self.read(self.spec), self.read(self.page))
        rc, out = self.sh(argv, stdin)
        bad = classify_output(rc, out)
        if bad == "step-refused" and expect_refusal:
            bad = None
        if bad:
            self.fail(bad, "the step succeeds", "rc=%d: %s" % (rc, " | ".join(out.strip().split("\n"))[-700:] or "(no output)"))
            self.alive = False
        after = (self.read(self.spec), self.read(self.page))
        if rc != 0:
            self.alive = False
            if writes == "page" and name.startswith(("decide", "add-item", "new-round verb")) and after[0] != before[0]:
                self.fail("refusal-wrote", "spec byte-identical after a refused verb", "spec changed")
            if after[1] != before[1]:
                self.fail("refusal-wrote", "page byte-identical after a refused step", "page changed")
            return False
        if bad:
            return False
        if writes == "none" and after != before:
            self.fail("refusal-wrote", "save-reply leaves spec and page byte-identical", "a file changed")
        if model_after:
            model_after()
        if writes == "page":
            self.after_rebuild()
        return True

    def model(self):
        return {"items": self.items, "round": self.round, "ledger_expect": self.ledger_expect,
                "ledger_seen": self.ledger_seen, "stamps": self.stamps}

    def after_rebuild(self):
        if self.pending:
            self.round, self.pending = self.round + 1, False
        raw = self.read(self.page)
        page = parse_page(raw.decode("utf-8", "replace") if raw else "")
        for it in page["items"]:                                 # a stamp is set once, on first sight
            if it[1] is not None and it[0] not in self.stamps:
                self.stamps[it[0]] = self.round
        found = check_model(self.model(), page, self.answered)
        for f in found:
            self.fail(*f)
        if found:
            self.alive = False
        self.ledger_seen.update(page["ledger"])
        self.ledger_expect = None
        if raw is not None:
            h = hashlib.sha1(raw).hexdigest()
            if h not in self.hashes:
                self.hashes.add(h)
                dst = os.path.join(self.pages_dir, "s%d-%d.html" % (self.seed, len(self.steps)))
                shutil.copyfile(self.page, dst)
                self.pages.append(dst)

    # the sequence
    def play(self):
        rng = self.rng
        self.lang = rng.choice(["en", "es"])
        n = rng.choice([1, 1, 2, 3, 4, 6, 8, 12, 20, 32])
        k = rng.randint(1, min(n, 8 if n > 12 else 5))
        self.groups = [("G%d" % (g + 1), "%s %d" % (TEXT[self.lang]["group"], g + 1)) for g in range(k)]
        self.items, self.next_num = [], 1
        spread = [g[0] for g in self.groups] + [rng.choice(self.groups)[0] for _ in range(n - k)]
        spread.sort()
        for gid in spread:
            prop = rng.random() < 0.08 and n > 1
            it = make_item(rng, self.lang, "Q%d" % self.next_num, self.next_num, gid)
            if prop:
                it = make_item(rng, self.lang, it.id, self.next_num, gid, proposal=True)
                if it.rec is None:
                    it.rec = 0
                    it.decided = it.opts[0]
            self.items.append(it)
            self.next_num += 1
        with open(self.spec, "w", encoding="utf-8") as fh:
            fh.write(render_spec(self.lang, "Round probe %d" % self.seed, self.groups, self.items))
        build = [sys.executable, os.path.join(SCRIPTS, "spec_build.py"), "r.spec.md", "-o", "r.html", "--check"]
        if not self.step("build", build):
            return
        for _ in range(rng.randint(2, 4)):
            self.round_ids = set()
            self.round_chunks, self.round_gnotes, self.round_general = {}, {}, None
            reply, decide_cands = self.make_reply()
            if reply is None:
                return
            save = [bash_, os.path.join(SCRIPTS, "save-reply.sh"), "r.html", "-"]
            if not self.step("save-reply", save, stdin=reply, writes="none",
                             model_after=lambda: self.after_save(reply, decide_cands)):
                return
            if rng.random() < 0.15:          # the reader answers more and pastes again before the rebuild
                more, more_cands = self.make_reply()
                if more is not None:
                    decide_cands = decide_cands + more_cands
                    if not self.step("save-reply (same round)", save, stdin=more, writes="none",
                                     model_after=lambda: self.after_save(more, more_cands)):
                        return
            if rng.random() < 0.25:
                self.hand_round(decide_cands)
            else:
                self.verb_round(decide_cands)
            if not self.alive:
                return

    def after_save(self, reply, cands):
        self.round_ids.update(c[0].id for c in cands)
        self.pending = True
        self.answered.update(c[0].id for c in cands)
        self.saves += 1
        had = len(self.failures)
        saved = self.read(os.path.join(self.dir, ".aidex-artifact-prev", "r.reply.md"))
        ids = re.findall(r"^### (\S+) ", reply, re.M)
        text = (saved or b"").decode("utf-8", "replace")
        for i in ids:
            if "### %s " % i not in text:
                self.fail("save-files", "r.reply.md names %s" % i, "r.reply.md lacks it")
        if not os.path.isfile(os.path.join(self.dir, ".aidex-artifact-prev", "r.answered.html")):
            self.fail("save-files", "r.answered.html written", "missing")
        if len(self.failures) > had:
            self.alive = False

    # the reader
    def make_reply(self):
        rng, t = self.rng, TEXT[self.lang]
        openi = [i for i in self.items if i.decided is None and i.id not in self.round_ids]
        props = [i for i in self.items if i.proposal and i.id not in self.round_ids]
        if not openi and not props:
            return None, []
        pa = rng.choice([0.3, 0.6, 1.0])
        pick = [i for i in openi if rng.random() < pa]
        if not pick and openi:
            pick = [rng.choice(openi)]
        style, cands = {}, []
        for it in pick:
            s = rng.choices(["pick", "pick+note", "note", "other", "notnow"], [55, 20, 10, 8, 7])[0]
            style[it.id] = s
        chunks = {}
        for it in self.items:
            body = None
            if it.id in style:
                s = style[it.id]
                label = it.opts[rng.randrange(len(it.opts))]
                mark = "- %s%s" % (label, t["rec"] if it.opts.index(label) == it.rec else "")
                note = rng.choice(NOTES)
                body = {"pick": mark, "pick+note": mark + "\n\n" + note, "note": note,
                        "other": "- %s\n\n%s" % (t["other"], note), "notnow": "- [not-now]"}[s]
                if s != "notnow":
                    cands.append((it, s, label))
            elif it.proposal and it.id not in self.round_ids and rng.random() < 0.2:
                body = rng.choice(NOTES)
                cands.append((it, "proposal-note", None))
            if body is not None:
                chunks[it.id] = "### %s · %s\n\n%s" % (it.id, it.title, body)
        if not chunks and self.round_chunks:
            return None, []
        self.round_chunks.update(chunks)
        for gid, _ in self.groups:
            if gid not in self.round_gnotes and rng.random() < 0.15:
                self.round_gnotes[gid] = rng.choice(NOTES)
        if self.round_general is None and rng.random() < 0.25:
            self.round_general = rng.choice(NOTES)
        # a composer paste is the reader's WHOLE state of the page: a second paste in the same
        # round repeats the first one's answers and adds the new ones (BL-598 reads it so)
        parts = []
        for gid, gtitle in self.groups:
            mine = [self.round_chunks[i.id] for i in self.items if i.group == gid and i.id in self.round_chunks]
            note = self.round_gnotes.get(gid, "")
            if mine or note:
                parts.append("## %s \u00b7 %s" % (gid, gtitle) + ("\n\n" + note if note else ""))
                parts += mine
        if self.round_general:
            parts.append("### notes \u00b7 %s\n\n%s" % (t["notes"], self.round_general))
        if not parts:
            return None, []
        return "\n\n".join(parts) + "\n", cands

    # the agent, route 1: the verbs
    def verb_round(self, cands):
        rng = self.rng
        todo = []
        for it, s, label in cands:
            if s == "proposal-note":
                continue
            if s in ("pick", "pick+note"):       # a pick with no ask is decided; notes-only stays open
                todo.append((it, label))
        verbs = os.path.join(SCRIPTS, "spec_verbs.py")
        base = [sys.executable, verbs]
        if todo:
            batched = len(todo) > 4 or rng.random() < 0.5
            groups = [todo] if batched else [[x] for x in todo]
            for grp in groups:
                argv = base + ["decide", "r.spec.md"]
                for it, v in grp:
                    argv += ["--id", it.id, "--verdict", v]
                def upd(grp=grp):
                    for it, v in grp:
                        it.decided = v
                if not self.step("decide %s" % " ".join(i.id for i, _ in grp), argv, model_after=upd):
                    return
        for _ in range(rng.choice([0, 0, 1, 2])):
            g = rng.choice(self.groups)[0]
            it = make_item(rng, self.lang, "Q%d" % self.next_num, self.next_num, g)
            argv = base + ["add-item", "r.spec.md", "--group", g, "--id", it.id, "--title", it.title,
                           "--body", "%s %s" % (it.body, it.title)]
            for o in it.opts:
                argv += ["--option", o + (" {recommended}" if it.opts.index(o) == it.rec else "")]
            def upd(it=it):
                at = max([n for n, x in enumerate(self.items) if x.group == it.group], default=-1) + 1
                self.items.insert(at, it)
                self.next_num += 1
            if not self.step("add-item %s" % it.id, argv, model_after=upd):
                return
        if todo and rng.random() < 0.3:
            self.ledger_expect = None
            return
        drop = self.retire_one(todo)
        def upd():
            seen = self.seen_proposals()
            for it in self.items:
                if it.proposal and it.id in seen:
                    it.proposal, it.expired = False, True
            if drop:
                self.items = [i for i in self.items if i.id != drop]
            self.ledger_expect = {i.id: i for i in self.items if i.decided is not None and not i.proposal}
        argv = base + ["new-round", "r.spec.md"] + (["--drop", drop] if drop else [])
        self.step("new-round verb" + (" --drop %s" % drop if drop else ""), argv, model_after=upd)
        if self.alive:
            self.check_ledger_rows()
        if self.alive and rng.random() < 0.2:      # a plain rebuild inside the round: the round must not move
            self.step("rebuild same round", [sys.executable, os.path.join(SCRIPTS, "spec_build.py"),
                                             "r.spec.md", "-o", "r.html", "--check"])

    def retire_one(self, todo):
        """The agent takes one open question off the page (the reader called it invalid): removes
        its block from the spec by hand and returns its id, for `new-round --drop`. Never the last
        item of a group (a group needs one) and never an item decided this round."""
        rng = self.rng
        if rng.random() > 0.12:
            return None
        busy = {i.id for i, _ in todo}
        cands = [i for i in self.items if i.decided is None and i.id not in busy
                 and sum(1 for x in self.items if x.group == i.group) > 1]
        if not cands:
            return None
        gone = rng.choice(cands)
        with open(self.spec, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        start = next(n for n, ln in enumerate(lines) if re.match(r"::: item \{#%s\b" % re.escape(gone.id), ln))
        end = next(n for n in range(start + 1, len(lines)) if re.match(r":::\s*$", lines[n]))
        del lines[start:end + 1]
        with open(self.spec, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines))
        return gone.id

    def seen_proposals(self):
        raw = self.read(os.path.join(self.dir, ".aidex-artifact-prev", "r.answered.html"))
        return {p[0] for p in parse_page((raw or b"").decode("utf-8", "replace"))["items"] if p[2]}

    def check_ledger_rows(self):
        """Row text of a freshly synced ledger: `<title> (<verdict>)` for every settled item."""
        page = parse_page((self.read(self.page) or b"").decode("utf-8", "replace"))
        for it in self.items:
            if it.decided is not None and not it.proposal and not it.expired and it.id in page["ledger"]:
                want = "%s (%s)" % (it.title, it.decided)
                if page["ledger"][it.id] != want:
                    self.fail("ledger-rows", "#%s row %r" % (it.id, want), "#%s row %r" % (it.id, page["ledger"][it.id]))

    # the agent, route 2: hand-edit the spec, then ONE --new-round build
    def hand_round(self, cands):
        rng = self.rng
        with open(self.spec, encoding="utf-8") as fh:
            text = fh.read()
        decided, seen = [], self.seen_proposals()
        for it, s, label in cands:
            if s in ("pick", "pick+note"):
                text = text_of_edit_set_decided(text, it.id, label)
                decided.append((it, label))
        for it in self.items:
            if it.proposal and it.id in seen:
                text = text_of_edit_drop_proposal(text, it.id)
        new = []
        for _ in range(rng.choice([0, 1, 2])):
            g = rng.choice(self.groups)[0]
            it = make_item(rng, self.lang, "Q%d" % self.next_num, self.next_num, g, proposal=rng.random() < 0.3)
            self.next_num += 1
            text = text_of_edit_add_item(text, g, item_block(it, self.lang))
            new.append(it)
        with open(self.spec, "w", encoding="utf-8") as fh:
            fh.write(text)
        def upd():
            for it, label in decided:
                it.decided = label
            for it in self.items:
                if it.proposal and it.id in seen:
                    it.proposal, it.expired = False, True
            for it in new:
                at = max([n for n, x in enumerate(self.items) if x.group == it.group], default=-1) + 1
                self.items.insert(at, it)
        argv = [sys.executable, os.path.join(SCRIPTS, "spec_build.py"), "r.spec.md", "-o", "r.html", "--check", "--new-round"]
        self.step("hand edit + build --new-round", argv, model_after=upd)


def run_sequence(seed, pages_dir):
    work = tempfile.mkdtemp(prefix="rounds-%d-" % seed)
    try:
        seq = Sequence(seed, work, pages_dir)
        seq.play()
        seq.finish()
        return seq
    finally:
        shutil.rmtree(work, ignore_errors=True)


# --- probe, in batches -----------------------------------------------------------
def probe_pages(pages):
    """-> ({page basename: [(invariant, detail)]}, error text or '')."""
    if not pages:
        return {}, ""
    r = subprocess.run(["bash", PROBE, "--invariants"] + pages, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       encoding="utf-8", errors="replace")
    summary = re.search(r"^INVARIANTS pages=(\d+) violations=(\d+)$", r.stdout, re.M)
    found, n = {}, 0
    for ln in r.stdout.splitlines():
        m = re.match(r"^INV (\S+) (\S+) (.*)$", ln)
        if m:
            n += 1
            found.setdefault(m.group(2), []).append((m.group(1), m.group(3)))
    # a verdict is consistent: every page counted, the INV lines add up to the summary, and the
    # exit code says the same thing (1 iff violations)
    if (not summary or int(summary.group(1)) != len(pages) or int(summary.group(2)) != n
            or r.returncode != (1 if n else 0)):
        return {}, "probe gave no verdict on %d page(s) (rc=%d, %d INV line(s)): %s" % (
            len(pages), r.returncode, n, (r.stderr.strip() or r.stdout.strip())[-300:])
    return found, ""


def run_batch(seeds):
    pages_dir = tempfile.mkdtemp(prefix="rounds-pages-")
    try:
        seqs = []
        for s in seeds:
            try:
                seqs.append(run_sequence(s, pages_dir))
            except subprocess.TimeoutExpired:
                bad = Sequence(s, "", pages_dir)
                bad.steps.append("(a step)")
                bad.fail("step-timeout", "a step ends within %ds" % STEP_TIMEOUT, "timed out")
                seqs.append(bad)
        pages = [p for q in seqs for p in q.pages]
        found, err = probe_pages(pages)
        for q in seqs:
            for p in q.pages:
                name = os.path.basename(p)
                step = int(name.rsplit("-", 1)[1].split(".")[0])
                if err:
                    q.steps = q.steps or ["(probe)"]
                    q.failures.append({"seed": q.seed, "step": step, "name": q.steps[step - 1], "check": "probe-no-verdict",
                                       "expected": "a probe verdict", "got": err})
                    break
                for inv, detail in found.get(name, []):
                    q.failures.append({"seed": q.seed, "step": step, "name": q.steps[step - 1],
                                       "check": "invariant:" + inv, "expected": "no %s violation" % inv, "got": detail})
        return seqs
    finally:
        shutil.rmtree(pages_dir, ignore_errors=True)


def verdict(x, y):
    """Exit code: 0 iff every sequence passed and there were at least MIN_SEQUENCES."""
    return 0 if x == y and y >= MIN_SEQUENCES else 1


def report(failed, verbose):
    classes = {}
    for q in failed:
        firsts = {}
        for f in sorted(q.failures, key=lambda f: f["step"]):
            firsts.setdefault(f["check"], f)
        for check, f in firsts.items():
            classes.setdefault(check, []).append((q.seed, f))
    if not verbose:
        return
    for check, rows in sorted(classes.items(), key=lambda kv: -len(kv[1])):
        print("class %s: %d sequence(s), smallest seed %d, e.g. step %d (%s)" % (
            check, len(rows), min(r[0] for r in rows), rows[0][1]["step"], rows[0][1]["name"]), file=sys.stderr)
    for q in sorted(failed, key=lambda q: q.seed):
        for f in sorted(q.failures, key=lambda f: f["step"]):
            print("FAIL seed=%d step=%d (%s) check=%s\n  expected: %s\n  got: %s" % (
                f["seed"], f["step"], f["name"], f["check"], f["expected"], f["got"]), file=sys.stderr)
        print("  replay: python3 %s --seed %d --count 1 --verbose" % (os.path.abspath(__file__), q.seed), file=sys.stderr)



def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seed", type=int, default=BASE_SEED)
    ap.add_argument("--count", type=int, default=MIN_SEQUENCES)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args(argv)
    print("rounds-gate: base seed %d, %d sequence(s)" % (args.seed, args.count), file=sys.stderr)
    seeds = list(range(args.seed, args.seed + args.count))
    failed = []
    for i in range(0, len(seeds), BATCH):
        for q in run_batch(seeds[i:i + BATCH]):
            if not q.passed():
                failed.append(q)
    x = len(seeds) - len(failed)
    report(failed, args.verbose)
    print("rounds: %d/%d" % (x, len(seeds)))
    return verdict(x, len(seeds))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
