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

Seven keys, per project:

  hasher_pytest     - does the settings module *pytest* loads put MD5 first?
  hasher_e2e        - does backend/config/settings/test_e2e.py put MD5 first?
  vitest_include    - does each vitest.config.* declare coverage.include?
  coverage_provider - is @vitest/coverage-v8 a real devDependency, and does
                       it agree with the declared coverage.provider?
  no_n_auto         - is `-n auto` / `--numprocesses auto` absent from project
                       configuration? A fixed integer is compliant, and so is
                       a declared pytest-xdist (BL-236).
  fail_under        - does the backend enforce a coverage threshold —
                       [tool.coverage.report] fail_under in pyproject.toml,
                       [report] fail_under in .coveragerc / setup.cfg, or
                       --cov-fail-under in pytest addopts? (BL-200)
  vitest_thresholds - does each vitest.config.* declare coverage.thresholds?
                       (BL-200)

The two BL-200 keys are INFORMATIONAL: `absent` never counts as drift,
because adopting a threshold is a per-project decision — the test-coverage
audit records an absent threshold as a finding; this table only makes the
absence visible instead of only reporting the number.

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

# Hidden directories are pruned wholesale (.git, .venv, caches) EXCEPT the
# ones that carry first-party CI configuration — .github/workflows is exactly
# where a lingering `-n auto` lives, and pruning it read such projects
# compliant.
HIDDEN_SCAN_DIRS = {".github", ".circleci", ".gitlab"}

VITEST_CONFIG_RE = re.compile(r"^vitest\.config\.(ts|mts|js|mjs|cjs)$")
MD5_HASHER = "MD5PasswordHasher"

# A directory holding this relative path is a checkout of the checker itself,
# so the `tests/` beside it is the checker's own test data, not the scanned
# project's configuration. aidex was reported drifted by its own fixture's
# literal `-n auto` (BL-236). Keyed on the marker rather than on __file__ so
# it holds for the installed copy scanning the repo as well.
CHECKER_MARKER = os.path.join("scripts", "coverage", "config_check.py")

# Files scanned for a lingering -n auto / --numprocesses.
NO_N_AUTO_GLOBS = (
    ".sh", ".toml", ".ini", ".cfg", ".yml", ".yaml", ".lock",
)
NO_N_AUTO_NAMES = ("Makefile", "package.json")
NO_N_AUTO_PREFIX = "requirements"
WALK_MAX_DEPTH = 6


def _walk(root):
    root = os.path.abspath(root)
    base_depth = root.rstrip(os.sep).count(os.sep)
    # followlinks: a symlink-built scratch workspace (the BL-204 read-only
    # field run) read every discovery-based key as a silent n/a because
    # os.walk never descends symlinked dirs by default. WALK_MAX_DEPTH
    # bounds any symlink cycle.
    for dirpath, dirnames, filenames in os.walk(root, followlinks=True):
        depth = dirpath.rstrip(os.sep).count(os.sep) - base_depth
        if depth >= WALK_MAX_DEPTH:
            dirnames[:] = []
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIRS
            and (not d.startswith(".") or d in HIDDEN_SCAN_DIRS)
            and not (d == "tests" and os.path.isfile(
                os.path.join(dirpath, CHECKER_MARKER)))
        ]
        yield dirpath, dirnames, filenames


# ---------------------------------------------------------------------------
# hasher_pytest / hasher_e2e
# ---------------------------------------------------------------------------

def _find_django_settings_module(backend_dir):
    """Return the DJANGO_SETTINGS_MODULE dotted path declared for pytest, or
    None if no pytest/Django configuration exists in this backend at all.

    File order is pytest's own precedence (pytest.ini beats pyproject.toml).
    The value may be quoted (pyproject) or bare (pytest.ini / setup.cfg /
    pytest-env's `env = ["DJANGO_SETTINGS_MODULE=..."]`) — a quoted-only
    regex read the bare forms as "no configuration" and the project as clean."""
    for name in ("pytest.ini", "pyproject.toml", "setup.cfg"):
        path = os.path.join(backend_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        m = re.search(r"DJANGO_SETTINGS_MODULE\s*=\s*[\"']?([\w.]+)", text)
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
# The FIRST list entry decides, whatever module it comes from. Matching only
# django.contrib.* entries skipped a custom hasher sitting first — the exact
# slow-hasher-under-pytest state the check exists to catch.
_HASHER_ENTRY_RE = re.compile(r"[\"']([\w.]+)[\"']")


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
            return _module_to_path(base, rest)
        return None
    return _module_to_path(backend_dir, spec)


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
        cm = _HASHER_ENTRY_RE.search(m.group(1))
        if cm:
            return cm.group(1).rsplit(".", 1)[-1]

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
    requires BOTH a declared coverage.provider AND the @vitest/coverage-<provider>
    package it names as a dependency — a declaration with no installed
    package (the ns_backoffice_ws trap), or with the wrong one (istanbul
    declared, coverage-v8 installed), reports 'absent' for that package,
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
            has_dep = f"@vitest/coverage-{provider}" in deps
        if provider and has_dep:
            present += 1
    if total == 0:
        return "n/a", 0, 0
    return ("present" if present == total else "absent"), present, total


# ---------------------------------------------------------------------------
# coverage thresholds (BL-200)
# ---------------------------------------------------------------------------

_FAIL_UNDER_TOML_RE = re.compile(
    r"^\s*fail_under\s*=\s*([0-9]+(?:\.[0-9]+)?)", re.MULTILINE)
_COV_FAIL_UNDER_OPT_RE = re.compile(r"--cov-fail-under(?:=|\s+)([0-9]+(?:\.[0-9]+)?)")


def _fail_under_in_section(text, section_re):
    """A fail_under line inside the section the regex names, tracked by
    scanning section headers — an INI/TOML file can carry several sections
    and a flat search would credit fail_under from an unrelated one."""
    current = None
    for line in text.splitlines():
        m = re.match(r"\s*\[([^\]]+)\]", line)
        if m:
            current = m.group(1).strip()
            continue
        if current is not None and re.fullmatch(section_re, current):
            fm = re.match(r"\s*fail_under\s*=\s*([0-9]+(?:\.[0-9]+)?)", line)
            if fm:
                return fm.group(1)
    return None


def check_fail_under(backend_dir):
    """('present'|'absent', detail). Looks where coverage.py and pytest-cov
    actually read a threshold: [tool.coverage.report] in pyproject.toml,
    [report] in .coveragerc, [coverage:report] in setup.cfg, and a
    --cov-fail-under in any pytest addopts (pyproject/pytest.ini/setup.cfg)."""
    candidates = (
        ("pyproject.toml", r"tool\.coverage\.report"),
        (".coveragerc", r"report"),
        ("setup.cfg", r"coverage:report"),
    )
    for fname, section_re in candidates:
        path = os.path.join(backend_dir, fname)
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        value = _fail_under_in_section(text, section_re)
        if value is not None:
            return "present", f"{fname}: fail_under = {value}"
    for fname in ("pyproject.toml", "pytest.ini", "setup.cfg", "tox.ini"):
        path = os.path.join(backend_dir, fname)
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        m = _COV_FAIL_UNDER_OPT_RE.search(text)
        if m:
            return "present", f"{fname}: --cov-fail-under={m.group(1)}"
    return "absent", "no fail_under / --cov-fail-under in coverage or pytest config"


def check_vitest_thresholds(project_dir):
    """('n/a'|'present'|'absent', count, total). Same denominator as
    vitest_include: every vitest.config.* found, `present` only when all of
    them declare a coverage.thresholds block."""
    total = 0
    present = 0
    for cfg_path, _pkg_dir in _find_vitest_packages(project_dir):
        total += 1
        try:
            text = open(cfg_path, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        block = _extract_coverage_block(text)
        if block and re.search(r"\bthresholds\s*:", block):
            present += 1
    if total == 0:
        return "n/a", 0, 0
    return ("present" if present == total else "absent"), present, total


# ---------------------------------------------------------------------------
# no_n_auto
# ---------------------------------------------------------------------------

_N_AUTO_RE = re.compile(r"-n\s+auto|--numprocesses(?:=|\s+)auto")

# A DECLARED pytest-xdist is compliant, not drift. The rule used to read a
# locked dependency as drift because it encoded the 2026-08-23 ADR that
# declined xdist; that ADR is superseded by
# decision/2026-08-24-xdist-per-project-worker-counts.md, which deployed
# per-project fixed worker counts and mandated the dependency with them. Only
# the auto form above is drift (BL-236).


def check_no_n_auto(project_dir):
    """('compliant'|'drift', [hits]). Scans first-party configuration only
    (skips SKIP_DIRS and the checker's own tests, see _walk), never a
    full-text grep of the tree. Drift is `-n auto` / `--numprocesses auto`
    in a candidate file; a declared pytest-xdist is compliant (BL-236)."""
    hits = []
    for dirpath, _dirnames, filenames in _walk(project_dir):
        # requirements*.txt, or the cookiecutter `requirements/<env>.txt` layout
        # — matching the basename prefix alone never saw `dev.txt`.
        in_req_dir = os.path.basename(dirpath) == NO_N_AUTO_PREFIX
        for fn in filenames:
            is_req = fn.startswith(NO_N_AUTO_PREFIX) or (in_req_dir and fn.endswith(".txt"))
            is_candidate = (
                fn.endswith(NO_N_AUTO_GLOBS)
                or fn in NO_N_AUTO_NAMES
                or is_req
                # PYTEST_ADDOPTS="-n auto" lives in a Dockerfile or .env as well
                or fn.startswith(("Dockerfile", ".env"))
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
    if has_backend:
        fail_under, fu_detail = check_fail_under(backend_dir)
    else:
        fail_under, fu_detail = "n/a", "no backend/ directory"
    vitest_thresholds, vt_count, vt_total = check_vitest_thresholds(project_dir)

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
        # BL-200 — informational: absent is a finding for the audit, not drift.
        "fail_under": {"value": fail_under, "detail": fu_detail},
        "vitest_thresholds": {"value": vitest_thresholds, "count": vt_count, "total": vt_total},
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
            if i >= len(argv):
                print("--root requires a value", file=sys.stderr)
                return 2
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
        if not rows:
            # compliance-sweep.sh's guard: silent-when-clean must never cover
            # "nothing was checked" (a --root typo landing on a real directory).
            print(f"no projects to check under {root}", file=sys.stderr)
            return 2

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
        header = f"{'project':<30} {'hasher_pytest':<14} {'hasher_e2e':<10} {'vitest_include':<18} {'coverage_provider':<20} {'no_n_auto':<10} {'fail_under':<11} vitest_thresholds"
        print(header)
        for name in sorted(rows):
            r = rows[name]
            print(
                f"{name:<30} "
                f"{_fmt_scalar(r['hasher_pytest']):<14} "
                f"{_fmt_scalar(r['hasher_e2e']):<10} "
                f"{_fmt_frac(r['vitest_include']):<18} "
                f"{_fmt_frac(r['coverage_provider']):<20} "
                f"{_fmt_scalar(r['no_n_auto']):<10} "
                f"{_fmt_scalar(r['fail_under']):<11} "
                f"{_fmt_frac(r['vitest_thresholds'])}"
            )
        if drifted_names:
            print(f"\n{len(drifted_names)} of {len(rows)} project(s) drifted: {', '.join(sorted(drifted_names))}")
        elif verbose:
            print(f"\n{len(rows)} project(s) clean")

    return 1 if drifted_names else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
