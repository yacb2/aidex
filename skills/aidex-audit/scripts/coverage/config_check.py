#!/usr/bin/env python3
"""config_check.py — read-only drift check for the suite-speed-and-coverage
configuration levers (Phase 4 of the 2026-08-22 suite-speed-and-coverage-rollout
plan).

Reads pyproject.toml, vitest.config.*, package.json and the Django settings
modules a project actually loads. Never runs a test, never starts a service,
never writes into a project. Reports NAME / KEY / VALUE — never a verdict; the
verdict is the human's, recorded as a finding.

A clean run is SILENT (compliance-sweep.sh's contract): the table prints only
when at least one enumerated project drifted. `--verbose` prints the full
table even when nothing drifted; `--json` always emits every row regardless
of drift, since it is the machine-readable roll-up, not the silent surface.

Five keys, per project:

  hasher_pytest     - does the settings module *pytest* loads put MD5 first?
  hasher_e2e        - does backend/config/settings/test_e2e.py put MD5 first?
  vitest_include    - does each vitest.config.* declare coverage.include?
  coverage_provider - is @vitest/coverage-v8 a real devDependency, and does
                       it agree with the declared coverage.provider?
  no_n_auto         - is `-n auto` / `--numprocesses` absent from project
                       configuration, and pytest-xdist absent from lockfiles?

Values: "present" | "absent" | "n/a" | "unresolvable" for hasher_pytest (the
DJANGO_SETTINGS_MODULE names a module that does not resolve to a file — the
anamnesis_poc_ws trap: a check keyed on config/settings/ would silently skip
this project and report it clean instead). Fractional keys (vitest_include,
coverage_provider) also carry a count/total pair.

Stdlib only.
"""
import json
import os
import re
import sys

# Directories never descended into while looking for vitest.config.* or
# package.json inside a project — vendored, generated, or explicitly archived
# copies that would inflate or corrupt the per-project denominator (the
# work_hours_ws trap: its own _archive/ carries two stale vitest.config.ts).
SKIP_DIRS = {
    "node_modules", "_archive", "dist", "build", "coverage", ".venv", "venv",
    "__pycache__", ".git", ".next", ".nuxt", "_sandbox", "_backups",
    "_db_bkps", "_bp", "_tmp", "_scratch", "_scripts",
}

VITEST_CONFIG_RE = re.compile(r"^vitest\.config\.(ts|mts|js|mjs|cjs)$")
MD5_HASHER = "MD5PasswordHasher"

# Files scanned for a lingering -n auto / --numprocesses / pytest-xdist.
NO_N_AUTO_GLOBS = (
    ".sh", ".toml", ".ini", ".cfg", ".yml", ".yaml", ".lock",
)
NO_N_AUTO_NAMES = ("Makefile", "package.json")
NO_N_AUTO_PREFIX = "requirements"


def _walk(root, skip_dirs=SKIP_DIRS, max_depth=6):
    root = os.path.abspath(root)
    base_depth = root.rstrip(os.sep).count(os.sep)
    for dirpath, dirnames, filenames in os.walk(root):
        depth = dirpath.rstrip(os.sep).count(os.sep) - base_depth
        if depth >= max_depth:
            dirnames[:] = []
        dirnames[:] = [d for d in dirnames if d not in skip_dirs and not d.startswith(".")]
        yield dirpath, dirnames, filenames


# ---------------------------------------------------------------------------
# hasher_pytest / hasher_e2e
# ---------------------------------------------------------------------------

def _find_django_settings_module(backend_dir):
    """Return the DJANGO_SETTINGS_MODULE dotted path declared for pytest, or
    None if no pytest/Django configuration exists in this backend at all."""
    for name in ("pyproject.toml", "pytest.ini", "setup.cfg"):
        path = os.path.join(backend_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"DJANGO_SETTINGS_MODULE\s*=\s*[\"']([\w.]+)[\"']", text)
        if m:
            return m.group(1)
    return None


def _module_to_path(backend_dir, dotted):
    """Dotted module path -> existing .py file, or None if it does not
    resolve to one (the anamnesis_poc_ws trap: 'core.settings' with no such
    package under backend/)."""
    rel = dotted.replace(".", os.sep)
    candidate = os.path.join(backend_dir, rel + ".py")
    if os.path.isfile(candidate):
        return candidate
    candidate = os.path.join(backend_dir, rel, "__init__.py")
    if os.path.isfile(candidate):
        return candidate
    return None


_IMPORT_STAR_RE = re.compile(r"^\s*from\s+([.\w]+)\s+import\s+\*", re.MULTILINE)
_PASSWORD_HASHERS_RE = re.compile(r"PASSWORD_HASHERS\s*=\s*\[([^\]]*)\]")
_HASHER_CLASS_RE = re.compile(r"[\"']django\.contrib\.auth\.hashers\.(\w+)[\"']")


def _resolve_import_target(from_dir, backend_dir, spec):
    """Resolve a 'from X import *' target (relative '.mod'/'..pkg.mod' or an
    absolute dotted path) to a file, staying inside backend_dir."""
    if spec.startswith("."):
        dots = len(spec) - len(spec.lstrip("."))
        rest = spec[dots:]
        base = from_dir
        for _ in range(dots - 1):
            base = os.path.dirname(base)
        if rest:
            return _resolve_relative(base, rest)
        return None
    return _module_to_path(backend_dir, spec)


def _resolve_relative(base_dir, rest):
    rel = rest.replace(".", os.sep)
    candidate = os.path.join(base_dir, rel + ".py")
    if os.path.isfile(candidate):
        return candidate
    candidate = os.path.join(base_dir, rel, "__init__.py")
    if os.path.isfile(candidate):
        return candidate
    return None


def _first_hasher_in_file(path, backend_dir, seen=None, depth=0):
    """BFS, leaf-first: check this file's own PASSWORD_HASHERS assignment
    before following its 'import *' chain, so a leaf override wins over the
    base it inherits from. Returns the first hasher classname found, or None."""
    if seen is None:
        seen = set()
    path = os.path.abspath(path)
    if path in seen or depth > 6:
        return None
    seen.add(path)
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None

    m = _PASSWORD_HASHERS_RE.search(text)
    if m:
        cm = _HASHER_CLASS_RE.search(m.group(1))
        if cm:
            return cm.group(1)

    for spec in _IMPORT_STAR_RE.findall(text):
        target = _resolve_import_target(os.path.dirname(path), backend_dir, spec)
        if target:
            found = _first_hasher_in_file(target, backend_dir, seen, depth + 1)
            if found:
                return found
    return None


def check_hasher_pytest(backend_dir):
    """('n/a'|'unresolvable'|'present'|'absent', detail)"""
    dotted = _find_django_settings_module(backend_dir)
    if dotted is None:
        return "n/a", "no pytest/Django settings configuration found"
    settings_file = _module_to_path(backend_dir, dotted)
    if settings_file is None:
        return "unresolvable", f"DJANGO_SETTINGS_MODULE={dotted!r} does not resolve to a file"
    hasher = _first_hasher_in_file(settings_file, backend_dir)
    if hasher is None:
        return "absent", f"no PASSWORD_HASHERS in {os.path.relpath(settings_file, backend_dir)} or its chain"
    if hasher == MD5_HASHER:
        return "present", f"{hasher} first in {os.path.relpath(settings_file, backend_dir)}"
    return "absent", f"first hasher is {hasher}, not {MD5_HASHER}"


def check_hasher_e2e(backend_dir):
    """('n/a'|'present'|'absent', detail). Fixed path per the plan spec, not
    resolved via DJANGO_SETTINGS_MODULE — test_e2e.py is loaded directly by
    test-e2e.sh, not through pytest's settings resolution."""
    path = os.path.join(backend_dir, "config", "settings", "test_e2e.py")
    if not os.path.isfile(path):
        return "n/a", "no backend/config/settings/test_e2e.py"
    hasher = _first_hasher_in_file(path, backend_dir)
    if hasher is None:
        return "absent", "no PASSWORD_HASHERS in test_e2e.py"
    if hasher == MD5_HASHER:
        return "present", f"{hasher} first"
    return "absent", f"first hasher is {hasher}, not {MD5_HASHER}"


# ---------------------------------------------------------------------------
# vitest_include / coverage_provider
# ---------------------------------------------------------------------------

def _find_vitest_packages(project_dir):
    """Yield (vitest_config_path, package_dir) for every live vitest.config.*
    under project_dir, skipping vendored/archived/generated directories."""
    for dirpath, _dirnames, filenames in _walk(project_dir):
        for fn in filenames:
            if VITEST_CONFIG_RE.match(fn):
                yield os.path.join(dirpath, fn), dirpath


def _extract_coverage_block(text):
    """Return the substring of a vitest.config.* body inside its
    `coverage: { ... }` block, or None if there is no coverage block. A
    bracket-depth scan, not a single-level regex, because coverage.reporter
    is an array literal and a naive '[^}]*' still works for that shape — but
    thresholds/watermarks nest another object, so depth-tracking is what
    keeps this correct if a project adds one."""
    m = re.search(r"\bcoverage\s*:\s*\{", text)
    if not m:
        return None
    start = m.end() - 1  # index of the opening '{'
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    return text[start + 1:]  # unterminated; best effort


def check_vitest_include(project_dir):
    """('n/a'|'present'|'absent', count, total)."""
    total = 0
    present = 0
    for cfg_path, _pkg_dir in _find_vitest_packages(project_dir):
        total += 1
        try:
            text = open(cfg_path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        block = _extract_coverage_block(text)
        if block and re.search(r"\binclude\s*:", block):
            present += 1
    if total == 0:
        return "n/a", 0, 0
    return ("present" if present == total else "absent"), present, total


def check_coverage_provider(project_dir):
    """('n/a'|'present'|'absent', count, total). 'present' for a package
    requires BOTH a declared coverage.provider AND a matching
    @vitest/coverage-v8 devDependency — a declaration with no installed
    package (the ns_backoffice_ws trap) reports 'absent' for that package,
    same as no declaration at all."""
    total = 0
    present = 0
    for cfg_path, pkg_dir in _find_vitest_packages(project_dir):
        total += 1
        try:
            text = open(cfg_path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        block = _extract_coverage_block(text)
        provider = None
        if block:
            pm = re.search(r"\bprovider\s*:\s*[\"']([^\"']+)[\"']", block)
            if pm:
                provider = pm.group(1)
        has_dep = False
        pkg_json = os.path.join(pkg_dir, "package.json")
        if os.path.isfile(pkg_json):
            try:
                data = json.load(open(pkg_json, encoding="utf-8", errors="replace"))
            except (OSError, ValueError):
                data = {}
            deps = {}
            for section in ("dependencies", "devDependencies"):
                deps.update(data.get(section) or {})
            has_dep = "@vitest/coverage-v8" in deps
        if provider and has_dep:
            present += 1
    if total == 0:
        return "n/a", 0, 0
    return ("present" if present == total else "absent"), present, total


# ---------------------------------------------------------------------------
# no_n_auto
# ---------------------------------------------------------------------------

_N_AUTO_RE = re.compile(r"-n\s+auto|--numprocesses(?:=|\s+)auto")

# pytest-xdist as an actually LOCKED/declared package — not any mention. A
# lockfile records every transitive package's optional "extras" metadata too
# (poetry.lock's `test = ["pytest-xdist (>=3.6.1)", ...]` on an unrelated,
# vendored dependency), and those are not this project's own dependency.
# Only a real package declaration counts: a poetry/Pipfile.lock `[[package]]`
# name field, an npm lockfile key, or a bare requirements.txt entry.
_XDIST_PKG_RE = re.compile(
    r'^\s*name\s*=\s*"pytest-xdist"'      # poetry.lock / Pipfile.lock style
    r'|"pytest-xdist"\s*:'                 # package-lock.json / yarn.lock key
    r'|^pytest-xdist\s*(?:[=><~!\[]|$)',   # requirements*.txt bare entry
    re.MULTILINE,
)


def check_no_n_auto(project_dir):
    """('compliant'|'drift', [hits]). Scans first-party configuration only
    (skips SKIP_DIRS), never a full-text grep of the tree. Two independent
    sub-checks, both must be clean: `-n auto`/`--numprocesses` in any
    candidate file, and `pytest-xdist` as an actually locked/declared
    package in a lockfile or requirements file specifically."""
    hits = []
    for dirpath, _dirnames, filenames in _walk(project_dir):
        for fn in filenames:
            is_lockish = fn.endswith(".lock") or fn.startswith(NO_N_AUTO_PREFIX)
            is_candidate = (
                fn.endswith(NO_N_AUTO_GLOBS)
                or fn in NO_N_AUTO_NAMES
                or fn.startswith(NO_N_AUTO_PREFIX)
            )
            if not is_candidate:
                continue
            path = os.path.join(dirpath, fn)
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            m = _N_AUTO_RE.search(text)
            if m:
                hits.append(f"{os.path.relpath(path, project_dir)}: {m.group(0)!r}")
            if is_lockish:
                xm = _XDIST_PKG_RE.search(text)
                if xm:
                    hits.append(f"{os.path.relpath(path, project_dir)}: pytest-xdist locked")
    return ("drift" if hits else "compliant"), hits


# ---------------------------------------------------------------------------
# Per-project report
# ---------------------------------------------------------------------------

def check_project(project_dir):
    backend_dir = os.path.join(project_dir, "backend")
    has_backend = os.path.isdir(backend_dir)

    if has_backend:
        hasher_pytest, hp_detail = check_hasher_pytest(backend_dir)
        hasher_e2e, he_detail = check_hasher_e2e(backend_dir)
    else:
        hasher_pytest, hp_detail = "n/a", "no backend/ directory"
        hasher_e2e, he_detail = "n/a", "no backend/ directory"

    vitest_include, vi_count, vi_total = check_vitest_include(project_dir)
    coverage_provider, cp_count, cp_total = check_coverage_provider(project_dir)
    no_n_auto, n_hits = check_no_n_auto(project_dir)

    stack_bits = []
    if has_backend and hasher_pytest != "n/a":
        stack_bits.append("django")
    elif has_backend:
        stack_bits.append("django?")
    if vi_total > 0:
        stack_bits.append("vitest")
    stack = " + ".join(stack_bits) if stack_bits else "neither"

    return {
        "stack": stack,
        "hasher_pytest": {"value": hasher_pytest, "detail": hp_detail},
        "hasher_e2e": {"value": hasher_e2e, "detail": he_detail},
        "vitest_include": {"value": vitest_include, "count": vi_count, "total": vi_total},
        "coverage_provider": {"value": coverage_provider, "count": cp_count, "total": cp_total},
        "no_n_auto": {"value": no_n_auto, "hits": n_hits},
    }


# ---------------------------------------------------------------------------
# Portfolio sweep
# ---------------------------------------------------------------------------

EXCLUDE_NAME_PREFIXES = ("_",)
EXCLUDE_NAMES = {"oss"}


def _is_worktree(name):
    return "-wt-" in name


def enumerate_projects(root, include_worktrees=False):
    projects = []
    for entry in sorted(os.listdir(root)):
        path = os.path.join(root, entry)
        if not os.path.isdir(path):
            continue
        if entry in EXCLUDE_NAMES:
            continue
        if entry.startswith(EXCLUDE_NAME_PREFIXES):
            continue
        if _is_worktree(entry) and not include_worktrees:
            continue
        projects.append((entry, path))
    return projects


def _fmt_frac(cell):
    v = cell["value"]
    if v == "n/a":
        return "n/a"
    return f"{v} ({cell['count']}/{cell['total']})"


def _fmt_scalar(cell):
    return cell["value"]


def sweep(root, include_worktrees=False):
    results = {}
    for name, path in enumerate_projects(root, include_worktrees=include_worktrees):
        results[name] = check_project(path)
    return results


def _project_drifted(row):
    if row["hasher_pytest"]["value"] in ("absent", "unresolvable"):
        return True
    if row["hasher_e2e"]["value"] == "absent":
        return True
    if row["vitest_include"]["value"] == "absent":
        return True
    if row["coverage_provider"]["value"] == "absent":
        return True
    if row["no_n_auto"]["value"] == "drift":
        return True
    return False


def main(argv):
    root = os.path.expanduser("~/Documents/projects")
    include_worktrees = False
    as_json = False
    verbose = False
    only = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--root":
            i += 1
            root = os.path.abspath(os.path.expanduser(argv[i]))
        elif a == "--include-worktrees":
            include_worktrees = True
        elif a == "--json":
            as_json = True
        elif a in ("-v", "--verbose"):
            verbose = True
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            only.append(a)
        i += 1

    if not os.path.isdir(root):
        print(f"no such root: {root}", file=sys.stderr)
        return 2

    if only:
        rows = {}
        for name in only:
            path = os.path.join(root, name)
            if not os.path.isdir(path):
                print(f"no such project under {root}: {name}", file=sys.stderr)
                return 2
            rows[name] = check_project(path)
    else:
        rows = sweep(root, include_worktrees=include_worktrees)

    drifted_names = [n for n, r in rows.items() if _project_drifted(r)]

    if as_json:
        # --json is the machine-readable roll-up: always emits every row,
        # n/a included, regardless of drift — never gated by silent-when-clean.
        print(json.dumps(rows, indent=2, sort_keys=True))
    elif drifted_names or verbose:
        # A clean run is SILENT (compliance-sweep.sh's contract): the table
        # prints only when at least one project drifted, or --verbose was
        # given. Whenever it does print, every enumerated project gets a
        # row — n/a included, that is the recorded denominator, not a
        # filtered "just the drifted ones" view.
        header = f"{'project':<30} {'hasher_pytest':<14} {'hasher_e2e':<10} {'vitest_include':<18} {'coverage_provider':<20} no_n_auto"
        print(header)
        for name in sorted(rows):
            r = rows[name]
            print(
                f"{name:<30} "
                f"{_fmt_scalar(r['hasher_pytest']):<14} "
                f"{_fmt_scalar(r['hasher_e2e']):<10} "
                f"{_fmt_frac(r['vitest_include']):<18} "
                f"{_fmt_frac(r['coverage_provider']):<20} "
                f"{_fmt_scalar(r['no_n_auto'])}"
            )
        if drifted_names:
            print(f"\n{len(drifted_names)} of {len(rows)} project(s) drifted: {', '.join(sorted(drifted_names))}")
        elif verbose:
            print(f"\n{len(rows)} project(s) clean")

    return 1 if drifted_names else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
