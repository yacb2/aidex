#!/usr/bin/env python3
"""Render an audit methodology's inventory board: severity/status tiles + a

sortable findings table. Parses the pipe table in
`.context/audits/<methodology>/00-inventory.md` and writes the sibling render
`.context/audits/<methodology>/00-inventory.html`. Markdown stays canon.
"""
import os
import re

import _parse as P
import _shell as S

SEV_TONE = {"P0": "warn", "P1": "warn", "P2": "", "P3": "plain"}
OPEN_STATUSES = {"open", "doing", "in-progress", "todo", ""}

_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)


def _col(headers, *names):
    low = [h.strip().lower() for h in headers]
    for n in names:
        if n in low:
            return low.index(n)
    return None


def _findings_table(text):
    """Locate the findings pipe table: the first table whose header carries the
    required ID / Status / Severity columns.

    HTML comment blocks (the template's EXAMPLE rows) are stripped first, and the
    leading legend table ('How to read this file', header `Column | Meaning`) is
    skipped because it lacks those columns — so the real findings table is found
    regardless of what precedes it. A rename of any required column leaves no
    qualifying table, which the caller turns into a loud exit rather than a board
    where every cell of the renamed column is silently empty.
    """
    lines = _COMMENT.sub("", text).splitlines()
    for i, line in enumerate(lines):
        s = line.strip()
        if not (s.startswith("|") and s.count("|") >= 2):
            continue
        cells = {c.strip().lower() for c in s.strip("|").split("|")}
        if {"id", "status", "severity"} <= cells:
            return P.md_table(lines[i:])
    return [], []


def _trunc(s, n=120):
    s = s.strip()
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def render(root, methodology):
    if not methodology:
        P.die("audit target needs a methodology name (e.g. audit ecosystem)")
    inv = os.path.join(root, ".context", "audits", methodology, "00-inventory.md")
    if not os.path.isfile(inv):
        P.die(f"no inventory at {inv}")

    headers, rows = _findings_table(P.read_text(inv))
    if not headers or not rows:
        # No table carries all of ID / Status / Severity — a renamed or absent
        # required column, not sparse data. Refuse rather than render a
        # structurally valid but wrong board under the GENERATED authority header.
        P.die(f"no findings table with ID/Status/Severity columns in {inv}")

    i_id = _col(headers, "id")
    i_type = _col(headers, "type")
    i_mod = _col(headers, "module")
    i_sum = _col(headers, "summary")
    i_status = _col(headers, "status")
    i_sev = _col(headers, "severity")

    def cell(row, idx):
        return row[idx].strip() if idx is not None and idx < len(row) else ""

    sev_counts, status_open, status_done = {}, 0, 0
    board = []
    for r in rows:
        sev = cell(r, i_sev)
        status = cell(r, i_status).lower()
        sev_counts[sev or "—"] = sev_counts.get(sev or "—", 0) + 1
        if status in OPEN_STATUSES:
            status_open += 1
        else:
            status_done += 1
        summ = cell(r, i_sum)
        board.append([
            S.esc(cell(r, i_id)),
            S.esc(cell(r, i_type)),
            S.esc(cell(r, i_mod)),
            S.pill(sev or "—", SEV_TONE.get(sev, "")),
            S.pill(cell(r, i_status) or "—",
                   "" if status in OPEN_STATUSES else "ok"),
            f'<span title="{S.esc(summ)}">{S.esc(_trunc(summ))}</span>',
        ])

    high = sev_counts.get("P0", 0) + sev_counts.get("P1", 0)
    tiles = S.tiles([
        {"n": len(rows), "l": "findings"},
        {"n": status_open, "l": "open", "warned": status_open > 0},
        {"n": status_done, "l": "resolved"},
        {"n": high, "l": "P0/P1 severity", "warned": high > 0},
    ])

    peak = max(sev_counts.values()) if sev_counts else 0
    prio = []
    for sev in ["P0", "P1", "P2", "P3"]:
        n = sev_counts.get(sev, 0)
        if n:
            prio.append({"label": sev, "pct": (100 * n / peak) if peak else 0, "n": n})

    cols = [("ID", "s"), ("Type", "s"), ("Module", "s"),
            ("Severity", "s"), ("Status", "s"), ("Summary", "s")]
    sections = [tiles]
    if prio:
        sections.append(S.card("Findings by severity", S.prio_rows(prio)))
    sections.append(S.card("Findings", S.table("findings", cols, board),
                           search_id="findings"))
    html = S.page(f"Audit inventory — {methodology}", sections, f"audit {methodology}")

    out = os.path.join(root, ".context", "audits", methodology, "00-inventory.html")
    S.write_page(out, html)
    return out
