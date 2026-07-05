#!/usr/bin/env python3
"""Render an audit methodology's inventory board: severity/status tiles + a

sortable findings table. Parses the pipe table in
`.context/audits/<methodology>/00-inventory.md` and writes the sibling render
`.context/audits/<methodology>/00-inventory.html`. Markdown stays canon.
"""
import os

import _parse as P
import _shell as S

SEV_TONE = {"P0": "warn", "P1": "warn", "P2": "", "P3": "plain"}
OPEN_STATUSES = {"open", "doing", "in-progress", "todo", ""}


def _col(headers, *names):
    low = [h.strip().lower() for h in headers]
    for n in names:
        if n in low:
            return low.index(n)
    return None


def _trunc(s, n=120):
    s = s.strip()
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def render(root, methodology):
    if not methodology:
        P.die("audit target needs a methodology name (e.g. audit ecosystem)")
    inv = os.path.join(root, ".context", "audits", methodology, "00-inventory.md")
    if not os.path.isfile(inv):
        P.die(f"no inventory at {inv}")

    headers, rows = P.md_table(P.read_text(inv))
    if not headers or not rows:
        P.die(f"no findings table found in {inv}")

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
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    return out
