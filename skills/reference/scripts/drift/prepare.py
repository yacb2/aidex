"""Pre-launch step of `/aidex:reference drift`: pick the code units a reference covers.

Usage: python3 prepare.py <project_root> <work_dir>
Writes <work_dir>/manifest.json (`units`: one entry per kept unit with unit, slug, files,
references, tokens_est; `skipped`: covered units too large or data-like to extract, with
unit, references, reason) and <work_dir>/units/<slug>.txt (the unit's file list) and units/<slug>.refs.txt (its covering references). Both are
replaced on every run. The Workflow gets its unit slugs from the manifest, never recomputes them. Stdlib only.

Every `.md` under <root>/.context/references/ is a reference, except `00-profile.md`, the
root `00-index.md` and any reference whose front-matter says `status: dropped`. A reference covers a unit when it:
  - cites the path of one of the unit's files, or the unit's directory path, either from the
    project root or relative to the unit's own git repo (that form needs a `/`, so a bare
    `types` never matches), or as the `@/` alias of a `src/` path;
  - cites in backticks an identifier defined in the unit (4+ characters), when that
    identifier is defined in at most 3 units (a name defined everywhere says nothing);
  - declares it in the front-matter `covers:` header. Entries are `axis: item` (parsed by
    docs-census.py `load_ownership`); the item is expanded through the profile's `paths:`
    template for that axis (docs-census.py `load_profile`) and also taken as a path as written.
    A path equal to a file or directory of the unit, or above it, covers it.
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import module_map  # noqa: E402

BUDGET = 20000
MIN_SYMBOL = 4
MAX_SYMBOL_UNITS = 3
SYMBOL_RE = re.compile(
    r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:def|class|function\*?)\s+([A-Za-z_]\w*)"
    r"|^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_]\w*)\s*=\s*(?:async\s*)?(?:\(|function\b|\w+\s*=>)",
    re.M)
TICKS_RE = re.compile(r"`([^`\n]+)`")
IDENT_RE = re.compile(r"[A-Za-z_]\w*")
COMPOUND_RE = re.compile(r"[a-z][A-Z]")
FRONT_RE = re.compile(r"\A---\n(.*?)\n---", re.S)
DROPPED_RE = re.compile(r"^status:\s*[\"']?dropped[\"']?\s*$", re.M)
_spec = importlib.util.spec_from_file_location(
    "docs_census", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs-census.py"))
census = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(census)


def compound(name):
    """snake_case or camelCase: specific enough to name a unit even when defined in a few."""
    return "_" in name.strip("_") or COMPOUND_RE.search(name) is not None


def slug(uid):
    return re.sub(r"^-|-$", "", re.sub(r"[^A-Za-z0-9]+", "-", uid))


def cites(text, path):
    """True when `path` appears in text as a whole path, not as the start of a longer one.
    A leading `./` or `../` run is allowed."""
    return path in text and re.search(
        r"(?<![\w./-])(?:\.{1,2}/)*" + re.escape(path) + r"(?![\w-]|\.\w|/[\w.])", text) is not None


def read_references(root):
    refs = {}
    base = Path(root) / ".context" / "references"
    for p in sorted(base.rglob("*.md")):
        rel = p.relative_to(base).as_posix()
        if rel in ("00-profile.md", "00-index.md"):
            continue
        text = p.read_text(errors="replace")
        # A dropped reference is nothing a maintainer would edit (BL-740).
        front = FRONT_RE.match(text)
        if front and DROPPED_RE.search(front.group(1)):
            continue
        refs[p.relative_to(root).as_posix()] = text
    return refs


def declared_paths(root, refs):
    """reference -> paths its `covers:` header names (templated through the profile, and as written)."""
    base = Path(root) / ".context" / "references"
    axes, problems, _ = census.load_profile(base / "00-profile.md")
    template = {a.name: a.paths for a in axes if a.paths}
    owners, _, _, more = census.load_ownership(base)
    for line in problems + more:
        print(f"prepare: {line}", file=sys.stderr)
    out = {r: set() for r in refs}
    for axis, items in owners.items():
        for item, docs in items.items():
            cands = {item.strip("/")}
            if axis in template:
                cands.add(template[axis].replace("{item}", item).strip("/"))
            for d in docs:
                if d in out:
                    out[d] |= {c for c in cands if c}
    return out


def forms(unit):
    """(root-relative paths, repo-relative and `@/` paths) naming the unit's files and directory."""
    root_rel = [p for p in unit["files"] + [unit["path"]] if p != "."]
    strip = "" if unit["repo"] == "." else unit["repo"] + "/"
    repo_rel = [p[len(strip):] for p in root_rel if strip and p.startswith(strip)]
    repo_rel = [p for p in repo_rel if "/" in p]
    alias = ["@/" + p[4:] for p in
             [p[len(strip):] for p in root_rel if p.startswith(strip)] if p.startswith("src/")]
    return root_rel, repo_rel + alias


def declares(path, unit):
    """Does a `covers:` path name the unit: one of its files, its directory, or a directory above."""
    root_rel, repo_rel = forms(unit)
    return (path in root_rel + repo_rel
            or any(p.startswith(path + "/") for p in root_rel)
            or "/" in path and any(p.startswith(path + "/") for p in repo_rel))


def refuse_tracked_work(root, work):
    """The work dir's `units/` is deleted on every run: never the project root or tracked files."""
    if work == root:
        print(f"prepare: work dir {work} is the project root", file=sys.stderr)
        sys.exit(2)
    if root in work.parents:
        near = work
        while not near.exists():
            near = near.parent
        r = subprocess.run(["git", "-C", str(near), "ls-files", "--", str(work)],
                           capture_output=True, text=True)
        if r.stdout.strip():
            print(f"prepare: work dir {work} holds files git tracks", file=sys.stderr)
            sys.exit(2)


def prepare(root, work, budget=BUDGET):
    root, work = Path(root).resolve(), Path(work).resolve()
    refuse_tracked_work(root, work)
    _, _, files = module_map.collect(str(root))
    all_units = module_map.build_units(files, budget)

    defined = {}  # identifier -> ids of the units defining it
    for u in all_units:
        for f in u["files"]:
            for m in SYMBOL_RE.finditer(files[f][2]):
                name = m.group(1) or m.group(2)
                if len(name) >= MIN_SYMBOL:
                    defined.setdefault(name, set()).add(u["id"])

    refs = read_references(root)
    by_symbol = {}  # reference -> units owning an identifier it cites in backticks
    for r, t in refs.items():
        names = {i for span in TICKS_RE.findall(t) for i in IDENT_RE.findall(span)}
        by_symbol[r] = {u for n in names
                        if len(defined.get(n, ())) == 1
                        or 0 < len(defined.get(n, ())) <= MAX_SYMBOL_UNITS and compound(n)
                        for u in defined[n]}
    header = declared_paths(root, refs)

    kept, skipped = [], []
    for u in all_units:
        names = sum(forms(u), [])
        covering = [r for r, text in refs.items()
                    if any(cites(text, p) for p in names) or u["id"] in by_symbol[r]
                    or any(declares(p, u) for p in header[r])]
        if not covering:
            continue
        if u["extract"]:
            kept.append({"unit": u["id"], "slug": slug(u["id"]), "files": u["files"],
                         "references": covering, "tokens_est": u["tokens_est"]})
        else:
            skipped.append({"unit": u["id"], "references": covering,
                            "reason": "oversize" if u["oversize"] else "data-like"})

    (work / "manifest.json").unlink(missing_ok=True)  # a failed run leaves no old selection
    seen = {}
    for k in kept:
        if seen.setdefault(k["slug"], k["unit"]) != k["unit"]:
            sys.exit(f"slug collision: units {seen[k['slug']]!r} and {k['unit']!r} "
                     f"both map to {k['slug']!r}")

    shutil.rmtree(work / "units", ignore_errors=True)
    (work / "units").mkdir(parents=True)
    for k in kept:
        (work / "units" / f"{k['slug']}.txt").write_text("\n".join(k["files"]) + "\n")
        (work / "units" / f"{k['slug']}.refs.txt").write_text("\n".join(k["references"]) + "\n")
    manifest = {"project": root.name, "root": str(root), "units": kept, "skipped": skipped}
    (work / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    return manifest


if __name__ == "__main__":
    m = prepare(sys.argv[1], sys.argv[2])
    print(f"{m['project']}: {len(m['units'])} covered units, {len(m['skipped'])} covered but skipped")
