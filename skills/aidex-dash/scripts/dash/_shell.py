#!/usr/bin/env python3
"""HTML shell for the dash render layer: design tokens, components, and the

vanilla sort/filter JS — all reused from the session-validated visual reference
(.context/drafts/aidex-dash-demo.html). Stdlib only. No external requests, no
emojis; every page is a self-contained single file that works from file://.

Public surface:
  page(title, sections, generated_by)   -> full HTML string
  tiles(items)                          -> stat-tile grid block
  card(eyebrow, inner, search_id=None)  -> titled card section
  table(tid, cols, rows, mod_first=True)-> sortable/filterable table block
  bar(pct, kind, title)                 -> inline share bar
  pill(text, tone)                      -> status pill
  prio_rows(rows)                       -> priority-bar rows block
  esc(s)                                -> HTML-escape a value
"""
import os

from datetime import datetime
from html import escape
from urllib.parse import quote

# Design tokens + components + JS, lifted verbatim from the visual reference.
_STYLE = """<style>
  :root {
    --bg: #F7F9FA; --card: #FFFFFF; --ink: #1B2A30; --muted: #5C7078;
    --border: #DEE7EA; --accent: #0A84A8; --unit: #0A84A8; --e2e: #C07A2B;
    --ok: #2F7D51; --warn: #8A5A10; --warn-bg: #F6EBD9; --ok-bg: #E3F0E8;
    --track: #EDF2F4;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #101619; --card: #172126; --ink: #E2EBEE; --muted: #8FA3AB;
      --border: #24333A; --accent: #22A5C4; --unit: #22A5C4; --e2e: #C07E2F;
      --ok: #4C9E72; --warn: #C98A3D; --warn-bg: #2E2416; --ok-bg: #16281E;
      --track: #1F2C33;
    }
  }
  :root[data-theme="light"] {
    --bg: #F7F9FA; --card: #FFFFFF; --ink: #1B2A30; --muted: #5C7078;
    --border: #DEE7EA; --accent: #0A84A8; --unit: #0A84A8; --e2e: #C07A2B;
    --ok: #2F7D51; --warn: #8A5A10; --warn-bg: #F6EBD9; --ok-bg: #E3F0E8;
    --track: #EDF2F4;
  }
  :root[data-theme="dark"] {
    --bg: #101619; --card: #172126; --ink: #E2EBEE; --muted: #8FA3AB;
    --border: #24333A; --accent: #22A5C4; --unit: #22A5C4; --e2e: #C07E2F;
    --ok: #4C9E72; --warn: #C98A3D; --warn-bg: #2E2416; --ok-bg: #16281E;
    --track: #1F2C33;
  }
  * { box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--ink);
    font: 15px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif;
    margin: 0; padding: 32px 20px 48px;
  }
  .wrap { max-width: 1060px; margin: 0 auto; display: flex; flex-direction: column; gap: 28px; }
  header { display: flex; flex-wrap: wrap; align-items: baseline; gap: 12px 16px; }
  h1 { font-size: 22px; font-weight: 650; margin: 0; letter-spacing: -0.01em; }
  .stamp {
    font: 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace;
    color: var(--muted); border: 1px solid var(--border); border-radius: 999px;
    padding: 5px 10px; letter-spacing: 0.04em;
  }
  .eyebrow {
    font: 600 11px/1 ui-monospace, SFMono-Regular, Menlo, monospace;
    text-transform: uppercase; letter-spacing: 0.09em; color: var(--muted);
    margin: 0 0 10px;
  }
  .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; }
  .tile {
    background: var(--card); border: 1px solid var(--border); border-radius: 10px;
    padding: 14px 16px 12px;
  }
  .tile .n {
    font-size: 30px; font-weight: 650; letter-spacing: -0.02em;
    font-variant-numeric: tabular-nums; display: block;
  }
  .tile .l { font-size: 12.5px; color: var(--muted); }
  .tile.warned .n { color: var(--warn); }
  section.card {
    background: var(--card); border: 1px solid var(--border); border-radius: 10px;
    padding: 18px 18px 8px;
  }
  .sec-head { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; justify-content: space-between; }
  .sec-head input {
    background: var(--bg); color: var(--ink); border: 1px solid var(--border);
    border-radius: 7px; padding: 6px 10px; font: inherit; font-size: 13px; width: 200px;
  }
  .sec-head input:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
  .tbl-wrap { overflow-x: auto; margin: 6px -6px 0; padding: 0 6px 10px; }
  table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
  th, td { text-align: right; padding: 8px 12px; border-bottom: 1px solid var(--border); white-space: nowrap; }
  th:first-child, td:first-child { text-align: left; }
  tbody tr:last-child td { border-bottom: none; }
  th {
    font: 600 11px/1.3 ui-monospace, SFMono-Regular, Menlo, monospace;
    text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted);
    cursor: pointer; user-select: none; position: relative;
  }
  th:hover, th:focus-visible { color: var(--ink); outline: none; }
  th .dir { font-size: 9px; margin-left: 3px; }
  td.mod { font-weight: 600; }
  td .sub { display: block; font-size: 11.5px; color: var(--muted); font-weight: 400; }
  .bar {
    display: inline-block; vertical-align: middle; height: 8px; border-radius: 4px 4px 4px 4px;
    background: var(--track); width: 110px; margin-left: 10px; position: relative; overflow: hidden;
  }
  .bar i { position: absolute; inset: 0 auto 0 0; border-radius: 4px; }
  .bar i.u { background: var(--unit); }
  .bar i.e { background: var(--e2e); }
  .pill {
    display: inline-block; font-size: 11.5px; font-weight: 600; border-radius: 999px;
    padding: 3px 10px; letter-spacing: 0.02em;
  }
  .pill.warn { color: var(--warn); background: var(--warn-bg); }
  .pill.ok { color: var(--ok); background: var(--ok-bg); }
  .pill.plain { color: var(--muted); background: var(--track); }
  .legend { display: flex; gap: 16px; flex-wrap: wrap; font-size: 12.5px; color: var(--muted); padding: 10px 2px 4px; }
  .legend b { display: inline-block; width: 10px; height: 10px; border-radius: 3px; margin-right: 6px; vertical-align: -1px; }
  .prio-rows { display: flex; flex-direction: column; gap: 10px; padding: 10px 2px 14px; }
  .prio { display: grid; grid-template-columns: 110px 1fr 60px; align-items: center; gap: 12px; }
  .prio .pl { font: 600 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--muted); letter-spacing: 0.05em; }
  .prio .pt { height: 12px; background: var(--track); border-radius: 5px; overflow: hidden; }
  .prio .pt i { display: block; height: 100%; background: var(--accent); border-radius: 5px; }
  .prio .pn { font-variant-numeric: tabular-nums; font-size: 13px; color: var(--ink); }
  footer { font-size: 12.5px; color: var(--muted); border-top: 1px solid var(--border); padding-top: 14px; }
  footer code { font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; }
</style>"""

# Row filter is wired generically (input[data-target] -> table id) so any number
# of filterable cards work on one page; column sort is numeric-aware, no library.
_SCRIPT = """<script>
  // Row filter: each search input names its table via data-target.
  document.querySelectorAll('input[data-target]').forEach(function (inp) {
    inp.addEventListener('input', function () {
      var needle = inp.value.toLowerCase();
      var body = document.querySelector('#' + inp.dataset.target + ' tbody');
      if (!body) return;
      body.querySelectorAll('tr').forEach(function (tr) {
        tr.hidden = needle && tr.textContent.toLowerCase().indexOf(needle) === -1;
      });
    });
  });
  // Tiny column sort (numeric-aware), no library needed.
  document.querySelectorAll('th[data-k]').forEach(function (th) {
    th.tabIndex = 0;
    var asc = false;
    function sortBy() {
      var table = th.closest('table');
      var k = +th.dataset.k, num = th.dataset.t === 'n';
      asc = !asc;
      table.querySelectorAll('th .dir').forEach(function (d) { d.remove(); });
      var d = document.createElement('span'); d.className = 'dir'; d.textContent = asc ? '\\u25B2' : '\\u25BC';
      th.appendChild(d);
      var rows = Array.from(table.tBodies[0].rows);
      rows.sort(function (a, b) {
        var av = a.cells[k].textContent.trim(), bv = b.cells[k].textContent.trim();
        if (num) { av = parseFloat(av.replace(/[^0-9.-]/g, '')) || 0; bv = parseFloat(bv.replace(/[^0-9.-]/g, '')) || 0; return asc ? av - bv : bv - av; }
        return asc ? av.localeCompare(bv) : bv.localeCompare(av);
      });
      rows.forEach(function (r) { table.tBodies[0].appendChild(r); });
    }
    th.addEventListener('click', sortBy);
    th.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); sortBy(); } });
  });
</script>"""

_FOOTER = (
    '<footer>This page is a <strong>render, not a source</strong>: every value above '
    'lives in <code>.context/</code> markdown/JSON (the canon). Regenerate anytime with '
    'aidex-dash; never edit by hand. Self-contained single file &mdash; works from '
    '<code>file://</code> with no server and no external requests.</footer>'
)


def esc(s):
    return escape(str(s), quote=True)


# ---------- Document envelope (shared by both artifact routes) ----------
#
# The Artifact tool wraps a page at PUBLISH time: doctype, head, body, and a
# minimal CSS reset. A local-first artifact never gets that wrapper, so the
# envelope has to be supplied here or the file lands as a headless fragment
# (field-measured: 2 of 4 reports in echo_lab_ws had no doctype -> quirks mode).
# Route A (dash renders) and route B (ad-hoc reports via wrap-report.sh) call
# this same function, so both routes produce the same kind of document.
#
# Deliberately envelope + minimal reset ONLY. Theming stays with the page's own
# <style> — a second theme system here would fight the author's palette.

_RESET = """<style>
  *, *::before, *::after { box-sizing: border-box; }
  body { margin: 0; }
  img, svg, video, canvas { max-width: 100%; height: auto; }
</style>"""


def _favicon_link(favicon):
    """Emoji -> inline SVG data URI. No external request, CSP-safe."""
    if not favicon:
        return ""
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
           f'<text y=".9em" font-size="90">{escape(favicon)}</text></svg>')
    return f'\n<link rel="icon" href="data:image/svg+xml,{quote(svg)}">'


def document(title, body, lang="en", favicon="", head_extra="", prelude=""):
    """Assemble a complete, self-contained HTML document.

    `prelude` goes before the doctype (dash puts its GENERATED contract comment
    there; comments before a doctype do not trigger quirks mode). `head_extra`
    is the page's own <style>/<meta> block, emitted after the reset so the
    author's rules win.
    """
    pre = f"{prelude}\n" if prelude else ""
    return (
        f"{pre}<!doctype html>\n"
        f'<html lang="{esc(lang)}">\n'
        "<head>\n"
        '<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        f"<title>{esc(title)}</title>"
        f"{_favicon_link(favicon)}\n"
        f"{_RESET}\n"
        f"{head_extra}\n"
        "</head>\n"
        "<body>\n"
        f"{body}\n"
        "</body>\n"
        "</html>\n"
    )


def _clamp(pct):
    try:
        pct = float(pct)
    except (TypeError, ValueError):
        pct = 0
    return max(0, min(100, pct))


def bar(pct, kind="u", title=""):
    """Inline share bar. `kind` selects the fill color class ('u' unit/accent,
    'e' e2e/amber). `pct` is clamped to 0..100."""
    w = _clamp(pct)
    t = f' title="{esc(title)}"' if title else ""
    cls = kind if kind in ("u", "e") else "u"
    return f'<span class="bar"{t}><i class="{cls}" style="width:{w:g}%"></i></span>'


def pill(text, tone=""):
    """Status pill. tone in {'ok','warn',''} ('' -> neutral 'plain')."""
    cls = tone if tone in ("ok", "warn") else "plain"
    return f'<span class="pill {cls}">{esc(text)}</span>'


def tiles(items):
    """Stat-tile grid. items: list of dicts {n, l, warned?}."""
    cells = []
    for it in items:
        warned = " warned" if it.get("warned") else ""
        cells.append(
            f'<div class="tile{warned}"><span class="n">{esc(it["n"])}</span>'
            f'<span class="l">{esc(it["l"])}</span></div>'
        )
    return '<div class="tiles">' + "".join(cells) + "</div>"


def card(eyebrow, inner, search_id=None):
    """Titled card section. If search_id is given, add a filter input bound to
    that table id (generic data-target wiring)."""
    head = f'<p class="eyebrow" style="margin:0">{esc(eyebrow)}</p>'
    if search_id:
        head += (
            f'<input type="search" data-target="{esc(search_id)}" '
            f'placeholder="Filter…" aria-label="Filter rows">'
        )
    return (
        '<section class="card"><div class="sec-head">'
        + head
        + "</div>"
        + inner
        + "</section>"
    )


def table(tid, cols, rows, mod_first=True):
    """Sortable table. cols: list of (label, type) where type is 's' or 'n'.
    rows: list of lists of pre-built cell HTML strings. First column is bolded
    (class 'mod') when mod_first."""
    ths = []
    for i, (label, typ) in enumerate(cols):
        t = "n" if typ == "n" else "s"
        ths.append(f'<th data-k="{i}" data-t="{t}">{esc(label)}</th>')
    trs = []
    for r in rows:
        tds = []
        for i, cell in enumerate(r):
            cls = ' class="mod"' if (i == 0 and mod_first) else ""
            tds.append(f"<td{cls}>{cell}</td>")
        trs.append("<tr>" + "".join(tds) + "</tr>")
    return (
        f'<div class="tbl-wrap"><table id="{esc(tid)}"><thead><tr>'
        + "".join(ths)
        + "</tr></thead><tbody>"
        + "".join(trs)
        + "</tbody></table></div>"
    )


def prio_rows(rows):
    """Priority bars. rows: list of dicts {label, pct, n, note?}."""
    out = ['<div class="prio-rows">']
    for r in rows:
        w = _clamp(r.get("pct", 0))
        note = ""
        if r.get("note"):
            note = f' <small style="color:var(--muted)">({esc(r["note"])})</small>'
        out.append(
            '<div class="prio">'
            f'<span class="pl">{esc(r["label"])}</span>'
            f'<span class="pt"><i style="width:{w:g}%"></i></span>'
            f'<span class="pn">{esc(r["n"])}{note}</span>'
            "</div>"
        )
    out.append("</div>")
    return "".join(out)


def legend(spans):
    """Legend row. spans: list of pre-built HTML strings."""
    return '<div class="legend">' + "".join(f"<span>{s}</span>" for s in spans) + "</div>"


def write_page(out, html):
    """Write the rendered page atomically (tmp + os.replace): a failed write
    must never truncate the previous good render in place — a half-written
    board with an intact GENERATED first line passes every first-line check."""
    tmp = out + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(html)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    os.replace(tmp, out)


def page(title, sections, generated_by):
    """Assemble the full self-contained HTML document.

    Line 1 is always the GENERATED contract comment (same contract as
    coverage-matrix.md): markdown/JSON stays canon, this file is a regenerable
    render. `sections` is a list of pre-built HTML block strings.
    """
    stamp = datetime.now().isoformat(timespec="seconds")
    generated = (
        f"<!-- GENERATED {stamp} by /aidex-dash {generated_by} "
        "— DO NOT EDIT, regenerate instead -->"
    )
    body = (
        '<div class="wrap"><header>'
        f"<h1>{esc(title)}</h1>"
        f'<span class="stamp">GENERATED {stamp} — {esc(generated_by)}</span>'
        "</header>"
        + "".join(sections)
        + _FOOTER
        + "</div>"
    )
    return document(title, body + "\n" + _SCRIPT, head_extra=_STYLE, prelude=generated)
