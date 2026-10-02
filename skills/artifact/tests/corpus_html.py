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


# Inside a consult option's label ONLY (owner ruling 2026-09-28, the consult
# contract wins): the builder writes `label <span class="hint">hint</span>`
# where older pages wrote the separator as text, `label — hint`, and the kit
# draws the recommended badge itself where older pages carried its word as text
# (composer.js `rec`; test-goal-gate.sh holds BADGE_WORDS to it). So an option
# label is read in one canonical form: a `.hint` gets the " — " separator in front unless it already starts with one,
# and one badge word is taken out. Nothing outside an option label is
# normalised. Which option is recommended, which is checked, and its input type
# (radio/checkbox, BL-550) IS compared (`option_flags`): a decided item's winning option is `{chosen}` in a spec
# (checked, not recommended), a real recommendation is `{recommended}`.
OPTION_SEP = "\u2014"
BADGE_WORDS = {"Recomendada", "Recommended"}


def _option_input(node):
    """The radio/checkbox a `<label>` wraps, or None: that is an option."""
    if node.tag != "label":
        return None
    return next((n for n in node.walk() if n.tag == "input"
                 and n.attrs.get("type") in ("radio", "checkbox")), None)


def option_flags(node, original=False):
    """`[(label, recommended, checked, open_verdict, type), ...]`, one per
    option, in reading order.

    Recommended is the `data-recommended` attribute OR the badge the older
    pages carried as markup or text (a `.rec` element or a badge word in the
    label), read on the ORIGINAL side only (`original=True`): the kit draws the
    badge from the attribute, so the built page has only the attribute. Checked is the input's `checked` attribute, counted
    only inside a decided item (`data-decided`): the grammar can check an
    option only to show a verdict, so a pre-checked option of an UNDECIDED item
    (contracts-sweep-decisions Q17) has no spelling and is not compared.
    The fourth flag, `open_verdict`, is whether the option's item is decided
    with no option checked in it: only there may a build add a check.
    The fifth, `type`, is the input's `radio` or `checkbox`: the item's
    select=one or select=many (BL-550).
    """
    found = []
    for el in node.walk():
        inp = _option_input(el)
        if inp is None or _dropped(el):
            continue
        item = el.parent
        while item is not None and not item.has("consult-item"):
            item = item.parent
        found.append((el, inp, item))
    checked_items = {id(item) for _, inp, item in found
                     if item is not None and "checked" in inp.attrs}
    out = []
    for el, inp, item in found:
        words = _option_tokens(el)
        sub = []
        _collect_option(el, sub)
        raw = html.unescape("".join(sub)).split()
        rec = "data-recommended" in inp.attrs or (original and (
            any(w in BADGE_WORDS for w in raw)
            or any(n.has("rec") for n in el.walk())))
        decided = item is not None and "data-decided" in item.attrs
        out.append((" ".join(words), rec, decided and "checked" in inp.attrs,
                    decided and id(item) not in checked_items,
                    inp.attrs.get("type")))
    return out


def _collect_option(node, out):
    for child in node.children:
        if child.tag == "#text":
            out.append(child.text)
            continue
        if _dropped(child):
            continue
        out.append(" ")
        if child.has("hint"):
            inner = []
            _collect(child, inner)
            hint = html.unescape("".join(inner)).strip()
            if hint and not hint.startswith(OPTION_SEP):
                out.append(OPTION_SEP + " ")
            out.append(hint)
        else:
            _collect_option(child, out)
        out.append(" ")


def _option_tokens(label):
    sub = []
    _collect_option(label, sub)
    words = html.unescape("".join(sub)).split()
    badge = next((w for w in words if w in BADGE_WORDS), None)
    if badge:
        words.remove(badge)
    return words


def _h3_is_title(h3):
    """True when the h3 reads exactly as its section's data-title (id badge aside)."""
    title = h3.parent.attrs.get("data-title") if h3.parent else None
    if not title:
        return False
    words = []
    for n in h3.walk():
        if n.tag == "#text" and not any(
                a.has("consult-id") for a in _ancestors(n, h3)):
            words.append(n.text)
    return _plain("".join(words)) == _plain(title)


def _plain(text):
    """Words of a title with its inline markup (tags, backticks, emphasis) off."""
    text = re.sub(r"<[^>]*>", "", html.unescape(text))
    return " ".join(re.sub(r"[`*_]", "", text).split())


def _ancestors(node, stop):
    n = node.parent
    while n is not None and n is not stop.parent:
        yield n
        n = n.parent


def _lead_first(children, lead_first_ids=()):
    """Reading order of an item's children, the situation lead first.

    The builder (BL-514) keeps only an item's closing question in the h3 and
    moves the situation sentences into a `.consult-lead` paragraph right UNDER it;
    older pages wrote both in the h3, lead first. A built item is read in the
    old order: its lead goes in front of the h3. Nothing else is moved.

    An item whose first paragraph asks no question keeps its TITLE in the h3 and
    that paragraph becomes the lead (BL-576): the original read heading, then
    statement, so a lead under an h3 that is the item's data-title stays put
    unless the original item with that data-id had content before its h3
    (`lead_first_ids`: a finding card whose chips precede the title).
    """
    out, moved = [], set()
    for i, c in enumerate(children):
        if c.tag != "h3" or (_h3_is_title(c) and (
                c.parent.attrs.get("data-id") not in lead_first_ids)):
            continue
        nxt = next((n for n in children[i + 1:]
                    if not (n.tag == "#text" and not n.text.strip())), None)
        if nxt is not None and nxt.has("consult-lead"):
            moved.add(id(nxt))
    if not moved:
        return children
    for c in children:
        if id(c) in moved:
            continue
        if c.tag == "h3":
            out.extend(n for n in children if id(n) in moved)
        out.append(c)
    return out


def _collect(node, out, lead_first_ids=()):
    for child in _lead_first(node.children, lead_first_ids):
        if child.tag == "#text":
            out.append(child.text)
            continue
        if _dropped(child):
            continue
        out.append(" ")
        if _option_input(child) is not None:
            out.append(" ".join(_option_tokens(child)))
        else:
            _collect(child, out, lead_first_ids)
        out.append(" ")


def visible_text(node, lead_first_ids=()):
    out = []
    _collect(node, out, lead_first_ids)
    return html.unescape("".join(out))


def tokens(node, lead_first_ids=()):
    """The comparison unit: whitespace-collapsed words, in reading order."""
    return visible_text(node, lead_first_ids).split()


def ids_with_content_before_h3(node):
    """data-ids of the ORIGINAL's items that show something before their h3."""
    found = set()
    for n in node.walk():
        if "data-id" not in n.attrs:
            continue
        for c in n.children:
            if c.tag == "h3":
                break
            if c.tag != "#text" and not _dropped(c) and visible_text(c).strip():
                found.add(n.attrs["data-id"])
                break
            if c.tag == "#text" and c.text.strip():
                found.add(n.attrs["data-id"])
                break
    return found


def ids(node, skip=()):
    """Every block/item id the region declares, in document order.

    `data-id` is the kit's own addressing attribute — the rail anchor, the paste
    key, and what `check_artifact.py`'s consult-shape rules read. A dropped
    subtree's ids go with it (there are none: no chrome carries a `data-id`).
    A node in `skip` keeps its subtree's ids and loses only its own.
    """
    out = []

    def rec(el):
        for child in el.children:
            if child.tag == "#text" or _dropped(child):
                continue
            if "data-id" in child.attrs and child not in skip:
                out.append(child.attrs["data-id"])
            rec(child)

    rec(node)
    return out
