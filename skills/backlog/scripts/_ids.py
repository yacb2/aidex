"""_ids.py — what renumber-ids.py and migrate-filenames.py share. Imported, never run.

Both scripts rewrite BL-NNN ids or filenames across the same project surface, so the
id shape, the files they scan and the project-root rule live here once.
"""

import os
import re
import subprocess
from pathlib import Path

CONFORMING = re.compile(r"^BL-\d{3,5}$")  # register-item.sh mints 3-5 digits
SCAN_SUFFIXES = {".md", ".html", ".json", ".txt", ".yml", ".yaml"}
SCAN_NAMES = {".aidex-waivers"}


def _git(start: Path, *args: str):
    try:
        r = subprocess.run(["git", "-C", str(start), "rev-parse", *args],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else None


def find_root(start: Path) -> Path:
    """The nearest ancestor holding `.context/`, never climbing into $HOME (a stray
    ~/.context must not capture a project with none). A linked git worktree is a sibling
    of its project, so when the walk finds none the main worktree answers, as in
    conventions/scripts/_lib.sh find_project_root. Otherwise `start` itself."""
    d = start.resolve()
    home = os.environ.get("HOME")
    stop = Path(home).resolve() if home and Path(home).is_dir() else None
    while d != d.parent:
        if stop is not None and d == stop:
            break
        if (d / ".context").is_dir():
            return d
        d = d.parent
    common = _git(start, "--path-format=absolute", "--git-common-dir")
    gitdir = _git(start, "--absolute-git-dir")
    if common and gitdir and Path(common).resolve() != Path(gitdir).resolve():
        main = Path(common).resolve().parent
        if main != stop:
            return main
    return start.resolve()


def memory_dir(root: Path):
    base = "-" + str(root).lstrip("/").replace("/", "-")
    for slug in (base, base.replace("_", "-")):
        d = Path.home() / ".claude" / "projects" / slug / "memory"
        if d.is_dir():
            return d
    return None


def scan_targets(root: Path, ctx: Path):
    files = [p for p in ctx.rglob("*")
             if p.is_file() and "/_tmp/" not in str(p)
             and (p.suffix in SCAN_SUFFIXES or p.name in SCAN_NAMES)]
    if (root / "CLAUDE.md").is_file():
        files.append(root / "CLAUDE.md")
    md = memory_dir(root)
    if md:
        files.extend(md.rglob("*.md"))
    return files
