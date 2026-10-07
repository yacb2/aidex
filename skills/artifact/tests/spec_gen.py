#!/usr/bin/env python3
"""spec_gen.py — a seeded spec generator and a shrinker for the LOOP-008 generated gate.

    generate(seed) -> spec text     the same seed gives the same bytes in any process
    shrink(spec, still_fails)       a smaller spec that still fails (greedy, balanced blocks
                                    first, then runs of lines); `shrinker(spec)` is the same
                                    search as a generator so a driver can batch the probes

Stdlib only. Borrowed from Hypothesis: a fixed seed reproduces any failure, and a failing
spec is shrunk to a smallest one that still fails.

About two thirds of the specs are valid by construction (references/03-spec-grammar.md, the
generator notes of the loop's grammar table): one masthead first, ASCII ids unique
case-insensitively, every group holds an item, every item has two or more flush-left
options and a question ending in `?`, exactly one `notes` last. The rest carry ONE edge shape
(see EDGES), so a failure is attributable to it. Edge shapes may be refused by the builder:
a loud refusal is as good as a valid page for the gate.

Every seed has a FOCUS kind (seed modulo the kind list), so coverage of every block kind is
by construction, not by luck. `ASSETS` are the files a spec's `figure`/`video` blocks name;
the gate writes them next to each spec. There is no sets or dict-ordering dependence on
hash seeds: only `random.Random(seed)` over lists.
"""
import base64
import random
import struct
import zlib

# Every block type the builder has an emitter for (spec_build.py `@emitter`); a test compares
# this tuple with the builder's own registry so a new block cannot go unmodelled.
KINDS = ("callout", "chart", "diagram", "figure", "gallery", "graph", "group", "item",
         "ledger", "masthead", "note", "notes", "prose", "section", "verdict", "video")
# Kinds the generator only produces in a form the builder refuses, and why.
REFUSAL_MESSAGE = {"gallery": "`gallery` rows="}      # what the refusal of each REFUSAL_ONLY kind says
REFUSAL_ONLY = {"gallery": "a gallery needs a rows JSON of real captures inside a git checkout; "
                           "it is emitted with a rows file that does not exist, so only the "
                           "SystemExit-to-refusal path is exercised"}
EDGES = ("backticks", "bom", "case_dup_id", "crlf", "dup_id", "empty_section", "forty",
         "huge_number", "item_flags", "long_token", "md_markers", "nested_group",
         "nested_note", "no_masthead", "no_notes", "notes_not_last", "one_option",
         "two_mastheads", "unicode", "zero_items")
EDGE_SHARE = 0.35
CONSULT_ONLY = ("item_flags", "nested_group", "no_notes", "notes_not_last", "one_option", "zero_items")
PRESENTATION_ONLY = ("empty_section",)


def _png(w=8, h=8):
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))
    raw = b"".join(b"\x00" + bytes([128, 128, 160]) * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


# A real 16x16, 0.2 s h264 clip (ffmpeg color source, 1.5 KB): a 0-byte file made the browser
# answer the range request with ERR_REQUEST_RANGE_NOT_SATISFIABLE, which RUN-3 counted as a
# page defect that the generator itself had caused.
_MP4 = base64.b64decode(
    "AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAMUbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAA"
    "AMgAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAgAAAj90cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAMgAAAAAAAAAAAAA"
    "AAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0"
    "AAAAAAAAAAEAAADIAAAAAAABAAAAAAG3bWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAoAAAACABVxAAAAAAALWhk"
    "bHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABYm1pbmYAAAAUdm1oZAAAAAEAAAAAAAAA"
    "AAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAASJzdGJsAAAAvnN0c2QAAAAAAAAAAQAAAK5h"
    "dmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABFExhdmM2My4xLjEwMiBsaWJ4MjY0"
    "AAAAAAAAAAAAAAAAGP//AAAANGF2Y0MBZAAK/+EAF2dkAAqs2V7ARAAAAwAEAAADACg8SJZYAQAGaOvjyyLA/fj4"
    "AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAAG5QAAAAAAAAABhzdHRzAAAAAAAAAAEAAAABAAAIAAAAABxz"
    "dHNjAAAAAAAAAAEAAAABAAAAAQAAAAEAAAAUc3RzegAAAAAAAALCAAAAAQAAABRzdGNvAAAAAAAAAAEAAANEAAAA"
    "YXVkdGEAAABZbWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAsaWxzdAAAACSpdG9v"
    "AAAAHGRhdGEAAAABAAAAAExhdmY2My4xLjEwMgAAAAhmcmVlAAACym1kYXQAAAKtBgX//6ncRem95tlIt5Ys2CDZ"
    "I+7veDI2NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxl"
    "ZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9"
    "MSByZWY9MyBkZWJsb2NrPTE6MDowIGFuYWx5c2U9MHgzOjB4MTEzIG1lPWhleCBzdWJtZT03IHBzeT0xIHBzeV9y"
    "ZD0xLjAwOjAuMDAgbWl4ZWRfcmVmPTEgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0xIDh4OGRjdD0x"
    "IGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0PS0yIHRocmVhZHM9MSBs"
    "b29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBi"
    "bHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTMgYl9weXJhbWlkPTIgYl9hZGFwdD0x"
    "IGJfYmlhcz0wIGRpcmVjdD0xIHdlaWdodGI9MSBvcGVuX2dvcD0wIHdlaWdodHA9MiBrZXlpbnQ9MjUwIGtleWlu"
    "dF9taW49NSBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAgcmNfbG9va2FoZWFkPTQwIHJjPWNyZiBtYnRyZWU9"
    "MSBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40MCBhcT0x"
    "OjEuMDAAgAAAAA1liIQAP//+92ifAjOZ")

ASSETS = {
    "fig.svg": ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40" width="120" '
                'height="40"><rect x="2" y="2" width="116" height="36" fill="none" '
                'stroke="currentColor"/><text x="12" y="25" font-size="12" '
                'fill="currentColor">Figure</text></svg>\n').encode("utf-8"),
    "fig.png": _png(),
    "poster.png": _png(),
    "clip.mp4": _MP4,
}

WORDS = {
    "es": "cuenta pago envío revisión equipo plan riesgo cambio lista tarea página informe "
          "cliente flujo dato regla prueba costo acceso".split(),
    "en": "account payment shipping review team plan risk change list task page report "
          "client flow data rule test cost access".split(),
}
LONG = "supercalifragilisticoespialidoso" * 8          # 256 chars, no space
UNI = ["ñandú", "café", "日本語", "naïve", "Ünïcödé", "🙂", "—", "“quoted”"]
MD = ["**bold", "a * b * c", "_x_y_z_", "[not a link]", "[t](u)", "# hash", "1. one", "> q",
      "{#x}", "{recommended}", "<b>tag</b>", "~~s~~", "* star"]
TONES = ("high", "info", "warn")


def _q(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def _fence(kind, ident=None, attrs=(), body=()):
    """The lines of one `:::` block. attrs: (key, value) pairs, values quoted unless bare."""
    parts = []
    if ident:
        parts.append("#" + ident)
    for k, v in attrs:
        parts.append("%s=%s" % (k, v if v.startswith('"') or v.isalnum() else _q(v)))
    head = "::: " + kind + (" {" + " ".join(parts) + "}" if parts else "")
    return [head] + list(body) + [":::"]


class _Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.seed = seed
        self.lang = "en" if self.r.random() < 0.35 else "es"
        self.focus = KINDS[seed % len(KINDS)]
        self.edge = None
        self.n = {"Q": 0, "G": 0, "S": 0, "F": 0}
        self.ids = []
        self.edge_used = False

    # ---- text -------------------------------------------------------------------------
    def w(self, n):
        return " ".join(self.r.choice(WORDS[self.lang]) for _ in range(n))

    def title(self):
        t = self.w(self.r.randint(1, 3)).capitalize()
        if self.edge == "unicode" and self.r.random() < 0.5:
            t += " " + self.r.choice(UNI)
        if self.edge == "long_token" and self.r.random() < 0.4:
            t += " " + LONG
        return t

    def question(self):
        s = self.w(self.r.randint(3, 7)).capitalize()
        return ("¿%s?" % s) if self.lang == "es" else ("%s?" % s)

    def inline(self, codes):
        c = self.r.random()
        if c < 0.55:
            return self.w(self.r.randint(1, 3)), codes
        if c < 0.67:
            return "**%s**" % self.w(1), codes
        if c < 0.77:
            return "_%s_" % self.w(1), codes
        if c < 0.87 and codes < 2:
            return "`%s_%s`" % (self.w(1), self.r.randint(1, 9)), codes + 1
        if c < 0.94:
            return "[%s](https://example.com/%s)" % (self.w(1), self.w(1)), codes
        return "[%s]{.pill .%s}" % (self.w(1), self.r.choice(TONES)), codes

    def para(self):
        out, codes = [], 0
        for _ in range(self.r.randint(2, 6)):
            s, codes = self.inline(codes)
            out.append(s)
        text = " ".join(out)
        if self.edge == "md_markers" and self.r.random() < 0.6:
            text += " " + self.r.choice(MD)
        if self.edge == "backticks" and self.r.random() < 0.6:
            text += " " + self.r.choice(["`a` `b` `c` `d` `e`", "an `unclosed tick", "``double`` `x",
                                         "`" + LONG + "`"])
        if self.edge == "long_token" and self.r.random() < 0.5:
            text += " " + LONG
        if self.edge == "unicode" and self.r.random() < 0.5:
            text += " " + " ".join(self.r.choice(UNI) for _ in range(3))
        return text[0].upper() + text[1:] + "."

    def prose(self, n=None):
        lines = []
        for _ in range(n or self.r.randint(1, 2)):
            lines += [self.para(), ""]
        c = self.r.random()
        if c < 0.25:
            lines += ["- " + self.w(2) for _ in range(self.r.randint(1, 4))] + [""]
        elif c < 0.4:
            lines += ["%d. %s" % (i + 1, self.w(2)) for i in range(self.r.randint(1, 3))] + [""]
        elif c < 0.55:
            lines += ["| %s | %s |" % (self.w(1), self.w(1)), "|---|---|"]
            lines += ["| %s | %d |" % (self.w(1), self.r.randint(1, 99)) for _ in range(self.r.randint(1, 3))]
            lines += [""]
        elif c < 0.62:
            lines += ["```", "x = 1  # " + self.w(2), "```", ""]
        return lines

    def new_id(self, prefix):
        self.n[prefix] += 1
        i = "%s%d" % (prefix, self.n[prefix])
        self.ids.append(i)
        return i

    # ---- blocks -----------------------------------------------------------------------
    def ledger(self):
        n = 40 if self.edge == "forty" else self.r.choice([0, 1, 2, 3, 5])
        return _fence("ledger", body=["- %s — %s" % (self.w(1), self.w(3)) for _ in range(n)])

    def verdict(self):
        labels = [self.w(1).capitalize() + str(i) for i in range(self.r.randint(2, 4))]
        rows = ["| %dx | %s | %s |" % (i + 1, lab, self.w(2)) for i, lab in enumerate(labels)]
        body = ["| Fig | Label | Caption |", "|---|---|---|"] + rows
        attrs = [("win", labels[0])] if self.r.random() < 0.5 else []
        return _fence("verdict", attrs=attrs, body=body)

    def callout(self):
        return _fence("callout", body=self.prose(1)[:1])

    def note(self, depth=1):
        body = self.prose(1)
        if depth > 1:
            body += self.note(depth - 1)
        attrs = []
        return _fence("note", attrs=attrs, body=body)

    def chart(self):
        t = self.r.choice(["bar", "line", "stacked"])
        title = self.title()
        n = 40 if self.edge == "forty" else self.r.randint(1, 6)
        big = "9" * 400 if self.edge == "huge_number" else None
        if t == "stacked" or self.r.random() < 0.3:
            head = ["| Step"] + [" | %s%d" % (self.w(1).capitalize(), i) for i in range(self.r.randint(1, 3))]
            ncol = len(head) - 1
            lines = ["".join(head) + " |", "|---" * (ncol + 1) + "|"]
            for i in range(min(n, 8)):
                cells = [big if (big and i == 0 and j == 0) else str(self.r.randint(1, 90))
                         for j in range(ncol)]
                lines.append("| %s%d | %s |" % (self.w(1), i, " | ".join(cells)))
            body = lines
        else:
            body = ["%s%d,%s" % (self.w(1), i, big if (big and i == 0)
                                else "%d.%d" % (self.r.randint(1, 90), self.r.randint(0, 9)))
                    for i in range(n)]
        attrs = [("type", t), ("title", title)]
        if self.r.random() < 0.4 and t != "stacked":
            attrs.append(("labels", self.r.choice(["on", "off"])))
        return _fence("chart", self.new_id("F") if self.r.random() < 0.5 else None, attrs, body)

    def diagram(self):
        shape = self.r.choice(["row", "pipeline", "before-after", "cycle", "tree", "compare"])
        names = ["b%d" % i for i in range(self.r.randint(2, 5))]
        lab = lambda: self.w(self.r.randint(1, 2)).capitalize()  # noqa: E731
        box = lambda n: "%s: %s" % (n, lab())                    # noqa: E731
        if shape in ("row", "pipeline"):
            body = [box(n) for n in names] + ["%s -> %s" % (a, b) for a, b in zip(names, names[1:])]
        elif shape == "cycle":
            body = [box(n) for n in names] + ["%s -> %s" % (a, b)
                                              for a, b in zip(names, names[1:] + names[:1])]
        elif shape == "tree":
            body = [box(n) for n in names] + ["%s -> %s" % (names[0], n) for n in names[1:]]
        elif shape == "before-after":
            body = ["lane " + lab()] + [box("a1"), box("a2"), "a1 -> a2", "lane " + lab(), box("c1")]
        else:
            body = []
            for k, rec in (("A", True), ("B", False)):
                body += ["panel row Option " + k, box("x"), box("y"), "x -> y", "outcome " + self.w(4)]
                if rec:
                    body.append("recommended")
        attrs = [("shape", shape)]
        if self.r.random() < 0.7:
            attrs.append(("title", self.title()))
        return _fence("diagram", self.new_id("F") if self.r.random() < 0.4 else None, attrs, body)

    def graph(self):
        nodes = ["n%d" % i for i in range(self.r.randint(2, 5))]
        edges = "; ".join("%s -> %s" % (a, b) for a, b in zip(nodes, nodes[1:]))
        return _fence("graph", attrs=[("title", self.title())] if self.r.random() < 0.5 else [],
                      body=["digraph G { rankdir=LR; %s; }" % edges])

    def figure(self):
        if self.r.random() < 0.5:
            attrs = [("src", "fig.svg"), ("title", self.title())]
        else:
            attrs = [("src", "fig.png"), ("alt", self.w(3)), ("title", self.title())]
        out = _fence("figure", attrs=attrs)
        if self.r.random() < 0.3:                       # two adjacent figures render as a grid
            out += _fence("figure", attrs=[("src", "fig.svg")])
        return out

    def video(self):
        attrs = [("src", "clip.mp4"), ("title", self.title())]
        if self.r.random() < 0.5:
            attrs.append(("poster", "poster.png"))
        return _fence("video", attrs=attrs)

    def gallery(self):
        return _fence("gallery", self.new_id("G"), [("title", self.title()), ("rows", "missing-rows.json"), ("root", ".")])

    def free_block(self, kind):
        """One block that sits anywhere (section, group or item body)."""
        return {"callout": self.callout, "chart": self.chart, "diagram": self.diagram,
                "figure": self.figure, "graph": self.graph, "ledger": self.ledger,
                "note": self.note, "verdict": self.verdict, "video": self.video}[kind]()

    FREE = ("callout", "chart", "diagram", "figure", "graph", "ledger", "note", "verdict", "video")

    # what an `item` body may carry (spec_build `_segments`): no ledger, no verdict
    ITEM_FREE = ("callout", "chart", "diagram", "figure", "graph", "note", "video")

    def some_blocks(self, extra=None, pool=None):
        kinds = [self.r.choice(pool or self.FREE) for _ in range(self.r.randint(0, 2))]
        if extra:
            kinds.append(extra)
        out = []
        for k in kinds:
            out += [""] + self.free_block(k)
        return out

    # ---- consult items ----------------------------------------------------------------
    def options(self):
        n = self.r.choice([2, 2, 3, 4, 5])
        if self.edge == "forty":
            n = 40
        elif self.edge == "one_option":
            n = 1
        rec = self.r.randrange(n) if self.r.random() < 0.6 else -1
        out = []
        for i in range(n):
            label = "%s %d" % (self.w(self.r.randint(1, 2)).capitalize(), i)
            if self.edge == "unicode" and self.r.random() < 0.3:
                label += " " + self.r.choice(UNI)
            if self.edge == "long_token" and i == 0:
                label += " " + LONG
            line = "- " + label
            if i == rec:
                line += " {recommended}"
            if self.r.random() < 0.5:
                line += " — " + self.w(3)
            out.append(line)
        return out, rec

    def item(self, extra=None):
        ident = self.new_id("Q")
        attrs = [("title", self.title())]
        opts, rec = self.options()
        if self.r.random() < 0.3:
            attrs.append(("heading", self.question()))
        if self.edge == "item_flags":
            attrs.append(self.r.choice([("decided", "yes"), ("dropped", "out of scope"), ("free", "yes"),
                                        ("select", "many"), ("select", "two"), ("proposal", "yes"),
                                        ("decided", "0"), ("decided", '"Sí"')]))
        elif self.r.random() < 0.1:
            attrs.append(("select", "many"))
        body = [self.question(), ""]
        if self.r.random() < 0.3:
            body += [self.para(), ""]
        body += opts
        body += self.some_blocks(extra, self.ITEM_FREE)
        return _fence("item", ident, attrs, body)

    def group(self, extra=None):
        ident = self.new_id("G")
        attrs = [("title", self.title())]
        if self.r.random() < 0.4:
            attrs.append(("heading", self.title()))
        body = []
        if self.r.random() < 0.3:
            body += self.prose(1)
        n_items = 0 if self.edge == "zero_items" else self.r.randint(1, 3)
        for i in range(n_items):
            body += self.item(extra if i == 0 and extra in self.ITEM_FREE else None) + [""]
        if extra and (n_items == 0 or extra not in self.ITEM_FREE):
            body += self.free_block(extra)
        if self.edge == "nested_group" and not self.edge_used:
            self.edge_used = True
            body += self.group()
        if self.edge == "nested_note":
            body += self.note(self.r.randint(3, 6))
        return _fence("group", ident, attrs, body)

    def section(self, extra=None):
        ident = self.new_id("S")
        attrs = [("heading", self.title())]
        if self.r.random() < 0.3:
            attrs.append(("eyebrow", self.w(1)))
        body = [] if self.edge == "empty_section" else self.prose()
        body += self.some_blocks(extra)
        if self.edge == "nested_note":
            body += self.note(self.r.randint(3, 6))
        return _fence("section", ident, attrs, body)

    def masthead(self, consult):
        title = self.title()
        attrs, body = [], []
        if self.r.random() < 0.5:
            attrs.append(("title", title))
        else:
            body.append("# " + title)
        if self.lang == "en":
            attrs.append(("lang", "en"))
        if self.r.random() < 0.3:
            attrs.append(("eyebrow", self.w(2)))
        if self.r.random() < 0.3:
            attrs.append(("byline", "aidex"))
        if consult:
            attrs.append(("visual", "none: " + self.w(2)))
        body += ["", self.para()] if self.r.random() < 0.8 else []
        return _fence("masthead", attrs=attrs, body=body)

    # ---- the page ---------------------------------------------------------------------
    def spec(self):
        f = self.focus
        # a `section` between groups and notes is refused by consult-shape, so a section focus
        # is a presentation page; item/notes/group/gallery need a consultation page
        consult = f in ("item", "notes", "group", "gallery") or (f != "section" and self.r.random() < 0.5)
        # a refusal-only seed carries no edge shape: its refusal would mask the edge
        if f not in REFUSAL_ONLY and self.r.random() < EDGE_SHARE:           # an edge that has a site on this page kind
            self.edge = self.r.choice([e for e in EDGES if e not in (PRESENTATION_ONLY if consult else CONSULT_ONLY)])
        out = []
        if self.edge != "no_masthead":
            out += self.masthead(consult) + [""]
            if self.edge == "two_mastheads":
                out += self.masthead(consult) + [""]
        extra = f if f in self.FREE else ("chart" if self.edge == "huge_number" else None)
        if consult:
            for i in range(self.r.randint(1, 3)):
                out += self.group(extra if i == 0 else None) + [""]
            if f == "gallery":
                out += self.gallery() + [""]
            if self.edge != "no_notes":
                notes = _fence("notes", "notes" if self.r.random() < 0.7 else None, [("title", self.title())])
                if self.edge == "notes_not_last":
                    out += notes + [""] + self.group() + [""]
                else:
                    out += notes + [""]
        else:
            for i in range(self.r.randint(1, 3)):
                out += self.section(extra if i == 0 else None) + [""]
        if f == "prose" and not consult:
            out += self.prose(1)
        if self.edge in ("dup_id", "case_dup_id") and len(self.ids) >= 2:
            first, last = self.ids[0], self.ids[-1]
            dup = first if self.edge == "dup_id" else first.lower() if first != first.lower() else first.upper()
            out = [ln.replace("#" + last, "#" + dup, 1) if ln.startswith("::: ") and "#" + last in ln else ln
                   for ln in out]
        text = "\n".join(out).rstrip("\n") + "\n"
        if self.edge == "crlf":
            text = text.replace("\n", "\r\n")
        if self.edge == "bom":
            text = "\ufeff" + text
        return text


def generate(seed):
    return _Gen(seed).spec()


def intent(seed):
    """What the builder owes this seed: "valid" (it must build; a refusal is a defect),
    "edge" (one edge shape; a loud refusal is as good as a page) or "refusal-only" (a kind
    only emitted in a form the builder must refuse with REFUSAL_MESSAGE)."""
    g = _Gen(seed)
    g.spec()
    if g.focus in REFUSAL_ONLY:
        return "refusal-only"
    return "edge" if g.edge else "valid"


# ---- shrinking --------------------------------------------------------------------------

def _is_open(line):
    return line.startswith(":::") and line[3:].lstrip(":").strip() != "" and line.lstrip(":")[:1] == " "


def _is_close(line):
    return line.startswith(":::") and line.strip(":").strip() == ""


def _block_ranges(lines):
    """(start, end) inclusive of every balanced block, by open/close nesting."""
    stack, out = [], []
    fence = False
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith(("```", "~~~")):
            fence = not fence
        if fence:
            continue
        if _is_close(ln.rstrip("\r")):
            if stack:
                out.append((stack.pop(), i))
        elif _is_open(ln):
            stack.append(i)
    return sorted(out, key=lambda p: p[0] - p[1])          # biggest first


def _candidates(spec):
    lines = spec.split("\n")
    seen, out = {spec}, []

    def add(drop):
        keep = [ln for i, ln in enumerate(lines) if i not in drop]
        text = "\n".join(keep)
        if text not in seen and text.strip():
            seen.add(text)
            out.append(text)
    for a, b in _block_ranges(lines):
        add(set(range(a, b + 1)))
    n = len(lines)
    size = max(n // 2, 1)
    while True:
        for start in range(0, n, size):
            add(set(range(start, min(start + size, n))))
        if size == 1:
            break
        size = max(size // 2, 1)
    return out


def shrinker(spec, batch=8):
    """The shrink search as a generator. It yields a LIST of candidate specs, is sent the
    list of booleans (does each still fail), and returns the smallest spec it reached
    (StopIteration.value). A driver can evaluate one batch with a single browser run."""
    cur = spec
    while True:
        cands = _candidates(cur)
        start, moved = 0, False
        while start < len(cands):
            chunk = cands[start:start + batch]
            verdicts = yield chunk
            hit = next((c for c, v in zip(chunk, verdicts) if v), None)
            if hit is not None:
                cur, moved = hit, True
                break
            start += batch
        if not moved:
            return cur


def shrink(spec, still_fails):
    """A smaller spec than `spec` that `still_fails` accepts, by greedy removal. The caller
    checked that `spec` itself fails."""
    gen = shrinker(spec, batch=1)
    try:
        chunk = next(gen)
        while True:
            chunk = gen.send([still_fails(c) for c in chunk])
    except StopIteration as done:
        return done.value


if __name__ == "__main__":
    import sys
    sys.stdout.write(generate(int(sys.argv[1]) if len(sys.argv) > 1 else 1))
