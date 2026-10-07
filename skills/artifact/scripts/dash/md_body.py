#!/usr/bin/env python3
"""Render the markdown a close-out already writes into an artifact-kit page body.

BL-345. A run's close-out emits durable markdown — `sweep-report.sh`'s companion
report, `plan-exec`'s `human-verification.md` — and nothing turned it into a
page, so the reader asked for the artifact every time. `wrap-report.sh` supplies
the envelope but consumes page CONTENT (styles and markup), and dash carried no
markdown renderer at all: "wrap the report" had no mechanism.

This is that mechanism and nothing more. The subset is what those two producers
emit — front matter, `#`/`##`/`###` and deeper, paragraphs, `-` and `1.` lists with
their indented continuation lines and sub-lists, pipe tables, `` `code` ``, `**bold**`,
`_italic_`. Anything richer belongs in the page's own author, not here: a general
markdown implementation is a dependency this repo does not have and a surface this
one caller does not need.

Only ONE of the two producers is script-generated. `human-verification.md` is
written by the session, in prose, and it is the input that found every gap this
renderer had: a numbered checklist joined into one run-on paragraph, a heading
level the subset did not name dropped without trace, a file with no `# ` title
rendering headless. So the rule is **degrade, never drop** — a construct outside
the subset comes out as readable text, because a renderer that silently deletes
its input is worse than one that renders it plainly, and the whole point of the
wrap is a page the reader finds MORE readable than the markdown, not less.

Two decisions that are load-bearing:

- **Everything is escaped before anything is emitted.** The rows carry backlog
  titles and proof cells, which are author-written text reaching this renderer
  verbatim. A `<` in one of them is data.
- **The output carries the kit's `.page` / `.main` structure**, because
  `check-artifact.sh` fails a kit-stamped page without it (BL-177) and a page
  without it renders full-bleed. Sections get ids and an `h2` so the composer's
  rail builds an index over them (`.main > section[id]`).

It emits no `data-id`, no reply surface and no copy bar: a report is read, not
answered, and any of those would drag it into the §8 consultation battery.
"""
import html as _html
import re

from _shell import esc

FM = re.compile(r"\A---\n.*?\n---\n?", re.S)
# The kit's static chrome, per page language: the one table the builders read
# for it (this module's `render`, `wrap_report.inject_rail`/`localize_chrome`,
# `spec_build.build`). Keys and values are composer.js's CHROME keys in its
# STRINGS.en/.es, in lockstep with it and with contract_defects.KIT_STRINGS
# (test-contract-defects.sh). A page read without JS (a static snapshot) shows
# this text as written, so the wrap writes it in the page's language at build
# time instead of leaving it to composer.js's relabel (LOOP-006
# ui-string-language).
CHROME = {
    "copy": {"en": "Copy my answers", "es": "Copiar mis respuestas"},
    "contents": {"en": "Contents", "es": "Contenido"},
    "notes": {"en": "Notes on this one", "es": "Notas sobre esta"},
    "choice": {"en": "The choice", "es": "La elección"},
    "value": {"en": "The value", "es": "El valor"},
    "general": {"en": "Anything that does not fit above",
                "es": "Cualquier cosa que no encaje arriba"},
    "notesPh": {"en": "Anything the options do not cover…",
                "es": "Cualquier cosa que las opciones no cubran…"},
    "listPh": {"en": "Anything the list does not cover…",
               "es": "Cualquier cosa que la lista no cubra…"},
    "valuePh": {"en": "Anything the value alone does not say…",
                "es": "Cualquier cosa que el valor por sí solo no diga…"},
    "generalPh": {"en": "Whatever it is…", "es": "Lo que sea…"},
    "pageNotes": {"en": "Notes for the whole page", "es": "Notas de la página"},
    "groupNotes": {"en": "Notes on this block", "es": "Notas de este bloque"},
    "groupNotesPh": {"en": "Anything about the block as a whole…",
                     "es": "Lo que afecta a todo el bloque…"},
}


def chrome(key, lang):
    """Kit string `key` for `lang` (a BCP-47 tag); English for a language the
    kit has no strings for, like the composer."""
    return CHROME[key].get((lang or "en")[:2].lower(), CHROME[key]["en"])


def railhead(lang):
    """The rail heading for `lang`."""
    return chrome("contents", lang)

# The OPENING backtick may not be escaped. The escape pass runs after this one
# (a backslash inside a code span is literal, per CommonMark), so without this
# guard `` \`0013\` `` still opened a span and shipped `\<code>0013</code>\.` —
# both backslashes visible and the backticks gone, which is the opposite of
# what the author asked for. Guarding the opening backtick is enough: a span
# needs a pair, so an escaped opener leaves its partner with nothing to close.
CODE = re.compile(r"(?<!\\)`([^`]+)`")
BOLD = re.compile(r"\*\*(.+?)\*\*")
ITAL = re.compile(r"(?<![\w*])[_*]([^_*\n]+)[_*](?![\w*])")
SEP_ROW = re.compile(r"^\|[\s:|-]+\|$")
# The PLAIN form of a label or verdict. What `data-label` carries is TEXT: the
# composer copies that attribute into the reply, so a backtick or a `**` written
# for the page's own rendering would travel into the paste as punctuation the
# reader never wrote. Backticks and asterisks only — `_` is stripped by NO rule
# here, because this module italicises it only in pairs and a label naming
# `a_file.py` must not come back as `afile.py`. spec_build (labels, `decide`)
# and wrap_report (the decided-round stamp, BL-545) compare in this form.
PLAIN = re.compile(r"[`*]")
# `-`/`*`/`+` and `1.`/`1)` both open a list item. ONE marker for both kinds, because
# the paragraph branch's guard has to exclude exactly what the list branch consumes:
# when the two drifted apart, `1.` fell through to the paragraph branch and a
# three-item human-verification checklist came out as one run-on <p>.
MARKER = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")
ORDERED = re.compile(r"^\s*\d+[.)]\s+")
# An ATX heading of any level. `render()` peels `# `/`## `/`### ` itself; anything
# deeper reaches `_blocks`, which used to advance past it and emit nothing at all.
HEADING = re.compile(r"^#{1,6}\s")
# A fenced block. It is the one construct that must NOT be read line by line: a
# ```bash run fell into the paragraph branch, so the fence LINES were joined with the
# code into one <p> and CODE paired the first backtick of the opening fence with the
# last of the closing one, wrapping the whole run in a bogus <code> span (BL-352).
# Group 1 is the MARKER, group 2 the language. A block closes only on its own marker:
# toggling on either one let a bare `~~~` line inside a ```-block close it, which
# emitted an EMPTY <pre>, leaked the code out as a paragraph, and left the section
# splitter's flag stuck on so every later `## ` heading vanished (branch review,
# 2026-09-08). The marker must be bare and alone on its line — a line with prose
# after it, or text before it, is content.
FENCE = re.compile(r"^\s*(```|~~~)\s*([A-Za-z0-9_+-]*)\s*$")
# What CLOSES an open fence is narrower than what opens one, by CommonMark: the
# opener's marker character, at least as long, at most 3 spaces deeper than the
# OPENER, and nothing after it. Reusing FENCE as the closer closed a block on a
# 4-space-indented marker or on a marker carrying an info string, so the next bare
# fence line OPENED a block and swallowed the real headings after it (BL-477
# review). The indent is relative to the opener, not to column 0, because a list
# item never contains a fence here (an indented fence ends the list): a fence written
# under a list item opens at the item's indent and closes at it, and a column-0 cap
# left every such block unclosed.
# Every tracker goes through `fence_closes` / `fence_state`, never FENCE, to close.
CLOSER = re.compile(r"^([ \t]*)(`{3,}|~{3,})[ \t]*$")


def fence_closes(line, opener):
    """True when `line` closes the fence whose OPENING line is `opener`."""
    c, o = CLOSER.match(line), FENCE.match(opener)
    if not c:
        return False
    indent = len(opener) - len(opener.lstrip())
    return (c.group(2)[0] == o.group(1)[0] and len(c.group(2)) >= len(o.group(1))
            and len(c.group(1)) <= indent + 3)


def fence_state(line, opener):
    """The open fence's opening line after `line`, given the one before it
    (None: outside any fence)."""
    if opener is None:
        return line if FENCE.match(line) else None
    return None if fence_closes(line, opener) else opener
# A bracketed inline span, `[text]{.pill .high}` — Pandoc's span syntax, the
# inline half of the `:::` fence grammar the page spec borrows
# (references/03-spec-grammar.md § Provenance). It exists for the two inline
# types the corpus repeats and `components.css` does not define, `pill` and
# `chip` (references/04-block-vocabulary.md), and it fires for NOTHING else:
# `[a]{.foo}` is left exactly as written. A general attribute-on-any-span would
# be a way to put arbitrary classes — and arbitrary markup — into report prose
# that reaches this renderer from backlog titles and proof cells.
SPAN = re.compile(r"\[([^\]\n]+)\]\{([^}\n]*)\}")
# A backslash escape for this renderer's OWN inline markers, and for nothing
# else: `\\`, `` \` ``, `\*`, `\_`, `\[`. Standard markdown, and the hole the
# corpus walked into — `.context/worklists/_archive/*-report.md`, written as
# plain prose, came out as `.context/worklists/archive/-report.md` with an
# `<em>` around the middle. Both the underscore and the asterisk were EATEN,
# silently, on a page `check-artifact` passes, and this function's own
# docstring already named that exact path as the thing backticks protect. A
# page that cannot write a filename without a monospace font it did not mean
# is a renderer missing its escape, not an author's mistake.
#
# Deliberately NOT escapable: `#`, `-`, `|`, `:::`. Those are BLOCK markers,
# read by `_blocks` a layer above this one, and an escape here would be read
# after they had already done their work.
ESCAPE = re.compile(r"\\([\\`*_\[])")
SPAN_TYPES = ("pill", "chip")
SPAN_CLASS = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
# The tones a `pill` or `chip` span may carry: the kit's styled ones plus every
# tone the spec corpus writes (2026-10-07). `spec_build` refuses a span whose
# tone is outside this set (`bad_spans`); the renderers here still pass any
# well-formed span through, so a backlog title is never refused.
SPAN_TONES = frozenset("""
acc chip-est chip-gate chip-id chip-kill chip-ready chip-stale chip--crit
chip--high chip--med chip--ok crit done flat ghost high info keep kill live
loc low med merge move ok orig s soft split stop wait warn watch xs
""".split())
SPAN_TAG = re.compile(r"\[([^\]\n]+)\]\{(\s*\.(?:pill|chip)\b[^}\n]*)\}")
# A right-aligned column in a pipe table's separator row (`---:`). Standard
# markdown alignment, read here as the `num` marker of the block vocabulary:
# right-aligned, `tabular-nums`. The kit did NOT style `.num` when this was
# written — the class was emitted and rendered as an ordinary cell, which is
# what `04-block-vocabulary.md § num` said was already handled and was not
# (kit v22 adds `th.num, td.num`). No new syntax was invented for the marker —
# the one an author already knows is the one that was missing a meaning here.
RIGHT_ALIGNED = re.compile(r"^-+:$")

# The stash sentinel of `_inline`. U+0000 cannot appear in the author's text
# (it is stripped on the way in) and cannot survive into the output (the
# restore loop below runs until none is left), so the two halves of that
# invariant are named here rather than spelled twice inside the function.
NUL = "\x00"
STASHED = re.compile(r"\x00(\d+)\x00")


# An inline link, `[text](target)`. The target may hold ONE level of balanced
# parentheses (`wiki/Ley_(física)`) and no whitespace. What becomes an `<a>`: a
# relative path, a `#fragment`, and the schemes in LINK_SCHEMES, none of which
# carries script. `http:` and `mailto:` are there because research notes wrapped
# from markdown use them (21 links in 10 of 9,242 fleet .md files, 2026-09-25).
# Every other scheme (`javascript:`, `data:`, `vbscript:`, `file:`), a
# protocol-relative `//host`, a backslash (read as `/` by the URL parser), a
# backslash escape and any control character (a leading one is stripped by the
# URL parser, so `\x01javascript:` would run) are refused. A refused link is
# rendered as plain text, `label (target)`: no href, and no `[x](y)` shape left
# for `check_artifact.py`'s `raw-link` check, so a markdown wrap still writes.
# `spec_build.py` refuses the same targets earlier, with the spec line.
LINK = re.compile(r"\[([^\]\n]+)\]\(((?:[^\s()]|\([^\s()]*\))+)\)")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
LINK_SCHEMES = ("https:", "http:", "mailto:")


def link_ok(target):
    """True when `target` may become an href: relative, #fragment or LINK_SCHEMES."""
    if any(ord(c) < 0x21 or ord(c) == 0x7F or c == "\\" for c in target):
        return False
    if target.startswith("//"):
        return False
    m = SCHEME.match(target)
    return not m or m.group(0).lower() in LINK_SCHEMES


def refused_links(text):
    """The link targets in one line of inline text that `_inline` refuses.

    The same tokenisation as `_inline`: code spans are taken out first, and a
    backslash escape becomes a NUL marker exactly as `_inline`'s stash does, so
    `\\[x](y)` is not a link and a target holding an escape (`a\\_b.html`) is
    refused here as it is there.
    """
    # NUL + the escaped character, so the target can be reported as written;
    # an escaped `[` stays out of LINK's reach as `\x01`, as the stash keeps it.
    text = ESCAPE.sub(lambda e: NUL + e.group(1).replace("[", "\x01"),
                      CODE.sub(" ", text.replace(NUL, "")))
    return [m.group(2).replace(NUL, "\\").replace("\x01", "[")
            for m in LINK.finditer(text) if not link_ok(m.group(2))]


def _span_classes(attr_text):
    """The class list of a bracketed span, or None when it is not one of ours.

    `.name` accumulates a class; a bare `tone=name` adds its value as a class,
    which is how `04-block-vocabulary.md` spells the second class of a `pill`
    or a `chip`. The text arrives ALREADY ESCAPED, so a quoted value would have
    become `&quot;` — quoting is not offered here, and a value that needs it is
    not a one-word tone.
    """
    classes = []
    for tok in attr_text.split():
        if tok.startswith(".") and SPAN_CLASS.match(tok[1:]):
            classes.append(tok[1:])
        elif tok.startswith("tone=") and SPAN_CLASS.match(tok[5:]):
            classes.append(tok[5:])
        else:
            return None
    if not classes or classes[0] not in SPAN_TYPES:
        return None
    return classes


def bad_spans(text):
    """`(type, token)` for each pill/chip span in one line whose tone is refused.

    Refused: a malformed tone (`{.pill .1x}`) or one outside SPAN_TONES. Code
    spans are skipped; `token` is the offending class as written.
    """
    out = []
    for m in SPAN_TAG.finditer(CODE.sub(" ", text)):
        toks = m.group(2).split()
        kind = toks[0][1:]
        classes = _span_classes(m.group(2))
        if classes is None:
            out.append((kind, next(
                (t for t in toks[1:] if not SPAN_CLASS.match(t.lstrip(".")[5 if t.startswith("tone=") else 0:])),
                m.group(2).strip())))
        else:
            out.extend((kind, c) for c in classes[1:] if c not in SPAN_TONES)
    return out


def _inline(text):
    """Inline spans, on already-escaped text.

    Code first and stashed: a path or a commit line inside backticks is literal,
    and letting `**` or `_` run over it is how `sweep-report.sh`'s own
    `_archive/<worklist>-report.md` would come out italicised in the middle.
    The bracketed `[x]{.pill}` span is stashed for the same reason — a tone with
    an underscore in it would otherwise be read as emphasis inside the class
    attribute this renderer just wrote.

    TWO INVARIANTS, both of them load-bearing and both tested:

    1. **No `NUL` reaches the output.** The stash marker is `\\x00<n>\\x00`, and
       a span STASHED INSIDE another stashed span (a code span in a pill label,
       the shape `[`T-12`]{.chip}` writes) leaves a marker inside the first
       stash's own text. A single `re.sub` replaced the outer marker and never
       rescanned its replacement, so the author's identifier was replaced by the
       stash INDEX between two literal U+0000 bytes — data loss, past a green
       `check-artifact`. The restore runs until nothing is left to restore, and
       any `NUL` the input itself carried is dropped before anything is stashed,
       so the sentinel can only ever be this function's own.
    2. **A stashed span's label is still markdown.** `[**bold**]{.pill}` used to
       ship its asterisks as literal text, because `SPAN.sub` ran before
       `BOLD.sub` and stashed content was never re-processed. The label is run
       through emphasis HERE, before it is stashed, which is the only place it
       can be done without exposing the class attribute to `ITAL`.
    """
    stash = []

    def keep(html):
        stash.append(html)
        return f"{NUL}{len(stash) - 1}{NUL}"

    def keep_code(m):
        return keep(f"<code>{m.group(1)}</code>")

    def keep_span(m):
        classes = _span_classes(m.group(2))
        if classes is None:
            return m.group(0)
        label = ITAL.sub(r"<em>\1</em>", BOLD.sub(r"<strong>\1</strong>",
                                                 m.group(1)))
        return keep(f'<span class="{" ".join(classes)}">{label}</span>')

    def keep_link(m):
        # The target arrives escaped (`&` is `&amp;`, `"` is `&quot;`), which is
        # what an attribute value needs. Tested on the UNESCAPED text, so an
        # entity cannot spell a scheme past the check.
        target = _html.unescape(m.group(2))
        label = ITAL.sub(r"<em>\1</em>", BOLD.sub(r"<strong>\1</strong>",
                                                 m.group(1)))
        if NUL in m.group(2) or not link_ok(target):
            return keep(f"{label} ({m.group(2)})")
        return keep(f'<a href="{m.group(2)}">{label}</a>')

    text = CODE.sub(keep_code, esc(text.replace(NUL, "")))
    # AFTER the code spans and BEFORE everything else. After, because a
    # backslash inside a code span is literal (CommonMark says so, and a path
    # in backticks is the one place an author means the backslash they typed).
    # Before, because the point is to stop `SPAN`, `BOLD` and `ITAL` from
    # seeing the character at all.
    # `\[` is kept as `&#91;`: the reader sees a bracket, and `check_artifact`'s
    # `raw-link` (which reads the source) does not take `\[x](y)` for a link the
    # builder failed to render.
    text = ESCAPE.sub(lambda m: keep("&#91;" if m.group(1) == "[" else m.group(1)),
                      text)
    text = SPAN.sub(keep_span, text)
    text = LINK.sub(keep_link, text)
    text = BOLD.sub(r"<strong>\1</strong>", text)
    text = ITAL.sub(r"<em>\1</em>", text)
    # Bounded by the stash: every pass resolves at least the outermost marker,
    # so `len(stash)` passes resolve a chain that is `len(stash)` deep, and a
    # marker that survives all of them cannot exist (nothing but `keep` writes
    # one). The guard is the bound, not a `while True`.
    for _ in range(len(stash)):
        if NUL not in text:
            break
        text = STASHED.sub(lambda m: stash[int(m.group(1))], text)
    return text


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _num_columns(sep_row):
    """Which columns a separator row marks right-aligned — the `num` columns."""
    return [bool(RIGHT_ALIGNED.match(c)) for c in _cells(sep_row)]


def _table(rows):
    """A pipe table inside the kit's scroll wrapper.

    `.tw` is not decoration: a table is the one element the page cannot cap, so
    an unwrapped wide one is drawn straight over the rail with no scrollbar —
    which `check-artifact.sh` fails.
    """
    has_sep = len(rows) > 1 and bool(SEP_ROW.match(rows[1]))
    head, body = rows[0], rows[2:] if has_sep else rows[1:]
    nums = _num_columns(rows[1]) if has_sep else []

    def cls(n):
        # A table with a ragged row is ordinary in a hand-written report, so the
        # marker is read by INDEX and a column the separator never described is
        # simply not a num column.
        return ' class="num"' if n < len(nums) and nums[n] else ""

    out = ['<div class="tw"><table>', "<thead><tr>"]
    out += [f"<th{cls(n)}>{_inline(c)}</th>" for n, c in enumerate(_cells(head))]
    out.append("</tr></thead><tbody>")
    for r in body:
        out.append("<tr>" + "".join(f"<td{cls(n)}>{_inline(c)}</td>"
                                    for n, c in enumerate(_cells(r))) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


# How deep a markdown list may nest. A sub-list is rendered by recursing, and a
# few hundred levels (fewer inside nested spec fences) hit Python's recursion
# limit (a RecursionError traceback, LOOP-008). Real lists nest 2-3 deep.
MAX_LIST_DEPTH = 50


class ListTooDeep(ValueError):
    """A list nested past MAX_LIST_DEPTH; the message says what to change."""


def _blocks(lines, depth=0):
    """Paragraph / list / table blocks from a run of body lines."""
    if depth > MAX_LIST_DEPTH:
        raise ListTooDeep("a markdown list nests %d levels deep — lists nest at "
                          "most %d deep; flatten the deeper levels"
                          % (depth, MAX_LIST_DEPTH))
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if not ln.strip():
            i += 1
        elif FENCE.match(ln):
            # Verbatim: escaped, but NOT run through _inline, or a `**` in a command
            # becomes markup. An unclosed fence takes the rest of the run rather than
            # falling back to paragraphs — degrade, never drop.
            opener = FENCE.match(ln)
            lang = opener.group(2)
            i += 1
            code = []
            while i < len(lines):
                if fence_closes(lines[i], ln):
                    break
                code.append(lines[i])
                i += 1
            i += 1  # the closing fence, or past the end
            cls = f' class="lang-{esc(lang)}"' if lang else ""
            out.append(f"<pre><code{cls}>" + esc("\n".join(code)) + "</code></pre>")
        elif ln.lstrip().startswith("|"):
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                rows.append(lines[i])
                i += 1
            out.append(_table(rows))
        elif MARKER.match(ln):
            # An INDENTED non-blank line after an item is that item's continuation and
            # is folded into it. Without this, adding `1.` to the marker alone would
            # move the defect rather than fix it: the wrapped second line of every
            # numbered item would fall out between the <li>s as an orphan <p>.
            # Indentation is required — an unindented line after a list is a new
            # paragraph far more often than it is a lazy continuation.
            # A marker indented DEEPER than the list's first marker opens a sub-list
            # of the item above, and every indented line after it is that sub-list's,
            # rendered by recursing into this branch (BL-568). Read as a sibling, it
            # renumbered point 4's a/b/c as points 5, 6, 7 on a graded page.
            tag = "ol" if ORDERED.match(ln) else "ul"
            base = len(ln) - len(ln.lstrip())
            items = []  # [text, the item's sub-list lines]
            while i < len(lines):
                cur = lines[i]
                deeper = len(cur) - len(cur.lstrip()) > base
                if MARKER.match(cur) and not deeper:
                    items.append([MARKER.sub("", cur, count=1).strip(), []])
                elif (items and cur.strip() and cur[:1].isspace()
                      and not cur.lstrip().startswith("|")
                      and not HEADING.match(cur.lstrip())
                      and not FENCE.match(cur)):
                    # An ordered marker opens a sub-list only when it counts from
                    # 1 (CommonMark's rule): `   25. Bulk-mark` is a wrapped line
                    # that happens to start with a number, not a nested list.
                    opens = (MARKER.match(cur) and deeper
                             and (not ORDERED.match(cur)
                                  or re.match(r"\s*1[.)]", cur)))
                    if items[-1][1] or opens:
                        items[-1][1].append(cur)
                    else:
                        items[-1][0] += " " + cur.strip()
                else:
                    break
                i += 1
            out.append(f"<{tag}>"
                       + "".join(f"<li>{_inline(x)}{''.join(_blocks(sub, depth + 1))}</li>"
                                 for x, sub in items)
                       + f"</{tag}>")
        elif HEADING.match(ln):
            # `####` and deeper, or a second `# `. Demoted to an h3 rather than
            # dropped: the rail indexes h2 only, so a deeper level has nowhere else to
            # go, and losing the line entirely is the one outcome the reader cannot
            # recover from — the page would be missing text the markdown had.
            out.append(f"<h3>{_inline(ln.lstrip('#').strip())}</h3>")
            i += 1
        else:
            para = []
            while i < len(lines) and lines[i].strip() \
                    and not lines[i].lstrip().startswith("|") \
                    and not MARKER.match(lines[i]) \
                    and not HEADING.match(lines[i]) \
                    and not FENCE.match(lines[i]):
                para.append(lines[i].strip())
                i += 1
            # Reached only on a non-blank line no branch above claimed, so the loop
            # always consumes at least one: there is no empty-paragraph case left to
            # skip past, and the arm that used to do it is what swallowed the headings.
            out.append(f"<p>{_inline(' '.join(para))}</p>")
    return out


def _slug(text, n, seen):
    """A section id, unique within the page.

    Two `## ` headings with the same text are ordinary in a report (`## Notes` under
    two items) and used to emit the same id twice, so the rail's second entry linked
    back to the first section.
    """
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    base = f"sec-{s[:40]}" if s else f"sec-{n}"
    seen[base] = seen.get(base, 0) + 1
    return base if seen[base] == 1 else f"{base}-{seen[base]}"


def render(md_text, title="", lang="en"):
    """The markdown as an artifact-kit page body (no doctype, no head).

    `title` is the fallback h1, for a report whose markdown carries no `# ` line.
    `human-verification.md` is exactly that shape and rendered headless — no on-page
    heading at all, and an empty rail — while the caller had the document title in
    hand the whole time. A `# ` in the markdown still wins over it. `lang` is the
    page's language, which the rail heading is written in.
    """
    lines = FM.sub("", md_text).split("\n")

    md_title, pre, sections, cur = "", [], [], None
    # Tracking the open fence is not an optimisation: a command that echoes markdown
    # ("grep '## '") would otherwise open a section from inside a code block and split it
    # in half. The OPENING LINE is remembered, not a boolean — see CLOSER above.
    fence_open = None
    for ln in lines:
        before, fence_open = fence_open, fence_state(ln, fence_open)
        if before is not None or fence_open is not None:
            (cur["body"] if cur is not None else pre).append(ln)
        elif ln.startswith("# ") and not md_title and cur is None:
            md_title = ln[2:].strip()
        elif ln.startswith("## "):
            cur = {"h2": ln[3:].strip(), "body": []}
            sections.append(cur)
        elif cur is None:
            pre.append(ln)
        else:
            cur["body"].append(ln)

    title = md_title or title.strip()

    out = ['<div class="page">', '<main class="main">']

    intro = _blocks(pre)
    if title or intro:
        out.append("<header>")
        if title:
            out.append(f"<h1>{_inline(title)}</h1>")
        if intro:
            # The first paragraph is the standfirst — the strongest thing the
            # report has to say, on the first screen, as the skeleton lays it out.
            out.append(intro[0].replace("<p>", '<p class="standfirst">', 1)
                       if intro[0].startswith("<p>") else intro[0])
            out += intro[1:]
        out.append("</header>")

    seen = {}
    for n, sec in enumerate(sections, 1):
        out.append(f'<section id="{esc(_slug(sec["h2"], n, seen))}">')
        out.append(f'<div class="sec-head"><h2>{_inline(sec["h2"])}</h2></div>')
        run = []
        # The same fence tracking as the splitter above: a `### ` line inside a
        # code block is data, and peeling it split the block in two (BL-477).
        fence_open = None
        for ln in sec["body"]:
            before, fence_open = fence_open, fence_state(ln, fence_open)
            if before is None and fence_open is None and ln.startswith("### "):
                out += _blocks(run)
                run = []
                out.append(f"<h3>{_inline(ln[4:].strip())}</h3>")
            else:
                run.append(ln)
        out += _blocks(run)
        out.append("</section>")

    out += ["</main>",
            '<aside class="rail">',
            f'<p class="railhead">{esc(railhead(lang))}</p>',
            '<nav class="raillist" id="raillist"></nav>',
            "</aside>",
            "</div>"]
    return "\n".join(out)


def fragment(md_text):
    """The markdown as a run of body-level blocks — no page, no sections, no rail.

    `render()` is the whole-document entry: it takes a report and returns the
    kit's `.page`/`.main` skeleton with a rail. A page SPEC needs the other half —
    the prose inside one `:::` block, or one run between two of them, rendered in
    place with whatever wrapper that block's emitter puts around it
    (`../spec_build.py`). Splitting a document into sections there would put a
    `<section>` inside a `.consult-item`.

    This is the same subset, the same escaping and the same `degrade, never drop`
    rule as `render()` — it is that function's block loop, exposed. There is no
    second renderer, by Q7 of the plan.
    """
    return "\n".join(blocks(md_text))


def blocks(md_text):
    """`fragment()` as a LIST of block-level fragments, in written order.

    A spec emitter needs the parts, not the join: `masthead` promotes the first
    paragraph to the standfirst and `item` promotes the first one to its `<h3>`,
    and a joined string cannot be split back — a fenced code block contains
    newlines of its own.
    """
    return _blocks(md_text.split("\n"))
