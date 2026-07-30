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
Axis commands are shell strings from `.context/references/00-profile.md` and
they run as you. This tool is installed machine-wide and is meant to be run
against arbitrary projects, so a cloned repo can ship a profile -- and
`find_root()` walks up parents, so merely being *inside* such a tree is enough.

That is a real execution vector, so consent is **enforced, not documented**:
an unrecognised census block is printed and refused (exit 3) until approved
with `--trust`. Approvals are keyed by sha256 of the census block and stored
under $HOME (never in the project), so a repo cannot ship its own approval.
Editing the block revokes it. `--dry-run` never executes and needs no trust.

Deliberately NOT done: an allowlist of permitted binaries. Axis commands are
pipelines, and identifying the binaries in a shell pipeline without a shell
parser is unreliable -- an allowlist here would look like a control while not
being one, which is the failure mode this whole skill exists to name. The gate
is provenance; the commands are shown in full so a human reads them.

No third-party dependencies. Front-matter parsing is deliberately FLAT so the
shared `validate.py` parser reads the same fields without nested-YAML support.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

FM_DELIM = re.compile(r"^---\s*$")

# Approvals live under $HOME, never in the project: a repo that ships a profile
# must not be able to ship its own approval for it.
TRUST_FILE = Path(
    os.environ.get("AIDEX_CENSUS_TRUST")
    or (Path.home() / ".aidex" / ".census-trust")
)


def block_digest(block: str) -> str:
    """Hash the executable block only, so prose edits do not revoke approval."""
    return hashlib.sha256(block.strip().encode()).hexdigest()


def load_trust() -> dict[str, str] | None:
    """Approved profiles as {path: digest}. None means the store exists but could
    not be read -- distinct from {} (no approvals), because a caller that merges
    into {} would silently destroy every other project's approval.

    JSON, not a line format: the previous `{digest}  {path}` format had no
    escaping, so a project directory whose NAME contains a newline forged an
    approval line for an arbitrary other profile. Verified as a full consent-gate
    bypass on 2026-07-30 -- an unapproved hostile census executed with no --trust.
    A repo can choose its own directory name; git clones it.
    """
    if not TRUST_FILE.is_file():
        return {}
    try:
        raw = TRUST_FILE.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"WARN: trust store unreadable ({exc})", file=sys.stderr)
        return None
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except ValueError:
        # The pre-JSON store was `{digest}  {path}` per line. Do NOT migrate it:
        # that format had no escaping, so a project directory name containing a
        # newline could forge an approval for an arbitrary other profile. Its
        # contents therefore cannot be assumed genuine, and carrying them forward
        # would launder a possible forgery into the new format. Re-approval is
        # the only safe path, so say exactly that instead of a generic parse error.
        if re.search(r"^[0-9a-f]{64}\s\s\S", raw, re.M):
            print(f"WARN: {TRUST_FILE} is in the legacy line format, which could be "
                  f"forged by a crafted directory name. Its approvals cannot be "
                  f"trusted and are NOT migrated.\n"
                  f"      Delete it and re-approve:  rm {TRUST_FILE}",
                  file=sys.stderr)
        else:
            print(f"WARN: trust store {TRUST_FILE} is not valid JSON; refusing to "
                  f"read or overwrite it", file=sys.stderr)
        return None
    if not isinstance(data, dict):
        print(f"WARN: trust store {TRUST_FILE} has an unexpected shape", file=sys.stderr)
        return None
    return {str(k): str(v) for k, v in data.items()}


def record_trust(profile: Path, digest: str) -> None:
    trust = load_trust()
    if trust is None:
        # Never merge into an empty dict after a failed read: that rewrites the
        # store with only the new entry and silently revokes everything else.
        raise SystemExit(
            f"refusing to write {TRUST_FILE}: it exists but could not be read. "
            f"Approving now would delete every other project's approval. "
            f"Fix or remove the file, then re-run --trust.")
    trust[str(profile)] = digest
    tmp = TRUST_FILE.with_name(TRUST_FILE.name + f".tmp{os.getpid()}")
    try:
        TRUST_FILE.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(trust, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        try:
            tmp.chmod(0o600)
        except OSError:
            pass
        os.replace(tmp, TRUST_FILE)  # atomic; a crash mid-write cannot truncate it
    except OSError as exc:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise SystemExit(f"could not write trust store {TRUST_FILE}: {exc}")


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


def load_profile(path: Path) -> tuple[list[Axis], list[str], str]:
    """Parse the ```census block. Records are blank-line separated key: value.

    Also returns the raw block, which is what the trust gate hashes.
    """
    problems: list[str] = []
    if not path.is_file():
        return [], [f"no profile at {path}"], ""
    text = path.read_text(encoding="utf-8", errors="replace")
    m = CENSUS_BLOCK.search(text)
    if not m:
        return [], [f"{path} has no ```census block"], ""
    block = m.group(1)
    axes: list[Axis] = []
    for chunk in re.split(r"\n\s*\n", m.group(1).strip()):
        rec: dict[str, str] = {}
        # Count `axis:` BEFORE the comment skip. Commenting one line out is the
        # most natural way to disable a record, and it used to slip past the
        # counter while the record's other keys still overwrote the previous one.
        axis_lines = len(re.findall(r"^\s*#?\s*axis\s*:", chunk, re.M))
        for line in chunk.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            k, _, v = line.partition(":")
            rec[k.strip()] = v.strip()
        if not rec:
            continue
        if axis_lines > 1:
            problems.append(
                f"{path}: a census record declares {axis_lines} `axis:` lines "
                f"(commented-out ones count) — records must be separated by a BLANK "
                f"LINE. This whole record is dropped: {chunk.splitlines()[0]!r}...")
            continue
        name = rec.get("axis", "")
        command = rec.get("command", "")
        if not name or not command:
            problems.append(f"incomplete axis record: {rec or chunk!r}")
            continue
        if name in {a.name for a in axes}:
            problems.append(f"{path}: duplicate axis {name!r} — the FIRST record is "
                            f"kept and this one is dropped; give each axis a distinct name")
            continue
        axes.append(Axis(name, rec.get("label", ""), command))
    if not axes:
        problems.append(f"{path}: ```census block declares no usable axis")
    return axes, problems, block


# ---------- ownership ----------

def load_ownership(refs: Path) -> tuple[dict[str, dict[str, list[str]]], int, int, list[str]]:
    """axis -> item -> [declaring files]. Also (scanned, declaring, problems).

    Grammar: comma-separated `axis: item` entries, partitioned on the FIRST
    colon. Commas rather than whitespace because axis names and items both
    legitimately contain spaces -- `scheduled jobs`, `GET /api/voices` -- and
    the whitespace-split version silently dropped them, reporting 100% gap on
    correctly documented code. First-colon partition so an item may itself
    contain colons (`/productions/:id`).

    An entry that cannot be parsed is REPORTED, never dropped: a silent drop
    turns a correct declaration into a false finding, which is the exact
    check-that-lies failure this tool exists to surface.
    """
    owners: dict[str, dict[str, list[str]]] = {}
    problems: list[str] = []
    scanned = declaring = 0
    for md in sorted(refs.rglob("*.md")):
        fm = parse_frontmatter(md.read_text(encoding="utf-8", errors="replace"))
        raw = fm.get("covers", "").strip()
        # The profile and indexes are not modules, so they do not move the N/M
        # adoption figure -- but if one DOES declare covers:, that ownership is
        # still real. Skipping them before parsing deleted contested and phantom
        # findings outright and turned covered items into false gaps.
        is_module = md.name not in ("00-profile.md", "00-index.md", "00-overview.md")
        if is_module:
            scanned += 1
        if not raw:
            continue
        if is_module:
            declaring += 1
        rel = str(md.relative_to(refs.parent.parent))
        for entry in raw.split(","):
            entry = entry.strip()
            if not entry:
                continue
            axis, sep, item = entry.partition(":")
            axis, item = axis.strip(), item.strip()
            if not sep or not axis or not item:
                problems.append(
                    f"{rel}: covers entry {entry!r} is not `axis: item` — ignored")
                continue
            owners.setdefault(axis, {}).setdefault(item, []).append(rel)
    return owners, scanned, declaring, problems


# ---------- report ----------

def build_report(axes: list[Axis], owners, root: Path, dry_run: bool) -> dict:
    report: dict = {"axes": [], "errors": []}
    # An axis declared in `covers:` that no census axis produces can never
    # match anything. Silently ignoring it is how a documented project reads
    # as 100% gap.
    if not dry_run:
        declared = set(owners)
        known = {a.name for a in axes}
        for orphan in sorted(declared - known):
            files = sorted({f for fs in owners[orphan].values() for f in fs})
            report["errors"].append(
                f"covers axis {orphan!r} matches no census axis "
                f"(declared in {', '.join(files[:3])}) — check the profile")
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
    ap.add_argument("--trust", action="store_true",
                    help="approve this profile's census block, then run it")
    args = ap.parse_args()

    root = find_root(args.root.resolve())
    if root is None:
        print(f"no .context/ found from {args.root}", file=sys.stderr)
        return 2
    refs = root / ".context" / "references"
    if not refs.is_dir():
        print(f"no {refs}", file=sys.stderr)
        return 2

    profile = (args.profile or (refs / "00-profile.md")).resolve()
    axes, problems, block = load_profile(profile)
    if not axes:
        for p in problems:
            print(f"ERROR: {p}", file=sys.stderr)
        print("\nCreate one from "
              "skills/aidex-reference/assets/templates/00-profile.md.template",
              file=sys.stderr)
        return 2
    # Profile problems are ERRORS, not warnings: a dropped axis means the census
    # measured less than it reports, so it must reach --json, the matrix and the
    # exit code -- not only a human reading stderr.

    # ---- trust gate ----------------------------------------------------
    # These are shell strings from a file that may have arrived with a clone.
    # Consent is enforced here rather than asked for in a docstring, because a
    # rule that depends on the operator remembering is a rule that is not run.
    digest = block_digest(block)
    known_store = load_trust()
    if known_store is None:
        # Unreadable/corrupt store: fail closed. Never fall through to "no
        # approvals", which would also let record_trust overwrite it.
        trusted = False
    else:
        trusted = known_store.get(str(profile)) == digest
    if args.trust and not args.dry_run:
        record_trust(profile, digest)
        trusted = True
        print(f"approved {profile}\n  sha256:{digest[:16]}… recorded in {TRUST_FILE}",
              file=sys.stderr)
    if not trusted and not args.dry_run:
        known = (known_store or {}).get(str(profile))
        if known_store is None:
            why = "the trust store could not be read, so nothing is approved"
        else:
            why = ("its census block CHANGED since it was approved"
                   if known else "it has not been approved on this machine")
        print(f"REFUSED: not running {profile} — {why}.\n", file=sys.stderr)
        print("These axis commands would run as you, from "
              f"{root}:\n", file=sys.stderr)
        for ax in axes:
            print(f"  [{ax.name}] {ax.command}", file=sys.stderr)
        print("\nRead them. Then either:\n"
              f"  --dry-run   inspect without running (no approval needed)\n"
              f"  --trust     approve this exact block and run it\n", file=sys.stderr)
        return 3

    owners, scanned, declaring, cover_problems = load_ownership(refs)
    report = build_report(axes, owners, root, args.dry_run)
    report["errors"] = problems + cover_problems + report["errors"]
    report["modules_scanned"] = scanned
    report["modules_declaring"] = declaring

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(render(report, scanned, declaring))

    if args.write and not args.dry_run:
        # Resolve against the project root, never cwd: find_root() walks UP, so a
        # cwd-relative --write from a subdirectory creates <subdir>/.context/...
        # which then becomes the nearest root and captures every later run.
        out = args.write if args.write.is_absolute() else root / args.write
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render_matrix(report), encoding="utf-8")
        print(f"\nwrote {out}", file=sys.stderr)

    if args.advisory or args.dry_run:
        return 0
    if report["errors"]:
        return 2
    findings = sum(len(a.get("gap", [])) + len(a.get("phantom", [])) + len(a.get("contested", []))
                   for a in report["axes"])
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
