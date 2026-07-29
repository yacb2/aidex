#!/usr/bin/env python3
"""Documentation coverage census — the cost reducer for completeness.

Diffs what the CODE declares (census axes, enumerated by project-supplied
commands) against what the DOCS declare they own (`covers:` front-matter).

Why this exists
---------------
The manual version of this check found a whole pipeline stage with no route and
an app with no module -- but only by hand, and only once, because ownership was
inferred from prose. "Mentioned" is not "described" and grep cannot tell them
apart. Declaring ownership converts an unanswerable reading into a diff.

Three failure classes, all reported:

  gap        item exists in code, no document declares it   -> undocumented
  phantom    a document declares an item that no census returns -> stale doc
  contested  two or more documents declare the same item    -> will drift

Trust model
-----------
Axis commands come from `.context/references/00-profile.md`, a file in the
project you are already running code from -- same trust level as a Makefile.
`--dry-run` prints every command without executing it; run it first on a
profile you did not write.

No third-party dependencies. Front-matter parsing is deliberately FLAT so the
shared `validate.py` parser reads the same fields without nested-YAML support.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

FM_DELIM = re.compile(r"^---\s*$")
CENSUS_BLOCK = re.compile(r"^```census\s*$(.*?)^```\s*$", re.M | re.S)


# ---------- front-matter (flat, mirrors validate.py) ----------

def parse_frontmatter(text: str) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or not FM_DELIM.match(lines[0]):
        return {}
    end = None
    for i in range(1, len(lines)):
        if FM_DELIM.match(lines[i]):
            end = i
            break
    if end is None:
        return {}
    fields: dict[str, str] = {}
    for raw in lines[1:end]:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][\w-]*)\s*:\s*(.*)$", raw)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if len(val) > 1 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        fields[key] = val
    return fields


# ---------- profile ----------

class Axis:
    def __init__(self, name: str, label: str, command: str) -> None:
        self.name = name
        self.label = label or name
        self.command = command

    def enumerate(self, root: Path) -> tuple[set[str], str | None]:
        """Run the axis command. Returns (items, error)."""
        try:
            proc = subprocess.run(
                ["bash", "-c", self.command],
                cwd=root, capture_output=True, text=True, timeout=120,
            )
        except subprocess.TimeoutExpired:
            return set(), "timed out after 120s"
        except OSError as exc:  # pragma: no cover - environment failure
            return set(), str(exc)
        items = {ln.strip() for ln in proc.stdout.splitlines() if ln.strip()}
        if not items:
            detail = proc.stderr.strip().splitlines()
            hint = detail[0] if detail else "no output"
            # An axis that returns nothing is a broken axis, not an empty project.
            # Reporting it as "0 items, all covered" is the check-that-cannot-fail.
            return set(), f"returned no items ({hint})"
        return items, None


def load_profile(path: Path) -> tuple[list[Axis], list[str]]:
    """Parse the ```census block. Records are blank-line separated key: value."""
    problems: list[str] = []
    if not path.is_file():
        return [], [f"no profile at {path}"]
    text = path.read_text(encoding="utf-8", errors="replace")
    m = CENSUS_BLOCK.search(text)
    if not m:
        return [], [f"{path} has no ```census block"]
    axes: list[Axis] = []
    for chunk in re.split(r"\n\s*\n", m.group(1).strip()):
        rec: dict[str, str] = {}
        for line in chunk.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition(":")
            rec[k.strip()] = v.strip()
        if not rec:
            continue
        name = rec.get("axis", "")
        command = rec.get("command", "")
        if not name or not command:
            problems.append(f"incomplete axis record: {rec or chunk!r}")
            continue
        axes.append(Axis(name, rec.get("label", ""), command))
    if not axes:
        problems.append(f"{path}: ```census block declares no usable axis")
    return axes, problems


# ---------- ownership ----------

COVER_TOKEN = re.compile(r"^([A-Za-z_][\w-]*):(.+)$")


def load_ownership(refs: Path) -> tuple[dict[str, dict[str, list[str]]], int, int]:
    """axis -> item -> [declaring files]. Also (modules scanned, modules declaring)."""
    owners: dict[str, dict[str, list[str]]] = {}
    scanned = declaring = 0
    for md in sorted(refs.rglob("*.md")):
        scanned += 1
        fm = parse_frontmatter(md.read_text(encoding="utf-8", errors="replace"))
        raw = fm.get("covers", "").strip()
        if not raw:
            continue
        declaring += 1
        rel = str(md.relative_to(refs.parent.parent))
        for token in raw.split():
            m = COVER_TOKEN.match(token)
            if not m:
                continue
            axis, item = m.group(1), m.group(2)
            owners.setdefault(axis, {}).setdefault(item, []).append(rel)
    return owners, scanned, declaring


# ---------- report ----------

def build_report(axes: list[Axis], owners, root: Path, dry_run: bool) -> dict:
    report: dict = {"axes": [], "errors": []}
    for ax in axes:
        if dry_run:
            report["axes"].append({"axis": ax.name, "label": ax.label,
                                   "command": ax.command, "dry_run": True})
            continue
        items, err = ax.enumerate(root)
        owned = owners.get(ax.name, {})
        if err:
            report["errors"].append(f"axis '{ax.name}': {err}")
            report["axes"].append({"axis": ax.name, "label": ax.label, "broken": err,
                                   "items": 0, "gap": [], "phantom": [], "contested": []})
            continue
        gap = sorted(i for i in items if i not in owned)
        phantom = sorted(i for i in owned if i not in items)
        contested = sorted(i for i, fs in owned.items() if len(fs) > 1 and i in items)
        report["axes"].append({
            "axis": ax.name, "label": ax.label, "items": len(items),
            "covered": len(items) - len(gap),
            "gap": gap, "phantom": phantom,
            "contested": [{"item": i, "files": owned[i]} for i in contested],
        })
    return report


def render(report: dict, scanned: int, declaring: int) -> str:
    out: list[str] = []
    for a in report["axes"]:
        if a.get("dry_run"):
            out.append(f"[dry-run] {a['axis']} ({a['label']})\n    {a['command']}")
            continue
        if a.get("broken"):
            out.append(f"BROKEN  {a['axis']:<12} {a['broken']}")
            continue
        pct = 100 * a["covered"] // a["items"] if a["items"] else 0
        out.append(f"{a['axis']:<12} {a['covered']}/{a['items']} covered ({pct}%)  "
                   f"gap={len(a['gap'])} phantom={len(a['phantom'])} "
                   f"contested={len(a['contested'])}")
        for i in a["gap"]:
            out.append(f"    gap        {i}")
        for i in a["phantom"]:
            out.append(f"    phantom    {i}  (declared, not found in code)")
        for c in a["contested"]:
            out.append(f"    contested  {c['item']}  <- {', '.join(c['files'])}")
    if declaring == 0 and not any(a.get("dry_run") for a in report["axes"]):
        out.append("")
        out.append(f"NOTE: 0 of {scanned} reference modules declare `covers:`. "
                   "Every item above is an adoption gap, not a coverage gap — "
                   "declare ownership on sweep, never by backfilling a guess.")
    else:
        out.append("")
        out.append(f"{declaring}/{scanned} reference modules declare `covers:`.")
    for e in report["errors"]:
        out.append(f"ERROR: {e}")
    return "\n".join(out)


def render_matrix(report: dict) -> str:
    lines = ["<!-- GENERATED by aidex-reference/scripts/docs-census.py — do not hand-edit -->",
             "", "# Documentation coverage matrix", "",
             "| Axis | Items | Covered | Gap | Phantom | Contested |",
             "|---|---:|---:|---:|---:|---:|"]
    for a in report["axes"]:
        if a.get("dry_run"):
            continue
        if a.get("broken"):
            lines.append(f"| {a['axis']} | — | — | — | — | BROKEN |")
            continue
        lines.append(f"| {a['axis']} | {a['items']} | {a['covered']} | {len(a['gap'])} "
                     f"| {len(a['phantom'])} | {len(a['contested'])} |")
    for a in report["axes"]:
        if a.get("dry_run") or a.get("broken") or not (a["gap"] or a["phantom"] or a["contested"]):
            continue
        lines += ["", f"## {a['axis']} — {a['label']}", ""]
        for i in a["gap"]:
            lines.append(f"- **gap** `{i}` — no module declares it")
        for i in a["phantom"]:
            lines.append(f"- **phantom** `{i}` — declared, not found in code")
        for c in a["contested"]:
            lines.append(f"- **contested** `{c['item']}` — {', '.join(c['files'])}")
    return "\n".join(lines) + "\n"


def find_root(start: Path) -> Path | None:
    for d in [start, *start.parents]:
        if (d / ".context").is_dir():
            return d
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="Documentation coverage census")
    ap.add_argument("--root", type=Path, default=Path.cwd())
    ap.add_argument("--profile", type=Path, default=None,
                    help="default: <root>/.context/references/00-profile.md")
    ap.add_argument("--dry-run", action="store_true",
                    help="print axis commands without executing them")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--write", type=Path, default=None,
                    help="also write a GENERATED matrix to this path")
    ap.add_argument("--advisory", action="store_true",
                    help="always exit 0 (report only)")
    args = ap.parse_args()

    root = find_root(args.root.resolve())
    if root is None:
        print(f"no .context/ found from {args.root}", file=sys.stderr)
        return 2
    refs = root / ".context" / "references"
    if not refs.is_dir():
        print(f"no {refs}", file=sys.stderr)
        return 2

    profile = args.profile or (refs / "00-profile.md")
    axes, problems = load_profile(profile)
    if not axes:
        for p in problems:
            print(f"ERROR: {p}", file=sys.stderr)
        print("\nCreate one from "
              "skills/aidex-reference/assets/templates/00-profile.md.template",
              file=sys.stderr)
        return 2
    for p in problems:
        print(f"WARN: {p}", file=sys.stderr)

    owners, scanned, declaring = load_ownership(refs)
    report = build_report(axes, owners, root, args.dry_run)
    report["modules_scanned"] = scanned
    report["modules_declaring"] = declaring

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(render(report, scanned, declaring))

    if args.write and not args.dry_run:
        args.write.parent.mkdir(parents=True, exist_ok=True)
        args.write.write_text(render_matrix(report), encoding="utf-8")
        print(f"\nwrote {args.write}", file=sys.stderr)

    if args.advisory or args.dry_run:
        return 0
    if report["errors"]:
        return 2
    findings = sum(len(a.get("gap", [])) + len(a.get("phantom", [])) + len(a.get("contested", []))
                   for a in report["axes"])
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
