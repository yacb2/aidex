#!/usr/bin/env python3
"""Cross-number checks of artifact rubric line 7 (BL-852): the page says one figure
in two places and the two must agree. Pure functions over page markup; check_artifact
wires them as WARNs (exit-neutral, named files only, never in the census).

    cross_numbers.findings(markup) -> [(slug, message)]

Slugs and the exact rule each one enforces:

cross-number-chart
    A kit chart mark names a category (`<title>label: value</title>`, multi-series
    `series · label: value`) or an element carries `data-label` + `data-value`. When
    the first cell of a table row is that same label (accent- and case-insensitive),
    the value must equal a numeric cell of that row, compared only against cells of
    the same kind (a `%` value against `%` cells, a plain value against plain cells:
    a share chart beside an absolute table is two measures, not a mismatch). A label
    with no table row, or a row with no cell of that kind, says nothing. Equality
    is the kit's own float round() to the fewer decimals of the two, or half away
    from zero; a percent tick is `%` right after the number (`80 % del total`).

table-header-unit
    A table column (not the first) whose body cells, at least two, are all bare
    numbers and whose header names a time or money measure (time, duration, wait,
    latency, delay, cost, price, spend, p50..p99 and the Spanish forms) needs a
    unit in that header: a parenthesis or bracket, `%`, `/`, a currency sign, or a
    unit word (s, ms, min, h, USD, days...). A possessive `'s` is not the
    unit `s`. Left without one on purpose: sizes, rates, counts and identifiers
    (`Batch size`, `Hit rate`, `Ronda`), whose bare number is a count or a ratio.

Both are WARNs (check_artifact wires them as warnings: exit-neutral, named files
only, never in the census). A cross-number rule for prose ("Otras skills 4930"
against a table) was built and REMOVED: it misread `(84%)`, `(12)` and years as the
label's figure, could not tell a figure given to the wrong row, and no cheap rule
was sound; the grader keeps that half of rubric line 7.

Skipped on purpose (semantic, not deterministic): a number written as a word
("four" against "three"), a range cell (`16-18 s`), an arrow (`51->49`), a heading
that calls a row the largest, and any table with colspan/rowspan.
"""
import html as _html
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import re
import unicodedata

_TABLE = re.compile(r"<table\b.*?</table\s*>", re.I | re.S)
_ROW = re.compile(r"<tr\b.*?</tr\s*>", re.I | re.S)
_CELL = re.compile(r"<t([hd])\b[^>]*>(.*?)</t\1\s*>", re.I | re.S)
_SVG = re.compile(r"<svg\b.*?</svg\s*>", re.I | re.S)
_FIG_CHART = re.compile(r"<figure\b[^>]*\bclass\s*=\s*[\"'][^\"']*\bchart\b[^>]*>.*?</figure\s*>",
                        re.I | re.S)
_PCT_TICK = re.compile(r">\s*[\d.,]+\s*%[^<]*<")
_TITLE = re.compile(r"<title>(.*?)</title>", re.I | re.S)
_DATA_MARK = re.compile(r"<[a-z][^>]*>", re.I)
_DATA_ATTR = re.compile(r"\b(data-label|data-value)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')", re.I)
_NUM = re.compile(r"[+\-−]?\d[\d.,]*")
_RANGE = re.compile(r"\d\s*(?:[-–—]|->|→|\bto\b|\ba\b)\s*\d", re.I)
_BARE = re.compile(r"^[+\-−]?\d+(?:[.,]\d+)*$")
_EMPTY = {"", "-", "—", "–", "n/a", "na", "·", "?"}
_UNIT_MARK = re.compile(r"[(\[%/$€£]")
_UNIT_WORD = re.compile(
    r"\b(?:s|sec|secs|seg|segs|ms|min|mins|h|hr|hrs|usd|eur|kb|mb|gb|tb|kib|mib|bytes?|"
    r"days?|días|dias|horas?|hours?|minutes?|minutos?|seconds?|segundos?|"
    r"weeks?|semanas?|px|rem|pts?|puntos|pct|fps)\b", re.I)
_MEASURE_WORD = re.compile(
    r"\b(?:time|duration|wait|latency|delay|cost|price|spend|p50|p90|p95|p99|"
    r"tiempo|duracion|espera|latencia|costo|coste|precio|gasto)\b", re.I)
_POSSESSIVE = re.compile(r"['\u2019]s\b", re.I)

def _norm(s):
    s = unicodedata.normalize("NFD", _html.unescape(s))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return " ".join(s.split()).casefold()


def _text(markup):
    return " ".join(_html.unescape(re.sub(r"<[^>]+>", " ", markup)).split())


def parse_nums(s):
    """Candidate readings of the first number in `s`: [(value, decimals)], or []
    when `s` has none or is a range/arrow. A lone separator before exactly three
    digits is both a thousands mark and a decimal point, so both readings return."""
    if _RANGE.search(s):
        return []
    m = _NUM.search(s)
    if not m:
        return []
    tok = m.group(0).replace("−", "-").rstrip(".,")
    sign = -1.0 if tok.startswith("-") else 1.0
    tok = tok.lstrip("+-")
    if not tok or not tok[0].isdigit():
        return []

    def val(t, dec_sep=None):
        if dec_sep:
            ip, _, fp = t.rpartition(dec_sep)
            ip = re.sub(r"[.,]", "", ip)
            return (sign * float(ip + "." + fp), len(fp))
        return (sign * float(re.sub(r"[.,]", "", t)), 0)

    seps = re.findall(r"[.,]", tok)
    if not seps:
        return [val(tok)]
    if "." in seps and "," in seps:
        return [val(tok, tok[max(tok.rfind("."), tok.rfind(","))])]
    sep = seps[0]
    if len(seps) > 1:
        return [val(tok)]                         # 1.234.567: groups of thousands
    after = tok.split(sep)[1]
    if len(after) == 3 and 1 <= len(tok.split(sep)[0]) <= 3 and tok[0] != "0":
        return [val(tok), val(tok, sep)]
    return [val(tok, sep)]


_CELL_FIG = re.compile(r"^[$\u20ac\u00a3]?\s*([+\-\u2212]?\d[\d.,]*)\s*(?:%|[^\W\d_]{1,8}(?:/[^\W\d_]{1,8})?)?$")


def cell_figure(cell):
    """The readings of a table cell that IS a figure: a number with at most a
    short unit after it (`16 s`, `12%`, `$3`). A sentence with a number inside,
    a fraction (`1/2`) or a range is not one."""
    m = _CELL_FIG.match(cell.strip())
    return parse_nums(m.group(1)) if m else []


def _same(a, b):
    """Equal at the fewer decimals of the two. The kit prints a mark with float
    round() (chart_svg._fmt), so that reading always counts; a hand-typed half-up
    reading (12.5 -> 13) counts too. A WARN check never raises: a cell too big
    for Decimal falls back to the float reading."""
    d = min(a[1], b[1])
    if round(a[0], d) == round(b[0], d):
        return True
    try:
        q = Decimal(1).scaleb(-d)
        return (Decimal(repr(a[0])).quantize(q, ROUND_HALF_UP)
                == Decimal(repr(b[0])).quantize(q, ROUND_HALF_UP))
    except InvalidOperation:
        return False


def _agrees(reading, known):
    return any(_same(r, k) for r in reading for k in known)


def tables(markup):
    """[(header_cells, body_rows)] of every table without colspan/rowspan; cells
    are text. The header is the first row."""
    out = []
    for t in _TABLE.findall(markup):
        if re.search(r"\b(?:colspan|rowspan)\s*=", t, re.I):
            continue
        rows = [[_text(c[1]) for c in _CELL.findall(r)] for r in _ROW.findall(t)]
        rows = [r for r in rows if r]
        if len(rows) >= 2:
            out.append((rows[0], rows[1:]))
    return out


def chart_marks(markup):
    """{(norm label): [(readings, is_percent, printed value)]} from kit chart
    marks and data-label / data-value elements. One figure's wide and narrow
    renderings are one entry."""
    out, seen = {}, set()

    def add(label, raw, pct):
        reading = parse_nums(raw)
        key = (_norm(label), tuple(reading), pct)
        if reading and key not in seen:
            seen.add(key)
            out.setdefault(key[0], []).append((reading, pct, raw.strip()))

    for fig in _FIG_CHART.findall(markup):
        # The kit writes the unit on the axis ticks (`80 %`), not in the mark title.
        pct = bool(_PCT_TICK.search(fig))
        for svg in _SVG.findall(fig):
            for ttl in _TITLE.findall(svg):
                txt = _text(ttl)
                if ": " not in txt:
                    continue
                left, _, right = txt.rpartition(": ")
                for c in {left, left.split(" · ", 1)[-1]}:
                    add(c, right, pct or "%" in right)
    for tag in _DATA_MARK.findall(markup):
        attrs = {m.group(1).lower(): _html.unescape(m.group(2) or m.group(3) or "")
                 for m in _DATA_ATTR.finditer(tag)}
        if "data-label" in attrs and "data-value" in attrs:
            add(attrs["data-label"], attrs["data-value"], "%" in attrs["data-value"])
    return out


def table_figures(tbls):
    """{(norm first cell): [(readings, is_percent)] of each numeric cell of those rows}."""
    out = {}
    for _head, body in tbls:
        for row in body:
            label = _norm(row[0])
            if not label or cell_figure(label):
                continue
            nums = [(r, "%" in c) for c in row[1:] for r in [cell_figure(c)] if r]
            out.setdefault(label, []).extend(nums)
    return out


def _unit_findings(tbls):
    out = []
    for head, body in tbls:
        for j in range(1, len(head)):
            col = [r[j] for r in body if len(r) > j and _norm(r[j]) not in _EMPTY]
            if len(col) < 2 or not all(_BARE.match(c.strip()) for c in col):
                continue
            h = head[j].strip()
            plain = _POSSESSIVE.sub("", h)
            if (not _MEASURE_WORD.search(_norm(plain)) or _UNIT_MARK.search(plain)
                    or _UNIT_WORD.search(plain)):
                continue
            out.append(("table-header-unit",
                        f"the table column headed \"{h}\" holds only bare numbers "
                        f"({col[0]}, {col[1]}...) and its header gives no unit; write the unit "
                        f"in the header, e.g. \"{h} (unit)\""))
    return out


def findings(markup):
    tbls = tables(markup)
    out = list(_unit_findings(tbls))
    tfig = table_figures(tbls)
    for label, marks in chart_marks(markup).items():
        for reading, pct, raw in marks:
            same_kind = [r for r, p in tfig.get(label, []) if p == pct]
            if same_kind and not _agrees(reading, [k for ks in same_kind for k in ks]):
                out.append(("cross-number-chart",
                            f"the chart gives \"{label}\" as {raw} but the table row "
                            f"\"{label}\" has no cell equal to it; make the chart and the "
                            f"table agree"))
    return out
