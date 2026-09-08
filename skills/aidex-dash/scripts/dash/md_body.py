#!/usr/bin/env python3
"""Render the markdown a close-out already writes into an artifact-kit page body.

BL-345. A run's close-out emits durable markdown — `sweep-report.sh`'s companion
report, `aidex-plan-exec`'s `human-verification.md` — and nothing turned it into a
page, so the reader asked for the artifact every time. `wrap-report.sh` supplies
the envelope but consumes page CONTENT (styles and markup), and dash carried no
markdown renderer at all: "wrap the report" had no mechanism.

This is that mechanism and nothing more. The subset is exactly what those two
producers emit — front matter, `#`/`##`/`###`, paragraphs, `-` lists, pipe tables,
`` `code` ``, `**bold**`, `_italic_` — because the input is script-generated, not
arbitrary prose. Anything richer belongs in the page's own author, not here: a
general markdown implementation is a dependency this repo does not have and a
surface this one caller does not need.

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
        elif re.match(r"^\s*[-*+]\s+", ln):
            items = []
            while i < len(lines) and re.match(r"^\s*[-*+]\s+", lines[i]):
                items.append(_inline(re.sub(r"^\s*[-*+]\s+", "", lines[i])))
                i += 1
            out.append("<ul>" + "".join(f"<li>{t}</li>" for t in items) + "</ul>")
        else:
            para = []
            while i < len(lines) and lines[i].strip() \
                    and not lines[i].lstrip().startswith("|") \
                    and not re.match(r"^\s*[-*+]\s+", lines[i]) \
                    and not lines[i].startswith("#"):
                para.append(lines[i].strip())
                i += 1
            if para:
                out.append(f"<p>{_inline(' '.join(para))}</p>")
            else:                       # a heading inside a run: handled by the caller
                i += 1
    return out


def _slug(text, n):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return f"sec-{s[:40]}" if s else f"sec-{n}"


def render(md_text):
    """The markdown as an artifact-kit page body (no doctype, no head)."""
    lines = FM.sub("", md_text).split("\n")

    title, pre, sections, cur = "", [], [], None
    for ln in lines:
        if ln.startswith("# ") and not title and cur is None:
            title = ln[2:].strip()
        elif ln.startswith("## "):
            cur = {"h2": ln[3:].strip(), "body": []}
            sections.append(cur)
        elif cur is None:
            pre.append(ln)
        else:
            cur["body"].append(ln)

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

    for n, sec in enumerate(sections, 1):
        out.append(f'<section id="{esc(_slug(sec["h2"], n))}">')
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
