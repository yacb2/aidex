#!/usr/bin/env python3
"""Affected-tests resolver — dev-time answer to "I changed something, what do
I run?". Two tiers: a changed file with a COLOCATED test narrows to it
(all-or-nothing per module, BL-212); otherwise module-level impact
(non-goal: per-line TIA). The full suite gates integration, never the
inner loop (decision 2026-08-24).

CLI: affected_tests.py <workspace-root> [--since <ref>] [--command]

--command prints ONE runnable unit-test command per repo (paths merged) and
nothing else, so a caller can run the selection directly instead of composing it
from the human-readable report. Exit 3 means "no selection available" — no map, git
failure, no changed files, nothing matched, or only advisories (e2e-only match,
no test_hint) — and the caller must fall back to the full suite and say so. The
reason is always on stderr.

Changed-file collection per repo:
  - default: working tree + staged (`git status --porcelain`)
  - --since <ref>: `git diff --name-only <ref>..HEAD` per repo; repos where the
    ref doesn't exist are skipped with a warning (repos have independent
    histories)

Prints affected modules (test path groups + rendered test_hint) and any
changed files that matched no module, under "Unmapped changes". Never
executes tests — E2E execution stays exclusively behind each project's
test-e2e.sh, per global rules.

Exit 0 always, except exit 2 on hard errors (no map, git failure, or a
module-map path that cannot be safely rendered into a shell command).

--out <dir>: read module-map.json from, and write any output to, <dir>
instead of <workspace-root>/.context/audits/test-coverage — the read-only
mode for auditing a workspace you must not write into (BL-204).
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _coverage_lib as lib
import defect_prone

# Anything that is not a path or a glob. `--command` output is executed by the
# caller, so a map entry containing any of these is refused, not emitted.
#
# Whitespace is in the class because paths are joined with spaces and never
# quoted (globs must expand): a rel containing a space word-splits into two bogus
# paths, and one that *starts* with a dash (`-rf`, `--rootdir=x`) arrives at the
# runner as an OPTION, not a path — hence the leading `-`/`~` alternative (`~` is
# expanded by the shell before the runner sees it).
UNSAFE = re.compile(r'[;&|`$(){}<>\s\\"\']|^[-~]')


class UnsafeMapEntry(Exception):
    """A module-map path that cannot be safely rendered into a shell command."""


def repo_prefix_for(repo):
    return "" if repo["path"] in (".", "") else repo["path"] + "/"


def parse_status_line(line):
    """`git status --porcelain` line -> repo-relative path (last token, handles
    rename arrows and quoted paths). Every line is `XY<space><path>`."""
    rest = line[3:]
    if " -> " in rest:
        rest = rest.split(" -> ")[-1]
    return rest.strip().strip('"')


def status_changes(root, repo):
    """Working tree + staged changes for one repo, as workspace-relative paths."""
    repo_dir = lib.repo_dir(root, repo)
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
    repo_dir = lib.repo_dir(root, repo)
    # Kept as a direct subprocess.run rather than lib.git on purpose: lib.git
    # sys.exit()s on any non-zero return, and a ref missing from ONE repo must be
    # a warning + skip (repos have independent histories), not a hard stop.
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
    skipped = 0
    for repo in repos:
        changed = diff_changes(root, repo, since) if since else status_changes(root, repo)
        if changed is None:
            skipped += 1
            continue
        files.extend(changed)
    # Skipping one repo is a partial result; skipping ALL of them is "nothing was
    # checked", which must not come back as "nothing changed".
    if since and repos and skipped == len(repos):
        sys.exit(f"ERROR: ref {since!r} not found in any repo — nothing was checked")
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


# Test-file extensions a colocated JS/TS test can carry.
TEST_EXTS = (".ts", ".tsx", ".js", ".jsx", ".mjs", ".mts")


def colocated_tests(root, path, test_globs):
    """Changed workspace-relative file -> the test files that plainly name it.

    File-granularity selection (BL-212): at real module sizes the module tier
    barely selects (echo_lab's `timeline` is 170 of 322 test files — mapping a
    diff to it recovers 16% of the wall clock where the one colocated file
    recovers 92%). The signal is deliberately the CHEAPEST one: a test file
    named after the changed file, in the same directory or its __tests__/ /
    tests/ sibling. No import graph, no coverage data — a file this rule
    cannot find keeps the module tier (see the all-or-nothing rule at the
    call site), because a narrow-but-wrong selection is worse than a wide one.
    A changed file that is itself one of the module's tests targets itself.
    """
    if lib.matches(path, test_globs):
        return [path]
    d, base = os.path.split(path)
    name, _ = os.path.splitext(base)
    cands = []
    for sub in ("", "__tests__", "tests"):
        pdir = os.path.join(d, sub) if sub else d
        cands.append(os.path.join(pdir, f"test_{name}.py"))
        cands.append(os.path.join(pdir, f"test-{name}.sh"))
        for infix in (".test", ".spec"):
            for ext in TEST_EXTS:
                cands.append(os.path.join(pdir, name + infix + ext))
    return [c for c in cands if os.path.isfile(os.path.join(root, c))]


def affected_modules(root, repos, modules, changed_files):
    """(module rows, unmapped files)."""
    rows = []
    unmapped = list(changed_files)
    for mod in modules:
        # A change belongs to the module if it touches its src OR its tests —
        # a modified test file must attribute here, not read as "unmapped".
        tests = mod.get("tests", {}) or {}
        # Raw `src`, NOT lib.src_matches: `src_exclude` (BL-229) is coverage
        # ACCOUNTING, not change ATTRIBUTION. A changed co-located fixture can
        # break the tests that read it, so it must still select this module
        # rather than fall through to "Unmapped changes".
        own_globs = list(mod.get("src", []))
        for kind_globs in tests.values():
            own_globs.extend(kind_globs or [])
        matched = [f for f in changed_files if lib.matches(f, own_globs)]
        if not matched:
            continue
        unmapped = [f for f in unmapped if f not in matched]

        groups = []
        # Repo-aware module tier (BL-272): a functional module maps both repos
        # of a two-repo workspace, and emitting every glob of every kind for a
        # change in either printed ~240 Vitest files next to the pytest line
        # for a Django-only edit. A non-e2e glob stays only when its repo is
        # the repo of a changed file; e2e crosses repos by nature and stays.
        # A glob or file no repo owns keeps the glob — wide, never wrong.
        # What this deliberately does NOT do: widen across the API contract
        # (a serializer rename still needs the frontend tests) — that is a
        # blindspot expansion named in the profile, not this tier.
        changed_repos = {r["name"] for r in (lib.repo_for(f, repos) for f in matched) if r}
        # Every kind, not ("unit", "e2e"): the keys are open-ended
        # (06-test-coverage.md), and a module mapped only through a third kind
        # read as "no tests mapped". A non-e2e kind runs through the repo's
        # test_hint exactly as unit does.
        for kind, kind_globs in tests.items():
            for glob in kind_globs or []:
                display_dir, hint = render_hint(root, repos, glob)
                if kind != "e2e" and changed_repos:
                    owner = lib.repo_for(display_dir.rstrip("/"), repos)
                    if owner and owner["name"] not in changed_repos:
                        continue
                groups.append((kind, display_dir, hint))

        # All-or-nothing narrowing (BL-212): the module's selection narrows to
        # colocated test files ONLY when every changed file in it has one.
        # A module where any changed file is un-targeted keeps the whole-module
        # tier — src/lib-shaped fan-out surfaces (36 feature tests reading
        # i18n locales in the measured case) are exactly what a partial narrow
        # would silently miss. Fast and wrong is the one outcome this refuses.
        test_globs = [g for kind_globs in tests.values() for g in (kind_globs or [])]
        targeted, complete = [], True
        for f in matched:
            hits = colocated_tests(root, f, test_globs)
            if hits:
                targeted.extend(hits)
            else:
                complete = False
        rows.append({"id": mod["id"], "groups": groups, "changed": matched,
                     "targeted": sorted(set(targeted)) if complete and targeted else None})
    return rows, sorted(set(unmapped))


def render(rows, unmapped, n_changed):
    lines = []
    lines.append(
        f"AFFECTED TESTS — {n_changed} changed file{'s' if n_changed != 1 else ''}, "
        f"{len(rows)} module{'s' if len(rows) != 1 else ''}"
    )
    for row in rows:
        lines.append(f"[{row['id']}]")
        if row.get("targeted"):
            lines.append("  targeted: " + " ".join(row["targeted"])
                         + "   (colocated; the selection narrows to these — "
                           "the full suite still gates integration)")
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


def render_commands(root, repos, rows, unmapped):
    """One runnable unit-test command per repo plus `#` advisory lines, or None when
    there is nothing at all to say. Advisories are emitted even when no command
    renders: main() decides between exit 0 and exit 3 by whether a runnable line
    exists, so an e2e-only or no-test_hint match still tells the caller why.

    Why combined and not per-module (BL-135): a containerised run carries a fixed
    per-invocation floor — `docker compose run --rm` has a 15 s median and a 114 s p90
    before a single test executes. Emitting one command per affected module turns a
    3-module change into 3 round-trips through that floor, which can cost more than the
    selection saves. Repos share a `test_hint`, so the paths merge into one invocation.

    E2E is deliberately excluded: execution stays behind each project's `test-e2e.sh`
    (global rule), so specs are surfaced as a comment, never as a command to run.

    TRUST BOUNDARY. Paths are *data* and are validated against UNSAFE below. A repo's
    `test_hint` is *not* — it is a shell-command template by design (`cd backend &&
    pytest {path}`), so the metacharacters that are an attack in a path are the
    feature in a hint, and validating it would reject every real map. The boundary
    is therefore the module-map file itself: it carries the same trust as any
    checked-in build script in the repo. Anyone who can edit it can already run code
    via a hundred other paths. What must never happen is *path data* escaping into
    the command position, and that is what the validation prevents.
    """
    by_repo = {}          # repo name -> (test_hint, [repo-relative dirs])
    e2e_specs = []
    no_command = []       # affected modules that yield no runnable command
    no_tests = []         # affected modules with no tests mapped at all
    narrowed = []
    for row in rows:
        if not row["groups"]:
            no_tests.append(row["id"])
        # Narrowed module (BL-212): the colocated test files replace the module
        # dirs in the runnable selection; its e2e globs stay surfaced as the
        # usual advisory. Anything that stops the narrow tier from rendering
        # (no repo, no test_hint) falls back to the module tier rather than
        # dropping the module from the selection.
        if row.get("targeted"):
            ok = True
            for tf in row["targeted"]:
                repo = lib.repo_for(tf, repos)
                if repo is None or not repo.get("test_hint"):
                    ok = False
                    break
            if ok:
                for tf in row["targeted"]:
                    repo = lib.repo_for(tf, repos)
                    slot = by_repo.setdefault(repo["name"], (repo["test_hint"], []))
                    rel = lib.to_repo_relative(tf, repo)
                    if rel not in slot[1]:
                        slot[1].append(rel)
                narrowed.append(row["id"])
                for kind, display_dir, hint in row["groups"]:
                    if kind == "e2e":
                        e2e_specs.append(display_dir)
                continue
        for kind, display_dir, hint in row["groups"]:
            if kind == "e2e":
                e2e_specs.append(display_dir)
                continue
            repo = lib.repo_for(display_dir.rstrip("/"), repos)
            if repo is None or not repo.get("test_hint"):
                # Dropping this silently is a fail-open: the caller runs a
                # selection that omits real tests while reading as complete.
                no_command.append(row["id"])
                continue
            slot = by_repo.setdefault(repo["name"], (repo["test_hint"], []))
            rel = lib.to_repo_relative(display_dir, repo)
            if rel not in slot[1]:
                slot[1].append(rel)

    # This output is meant to be RUN. A map entry carrying shell metacharacters
    # would execute as part of the command, so refuse rather than emit it.
    # Globs stay legal — pytest relies on the shell expanding `test_auth_*.py`,
    # so quoting the paths is not an option and validation is.
    for name, (hint, rels) in by_repo.items():
        for rel in rels:
            bad = UNSAFE.search(rel)
            if bad:
                raise UnsafeMapEntry(
                    f"unsafe path in module-map for repo {name!r}: {rel!r} "
                    f"contains {bad.group(0)!r}. --command output is executed; "
                    "only glob characters (* ?) are allowed beyond a path.")
    for spec in e2e_specs:
        bad = UNSAFE.search(spec)
        if bad:
            raise UnsafeMapEntry(
                f"unsafe e2e path in module-map: {spec!r} contains {bad.group(0)!r}")

    lines = []
    for _, (hint, rels) in sorted(by_repo.items()):
        lines.append(hint.replace("{path}", " ".join(rels)))
    if narrowed:
        lines.append("# targeted: " + ", ".join(sorted(narrowed))
                     + " narrowed to colocated test file(s) — the full suite still "
                       "gates integration (decision 2026-08-24)")
    if no_command:
        mods = ", ".join(sorted(set(no_command)))
        lines.append(f"# INCOMPLETE: {len(set(no_command))} affected module(s) have no "
                     f"runnable command (no test_hint on their repo): {mods} — "
                     "their tests are NOT in the selection above")
    if no_tests:
        lines.append(f"# INCOMPLETE: {len(no_tests)} changed module(s) have no tests mapped: "
                     + ", ".join(sorted(no_tests)))

    # An unmapped change means the selection does not cover everything that moved.
    # Saying so is the difference between a faster loop and a false all-clear.
    if unmapped:
        lines.append(f"# INCOMPLETE: {len(unmapped)} changed file(s) match no module — "
                     "this selection does not cover them; unmapped scope still requires "
                     "the full suite before integration (decision 2026-08-24: the full-"
                     "suite gate sits at the integration boundary)")
    if e2e_specs:
        lines.append("# e2e specs affected — run ONLY these, one spec at a time (./test-e2e.sh <spec>, never playwright directly): "
                     + " ".join(sorted(set(e2e_specs))))
    return "\n".join(lines) if lines else None


USAGE = "usage: affected_tests.py <workspace-root> [--since <ref>] [--command] [--out <dir>]"


def main():
    args = sys.argv[1:]
    since = None
    as_command = False
    out_override = None
    positional = []
    i = 0
    while i < len(args):
        if args[i] in ("-h", "--help"):
            print(__doc__)
            sys.exit(0)
        elif args[i] == "--command":
            as_command = True
            i += 1
        elif args[i] == "--since":
            if i + 1 >= len(args):
                sys.exit(USAGE)
            since = args[i + 1]
            i += 2
        elif args[i] == "--out":
            if i + 1 >= len(args):
                sys.exit(USAGE)
            out_override = args[i + 1]
            i += 2
        elif args[i].startswith("-"):
            sys.exit(f"unknown option {args[i]!r}\n{USAGE}")
        else:
            positional.append(args[i])
            i += 1
    if not positional:
        sys.exit(USAGE)
    root = positional[0]

    try:
        m = lib.load_map(root, out_override)
        changed_files = collect_changed_files(root, m["repos"], since)
    except SystemExit as e:
        # --command is consumed by a caller deciding what to run, so a missing map or
        # a git failure is "no selection available" (exit 3), not a hard error. The
        # caller names the narrowest paths it can, or falls back to the full suite at the boundary, and says why — a silent empty result
        # would read as "nothing to run", inverting the always-on verification rule
        # at the loop level. The real error text still goes out, or the operator is
        # sent hunting for the wrong cause.
        if as_command:
            print(f"# {e} — no selection available; name the narrowest paths you can (the full suite is the boundary gate only)", file=sys.stderr)
            sys.exit(3)
        print(e, file=sys.stderr)
        sys.exit(2)

    if not changed_files:
        if as_command:
            print("# no changed files — nothing to select", file=sys.stderr)
            sys.exit(3)
        print("AFFECTED TESTS — 0 changed files, 0 modules")
        sys.exit(0)

    rows, unmapped = affected_modules(root, m["repos"], m["modules"], changed_files)

    # Advisory (BL-133 criterion 2), and it rides this call rather than adding a
    # step. It must reach the reader in BOTH modes: the two places that route here
    # — aidex-bugfix step 6 and plan-exec phase verification — both call
    # `--command`, so rendering only in human mode would ship a check nothing
    # calls, which is the BL-135 defect over again. stdout stays byte-identical
    # under `--command` (it is executed); stderr is where that mode already puts
    # everything it wants a reader to see.
    try:
        block = defect_prone.section(root, m["repos"], m["modules"], changed_files)
    except (Exception, SystemExit) as e:  # noqa: BLE001 - advisory must never gate
        print(f"WARNING: defect-prone check skipped: {e}", file=sys.stderr)
        block = None
    if block and as_command:
        print(block, file=sys.stderr)

    if as_command:
        try:
            cmds = render_commands(root, m["repos"], rows, unmapped)
        except UnsafeMapEntry as e:
            print(f"# refusing to emit a command: {e}", file=sys.stderr)
            sys.exit(2)
        if cmds is None:
            print("# changed files match no mapped module — no selection available; "
                  "name the narrowest paths you can (the full suite is the boundary gate only)", file=sys.stderr)
            sys.exit(3)
        if not any(not line.startswith("#") for line in cmds.splitlines()):
            # Only advisories (e2e pointer, INCOMPLETE reasons): nothing runnable, so
            # they belong on stderr and the exit is the full-suite fallback.
            print(cmds, file=sys.stderr)
            print("# no runnable unit selection; name the narrowest paths you can (the full suite is the boundary gate only)", file=sys.stderr)
            sys.exit(3)
        print(cmds)
        sys.exit(0)
    print(render(rows, unmapped, len(changed_files)))
    if block:
        print(block)
    sys.exit(0)


if __name__ == "__main__":
    main()
