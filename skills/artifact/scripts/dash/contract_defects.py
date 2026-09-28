#!/usr/bin/env python3
"""Page-contract consistency checks: one function per frozen defect class
(LOOP-006, `.context/loops/2026-09-27-artifact-contract-defects-STATE.md` in the
workspace). Each takes (path, html_text) and returns [(slug, line, message)].

    python3 contract_defects.py [--class SLUG] PAGE...     # exit 1 on any finding

Classes and the exact rule each one enforces:

decision-item-without-options
    The single owner of the item rule (check_artifact's BL-468 `consult-free`
    warning is replaced by a call here in Phase C). An element with class
    `consult-item` and a `data-id` must offer at least OPTIONS_MIN options: that
    many radio/checkbox inputs, or a <select> with that many <option>s, counted
    on the item's OWN subtree (a nested consult item's options answer the nested
    item). Exempt: the general-notes item (`consult-notes`), a settled item
    (`data-decided`, the exact attribute; `data-decided-round` alone is not one)
    and an OPEN ANSWER marked `data-free` whose value is not "no"/"false" — the
    marker the spec route already writes for `free=yes` (spec_build.py). Also
    fails on a literal `{recommended}` in any attribute value (data-label is
    what the composer copies) or in visible text outside <code>/<pre> (inside
    code it is a page talking ABOUT the marker).

decision-page-not-interactive
    An <h1>-<h4> whose text names a pending decision — a DECISION_PHRASES entry
    matched whole at word boundaries, accent- and case-insensitively, with no
    NEGATION word among the three words before it ("nada por decidir", "no
    pending decisions" pass) — or that starts with the imperative
    "Decide"/"Decidir", must be followed, before the next heading of the same or
    higher level, by a `.consult-item` other than the notes item. A heading
    inside a consult item passes. Any other `data-id` (a table row) is not one.

mixed-content-types
    (a) a <p> (not `.fieldlabel`) with FACTS_MIN or more <code> tokens or
    semicolon-separated clauses (a `;` inside <code> does not count) —
    check_artifact's consult-facts warning rule, same threshold, applied to every
    paragraph of the page instead of only those inside consult items; (b) a
    <pre>, or a <code> outside <pre>, holding PROSE_SENTENCES or more prose
    sentences; (c) a <p> containing a run of PATH_RUN or more file paths joined
    by `,`/`;`/and/y/e (a list written as a sentence). Not paths: dd/mm and
    dd/mm/yyyy dates and `<area>/BL-nnn` backlog references.

copy-control-placement
    On a page with at least one `consult-item`: exactly one `#consult-copy`,
    inside `.consult-bar` inside `aside.rail`; exactly one `#consult-copy-end`,
    inside <main>; neither inside an element carrying `hidden` or an inline
    `display: none` (itself included). A page with no consult item needs
    neither. Source-level: the rendered box is render-probe's.

ui-string-language
    The static text of the kit's chrome (`#consult-copy`, `#consult-copy-end`,
    `.railhead`, `.fieldlabel`, `.consult-status`, textarea placeholders) must
    not be a kit string of the OTHER language than `<html lang>` (es/en only).
    Pages with no lang or another lang are skipped; the label is the element's
    own text (child counters dropped), whitespace collapsed. Judged on the
    source: the composer relabels exact English defaults at run
    time, so a JS-less read, a copy of the source, or an older composer shows
    what this reads.
"""

import argparse
import re
import sys
import unicodedata
from html.parser import HTMLParser

# --- a small tree ------------------------------------------------------------

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr"}
# A block start closes an open <p>: pages with an unclosed <p> must not nest the
# rest of the document under it.
P_CLOSERS = {"address", "article", "aside", "blockquote", "div", "dl",
             "fieldset", "figure", "footer", "form", "h1", "h2", "h3", "h4",
             "h5", "h6", "header", "hr", "main", "nav", "ol", "p", "pre",
             "section", "table", "ul"}
RAW = {"script", "style"}


class Node:
    __slots__ = ("tag", "attrs", "line", "parent", "children")

    def __init__(self, tag, attrs, line, parent):
        self.tag, self.attrs, self.line, self.parent = tag, attrs, line, parent
        self.children = []

    def classes(self):
        return set((self.attrs.get("class") or "").split())

    def ancestors(self):
        n = self.parent
        while n is not None:
            yield n
            n = n.parent

    def walk(self):
        for c in self.children:
            if isinstance(c, Node):
                yield c
                yield from c.walk()

    def text(self):
        out = []
        for c in self.children:
            if isinstance(c, Node):
                if c.tag not in RAW:
                    out.append(c.text())
            else:
                out.append(c[1])
        return "".join(out)


class _Builder(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root", {}, 1, None)
        self.stack = [self.root]
        self.texts = []                     # (line, text, parent node)

    def _open(self, tag, attrs, push):
        if tag in P_CLOSERS and self.stack[-1].tag == "p":
            self.stack.pop()
        if tag == "li" and self.stack[-1].tag == "li":
            self.stack.pop()
        node = Node(tag, {k: (v if v is not None else "") for k, v in attrs},
                    self.getpos()[0], self.stack[-1])
        self.stack[-1].children.append(node)
        if push and tag not in VOID:
            self.stack.append(node)

    def handle_starttag(self, tag, attrs):
        self._open(tag, attrs, True)

    def handle_startendtag(self, tag, attrs):
        self._open(tag, attrs, False)

    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]
                return

    def handle_data(self, data):
        top = self.stack[-1]
        top.children.append((self.getpos()[0], data))
        if top.tag not in RAW:
            self.texts.append((self.getpos()[0], data, top))


def parse(html_text):
    b = _Builder()
    b.feed(html_text)
    b.close()
    return b


def _norm(s):
    return " ".join(s.split())


def _is_item(n):
    """A consult item that asks something: not a block, not the notes box."""
    c = n.classes()
    return ("consult-item" in c and "consult-notes" not in c
            and "consult-group" not in c)


# --- 1. decision-item-without-options ------------------------------------------

OPTION_INPUT = ("radio", "checkbox")
RECOMMENDED = "{recommended}"


OPTIONS_MIN = 2          # one option is not a choice
FREE_OFF = ("no", "false")


def _own_walk(item):
    """The item's descendants, minus any nested consult item's subtree: a
    nested item's options answer the nested item, never the outer one."""
    for c in item.children:
        if isinstance(c, Node):
            if "consult-item" in c.classes():
                continue
            yield c
            yield from _own_walk(c)


def option_count(item):
    """Radio/checkbox inputs, or the largest <select>'s <option> count."""
    inputs, select = 0, 0
    for d in _own_walk(item):
        if d.tag == "input" and (d.attrs.get("type") or "").lower() in OPTION_INPUT:
            inputs += 1
        elif d.tag == "select":
            select = max(select, sum(1 for o in d.walk() if o.tag == "option"))
    return max(inputs, select)


def check_decision_item_without_options(path, html_text):
    b, out, slug = parse(html_text), [], "decision-item-without-options"
    for n in b.root.walk():
        if not (_is_item(n) and "data-id" in n.attrs):
            continue
        free = n.attrs.get("data-free")
        if "data-decided" in n.attrs or (
                free is not None and free.strip().lower() not in FREE_OFF):
            continue
        k = option_count(n)
        if k < OPTIONS_MIN:
            out.append((slug, n.line,
                        "item '%s' offers %d option(s): a decision needs at least "
                        "%d (radio, checkbox or select). Give it its options, or "
                        "mark it an open answer with data-free (free=yes in a spec)"
                        % (n.attrs["data-id"], k, OPTIONS_MIN)))
    for n in b.root.walk():
        for name, val in n.attrs.items():
            if RECOMMENDED in (val or ""):
                out.append((slug, n.line, "literal %s in the %s attribute: the "
                            "builder did not read the marker" % (RECOMMENDED, name)))
    for line, text, parent in b.texts:
        if RECOMMENDED not in text:
            continue
        if parent.tag in ("code", "pre") or any(
                a.tag in ("code", "pre") for a in parent.ancestors()):
            continue
        out.append((slug, line, "literal %s shows as page text: the builder did "
                    "not read the marker, so the option carries no "
                    "data-recommended" % RECOMMENDED))
    return out


# --- 2. decision-page-not-interactive ------------------------------------------

# Matched accent- and case-insensitively on the heading's text. Kept explicit and
# small: every entry is a way a heading SAYS the reader must decide something.
DECISION_PHRASES = (
    "necesita decision", "necesitan decision", "decisiones pendientes",
    "decision pendiente", "pendiente de decision", "por decidir",
    "needs a decision", "need a decision", "needs decision",
    "pending decisions", "pending decision", "to decide",
)
PHRASE = re.compile(r"\b(?:%s)\b" % "|".join(
    re.escape(p).replace(r"\ ", r"\s+") for p in DECISION_PHRASES))
IMPERATIVE = re.compile(r"^(decide|decidir)\b")
# A negation word within the three words before the phrase: "nada por decidir",
# "nothing (left) to decide", "sin decisiones pendientes", "no pending decisions".
NEGATION = {"nada", "nothing", "sin", "no", "ninguna", "ninguno", "none", "zero"}
HEADING = re.compile(r"^h([1-6])$")
HEADINGS_READ = ("h1", "h2", "h3", "h4")


def _fold(s):
    s = unicodedata.normalize("NFKD", s)
    return "".join(ch for ch in s if not unicodedata.combining(ch)).lower()


def decision_heading(text):
    t = _norm(_fold(text))
    if IMPERATIVE.match(t):
        return True
    for m in PHRASE.finditer(t):
        before = re.findall(r"\w+", t[:m.start()])[-3:]
        if not NEGATION.intersection(before):
            return True
    return False


def check_decision_page_not_interactive(path, html_text):
    b, out = parse(html_text), []
    order = list(b.root.walk())
    for i, n in enumerate(order):
        if n.tag not in HEADINGS_READ or not decision_heading(n.text()):
            continue
        if any(_is_item(a) for a in n.ancestors()):
            continue
        level, found = int(n.tag[1]), False
        for m in order[i + 1:]:
            h = HEADING.match(m.tag)
            if h and int(h.group(1)) <= level:
                break
            if _is_item(m):
                found = True
                break
        if not found:
            out.append(("decision-page-not-interactive", n.line,
                        "heading \"%s\" asks for a decision and its section has "
                        "no consult item to answer it with" % _norm(n.text())[:70]))
    return out


# --- 3. mixed-content-types -----------------------------------------------------

FACTS_MIN = 4           # check_artifact.FACTS_MIN (consult-facts warning, BL-270)
PROSE_SENTENCES = 3
PATH_RUN = 3
# A prose sentence: starts with a capital (or ¿/¡), runs at least four words of
# letters, ends with . ! or ? before whitespace or the end.
SENTENCE = re.compile(r"[¿¡]?[A-ZÁÉÍÓÚÑ][a-záéíóúñü]*(?:[ ,][^\s.!?]+){3,}?"
                      r"[^.!?\n]*[.!?](?=\s|$)")
WORD = re.compile(r"^[A-Za-zÁÉÍÓÚÑáéíóúñü¿¡,'’()-]+$")
PATH = (r"(?:~?[\w.@-]*(?:/[\w.@-]+)+/?|[\w-]+\.(?:py|sh|md|html|js|mjs|json|"
        r"jsonl|css|ts|tsx|yml|yaml|toml|txt|tsv|csv))(?::\d+(?:-\d+)?)?")
PATH_TOKEN = re.compile(PATH)
# "a, b and c" / "a, b y c": the last separator may be a conjunction alone.
PATH_SEP = re.compile(r"^(?:\s*[,;]\s*(?:(?:and|y|e)\s+)?|\s+(?:and|y|e)\s+)$")
# Not paths although they carry a slash: dd/mm and dd/mm/yyyy dates, and
# `<area>/BL-nnn` backlog references (corpus false positives, 2026-09-27).
NOT_PATH = re.compile(r"^\d{1,2}/\d{1,2}(?:/\d{2,4})?$|(?:^|/)BL-\d+$")


def path_run(text):
    """The first run of PATH_RUN+ path tokens joined only by list separators,
    or ""."""
    toks = [m for m in PATH_TOKEN.finditer(text) if not NOT_PATH.search(m.group(0))]
    run = []
    for m in toks:
        if run and PATH_SEP.match(text[run[-1].end():m.start()]):
            run.append(m)
        else:
            run = [m]
        if len(run) >= PATH_RUN:
            return text[run[0].start():run[-1].end()]
    return ""


def text_outside_code(node):
    out = []
    for c in node.children:
        if isinstance(c, Node):
            if c.tag not in RAW and c.tag != "code":
                out.append(text_outside_code(c))
        else:
            out.append(c[1])
    return "".join(out)


def prose_sentences(text):
    n = 0
    for m in SENTENCE.finditer(text):
        words = m.group(0).split()
        if len(words) >= 4 and sum(1 for w in words if WORD.match(w.rstrip(".!?:;"))) >= 4:
            n += 1
    return n


def check_mixed_content_types(path, html_text):
    b, out, slug = parse(html_text), [], "mixed-content-types"
    for n in b.root.walk():
        if n.tag == "p" and "fieldlabel" not in n.classes():
            codes = sum(1 for d in n.walk() if d.tag == "code")
            prose = n.text()
            bare = text_outside_code(n)          # a `;` inside <code> is code
            clauses = bare.count(";") + 1 if ";" in bare else 1
            if codes >= FACTS_MIN or clauses >= FACTS_MIN:
                shape = ("%d <code> tokens" % codes if codes >= FACTS_MIN
                         else "%d semicolon-separated clauses" % clauses)
                out.append((slug, n.line, "paragraph with %s (\"%s…\"): facts of "
                            "one shape are a list or a table"
                            % (shape, _norm(prose)[:50])))
            run = path_run(prose)
            if run:
                out.append((slug, n.line, "paragraph lists file paths in a "
                            "sentence (\"%s\"): write them as a list"
                            % _norm(run)[:60]))
        elif n.tag == "pre" or (n.tag == "code" and not any(
                a.tag == "pre" for a in n.ancestors())):
            k = prose_sentences(n.text())
            if k >= PROSE_SENTENCES:
                out.append((slug, n.line, "<%s> holds %d prose sentences: prose "
                            "belongs in a paragraph, not a code block" % (n.tag, k)))
    return out


# --- 4. copy-control-placement --------------------------------------------------

def check_copy_control_placement(path, html_text):
    b, out, slug = parse(html_text), [], "copy-control-placement"
    nodes = list(b.root.walk())
    if not any("consult-item" in n.classes() for n in nodes):
        return out
    rail = [n for n in nodes if n.attrs.get("id") == "consult-copy"]
    end = [n for n in nodes if n.attrs.get("id") == "consult-copy-end"]
    for ident, found in (("consult-copy", rail), ("consult-copy-end", end)):
        if len(found) != 1:
            out.append((slug, found[1].line if len(found) > 1 else 1,
                        "a consultation carries exactly one #%s; this page has %d"
                        % (ident, len(found))))
    for n in rail:
        anc = list(n.ancestors())
        ok = any("consult-bar" in a.classes() and any(
            r.tag == "aside" and "rail" in r.classes() for r in a.ancestors())
            for a in anc)
        if not ok:
            out.append((slug, n.line, "#consult-copy sits outside aside.rail "
                        "> .consult-bar, so the rail has no copy control"))
    for n in end:
        if not any(a.tag == "main" for a in n.ancestors()):
            out.append((slug, n.line, "#consult-copy-end sits outside <main>, "
                        "so the end of the page has no copy control"))
    for n in rail + end:
        for a in [n] + list(n.ancestors()):
            if _hidden(a):
                out.append((slug, a.line, "#%s is inside a hidden element <%s> "
                            "(hidden or inline display:none), so the reader "
                            "never sees it" % (n.attrs["id"], a.tag)))
                break
    return out


INLINE_NONE = re.compile(r"(?:^|;)\s*display\s*:\s*none\b", re.I)


def _hidden(n):
    return "hidden" in n.attrs or bool(INLINE_NONE.search(n.attrs.get("style") or ""))


# --- 5. ui-string-language ------------------------------------------------------

# The kit's static chrome, per language: composer.js STRINGS (the relabelled
# keys), spec_build.STRINGS and gallery_items' notes box. Kept here, not read
# from those files, so a page is judged the same whichever kit built it.
KIT_STRINGS = {
    "en": {"Copy my answers", "Contents", "Notes on this one",
           "Anything the options do not cover…", "Anything the list does not cover…",
           "Anything the value alone does not say…", "The choice", "The value",
           "Anything that does not fit above", "Whatever it is…", "Your answer…",
           "Notes on this row", "What to change…"},
    "es": {"Copiar mis respuestas", "Contenido", "Notas sobre esta",
           "Notas sobre esto", "Cualquier cosa que las opciones no cubran…",
           "Lo que las opciones no cubren…", "Cualquier cosa que la lista no cubra…",
           "Cualquier cosa que el valor por sí solo no diga…", "La elección",
           "El valor", "Cualquier cosa que no encaje arriba",
           "Lo que no encaja arriba", "Lo que sea…", "Tu respuesta…",
           "Notas sobre esta fila", "Qué cambiar…"},
}
CHROME_IDS = ("consult-copy", "consult-copy-end")
CHROME_CLASSES = ("railhead", "fieldlabel", "consult-status")


def check_ui_string_language(path, html_text):
    b, out = parse(html_text), []
    html = next((n for n in b.root.walk() if n.tag == "html"), None)
    lang = ((html.attrs.get("lang") if html else "") or "")[:2].lower()
    if lang not in KIT_STRINGS:          # no lang, or one the kit has no strings for
        return out
    other = "es" if lang == "en" else "en"
    for n in b.root.walk():
        shown = []
        if n.attrs.get("id") in CHROME_IDS or n.classes() & set(CHROME_CLASSES):
            # The label is the element's OWN text: a child counter or badge
            # (`<span class="n">3</span>`) is not part of the kit string.
            shown.append(_norm("".join(c[1] for c in n.children
                                       if not isinstance(c, Node))))
        if n.tag == "textarea" and "placeholder" in n.attrs:
            shown.append(_norm(n.attrs["placeholder"]))
        for s in shown:
            if s in KIT_STRINGS[other]:
                out.append(("ui-string-language", n.line, "kit string \"%s\" is "
                            "%s on a lang=\"%s\" page" % (s, other, lang)))
    return out


CHECKS = {
    "decision-item-without-options": check_decision_item_without_options,
    "decision-page-not-interactive": check_decision_page_not_interactive,
    "mixed-content-types": check_mixed_content_types,
    "copy-control-placement": check_copy_control_placement,
    "ui-string-language": check_ui_string_language,
}


def findings(path, slugs=None):
    text = open(path, encoding="utf-8", errors="replace").read()
    out = []
    for slug in (slugs or CHECKS):
        out.extend(CHECKS[slug](path, text))
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--class", dest="cls", choices=sorted(CHECKS))
    ap.add_argument("pages", nargs="+")
    args = ap.parse_args(argv)
    bad = 0
    for page in args.pages:
        for slug, line, msg in findings(page, [args.cls] if args.cls else None):
            print("FAIL [%s] %s:%d: %s" % (slug, page, line, msg))
            bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
