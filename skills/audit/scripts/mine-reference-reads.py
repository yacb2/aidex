#!/usr/bin/env python3
"""mine-reference-reads.py — is a cited reference actually READ?

Answers the question that decides whether always-on content can be relocated:
when a skill cites a reference ("apply [Mode A autonomy](../references/x.md)"),
do its real sessions pull that file into context, or is the link decorative?

This matters because a markdown link is an invitation, not a load. Relocating
always-on content behind a pointer is only safe if the pointer is followed. If it
is not, the relocation removes governance and nothing replaces it — silently,
because the stub still says "read this" and nothing errors.

Measured 2026-08-05 for autonomy-conventions.md: cited 26 times across five run
skills, read in 5 of 180 sessions where a run skill fired (2.8%), and most of
those were Bash greps during development rather than a run consuming it. The
always-on summary was the sole delivery path. See
`assets/templates/methodology/rule-ablation.md.template`.

Read-only over ~/.claude/projects.

Usage:
  mine-reference-reads.py <reference-basename> [--when-skill S1,S2,...]

  <reference-basename>  e.g. autonomy-conventions.md
  --when-skill          restrict the denominator to sessions where one of these
                        skills fired. Without it, the denominator is all sessions.
"""
import argparse, collections, glob, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _reference_reads import bare_skill, pulls_into_context, tool_uses

PROJECTS = os.path.expanduser("~/.claude/projects")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("reference")
    ap.add_argument("--when-skill", default="")
    a = ap.parse_args()
    gate = {bare_skill(s.strip()) for s in a.when_skill.split(",") if s.strip()}
    needle = a.reference

    denom = 0
    hits = 0
    per_skill = collections.Counter()
    per_skill_read = collections.Counter()
    how = collections.Counter()

    for f in glob.glob(PROJECTS + "/*/*.jsonl"):
        try:
            calls = list(tool_uses(f))
        except OSError:
            continue
        fired, touched = set(), set()
        for name, inp in calls:
            if name == "Skill":
                sk = inp.get("skill") or ""
                if sk:
                    fired.add(bare_skill(sk))
            blob = pulls_into_context(name, inp)
            if blob and needle in blob:
                touched.add(name)

        in_scope = bool(fired & gate) if gate else True
        if not in_scope:
            continue
        denom += 1
        for s in (fired & gate) if gate else fired:
            per_skill[s] += 1
        if touched:
            hits += 1
            for s in (fired & gate) if gate else fired:
                per_skill_read[s] += 1
            for t in touched:
                how[t] += 1

    if not denom:
        sys.exit("no sessions in scope")

    scope = f"sessions where {'/'.join(sorted(gate))} fired" if gate else "all sessions"
    print(f"reference: {needle}")
    print(f"scope:     {scope}")
    print(f"\n{denom} in scope · {hits} pulled it into context · {hits/denom:.1%}")
    if per_skill:
        print(f"\n{'skill':20s} {'in scope':>9s} {'read':>6s}")
        for s in sorted(per_skill):
            print(f"{s:20s} {per_skill[s]:9d} {per_skill_read[s]:6d}")
    print(f"\nhow it was pulled: {dict(how) or '(never)'}")
    print("\nNote: Bash hits include greps done while working ON the file, not only "
          "a run consuming it. Treat this rate as an upper bound.")


if __name__ == "__main__":
    main()
