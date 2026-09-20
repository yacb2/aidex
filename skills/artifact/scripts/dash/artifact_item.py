#!/usr/bin/env python3
"""artifact_item.py — outline, read and replace ONE unit of a page's BODY SIDECAR.

A revision round does not need the wrapped page, and since the sidecar it does not
need the whole body either. Measured 2026-09-20 on one consultation: editing a
single item cost 131 KB read from the wrapped file, 43 KB from the sidecar, ~2.7 KB
with `list` + `get` of the one unit.

This is Aider's "map then fetch" (repo map -> one symbol) applied to the one file
the wrap already keeps: `list` is the map, `get` is the fetch, `put` is the write
back. It edits the SIDECAR only and never wraps — wrapping is what verifies the
contract, and a tool that both edits and wraps would make a failed contract look
like a failed edit.

Addressing:
  .body     units are every element carrying `data-id` (item, or group when its
            class has `consult-group`) and every `<section id="...">`.
  .body.md  units are the `## ` sections, addressed by the same slug `md_body`
            gives them in the rendered page (imported, never re-derived).

Offsets come from html.parser, not from a regex: an item nests inside a group, and
a greedy `<section ...>.*</section>` takes the block for the item. `<pre>`,
`<script>`, `<style>`, `<textarea>` and `<svg>` subtrees are opaque — markup shown
inside a `<pre>` is not addressable, and an `id` inside an inline drawing does not
collide with the item that contains it.
"""

import html as _html
import os
import re
import shlex
import sys
from html.parser import HTMLParser

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import md_body  # noqa: E402

SCRIPTS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WRAP = os.path.join(SCRIPTS, "wrap-report.sh")

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr"}
OPAQUE = {"pre", "script", "style", "textarea", "svg"}

HEADING = re.compile(r"<h[1-6][^>]*>(.*?)</h[1-6]>", re.S | re.I)
TAGS = re.compile(r"<[^>]*>", re.S)


def die(msg, code=1):
    sys.stderr.write("artifact-item: " + msg + "\n")
    raise SystemExit(code)


class Unit:
    def __init__(self, uid, kind, title, start, end, depth):
        self.uid, self.kind, self.title = uid, kind, title
        self.start, self.end, self.depth = start, end, depth

    def source(self, text):
        return text[self.start:self.end]


class _Outline(HTMLParser):
    """Byte-faithful outline of an html body: every unit with its exact span."""

    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.text = text
        self.line_at = [0]
        for i, ch in enumerate(text):
            if ch == "\n":
                self.line_at.append(i + 1)
        self.stack = []      # [tag, start, unit_or_None]
        self.units = []
        self.opaque = None   # stack index of the opaque element, while inside one
        # What the parser and a browser would read differently. Harmless in the
        # sidecar's own outline (an unclosed unit simply is not addressable); fatal
        # in a REPLACEMENT, where it decides what ends up inside what.
        self.unclosed = []       # [(uid|None, tag)] opened and never closed
        self.self_closed = []    # [(uid|None, tag)] a non-void element written `/>`
        self._slash = False

    # -- offsets ---------------------------------------------------------
    def _off(self):
        line, col = self.getpos()
        return self.line_at[line - 1] + col

    def _starttag_end(self, start):
        """The end of the tag that is open right now, from the parser itself.

        `text.find(">")` ends a tag inside its own attribute value — a
        `data-title="antes>después"` is enough — and returns half a unit.
        """
        raw = self.get_starttag_text()
        return start + len(raw) if raw else self._tag_end(start)

    def _tag_end(self, start):
        # End tags carry no attributes, so the first ">" is theirs.
        i = self.text.find(">", start)
        return len(self.text) if i < 0 else i + 1

    # -- units -----------------------------------------------------------
    @staticmethod
    def _unit_of(tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        did = a.get("data-id", "").strip()
        if did:
            kind = "group" if "consult-group" in a.get("class", "").split() else "item"
            return Unit(did, kind, a.get("data-title", "").strip(), 0, 0, 0)
        if tag == "section" and a.get("id", "").strip():
            return Unit(a["id"].strip(), "section", a.get("data-title", "").strip(),
                        0, 0, 0)
        return None

    def _emit(self, unit, start, end):
        unit.start, unit.end = start, end
        unit.depth = sum(1 for f in self.stack if f[2])
        if not unit.title:
            m = HEADING.search(self.text[start:end])
            if m:
                txt = _html.unescape(TAGS.sub(" ", m.group(1)))
                unit.title = " ".join(txt.split())
        self.units.append(unit)

    # -- parser hooks ----------------------------------------------------
    def handle_starttag(self, tag, attrs):
        unit = None if self.opaque is not None else self._unit_of(tag, attrs)
        if tag in VOID:
            # A void element closes itself: `<img data-id="fig1">` is a whole unit.
            if unit:
                start = self._off()
                self._emit(unit, start, self._starttag_end(start))
            return
        if self._slash:
            self.self_closed.append((unit.uid if unit else None, tag))
        if self.opaque is None and tag in OPAQUE:
            self.opaque = len(self.stack)
        self.stack.append([tag, self._off(), unit])

    def handle_startendtag(self, tag, attrs):
        if tag in VOID or tag in OPAQUE:
            # `<img …/>` is ordinary html; `<svg …/>` is foreign content, where the
            # slash does close the element.
            if self.opaque is None:
                unit = self._unit_of(tag, attrs)
                if unit:
                    start = self._off()
                    self._emit(unit, start, self._starttag_end(start))
            return
        # Everywhere else HTML ignores the slash: `<div data-id="q3"/>` OPENS a div,
        # and the next sibling becomes its content. Parse it the way the browser
        # will — and remember, because in a replacement it is a refusal.
        self._slash = True
        try:
            self.handle_starttag(tag, attrs)
        finally:
            self._slash = False

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        for i in range(len(self.stack) - 1, -1, -1):
            if self.stack[i][0] == tag:
                break
        else:
            return  # a stray close tag closes nothing
        frame = self.stack[i]
        end = self._tag_end(self._off())
        # This close tag belongs to stack[i]; everything above it was never closed,
        # so a unit in there is invisible to the outline — which is exactly how a
        # duplicated id used to slip past the collision check.
        for lost in self.stack[i + 1:]:
            self.unclosed.append((lost[2].uid if lost[2] else None, lost[0]))
        del self.stack[i:]
        if self.opaque is not None and self.opaque >= len(self.stack):
            self.opaque = None
        if frame[2]:
            self._emit(frame[2], frame[1], end)


    def close(self):
        super().close()
        for lost in self.stack:
            self.unclosed.append((lost[2].uid if lost[2] else None, lost[0]))
        self.stack = []


def _parse(text):
    p = _Outline(text)
    p.feed(text)
    p.close()
    return p


def html_units(text):
    return sorted(_parse(text).units, key=lambda u: u.start)


def md_units(text):
    """The `## ` sections, with md_body's own ids and its own fence rule."""
    m = md_body.FM.match(text)
    pos = m.end() if m else 0
    units, opened, fence = [], [], None
    off = pos
    for ln in text[pos:].split("\n"):
        fm = md_body.FENCE.match(ln)
        if fm and (fence is None or fm.group(1) == fence):
            fence = fm.group(1) if fence is None else None
        elif fence is None and ln.startswith("## "):
            if opened:
                opened[-1][2] = off
            opened.append([ln[3:].strip(), off, None])
        off += len(ln) + 1
    if opened:
        opened[-1][2] = len(text)
    seen = {}
    for n, (h2, start, end) in enumerate(opened, 1):
        units.append(Unit(md_body._slug(h2, n, seen), "section", h2, start, end, 0))
    return units


# ---------------------------------------------------------------------------


def sidecar_of(page):
    page = os.path.abspath(page)
    prev = os.path.join(os.path.dirname(page), ".aidex-artifact-prev")
    base = os.path.join(prev, os.path.basename(page))
    htm, md = base + ".body", base + ".body.md"
    have = [p for p in (htm, md) if os.path.isfile(p)]
    if len(have) == 2:
        die("two sidecars for this page — %s and %s. The wrap keeps one; remove the\n"
            "  one that is not the source of the page on disk before editing."
            % (htm, md))
    if not have:
        die("no body sidecar for %s.\n"
            "  Looked for %s and %s.\n"
            "  A page that predates the sidecar has none: carve its content out once\n"
            "  and wrap it with `wrap-report.sh --in <content> --out %s`, which writes\n"
            "  the sidecar. See references/02-local-first-artifacts.md § Update in\n"
            "  place, 'Revise the CONTENT, never the wrapped file'."
            % (page, htm, md, page))
    return have[0], have[0].endswith(".body.md")


def read_text(path):
    with open(path, "rb") as fh:
        return fh.read().decode("utf-8")


def units_of(path, is_md):
    text = read_text(path)
    return text, (md_units(text) if is_md else html_units(text))


def one_unit(units, uid, where):
    hit = [u for u in units if u.uid == uid]
    if not hit:
        known = ", ".join(u.uid for u in units) or "(none)"
        die("no unit '%s' in %s. Units there: %s" % (uid, where, known))
    if len(hit) > 1:
        die("'%s' appears %d times in %s (byte offsets %s) — refusing to guess which\n"
            "  one you mean. Ids are assigned once and never duplicated."
            % (uid, len(hit), where, ", ".join(str(u.start) for u in hit)))
    return hit[0]


def wrap_hint(page, sidecar):
    title, lang = os.path.basename(page), None
    if os.path.isfile(page):
        head = open(page, "rb").read(8192).decode("utf-8", "replace")
        m = re.search(r"<title[^>]*>(.*?)</title>", head, re.S | re.I)
        if m:
            title = " ".join(_html.unescape(m.group(1)).split())
        m = re.search(r"<html[^>]*\blang=[\"']([^\"']+)", head, re.I)
        if m:
            lang = m.group(1)
    cmd = [WRAP, "--title", title]
    if lang:
        cmd += ["--lang", lang]
    cmd += ["--in", sidecar, "--out", page]
    return " ".join(shlex.quote(c) for c in cmd)


# ---------------------------------------------------------------------------


def cmd_list(page):
    sidecar, is_md = sidecar_of(page)
    text, units = units_of(sidecar, is_md)
    total = len(text.encode("utf-8"))
    print("%s  (%d units, %d B)" % (sidecar, len(units), total))
    for u in units:
        size = len(u.source(text).encode("utf-8"))
        print("%s%s · %s · %d B · %s"
              % ("  " * u.depth, u.uid, u.kind, size, u.title or "—"))
    return 0


def cmd_get(page, uid):
    sidecar, is_md = sidecar_of(page)
    text, units = units_of(sidecar, is_md)
    src = one_unit(units, uid, sidecar).source(text)
    sys.stdout.write(src if src.endswith("\n") else src + "\n")
    return 0


def _label(uid, tag):
    return "<%s data-id=\"%s\">" % (tag, uid) if uid else "<%s>" % tag


def _check_html_replacement(new, uid):
    p = _parse(new)
    # Both of these parse into something a browser reads differently from the way
    # it is written, and both survived the wrap and the contract check.
    if p.self_closed:
        die("the replacement writes %s as self-closing. HTML ignores the slash on a\n"
            "  non-void element: it OPENS, and whatever follows becomes its content\n"
            "  instead of its sibling — the next round's outline, the composer and the\n"
            "  reader all see the swallowed item inside it, and the contract check\n"
            "  passes. Close the element. Nothing was written."
            % ", ".join(_label(i, t) for i, t in p.self_closed))
    if p.unclosed:
        die("the replacement leaves %s unclosed — the next close tag belongs to an\n"
            "  element further out, so everything after it lands inside this one. Close\n"
            "  it. (An id inside an unclosed element is invisible to this tool, which is\n"
            "  also how a duplicate of an id used elsewhere slips through.) Nothing was\n"
            "  written." % ", ".join(_label(i, t) for i, t in p.unclosed))
    units = sorted(p.units, key=lambda u: u.start)
    top = [u for u in units if u.depth == 0]
    if len(top) != 1:
        die("the replacement must be exactly one addressable element; found %d at its\n"
            "  outer level. Wrap it in the same element the unit had." % len(top))
    u = top[0]
    if u.uid != uid:
        die("the replacement's outer element carries '%s', not '%s'. Ids are assigned\n"
            "  once and never renumbered — fix the id, do not re-address the edit."
            % (u.uid, uid))
    if new[:u.start].strip() or new[u.end:].strip():
        die("the replacement has content outside its outer element; only that element\n"
            "  and surrounding whitespace may be in the file.")
    return new[u.start:u.end]


def cmd_put(page, uid, src_file):
    sidecar, is_md = sidecar_of(page)
    text, units = units_of(sidecar, is_md)
    unit = one_unit(units, uid, sidecar)
    new = read_text(src_file)

    old = unit.source(text)
    if is_md:
        core = old.rstrip("\r\n")
        tail = old[len(core):]
        piece = new.rstrip("\r\n") + tail
    else:
        piece = _check_html_replacement(new, uid)

    out = text[:unit.start] + piece + text[unit.end:]

    # Re-read the result the same way the page will. What must hold is that the id
    # addressed still names one unit and that no OTHER id was broken — never that
    # the outline has the same shape: a round that adds a question to a block, or
    # drops one from it, changes exactly that and is an ordinary revision.
    after = md_units(out) if is_md else html_units(out)
    moved = _outline_delta(units, after, uid, is_md)

    with open(sidecar, "wb") as fh:
        fh.write(out.encode("utf-8"))
    print("%s · %s · %d B -> %d B"
          % (sidecar, uid, len(old.encode("utf-8")), len(piece.encode("utf-8"))))
    if moved:
        print("nested: " + " ".join(moved))
    print("next: " + wrap_hint(os.path.abspath(page), sidecar))
    return 0


def _outline_delta(before, after, uid, is_md):
    """Refuse what the edit BREAKS; report what it merely moved.

    A markdown sidecar is the strict case and has to be: its ids are slugs of the
    headings in document order, so adding or dropping a `## ` re-slugs every
    section after it and silently renames ids the reader is already citing.
    """
    ids_before = [u.uid for u in before]
    ids_after = [u.uid for u in after]
    if is_md:
        if len(ids_after) != len(ids_before):
            die("the replacement changes the number of `## ` sections (%d -> %d), and\n"
                "  a markdown id is the slug of its heading in document order — every\n"
                "  section after this one would be renamed. Put one section at a time.\n"
                "  Nothing was written." % (len(ids_before), len(ids_after)))
        i = ids_before.index(uid)
        if ids_after[i] != uid:
            die("the replacement changes the unit's identity (%s -> %s): the heading is\n"
                "  what the id is made of, and ids are assigned once and never\n"
                "  renumbered. Nothing was written." % (uid, ids_after[i]))
        return []

    if ids_after.count(uid) != 1:
        die("the replacement leaves %d units answering to '%s'. Nothing was written."
            % (ids_after.count(uid), uid))
    dup_before = {i for i in ids_before if ids_before.count(i) > 1}
    stolen = sorted({i for i in ids_after
                     if ids_after.count(i) > 1 and i not in dup_before})
    if stolen:
        die("the replacement brings %s, which the sidecar already uses elsewhere —\n"
            "  an id names one claim and is assigned once (§ 8.1). Nothing was written."
            % ", ".join("'%s'" % i for i in stolen))
    added = [i for i in ids_after if i not in ids_before]
    removed = [i for i in ids_before if i not in ids_after]
    return ["+" + i for i in added] + ["-" + i for i in removed]


USAGE = """usage: artifact-item.sh list <page.html>
       artifact-item.sh get  <page.html> <id>
       artifact-item.sh put  <page.html> <id> <file>"""


def main(argv):
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    action, rest = argv[0], argv[1:]
    try:
        if action == "list" and len(rest) == 1:
            return cmd_list(rest[0])
        if action == "get" and len(rest) == 2:
            return cmd_get(*rest)
        if action == "put" and len(rest) == 3:
            return cmd_put(*rest)
    except FileNotFoundError as e:
        die("%s: %s" % (e.strerror, e.filename))
    except UnicodeDecodeError as e:
        die("not utf-8 text: %s" % e)
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
