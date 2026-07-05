#!/usr/bin/env python3
"""Render the backlog board: stat tiles + priority bars + sortable item table.

Reads the front-matter of every top-level `.context/backlog/*.md` item (never
the `_archive/` bodies — those are counted only) and writes the sibling render
`.context/backlog/00-index.html`. The markdown stays canon.
"""
import glob
import os

import _parse as P
import _shell as S

STATUS_TONE = {"doing": "warn", "open": "", "done": "ok", "dropped": "plain",
               "deferred": "plain", "blocked": "warn"}


def _items(backlog_dir):
    items = []
    for path in sorted(glob.glob(os.path.join(backlog_dir, "*.md"))):
        if os.path.basename(path) == "00-index.md":
            continue
        fm = P.front_matter(path)
        if not fm:
            continue
        items.append({
            "id": fm.get("id", ""),
            "title": fm.get("title", os.path.basename(path)),
            "status": fm.get("status", ""),
            "priority": fm.get("priority", ""),
            "estimate": fm.get("estimate", ""),
            "origin_ref": fm.get("origin_ref", ""),
        })
    return items


def render(root):
    backlog_dir = os.path.join(root, ".context", "backlog")
    if not os.path.isdir(backlog_dir):
        P.die(f"no backlog directory at {backlog_dir}")

    items = _items(backlog_dir)
    if not items:
        P.die(f"no backlog items found under {backlog_dir}")

    archived = len(glob.glob(os.path.join(backlog_dir, "_archive", "*.md")))
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

    # Item table.
    cols = [("ID", "s"), ("Title", "s"), ("Status", "s"),
            ("Priority", "s"), ("Estimate", "s")]
    rows = []
    for it in sorted(items, key=lambda x: (x["priority"], x["id"])):
        tone = STATUS_TONE.get(it["status"], "")
        rows.append([
            S.esc(it["id"]),
            S.esc(it["title"]),
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
