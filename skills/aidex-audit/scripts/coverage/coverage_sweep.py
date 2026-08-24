#!/usr/bin/env python3
"""Coverage sweep — drift-based re-run detector.

CLI: coverage_sweep.py <workspace-root> [--since ISO]

Advisory only. Prints a ranked plain-text table of per-module drift and never
runs anything. Exit 0 whenever it ran, flagged rows or not (backlog sweep.sh's
dry-run philosophy); exit 2 when it could not run at all — no or invalid
module-map, a bad flag — so that a broken map is never read as "drift" (exit 1
is config_check's drift code in this script family). The high-signal event is
the asymmetry "commits touched a module's src but not its tests" since the last
coverage matrix — the proforma-16338 failure mode.

Baseline (reference date) per module, first match wins:
  1. --since flag
  2. coverage-matrix.json `generated` timestamp
  3. warn (no baseline) and fall back to the last 90 days

Drift score, simple and explainable:
  drift = src_commits - test_commits + 2 * max(0, new_untested_surfaces)
where new_untested_surfaces = max(0, current_src_files - stored_src_files).
Surfaces are counted from tracked files (git ls-files), the same method the
matrix uses, so current - stored is apples-to-apples.

--out <dir>: read module-map.json from, and write any output to, <dir>
instead of <workspace-root>/.context/audits/test-coverage — the read-only
mode for auditing a workspace you must not write into (BL-204).
"""
import json
import os
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _coverage_lib as lib

# Re-run is recommended once a module's drift reaches this score. Constant, not
# calendar-based: src-vs-test commit asymmetry plus new untested surfaces.
RERUN_THRESHOLD = 3


def matrix_path(root, coverage_dir=None):
    return os.path.join(coverage_dir or os.path.join(
        root, ".context", "audits", "test-coverage"), "coverage-matrix.json")


def resolve_since(root, cli_since, coverage_dir=None):
    """(since_for_git, display_date, baseline_label). First match wins."""
    if cli_since:
        # git's approxidate turns an unparsable --since into "now" (or a
        # mangled nearby date) and still exits 0, so a typo prints a table of
        # zeros labelled "since <typo>" — the all-clear the sweep exists to catch.
        try:
            datetime.fromisoformat(_date_part(cli_since))
        except ValueError:
            usage(f"--since must be an ISO date, got {cli_since!r}")
        return cli_since, _date_part(cli_since), "--since flag"
    mp = matrix_path(root, coverage_dir)
    if os.path.isfile(mp):
        with open(mp) as f:
            gen = json.load(f).get("generated")
        if gen:
            # A baseline stamped today measures nothing: every drift is 0 by
            # construction, and a table of zeros right after a rebuild reads
            # as "all clear" when it is really "no elapsed window".
            if _date_part(gen) == datetime.now().date().isoformat():
                print(
                    "NOTE: baseline regenerated today — the sweep carries no "
                    "signal until src/test commits accrue after the matrix run",
                    file=sys.stderr,
                )
            return gen, _date_part(gen), "coverage-matrix.json"
    fallback = (datetime.now() - timedelta(days=90)).isoformat(timespec="seconds")
    print(
        "WARNING: no baseline — run coverage-matrix first; using last 90 days",
        file=sys.stderr,
    )
    return fallback, _date_part(fallback), "last 90 days (no matrix)"


def _date_part(s):
    return s.split("T")[0] if "T" in s else s


def load_stored(root, coverage_dir=None):
    """module id -> stored matrix row, {} if no matrix on disk."""
    mp = matrix_path(root, coverage_dir)
    if not os.path.isfile(mp):
        return {}
    with open(mp) as f:
        data = json.load(f)
    return {r["id"]: r for r in data.get("modules", [])}


def module_drift(root, repos, files, mod, since, stored):
    src_globs = mod.get("src", [])
    t_globs = lib.test_globs(mod)  # every kind, so a third kind is not read as src-only drift

    src_commits = sum(lib.commits_since(root, r, since, src_globs) for r in repos)
    test_commits = sum(lib.commits_since(root, r, since, t_globs) for r in repos)

    cur_src = len([f for f in files if lib.matches(f, src_globs)])
    cur_specs = len([f for f in files if lib.matches(f, lib.e2e_globs(mod))])

    row = stored.get(mod["id"], {})
    stored_src = row.get("src_files", 0)
    stored_specs = row.get("e2e_files", 0)

    delta_src = cur_src - stored_src
    delta_specs = cur_specs - stored_specs
    new_untested = max(0, delta_src)

    drift = src_commits - test_commits + 2 * new_untested

    return {
        "id": mod["id"],
        "src_commits": src_commits,
        "test_commits": test_commits,
        "delta_src": delta_src,
        "delta_specs": delta_specs,
        "drift": drift,
    }


def fmt_surface_delta(delta_specs, delta_src):
    parts = []
    if delta_specs:
        parts.append(f"{delta_specs:+d} specs")
    if delta_src:
        parts.append(f"{delta_src:+d} src")
    return ", ".join(parts) if parts else "0"


def render(rows, display_date, baseline_label):
    lines = []
    lines.append(
        f"COVERAGE SWEEP — since {display_date} (baseline: {baseline_label})"
    )

    header = ["Module", "Src commits", "Test commits", "Surface delta", "Drift", "Recommendation"]
    body = []
    flagged = False
    for r in rows:
        rec = "RE-RUN RECOMMENDED" if r["drift"] >= RERUN_THRESHOLD else "ok"
        if r["drift"] >= RERUN_THRESHOLD:
            flagged = True
        body.append([
            r["id"],
            str(r["src_commits"]),
            str(r["test_commits"]),
            fmt_surface_delta(r["delta_specs"], r["delta_src"]),
            str(r["drift"]),
            rec,
        ])

    widths = [len(h) for h in header]
    for cells in body:
        for i, c in enumerate(cells):
            widths[i] = max(widths[i], len(c))

    def line(cells):
        return "  ".join(c.ljust(widths[i]) for i, c in enumerate(cells)).rstrip()

    lines.append(line(header))
    for cells in body:
        lines.append(line(cells))

    if flagged:
        lines.append(
            "Next: /aidex-audit new test-coverage <slug> scoped to the flagged "
            "modules, then regenerate the matrix."
        )
    return "\n".join(lines)


def usage(msg):
    print(f"{msg}\nusage: coverage_sweep.py <workspace-root> [--since ISO] [--out <dir>]",
          file=sys.stderr)
    sys.exit(2)


def main():
    args = sys.argv[1:]
    cli_since = None
    out_override = None
    positional = []
    i = 0
    while i < len(args):
        if args[i] in ("-h", "--help"):
            print(__doc__.strip())
            sys.exit(0)
        if args[i] == "--since":
            if i + 1 >= len(args):
                usage("--since requires a value")
            cli_since = args[i + 1]
            i += 2
        elif args[i] == "--out":
            if i + 1 >= len(args):
                usage("--out requires a value")
            out_override = args[i + 1]
            i += 2
        elif args[i].startswith("-"):
            # A misspelled flag used to land in positional[1:] and vanish, so
            # `--sinc 2020-01-01` ran a baseline-dated sweep that looked answered.
            usage(f"unknown flag: {args[i]}")
        else:
            positional.append(args[i])
            i += 1
    if len(positional) != 1:
        usage("expected exactly one <workspace-root>")
    root = positional[0]

    try:
        m = lib.load_map(root, out_override)
        files = lib.list_files(root, m["repos"])
    except SystemExit as e:
        print(e.code, file=sys.stderr)
        sys.exit(2)  # could not run — distinct from 0 (ran) and from drift elsewhere
    since, display_date, baseline_label = resolve_since(root, cli_since, out_override)
    stored = load_stored(root, out_override)

    rows = [
        module_drift(root, m["repos"], files, mod, since, stored)
        for mod in m["modules"]
    ]
    rows.sort(key=lambda r: r["drift"], reverse=True)

    print(render(rows, display_date, baseline_label))
    sys.exit(0)


if __name__ == "__main__":
    main()
