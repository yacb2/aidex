#!/usr/bin/env python3
"""Render plans: a rollup board (no arg) or one plan's progress page (slug arg).

  render_plans.render(root)          -> plans/00-index.html   (rollup)
  render_plans.render(root, slug)    -> plans/<slug>/00-index.html   (multi-file)
                                        or plans/<slug>.html          (single-file)

The rollup scans `plans/*.md` (single-file plans) and `plans/*/00-index.md`
(multi-file plans), plus `_archive/` counts. A progress page parses the plan's
Phases Overview table and counts the `- [x]`/`- [ ]` task checkboxes in each
referenced phase file. Markdown stays canon.
"""
import glob
import os
import re

import _parse as P
import _shell as S

STATUS_TONE = {"open": "", "in-progress": "warn", "doing": "warn",
               "complete": "ok", "done": "ok", "closed": "ok", "dropped": "plain"}
_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def _phases_overview(text):
    """Return the rows of the plan's `Phases Overview` table, or []."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().lower().startswith("## phases overview"):
            _, rows = P.md_table(lines[i + 1:])
            return rows
    # Fall back to the first pipe table whose header mentions "Phase".
    headers, rows = P.md_table(lines)
    if headers and any("phase" in h.lower() for h in headers):
        return rows
    return []


def _rollup(root, plans_dir):
    pd = glob.escape(plans_dir)  # the workspace path is data, not a pattern (foo-[bl-9] roots)
    plans = []
    # single-file plans
    for path in sorted(glob.glob(os.path.join(pd, "*.md"))):
        if os.path.basename(path) == "00-index.md":
            continue
        plans.append((os.path.splitext(os.path.basename(path))[0], path))
    # multi-file plans; _archive and dotted dirs are never live plans
    for path in sorted(glob.glob(os.path.join(pd, "*", "00-index.md"))):
        d = os.path.basename(os.path.dirname(path))
        if d == "_archive" or d.startswith("."):
            continue
        plans.append((d, path))

    # A plan directory whose 00-index.md is missing (renamed, or an
    # interrupted plan creation) is corpus both globs are blind to — die
    # rather than render a board the plan silently vanished from.
    for entry in sorted(os.listdir(plans_dir)):
        d = os.path.join(plans_dir, entry)
        if not os.path.isdir(d) or entry == "_archive" or entry.startswith("."):
            continue
        if not os.path.isfile(os.path.join(d, "00-index.md")) \
                and glob.glob(os.path.join(glob.escape(d), "*.md")):
            P.die(f"plan directory without 00-index.md: {entry}/ — its phase "
                  f"files are invisible to the rollup; add the index or move "
                  f"the directory to _archive/")

    # Zero active plans is a legitimate state — the all-archived end-state after
    # a D-10 close — not a missing source, so no guard here: the board renders
    # with an empty table and the tiles still carry the archived count. Only a
    # missing plans/ directory (render()) is an error.
    archived = (len(glob.glob(os.path.join(pd, "_archive", "*.md")))
                + len(glob.glob(os.path.join(pd, "_archive", "*", "00-index.md"))))

    rows, open_n = [], 0
    for slug, path in plans:
        fm = P.front_matter(path)
        status = fm.get("status", "")
        if status not in ("complete", "done", "closed", "dropped"):
            open_n += 1
        text = P.read_text(path)
        n_phases = len(_phases_overview(text))
        done, total = P.checkbox_counts(text)
        rows.append([
            S.esc(fm.get("title", slug)),
            S.pill(status or "—", STATUS_TONE.get(status, "")),
            S.esc(n_phases or "—"),
            S.esc(f"{done}/{total}") if total else "—",
        ])

    tiles = S.tiles([
        {"n": len(plans), "l": "plans"},
        {"n": open_n, "l": "open"},
        {"n": archived, "l": "archived"},
    ])
    cols = [("Plan", "s"), ("Status", "s"), ("Phases", "n"), ("Tasks done", "s")]
    sections = [tiles, S.card("Plans", S.table("plans", cols, rows), search_id="plans")]
    html = S.page("Plans rollup", sections, "plans")

    out = os.path.join(plans_dir, "00-index.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    return out


def _progress(root, plans_dir, slug):
    multi = os.path.join(plans_dir, slug, "00-index.md")
    single = os.path.join(plans_dir, slug + ".md")
    if os.path.isfile(multi):
        index_path, base_dir, out = multi, os.path.join(plans_dir, slug), \
            os.path.join(plans_dir, slug, "00-index.html")
    elif os.path.isfile(single):
        index_path, base_dir, out = single, plans_dir, \
            os.path.join(plans_dir, slug + ".html")
    else:
        P.die(f"no plan '{slug}' at {multi} or {single}")

    fm = P.front_matter(index_path)
    text = P.read_text(index_path)
    over = _phases_overview(text)

    phase_rows, tot_done, tot_all, phases_complete = [], 0, 0, 0
    if over:
        for r in over:
            phase = r[0] if len(r) > 0 else ""
            file_cell = r[1] if len(r) > 1 else ""
            desc = r[2] if len(r) > 2 else ""
            m = _LINK.search(file_cell)
            done = total = 0
            if m:
                pf = os.path.join(base_dir, m.group(1))
                if os.path.isfile(pf):
                    done, total = P.checkbox_counts(P.read_text(pf))
            tot_done += done
            tot_all += total
            if total and done == total:
                phases_complete += 1
            pct = (100 * done / total) if total else 0
            prog = (f"{done}/{total} " + S.bar(pct, "u", f"{done} of {total} tasks")) \
                if total else "—"
            phase_rows.append([S.esc(phase), S.esc(desc), prog])
    else:
        # Single-file plan with no Phases Overview: one overall progress row.
        tot_done, tot_all = P.checkbox_counts(text)
        pct = (100 * tot_done / tot_all) if tot_all else 0
        prog = (f"{tot_done}/{tot_all} " + S.bar(pct, "u")) if tot_all else "—"
        phase_rows.append(["overall", S.esc(fm.get("title", slug)), prog])

    status = fm.get("status", "")
    tiles = S.tiles([
        {"n": len(over) if over else 1, "l": "phases"},
        {"n": phases_complete, "l": "phases complete"},
        {"n": f"{tot_done}/{tot_all}" if tot_all else "0", "l": "tasks done"},
        {"n": status or "—", "l": "plan status"},
    ])
    cols = [("Phase", "s"), ("Description", "s"), ("Progress", "s")]
    sections = [
        tiles,
        S.card("Phase progress", S.table("phases", cols, phase_rows, mod_first=True),
               search_id="phases"),
    ]
    html = S.page(fm.get("title", slug), sections, f"plans {slug}")

    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    return out


def render(root, slug=None):
    plans_dir = os.path.join(root, ".context", "plans")
    if not os.path.isdir(plans_dir):
        P.die(f"no plans directory at {plans_dir}")
    if slug:
        return _progress(root, plans_dir, slug)
    return _rollup(root, plans_dir)
