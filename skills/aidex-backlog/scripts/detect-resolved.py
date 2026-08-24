#!/usr/bin/env python3
"""detect-resolved.py — which open items are worth checking against the code, and with what?

An item that the work already fixed stays open until a human happens to read it. Nothing
checks an open item against current code (RETRO-09 / BL-214). `harvest-commit.sh` closes on
a commit trailer, which only catches the items someone remembered to name.

This is the MECHANICAL half of `/aidex-backlog detect-resolved`. It does not decide
anything: it enumerates open items and, for each, the anchors a reviewer would need — the
paths its body cites, the commits it cites, the skills and scripts it names. The judgement
half is a read-only subagent per item, fanned out by the skill, which reads those anchors
and reports back.

**It proposes; it never closes.** An item that looks resolved from the code may be open for
a reason the code cannot show — a decision deferred, a follow-up owed. Closing on this
signal alone would be the auto-close defect the finding is about, moved one layer down.

Unlike quick-wins.py this DOES read bodies: the anchors are in them, and there is no
cheaper place to get a cited path from.

Usage:
  detect-resolved.py [<path-to-.context>] [--json OUT] [--limit N]

Exit 0 always: this produces a work-list, it does not gate.
"""
import argparse, json, os, re, subprocess, sys

FM_END = re.compile(r"^---\s*$", re.M)
SHA = re.compile(r"\b[0-9a-f]{7,40}\b")
# A path anchor is worth citing only if it looks like a real repo path, not prose with a
# slash in it. Requires a directory segment and a file extension we actually ship.
# The lookbehind rather than \b so a leading dot survives: with \b, ".context/x.md"
# matched as "context/x.md" and the .context/ filter below never fired.
PATH_RE = re.compile(r"(?<![\w/.-])((?:[\w.-]+/){1,6}[\w.-]+\.(?:py|sh|md|js|json|ts|yml|yaml))\b")
# D-03 cross-reference markers (`decision/<file>.md`) are references to other artifacts,
# not code paths. They resolve inside .context/, so a reviewer checking CODE has no use
# for them and they would otherwise dominate the ABSENT list.
CROSSREF_PREFIXES = ("audit/", "backlog/", "plan/", "request/", "decision/", "reference/",
                     "research/", "communication/", "loop/", "worktree/", "context/")
SKILL_RE = re.compile(r"\b(aidex(?:-[a-z]+)?)\b")
CODE_FENCE = re.compile(r"(?ms)^[ \t]*```.*?^[ \t]*```[ \t]*$")


def split_frontmatter(text):
    if not text.startswith("---"):
        return "", text
    m = FM_END.search(text, 3)
    return (text[:m.end()], text[m.end():]) if m else ("", text)


def field(block, key):
    m = re.search(rf"^{key}:\s*[\"']?(.*?)[\"']?\s*$", block, re.M)
    return m.group(1).strip() if m else ""


def commit_exists(repo, sha):
    if not repo:
        return False
    try:
        r = subprocess.run(["git", "-C", repo, "cat-file", "-e", f"{sha}^{{commit}}"],
                           capture_output=True, timeout=10)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def anchors_for(body, ctx, repo):
    """Everything a reviewer would open to judge this item. Deduped, order-stable, and
    limited — an item citing forty paths gets a subagent a prompt it cannot use."""
    prose = CODE_FENCE.sub("", body)
    paths, missing = [], []
    for p in dict.fromkeys(PATH_RE.findall(prose)):
        if p.startswith(".context/") or p.startswith(CROSSREF_PREFIXES):
            continue  # its own tier or a D-03 marker; the reviewer is checking CODE
        full = os.path.join(os.path.dirname(ctx), p)
        (paths if os.path.exists(full) else missing).append(p)
    commits = [c for c in dict.fromkeys(SHA.findall(prose)) if commit_exists(repo, c)]
    skills = [s for s in dict.fromkeys(SKILL_RE.findall(prose)) if "-" in s]
    return paths[:8], missing[:4], commits[:6], skills[:6]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("context", nargs="?", default=None)
    ap.add_argument("--json", dest="json_out")
    ap.add_argument("--limit", type=int, default=0, help="only the first N open items")
    args = ap.parse_args()

    ctx = os.path.abspath(args.context or ".context")
    base = os.path.join(ctx, "backlog")
    if not os.path.isdir(base):
        print(f"error: no backlog/ under {ctx}", file=sys.stderr)
        return 2
    repo = os.path.dirname(ctx)
    if not os.path.isdir(os.path.join(repo, ".git")):
        repo = None

    rows = []
    for name in sorted(os.listdir(base)):
        if not (name.endswith(".md") and not name.startswith("00-")):
            continue
        with open(os.path.join(base, name), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        fm, body = split_frontmatter(text)
        if field(fm, "status") not in ("open", "doing"):
            continue
        paths, missing, commits, skills = anchors_for(body, ctx, repo)
        rows.append({"id": field(fm, "id") or "?", "title": field(fm, "title"),
                     "file": name, "priority": field(fm, "priority"),
                     "paths": paths, "paths_not_found": missing,
                     "commits": commits, "skills": skills,
                     "checkable": bool(paths or commits)})
        if args.limit and len(rows) >= args.limit:
            break

    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump({"context": ctx, "items": rows}, fh, indent=2)

    checkable = [r for r in rows if r["checkable"]]
    print(f"detect-resolved work-list — {len(rows)} open item(s), {len(checkable)} with "
          f"anchors worth checking")
    if repo is None:
        print("  note: no git repo above .context/, so cited commits were not verified")
    if not rows:
        return 0

    for r in rows:
        mark = " " if r["checkable"] else "~"
        print(f"\n{mark} {r['id']:8} {r['title'][:70]}")
        if r["paths"]:
            print(f"    paths:   {', '.join(r['paths'])}")
        if r["commits"]:
            print(f"    commits: {', '.join(c[:8] for c in r['commits'])}")
        if r["skills"]:
            print(f"    skills:  {', '.join(r['skills'])}")
        if r["paths_not_found"]:
            print(f"    cited but ABSENT: {', '.join(r['paths_not_found'])}  "
                  f"(moved, renamed, or never existed — worth a look either way)")
        if not r["checkable"]:
            print("    no code anchor — a reviewer would have nothing to open; skip it")

    print("\n  This is the input to the fan-out, not its answer. One read-only subagent per")
    print("  item reads these anchors and reports SUSPECTED-RESOLVED with a cited path or")
    print("  commit. Nothing here closes anything — an item can be open for a reason the")
    print("  code cannot show.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
