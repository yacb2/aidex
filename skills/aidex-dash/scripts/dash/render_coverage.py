#!/usr/bin/env python3
"""Render the test-coverage matrix board from the existing (pre-generated)

`.context/audits/test-coverage/coverage-matrix.json` — the only JSON consumed
by dash; no new JSON is introduced. Writes the sibling render
`.context/audits/test-coverage/coverage-matrix.html`. The JSON stays canon.
"""
import json
import os

import _parse as P
import _shell as S

# The producer (aidex-audit coverage_matrix.py) pins this value into every
# coverage-matrix.json. A missing or unknown value means the shape drifted —
# refuse rather than render a confidently-wrong GENERATED board.
EXPECTED_SCHEMA = "coverage-matrix/2"


def _route_board(modules, gaps):
    """Route x spec x endpoint board. Returns "" when no module declares routes —
    most maps do not, and a routeless map is a normal state, not an error."""
    rows = []
    for m in modules:
        for rt in m.get("routes") or []:
            acts = rt.get("actions") or []
            action_cell = "<br>".join(S.esc(a.get("action", "")) for a in acts) or "—"
            endpoint_cell = "<br>".join(S.esc(a.get("endpoint", "")) for a in acts) or "—"
            reached = rt.get("reached_by") or []
            if rt.get("covered"):
                label = f"{len(reached)} spec" + ("s" if len(reached) != 1 else "")
                # The names go in the tooltip: the column answers "is it reached",
                # and a full path list per row would drown the board.
                e2e_cell = (f'<span title="{S.esc(", ".join(reached))}">'
                            + S.pill(label, "ok") + "</span>")
            else:
                e2e_cell = S.pill("no E2E spec", "warn")
            rows.append([
                S.esc(rt.get("path", "")),
                S.esc(m.get("id", "")),
                S.esc(rt.get("spec") or "—"),
                action_cell,
                endpoint_cell,
                e2e_cell,
            ])
    if not rows:
        return ""

    cols = [("Route", "s"), ("Module", "s"), ("Serves", "s"),
            ("Action", "s"), ("Endpoint", "s"), ("E2E", "s")]
    inner = S.table("routes", cols, rows)
    # The output the field exists for: name the uncovered routes, do not leave
    # them as an absence the reader has to notice.
    if gaps:
        items = "".join(
            f"<li><code>{S.esc(g.get('path', ''))}</code> "
            f"<small style=\"color:var(--muted)\">({S.esc(g.get('module', ''))})</small></li>"
            for g in gaps
        )
        inner += (f'<p class="eyebrow" style="margin:16px 0 4px">'
                  f"Routes with no reaching E2E spec ({len(gaps)})</p><ul>{items}</ul>")
    else:
        inner += ('<p class="eyebrow" style="margin:16px 0 4px">'
                  "Every declared route is reached by an E2E spec.</p>")
    return S.card("Pages and actions — route x spec x endpoint", inner, search_id="routes")


def render(root):
    jpath = os.path.join(root, ".context", "audits", "test-coverage", "coverage-matrix.json")
    if not os.path.isfile(jpath):
        P.die(f"no coverage-matrix.json at {jpath} — run /aidex-audit coverage-matrix first")
    try:
        with open(jpath, encoding="utf-8") as f:
            data = json.load(f)
    except (ValueError, OSError) as e:
        P.die(f"cannot parse {jpath}: {e}")

    schema = data.get("schema")
    if schema != EXPECTED_SCHEMA:
        P.die(f"coverage-matrix.json schema {schema!r} is not supported "
              f"(expected {EXPECTED_SCHEMA!r}) at {jpath} — "
              "regenerate via /aidex-audit coverage-matrix")

    modules = data.get("modules") or []
    if not modules:
        P.die(f"coverage-matrix.json has no modules: {jpath}")
    totals = data.get("totals") or {}
    tot_unit = totals.get("unit_tests", 0) or 0
    tot_e2e = totals.get("e2e_tests", 0) or 0

    gaps = data.get("route_gaps") or []
    tile_items = [
        {"n": totals.get("src_files", 0), "l": "source files"},
        {"n": tot_unit, "l": "unit tests"},
        {"n": tot_e2e, "l": "E2E tests"},
        {"n": len(data.get("unmapped_test_files") or []), "l": "unmapped test files",
         "warned": bool(data.get("unmapped_test_files"))},
    ]
    if totals.get("routes"):
        tile_items.append({"n": totals["routes"], "l": "routes"})
        tile_items.append({"n": len(gaps), "l": "routes with no E2E spec",
                           "warned": bool(gaps)})
    tiles = S.tiles(tile_items)

    cols = [("Module", "s"), ("Src files", "n"), ("Unit tests", "n"),
            ("E2E specs", "n"), ("E2E tests", "n"), ("Notes", "s")]
    rows = []
    for m in modules:
        ut = m.get("unit_tests", 0) or 0
        et = m.get("e2e_tests", 0) or 0
        u_share = (100 * ut / tot_unit) if tot_unit else 0
        e_share = (100 * et / tot_e2e) if tot_e2e else 0
        notes = (m.get("notes") or "").strip()
        note_cell = S.pill("covered", "ok") if notes in ("", "—") \
            else S.pill(notes, "warn")
        rows.append([
            S.esc(m.get("id", "")),
            S.esc(m.get("src_files", 0)),
            f"{ut}" + S.bar(u_share, "u", f"{u_share:.0f}% of unit tests"),
            S.esc(m.get("e2e_files", 0)),
            f"{et}" + S.bar(e_share, "e", f"{e_share:.0f}% of E2E tests"),
            note_cell,
        ])

    leg = S.legend([
        '<b style="background:var(--unit)"></b>unit share',
        '<b style="background:var(--e2e)"></b>E2E share',
        "bars = share of workspace totals",
    ])
    sections = [
        tiles,
        S.card("Coverage matrix — breadth (modules x tests)",
               S.table("matrix", cols, rows) + leg, search_id="matrix"),
    ]
    board = _route_board(modules, gaps)
    if board:
        sections.append(board)
    html = S.page("Coverage matrix", sections, "coverage")

    out = os.path.join(root, ".context", "audits", "test-coverage", "coverage-matrix.html")
    S.write_page(out, html)
    return out
