#!/usr/bin/env python3
"""Render the markdown a close-out already writes into an artifact-kit page body.

BL-345. A run's close-out emits durable markdown — `sweep-report.sh`'s companion
report, `aidex-plan-exec`'s `human-verification.md` — and nothing turned it into a
page, so the reader asked for the artifact every time. `wrap-report.sh` supplies
the envelope but consumes page CONTENT (styles and markup), and dash carried no
markdown renderer at all: "wrap the report" had no mechanism.

This is that mechanism and nothing more. The subset is what those two producers
emit — front matter, `#`/`##`/`###` and deeper, paragraphs, `-` and `1.` lists with
their indented continuation lines, pipe tables, `` `code` ``, `**bold**`,
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
import re

from _shell import esc

FM = re.compile(r"\A---\n.*?\n---\n?", re.S)
CODE = re.compile(r"`([^`]+)`")
BOLD = re.compile(r"\*\*(.+?)\*\*")
ITAL = re.compile(r"(?<![\w*])[_*]([^_*\n]+)[_*](?![\w*])")
SEP_ROW = re.compile(r"^\|[\s:|-]+\|$")
# `-`/`*`/`+` and `1.`/`1)` both open a list item. ONE marker for both kinds, because
# the paragraph branch's guard has to exclude exactly what the list branch consumes:
# when the two drifted apart, `1.` fell through to the paragraph branch and a
# three-item human-verification checklist came out as one run-on <p>.
MARKER = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+")
ORDERED = re.compile(r"^\s*\d+[.)]\s+")
# An ATX heading of any level. `render()` peels `# `/`## `/`### ` itself; anything
# deeper reaches `_blocks`, which used to advance past it and emit nothing at all.
HEADING = re.compile(r"^#{1,6}\s")


def _inline(text):
    """Inline spans, on already-escaped text.

    Code first and stashed: a path or a commit line inside backticks is literal,
    and letting `**` or `_` run over it is how `sweep-report.sh`'s own
    `_archive/<worklist>-report.md` would come out italicised in the middle.
    """
    stash = []

    def keep(m):
        stash.append(m.group(1))
        return f"\x00{len(stash) - 1}\x00"

    text = CODE.sub(keep, esc(text))
    text = BOLD.sub(r"<strong>\1</strong>", text)
    text = ITAL.sub(r"<em>\1</em>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: f"<code>{stash[int(m.group(1))]}</code>", text)


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _table(rows):
    """A pipe table inside the kit's scroll wrapper.

    `.tw` is not decoration: a table is the one element the page cannot cap, so
    an unwrapped wide one is drawn straight over the rail with no scrollbar —
    which `check-artifact.sh` fails.
    """
    head, body = rows[0], rows[2:] if len(rows) > 1 and SEP_ROW.match(rows[1]) else rows[1:]
    out = ['<div class="tw"><table>', "<thead><tr>"]
    out += [f"<th>{_inline(c)}</th>" for c in _cells(head)]
    out.append("</tr></thead><tbody>")
    for r in body:
        out.append("<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in _cells(r)) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


def _blocks(lines):
    """Paragraph / list / table blocks from a run of body lines."""
    out, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if not ln.strip():
            i += 1
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
            tag = "ol" if ORDERED.match(ln) else "ul"
            items = []
            while i < len(lines):
                cur = lines[i]
                if MARKER.match(cur):
                    items.append(MARKER.sub("", cur, count=1).strip())
                elif (items and cur.strip() and cur[:1].isspace()
                      and not cur.lstrip().startswith("|")
                      and not HEADING.match(cur.lstrip())):
                    items[-1] += " " + cur.strip()
                else:
                    break
                i += 1
            out.append(f"<{tag}>"
                       + "".join(f"<li>{_inline(x)}</li>" for x in items)
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
                    and not HEADING.match(lines[i]):
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


def render(md_text, title=""):
    """The markdown as an artifact-kit page body (no doctype, no head).

    `title` is the fallback h1, for a report whose markdown carries no `# ` line.
    `human-verification.md` is exactly that shape and rendered headless — no on-page
    heading at all, and an empty rail — while the caller had the document title in
    hand the whole time. A `# ` in the markdown still wins over it.
    """
    lines = FM.sub("", md_text).split("\n")

    md_title, pre, sections, cur = "", [], [], None
    for ln in lines:
        if ln.startswith("# ") and not md_title and cur is None:
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
        for ln in sec["body"]:
            if ln.startswith("### "):
                out += _blocks(run)
                run = []
                out.append(f"<h3>{_inline(ln[4:].strip())}</h3>")
            else:
                run.append(ln)
        out += _blocks(run)
        out.append("</section>")

    out += ["</main>",
            '<aside class="rail">',
            '<p class="railhead">Contents</p>',
            '<nav class="raillist" id="raillist"></nav>',
            "</aside>",
            "</div>"]
    return "\n".join(out)
