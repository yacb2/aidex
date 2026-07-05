#!/usr/bin/env python3
"""Coverage matrix generator — breadth layer (modules x tests; surface counts land in the .json).

CLI: coverage_matrix.py <workspace-root>

Reads .context/audits/test-coverage/module-map.json (via _coverage_lib) and the
workspace's tracked files, and writes two GENERATED artifacts under
.context/audits/test-coverage/: coverage-matrix.md (human-readable) and
coverage-matrix.json (machine-readable, consumed by coverage-sweep's
surface-delta). Never hand-edit the outputs — re-run this script instead.
"""
import json
import os
import re
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _coverage_lib as lib

# Heuristic for "this tracked file is a test file", used only to find test
# files that match no module's test globs (breadth gaps in the map itself).
TEST_FILE_RE = re.compile(
    r"(^|/)tests?/|(^|/)test_[^/]+\.py$|_test\.py$|\.spec\.[jt]sx?$|\.test\.[jt]sx?$"
)


def module_row(root, files, mod):
    src = [f for f in files if lib.matches(f, mod.get("src", []))]

    tests = mod.get("tests", {}) or {}
    unit_globs = tests.get("unit", []) or []
    e2e_globs = tests.get("e2e", []) or []
    unit_files = [f for f in files if lib.matches(f, unit_globs)]
    e2e_files = [f for f in files if lib.matches(f, e2e_globs)]

    unit_tests = lib.count_tests(root, unit_files)
    e2e_tests = lib.count_tests(root, e2e_files)

    total_test_files = 0
    for kind_globs in tests.values():
        total_test_files += len([f for f in files if lib.matches(f, kind_globs or [])])

    surfaces = mod.get("surfaces")
    surface_files = 0
    if surfaces:
        for surface_globs in surfaces.values():
            surface_files += len([f for f in files if lib.matches(f, surface_globs or [])])

    notes = "NO TESTS" if total_test_files == 0 else "—"

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
        "notes": notes,
    }, unit_files + e2e_files


def find_unmapped_test_files(files, mapped_test_files):
    mapped = set(mapped_test_files)
    unmapped = [
        f for f in files
        if TEST_FILE_RE.search(f) and f not in mapped
        and os.path.basename(f) != "__init__.py"  # packaging stub, not a test
    ]
    return sorted(unmapped)


def build_matrix(root):
    m = lib.load_map(root)
    files = lib.list_files(root, m["repos"])

    rows = []
    all_mapped_test_files = []
    for mod in m["modules"]:
        row, mapped_test_files = module_row(root, files, mod)
        rows.append(row)
        all_mapped_test_files.extend(mapped_test_files)

    unmapped = find_unmapped_test_files(files, all_mapped_test_files)

    totals = {
        "src_files": sum(r["src_files"] for r in rows),
        "unit_files": sum(r["unit_files"] for r in rows),
        "unit_tests": sum(r["unit_tests"] for r in rows),
        "e2e_files": sum(r["e2e_files"] for r in rows),
        "e2e_tests": sum(r["e2e_tests"] for r in rows),
    }

    return {
        "generated": datetime.now().isoformat(timespec="seconds"),
        "modules": rows,
        "totals": totals,
        "unmapped_test_files": unmapped,
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


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: coverage_matrix.py <workspace-root>")
    root = sys.argv[1]

    data = build_matrix(root)

    out_dir = os.path.join(root, ".context", "audits", "test-coverage")
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
