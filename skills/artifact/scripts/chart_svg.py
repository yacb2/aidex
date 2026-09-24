#!/usr/bin/env python3
"""chart_svg.py — the `::: chart` body grammar and its stdlib SVG renderer.

Two halves, and they are separate on purpose:

  `parse_data()` reads the block's BODY — the data rows — and refuses every
  malformed one with `SpecSyntaxError` carrying the line INSIDE the fence. It
  reuses that exception type rather than inventing a second one (Phase 2's
  acceptance says so): an author fixing a chart row is fixing the same kind of
  thing they fix when a fence is malformed, and one error surface is what the
  whole spec API promises.

  `svg()` turns the parsed data into an SVG string. Pure string building on the
  stdlib — no vl-convert, no Vega-Lite, no matplotlib (decision d2). The
  geometry is fixed at the kit's page width; `figure svg { width: 100% }` in
  components.css does the rest, so there is no responsive or zoom logic here
  and none is wanted.

Where the LAYERS sit
--------------------
The tokenizer (`spec_parser.py`) knows shape only: to it a chart body is a
prose run like any other, and `03-spec-grammar.md` § Two layers says so in as
many words ("it does not know ... that a `chart` body must be a table. Those
are ... builder rules"). So the body grammar lives HERE, on the builder side,
and not in the tokenizer — putting it there would be the one change that file's
docstring forbids. What Phase 2's acceptance actually pins is the exception
TYPE and the line number, and both are kept.

Colour
------
Every series colour is `var(--sN)` for N in 1..8, straight out of `tokens.css`.
There is no literal hex in this file and there must never be one: the kit
defines those slots four times over (light, system dark, both explicit
toggles), and a hex here would be a fifth definition that only ever agrees with
one of them. `--s0` is the neutral "rest" fill and is not a series slot, so it
is not assigned by this file either.

tokens.css also says the slots are assigned in FIXED ORDER and never cycled:
"Past --s8 the answer is to fold into 'other' or facet, not to invent a ninth
hue." A ninth series is therefore REFUSED by the caller (`spec_build.py`), not
silently wrapped back onto `--s1` — two series sharing one colour is a chart
that lies, and it lies in the one place a reader cannot check.

Text
----
Everything that reaches the SVG goes through `esc()`, once, at the point of
emission — labels, series names, tick text, the caption. A label holding `<`,
`&` or a quote is DATA: it must not be able to close an attribute or open an
element. `_shell.esc` is `html.escape(quote=True)`, which covers both the
attribute and the text contexts this file writes.
"""

import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "dash"))
sys.path.insert(0, _HERE)
from _shell import esc                             # noqa: E402
from spec_parser import SpecSyntaxError            # noqa: E402

# The series slots of tokens.css. `--s0` is the neutral "rest" fill, not a
# series, so it is not in here.
SERIES_TOKENS = tuple("--s%d" % i for i in range(1, 9))
MAX_SERIES = len(SERIES_TOKENS)

KINDS = ("bar", "line", "stacked")

# A number this grammar accepts: an optional sign and decimal digits, with a
# POINT for the fraction. Deliberately narrower than `float()`:
#
#   `1e3`   — exponent notation in a data row is almost always a typo, and when
#             it is not, `1000` is what the axis will read anyway.
#   `NaN`, `inf`, `-inf` — `float()` takes all three and a chart cannot draw
#             any of them; they would come out as a bar of NaN pixels, which
#             browsers drop silently. That is the "renders a broken chart with
#             no error" outcome this phase exists to prevent.
#   `0x10`, `0b1`, `1_000` — Python literal spellings that are not data.
#   `1,5`   — the decimal comma. The corpus is Spanish pages, so this is the
#             most likely wrong value in the file; it gets its own hint below.
NUM = re.compile(r"^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$")
# A markdown separator row cell: `---`, `:--`, `--:`, `:-:`.
SEP_CELL = re.compile(r"^:?-+:?$")

# --- geometry, at the kit's page width ---------------------------------------
W, H = 720, 300
PAD_L, PAD_R, PAD_B = 64, 16, 44
PAD_T = 16
LEGEND_H = 24          # extra top room when a legend is drawn
TICK_SIZE = 11
LABEL_SIZE = 11
LEGEND_SIZE = 11
LEGEND_SWATCH = 10
# How much of its own share of the category slot a bar paints. The rest is the
# gap, split evenly on both sides, which is what keeps a bar centred over its
# label whatever the series count is.
BAR_FILL = 0.86


def _num(x):
    """A float as the shortest stable decimal string.

    Determinism: `repr()` of a float differs in its tail across inputs that
    should draw identically, and `-0.0` prints a minus sign for a value that is
    zero. Two decimals is finer than a pixel at this size.
    """
    v = round(float(x), 2)
    if v == 0:
        v = 0.0                                    # kills `-0.0`
    s = "%.2f" % v
    s = s.rstrip("0").rstrip(".")
    return s or "0"


def _text_width(label, size):
    """A deliberately GENEROUS width estimate, used only to space the legend.

    Over-estimating is the safe direction here: the cost is a wider gap, and
    the cost of under-estimating is two legend labels drawn on top of each
    other — which `check_artifact.py`'s `svg-text` check reports and a reader
    sees. This is not the checker's calibrated table and does not try to be.
    """
    return 0.62 * size * len(label)


# --- the body grammar ---------------------------------------------------------
def _cells_pipe(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def _is_separator(cells):
    return bool(cells) and all(SEP_CELL.match(c) for c in cells)


def _number(line_no, raw, column, stacked=False):
    """One cell as a float, or a refusal naming the line inside the fence."""
    if not raw:
        raise SpecSyntaxError(
            line_no,
            "column %d of this data row is empty — every value of a `chart` "
            "row is a number (a missing measurement is the row not being "
            "there, or a 0 written out)" % column)
    if not NUM.match(raw):
        hint = ""
        if "," in raw:
            hint = (" — a decimal COMMA is not a number here; write `%s`"
                    % raw.replace(",", ".", 1))
        elif raw.lower() in ("nan", "inf", "-inf", "+inf", "infinity"):
            hint = " — there is no bar to draw for it"
        elif re.match(r"^[+-]?\d", raw):
            hint = (" — digits, an optional sign and a decimal POINT only; no "
                    "exponent, no 0x, no thousands separator")
        raise SpecSyntaxError(
            line_no,
            "column %d of this data row is %r, which is not a number%s"
            % (column, raw, hint))
    value = float(raw)
    if stacked and value < 0:
        # A stacked bar lays its segments end to end and measures the bar on
        # its row's TOTAL scale: a negative segment would have to be laid
        # backwards over the ones before it, and the total at the bar's end
        # would stop being the bar's length. Refused, never drawn.
        raise SpecSyntaxError(
            line_no,
            "column %d of this data row is %s — a `stacked` bar is its "
            "segments laid end to end on the row's total scale, so a segment "
            "cannot be negative; draw signed values as type=bar"
            % (column, raw))
    return value


def parse_data(rows, kind=""):
    """`(labels, series)` from a chart body.

    `rows` is `[(line_no, text)]` — every physical body line with the SPEC line
    it came from, so a refusal names the offending line inside the fence and
    not the fence itself. `series` is `[(name, [float])]`, one entry per data
    column, in written order.

    Two accepted forms, chosen by the first non-blank line:

      `label,value`   one series, one row per line. There is no quoting: a
                      label with a comma in it is a table, not a CSV row, and
                      the refusal says so rather than guessing where the label
                      ends.

      a pipe table    `| Label | S1 | S2 |`, an optional separator row, then
                      the data rows. This is the multi-series form and the one
                      `04-block-vocabulary.md` shows.

    Blank lines are ignored anywhere. Mixing the two forms in one body is
    refused: the second form is never a continuation of the first, it is the
    author having changed their mind halfway down.

    `kind` matters for one rule only: a `stacked` chart refuses a negative
    cell, at its own line.
    """
    body = [(n, ln) for n, ln in rows if ln.strip()]
    if not body:
        # The caller checks this first and says it better (it knows the fence
        # line). Kept so a direct call cannot walk off the end of the list.
        raise SpecSyntaxError(rows[0][0] if rows else 0,
                              "a `chart` body has no data rows")

    stacked = kind == "stacked"
    pipe = body[0][1].strip().startswith("|")
    if pipe:
        return _parse_table(body, stacked)
    return _parse_csv(body, stacked)


def _parse_csv(body, stacked=False):
    labels, values = [], []
    for n, ln in body:
        if ln.strip().startswith("|"):
            raise SpecSyntaxError(
                n,
                "this body started as `label,value` rows and this line is a "
                "pipe table row — one form per chart; the table form is the "
                "one that carries more than one series")
        cells = [c.strip() for c in ln.split(",")]
        if len(cells) != 2:
            extra = ("a label containing a comma has to be written as a pipe "
                     "table, and so does a second series"
                     if len(cells) > 2 else
                     "a row is `label,value` — this one has no comma")
            raise SpecSyntaxError(
                n, "this data row has %d comma-separated field(s), not 2 — %s"
                   % (len(cells), extra))
        if not cells[0]:
            raise SpecSyntaxError(
                n, "this data row has an empty label — the label is what the "
                   "chart's axis says, so a row without one is unreadable")
        labels.append(cells[0])
        values.append(_number(n, cells[1], 2, stacked))
    # One unnamed series: there is no header row to name it, so the chart draws
    # no legend rather than inventing a name for it.
    return labels, [("", values)]


def _parse_table(body, stacked=False):
    head_n, head = body[0]
    names = _cells_pipe(head)
    if _is_separator(names):
        raise SpecSyntaxError(
            head_n, "the table starts with its separator row — the first row "
                    "of a `chart` table names the columns")
    ncols = len(names)
    if ncols < 2:
        raise SpecSyntaxError(
            head_n, "a `chart` table needs at least 2 columns (the label and "
                    "one series); this header row has %d" % ncols)
    if ncols - 1 > MAX_SERIES:
        # Said HERE as well as at the block level, because the header row is
        # the line the author edits.
        raise SpecSyntaxError(
            head_n,
            "this table has %d series columns and the kit has %d series "
            "tokens (--s1..--s8) — fold the rest into one 'other' column or "
            "split the chart" % (ncols - 1, MAX_SERIES))

    labels = []
    cols = [[] for _ in range(ncols - 1)]
    for n, ln in body[1:]:
        if not ln.strip().startswith("|"):
            raise SpecSyntaxError(
                n, "this body is a pipe table and this line is not a table "
                   "row — one form per chart")
        cells = _cells_pipe(ln)
        if _is_separator(cells):
            continue
        if len(cells) != ncols:
            raise SpecSyntaxError(
                n, "this row has %d cells and the header has %d — a `chart` "
                   "table is not ragged" % (len(cells), ncols))
        if not cells[0]:
            raise SpecSyntaxError(
                n, "this data row has an empty label — the label is what the "
                   "chart's axis says, so a row without one is unreadable")
        labels.append(cells[0])
        for i, raw in enumerate(cells[1:]):
            cols[i].append(_number(n, raw, i + 2, stacked))

    if not labels:
        raise SpecSyntaxError(
            head_n, "this `chart` table has a header row and no data rows")
    return labels, list(zip(names[1:], cols))


# --- the renderer -------------------------------------------------------------
def _domain(series):
    """`(lo, hi)`, the value range the plot is drawn against.

    ZERO IS ALWAYS IN IT. A bar is a length measured from the baseline, so a
    baseline that is not zero draws a bar three times another one for values of
    11 and 13; the same domain is used for `line` so that both kinds of one
    page read against the same axis.

    The two collapse cases are the ones that divide by zero if they are not
    named: every value exactly 0 (lo == hi == 0), and — because 0 is forced in
    — nothing else. A single row, all-equal values and all-negative values all
    come out of here with hi > lo already.
    """
    vals = [v for _name, col in series for v in col]
    lo = min([0.0] + vals)
    hi = max([0.0] + vals)
    if hi == lo:
        hi = lo + 1.0
    return lo, hi


def _ticks(lo, hi, unit):
    out = []
    for v in (hi, (lo + hi) / 2.0, lo):
        t = _num(v)
        out.append((v, t + (" " + unit if unit else "")))
    return out


def svg(kind, labels, series, unit=""):
    """The chart as one `<svg>` element.

    `series` is `[(name, [float])]`; every column is as long as `labels`, which
    is the caller's job (`parse_data` builds them together). At most
    `MAX_SERIES` columns — the caller refuses more, with the reason.
    """
    if kind not in KINDS:
        raise ValueError("unknown chart kind %r" % (kind,))
    if not labels:
        raise ValueError("a chart needs at least one data row")
    if len(series) > MAX_SERIES:
        raise ValueError("a chart has at most %d series" % MAX_SERIES)

    if kind == "stacked":
        return _stacked(labels, series, unit)

    x0, x1 = float(PAD_L), float(W - PAD_R)
    legend, legend_rows = _legend(series, x0, x1)
    top = PAD_T + LEGEND_H * legend_rows
    y0, y1 = float(top), float(H - PAD_B)
    lo, hi = _domain(series)

    def ypix(v):
        return y1 - (float(v) - lo) / (hi - lo) * (y1 - y0)

    n = len(labels)
    slot = (x1 - x0) / n
    zero = ypix(0.0)

    out = ['<svg viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg" '
           'role="img">' % (W, H)]

    # Axis furniture. `currentColor` rather than a literal: components.css sets
    # `figure svg { color: var(--ink) }`, so the rules and the text follow the
    # theme — which is also the only fill `check_artifact.py`'s contrast check
    # accepts without a literal background drawn under it.
    for v, text in _ticks(lo, hi, unit):
        y = ypix(v)
        out.append('  <line x1="%s" y1="%s" x2="%s" y2="%s" '
                   'stroke="currentColor" stroke-opacity="0.15"/>'
                   % (_num(x0), _num(y), _num(x1), _num(y)))
        out.append('  <text x="%s" y="%s" text-anchor="end" font-size="%d" '
                   'fill="currentColor" fill-opacity="0.7">%s</text>'
                   % (_num(x0 - 8), _num(y + 4), TICK_SIZE, esc(text)))
    # The zero rule is drawn solid on top of the tick grid whenever it is not
    # already one of the three ticks — with negative values in the data it is
    # the line every bar is measured from, and a reader cannot see which side
    # of nothing a bar is on without it.
    if lo < 0 < hi:
        out.append('  <line x1="%s" y1="%s" x2="%s" y2="%s" '
                   'stroke="currentColor" stroke-opacity="0.45"/>'
                   % (_num(x0), _num(zero), _num(x1), _num(zero)))

    out += legend

    if kind == "bar":
        out += _bars(labels, series, x0, slot, zero, ypix)
    else:
        out += _lines(labels, series, x0, slot, ypix)

    # The category axis, once, whatever the kind.
    for i, label in enumerate(labels):
        out.append('  <text x="%s" y="%s" text-anchor="middle" font-size="%d" '
                   'fill="currentColor" fill-opacity="0.7">%s</text>'
                   % (_num(x0 + (i + 0.5) * slot), _num(y1 + 16), LABEL_SIZE,
                      esc(label)))
    out.append("</svg>")
    return "\n".join(out)


def _legend(series, x0, x1):
    """`(elements, rows)`: the swatch-and-name legend, wrapped to the plot.

    Drawn only when there is more than one series and every one is named. An
    entry that would run past `x1` starts a new line `LEGEND_H` below — six
    long names on one line walked off the right of the viewBox. A legend that
    fits on one line is placed exactly as it always was.
    """
    names = [n for n, _c in series if n.strip()]
    if not (len(series) > 1 and len(names) == len(series)):
        return [], 0
    out, lx, ly, rows = [], x0, float(PAD_T), 1
    for i, (name, _col) in enumerate(series):
        step = LEGEND_SWATCH + 5 + _text_width(name, LEGEND_SIZE)
        if lx > x0 and lx + step > x1:
            lx, ly, rows = x0, ly + LEGEND_H, rows + 1
        out.append('  <rect x="%s" y="%s" width="%d" height="%d" '
                   'fill="var(%s)"/>'
                   % (_num(lx), _num(ly), LEGEND_SWATCH, LEGEND_SWATCH,
                      SERIES_TOKENS[i]))
        out.append('  <text x="%s" y="%s" font-size="%d" '
                   'fill="currentColor">%s</text>'
                   % (_num(lx + LEGEND_SWATCH + 5),
                      _num(ly + LEGEND_SWATCH - 1), LEGEND_SIZE, esc(name)))
        lx += step + 18
    return out, rows


# --- stacked: horizontal bars, one segment per series column ------------------
# A row is one bar, its label on the line above it and its TOTAL just past its
# end; the segments are the row's cells laid end to end in series order. The
# bar's length is the row's total against the longest row's total — its own
# scale, which is why a negative cell is refused at parse time. One series
# column is the plain horizontal bar chart. There is no value axis: every
# total is written out, and so is every segment wide enough to hold its
# number, in a row that has two or more segments (a lone segment's value IS
# the total). Text goes UNDER the bar in `currentColor`, never inside a
# segment: `--s2..--s5` sit below 3:1 against the light page, so neither ink
# nor paper is legible on every slot.
STACK_PAD_X = 16
STACK_LABEL_H = 16     # the row label's line, above the bar
STACK_BAR_H = 20
STACK_VALUE_H = 16     # the segment values' line, under the bar
STACK_GAP = 8
STACK_PITCH = STACK_LABEL_H + STACK_BAR_H + STACK_VALUE_H + STACK_GAP
VALUE_SIZE = 10
# The narrowest plot a stacked chart draws. The totals' text is reserved out of
# the kit's width, so a long enough `unit` left a negative plot and negative
# rect widths with no error; below this the caller refuses the chart.
MIN_STACK_PLOT = 200


def _stacked_totals(labels, series, unit):
    totals = [sum(col[i] for _n, col in series) for i in range(len(labels))]
    return totals, [_num(t) + (" " + unit if unit else "") for t in totals]


def stacked_plot_width(labels, series, unit):
    """The px left for the bars once the widest total has its room."""
    _totals, text = _stacked_totals(labels, series, unit)
    return (W - 2 * STACK_PAD_X
            - max(_text_width(t, TICK_SIZE) for t in text) - 6)


def _stacked(labels, series, unit):
    x0 = float(STACK_PAD_X)
    if stacked_plot_width(labels, series, unit) < MIN_STACK_PLOT:
        raise ValueError("the totals leave less than %d px for the bars"
                         % MIN_STACK_PLOT)
    legend, legend_rows = _legend(series, x0, float(W - STACK_PAD_X))
    top = PAD_T + LEGEND_H * legend_rows
    totals, total_text = _stacked_totals(labels, series, unit)
    # Room for the widest total past the end of the longest bar.
    x1 = x0 + stacked_plot_width(labels, series, unit)
    hi = max(totals) or 1.0            # every row zero: bars of width 0, no /0
    scale = (x1 - x0) / hi
    height = top + len(labels) * STACK_PITCH

    out = ['<svg viewBox="0 0 %d %s" xmlns="http://www.w3.org/2000/svg" '
           'role="img">' % (W, _num(height))]
    out += legend
    for r, label in enumerate(labels):
        ry = top + r * STACK_PITCH
        by = ry + STACK_LABEL_H
        out.append('  <text x="%s" y="%s" font-size="%d" '
                   'fill="currentColor">%s</text>'
                   % (_num(x0), _num(ry + 12), LABEL_SIZE, esc(label)))
        cells = [col[r] for _n, col in series]
        # A cell is labelled only if its two-decimal text is not "0": a
        # positive 0.004 prints as 0, which says the segment is not there.
        # `several` counts the same way, so a row of one real segment and a
        # few sub-precision ones still leaves its value to the total.
        several = sum(1 for v in cells if _num(v) != "0") > 1
        bx = x0
        for si, v in enumerate(cells):
            w = v * scale
            # A zero cell is a zero-width rect — the bar chart's rule for a
            # value of 0 — and never carries a number.
            out.append('  <rect x="%s" y="%s" width="%s" height="%d" '
                       'fill="var(%s)"/>'
                       % (_num(bx), _num(by), _num(w), STACK_BAR_H,
                          SERIES_TOKENS[si]))
            text = _num(v)
            if several and text != "0" and _text_width(text, VALUE_SIZE) <= w:
                out.append('  <text x="%s" y="%s" text-anchor="middle" '
                           'font-size="%d" fill="currentColor" '
                           'fill-opacity="0.7">%s</text>'
                           % (_num(bx + w / 2.0),
                              _num(by + STACK_BAR_H + 12), VALUE_SIZE,
                              esc(text)))
            bx += w
        out.append('  <text x="%s" y="%s" font-size="%d" '
                   'fill="currentColor">%s</text>'
                   % (_num(bx + 6), _num(by + STACK_BAR_H / 2.0 + 4),
                      TICK_SIZE, esc(total_text[r])))
    out.append("</svg>")
    return "\n".join(out)


def _bars(labels, series, x0, slot, zero, ypix):
    out = []
    group = slot * 0.7
    width = group / len(series)
    for si, (_name, col) in enumerate(series):
        token = SERIES_TOKENS[si]
        for i, v in enumerate(col):
            # The gap between bars comes off BOTH sides of each bar's share of
            # the group, not off the right side only: taking it off one side
            # walked every bar left of its own slot, and with a single series
            # (the common chart) that put the one bar 31 px left of the
            # category label under it.
            bx = (x0 + i * slot + (slot - group) / 2.0 + si * width
                  + width * (1 - BAR_FILL) / 2.0)
            y = ypix(v)
            # A value of exactly 0 draws a rect of height 0 — a legal element
            # the browser paints as nothing, which is the honest picture. It is
            # NOT bumped to a minimum height: a 1 px bar for a 0 is a chart
            # saying something the data does not.
            top, height = (min(y, zero), abs(y - zero))
            out.append('  <rect x="%s" y="%s" width="%s" height="%s" '
                       'fill="var(%s)"/>'
                       % (_num(bx), _num(top), _num(width * BAR_FILL),
                          _num(height), token))
    return out


def _lines(labels, series, x0, slot, ypix):
    out = []
    for si, (_name, col) in enumerate(series):
        token = SERIES_TOKENS[si]
        pts = [(x0 + (i + 0.5) * slot, ypix(v)) for i, v in enumerate(col)]
        # A `<polyline>` of ONE point renders nothing at all — the single-row
        # line chart was an empty box. The dots are emitted for every point, so
        # a one-point series is visible and a many-point one gains its markers;
        # the polyline stays because that is what a line chart is.
        out.append('  <polyline fill="none" stroke="var(%s)" stroke-width="2" '
                   'points="%s"/>'
                   % (token,
                      " ".join("%s,%s" % (_num(px), _num(py))
                               for px, py in pts)))
        for px, py in pts:
            out.append('  <circle cx="%s" cy="%s" r="3" fill="var(%s)"/>'
                       % (_num(px), _num(py), token))
    return out


def figure(kind, labels, series, title="", unit="", classes="", ident=""):
    """The whole block: the kit's `<figure>` with the chart and its caption.

    The title is the CAPTION, not a `<text>` inside the drawing. `figcaption`
    is already styled by components.css, it wraps at any page width, and one
    fewer text node inside the SVG is one fewer thing the `svg-text` geometry
    check has to place.
    """
    # The id is carried BYTE-EXACTLY (property 2 of spec_build.py) as `id=` and
    # NOTHING ELSE. No `data-id=`: that attribute is how `check_artifact.py`
    # recognises a consultation ITEM, so a chart carrying one was read as a
    # decision with no title, no reply surface and no notes box — eight
    # contract violations on a page with no questions in it at all.
    head = "<figure"
    if ident:
        head += ' id="%s"' % esc(ident)
    if classes:
        head += ' class="%s"' % esc(classes)
    out = [head + ">", svg(kind, labels, series, unit)]
    if title:
        out.append("<figcaption>%s</figcaption>" % esc(title))
    out.append("</figure>")
    return "\n".join(out)
