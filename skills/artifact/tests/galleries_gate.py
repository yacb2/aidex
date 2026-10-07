#!/usr/bin/env python3
"""The LOOP-008 galleries gate: ui-contract galleries keep the kit's chrome and their cells.

    python3 galleries_gate.py [--verbose] [--expected] [--only SUBSTRING]

stdout is exactly one line, `galleries: X/Y`, with ` (N migrated)` when N manifest specs were
measured from their migrated copy and ` (pin P)` when Y is not the pinned count; everything else
goes to stderr. Exit 0 iff X == Y and Y equals the pinned count (`--expected` prints it).
`--only` measures the units whose tag contains the substring (a replay aid: the pin check then
fails by design).

Units (Y = MANIFEST_PIN + GENERATED_PIN, both literals; the generated set is checked against
GENERATED_PIN at import, so dropping a case refuses the gate instead of shrinking Y):
  (a) the FROZEN MANIFEST: <corpus>/galleries/<name>/ holds a harvested ui-contract gallery spec
      (spec.md), its rows, its captures under root/ and its relative assets, harvested once by
      galleries_harvest.py. Each is rebuilt with TODAY's builder in a temp tree of symlinks (never
      written into the corpus). The original is tried first; <corpus>/galleries/migrated/<name>/
      is built instead ONLY while the original is refused for the reason MIGRATED_EXPECT records for it (one row in
      galleries/MIGRATIONS.md each; an original refused for any OTHER reason is a BUILD:new-refusal
      failure naming that reason); a migrated copy beside an original that builds is reported `stale migration` and
      ignored. The live walk of the projects is a stderr census ("K gallery specs on disk not in
      the manifest") and never fails.
  (b) the fixed GENERATED set below: gallery specs plus rows.json and PNG captures built here.

A unit PASSES when it builds and
  1. `render-probe.sh --invariants` reports no violation for the page (one probe call for all;
     every message of every invariant is kept),
  2. the page carries the kit this checkout ships: `<meta name="artifact-kit">` with the
     VERSION of assets/artifact-kit, and the kit's tokens.css and components.css verbatim,
  3. every gallery declares at least one shown cell, every declared cell renders (section
     exists, one tile per declared capture, each tile shows the capture the row declares for it
     (sha256 of the image file against sha256 of the declared file: before, after, captures[id],
     states[i].capture), each tile's image file exists with real size and is not hidden, each
     caption is visible), an alternatives or states row never shows two tiles with the same
     image CONTENT, no two shown rows of one gallery share an after-capture content hash, and no
     section with tiles is undeclared. A live before/after pair with identical pixels is refused
     by the builder (owner, LOOP-008 Q8, 2026-10-07): case identical-pair is refusal-only.
or it is refused loudly (non-zero exit, a message, no traceback, no page, no residue) and its
INTENT allows that: `valid` may not be refused; `refusal-only` (invalid input) must be refused
with a message naming the `gallery` block (or the case's own `expect`).

Test seams: AIDEX_RENDER_PROBE replaces scripts/render-probe.sh; AIDEX_GALLERIES_MANIFEST the
manifest dir; AIDEX_GALLERIES_PROJECTS the projects dir (census).
"""
import argparse
import concurrent.futures
import contextlib
import hashlib
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.parse
import zlib
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SCRIPTS = os.path.join(SKILL, "scripts")
KIT = os.path.join(SKILL, "assets", "artifact-kit")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))
import gallery_items  # noqa: E402
import spec_build  # noqa: E402
import spec_parser  # noqa: E402

SPEC_BUILD = os.path.join(SCRIPTS, "spec_build.py")
PROBE = os.environ.get("AIDEX_RENDER_PROBE") or os.path.join(SCRIPTS, "render-probe.sh")
PROJECTS = os.environ.get("AIDEX_GALLERIES_PROJECTS") or os.path.expanduser("~/Documents/projects")
MANIFEST_PIN = 13           # galleries/<name>/ dirs in the manifest (harvested 2026-10-07)
GENERATED_PIN = 31          # len(generated_cases()), checked at import next to PINNED
# Why today's builder refuses each ORIGINAL that has a migrated copy: a substring of its message. The
# copy is measured only while the original is refused for this reason; any other refusal is a new defect.
_PAREN = "carries a parenthetical"
_HL = "needs a 'highlight'"
MIGRATED_EXPECT = {
    "asset_lab_ws__.context__artifacts__2026-09-29-bl011-esqueleto-revision__bl011-esqueleto-revision": "has no 'look' line",
    "asset_lab_ws__.context__artifacts__2026-10-01-inicio-rediseno-consulta__inicio-rediseno-consulta": _HL,
    "asset_lab_ws__.context__artifacts__2026-10-03-actividades-rediseno-consulta__actividades-rediseno-consulta": _PAREN,
    "asset_lab_ws__.context__artifacts__2026-10-03-revision-operaciones-consulta__revision-operaciones-consulta": "is pixel-identical to the one of",
    "echo_lab_ws__.context__plans__2026-10-01-access-delivery__accesos-review": _PAREN,
    "echo_lab_ws__.context__plans__2026-10-01-access-delivery__s3-review": _PAREN,
    "echo_lab_ws__.context__plans__2026-10-01-access-delivery__s5-review": _HL,
    "echo_lab_ws__.context__research__2026-10-03-voice-pairs-page__r2-consulta": _PAREN,
    "dashboard_template_ws___tmp__ui-contract__consult-patterns-lfm__patrones-lfm": "its before and after are pixel-identical",
}
BUILD_TIMEOUT = 120
PROBE_TIMEOUT = 900
WORKERS = max(2, min(6, os.cpu_count() or 2))
SKIP_DIRS = {"node_modules", ".git", "wt", ".venv", "venv", "__pycache__"}
TRACEBACK = "Traceback (most recent call last)"
GALLERY_LINE = re.compile(r"^:{3,}\s*gallery\b", re.M)


def manifest_dir():
    """The galleries manifest: AIDEX_GALLERIES_MANIFEST, else <corpus>/galleries, the corpus found by
    climbing from this file (the loop worktree sits under <workspace>/_tmp/wt/)."""
    if os.environ.get("AIDEX_GALLERIES_MANIFEST"):
        return os.environ["AIDEX_GALLERIES_MANIFEST"]
    d = HERE
    while True:
        c = os.path.join(d, ".context", "research", "2026-09-24-artifact-spec-corpus")
        if os.path.isdir(c):
            return os.path.join(c, "galleries")
        if os.path.dirname(d) == d:
            return ""
        d = os.path.dirname(d)


# ---- the generated set -------------------------------------------------------------------

def png(k, w=160, h=90):
    """A flat PNG whose colour is `k`, so every tile of a case is a different image. Consecutive
    k are spread far apart in two channels: the builder treats channel values within 4 of 255 as
    the same pixel (identical pairs, repeated regions), so k and k+1 must differ by more."""
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))
    px = bytes([(k * 53) % 256, (k * 101) % 256, 128])
    raw = b"".join(b"\x00" + px * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


class Case:
    def __init__(self, tag, intent, lang="en"):
        self.tag, self.intent, self.lang = tag, intent, lang
        self.expect = "`gallery`"      # what a refusal of this case must say
        self.files, self.rows, self.raw_rows = {}, [], None
        self.doc = {"gallery": "gal", "variants": ["light-desktop"]}
        self.items = ""          # extra consult items, spec text
        self.gallery_attrs = 'rows="rows.json" root="."'
        self._k = 0

    def cap(self, name=None, w=160, h=90, same_as=None):
        """Write one capture and return its path (a new image unless `same_as`)."""
        if same_as:
            return same_as
        self._k += 1
        path = "shots/%s.png" % (name or "c%03d" % self._k)
        self.files[path] = png(self._k + len(self.tag) * 977, w, h)
        return path

    def row(self, cell, kind="review", pair=True, variant="light-desktop", **extra):
        r = {"cell": cell, "variant": variant, "kind": kind,
             "look": "What changed in %s." % cell}
        if kind != "alternatives" and kind != "states":
            if pair and kind != "sample":
                r["before"] = self.cap()
            r["after"] = self.cap()
        r.update(extra)
        self.rows.append(r)
        return r

    def build_files(self):
        files = dict(self.files)
        doc = dict(self.doc, rows=self.rows)
        files["rows.json"] = (self.raw_rows if self.raw_rows is not None
                              else json.dumps(doc, ensure_ascii=False, indent=1)).encode("utf-8")
        title = {"es": "Galería de prueba", "en": "Test gallery"}[self.lang]
        files["p.spec.md"] = (
            '::: masthead {eyebrow="gate" lang="%s" title="%s" visual="none: gate fixture"}\n'
            "A fixture page for the galleries gate.\n:::\n\n"
            '::: group {#G1 title="Decide" heading="Decide"}\n'
            '::: item {#Q1 title="Which direction?"}\nPick one.\n\n- Option A {recommended}\n- Option B\n- Option C\n:::\n'
            "%s:::\n\n"
            '::: gallery {#GA title="%s" %s}\n:::\n\n'
            '::: notes {#notes title="Notes"}\n:::\n'
            % (self.lang, title, self.items, title, self.gallery_attrs)).encode("utf-8")
        return files


def _alts(c, labels):
    c.doc["alternatives"] = [{"id": "a%d" % i, "label": lb} for i, lb in enumerate(labels)]
    return [a["id"] for a in c.doc["alternatives"]]


def generated_cases():
    cases = []

    def new(tag, intent="valid", lang="en"):
        c = Case(tag, intent, lang)
        cases.append(c)
        return c

    for n in (1, 5, 30):                                            # row counts, both languages
        for lang in ("es", "en"):
            c = new("rows%d-%s" % (n, lang), lang=lang)
            c.doc["variants"] = ["light-desktop", "dark-mobile"]
            for i in range(n):
                c.row("cell-%02d" % i, pair=i % 3 != 2, variant=c.doc["variants"][i % 2],
                      **({"noBefore": "new screen"} if i % 3 == 2 and n > 1 else {}))
    for lang in ("es", "en"):                    # look and note are prose: inline markup is rendered
        c = new("markdown-look-%s" % lang, lang=lang)
        c.row("look", look="Look at **this**, `that`, _under_ and [the spec](https://example.test/x).")
        c.row("note", note=["First **point**", "Second `point` with [a link](https://example.test/y)"])
    c = new("markdown-title")                    # title follows the title= rules: markers are rendered
    c.row("bold", title="A **bold** title with `code`")
    c = new("long-labels")
    c.row("long-title", title="T" * 200, look="L" * 90)
    c.row("a-cell-with-a-quite-long-slug-" + "x" * 30, look="word " * 40)
    c.row("unbroken", look="U" * 120)
    c = new("long-alternatives", lang="es")
    ids = _alts(c, ["Opción con una etiqueta muy larga " * 4, "B" * 100, "Corta"])
    c.row("lista", kind="alternatives", captures={i: c.cap() for i in ids}, look="Compara las tres.")
    c = new("pairs-unrequested")
    c.doc["variants"] = ["light-desktop", "dark-desktop", "light-mobile"]
    c.row("changed", pair=True)
    c.row("moved", kind="unrequested", also=["dark-desktop"], look="This moved without being asked.")
    c.row("fresh", pair=False, noBefore="the screen did not exist")
    c = new("identical-pair", "refusal-only")    # Q8: a live pair showing no change is refused
    c.expect = "pixel-identical"
    same = c.cap()
    c.row("unchanged", before=same, after=same)
    c = new("decision-waits")                                       # a row built on an open item
    c.items = "\n::: item {#Q2 title=\"Which layout?\"}\nPick one.\n\n- Layout A\n- Layout B\n:::\n"
    c.row("waits", depends_on="Q2")
    c.row("plain")
    c = new("decision-options")                                     # proposals as options of one row
    ids = _alts(c, ["Layout A", "Layout B", "Today"])
    c.row("proposals", kind="alternatives", captures={i: c.cap() for i in ids}, look="One option per proposal.")
    c = new("decided-alternatives", lang="es")
    ids = _alts(c, ["A, fila desplegable", "B, panel lateral"])
    c.row("lista", kind="alternatives", captures={i: c.cap() for i in ids}, decided="A, fila desplegable")
    c.row("detalle", kind="alternatives", captures={i: c.cap() for i in ids})
    c = new("states-row")
    c.row("estados", kind="states", states=[{"id": "empty", "label": "Empty", "capture": c.cap()},
                                              {"id": "loaded", "label": "Loaded", "capture": c.cap()},
                                              {"id": "error", "label": "Error", "capture": c.cap()}],
          look="Tick each state you approve.")
    c = new("na-and-dropped")
    c.row("shown")
    c.rows.append({"cell": "na", "variant": "light-desktop", "kind": "review", "notApplicable": "the screen has no such state"})
    c.rows.append({"cell": "gone", "variant": "light-desktop", "kind": "review", "dropped": "removed from the round",
                   "look": "x", "after": c.cap()})
    c = new("highlight")
    c.row("marked", highlight={"x": 10, "y": 10, "w": 40, "h": 20}, highlight_before={"x": 5, "y": 5, "w": 30, "h": 20})
    c = new("mobile-tall")
    c.doc["variants"] = ["light-mobile", "dark-mobile"]
    c.row("phone", variant="light-mobile", before=c.cap(w=39, h=84), after=c.cap(w=39, h=84))
    c.row("phone2", variant="dark-mobile", pair=False, noBefore="new", after=c.cap(w=39, h=84))
    c = new("sample-only")
    c.row("illustration", kind="sample")
    # invalid input: refused loudly, naming the gallery block
    c = new("bad-missing-capture", "refusal-only")
    c.row("lost")
    c.rows[0]["after"] = "shots/not-there.png"
    c = new("bad-no-look", "refusal-only")
    c.row("silent")
    del c.rows[0]["look"]
    c = new("bad-json", "refusal-only")
    c.raw_rows = '{"gallery": "gal", "variants": ['
    c = new("bad-kind", "refusal-only")
    c.row("odd", kind="mystery")
    c = new("bad-lang", "refusal-only")
    c.row("ok")
    c.gallery_attrs += ' lang="fr"'
    c = new("bad-rows-file", "refusal-only")
    c.row("ok")
    c.gallery_attrs = 'rows="absent.json" root="."'
    c = new("bad-duplicate-label", "refusal-only")
    _alts(c, ["Same", "Same"])
    c.row("lista", kind="alternatives", captures={"a0": c.cap(), "a1": c.cap()})
    c = new("bad-title-link", "refusal-only")    # a link in a title is refused (title= rules)
    c.expect = "raw-link"
    c.row("link", title="See [the spec](https://example.test/x)")
    c = new("bad-proposals-as-rows", "refusal-only")   # asset_lab 4b192d67: a decision shown as independent rows
    c.row("proposal-a", pair=False)
    c.row("proposal-b", pair=False)
    c.row("hoy", pair=False)
    c = new("bad-unknown-dependency", "refusal-only")
    c.row("waits", depends_on="Q99")
    return cases


# ---- units, build ------------------------------------------------------------------------

def on_disk_specs(projects):
    """[(project, spec path)] for every *.spec.md under projects/*/ with a gallery block (a census
    and the harvester's source; the gate's own input is the manifest)."""
    found = []
    for proj in sorted(os.listdir(projects)) if os.path.isdir(projects) else []:
        top = os.path.join(projects, proj)
        for dirpath, dirs, names in os.walk(top):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not os.path.islink(os.path.join(dirpath, d)))
            if proj == "aidex_ws" and os.path.relpath(dirpath, top).split(os.sep)[0] in ("aidex", "_tmp"):
                dirs[:] = []
                continue
            for n in sorted(names):
                p = os.path.join(dirpath, n)
                if n.endswith(".spec.md") and not os.path.islink(p):
                    try:
                        text = open(p, encoding="utf-8", errors="replace").read()
                    except OSError:
                        continue
                    if GALLERY_LINE.search(text):
                        found.append((proj, p))
    return found


def manifest_units(mdir):
    """[unit] for each galleries/<name>/ (spec.md inside), with `alt` = its migrated copy's unit."""
    def unit(d, name, migrated):
        return {"tag": "disk:" + name, "intent": "valid", "link_dir": d, "files": None, "spec": None,
                "source": (open(os.path.join(d, "ORIGIN")).read().strip() if os.path.isfile(os.path.join(d, "ORIGIN")) else d),
                "replay": "python3 %s --only disk:%s --verbose" % (os.path.abspath(__file__), name),
                "migrated": migrated, "expect": "`gallery`", "alt": None}
    out = []
    if not mdir or not os.path.isdir(mdir):
        return out
    for name in sorted(os.listdir(mdir)):
        d = os.path.join(mdir, name)
        if name == "migrated" or not os.path.isfile(os.path.join(d, "spec.md")):
            continue
        u = unit(d, name, False)
        m = os.path.join(mdir, "migrated", name)
        if os.path.isfile(os.path.join(m, "spec.md")):
            u["alt"] = unit(m, name, True)
            u["alt_expect"] = MIGRATED_EXPECT.get(name)
        out.append(u)
    return out


def case_unit(c):
    return {"tag": "gen:" + c.tag, "intent": c.intent, "source": "generated case %r in %s" % (c.tag, __file__),
            "spec": None, "files": c.build_files(), "link_dir": None, "migrated": False, "alt": None,
            "expect": c.expect, "replay": "python3 %s --only gen:%s --verbose" % (os.path.abspath(__file__), c.tag)}


def make_units(mdir, only=""):
    units = manifest_units(mdir)
    units += [case_unit(c) for c in generated_cases()]
    return [u for u in units if only in u["tag"]]


def classify_build(rc, output, page_exists, residue):
    if TRACEBACK in output:
        return "traceback"
    if rc < 0 or "Fatal Python error" in output:
        return "crashed"
    if rc == 0:
        return "built" if page_exists else "no-page"
    if page_exists or residue:
        return "half-written"
    if not output.strip():
        return "silent-refusal"
    return "refused"


def said_of(out):
    lines = [ln.strip() for ln in out.strip().splitlines() if ln.strip()]
    return next((ln for ln in lines if "`gallery`" in ln or "has no file" in ln or ln.startswith("FAIL [")),
                lines[0] if lines else "")[:240]


def build_unit(root, n, u):
    """Build one unit in its own temp dir. Returns {unit, dir, page, kind, fails}. The page is
    rebuilt<n>.html, a name no other unit of the run shares (the probe reports by basename)."""
    d = os.path.join(root, "u%03d" % n)
    os.makedirs(d)
    spec_name, page_name = "p.spec.md", "rebuilt%03d.html" % n
    if u["link_dir"]:
        for name in os.listdir(u["link_dir"]):
            if name not in (".aidex-artifact-prev", "spec.md", "ORIGIN"):   # the corpus's residue is not this build's
                os.symlink(os.path.join(u["link_dir"], name), os.path.join(d, name))
        shutil.copyfile(os.path.join(u["link_dir"], "spec.md"), os.path.join(d, spec_name))
    else:
        for name, data in u["files"].items():
            os.makedirs(os.path.dirname(os.path.join(d, name)), exist_ok=True)
            with open(os.path.join(d, name), "wb") as f:
                f.write(data)
    page = os.path.join(d, page_name)
    res = {"unit": u, "dir": d, "page": None, "fails": []}
    try:
        r = subprocess.run([sys.executable, SPEC_BUILD, os.path.join(d, spec_name), "-o", page],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=BUILD_TIMEOUT)
        out, rc = r.stdout.decode("utf-8", "replace"), r.returncode
    except subprocess.TimeoutExpired:
        res["fails"].append(("BUILD:timeout", "build past %ds" % BUILD_TIMEOUT))
        res["kind"] = "timeout"
        return res
    prev = os.path.join(d, ".aidex-artifact-prev")
    residue = os.path.isdir(prev) and bool(os.listdir(prev))
    kind = classify_build(rc, out, os.path.exists(page), residue)
    said = said_of(out)
    res["kind"], res["out"] = kind, out
    if kind == "refused":
        if u["intent"] == "valid":
            why = "source-missing" if "has no file" in out else "valid-refused"
            res["fails"].append(("BUILD:" + why, said))
        elif u["expect"] not in out:
            res["fails"].append(("BUILD:wrong-refusal", said))
    elif kind == "built":
        if u["intent"] == "refusal-only":
            res["fails"].append(("BUILD:refusal-only-built", "invalid input built a page"))
        else:
            res["page"] = page
    else:
        res["fails"].append(("BUILD:" + kind, said))
    return res


# ---- the page checks ---------------------------------------------------------------------

class Sections(HTMLParser):
    """The `.consult-gallery` sections of a page: data-id -> [tile dicts]."""
    VOID = ("br", "img", "input", "meta", "link", "hr")

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.sections, self.stack, self.cur, self.fig, self.in_cap, self.metas = {}, [], None, None, False, []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "meta":
            self.metas.append(a)
        if tag == "img":
            if self.fig is not None:
                style = (a.get("style") or "").replace(" ", "").lower()
                self.fig["src"] = a.get("src", "")
                self.fig["img_hidden"] = (any(h for _, h in self.stack) or "hidden" in a
                                          or "display:none" in style or "visibility:hidden" in style
                                          or str(a.get("width", "")).strip() == "0" or str(a.get("height", "")).strip() == "0")
            return
        if tag in self.VOID:
            return
        style = (a.get("style") or "").replace(" ", "").lower()
        self.stack.append((tag, "hidden" in a or "display:none" in style or "visibility:hidden" in style))
        if tag == "section" and "consult-gallery" in (a.get("class") or "").split() and a.get("data-id"):
            self.cur = self.sections.setdefault(a["data-id"], [])
            self.cur_depth = len(self.stack)
        if tag == "figure" and self.cur is not None:
            self.fig = {"tile": a.get("data-tile", ""), "src": "", "caption": "", "hidden": False, "img_hidden": False}
            self.cur.append(self.fig)
        if tag == "figcaption" and self.fig is not None:
            self.in_cap = True
            self.fig["hidden"] = any(h for _, h in self.stack)

    def handle_endtag(self, tag):
        if tag in self.VOID:
            return
        while self.stack and self.stack[-1][0] != tag:
            self.stack.pop()
        if self.stack:
            self.stack.pop()
        if tag == "figcaption":
            self.in_cap = False
        if tag == "figure":
            self.fig = None
        if tag == "section" and self.cur is not None and len(self.stack) < self.cur_depth:
            self.cur = None

    def handle_data(self, data):
        if self.in_cap and self.fig is not None:
            self.fig["caption"] += data


def read_kit(name):
    try:
        with open(os.path.join(KIT, name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def walk(nodes):
    for n in nodes:
        yield n
        yield from walk(n.children)


def declared_cells(spec_text, base_dir):
    """(cells, all_ids, problems). cells: [{"id", "row", "gallery"}] for the rows the page must show,
    read from every `gallery` block of the spec (found by the builder's own parser) minus the ids the
    masthead drops, `dropped` rows and not-applicable rows. all_ids: every row id, shown or not.
    problems: [(code, detail)] for a gallery that declares no shown cell or whose rows cannot be read."""
    cells, all_ids, problems = [], set(), []
    try:
        nodes = list(walk(spec_parser.parse(spec_text)))
    except spec_parser.SpecSyntaxError as exc:
        return cells, all_ids, [("CELL:none", "the spec does not parse: %s" % exc)]
    dropped = set()
    for n in nodes:
        dropped.update(n.attrs.get("dropped-ids", "").split())
    for n in nodes:
        if n.block_type != "gallery":
            continue
        path = os.path.join(base_dir, n.attrs.get("rows", ""))
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                doc = gallery_items.load(path)
        except (SystemExit, OSError):
            problems.append(("CELL:none", "gallery %s: rows %r cannot be read" % (n.id, n.attrs.get("rows"))))
            continue
        try:
            root = (os.path.normpath(os.path.join(base_dir, n.attrs["root"])) if "root" in n.attrs
                    else spec_build._checkout_root(n, base_dir))
        except spec_build.SpecBuildError as exc:
            problems.append(("CELL:none", "gallery %s: no capture root: %s" % (n.id, exc)))
            continue
        shown = 0
        for row in doc["rows"]:
            if not isinstance(row, dict):
                continue
            rid = gallery_items.row_id(doc["gallery"], row.get("cell"), row.get("variant"), row.get("kind", "review"))
            all_ids.add(rid)
            if "dropped" in row or "notApplicable" in row or rid in dropped:
                continue
            shown += 1
            cells.append({"id": rid, "row": row, "gallery": doc["gallery"], "root": root})
        if not shown:
            problems.append(("CELL:none", "gallery %s (%s) declares no shown cell" % (n.id, n.attrs.get("rows"))))
    return cells, all_ids, problems


def declared_tiles(row):
    n = 0
    for k in ("before", "after"):
        n += k in row
    caps = row.get("captures")
    if isinstance(caps, dict):
        n += sum(len(v) if isinstance(v, dict) else 1 for v in caps.values())
    if isinstance(row.get("states"), list):
        n += len(row["states"])
    return n


def declared_captures(row, root):
    """{tile id: capture file} the builder shows for a row: before, after, captures[id] (or
    captures[id][state] as `id-state`) and states[i].capture, joined to the gallery's root."""
    out = {}
    def put(tile, path):
        if isinstance(path, str):
            out[tile] = os.path.join(root, path.lstrip("/"))
    for k in ("before", "after"):
        if k in row:
            put(k, row[k])
    if isinstance(row.get("captures"), dict):
        for aid, v in row["captures"].items():
            if isinstance(v, dict):
                for st, path in v.items():
                    put("%s-%s" % (aid, st), path)
            else:
                put(aid, v)
    if isinstance(row.get("states"), list):
        for st in row["states"]:
            if isinstance(st, dict):
                put(st.get("id"), st.get("capture"))
    return out


def file_hash(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    return hashlib.sha256(data).hexdigest() if data else None


def parse_page(html):
    p = Sections()
    p.feed(html)
    p.close()
    return p


def content_hash(page, src):
    """sha256 of the image file a tile's src names, beside the page; None when there is no such file."""
    return file_hash(os.path.join(os.path.dirname(page), urllib.parse.unquote(src)))


def check_page(page, declared):
    """[(code, detail)] the page fails on. `declared` is declared_cells' triple."""
    cells, all_ids, problems = declared
    fails = list(problems)
    with open(page, encoding="utf-8", errors="replace") as f:
        html = f.read()
    parsed = parse_page(html)
    version = (read_kit("VERSION") or "").strip()
    meta = [m for m in parsed.metas if m.get("name") == "artifact-kit"]
    if not meta or meta[0].get("content") != version:
        fails.append(("KIT:marker", "meta artifact-kit is %r, this checkout ships %r"
                      % (meta[0].get("content") if meta else None, version)))
    for name in ("tokens.css", "components.css"):
        css = read_kit(name)
        if css is None or css not in html:
            fails.append(("KIT:" + name, "the page does not carry the kit's %s verbatim" % name))
    sections = parsed.sections
    after_of = {}                                       # (gallery, content hash) -> [row ids]
    for c in cells:
        rid, row = c["id"], c["row"]
        tiles = sections.get(rid)
        if tiles is None:
            fails.append(("CELL:missing", "declared cell %s has no section" % rid))
            continue
        want = declared_tiles(row)
        if len(tiles) != want:
            fails.append(("CELL:tiles", "%s declares %d capture(s), the page shows %d" % (rid, want, len(tiles))))
        hashes = []
        want_files = declared_captures(row, c["root"])
        for t in tiles:
            h = content_hash(page, t["src"]) if t["src"] else None
            hashes.append(h)
            if t["tile"] not in want_files:
                fails.append(("CELL:content", "%s shows tile %r, which the row does not declare" % (rid, t["tile"])))
            elif h is not None and h != file_hash(want_files[t["tile"]]):
                fails.append(("CELL:content", "%s tile %r shows %r, not the capture the row declares (%s)"
                              % (rid, t["tile"], t["src"], want_files[t["tile"]])))
            if h is None:
                fails.append(("CELL:image", "%s tile %r has no image file (or an empty one) at %r" % (rid, t["tile"], t["src"])))
            if t["img_hidden"]:
                fails.append(("CELL:image-hidden", "%s tile %r: the image is hidden or has no size" % (rid, t["tile"])))
            if t["hidden"] or not t["caption"].strip():
                fails.append(("CELL:caption", "%s tile %r has no visible caption" % (rid, t["tile"])))
        # A tile shown twice with another missing passes the count and membership checks above.
        for name in sorted(set(want_files) - {t["tile"] for t in tiles}):
            fails.append(("CELL:content", "%s is missing tile %r" % (rid, name)))
        if row.get("kind") in ("alternatives", "states"):
            known = [h for h in hashes if h]
            if len(set(known)) != len(known):
                fails.append(("CELL:distinct", "%s shows the same image content in %d tiles" % (rid, len(known) - len(set(known)) + 1)))
        else:
            for t, h in zip(tiles, hashes):
                if t["tile"] == "after" and h:
                    after_of.setdefault((c["gallery"], h), []).append(rid)
    for (gal, _), ids in sorted(after_of.items()):
        if len(ids) > 1:
            fails.append(("CELL:duplicate-after", "%s: rows %s share one after capture" % (gal, ", ".join(ids))))
    for rid, tiles in sections.items():
        if tiles and rid not in all_ids:
            fails.append(("CELL:undeclared", "section %s shows %d tile(s) but no row declares it" % (rid, len(tiles))))
    return fails


def probe(pages):
    """{page basename: {invariant id: [every message]}} for pages with a violation, or None when the
    probe gave no verdict (a page it could not judge is never a pass)."""
    if not pages:
        return {}
    try:
        r = subprocess.run(["bash", PROBE, "--invariants"] + pages, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=PROBE_TIMEOUT)
    except subprocess.TimeoutExpired:
        print("galleries-gate: probe past %ds on %d page(s)" % (PROBE_TIMEOUT, len(pages)), file=sys.stderr)
        return None
    summary = re.search(r"^INVARIANTS pages=(\d+) violations=(\d+)$", r.stdout, re.M)
    if r.returncode not in (0, 1) or not summary or int(summary.group(1)) != len(pages):
        print("galleries-gate: probe gave no verdict on %d page(s) (rc=%d): %s"
              % (len(pages), r.returncode, r.stderr.strip() or r.stdout.strip()[-200:]), file=sys.stderr)
        return None
    fired, lines = {}, 0
    for ln in r.stdout.splitlines():
        m = re.match(r"^INV (\S+) (\S+) (.*)$", ln)
        if m:
            lines += 1
            fired.setdefault(m.group(2), {}).setdefault(m.group(1), []).append(m.group(3))
    n = int(summary.group(2))
    given = {os.path.basename(p) for p in pages}
    if lines != n or not set(fired) <= given or (r.returncode == 0) != (n == 0):
        print("galleries-gate: probe output is inconsistent; no verdict", file=sys.stderr)
        return None
    return fired


def measure(units):
    """[(unit, fails, migrated)]: every unit's failures, empty = pass. A manifest unit whose original is
    refused is measured from its migrated copy when there is one; a migrated copy beside an original
    that builds is reported `stale migration` and ignored."""
    root = tempfile.mkdtemp(prefix="galleries-gate-")
    try:
        jobs = [u for u in units] + [u["alt"] for u in units if u.get("alt")]
        with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
            built = dict(zip(map(id, jobs), pool.map(lambda it: build_unit(root, *it), enumerate(jobs))))
        chosen = []
        for u in units:
            b = built[id(u)]
            if u.get("alt"):
                if b["kind"] == "built":
                    print("galleries-gate: stale migration: %s builds as it is, migrated copy ignored" % u["tag"], file=sys.stderr)
                elif b["kind"] == "refused":
                    want = u.get("alt_expect")
                    if want and want in b["out"]:
                        b = built[id(u["alt"])]
                        b["unit"] = dict(u["alt"], tag=u["tag"])
                    else:
                        b["fails"].append(("BUILD:new-refusal", "refused for a reason the migration does not cover "
                                           "(expected %r): %s" % (want, said_of(b["out"]))))
            chosen.append(b)
        for b in chosen:
            if b["page"]:
                u = b["unit"]
                text = u["spec"] if u["spec"] is not None else open(os.path.join(b["dir"], "p.spec.md"), encoding="utf-8").read()
                b["fails"] += check_page(b["page"], declared_cells(text, b["dir"]))
        pages = [b["page"] for b in chosen if b["page"]]
        fired = probe(pages) if pages else {}
        for b in chosen:
            if not b["page"]:
                continue
            if fired is None:
                b["fails"].append(("PROBE:no-verdict", "the probe gave no verdict"))
            else:
                for i, msgs in fired.get(os.path.basename(b["page"]), {}).items():
                    b["fails"] += [("INV:" + i, m) for m in msgs]
        return [(b["unit"], b["fails"], bool(b["unit"].get("migrated"))) for b in chosen]
    finally:
        shutil.rmtree(root, ignore_errors=True)


PINNED = MANIFEST_PIN + GENERATED_PIN
# Y is pinned in both halves: a generated case dropped from the table must not read as green.
if len(generated_cases()) != GENERATED_PIN:
    raise SystemExit("galleries_gate: %d generated cases, GENERATED_PIN is %d" % (len(generated_cases()), GENERATED_PIN))


def census(mdir, verbose):
    """stderr only: gallery specs on disk the manifest does not hold. Never a failure."""
    held = set()
    for u in manifest_units(mdir):
        held.add(u["source"])
    extra = [p for _, p in on_disk_specs(PROJECTS) if p not in held]
    print("galleries-gate: %d gallery spec(s) on disk not in the manifest" % len(extra), file=sys.stderr)
    if verbose:
        for p in extra:
            print("  not in the manifest: " + p, file=sys.stderr)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--expected", action="store_true")
    ap.add_argument("--only", default="")
    a = ap.parse_args(argv)
    if a.expected:
        print(PINNED)
        return 0
    mdir = manifest_dir()
    results = measure(make_units(mdir, a.only))
    y = len(results)
    x = sum(1 for _, f, _ in results if not f)
    migrated = sum(1 for _, _, m in results if m)
    disk = sum(1 for u, _, _ in results if u["tag"].startswith("disk:"))
    print("galleries-gate: %d unit(s): %d from the manifest (pinned %d), %d generated; %d failing"
          % (y, disk, MANIFEST_PIN, y - disk, y - x), file=sys.stderr)
    census(mdir, a.verbose)
    if a.verbose:
        classes = {}
        for u, fails, m in results:
            for code, detail in fails:
                classes.setdefault(code, []).append((u, detail))
            if fails:
                print("  FAIL %s%s\n        source: %s\n        replay: %s" % (u["tag"], " (migrated copy)" if m else "", u["source"], u["replay"]), file=sys.stderr)
                for code, detail in fails:
                    print("        %s: %s" % (code, detail), file=sys.stderr)
        print("CLASSES (one line per failure code, smallest example first):", file=sys.stderr)
        for code, hits in sorted(classes.items(), key=lambda kv: (-len({h[0]["tag"] for h in kv[1]}), kv[0])):
            u, detail = min(hits, key=lambda h: len(h[0]["tag"]))
            print("  %3d units  %-22s e.g. %s: %s" % (len({h[0]["tag"] for h in hits}), code, u["tag"], detail), file=sys.stderr)
    line = "galleries: %d/%d" % (x, y)
    if migrated:
        line += " (%d migrated)" % migrated
    if y != PINNED:
        line += " (pin %d)" % PINNED
    print(line)
    return 0 if x == y and y == PINNED else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
