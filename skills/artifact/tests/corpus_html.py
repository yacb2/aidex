#!/usr/bin/env python3
"""A tiny DOM over the corpus pages, and the ONE definition of "visible text".

Shared by `corpus_diff.py` (which verifies a conversion) and
`corpus_convert.py` (which drafts one). They must agree about what a page says,
or the drafting aid would be chasing a target the verifier does not use.

Stdlib only: `html.parser`, which is all a page of this shape needs.

## What "visible text" means here

The corpus spans a year of kit versions, so the comparison cannot be over
markup — the whole point of the conversion is that the markup changes. What has
to survive is what a READER sees, in the order they see it. So:

- every element is flattened to its text, with a space inserted at every tag
  boundary (`<b>6</b><span>archivos</span>` and `<b>6</b> archivos` are the same
  two words, and a comparison that joined them into `6archivos` would be
  measuring the markup again);
- entities are resolved, whitespace collapsed, and the result compared as a
  list of tokens.

## What is excluded, and why each exclusion is not a hole

`DROP_TAGS` — `script`, `style`, `noscript`, `template`: never rendered.
`input`, `button`, `select`, `textarea`: the kit's own answer widgets. Their
labels are injected by the builder from `STRINGS`, in the page's language, and
an author never writes them; comparing them would compare kit versions.

`DROP_CLASSES` — the kit chrome that the same builder injects: the rail, the two
copy bars, the `fieldlabel` above a notes box, and the
`consult-id` badge (the id is compared separately and exactly, so comparing its
echo inside the h3 would double-count it). `.stamp` is deliberately NOT on the
list: the kit's own build stamp lives outside `<main>` and never reaches the
content root, while three pre-kit pages use the same class name for an AUTHORED
run of facts (`Fecha 2026-08-06 · Agentes 51 · Push ninguno`). Dropping it
by name would have hidden authored text behind a class collision.

`<figure>` holding an `<svg>` or an `<img>` — **this is the one exclusion that
drops authored content**, and it is deliberate: hand-drawn figures are counted
by the gate's `figures: C/45` line (once `diagrams: N/N`), and Phase 3's
`corpus:` line would otherwise be gated on a block type that does not exist yet. `figures_dropped()` reports the count so the
omission is visible in the notes rather than silent. A `<figure>` with neither —
a table with a caption, say — is NOT dropped.
"""

import html
import html.parser
import re

DROP_TAGS = {"script", "style", "noscript", "template",
             "input", "button", "select", "textarea", "svg"}

DROP_CLASSES = {
    "rail", "railhead", "raillist",       # the contents rail
    "consult-bar", "endbar", "inbar",     # the two copy bars
    "consult-status", "consult-id",       # status line, id badge
    "fieldlabel",                         # the label above a notes box
}

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr"}


class Node:
    __slots__ = ("tag", "attrs", "children", "parent", "text")

    def __init__(self, tag, attrs=None, text=None, parent=None):
        self.tag = tag
        self.attrs = attrs or {}
        self.children = []
        self.parent = parent
        self.text = text

    # -- convenience -------------------------------------------------------
    @property
    def classes(self):
        return self.attrs.get("class", "").split()

    def has(self, name):
        return name in self.classes

    def find(self, tag=None, cls=None):
        for n in self.walk():
            if n is self:
                continue
            if tag and n.tag != tag:
                continue
            if cls and not n.has(cls):
                continue
            return n
        return None

    def find_all(self, tag=None, cls=None):
        out = []
        for n in self.walk():
            if n is self:
                continue
            if tag and n.tag != tag:
                continue
            if cls and not n.has(cls):
                continue
            out.append(n)
        return out

    def walk(self):
        yield self
        for c in self.children:
            for n in c.walk():
                yield n

    @property
    def elements(self):
        return [c for c in self.children if c.tag != "#text"]

    def __repr__(self):
        return "<%s %s>" % (self.tag, self.attrs.get("class", ""))


class _Parser(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root")
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, dict(attrs), parent=self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, dict(attrs), parent=self.cur))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        node = self.cur
        while node is not self.root and node.tag != tag:
            node = node.parent
        if node is not self.root:
            self.cur = node.parent

    def handle_data(self, data):
        self.cur.children.append(Node("#text", text=data, parent=self.cur))


def parse(text):
    """The page as a tree. Comments are stripped first — `convert_charrefs`
    keeps entity text, and a comment holding markup would otherwise parse."""
    p = _Parser()
    p.feed(re.sub(r"(?s)<!--.*?-->", "", text))
    p.close()
    return p.root


def content_root(text):
    """The authored region: `<main>`, else `<body>`, else the whole fragment.

    The same three-rung fallback `baseline-method.md` records, for the same
    reason: two of the sampled pages are HTML *fragments* with no `<body>` at
    all, and dropping them would be the exclusion the plan forbids.
    """
    root = parse(text)
    for tag in ("main", "body"):
        node = root.find(tag=tag)
        if node is not None:
            return node
    return root


def _dropped(node):
    if node.tag in DROP_TAGS:
        return True
    if DROP_CLASSES.intersection(node.classes):
        return True
    if node.tag == "figure":
        for n in node.walk():
            if n.tag in ("svg", "img"):
                return True
    return False


def figures_dropped(node):
    """How many `<figure>`s this region hands to Phase 6."""
    n = 0
    for el in node.walk():
        if el.tag == "figure" and _dropped(el):
            n += 1
    return n


def _collect(node, out):
    for child in node.children:
        if child.tag == "#text":
            out.append(child.text)
            continue
        if _dropped(child):
            continue
        out.append(" ")
        _collect(child, out)
        out.append(" ")


def visible_text(node):
    out = []
    _collect(node, out)
    return html.unescape("".join(out))


def tokens(node):
    """The comparison unit: whitespace-collapsed words, in reading order."""
    return visible_text(node).split()


def ids(node):
    """Every block/item id the region declares, in document order.

    `data-id` is the kit's own addressing attribute — the rail anchor, the paste
    key, and what `check_artifact.py`'s consult-shape rules read. A dropped
    subtree's ids go with it (there are none: no chrome carries a `data-id`).
    """
    out = []

    def rec(el):
        for child in el.children:
            if child.tag == "#text" or _dropped(child):
                continue
            if "data-id" in child.attrs:
                out.append(child.attrs["data-id"])
            rec(child)

    rec(node)
    return out
