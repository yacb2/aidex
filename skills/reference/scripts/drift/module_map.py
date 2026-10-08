"""Code units for reference drift: files grouped by directory under a token budget.

Library for prepare.py (no CLI). Ported from the WF-001 pilot module-map.py without
import edges, `--since` or the CLI. Stdlib only.
"""
import os
import re
import subprocess

SKIP_DIRS = {"node_modules", "_wt", "_tmp", "_backups", ".git"}
EXCLUDE_COMPONENTS = {".context", ".claude", "migrations"}
LOCKFILES = {"package-lock.json", "pnpm-lock.yaml", "yarn.lock", "poetry.lock", "uv.lock"}
BINARY_EXT = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp", ".tiff", ".svg", ".pdf",
    ".woff", ".woff2", ".ttf", ".otf", ".eot", ".zip", ".gz", ".tar", ".tgz", ".mp3",
    ".mp4", ".mov", ".webm", ".wav", ".pyc", ".so", ".dylib", ".exe", ".bin", ".sqlite",
    ".sqlite3", ".db", ".parquet", ".wasm", ".jar",
}


def run_git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, check=True)
    return r.stdout.decode("utf-8", "replace")


def find_repos(root):
    """Absolute paths of every git repo at or below root (worktrees skipped)."""
    repos = []
    for dp, dns, fns in os.walk(root):
        dns[:] = sorted(d for d in dns if d not in SKIP_DIRS)
        g = os.path.join(dp, ".git")
        if os.path.isdir(g):
            repos.append(dp)
        elif os.path.isfile(g):
            with open(g, errors="replace") as f:
                if "/worktrees/" not in f.read():
                    repos.append(dp)  # submodule-style checkout
            dns[:] = []  # a worktree is never mapped, its main repo is
    return sorted(repos)


def excluded(rel):
    parts = rel.split("/")
    name = parts[-1]
    if any(p in EXCLUDE_COMPONENTS for p in parts[:-1]):
        return True
    if name in LOCKFILES or ".min." in name:
        return True
    return os.path.splitext(name)[1].lower() in BINARY_EXT


def read_text_file(path):
    """(bytes, text) or None when missing, unreadable or binary (NUL in first 8 KB)."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if b"\0" in data[:8192]:
        return None
    return len(data), data.decode("utf-8", "replace")


def collect(root):
    """Return repos [(abs, rel)], files {rel: (repo_rel, tokens, text)}."""
    abs_repos = find_repos(root)
    rels = [os.path.relpath(r, root).replace(os.sep, "/") for r in abs_repos]
    files = {}
    for ab, rr in zip(abs_repos, rels):
        prefix = "" if rr == "." else rr + "/"
        nested = [x + "/" for x in rels if x != rr and (rr == "." or x.startswith(prefix))]
        for f in run_git(ab, "ls-files", "-z").split("\0"):
            if not f:
                continue
            rel = prefix + f
            if any(rel.startswith(n) for n in nested) or excluded(rel):
                continue
            got = read_text_file(os.path.join(root, rel))
            if got is None:
                continue
            files[rel] = (rr, got[0] // 4, got[1])
    return rels, abs_repos, files


DATA_EXT = {".jsonl", ".json", ".csv", ".tsv", ".ndjson", ".log", ".txt", ".lock"}


def skipped(rel, tok, budget):
    """Files the workflow must not extract: over budget, or data-like and over budget/4."""
    return tok > budget or (os.path.splitext(rel)[1].lower() in DATA_EXT and tok > budget / 4)


def build_units(files, budget):
    """Group files into units by directory under the token budget."""
    by_repo = {}
    for rel, (rr, tok, _) in files.items():
        by_repo.setdefault(rr, []).append((rel, tok))
    units = []

    def total(fs):
        return sum(t for _, t in fs)

    def emit(uid, repo, path, fs, oversize=False, extract=True):
        if fs:
            units.append({"id": uid, "repo": repo, "path": path,
                          "files": sorted(r for r, _ in fs), "tokens_est": total(fs),
                          "oversize": oversize, "extract": extract})

    def walk(repo, dirpath, fs):
        if total(fs) <= budget:
            emit(dirpath, repo, dirpath, fs)
            return
        prefix = "" if dirpath == "." else dirpath + "/"
        direct, children = [], {}
        for rel, t in fs:
            rest = rel[len(prefix):]
            if "/" in rest:
                children.setdefault(rest.split("/", 1)[0], []).append((rel, t))
            else:
                direct.append((rel, t))
        chunks, chunk = [], []  # a wide flat directory is packed, in path order, into units within budget
        for item in sorted(direct):
            if chunk and total(chunk) + item[1] > budget:
                chunks.append(chunk)
                chunk = []
            chunk.append(item)
        if chunk:
            chunks.append(chunk)
        for n, c in enumerate(chunks, 1):
            emit(f"{dirpath}/(files)" if len(chunks) == 1 else f"{dirpath}/(files-{n})", repo, dirpath, c)
        for name in sorted(children):
            walk(repo, prefix + name, children[name])

    for repo, fs in by_repo.items():
        heavy = [(r, t) for r, t in fs if skipped(r, t, budget)]
        for rel, t in heavy:
            emit(rel, repo, rel, [(rel, t)], oversize=t > budget, extract=False)
        normal = [x for x in fs if x not in heavy]
        if normal:
            walk(repo, repo, normal)
    return sorted(units, key=lambda u: u["id"])
