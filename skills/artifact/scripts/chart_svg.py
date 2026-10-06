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
  stdlib — no vl-convert, no Vega-Lite, no matplotlib (decision d2). The kit
  scales an svg to its column (`figure svg { width: 100% }`), and the column
  is 888 px at a 1280 px viewport and 294 px at 390: a factor of three that no
  single viewBox survives — 11-unit text in a 720-wide drawing reads 4.5 px on
  a phone, and a drawing narrow enough for 11 px there reads 33 px on a
  desktop. So `figure()` emits TWO renderings, a wide one (720 units, every
  text >= 11 units, so >= 11 px from a 720 px column up) and a narrow one (300
  units, text 12, so >= 11 px from a 275 px column up; bars become horizontal
  there, so a value label has a whole row to sit in), and a container query on
  the figure shows one of them. No minimum width anywhere: that is how a figure
  makes a page scroll sideways at 390 px.

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

import math
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
# The magnitudes a nonzero value may have. Past ~1.8e308 `float()` gives `inf`, and
# well before it the axis arithmetic does (a span of -x..x, a stacked total of 8
# series, the tick rounding up): an OverflowError. Below ~1e-308 the value is
# subnormal and the tick step divides by zero or takes log10(0): a
# ZeroDivisionError or ValueError. 1e-300..1e300 leaves that arithmetic orders of
# magnitude of headroom and refuses nothing a chart can mean.
MIN_ABS, MAX_ABS = 1e-300, 1e300
# A markdown separator row cell: `---`, `:--`, `--:`, `:-:`.
SEP_CELL = re.compile(r"^:?-+:?$")

# --- geometry, at the kit's page width ---------------------------------------
W = 720
PAD_EDGE = 8           # nothing is drawn closer than this to the viewBox edge
TICK_GAP = 8           # between a tick label's right end and the plot
PAD_R = 16
PAD_T = 16
LEGEND_H = 24          # extra top room when a legend is drawn
PLOT_H = 220
TICK_SIZE = 11
LABEL_SIZE = 11
LEGEND_SIZE = 11
LEGEND_SWATCH = 10
VALUE_SIZE = 11        # a bar's value label: 11, like every text of the wide svg
# How much of a category slot the bar group takes, and how much of its own share
# of the group a bar paints. The rest is the gap, split evenly on both sides,
# which is what keeps a bar centred over its label whatever the series count is.
BAR_GROUP = 0.8
BAR_FILL = 0.86
MINUS = "\u2212"


class _Geo(object):
    """One rendering's width and text sizes. `font` is every text but the value
    labels, `value` is those."""

    def __init__(self, w, font, value, legend_h, plot_h, cls):
        self.w, self.font, self.value = w, font, value
        self.legend_h, self.plot_h, self.cls = legend_h, plot_h, cls


WIDE = _Geo(W, TICK_SIZE, VALUE_SIZE, LEGEND_H, PLOT_H, "chart-w")
# 12 units in 300 is 11.76 px on the 294 px column of a 390 px viewport.
NARROW = _Geo(300, 12, 12, 22, 180, "chart-n")
# Below this container width the wide rendering's 11-unit text is under 11 px.
# The narrow one is capped so a tablet column does not blow its text up to 29 px.
CHART_CSS = ("<style>figure.chart { container-type: inline-size; }\n"
             "figure.chart > svg.chart-n { display: none; max-width: 26rem; }\n"
             "@container (width < %dpx) { figure.chart > svg.chart-w "
             "{ display: none; } figure.chart > svg.chart-n { display: block; } }"
             "</style>" % W)


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
    """A deliberately GENEROUS width estimate: it spaces the legend, sizes the
    left margin to the widest tick label, and decides when two value labels
    would touch.

    Over-estimating is the safe direction here: the cost is a wider gap (or a
    label moved out a line), and the cost of under-estimating is two labels
    drawn on top of each other — which `check_artifact.py`'s `svg-text` check reports and a reader
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
    if value and not MIN_ABS <= abs(value) <= MAX_ABS:
        raise SpecSyntaxError(
            line_no,
            "column %d of this data row is out of a chart's range — a value is "
            "0 or between %g and %g either side of 0; write it in another unit"
            % (column, MIN_ABS, MAX_ABS))
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
    """`(lo, hi)`, the value range of the data, with zero forced in.

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


def _nice_step(span, target=5):
    """The tick step: the smallest 1, 2 or 5 x 10^n that cuts `span` into at
    most about `target` intervals."""
    raw = span / float(target)
    mag = 10 ** math.floor(math.log10(raw))
    for m in (1, 2, 5, 10):
        if m * mag >= raw * (1 - 1e-9):
            return m * mag
    return 10 * mag                                 # unreachable: m=10 >= raw


def _clean(v, unit):
    """`v` without float noise, at a precision relative to `unit` (the half
    step): a fixed `round(v, 10)` collapsed a 3e-12 domain to 0..0."""
    v = round(v, max(0, -int(math.floor(math.log10(unit)))) + 3)
    return 0.0 if v == 0 else v


def _places(x):
    """The fewest decimals that write `x` exactly (0.25 needs 2, 3e-12 needs
    12). Relative tolerance: a fixed one wrote every tiny tick as `0`."""
    for d in range(0, 16):
        if abs(round(x, d) - x) <= 1e-9 * abs(x):
            return d
    return 15


def _scale(lo, hi, target=5):
    """`(d_lo, d_hi, ticks)`: the drawn domain and its tick values.

    Each end of the domain is the data's end rounded OUT to half a step, and
    labelled: -36.23 .. 272.87 at a step of 100 draws -50 .. 300, ticked at
    -50 / 0 / 100 / 200 / 300. Rounding to a whole step would give the 36 of
    negative data a 100 of room; not rounding at all is the arm-B chart, ticked
    at its own data extremes. Every inner tick is a multiple of the step, so 0
    is always a tick — and 0 is always in the domain, forced here as well as in
    `_domain`, so a direct call cannot lose it.
    """
    lo, hi = min(lo, 0.0), max(hi, 0.0)
    if hi == lo:
        hi = lo + 1.0
    step = _nice_step(hi - lo, target)
    # The ends round out to HALF a step only when the half is as round as the
    # step (100 -> 50, 0.2 -> 0.1); a step of 5 or 1 would put 12.5 or 1.5 at
    # the end and force a decimal onto an axis of integers.
    half = step / 2.0
    if _places(half) > _places(step):
        half = step
    d_lo = _clean(math.floor(lo / half + 1e-9) * half, half)
    d_hi = _clean(math.ceil(hi / half - 1e-9) * half, half)
    first = int(math.ceil(d_lo / step - 1e-9))
    last = int(math.floor(d_hi / step + 1e-9))
    ticks = set(_clean(k * step, half) for k in range(first, last + 1))
    return d_lo, d_hi, sorted(ticks | {d_lo, d_hi})


def _tick_text(ticks, lang, signed):
    """Each tick with its own fewest decimals: 0 / 0,5 / 1, never 1,0."""
    return [_fmt(t, _places(t), lang, signed) for t in ticks]


def _value_places(v):
    """A value label's decimals: the value's own precision, cut to two
    decimals or three significant digits, whichever is finer — 38.06 keeps 2,
    1/3 gets 2, 0.001 gets 3 instead of printing as 0, and -272 stays -272.
    Per value, not one count per chart: padding -272 to the 3 decimals of a
    0.004 beside it wrote `-272,000`, which a Spanish reader takes for two
    hundred seventy-two thousand. A nonzero value never prints `0`."""
    if v == 0:
        return 0
    sig = 2 - int(math.floor(math.log10(abs(v))))
    d = min(_places(v), max(2, sig))
    # A rounding carry leaves zeros the data never had (99.995 -> 100.00):
    # the decimals are the ROUNDED value's own.
    return min(d, _places(round(v, d)))


def _fmt(v, decimals, lang, signed):
    """A number the way the page writes it: a decimal COMMA on an `es` page, a
    point otherwise; U+2212 for minus; `+` on positives when `signed` (a
    mixed-sign chart, where the sign is what the reader compares). No thousands
    separator — `1.234` would read as one-point-two on a Spanish page.
    `decimals` None is the value's own (`_value_places`)."""
    if decimals is None:
        decimals = _value_places(float(v))
    r = round(float(v), decimals)
    if r == 0:
        return "0"
    text = "%.*f" % (decimals, abs(r))
    if lang == "es":
        text = text.replace(".", ",")
    return (MINUS if r < 0 else "+" if signed else "") + text


def _wrap(text, size, width):
    """`text` cut at spaces into lines no wider than `width` (by the generous
    estimate). A single word wider than the line is its own line."""
    lines, cur = [], ""
    per = max(1, int(width // _text_width("x", size)))
    words = []
    for word in text.split():
        # A word wider than the line is cut into line-sized pieces: a model id
        # or a URL has no space to break at, and it ran out of the viewBox.
        words += [word[k:k + per] for k in range(0, len(word), per)]
    for word in words:
        cand = (cur + " " + word).strip()
        if cur and _text_width(cand, size) > width:
            lines.append(cur)
            cur = word
        else:
            cur = cand
    return lines + ([cur] if cur else [])


def _overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def _text_el(x, y, size, text, anchor="", extra=""):
    return ('  <text x="%s" y="%s"%s font-size="%s"%s fill="currentColor">%s'
            '</text>' % (_num(x), _num(y),
                         ' text-anchor="%s"' % anchor if anchor else "",
                         _num(size), extra, esc(text)))


def _place_labels(cands, obstacles, bounds, size):
    """Value labels that never overlap. `cands` is
    `[(key, value, text, x, [baseline, ...], anchor)]`, the baselines in order
    of preference; `obstacles` are boxes `(x0, y0, x1, y1)` no label may cover
    (the bars, the points). Placed in order of |value|, biggest first, so when
    two labels contend the SMALLER one moves to its second baseline — the
    labels of one slot alternate — and, when that is taken too, is dropped:
    `{key: (x, baseline, anchor, text)}` holds the placed ones, and the caller
    puts a dropped one's text in its mark's `<title>`."""
    placed, boxes = {}, list(obstacles)
    for key, value, text, x, baselines, anchor in sorted(
            cands, key=lambda c: -abs(c[1])):
        w = _text_width(text, size)
        x0 = {"start": x, "middle": x - w / 2.0, "end": x - w}[anchor]
        for b in baselines:
            box = (x0, b - size, x0 + w, b)
            if (bounds[0] <= box[0] and box[2] <= bounds[2]
                    and bounds[1] <= box[1] and box[3] <= bounds[3]
                    and not any(_overlap(box, o) for o in boxes)):
                placed[key] = (x, b, anchor, text)
                boxes.append(box)
                break
    return placed


def _label_el(spot, size):
    x, b, anchor, text = spot
    return _text_el(x, b, size, text, anchor, ' class="val"')


def _tooltip(name, label, text):
    return "<title>%s</title>" % esc(
        "%s · %s: %s" % (name, label, text) if name else "%s: %s" % (label, text))


def svg(kind, labels, series, unit="", lang="es", show_labels=None,
        ytitle="", xtitle="", g=WIDE):
    """The chart as one `<svg>` element, or None for a narrow rendering that
    has no room (a stacked chart whose totals eat the 300 units).

    `series` is `[(name, [float])]`; every column is as long as `labels`, which
    is the caller's job (`parse_data` builds them together). At most
    `MAX_SERIES` columns — the caller refuses more, with the reason.
    `show_labels` None means the kind's default: on for bars, off for lines.
    """
    if kind not in KINDS:
        raise ValueError("unknown chart kind %r" % (kind,))
    if not labels:
        raise ValueError("a chart needs at least one data row")
    if len(series) > MAX_SERIES:
        raise ValueError("a chart has at most %d series" % MAX_SERIES)
    if show_labels is None:
        show_labels = kind == "bar"
    if kind == "stacked":
        return _stacked(labels, series, unit, g, lang)
    if kind == "bar" and g is NARROW:
        return _hbars(labels, series, unit, lang, show_labels, ytitle, xtitle, g)
    return _vertical(kind, labels, series, unit, lang, show_labels, ytitle,
                     xtitle, g)


def _titles_top(out, ytitle, g):
    """The value axis's title, wrapped, at the top left; returns the y under it.
    Horizontal, as F5 drew it: a rotated title is a line a reader turns their
    head for."""
    y = float(PAD_T)
    lines = _wrap(ytitle, g.font, g.w - 2 * PAD_EDGE)
    for line in lines:
        out.append(_text_el(PAD_EDGE, y + g.font, g.font, line,
                            extra=' fill-opacity="0.7"'))
        y += g.font + 4
    return y + (4 if lines else 0)


def _titles_bottom(out, xtitle, y, g):
    lines = _wrap(xtitle, g.font, g.w - 2 * PAD_EDGE)
    for line in lines:
        out.append(_text_el(g.w / 2.0, y + g.font, g.font, line, "middle",
                            ' fill-opacity="0.7"'))
        y += g.font + 4
    return y


def _open(g, height):
    return ['<svg class="%s" viewBox="0 0 %d %s" '
            'xmlns="http://www.w3.org/2000/svg" role="img">'
            % (g.cls, g.w, _num(height))]


def _vertical(kind, labels, series, unit, lang, show_labels, ytitle, xtitle,
              g):
    """Vertical bars or lines against a value axis on the left."""
    lo, hi = _domain(series)
    d_lo, d_hi, ticks = _scale(lo, hi)
    signed = lo < 0 < hi
    tick_text = [(t, x + (" " + unit if unit else ""))
                 for t, x in zip(ticks, _tick_text(ticks, lang, signed))]
    # The left margin is the widest tick label's own width: a fixed 64 cut
    # `272.87 USD` at the svg's edge on every arm-B chart.
    widest = max(_text_width(t, g.font) for _v, t in tick_text)
    x0, x1 = PAD_EDGE + widest + TICK_GAP, float(g.w - PAD_R)

    body = []
    top = _titles_top(body, ytitle, g)
    # The narrow rendering's legend takes the whole width: its plot starts
    # after the tick labels, and a long series name there had 190 units.
    legend, legend_rows = _legend(series, x0 if g is WIDE else float(PAD_EDGE),
                                  x1, top, g.font, g.legend_h)
    body += legend
    room = g.value + 6 if show_labels else 0
    y0 = top + g.legend_h * legend_rows + room
    y1 = y0 + g.plot_h

    def ypix(v):
        return y1 - (float(v) - d_lo) / (d_hi - d_lo) * (y1 - y0)

    n = len(labels)
    slot = (x1 - x0) / n
    zero = ypix(0.0)

    grid = []
    # Axis furniture. `currentColor` rather than a literal: components.css sets
    # `figure svg { color: var(--ink) }`, so the rules and the text follow the
    # theme — which is also the only fill `check_artifact.py`'s contrast check
    # accepts without a literal background drawn under it.
    for v, text in tick_text:
        y = ypix(v)
        grid.append('  <line x1="%s" y1="%s" x2="%s" y2="%s" '
                    'stroke="currentColor" stroke-opacity="0.15"/>'
                    % (_num(x0), _num(y), _num(x1), _num(y)))
        grid.append(_text_el(x0 - TICK_GAP, y + 4, g.font, text, "end",
                             ' fill-opacity="0.7"'))
    # The zero rule is drawn solid on top of the grid whenever the data has
    # both signs — it is the line every bar is measured from, and a reader
    # cannot see which side of nothing a bar is on without it.
    if lo < 0 < hi:
        grid.append('  <line x1="%s" y1="%s" x2="%s" y2="%s" '
                    'stroke="currentColor" stroke-opacity="0.45"/>'
                    % (_num(x0), _num(zero), _num(x1), _num(zero)))

    dec = None
    bounds = (x0, y0 - room, float(g.w), y1 + room)
    if kind == "bar":
        marks = _bars(labels, series, x0, slot, zero, ypix)
        cands = [((si, i), v, _fmt(v, dec, lang, signed), x + w / 2.0,
                  ([y - 4, y - 6 - g.value] if v >= 0 else
                   [y + h + 4 + g.value, y + h + 6 + 2 * g.value]), "middle")
                 for (si, i, v, x, y, w, h) in marks]
        obstacles = [(x, y, x + w, y + h) for (_s, _i, _v, x, y, w, h) in marks]
    else:
        marks = _points(series, x0, slot, ypix)
        cands = [((si, i), v, _fmt(v, dec, lang, signed), px,
                  [py - 6, py + 8 + g.value], "middle")
                 for (si, i, v, px, py) in marks]
        obstacles = [(px - 3, py - 3, px + 3, py + 3)
                     for (_s, _i, _v, px, py) in marks]
    placed = (_place_labels(cands, obstacles, bounds, g.value)
              if show_labels else {})
    # Every mark's <title> names its series, category and value, labelled or
    # not: a thinned category axis or a dropped label must never leave a bar
    # that nothing on the page names.
    tips = {c[0]: c[2] for c in cands}
    marks_out = (_bars_el(series, labels, marks, tips) if kind == "bar"
                 else _lines_el(series, labels, marks, tips))
    values = [_label_el(placed[k], g.value) for k in sorted(placed)]

    cat_y = y1 + room + g.font + 6
    cats, cat_lines = _categories(labels, x0, slot, cat_y, g)
    bottom = _titles_bottom(cats, xtitle,
                            cat_y + (cat_lines - 1) * (g.font + 4) + 8,
                            g) + PAD_EDGE
    return "\n".join(_open(g, bottom) + grid + body + marks_out + values
                     + cats + ["</svg>"])


def _categories(labels, x0, slot, y, g):
    """`(elements, lines)`: the category axis, once, whatever the kind.

    A label wider than its slot wraps at its spaces, up to three lines, when
    every word fits the slot — or when the slot holds at least eight
    characters, so a word too long for it (a URL) is cut into pieces rather
    than thinned away. Otherwise only every k-th label is written, and
    always the first and the LAST (the one before the last yields when the two
    would touch): a line chart of twelve months that ended its axis at
    October read as a year that stopped there."""
    n, room = len(labels), slot - 4
    wrapped = [_wrap(lb, g.font, room) or [lb] for lb in labels]
    cuttable = room >= _text_width("x" * 8, g.font)
    if all(len(ls) <= 3 and (cuttable or all(_text_width(w, g.font) <= room
                                             for w in lb.split()))
           for lb, ls in zip(labels, wrapped)):
        keep, lines = set(range(n)), wrapped
    else:
        widest = max(_text_width(lb, g.font) for lb in labels)
        step = 1
        while step < n and widest > step * slot - 4:
            step += 1
        keep = set(i for i in range(n) if i % step == 0)
        if n - 1 not in keep:
            prev = max(keep)
            if (n - 1 - prev) * slot < widest + 4 and prev != 0:
                keep.discard(prev)
            if (n - 1 - max(keep)) * slot >= widest + 4:
                keep.add(n - 1)
        # A kept label wider than the whole plot is cut like any other line.
        lines = [_wrap(lb, g.font, step * slot - 4) or [lb] for lb in labels]
    out = []
    for i in sorted(keep):
        for k, line in enumerate(lines[i]):
            # Centred on its slot, but never past the viewBox: a thinned label
            # may be wider than its own slot, and the first and last slots
            # sit next to the edges.
            half = _text_width(line, g.font) / 2.0
            cx = min(max(x0 + (i + 0.5) * slot, PAD_EDGE + half),
                     g.w - PAD_EDGE - half)
            out.append(_text_el(cx, y + k * (g.font + 4), g.font, line,
                                "middle", ' fill-opacity="0.7"'))
    return out, max(len(lines[i]) for i in keep)


def _legend(series, x0, x1, y=PAD_T, size=LEGEND_SIZE, row_h=LEGEND_H):
    """`(elements, rows)`: the swatch-and-name legend, wrapped to the plot.

    Drawn only when there is more than one series and every one is named. An
    entry that would run past `x1` starts a new line `row_h` below — six
    long names on one line walked off the right of the viewBox. A legend that
    fits on one line is placed exactly as it always was.
    """
    names = [n for n, _c in series if n.strip()]
    if not (len(series) > 1 and len(names) == len(series)):
        return [], 0
    out, lx, ly, rows = [], x0, float(y), 1
    room = x1 - x0 - LEGEND_SWATCH - 5
    for i, (name, _col) in enumerate(series):
        # A name wider than the whole legend line wraps under its swatch and
        # takes the rows its lines need; one that fits is one line, as before.
        lines = (_wrap(name, size, room) or [name]
                 if _text_width(name, size) > room else [name])
        step = LEGEND_SWATCH + 5 + max(_text_width(t, size) for t in lines)
        if lx > x0 and lx + step > x1:
            lx, ly, rows = x0, ly + row_h, rows + 1
        out.append('  <rect x="%s" y="%s" width="%d" height="%d" '
                   'fill="var(%s)"/>'
                   % (_num(lx), _num(ly), LEGEND_SWATCH, LEGEND_SWATCH,
                      SERIES_TOKENS[i]))
        for k, line in enumerate(lines):
            out.append('  <text x="%s" y="%s" font-size="%s" '
                       'fill="currentColor">%s</text>'
                       % (_num(lx + LEGEND_SWATCH + 5),
                          _num(ly + LEGEND_SWATCH - 1 + k * (size + 4)),
                          _num(size), esc(line)))
        lx += step + 18
        if len(lines) > 1:
            extra = int(math.ceil((len(lines) - 1) * (size + 4) / float(row_h)))
            lx, ly, rows = x1, ly + extra * row_h, rows + extra
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
# The narrowest plot a stacked chart draws. The totals' text is reserved out of
# the kit's width, so a long enough `unit` left a negative plot and negative
# rect widths with no error; below this the caller refuses the chart. The
# narrow rendering has its own, smaller floor: under it the figure carries the
# wide rendering only.
MIN_STACK_PLOT = 200
MIN_STACK_PLOT_NARROW = 120


def _stacked_totals(labels, series, unit, lang="en"):
    """`(totals, their text, decimals)`: the totals written the page's way,
    each with its own decimals (`_value_places`)."""
    totals = [sum(col[i] for _n, col in series) for i in range(len(labels))]
    dec = None
    return totals, [_fmt(t, dec, lang, False) + (" " + unit if unit else "")
                    for t in totals], dec


def stacked_plot_width(labels, series, unit, g=WIDE):
    """The px left for the bars once the widest total has its room (a comma
    and a point are one character each, so the language does not move it)."""
    _totals, text, _dec = _stacked_totals(labels, series, unit)
    return (g.w - 2 * STACK_PAD_X
            - max(_text_width(t, g.font) for t in text) - 6)


def _stacked(labels, series, unit, g=WIDE, lang="en"):
    x0 = float(STACK_PAD_X)
    floor = MIN_STACK_PLOT if g is WIDE else MIN_STACK_PLOT_NARROW
    if stacked_plot_width(labels, series, unit, g) < floor:
        if g is not WIDE:
            return None
        raise ValueError("the totals leave less than %d px for the bars"
                         % MIN_STACK_PLOT)
    legend, legend_rows = _legend(series, x0, float(g.w - STACK_PAD_X),
                                  PAD_T, g.font, g.legend_h)
    top = PAD_T + g.legend_h * legend_rows
    totals, total_text, dec = _stacked_totals(labels, series, unit, lang)
    # Room for the widest total past the end of the longest bar.
    x1 = x0 + stacked_plot_width(labels, series, unit, g)
    hi = max(totals) or 1.0            # every row zero: bars of width 0, no /0
    scale = (x1 - x0) / hi
    # A row label wider than the drawing wraps, one more label line per line:
    # on the 300-unit rendering a 45-character label ran out of the viewBox.
    heads = [_wrap(label, g.font, g.w - 2 * STACK_PAD_X) or [label]
             for label in labels]
    height = top + sum(STACK_PITCH + (len(h) - 1) * STACK_LABEL_H
                       for h in heads)

    out = _open(g, height)
    out += legend
    ry = top
    for r, _label in enumerate(labels):
        for k, line in enumerate(heads[r]):
            out.append(_text_el(x0, ry + 12 + k * STACK_LABEL_H, g.font, line))
        ry += (len(heads[r]) - 1) * STACK_LABEL_H
        by = ry + STACK_LABEL_H
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
            text = _fmt(v, dec, lang, False)
            if (several and _num(v) != "0"
                    and _text_width(text, g.value) <= w):
                out.append(_text_el(bx + w / 2.0, by + STACK_BAR_H + 12,
                                    g.value, text, "middle",
                                    ' class="val" fill-opacity="0.7"'))
            bx += w
        out.append(_text_el(bx + 6, by + STACK_BAR_H / 2.0 + 4, g.font,
                            total_text[r]))
        ry += STACK_PITCH
    out.append("</svg>")
    return "\n".join(out)


def _bars(labels, series, x0, slot, zero, ypix):
    """Every bar's geometry: `[(si, i, v, x, y, width, height)]`."""
    out = []
    group = slot * BAR_GROUP
    width = group / len(series)
    for si, (_name, col) in enumerate(series):
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
            out.append((si, i, v, bx, min(y, zero), width * BAR_FILL,
                        abs(y - zero)))
    return out


def _bars_el(series, labels, marks, tips):
    out = []
    for si, i, _v, x, y, w, h in marks:
        out.append('  <rect x="%s" y="%s" width="%s" height="%s" '
                   'fill="var(%s)">%s</rect>'
                   % (_num(x), _num(y), _num(w), _num(h), SERIES_TOKENS[si],
                      _tooltip(series[si][0], labels[i], tips[(si, i)])))
    return out


def _points(series, x0, slot, ypix):
    return [(si, i, v, x0 + (i + 0.5) * slot, ypix(v))
            for si, (_n, col) in enumerate(series) for i, v in enumerate(col)]


def _lines_el(series, labels, marks, tips):
    out = []
    for si, (_name, _col) in enumerate(series):
        token = SERIES_TOKENS[si]
        pts = [(px, py, i) for (s_, i, _v, px, py) in marks if s_ == si]
        # A `<polyline>` of ONE point renders nothing at all — the single-row
        # line chart was an empty box. The dots are emitted for every point, so
        # a one-point series is visible and a many-point one gains its markers;
        # the polyline stays because that is what a line chart is.
        out.append('  <polyline fill="none" stroke="var(%s)" stroke-width="2" '
                   'points="%s"/>'
                   % (token, " ".join("%s,%s" % (_num(px), _num(py))
                                      for px, py, _i in pts)))
        for px, py, i in pts:
            out.append('  <circle cx="%s" cy="%s" r="3" fill="var(%s)">%s'
                       '</circle>' % (_num(px), _num(py), token,
                                      _tooltip(series[si][0], labels[i],
                                               tips[(si, i)])))
    return out


# --- the narrow rendering of a bar chart: horizontal bars ----------------------
NARROW_BAR_H = 12
NARROW_BAR_GAP = 4


def _hbars(labels, series, unit, lang, show_labels, ytitle, xtitle, g):
    """One row per bar, grouped under its category's label, the value axis
    horizontal and ticked below. A value label sits past its bar's end on the
    bar's own row — right of a positive bar, left of a negative one — so no two
    labels can share a line, however many series there are."""
    lo, hi = _domain(series)
    d_lo, d_hi, ticks = _scale(lo, hi, target=4)
    signed = lo < 0 < hi
    dec = None
    # The unit rides on the last tick only: the ticks share one 300-unit line,
    # and "+100 USD" four times over is what pushed them into each other.
    tick_text = [(t, x + (" " + unit if unit and t == ticks[-1] else ""))
                 for t, x in zip(ticks, _tick_text(ticks, lang, signed))]
    text = {(si, i): _fmt(v, dec, lang, signed)
            for si, (_n, col) in enumerate(series) for i, v in enumerate(col)}
    neg = [_text_width(text[(si, i)], g.value)
           for si, (_n, col) in enumerate(series)
           for i, v in enumerate(col) if v < 0] if show_labels else []
    pos = [_text_width(text[(si, i)], g.value)
           for si, (_n, col) in enumerate(series)
           for i, v in enumerate(col) if v >= 0] if show_labels else []
    half_first = _text_width(tick_text[0][1], g.font) / 2.0
    half_last = _text_width(tick_text[-1][1], g.font) / 2.0
    x0 = PAD_EDGE + max([half_first] + [w + 4 for w in neg])
    x1 = g.w - PAD_EDGE - max([half_last] + [w + 4 for w in pos])

    def xpix(v):
        return x0 + (float(v) - d_lo) / (d_hi - d_lo) * (x1 - x0)

    zero = xpix(0.0)
    out = []
    y = _titles_top(out, ytitle, g)
    legend, rows = _legend(series, float(PAD_EDGE), float(g.w - PAD_EDGE), y,
                           g.font, g.legend_h)
    out += legend
    y += g.legend_h * rows
    grid_top = y
    marks, values = [], []
    for i, label in enumerate(labels):
        for line in _wrap(label, g.font, g.w - 2 * PAD_EDGE):
            marks.append(_text_el(PAD_EDGE, y + g.font, g.font, line))
            y += g.font + 4
        for si, (name, col) in enumerate(series):
            v = col[i]
            end = xpix(v)
            rect = ('  <rect x="%s" y="%s" width="%s" height="%d" '
                    'fill="var(%s)">%s</rect>'
                    % (_num(min(zero, end)), _num(y), _num(abs(end - zero)),
                       NARROW_BAR_H, SERIES_TOKENS[si],
                       _tooltip(name, label, text[(si, i)])))
            marks.append(rect)
            if show_labels:
                base = y + NARROW_BAR_H / 2.0 + g.value * 0.35
                if v >= 0:
                    values.append(_label_el((end + 4, base, "start",
                                             text[(si, i)]), g.value))
                else:
                    values.append(_label_el((end - 4, base, "end",
                                             text[(si, i)]), g.value))
            y += NARROW_BAR_H + NARROW_BAR_GAP
        y += 6
    grid_bottom = y
    grid = []
    for v, _t in tick_text:
        grid.append('  <line x1="%s" y1="%s" x2="%s" y2="%s" '
                    'stroke="currentColor" stroke-opacity="0.15"/>'
                    % (_num(xpix(v)), _num(grid_top), _num(xpix(v)),
                       _num(grid_bottom)))
    if lo < 0 < hi:
        grid.append('  <line x1="%s" y1="%s" x2="%s" y2="%s" '
                    'stroke="currentColor" stroke-opacity="0.45"/>'
                    % (_num(zero), _num(grid_top), _num(zero),
                       _num(grid_bottom)))
    # Tick labels share one line, so the ones that would touch are dropped:
    # zero first, then the biggest magnitudes. The gridlines stay.
    tick_y = grid_bottom + g.font + 2
    kept, unit_kept = [], False
    for v, t in sorted(tick_text, key=lambda vt: (vt[0] != 0, -abs(vt[0]))):
        w = _text_width(t, g.font)
        box = (xpix(v) - w / 2.0 - 3, 0, xpix(v) + w / 2.0 + 3, 1)
        if not any(_overlap(box, k) for k in kept):
            kept.append(box)
            unit_kept = unit_kept or v == ticks[-1]
            grid.append(_text_el(xpix(v), tick_y, g.font, t, "middle",
                                 ' fill-opacity="0.7"'))
    # The tick carrying the unit can be the one that yields; the unit then
    # gets a line of its own under the axis's right end, never nothing.
    if unit and not unit_kept:
        tick_y += g.font + 4
        grid.append(_text_el(g.w - PAD_EDGE, tick_y, g.font, unit, "end",
                             ' fill-opacity="0.7"'))
    bottom = _titles_bottom(grid, xtitle, tick_y + 8, g) + PAD_EDGE
    return "\n".join(_open(g, bottom) + out + grid + marks + values
                     + ["</svg>"])


def figure(kind, labels, series, title="", unit="", classes="", ident="",
           lang="es", show_labels=None, ytitle="", xtitle=""):
    """The whole block: the kit's `<figure>` with the chart and its caption.

    The title is the CAPTION, not a `<text>` inside the drawing. `figcaption`
    is already styled by components.css, it wraps at any page width, and one
    fewer text node inside the SVG is one fewer thing the `svg-text` geometry
    check has to place.

    Two renderings and the rule that picks one (module docstring). The rule
    travels with the figure rather than living in components.css: the kit is
    another phase's file, and a figure whose narrow rendering is shown by a
    stylesheet it does not carry is a figure that draws twice.
    """
    # The id is carried BYTE-EXACTLY (property 2 of spec_build.py) as `id=` and
    # NOTHING ELSE. No `data-id=`: that attribute is how `check_artifact.py`
    # recognises a consultation ITEM, so a chart carrying one was read as a
    # decision with no title, no reply surface and no notes box — eight
    # contract violations on a page with no questions in it at all.
    kw = dict(lang=lang, show_labels=show_labels, ytitle=ytitle, xtitle=xtitle)
    wide = svg(kind, labels, series, unit, g=WIDE, **kw)
    narrow = svg(kind, labels, series, unit, g=NARROW, **kw)
    head = "<figure"
    if ident:
        head += ' id="%s"' % esc(ident)
    head += ' class="%s"' % esc(("chart " + classes).strip())
    out = [head + ">"]
    if narrow:
        out += [CHART_CSS, wide, narrow]
    else:
        out.append(wide)
    if title:
        out.append("<figcaption>%s</figcaption>" % esc(title))
    out.append("</figure>")
    return "\n".join(out)
