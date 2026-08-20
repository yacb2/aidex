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
EXPECTED_SCHEMA = "coverage-matrix/1"


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

    tiles = S.tiles([
        {"n": totals.get("src_files", 0), "l": "source files"},
        {"n": tot_unit, "l": "unit tests"},
        {"n": tot_e2e, "l": "E2E tests"},
        {"n": len(data.get("unmapped_test_files") or []), "l": "unmapped test files",
         "warned": bool(data.get("unmapped_test_files"))},
    ])

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
    html = S.page("Coverage matrix", sections, "coverage")

    out = os.path.join(root, ".context", "audits", "test-coverage", "coverage-matrix.html")
    S.write_page(out, html)
    return out
