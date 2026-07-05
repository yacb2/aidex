#!/usr/bin/env python3
"""Shared library for aidex-audit coverage tooling. Stdlib only."""
import functools
import json, os, re, subprocess, sys


def load_map(root):
    path = os.path.join(root, ".context", "audits", "test-coverage", "module-map.json")
    if not os.path.isfile(path):
        sys.exit(f"ERROR: no module-map at {path} — run the test-coverage playbook first")
    with open(path) as f:
        m = json.load(f)
    for key in ("version", "repos", "modules"):
        if key not in m:
            sys.exit(f"ERROR: module-map missing key: {key}")
    for repo in m["repos"]:
        for key in ("name", "path"):
            if key not in repo:
                sys.exit(f"ERROR: repo {repo.get('name','?')} missing key: {key}")
    for mod in m["modules"]:
        for key in ("id", "src", "tests"):
            if key not in mod:
                sys.exit(f"ERROR: module {mod.get('id','?')} missing key: {key}")
    return m


@functools.lru_cache(maxsize=None)
def glob_to_re(pattern):
    """Workspace-relative glob -> regex. '**' spans dirs, '*' stays within one."""
    out, i = "", 0
    while i < len(pattern):
        c = pattern[i]
        if pattern[i:i + 2] == "**":
            out += ".*"; i += 2
            if i < len(pattern) and pattern[i] == "/": i += 1
        elif c == "*":  out += "[^/]*"; i += 1
        elif c == "?":  out += "[^/]";  i += 1
        else:           out += re.escape(c); i += 1
    return re.compile("^" + out + ("$" if pattern.endswith(("*", "?")) else "(/.*)?$"))


def matches(path, patterns):
    return any(glob_to_re(p).match(path) for p in patterns)


def repo_for(path, repos):
    """Most-specific match wins: the repo whose path is the LONGEST prefix of `path`
    ('.'/'' count as a zero-length prefix, so a nested repo always beats the root)."""
    best, best_len = None, -1
    for r in repos:
        p = r["path"]
        if p in (".", ""):
            plen = 0
        elif path == p or path.startswith(p + "/"):
            plen = len(p)
        else:
            continue
        if plen > best_len:
            best, best_len = r, plen
    return best


def to_repo_relative(path, repo):
    p = repo["path"]
    return path if p in (".", "") else path[len(p) + 1:]


def git(repo_dir, *args):
    res = subprocess.run(["git", "-C", repo_dir, *args],
                          capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(f"ERROR: git {' '.join(args)} in {repo_dir}: {res.stderr.strip()}")
    return res.stdout


def list_files(root, repos):
    """All tracked files per repo, as workspace-relative paths."""
    files = []
    for r in repos:
        repo_dir = os.path.join(root, r["path"]) if r["path"] not in (".", "") else root
        prefix = "" if r["path"] in (".", "") else r["path"] + "/"
        for line in git(repo_dir, "ls-files").splitlines():
            files.append(prefix + line)
    return files


def commits_since(root, repo, since, workspace_globs):
    """Count commits since ISO date touching any of the globs (repo-relative pathspecs)."""
    own = [g for g in workspace_globs if repo_for(g.split("*")[0].rstrip("/"), [repo])]
    if not own:
        return 0
    specs = [":(glob)" + to_repo_relative(g, repo) for g in own]
    repo_dir = os.path.join(root, repo["path"]) if repo["path"] not in (".", "") else root
    out = git(repo_dir, "log", "--oneline", f"--since={since}", "--", *specs)
    return len(out.splitlines())


TEST_PATTERNS = [re.compile(r"\btest(\.\w+)?\s*\("), re.compile(r"\bdef test_")]


def count_tests(root, files):
    n = 0
    for f in files:
        try:
            with open(os.path.join(root, f), errors="ignore") as fh:
                text = fh.read()
            n += sum(len(p.findall(text)) for p in TEST_PATTERNS)
        except OSError:
            pass
    return n


if __name__ == "__main__":
    # Tiny CLI so validate-audit.sh can check that module-map.json parses:
    #   python3 _coverage_lib.py load <workspace-root>
    # Exits 0 on a valid map, non-zero (with an ERROR message) otherwise.
    if len(sys.argv) >= 3 and sys.argv[1] == "load":
        load_map(sys.argv[2])
        sys.exit(0)
    sys.exit("usage: _coverage_lib.py load <workspace-root>")
