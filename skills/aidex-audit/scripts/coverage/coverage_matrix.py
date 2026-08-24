#!/usr/bin/env python3
"""Coverage matrix generator — breadth layer (modules x tests) + the route board.

CLI: coverage_matrix.py <workspace-root>

Reads .context/audits/test-coverage/module-map.json (via _coverage_lib) and the
workspace's tracked files, and writes two GENERATED artifacts under
.context/audits/test-coverage/: coverage-matrix.md (human-readable) and
coverage-matrix.json (machine-readable, consumed by coverage-sweep's
surface-delta). Never hand-edit the outputs — re-run this script instead.

--out <dir>: read module-map.json from, and write any output to, <dir>
instead of <workspace-root>/.context/audits/test-coverage — the read-only
mode for auditing a workspace you must not write into (BL-204).
"""
import json
import os
import re
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _coverage_lib as lib

# Pinned shape of coverage-matrix.json. Bump when the key set changes; the dash
# consumer (aidex-dash render_coverage.py) rejects any value it does not know,
# so a producer-side rename fails loudly instead of rendering a wrong board.
# /2 adds the route board: typed `surfaces.routes` + `surfaces.actions`, per-route
# E2E reach, and `route_gaps`. Stamped on EVERY run, including a v1 input map —
# the consumer pins a single value, so emitting /1 for unmigrated maps would break
# their board instead of just leaving it routeless.
SCHEMA = "coverage-matrix/2"

# Heuristic for "this tracked file is a test file", used only to find test
# files that match no module's test globs (breadth gaps in the map itself).
TEST_FILE_RE = re.compile(
    r"(^|/)tests?/|(^|/)test_[^/]+\.py$|_test\.py$|\.spec\.[jt]sx?$|\.test\.[jt]sx?$"
)


# A `:param` segment never appears literally in a spec, so it is translated to
# "one path segment" before matching; without that every parameterised route
# reads uncovered forever. The segment class is permissive enough to swallow a
# template placeholder (`/suppliers/invoices/${inv.id}/edit`), which is how the
# measured corpus actually writes a parameterised URL.
_PARAM_RE = re.compile(r":[A-Za-z_][A-Za-z0-9_]*\??")
_SEGMENT = r"[^/'\"`?\s]+"

# The URL must END where the route ends: a closing quote/backtick, or the start
# of a query/fragment. This is what stops `/people` from being reported covered
# by a spec that only ever visits `/people/create` — silent over-reporting is
# the failure mode the board exists to expose, so it is the side that gets the
# strict rule. The preceding character may be anything that is not part of a
# longer path or identifier; `*` and `/` are excluded so that a `*/` comment
# terminator or a `//` cannot pass as the root route, and `@`/`~` so that a
# Vite alias import (`from '@/login'`) is not a visit to `/login`.
_ROUTE_END = r"(?=['\"`?#])"
_ROUTE_START = r"(?<![\w*./@~-])"


def route_regex(path):
    """URL route -> regex matching a literal mention of it in a spec file."""
    out, pos = [], 0
    for m in _PARAM_RE.finditer(path):
        out.append(re.escape(path[pos:m.start()]))
        out.append(_SEGMENT)
        pos = m.end()
    out.append(re.escape(path[pos:]))
    return re.compile(_ROUTE_START + "".join(out) + _ROUTE_END)


def is_glob_list(value):
    """True for the v1 surface shape: a list of glob STRINGS.

    `surface_files` is summed only over these. A typed surface (`routes`,
    `actions` — lists of dicts) is not a file path, so counting it would report
    zero files for the very modules that adopt the new shape. Sniffing the value
    rather than whitelisting key names keeps a project's own custom surface key
    counted, since the key set is open-ended by design.
    """
    return isinstance(value, list) and all(isinstance(x, str) for x in value)


# A spec, not merely a file an e2e glob happens to cover. Measured on NS
# 2026-08-23: the e2e globs also pull in `tests/e2e-setup/test-routes.ts`, a
# table of route CONSTANTS, and counting it marked 13 of 79 routes "covered"
# with no spec behind any of them. A route reached only through a helper now
# reads as a gap instead — a false alarm a human resolves, which is the
# direction to err in when the alternative is a checker that lies.
E2E_SPEC_RE = re.compile(r"\.(spec|test)\.[jt]sx?$|(^|/)test_[^/]+\.py$|_test\.py$")


def e2e_spec_index(root, files, modules):
    """{spec path: text} over the UNION of every module's e2e globs.

    Union, not the owning module's globs: a top-level smoke spec that walks many
    routes belongs to no module, and scoping the scan per module would make the
    coverage it provides invisible.
    """
    globs = []
    for mod in modules:
        globs.extend(lib.e2e_globs(mod))
    matched = [f for f in files if lib.matches(f, globs)]
    specs = [f for f in matched if E2E_SPEC_RE.search(f)]
    # A project whose specs use none of the known naming conventions would
    # otherwise be scanned as if it had no E2E at all, reporting every route as
    # a gap. Falling back to the glob set keeps that failure visible-but-honest.
    if matched and not specs:
        specs = matched
    index = {}
    for f in specs:
        try:
            with open(os.path.join(root, f), errors="ignore") as fh:
                index[f] = fh.read()
        except OSError:
            pass
    return index


def route_rows(mod, spec_index):
    """Typed `surfaces.routes` -> route entries with their actions and E2E reach.

    Returns (routes, unmapped_actions). A v1 map (routes as globs) yields no
    route entries — it is counted as files by `surface_files` instead.
    """
    surfaces = mod.get("surfaces") or {}
    raw_routes = surfaces.get("routes") or []
    actions = [a for a in (surfaces.get("actions") or []) if isinstance(a, dict)]
    if is_glob_list(raw_routes):
        # v1 (or routeless) module. Any action it declares references a route no
        # `routes` entry defines, so it is reported rather than silently dropped.
        return [], [
            {"module": mod["id"], "route": a.get("route", ""),
             "action": a.get("action", ""), "endpoint": a.get("endpoint", "")}
            for a in actions
        ]

    by_route = {}
    for a in actions:
        by_route.setdefault(a.get("route"), []).append(a)

    routes = []
    for r in raw_routes:
        if not isinstance(r, dict):
            continue
        path = r.get("path", "")
        rx = route_regex(path) if path else None
        reached = sorted(
            f for f, text in spec_index.items() if rx and rx.search(text)
        ) if rx else []
        routes.append({
            "path": path,
            "spec": r.get("spec", ""),
            "actions": [
                {"action": a.get("action", ""), "endpoint": a.get("endpoint", "")}
                for a in by_route.get(path, [])
            ],
            "reached_by": reached,
            "covered": bool(reached),
        })

    declared = {r["path"] for r in routes}
    unmapped_actions = [
        {"module": mod["id"], "route": a.get("route", ""),
         "action": a.get("action", ""), "endpoint": a.get("endpoint", "")}
        for a in actions if a.get("route") not in declared
    ]
    return routes, unmapped_actions


def module_row(root, files, mod, spec_index):
    src = [f for f in files if lib.matches(f, mod.get("src", []))]

    unit_globs = (mod.get("tests", {}) or {}).get("unit", []) or []
    unit_files = [f for f in files if lib.matches(f, unit_globs)]
    e2e_files = [f for f in files if lib.matches(f, lib.e2e_globs(mod))]
    # "The module's test files" is every kind, not unit + e2e: the columns
    # report those two, but a file under a third kind is mapped (never
    # "unmapped") and a module with only that kind is not NO TESTS.
    all_test_files = [f for f in files if lib.matches(f, lib.test_globs(mod))]

    unit_tests = lib.count_tests(root, unit_files)
    e2e_tests = lib.count_tests(root, e2e_files)

    surfaces = mod.get("surfaces")
    surface_files = 0
    if surfaces:
        for surface_value in surfaces.values():
            if not is_glob_list(surface_value):
                continue  # typed surface (routes/actions) — not file paths
            surface_files += len([f for f in files if lib.matches(f, surface_value)])

    routes, unmapped_actions = route_rows(mod, spec_index)
    uncovered = [r for r in routes if not r["covered"]]

    notes = "NO TESTS" if not all_test_files else "—"

    return {
        "id": mod["id"],
        "title": mod.get("title", mod["id"]),
        "src_files": len(src),
        "unit_files": len(unit_files),
        "unit_tests": unit_tests,
        "e2e_files": len(e2e_files),
        "e2e_tests": e2e_tests,
        "surface_files": surface_files,
        "has_surfaces": bool(surfaces),
        "routes": routes,
        "routes_total": len(routes),
        "routes_uncovered": len(uncovered),
        "notes": notes,
    }, all_test_files, unmapped_actions


def find_unmapped_test_files(files, mapped_test_files):
    mapped = set(mapped_test_files)
    unmapped = [
        f for f in files
        if TEST_FILE_RE.search(f) and f not in mapped
        and os.path.basename(f) != "__init__.py"  # packaging stub, not a test
    ]
    return sorted(unmapped)


def build_matrix(root, coverage_dir=None):
    m = lib.load_map(root, coverage_dir)
    files = lib.list_files(root, m["repos"])

    spec_index = e2e_spec_index(root, files, m["modules"])

    rows = []
    all_mapped_test_files = []
    unmapped_actions = []
    for mod in m["modules"]:
        row, mapped_test_files, orphan_actions = module_row(root, files, mod, spec_index)
        rows.append(row)
        all_mapped_test_files.extend(mapped_test_files)
        unmapped_actions.extend(orphan_actions)

    unmapped = find_unmapped_test_files(files, all_mapped_test_files)

    # The output the field exists for: a declared route no E2E spec ever visits.
    route_gaps = [
        {"module": r["id"], "path": rt["path"], "spec": rt["spec"]}
        for r in rows for rt in r["routes"] if not rt["covered"]
    ]

    totals = {
        "src_files": sum(r["src_files"] for r in rows),
        "unit_files": sum(r["unit_files"] for r in rows),
        "unit_tests": sum(r["unit_tests"] for r in rows),
        "e2e_files": sum(r["e2e_files"] for r in rows),
        "e2e_tests": sum(r["e2e_tests"] for r in rows),
        "routes": sum(r["routes_total"] for r in rows),
        "routes_uncovered": len(route_gaps),
    }

    return {
        "schema": SCHEMA,
        "generated": datetime.now().isoformat(timespec="seconds"),
        "modules": rows,
        "totals": totals,
        "unmapped_test_files": unmapped,
        "route_gaps": route_gaps,
        "unmapped_actions": unmapped_actions,
    }


def render_markdown(data):
    lines = []
    lines.append(
        f"<!-- GENERATED {data['generated']} by /aidex-audit coverage-matrix "
        "— DO NOT EDIT, regenerate instead -->"
    )
    lines.append("# Coverage Matrix")
    lines.append("")
    lines.append("| Module | Src files | Unit files | Unit tests | E2E specs | E2E tests | Notes |")
    lines.append("|---|---|---|---|---|---|---|")
    for r in data["modules"]:
        lines.append(
            f"| {r['id']} | {r['src_files']} | {r['unit_files']} | {r['unit_tests']} | "
            f"{r['e2e_files']} | {r['e2e_tests']} | {r['notes']} |"
        )
    lines.append("")
    t = data["totals"]
    lines.append("## Totals")
    lines.append("")
    lines.append("| Src files | Unit files | Unit tests | E2E specs | E2E tests |")
    lines.append("|---|---|---|---|---|")
    lines.append(
        f"| {t['src_files']} | {t['unit_files']} | {t['unit_tests']} | "
        f"{t['e2e_files']} | {t['e2e_tests']} |"
    )
    lines.append("")
    routes = [(r["id"], rt) for r in data["modules"] for rt in r["routes"]]
    if routes:
        lines.append("## Routes (page x action x endpoint)")
        lines.append("")
        lines.append("| Route | Module | Serves | Action | Endpoint | E2E |")
        lines.append("|---|---|---|---|---|---|")
        for mod_id, rt in routes:
            acts = rt["actions"] or [{"action": "—", "endpoint": "—"}]
            e2e = ", ".join(rt["reached_by"]) if rt["covered"] else "NO E2E SPEC"
            for i, a in enumerate(acts):
                lines.append(
                    f"| {rt['path'] if i == 0 else ''} | {mod_id if i == 0 else ''} | "
                    f"{(rt['spec'] or '—') if i == 0 else ''} | "
                    f"{a['action'] or '—'} | {a['endpoint'] or '—'} | "
                    f"{e2e if i == 0 else ''} |"
                )
        lines.append("")
        lines.append("### Routes with no reaching E2E spec")
        lines.append("")
        if data["route_gaps"]:
            for g in data["route_gaps"]:
                lines.append(f"- `{g['path']}` ({g['module']}) — serves: {g['spec'] or '—'}")
        else:
            lines.append("None.")
        lines.append("")
    # Outside `if routes:` on purpose: a v1 map has no route board at all, and
    # that is exactly when every action it declares is orphaned.
    if data["unmapped_actions"]:
        lines.append("### Actions on an undeclared route")
        lines.append("")
        lines.append("Declared under `surfaces.actions` with a `route` no `surfaces.routes` "
                     "entry declares — a defect in the map, not in the router:")
        lines.append("")
        for a in data["unmapped_actions"]:
            lines.append(f"- `{a['route']}` -> {a['action']} ({a['module']})")
        lines.append("")

    lines.append("## Unmapped test files")
    lines.append("")
    if data["unmapped_test_files"]:
        lines.append(
            "Tracked test files matching no module's test globs "
            "(breadth gaps in the map itself):"
        )
        lines.append("")
        for f in data["unmapped_test_files"]:
            lines.append(f"- {f}")
    else:
        lines.append("None.")
    lines.append("")
    return "\n".join(lines)


USAGE = "usage: coverage_matrix.py <workspace-root> [--out <dir>]"


def main():
    args = sys.argv[1:]
    out_override = None
    positional = []
    i = 0
    while i < len(args):
        if args[i] in ("-h", "--help"):
            print(__doc__.strip())
            sys.exit(0)
        elif args[i] == "--out":
            if i + 1 >= len(args):
                sys.exit(f"--out requires a value\n{USAGE}")
            out_override = args[i + 1]
            i += 2
        elif args[i].startswith("-"):
            sys.exit(f"unknown option {args[i]!r}\n{USAGE}")
        else:
            positional.append(args[i])
            i += 1
    if len(positional) != 1:
        sys.exit(USAGE)
    root = positional[0]

    data = build_matrix(root, out_override)

    # A v1 map (routes as globs, or no routes at all) yields an empty route
    # board while the run still stamps coverage-matrix/2 and exits 0 — which is
    # how echo_lab's board sat silently inert for a month. Say it out loud.
    if not any(r["routes_total"] for r in data["modules"]):
        print(
            "NOTE: no typed surfaces.routes in the map — route board suppressed. "
            "If this workspace serves pages, migrate the map to v2 "
            "(06-test-coverage.md § Migrating a v1 map).",
            file=sys.stderr,
        )

    out_dir = out_override or os.path.join(root, ".context", "audits", "test-coverage")
    os.makedirs(out_dir, exist_ok=True)

    md_path = os.path.join(out_dir, "coverage-matrix.md")
    json_path = os.path.join(out_dir, "coverage-matrix.json")

    with open(md_path, "w") as f:
        f.write(render_markdown(data))
    with open(json_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    print(f"wrote {md_path}")
    print(f"wrote {json_path}")


if __name__ == "__main__":
    main()
