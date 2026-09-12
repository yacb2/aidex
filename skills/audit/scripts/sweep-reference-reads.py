#!/usr/bin/env python3
"""sweep-reference-reads.py — suite-wide: which cited references are never read?

Single-pass generalization of mine-reference-reads.py. Enumerates every reference
a SKILL.md points at, then measures, in one walk of the corpus, how often sessions
that fired the citing skill actually pulled that reference into context.

Motivation (RA-CITE-1, 2026-08-05): `autonomy-conventions.md` is cited 26 times
across five run skills and was read in 5 of 180 runs — all five Bash greps by
someone working on the file. A markdown link is an invitation, not a load. A
reference that is written, shipped, and never read is documentation debt that
looks like coverage.

Read-only over ~/.claude/projects.

Usage:
  sweep-reference-reads.py [--skills-dir DIR] [--min-fired N] [--json OUT]
"""
import argparse, collections, glob, json, os, re, sys

PROJECTS = os.path.expanduser("~/.claude/projects")
DEFAULT_SKILLS = os.path.expanduser("~/.claude/skills")

# markdown links and bare paths pointing at a .md under a references/ dir
CITE_RX = re.compile(r"(?:\.\./|/|\b)([A-Za-z0-9_\-]+/)?references/([A-Za-z0-9._\-]+\.md)")
# ...but a project's own `.context/references/` is an artifact the skill WRITES, not a
# reference it should read. Counting those inflates the never-read set with rows no
# rewrite can fix (aidex/01-project-commands.md, 0/25, was one).
ARTIFACT_RX = re.compile(r"\.context/references/([A-Za-z0-9._\-]+\.md)")


def collect_citations(skills_dir):
    """skill -> set(reference basenames it points at)."""
    out = collections.defaultdict(set)
    for skill_md in glob.glob(os.path.join(skills_dir, "*", "SKILL.md")):
        skill = os.path.basename(os.path.dirname(skill_md))
        try:
            txt = open(skill_md, errors="replace").read()
        except OSError:
            continue
        artifacts = set(ARTIFACT_RX.findall(txt))
        for _, base in CITE_RX.findall(txt):
            if base not in artifacts:
                out[skill].add(base)
    return out


def pulls_into_context(name, inp):
    if name in ("Read", "NotebookEdit"):
        return str(inp.get("file_path", ""))
    if name == "Bash":
        return str(inp.get("command", ""))
    if name == "Grep":
        return str(inp.get("path", "")) + " " + str(inp.get("glob", ""))
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skills-dir", default=DEFAULT_SKILLS)
    ap.add_argument("--min-fired", type=int, default=5,
                    help="skip references whose citing skills fired fewer times")
    ap.add_argument("--json")
    a = ap.parse_args()

    cites = collect_citations(a.skills_dir)
    if not cites:
        sys.exit(f"no SKILL.md citations found under {a.skills_dir}")
    all_refs = sorted({r for rs in cites.values() for r in rs})
    print(f"{len(cites)} skills cite {len(all_refs)} distinct references", flush=True)

    fired_count = collections.Counter()          # skill -> sessions where it fired
    read_pairs = collections.Counter()           # (skill, ref) -> sessions fired AND read
    fired_pairs = collections.Counter()          # (skill, ref) -> sessions fired
    how = collections.defaultdict(collections.Counter)

    for f in glob.glob(PROJECTS + "/*/*.jsonl"):
        try:
            lines = open(f, errors="replace").read().splitlines()
        except OSError:
            continue
        fired, touched = set(), {}
        for l in lines:
            if not l.strip():
                continue
            try:
                o = json.loads(l)
            except Exception:
                continue
            if o.get("type") != "assistant":
                continue
            for b in o.get("message", {}).get("content", []) or []:
                if not (isinstance(b, dict) and b.get("type") == "tool_use"):
                    continue
                name, inp = b.get("name") or "", b.get("input") or {}
                if name == "Skill":
                    sk = inp.get("skill") or ""
                    if sk:
                        fired.add(sk)
                blob = pulls_into_context(name, inp)
                if blob:
                    for ref in all_refs:
                        if ref in blob:
                            touched.setdefault(ref, set()).add(name)
        if not fired:
            continue
        for sk in fired:
            fired_count[sk] += 1
            for ref in cites.get(sk, ()):
                fired_pairs[(sk, ref)] += 1
                if ref in touched:
                    read_pairs[(sk, ref)] += 1
                    for t in touched[ref]:
                        how[(sk, ref)][t] += 1

    rows = []
    for (sk, ref), n in sorted(fired_pairs.items(), key=lambda kv: -kv[1]):
        if n < a.min_fired:
            continue
        r = read_pairs[(sk, ref)]
        rows.append(dict(skill=sk, reference=ref, fired=n, read=r,
                         rate=round(r / n, 4), how=dict(how[(sk, ref)])))

    print(f"\n{'skill':22s} {'reference':44s} {'fired':>6s} {'read':>5s} {'rate':>7s}")
    for row in rows:
        print(f"{row['skill']:22s} {row['reference'][:44]:44s} "
              f"{row['fired']:6d} {row['read']:5d} {row['rate']:6.1%}")

    never = [r for r in rows if r["read"] == 0]
    print(f"\n{len(rows)} (skill, reference) pairs with >= {a.min_fired} firings")
    print(f"{len(never)} were NEVER read in any session where the citing skill fired")
    print("\nBash hits include greps done while working ON a file. Rates are upper bounds.")

    if a.json:
        json.dump(dict(rows=rows, skills_fired=dict(fired_count)),
                  open(a.json, "w"), indent=2)
        print(f"\nwrote {a.json}")


if __name__ == "__main__":
    main()
