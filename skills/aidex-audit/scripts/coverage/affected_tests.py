#!/usr/bin/env python3
"""Affected-tests resolver — dev-time answer to "I changed something, what do
I run?". Module-level impact only (non-goal: per-line TIA).

CLI: affected_tests.py <workspace-root> [--since <ref>]

Changed-file collection per repo:
  - default: working tree + staged (`git status --porcelain`)
  - --since <ref>: `git diff --name-only <ref>..HEAD` per repo; repos where the
    ref doesn't exist are skipped with a warning (repos have independent
    histories)

Prints affected modules (test path groups + rendered test_hint) and any
changed files that matched no module, under "Unmapped changes". Never
executes tests — E2E execution stays exclusively behind each project's
test-e2e.sh, per global rules.

Exit 0 always, except exit 2 on hard errors (no map, git failure).
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _coverage_lib as lib


def repo_dir_for(root, repo):
    return root if repo["path"] in (".", "") else os.path.join(root, repo["path"])


def repo_prefix_for(repo):
    return "" if repo["path"] in (".", "") else repo["path"] + "/"


def parse_status_line(line):
    """`git status --porcelain` line -> repo-relative path (last token, handles
    rename arrows and quoted paths)."""
    rest = line[3:] if len(line) > 3 else line.strip()
    if " -> " in rest:
        rest = rest.split(" -> ")[-1]
    return rest.strip().strip('"')


def status_changes(root, repo):
    """Working tree + staged changes for one repo, as workspace-relative paths."""
    repo_dir = repo_dir_for(root, repo)
    out = lib.git(repo_dir, "status", "--porcelain")
    prefix = repo_prefix_for(repo)
    files = []
    for line in out.splitlines():
        if not line.strip():
            continue
        files.append(prefix + parse_status_line(line))
    return files


def diff_changes(root, repo, since):
    """Changes since `since` for one repo. Returns None (with a stderr warning)
    if `since` doesn't resolve in this repo's history."""
    repo_dir = repo_dir_for(root, repo)
    check = subprocess.run(
        ["git", "-C", repo_dir, "rev-parse", "--verify", "--quiet", since],
        capture_output=True, text=True,
    )
    if check.returncode != 0:
        print(
            f"WARNING: ref {since!r} not found in repo {repo['name']} — skipping",
            file=sys.stderr,
        )
        return None
    out = lib.git(repo_dir, "diff", "--name-only", f"{since}..HEAD")
    prefix = repo_prefix_for(repo)
    return [prefix + line for line in out.splitlines() if line.strip()]


def collect_changed_files(root, repos, since):
    files = []
    for repo in repos:
        changed = diff_changes(root, repo, since) if since else status_changes(root, repo)
        if changed is None:
            continue
        files.extend(changed)
    return files


def glob_to_dir(glob):
    """Test glob -> displayable directory ('**' stripped, trailing '*' kept
    minimal). 'a/b/**' -> 'a/b/', 'a/b/*' -> 'a/b/'."""
    d = glob
    if d.endswith("**"):
        d = d[:-2]
    elif d.endswith("*"):
        d = d[:-1]
    return d


def render_hint(root, repos, glob):
    """(display_dir, hint) for a single test glob, or (display_dir, None) if no
    repo owns it or it has no test_hint."""
    display_dir = glob_to_dir(glob)
    repo = lib.repo_for(display_dir.rstrip("/"), repos)
    if repo is None:
        return display_dir, None
    test_hint = repo.get("test_hint")
    if not test_hint:
        return display_dir, None
    rel = lib.to_repo_relative(display_dir, repo)
    return display_dir, test_hint.replace("{path}", rel)


def affected_modules(root, repos, modules, changed_files):
    """(module rows, unmapped files)."""
    rows = []
    unmapped = list(changed_files)
    for mod in modules:
        src_globs = mod.get("src", [])
        matched = [f for f in changed_files if lib.matches(f, src_globs)]
        if not matched:
            continue
        unmapped = [f for f in unmapped if f not in matched]

        groups = []
        tests = mod.get("tests", {}) or {}
        for kind in ("unit", "e2e"):
            globs = tests.get(kind) or []
            if not globs:
                continue
            display_dir, hint = render_hint(root, repos, globs[0])
            groups.append((kind, display_dir, hint))

        rows.append({"id": mod["id"], "groups": groups, "changed": matched})
    return rows, sorted(set(unmapped))


def render(rows, unmapped, n_changed):
    lines = []
    lines.append(
        f"AFFECTED TESTS — {n_changed} changed file{'s' if n_changed != 1 else ''}, "
        f"{len(rows)} module{'s' if len(rows) != 1 else ''}"
    )
    for row in rows:
        lines.append(f"[{row['id']}]")
        if not row["groups"]:
            lines.append("  (no tests mapped for this module)")
            continue
        label_w = max(len(kind) for kind, _, _ in row["groups"])
        dir_w = max(len(d) for _, d, _ in row["groups"])
        for kind, display_dir, hint in row["groups"]:
            label = (kind + ":").ljust(label_w + 1)
            dir_part = display_dir.ljust(dir_w)
            if hint:
                lines.append(f"  {label} {dir_part} hint: {hint}")
            else:
                lines.append(f"  {label} {dir_part}")
    if unmapped:
        lines.append("Unmapped changes (extend module-map?):")
        for f in unmapped:
            lines.append(f"  {f}")
    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    since = None
    positional = []
    i = 0
    while i < len(args):
        if args[i] == "--since":
            if i + 1 >= len(args):
                sys.exit("usage: affected_tests.py <workspace-root> [--since <ref>]")
            since = args[i + 1]
            i += 2
        else:
            positional.append(args[i])
            i += 1
    if not positional:
        sys.exit("usage: affected_tests.py <workspace-root> [--since <ref>]")
    root = positional[0]

    try:
        m = lib.load_map(root)
        changed_files = collect_changed_files(root, m["repos"], since)
    except SystemExit as e:
        print(e, file=sys.stderr)
        sys.exit(2)

    if not changed_files:
        print("AFFECTED TESTS — 0 changed files, 0 modules")
        sys.exit(0)

    rows, unmapped = affected_modules(root, m["repos"], m["modules"], changed_files)
    print(render(rows, unmapped, len(changed_files)))
    sys.exit(0)


if __name__ == "__main__":
    main()
