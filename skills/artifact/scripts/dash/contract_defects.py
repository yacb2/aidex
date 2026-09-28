#!/usr/bin/env python3
"""Page-contract consistency checks: one function per frozen defect class
(LOOP-006, `.context/loops/2026-09-27-artifact-contract-defects-STATE.md` in the
workspace). Each takes (path, html_text) and returns [(slug, line, message)].

    python3 contract_defects.py [--class SLUG] PAGE...     # exit 1 on any finding

Classes and the exact rule each one enforces:

decision-item-without-options
    The single owner of the item rule and of the leaked-marker rule:
    check_artifact's BL-468 `consult-free` warning and its BL-481 `rec-leak`
    check were replaced by a call here (LOOP-006 Phase C). An element with class
    `consult-item` and a `data-id` must offer at least OPTIONS_MIN options: that
    many radio/checkbox inputs, or a <select> with that many <option>s, counted
    on the item's OWN subtree (a nested consult item's options answer the nested
    item). Exempt: the general-notes item (`consult-notes`), a settled item
    (`data-decided`, the exact attribute; `data-decided-round` alone is not one),
    a gallery SAMPLE row — exactly what composer.js:707-712 leaves uncounted
    (BL-466): a gallery row with no `.opts` group — and an OPEN ANSWER marked `data-free` whose value is not "no"/"false" — the
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
    not be a kit string of the OTHER language than `<html lang>` (es/en only;
    the primary subtag, read by page_lang: "es_ES" and "es-419" are es).
    Pages with no lang or another lang are skipped; the label is the element's
    own text (child counters dropped), whitespace collapsed. Judged on the
    source: the composer relabels exact English defaults at run
    time, so a JS-less read, a copy of the source, or an older composer shows
    what this reads.

decided-item-without-verdict
    A `.consult-item` carrying `data-decided` must carry the verdict its fold
    shows, read the way composer.js decidedSummary/decidedLine read it: a
    non-blank `data-decided` value, or anywhere in its subtree (nested items
    included, as querySelectorAll walks them) a `checked` radio/checkbox whose
    label (data-label, else value, else "on") is non-blank, or an explicitly
    `selected` <option> whose value (value attribute, else its text) is
    non-empty — a selected placeholder `value=""` is no verdict. Two rules are
    deliberately STRICTER than the runtime: a select's implicit first option
    is not a verdict (the source does not say it was chosen), and a
    `data-decided` of "yes"/"true"/"1" (any case) is not one either — the fold
    would show a bare "yes". A verdict only in the item's prose is hidden by
    the fold.

item-title-repeats-id
    A consult item's `data-title` must not equal its `data-id` nor start with
    it followed by a separator (" · ", ":", " - ", a space, a "." not followed
    by a digit), compared case-insensitively: the composer already prefixes
    the id, so the reply reads "M1 · M1 · …". "M10 …" and "M1.2 …" under id M1
    are different tokens and pass.

lang-follows-profile
    A page under a project whose `.context/artifact-style.md` declares
    `language: X` carries `<html lang>` whose primary subtag is X; a missing
    lang fails too. The project and the field are read by wrap_report's own
    find_context_dir/profile_language, so the verdict depends on WHERE the page
    sits. Close-out reports under `/worklists/_archive/` are not exempt (BL-382);
    `human-verification.*` pages are, the one page English by D-04 (owner
    ruling, LOOP-006: no wrap flag switches this class off). No profile, or no
    `language:` field: not judged.

decided-section-anchor
    Mirrors composer.js collapseDecided: a decided item outside any
    `.consult-group`, or a group whose every consult item is decided, is a unit
    the composer moves into the collapsed "decided" section. A page with at
    least one such unit has an element `#sec-ledger` or a <header> whose parent
    carries class `main`: the section goes after that anchor, and without one
    it is appended at the end of `.main`, after the general notes. A decided
    item in a half-open group folds in place and needs no anchor.

img-src-portable
    No <img> `src` or `srcset` candidate with the `file:` scheme or an absolute
    filesystem path (a leading "/" that is not "//", a drive letter, a UNC
    `\\\\server\\` path). Images are data: URIs or page-relative copies.

unique-dom-ids
    Every non-empty `id` value appears once in the document, inline-SVG ids
    included (a marker id repeated across two figures sends the second
    figure's url(#…) to the first).

group-item-id-collision
    An element whose id equals a consult item's `data-id` (the item's own id
    excepted). composer.js (kit 27) gives every item an id through claimId: its
    `data-id`, or the first free `<id>-<n>` when another element already holds
    it. The rail links to the id the item really got, so the rail still lands on
    the item; what breaks is every hand-written `#<id>` link — a reply, a note,
    another page — which opens the other element instead. The ids that exist
    before the items claim theirs: every authored `id`, a group's included, and
    the `data-id` that groupEntry claims for a `.consult-group` with no id of
    its own, replayed in the composer's order: `.main > section[id]` in
    document order, a non-group section only if it holds an h2, a group moved
    into the decided section never, and an item that claimed the id first keeps
    it (the group yields). A data-id-only group anywhere else never gets an id. Two
    items sharing a `data-id` are check-artifact's `duplicate ids` finding, not
    this class's. Invisible to unique-dom-ids on the source.

body-language-follows-lang
    The page's prose is in the language `<html lang>` names (es/en only, by
    page_lang's primary subtag, as ui-string-language reads it; no
    lang or another lang is not judged — a missing lang is lang-follows-profile's).
    That class compares the attribute to the profile; this one compares the
    body to the attribute, profile or not. A stopword count over the visible
    prose: each word is looked up in two lists of function words that belong to
    ONE language only (STOPWORDS). Not prose: <code>, <pre>, <kbd>, <samp>,
    <var>, <svg>, <math>, form controls, <nav>, the kit chrome that
    ui-string-language reads, a `hidden` element, any element with its own
    `lang` (a quotation marked as another language), and a token glued to
    `_`, `/`, `-`, `#`, `@`, a digit or a `.x` suffix (an identifier). Not
    counted: a function word inside a proper name or a title ("Calle de
    Alcalá", "Gone with the Wind") — a capitalised one followed by a
    capitalised word, or a lower-case one whose nearest other words on both
    sides are capitalised. Judged only from LANG_WORDS_MIN (80) prose words AND
    LANG_FUNCTION_MIN (25) function words counted, so a noun-heavy page (a
    table of names) is not decided by a handful; fails when the other language
    holds LANG_DOMINANCE (75%) or more of them, each bound inclusive. Census
    2026-09-28 over 179 report pages: 164 over the word floor, the fewest
    function words among them 162 (so the 25 floor skipped none), the highest
    wrong-language share 5.4%, and every judged page flipped to the other lang
    failed. Not frozen on a shipped page: no page in that census had the
    defect, so the registry has no original for it yet.
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


def _gallery_sample(item):
    """composer.js:707-712 (BL-466): a gallery row with no `.opts` group is a
    SAMPLE that asks nothing, counted nowhere like the notes item. Same
    predicate as the composer: isGalleryRow (composer.js:1433: class
    `consult-gallery`, or a `.gal` / `figure[data-tile]` anywhere in the
    subtree) and no `.opts` anywhere in the subtree (querySelector)."""
    sub = list(item.walk())
    gallery = "consult-gallery" in item.classes() or any(
        "gal" in d.classes() or (d.tag == "figure" and "data-tile" in d.attrs)
        for d in sub)
    return gallery and not any("opts" in d.classes() for d in sub)


def check_decision_item_without_options(path, html_text):
    b, out, slug = parse(html_text), [], "decision-item-without-options"
    for n in b.root.walk():
        if not (_is_item(n) and "data-id" in n.attrs) or _gallery_sample(n):
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


def page_lang(root):
    """(the <html> node or None, the primary subtag of its lang, lower-cased):
    "es-419", "es_ES" and "ES" are all "es"; no lang is ""."""
    html = next((n for n in root.walk() if n.tag == "html"), None)
    raw = ((html.attrs.get("lang") if html else "") or "").strip()
    return html, re.split(r"[-_]", raw)[0].lower()


def check_ui_string_language(path, html_text):
    b, out = parse(html_text), []
    html, lang = page_lang(b.root)
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


# --- 6. decided-item-without-verdict --------------------------------------------

NOT_A_VERDICT = ("yes", "true", "1")      # stricter than the runtime, on purpose


def _has_verdict(item):
    v = (item.attrs.get("data-decided") or "").strip()
    if v:
        return v.lower() not in NOT_A_VERDICT
    for d in item.walk():                     # composer.js:346, the whole subtree
        if d.tag == "input" and (d.attrs.get("type") or "").lower() in OPTION_INPUT \
                and "checked" in d.attrs:
            label = d.attrs.get("data-label") or d.attrs.get("value", "on")
            if label.strip():
                return True
        if d.tag == "option" and "selected" in d.attrs:
            value = d.attrs["value"] if "value" in d.attrs else d.text()
            if value.strip():
                return True
    return False


def check_decided_item_without_verdict(path, html_text):
    out = []
    for n in parse(html_text).root.walk():
        if "consult-item" in n.classes() and "data-decided" in n.attrs \
                and not _has_verdict(n):
            out.append(("decided-item-without-verdict", n.line,
                        "item '%s' is decided but carries no verdict: its fold "
                        "shows the title alone. Put the verdict in data-decided=\"…\" "
                        "or check the chosen option" % n.attrs.get("data-id", "?")))
    return out


# --- 7. item-title-repeats-id ---------------------------------------------------

def title_repeats_id(ident, title):
    ident, title = ident.strip(), title.strip()
    if not ident or not title.casefold().startswith(ident.casefold()):
        return False
    rest = title[len(ident):]
    if not rest:
        return True
    if rest[0].isalnum() or (rest[0] == "." and rest[1:2].isdigit()):
        return False                          # M10, M1.2: another token
    return True


def check_item_title_repeats_id(path, html_text):
    out = []
    for n in parse(html_text).root.walk():
        if _is_item(n) and title_repeats_id(n.attrs.get("data-id") or "",
                                            n.attrs.get("data-title") or ""):
            out.append(("item-title-repeats-id", n.line,
                        "item '%s' has data-title \"%s\": the composer prefixes "
                        "the id already, so the reply reads the id twice"
                        % (n.attrs["data-id"], _norm(n.attrs["data-title"])[:60])))
    return out


# --- 8. lang-follows-profile ----------------------------------------------------

LANG_EXEMPT_PREFIX = "human-verification."     # D-04, owner ruling LOOP-006
_CONTEXT_DIRS = {}                             # page directory -> .context or None


def check_lang_follows_profile(path, html_text):
    import os
    import wrap_report                   # the profile's one reader (find + field)
    if os.path.basename(path).startswith(LANG_EXEMPT_PREFIX):
        return []
    here = os.path.dirname(os.path.abspath(path))
    if here not in _CONTEXT_DIRS:        # one bash spawn per directory, not per page
        _CONTEXT_DIRS[here] = wrap_report.find_context_dir(here)
    ctx = _CONTEXT_DIRS[here]
    want = wrap_report.profile_language(ctx)
    if not want:
        return []
    html = next((n for n in parse(html_text).root.walk() if n.tag == "html"), None)
    got = ((html.attrs.get("lang") if html else "") or "").strip()
    if got.split("-")[0].lower() == want.split("-")[0].lower():
        return []
    return [("lang-follows-profile", html.line if html else 1,
             "<html lang=\"%s\"> but %s/artifact-style.md declares language: %s"
             % (got, ctx, want))]


# --- 9. decided-section-anchor --------------------------------------------------

def _group(n):
    return next((a for a in n.ancestors() if "consult-group" in a.classes()), None)


def check_decided_section_anchor(path, html_text):
    nodes = list(parse(html_text).root.walk())
    items = [n for n in nodes if "consult-item" in n.classes()]
    decided = []                       # composer.js collapseDecided's units
    for n in items:
        if "data-decided" not in n.attrs:
            continue
        g = _group(n)
        if g is None or all("data-decided" in d.attrs for d in g.walk()
                            if "consult-item" in d.classes()):
            decided.append(n)
    if not decided or any(
            n.attrs.get("id") == "sec-ledger"
            or (n.tag == "header" and n.parent is not None
                and "main" in n.parent.classes())
            for n in nodes):
        return []
    return [("decided-section-anchor", decided[0].line,
             "%d decided item(s) and no anchor for their section: neither "
             "#sec-ledger nor a <header> directly under .main, so the composer "
             "appends the settled questions after the general notes" % len(decided))]


# --- 10. img-src-portable -------------------------------------------------------

NOT_PORTABLE = re.compile(r"^(?:file:|/(?!/)|[A-Za-z]:[\\/]|\\\\)", re.I)


def check_img_src_portable(path, html_text):
    out = []
    for n in parse(html_text).root.walk():
        if n.tag != "img":
            continue
        urls = [("src", (n.attrs.get("src") or "").strip())]
        urls += [("srcset", c.split()[0]) for c in (n.attrs.get("srcset") or "").split(",")
                 if c.strip()]
        for attr, url in urls:
            if NOT_PORTABLE.match(url):
                out.append(("img-src-portable", n.line,
                            "<img %s=\"%s\"> points at this machine's filesystem: "
                            "inline it as a data: URI or copy it beside the page"
                            % (attr, url[:80])))
    return out


# --- 11. unique-dom-ids ---------------------------------------------------------

def check_unique_dom_ids(path, html_text):
    seen, out = {}, []
    for n in parse(html_text).root.walk():
        ident = n.attrs.get("id")
        if not ident:
            continue
        if ident in seen:
            if seen[ident] is not None:
                out.append(("unique-dom-ids", n.line,
                            "id \"%s\" is used again (first on line %d): "
                            "getElementById and url(#…) resolve to the first"
                            % (ident[:60], seen[ident])))
                seen[ident] = None               # one finding per value
        else:
            seen[ident] = n.line
    return out


# --- 12. group-item-id-collision ------------------------------------------------

def _moved_to_decided(group):
    """composer.js collapseDecided moves a group whose every consult item is
    decided into the decided section (same test as decided-section-anchor)."""
    its = [d for d in group.walk() if "consult-item" in d.classes()]
    return bool(its) and all("data-decided" in d.attrs for d in its)


def _runtime_group_ids(nodes):
    """{group node: the data-id composer.js groupEntry claims for it}, replayed
    in the composer's own order (kit 27, composer.js:498-515). It walks
    `.main > section[id]` in document order: a group there is entered at once;
    any other section needs an h2 and then enters every `.consult-group` inside
    it. Entering a group with no id and a data-id claims that data-id unless an
    item already took it; then the group's items claim theirs. A group moved
    into the decided section is never entered."""
    claimed, out = set(), {}

    def enter(g):
        ident = g.attrs.get("data-id")
        if not g.attrs.get("id") and ident and ident not in claimed:
            out[g] = ident
            claimed.add(ident)
        for d in g.walk():
            if "consult-item" in d.classes() and d.attrs.get("data-id"):
                claimed.add(d.attrs["data-id"])

    for m in nodes:
        if "main" not in m.classes():
            continue
        for sec in m.children:
            if not (isinstance(sec, Node) and sec.tag == "section" and "id" in sec.attrs):
                continue
            if "consult-group" in sec.classes():
                if not _moved_to_decided(sec):
                    enter(sec)
                continue
            if not any(d.tag == "h2" for d in sec.walk()):
                continue
            for g in sec.walk():
                if "consult-group" in g.classes() and not _moved_to_decided(g):
                    enter(g)
    return out


def check_group_item_id_collision(path, html_text):
    """Ids that exist before composer.js assigns item ids, checked against the
    items' data-ids."""
    nodes = list(parse(html_text).root.walk())
    slug, out = "group-item-id-collision", []
    runtime = _runtime_group_ids(nodes)
    items = {}                                       # data-id -> first item
    for n in nodes:
        if ("consult-item" in n.classes() and "consult-group" not in n.classes()
                and n.attrs.get("data-id")):
            items.setdefault(n.attrs["data-id"], n)
    for n in nodes:
        if "consult-item" in n.classes() and "consult-group" not in n.classes():
            continue                                 # an item's own id: its own
        if "consult-group" in n.classes():
            ident = n.attrs.get("id") or runtime.get(n)
            what = "consult-group"
        else:
            ident, what = n.attrs.get("id"), "<%s id>" % n.tag
        if ident and ident in items:
            out.append((slug, n.line, "%s and consult-item both use \"%s\": the "
                        "item yields and gets \"%s-2\", so a hand-written #%s link "
                        "(a reply, a note, another page) opens the %s instead of "
                        "the item. Rename one of them"
                        % (what, ident, ident, ident, what)))
    return out


# --- 13. body-language-follows-lang --------------------------------------------

# Function words only, each in ONE language: a word both languages write ("a",
# "no", "me", "he", "son", "sin", "con", "la", "come") is in neither list.
STOPWORDS = {
    "en": frozenset("""the and of to in is are was were be been that this these
        those it its for on with as by from at or but not which what when where
        who how why will would can could should have has had an they their them
        there than then so if into about also only just more most other such
        each any all our your we you do does did doesn't don't isn't it's
        because while after before over under between""".split()),
    "es": frozenset("""el los las de del que y en un una unos unas por para es
        está están se lo al como más pero sus su este esta estos estas esto
        ese esa eso sobre también ya hay cuando porque muy qué cómo donde
        dónde cada todo todos toda todas entre sino aunque ni ser fue han
        ha tiene tienen puede pueden hace hacer sólo tras
        desde hasta según nos les le""".split()),
}
LANG_WORDS_MIN = 80        # prose words before a page is judged at all
LANG_FUNCTION_MIN = 25     # function words counted before a page is judged at all
LANG_DOMINANCE = 0.75      # the other language's share of function words to fail
LANG_SKIP_TAGS = {"code", "pre", "kbd", "samp", "var", "svg", "math", "textarea",
                  "template", "select", "option", "nav", "head"}
PROSE_WORD = re.compile(r"(?<![\w./#@-])[^\W\d_]+(?:'[^\W\d_]+)?(?![\w/#@-]|\.\w)")
FUNCTION_WORDS = STOPWORDS["en"] | STOPWORDS["es"]


def prose_runs(root):
    """The page's visible prose: one list of words (case kept) per text node.
    Skipped subtrees: code and its kin, svg, form controls, nav, the kit chrome
    labels, anything `hidden`, and any element carrying its own `lang` (a
    quotation the page marks as another language). A token glued to `_`, `/`,
    `-`, `.x`, `#`, `@` or a digit is an identifier, not a word."""
    out = []

    def visit(n):
        for c in n.children:
            if isinstance(c, Node):
                if (c.tag in RAW or c.tag in LANG_SKIP_TAGS or "hidden" in c.attrs
                        or ("lang" in c.attrs and c.tag != "html")
                        or c.attrs.get("id") in CHROME_IDS
                        or c.classes() & set(CHROME_CLASSES)):
                    continue
                visit(c)
            else:
                out.append(PROSE_WORD.findall(c[1]))
    visit(root)
    return out


def _in_name(run, i):
    """Whether the function word run[i] is part of a proper name or a title
    ("Calle de Alcalá", "Gone with the Wind", "The Lord of the Rings"): a
    capitalised one followed by a capitalised word, or a lower-case one whose
    nearest words on both sides that are not lower-case function words are
    capitalised."""
    def cap(w):
        return w[0].isupper()

    def lower_fn(w):
        return not cap(w) and w.lower() in FUNCTION_WORDS
    if cap(run[i]):
        return i + 1 < len(run) and cap(run[i + 1])
    prev = next((w for w in reversed(run[:i]) if not lower_fn(w)), None)
    nxt = next((w for w in run[i + 1:] if not lower_fn(w)), None)
    return bool(prev and nxt and cap(prev) and cap(nxt))


def function_word_hits(runs):
    """Function words per language, those inside a name left out."""
    hits = {k: 0 for k in STOPWORDS}
    for run in runs:
        for i, w in enumerate(run):
            k = next((k for k, v in STOPWORDS.items() if w.lower() in v), None)
            if k and not _in_name(run, i):
                hits[k] += 1
    return hits


def check_body_language_follows_lang(path, html_text):
    html, lang = page_lang(parse(html_text).root)
    if lang not in STOPWORDS:            # no lang, or one this class cannot read
        return []
    runs = prose_runs(html)
    words = sum(len(r) for r in runs)
    if words < LANG_WORDS_MIN:
        return []
    hits = function_word_hits(runs)
    other = "es" if lang == "en" else "en"
    total = hits["en"] + hits["es"]
    if total < LANG_FUNCTION_MIN or hits[other] / total < LANG_DOMINANCE:
        return []
    return [("body-language-follows-lang", html.line,
             "<html lang=\"%s\"> but the prose reads %s: %d of %d function words "
             "are %s (%d prose words)" % (html.attrs.get("lang"), other,
                                           hits[other], total, other, words))]


CHECKS = {
    "decision-item-without-options": check_decision_item_without_options,
    "decision-page-not-interactive": check_decision_page_not_interactive,
    "mixed-content-types": check_mixed_content_types,
    "copy-control-placement": check_copy_control_placement,
    "ui-string-language": check_ui_string_language,
    "decided-item-without-verdict": check_decided_item_without_verdict,
    "item-title-repeats-id": check_item_title_repeats_id,
    "lang-follows-profile": check_lang_follows_profile,
    "decided-section-anchor": check_decided_section_anchor,
    "img-src-portable": check_img_src_portable,
    "unique-dom-ids": check_unique_dom_ids,
    "group-item-id-collision": check_group_item_id_collision,
    "body-language-follows-lang": check_body_language_follows_lang,
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
