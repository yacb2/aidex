#!/usr/bin/env python3
"""surface-drift-check.py — is the auditor's advice still checked against this Claude Code?

The ecosystem auditor recommends configuration changes, and each recommendation rests on a
Claude Code behaviour that a release can change. When one does, the recommendation does not
error — it becomes confidently wrong advice, which is the worse failure. It happened once:
aidex caught up with skillOverrides and MCP scoping by hand only after recommending the
removal of plugins that were fine (RETRO-40 / BL-222).

This compares `references/06-claude-code-surface.md` — where each surface records the Claude
Code version its behaviour was last verified against — with the installed `claude --version`,
and names the rows nobody has looked at since.

READ-ONLY, and it does not say what to change. A newer Claude Code does not mean a
recommendation is wrong; it means it is unverified. Prescribing a fix from a version number
alone would reproduce the exact defect this exists to catch.

Usage:
  surface-drift-check.py [--reference <path>] [--installed <version>] [--json OUT]

  --installed  skip `claude --version` and compare against this version instead. For tests
               and for checking what a future release would flag.

Exit 0 when nothing has drifted, 1 when at least one surface needs re-verifying, 2 on a
usage error (missing or unparsable reference). Exit 1 is "go look", never "something broke".
"""
import argparse, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_REFERENCE = os.path.join(HERE, "..", "references", "06-claude-code-surface.md")
VERSION_RE = re.compile(r"\b(\d+)\.(\d+)\.(\d+)\b")


def parse_version(text):
    """First MAJOR.MINOR.PATCH in the text, as a comparable tuple. `claude --version`
    prints '2.1.241 (Claude Code)', so the trailing product name is ignored."""
    m = VERSION_RE.search(text or "")
    return tuple(int(g) for g in m.groups()) if m else None


def fmt(v):
    return ".".join(str(n) for n in v)


def read_surfaces(path):
    """Rows of the `## Surfaces` table: (surface, version tuple, dependent recommendation).

    Parsed from the doc rather than duplicated in code on purpose — a second copy of the
    version numbers is the drift this file exists to detect, reproduced one level down."""
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    rows, in_section = [], False
    for line in lines:
        if line.startswith("## "):
            in_section = line.strip() == "## Surfaces"
            continue
        if not in_section or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3:
            continue
        if cells[0].lower() == "surface" or set(cells[0]) <= set("-: "):
            continue  # header or separator
        v = parse_version(cells[1])
        if v is None:
            raise ValueError(f"row {cells[0]!r} has no MAJOR.MINOR.PATCH in its version column")
        rows.append({"surface": cells[0], "verified_against": fmt(v), "_v": v,
                     "depends": cells[2]})
    return rows


def installed_version():
    try:
        out = subprocess.run(["claude", "--version"], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    return parse_version(out.stdout) or parse_version(out.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--reference", default=DEFAULT_REFERENCE)
    ap.add_argument("--installed")
    ap.add_argument("--json", dest="json_out")
    args = ap.parse_args()

    ref = os.path.abspath(args.reference)
    if not os.path.isfile(ref):
        print(f"error: no surface reference at {ref}", file=sys.stderr)
        return 2
    try:
        rows = read_surfaces(ref)
    except (OSError, ValueError) as e:
        print(f"error: cannot read the surface table: {e}", file=sys.stderr)
        return 2
    if not rows:
        print(f"error: no surface rows found under '## Surfaces' in {ref}", file=sys.stderr)
        return 2

    if args.installed:
        cur = parse_version(args.installed)
        if cur is None:
            print(f"error: --installed {args.installed!r} is not MAJOR.MINOR.PATCH", file=sys.stderr)
            return 2
    else:
        cur = installed_version()

    if cur is None:
        # Not a drift finding: we simply could not look. Saying "up to date" here would be
        # the lie this whole check exists to prevent.
        print("Claude Code surface — could not read `claude --version`; nothing was compared.")
        print(f"  {len(rows)} surface(s) recorded in {os.path.relpath(ref)}")
        print("  re-run where the CLI is on PATH, or pass --installed <version>")
        return 0

    stale = [r for r in rows if r["_v"] < cur]
    payload = {"installed": fmt(cur), "reference": ref,
               "surfaces": [{k: v for k, v in r.items() if k != "_v"} for r in rows],
               "needs_reverification": [r["surface"] for r in stale]}
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent=2)

    print(f"Claude Code surface — installed {fmt(cur)}")
    if not stale:
        newest = fmt(max(r["_v"] for r in rows))
        print(f"  all {len(rows)} surface(s) verified against {newest} or newer — nothing to re-verify")
        return 0

    print(f"  {len(stale)} of {len(rows)} surface(s) were last verified against an older "
          f"Claude Code.\n  This does NOT mean the advice is wrong — it means nobody has "
          f"looked since.\n")
    for r in stale:
        print(f"  {r['surface']}  (verified against {r['verified_against']}, installed {fmt(cur)})")
        print(f"    at risk: {r['depends']}")
    print(f"\n  Re-verify each, then bump its version column in {os.path.relpath(ref)}.")
    print("  Unchanged behaviour is the normal outcome: bumping the column is the point.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
