#!/usr/bin/env python3
"""Shared library for aidex-audit coverage tooling. Stdlib only."""
import datetime
import functools
import json, os, re, subprocess, sys


def load_map(root, coverage_dir=None):
    """coverage_dir overrides <root>/.context/audits/test-coverage — the
    read-only mode (BL-204): map read from, and outputs written to, a
    directory outside the target workspace."""
    path = os.path.join(coverage_dir or os.path.join(
        root, ".context", "audits", "test-coverage"), "module-map.json")
    if not os.path.isfile(path):
        sys.exit(f"ERROR: no module-map at {path} — run the test-coverage playbook first")
    try:
        with open(path) as f:
            m = json.load(f)
    except ValueError as e:
        sys.exit(f"ERROR: module-map is not valid JSON: {e}")
    for key in ("version", "repos", "modules"):
        if key not in m:
            sys.exit(f"ERROR: module-map missing key: {key}")
    if not m["repos"]:
        # Every consumer iterates repos; with none, each returns an all-zero /
        # all-ok result that reads as an all-clear for a workspace never listed.
        sys.exit("ERROR: module-map declares no repos")
    for repo in m["repos"]:
        for key in ("name", "path"):
            if key not in repo:
                sys.exit(f"ERROR: repo {repo.get('name','?')} missing key: {key}")
    if not isinstance(m.get("unmapped_ok", []), list):
        # A string glob iterates character by character (same trap as tests
        # kinds below) — "backend/**" would become the globs b, a, c, ...
        sys.exit("ERROR: unmapped_ok must be a list of globs")
    for mod in m["modules"]:
        for key in ("id", "src", "tests"):
            if key not in mod:
                sys.exit(f"ERROR: module {mod.get('id','?')} missing key: {key}")
        # A string glob iterates character by character: "backend/**" becomes
        # the globs b, a, c, ... and its "*" then matches every top-level file.
        tests = mod["tests"] or {}
        if not isinstance(mod["src"], list) or not isinstance(tests, dict) \
                or not all(isinstance(g or [], list) for g in tests.values()):
            sys.exit(f"ERROR: module {mod['id']}: src and each tests kind must be a list of globs")
    return m


@functools.lru_cache(maxsize=None)
def glob_to_re(pattern):
    """Workspace-relative glob -> regex. '**' spans whole dirs, '*' stays within one."""
    pattern = pattern.rstrip("/") or pattern  # `a/b/` names the directory a/b
    out, i = "", 0
    while i < len(pattern):
        c = pattern[i]
        if pattern[i:i + 2] == "**":
            i += 2
            if i < len(pattern) and pattern[i] == "/":
                # Any number of WHOLE segments, zero included: `a/**/b` must not
                # match `a/xb`, which a bare `.*` did.
                out += "(?:.*/)?"; i += 1
            else:
                out += ".*"
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


def repo_dir(root, repo):
    """Filesystem directory of a repo: the workspace root itself for path '.'/''."""
    return root if repo["path"] in (".", "") else os.path.join(root, repo["path"])


def e2e_globs(mod):
    """A module's e2e test globs, [] when the key or the tests block is absent."""
    return (mod.get("tests", {}) or {}).get("e2e", []) or []


def test_globs(mod):
    """A module's test globs across EVERY kind. The `tests` keys are open-ended
    (06-test-coverage.md), so "the module's test files" is this union, not
    unit + e2e — a third kind must count as tests everywhere or nowhere."""
    return [g for globs in (mod.get("tests", {}) or {}).values() for g in (globs or [])]


def _repo_prefix(repo):
    return "" if repo["path"] in (".", "") else repo["path"] + "/"


def git(repo_dir, *args):
    # core.quotePath=false: git's default C-quotes any non-ASCII path
    # ("api/t\303\251st.py"), which then matches no glob and opens no file.
    res = subprocess.run(["git", "-C", repo_dir, "-c", "core.quotePath=false", *args],
                          capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(f"ERROR: git {' '.join(args)} in {repo_dir}: {res.stderr.strip()}")
    return res.stdout


def list_files(root, repos):
    """All tracked files per repo, as workspace-relative paths."""
    files = []
    for r in repos:
        for line in git(repo_dir(root, r), "ls-files").splitlines():
            files.append(_repo_prefix(r) + line)
    return files


def commits_since(root, repo, since, workspace_globs):
    """Count commits since ISO date touching any file the globs match.

    Files are attributed with the same matcher the matrix uses (`matches`), so
    a module's commit count and its file count come from ONE definition. The
    earlier repo-relative pathspec dropped any glob whose first wildcard sat
    above the repo path (`**/*.py` on a nested repo counted 0 commits for files
    it plainly matched), and git's own `:(glob)` disagreed with ours on `a/**/b`.
    """
    if not workspace_globs:
        return 0
    prefix = _repo_prefix(repo)
    return sum(
        1 for files in _commit_files(repo_dir(root, repo), since)
        if any(matches(prefix + f, workspace_globs) for f in files)
    )


@functools.lru_cache(maxsize=None)
def _commit_files(d, since):
    """Per commit since `since`, the tuple of repo-relative files it touched.
    One git call per (repo, since), shared by every module."""
    # `--since` is interpreted in LOCAL time, so an epoch-day sentinel like
    # "1970-01-01" becomes 1969-12-31T22:00Z in TZ +0200 — before the epoch. git
    # then silently matches nothing and the count reads as "no commits" rather than
    # "no lower bound". Callers pass an early date to mean all-time, so honour that
    # by dropping the flag instead of asking git for a negative timestamp.
    args = ["log", "--format=%x00%H", "--name-only"]
    if not _is_all_time(since):
        args.append(f"--since={since}")
    commits = []
    for chunk in git(d, *args).split("\0")[1:]:
        lines = [l for l in chunk.splitlines() if l]
        commits.append(tuple(lines[1:]))  # lines[0] is the hash
    return commits


def _is_all_time(since):
    """True when `since` is empty or early enough to be an all-time sentinel."""
    if not since:
        return True
    try:
        return datetime.date.fromisoformat(str(since)[:10]) <= datetime.date(1970, 1, 2)
    except ValueError:
        return False


# What counts as a test (06-test-coverage.md § What counts as a test): a
# `test(` / `it(` call, optionally through one modifier (`test.only(`,
# `it.skip(`, `test.each(`), or a pytest `def test_`. Structural calls
# (`test.describe(`, `test.beforeEach(`, `test.step(`) and `RegExp.test(` are
# not tests — the old `test(\.\w+)?` counted every one of them.
TEST_PATTERNS = [
    re.compile(r"(?<![\w.])(?:test|it)(?:\.(?:only|skip|todo|fixme|fails|concurrent|each))?\s*\("),
    re.compile(r"\bdef test_"),
]


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
