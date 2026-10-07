#!/usr/bin/env python3
"""galleries_harvest.py — freeze the gallery specs on disk into the galleries gate's manifest.

    python3 galleries_harvest.py [--into DIR] [--projects DIR]

For each `*.spec.md` under <projects>/*/ that holds a `gallery` block (skipping node_modules, .git,
aidex_ws/aidex, aidex_ws/_tmp and any .context/proofs/), writes `DIR/<project>__<path>/` holding
the spec (every gallery's `root=` rewritten to `root`, `rows=` to the copied rows file's name),
the rows files, the captures they name under `root/<path>` and the spec's own relative `src=` /
`poster=` files, plus `ORIGIN` (the source spec's path). Reads projects, writes only into DIR.
Run once; the manifest is the gate's frozen input (galleries_gate.py reads it, never the projects).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))
import spec_parser  # noqa: E402
import galleries_gate as gg  # noqa: E402


def walk(nodes):
    for n in nodes:
        yield n
        yield from walk(n.children)


def harvest(path, projects, into):
    rel = os.path.relpath(path, projects)
    name = re.sub(r"\.spec\.md$", "", rel).replace(os.sep, "__")
    out = os.path.join(into, name)
    here = os.path.dirname(path)
    text = open(path, encoding="utf-8").read()
    lines = text.split("\n")
    top = subprocess.run(["git", "-C", here, "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "root"))
    missing = []
    for node in walk(spec_parser.parse(text)):
        a = node.attrs
        for key in ("src", "poster"):
            v = a.get(key, "")
            if v and not re.match(r"^[a-z]+:|^/|^#", v) and os.path.isfile(os.path.join(here, v)):
                dest = os.path.normpath(v)
                if dest.startswith(".."):                  # outside the spec's dir: keep it inside the unit
                    dest = os.path.join("_outside", os.path.basename(v))
                    lines[node.line - 1] = lines[node.line - 1].replace('%s="%s"' % (key, v), '%s="%s"' % (key, dest))
                os.makedirs(os.path.dirname(os.path.join(out, dest)), exist_ok=True)
                shutil.copyfile(os.path.join(here, v), os.path.join(out, dest))
        if node.block_type != "gallery":
            continue
        root = os.path.normpath(os.path.join(here, a["root"])) if "root" in a else top
        rows_src = os.path.join(here, a["rows"])
        rows_name = os.path.basename(a["rows"])
        shutil.copyfile(rows_src, os.path.join(out, rows_name))
        doc = json.load(open(rows_src, encoding="utf-8"))
        page = os.path.join(here, re.sub(r"\.spec\.md$", ".html", os.path.basename(path)))
        sections = gg.parse_page(open(page, encoding="utf-8", errors="replace").read()).sections if os.path.isfile(page) else {}
        rescue = {}              # capture path -> the page's persistent hash copy of it (before/after of a review row)
        for r in doc.get("rows", []):
            rid = gg.gallery_items.row_id(doc.get("gallery"), r.get("cell"), r.get("variant"), r.get("kind", "review"))
            for t in sections.get(rid, []):
                if t["tile"] in ("before", "after") and isinstance(r.get(t["tile"]), str):
                    rescue[r[t["tile"]]] = os.path.join(here, urllib.parse.unquote(t["src"]))
        paths = []
        for r in doc.get("rows", []):
            for k in ("before", "after"):
                paths.append(r.get(k))
            caps = r.get("captures") or {}
            for v in caps.values():
                paths += list(v.values()) if isinstance(v, dict) else [v]
            paths += [s.get("capture") for s in r.get("states", []) if isinstance(s, dict)]
        for p in {p for p in paths if isinstance(p, str)}:
            for q in (p, re.sub(r"\.png$", ".regions.json", p)):
                src = os.path.join(root, q.lstrip("/"))
                if os.path.isfile(src):
                    os.makedirs(os.path.dirname(os.path.join(out, "root", q.lstrip("/"))), exist_ok=True)
                    shutil.copyfile(src, os.path.join(out, "root", q.lstrip("/")))
                elif q == p and os.path.isfile(rescue.get(p, "")):
                    os.makedirs(os.path.dirname(os.path.join(out, "root", q.lstrip("/"))), exist_ok=True)
                    shutil.copyfile(rescue[p], os.path.join(out, "root", q.lstrip("/")))
                elif q == p:
                    missing.append(p)
        i = node.line - 1
        ln = re.sub(r'\s(root|rows)="[^"]*"', "", lines[i])
        lines[i] = ln[:ln.rindex("}")].rstrip() + ' rows="%s" root="root"}' % rows_name
    with open(os.path.join(out, "spec.md"), "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines))
    with open(os.path.join(out, "ORIGIN"), "w") as f:
        f.write(path + "\n")
    return name, missing


EXCLUDED = {       # path fragment -> why it is not in the manifest
    "/.context/proofs/": "proof scratch of a fix round, not an owner gallery",
    "/aidex_ws/.context/reports/2026-09-26-mecanismo-revision-ui.spec.md":
        "rows file in the retired tile-matrix format (no variants/kind) whose captures are gone with their worktree; no migration keeps its meaning",
}


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--into", default=gg.manifest_dir())
    ap.add_argument("--projects", default=gg.PROJECTS)
    a = ap.parse_args(argv)
    for _, path in gg.on_disk_specs(a.projects):
        why = next((w for k, w in EXCLUDED.items() if k in path), None)
        if why:
            print("excluded: %s (%s)" % (path, why), file=sys.stderr)
            continue
        name, missing = harvest(path, a.projects, a.into)
        print("%s%s" % (name, "  MISSING " + ", ".join(missing) if missing else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
