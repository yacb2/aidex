#!/usr/bin/env python3
"""Render the backlog board: stat tiles + priority bars + sortable item table.

Reads the front-matter of every top-level `.context/backlog/*.md` item (never
the `_archive/` bodies — those are counted only) and writes the sibling render
`.context/backlog/00-index.html`. The markdown stays canon.
"""
import glob
import os
import sys

import _parse as P
import _shell as S

# Producer-consumer contract pin (BL-060 pattern). The producer is
# register-item.sh's item front-matter (documented in
# aidex-backlog/references/01-backlog-conventions.md); this renderer is the
# consumer. Bumped to /2 when the `type` facet was added (ADR 2026-07-23). Unlike
# coverage-matrix (a JSON key the renderer can hard-check), backlog items carry no
# per-file schema stamp, so this is documentary: the renderer stays tolerant of
# items predating a field (absent `type` renders as "—"), which is why the type
# addition is additive rather than a fail-loud break.
BACKLOG_SCHEMA = "backlog-fm/2"

CONSUMED_FIELDS = ("id", "title", "status", "priority", "type", "estimate", "origin_ref")

STATUS_TONE = {"doing": "warn", "open": "", "done": "ok", "dropped": "plain",
               "deferred": "plain", "blocked": "warn"}


def _items(backlog_dir):
    items, skipped = [], []
    # glob.escape: the workspace path is data, not a pattern (foo-[bl-9] roots)
    for path in sorted(glob.glob(os.path.join(glob.escape(backlog_dir), "*.md"))):
        if os.path.basename(path) == "00-index.md":
            continue
        fm = P.front_matter(path)
        if not fm:
            # An unparseable item must stay visible: dropping it silently is
            # how a malformed corpus masquerades as the all-archived end-state.
            skipped.append(path)
            print(f"NOTE: skipped (unparseable front matter): {path}", file=sys.stderr)
            continue
        items.append({
            "id": fm.get("id", ""),
            "title": fm.get("title", os.path.basename(path)),
            "status": fm.get("status", ""),
            "priority": fm.get("priority", ""),
            "type": fm.get("type", ""),
            "estimate": fm.get("estimate", ""),
            "origin_ref": fm.get("origin_ref", ""),
        })
    return items, skipped


def render(root):
    backlog_dir = os.path.join(root, ".context", "backlog")
    if not os.path.isdir(backlog_dir):
        P.die(f"no backlog directory at {backlog_dir}")

    # Zero item FILES is a legitimate state — everything closed and archived
    # per D-10 — and renders as an empty board (same decision as render_plans;
    # downstream math is zero-safe). N files with zero PARSED is not: that is
    # a malformed corpus, and rendering it healthy is the lie-by-omission the
    # 2026-08-20 review confirmed, so it dies before any board is written.
    items, skipped = _items(backlog_dir)
    if skipped and not items:
        P.die(f"{len(skipped)} backlog item file(s) under {backlog_dir} but none parsed "
              f"— front matter must open with '---' on line 1 (a BOM, leading blank "
              f"line or merge marker breaks it); first offender: "
              f"{os.path.basename(skipped[0])}")
    archived = len(glob.glob(os.path.join(glob.escape(backlog_dir), "_archive", "*.md")))
    active = sum(1 for it in items if it["status"] not in ("done", "dropped"))
    doing = sum(1 for it in items if it["status"] == "doing")

    tiles = S.tiles([
        {"n": active, "l": "active items"},
        {"n": doing, "l": "doing", "warned": doing > 0},
        {"n": archived, "l": "archived"},
        {"n": len(items), "l": "live files parsed"},
    ])

    # Priority bars over live (non-archived) items.
    prio_counts = {}
    for it in items:
        prio_counts[it["priority"] or "—"] = prio_counts.get(it["priority"] or "—", 0) + 1
    order = ["P1", "P2", "P3"]
    labels = {"P1": "P1 HIGH", "P2": "P2 MEDIUM", "P3": "P3 LOW"}
    peak = max(prio_counts.values()) if prio_counts else 0
    prio = []
    for p in order:
        n = prio_counts.get(p, 0)
        prio.append({"label": labels[p], "pct": (100 * n / peak) if peak else 0, "n": n})
    for p in sorted(k for k in prio_counts if k not in order):
        n = prio_counts[p]
        prio.append({"label": p, "pct": (100 * n / peak) if peak else 0, "n": n})

    # Item table. `type` renders as a chip (one queue, a facet — never a section).
    cols = [("ID", "s"), ("Title", "s"), ("Type", "s"), ("Status", "s"),
            ("Priority", "s"), ("Estimate", "s")]
    rows = []
    for it in sorted(items, key=lambda x: (x["priority"], x["id"])):
        tone = STATUS_TONE.get(it["status"], "")
        rows.append([
            S.esc(it["id"]),
            S.esc(it["title"]),
            S.pill(it["type"], "plain") if it["type"] else S.esc("—"),
            S.pill(it["status"] or "—", tone),
            S.esc(it["priority"] or "—"),
            S.esc(it["estimate"] or "—"),
        ])

    sections = [
        tiles,
        S.card("Backlog by priority (live items)", S.prio_rows(prio)),
        S.card("Backlog items", S.table("items", cols, rows), search_id="items"),
    ]
    html = S.page("Backlog board", sections, "backlog")

    out = os.path.join(backlog_dir, "00-index.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    return out
