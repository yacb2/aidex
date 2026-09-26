#!/usr/bin/env python3
"""diagram_svg.py — the `::: diagram` renderer. A serialiser and nothing else.

Every number this file writes was decided by `diagram_layout.py`. That split is
the point: a layout is a thing you can assert about (a box's width, a route's
points, the ring's radius) without parsing markup, and a renderer you can read
in one sitting because it holds no arithmetic worth being wrong about.

Colour
------
Three classes and no fourth, straight out of `components.css`:

    figure svg .acc { color: var(--accent) }
    figure svg .flg { color: var(--flag) }
    figure svg .mut { color: var(--muted) }

and every shape is painted `currentColor`, so the class is what themes it and
the browser resolves it in light, dark and both explicit toggles alike. There
is NO literal hex in this file and there must never be one, for the reason
`chart_svg.py` gives about `--s1..--s8`: the kit defines these four times over
and a fifth definition here would agree with exactly one of them. There is also
no `fill="var(--accent)"` — `components.css` says in as many words that the
browser does not resolve a custom property in a presentation attribute and
falls back to black, which is invisible in dark mode.

What each class MEANS here, so the page is readable and not merely coloured:

    acc   a box. The thing the diagram is made of.
    mut   the arrows that go forward, the lane titles, the dividing rule, and
          the boxes of a `before-after`'s FIRST lane — the state being left.
    flg   an arrow that goes BACKWARD: the retry, the rejection, the edge that
          closes a ring. `--flag` is the kit's colour for exactly that, and a
          backward arrow drawn like a forward one is the one thing a reader of
          a flow diagram cannot recover from the picture.

Text
----
Labels are drawn in the kit's `--sans` token, set ONCE on the root as
`style="font-family:var(--sans)"`: a style attribute resolves a custom
property where a presentation attribute does not, so no font stack is copied
here. `diagram_layout.text_width` sizes every box for that font. The same
`style` caps the drawing at `MAX_SCALE` px per unit, so a short row is never
blown up to the column's width.

Two drawings, one figure
------------------------
When `diagram_layout.drawings` returns a narrow twin, the figure carries both
svgs (`dg-wide`, `dg-narrow`) and one `<style>` rule that shows the wide one
above 48rem and the narrow one at or under it. 48rem because the kit's column
there is at least 672 px, where a 720-unit drawing still draws 12-unit
sublabels at 11 px. The rule lives HERE, not in `components.css`, only because
the kit is another phase's file; it is `SWAP_CSS` and moves there verbatim.

Every label reaching the SVG goes through `esc()`, once, at the point of
emission — `_shell.esc` is `html.escape(quote=True)`. A box label is DATA and
must not be able to close an attribute or open an element.
"""

import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "dash"))
sys.path.insert(0, _HERE)
from _shell import esc                             # noqa: E402
import diagram_layout as dl                        # noqa: E402

HEAD_L = 9.0           # the arrowhead, from its tip back along the line
HEAD_A = 0.38          # half its opening, in radians
CORNER = 3.0           # the box's corner radius
STROKE = 1.5
# `graph_svg.py` still draws in the monospace stack and reads it from here.
# Byte-for-byte the `--mono` stack of `tokens.css`; the two are checked against
# each other by `test_diagram.py`, so this copy cannot drift silently.
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
SWAP_CSS = ("figure svg.dg-narrow{display:none}"
            "@media (max-width: 48rem){figure svg.dg-wide{display:none}"
            "figure svg.dg-narrow{display:block}}")


def _num(x):
    """A float as the shortest stable decimal string.

    The same function `chart_svg.py` carries, for the same reason: `repr()` of
    a float has a tail that differs between inputs that draw identically, and
    `-0.0` prints a minus sign for a value that is zero. Two decimals is finer
    than a pixel at this size, and it is what makes two builds byte-identical.
    """
    v = round(float(x), 2)
    if v == 0:
        v = 0.0
    s = "%.2f" % v
    s = s.rstrip("0").rstrip(".")
    return s or "0"


def _path(points):
    """`M`, then `L` per leg of a polyline, or `Q` for a 3-point quadratic."""
    d = "M %s,%s" % (_num(points[0][0]), _num(points[0][1]))
    if len(points) != 3:
        for x, y in points[1:]:
            d += " L %s,%s" % (_num(x), _num(y))
    else:
        d += " Q %s,%s %s,%s" % (_num(points[1][0]), _num(points[1][1]),
                                 _num(points[2][0]), _num(points[2][1]))
    return d


def _head(x, y, angle, tone):
    """The arrowhead as a filled triangle, pointing along `angle`.

    It is drawn BACKWARD from the tip, so it never reaches past the point the
    layout put it at and cannot push anything out of the viewBox.
    """
    back = angle + math.pi
    a = (x + HEAD_L * math.cos(back - HEAD_A),
         y + HEAD_L * math.sin(back - HEAD_A))
    b = (x + HEAD_L * math.cos(back + HEAD_A),
         y + HEAD_L * math.sin(back + HEAD_A))
    return ('  <path class="%s" d="M %s,%s L %s,%s L %s,%s Z" '
            'fill="currentColor"/>'
            % (tone, _num(x), _num(y), _num(a[0]), _num(a[1]),
               _num(b[0]), _num(b[1])))


def svg(lay, cls=""):
    """One `<svg>` element for a placed `diagram_layout.Layout`."""
    vx, vy, vw, vh = lay.view
    out = ['<svg%s viewBox="%s %s %s %s" xmlns="http://www.w3.org/2000/svg" '
           'role="img" style="font-family:var(--sans);max-width:%spx">'
           % (' class="%s"' % cls if cls else "", _num(vx), _num(vy),
              _num(vw), _num(vh), _num(vw * dl.MAX_SCALE))]

    if lay.divider:
        dx0, dy, dx1 = lay.divider
        out.append('  <line class="mut" x1="%s" y1="%s" x2="%s" y2="%s" '
                   'stroke="currentColor" stroke-opacity="0.5" '
                   'stroke-dasharray="4 4"/>'
                   % (_num(dx0), _num(dy), _num(dx1), _num(dy)))

    for text, tx, ty in lay.titles:
        out.append('  <text class="mut" x="%s" y="%s" font-size="%s" '
                   'fill="currentColor">%s</text>'
                   % (_num(tx), _num(ty), _num(dl.TITLE_FS), esc(text)))

    # The arrows first, so a box is painted over the line that reaches it and
    # not under it. Both are `currentColor` on a transparent box, so the order
    # only shows where the head meets the border — which is every arrow.
    for r in lay.routes:
        out.append('  <path class="%s" d="%s" fill="none" stroke="currentColor" '
                   'stroke-width="%s"/>' % (r.tone, _path(r.points),
                                            _num(STROKE)))
        tip = r.points[-1]
        out.append(_head(tip[0], tip[1], r.angle, r.tone))

    for b in lay.boxes:
        # A decision is a rounded box: its ends are half circles, of a
        # one- or two-line box's height at most, so a wrapped label in a tall
        # decision is not eaten by the curve.
        out.append('  <rect class="%s" x="%s" y="%s" width="%s" height="%s" '
                   'rx="%s" fill="none" stroke="currentColor" '
                   'stroke-width="%s"/>'
                   % (b.tone, _num(b.x), _num(b.y), _num(b.w), _num(b.h),
                      _num(min(b.h, dl.SUB_BOX_H) / 2.0 if b.decision
                           else CORNER), _num(STROKE)))
        # The label's lines, then the sublabel, as one block LINE_H apart and
        # centred on the box's middle; a lone line's baseline sits 0.35 em
        # below the middle, where a cap-height glyph reads as centred.
        # `check_artifact` measures a line from 0.8 em above its baseline to
        # 0.25 em below it (13.65 units at FS): every glyph box stays inside
        # the rect and apart from the next.
        rows = [(ln, dl.FS, "") for ln in b.lines]
        rows += [(sl, dl.SUB_FS, ' class="mut"') for sl in b.sub_lines]
        y = b.cy + 0.35 * dl.FS - (len(rows) - 1) * dl.LINE_H / 2.0
        for text, size, cls in rows:
            out.append('  <text%s x="%s" y="%s" text-anchor="middle" '
                       'font-size="%s" fill="currentColor">%s</text>'
                       % (cls, _num(b.cx), _num(y), _num(size), esc(text)))
            y += dl.LINE_H

    out.append("</svg>")
    return "\n".join(out)


def figure(lay, title="", classes="", ident="", narrow=None):
    """The whole block: the kit's `<figure>`, the diagram, and its caption.

    Identical plumbing to `chart_svg.figure`, including the one thing that is
    easy to get wrong: the id is carried byte-exactly as `id=` and NOTHING
    else. No `data-id=` — that attribute is how `check_artifact.py` recognises
    a consultation ITEM, and a figure wearing one is read as a decision with no
    title and no reply surface.
    """
    head = "<figure"
    if ident:
        head += ' id="%s"' % esc(ident)
    if classes:
        head += ' class="%s"' % esc(classes)
    if narrow is None:
        out = [head + ">", svg(lay)]
    else:
        out = [head + ">", "<style>%s</style>" % SWAP_CSS,
               svg(lay, "dg-wide"), svg(narrow, "dg-narrow")]
    if title:
        out.append("<figcaption>%s</figcaption>" % esc(title))
    out.append("</figure>")
    return "\n".join(out)
